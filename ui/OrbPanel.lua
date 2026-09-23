-- One assigned target and one explicit Start. Reading either view is passive.
Nexus=Nexus or {}
local UI={};Nexus.OrbPanel=UI
local frame,advanced=nil,false
local sourcePage=1
local CLOSE_NOTICE="Closing the window does not stop an approved run. Use Pause or Stop."
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
-- Legacy EditBox has no Button Enable/Disable API. Lock both input routes and
-- release focus so an approved maximum cannot remain editable during a run.
local function editLimit(on)
    local e=frame.limit;e.editable=on==true
    e:EnableMouse(e.editable);e:EnableKeyboard(e.editable);e:SetAlpha(e.editable and 1 or .5)
    if not e.editable then e:ClearFocus()end
end
local function inactiveControls()
    editLimit(false)
    for _,b in ipairs(frame.mutations)do b:Disable()end
    frame.advanced:Hide();frame:SetHeight(445)
end
local function name(s)return tostring(s or ""):gsub("|","||"):gsub("[%c]"," "):sub(1,100)end
local function notify(ok,err)
    if frame then frame.notice:SetText(err or (ok and "" or "No change."))end
    UI.Refresh()
end
local function primary(limit)
    local s=Nexus.OrbRuntime.Status()
    if s.running then return Nexus.OrbRuntime.Pause()end
    if s.state=="PAUSED" then return Nexus.OrbRuntime.Resume()end
    return Nexus.OrbRuntime.Start(limit)
end
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

-- Read-only Orb history window. It renders one fixed row pool, reads only the
-- page it shows plus the operation whose details are open, and performs no Orb
-- action: opening, paging, selecting and copying spend nothing, select nothing
-- and write nothing. All presentation lives in Nexus.OrbHistory, which reads
-- recorded fields only.
local LOG_ROWS=8
local logFrame,logView,logPage=nil,"current",1
local logSelection=nil
local logCopyFrame=nil
local logCopy={key=nil,text=nil}
local logSeen={}
local logRendered=nil
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
    -- The revision changes on every recorded event, so a cached copy cannot
    -- outlive the history it was made from.
    return table.concat({tostring(run.which),tostring(run.runId),
        tostring(run.revision),tostring(run.total)},"|")
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
local function refresh()
    if not frame or not frame:IsShown()then return end
    local ready=Nexus.StartupStatus and Nexus.StartupStatus()
    if not ready or not ready.coreReady then
        frame.plan:SetText("Restoring assigned Wishlist...")
        frame.status:SetText("Reading local saved data. Shared-library loading is not required.")
        frame.balance:SetText("Orb balance: loading")
        frame.targets:SetText("");frame.permanent:SetText("");frame.usage:SetText("")
        inactiveControls()
        return
    end
    -- One display read per refresh; the source list is prepared only for Advanced.
    -- The snapshot authorizes nothing: Start, Resume and every spend read again.
    local s=Nexus.OrbRuntime.Status(advanced);frame.snapshot=s
    local a=s.assignment or {};local busy=s.running or s.pending or s.state=="PAUSED" or s.state=="LIMIT"
    frame.plan:SetText(a.state=="restoring" and "Restoring assigned Wishlist..." or ("Assigned Wishlist: "..name(a.name or "none")))
    frame.targets:SetText(s.progress and (s.progress.rolledMissing.." rolled target copies still missing")
        or a.note or "Assign a Wishlist through My Builds to begin.")
    local permanent=s.progress and s.progress.permanentMissing
    frame.permanent:SetText(permanent and permanent>0 and (permanent.." permanent target copies remain. Orbs cannot change permanent slots.")or "")
    frame.balance:SetText(s.charges~=nil and ("Confirmed Orb balance: "..s.charges)
        or ("Orb balance: "..(s.balanceState or "unknown")..". "..(s.balanceReason or "")))
    if s.state~="FINISHED" then confirmNewRun=false end
    frame.start:SetText(s.running and "Pause" or (s.state=="PAUSED" and "Resume"
        or (s.state=="FINISHED" and (confirmNewRun and "Confirm new run" or "Start new run") or "Start")))
    editLimit(not busy)
    if not frame.limit:HasFocus()then frame.limit:SetText(tostring(busy and s.limit or s.config.maxOrbs))end
    frame.usage:SetText("Orbs used: "..s.spent.." / "..((busy or s.limit>0)and s.limit or s.config.maxOrbs)
        ..(s.reserved>0 and ("; unresolved exposure: "..s.reserved)or ""))
    local reason=(s.running or s.pending or s.state=="PAUSED")and s.reason or (s.startReason or s.reason)
    frame.status:SetText((phases[s.state]or s.state).."\n"..(reason or s.error or ""))
    if confirmNewRun and s.state=="FINISHED" then
        frame.status:SetText(frame.status:GetText().."\nPress Confirm new run to start a new run of up to "
            ..tostring(frame.limit:GetText()).." Orb(s). Close this window to cancel.")
    end
    if s.targetChanged then frame.status:SetText(frame.status:GetText().."\nOriginal operation: "..name(s.operationName))end
    frame.assignmentNote:SetText(a.mirrorNote or "")
    if advanced then
        local rows=s.sources or {};sourcePage=math.max(1,math.min(sourcePage,math.max(1,math.ceil(#rows/4))))
        for i,r in ipairs(frame.sourceRows)do
            local v=rows[(sourcePage-1)*4+i];r.key=v and v.key
            r.label:SetText(v and (name(v.name).." (quality "..v.quality.."): "..v.excess.." safe excess")or "")
            enable(r.exclude,v~=nil and not busy)
        end
        enable(frame.clearExclusions,not busy)
        frame.sourcePage:SetText("Eligible sources "..sourcePage.." / "..math.max(1,math.ceil(#rows/4)))
    end
    enable(frame.start,s.running or s.canResume or s.canStart);enable(frame.stop,busy);enable(frame.assigned,not busy)
    if advanced then frame.advanced:Show()else frame.advanced:Hide()end
    frame:SetHeight(advanced and 660 or 445)
end
function UI.Refresh()
    if not frame or not frame:IsShown()then return end
    local ok,err=pcall(refresh)
    if not ok then
        inactiveControls()
        frame.status:SetText("Orb panel refresh failed. Controls are unavailable.")
        error(err,0)
    end
end
local function ensure()
    if frame then return end
    frame=CreateFrame("Frame","NexusOrbPanel",UIParent);frame:Hide();frame:SetSize(620,445);frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    frame:SetFrameStrata("DIALOG");frame:SetFrameLevel(30);frame:EnableMouse(true);frame:SetMovable(true);frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton");frame:SetScript("OnDragStart",function(self)self:StartMoving()end)
    frame:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    frame:SetBackdropColor(.035,.04,.05,1)
    text(frame,20,-16,560,24,"Orbs / Lost Memories")
    frame.plan=text(frame,20,-48,440,32)
    frame.assigned=button(frame,469,-48,130,"My Builds",function()
        if Nexus.JournalTab and Nexus.JournalTab.OpenBuilds then Nexus.JournalTab.OpenBuilds()
        elseif Nexus.WishlistEditor then Nexus.WishlistEditor.Show()end
    end)
    frame.targets=text(frame,20,-82,580,26);frame.permanent=text(frame,20,-112,580,28);frame.balance=text(frame,20,-144,580,34)
    text(frame,20,-190,225,24,"Maximum Orbs this run:")
    frame.limit=CreateFrame("EditBox",nil,frame,"InputBoxTemplate");frame.limit:SetSize(65,25);frame.limit:SetPoint("TOPLEFT",225,-188)
    frame.limit:SetFrameLevel(32);frame.limit:SetAutoFocus(false);frame.limit:SetNumeric(true);frame.limit:SetMaxLetters(5)
    frame.limit:SetScript("OnEditFocusGained",function(self)if not self.editable or not frame:IsShown()then self:ClearFocus()end end)
    frame.limit:SetScript("OnEnterPressed",function(self)
        if not self.editable then self:ClearFocus();return end
        local ok,err=Nexus.OrbRuntime.SetLimit(tonumber(self:GetText()));self:ClearFocus();notify(ok,err)
    end)
    frame.limit:SetScript("OnEscapePressed",function(self)self:ClearFocus();UI.Refresh()end)
    frame.start=button(frame,326,-188,120,"Start",function()
        if Nexus.OrbRuntime.Status().state=="FINISHED" and not confirmNewRun then
            confirmNewRun=true;UI.Refresh();return
        end
        confirmNewRun=false;notify(primary(tonumber(frame.limit:GetText())))
    end)
    frame.stop=button(frame,461,-188,120,"Stop",function()notify(Nexus.OrbRuntime.Stop())end)
    frame.approval=text(frame,20,-221,580,37,"Start approves this maximum and automatic use of eligible surplus copies, including safe recycling. Ordinary Automation will turn OFF.")
    frame.usage=text(frame,20,-263,580,22);frame.status=text(frame,20,-289,580,74);frame.notice=text(frame,20,-364,580,24)
    frame.closeNotice=text(frame,20,-393,580,20,CLOSE_NOTICE)
    button(frame,20,-414,85,"Help",function()Nexus.Help.Show("orbs")end)
    button(frame,115,-414,95,"Advanced",function()advanced=not advanced;UI.Refresh()end)
    button(frame,220,-414,95,"Run log",function()UI.ShowLog()end)
    button(frame,515,-414,85,"Close",function()frame:Hide()end)
    frame.advanced=CreateFrame("Frame",nil,frame);frame.advanced:Hide();frame.advanced:SetSize(590,205);frame.advanced:SetPoint("TOPLEFT",15,-446);frame.advanced:SetFrameLevel(31)
    local af=frame.advanced
    button(af,5,-4,100,"Recheck",function()notify(Nexus.OrbRuntime.Recheck())end)
    frame.clearExclusions=button(af,116,-4,195,"Clear source exclusions",function()notify(Nexus.OrbRuntime.ClearExclusions())end)
    frame.sourceRows={}
    for i=1,4 do
        local r={};r.label=text(af,5,-38-(i-1)*28,455,25)
        r.exclude=button(af,468,-35-(i-1)*28,100,"Exclude",function()if r.key then notify(Nexus.OrbRuntime.Exclude(r.key,true))end end)
        frame.sourceRows[i]=r
    end
    frame.sourcePage=text(af,5,-151,250,23)
    button(af,285,-151,85,"Previous",function()sourcePage=math.max(1,sourcePage-1);UI.Refresh()end)
    button(af,380,-151,85,"Next",function()sourcePage=sourcePage+1;UI.Refresh()end)
    frame.assignmentNote=text(af,5,-180,565,31)
    frame.mutations={frame.start,frame.stop,frame.assigned,frame.clearExclusions}
    for _,r in ipairs(frame.sourceRows)do frame.mutations[#frame.mutations+1]=r.exclude end
    inactiveControls()
    frame:SetScript("OnShow",function()UI.Refresh()end)
    frame:SetScript("OnHide",function()editLimit(false);confirmNewRun=false end)
    local elapsed=0;frame:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;UI.Refresh()end end)
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
-- Two lines per Echo cell: the name, then the rarity word. The colour repeats
-- the rarity; it is never the only cue.
local CELL_LETTERS=30
local function logEchoText(cell)
    if not cell then return "" end
    local history=Nexus.OrbHistory
    local shown=history.Ellipsis(cell.label,CELL_LETTERS)
    if cell.recorded==false then return shown end
    return shown.."\n"..cell.rarity.label
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
            parts[#parts+1]=offer.label.." ("..offer.rarity.label..")"..mark
        end
        add("Offered: "..table.concat(parts,"   "))
    else
        add("Offered: "..tostring(details.offersNote))
    end
    add("Why: "..details.reason.label..(details.reason.detail and (" - "..details.reason.detail) or ""))
    if details.proposedSource then
        add("Proposed source: "..details.proposedSource.label
            .." ("..details.proposedSource.rarity.label..")"
            .."; no consumed source is recorded for this operation.")
    elseif details.consumed then
        add("Consumed source: "..details.consumed.label
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
local function refreshLog(force)
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
    logFrame.header:SetText(header.empty and header.status
        or (header.runLabel.." - "..header.wishlist.."\n"..header.status.."\n"..header.usage
            ..(header.increased and " (maximum was increased)" or "")))
    local warnings={}
    if header.pending then warnings[#warnings+1]=header.pending end
    if header.truncated then warnings[#warnings+1]=header.truncated end
    logFrame.warning:SetText(table.concat(warnings,"  "))
    enable(logFrame.current,logView~="current")
    enable(logFrame.previous,logView~="previous" and header.hasPrevious)
    local rows=history.Rows(run,logResolve)
    local selected=nil
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
            row.full=model.source.label.." ("..model.source.rarity.label..")"
                .."  ->  "..model.replacement.label
                ..(model.replacement.recorded~=false
                    and (" ("..model.replacement.rarity.label..")") or "")
            row.icon:SetTexture(model.source.icon or "")
            row.resultIcon:SetTexture(model.replacement.icon or "")
            if logSelection and model.serial==logSelection then
                selected=model;row.highlight:Show()
            else row.highlight:Hide() end
        else
            row:Hide();row.highlight:Hide();row.detail=nil;row.full=nil
            logCell(row.index,"");logCell(row.source,"");logCell(row.replacement,"")
            logCell(row.reason,"");logCell(row.result,"")
        end
    end
    if logSelection and not selected then logSelection=nil end
    local details=selected and history.Details(selected.entry,logResolve,run and run.startedAt) or nil
    logFrame.details:SetText(logDetailText(details,history))
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
-- run. It re-renders only when the recorded history actually changed.
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
local function ensureCopyView()
    if logCopyFrame then return logCopyFrame end
    local f=CreateFrame("Frame","NexusOrbHistoryCopy",UIParent);f:Hide()
    logCopyFrame=f
    f:SetSize(640,460);f:SetPoint("CENTER",UIParent,"CENTER",0,0)
    f:SetFrameStrata("DIALOG");f:SetFrameLevel(60);f:EnableMouse(true)
    f:SetMovable(true);f:SetClampedToScreen(true);f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(self)self:StartMoving()end)
    f:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(.035,.04,.05,1)
    text(f,20,-14,600,22,"Copy this report")
    text(f,20,-36,600,32,"Select the text and copy it. Opening this view sends nothing anywhere.")
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
    button(f,20,-410,110,"Clear focus",function()f.editBox:ClearFocus()end)
    button(f,515,-410,85,"Close",function()f:Hide()end)
    f:SetScript("OnHide",function()f.editBox:ClearFocus()end)
    UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusOrbHistoryCopy"
    return f
end
local function ensureLog()
    if logFrame then return end
    logFrame=CreateFrame("Frame","NexusOrbRunLog",UIParent);logFrame:Hide()
    logFrame:SetSize(760,560);logFrame:SetPoint("CENTER",UIParent,"CENTER",40,-20)
    logFrame:SetFrameStrata("DIALOG");logFrame:SetFrameLevel(40);logFrame:EnableMouse(true)
    logFrame:SetMovable(true);logFrame:SetClampedToScreen(true);logFrame:RegisterForDrag("LeftButton")
    logFrame:SetScript("OnDragStart",function(self)self:StartMoving()end)
    logFrame:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
    logFrame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
    logFrame:SetBackdropColor(.035,.04,.05,1)
    text(logFrame,20,-14,400,24,"Orb history")
    logFrame.current=button(logFrame,20,-42,120,"Current run",function()
        if logView=="current" then return end
        logView="current";logPage=1;logSelection=nil;refreshLog()
    end)
    logFrame.previous=button(logFrame,146,-42,120,"Previous run",function()
        if logView=="previous" then return end
        logView="previous";logPage=1;logSelection=nil;refreshLog()
    end)
    logFrame.header=text(logFrame,280,-40,460,50)
    logFrame.warning=text(logFrame,20,-72,720,20)
    logFrame.columns=text(logFrame,20,-96,720,18,
        "#      Replaced Echo                 Replacement                    Why selected            Result")
    logFrame.rows={}
    for i=1,LOG_ROWS do
        local row=CreateFrame("Button",nil,logFrame)
        row:SetSize(720,40);row:SetPoint("TOPLEFT",20,-118-(i-1)*40)
        row:SetFrameLevel(logFrame:GetFrameLevel()+1)
        row.highlight=row:CreateTexture(nil,"BACKGROUND")
        row.highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.highlight:SetAllPoints(row);row.highlight:SetVertexColor(.16,.24,.29,.5)
        row.highlight:Hide()
        row.separator=row:CreateTexture(nil,"BACKGROUND")
        row.separator:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.separator:SetSize(720,1);row.separator:SetPoint("BOTTOMLEFT",0,0)
        row.separator:SetVertexColor(.22,.24,.28,.55)
        row.index=text(row,0,-4,28,18)
        row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(18,18)
        row.icon:SetPoint("TOPLEFT",30,-4)
        row.source=text(row,52,-4,180,34)
        row.resultIcon=row:CreateTexture(nil,"ARTWORK");row.resultIcon:SetSize(18,18)
        row.resultIcon:SetPoint("TOPLEFT",238,-4)
        row.replacement=text(row,260,-4,190,34)
        row.reason=text(row,456,-4,150,34)
        row.result=text(row,612,-4,105,34)
        row:SetScript("OnClick",function(self)
            -- Reading only: this selects a row for display and nothing else.
            if logSelection==self.serial then logSelection=nil
            else logSelection=self.serial end
            refreshLog()
        end)
        row:SetScript("OnEnter",function(self)
            -- A shortened cell keeps its whole recorded value here.
            if not GameTooltip or (not self.detail and not self.full) then return end
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:SetText(self.full or "Why this Echo was selected")
            if self.detail then GameTooltip:AddLine(self.detail,1,1,1,true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide()
        logFrame.rows[i]=row
    end
    logFrame.detailScroll=CreateFrame("ScrollFrame","NexusOrbHistoryDetailScroll",
        logFrame,"UIPanelScrollFrameTemplate")
    logFrame.detailScroll:SetPoint("TOPLEFT",20,-444)
    logFrame.detailScroll:SetSize(700,96)
    logFrame.detailChild=CreateFrame("Frame",nil,logFrame.detailScroll)
    logFrame.detailChild:SetSize(680,96)
    logFrame.details=text(logFrame.detailChild,0,0,680,400)
    logFrame.detailScroll:SetScrollChild(logFrame.detailChild)
    logFrame.page=text(logFrame,20,-512,300,22)
    logFrame.prev=button(logFrame,320,-510,85,"Previous",function()
        if logPage<=1 then return end
        logPage=logPage-1;logSelection=nil;refreshLog()
    end)
    logFrame.next=button(logFrame,410,-510,85,"Next",function()
        logPage=logPage+1;logSelection=nil;refreshLog()
    end)
    button(logFrame,500,-510,115,"Copy report",function()
        local view=ensureCopyView()
        view:Show()
        view.editBox:SetText(logReportText(view.check:GetChecked() and true or false))
        view.editBox:SetCursorPosition(0)
    end)
    button(logFrame,625,-510,95,"Close",function()logFrame:Hide()end)
    logFrame.note=text(logFrame,20,-536,720,20,Nexus.OrbHistory and Nexus.OrbHistory.SESSION_NOTE or "")
    logFrame:SetScript("OnShow",function()refreshLog()end)
    logFrame:SetScript("OnHide",function() if logCopyFrame then logCopyFrame:Hide() end end)
    local elapsed=0
    logFrame:SetScript("OnUpdate",function(_,dt)
        -- Nothing runs while hidden; visible, this is one bounded header read.
        elapsed=elapsed+(dt or 0);if elapsed>=.5 then elapsed=0;logVisibleCheck() end
    end)
    UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusOrbRunLog"
end
function UI.ShowLog()
    ensureLog();logFrame:Show();refreshLog();return logFrame
end
function UI.Show()ensure();frame:Show();UI.Refresh();return frame end
function UI.Hide()if frame then frame:Hide()end end

-- Compact main-panel controls remain usable when the detailed window is hidden.
-- The ticker reads compact state only. It never advances an operation.
function UI.AttachMainPanel(parent)
    if parent._orbControls then return parent._orbControls end
    local f=CreateFrame("Frame",nil,parent);parent._orbControls=f
    f:SetPoint("TOPLEFT",parent,"BOTTOMLEFT",0,-2);f:SetSize(parent:GetWidth(),100);f:SetFrameLevel(parent:GetFrameLevel()+3)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});f:SetBackdropColor(.035,.04,.05,.95)
    f.summary=text(f,8,-6,252,52)
    f.primary=button(f,8,-65,87,"Pause",function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if s and s.running then Nexus.OrbRuntime.Pause()elseif s and s.canResume then Nexus.OrbRuntime.Resume()end
        f.refresh()
    end)
    f.stop=button(f,102,-65,65,"Stop",function()Nexus.OrbRuntime.Stop();f.refresh()end)
    f.details=button(f,174,-65,88,"Details",function()UI.Show()end)
    f.refresh=function()
        local s=Nexus.OrbRuntime.CompactStatus()
        if not s then f:Hide();return end
        f:Show();f.summary:SetText("Orbs: "..s.spent.." / "..s.limit.." used"..(s.reserved>0 and (" + "..s.reserved.." pending")or "")
            .."\n"..(s.remaining~=nil and (s.remaining.." target copies remaining")or "Target data unavailable").."\n"..(phases[s.state]or s.state))
        f.primary:SetText(s.running and "Pause"or "Resume");enable(f.primary,s.running or s.canResume)
        enable(f.stop,s.running or s.pending or s.state=="PAUSED"or s.state=="LIMIT")
    end
    local elapsed=0
    parent:HookScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;f.refresh()end end)
    f.refresh();return f
end
