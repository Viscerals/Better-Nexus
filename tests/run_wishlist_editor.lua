local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")

NexusDB = {}
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
    { spellId = 200104, quality = 2, stacks = 3 },
} }
H.playerLevel = 5
IsSpellKnown = function(id) return id == 300100 end

local Adapter, Model = Nexus.GameAdapter, Nexus.Model
Adapter.Wishlist = function()
    return { name=H.wishlist.name, class=H.wishlist.class, entries=H.wishlist.echoes }
end
local EW = Nexus.WishlistEditor
EW.Init(Adapter, Model)

local realCreateFrame = CreateFrame
local checkFrames = {}
CreateFrame = function(kind, name, parent, template)
    local made = realCreateFrame(kind, name, parent, template)
    if template == "UICheckButtonTemplate" then
        checkFrames[#checkFrames + 1] = made
    end
    return made
end
local recomputeRequests = 0
local retryRequests, retryAccepted = 0, false
Nexus.RequestRecompute = function()
    recomputeRequests = recomputeRequests + 1
    return true
end
Nexus.RetryAutoLock = function()
    retryRequests = retryRequests + 1
    return retryAccepted
end

local ok = pcall(EW.OpenForCandidate, {title=H.wishlist.name, echoes=H.wishlist.echoes})
assert(ok, "Show() threw")
local frame = _G.NexusEditorFrame
assert(frame:IsShown(), "editor frame not shown after Show()")

-- The auto-lock setting changes Main's mutation plan. Its checkbox is the
-- first checkbutton created by the editor and must request one next-tick
-- recomputation instead of waiting for the slow fallback.
local autoLockCheck = checkFrames[1]
assert(autoLockCheck and autoLockCheck.scripts.OnClick,
    "auto-lock checkbox was not created")
autoLockCheck:SetChecked(true)
autoLockCheck.scripts.OnClick(autoLockCheck)
assert(NexusDB.settings.autoLockEchoes == true and recomputeRequests == 1
        and retryRequests == 1,
    "auto-lock setting did not request immediate safe recomputation")
autoLockCheck:SetChecked(false)
autoLockCheck.scripts.OnClick(autoLockCheck)
retryAccepted = true
autoLockCheck:SetChecked(true)
autoLockCheck.scripts.OnClick(autoLockCheck)
assert(NexusDB.settings.autoLockEchoes == true and recomputeRequests == 2
        and retryRequests == 2,
    "checkbox re-enable did not route an accepted terminal retry exactly once")

-- pending list should be seeded from the real wishlist: 2 entries
assert(EW.DebugPendingCount() == 2,
    "expected pending seeded with 2 entries, got " .. EW.DebugPendingCount())

-- toggle hides/shows correctly
EW.Toggle()
assert(not frame:IsShown(), "Toggle() did not hide")
EW.Toggle()
assert(frame:IsShown(), "Toggle() did not re-show")

-- refresh never throws across repeated calls (search/filter changes etc.)
for i = 1, 5 do
    local ok2 = pcall(EW.Refresh)
    assert(ok2, "Refresh() threw on iteration " .. i)
end

-- Regression: opening Wishlists with an active Saved Build that has no
-- association used to initialize the new-wishlist draft without showing the
-- editor. The Panel had already suppressed its HUD, leaving both windows
-- invisible and causing the HUD to flash closed on every subsequent render.
-- Seed a prior unsaved draft with a queued lock design and a fulfilled lock
-- target. Neither may carry into the new active-loadout draft.
local staleEchoes = {}
for i = 1, 80 do
    staleEchoes[i] = { spellId = 310000 + i, quality = 3, stacks = 1 }
end
staleEchoes[80].locked = true
local seededOk = pcall(EW.OpenForCandidate,
    { title="Stale draft", echoes=staleEchoes })
assert(seededOk, "failed to seed the prior unsaved lock-design draft")
local staleDraft = EW.DebugDraftState()
assert(staleDraft.pendingLock == 1,
    "test setup did not create a queued stale lock design")
EW._fulfilledDraftTargets[399999] = true
frame:Hide()
Adapter.Slots = function()
    return {
        activeSlot = 2,
        maxSlots = 5,
        bySlot = {
            [2] = { slot = 2, name = "best2", echoes = {
                { spellId = 200100, quality = 3, stacks = 1 },
            } },
        },
    }
end
Adapter.GetLoadoutWishlist = function() return nil end
local ok3 = pcall(EW.Show)
assert(ok3, "Show() threw for an unassociated active loadout")
assert(frame:IsShown(), "editor stayed hidden for an unassociated active loadout")
local freshDraft = EW.DebugDraftState()
assert(freshDraft.pending == 0 and freshDraft.pendingLock == 0
    and freshDraft.fulfilled == 0,
    "unassociated active loadout inherited stale draft or lock state")
assert(freshDraft.scrollOffset == 0 and freshDraft.pickOffset == 0
    and freshDraft.pendingLoadoutOpen == nil,
    "unassociated active loadout did not reset complete editor draft state")

-- A rejected associated Wishlist must leave the server journal and editor UI
-- untouched. In particular, no renderer preparation may run before the
-- controller accepts the transition.
local serverJournal = CreateFrame("Frame", "ProjectEbonholdEchoJournal", UIParent)
serverJournal:Show()
frame:Hide()
local hideCalls, attachCalls, styleCalls, closeCalls = 0, 0, 0, 0
HideUIPanel = function(target)
    hideCalls = hideCalls + 1
    target:Hide()
end
Nexus.Panel = {
    AttachMenuFrame = function() attachCalls = attachCalls + 1 end,
    CloseOtherWindows = function() closeCalls = closeCalls + 1 end,
}
Nexus.Theme = {
    StyleWindow = function() styleCalls = styleCalls + 1 end,
    StyleTree = function() end,
}
local oversized = {}
for i = 1, 80 do
    oversized[i] = { spellId = 320000 + i, quality = 3, stacks = 1 }
end
Adapter.GetLoadoutWishlist = function()
    return {slot=1, name="Rejected", key="rejected", echoes=oversized}
end
local accepted, rejectedMode = EW.Show()
assert(serverJournal:IsShown() and hideCalls == 0,
    "rejected Show hid the server Echo UI")
assert(not frame:IsShown(), "rejected Show displayed the Wishlist Editor")
assert(attachCalls == 0 and styleCalls == 0 and closeCalls == 0,
    "rejected Show prepared or suppressed UI before controller acceptance")
assert(accepted == false and rejectedMode == "wishlist",
    "rejected Show did not return the controller result")

print("wishlist editor: lifecycle + fail-closed Show OK (checks=17)")
