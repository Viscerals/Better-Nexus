-- Stage 30.4 regression: Wishlist lock evidence is classified without
-- coercing unknown booleans so a matching pending identity can be refreshed
-- safely when the authoritative server mirror arrives.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")

NexusDB = {
    settingsVersion=2,settings={},chars={},communityBuilds={},buildFilters={},
    dpsCapture={},
}
Nexus.Store.Init()
local Adapter = Nexus.GameAdapter
Adapter.Init({}, Nexus.Store)

local function Rows(ordinary, locked, explicit)
    local rows = {}
    for index = 1, ordinary do
        local row = {spellId=790000+index,quality=index%4,stacks=1}
        if explicit then row.locked = false end
        rows[#rows + 1] = row
    end
    for index = 1, locked do
        local row = {
            spellId=790000+ordinary+index,quality=3,stacks=1,
        }
        if explicit then row.locked = true end
        rows[#rows + 1] = row
    end
    return rows
end

local failures = {}
local function Expect(name, condition, detail)
    if not condition then failures[#failures + 1] = name .. ": " .. detail end
end

local classify = Adapter.WishlistEvidenceState
Expect("bounded_wishlist_evidence_states", type(classify) == "function",
    "GameAdapter.WishlistEvidenceState is unavailable")

if type(classify) == "function" then
    local ordinary = Rows(41, 0, false)
    local pending = Rows(79, 6, false)
    local authoritative = Rows(79, 6, true)
    local pendingKey = assert(Adapter.WishlistKey(pending))
    local authoritativeKey = assert(Adapter.WishlistKey(authoritative))
    local malformed = {
        [1]={spellId=799901,stacks=1},
        [3]={spellId=799903,stacks=1},
    }

    local missingState = classify(nil)
    local ordinaryState = classify({
        key=Adapter.WishlistKey(ordinary),echoes=ordinary,
    })
    local pendingState = classify({
        key=pendingKey,echoes=pending,lockEvidenceStatus="unavailable",
    })
    local authoritativeState = classify({
        key=authoritativeKey,echoes=authoritative,lockEvidenceVersion=1,
    })
    local mismatchState = classify({
        key=authoritativeKey,echoes=authoritative,lockEvidenceVersion=1,
    }, "different:1")
    local malformedState = classify({echoes=malformed})
    local numericKeyState = classify({key=123,echoes=ordinary})
    local malformedLockState = classify({
        echoes={{spellId=799904,stacks=1,locked="false"}},
    })
    local incompleteMarkedState = classify({
        key=pendingKey,echoes=pending,lockEvidenceVersion=1,
    })

    Expect("bounded_wishlist_evidence_states",
        missingState == "identity-unavailable"
            and ordinaryState == "actionable"
            and pendingState == "evidence-pending"
            and authoritativeState == "actionable"
            and mismatchState == "association-mismatch"
            and malformedState == "invalid-schema"
            and numericKeyState == "invalid-schema"
            and malformedLockState == "invalid-schema"
            and incompleteMarkedState == "invalid-schema",
        table.concat({
            tostring(missingState),tostring(ordinaryState),
            tostring(pendingState),tostring(authoritativeState),
            tostring(mismatchState),tostring(malformedState),
            tostring(numericKeyState),tostring(malformedLockState),
            tostring(incompleteMarkedState),
        }, ","))
    Expect("unknown_lock_booleans_remain_unknown",
        ordinary[1].locked == nil and pending[1].locked == nil
            and pending[80].locked == nil,
        "classification rewrote an unknown lock boolean")

    local revision, currentState, currentCandidate = 10,
        "evidence-pending", {
            slot=106,name="Awaited Wishlist",key=pendingKey,
            echoes=pending,lockEvidenceStatus="unavailable",
        }
    local actionCalls = 0
    local fakeAdapter = {
        Slots=function()
            return {activeSlot=1,maxSlots=5,bySlot={
                [1]={slot=1,name="Saved Build",verified=true,
                    echoes={{spellId=790001,stacks=1}}},
            }}
        end,
        GetLoadoutWishlist=function() return nil end,
        GetLoadoutWishlistState=function()
            return currentCandidate, currentState, pendingKey
        end,
        PresentationRevisions=function()
            return 0,0,0,0,revision
        end,
        WishlistKey=Adapter.WishlistKey,
        Catalog=function() return {rows={}} end,
        LockedOwned=function() return {bySpell={}} end,
        UploadWishlist=function() actionCalls = actionCalls + 1 end,
        SetLoadoutWishlistIdentity=function() actionCalls = actionCalls + 1 end,
        LockPerk=function() actionCalls = actionCalls + 1 end,
    }
    local function NewController()
        local controller = Nexus.WishlistInternals.Controller.New({
            model=Nexus.WishlistModel.New(),store=Nexus.Store,
            accountRoot=function() return NexusDB end,
            notify=function() end,
        })
        controller.Initialize(fakeAdapter)
        return controller
    end

    local controller = NewController()
    local began, mode = controller.BeginShow()
    local awaitingBefore = controller.DebugDraftState().awaitingWishlist
    currentState, currentCandidate = "actionable", {
        slot=106,name="Awaited Wishlist",key=authoritativeKey,
        echoes=authoritative,lockEvidenceVersion=1,
    }
    revision = revision + 1
    local promoted, promotedName = controller.RefreshWishlistEvidence("")
    local revisionReadsOnly = not controller.RefreshWishlistEvidence("")
    Expect("untouched_open_editor_promotes_once",
        began and mode == "new" and awaitingBefore
            and promoted and promotedName == "Awaited Wishlist"
            and controller.EditingContext()
            and controller.EditingContext().key == authoritativeKey
            and revisionReadsOnly,
        "an untouched pending controller did not promote exactly once")

    currentState, currentCandidate = "evidence-pending", {
        slot=106,name="Awaited Wishlist",key=pendingKey,
        echoes=pending,lockEvidenceStatus="unavailable",
    }
    revision = revision + 1
    local edited = NewController()
    edited.BeginShow()
    edited.AddPending({spellId=790001,quality=1,stacks=1})
    currentState, currentCandidate = "actionable", {
        slot=106,name="Awaited Wishlist",key=authoritativeKey,
        echoes=authoritative,lockEvidenceVersion=1,
    }
    revision = revision + 1
    local editedPromoted = edited.RefreshWishlistEvidence("")
    Expect("started_draft_is_never_replaced",
        not editedPromoted and edited.EditingContext() == nil
            and edited.PendingTotal() == 1
            and edited.DebugDraftState().awaitingWishlist == nil,
        "authoritative evidence replaced an in-progress new Wishlist draft")

    currentState, currentCandidate = "evidence-pending", {
        slot=106,name="Awaited Wishlist",key=pendingKey,
        echoes=pending,lockEvidenceStatus="unavailable",
    }
    revision = revision + 1
    local invalidated = NewController()
    invalidated.BeginShow()
    currentState, currentCandidate = "invalid-schema", nil
    revision = revision + 1
    local invalidPromoted = invalidated.RefreshWishlistEvidence("")
    Expect("invalid_transition_clears_stale_waiter",
        not invalidPromoted
            and invalidated.DebugDraftState().awaitingWishlist == nil,
        "invalid evidence left a stale automatic-promotion waiter")
    Expect("auto_refresh_is_read_only", actionCalls == 0,
        "controller refresh submitted a gameplay or association action")
end

if #failures > 0 then
    error("Stage 30.4 Wishlist auto-refresh regression ("
        .. #failures .. "):\n - " .. table.concat(failures, "\n - "))
end

print("Wishlist evidence auto-refresh characterization -- OK")
