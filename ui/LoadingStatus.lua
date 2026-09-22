-- Nexus: read-only, non-modal startup status. No SavedVariables, work pumping,
-- readiness writes, or timer-based claims of completion live in this module.
Nexus = Nexus or {}
local M = {}
Nexus.LoadingStatus = M
local frame, lastSnapshot, startedAt, completedAt
local lastUpdate, dismissed = -math.huge, false
local buttons = setmetatable({}, {__mode="k"})
-- One plain description per step reported by StartupStatus. Any step not
-- listed falls back to a general description, never to a percentage.
local phases = {
    ["store-validation"]="Reading your saved data",
    ["store-characters"]="Checking saved character data",
    ["store-finish"]="Finishing saved-data checks",
    ["local-setup"]="Starting local Wishlist and Echo tools",
    catalog="Preparing the build library",
    ["catalog-collect"]="Collecting build library records",
    ["catalog-sort"]="Sorting build library records",
    ["catalog-rows"]="Checking build library records",
    ["catalog-finalize-scan"]="Verifying checked build library records",
    ["catalog-finalize-prune"]="Removing redundant build library copies",
    ["catalog-index"]="Indexing build library records",
    ["catalog-bundle"]="Preparing the build library save",
    ["catalog-witness-capture"]="Verifying build library data",
    ["catalog-witness-verify"]="Verifying build library data",
    ["catalog-mutation-bundle"]="Preparing a build library update",
    ["catalog-mutation"]="Preparing a build library update",
    ["catalog-maintenance-prepare"]="Preparing a build library update",
    ["catalog-put-prepare"]="Preparing a build library update",
    ["catalog-mutation-session-writes"]="Applying a build library update",
    ["catalog-mutation-session-tombstones"]="Applying a build library update",
    ["catalog-mutation-session-barriers"]="Applying a build library update",
    ["catalog-published"]="Finishing a build library update",
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
-- Saved-capacity refusals of the shared catalog, stated plainly. The data is
-- complete and unchanged; only the shared catalog cannot be opened.
local capacity = {
    ROOT_SLOT_LIMIT="Community data unavailable: your saved Community list holds more builds than this build opens (limit 2048). Nothing was changed or deleted.",
    TOMBSTONE_SET_LIMIT="Community data unavailable: the saved removal markers exceed the limit (2048). Nothing was changed or deleted.",
    BARRIER_SET_LIMIT="Community data unavailable: the saved retention markers exceed the limit (2048). Nothing was changed or deleted.",
}
function M.PhaseText(status)
    status=status or Snapshot()
    if status.state=="failed" then
        if status.coreReady and capacity[status.reason] then return capacity[status.reason] end
        return (status.coreReady and "Shared data unavailable: " or "Startup stopped: ") .. Safe(status.reason)
    end
    if status.state=="ready" then return "Community builds and Leaderboard ready" end
    local step=status.step or status.phase
    if phases[step] then return phases[step] end
    -- An unlisted catalog step is still catalog work, not Community reading.
    if type(step)=="string" and step:sub(1,8)=="catalog-" then return phases.catalog end
    return phases[status.phase] or "Preparing Community data"
end
-- A percentage exists only for the current step, from that step's own
-- completed/total pair in the same snapshot. Every other step is shown as
-- in progress with no bar, so a previous step's value cannot remain.
function M.Progress(status)
    local done,total=tonumber(status.stepDone),tonumber(status.stepTotal)
    if status.state=="ready" then return 100,"Ready" end
    if status.state=="failed" then return nil,"See /nexus status for the recorded reason" end
    local step=M.PhaseText(status)
    if done and total and total>0 and total<math.huge and done>=0 and done<=total
        and done==math.floor(done) and total==math.floor(total) then
        local percent=math.floor(done*100/total)
        return percent,string.format("Current step: %s; %d / %d (%d%%)",step,done,total,percent)
    end
    local scanned=tonumber(status.recordsSeen)
    if (status.step or status.phase)=="scan" and scanned and scanned>0 and scanned<math.huge
        and scanned==math.floor(scanned) then
        return nil,string.format("Current step: %s; %d records read (in progress)",step,scanned)
    end
    return nil,"Current step: "..step.." (in progress)"
end
-- Local availability only; the step line is shown once, next to its bar.
function M.Detail(status)
    if status.state=="failed" then
        return status.coreReady and "Local Wishlist tools and Echo controls remain available.\nShared views are unavailable; see status for the reason."
            or "Local controls wait until saved data is checked.\nSee /nexus status for details. Keep your saved-data backup."
    end
    return status.coreReady and "Wishlist tools are ready; shared builds are still loading."
        or "Wishlist tools unlock after your saved data is checked."
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
    f:SetSize(430,130);f:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",-24,180)
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
    f.detail:SetPoint("TOPLEFT",12,-31);f.detail:SetSize(402,42);f.detail:SetJustifyH("LEFT")
    f.bar=CreateFrame("StatusBar",nil,f)
    f.bar:SetPoint("TOPLEFT",12,-76);f.bar:SetSize(402,10)
    f.bar:SetFrameStrata("HIGH");f.bar:SetFrameLevel(81)
    f.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f.bar:SetStatusBarColor(.3,.65,.9,1);f.bar:SetMinMaxValues(0,100)
    local bg=f.bar:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints(f.bar)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8");bg:SetVertexColor(.10,.12,.15,1)
    f.progress=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.progress:SetPoint("TOPLEFT",12,-92);f.progress:SetSize(300,28);f.progress:SetJustifyH("LEFT")
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
    -- The full-width line carries the step; elapsed time never sets a percent.
    f.detail:SetText(localText.."\n"..progress)
    local elapsed=math.max(0,math.floor(now-startedAt))
    f.progress:SetText(status.state=="ready" and "" or string.format("Elapsed %d:%02d",math.floor(elapsed/60),elapsed%60))
    -- Unknown size: no bar at all, rather than an empty one that looks stuck.
    if percent then f.bar:SetValue(percent);f.bar:Show() else f.bar:Hide() end
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
