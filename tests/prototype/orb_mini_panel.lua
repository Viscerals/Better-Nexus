-- Real OrbRuntime and mini handlers; synthetic WoW/services, no game access.
local H=dofile('tests/prototype/orbs_support.lua');local M=H.M;local UI=Nexus.OrbPanel
local n=0;local function check(v,m)assert(v,m);n=n+1 end
local function direct(b)b:GetScript('OnClick')(b)end
-- v22 (owner brief): the mini fits what it shows. Measured on the real mini
-- after ShowMini, in this model's units (the anchors and sizes the panel
-- sets, resolved as the client places them; no font renderer, so labels are
-- read in the conservative 7-unit-per-character model the lines already use).
-- GUARD (hard): every shown line and control lies wholly inside the mini; the
-- status lines stack without meeting; the closing note, a shown notice and
-- the footer buttons never meet each other; the title and Close never meet;
-- every button holds its whole label (7 units a character and its two 6-unit
-- end caps) and is at least 20 units high.
-- EXPECT (collected, failing on f727 by design: the mini is a fixed 356 x 196
-- with a fixed row kept for the optional notice): at the normal font (font
-- scale 1) the mini is no wider than the main panel's 284-unit base width (a
-- larger font may keep 356 or the base width x the scale); and with no notice
-- shown, the closing note stands no further under the last status line than
-- the status lines stand from each other (no empty notice row). Two footer
-- rows are allowed. Native pixels and capture sizes are separate from these
-- units (units x the effective scale are nominal pixels); NOT RUN.
local G=dofile('tests/prototype/layout_geometry_support.lua')
local layoutMisses,layoutCases={},0
-- Wrapped lines (v22, Root option B): a status line, the notice and the
-- closing note may take as many rows as their shown text needs in the
-- conservative model this file uses (7 units a character, greedy word wrap,
-- a word longer than a row broken across rows), each row the model's
-- 17-unit line. A line that needs more than one row must wrap (its word wrap
-- not turned off) and be at least that many rows tall. The harness keeps no
-- word-wrap state, so the request is recorded on the region here
-- (_wordWrap) and passed on; nothing else of the harness changes. A
-- FontString the client was never told about wraps (its default).
do
 local methods=G.RegionMethods();local had=rawget(methods,'SetWordWrap')
 methods.SetWordWrap=function(self,on,...)
  if type(self)=='table' then rawset(self,'_wordWrap',on and true or false) end
  if had then return had(self,on,...) end
 end
end
-- Rows of `text` (as shown, its escaped pipes read as one) in `width` units.
local function Rows(text,width)
 local per=math.max(1,math.floor((tonumber(width) or 0)/7))
 local rows=0
 for row in (text..'\n'):gmatch('(.-)\n') do
  rows=rows+1;local used=0
  for word in row:gmatch('%S+') do
   local n=G.Length(word);local gap=used>0 and 1 or 0
   if used>0 and used+gap+n>per then rows=rows+1;used=0;gap=0 end
   while n>per do rows=rows+1;n=n-per end
   used=used+gap+n
  end
 end
 return math.max(1,rows)
end
local function Wrapped(tag,key,line)
 local shown=(line:GetText() or ''):gsub('||','|')
 local width,height=tonumber(line:GetWidth()) or 0,tonumber(line:GetHeight()) or 0
 local rows=Rows(shown,width)
 check(rows==1 or rawget(line,'_wordWrap')~=false,
  tag..': the '..key..' line needs '..rows..' rows of its '..width..' units and wraps (its word wrap is not off)')
 check(height>=rows*17,tag..': the '..key..' line is tall enough for its '..rows..' row(s) of 17 units ('..height..')')
end
local function MiniLayout(tag,w)
 layoutCases=layoutCases+1
 local width,height=w:GetWidth(),w:GetHeight()
 local box={0,0,width,height}
 local function Place(region) local ok,r=pcall(G.Rect,region,w);return ok and r or nil end
 local function Shown(key)
  local region=w[key]
  return region~=nil and region:IsShown() and not (key=='notice' and (region:GetText() or '')=='')
 end
 local at={}
 for _,key in ipairs({'title','drag','close','state','reason','usage','pending','missing','notice','note','pause','resume','stop','open'})do
  if Shown(key) then
   local r=Place(w[key])
   check(r~=nil,tag..': fixture: the mini\'s '..key..' has a place')
   check(G.Inside(r,box),tag..': '..key..' lies wholly inside the mini '..G.Text(r)..' in '..width..'x'..height)
   at[key]=r
  end
 end
 local last
 for _,key in ipairs({'state','reason','usage','pending','missing','notice','note'})do
  if at[key] then
   if last then check(G.Apart(at[last],at[key]),tag..': the '..last..' and '..key..' lines do not overlap') end
   last=key
  end
 end
 for _,a in ipairs({'note','notice','pause','resume','stop','open'})do
  for _,b in ipairs({'pause','resume','stop','open'})do
   if a~=b and at[a] and at[b] then check(G.Apart(at[a],at[b]),tag..': '..a..' and '..b..' do not meet') end
  end
 end
 if at.title and at.close then check(G.Apart(at.title,at.close),tag..': the title and Close do not meet') end
 for _,key in ipairs({'pause','resume','stop','open','close'})do
  local b=w[key];local label=G.Visible(b:GetText() or '')
  check(b:GetWidth()>=G.Length(label)*7+12 and b:GetHeight()>=20,
   tag..': '..key..' holds its whole label "'..label..'" ('..tostring(b:GetWidth())..'x'..tostring(b:GetHeight())..')')
 end
 local scale=1
 if Nexus.LayoutMetrics and type(Nexus.LayoutMetrics.RuntimeMetrics)=='function' then
  scale=tonumber((Nexus.LayoutMetrics.RuntimeMetrics())) or 1
 end
 local limit=scale<=1 and 284 or math.max(356,math.floor(284*math.min(2,scale)+0.5))
 if width>limit then
  layoutMisses[#layoutMisses+1]=tag..': the mini is '..tostring(width)..' units wide; at font scale '..tostring(scale)
   ..' it fits within '..limit..' (the main panel\'s base width at the normal font)'
 end
 if not Shown('notice') and at.note then
  local gap,lastBottom=0,nil
  for _,key in ipairs({'state','reason','usage','pending','missing'})do
   if at[key] then
    if lastBottom then gap=math.max(gap,at[key][2]-lastBottom) end
    lastBottom=at[key][4]
   end
  end
  if lastBottom and at.note[2]-lastBottom>gap then
   layoutMisses[#layoutMisses+1]=tag..': with no notice the closing note stands '..tostring(at.note[2]-lastBottom)
    ..' units under the last status line, where the status lines stand at most '..tostring(gap)..' apart (an empty notice row is kept)'
  end
 end
end
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
MiniLayout('no approved run',f)
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
MiniLayout('approved run reopened, no notice',f)
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
MiniLayout('paused, refusal notice shown',f)
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
MiniLayout('long reason line',f)
for _,key in ipairs({'state','reason','usage','pending','missing','notice','note'})do
 local line=f[key];local _,x,y=line:GetPoint();check(x>=0 and -y+line:GetHeight()<=f:GetHeight(),'line '..key..' is inside panel')
 -- v22 (Root option B): was the one-line bound "visible characters x 7 <=
 -- the line's width" (status lines only). Now the wrapped-layout bound in the
 -- same model, for the closing note too: the rows the shown text needs at
 -- the line's width, the line wrapping when that is more than one, and the
 -- line at least that many 17-unit rows tall (Wrapped, above).
 Wrapped('long reason line',key,line)
end
for _,key in ipairs({'pause','resume','stop','open','close'})do
 local b=f[key];local _,x,y=b:GetPoint();check(x>=0 and x+b:GetWidth()<=f:GetWidth() and -y+b:GetHeight()<=f:GetHeight(),'control '..key..' fits')
end
-- v22 wrap case (Root option B): the two longest complete status forms this
-- file asks for elsewhere, on the real mini through the same read seam: a
-- paused run whose rolled-copies count is absent ("...missing: unavailable")
-- and whose unknown spend and outcomes are unread ("...; Outcomes: ?"). GUARD:
-- each is shown whole (no cut, nothing moved to the tooltip only), every line
-- wraps and is tall enough for its rows, and the layout guards hold; the
-- collected width EXPECT is asked again.
view={state='PAUSED',running=false,pending=true,canResume=false,spent=2,limit=3,reserved=1}
UI.ShowMini()
do
 local tag='long unavailable and outcome lines'
 local missing=(f.missing:GetText() or ''):gsub('||','|')
 local pending=(f.pending:GetText() or ''):gsub('||','|')
 check(f.missing._nexusFullText==nil and missing:find('unavailable',1,true) and not missing:find('...',1,true),
  tag..': the rolled-copies line is shown whole, ending in unavailable: '..missing)
 check(pending:find('Outcomes: ?',1,true) and not pending:find('...',1,true),
  tag..': the pending counts line is shown whole, with its unknown outcomes: '..pending)
 for _,key in ipairs({'state','reason','usage','pending','missing','notice','note'})do Wrapped(tag,key,f[key]) end
 MiniLayout(tag,f)
end
f.GetLeft=function()return 1700 end;f.GetTop=function()return 100 end
UIParent:SetSize(640,480);UI.ShowMini()
local anchor,parent,relative,x,y=f:GetPoint()
-- v22: the clamp is asked of the mini's own size (it was the fixed 356 x 196:
-- 640 - 356 = 284 and 196), the same rule for a content-fit mini.
check(anchor=='TOPLEFT' and parent==UIParent and relative=='BOTTOMLEFT' and x==UIParent:GetWidth()-f:GetWidth() and y==f:GetHeight(),
 'resize clamps right and bottom edges in the model')
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
MiniLayout('finished run (fresh boot)',mf)
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
local pendingFull=mf.pending._nexusFullText or mf.pending:GetText()
check(not mf.pause:IsEnabled() and not mf.resume:IsEnabled() and mf.stop:IsEnabled()
 and pendingFull:find('not settled',1,true) and mf.pending:GetText():find('Outcomes: ?',1,true),
 'mini keeps restored pending explanation, visibly unknown prior outcomes and Resume disabled')
mf.pendingHit:GetScript('OnEnter')(mf.pendingHit)
check(GameTooltip:GetText()==pendingFull and GameTooltip:GetText():find('not settled',1,true),
 'real pending hover exposes the complete restored unsettled explanation')
mf.pendingHit:GetScript('OnLeave')(mf.pendingHit)
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
-- The collected v22 layout EXPECT fails only after every check above ran.
if #layoutMisses>0 then
 error('orb_mini_panel: EXPECT the mini fits what it shows ('..#layoutMisses..' misses in '..layoutCases..' cases): '
  ..table.concat(layoutMisses,' | ')..'; checks='..n,0)
end
print('PASS Orb mini real actions, stale/reentrant/failure gates, pending Stop, close/reopen, tooltips and synthetic geometry: '..n..' assertions')
