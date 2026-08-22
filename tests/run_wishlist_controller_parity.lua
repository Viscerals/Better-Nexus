-- Frame-free Wishlist controller transition, association, and retry parity.
Nexus = {}
dofile("core/CandidateEvidence.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")

local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local root = {
    editorSearch = "alpha",
    editorClassOnly = false,
    futurePreference = {keep=true},
    lockDesignTargets = {[1999]=true},
}
local legacyTargets = root.lockDesignTargets
local character = {futureCharacter={keep=true}}
local Store = {State=function() return character end}
local model = assert(Nexus.WishlistModel.New)()
local notices, communityOpens, frameCalls = {}, 0, 0
CreateFrame = function()
    frameCalls = frameCalls + 1
    error("controller created a frame")
end

local catalog = {rows={
    [1001]={spellId=1001,name="Alpha",quality=1,groupId=1,maxStack=3},
    [1002]={spellId=1002,name="Beta",quality=2,groupId=2,maxStack=1},
    [1003]={spellId=1003,name="Gamma",quality=3,groupId=3,maxStack=2},
    [1999]={spellId=1999,name="Old Lock",quality=2,groupId=9,maxStack=1},
}}
local activeSlot = 1
local linked = {}
local uploadMode, uploadCalls = "success", {}
local createdAssociations, updatedAssociations, directAssociations = {}, {}, {}
local firstAssociations = {}
local lockedProjection = {bySpell={},synced=true}
local Adapter = {
    Catalog=function() return catalog end,
    LockedOwned=function() return lockedProjection end,
    WishlistKey=function(echoes) return "key:" .. tostring(#(echoes or {})) end,
    Wishlist=function() return {name="Seed",entries={{spellId=1001,quality=1,stacks=1}}} end,
    Slots=function()
        return {activeSlot=activeSlot,maxSlots=5,bySlot={
            [1]={slot=1,name="Primary",echoes={{spellId=1001}}},
            [2]={slot=2,name="Secondary",echoes={{spellId=1002}}},
        }}
    end,
    GetLoadoutWishlist=function(slot) return linked[slot] end,
    GetFirstRunWishlist=function() return nil end,
    UploadWishlist=function(slot, name, echoes)
        uploadCalls[#uploadCalls + 1] = {slot=slot,name=name,echoes=echoes}
        if uploadMode == "spacing" then return false, "spacing" end
        if uploadMode == "refused" then return false, "refused" end
        return true
    end,
    SetLoadoutWishlistIdentity=function(slot, name, echoes)
        createdAssociations[#createdAssociations + 1] = {slot=slot,name=name,echoes=echoes}
        return true
    end,
    SetFirstLoadoutWishlistIdentity=function(name, echoes)
        firstAssociations[#firstAssociations + 1] = {name=name,echoes=echoes}
        return true
    end,
    UpdateWishlistAssociationAfterSave=function(loadoutSlot, slot, name, echoes)
        updatedAssociations[#updatedAssociations + 1] = {
            loadoutSlot=loadoutSlot,slot=slot,name=name,echoes=echoes,
        }
        return true
    end,
    SetLoadoutWishlist=function(loadoutSlot, wishlistSlot)
        directAssociations[#directAssociations + 1] = {
            loadoutSlot=loadoutSlot,wishlistSlot=wishlistSlot,
        }
        return true
    end,
}

local Controller = assert(Nexus.WishlistInternals.Controller)
local controller = Controller.New({
    model=model,
    store=Store,
    accountRoot=function() return root end,
    notify=function(message) notices[#notices + 1] = message end,
    openCommunity=function() communityOpens = communityOpens + 1; return true end,
})
controller.Initialize(Adapter)

-- Partial lock reads are diagnostic only: they cannot reach the renderer as
-- authority or append an unseen locked row to the public export.
catalog.rows[1777] = {spellId=1777,name="Partial Lock",quality=2,
    groupId=17,maxStack=1}
lockedProjection = {bySpell={[1777]=6},synced=false}
Check(controller.LockedProjection() == nil,
    "controller exposed unsynced partial lock evidence to the renderer")
local partialExport = controller.ExportEntries()
local leakedPartial = false
for _, row in ipairs(partialExport) do
    if tonumber(row.spellId) == 1777 and row.locked then leakedPartial = true end
end
Check(not leakedPartial,
    "unsynced partial lock evidence leaked into public EBH1 export entries")
lockedProjection = {bySpell={},synced=true}

lockedProjection = {bySpell={[1001]=1,["1001"]=1},synced=true}
Check(controller.LockedProjection() == nil,
    "controller merged canonical aliases in locked evidence")
lockedProjection = {bySpell={},synced=true}

lockedProjection = {bySpell={[math.huge]=1},synced=true}
Check(controller.LockedProjection() == nil,
    "controller trusted a nonfinite locked spell identity")
local infiniteExport = controller.ExportEntries()
local leakedInfinite = false
for _, row in ipairs(infiniteExport) do
    if row.locked and row.spellId == math.huge then leakedInfinite = true end
end
Check(not leakedInfinite,
    "nonfinite locked spell identity leaked into public export entries")
lockedProjection = {bySpell={},synced=true}

-- Filters and large draft views stay controller-owned without replacing
-- future preferences or creating frames/actions.
local filter = controller.FilterState()
filter.search = "mutated snapshot"
controller.SetSearch("beta")
controller.SetClassOnly(true)
Check(root.editorSearch == "beta" and root.editorClassOnly == true
    and root.futurePreference.keep,
    "filter transition replaced or leaked future preferences")
controller.BeginCandidate({title="Candidate",echoes={
    {spellId=1001,quality=1,stacks=2},
    {spellId=1002,quality=2,stacks=1},
}})
Check(controller.DebugDraftState().pending == 2
    and character.lockDesignTargetsBySlot["key:2"] == legacyTargets
    and root.lockDesignTargets == nil and character.futureCharacter.keep,
    "candidate load lost draft or legacy lock-target identity")
local beforeInit = controller.PendingRows()
controller.Initialize(Adapter)
Check(controller.PendingRows() == beforeInit
    and controller.DebugDraftState().pending == 2,
    "repeated initialization replaced the active draft")
local optionalCatalogCalls = 0
controller.Initialize({Catalog=function()
    optionalCatalogCalls = optionalCatalogCalls + 1
    return catalog
end})
controller.ExportEntries()
Check(optionalCatalogCalls == 0,
    "export reached catalog after optional locked ownership was absent")
controller.Initialize(Adapter)

Check(controller.AddPending(catalog.rows[1003]) == "added"
    and controller.AdjustStacks(model.Family(1003, catalog), 1) == "adjusted",
    "add/stack controller transitions changed")
controller.ToggleEmptyAssignment()
Check(controller.IsAssigningLockSlot()
    and controller.AssignLockSlot(catalog.rows[1003]) == "tagged",
    "slot-assignment transition changed")
controller.EndAssignment()
controller.SetScrollOffset(9)
controller.SetPickOffset(4)
controller.BeginNewWishlist()
local reset = controller.DebugDraftState()
Check(reset.pending == 0 and reset.pendingLock == 0
    and reset.scrollOffset == 0 and reset.pickOffset == 0
    and controller.CreateTargetContext().loadoutSlot == 1,
    "new-draft reset or active association intention changed")

-- The first spacing payload remains the exact pending record. A second
-- explicit spacing attempt still reaches the adapter but does not supersede it.
controller.AddPending(catalog.rows[1001])
local payload, mode = controller.PrepareApply("  New Target  ")
Check(mode == "create" and payload.slot == 0 and payload.name == "New Target"
    and payload.echoes[1].spellId == 1001,
    "create preparation changed canonical payload or name")
uploadMode = "spacing"
Check(not controller.AcceptApply(payload.slot, payload.name, payload.echoes)
    and controller.IsApplyPending(),
    "initial spacing did not retain pending Wishlist work")
local firstPending = controller.PendingApply()
Check(firstPending.echoes == payload.echoes and firstPending.tries == 0,
    "spacing retry recreated or advanced the exact payload")
controller.Initialize(Adapter)
local secondEchoes = {{spellId=1002,quality=2,stacks=1}}
controller.AcceptApply(0, "Second", secondEchoes)
Check(#uploadCalls == 2 and controller.PendingApply().echoes == payload.echoes
    and controller.PendingApply().name == "New Target",
    "later explicit spacing unexpectedly superseded the first pending payload")
uploadMode = "success"
Check(controller.PumpApplyRetry() and not controller.IsApplyPending()
    and uploadCalls[3].echoes == payload.echoes
    and createdAssociations[1].slot == 1
    and createdAssociations[1].name == "New Target",
    "capacity recovery changed payload identity or create association")

-- Initial upload plus 12 retry uploads; the next pump expires without a
-- thirteenth retry upload and non-spacing failure never gains a lifetime.
uploadMode, uploadCalls = "spacing", {}
controller.AcceptApply(0, "Bounded", payload.echoes)
for retry = 1, 12 do
    controller.PumpApplyRetry()
    Check(controller.PendingApply().tries == retry,
        "retry attempt counter changed at " .. tostring(retry))
end
local beforeExpiry = #uploadCalls
local expired, reason = controller.PumpApplyRetry()
Check(not expired and reason == "expired" and beforeExpiry == 13
    and #uploadCalls == 13 and not controller.IsApplyPending(),
    "Wishlist retry expiry admitted an extra upload or retained work")
uploadMode = "refused"
controller.AcceptApply(0, "Refused", payload.echoes)
Check(not controller.IsApplyPending(),
    "non-spacing refusal acquired a retry lifetime")

-- Editing and direct candidate association re-read current authority at the
-- mutation boundary and preserve exact loadout/wishlist slots.
uploadMode = "success"
Check(controller.BeginWishlist({slot=7,name="Edited",key="seven",echoes={
    {spellId=1002,quality=2,stacks=1},
}}, 2), "valid editing session was rejected")
local editPayload, editMode = controller.PrepareApply("ignored")
controller.AcceptApply(editPayload.slot, editPayload.name, editPayload.echoes)
Check(editMode == "update" and editPayload.slot == 7
    and updatedAssociations[1].loadoutSlot == 2
    and updatedAssociations[1].slot == 7,
    "edit save changed exact association arguments")
activeSlot = 2
local candidate = {slot=7,key="seven"}
linked[2] = candidate
local assignedSlot, assignedName = controller.CandidateAssignment(candidate)
local associated, _, active = controller.AssociateCandidate(candidate)
Check(assignedSlot == 2 and assignedName == "Secondary"
    and associated and active == 2
    and directAssociations[1].loadoutSlot == 2
    and directAssociations[1].wishlistSlot == 7,
    "candidate association used stale or wrong slot identity")

local uploadsBeforeRead = #uploadCalls
local associationsBeforeRead = #directAssociations + #createdAssociations
controller.PendingRows()
controller.PendingLockRows()
controller.FulfilledDraftTargets()
controller.FilterState()
controller.DebugDraftState()
controller.ClampScroll(1000, 19)
controller.ClampPick(500, 18)
Check(#uploadCalls == uploadsBeforeRead
    and #directAssociations + #createdAssociations == associationsBeforeRead,
    "render/status reads submitted a gameplay or association action")
Check(controller.OpenCommunity() and communityOpens == 1,
    "injected Community intention was bypassed")
Check(frameCalls == 0, "controller constructed a frame")

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local value = handle:read("*a")
    handle:close()
    return value
end
local controllerSource = Read("core/WishlistController.lua")
for _, forbidden in ipairs({
    "CreateFrame", "SetScript", "StaticPopup_Show", "ProjectEbonhold",
}) do
    Check(not controllerSource:find(forbidden, 1, true),
        "WishlistController acquired rendering/direct-game authority: " .. forbidden)
end
local editorSource = Read("ui/WishlistEditor.lua")
for _, forbidden in ipairs({
    "Adapter.UploadWishlist", "Adapter.SetLoadoutWishlist(",
    "Adapter.SetLoadoutWishlistIdentity", "Adapter.UpdateWishlistAssociationAfterSave",
    "Nexus.Store.State", "local applyRetry", "local pending = {}",
    "DraftModel.ReconcileLocked", "DraftModel.PlanLockCommit",
}) do
    Check(not editorSource:find(forbidden, 1, true),
        "WishlistEditor retained controller mutation authority: " .. forbidden)
end
local toc = Read("Nexus.toc")
local modelAt = assert(toc:find("core\\WishlistModel.lua", 1, true))
local controllerAt = assert(toc:find("core\\WishlistController.lua", 1, true))
local editorAt = assert(toc:find("ui\\WishlistEditor.lua", 1, true))
Check(modelAt < controllerAt and controllerAt < editorAt,
    "Wishlist model/controller/editor TOC order changed")

print(string.format(
    "wishlist controller: checks=%d retries=%d frames=0 actions-on-read=0 -- OK",
    checks, beforeExpiry - 1))
