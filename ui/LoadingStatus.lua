-- Nexus: read-only, non-modal startup status. No SavedVariables, work pumping,
-- readiness writes, or timer-based claims of completion live in this module.
Nexus = Nexus or {}
local M = {}
Nexus.LoadingStatus = M
local frame, lastSnapshot, startedAt, completedAt
local lastUpdate, dismissed = -math.huge, false
local buttons = setmetatable({}, {__mode="k"})
-- Full UI localization (issues #143-#148): every sentence below comes from
-- Nexus.Localization, looked up when it is shown. Numbers, times, reasons
-- and the labels callers supply are formatted here and inserted verbatim;
-- line breaks stay in code. The English bytes are unchanged.
local function T(key) return (Nexus.Localization.Text(key)) end
local function TF(key, args) return (Nexus.Localization.Format(key, args)) end
-- One plain description per step reported by StartupStatus. Any step not
-- listed falls back to a general description, never to a percentage. Each
-- step code maps to the semantic key of its description; the step codes
-- stay the lookup keys and are never shown.
local phases = {
    ["store-validation"]="loading.status.reading_saved_data",
    ["store-characters"]="loading.status.checking_character_data",
    ["store-finish"]="loading.status.finishing_saved_data_checks",
    ["local-setup"]="loading.status.starting_local_tools",
    catalog="loading.status.preparing_build_library",
    ["catalog-collect"]="loading.status.collecting_library_records",
    ["catalog-sort"]="loading.status.sorting_library_records",
    ["catalog-rows"]="loading.status.checking_library_records",
    ["catalog-finalize-scan"]="loading.status.verifying_checked_records",
    ["catalog-finalize-prune"]="loading.status.removing_redundant_copies",
    ["catalog-index"]="loading.status.indexing_library_records",
    ["catalog-bundle"]="loading.status.preparing_library_save",
    ["catalog-witness-capture"]="loading.status.verifying_library_data",
    ["catalog-mutation-capture"]="loading.status.verifying_library_data",
    ["catalog-witness-verify"]="loading.status.verifying_library_data",
    ["catalog-mutation-bundle"]="loading.status.preparing_library_update",
    ["catalog-mutation"]="loading.status.preparing_library_update",
    ["catalog-maintenance-prepare"]="loading.status.preparing_library_update",
    ["catalog-put-prepare"]="loading.status.preparing_library_update",
    ["catalog-mutation-session-writes"]="loading.status.applying_library_update",
    ["catalog-mutation-session-tombstones"]="loading.status.applying_library_update",
    ["catalog-mutation-session-barriers"]="loading.status.applying_library_update",
    ["catalog-published"]="loading.status.finishing_library_update",
    scan="loading.status.reading_community_builds",
    legacy="loading.status.reading_older_community_records",
    identities="loading.status.preparing_shared_build_info",
    commit="loading.status.updating_build_library",
    ["source-changed"]="loading.status.refreshing_changed_community",
    community="loading.status.preparing_community_data",
    complete="loading.status.community_data_ready",
}
local function Now()
    local value=type(GetTime)=="function" and GetTime() or 0
    return type(value)=="number" and value==value and value>=0 and value<math.huge and value or 0
end
local function Safe(value)
    local text=tostring(value or "")
    local identity=Nexus.Identity
    if identity and identity.DisplaySafeText then
        return identity.DisplaySafeText(text,320,true) or T("loading.value.reason_unavailable")
    end
    return text:gsub("|","||"):gsub("[%c]"," "):sub(1,320)
end
local function Snapshot()
    if type(Nexus.StartupStatus)=="function" then return Nexus.StartupStatus() end
    return {state="pending",coreReady=false,phase="store-validation"}
end
-- Saved-capacity refusals of the shared catalog, stated plainly. The data is
-- complete and unchanged; only the shared catalog cannot be opened.
-- The catalog opens up to 2048 different builds (saved and shipped together),
-- 2048 removal markers and 2048 retention markers. The sentence follows the
-- counter, the map and the limit the catalog recorded, and names only what
-- took part: a map alone above its limit ("map-keys"), different builds
-- ("distinct-builds"), all different entries ("distinct-slots"), or all raw
-- keys ("root-map-edges"). The maps are read in a fixed order (builds,
-- shipped builds, removal markers, retention markers), so nothing after the
-- map where counting stopped is named.
-- body is the translated clause. A limit is inserted as code-formatted text.
local function Refused(body)
    return TF("loading.status.community_unavailable_refused",{reason=body})
end
local function Clause(key, limitText)
    if limitText == nil then return T(key) end
    return TF(key,{limit=limitText})
end
local single = {
    TOMBSTONE_SET_LIMIT="loading.status.removal_markers_over_limit",
    BARRIER_SET_LIMIT="loading.status.retention_markers_over_limit",
}
-- The one sentence for a saved-capacity refusal, or nil for every other
-- state. Callers ask for it directly instead of matching message text.
function M.CapacityText(status)
    status=status or Snapshot()
    if not (status.state=="failed" and status.coreReady) then return nil end
    local reason=status.reason
    if reason~="ROOT_SLOT_LIMIT" and reason~="TOMBSTONE_SET_LIMIT"
        and reason~="BARRIER_SET_LIMIT" and reason~="ROOT_MAP_LIMIT" then return nil end
    local facts=type(status.failure)=="table" and status.failure or {}
    local counter,map=facts.counter,facts.map
    local limit=math.floor(tonumber(facts.limit) or 0)
    local counted=type(facts.counted)=="table" and facts.counted or {}
    local shipped=(tonumber(counted.bundled) or 0)>0
    if reason=="ROOT_MAP_LIMIT" or counter=="root-map-edges" then
        return Refused(Clause("loading.status.records_markers_over_total"))
    end
    if limit<=0 then
        return Refused(Clause("loading.status.saved_community_data_too_large"))
    end
    -- The limit exactly as the English showed it: concatenated, or %d for
    -- the two marker sets.
    local limitText=tostring(limit)
    if counter=="map-keys" then
        if reason=="ROOT_SLOT_LIMIT" then
            return Refused(map=="bundled"
                and Clause("loading.status.shipped_builds_over_limit",limitText)
                or Clause("loading.status.saved_list_over_build_limit",limitText))
        end
        return Refused(Clause(single[reason],string.format("%d",limit)))
    end
    if counter=="distinct-builds" then
        return Refused(Clause(shipped
            and "loading.status.saved_and_shipped_over_distinct_builds"
            or "loading.status.saved_list_over_distinct_builds",limitText))
    end
    if counter=="distinct-slots" then
        -- One whole clause for each combination of the counted maps.
        local key
        if map=="barrier" then
            key=shipped and "loading.status.saved_shipped_markers_over_entries"
                or "loading.status.saved_markers_over_entries"
        elseif map=="tombstone" then
            key=shipped and "loading.status.saved_shipped_removals_over_entries"
                or "loading.status.saved_removals_over_entries"
        else
            key=shipped and "loading.status.saved_and_shipped_over_entries"
                or "loading.status.saved_builds_over_entries"
        end
        return Refused(Clause(key,limitText))
    end
    return Refused(Clause("loading.status.saved_community_data_too_large"))
end
function M.PhaseText(status)
    status=status or Snapshot()
    if status.state=="failed" then
        local text=M.CapacityText(status)
        if text then return text end
        return TF(status.coreReady and "loading.status.shared_data_unavailable_reason"
            or "loading.status.startup_stopped_reason",{reason=Safe(status.reason)})
    end
    if status.state=="ready" then return T("loading.status.community_leaderboard_ready") end
    local step=status.step or status.phase
    if phases[step] then return T(phases[step]) end
    -- An unlisted catalog step is still catalog work, not Community reading.
    if type(step)=="string" and step:sub(1,8)=="catalog-" then return T(phases.catalog) end
    return T(phases[status.phase] or phases.community)
end
-- A percentage exists only for the current step, from that step's own
-- completed/total pair in the same snapshot. Every other step is shown as
-- in progress with no bar, so a previous step's value cannot remain.
function M.Progress(status)
    local done,total=tonumber(status.stepDone),tonumber(status.stepTotal)
    if status.state=="ready" then return 100,T("loading.status.ready") end
    if status.state=="failed" then
        return nil,TF("loading.status.see_status_for_reason",{command="/nexus status"})
    end
    local step=M.PhaseText(status)
    if done and total and total>0 and total<math.huge and done>=0 and done<=total
        and done==math.floor(done) and total==math.floor(total) then
        local percent=math.floor(done*100/total)
        return percent,TF("loading.status.current_step_counted",{step=step,
            done=string.format("%d",done),total=string.format("%d",total),
            percent=string.format("%d",percent)})
    end
    local scanned=tonumber(status.recordsSeen)
    if (status.step or status.phase)=="scan" and scanned and scanned>0 and scanned<math.huge
        and scanned==math.floor(scanned) then
        return nil,TF("loading.status.current_step_records_read",{step=step,
            records=string.format("%d",scanned)})
    end
    return nil,TF("loading.status.current_step_in_progress",{step=step})
end
-- Local availability only; the step line is shown once, next to its bar.
function M.Detail(status)
    if status.state=="failed" then
        return status.coreReady and (T("loading.body.local_tools_remain_available").."\n"
                ..T("loading.body.shared_views_unavailable"))
            or (T("loading.body.local_controls_wait").."\n"
                ..TF("loading.body.see_status_keep_backup",{command="/nexus status"}))
    end
    return T(status.coreReady and "loading.body.wishlist_ready_shared_loading"
        or "loading.body.wishlist_unlocks_after_check")
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
                -- label is the caller's own (already shown) button text.
                GameTooltip:AddLine(TF(status.state=="failed" and "loading.tooltip.view_unavailable"
                    or "loading.tooltip.view_loading",{view=label}),.65,.65,.68)
                GameTooltip:AddLine(M.PhaseText(status),.9,.9,.9,true)
                GameTooltip:AddLine(T(status.coreReady and "loading.tooltip.local_tools_available"
                    or "loading.tooltip.local_tools_unlock"),.8,.8,.8,true)
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
    f.localButton:SetPoint("BOTTOMRIGHT",-12,8);f.localButton:SetSize(96,23);f.localButton:SetText(T("loading.button.wishlists"))
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
    f.title:SetText(T(status.state=="ready" and "loading.title.ready"
        or status.state=="failed" and "loading.title.stopped" or "loading.title.loading"))
    local localText=T(status.coreReady and "loading.status.wishlist_ready_shared_may_load"
        or "loading.status.reading_local_data")
    -- The full-width line carries the step; elapsed time never sets a percent.
    f.detail:SetText(localText.."\n"..progress)
    -- Both lines keep their measured height (a wider face wraps the step
    -- line); the bar and the elapsed line follow, inside the window.
    local extra=Nexus.LayoutMetrics and (Nexus.LayoutMetrics.WrapHeight(f.detail,402,42)-42) or 0
    if f._nexusExtra~=extra then
        f._nexusExtra=extra
        f.bar:ClearAllPoints();f.bar:SetPoint("TOPLEFT",12,-76-extra)
        f.progress:ClearAllPoints();f.progress:SetPoint("TOPLEFT",12,-92-extra)
        f:SetHeight(130+extra)
    end
    local elapsed=math.max(0,math.floor(now-startedAt))
    f.progress:SetText(status.state=="ready" and "" or TF("loading.status.elapsed",
        {time=string.format("%d:%02d",math.floor(elapsed/60),elapsed%60)}))
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
