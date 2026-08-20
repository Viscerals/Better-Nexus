-- Final Wishlist facade parity: one model/controller/renderer chain owns all
-- presentation behind the established public editor facade. The display popup
-- remains lazy, stable, and action-free across reuse and cosmetic failure.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Codec.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")

NexusDB = {
    settingsVersion=2, settings={}, chars={}, dpsCapture={},
    editorClassOnly=false, futureRoot={keep=true},
}
UISpecialFrames = {}
Nexus.Store.Init()

local mutations = {upload=0, association=0}
local Adapter = Nexus.GameAdapter
Adapter.Catalog = function()
    return {rows={
        [810001]={spellId=810001, groupId=810001, name="Facade Echo",
            quality=2, maxStack=1, classMask=1},
    }, playerMask=1}
end
Adapter.Owned = function() return {bySpell={}} end
Adapter.LockedOwned = function() return {bySpell={}} end
Adapter.Wishlist = function() return nil end
Adapter.GetWishlistCandidates = function() return {} end
Adapter.Slots = function() return {activeSlot=0, maxSlots=5, bySlot={}} end
Adapter.GetLoadoutWishlist = function() return nil end
Adapter.UploadWishlist = function()
    mutations.upload = mutations.upload + 1
    return false, "spacing"
end
Adapter.SetLoadoutWishlist = function()
    mutations.association = mutations.association + 1
    return true
end

local overlay = {shown=false, locked=false, scale=1, resets=0}
local overlayFacade = {
    IsShown=function() return overlay.shown end,
    Show=function() overlay.shown = true end,
    Hide=function() overlay.shown = false end,
    IsLocked=function() return overlay.locked end,
    ToggleLock=function() overlay.locked = not overlay.locked end,
    GetScale=function() return overlay.scale end,
    SetScale=function(value) overlay.scale = value end,
    ResetPosition=function()
        overlay.resets = overlay.resets + 1
        overlay.shown = true
    end,
}
Nexus.WishlistOverlay = overlayFacade
Nexus.Panel = {
    AttachMenuFrame=function() end,
    CloseOtherWindows=function() end,
}
Nexus.Theme = {StyleWindow=function() end, StyleTree=function() end}

local created = {}
local realCreateFrame = CreateFrame
CreateFrame = function(kind, name, parent, template)
    local frame = realCreateFrame(kind, name, parent, template)
    frame._kind, frame._name = kind, name
    frame._parent, frame._template = parent, template
    created[#created + 1] = frame
    return frame
end

local modelNews, controllerNews, rendererNews = 0, 0, 0
local realModelNew = Nexus.WishlistModel.New
Nexus.WishlistModel.New = function(...)
    modelNews = modelNews + 1
    return realModelNew(...)
end
local realControllerNew = Nexus.WishlistInternals.Controller.New
Nexus.WishlistInternals.Controller.New = function(...)
    controllerNews = controllerNews + 1
    return realControllerNew(...)
end
local realRendererNew = Nexus.WishlistInternals.Renderer.New
Nexus.WishlistInternals.Renderer.New = function(...)
    rendererNews = rendererNews + 1
    return realRendererNew(...)
end

dofile("ui/WishlistEditor.lua")
local Editor = Nexus.WishlistEditor
Editor.Init(Adapter, Nexus.Model)
Editor.Init(Adapter, Nexus.Model)
assert(modelNews == 1 and controllerNews == 1 and rendererNews == 1,
    string.format("Wishlist assembly duplicated owners: model=%d controller=%d renderer=%d",
        modelNews, controllerNews, rendererNews))

Editor.NewWishlist()
local main = assert(H.frames.NexusEditorFrame, "Wishlist main frame missing")
assert(main:IsShown() and UISpecialFrames[1] == "NexusEditorFrame"
    and UISpecialFrames[2] == nil,
    "Wishlist main-frame identity or escape-close registration changed")

local function FindButton(text, parent)
    for _, frame in ipairs(created) do
        if frame._kind == "Button" and frame._parent == parent
            and frame.text == text then
            return frame
        end
    end
end

local displayButton = assert(FindButton("Display Settings", main),
    "renderer lost the display-settings entry point")
displayButton.IsVisible = function() return true end
Nexus.WishlistOverlay = nil
assert(pcall(displayButton:GetScript("OnClick"), displayButton),
    "display popup could not open while optional overlay facade was unavailable")
local popup = assert(H.frames.NexusDisplayPopup, "display popup identity changed")
assert(popup:IsShown() and popup:GetFrameStrata() == "TOOLTIP"
    and popup:GetFrameLevel() == 100,
    "display popup visibility or z-order changed")
local point, relative, relativePoint, x, y = popup:GetPoint(1)
assert(point == "TOPRIGHT" and relative == displayButton
    and relativePoint == "BOTTOMRIGHT" and x == 0 and y == -6,
    "display popup did not retain its visible-anchor placement")

local onShow = assert(popup:GetScript("OnShow"), "display popup lost OnShow refresh")
assert(pcall(onShow, popup),
    "display popup refresh failed while optional overlay facade was unavailable")
Nexus.WishlistOverlay = overlayFacade
onShow(popup)
local check
for _, frame in ipairs(created) do
    if frame._kind == "CheckButton" and frame._parent == popup then
        check = frame
        break
    end
end
check = assert(check, "display popup lost overlay visibility control")
assert(check:GetChecked() == false, "display popup did not read overlay visibility")
check:SetChecked(true)
check:GetScript("OnClick")(check)
assert(overlay.shown, "display popup did not show the overlay through its facade")
check:SetChecked(false)
check:GetScript("OnClick")(check)
assert(not overlay.shown, "display popup did not hide the overlay through its facade")

local lock = assert(FindButton("Lock Position", popup),
    "display popup lost lock-position control")
lock:GetScript("OnClick")(lock)
assert(overlay.locked and lock.text == "Unlock to Move",
    "display popup lock state did not refresh")
local reset = assert(FindButton("Reset Position", popup),
    "display popup lost reset-position control")
reset:GetScript("OnClick")(reset)
assert(overlay.resets == 1 and overlay.shown and check:GetChecked(),
    "display popup reset did not restore visible overlay state")

local slider = assert(H.frames.NexusScaleSlider, "display scale identity changed")
assert(slider.sliderMin == 0.5 and slider.sliderMax == 1.6
    and slider.sliderStep == 0.02 and slider:GetValue() == 1,
    "display scale bounds or initial value changed")
slider:GetScript("OnValueChanged")(slider, 1.2)
assert(math.abs(overlay.scale - 1.2) < 0.0001,
    "display scale slider did not route through overlay facade")
local minus = assert(FindButton("-", popup), "display scale minus control missing")
local plus = assert(FindButton("+", popup), "display scale plus control missing")
minus:GetScript("OnClick")(minus)
plus:GetScript("OnClick")(plus)
assert(math.abs(overlay.scale - 1.2) < 0.0001,
    "display scale step controls changed their net result")

local dragBar
for _, frame in ipairs(created) do
    if frame._kind == "Frame" and frame._parent == popup and frame.h == 30 then
        dragBar = frame
        break
    end
end
dragBar = assert(dragBar, "display popup lost title-only drag bar")
local started, stopped = 0, 0
popup.StartMoving = function() started = started + 1 end
popup.StopMovingOrSizing = function() stopped = stopped + 1 end
dragBar:GetScript("OnDragStart")(dragBar)
dragBar:GetScript("OnDragStop")(dragBar)
assert(started == 1 and stopped == 1, "display popup drag lifecycle changed")

local createdBeforeReuse = #created
Editor.ToggleDisplayPopup(displayButton)
Editor.ToggleDisplayPopup(displayButton)
assert(#created == createdBeforeReuse,
    "display popup reuse allocated another frame or control")
main:GetScript("OnHide")()
assert(not popup:IsShown(), "closing the editor left display popup visible")

StaticPopupDialogs.WISHLISTREALIZER_CREATE_WISHLIST.OnAccept(nil, {
    slot=0, name="Pending Facade", echoes={{spellId=810001, quality=2, stacks=1}},
})
assert(Editor.IsApplyPending() and mutations.upload == 1,
    "retry fixture did not retain the established pending payload")
local beforeFailure = Editor.DebugDraftState()
Nexus.Theme.StyleTree = function() error("cosmetic failure") end
local ok = pcall(Editor.Refresh)
assert(not ok and Editor.IsApplyPending() and mutations.upload == 1
    and mutations.association == 0,
    "render failure mutated or retried Wishlist action state")
local afterFailure = Editor.DebugDraftState()
assert(afterFailure.pending == beforeFailure.pending
    and afterFailure.pendingLock == beforeFailure.pendingLock,
    "render failure damaged controller draft state")
Nexus.Theme.StyleTree = function() end
Editor.Refresh()
assert(NexusDB.futureRoot.keep, "Wishlist facade damaged unknown SavedVariables")

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local value = handle:read("*a")
    handle:close()
    return value
end

local facadeSource = Read("ui/WishlistEditor.lua")
for _, moved in ipairs({
    "NexusDisplayPopup", "NexusScaleSlider", "EnsureDisplayPopup",
    "RefreshDisplayControls", "displayPopup", "CreateFrame",
}) do
    assert(not facadeSource:find(moved, 1, true),
        "Wishlist facade retained display rendering/owner path: " .. moved)
end
assert(select(2, facadeSource:gsub("WishlistModelFactory.New%(", "")) == 1
    and select(2, facadeSource:gsub("WishlistControllerFactory.New%(", "")) == 1
    and select(2, facadeSource:gsub("WishlistRendererFactory.New%(", "")) == 1,
    "Wishlist facade source no longer assembles exactly one owner chain")

local rendererSource = Read("ui/WishlistRenderer.lua")
assert(rendererSource:find('"NexusDisplayPopup"', 1, true)
    and rendererSource:find('"NexusScaleSlider"', 1, true),
    "Wishlist renderer does not own the named display presentation")
for _, forbidden in ipairs({
    "NexusDB", "UploadWishlist", "SetLoadoutWishlist",
    "UpdateWishlistAssociation", "ProjectEbonhold",
    "Nexus.Store", "Nexus.Sync", "BroadcastBuild",
}) do
    assert(not rendererSource:find(forbidden, 1, true),
        "Wishlist renderer gained forbidden product authority: " .. forbidden)
end

print("Wishlist facade/display popup single-owner parity and failure isolation -- OK")
