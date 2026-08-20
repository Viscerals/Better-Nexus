-- Freeze WishlistEditor draft, association, import, frame, and retry behavior
-- across its model/controller/renderer boundaries.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Codec.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")

UnitName = function() return "Editor" end
H.playerLevel = 80
local designed = {
    {spellId=200100, quality=3, stacks=1},
    {spellId=200104, quality=2, stacks=2},
}
UISpecialFrames = {}
NexusDB = {
    settingsVersion=2, settings={}, chars={Editor={futureSafety={keep=true}}},
    communityBuilds={}, editorSearch="alpha", editorClassOnly=false,
    futureRoot={keep=true},
}
local Store, Adapter = Nexus.Store, Nexus.GameAdapter
Store.Init()
Adapter.Init({}, Store)
H.DeliverSlots({
    [1]={slot=1, name="Active Saved Build", verified=true,
        echoes={{spellId=200102, quality=2, stacks=1}}},
    [6]={slot=6, name="Designed Wishlist", verified=false, echoes=designed},
}, 1)
assert(Adapter.SetLoadoutWishlist(1, 6), "association fixture failed")

Nexus.Panel = {
    AttachMenuFrame=function() end,
    CloseOtherWindows=function() end,
}
Nexus.Theme = {StyleWindow=function() end, StyleTree=function() end}
local overlayShown, overlayLocked, overlayScale = false, false, 1
Nexus.WishlistOverlay = {
    IsShown=function() return overlayShown end,
    Show=function() overlayShown = true end,
    Hide=function() overlayShown = false end,
    IsLocked=function() return overlayLocked end,
    ToggleLock=function() overlayLocked = not overlayLocked end,
    GetScale=function() return overlayScale end,
    SetScale=function(value) overlayScale = value end,
    ResetPosition=function() end,
}

local EW = Nexus.WishlistEditor
EW.Init(Adapter, Nexus.Model)
for _, name in ipairs({
    "_PumpApplyRetry", "IsApplyPending", "ImportEBH1String", "Refresh",
    "ToggleDisplayPopup", "Init", "DebugPendingCount", "DebugDraftState",
    "OpenForCandidate", "OpenForWishlist", "NewWishlist", "Show", "Toggle",
}) do
    assert(type(EW[name]) == "function", "Wishlist facade lost " .. name)
end

local sourceHandle = assert(io.open("ui/WishlistEditor.lua", "rb"))
local source = sourceHandle:read("*a")
sourceHandle:close()
local rendererHandle = assert(io.open("ui/WishlistRenderer.lua", "rb"))
source = source .. rendererHandle:read("*a")
rendererHandle:close()
for _, name in ipairs({
    "NexusWishlistEditorSwitchMenu", "NexusWishlistEditorLoadoutMenu",
    "NexusEditorFrame", "NexusWishlistNameInput", "NexusEditorSearch",
    "NexusDisplayPopup", "NexusScaleSlider",
}) do
    assert(source:find('"' .. name .. '"', 1, true),
        "Wishlist named frame literal lost: " .. name)
end

-- Show resolves the exact active-loadout association and retains frame names,
-- selection counts, and hidden/shown lifecycle behavior.
EW.Show()
assert(H.frames.NexusEditorFrame and H.frames.NexusEditorFrame:IsShown()
    and EW.DebugPendingCount() == 2,
    "associated Wishlist did not open in NexusEditorFrame")
assert(UISpecialFrames[1] == "NexusEditorFrame",
    "Wishlist escape-close frame registration changed")
local associatedState = EW.DebugDraftState()
assert(associatedState.pending == 2 and associatedState.pendingLoadoutOpen == nil,
    "associated wishlist draft shape changed")
EW.Toggle()
assert(not H.frames.NexusEditorFrame:IsShown(), "editor Toggle did not hide")
EW.Toggle()
assert(H.frames.NexusEditorFrame:IsShown(), "editor Toggle did not restore")
EW.ToggleDisplayPopup(H.frames.NexusEditorFrame)
assert(H.frames.NexusDisplayPopup and H.frames.NexusDisplayPopup:IsShown(),
    "display controller did not preserve NexusDisplayPopup")
for _, name in ipairs({
    "NexusEditorFrame", "NexusWishlistNameInput", "NexusEditorSearch",
    "NexusDisplayPopup", "NexusScaleSlider",
}) do
    assert(H.frames[name], "Wishlist eager named frame lost: " .. name)
end
EW.ToggleDisplayPopup(H.frames.NexusEditorFrame)
assert(not H.frames.NexusDisplayPopup:IsShown(),
    "display popup toggle did not hide the established frame")

-- Invalid controller inputs fail without replacing the currently represented
-- draft; candidates and new drafts reset complete local selection state.
local beforeInvalid = EW.DebugDraftState()
assert(EW.OpenForWishlist({name="missing slot"}) == false,
    "invalid associated wishlist was accepted")
local afterInvalid = EW.DebugDraftState()
assert(afterInvalid.pending == beforeInvalid.pending
    and afterInvalid.pendingLock == beforeInvalid.pendingLock,
    "invalid associated wishlist replaced the active draft")
EW.OpenForCandidate({title="Candidate", echoes={{spellId=200102, quality=2, stacks=1}}})
assert(EW.DebugPendingCount() == 1 and H.frames.NexusWishlistNameInput:GetText() == "Candidate",
    "candidate controller did not bind exact content/name")
EW.NewWishlist()
local blank = EW.DebugDraftState()
assert(blank.pending == 0 and blank.pendingLock == 0 and blank.fulfilled == 0
    and blank.scrollOffset == 0 and blank.pickOffset == 0,
    "new-wishlist controller retained stale draft state")

-- Malformed import is a no-op. A valid EBH1 import is always a fresh draft,
-- preserves exact Echo/lock intent, resets offsets, and uses the chosen name.
EW.OpenForCandidate({title="Stale", echoes={{spellId=200102, quality=2, stacks=1}}})
local stale = EW.DebugDraftState()
EW.ImportEBH1String("not-ebh1", "Ignored")
assert(EW.DebugDraftState().pending == stale.pending,
    "malformed EBH1 import discarded the existing draft")
local encoded = Nexus.Codec.EncodeEBH1({
    {spellId=200100, quality=3, stacks=1},
    {spellId=200104, quality=2, stacks=2, locked=true},
}, "MAGE", "Encoded Name")
EW.ImportEBH1String(encoded, "  Imported Contract  ")
local imported = EW.DebugDraftState()
assert(imported.pending == 1 and imported.pendingLock == 1
    and imported.scrollOffset == 0
    and imported.pickOffset == 0
    and H.frames.NexusWishlistNameInput:GetText() == "Imported Contract",
    "valid EBH1 import lost exact content, reset state, or chosen name")

-- Create/update confirmation remains the only apply path. Spacing retains the
-- immutable request, successful retry associates it to the active Saved Build,
-- and unproductive retries expire after the established 12 attempts.
local uploadCalls, alwaysSpacing, associated = 0, false, nil
Adapter.UploadWishlist = function(slot, name, echoes)
    uploadCalls = uploadCalls + 1
    assert(slot == 0 and name == "Imported Contract" and #echoes == 2,
        "apply retry changed imported payload identity")
    if alwaysSpacing or uploadCalls == 1 then return false, "spacing" end
    return true
end
Adapter.SetLoadoutWishlistIdentity = function(loadoutSlot, name, echoes)
    associated = {loadoutSlot=loadoutSlot, name=name, count=#echoes}
    return true
end
local payload = {
    slot=0, name="Imported Contract",
    echoes={{spellId=200100, quality=3, stacks=1},
        {spellId=200104, quality=2, stacks=2, locked=true}},
}
StaticPopupDialogs.WISHLISTREALIZER_CREATE_WISHLIST.OnAccept(nil, payload)
assert(EW.IsApplyPending(), "spacing did not retain pending wishlist apply")
EW._PumpApplyRetry()
assert(not EW.IsApplyPending() and uploadCalls == 2 and associated
    and associated.loadoutSlot == 1 and associated.name == payload.name,
    "wishlist retry did not resume once or preserve active association")

alwaysSpacing, uploadCalls = true, 0
StaticPopupDialogs.WISHLISTREALIZER_CREATE_WISHLIST.OnAccept(nil, payload)
for _ = 1, 13 do EW._PumpApplyRetry() end
assert(not EW.IsApplyPending() and uploadCalls == 13,
    "unproductive wishlist retry did not expire predictably")

local uploadsBeforeRefresh, associationBeforeRefresh = uploadCalls, associated
EW.Refresh()
assert(uploadCalls == uploadsBeforeRefresh and associated == associationBeforeRefresh,
    "Wishlist Refresh submitted an upload or association action")

local snapshot = EW.DebugDraftState()
snapshot.pending = -1
local defensive = EW.DebugDraftState()
assert(defensive.pending == 1 and defensive.pendingLock == 1
    and NexusDB.editorSearch == "alpha" and NexusDB.editorClassOnly == false
    and NexusDB.futureRoot.keep and Store.State().futureSafety.keep,
    "Wishlist diagnostics/rendering leaked or replaced persistent state")

print("Wishlist facade, frames, drafts, exact import, association, and bounded retry -- OK")
