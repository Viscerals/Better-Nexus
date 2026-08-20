-- Stage 21.1 expected red: a default-visible Panel suppressed by Changelog
-- before its first render must appear after the popup closes.
local H = dofile("tests/harness.lua")

local function LoadPanel()
    dofile("ui/Panel.lua")
    NexusDB = {}
    Nexus.Panel.Init({ToggleAuto=function() return true end})
    return Nexus.Panel
end

local model = {status="ready",cards={},recommendation="",auto=true,version="v"}

local function ShowFrame(target)
    target:Show()
    local onShow = target:GetScript("OnShow")
    if onShow then onShow(target) end
end

local function HideFrame(target)
    target:Hide()
    local onHide = target:GetScript("OnHide")
    if onHide then onHide(target) end
end

-- Existing menu/explicit-hide controls remain green.
local Panel = LoadPanel()
Panel.Render(model)
local frame = assert(_G.NexusPanel)
assert(frame:IsShown(), "default first render did not show Panel")
for _, name in ipairs({
    "NexusCommunityBuildsFrame", "NexusLeaderboardFrame", "NexusLogViewer",
    "NexusEditorFrame", "NexusQuickStart", "NexusChangelogPopup",
}) do
    local menu = CreateFrame("Frame", name, UIParent)
    Panel.AttachMenuFrame(menu)
    Panel.CloseOtherWindows(name)
    ShowFrame(menu)
    assert(not frame:IsShown(), name .. " did not suppress visible Panel")
    HideFrame(menu)
    assert(frame:IsShown(), name .. " did not restore visible Panel")
end

Panel.Hide()
local hiddenMenu = CreateFrame("Frame", "NexusHiddenControlMenu", UIParent)
Panel.AttachMenuFrame(hiddenMenu)
Panel.CloseOtherWindows("NexusHiddenControlMenu")
ShowFrame(hiddenMenu)
HideFrame(hiddenMenu)
Panel.Render(model)
assert(not frame:IsShown(), "explicit user hide was lost across menu/render")

Panel.Show()
local first = _G.NexusCommunityBuildsFrame
local second = _G.NexusLeaderboardFrame
Panel.CloseOtherWindows("NexusCommunityBuildsFrame")
ShowFrame(first)
Panel.CloseOtherWindows("NexusLeaderboardFrame")
first:Hide()
ShowFrame(second)
assert(not frame:IsShown(), "menu transition briefly reopened Panel")
local firstHide = first:GetScript("OnHide")
if firstHide then firstHide(first) end
assert(not frame:IsShown(), "closing old menu reopened Panel over new menu")
HideFrame(second)
assert(frame:IsShown(), "final menu close did not restore Panel")

-- Fresh module locals reproduce the real startup order. Do not render first.
Panel = LoadPanel()
NexusDB.hasSeenQuickStart = true
dofile("ui/Changelog.lua")
Nexus.Changelog.ShowIfNeeded()
local popup = assert(_G.NexusChangelogPopup)
assert(popup:IsShown(), "Changelog did not open before first Panel render")
Panel.Render(model)
frame = assert(_G.NexusPanel)
assert(not frame:IsShown(), "Panel ignored active startup-menu suppression")
HideFrame(popup)

assert(frame:IsShown(),
    "Stage 21.1 expected red: default-visible Panel stayed hidden after Changelog closed before first render")

-- Explicit intent must also exist before materialization; closing the startup
-- popup may restore the default, but never override an early explicit hide.
Panel = LoadPanel()
Panel.Hide()
NexusDB.hasSeenQuickStart = true
dofile("ui/Changelog.lua")
Nexus.Changelog.ShowIfNeeded()
popup = assert(_G.NexusChangelogPopup)
Panel.Render(model)
frame = assert(_G.NexusPanel)
HideFrame(popup)
assert(not frame:IsShown(),
    "startup menu close overrode explicit pre-render Panel hide intent")
print("Stage 21 startup Panel restoration characterization -- OK")
