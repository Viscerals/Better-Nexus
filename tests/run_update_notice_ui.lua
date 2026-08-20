local H = dofile("tests/harness.lua")
dofile("ui/Panel.lua")

local Updates, Panel = Nexus.Updates, Nexus.Panel
Nexus.Release = {
    version="1.19.4-dev", baseVersion="1.19.4", published=false,
    releasesUrl="https://github.com/Viscerals/Better-Nexus/releases",
}
NexusDB = {
    settings={updateNotifications=true,autoPick=false,customPreference="keep"},
    updateNotice={version="1.20.0",observedAt=123,source="Peer"},
}
local notices, menuItems = 0, nil
EasyMenu = function(items) menuItems = items end
CloseDropDownMenus = function() end
Panel.Init({ToggleAuto=function() return true end})
local model = {status="ready",progress={},cards={},recommendation="",auto=true}
local function RefreshDisplay()
    model.updateNotice = Updates.GetVisibleNotice()
    Panel.Render(model)
end
Updates.Init({
    notify=function() notices=notices+1 end,
    refresh=RefreshDisplay,
})
Panel.Render(model)

local frame = _G.NexusPanel
assert(frame and frame._menuBtn and frame._menuBtn.text == "!",
    "persistent update marker was not visible on the settings surface")
frame._menuBtn:GetScript("OnClick")(frame._menuBtn)
assert(menuItems and menuItems[1].text == "Update available: v1.20.0"
    and menuItems[2].text == "Disable Update Notices",
    "settings menu did not expose update/candidate controls")
menuItems[1].func()
assert(H.lastStaticPopup and H.lastStaticPopup.which == "NEXUS_UPDATE_RELEASES"
    and H.lastStaticPopup.arg1 == "1.20.0"
    and H.lastStaticPopup.arg2 == Nexus.Release.releasesUrl,
    "update action did not open the manual releases-page surface")

local popup = StaticPopupDialogs.NEXUS_UPDATE_RELEASES
local copied, highlighted, focused
popup.OnShow({editBox={
    SetText=function(_,value) copied=value end,
    HighlightText=function() highlighted=true end,
    SetFocus=function() focused=true end,
}})
assert(popup.hasEditBox and copied == Nexus.Release.releasesUrl
    and highlighted and focused,
    "release URL was not presented as selected copyable text")

menuItems[2].func()
assert(NexusDB.settings.updateNotifications == false
    and NexusDB.settings.autoPick == false
    and NexusDB.settings.customPreference == "keep"
    and NexusDB.updateNotice.version == "1.20.0",
    "opt-out reset unrelated preferences or erased the candidate")
assert(frame._menuBtn.text == "..." and Updates.GetVisibleNotice() == nil,
    "opt-out did not hide the persistent notice")

frame._menuBtn:GetScript("OnClick")(frame._menuBtn)
assert(menuItems[2].text == "Enable Update Notices", "opt-in control did not persist")
menuItems[2].func()
assert(frame._menuBtn.text == "!" and Updates.GetVisibleNotice().version == "1.20.0",
    "re-enabled retained notice did not return")
assert(notices == 1, "UI toggles produced duplicate chat notifications")

-- Simulated reload keeps the candidate and prints no more than once in the new session.
dofile("core/Updates.lua")
Updates = Nexus.Updates
Updates.Init({notify=function() notices=notices+1 end,refresh=RefreshDisplay})
assert(Updates.GetVisibleNotice().version == "1.20.0" and frame._menuBtn.text == "!"
    and notices == 2,
    "persistent notice did not survive reload semantics")

print("persistent opt-out update notice and copyable release URL -- OK")
