-- Real OrbRuntime and mini handlers; synthetic WoW/services, no game access.
local H=dofile('tests/prototype/orbs_support.lua');local M=H.M;local UI=Nexus.OrbPanel
local n=0;local function check(v,m)assert(v,m);n=n+1 end
local function direct(b)b:GetScript('OnClick')(b)end
UIParent:SetSize(1920,1080)
check(not UI.MiniShown() and NexusOrbMini==nil,'mini is absent until explicitly opened')
local settings=H.Clone(NexusDB.settings)
local function same(a,b)
 if type(a)~='table' or type(b)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local f=UI.ShowMini();local frames=#H.frames
check(f==NexusOrbMini and UI.MiniShown(),'explicit open returns the named panel')
check(not f.pause:IsEnabled() and not f.resume:IsEnabled() and not f.stop:IsEnabled(),'no approved run offers no action')
check(f.state:GetText()=='No approved Orb run' and f.missing:GetText():find('unavailable',1,true),'no run is not zero missing')
for i=1,5 do UI.HideMini();UI.ShowMini()end
local escapes=0;for _,name in ipairs(UISpecialFrames)do if name=='NexusOrbMini'then escapes=escapes+1 end end
check(#H.frames==frames and escapes==1,'reopen reuses frames and registers Escape once')
check(same(settings,NexusDB.settings),'showing mini preserves all settings')
check(H.Count('orb-spend')==0,'opening and reopening do not spend')

-- Approved real run, submitted offer, Pause/Resume, close and Stop settlement.
H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
local full=UI.Show();full.limit:SetText('3');full.start:Click();UI.ShowMini()
check(H.Count('orb-spend')==1 and M.Status().limit==3,'start remains the full-window approval path')
check(f.pause:IsEnabled() and not f.resume:IsEnabled() and f.stop:IsEnabled(),'running gates')
check(f.pending:GetText():find('requested',1,true),'pending spend is separately disclosed')
f.pause:Click();direct(f.pause)
check(not M.Status().running and H.Count('orb-spend')==1,'repeated Pause never resumes or spends')
H.Offer();check(H.Count('take')==0,'paused outstanding offer is not selected')
UI.ShowMini();f.resume:Click();direct(f.resume)
check(M.Status().running and H.Count('take')==1 and M.Status().limit==3,'Resume retains approval and repeated Resume is inert')
full:Hide();f.close:Click();check(not UI.MiniShown() and not full:IsShown() and M.Status().running,'Close hides both detail views without pausing the approved run')
UI.ShowMini();check(f.notice:GetText()=='','reopen clears stale action notice')
H.Result(410002,2);H.Advance(.3)
check(H.Count('orb-spend')==2,'approved run continues while detail/mini may close')
check(not full:IsShown(),'the full window is closed before testing Open Orbs')
f.open:Click();check(full:IsShown() and H.Count('orb-spend')==2,'Open Orbs opens a previously closed full window without spending')
f.stop:Click();direct(f.stop)
check(not M.Status().running and H.Count('orb-spend')==2,'Stop cannot authorize another spend')
local beforeTake=H.Count('take');H.Offer();UI.ShowMini()
check(M.Status().pending and f.stop:IsEnabled() and not f.resume:IsEnabled() and H.Count('take')==beforeTake,'stopped pending offer is retained without automatic selection')
H.service.SelectPerk(410002) -- synthetic operator resolves the legitimate offer
H.Result(410002,2);H.Advance(.5)
check(M.Status().state=='STOPPED' and H.Count('orb-spend')==2,'submitted result settles after Stop without a new Orb')
UI.ShowMini();check(f.state:GetText()=='Stopped' and not f.pause:IsEnabled() and not f.resume:IsEnabled() and not f.stop:IsEnabled(),'settled Stop is accurately displayed with no further action')
check(Nexus.RecomputeStats().autoEnabled==false,'ordinary automation stays OFF')

-- Fault injection changes only the read seam; action calls are separately counted.
local compact,Pause,Resume,Stop=M.CompactStatus,M.Pause,M.Resume,M.Stop
local view={state='PAUSED',running=false,pending=false,canResume=true,spent=2,limit=3,reserved=0,remaining=1}
local reads,calls=0,0
M.CompactStatus=function()reads=reads+1;return view end
M.Pause=function()calls=calls+1;return true end
M.Resume=function()calls=calls+1;direct(f.resume);return false,'synthetic refusal' end
M.Stop=function()calls=calls+1;error('synthetic action failure')end
UI.ShowMini();check(f.resume:IsEnabled(),'valid paused snapshot offers Resume')
view.canResume=false;direct(f.resume)
check(calls==0 and f.notice:GetText():find('pending result',1,true),'stale enabled snapshot is rechecked at click')
view.canResume=true;UI.ShowMini();f.resume:Click()
check(calls==1 and f.notice:GetText():find('synthetic refusal',1,true),'nested click is blocked and refusal is shown')
f.stop:Click();check(calls==2 and f.notice:GetText():find('failed',1,true) and not f.notice:GetText():find('synthetic action failure',1,true),'action error reports a user-facing failure without raw diagnostic text')
view.state='UNRECOGNIZED';view.canResume=true;UI.ShowMini();direct(f.resume)
check(not f.resume:IsEnabled() and calls==2 and f.state:GetText():find('Unknown state',1,true),'unknown phase cannot resume')
view.state='PAUSED';view.remaining=nil;UI.ShowMini()
check(f.missing:GetText():find('unavailable',1,true) and f.resume:IsEnabled(),'missing progress stays unavailable without inventing action restrictions')
for _,bad in ipairs({'3',-1,1.5,math.huge})do
 view.spent=bad;UI.ShowMini();direct(f.pause);direct(f.resume);direct(f.stop)
 check(not f.pause:IsEnabled() and not f.resume:IsEnabled() and not f.stop:IsEnabled() and calls==2,'malformed counts fail closed')
end
view.spent=2;view.running='true';UI.ShowMini();check(not f.resume:IsEnabled(),'nonboolean status fails closed');view.running=false
view=nil;UI.ShowMini();check(f.state:GetText()=='No approved Orb run','nil status means no approved run')
view={state='PAUSED',running=false,pending=true,canResume=false,spent=2,limit=3,reserved=0}
UI.ShowMini();check(not f.resume:IsEnabled() and f.stop:IsEnabled(),'unresolved submitted result prevents Resume but permits Stop')

local errors=0;local oldError=geterrorhandler
geterrorhandler=function()return function()errors=errors+1 end end
M.CompactStatus=function()error('synthetic status failure')end
UI.ShowMini();for i=1,8 do f:GetScript('OnUpdate')(f,.25)end
direct(f.pause);direct(f.resume);direct(f.stop)
check(errors==1 and calls==2 and f.state:GetText()=='Run status unavailable','read failure clears stale controls and reports once')
M.CompactStatus=function()reads=reads+1;return view end;UI.ShowMini()
M.CompactStatus=function()error('second failure after recovery')end;UI.ShowMini()
check(errors==2,'a recovered read allows one later failure report')
geterrorhandler=oldError
M.CompactStatus=function()reads=reads+1;return view end
UI.HideMini();local before=reads;f:GetScript('OnUpdate')(f,10)
check(reads==before,'hidden mini does no status reads')

-- Text and geometry model; native font pixels, drag and Escape remain NOT_RUN.
view.reason=string.rep('Écho |cffffffff long label ',20)..'\nend';view.remaining=999999
UI.ShowMini()
check(f.reason._nexusFullText and f.reason:GetText():find('...',1,true),'long UTF-8 reason keeps complete tooltip text')
check(not f.reason:GetText():find('\n',1,true) and f.reason._nexusFullText:find('||cffffffff',1,true),'control text is flattened and markup escaped')
f.reasonHit:GetScript('OnEnter')(f.reasonHit)
check(GameTooltip:GetText()==f.reason._nexusFullText,'hover exposes the complete reason')
f.reasonHit:GetScript('OnLeave')(f.reasonHit);check(not GameTooltip:IsShown(),'tooltip hides on leave')
for _,key in ipairs({'state','reason','usage','pending','missing','notice','note'})do
 local line=f[key];local _,x,y=line:GetPoint();check(x>=0 and -y+line:GetHeight()<=f:GetHeight(),'line '..key..' is inside panel')
 if key~='note'then
  local visible=line:GetText():gsub('||','|');local _,chars=visible:gsub('[^\128-\191]','')
  check(chars*7<=line:GetWidth(),'bounded character model for '..key)
 end
end
for _,key in ipairs({'pause','resume','stop','open','close'})do
 local b=f[key];local _,x,y=b:GetPoint();check(x>=0 and x+b:GetWidth()<=f:GetWidth() and -y+b:GetHeight()<=f:GetHeight(),'control '..key..' fits')
end
f.GetLeft=function()return 1700 end;f.GetTop=function()return 100 end
UIParent:SetSize(640,480);UI.ShowMini()
local anchor,parent,relative,x,y=f:GetPoint()
check(anchor=='TOPLEFT' and parent==UIParent and relative=='BOTTOMLEFT' and x==284 and y==196,'resize clamps right and bottom edges in the model')
local moved,stopped,placed=0,0,nil
f.StartMoving=function()moved=moved+1 end;f.StopMovingOrSizing=function()stopped=stopped+1 end
f.SetUserPlaced=function(_,v)placed=v end
f.drag:GetScript('OnDragStart')(f.drag);f.drag:GetScript('OnDragStop')(f.drag)
check(moved==1 and stopped==1 and placed==false,'drag handlers avoid saved placement')
M.CompactStatus,M.Pause,M.Resume,M.Stop=compact,Pause,Resume,Stop
check(H.Count('orb-spend')==2,'all fault/read/layout tests leave spend count unchanged')

-- Missing runtime and loading cannot inherit a stale approved/pending display.
Nexus.OrbRuntime=nil;UI.ShowMini();direct(f.resume)
check(not f.pause:IsEnabled() and not f.resume:IsEnabled() and not f.stop:IsEnabled() and f.pending:GetText():find('unavailable',1,true),'missing runtime fails closed with unavailable pending')
Nexus.OrbRuntime=M
local startup=Nexus.StartupStatus;local statusReads=0
Nexus.StartupStatus=function()return {coreReady=false}end
M.CompactStatus=function()statusReads=statusReads+1;return nil end
full:Show();UI.Refresh();UI.ShowMini()
check(not full.miniPanel:IsEnabled() and statusReads==0 and f.pending:GetText():find('unavailable',1,true),'restoring disables footer and programmatic mini does not claim no pending')
check(f.state:GetText()~='No approved Orb run','loading is distinct from an approved-data no-run state')
Nexus.StartupStatus=startup;M.CompactStatus=compact;UI.Refresh()
check(full.miniPanel:IsEnabled(),'footer re-enables after core readiness')

-- Full hover access for short text that may be wide in a native font.
local shortWide=string.rep('W',40)
M.CompactStatus=function()return {state='PAUSED',running=false,pending=false,canResume=true,spent=1,limit=3,reserved=0,remaining=2,reason=shortWide}end
UI.ShowMini();GameTooltip:SetText('sentinel');f.reasonHit:GetScript('OnEnter')(f.reasonHit)
check(GameTooltip:GetText()==shortWide,'even model-unshortened wide text has complete hover access')
M.CompactStatus=function()return {state='LIMIT',running=false,pending=true,canResume=true,spent=1,limit=1,reserved=0,remaining=2,reason='Synthetic unsettled limit snapshot'}end
UI.ShowMini()
check(f.state:GetText()=='Maximum reached' and not f.pause:IsEnabled() and not f.resume:IsEnabled() and f.stop:IsEnabled(),'explicit LIMIT snapshot displays retained pending Stop without Resume')
M.CompactStatus=compact

-- Independent real-runtime scenarios use fresh synthetic addon sessions.
local function fresh()
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;NexusOrbRuntime=nil
 local q=dofile('tests/prototype/orbs_support.lua');UIParent:SetSize(1920,1080)
 q.OrbPlan({{spellId=410002,quality=2,stacks=3}})
 return q,Nexus.OrbPanel,Nexus.OrbPanel.ShowMini()
end
local q,u,mf=fresh();q.Approve(1,false);q.Offer();q.Result(410002,2);u.ShowMini()
check(q.M.Status().state=='FINISHED' and mf.state:GetText()=='Finished - limit reached','real settled maximum displays FINISHED')
check(mf.usage:GetText()=='Orbs used: 1 of 1 approved' and not mf.pause:IsEnabled() and not mf.resume:IsEnabled() and not mf.stop:IsEnabled(),'finished mini retains usage and offers no run action')
local finishedSpends=q.Count('orb-spend');direct(mf.resume);u.HideMini();u.ShowMini()
check(q.Count('orb-spend')==finishedSpends and q.M.Status().state=='FINISHED','finished click/reopen cannot authorize another run')

for _,kind in ipairs({'board','empty balance'})do
 q,u,mf=fresh();q.Approve(3,false);u.ShowMini();mf.pause:Click();q.Offer();u.ShowMini();mf.resume:Click();mf.pause:Click();q.Result(410002,2)
 check(q.M.Status().state=='PAUSED' and not q.M.Status().pending,'real settled paused run for '..kind)
 if kind=='board'then q.Board({{spellId=410002,quality=2},{spellId=410003,quality=0}});q.A.Poll()
 else q.O.charges=0 end
 u.ShowMini();check(mf.resume:IsEnabled(),'runtime offers Resume before synchronous '..kind..' recheck')
 local spends=q.Count('orb-spend');mf.resume:Click()
 local state=q.M.Status().state
 check(not q.M.Status().running and state==(kind=='board' and 'PAUSED' or 'OUT_OF_ORBS'),'Resume immediately enters actual '..kind..' state')
 check(not mf.notice:GetText():find('^Resumed') and mf.state:GetText()~='Running' and q.Count('orb-spend')==spends,'post-Resume notice does not claim ongoing execution after '..kind)
end

q,u,mf=fresh();q.Approve(3,false);q.Offer();q.Fire('PLAYER_LOGOUT')
local spends=q.Count('orb-spend');local takes=q.Count('take')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide()end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{});assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
q.M=Nexus.OrbRuntime;u.ShowMini()
check(q.M.Status().state=='RECOVERY' and q.M.Status().pending and not q.M.Status().running,'real receipt reload remains passive recovery')
check(not mf.pause:IsEnabled() and not mf.resume:IsEnabled() and mf.stop:IsEnabled() and mf.pending:GetText():find('not settled',1,true),'mini shows real restored pending and keeps Resume disabled')
direct(mf.resume);mf.close:Click();u.ShowMini()
check(q.Count('orb-spend')==spends and q.Count('take')==takes and q.M.Status().state=='RECOVERY','restored pending click/close/reopen has no replay or spend')
-- Unknown optional counters are never rendered as measured zero; malformed
-- present values cannot supply action affordances. Real held/checking phases
-- remain visible in the compact surfaces without opening Details.
local recoveryFailures={}
local function recoveryCase(name,fn)
 local ok,why=pcall(fn);if not ok then recoveryFailures[#recoveryFailures+1]=name..': '..tostring(why)end
end
local function miniModel(model)
 local q,u,mf=fresh();local raw=q.M.CompactStatus;q.M.CompactStatus=function()return model end;u.ShowMini()
 return q,u,mf,raw
end
recoveryCase('absent unknown spend is unavailable',function()
 local q,u,mf=miniModel({state='PAUSED',running=false,pending=true,canResume=false,spent=1,limit=3,reserved=1,historyKnown=false})
 local text=mf.pending._nexusFullText or mf.pending:GetText()
 check(text:find('Unknown spend: unavailable',1,true) and not text:find('Unknown spend: 0',1,true),'EXPECT absent uncertain count stays unavailable')
end)
recoveryCase('absent outcome total is unavailable',function()
 local q,u,mf=miniModel({state='PAUSED',running=false,pending=true,canResume=false,spent=1,limit=3,reserved=1,uncertain=1,historyKnown=true})
 local text=mf.pending._nexusFullText or mf.pending:GetText()
 check(text:find('unconfirmed outcomes: unavailable',1,true) and not text:find('unconfirmed outcomes: 0',1,true),'EXPECT missing earlier outcome total is never coerced to zero')
end)
for _,field in ipairs({'historyKnown','uncertain'})do
 recoveryCase('malformed '..field,function()
  local model={state='PAUSED',running=false,pending=false,canResume=true,spent=1,limit=3,reserved=0,uncertain=0,historyKnown=true};model[field]=field=='historyKnown' and 'false' or false
  local q,u,mf=miniModel(model)
  check(not mf.pause:IsEnabled() and not mf.resume:IsEnabled() and not mf.stop:IsEnabled(),'EXPECT malformed optional '..field..' value is not an action-bearing run view')
 end)
end
recoveryCase('real checking and held phases are visible first',function()
 local R=dofile('tests/prototype/orb_recovery_support.lua');local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={};assert(M.Start(3))
 local server=R.Server(H,{mode='hold'});H.service.RequestChoice=function()SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME)end
 for _=1,80 do if M.Status().recoveries==1 then break end;H.Advance(.25)end
 assert(M.Status().recoveries==1 and M.ContinueView().liveStage=='checking','SETUP actual admitted automatic check')
 local UI=Nexus.OrbPanel;local mf=UI.ShowMini();local parent=CreateFrame('Frame');parent:SetWidth(280);local strip=UI.AttachMainPanel(parent)
 check(mf.state:GetText():find('Checking',1,true) and strip.summary:GetText():match('^[^\n]*Checking'),'EXPECT checking phase remains visible at the start of compact status')
 assert(M.Pause());UI.ShowMini();strip.refresh()
 check(mf.state:GetText():find('held',1,true) and strip.summary:GetText():match('^[^\n]*held'),'EXPECT held automatic recovery is visible before long exposure text')
 check(H.Count('orb-spend')==1 and H.Count('take')==0,'GUARD compact display never advances the held owner')
end)
if #recoveryFailures>0 then error(table.concat(recoveryFailures,'\n'),0)end
print('PASS Orb mini real actions, stale/reentrant/failure gates, pending Stop, close/reopen, tooltips and synthetic geometry: '..n..' assertions')
