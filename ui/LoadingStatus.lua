-- Nexus: read-only, non-modal startup status. No SavedVariables, work pumping,
-- readiness writes, or timer-based claims of completion live in this module.
Nexus = Nexus or {}
local M = {}
Nexus.LoadingStatus = M
local frame, lastSnapshot, startedAt, completedAt
local lastUpdate, dismissed = -math.huge, false
local buttons = setmetatable({}, {__mode="k"})
local phases = {
    ["store-validation"]="Reading your saved data",
    scan="Reading Community builds",
    legacy="Reading older saved Community records",
    identities="Preparing shared build information",
    commit="Updating the build library",
    ["source-changed"]="Refreshing changed Community data",
    community="Preparing Community data",
    complete="Community data ready",
}
local function Now()
    local value=type(GetTime)=="function" and GetTime() or 0
    return type(value)=="number" and value==value and value>=0 and value<math.huge and value or 0
end
local function Safe(value)
    local text=tostring(value or "")
    local identity=Nexus.Identity
    if identity and identity.DisplaySafeText then
        return identity.DisplaySafeText(text,320,true) or "Unavailable"
    end
    return text:gsub("|","||"):gsub("[%c]"," "):sub(1,320)
end
local function Snapshot()
    if type(Nexus.StartupStatus)=="function" then return Nexus.StartupStatus() end
    return {state="pending",coreReady=false,phase="store-validation"}
end
function M.PhaseText(status)
    status=status or Snapshot()
    if status.state=="failed" then
        return (status.coreReady and "Shared data unavailable: " or "Startup stopped: ") .. Safe(status.reason)
    end
    if status.state=="ready" then return "Community builds and Leaderboard ready" end
    return phases[status.phase] or "Preparing Community data"
end
function M.Progress(status)
    local done,total=tonumber(status.progressDone),tonumber(status.progressTotal)
    if status.state=="ready" then return 100,"Ready" end
    if status.state=="failed" then return nil,"See /nexus status for the recorded reason" end
    if done and total and total>0 and total<math.huge and done>=0 and done<=total
        and done==math.floor(done) and total==math.floor(total) then
        local percent=math.floor(done*100/total)
        return percent,string.format("This step: %d / %d (%d%%)",done,total,percent)
    end
    if status.coreReady==false and tonumber(status.coreSlices) then
        return nil,"Checking saved data; total progress is not yet measurable"
    end
    local scanned=tonumber(status.recordsSeen)
    if status.phase=="scan" and scanned and scanned>=0 and scanned<math.huge then
        return nil,string.format("%d records inspected; total work not yet known",scanned)
    end
    return nil,"Working... total progress is not yet measurable"
end
function M.Detail(status)
    local _,progress=M.Progress(status)
    if status.state=="failed" then
        return status.coreReady and "Local Wishlist tools and Echo controls remain available.\nShared views are unavailable; see status for the reason."
            or "Local controls wait until saved data is checked.\nSee /nexus status for details. Keep your saved-data backup."
    end
    return (status.coreReady and "Wishlist tools are ready; shared builds are still loading.\n" or "Wishlist tools unlock after your saved data is checked.\n")
        .. M.PhaseText(status) .. ".\n" .. progress .. "\nProgress is for this step, not total startup."
end
local function PaintButtons(status)
    for button,label in pairs(buttons) do
        local text=label
        if status.state~="ready" then text="|cff888888"..label.."|r" end
        button._nexusDataLoading=status.state~="ready"
        if button._nexusLoadingText~=text then
            button:SetText(text);button._nexusLoadingText=text
        end
    end
end
function M.BindSharedButton(button,label)
    if not button then return end
    buttons[button]=label
    if button.HookScript and not button._nexusLoadingTip then
        button._nexusLoadingTip=true
        button:HookScript("OnEnter",function(self)
            local status=Snapshot()
            if status.state~="ready" and GameTooltip then
                GameTooltip:SetOwner(self,"ANCHOR_TOP")
                GameTooltip:AddLine(label .. " - " .. (status.state=="failed" and "unavailable" or "Loading"),.65,.65,.68)
                GameTooltip:AddLine(M.PhaseText(status),.9,.9,.9,true)
                GameTooltip:AddLine(status.coreReady and "Local Wishlist and Echo tools remain available." or "Local tools unlock after saved-data validation.",.8,.8,.8,true)
                GameTooltip:Show()
            end
        end)
        button:HookScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    end
    -- The button may open the guarded placeholder, never a premature query.
    PaintButtons(lastSnapshot or Snapshot())
end
local function EnsureFrame()
    if frame then return frame end
    local f=CreateFrame("Frame","NexusLoadingStatusFrame",UIParent)
    frame=f
    f:SetSize(430,118);f:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",-24,180)
    f:SetFrameStrata("HIGH");f:SetFrameLevel(80);f:SetClampedToScreen(true)
    f:EnableMouse(false) -- no full-screen shield; other controls remain usable
    f:SetMovable(true)
    local drag=CreateFrame("Frame",nil,f)
    drag:SetFrameStrata("HIGH");drag:SetFrameLevel(81)
    drag:SetPoint("TOPLEFT",4,-4);drag:SetSize(390,22);drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function() f:StartMoving() end)
    drag:SetScript("OnDragStop",function() f:StopMovingOrSizing() end)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=false,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    f:SetBackdropColor(0.025,0.03,0.045,0.96)
    f.title=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f.title:SetPoint("TOPLEFT",12,-10);f.title:SetWidth(375);f.title:SetJustifyH("LEFT")
    f.detail=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.detail:SetPoint("TOPLEFT",12,-31);f.detail:SetSize(402,30);f.detail:SetJustifyH("LEFT")
    f.bar=CreateFrame("StatusBar",nil,f)
    f.bar:SetPoint("TOPLEFT",12,-64);f.bar:SetSize(402,10)
    f.bar:SetFrameStrata("HIGH");f.bar:SetFrameLevel(81)
    f.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f.bar:SetStatusBarColor(.3,.65,.9,1);f.bar:SetMinMaxValues(0,100)
    local bg=f.bar:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints(f.bar)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8");bg:SetVertexColor(.10,.12,.15,1)
    f.progress=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.progress:SetPoint("TOPLEFT",12,-78);f.progress:SetSize(300,28);f.progress:SetJustifyH("LEFT")
    f.localButton=CreateFrame("Button","NexusLoadingOpenWishlist",f,"UIPanelButtonTemplate")
    f.localButton:SetFrameStrata("HIGH");f.localButton:SetFrameLevel(82)
    f.localButton:SetPoint("BOTTOMRIGHT",-12,8);f.localButton:SetSize(96,23);f.localButton:SetText("Wishlists")
    f.localButton:SetScript("OnClick",function()
        local status=Snapshot()
        if status.coreReady and Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end
    end)
    local close=CreateFrame("Button","NexusLoadingDismiss",f,"UIPanelCloseButton")
    close:SetFrameStrata("HIGH");close:SetFrameLevel(82);close:SetPoint("TOPRIGHT",-1,-1)
    close:SetScript("OnClick",function() dismissed=true;f:Hide() end)
    f:Hide()
    return f
end
function M.Update(status,force)
    local now=Now()
    if not force and now>=lastUpdate and now-lastUpdate<.25 then return end
    lastUpdate=now
    status=status or Snapshot()
    lastSnapshot=status
    startedAt=startedAt or now
    PaintButtons(status)
    -- No status frame is allocated for a fully ready standalone consumer.
    if not frame and status.state=="ready" and not force then return end
    local f=EnsureFrame()
    local percent,progress=M.Progress(status)
    f.title:SetText(status.state=="ready" and "Nexus ready"
        or status.state=="failed" and "Nexus loading stopped" or "Nexus loading")
    local localText=status.coreReady and "Wishlist tools ready; shared builds may still be loading" or "Reading your local Wishlist and Echo data"
    f.detail:SetText(localText.."\n"..M.PhaseText(status))
    local elapsed=math.max(0,math.floor(now-startedAt))
    f.progress:SetText(progress .. (status.state=="ready" and "" or string.format("\nElapsed %d:%02d",math.floor(elapsed/60),elapsed%60)))
    f.bar:SetValue(percent or 0) -- unknown is not an invented percentage
    if status.coreReady then f.localButton:Enable() else f.localButton:Disable() end
    if status.state=="ready" then
        completedAt=completedAt or now
        if not force and now-completedAt>=3 then f:Hide();return end
    else completedAt=nil end
    if not dismissed then f:Show() end
end
function M.Show()
    dismissed=false
    local status=Snapshot()
    if status.state=="ready" then completedAt=Now() end
    M.Update(status,true)
end
