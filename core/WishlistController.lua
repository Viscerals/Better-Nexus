-- Nexus: core/WishlistController.lua
-- Frame-free Wishlist draft, session, association, and apply-retry owner.

Nexus = Nexus or {}
Nexus.WishlistInternals = Nexus.WishlistInternals or {}

local Controller = {}

function Controller.New(options)
    options = type(options) == "table" and options or {}
    local DraftModel = assert(options.model, "Wishlist controller requires WishlistModel")
    local Store = assert(options.store, "Wishlist controller requires Store")
    local notify = type(options.notify) == "function" and options.notify or print
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
            if locked and locked.synced == true
                and type(locked.bySpell) == "table" then
                local bySpell = {}
                for spellId, count in pairs(locked.bySpell) do
                    local id, copies = tonumber(spellId), tonumber(count)
                    if not id or id <= 0 or id >= math.huge
                        or id ~= math.floor(id)
                        or not copies or copies <= 0 or copies >= math.huge
                        or copies ~= math.floor(copies) then
                        return nil
                    end
                    if bySpell[id] ~= nil then return nil end
                    bySpell[id] = copies
                end
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

    local function LockDesignTargets()
        local account = AccountRoot()
        local character = Store.State()
        local old = account.lockDesignTargets
        character.lockDesignTargetsBySlot = character.lockDesignTargetsBySlot or {}
        if type(old) == "table" then
            local key = state.currentLockKey or 0
            if not character.lockDesignTargetsBySlot[key] then
                character.lockDesignTargetsBySlot[key] = old
            end
            account.lockDesignTargets = nil
        end
        local key = state.currentLockKey or 0
        character.lockDesignTargetsBySlot[key] =
            character.lockDesignTargetsBySlot[key] or {}
        return character.lockDesignTargetsBySlot[key]
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
                "|cffff6060Nexus:|r this wishlist has more than %d Echo copies, but Nexus can't "
                    .. "safely tell which %d were meant to be your locked picks -- this usually "
                    .. "happens after importing through the game's own Import feature instead of "
                    .. "Nexus's, which doesn't preserve pick order. They were left out rather than "
                    .. "risk locking the wrong ones. Delete this wishlist and use Nexus's own "
                    .. "Import button (Wishlist Editor) with the same string instead, or tag your "
                    .. "locked picks manually here.",
                MAX_WISHLIST_ECHOES, metrics.untrustedOverflowSkipped))
        end
        if metrics.swapPairs > 0 then
            notify(string.format(
                "|cff4dff80Nexus:|r this build wants %d locked Echo%s different from what you have "
                    .. "locked now -- shown gold in the Locked strip. Your current ones stay locked "
                    .. "and useful; lock the new ones in as soon as you get each one, replacing "
                    .. "whichever old one you're ready to let go.",
                metrics.swapPairs, metrics.swapPairs == 1 and "" or "es"))
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
                    .. "%d permanent slots can ever hold -- they were left out entirely, not just queued.",
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

    function M.SlotsProjection()
        return Adapter and Adapter.Slots and Adapter.Slots() or nil
    end

    function M.LoadoutWishlistProjection(slot)
        return Adapter and Adapter.GetLoadoutWishlist
            and Adapter.GetLoadoutWishlist(slot) or nil
    end

    function M.AutoLockEnabled()
        local settings = Preferences().settings
        return settings and settings.autoLockEchoes and true or false
    end

    function M.SetAutoLockEnabled(value)
        local preferences = Preferences()
        preferences.settings = preferences.settings or {}
        local wasEnabled = preferences.settings.autoLockEchoes and true or false
        local enabled = value and true or false
        preferences.settings.autoLockEchoes = enabled
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
        if state.scrollOffset >= count then
            local nextOffset = math.max(0, count - visible)
            if state.scrollOffset ~= nextOffset then
                state.scrollOffset = nextOffset
                TouchPresentation()
            end
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
        if state.pickOffset >= count then
            local nextOffset = math.max(0, count - visible)
            if state.pickOffset ~= nextOffset then
                state.pickOffset = nextOffset
                TouchPresentation()
            end
        end
        return state.pickOffset
    end

    function M.LoadPendingEchoes(echoes, trustOrder)
        if trustOrder == nil then trustOrder = true end
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

        local withCommitted = DraftModel.ApplyCommittedTargets(prepared,
            LockDesignTargets(), {catalog = catalog, lockedBySpell = lockedBySpell})
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
        if wishlist then M.LoadPendingEchoes(wishlist.entries or {}, false) end
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
            notify("|cff4dff80Nexus:|r click an Echo -- either list -- to design its "
                .. "replacement. Your current one stays locked until Nexus swaps it "
                .. "in automatically once you have the replacement.")
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

    function M.ResetNewWishlistDraft()
        state.editingContext = nil
        state.createTargetContext = nil
        state.awaitingWishlist = nil
        state.pending = {}
        state.pendingLock = {}
        state.fulfilledDraftTargets = {}
        state.scrollOffset = 0
        state.pickOffset = 0
        state.pendingLoadoutOpen = nil
        state.pendingSeeded = true
        state.currentLockKey = 0
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

    function M.BeginWishlist(wishlist, loadoutSlot)
        state.candidateContext = nil
        state.candidateApplyToken = nil
        state.applyRetry = nil
        state.createTargetContext = nil
        if type(wishlist) ~= "table" or not tonumber(wishlist.slot) then
            notify("|cffff6060Nexus:|r Associated wishlist data is unavailable.")
            return false
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
            loadoutSlot = tonumber(loadoutSlot),
            loadoutName = tostring(wishlist.loadoutName or ""),
        }
        M.LoadPendingEchoes(wishlist.echoes or {}, false)
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
        if linked and tonumber(linked.slot) then
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
        if active >= 1 and active <= 5 then
            local ok, mode = M.SelectLoadout(active)
            return ok, mode, mode == "new"
        end
        local firstRun = Adapter and Adapter.GetFirstRunWishlist
            and Adapter.GetFirstRunWishlist()
        if firstRun and tonumber(firstRun.slot) then
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
                if linked and ((candidate.key and linked.key == candidate.key)
                    or tonumber(linked.slot) == tonumber(candidate.slot)) then
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
            return ok, err or "first-run association unavailable", nil, true
        end
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
        return DraftModel.ExportEntries(state.pending, state.pendingLock,
            lockedBySpell, catalog, state.fulfilledDraftTargets)
    end

    function M.ExportName(nameText)
        if state.editingContext then return state.editingContext.name end
        if nameText ~= nil then return nameText end
        if Adapter and Adapter.Wishlist and Adapter.Wishlist() then
            return Adapter.Wishlist().name
        end
        return "Nexus"
    end

    local function CommitLockDesignTargets()
        local previousKey = state.currentLockKey or 0
        local existing = LockDesignTargets()
        local lockedBySpell = LockedBySpell()
        local fresh = DraftModel.PlanLockCommit(state.pending, state.pendingLock,
            state.fulfilledDraftTargets,
            state.candidateContext and {} or existing, lockedBySpell)
        local nextKey = (Adapter and Adapter.WishlistKey
            and Adapter.WishlistKey(M.CanonicalEchoes())) or 0
        local character = Store.State()
        character.lockDesignTargetsBySlot = character.lockDesignTargetsBySlot or {}
        character.lockDesignTargetsBySlot[nextKey] = fresh
        if previousKey ~= nextKey
            and character.lockDesignTargetsBySlot[previousKey] == existing then
            character.lockDesignTargetsBySlot[previousKey] = nil
        end
        state.currentLockKey = nextKey
        state.fulfilledDraftTargets = {}
        for id, value in pairs(fresh) do
            local copies = DraftModel.TargetCopies(value, id)
            if copies and (tonumber(lockedBySpell[id]) or 0) >= copies then
                state.fulfilledDraftTargets[id] = value
            end
        end
    end

    local function TryApply(slot, name, echoes, guard)
        local ok, err = Adapter.UploadWishlist(slot or 0, name, echoes)
        if ok then
            notify("|cff4dff80Nexus:|r wishlist saved ("
                .. DraftModel.EchoListTotal(echoes) .. " / 79 Echoes).")
            CommitLockDesignTargets()
            if state.editingContext and Adapter.UpdateWishlistAssociationAfterSave then
                Adapter.UpdateWishlistAssociationAfterSave(
                    state.editingContext.loadoutSlot, slot, name, echoes)
            elseif state.createTargetContext and Adapter.SetLoadoutWishlistIdentity then
                Adapter.SetLoadoutWishlistIdentity(
                    state.createTargetContext.loadoutSlot, name, echoes)
                notify("|cff4dff80Nexus:|r associated '" .. tostring(name)
                    .. "' with " .. tostring(state.createTargetContext.loadoutName
                        or "the active Saved Build") .. ".")
            elseif Adapter.SetFirstLoadoutWishlistIdentity then
                Adapter.SetFirstLoadoutWishlistIdentity(name, echoes)
            end
            state.applyRetry = nil
            state.candidateContext = nil
            state.candidateApplyToken = nil
            return true
        end
        if tostring(err) == "spacing" then
            state.applyRetry = state.applyRetry or {
                slot=slot,name=name,echoes=echoes,tries=0,
                candidateSerial=guard and guard.candidateSerial,
                draftToken=guard and guard.draftToken,
                applyToken=guard and guard.applyToken
                    or ApplyPayloadToken(slot,name,echoes),
            }
            return false, "spacing"
        end
        notify("|cffff6060Nexus:|r couldn't apply: "
            .. (APPLY_FRIENDLY[tostring(err)] or tostring(err)))
        state.applyRetry = nil
        return false, err
    end

    function M.PrepareApply(nameText)
        if not (Adapter and Adapter.UploadWishlist) then
            notify("|cffff6060Nexus:|r adapter not ready.")
            return nil, "adapter"
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
            name = tostring(state.editingContext.name or "Wishlist")
        else
            name = DraftModel.TrimName(nameText)
            if name == "" then
                notify("|cffff6060Nexus:|r Enter a wishlist name before saving.")
                return nil, "name"
            end
        end
        local data = {slot = slot, name = name, echoes = echoes}
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
        return TryApply(slot, name, echoes, data)
    end

    function M.PumpApplyRetry()
        local retry = state.applyRetry
        if not retry then return nil, "idle" end
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
