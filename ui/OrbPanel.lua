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
    NO_SOURCES="No safe surplus copies remain",RECOVERY="Previous result is unresolved"}
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
    local s=Nexus.OrbRuntime.Status();frame.snapshot=s
    local a=s.assignment or {};local busy=s.running or s.pending or s.state=="PAUSED" or s.state=="LIMIT"
    frame.plan:SetText(a.state=="restoring" and "Restoring assigned Wishlist..." or ("Assigned Wishlist: "..name(a.name or "none")))
    frame.targets:SetText(s.progress and (s.progress.rolledMissing.." rolled target copies still missing")
        or a.note or "Assign a Wishlist through My Builds to begin.")
    local permanent=s.progress and s.progress.permanentMissing
    frame.permanent:SetText(permanent and permanent>0 and (permanent.." permanent target copies remain. Orbs cannot change permanent slots.")or "")
    frame.balance:SetText(s.charges~=nil and ("Confirmed Orb balance: "..s.charges)
        or ("Orb balance: "..(s.balanceState or "unknown")..". "..(s.balanceReason or "")))
    frame.start:SetText(s.running and "Pause" or (s.state=="PAUSED" and "Resume" or "Start"))
    editLimit(not busy)
    if not frame.limit:HasFocus()then frame.limit:SetText(tostring(busy and s.limit or s.config.maxOrbs))end
    frame.usage:SetText("Orbs used: "..s.spent.." / "..((busy or s.limit>0)and s.limit or s.config.maxOrbs)
        ..(s.reserved>0 and ("; unresolved exposure: "..s.reserved)or ""))
    local reason=(s.running or s.pending or s.state=="PAUSED")and s.reason or (s.startReason or s.reason)
    frame.status:SetText((phases[s.state]or s.state).."\n"..(reason or s.error or ""))
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
    frame.start=button(frame,326,-188,120,"Start",function()notify(primary(tonumber(frame.limit:GetText())))end)
    frame.stop=button(frame,461,-188,120,"Stop",function()notify(Nexus.OrbRuntime.Stop())end)
    frame.approval=text(frame,20,-221,580,37,"Start approves this maximum and automatic use of eligible surplus copies, including safe recycling. Ordinary Automation will turn OFF.")
    frame.usage=text(frame,20,-263,580,22);frame.status=text(frame,20,-289,580,74);frame.notice=text(frame,20,-364,580,24)
    frame.closeNotice=text(frame,20,-393,580,20,CLOSE_NOTICE)
    button(frame,20,-414,85,"Help",function()Nexus.Help.Show("orbs")end)
    button(frame,115,-414,95,"Advanced",function()advanced=not advanced;UI.Refresh()end)
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
    frame:SetScript("OnHide",function()editLimit(false)end)
    local elapsed=0;frame:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.25 then elapsed=0;UI.Refresh()end end)
    frame:Hide();UISpecialFrames=UISpecialFrames or {};UISpecialFrames[#UISpecialFrames+1]="NexusOrbPanel"
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
