-- One assigned target and one explicit Start. Reading either view is passive.
-- One window, NexusOrbPanel, holds two pages: the run controls and the
-- read-only history (NexusOrbRunLog, a child page, not its own window).
-- Switching pages only shows and hides frames: it starts, resumes, confirms
-- and cancels nothing. Closing the window (Close or Escape) is the one place
-- an armed new-run review is cancelled, exactly as before.
Nexus=Nexus or {}
local UI={};Nexus.OrbPanel=UI
local frame,advanced=nil,false
local sourcePage=1
local page="run"
local refreshFailing=false
local CLOSE_NOTICE="Closing the window does not stop an approved run. Use Pause or Stop."
local MINI_OPEN_TIP="Shows a small movable panel with this run's status and Pause, Resume and Stop. Opening it starts, resumes and spends nothing."
-- Page sizes. The run page keeps its measured sizes; the history page is
-- taller so its footer sits below the details instead of over them. Both fit
-- a 768-unit-high UI (1280x720 or 1366x768 at the largest UI scale).
local RUN_W,RUN_H,RUN_H_ADVANCED=620,445,660
local LOG_TOP=40
local LOG_W,LOG_H=760,588
local function text(parent,x,y,w,h,value)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f:SetPoint("TOPLEFT",x,y);f:SetSize(w,h);f:SetJustifyH("LEFT");f:SetJustifyV("TOP")
    f:SetText(value or "");return f
end
local function button(parent,x,y,w,label,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(w,24);b:SetPoint("TOPLEFT",x,y);b:SetText(label);b:SetScript("OnClick",fn)
    b:SetFrameLevel(parent:GetFrameLevel()+2);b:EnableMouse(true);return b
end
local function enable(b,on)if on then b:Enable()else b:Disable()end end
local function selected(b,on)
    if Nexus.Theme and Nexus.Theme.SetSelected then Nexus.Theme.SetSelected(b,on) end
end
local function styled(window,alpha)
    if not Nexus.Theme then return end
    if Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(window,alpha) end
    if Nexus.Theme.StyleTree then Nexus.Theme.StyleTree(window) end
end
-- A size change keeps the top-left corner where it is, so the control the
-- player just pressed stays under the pointer. GetLeft/GetTop and anchor
-- offsets share the frame's own scale.
local function pinTopLeft(f)
    local left,top=f:GetLeft(),f:GetTop()
    if not left or not top then return end
    f:ClearAllPoints();f:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left,top)
end
-- The whole window stays on the visible UI. A page taller or wider than the
-- UI is scaled down (LayoutMetrics.FitToScreen: never below 0.5, scale 1 when
-- it fits). Because GetLeft/GetTop and anchor offsets are in the frame's own
-- scale, a scale change converts the corner the player sees to the new scale,
-- then keeps every edge on the UI. Four size reads per refresh; nothing
-- moves unless the UI size or the page size changed.
local fitSeen={}
local function fitWindow()
    local LM=Nexus.LayoutMetrics
    if not (frame and LM and LM.FitToScreen and UIParent) then return end
    local sw,sh=tonumber(UIParent:GetWidth()),tonumber(UIParent:GetHeight())
    local w,h=tonumber(frame:GetWidth()),tonumber(frame:GetHeight())
    if fitSeen.sw==sw and fitSeen.sh==sh and fitSeen.w==w and fitSeen.h==h then return end
    fitSeen.sw,fitSeen.sh,fitSeen.w,fitSeen.h=sw,sh,w,h
    local before=tonumber(frame:GetScale()) or 1
    local left,top=frame:GetLeft(),frame:GetTop()
    -- nil: no plausible UI size was reported, so nothing is moved.
    local scale=LM.FitToScreen(frame)
    if not (scale and left and top and w and h) then return end
    local x,y=left*before,top*before
    local cx=math.max(0,math.min(x,sw-w*scale))
    local cy=math.min(sh,math.max(y,h*scale))
    if math.abs(scale-before)>0.001 or math.abs(cx-x)>0.5 or math.abs(cy-y)>0.5 then
        frame:ClearAllPoints();frame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",cx/scale,cy/scale)
    end
end
-- The runtime still names a limit-increase step that no window offers. Until
-- that runtime text changes, the window states the step that does exist.
local OBSOLETE_TEXT={
    ["Use Increase limit while paused, or finish this run first."]=
        "The maximum cannot change during a run. Stop this run, then start a new run with a higher maximum.",
    ["The approved limit is reached. Confirm an increased limit or stop."]=
        "The approved maximum is reached. Stop, then start a new run with a higher maximum.",
}
local function truthful(value)
    if value==nil then return nil end
    return OBSOLETE_TEXT[value] or value
end
-- Legacy EditBox has no Button Enable/Disable API. Lock both input routes and
-- release focus so an approved maximum cannot remain editable during a run.
local function editLimit(on)
    local e=frame.limit;e.editable=on==true
    e:EnableMouse(e.editable);e:EnableKeyboard(e.editable);e:SetAlpha(e.editable and 1 or .5)
    if not e.editable then e:ClearFocus()end
end
local function inactiveControls()
    editLimit(false)
    if frame.cont then frame.cont:Hide()end
    -- With no run read, Start alone holds its place, disabled like the rest.
    if frame.review then frame.review:Hide()end
    if frame.pause then frame.pause:Hide();frame.resume:Hide();frame.start:Show()end
    for _,b in ipairs(frame.mutations)do b:Disable()end
    frame.advanced:Hide();frame:SetHeight(RUN_H)
end
-- A recorded name on one line: at most 100 characters, cut on a character
-- boundary (never inside a multi-byte letter or an escaped "||"). whole keeps
-- the complete value for the box's tooltip.
local function name(s,whole)
    local v=tostring(s or ""):gsub("[%c]"," ")
    if not whole then
        if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then v=Nexus.LayoutMetrics.Truncate(v,100)
        elseif #v>100 then v=v:sub(1,100):gsub("[\192-\255][\128-\191]*$","") end
    end
    return (v:gsub("|","||"))
end
-- Sets a box's text. When a name in it was shortened, its tooltip
-- (LayoutMetrics.FullTextTooltip) carries the complete text.
local function setFull(fs,shown,full)
    fs:SetText(shown);fs._nexusFullText=(full and full~=shown) and full or nil
end
local function notify(ok,err)
    if frame then frame.notice:SetText(truthful(err) or (ok and "" or "No change."))end
    UI.Refresh()
end
-- Deliberate review of a changed Resume target. When a paused run's next
-- Resume would adopt a different ready assignment than the one it started
-- with (OrbRuntime resumeTarget kind "changed"), Resume is offered only in
-- this window and only after Review target for that exact assignment (its
-- key). Memory only: another assignment, leaving that state or closing the
-- window clears it. It writes and sends nothing and can only withhold Resume;
-- Resume itself still makes every runtime check and adopts what it reads.
local review={key=nil}
local function changedTarget(t) return type(t)=="table" and t.kind=="changed" end
local function reviewHeld(t)
    return changedTarget(t) and not (t.key~=nil and review.key==t.key)
end
local function quotedName(t,whole)
    return t.name~=nil and ("'"..name(t.name,whole).."'") or "an unnamed Wishlist"
end
local function reviewRefusal(t)
    if not reviewHeld(t) then return nil end
    return "Review the new target first: Resume would use "..quotedName(t)..". Nothing was resumed."
end
-- The legacy one-button entry (Pause while running, Resume while paused). The
-- window no longer shows it during a run; it stays for programmatic callers
-- and takes the same review.
local function primary(limit,tracked)
    local s=Nexus.OrbRuntime.Status()
    if s.running then return Nexus.OrbRuntime.Pause()end
    if s.state=="PAUSED" then
        local held=reviewRefusal(s.resumeTarget)
        if held then return nil,held end
        return Nexus.OrbRuntime.Resume()
    end
    return Nexus.OrbRuntime.Start(limit,tracked)
end
-- The maximum box shows the draft; a refresh sets it without counting as
-- typing (OnTextChanged ignores changes made here).
local function showLimit(value)
    local e=frame.limit;e.settingText=true;e:SetText(value);e.settingText=nil;e.shownDraft=value
end
local MAX_TIP="Follow your confirmed Orb balance, up to 1000, until you enter another amount or start the run. This does not spend Orbs."
local phases={IDLE="Not started",READY="Preparing next replacement",WAIT_OFFER="Waiting for the Orb offer",
    WAIT_RESULT="Waiting for result confirmation",PAUSED="Paused",STOPPED="Stopped",COMPLETE="Targets complete",
    ROLLED_COMPLETE="Rolled targets complete",LIMIT="Maximum reached",OUT_OF_ORBS="No Orbs remain",
    NO_SOURCES="No safe surplus copies remain",RECOVERY="Previous result is unresolved",
    FINISHED="Finished - limit reached"}
-- At FINISHED the primary control is the same button that was Pause while the
-- run was going and Resume while it was paused, and the limit box has just
-- been refilled with the configured maximum. One press there would start a new
-- spending run. The first press only arms it; the second press starts it.
local confirmNewRun=false
-- The maximum shown when the new run was armed. A different amount (for
-- example a tracked balance that changed) needs a new review.
local confirmAmount=nil
-- What an explicit Resume of a paused run would act on (OrbRuntime
-- resumeTarget): the ready assignment it would adopt, or the original
-- operation it would continue. An assignment that is not ready is never named.
local ASSIGNMENT_STATES={restoring="restoring",loading="loading",unavailable="unavailable",unassigned="not assigned"}
local function resumeTargetText(t,whole)
    if type(t)~="table" then return nil end
    local n=quotedName(t,whole)
    if t.kind=="original" then return "Resume continues the original operation for "..n.."."
    elseif t.kind=="same" then return "Resume would use "..n..", the same target."
    elseif t.kind=="changed" then
        local was=t.original~=nil and t.original~=t.name and (" instead of '"..name(t.original,whole).."'") or ""
        if not reviewHeld(t) then return "Reviewed: Resume would use "..n..was.." with the same maximum." end
        return "New target: Resume would use "..n..was..". Review target first."
    elseif t.kind=="settle" then return "Resume waits: the original operation must settle before a changed target can be used."
    elseif t.kind=="unavailable" then
        return "Resume target unknown: the assigned Wishlist is "..(ASSIGNMENT_STATES[t.assignmentState] or "not ready").."."
    end
    return nil
end
-- The compact views name the target in two short parts: what (with the raw
-- name; the caller shortens and escapes it) and the instruction.
local function compactTarget(t)
    if type(t)~="table" then return nil end
    local n=t.name~=nil and ("'"..tostring(t.name):gsub("%c"," ").."'") or "an unnamed Wishlist"
    if t.kind=="original" or t.kind=="same" then return "Resume uses: "..n,"Paused"
    elseif t.kind=="changed" then return "New target: "..n,"Paused - review it in the Orb window"
    elseif t.kind=="settle" then return nil,"Paused - original must settle first"
    elseif t.kind=="unavailable" then return "Resume target unknown","Paused - Wishlist not ready" end
    return nil
end
-- An unresolved earlier result, in layers: what it blocks, what the player can
-- do now (by the actual Continue state), then the runtime's own reason,
-- unshortened, so recorded Echo names and earlier facts stay exact.
local RECOVERY_HEADLINE="Previous result is unresolved: no new Orb run or ordinary roll until it settles."
local function recoveryActions(cv)
    if cv.stage=="checking" or cv.stage=="ready" then
        return "What you can do: finish or cancel the check in the Continue window."
    elseif cv.stage=="refused" then return "What you can do: Review check... below says why the check stopped."
    elseif cv.eligible==true then return "What you can do: Continue... below checks the game, then asks you to confirm."
    elseif cv.explanation==true then return "What you can do: follow the details; Why blocked... below explains this record." end
    return "What you can do: follow the details below."
end

-- Read-only Orb history page. It renders one fixed row pool, reads only the
-- page it shows plus the operation whose details are open, and performs no Orb
-- action: opening, paging, selecting and copying spend nothing, select nothing
-- and write nothing. All presentation lives in Nexus.OrbHistory, which reads
-- recorded fields only.
local LOG_ROWS=8
-- One column layout for the header AND the body. A heading that keeps its own
-- offsets drifts away from the values it labels the moment either side is
-- touched, so both read these measurements and nothing else. ROW_X is where a
-- row starts inside the page, so the header sits on the same origin.
local LOG_ROW_X,LOG_ROW_W=20,720
local LOG_COLUMNS={
    {key="index",label="#",x=0,w=28},
    {key="source",label="Replaced Echo",x=52,w=180,iconX=30},
    {key="replacement",label="Replacement",x=260,w=190,iconX=238},
    {key="reason",label="Why selected",x=456,w=150},
    {key="result",label="Result",x=612,w=105},
}
-- Vertical bands of the history page, top to bottom, each starting below the
-- previous one: run selector and header, warning, headings, rows, details,
-- footer, note.
local LOG_BANDS={
    header={y=-2,h=50},warning={y=-56,h=20},headings={y=-80,h=18},
    rows={y=-102,h=40},details={y=-428,h=96},footer={y=-530,h=24},
    note={y=-558,h=20},
}
local logFrame,logView,logPage=nil,"current",1
local logSelection=nil
local logCopyFrame=nil
local logCopy={key=nil,text=nil}
local logSeen={}
local logRendered=nil
local ensureLog,refreshLog
-- Labels resolved for the ids this page actually shows. Cleared whenever the
-- history revision changes, so a stale label cannot outlive its page.
local logLabels={key=nil,byId={}}
local function logRunKey(run)
    if not run then return "none" end
    return tostring(run.which).."|"..tostring(run.runId)
end
local function logPageView(page)
    return Nexus.OrbRuntime.RunLog(logView,((page or 1)-1)*LOG_ROWS+1,LOG_ROWS)
end
local function logKey(run)
    if not run then return "none" end
    -- The revision changes on every recorded event, and the live run's usage
    -- and exposure are read as they are now (RunLog), so a cached copy cannot
    -- outlive the history it was made from.
    return table.concat({tostring(run.which),tostring(run.runId),
        tostring(run.revision),tostring(run.total),tostring(run.spent),tostring(run.reserved)},"|")
end
-- One lookup of ONE recorded id, at most once per distinct id on the page:
-- the addon's shared catalog accessor, then the client's own spell info. It
-- indexes the catalog by that exact id and never iterates it; the accessor
-- itself may refresh its own cache when the client's data changed, which is
-- the same shared call every other view makes. It sends no request, reads no
-- gameplay state, and writes nothing back into the run, the log or the
-- profile.
local function logResolve(spellId)
    local found=logLabels.byId[spellId]
    if found~=nil then return found.label,found.icon end
    local label,icon
    local adapter=Nexus.GameAdapter
    local catalog=adapter and adapter.Catalog and adapter.Catalog()
    local rows=catalog and (catalog.rows or catalog)
    local row=type(rows)=="table" and rows[spellId] or nil
    if type(row)=="table" and row.name and row.name~="" then label=row.name end
    if type(GetSpellInfo)=="function" then
        local ok,spellName,_,texture=pcall(GetSpellInfo,spellId)
        if ok then
            if not label and spellName and spellName~="" then label=spellName end
            if texture and texture~="" then icon=texture end
        end
    end
    logLabels.byId[spellId]={label=label,icon=icon}
    return label,icon
end
local function logHistory() return assert(Nexus.OrbHistory,"Orb history projection unavailable") end
-- Pages share the one window. Only frames are shown and hidden here.
local function showPage(name)
    if page==name then return end
    page=name
    local onRun=name=="run"
    for _,w in ipairs(frame.runWidgets)do if onRun then w:Show()else w:Hide()end end
    selected(frame.runTab,onRun);selected(frame.historyTab,not onRun)
    pinTopLeft(frame)
    if onRun then
        if logFrame then logFrame:Hide()end
        frame:SetWidth(RUN_W);frame:SetHeight(advanced and RUN_H_ADVANCED or RUN_H)
    else
        -- A hidden box must not keep the keyboard. Typed text is already the
        -- runtime's draft, so nothing is lost.
        frame.limit:ClearFocus()
        ensureLog()
        frame:SetWidth(LOG_W);frame:SetHeight(LOG_TOP+LOG_H)
        logFrame:Show()
    end
    fitWindow()
end
local function refresh()
    if not frame or not frame:IsShown()then return end
    -- The history page is read-only and reads its own data; the run controls
    -- are hidden, so they are not rendered.
    if page~="run" then return end
    local ready=Nexus.StartupStatus and Nexus.StartupStatus()
    if not ready or not ready.coreReady then
        setFull(frame.plan,"Restoring assigned Wishlist...")
        setFull(frame.status,"Reading local saved data. Shared-library loading is not required.")
        frame.balance:SetText("Orb balance: loading")
        frame.targets:SetText("");frame.permanent:SetText("");frame.usage:SetText("")
        inactiveControls()
        -- No run can be read yet, so the compact status is not offered either.
        frame.miniPanel:Disable()
        return
    end
    frame.miniPanel:Enable()
    -- One display read per refresh; the source list is prepared only for Advanced.
    -- The snapshot authorizes nothing: Start, Resume and every spend read again.
    local s=Nexus.OrbRuntime.Status(advanced);frame.snapshot=s
    local a=s.assignment or {};local busy=s.running or s.pending or s.state=="PAUSED" or s.state=="LIMIT"
    -- A review belongs to the exact changed target it was made for.
    local target=s.state=="PAUSED" and s.resumeTarget or nil
    if not (changedTarget(target) and target.key~=nil and target.key==review.key) then review.key=nil end
    if a.state=="restoring" then setFull(frame.plan,"Restoring assigned Wishlist...")
    else setFull(frame.plan,"Assigned Wishlist: "..name(a.name or "none"),"Assigned Wishlist: "..name(a.name or "none",true)) end
    -- A ready assignment whose read was refused is still assigned: its progress
    -- is unavailable (the reason is in the status line), not unassigned.
    local targets
    if s.progress then targets=s.progress.rolledMissing.." rolled target copies still missing"
    elseif a.state=="ready" then targets="Target progress unavailable"..(a.note and (": "..tostring(a.note)) or ".")
    else targets=a.note or "Assign a Wishlist through My Builds to begin." end
    frame.targets:SetText(targets)
    local permanent=s.progress and s.progress.permanentMissing
    frame.permanent:SetText(permanent and permanent>0 and (permanent.." locked target copies remain. Orbs cannot change locked Echo slots.")or "")
    local d=s.limitDraft or {}
    local mode=""
    if not busy then
        if d.tracking then
            mode=d.value~=nil and ("\nMaximum follows this balance (up to "..tostring(d.cap or 1000)..") until you enter another amount.")
                or "\nMaximum follows the confirmed balance; unavailable until it is confirmed."
        elseif d.text~=nil and d.value==nil then
            mode="\nEnter a whole-number maximum from 1 to 10,000, or press Max."
        end
    end
    frame.balance:SetText((s.charges~=nil and ("Confirmed Orb balance: "..s.charges)
        or ("Orb balance: "..(s.balanceState or "unknown")..". "..(s.balanceReason or "")))..mode)
    if s.state~="FINISHED" then confirmNewRun=false;confirmAmount=nil end
    editLimit(not busy)
    local shown
    if busy then shown=tostring(s.limit)
    elseif d.text~=nil then shown=d.text
    else shown=d.value~=nil and tostring(d.value) or "" end
    if not frame.limit:HasFocus() and frame.limit:GetText()~=shown then showLimit(shown) end
    -- Max: only an editable draft with a confirmed balance above zero. The
    -- click checks again.
    enable(frame.max,not busy and (tonumber(s.charges) or 0)>0 and s.balanceState=="confirmed")
    if confirmNewRun and confirmAmount~=nil and frame.limit:GetText()~=confirmAmount then
        confirmNewRun=false;confirmAmount=nil
        frame.notice:SetText("The maximum changed. Review it, then press Start new run again.")
    end
    frame.start:SetText(s.running and "Pause" or (s.state=="PAUSED" and "Resume"
        or (s.state=="FINISHED" and (confirmNewRun and "Confirm new run" or "Start new run") or "Start")))
    -- During a run, separate fixed Pause and Resume: a repeated press of one
    -- never becomes the other. Otherwise Start (also the two-step new run).
    if busy then frame.start:Hide();frame.pause:Show();frame.resume:Show()
    else frame.pause:Hide();frame.resume:Hide();frame.start:Show() end
    -- One usage form on every surface: Orbs used against the approved maximum;
    -- a requested Orb whose spend is not confirmed is pending. Before a run,
    -- the maximum shown is the draft, not yet approved.
    frame.usage:SetText("Orbs used: "..s.spent.." / "..((busy or s.limit>0)and (s.limit.." approved") or (shown~="" and shown or "-"))
        ..(s.reserved>0 and ("; pending: "..s.reserved..(s.reserved==1 and " Orb" or " Orbs").." requested, not confirmed yet")or ""))
    local reason=(s.running or s.pending or s.state=="PAUSED")and s.reason or (s.startReason or s.reason)
    local detail=truthful(reason) or s.error or ""
    local cv=Nexus.OrbRuntime.ContinueView()
    local shownStatus,fullStatus
    if s.state=="RECOVERY" then
        shownStatus=RECOVERY_HEADLINE.."\n"..recoveryActions(cv).."\nDetails: "..detail
        fullStatus=shownStatus
    else
        local phase=phases[s.state]or s.state
        local line,whole=resumeTargetText(target,false),resumeTargetText(target,true)
        shownStatus=phase..(line and ("\n"..line) or "").."\n"..detail
        fullStatus=phase..(whole and ("\n"..whole) or "").."\n"..detail
    end
    if confirmNewRun and s.state=="FINISHED" then
        local tail="\nPress Confirm new run to start a new run of up to "
            ..tostring(frame.limit:GetText()).." Orb(s). Close this window to cancel."
        shownStatus,fullStatus=shownStatus..tail,fullStatus..tail
    end
    if s.targetChanged then
        shownStatus=shownStatus.."\nOriginal operation: "..name(s.operationName)
        fullStatus=fullStatus.."\nOriginal operation: "..name(s.operationName,true)
    end
    setFull(frame.status,shownStatus,fullStatus)
    frame.assignmentNote:SetText(a.mirrorNote or "")
    if advanced then
        local rows=s.sources or {};sourcePage=math.max(1,math.min(sourcePage,math.max(1,math.ceil(#rows/4))))
        for i,r in ipairs(frame.sourceRows)do
            local v=rows[(sourcePage-1)*4+i];r.key=v and v.key
            local tail=v and (" (quality "..v.quality.."): "..v.excess.." safe excess")
            setFull(r.label,v and (name(v.name)..tail) or "",v and (name(v.name,true)..tail))
            enable(r.exclude,v~=nil and not busy)
        end
        enable(frame.clearExclusions,not busy)
        frame.sourcePage:SetText("Eligible sources "..sourcePage.." / "..math.max(1,math.ceil(#rows/4)))
    end
    local held=reviewHeld(target)
    enable(frame.start,s.running or (s.canResume and not held) or s.canStart);enable(frame.stop,busy);enable(frame.assigned,not busy)
    enable(frame.pause,s.running);enable(frame.resume,not s.running and s.canResume and not held)
    do
        local stage=cv.stage
        frame.cont:SetText(stage=="done" and "Review outcome..."
            or stage=="refused" and "Review check..."
            or stage=="checking" and "Check progress..." or (stage=="ready" or cv.eligible==true) and "Continue..." or "Why blocked...")
        if cv.explanation==true or cv.eligible==true or stage=="checking" or stage=="ready" or stage=="refused" or stage=="done" then frame.cont:Show()else frame.cont:Hide()end
    end
    -- Review target shares Continue's place and is never shown with it.
    if changedTarget(target) and target.key~=nil and not frame.cont:IsShown() then
        frame.review:SetText(held and "Review target" or "Cancel review");frame.review:Show();frame.review:Enable()
    else frame.review:Hide() end
    if advanced then frame.advanced:Show()else frame.advanced:Hide()end
    selected(frame.advancedToggle,advanced)
    frame:SetHeight(advanced and RUN_H_ADVANCED or RUN_H)
    return true -- A complete run-status read/render, not a history/loading pass.
end
function UI.Refresh()
    if not frame or not frame:IsShown()then return end
    local ok,err=pcall(refresh)
    if not ok then
        inactiveControls()
        setFull(frame.status,"Orb panel refresh failed. Controls are unavailable.")
        -- Keep controls unavailable on every failed read, but report only the
        -- first error in an episode. A successful read permits a new report.
        if refreshFailing then return end
        refreshFailing=true
        error(err,0)
    end
    if err==true then refreshFailing=false end
    -- Advanced, a page change or a new UI scale or screen size.
    fitWindow()
end
local function ensure()
    if frame then return end
    frame=CreateFrame("Frame","NexusOrbPanel",UIParent);frame:Hide();frame:SetSize(RUN_W,RUN_H);frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    frame:SetFrameStrata("DIALOG");frame:SetFrameLevel(30);frame:EnableMouse(true);frame:SetMovable(true);frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton");frame:SetScript("OnDragStart",function(self)self:StartMoving()end)
    frame:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    frame:SetBackdropColor(.035,.04,.05,1)
    frame.plan=text(frame,20,-48,440,32)
    frame.assigned=button(frame,469,-48,130,"My Builds",function()
        if Nexus.JournalTab and Nexus.JournalTab.OpenBuilds then Nexus.JournalTab.OpenBuilds()
        elseif Nexus.WishlistEditor then Nexus.WishlistEditor.Show()end
    end)
    frame.targets=text(frame,20,-82,580,26);frame.permanent=text(frame,20,-112,580,28);frame.balance=text(frame,20,-144,580,34)
    frame.limitLabel=text(frame,20,-190,170,24,"Maximum Orbs this run:")
    frame.limit=CreateFrame("EditBox",nil,frame,"InputBoxTemplate");frame.limit:SetSize(65,25);frame.limit:SetPoint("TOPLEFT",196,-188)
    if Nexus.Theme and Nexus.Theme.StyleInput then Nexus.Theme.StyleInput(frame.limit) end
    frame.limit:SetFrameLevel(32);frame.limit:SetAutoFocus(false);frame.limit:SetNumeric(true);frame.limit:SetMaxLetters(5)
    frame.limit:SetScript("OnEditFocusGained",function(self)if not self.editable or not frame:IsShown()then self:ClearFocus()end end)
    frame.limit:SetScript("OnEnterPressed",function(self)
        if not self.editable then self:ClearFocus();return end
        local ok,err=Nexus.OrbRuntime.SetLimit(tonumber(self:GetText()));self:ClearFocus();notify(ok,err)
    end)
    frame.limit:SetScript("OnEscapePressed",function(self)Nexus.OrbRuntime.CancelLimitEdit();self:ClearFocus();UI.Refresh()end)
    -- Typing (also the same number, a partial or an empty text) is the
    -- player's own amount. A refresh setting the box, or focus alone, is not.
    frame.limit:SetScript("OnTextChanged",function(self,userInput)
        if self.settingText or not self.editable then return end
        if userInput==true or self:HasFocus() then Nexus.OrbRuntime.EditLimitText(self:GetText()) end
    end)
    -- A button click does not take keyboard focus from the box: release it
    -- first, so the refresh shows the tracked amount instead of old typing.
    frame.max=button(frame,268,-188,48,"Max",function()frame.limit:ClearFocus();notify(Nexus.OrbRuntime.TrackBalance())end)
    frame.max:SetScript("OnEnter",function(self)
        if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(MAX_TIP,1,1,1,1,true);GameTooltip:Show()end
    end)
    frame.max:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    frame.max.tooltip=MAX_TIP
    -- While a run is busy, Pause and Resume are separate buttons in Start's
    -- place, each with one fixed meaning: a repeated press of Pause can never
    -- become Resume. Each acts only when a fresh read offers it; the runtime
    -- then applies its own checks.
    frame.pause=button(frame,334,-188,58,"Pause",function()
        if not Nexus.OrbRuntime.Status().running then notify(nil,"Not paused: the run is not running.");return end
        notify(Nexus.OrbRuntime.Pause())
    end)
    frame.resume=button(frame,398,-188,62,"Resume",function()
        local s=Nexus.OrbRuntime.Status()
        if s.running then notify(nil,"Not resumed: the run is already running.");return end
        if not s.canResume then
            local t=s.state=="PAUSED" and s.resumeTarget or nil
            notify(nil,t and t.kind=="settle" and "Not resumed: the original operation must settle first."
                or t and t.kind=="unavailable" and "Not resumed: the assigned Wishlist is not ready."
                or "Not resumed: Orb mode does not offer Resume now.")
            return
        end
        local held=reviewRefusal(s.resumeTarget)
        if held then notify(nil,held);return end
        notify(Nexus.OrbRuntime.Resume())
    end)
    frame.pause:Hide();frame.resume:Hide()
    frame.start=button(frame,334,-188,126,"Start",function()
        local s=Nexus.OrbRuntime.Status()
        if s.state=="FINISHED" and not confirmNewRun then
            -- The explicit preparation of a new run: its draft follows the
            -- confirmed balance again; the amount is shown for review.
            -- A refusal (for example a balance that became unknown after the
            -- render) arms nothing and changes nothing.
            frame.limit:ClearFocus()
            local prepared,why=Nexus.OrbRuntime.NewRunDraft()
            if not prepared then notify(nil,why);return end
            UI.Refresh()
            local amount=frame.limit:GetText();local v=tonumber(amount)
            if v==nil or v<1 or v>10000 or v~=math.floor(v) then
                -- A draft that follows the balance has no amount of its own:
                -- name the balance, not typing or Max.
                local d=Nexus.OrbRuntime.LimitDraft()
                local why="Enter a whole-number maximum from 1 to 10,000, or press Max. Nothing was started."
                if d.tracking and d.text==nil then
                    why=d.value==0 and "The confirmed Orb balance is 0. Nothing was started."
                        or "The maximum follows the confirmed Orb balance, which is not available. Nothing was started."
                end
                notify(nil,why)
                return
            end
            confirmNewRun=true;confirmAmount=amount;UI.Refresh();return
        end
        -- The Confirm click checks the reviewed amount itself: an amount
        -- changed since the review (typed, or not yet refreshed) needs a new
        -- review, whatever the refresh timing.
        if confirmNewRun and frame.limit:GetText()~=confirmAmount then
            confirmNewRun=false;confirmAmount=nil
            notify(nil,"The maximum changed. Review it, then press Start new run again.")
            return
        end
        confirmNewRun=false;confirmAmount=nil
        if s.running or s.state=="PAUSED" then notify(primary(nil));return end
        -- Start uses the amount shown, never a newer balance read at the click.
        local d=s.limitDraft or {}
        local shown=frame.limit:GetText()
        local n=tonumber(shown)
        if n==nil or n<1 or n~=math.floor(n) then
            notify(nil,d.tracking and "The maximum follows the confirmed Orb balance, which is not available. Nothing was started."
                or "Enter a whole-number maximum from 1 to 10,000, or press Max. Nothing was started.")
            return
        end
        -- Still the tracked amount this window showed: approve it as shown.
        -- Any other text is the player's own amount (the existing path).
        notify(primary(n,d.tracking and d.text==nil and shown==frame.limit.shownDraft))
    end)
    frame.stop=button(frame,470,-188,120,"Stop",function()notify(Nexus.OrbRuntime.Stop())end)
    frame.approval=text(frame,20,-221,580,37,"Start approves this maximum and automatic use of eligible surplus copies, including safe recycling. Ordinary Automation will turn OFF.")
    frame.usage=text(frame,20,-263,580,22);frame.status=text(frame,20,-289,580,74);frame.notice=text(frame,20,-364,440,24)
    -- Fixed boxes; a status or refusal longer than its box is complete in a tooltip.
    if Nexus.LayoutMetrics then
        frame.statusHit=Nexus.LayoutMetrics.FullTextTooltip(frame.status,frame)
        frame.noticeHit=Nexus.LayoutMetrics.FullTextTooltip(frame.notice,frame)
        frame.balanceHit=Nexus.LayoutMetrics.FullTextTooltip(frame.balance,frame)
        frame.targetsHit=Nexus.LayoutMetrics.FullTextTooltip(frame.targets,frame)
        frame.planHit=Nexus.LayoutMetrics.FullTextTooltip(frame.plan,frame)
    end
    -- The same read-only explanation also serves ineligible restored receipts.
    frame.cont=button(frame,470,-364,130,"Continue...",function()UI.ShowContinue()end)
    frame.cont:Hide()
    -- The deliberate review of a changed Resume target (see `review`). Review
    -- and Cancel review only record or clear it: nothing is resumed or spent.
    frame.review=button(frame,470,-364,130,"Review target",function()
        local t=Nexus.OrbRuntime.Status().resumeTarget
        if not (changedTarget(t) and t.key~=nil) then
            review.key=nil;frame.notice:SetText("No changed target to review. Nothing was changed.")
        elseif review.key==t.key then
            review.key=nil;frame.notice:SetText("Review cancelled. Resume stays withheld; nothing was spent.")
        else
            review.key=t.key
            frame.notice:SetText("Reviewed: Resume would use "..quotedName(t).." with the same maximum. Nothing was spent.")
        end
        UI.Refresh()
    end)
    frame.review:Hide()
    frame.closeNotice=text(frame,20,-393,580,20,CLOSE_NOTICE)
    button(frame,20,-414,85,"Help",function()Nexus.Help.Show("orbs")end)
    frame.advancedToggle=button(frame,115,-414,95,"Advanced",function()
        advanced=not advanced;pinTopLeft(frame);UI.Refresh()
    end)
    frame.appearance=button(frame,220,-414,110,"Appearance",function(self)
        if Nexus.Theme and Nexus.Theme.ShowMenu then Nexus.Theme.ShowMenu(self)end
    end)
    frame.appearance:SetScript("OnEnter",function(self)
        if not (GameTooltip and Nexus.Theme) then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText("Appearance: "..Nexus.Theme.Summary(),1,1,1,1,true)
        GameTooltip:AddLine(Nexus.Theme.HELP,.9,.9,.9,true)
        GameTooltip:Show()
    end)
    frame.appearance:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    -- The optional compact status (UI.ShowMini). It only shows that panel:
    -- this window stays as it is, and nothing is started or changed.
    frame.miniPanel=button(frame,340,-414,110,"Mini panel",function()UI.ShowMini()end)
    frame.miniPanel:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(MINI_OPEN_TIP,1,1,1,1,true);GameTooltip:Show()
    end)
    frame.miniPanel:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    button(frame,515,-414,85,"Close",function()frame:Hide()end)
    frame.advanced=CreateFrame("Frame",nil,frame);frame.advanced:Hide();frame.advanced:SetSize(590,205);frame.advanced:SetPoint("TOPLEFT",15,-446);frame.advanced:SetFrameLevel(31)
    local af=frame.advanced
    button(af,5,-4,100,"Recheck",function()notify(Nexus.OrbRuntime.Recheck())end)
    frame.clearExclusions=button(af,116,-4,195,"Clear source exclusions",function()notify(Nexus.OrbRuntime.ClearExclusions())end)
    frame.sourceRows={}
    for i=1,4 do
        local r={};r.label=text(af,5,-38-(i-1)*28,455,25)
        if Nexus.LayoutMetrics then r.hit=Nexus.LayoutMetrics.FullTextTooltip(r.label,af) end
        r.exclude=button(af,468,-35-(i-1)*28,100,"Exclude",function()if r.key then notify(Nexus.OrbRuntime.Exclude(r.key,true))end end)
        frame.sourceRows[i]=r
    end
    frame.sourcePage=text(af,5,-151,250,23)
    button(af,285,-151,85,"Previous",function()sourcePage=math.max(1,sourcePage-1);UI.Refresh()end)
    button(af,380,-151,85,"Next",function()sourcePage=sourcePage+1;UI.Refresh()end)
    frame.assignmentNote=text(af,5,-180,565,31)
    frame.mutations={frame.start,frame.stop,frame.assigned,frame.clearExclusions,frame.max,frame.pause,frame.resume,frame.review}
    for _,r in ipairs(frame.sourceRows)do frame.mutations[#frame.mutations+1]=r.exclude end
    -- Only the run text and child controls belong to this page. Root Texture
    -- regions can be window backdrop/decorative artwork and must remain shown
    -- on history. The title, tabs and history are created after this capture.
    frame.runWidgets={}
    do
        local seen={}
        for _,list in ipairs({{frame:GetRegions()},{frame:GetChildren()}})do
            for _,w in ipairs(list)do
                if not seen[w] and (w:GetObjectType()~="Texture") then
                    seen[w]=true;frame.runWidgets[#frame.runWidgets+1]=w
                end
            end
        end
    end
    frame.title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    frame.title:SetPoint("TOPLEFT",20,-17);frame.title:SetSize(320,20);frame.title:SetJustifyH("LEFT")
    frame.title:SetText("Orbs / Lost Memories")
    frame.runTab=button(frame,352,-12,116,"Run controls",function()showPage("run");UI.Refresh()end)
    frame.historyTab=button(frame,474,-12,110,"Run history",function()UI.ShowLog()end)
    selected(frame.runTab,true)
    inactiveControls()
    frame:SetScript("OnShow",function()UI.Refresh()end)
    -- Closing the window is the one place an armed review is cancelled; it
    -- also closes the history page and its copy view, and clears a target
    -- review.
    frame:SetScript("OnHide",function()
        editLimit(false);confirmNewRun=false;confirmAmount=nil;review.key=nil
        if logFrame then logFrame:Hide()end
    end)
    local elapsed=0;frame:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;UI.Refresh()end end)
    styled(frame,0.96)
    frame:Hide();UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusOrbPanel"
end
local RESULT_TONE={Confirmed={.55,.85,.55},["Not sent"]={.95,.5,.45},
    Unconfirmed={.95,.78,.35},Paused={.95,.78,.35}}
local function logRowTone(result)
    if result.confirmed then return RESULT_TONE.Confirmed end
    if result.refused then return RESULT_TONE["Not sent"] end
    if result.unresolved then return RESULT_TONE.Unconfirmed end
    return {.82,.84,.88}
end
local function logCell(fs,label,color)
    fs:SetText(label or "")
    if color then pcall(fs.SetTextColor,fs,color[1],color[2],color[3]) end
end
-- Character-safe shortening, so a cut never splits a multi-byte letter.
local function shorten(value,limit)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then
        return Nexus.LayoutMetrics.Truncate(value,limit)
    end
    return (Nexus.OrbHistory.Ellipsis(value,limit))
end
-- Two lines per Echo cell: the name, then the rarity word. The colour repeats
-- the rarity; it is never the only cue. A proposed replacement keeps its
-- marker on the rarity line, so shortening a long name cannot drop it. The
-- name is cut from the unescaped recorded text and its pipes are doubled
-- after the cut, so the cut never splits a letter or an escaped "||".
local CELL_LETTERS=30
local function logEchoText(cell)
    if not cell then return "" end
    local shown=(shorten(tostring(cell.text or ""),CELL_LETTERS):gsub("|","||"))
    if cell.recorded==false then return shown end
    return shown.."\n"..cell.rarity.label..(cell.proposed and " - proposed" or "")
end
local function logDetailText(details,history)
    if not details then return "Select an operation to see what was offered and why it was chosen." end
    local lines={}
    local function add(text) lines[#lines+1]=text end
    add("Operation "..tostring(details.ordinal)..": "..details.result.label)
    if details.offers then
        local parts={}
        for _,offer in ipairs(details.offers) do
            local mark=offer.confirmed and " [received]" or (offer.selected and " [selected]" or "")
            parts[#parts+1]=offer.full.." ("..offer.rarity.label..")"..mark
        end
        add("Offered: "..table.concat(parts,"   "))
    else
        add("Offered: "..tostring(details.offersNote))
    end
    add("Why: "..details.reason.full..(details.reason.detail and (" - "..details.reason.detail) or ""))
    if details.proposedSource then
        add("Proposed source: "..details.proposedSource.full
            .." ("..details.proposedSource.rarity.label..")"
            .."; no consumed source is recorded for this operation.")
    elseif details.consumed then
        add("Consumed source: "..details.consumed.full
            .." ("..details.consumed.rarity.label..")")
    end
    if details.eligibleSurplus~=nil then
        add("Eligible surplus at selection: "..tostring(details.eligibleSurplus)
            .." copy(ies). This is what the policy could draw from, not a count of copies sacrificed.")
    end
    if details.recycled then add("This source was the run's permitted recycle candidate.") end
    if details.note then add("Recorded note: "..details.note) end
    local t=details.technical
    add("Technical: serial "..tostring(t.serial or details.serial)
        .."; state "..tostring(t.state)
        .."; source "..tostring(t.sourceKey)
        .."; selected "..tostring(t.selectedKey).." ("..tostring(t.selectionKind)..")"
        .."; obtained "..tostring(t.obtained)
        ..(details.sinceStart and ("; "..string.format("%.1f",details.sinceStart).."s after the run started") or ""))
    return table.concat(lines,"\n")
end
-- The whole recorded row for its tooltip: complete names, the proposed
-- marker, the reason with its explanation, the result and any recorded note.
local function logRowTip(model,history)
    local lines={}
    local replacement=model.replacement
    lines[#lines+1]="Replaced Echo: "..model.source.full.." ("..model.source.rarity.label..")"
    if replacement.recorded~=false then
        lines[#lines+1]="Replacement: "..replacement.full.." ("..replacement.rarity.label..")"
            ..(replacement.proposed and " - selected, not received" or "")
    else
        lines[#lines+1]="Replacement: "..replacement.full
    end
    lines[#lines+1]="Why selected: "..model.reason.full
    if model.reason.detail then lines[#lines+1]=model.reason.detail end
    lines[#lines+1]="Result: "..model.result.label
    local note=model.entry and model.entry.reason
    if note then lines[#lines+1]="Recorded note: "..history.Display(note) end
    return lines
end
function refreshLog(force)
    if not logFrame or not logFrame:IsShown() then return end
    local history=logHistory()
    local run=logPageView(logPage)
    local key=logKey(run)
    local runKey=logRunKey(run)
    if logLabels.key~=runKey then logLabels.key,logLabels.byId=runKey,{} end
    local total=run and run.total or 0
    local pages=history.Pages(total,LOG_ROWS)
    if logPage>pages then
        logPage=pages;logSelection=nil;run=logPageView(logPage);key=logKey(run)
    end
    local header=history.Header(run)
    -- A shortened Wishlist name is complete in the header's tooltip.
    local function headerText(wishlist)
        return header.runLabel.." - "..wishlist.."\n"..header.status.."\n"..header.usage
            ..(header.increased and " (maximum was increased)" or "")
    end
    if header.empty then setFull(logFrame.header,header.status)
    else setFull(logFrame.header,headerText(header.wishlist),headerText(header.wishlistFull)) end
    local warnings={}
    if header.pending then warnings[#warnings+1]=header.pending end
    if header.truncated then warnings[#warnings+1]=header.truncated end
    logFrame.warning:SetText(table.concat(warnings,"  "))
    -- The run shown is marked by a bar as well as by its disabled button.
    enable(logFrame.current,logView~="current")
    enable(logFrame.previous,logView~="previous" and header.hasPrevious)
    selected(logFrame.current,logView=="current");selected(logFrame.previous,logView=="previous")
    local rows=history.Rows(run,logResolve)
    local selectedModel=nil
    for index,row in ipairs(logFrame.rows) do
        local model=rows[index]
        row.serial=model and model.serial or nil
        if model then
            row:Show()
            logCell(row.index,tostring(model.ordinal)..".")
            logCell(row.source,logEchoText(model.source),model.source.rarity.color)
            logCell(row.replacement,logEchoText(model.replacement),model.replacement.rarity.color)
            logCell(row.reason,model.reason.label)
            logCell(row.result,model.result.label,logRowTone(model.result))
            row.detail=model.reason.detail
            row.full=model.source.full.." ("..model.source.rarity.label..")"
                .."  ->  "..model.replacement.full
                ..(model.replacement.recorded~=false
                    and (" ("..model.replacement.rarity.label..")") or "")
            row.tip=logRowTip(model,history)
            row.icon:SetTexture(model.source.icon or "")
            row.resultIcon:SetTexture(model.replacement.icon or "")
            if logSelection and model.serial==logSelection then
                selectedModel=model;row.highlight:Show()
            else row.highlight:Hide() end
        else
            row:Hide();row.highlight:Hide();row.detail=nil;row.full=nil;row.tip=nil
            logCell(row.index,"");logCell(row.source,"");logCell(row.replacement,"")
            logCell(row.reason,"");logCell(row.result,"")
        end
    end
    if logSelection and not selectedModel then logSelection=nil end
    local details=selectedModel and history.Details(selectedModel.entry,logResolve,run and run.startedAt) or nil
    logFrame.details:SetText(logDetailText(details,history))
    -- The scrolled child is as tall as the measured details, and the footer
    -- sits below the viewport, so every line of a long operation is reachable.
    if Nexus.LayoutMetrics then
        logFrame.detailChild:SetHeight(Nexus.LayoutMetrics.WrapHeight(logFrame.details,680,LOG_BANDS.details.h))
    end
    logFrame.page:SetText(history.PageLabel(total,logPage,LOG_ROWS,run and run.truncated))
    enable(logFrame.prev,logPage>1)
    enable(logFrame.next,logPage<pages)
    -- The page the player is reading stays where it is; new operations are
    -- announced instead of moving them.
    local seen=logSeen[tostring(logView)..":"..tostring(run and run.runId)]
    if seen and total>seen and logPage<pages then
        logFrame.note:SetText((total-seen).." new operation(s) recorded. Use Next to read them.")
    else
        logFrame.note:SetText(history.SESSION_NOTE)
    end
    logSeen[tostring(logView)..":"..tostring(run and run.runId)]=total
    logRendered=key
end
-- Cheap bounded check: one header read with a single entry, never the whole
-- run. It re-renders only when the shown history actually changed.
local function logVisibleCheck()
    if not logFrame or not logFrame:IsShown() then return end
    local probe=Nexus.OrbRuntime.RunLog(logView,1,1)
    if logKey(probe)~=logRendered then refreshLog() end
end
local function logReportText(technical)
    local run=Nexus.OrbRuntime.RunLog(logView)
    local key=logKey(run)..(technical and "|tech" or "|plain")
    if logCopy.key~=key or not logCopy.text then
        -- The whole selected run is serialized only here, for the text the
        -- player asked for, and only when it changed since the last request.
        logCopy.key,logCopy.text=key,logHistory().Report(run,logResolve,technical)
    end
    return logCopy.text
end
-- The copy view is a panel over the history page of the same window. It
-- closes with that page and with the window.
local function ensureCopyView()
    if logCopyFrame then return logCopyFrame end
    local f=CreateFrame("Frame","NexusOrbHistoryCopy",logFrame);f:Hide()
    logCopyFrame=f
    f:SetSize(640,460);f:SetPoint("CENTER",logFrame,"CENTER",0,0)
    f:SetFrameLevel(logFrame:GetFrameLevel()+20);f:EnableMouse(true)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(.035,.04,.05,1)
    text(f,20,-14,600,22,"Copy this report")
    text(f,20,-36,600,32,"Press Select all, then copy with Ctrl+C. Opening this view sends nothing anywhere.")
    f.check=CreateFrame("CheckButton","NexusOrbHistoryTechnical",f,"UICheckButtonTemplate")
    f.check:SetSize(22,22);f.check:SetPoint("TOPLEFT",20,-68)
    f.checkLabel=text(f,46,-72,400,20,"Include technical details")
    f.check:SetScript("OnClick",function(self)
        -- GetChecked answers 1 or nil on this client, never a boolean.
        f.editBox:SetText(logReportText(self:GetChecked() and true or false))
        f.editBox:SetCursorPosition(0)
    end)
    f.scroll=CreateFrame("ScrollFrame","NexusOrbHistoryCopyScroll",f,"UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT",20,-96);f.scroll:SetSize(580,300)
    f.editBox=CreateFrame("EditBox",nil,f.scroll)
    f.editBox:SetMultiLine(true)
    -- The dedicated copy field is sized for the whole report: no name-limited
    -- popup, and nothing is silently cut.
    f.editBox:SetMaxLetters(0)
    f.editBox:SetAutoFocus(false)
    f.editBox:SetFontObject(ChatFontNormal)
    f.editBox:SetWidth(566)
    f.editBox:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
    f.scroll:SetScrollChild(f.editBox)
    button(f,20,-410,110,"Select all",function()f.editBox:SetFocus();f.editBox:HighlightText()end)
    button(f,140,-410,110,"Clear focus",function()f.editBox:ClearFocus()end)
    button(f,515,-410,85,"Close",function()f:Hide()end)
    f:SetScript("OnHide",function()f.editBox:ClearFocus()end)
    styled(f,0.98)
    return f
end
function ensureLog()
    if logFrame then return end
    logFrame=CreateFrame("Frame","NexusOrbRunLog",frame);logFrame:Hide()
    logFrame:SetSize(LOG_W,LOG_H);logFrame:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-LOG_TOP)
    logFrame:SetFrameLevel(frame:GetFrameLevel()+1);logFrame:EnableMouse(true)
    logFrame.current=button(logFrame,20,-4,120,"Current run",function()
        if logView=="current" then return end
        logView="current";logPage=1;logSelection=nil;refreshLog()
    end)
    logFrame.previous=button(logFrame,146,-4,120,"Previous run",function()
        if logView=="previous" then return end
        logView="previous";logPage=1;logSelection=nil;refreshLog()
    end)
    logFrame.header=text(logFrame,280,LOG_BANDS.header.y,460,LOG_BANDS.header.h)
    logFrame.warning=text(logFrame,20,LOG_BANDS.warning.y,720,LOG_BANDS.warning.h)
    if Nexus.LayoutMetrics then
        logFrame.headerHit=Nexus.LayoutMetrics.FullTextTooltip(logFrame.header,logFrame)
        logFrame.warningHit=Nexus.LayoutMetrics.FullTextTooltip(logFrame.warning,logFrame)
    end
    -- The heading row is a frame on the row origin, and each heading is one
    -- font string at its own column's x and width. Same numbers, one source.
    logFrame.columns=CreateFrame("Frame",nil,logFrame)
    logFrame.columns:SetSize(LOG_ROW_W,LOG_BANDS.headings.h)
    logFrame.columns:SetPoint("TOPLEFT",LOG_ROW_X,LOG_BANDS.headings.y)
    logFrame.columnHeadings={}
    for _,column in ipairs(LOG_COLUMNS) do
        local heading=text(logFrame.columns,column.x,0,column.w,LOG_BANDS.headings.h,column.label)
        heading:SetJustifyV("MIDDLE")
        logFrame.columnHeadings[column.key]=heading
    end
    logFrame.rows={}
    local rowH=LOG_BANDS.rows.h
    for i=1,LOG_ROWS do
        local row=CreateFrame("Button",nil,logFrame)
        row:SetSize(LOG_ROW_W,rowH);row:SetPoint("TOPLEFT",LOG_ROW_X,LOG_BANDS.rows.y-(i-1)*rowH)
        row:SetFrameLevel(logFrame:GetFrameLevel()+1)
        row.highlight=row:CreateTexture(nil,"BACKGROUND")
        row.highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.highlight:SetAllPoints(row);row.highlight:SetVertexColor(.16,.24,.29,.5)
        row.highlight:Hide()
        -- Pointer feedback: the client shows this layer only under the mouse.
        row.hover=row:CreateTexture(nil,"HIGHLIGHT")
        row.hover:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.hover:SetAllPoints(row);row.hover:SetVertexColor(.30,.40,.52,.18)
        row.separator=row:CreateTexture(nil,"BACKGROUND")
        row.separator:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.separator:SetSize(LOG_ROW_W,1);row.separator:SetPoint("BOTTOMLEFT",0,0)
        row.separator:SetVertexColor(.22,.24,.28,.55)
        local columns={}
        for _,column in ipairs(LOG_COLUMNS) do columns[column.key]=column end
        row.index=text(row,columns.index.x,-4,columns.index.w,18)
        row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(18,18)
        row.icon:SetPoint("TOPLEFT",columns.source.iconX,-4)
        row.source=text(row,columns.source.x,-4,columns.source.w,34)
        row.resultIcon=row:CreateTexture(nil,"ARTWORK");row.resultIcon:SetSize(18,18)
        row.resultIcon:SetPoint("TOPLEFT",columns.replacement.iconX,-4)
        row.replacement=text(row,columns.replacement.x,-4,columns.replacement.w,34)
        row.reason=text(row,columns.reason.x,-4,columns.reason.w,34)
        row.result=text(row,columns.result.x,-4,columns.result.w,34)
        row:SetScript("OnClick",function(self)
            -- Reading only: this selects a row for display and nothing else.
            if logSelection==self.serial then logSelection=nil
            else logSelection=self.serial end
            refreshLog()
        end)
        row:SetScript("OnEnter",function(self)
            -- A shortened cell keeps its whole recorded value here, wrapped.
            if not GameTooltip or (not self.detail and not self.full) then return end
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            local lines=self.tip
            if lines and lines[1] then
                GameTooltip:SetText(lines[1],1,1,1,1,true)
                for index=2,#lines do GameTooltip:AddLine(lines[index],.9,.9,.9,true) end
            else
                GameTooltip:SetText(self.full or "Why this Echo was selected",1,1,1,1,true)
                if self.detail then GameTooltip:AddLine(self.detail,1,1,1,true) end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide()
        logFrame.rows[i]=row
    end
    logFrame.detailScroll=CreateFrame("ScrollFrame","NexusOrbHistoryDetailScroll",
        logFrame,"UIPanelScrollFrameTemplate")
    logFrame.detailScroll:SetPoint("TOPLEFT",20,LOG_BANDS.details.y)
    logFrame.detailScroll:SetSize(700,LOG_BANDS.details.h)
    logFrame.detailChild=CreateFrame("Frame",nil,logFrame.detailScroll)
    logFrame.detailChild:SetSize(680,LOG_BANDS.details.h)
    logFrame.details=text(logFrame.detailChild,0,0,680,400)
    logFrame.detailScroll:SetScrollChild(logFrame.detailChild)
    local footerY=LOG_BANDS.footer.y
    logFrame.page=text(logFrame,20,footerY-2,300,22)
    logFrame.prev=button(logFrame,320,footerY,85,"Previous",function()
        if logPage<=1 then return end
        logPage=logPage-1;logSelection=nil;refreshLog()
    end)
    logFrame.next=button(logFrame,410,footerY,85,"Next",function()
        logPage=logPage+1;logSelection=nil;refreshLog()
    end)
    button(logFrame,500,footerY,115,"Copy report",function()
        local view=ensureCopyView()
        view:Show()
        view.editBox:SetText(logReportText(view.check:GetChecked() and true or false))
        view.editBox:SetCursorPosition(0)
    end)
    -- Close closes the whole Orb window, like Escape.
    button(logFrame,625,footerY,95,"Close",function()frame:Hide()end)
    logFrame.note=text(logFrame,20,LOG_BANDS.note.y,720,LOG_BANDS.note.h,Nexus.OrbHistory and Nexus.OrbHistory.SESSION_NOTE or "")
    logFrame:SetScript("OnShow",function()refreshLog()end)
    logFrame:SetScript("OnHide",function() if logCopyFrame then logCopyFrame:Hide() end end)
    local elapsed=0
    logFrame:SetScript("OnUpdate",function(_,dt)
        -- Nothing runs while hidden; visible, this is one bounded header read.
        elapsed=elapsed+(dt or 0);if elapsed>=.5 then elapsed=0;logVisibleCheck() end
    end)
    if Nexus.Theme and Nexus.Theme.StyleTree then Nexus.Theme.StyleTree(logFrame) end
end
UI.LOG_BANDS,UI.LOG_SIZE,UI.RUN_SIZE={},{w=LOG_W,h=LOG_H,top=LOG_TOP},{w=RUN_W,h=RUN_H,advanced=RUN_H_ADVANCED}
for key,band in pairs(LOG_BANDS)do UI.LOG_BANDS[key]={y=band.y,h=band.h}end
-- The page shown now: "run" or "history".
function UI.Page() return page end
-- Opens the window on its history page. Reading only.
function UI.ShowLog()
    ensure();showPage("history");frame:Show();logFrame:Show();refreshLog();return logFrame
end

-- 035: Continue with an unconfirmed outcome. Reading and opening this window send nothing.
-- Check starts the strict read-only check; Continue, enabled only for the current ready token,
-- is the player's explicit confirmation; Cancel and closing the window cancel a check. The
-- text is the runtime's own (what was observed, what Continue does, what stays uncertain).
local contFrame
local function contRefresh()
    if not contFrame or not contFrame:IsShown()then return end
    local v=Nexus.OrbRuntime.ContinueView()
    contFrame.title:SetText((v.eligible==true or v.stage=="checking" or v.stage=="ready")
        and "Continue with an unconfirmed Orb outcome" or "Unresolved Orb action")
    contFrame.token=v.token
    contFrame.body:SetText(v.text or "")
    local idle=v.stage=="idle" or v.stage=="refused"
    local active=v.stage=="checking" or v.stage=="ready"
    enable(contFrame.check,v.eligible==true and idle)
    enable(contFrame.go,v.stage=="ready" and v.token~=nil)
    enable(contFrame.cancel,active)
    contFrame.state:SetText(v.stage=="ready" and "Ready: waiting for your confirmation"
        or v.stage=="checking" and "Checking the game's current state..."
        or v.stage=="done" and "Continued"
        or v.stage=="refused" and "Not continued"
        or (v.eligible and "Not checked yet" or "Not available"))
    -- A record restored after a reload: its saved facts are kept, but this
    -- session's history has none of the steps before the reload. Said only
    -- when the session history really is empty (a bounded header read).
    local log=v.explanation==true and Nexus.OrbRuntime.RunLog("current",1,0) or nil
    contFrame.history:SetText(log and log.runId==nil and Nexus.OrbHistory and Nexus.OrbHistory.RELOAD_CLEARED_NOTE or "")
end
local function ensureContinue()
    if contFrame then return end
    local f=CreateFrame("Frame","NexusOrbContinue",UIParent);contFrame=f;f:Hide()
    f:SetSize(580,330);f:SetPoint("CENTER",UIParent,"CENTER",30,10)
    f:SetFrameStrata("DIALOG");f:SetFrameLevel(50);f:EnableMouse(true);f:SetMovable(true);f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(self)self:StartMoving()end)
    f:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(.035,.04,.05,1)
    f.title=text(f,20,-14,540,22,"Unresolved Orb action")
    f.state=text(f,20,-40,540,20)
    f.body=text(f,20,-66,540,170)
    f.notice=text(f,20,-240,540,22)
    -- Fixed boxes; text longer than its box is complete in a tooltip.
    if Nexus.LayoutMetrics then
        f.bodyHit=Nexus.LayoutMetrics.FullTextTooltip(f.body,f)
        f.noticeHit=Nexus.LayoutMetrics.FullTextTooltip(f.notice,f)
    end
    f.check=button(f,20,-282,150,"Check the game's state",function()
        local ok,why=Nexus.OrbRuntime.ContinueBegin()
        f.notice:SetText(ok and "" or Nexus.OrbRuntime.ContinueReason(why))
        contRefresh()
    end)
    f.go=button(f,180,-282,130,"Continue",function()
        -- The token this window showed, never a newer one: a stale click is refused.
        local ok,why=Nexus.OrbRuntime.ContinueConfirm(f.token)
        f.notice:SetText(ok and "" or Nexus.OrbRuntime.ContinueReason(why))
        UI.Refresh();contRefresh()
    end)
    f.cancel=button(f,320,-282,90,"Cancel",function()
        Nexus.OrbRuntime.ContinueCancel();f.notice:SetText("");contRefresh()
    end)
    button(f,480,-282,80,"Close",function()f:Hide()end)
    f.history=text(f,20,-308,540,18)
    if Nexus.LayoutMetrics then f.historyHit=Nexus.LayoutMetrics.FullTextTooltip(f.history,f) end
    f:SetScript("OnShow",function()contRefresh()end)
    -- Closing the window (also with Escape) cancels a check: no token outlives its window.
    f:SetScript("OnHide",function()
        local v=Nexus.OrbRuntime.ContinueView()
        if v.stage=="checking" or v.stage=="ready" then Nexus.OrbRuntime.ContinueCancel()end
    end)
    local elapsed=0
    f:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;contRefresh()end end)
    styled(f,0.96)
    UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusOrbContinue"
end
function UI.ShowContinue()
    ensureContinue();contFrame:Show();contRefresh();return contFrame
end
do
    local refreshPanel=UI.Refresh
    function UI.Refresh(...)
        local perf=Nexus.Performance
        if perf and type(perf.MeasureDiagnostic)=="function" then return perf.MeasureDiagnostic("orb.panel",refreshPanel,...) end
        return refreshPanel(...)
    end
end
-- Opens the window on its run page.
function UI.Show()ensure();showPage("run");frame:Show();UI.Refresh();return frame end
function UI.Hide()if frame then frame:Hide()end end

-- Compact main-panel controls remain usable when the detailed window is hidden.
-- The ticker reads compact state only. It never advances an operation.
function UI.AttachMainPanel(parent)
    if parent._orbControls then return parent._orbControls end
    local f=CreateFrame("Frame",nil,parent);parent._orbControls=f
    f:SetPoint("TOPLEFT",parent,"BOTTOMLEFT",0,-2);f:SetSize(parent:GetWidth(),100);f:SetFrameLevel(parent:GetFrameLevel()+3)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});f:SetBackdropColor(.035,.04,.05,.95)
    f.summary=text(f,8,-6,252,52)
    -- Three lines; a shortened name is complete in the tooltip.
    if Nexus.LayoutMetrics then f.summaryHit=Nexus.LayoutMetrics.FullTextTooltip(f.summary,f) end
    -- The legacy one-button entry (Pause while running, Resume while paused):
    -- hidden, so it cannot be clicked, and kept for programmatic callers with
    -- the same gates as the fixed buttons below.
    f.primary=button(f,8,-65,87,"Pause",function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if s and s.running then Nexus.OrbRuntime.Pause()
        elseif s and s.canResume and not changedTarget(s.resumeTarget) then Nexus.OrbRuntime.Resume()end
        f.refresh()
    end)
    f.primary:Hide()
    -- Separate fixed Pause and Resume, as in the mini panel: a repeated press
    -- of one never becomes the other. A changed target resumes only after the
    -- review in the Orb window (Details).
    f.pause=button(f,8,-65,55,"Pause",function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if s and s.running then Nexus.OrbRuntime.Pause()end
        f.refresh()
    end)
    f.resume=button(f,69,-65,62,"Resume",function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if s and not s.running and s.canResume and not changedTarget(s.resumeTarget) then Nexus.OrbRuntime.Resume()end
        f.refresh()
    end)
    f.stop=button(f,137,-65,48,"Stop",function()Nexus.OrbRuntime.Stop();f.refresh()end)
    f.details=button(f,191,-65,69,"Details",function()UI.Show()end)
    -- One line of the conservative 7 px model; the name is cut on a character
    -- boundary, then pipes are doubled so they show as written.
    local STRIP_CHARS=math.floor(252/7)
    local function stripLine(v)
        local cut=v
        if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then cut=Nexus.LayoutMetrics.Truncate(v,STRIP_CHARS)
        elseif #v>STRIP_CHARS then cut=v:sub(1,STRIP_CHARS-3):gsub("[\192-\255][\128-\191]*$","").."..." end
        return (cut:gsub("|","||")),(v:gsub("|","||"))
    end
    f.refresh=function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if not s then f:Hide();return end
        f:Show()
        local usage="Orbs used: "..s.spent.." / "..s.limit.." approved"
        local second=s.reserved>0 and (s.reserved..(s.reserved==1 and " Orb" or " Orbs").." pending, not confirmed yet")
            or (s.remaining~=nil and (s.remaining.." target copies remaining")or "Target data unavailable")
        local third=phases[s.state]or s.state
        local what,instruction
        if s.state=="PAUSED" then what,instruction=compactTarget(s.resumeTarget) end
        if instruction then third=instruction end
        local shown,full=stripLine(second)
        -- While paused, the target takes the second line; a pending Orb then
        -- stays on the third.
        if what then
            shown,full=stripLine(what)
            if s.reserved>0 and third=="Paused" then third="Paused - "..s.reserved..(s.reserved==1 and " Orb" or " Orbs").." pending" end
        end
        setFull(f.summary,usage.."\n"..shown.."\n"..third,usage.."\n"..full.."\n"..third)
        local resumable=not s.running and s.canResume and not changedTarget(s.resumeTarget)
        f.primary:SetText(s.running and "Pause"or "Resume");enable(f.primary,s.running or resumable)
        enable(f.pause,s.running);enable(f.resume,resumable)
        enable(f.stop,s.running or s.pending or s.state=="PAUSED"or s.state=="LIMIT")
    end
    local elapsed=0
    parent:HookScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;f.refresh()end end)
    f.refresh();return f
end

-- Optional compact run status. NexusOrbMini is a small movable window that
-- only the player opens (UI.ShowMini, or Mini panel on the run page). It is
-- created on first use, is hidden in every new session and keeps its place
-- until a reload; nothing about it is saved. While it is shown its only run
-- read is OrbRuntime.CompactStatus, four times a second, made only once local
-- saved data is restored (the run page's own Restoring check); hidden, it
-- does no work. Its actions are Pause, Resume and Stop, each gated again on a
-- fresh read at the click (the runtime keeps its own final checks), and Open
-- Orbs, which is UI.Show. It never starts, prepares, confirms, changes a
-- maximum or advances a run. Close and Escape only hide it: an approved run
-- keeps running.
local mini,miniRefresh
local miniBusy,miniFailing=false,false
-- The outcome of the panel's last action and the state it was shown for.
local miniNotice={}
local miniSeen={}
local MINI_W,MINI_H,MINI_PAD,MINI_LINE=356,196,12,17
local MINI_TEXT_W=MINI_W-2*MINI_PAD
-- A shown line holds at most this many characters: one line of the
-- conservative 7 px model (docs/UI_TEXT_LAYOUT.md). A longer value is cut on
-- a character boundary and is complete in the line's tooltip.
local MINI_CHARS=math.floor(MINI_TEXT_W/7)
-- Line tops, top to bottom; every line is one MINI_LINE box.
local MINI_Y={state=-30,reason=-48,usage=-68,pending=-86,missing=-104,notice=-124,note=-142}
local MINI_BUTTON_Y=-164
-- Counts are whole numbers from 0 to the runtime's own bound (the default of
-- its integer()); anything else is unavailable, never 0.
local MINI_MAX_COUNT=1000000
local MINI_ACTIONS={pause="Pause",resume="Resume",stop="Stop"}
local MINI_UNREAD={missing="The Orb runtime is not loaded.",error="Reading the run status failed.",
    malformed="The run status has an unexpected form."}
local MINI_UNREAD_TEXT="Could not read the run. Open Orbs for details."
local function miniCount(v)
    if type(v)=="number" and v>=0 and v<=MINI_MAX_COUNT and v==math.floor(v) then return v==0 and 0 or v end
    return nil
end
local function miniNumber(v) return string.format("%d",v) end
-- One line of display text: control characters become spaces, a value longer
-- than the line is cut on a character boundary ("..." included), and pipes
-- are doubled after the cut so they show as written. Returns the shown text
-- and the complete text.
local function miniText(value)
    local v=tostring(value or ""):gsub("%c"," ")
    local cut=v
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then cut=Nexus.LayoutMetrics.Truncate(v,MINI_CHARS)
    elseif #v>MINI_CHARS then cut=v:sub(1,MINI_CHARS-3):gsub("[\192-\255][\128-\191]*$","").."..." end
    return (cut:gsub("|","||")),(v:gsub("|","||"))
end
-- One compact read: what the panel shows and offers. kind is "run" (a
-- well-formed status), "none" (no run was approved in this session),
-- "loading" (local saved data is not restored yet), "missing" (no runtime),
-- "error" (the read failed) or "malformed". A run needs a text state, boolean
-- flags and whole-number counts; remaining (the rolled target copies still
-- missing) and the reason may be absent.
local function miniView()
    -- Before saved data is restored the runtime cannot know of a run or of a
    -- result restored from it, so it is not asked and nothing reads "none".
    -- This is the run page's Restoring check: a scalar read that pumps and
    -- admits nothing.
    local okReady,ready=true,nil
    if type(Nexus.StartupStatus)=="function" then okReady,ready=pcall(Nexus.StartupStatus) end
    if not okReady then return {kind="error",error=ready} end
    if type(ready)~="table" or not ready.coreReady then return {kind="loading"} end
    local runtime=Nexus.OrbRuntime
    if type(runtime)~="table" or type(runtime.CompactStatus)~="function" then return {kind="missing"} end
    local ok,s=pcall(runtime.CompactStatus)
    if not ok then return {kind="error",error=s} end
    if s==nil then return {kind="none"} end
    if type(s)~="table" then return {kind="malformed"} end
    local v={kind="run",spent=miniCount(s.spent),limit=miniCount(s.limit),reserved=miniCount(s.reserved),
        remaining=miniCount(s.remaining),state=type(s.state)=="string" and s.state or nil,
        reason=type(s.reason)=="string" and s.reason or nil}
    for _,key in ipairs({"running","pending","canResume"}) do
        if type(s[key])=="boolean" then v[key]=s[key] end
    end
    -- What a Resume would act on (optional; absent offers no extra gate).
    local t=s.resumeTarget
    if type(t)=="table" and type(t.kind)=="string" then
        v.target={kind=t.kind,name=type(t.name)=="string" and t.name or nil}
    end
    if not (v.state and v.spent and v.limit and v.reserved) or v.running==nil or v.pending==nil
        or v.canResume==nil then v.kind="malformed" end
    return v
end
-- Pause while running; Resume only for a paused run the runtime offers to
-- resume (an unknown state never offers it) and never for a changed target,
-- which is reviewed and resumed in the Orb window; Stop as the main panel
-- offers it. Anything that is not a well-formed run offers nothing.
local function miniGates(v)
    if v.kind~="run" then return false,false,false end
    return v.running,v.state=="PAUSED" and v.canResume and not v.running and not changedTarget(v.target),
        v.running or v.pending or v.state=="PAUSED" or v.state=="LIMIT"
end
local function miniStateText(v)
    if v.kind=="none" then return "No approved Orb run" end
    if v.kind=="loading" then return "Run status loading..." end
    if v.kind~="run" then return "Run status unavailable" end
    local label=phases[v.state] or ("Unknown state: "..v.state)
    if v.running then return "Running - "..label end
    if v.state=="PAUSED" and changedTarget(v.target) then return "Paused - review the new target in Open Orbs" end
    if v.state=="PAUSED" and v.target and v.target.kind=="unavailable" then return "Paused - the assigned Wishlist is not ready" end
    -- Paused, and Resume is not offered: an earlier submitted action (restored
    -- after a reload, already chosen, or for a changed assignment) must settle.
    if v.state=="PAUSED" and not v.canResume then return "Paused - a pending result must settle first" end
    return label
end
local function miniReason(v)
    if v.kind=="none" then return miniText("Open Orbs to review a maximum and start a run.") end
    if v.kind=="loading" then return miniText("Reading local saved data.") end
    if v.kind~="run" then
        local _,detail=miniText(MINI_UNREAD[v.kind]..(v.error~=nil and (" "..tostring(v.error)) or ""))
        return MINI_UNREAD_TEXT,MINI_UNREAD_TEXT.." "..detail
    end
    -- Paused: the line names what Resume would act on; the run's reason stays
    -- complete in the tooltip.
    local what=v.state=="PAUSED" and compactTarget(v.target) or nil
    if what then
        local shown,full=miniText(what)
        local _,reason=miniText(truthful(v.reason))
        return shown,reason~="" and (full..". "..reason) or full
    end
    return miniText(truthful(v.reason))
end
local function miniUsage(v)
    if v.kind=="none" then return "Orbs used: no run approved this session" end
    local spent,limit=v.spent and miniNumber(v.spent),v.limit and miniNumber(v.limit)
    if spent and limit then return "Orbs used: "..spent.." of "..limit.." approved" end
    if limit then return "Orbs used: unavailable (approved limit "..limit..")" end
    if spent then return "Orbs used: "..spent.." (approved limit unavailable)" end
    return "Orbs used and approved limit: unavailable"
end
local function miniPending(v)
    if v.kind=="none" then return "Pending: none" end
    if v.reserved==nil or v.pending==nil then return "Pending: unavailable" end
    if v.reserved>0 then
        return "Pending: "..miniNumber(v.reserved)..(v.reserved==1 and " Orb" or " Orbs").." requested, not confirmed yet"
    end
    return v.pending and "Pending: the last Orb action is not settled" or "Pending: none"
end
-- Copies, not families: CompactStatus.remaining is the run's rolled target
-- copies still missing at its latest check. Absent is unavailable, never 0.
local function miniMissing(v)
    return "Rolled target copies missing: "..(v.remaining and miniNumber(v.remaining) or "unavailable")
end
local function miniKey(v)
    return table.concat({v.kind,tostring(v.state),tostring(v.running),tostring(v.pending),tostring(v.canResume),
        tostring(v.target and v.target.kind)},"|")
end
-- A new UI size moves the panel back inside the UI. The panel is smaller
-- than any UI this client supports (FitToScreen treats less than 640x480 as
-- implausible), so it keeps its scale; the client's own clamping keeps a drag
-- on screen. Two size reads per refresh; nothing moves otherwise.
local function clampMini()
    if not UIParent then return end
    local sw,sh=tonumber(UIParent:GetWidth()),tonumber(UIParent:GetHeight())
    if not (sw and sh) or (miniSeen.sw==sw and miniSeen.sh==sh) then return end
    local left,top=mini:GetLeft(),mini:GetTop()
    local w,h=tonumber(mini:GetWidth()),tonumber(mini:GetHeight())
    if not (left and top and w and h) then return end
    miniSeen.sw,miniSeen.sh=sw,sh
    local s=tonumber(mini:GetScale()) or 1
    local x,y=left*s,top*s
    local cx=math.max(0,math.min(x,sw-w*s))
    local cy=math.min(sh,math.max(y,h*s))
    if math.abs(cx-x)>0.5 or math.abs(cy-y)>0.5 then
        mini:ClearAllPoints();mini:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",cx/s,cy/s)
    end
end
-- Returns the read error, if the read failed, so it can be reported once.
local function miniRender()
    local v=miniView()
    setFull(mini.state,miniText(miniStateText(v)))
    setFull(mini.reason,miniReason(v))
    setFull(mini.usage,miniText(miniUsage(v)))
    setFull(mini.pending,miniText(miniPending(v)))
    setFull(mini.missing,miniText(miniMissing(v)))
    -- An outcome belongs to the state it was shown for; a later change of that
    -- state retires it, so it never describes a newer state.
    local key=miniKey(v)
    if miniNotice.text~=nil then
        if miniNotice.key==nil then miniNotice.key=key
        elseif miniNotice.key~=key then miniNotice.text,miniNotice.key=nil,nil end
    end
    setFull(mini.notice,miniText(miniNotice.text))
    local pause,resume,stop=miniGates(v)
    enable(mini.pause,pause and not miniBusy);enable(mini.resume,resume and not miniBusy)
    enable(mini.stop,stop and not miniBusy)
    clampMini()
    if v.kind=="error" then return tostring(v.error) end
end
-- A failure goes to the client's error handler, which may itself raise.
local function miniReport(failure)
    local handler=type(geterrorhandler)=="function" and geterrorhandler() or nil
    if type(handler)=="function" then pcall(handler,failure) end
end
miniRefresh=function()
    if not (mini and mini:IsShown()) then return end
    local ok,failure=pcall(miniRender)
    if ok and failure==nil then miniFailing=false;return end
    if not ok then
        -- Fail closed: nothing shown or offered may rest on an earlier read.
        enable(mini.pause,false);enable(mini.resume,false);enable(mini.stop,false)
        local _,detail=miniText(failure)
        setFull(mini.state,"Run status unavailable")
        setFull(mini.reason,MINI_UNREAD_TEXT,MINI_UNREAD_TEXT.." "..detail)
        setFull(mini.usage,"Orbs used and approved limit: unavailable")
        setFull(mini.pending,"Pending: unavailable")
        setFull(mini.missing,"Rolled target copies missing: unavailable")
    end
    -- Reported once per failure, not four times a second.
    if miniFailing then return end
    miniFailing=true
    miniReport(failure)
end
-- key, when given, is the state the outcome was worded from; otherwise the
-- next refresh binds it to the state it shows.
local function miniSay(message,key) miniNotice.text,miniNotice.key=message,key end
local function miniRefusal(kind,v)
    local unread=v.kind~="run" and v.kind~="none"
    if kind=="pause" then
        return unread and "Not paused: the run status could not be read." or "Not paused: the run is not running."
    elseif kind=="resume" then
        if unread then return "Not resumed: the run status could not be read." end
        if v.kind=="none" then return "Not resumed: there is no approved run." end
        if v.running then return "Not resumed: the run is already running." end
        -- One whole mini line (MINI_CHARS): the reason and the button to use.
        if v.state=="PAUSED" and changedTarget(v.target) then return "Not resumed: review the new target in Open Orbs" end
        if v.state=="PAUSED" then return "Not resumed: a pending result must settle." end
        return "Not resumed: only a paused run can resume."
    end
    if unread then return "Not stopped: the run status could not be read." end
    if v.kind=="none" then return "Not stopped: there is no approved run." end
    return "Not stopped: no run is active or pending."
end
-- Resume answers true even when its own first step at once paused or ended
-- the run again (an Echo board open, no Orbs left), so its success is worded
-- from the read taken after it (after): "Resumed" only for a running run.
local function miniOutcome(kind,done,why,after)
    if kind=="pause" then return done and "Paused." or "Not paused: the run was not running." end
    if not done then
        return (kind=="resume" and "Not resumed: " or "Not stopped: ")..(truthful(why) or "Orb mode refused it.")
    end
    if kind=="stop" then return "Stopped." end
    if not (after and after.kind=="run") then return "Resume accepted." end
    return after.running and "Resumed with the same approved maximum." or "Resume accepted; the run is not running now."
end
-- One action at a time. The click reads again and acts only if that read
-- offers the action; the runtime then applies its own final checks.
local function miniAct(kind)
    if miniBusy or not mini then return end
    miniBusy=true
    -- While it runs no control reads as available, so a nested click or
    -- refresh cannot act on the read taken before it.
    enable(mini.pause,false);enable(mini.resume,false);enable(mini.stop,false)
    local ok,err=pcall(function()
        local v=miniView()
        local pause,resume,stop=miniGates(v)
        local allowed=(kind=="pause" and pause) or (kind=="resume" and resume) or (kind=="stop" and stop)
        if not allowed then miniSay(miniRefusal(kind,v));return end
        local done,why=Nexus.OrbRuntime[MINI_ACTIONS[kind]]()
        -- An accepted Resume is worded from a fresh read and belongs to the
        -- state that read shows.
        local after=kind=="resume" and done and miniView() or nil
        miniSay(miniOutcome(kind,done,why,after),after and miniKey(after))
    end)
    miniBusy=false
    -- A short notice here; the error itself goes to the error handler, once
    -- for this action. The refresh then offers only what a new read allows.
    if not ok then miniSay(MINI_ACTIONS[kind].." failed: an error occurred.") end
    miniRefresh()
    if not ok then miniReport(err) end
end
local function miniTip(widget,tip)
    widget:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(tip,1,1,1,1,true);GameTooltip:Show()
    end)
    widget:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
end
-- One line and its hover area. The line never wraps: text the client draws
-- wider than the box, even within MINI_CHARS, is shortened there instead of
-- spilling out of its MINI_LINE box. Hovering a line that holds text always
-- shows its complete text (flattened and escaped, as shown) and, when given,
-- what the line means.
local function miniLine(f,key,about)
    local fs=text(f,MINI_PAD,MINI_Y[key],MINI_TEXT_W,MINI_LINE)
    if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(fs,nil,MINI_LINE) end
    local hit=CreateFrame("Frame",nil,f);hit:SetAllPoints(fs);hit:EnableMouse(true)
    hit:SetScript("OnEnter",function(self)
        local full=fs._nexusFullText or fs:GetText() or ""
        if not (GameTooltip and (full~="" or about)) then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText(full,1,1,1,1,true)
        if about then GameTooltip:AddLine(about,.9,.9,.9,true) end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave",function()if GameTooltip then GameTooltip:Hide()end end)
    f[key],f[key.."Hit"]=fs,hit
end
local function ensureMini()
    if mini then return mini end
    local f=CreateFrame("Frame","NexusOrbMini",UIParent);f:Hide()
    f:SetSize(MINI_W,MINI_H);f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",16,-150)
    -- Below the Orb window and Help (DIALOG): a status panel, not a dialog.
    f:SetFrameStrata("HIGH");f:SetFrameLevel(20);f:EnableMouse(true);f:SetMovable(true);f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(.035,.04,.05,1)
    f.title=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f.title:SetPoint("TOPLEFT",MINI_PAD,-9);f.title:SetSize(262,18);f.title:SetJustifyH("LEFT")
    f.title:SetText("Orb run status")
    -- The title bar moves the panel. Its place lasts for this session only:
    -- the client is asked not to keep it in its layout cache.
    f.drag=CreateFrame("Frame",nil,f);f.drag:SetPoint("TOPLEFT",6,-4);f.drag:SetSize(274,24)
    f.drag:SetFrameLevel(f:GetFrameLevel()+1);f.drag:EnableMouse(true);f.drag:RegisterForDrag("LeftButton")
    f.drag:SetScript("OnDragStart",function()f:StartMoving()end)
    f.drag:SetScript("OnDragStop",function()
        f:StopMovingOrSizing()
        if f.SetUserPlaced then pcall(f.SetUserPlaced,f,false) end
    end)
    miniTip(f.drag,"Drag to move this panel. It stays where you put it until you reload; nothing is saved.")
    f.close=button(f,MINI_W-MINI_PAD-58,-7,58,"Close",function()f:Hide()end);f.close:SetHeight(20)
    miniTip(f.close,"Hides this panel only. An approved run keeps running: use Pause or Stop. Mini panel in the Orb window shows it again.")
    miniLine(f,"state");miniLine(f,"reason")
    miniLine(f,"usage","Orbs this run has used, against the maximum approved when it started. The maximum cannot change during a run. Unavailable means it could not be read; it is not 0.")
    miniLine(f,"pending","An Orb requested whose spend is not confirmed yet, or an Orb action whose result has not settled. It counts against the approved maximum until it settles.")
    miniLine(f,"missing","Copies, not Echo families: the rolled target copies this run still needed at its latest check. Locked targets are not counted, because Orbs cannot change locked Echoes. Unavailable is not 0, and 0 does not mean the whole build is complete.")
    miniLine(f,"notice");miniLine(f,"note")
    f.note:SetText("Closing this panel does not stop the run.")
    -- Pause and Resume are separate buttons in fixed places, so a repeated
    -- press of one can never become the other.
    f.pause=button(f,MINI_PAD,MINI_BUTTON_Y,66,"Pause",function()miniAct("pause")end)
    f.resume=button(f,MINI_PAD+72,MINI_BUTTON_Y,74,"Resume",function()miniAct("resume")end)
    f.stop=button(f,MINI_PAD+152,MINI_BUTTON_Y,60,"Stop",function()miniAct("stop")end)
    f.open=button(f,MINI_W-MINI_PAD-96,MINI_BUTTON_Y,96,"Open Orbs",function()UI.Show()end)
    miniTip(f.pause,"Pause holds the run before its next Orb. An Orb already requested cannot be undone. Offered only while the run is running.")
    miniTip(f.resume,"Resume continues this paused run with the same approved maximum; its usage is not reset. It is not offered while an earlier action must settle first: one restored after a reload, one whose offer was already chosen, or one for a changed assignment. After a target change, review the new target in Open Orbs and resume there. Orb mode checks again before it continues.")
    miniTip(f.stop,"Stop ends this run: no further Orb is spent. An action already submitted may still finish; resolve its offer in the game.")
    miniTip(f.open,"Opens the full Orb window. Opening it starts, resumes and spends nothing.")
    f.pause:Disable();f.resume:Disable();f.stop:Disable()
    local elapsed=0
    f:SetScript("OnShow",function()elapsed=0;miniRefresh()end)
    -- An outcome is not carried into the next opening.
    f:SetScript("OnHide",function()miniNotice.text,miniNotice.key=nil,nil end)
    f:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;miniRefresh()end end)
    styled(f,0.94)
    UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusOrbMini"
    mini=f
    return f
end
-- Shows the compact run status. Reading only; repeated calls reuse it.
function UI.ShowMini()
    ensureMini()
    if mini:IsShown() then miniRefresh() else mini:Show() end
    return mini
end
-- Hides it, as Close and Escape do. An approved run keeps running.
function UI.HideMini() if mini then mini:Hide() end end
function UI.MiniShown() return mini~=nil and mini:IsShown() and true or false end
