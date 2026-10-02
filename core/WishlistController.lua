-- Nexus: core/WishlistController.lua
-- Frame-free Wishlist draft, session, association, and apply-retry owner.

Nexus = Nexus or {}
Nexus.WishlistInternals = Nexus.WishlistInternals or {}

local Controller = {}


-- MASTER-RC-001 (amendment 10). Store.State() is a DURABLE_READ returning a
-- defensive copy; writes must go through StoreAuthorityOwnerV1.UpdateStateV1,
-- the architecture's counted private mutation entry (lines 1907-1912).
-- The constructor records the INJECTED store here. The helper lives at file
-- scope (AutomationRuntime.New is already at the Lua 5.1 200-local ceiling),
-- so it cannot close over the constructor-local `Store` directly.
local boundStore

local function UpdateStoreState(mutator)
    local internals = Nexus and Nexus.MainInternals
    local owner = type(internals) == "table" and internals.StoreAuthorityOwner
    -- Honour the INJECTED Store. A stub Store must never resolve the real
    -- durable writer -- writing through the global owner would bypass
    -- dependency injection, which tests/run_wishlist_controller_parity.lua
    -- exists to catch. A stub exposes only the surface it needs (typically
    -- State/Settings); a real Store module exposes the full nine-export facade.
    -- Identity alone is not usable here: fixtures re-`dofile` core/Store.lua,
    -- which rebinds Nexus.Store and the owner while an already-initialized
    -- consumer still holds the previous module, so a real Store legitimately
    -- fails an identity check.
    local Store = boundStore
    local realStore = type(Store) == "table"
        and type(Store.Init) == "function"
        and type(Store.CurrentOwnerKey) == "function"
    if realStore and type(owner) == "table"
        and type(owner.UpdateStateV1) == "function" then
        return owner.UpdateStateV1(mutator)
    end
    -- No authorized owner for THIS Store. Fall back to whatever state table the
    -- injected facade exposes, which is exactly the pre-migration behaviour for
    -- such a Store.
    local injected = Store and Store.State and Store.State()
    if type(injected) ~= "table" then return nil end
    return true, mutator(injected)
end

-- A settings change from a control goes through the same owner the runtime
-- reads (Store.Settings), never into a settings table found on the saved root:
-- for a read-only saved root that table is not the one the runtime uses, and
-- it must stay unchanged. The real owner reports whether the change was saved
-- ("durable") or applies to this session only ("session").
local function UpdateStoreSetting(key, value)
    local internals = Nexus and Nexus.MainInternals
    local owner = type(internals) == "table" and internals.StoreAuthorityOwner
    local Store = boundStore
    local realStore = type(Store) == "table"
        and type(Store.Init) == "function"
        and type(Store.CurrentOwnerKey) == "function"
    if realStore and type(owner) == "table"
        and type(owner.UpdateSettingsV1) == "function" then
        return owner.UpdateSettingsV1(key, value)
    end
    local settings = Store and Store.Settings and Store.Settings()
    if type(settings) ~= "table" then return nil, "settings unavailable" end
    settings[key] = value
    return {mode="injected"}
end

function Controller.New(options)
    options = type(options) == "table" and options or {}
    local DraftModel = assert(options.model, "Wishlist controller requires WishlistModel")
    local Store = assert(options.store, "Wishlist controller requires Store")
    boundStore = Store
    local notify = function(message)
        local callback=type(options.notify)=="function" and options.notify or print
        callback(Nexus.UserText and Nexus.UserText.Message(message) or message)
    end
    local Adapter

    local MAX_WISHLIST_ECHOES = 79
    local MAX_LOCK_SLOTS = 6
    local APPLY_FRIENDLY = {
        spacing = "the server is busy with another build operation -- try again in a moment",
        refused = "the server refused the change (are you in a state that allows editing your build?)",
        ["no echoes"] = "there are no echoes in your pending list",
        ["no valid echoes"] = "none of the pending echoes look valid",
    }

    local state = {
        pending = {},
        pendingLock = {},
        fulfilledDraftTargets = {},
        pendingSeeded = false,
        editingContext = nil,
        createTargetContext = nil,
        awaitingWishlist = nil,
        scrollOffset = 0,
        pickOffset = 0,
        pendingLoadoutOpen = nil,
        assigningLockSlot = false,
        replacingSpellId = nil,
        currentLockKey = 0,
        applyRetry = nil,
        applyConfirmation = nil,
        candidateContext = nil,
        candidateSerial = 0,
        candidateApplyToken = nil,
        presentationRevision = 0,
    }
    local metrics = {
        lockedSkipped = 0,
        overflowSkipped = 0,
        untrustedOverflowSkipped = 0,
        lockDesignCollisions = 0,
        lockBudgetExceeded = 0,
        swapPairs = 0,
    }

    local M = {}

    local function TouchPresentation()
        state.presentationRevision = state.presentationRevision + 1
        if state.presentationRevision > 9007199254740000 then
            state.presentationRevision = 1
        end
        return state.presentationRevision
    end

    local function CopyRecord(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for key, field in pairs(value) do out[key] = field end
        return out
    end

    local function AccountRoot()
        if type(options.accountRoot) == "function" then
            local root = options.accountRoot()
            if type(root) == "table" then return root end
        end
        return {}
    end

    local function Preferences()
        return AccountRoot()
    end

    local function TrustedLockedProjection()
        if Adapter and Adapter.LockedOwned then
            local locked = Adapter.LockedOwned()
            local bySpell = DraftModel.LockedSpellCounts(locked)
            if bySpell then
                return {synced=true,bySpell=bySpell}
            end
        end
        return nil
    end

    local function LockedBySpell()
        local locked = TrustedLockedProjection()
        return locked and locked.bySpell or {}
    end

    local function Catalog()
        return Adapter and Adapter.Catalog and Adapter.Catalog() or nil
    end

    local function BoundedReason(value, fallback)
        local reason = tostring(value or fallback or "record evidence changed")
        if #reason > 140 then reason = reason:sub(1, 140) end
        return reason
    end

    local function CandidateCurrent()
        local context = state.candidateContext
        if not context then return true end
        if type(context.validate) ~= "function" then
            return false, "record validation is unavailable"
        end
        local ok, current, reason = pcall(context.validate,
            context.sourceIdentity, context.sourceRevision,
            context.evidenceToken)
        if not ok or current ~= true then
            return false, BoundedReason(reason,
                ok and "record evidence changed" or "record validation failed")
        end
        return true
    end

    local function CurrentDraftToken()
        local ordinary, locked = {}, {}
        for _, echo in ipairs(DraftModel.CanonicalEchoes(state.pending)) do
            ordinary[#ordinary + 1] = table.concat({
                tostring(echo.spellId or 0),
                tostring(echo.quality or 0),
                tostring(echo.stacks or 1),
            }, ":")
        end
        local function AddLockedToken(id, copies, replaces)
            id = tonumber(id)
            copies = tonumber(copies)
            if not id or not copies or copies < 1
                or copies >= math.huge or copies ~= math.floor(copies) then
                return
            end
            local current = locked[id] or {copies=0}
            current.copies = current.copies + copies
            if current.replaces == nil and type(replaces) == "number" then
                current.replaces = replaces
            end
            locked[id] = current
        end
        for _, row in pairs(state.pending) do
            if row and row.lockIntent and tonumber(row.spellId) then
                AddLockedToken(row.spellId, 1, row.replaces)
            end
        end
        for _, row in pairs(state.pendingLock) do
            if row and tonumber(row.spellId) then
                AddLockedToken(row.spellId, row.stacks, row.replaces)
            end
        end
        for spellId, replacement in pairs(state.fulfilledDraftTargets) do
            local id = tonumber(spellId)
            local copies = DraftModel.TargetCopies(replacement, id)
            if id and copies then
                locked[id] = {
                    copies=copies,
                    replaces=DraftModel.TargetReplacement(replacement, id),
                }
            end
        end
        local lockedIds = {}
        for id, replacement in pairs(locked) do
            lockedIds[#lockedIds + 1] = {
                id=id,replacement=tostring(replacement.copies) .. ":"
                    .. tostring(replacement.replaces or ""),
            }
        end
        table.sort(lockedIds,function(left,right) return left.id<right.id end)
        for index, row in ipairs(lockedIds) do
            lockedIds[index]=tostring(row.id)..">"..row.replacement
        end
        return table.concat(ordinary, ",") .. "|" .. table.concat(lockedIds, ",")
    end

    local function ApplyPayloadToken(slot, name, echoes)
        local safeName = tostring(name or "")
        local parts = {tostring(tonumber(slot) or 0),
            tostring(#safeName) .. ":" .. safeName}
        for _, echo in ipairs(type(echoes) == "table" and echoes or {}) do
            parts[#parts + 1] = table.concat({
                tostring(echo.spellId or 0),
                tostring(echo.quality or 0),
                tostring(echo.stacks or 1),
            }, ":")
        end
        return table.concat(parts, "|")
    end

    local function WishlistPresentationRevision()
        if not (Adapter and Adapter.PresentationRevisions) then return 0 end
        local _, _, _, _, revision = Adapter.PresentationRevisions()
        return tonumber(revision) or 0
    end

    local function DraftUntouched()
        return next(state.pending) == nil
            and next(state.pendingLock) == nil
            and next(state.fulfilledDraftTargets) == nil
            and (state.currentLockKey == nil or state.currentLockKey == 0)
    end

    -- Returns the committed per-slot target table of the current content key, read
    -- THROUGH the authorized entry rather than through Store.State() (the
    -- DURABLE_READ no longer hands out writable durable state). A lookup never
    -- creates a bucket: with no committed design it answers a fresh EMPTY table that
    -- is not stored. Its callers (ApplyCommittedTargets, PlanLockCommit) only read it;
    -- a bucket is created only by CommitLockDesignTargets for a design that has
    -- targets, and by the one-time move of the retired flat account table below.
    -- Before this rule every distinct Wishlist content that was opened or saved left a
    -- permanent empty bucket (docs/W4_EMPTY_LOCK_BUCKETS.md).
    local function LockDesignTargets()
        if state.currentDesignTargets~=nil then return state.currentDesignTargets end
        local account = AccountRoot()
        local old = account.lockDesignTargets
        local key = state.currentLockKey or 0
        local ok, targets = UpdateStoreState(function(character)
            local map = character.lockDesignTargetsBySlot
            local found = type(map) == "table" and map[key] or nil
            if found == nil and type(old) == "table" then
                -- The retired flat account table moves under this key, once.
                character.lockDesignTargetsBySlot = map or {}
                character.lockDesignTargetsBySlot[key] = old
                found = old
            end
            return found
        end)
        if type(old) == "table" then account.lockDesignTargets = nil end
        if not ok or type(targets) ~= "table" then return {} end
        return targets
    end

    local function PublishLoadMetrics()
        if metrics.overflowSkipped > 0 then
            notify(string.format(
                "|cffff6060Nexus:|r this wishlist has more than %d Echo copies -- %d don't fit "
                    .. "and aren't locked yet. They're listed below as locked-slot targets and are "
                    .. "pursued separately from the 79-copy wishlist.",
                MAX_WISHLIST_ECHOES, metrics.overflowSkipped))
        end
        if metrics.untrustedOverflowSkipped > 0 then
            notify(string.format(
                "|cffff6060Nexus:|r This import exceeds %d rolled copies, and %d copies could not be assigned a locked role. "
                    .. "Keep the original build. Review and confirm the intended locked targets before saving; do not delete the original to clear this message.",
                MAX_WISHLIST_ECHOES, metrics.untrustedOverflowSkipped))
        end
        if metrics.swapPairs > 0 then
            notify(string.format(
                "|cff4dff80Nexus:|r This plan has %d locked target%s different from your currently locked Echoes (gold in the target strip). "
                    .. "Choosing targets changes no owned Echoes. Review any replacement yourself, or use locked-Echo slot automation only with both Automation and that option enabled.",
                metrics.swapPairs, metrics.swapPairs == 1 and "" or "s"))
        end
        if metrics.lockDesignCollisions > 0 then
            notify(string.format(
                "|cffff9040Nexus:|r %d of this build's locked picks share an Echo with one already "
                    .. "queued (different quality copies of the same Echo) -- only the higher-quality "
                    .. "copy of each is kept, so fewer than 6 locked-design slots may be filled.",
                metrics.lockDesignCollisions))
        end
        if metrics.lockBudgetExceeded > 0 then
            notify(string.format(
                "|cffff6060Nexus:|r this build asks for %d more locked-design Echoes than the account's "
                    .. "%d locked Echo slots can ever hold -- they were left out entirely, not just queued.",
                metrics.lockBudgetExceeded, MAX_LOCK_SLOTS))
        end
    end

    function M.Initialize(adapter)
        -- Rebinding the live facade must not replace an in-progress draft or
        -- retry record. Store/account callbacks are deliberately read late.
        Adapter = adapter
        TouchPresentation()
        return true
    end

    -- Scalar-only invalidation state for the open editor. Adapter revisions
    -- own represented game data; this controller revision owns draft, filter,
    -- scroll, association-session, and retry-visible state. A missing revision
    -- provider deliberately disables the renderer's warm cache.
    function M.RefreshState()
        local provider = Adapter and Adapter.PresentationRevisions
        if type(provider) ~= "function" then
            return false, state.presentationRevision
        end
        local ok, slots, active, granted, owned, wishlist, catalog,
            locked, lockedProjection, discovery, lever, firstRun =
            pcall(provider)
        if not ok or slots == nil or active == nil or granted == nil
            or owned == nil or wishlist == nil or catalog == nil
            or locked == nil or lockedProjection == nil
            or discovery == nil or lever == nil or firstRun == nil then
            return false, state.presentationRevision
        end
        return true, state.presentationRevision, slots, active, granted,
            owned, wishlist, catalog, locked, lockedProjection, discovery,
            lever, firstRun
    end

    -- Read-only presentation projections keep the renderer behind this
    -- controller boundary. The Adapter remains private to the controller;
    -- render code cannot upload, associate, persist, or submit gameplay work.
    function M.CatalogProjection()
        return Catalog()
    end

    function M.OwnedProjection()
        return Adapter and Adapter.Owned and Adapter.Owned() or nil
    end

    function M.LockedProjection()
        return TrustedLockedProjection()
    end

    function M.WishlistProjection()
        return Adapter and Adapter.Wishlist and Adapter.Wishlist() or nil
    end

    function M.WishlistCandidatesProjection()
        return Adapter and Adapter.GetWishlistCandidates
            and Adapter.GetWishlistCandidates() or {}
    end

    -- Read-only management projections.
    function M.RetainedPlansProjection()
        return Adapter and Adapter.RetainedWishlistPlans
            and Adapter.RetainedWishlistPlans() or {}
    end

    function M.ForgottenPlanProjection()
        return Adapter and Adapter.ForgottenWishlistPlan
            and Adapter.ForgottenWishlistPlan() or nil
    end

    -- Everything still recoverable, newest first, so the list can offer more
    -- than the newest one back.
    function M.ForgottenPlansProjection()
        return Adapter and Adapter.ForgottenWishlistPlans
            and Adapter.ForgottenWishlistPlans() or {}
    end

    function M.ServerDeletionSupportProjection()
        local probe = Adapter and Adapter.ServerWishlistDeletionSupport
        if type(probe) ~= "function" then
            return {supported = false, reason = "deletion support is unknown"}
        end
        return probe()
    end

    -- Intentions. Each returns ok plus the reason to show when it refuses, and
    -- a refusal is retained with the same bounded facts as a switch refusal.
    function M.ForgetRetainedPlan(selector)
        local act = Adapter and Adapter.ForgetWishlistPlan
        if type(act) ~= "function" then
            return false, "this build cannot remove a saved wishlist"
        end
        local ok, reason, detail = act(selector)
        if not ok then
            if M._RecordSwitchRefusal then M._RecordSwitchRefusal("forget wishlist", "FORGET_REFUSED", {
                detail = reason,
                key = type(selector) == "table" and selector.key or nil,
                loadoutSlot = type(selector) == "table"
                    and selector.associationIndex or nil,
                sourceKind = "local",
            }) end
            return false, reason or "that plan could not be removed"
        end
        return true, nil, detail
    end

    function M.RestoreForgottenPlan(selector)
        local act = Adapter and Adapter.RestoreForgottenWishlistPlan
        if type(act) ~= "function" then
            return false, "this build cannot restore a removed wishlist"
        end
        local ok, reason, detail = act(selector)
        if ok then return true, nil, detail end
        if M._RecordSwitchRefusal then
            M._RecordSwitchRefusal("restore wishlist", "RESTORE_REFUSED",
                {detail = reason, sourceKind = "local"})
        end
        return false, reason or "nothing could be restored"
    end

    function M.SlotsProjection()
        return Adapter and Adapter.Slots and Adapter.Slots() or nil
    end

    function M.LoadoutWishlistProjection(slot)
        return Adapter and Adapter.GetLoadoutWishlist
            and Adapter.GetLoadoutWishlist(slot) or nil
    end

    -- The runtime's own settings (Store.Settings), so the editor shows exactly
    -- what locked-Echo slot automation will do.
    function M.AutoLockEnabled()
        local settings = Store.Settings and Store.Settings()
        return type(settings) == "table" and settings.autoLockEchoes and true or false
    end

    function M.SetAutoLockEnabled(value)
        local wasEnabled = M.AutoLockEnabled()
        local enabled = value and true or false
        local result, why = UpdateStoreSetting("autoLockEchoes", enabled)
        if not result then
            notify("|cffff6060Nexus:|r locked-Echo slot automation was not changed ("
                .. tostring(why) .. ").")
            return false
        end
        if result.mode == "session" and result.note then
            notify(string.format("|cffff9040Nexus:|r locked-Echo slot automation is %s "
                .. "for this session only: %s.", enabled and "on" or "off", result.note))
        end
        if wasEnabled ~= enabled then TouchPresentation() end
        local retried = false
        if enabled and not wasEnabled
            and type(options.retryAutoLock) == "function" then
            retried = options.retryAutoLock() == true
        end
        if not retried and type(options.requestRecompute) == "function" then
            options.requestRecompute()
        end
    end

    function M.PendingRows() return state.pending end
    function M.PendingLockRows() return state.pendingLock end
    function M.FulfilledDraftTargets() return state.fulfilledDraftTargets end
    function M.PendingTotal() return DraftModel.PendingTotal(state.pending) end
    function M.CanonicalEchoes() return DraftModel.CanonicalEchoes(state.pending) end
    function M.EditingContext() return CopyRecord(state.editingContext) end
    function M.IsEditing() return state.editingContext ~= nil end
    function M.CreateTargetContext() return CopyRecord(state.createTargetContext) end
    function M.CandidateContext()
        local context = state.candidateContext
        return context and {
            serial=context.serial,
            sourceIdentity=context.sourceIdentity,
            sourceRevision=context.sourceRevision,
            evidenceToken=context.evidenceToken,
        } or nil
    end
    function M.ApplyBlockReason()
        local current, reason = CandidateCurrent()
        return current and nil or reason
    end
    function M.IsAssigningLockSlot() return state.assigningLockSlot end
    function M.ReplacingSpellId() return state.replacingSpellId end
    function M.ScrollOffset() return state.scrollOffset end
    function M.PickOffset() return state.pickOffset end
    function M.PendingLoadoutOpen() return CopyRecord(state.pendingLoadoutOpen) end
    function M.ClearPendingLoadoutOpen()
        if state.pendingLoadoutOpen ~= nil then
            state.pendingLoadoutOpen = nil
            TouchPresentation()
        end
    end

    function M.FilterState()
        local preferences = Preferences()
        return {
            search = preferences.editorSearch or "",
            classOnly = preferences.editorClassOnly ~= false,
        }
    end

    function M.SetSearch(value)
        local preferences = Preferences()
        value = tostring(value or "")
        if tostring(preferences.editorSearch or "") ~= value
            or state.scrollOffset ~= 0 then
            preferences.editorSearch = value
            state.scrollOffset = 0
            TouchPresentation()
        end
    end

    function M.SetClassOnly(value)
        local preferences = Preferences()
        value = value and true or false
        if (preferences.editorClassOnly ~= false) ~= value
            or state.scrollOffset ~= 0 then
            preferences.editorClassOnly = value
            state.scrollOffset = 0
            TouchPresentation()
        end
    end

    function M.SetScrollOffset(value)
        value = math.max(0, tonumber(value) or 0)
        if state.scrollOffset ~= value then
            state.scrollOffset = value
            TouchPresentation()
        end
        return state.scrollOffset
    end

    function M.AdjustScroll(delta)
        return M.SetScrollOffset(state.scrollOffset - (tonumber(delta) or 0) * 3)
    end

    function M.ClampScroll(count, visible)
        count, visible = math.max(0, tonumber(count) or 0), math.max(0, tonumber(visible) or 0)
        -- #63: never past the last full window.
        local lastFull = math.max(0, count - visible)
        if state.scrollOffset > lastFull then
            state.scrollOffset = lastFull
            TouchPresentation()
        end
        return state.scrollOffset
    end

    function M.SetPickOffset(value)
        value = math.max(0, tonumber(value) or 0)
        if state.pickOffset ~= value then
            state.pickOffset = value
            TouchPresentation()
        end
        return state.pickOffset
    end

    function M.AdjustPick(delta)
        return M.SetPickOffset(state.pickOffset - (tonumber(delta) or 0) * 3)
    end

    function M.ClampPick(count, visible)
        count, visible = math.max(0, tonumber(count) or 0), math.max(0, tonumber(visible) or 0)
        -- #63: never past the last full window.
        local lastFull = math.max(0, count - visible)
        if state.pickOffset > lastFull then
            state.pickOffset = lastFull
            TouchPresentation()
        end
        return state.pickOffset
    end

    function M.LoadPendingEchoes(echoes, trustOrder, designTargets)
        if trustOrder == nil then trustOrder = true end
        state.currentDesignTargets=designTargets
        state.pending = {}
        state.pendingLock = {}
        state.fulfilledDraftTargets = {}
        state.currentLockKey = (Adapter and Adapter.WishlistKey
            and Adapter.WishlistKey(echoes)) or 0

        local catalog = Catalog()
        local lockedBySpell = LockedBySpell()
        local ordinaryEchoes, lockedEchoes = {}, {}
        local typedRoles = type(echoes) == "table" and #echoes > 0
        for _, echo in ipairs(type(echoes) == "table" and echoes or {}) do
            if type(echo) ~= "table" or type(echo.locked) ~= "boolean" then
                typedRoles = false
                break
            end
            local target = echo.locked and lockedEchoes or ordinaryEchoes
            target[#target + 1] = echo
        end
        local prepared, prepareError
        if typedRoles then
            prepared, prepareError = DraftModel.NormalizeCandidateEvidence(
                ordinaryEchoes, lockedEchoes, {
                    catalog=catalog,lockedBySpell=lockedBySpell,
                })
        else
            prepared = DraftModel.NormalizeDraft(echoes, {
                trustOrder = trustOrder,
                catalog = catalog,
                lockedBySpell = lockedBySpell,
            })
        end
        if not prepared then
            TouchPresentation()
            return false, prepareError or "Wishlist evidence is invalid"
        end
        state.pending = prepared.pending
        state.pendingLock = prepared.pendingLock
        state.fulfilledDraftTargets = prepared.fulfilledTargets
        metrics = prepared.metrics
        PublishLoadMetrics()

        -- A complete explicit-role input already contains its locked targets.
        -- Merging an older sidecar here would duplicate or resurrect targets.
        -- Ordinary-only server uploads still need their separate local designs.
        local withCommitted = prepared
        if not typedRoles or #lockedEchoes==0 then
            withCommitted = DraftModel.ApplyCommittedTargets(prepared,
                LockDesignTargets(), {catalog = catalog, lockedBySpell = lockedBySpell})
        end
        state.pending = withCommitted.pending
        state.pendingLock = withCommitted.pendingLock
        state.fulfilledDraftTargets = withCommitted.fulfilledTargets
        TouchPresentation()
        return true
    end

    function M.SeedPendingFromWishlist()
        if state.pendingSeeded then return false end
        state.pendingSeeded = true
        local wishlist = Adapter and Adapter.Wishlist and Adapter.Wishlist()
        if wishlist then M.LoadPendingEchoes(wishlist.entries or {}, false,wishlist.designTargets) end
        if not wishlist then TouchPresentation() end
        return wishlist ~= nil
    end

    function M.AddPending(row)
        if not row or not tonumber(row.spellId) then return "invalid" end
        local lockedBySpell = LockedBySpell()
        if (tonumber(lockedBySpell[tonumber(row.spellId)]) or 0) > 0 then
            notify("|cffff6060Nexus:|r " .. tostring(row.name or "that Echo")
                .. " is already locked -- it doesn't need a wishlist slot.")
            return "already_locked"
        end
        local nextPending, outcome = DraftModel.AddPending(state.pending, row, {
            catalog = Catalog(), lockedBySpell = lockedBySpell,
        })
        if outcome == "full" then
            notify("|cffff6060Nexus:|r wishlist is full (79 / 79 Echoes). Use an empty Locked slot to design an additional locked Echo.")
            return outcome
        end
        state.pending = nextPending
        TouchPresentation()
        return outcome
    end

    function M.RemovePending(rowKey)
        state.pending, state.pendingLock =
            DraftModel.RemovePending(state.pending, state.pendingLock, rowKey)
        TouchPresentation()
    end

    function M.ToggleDesignLock(rowKey)
        if not rowKey then return "invalid" end
        local resolved = DraftModel.ResolveDraftKey(state.pending, rowKey)
        local localOnly = state.pendingLock[rowKey]
            or (resolved and state.pending[resolved].lockIntent)
        if not localOnly and not resolved then return "unchanged" end
        local lockedBySpell = localOnly and {} or LockedBySpell()
        local nextPending, nextLock, nextReplacing, outcome =
            DraftModel.ToggleDesignLock(state.pending, state.pendingLock, rowKey, {
                lockedBySpell = lockedBySpell,
                replacingSpellId = state.replacingSpellId,
            })
        if outcome == "normal_full" then
            notify("|cffff6060Nexus:|r the normal wishlist is already full -- remove another Echo before moving this locked target back into it.")
            return outcome
        end
        if outcome == "lock_full" then
            notify(string.format(
                "|cffff6060Nexus:|r only %d Echoes can be locked in total -- untag one first.",
                MAX_LOCK_SLOTS))
        end
        state.pending, state.pendingLock, state.replacingSpellId =
            nextPending, nextLock, nextReplacing
        TouchPresentation()
        return outcome
    end

    function M.AdjustStacks(rowKey, delta)
        local nextPending, outcome = DraftModel.AdjustStacks(state.pending, rowKey, delta)
        if outcome == "full" then
            notify("|cffff6060Nexus:|r wishlist is full (79 / 79 Echoes).")
            return outcome
        end
        state.pending = nextPending
        TouchPresentation()
        return outcome
    end

    function M.AssignLockSlot(data)
        if not data or not tonumber(data.spellId) then return "invalid" end
        local catalog = Catalog()
        local family = DraftModel.Family(data.spellId, catalog)
        local rowKey = DraftModel.DraftKey(data.spellId, catalog)
        local localOnly = (state.pending[rowKey] and state.pending[rowKey].lockIntent)
            or state.pendingLock[family]
        local lockedBySpell = localOnly and {} or LockedBySpell()
        local nextPending, nextLock, nextReplacing, outcome =
            DraftModel.AssignLockSlot(state.pending, state.pendingLock, data, {
                catalog = catalog,
                lockedBySpell = lockedBySpell,
                replacingSpellId = state.replacingSpellId,
            })
        state.pending, state.pendingLock, state.replacingSpellId =
            nextPending, nextLock, nextReplacing
        TouchPresentation()
        if outcome == "tagged" then
            notify("|cff4dff80Nexus:|r " .. tostring(data.name)
                .. " is now designed for a locked slot and no longer consumes the 79-copy wishlist budget.")
        elseif outcome == "already" then
            notify("|cff4dff80Nexus:|r " .. tostring(data.name)
                .. " is already designed for a locked slot.")
        elseif outcome == "lock_full" then
            notify(string.format(
                "|cffff6060Nexus:|r only %d Echoes can be locked in total.",
                MAX_LOCK_SLOTS))
        elseif outcome == "queued" then
            notify("|cff4dff80Nexus:|r added " .. tostring(data.name)
                .. " as a locked-slot target. It is pursued separately from the 79-copy wishlist.")
        end
        return outcome
    end

    function M.ToggleEmptyAssignment()
        state.assigningLockSlot = not state.assigningLockSlot
        state.replacingSpellId = nil
        TouchPresentation()
        if state.assigningLockSlot then
            notify("|cff4dff80Nexus:|r click an Echo -- either list -- to assign it to this locked slot.")
        else
            notify("|cff7fff7fNexus:|r cancelled.")
        end
        return state.assigningLockSlot
    end

    function M.ToggleReplacementAssignment(spellId)
        spellId = tonumber(spellId)
        if not spellId then return false end
        if state.replacingSpellId == spellId then
            state.assigningLockSlot = false
            state.replacingSpellId = nil
            notify("|cff7fff7fNexus:|r cancelled.")
        else
            state.assigningLockSlot = true
            state.replacingSpellId = spellId
            notify("|cff4dff80Nexus:|r click an Echo in either list to plan its "
                .. "replacement. Your current one remains in its locked Echo slot. Automatic changes require "
                .. "both Automation and locked-Echo slot management ON, plus the acquired target and safety checks.")
        end
        TouchPresentation()
        return state.assigningLockSlot
    end

    function M.EndAssignment()
        if state.assigningLockSlot then
            state.assigningLockSlot = false
            TouchPresentation()
        end
    end

    function M.ReconcileLocked(lockedBySpell)
        state.pending, state.pendingLock, state.fulfilledDraftTargets =
            DraftModel.ReconcileLocked(state.pending, state.pendingLock,
                state.fulfilledDraftTargets, lockedBySpell)
        TouchPresentation()
    end

    function M.CancelApply(data)
        if data and data.confirmation ~= state.applyConfirmation then return false end
        state.applyConfirmation = nil
        state.applyRetry = nil
        state.candidateApplyToken = nil
        return true
    end

    function M.ResetNewWishlistDraft()
        M.CancelApply()
        state.editingContext = nil
        state.createTargetContext = nil
        -- Assignment actions as this new draft begins (see TryApply).
        state.draftActions = Adapter and Adapter.AssignmentActionSnapshot
            and Adapter.AssignmentActionSnapshot() or nil
        state.awaitingWishlist = nil
        state.pending = {}
        state.pendingLock = {}
        state.fulfilledDraftTargets = {}
        state.scrollOffset = 0
        state.pickOffset = 0
        state.pendingLoadoutOpen = nil
        state.pendingSeeded = true
        state.currentLockKey = 0
        state.currentDesignTargets={}
        state.candidateContext = nil
        state.candidateApplyToken = nil
        state.applyRetry = nil
        TouchPresentation()
    end

    function M.BeginCandidate(candidate)
        if type(candidate) == "table" and candidate.evidenceKind ~= nil then
            local evidence = Nexus and Nexus.CandidateEvidence
            if not (evidence and type(evidence.Validate) == "function") then
                notify("|cffff6060Nexus:|r Copy unavailable: record validation is unavailable.")
                return nil, "record validation is unavailable"
            end
            local current, validationReason = evidence.Validate(candidate)
            if not current then
                local reason = BoundedReason(validationReason,
                    "record evidence changed")
                notify("|cffff6060Nexus:|r Copy unavailable: " .. reason .. ".")
                return nil, reason
            end
            local catalog = Catalog()
            local lockedBySpell = LockedBySpell()
            local prepared, reason = DraftModel.NormalizeCandidateEvidence(
                current.ordinaryEchoes, current.lockedEchoes, {
                    catalog=catalog,
                    lockedBySpell=lockedBySpell,
                })
            if not prepared then
                notify("|cffff6060Nexus:|r Copy unavailable: "
                    .. BoundedReason(reason, "record evidence is ambiguous") .. ".")
                return nil, reason
            end
            M.ResetNewWishlistDraft()
            state.pendingSeeded = true
            state.pending = prepared.pending
            state.pendingLock = prepared.pendingLock
            state.fulfilledDraftTargets = prepared.fulfilledTargets
            metrics = prepared.metrics
            state.currentLockKey = (Adapter and Adapter.WishlistKey
                and Adapter.WishlistKey(current.ordinaryEchoes)) or 0
            state.candidateSerial = state.candidateSerial + 1
            state.candidateContext = {
                serial=state.candidateSerial,
                sourceIdentity=tostring(current.sourceIdentity or ""),
                sourceRevision=tostring(current.sourceRevision or ""),
                evidenceToken=tostring(current.evidenceToken or ""),
                validate=current.validate,
            }
            PublishLoadMetrics()
            return DraftModel.TrimName(current.title)
        end
        M.ResetNewWishlistDraft()
        state.pendingSeeded = true
        M.LoadPendingEchoes(type(candidate) == "table" and candidate.echoes or {})
        return type(candidate) == "table" and DraftModel.TrimName(candidate.title) or ""
    end

    -- Whether a Wishlist identity is the first-run plan: the same assignment
    -- identity; the content key when neither has one.
    local function IsFirstRunPlan(identity)
        local root = Store.State and Store.State()
        local first = type(root) == "table" and root.firstRunWishlist
        if type(first) ~= "table" or type(identity) ~= "table" then return false end
        if identity.assignmentId ~= nil or first.assignmentId ~= nil then
            return first.assignmentId == identity.assignmentId
        end
        return identity.key ~= nil and first.key == identity.key
    end

    function M.BeginWishlist(wishlist, loadoutSlot)
        M.CancelApply()
        state.candidateContext = nil
        state.candidateApplyToken = nil
        state.applyRetry = nil
        state.createTargetContext = nil
        if type(wishlist) ~= "table" or type(wishlist.echoes)~="table" then
            notify("|cffff6060Nexus:|r Associated wishlist data is unavailable.")
            return false
        end
        if Adapter and type(Adapter.ResolveWishlistEvidence) == "function"
            and (wishlist.lockEvidenceStatus == "unavailable"
                or wishlist.evidenceSource == "verified-active"
                or DraftModel.EchoListTotal(wishlist.echoes or {}) > MAX_WISHLIST_ECHOES) then
            local resolved, status, _, reason = Adapter.ResolveWishlistEvidence(wishlist)
            if status ~= "actionable" then
                notify("|cffff9040Nexus:|r " .. tostring(reason
                    or "Wishlist identity found; awaiting authoritative locked-Echo evidence") .. ".")
                return false
            end
            wishlist = resolved
        end
        if wishlist.lockEvidenceStatus == "unavailable"
            or (tonumber(wishlist.lockEvidenceVersion) ~= 1
                and DraftModel.EchoListTotal(wishlist.echoes or {})
                    > MAX_WISHLIST_ECHOES) then
            notify("|cffff9040Nexus:|r Wishlist identity found; awaiting authoritative lock evidence before editing.")
            return false
        end
        state.awaitingWishlist = nil
        state.pendingSeeded = true
        state.editingContext = {
            slot = tonumber(wishlist.slot),
            name = tostring(wishlist.name or "Wishlist"),
            key = wishlist.key,
            assignmentId=wishlist.assignmentId,
            loadoutSlot = tonumber(loadoutSlot),
            loadoutName = tostring(wishlist.loadoutName or ""),
            -- What that Saved Build and the first-run plan hold now: a save
            -- does not undo a choice made after this (see TryApply).
            boundAssignment = tonumber(loadoutSlot) and Adapter
                and Adapter.LoadoutAssignmentToken
                and Adapter.LoadoutAssignmentToken(loadoutSlot) or nil,
            boundFirstRun = tonumber(loadoutSlot) and Adapter
                and Adapter.FirstRunToken and Adapter.FirstRunToken() or nil,
            -- Assignment actions as the editor opens, and the destination its
            -- save assigns: the Saved Build, the first-run plan when this is
            -- that plan, or none.
            boundActions = Adapter and Adapter.AssignmentActionSnapshot
                and Adapter.AssignmentActionSnapshot() or nil,
        }
        state.editingContext.destination = tonumber(loadoutSlot)
            or (IsFirstRunPlan(wishlist) and "first" or nil)
        M.LoadPendingEchoes(wishlist.echoes or {}, false,wishlist.designTargets)
        return true
    end

    function M.SelectLoadout(slot)
        slot = tonumber(slot)
        if not slot then return false, "invalid" end
        local slots = Adapter and Adapter.Slots and Adapter.Slots()
        local row = slots and slots.bySlot and slots.bySlot[slot]
        local name = row and tostring(row.name or "") or ""
        if name == "" then name = "Saved Build " .. tostring(slot) end
        local linked = Adapter and Adapter.GetLoadoutWishlist
            and Adapter.GetLoadoutWishlist(slot)
        if linked then
            linked.loadoutName = name
            return M.BeginWishlist(linked, slot), "wishlist"
        end
        local pending, evidenceState, key
        if Adapter and Adapter.GetLoadoutWishlistState then
            pending, evidenceState, key = Adapter.GetLoadoutWishlistState(slot)
        end
        M.ResetNewWishlistDraft()
        state.createTargetContext = {loadoutSlot = slot, loadoutName = name}
        if evidenceState == "evidence-pending" and type(pending) == "table"
            and type(key) == "string" and key ~= "" then
            state.awaitingWishlist = {
                loadoutSlot=slot,loadoutName=name,key=key,
                revision=WishlistPresentationRevision(),
            }
        end
        return true, "new"
    end

    function M.BeginNewWishlist()
        M.ResetNewWishlistDraft()
        local slots = Adapter and Adapter.Slots and Adapter.Slots()
        local active = slots and tonumber(slots.activeSlot) or 0
        local maxSlots = slots and (tonumber(slots.maxSlots) or 5) or 5
        local activeRow = slots and slots.bySlot and slots.bySlot[active]
        if active >= 1 and active <= maxSlots and activeRow
            and type(activeRow.echoes) == "table" and #activeRow.echoes > 0 then
            local name = tostring(activeRow.name or "")
            if name == "" then name = "Saved Build " .. tostring(active) end
            state.createTargetContext = {loadoutSlot = active, loadoutName = name}
        end
    end

    function M.BeginShow()
        local slots = Adapter and Adapter.Slots and Adapter.Slots()
        local active = slots and tonumber(slots.activeSlot) or 0
        -- The Saved Builds the server declares (Slots() uses 5 when it
        -- declares nothing), not a fixed five.
        local maxSlots = slots and (tonumber(slots.maxSlots) or 5) or 5
        if active >= 1 and active <= maxSlots then
            local ok, mode = M.SelectLoadout(active)
            return ok, mode, mode == "new"
        end
        local firstRun = Adapter and Adapter.GetFirstRunWishlist
            and Adapter.GetFirstRunWishlist()
        if firstRun then
            return M.BeginWishlist(firstRun, nil), "wishlist", false
        end
        M.ResetNewWishlistDraft()
        return true, "new", false
    end

    -- The renderer calls this from its existing half-second refresh ticker.
    -- Until the bounded Wishlist revision changes this reads one scalar only;
    -- it never repeats catalog, slot, or candidate traversal on the warm path.
    function M.RefreshWishlistEvidence(nameText)
        local awaiting = state.awaitingWishlist
        if not awaiting then return false end
        local revision = WishlistPresentationRevision()
        if revision == awaiting.revision then return false end
        awaiting.revision = revision

        -- Never replace a draft the player has started while evidence was
        -- pending. Any typed name or Echo edit converts the view into an
        -- intentional new Wishlist and retires the automatic promotion.
        if tostring(nameText or "") ~= "" or not DraftUntouched() then
            state.awaitingWishlist = nil
            return false
        end
        if not (Adapter and Adapter.GetLoadoutWishlistState) then return false end
        local candidate, evidenceState, key =
            Adapter.GetLoadoutWishlistState(awaiting.loadoutSlot)
        if evidenceState ~= "actionable" or key ~= awaiting.key
            or type(candidate) ~= "table" then
            if evidenceState == "association-mismatch"
                or evidenceState == "invalid-schema" then
                state.awaitingWishlist = nil
            end
            return false
        end
        candidate.loadoutName = awaiting.loadoutName
        local name = tostring(candidate.name or "Wishlist")
        if not M.BeginWishlist(candidate, awaiting.loadoutSlot) then return false end
        return true, name
    end

    function M.CandidateAssignment(candidate)
        if type(candidate) ~= "table" then return nil, nil end
        local slots = Adapter and Adapter.Slots and Adapter.Slots()
        if not slots then return nil, nil end
        local active = tonumber(slots.activeSlot)
        local maxSlots = tonumber(slots.maxSlots) or 5
        local fallbackSlot, fallbackName
        for slotId, row in pairs(slots.bySlot or {}) do
            slotId = tonumber(slotId)
            if slotId and slotId >= 1 and slotId <= maxSlots and row
                and type(row.echoes) == "table" and #row.echoes > 0 then
                local linked = Adapter.GetLoadoutWishlist
                    and Adapter.GetLoadoutWishlist(slotId)
                local exact=linked and candidate.assignmentId and linked.assignmentId==candidate.assignmentId
                if linked and (exact or (not candidate.assignmentId
                    and ((candidate.key and linked.key==candidate.key)
                        or (candidate.slot and tonumber(linked.slot)==tonumber(candidate.slot))))) then
                    local name = tostring(row.name or "")
                    if name == "" then name = "Saved Build " .. tostring(slotId) end
                    if slotId == active then return slotId, name end
                    fallbackSlot = fallbackSlot or slotId
                    fallbackName = fallbackName or name
                end
            end
        end
        return fallbackSlot, fallbackName
    end

    function M.AssociateCandidate(candidate)
        local slots = Adapter and Adapter.Slots and Adapter.Slots()
        local active = slots and tonumber(slots.activeSlot) or 0
        local maxSlots = slots and (tonumber(slots.maxSlots) or 5) or 5
        if active >= 1 and active <= maxSlots then
            if not (Adapter and type(Adapter.SetLoadoutWishlist) == "function") then
                return false, "loadout association unavailable", active, false
            end
            local ok, err = Adapter.SetLoadoutWishlist(
                active, candidate and candidate.slot, candidate)
            if ok then
                TouchPresentation()
                return ok, err, active, false
            end
            if M._RecordSwitchRefusal then M._RecordSwitchRefusal("associate wishlist", "ASSOCIATION_REFUSED", {
                detail = err or "wishlist association failed",
                key = candidate and candidate.key or nil,
                loadoutSlot = active,
                mirrorSlot = candidate and candidate.slot or nil,
            }) end
            return ok, err or "wishlist association failed", active, false
        end
        if active == 0 then
            if not (Adapter and type(Adapter.SetFirstRunWishlist) == "function") then
                return false, "first-run association unavailable", nil, true
            end
            local ok, err = Adapter.SetFirstRunWishlist(
                candidate and candidate.slot, candidate)
            if ok then
                TouchPresentation()
                return ok, err, nil, true
            end
            if M._RecordSwitchRefusal then M._RecordSwitchRefusal("associate wishlist", "ASSOCIATION_REFUSED", {
                detail = err or "first-run association unavailable",
                key = candidate and candidate.key or nil,
                mirrorSlot = candidate and candidate.slot or nil,
            }) end
            return ok, err or "first-run association unavailable", nil, true
        end
        -- The active Saved Build is outside the configured range: the same
        -- refusal a player sees when switching, and it is retained too.
        if M._RecordSwitchRefusal then M._RecordSwitchRefusal("associate wishlist", "ASSOCIATION_REFUSED", {
            detail = "invalid active loadout",
            key = candidate and candidate.key or nil,
            loadoutSlot = active,
            mirrorSlot = candidate and candidate.slot or nil,
        }) end
        return false, "invalid active loadout", active, false
    end

    function M.LoadImported(parsed, chosenName)
        if not parsed or type(parsed.entries) ~= "table" or #parsed.entries == 0 then
            return false, nil, 0, "imported Echo evidence is unavailable"
        end
        local ordinary, locked = {}, {}
        for _, echo in ipairs(parsed.entries) do
            if type(echo) ~= "table"
                or (echo.locked ~= nil and type(echo.locked) ~= "boolean") then
                return false, nil, 0, "imported Echo evidence is invalid"
            end
            local target = echo.locked == true and locked or ordinary
            target[#target + 1] = echo
        end
        local prepared, why = DraftModel.NormalizeCandidateEvidence(
            ordinary, locked, {catalog=Catalog(),lockedBySpell=LockedBySpell()})
        if not prepared then return false, nil, 0, why end

        -- Only a fully representable typed draft may replace the current one.
        -- BeginNewWishlist owns the association/reset boundary; the prepared
        -- ordinary and locked pools are installed together afterward.
        M.BeginNewWishlist()
        state.pending = prepared.pending
        state.pendingLock = prepared.pendingLock
        state.fulfilledDraftTargets = prepared.fulfilledTargets
        state.pendingSeeded = true
        state.scrollOffset = 0
        state.pickOffset = 0
        metrics = prepared.metrics
        PublishLoadMetrics()
        TouchPresentation()
        return true, DraftModel.TrimName(chosenName), #parsed.entries
    end

    function M.ExportEntries()
        local locked = TrustedLockedProjection()
        local lockedBySpell = locked and locked.bySpell or {}
        local catalog = Adapter and Adapter.LockedOwned
            and Adapter.Catalog and Adapter.Catalog() or nil
        local planned = DraftModel.ExportEntries(state.pending, state.pendingLock,
            {}, catalog, state.fulfilledDraftTargets)
        -- A design may intentionally differ from current permanent ownership.
        -- Do not append unrelated owned locks to its explicit target set: that
        -- corrupts the exported role split (and can exceed the six-copy limit).
        for _, echo in ipairs(planned) do
            if echo.locked == true then return planned end
        end
        return DraftModel.ExportEntries(state.pending, state.pendingLock,
            lockedBySpell, catalog, state.fulfilledDraftTargets)
    end

    -- An exported code carries this name verbatim, and it is copied out of an
    -- edit box, so it is normalised here as well as where a name is accepted.
    -- The name box, an edit of an existing wishlist and the adapter record are
    -- three separate sources; a rule applied to only one of them is not a rule.
    function M.ExportName(nameText)
        if state.editingContext then
            return DraftModel.TrimName(state.editingContext.name)
        end
        if nameText ~= nil then return DraftModel.TrimName(nameText) end
        if Adapter and Adapter.Wishlist and Adapter.Wishlist() then
            return DraftModel.TrimName(Adapter.Wishlist().name)
        end
        return "Nexus"
    end

    local function CommitLockDesignTargets(echoes)
        local existing = LockDesignTargets()
        local lockedBySpell = LockedBySpell()
        local fresh = DraftModel.PlanLockCommit(state.pending, state.pendingLock,
            state.fulfilledDraftTargets,
            state.candidateContext and {} or existing, lockedBySpell, Catalog())
        local nextKey = (Adapter and Adapter.WishlistKey
            and Adapter.WishlistKey(echoes)) or 0
        local committed, commitReason = UpdateStoreState(function(character)
            -- Preserve legacy plans. New saves carry their own complete design
            -- on the durable assignment; equal rolled contents are not an ID.
            -- An empty design needs no bucket: absent reads as empty.
            if next(fresh) ~= nil then
                character.lockDesignTargetsBySlot =
                    character.lockDesignTargetsBySlot or {}
                if character.lockDesignTargetsBySlot[nextKey]==nil then
                    character.lockDesignTargetsBySlot[nextKey] = fresh
                end
            end
        end)
        if not committed then return false, commitReason or "local_state_unavailable" end
        if Adapter and type(Adapter.RememberWishlistRoles)=="function" then
            -- Do not append arbitrary currently-owned locks. Only this user's
            -- explicit design belongs to the saved plan's role evidence.
            local designed=DraftModel.ExportEntries(state.pending,state.pendingLock,
                {},Catalog(),state.fulfilledDraftTargets)
            local hasLocked=false
            for _,echo in ipairs(designed) do
                echo.locked=echo.locked==true
                if echo.locked then hasLocked=true end
            end
            if hasLocked then
                local saved,why=Adapter.RememberWishlistRoles(designed)
                if not saved then return false,why end
            end
        end
        state.currentLockKey = nextKey
        state.currentDesignTargets=fresh
        state.fulfilledDraftTargets = {}
        for id, value in pairs(fresh) do
            local copies = DraftModel.TargetCopies(value, id)
            if copies and (tonumber(lockedBySpell[id]) or 0) >= copies then
                state.fulfilledDraftTargets[id] = value
            end
        end
        return true,nil,fresh
    end

    -- Whether a save without a loadout context belongs to the first-run
    -- plan. An opened existing Wishlist does only when it is that plan (same
    -- assignment identity; the content key when neither has one): saving
    -- another Wishlist never takes over the first-run target. A new plan
    -- does when the first-run plan is the current target by the Echo
    -- Journal's rule (no active Saved Build in the declared range, or an
    -- empty one; see ui/JournalTab.lua). Slot data that is not loaded yet
    -- proves neither; the second result then says so.
    local function FirstRunOwnsSave()
        local context = state.editingContext
        if context then return IsFirstRunPlan(context) end
        local slots = Adapter and Adapter.Slots and Adapter.Slots()
        if type(slots) ~= "table" or slots.activeKnown == false then return false, true end
        local active = tonumber(slots.activeSlot) or 0
        local maxSlots = tonumber(slots.maxSlots) or 5
        local row = slots.bySlot and slots.bySlot[active]
        local populated = row and type(row.echoes) == "table" and #row.echoes > 0
        return active < 1 or active > maxSlots or not populated
    end

    -- A save stamps a new assignment identity on the plan it updated. The
    -- open editor still holds that same plan, so its binding follows the new
    -- identity (and, for a Saved Build, what it now holds): the next save in
    -- this session is proven by the unchanged checks. The first-run binding
    -- stays as it was at open. A new plan (no editing context) is not bound.
    -- Of the assignment actions, the editor adopts exactly the tokens its own
    -- save installed (AdoptActions); nothing else that happened since it
    -- opened.
    local function AdoptActions(bound, installed)
        if type(bound) ~= "table" or type(installed) ~= "table" then return end
        bound.tokens = bound.tokens or {}
        for destination, token in pairs(installed) do bound.tokens[destination] = token end
    end

    local function RebindAfterSave(assignmentId, key, installed)
        local context = state.editingContext
        if context and assignmentId ~= nil then
            context.assignmentId = assignmentId
            if key ~= nil then context.key = key end
            if context.loadoutSlot and Adapter.LoadoutAssignmentToken then
                context.boundAssignment = Adapter.LoadoutAssignmentToken(context.loadoutSlot)
            end
            AdoptActions(context.boundActions, installed)
        end
    end

    -- The destination this save would assign and the actions bound for it:
    -- an opened Wishlist's own; a new plan's Saved Build, or the first-run
    -- plan by the Echo Journal's rule (bound when the draft began).
    local function SaveDestination()
        local context = state.editingContext
        if context then return context.destination, context.boundActions end
        if state.createTargetContext then
            return state.createTargetContext.loadoutSlot, state.draftActions
        end
        if FirstRunOwnsSave() then return "first", state.draftActions end
        return nil
    end

    local function NotSavedChanged(destination)
        local context = state.editingContext or state.createTargetContext
        local label = context and context.loadoutName ~= nil and tostring(context.loadoutName) ~= ""
            and ("Saved Build '" .. tostring(context.loadoutName) .. "'")
            or (destination == "first" and "the first-run Wishlist")
            or ("Saved Build " .. tostring(destination))
        notify("|cffffd200Nexus:|r Not saved: " .. label .. " was assigned, unassigned or restored "
            .. "while the editor was open, and that choice is kept. Nothing was uploaded or "
            .. "assigned; your edits are still shown. Close and reopen the editor to edit the "
            .. "current Wishlist.")
    end

    local function TryApply(slot, name, echoes, guard)
        -- An upload may be delayed by the service's spacing guard. The confirmed
        -- draft must still be current BEFORE sending, not merely before opening
        -- the confirmation dialog. A changed draft is never silently substituted.
        local draftToken = guard and (guard.draftToken
            or (guard.confirmation and guard.confirmation.draftToken))
            or CurrentDraftToken()
        if draftToken ~= CurrentDraftToken() then
            state.applyRetry = nil
            notify("|cffff6060Nexus:|r Save cancelled: the editor changed. Review and save again.")
            return false, "stale_confirmation"
        end
        -- An Assign, Unassign or Restore of the destination this save would
        -- assign (in the Echo Journal, My Builds or the editor's own assign
        -- buttons), made after the editor bound it, is authoritative: nothing
        -- is uploaded, and the editor must be reopened. Checked again inside
        -- each writer.
        local destination, bound = SaveDestination()
        if destination ~= nil and bound ~= nil and Adapter.AssignmentActionUnchanged
            and not Adapter.AssignmentActionUnchanged(bound, destination) then
            state.applyRetry = nil
            NotSavedChanged(destination)
            return false, "assignment_changed"
        end
        local ok, err = Adapter.UploadWishlist(slot or 0, name, echoes)
        if ok then
            -- Service callbacks must not attach a newly edited draft to this
            -- completed upload. Report partial completion; never repeat upload.
            if draftToken ~= CurrentDraftToken() then
                state.applyRetry = nil
                notify("|cffff6060Nexus:|r Wishlist uploaded, but the editor changed; local targets were not reassigned. Review and save again.")
                return false, "uploaded_draft_changed"
            end
            local committed, commitReason, designTargets = CommitLockDesignTargets(echoes)
            if not committed then
                state.applyRetry = nil
                notify("|cffff6060Nexus:|r Wishlist uploaded, but local designed targets could not be saved. Your draft is preserved.")
                return false, commitReason or "local_save_incomplete"
            end
            -- The uploaded rows are exactly the plan's ORDINARY rows (locked
            -- targets are the committed design). Record them with that role:
            -- stored without it, an explicit ordinary row became untyped, and
            -- a save that changed nothing let current locks count for
            -- ordinary copies the plan still asks for.
            local recorded = {}
            for index, echo in ipairs(echoes) do
                recorded[index] = {spellId=echo.spellId, quality=echo.quality,
                    stacks=echo.stacks, locked=false}
            end
            local associated, associationReason = true, nil
            local function KeptNotice()
                -- Only if a destination changed after the check above.
                associated = true
                notify("|cffffd200Nexus:|r '" .. tostring(name) .. "' was uploaded, but its assignment "
                    .. "was changed while the editor was open; that choice is kept.")
            end
            if state.editingContext and state.editingContext.loadoutSlot
                and Adapter.UpdateWishlistAssociationAfterSave then
                -- The open editor's binding goes with the save (see the writer).
                local context, assignmentId, key, installed = state.editingContext
                associated, associationReason, assignmentId, key, installed =
                    Adapter.UpdateWishlistAssociationAfterSave(
                        context.loadoutSlot, slot, name, recorded, designTargets,
                        context.boundActions and {actions=context.boundActions,
                            assignment=context.boundAssignment,
                            firstRun=context.boundFirstRun} or nil)
                if associated then
                    RebindAfterSave(assignmentId, key, installed)
                elseif associationReason == "assignment_changed" then
                    KeptNotice()
                end
            elseif state.createTargetContext and Adapter.SetLoadoutWishlistIdentity then
                local createdId, createdKey, installed
                associated, associationReason, createdId, createdKey, installed = Adapter.SetLoadoutWishlistIdentity(
                    state.createTargetContext.loadoutSlot, name, recorded, designTargets,
                    state.draftActions)
                if associated then
                    AdoptActions(state.draftActions, installed)
                    notify("|cff4dff80Nexus:|r assigned '" .. tostring(name)
                    .. "' to " .. tostring(state.createTargetContext.loadoutName
                        or "the active Saved Build") .. ".")
                elseif associationReason == "assignment_changed" then
                    KeptNotice()
                end
            else
                -- No loadout context. It is the first-run plan's save only
                -- by FirstRunOwnsSave; otherwise (another existing Wishlist,
                -- or a new plan while a Saved Build is active) it assigns
                -- nothing and never falls back to slot 1 or the first-run plan.
                local firstRun, unloaded = FirstRunOwnsSave()
                local context = state.editingContext
                -- An opened Wishlist saves to the first-run plan only when it
                -- was that plan when the editor bound it.
                if context and context.destination ~= "first" then firstRun = false end
                if firstRun and Adapter.SetFirstLoadoutWishlistIdentity then
                    local assignmentId, key, installed
                    local bound = state.draftActions
                    if context then bound = context.boundActions end
                    associated, associationReason, assignmentId, key, installed =
                        Adapter.SetFirstLoadoutWishlistIdentity(name, recorded, designTargets, bound)
                    if associated then
                        if context then RebindAfterSave(assignmentId, key, installed)
                        else AdoptActions(state.draftActions, installed) end
                        notify("|cff4dff80Nexus:|r '" .. tostring(name)
                            .. "' is the first-run Wishlist target (used until a Saved Build with Echoes is active).")
                    elseif associationReason == "assignment_changed" then
                        KeptNotice()
                    end
                else
                    notify("|cffffd200Nexus:|r '" .. tostring(name) .. "' saved. "
                        .. (unloaded and "Saved Build data is not loaded yet, so it is not assigned."
                            or "No Saved Build was open in the editor, so it is not assigned.")
                        .. " To assign it, use the Wishlist selector in My Builds.")
                end
            end
            if associated ~= true then
                state.applyRetry = nil
                if M._RecordSwitchRefusal then M._RecordSwitchRefusal("assign saved wishlist", "ASSIGNMENT_REFUSED", {
                    detail = tostring(associationReason or "unavailable"),
                    loadoutSlot = state.createTargetContext
                        and state.createTargetContext.loadoutSlot or nil,
                }) end
                notify("|cffff6060Nexus:|r Wishlist uploaded and targets saved, but assignment failed ("
                    .. tostring(associationReason or "unavailable") .. "). Select a valid loadout and assign it again.")
                return false, "association_incomplete"
            end
            state.applyRetry = nil
            state.candidateContext = nil
            state.candidateApplyToken = nil
            notify("|cff4dff80Nexus:|r Wishlist saved ("
                .. DraftModel.EchoListTotal(echoes) .. "/79 rolled copies; planned locked targets are separate).")
            return true
        end
        if tostring(err) == "spacing" then
            state.applyRetry = state.applyRetry or {
                slot=slot,name=name,echoes=echoes,tries=0,
                candidateSerial=guard and guard.candidateSerial,
                draftToken=draftToken,
                applyToken=guard and guard.applyToken
                    or ApplyPayloadToken(slot,name,echoes),
                editingContext=state.editingContext,
                createTargetContext=state.createTargetContext,
            }
            return false, "spacing"
        end
        notify("|cffff6060Nexus:|r couldn't apply: "
            .. (APPLY_FRIENDLY[tostring(err)] or tostring(err)))
        state.applyRetry = nil
        return false, err
    end

    -- One bounded record of a refused switch, assignment or save, through the
    -- incident owner this addon already has. Identity travels as a short hash
    -- of the exact content key, never the key, the name, the Echo list or the
    -- character: enough to tell two plans apart in a ticket, not enough to
    -- reconstruct either. A refusal is a business rule, not a Lua error.
    local function RecordSwitchRefusal(operation, reason, detail)
        local support = Nexus and Nexus.SupportIncidents
        if not (support and type(support.Record) == "function") then return end
        detail = type(detail) == "table" and detail or {}
        local context = state.editingContext or {}
        local slots = Adapter and Adapter.Slots and Adapter.Slots() or nil
        local function alias(value)
            if type(value) ~= "string" or value == "" then return nil end
            local sum = 0
            for index = 1, #value do
                sum = (sum * 31 + value:byte(index)) % 4294967296
            end
            return string.format("plan-%08x", sum)
        end
        pcall(support.Record, "wishlist-refusal", {
            reason = reason,
            producer = "Wishlist editor",
            origin = "local",
            operation = operation,
            build = Nexus.Release and Nexus.Release.buildLabel or nil,
            representation = "inline",
            committed = false,
            scope = "no Wishlist was uploaded, assigned or removed by this refusal",
            detail = detail.detail,
            readiness = {
                planAlias = alias(detail.key or context.key),
                sourceKind = detail.sourceKind or (context.assignmentId and "local" or "live"),
                targetLoadoutSlot = tonumber(detail.loadoutSlot or context.loadoutSlot),
                mirrorSlot = tonumber(detail.mirrorSlot or context.slot),
                configuredMaxLoadout = tonumber(slots and slots.maxSlots),
                matchingCandidates = tonumber(detail.matches),
            },
        })
    end
    M._RecordSwitchRefusal = RecordSwitchRefusal

    function M.PrepareApply(nameText)
        if not (Adapter and Adapter.UploadWishlist) then
            notify("|cffff6060Nexus:|r adapter not ready.")
            return nil, "adapter"
        end
        if state.editingContext and not tonumber(state.editingContext.slot) then
            notify("|cffff9040Nexus:|r This saved plan has no distinct current server mirror. It is kept exactly as it is; saving it would need a mirror to write to, and no other Wishlist will be overwritten.")
            RecordSwitchRefusal("save wishlist", "MIRROR_UNRESOLVED",
                {detail = "the saved plan has no distinct current server mirror"})
            return nil,"mirror_unresolved"
        end
        local current, staleReason = CandidateCurrent()
        if not current then
            notify("|cffff6060Nexus:|r Copy can no longer be saved: "
                .. BoundedReason(staleReason) .. ". Reopen the current record.")
            return nil, "stale_candidate"
        end
        local echoes = M.CanonicalEchoes()
        if #echoes == 0 then
            notify("|cffff6060Nexus:|r pending list is empty -- add something first.")
            return nil, "empty"
        end
        local slot = state.editingContext and tonumber(state.editingContext.slot) or 0
        local name
        if state.editingContext then
            -- An existing wishlist keeps the name the game holds for it. This
            -- path re-uploads that name, so normalising it here would rename
            -- somebody's server wishlist as a side effect of saving echoes.
            name = tostring(state.editingContext.name or "Wishlist")
        else
            local typed = tostring(nameText or "")
            name = DraftModel.TrimName(typed)
            if name == "" then
                notify("|cffff6060Nexus:|r Enter a wishlist name before saving.")
                return nil, "name"
            end
            -- Said only once the name is usable, and said as intent: this
            -- prepares the confirmation, it does not save anything yet.
            if name ~= typed:gsub("^%s+", ""):gsub("%s+$", "") then
                notify("|cffff6060Nexus:|r the | character is not kept in a "
                    .. "wishlist name; this plan will be named \"" .. name .. "\".")
            end
        end
        local data = {slot = slot, name = name, echoes = echoes}
        local confirmation = {adapter=Adapter,editingContext=state.editingContext,
            createTargetContext=state.createTargetContext,
            draftToken=CurrentDraftToken(),
            applyToken=ApplyPayloadToken(slot,name,echoes)}
        state.applyConfirmation = confirmation
        data.confirmation = confirmation
        if state.candidateContext then
            data.candidateSerial = state.candidateContext.serial
            data.sourceIdentity = state.candidateContext.sourceIdentity
            data.sourceRevision = state.candidateContext.sourceRevision
            data.evidenceToken = state.candidateContext.evidenceToken
            data.draftToken = CurrentDraftToken()
            data.applyToken = ApplyPayloadToken(slot, name, echoes)
            state.candidateApplyToken = data.applyToken
        end
        return data,
            state.editingContext and "update" or "create"
    end

    function M.AcceptApply(slot, name, echoes)
        local data
        if type(slot) == "table" then
            data = slot
            slot, name, echoes = data.slot, data.name, data.echoes
            local confirmation = data.confirmation
            -- PrepareApply always binds UI confirmations. Preserve the existing
            -- direct controller payload API for callers without a popup token.
            if confirmation and (confirmation ~= state.applyConfirmation
                or confirmation.adapter ~= Adapter
                or confirmation.editingContext ~= state.editingContext
                or confirmation.createTargetContext ~= state.createTargetContext
                or confirmation.draftToken ~= CurrentDraftToken()
                or confirmation.applyToken ~= ApplyPayloadToken(slot,name,echoes)) then
                notify("|cffff6060Nexus:|r Save cancelled: the editor changed. Review and save again.")
                return false, "stale_confirmation"
            end
        end
        if state.candidateContext then
            local context = state.candidateContext
            local current, reason = CandidateCurrent()
            if not data or tonumber(data.candidateSerial) ~= context.serial
                or data.sourceIdentity ~= context.sourceIdentity
                or data.sourceRevision ~= context.sourceRevision
                or data.evidenceToken ~= context.evidenceToken
                or data.draftToken ~= CurrentDraftToken()
                or data.applyToken ~= state.candidateApplyToken
                or data.applyToken ~= ApplyPayloadToken(slot, name, echoes)
                or not current then
                notify("|cffff6060Nexus:|r Copy save refused: "
                    .. BoundedReason(reason, "the preview is stale")
                    .. ". Reopen the current record.")
                return false, "stale_candidate"
            end
        end
        state.applyConfirmation = nil
        return TryApply(slot, name, echoes, data)
    end

    function M.PumpApplyRetry()
        local retry = state.applyRetry
        if not retry then return nil, "idle" end
        if retry.editingContext ~= state.editingContext
            or retry.createTargetContext ~= state.createTargetContext then
            state.applyRetry = nil
            return false, "stale_confirmation"
        end
        if retry.draftToken ~= CurrentDraftToken() then
            state.applyRetry = nil
            notify("|cffff6060Nexus:|r Save retry cancelled: the draft changed. Review and save again.")
            return false, "stale_confirmation"
        end
        retry.tries = retry.tries + 1
        if retry.tries > 12 then
            notify("|cffff6060Nexus:|r couldn't apply: " .. APPLY_FRIENDLY.spacing)
            state.applyRetry = nil
            return false, "expired"
        end
        if state.candidateContext then
            local current = CandidateCurrent()
            if not current
                or retry.candidateSerial ~= state.candidateContext.serial
                or retry.draftToken ~= CurrentDraftToken()
                or retry.applyToken ~= state.candidateApplyToken
                or retry.applyToken ~= ApplyPayloadToken(
                    retry.slot,retry.name,retry.echoes) then
                state.applyRetry = nil
                notify("|cffff6060Nexus:|r Copy retry refused because its preview is stale.")
                return false, "stale_candidate"
            end
        elseif retry.applyToken ~= ApplyPayloadToken(
            retry.slot,retry.name,retry.echoes) then
            state.applyRetry = nil
            notify("|cffff6060Nexus:|r retry refused because its payload changed.")
            return false, "stale_payload"
        end
        return TryApply(retry.slot, retry.name, retry.echoes, retry)
    end

    function M.IsApplyPending() return state.applyRetry ~= nil end

    function M.PendingApply()
        local retry = state.applyRetry
        if not retry then return nil end
        return {
            slot = retry.slot,
            name = retry.name,
            echoes = retry.echoes,
            tries = retry.tries,
        }
    end

    function M.DebugDraftState()
        local pendingCount, pendingLockCount, fulfilledCount = 0, 0, 0
        for _ in pairs(state.pending) do pendingCount = pendingCount + 1 end
        for _ in pairs(state.pendingLock) do pendingLockCount = pendingLockCount + 1 end
        for _ in pairs(state.fulfilledDraftTargets) do fulfilledCount = fulfilledCount + 1 end
        return {
            pending = pendingCount,
            pendingLock = pendingLockCount,
            fulfilled = fulfilledCount,
            scrollOffset = state.scrollOffset,
            pickOffset = state.pickOffset,
            pendingLoadoutOpen = CopyRecord(state.pendingLoadoutOpen),
            awaitingWishlist = CopyRecord(state.awaitingWishlist),
            candidateContext = M.CandidateContext(),
            applyBlockReason = M.ApplyBlockReason(),
        }
    end

    function M.OpenCommunity()
        if type(options.openCommunity) == "function" then
            return options.openCommunity()
        end
        return false
    end

    return M
end

Nexus.WishlistInternals.Controller = Controller
