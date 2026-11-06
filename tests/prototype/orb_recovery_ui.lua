-- 035 part 2c: the player's side of Continue in the Orb window.
--
-- A "Continue..." button appears in the Orb window only while there is something to continue
-- or to read about it. It opens its own small window. Opening it, reading it and closing it send
-- nothing. "Check" starts the strict check, and only the player's click on "Continue" in the
-- window, enabled only for the current ready token, confirms. Closing the window or pressing
-- Cancel cancels a check. A stale click is refused with the reason and changes nothing.
-- Synthetic game and server; native behavior is NOT TESTED.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local failures={}
local function section(name,fn)
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function World(opts)
 local H,M,A,O=R.Class(opts)
 local server=R.Server(H,opts and opts.server)
 S.Pass(H,M,A,2)
 return H,M,A,O,server
end
local function Button(H,label,parent)
 for _,b in ipairs(H.frames) do
  if b.kind=='Button' and b:GetText()==label and (not parent or b:GetParent()==parent) then return b end
 end
 return nil
end
local function Until(H,fn,seconds)
 local waited=0
 while waited<(seconds or 20) do
  if fn() then return true end
  H.Advance(.25);waited=waited+.25
 end
 return fn()
end

section('1 the button and the window',function()
 local H,M,A,O,server=World()
 SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel)
 H.Advance(.5)
 check(f.cont and f.cont:IsShown() and f.cont:IsEnabled(),'the Continue button is shown for the class')
 check(f:GetHeight()==445,'the Orb window keeps its size')
 local sent=#H.sent;local reqs=server.requests
 f.cont:Click()
 local w=assert(NexusOrbContinue,'its own window');check(w:IsShown(),'the window opens')
 H.Advance(.5)
 -- The intro names the client-observed spend (no server reply confirms a spend).
 check(w.body:GetText():find('spend observed by this client',1,true) and w.body:GetText():find('No spend and no choice',1,true),'it explains what Continue is: '..w.body:GetText())
 check(w.check:IsEnabled() and not w.go:IsEnabled(),'only Check is available at first')
 check(server.requests==reqs and #H.sent==sent and H.Count('orb-spend')==0 and H.Count('take')==0,'opening it sent and spent nothing')
 -- no receipt: no button
 local H2,M2,A2,O2=S.Fresh()
 SlashCmdList.NEXUS('orbs');local f2=assert(NexusOrbPanel)
 H2.Advance(.5)
 check(f2.cont==nil or not f2.cont:IsShown(),'no receipt, no Continue button')
end)

section('2 check, ready, continue',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 SlashCmdList.NEXUS('orbs');local f=NexusOrbPanel
 f.cont:Click();local w=NexusOrbContinue
 server.mode='hold'
 w.check:Click()
 check(server.requests>=1,'Check asks the game (read-only)')
 H.Advance(.3)
 check(w.body:GetText():find('Checking',1,true) and not w.go:IsEnabled() and not w.check:IsEnabled(),'while checking: only the cancel is live')
 server.mode='auto'
 check(Until(H,function() return w.go:IsEnabled() end),'the Continue button becomes available only when the check is ready')
 check(w.body:GetText():find('unconfirmed',1,true) and w.body:GetText():find('not prove',1,true),'the window carries the full consent text')
 check(#w.body:GetText()<1500,'bounded text')
 check(R.Saved()~=nil and M.Status().pending==true,'nothing is released before the click')
 local sent=#H.sent
 w.go:Click()
 check(R.Saved()==nil and #R.SavedRow('orbRecoveryArchive')==1,'the click archives')
 H.Advance(.5)
 check(w.body:GetText():find('Continued',1,true) and not w.go:IsEnabled(),'the window says it is done; nothing left to confirm')
 check(M.Status().state=='STOPPED' and #H.sent==sent,'stopped, nothing sent')
 check(f.status:GetText():find('Stopped',1,true),'the Orb window shows Stopped')
 w:Hide()
end)

section('3 cancel and close',function()
 local H,M,A,O,server=World()
 SlashCmdList.NEXUS('orbs');NexusOrbPanel.cont:Click();local w=NexusOrbContinue
 w.check:Click();assert(Until(H,function() return w.go:IsEnabled() end))
 w.cancel:Click();H.Advance(.5)
 check(M.ContinueView().stage=='idle' and M.ContinueView().token==nil and not w.go:IsEnabled(),'Cancel returns to the start')
 w.check:Click();assert(Until(H,function() return w.go:IsEnabled() end))
 local token=M.ContinueView().token
 w:Hide();H.Advance(.5)
 check(M.ContinueView().stage=='idle' and select(2,M.ContinueConfirm(token))=='stale_token','closing the window cancels the check; the token is dead')
 check(R.Saved()~=nil,'nothing was released')
end)

section('4 a stale click',function()
 local H,M,A,O,server=World()
 SlashCmdList.NEXUS('orbs');NexusOrbPanel.cont:Click();local w=NexusOrbContinue
 w.check:Click();assert(Until(H,function() return w.go:IsEnabled() end))
 local original=H.Clone(R.Saved())
 H.perks.serverActiveSlot=102                  -- the game changed under the window
 H.Advance(6)
 check(not w.go:IsEnabled() and w.body:GetText():find('changed',1,true),'the window withdraws the confirmation and says why: '..w.body:GetText())
 -- a click that still reaches the handler (the window was not refreshed yet)
 local handler=w.go:GetScript('OnClick')
 handler(w.go)
 check(R.Same(R.Saved(),original) and R.SavedRow('orbRecoveryArchive')==nil,'a stale click changes nothing')
 check(w.notice:GetText()~=nil and w.notice:GetText()~='' and not w.notice:GetText():find('^[%l_]+$'),'and the player is told in words, not with a code: '..tostring(w.notice:GetText()))
end)

section('6 a click confirms what the window showed',function()
 local H,M,A,O,server=World()
 SlashCmdList.NEXUS('orbs');NexusOrbPanel.cont:Click();local w=NexusOrbContinue
 w.check:Click();assert(Until(H,function() return w.go:IsEnabled() end))
 local shown=w.token
 check(shown~=nil and shown==M.ContinueView().token,'the window holds the current token')
 -- the window stops refreshing (a stalled frame); the game side starts a new check with a new token
 w:SetScript('OnUpdate',nil)
 M.ContinueCancel();assert(M.ContinueBegin())
 assert(Until(H,function() return M.ContinueView().stage=='ready' end))
 local newest=M.ContinueView().token
 check(newest~=shown and w.token==shown,'the newest token is not the one the window showed')
 local original=H.Clone(R.Saved())
 w.go:GetScript('OnClick')(w.go)
 check(R.Same(R.Saved(),original) and R.SavedRow('orbRecoveryArchive')==nil,'a click confirms what the window showed, never a newer state: nothing changed')
 check(M.ContinueView().stage=='ready' and M.ContinueView().token==newest,'and the newer check is untouched')
end)

section('5 the help names Continue',function()
 -- the Orb help topic is a long string in ui/Help.lua; it must describe Continue and no longer claim there is no exit
 local f=assert(io.open('ui/Help.lua','rb'));local text=f:read('*a');f:close()
 local orbs=text:match('id="orbs".-id="troubleshooting"') or ''
 check(orbs:find('Continue:',1,true) and orbs:find('Nexus never continues by itself',1,true),'the Orb help describes Continue and says it is never automatic')
 check(not orbs:find('No exit from that block exists yet',1,true),'and no longer says no exit exists')
 check(orbs:find('not prove',1,true) and orbs:find('older answer',1,true),'it states what stays uncertain')
 check(orbs:find('at most two recovery checks',1,true) and orbs:find('then refused still uses one',1,true),
  'Help counts admitted checks, including refusals, rather than only archived outcomes')
end)

-- Semantic replacement of the old Archive-stub test: source projection and
-- formatting are exercised through a real durable production archive. A valid
-- consent version is1; zero is tested on numeric counts, not invented as v0.
section('7 real archive numeric facts distinguish absence, zero and invalid',function()
 local H,M,A,O,server=World()
 assert(M.ContinueBegin());assert(Until(H,function()return M.ContinueView().stage=='ready'end))
 assert(M.ContinueConfirm(M.ContinueView().token),'SETUP real production Continue creates a durable archive')
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 local original=H.Clone(R.SavedRow('orbRecoveryArchive')[1])
 local issues={}
 local function edit(fn)
  assert(owner.UpdateStateV1(function(row)row.orbRecoveryArchive[1]=H.Clone(original);fn(row.orbRecoveryArchive[1])end))
 end
 edit(function(e)e.spent=nil;e.limit=nil;e.uncertain=nil;e.consent=nil;e.late=nil;e.lateN=nil end)
 local absent=M.Archive().entries[1];local report=Nexus.SupportReport.Summary()
 check(absent.spent==nil and absent.limit==nil and absent.uncertain==nil and absent.consentVersion==nil,
  'GUARD genuinely absent numeric facts remain absent at the real producer')
 if not (report:find('run observed spends=not recorded limit=not recorded',1,true)
  and report:find('attempt unknown exposure=not recorded; consent not recorded',1,true))then
  issues[#issues+1]='EXPECT actual absent legacy facts say not recorded without inventing zero'
 end
 edit(function(e)e.spent=0;e.limit=0;e.uncertain=0;e.consent={v=1,policy='TWO_OBSERVED'};e.late={};e.lateN=0 end)
 local zero=M.Archive().entries[1];report=Nexus.SupportReport.Summary()
 check(zero.spent==0 and zero.limit==0 and zero.uncertain==0 and zero.lateN==0 and zero.consentVersion==1,
  'GUARD real recorded zeros and supported consent version survive projection')
 check(report:find('run observed spends=0 limit=0; attempt unknown exposure=0; consent v1',1,true)
  and report:find('late events kept=0 seen=0',1,true),'GUARD recorded zero remains exactly zero')
 for _,bad in ipairs({'SYNTHETIC_BAD_NUMERIC',-1,1.5,100001})do
  edit(function(e)e.spent=bad;e.limit=bad;e.uncertain=bad;e.lateN=bad;e.consent={v=0,policy='TWO_OBSERVED'}end)
  local saved=H.Clone(R.SavedRow('orbRecoveryArchive')[1])
  local projected=M.Archive().entries[1];local text=Nexus.SupportReport.Summary()
  print('SETUP R6a7 durable invalid numeric case '..tostring(bad)..' PASS')
  if projected.spent~='invalid' or projected.limit~='invalid' or projected.uncertain~='invalid'
   or projected.lateN~='invalid' or projected.consentVersion~='invalid' then
   issues[#issues+1]='EXPECT producer retains a bounded invalid marker for present malformed numeric facts: '..tostring(bad)
  end
  if not (text:find('run observed spends=unreadable limit=unreadable',1,true)
   and text:find('attempt unknown exposure=unreadable; consent unreadable',1,true)
   and text:find('seen=unreadable',1,true))then
   issues[#issues+1]='EXPECT real producer/consumer does not mislabel present invalid facts as absent: '..tostring(bad)
  end
  check(not text:find('SYNTHETIC_BAD_NUMERIC',1,true),'GUARD invalid raw content is never dumped into support text')
  check(R.Same(R.SavedRow('orbRecoveryArchive')[1],saved),'GUARD projection/report never repairs or rewrites stored evidence')
 end
 edit(function(e)e.uncertain=0;e.consent='SYNTHETIC_BAD_CONSENT';e.late='SYNTHETIC_BAD_LATE'end)
 local projected=M.Archive().entries[1];report=Nexus.SupportReport.Summary()
 if projected.consentVersion~='invalid' or projected.late~='invalid'
  or not report:find('consent unreadable',1,true) or not report:find('late events kept=unreadable',1,true)then
  issues[#issues+1]='EXPECT malformed containing structures do not turn into absent consent or zero events'
 end
 check(not report:find('SYNTHETIC_BAD_',1,true),'GUARD malformed containers expose no raw content')
 check(H.Count('orb-spend')==0 and H.Count('take')==0,'GUARD archive reporting sends no gameplay action')
 if #issues>0 then error(table.concat(issues,'\n'),0)end
end)

section('8 real archive code facts distinguish absent and invalid',function()
 local H,M,A,O,server=World();assert(M.ContinueBegin())
 assert(Until(H,function()return M.ContinueView().stage=='ready'end))
 assert(M.ContinueConfirm(M.ContinueView().token),'SETUP real durable archive for code-fact projection')
 local original=H.Clone(R.SavedRow('orbRecoveryArchive')[1]);local owner=Nexus.MainInternals.StoreAuthorityOwner
 local issues={}
 local function edit(fn)
  assert(owner.UpdateStateV1(function(row)row.orbRecoveryArchive[1]=H.Clone(original);fn(row.orbRecoveryArchive[1])end))
 end
 edit(function(e)e.kind=nil;e.resolution={};e.consent={v=1}end)
 local absent=M.Archive().entries[1];local report=Nexus.SupportReport.Summary()
 check(absent.kind==nil and absent.outcome==nil and absent.confidence==nil and absent.consentPolicy==nil,
  'GUARD genuinely absent code facts remain absent at the real producer')
 check(report:find('outcome=none; kind=none; confidence=none',1,true)
  and report:find('consent v1 none',1,true),'GUARD missing code facts remain distinct from supported NONE')
 for _,bad in ipairs({'SYNTHETIC_BAD_CODE',false,7})do
  edit(function(e)e.kind=bad;e.resolution={outcome=bad,confidence=bad};e.consent={v=1,policy=bad}end)
  local saved=H.Clone(R.SavedRow('orbRecoveryArchive')[1]);local projected=M.Archive().entries[1]
  local text=Nexus.SupportReport.Summary()
  print('SETUP R6a8 durable invalid code case '..tostring(bad)..' PASS')
  if projected.kind~='invalid' or projected.outcome~='invalid' or projected.confidence~='invalid'
   or projected.consentPolicy~='invalid' then
   issues[#issues+1]='EXPECT present invalid enum facts survive the producer as bounded invalid markers: '..tostring(bad)
  end
  if not (text:find('outcome=unreadable; kind=unreadable; confidence=unreadable',1,true)
   and text:find('consent v1 unreadable',1,true))then
   issues[#issues+1]='EXPECT unsupported stored enums are unreadable, never reported absent or NONE: '..tostring(bad)
  end
  check(not text:find('SYNTHETIC_BAD_CODE',1,true),'GUARD unsupported raw enum content is not dumped')
  check(R.Same(R.SavedRow('orbRecoveryArchive')[1],saved),'GUARD reporting preserves malformed retained facts')
 end
 edit(function(e)e.resolution='SYNTHETIC_BAD_RESOLUTION';e.consent={v=1,policy='TWO_OBSERVED'}end)
 local projected=M.Archive().entries[1];report=Nexus.SupportReport.Summary()
 if projected.outcome~='invalid' or projected.confidence~='invalid'
  or not report:find('outcome=unreadable',1,true)then
  issues[#issues+1]='EXPECT malformed present resolution container remains invalid rather than absent'
 end
 check(not report:find('SYNTHETIC_BAD_RESOLUTION',1,true),'GUARD malformed resolution exposes no raw payload')
 edit(function(e)e.kind='AUTO_UNCONFIRMED';e.resolution={outcome='UNCONFIRMED',confidence='NONE'}
  e.consent={v=1,policy='SESSION_BOUNDED_TWO'}end)
 projected=M.Archive().entries[1];report=Nexus.SupportReport.Summary()
 check(projected.kind=='AUTO_UNCONFIRMED' and projected.confidence=='NONE'
  and report:find('outcome=UNCONFIRMED; kind=AUTO_UNCONFIRMED; confidence=NONE',1,true)
  and report:find('consent v1 SESSION_BOUNDED_TWO',1,true),'GUARD actual supported enum facts remain exact')
 check(H.Count('orb-spend')==0 and H.Count('take')==0,'GUARD typed archive reads cause no gameplay action')
 if #issues>0 then error(table.concat(issues,'\n'),0)end
end)

section('9 real late rows must validate before their kept count is reported',function()
 local H,M,A,O,server=World();assert(M.ContinueBegin())
 assert(Until(H,function()return M.ContinueView().stage=='ready'end))
 assert(M.ContinueConfirm(M.ContinueView().token),'SETUP real durable archive for late-row facts')
 local original=H.Clone(R.SavedRow('orbRecoveryArchive')[1]);local owner=Nexus.MainInternals.StoreAuthorityOwner
 local issues={}
 local cases={
  {name='absent'},
  {name='empty',value={},seen=0,expected=0},
  {name='valid',value={{k='events_lost'}},seen=1,expected=1},
  {name='valid typed fields',value={{k='choice_push',ep=0,ch=1,pd=0,nr=false,w='known'}},seen=1,expected=1},
  {name='valid rows with bad independent seen counter',value={{k='events_lost'}},seen=-1,expected=1},
  {name='false row',value={false},seen=1,expected='invalid'},
  {name='unsupported code',value={{k='SYNTHETIC_UNSUPPORTED'}},seen=1,expected='invalid'},
  {name='bad scalar',value={{k='events_lost',ep='SYNTHETIC_BAD'}},seen=1,expected='invalid'},
  {name='negative scalar',value={{k='events_lost',ep=-1}},seen=1,expected='invalid'},
  {name='bad boolean',value={{k='events_lost',nr='SYNTHETIC_BAD'}},seen=1,expected='invalid'},
  {name='unknown field',value={{k='events_lost',extra='SYNTHETIC_BAD'}},seen=1,expected='invalid'},
  {name='sparse',value={[2]={k='events_lost'}},seen=1,expected='invalid'},
 }
 for _,case in ipairs(cases)do
  assert(owner.UpdateStateV1(function(row)
   row.orbRecoveryArchive[1]=H.Clone(original)
   row.orbRecoveryArchive[1].late=H.Clone(case.value);row.orbRecoveryArchive[1].lateN=case.seen
  end))
  local before=H.Clone(R.SavedRow('orbRecoveryArchive'));local projected=M.Archive().entries[1]
  local report=Nexus.SupportReport.Summary()
  print('SETUP R6c1 durable late-row '..case.name..' PASS')
  local expected=case.expected=='invalid' and 'unreadable' or case.expected==nil and 'not recorded' or tostring(case.expected)
  if projected.late~=case.expected or not report:find('late events kept='..expected,1,true)then
   issues[#issues+1]='EXPECT '..case.name..' keeps valid count or bounded invalid/absent distinction through the real report'
  end
  if case.seen==-1 then check(projected.lateN=='invalid' and report:find('seen=unreadable',1,true),
   'GUARD bad seen count does not erase a separately valid kept-row count')end
  check(R.Same(R.SavedRow('orbRecoveryArchive'),before),'GUARD late projection preserves all durable raw data')
  check(not report:find('SYNTHETIC_',1,true),'GUARD malformed late rows are not dumped into support text')
 end
 check(H.Count('orb-spend')==0 and H.Count('take')==0,'GUARD late reporting causes no gameplay action')
 if #issues>0 then error(table.concat(issues,'\n'),0)end
end)

section('10 actual malformed archive container counts remain unreadable',function()
 local H,M,A,O,server=World();assert(M.ContinueBegin())
 assert(Until(H,function()return M.ContinueView().stage=='ready'end))
 assert(M.ContinueConfirm(M.ContinueView().token),'SETUP real archive seed for top-level count truth')
 local original=H.Clone(R.SavedRow('orbRecoveryArchive'));assert(#original==1)
 local owner=Nexus.MainInternals.StoreAuthorityOwner;local issues={}
 for _,kind in ipairs({'absent','empty','valid','false','string','sparse','hole','bad entry','future','future pair','future bad row','future bad known row'})do
  assert(owner.UpdateStateV1(function(row)
   if kind=='absent'then row.orbRecoveryArchive=nil
   elseif kind=='empty'then row.orbRecoveryArchive={}
   elseif kind=='valid'then row.orbRecoveryArchive=H.Clone(original)
   elseif kind=='false'then row.orbRecoveryArchive=false
   elseif kind=='string'then row.orbRecoveryArchive='SYNTHETIC_BAD_ARCHIVE'
   elseif kind=='sparse'then row.orbRecoveryArchive={[2]=H.Clone(original[1])}
   elseif kind=='hole'then row.orbRecoveryArchive={[1]=H.Clone(original[1]),[3]=H.Clone(original[1])}
   elseif kind=='bad entry'then row.orbRecoveryArchive={false}
   else
    row.orbRecoveryArchive=H.Clone(original);row.orbRecoveryArchive[1].v=2
    if kind=='future pair'then row.orbRecoveryArchive[2]={v=3,id='next-format'}
    elseif kind=='future bad row'then row.orbRecoveryArchive[2]=false
    elseif kind=='future bad known row'then row.orbRecoveryArchive[2]={v=1}end
   end
  end))
  if kind=='false'then
   M=R.Reload(H)
   check(#M.ContinueLog()==0 and R.Saved()==nil and M.ContinueView().reason=='no_receipt',
    'SETUP report malformed archive without a pending receipt or session attempts')
  end
  local before=H.Clone(R.SavedRow('orbRecoveryArchive'));local projected=M.Archive()
  local report=Nexus.SupportReport.Summary();local numeric=kind=='absent'or kind=='empty'or kind=='valid'or kind=='future'or kind=='future pair'
  local expected=numeric and (kind=='future pair'and 2 or (kind=='valid'or kind=='future')and 1 or 0)or'invalid'
  local text=numeric and tostring(expected)or'unreadable'
  print('SETUP R6c1 durable archive container '..kind..' PASS')
  if projected.count~=expected or not report:find('archive='..text..'/8',1,true)then
   -- A genuinely empty, no-pending/no-log archive need not create a report section.
   if not (numeric and expected==0 and not report:find('archive=',1,true))then
    issues[#issues+1]='EXPECT '..kind..' reports established zero/count or bounded unreadable archive count'
   end
  end
  check(R.Same(R.SavedRow('orbRecoveryArchive'),before),'GUARD container projection never repairs raw archive data')
  check(not report:find('SYNTHETIC_BAD_ARCHIVE',1,true),'GUARD malformed archive payload never reaches support text')
 end
 check(H.Count('orb-spend')==0 and H.Count('take')==0,'GUARD archive-count reporting submits no action')
 if #issues>0 then error(table.concat(issues,'\n'),0)end
end)

section('11 truly cold Summary reads owned archive diagnostics without initializing the runner',function()
 local H,M,A,O,server=World();assert(M.ContinueBegin())
 assert(Until(H,function()return M.ContinueView().stage=='ready'end));assert(M.ContinueConfirm(M.ContinueView().token))
 local seed=H.Clone(R.SavedRow('orbRecoveryArchive')[1]);local issues={}
 for _,kind in ipairs({'absent','empty','valid','false','string','sparse','future','future pair','future bad row'})do
  local H,M,A,O=R.S.Fresh();local owner=Nexus.MainInternals.StoreAuthorityOwner
  assert(owner.UpdateStateV1(function(row)
   if kind=='absent'then row.orbRecoveryArchive=nil
   elseif kind=='empty'then row.orbRecoveryArchive={}
   elseif kind=='valid'then row.orbRecoveryArchive={H.Clone(seed)}
   elseif kind=='false'then row.orbRecoveryArchive=false
   elseif kind=='string'then row.orbRecoveryArchive='SYNTHETIC_COLD_ARCHIVE'
   elseif kind=='sparse'then row.orbRecoveryArchive={[2]=H.Clone(seed)}
   else
    row.orbRecoveryArchive={{v=2,id='future-row'}}
    if kind=='future pair'then row.orbRecoveryArchive[2]={v=3}
    elseif kind=='future bad row'then row.orbRecoveryArchive[2]=false end
   end
  end))
  M=R.Reload(H)
  assert(M.RunnerView().initialized==false,'SETUP actual post-reload cold owner with no pending receipt')
  local before=H.Clone(R.SavedRow('orbRecoveryArchive'));local frames=#H.frames;local calls=0
  local restores={}
  local function forbid(t,key)
   local old=t[key];restores[#restores+1]=function()t[key]=old end
   t[key]=function()calls=calls+1;error('synthetic forbidden cold diagnostic call '..key)end
  end
  for _,key in ipairs({'Archive','ContinueView','ContinueLog','Pump','Start','Resume'})do forbid(M,key)end
  for _,key in ipairs({'Read','TransportStatus','TransportSince','RequestRefresh','RequestOwnershipRefresh'})do forbid(A.Orbs,key)end
  forbid(owner,'UpdateStateV1')
  local ok,report=pcall(Nexus.SupportReport.Summary)
  for _,restore in ipairs(restores)do restore()end
  assert(ok,'SETUP cold Summary remains callable')
  print('SETUP R6c2 first cold Summary '..kind..' PASS')
  local numeric=kind=='absent'or kind=='empty'or kind=='valid'or kind=='future'or kind=='future pair'
  local count=kind=='future pair'and 2 or (kind=='valid'or kind=='future')and 1 or 0
  if not numeric then
   if not report:find('archive=unreadable/8',1,true)then issues[#issues+1]='EXPECT first cold '..kind..' report exposes unreadable retained archive'end
  elseif count>0 and not report:find('archive='..count..'/8',1,true)then
   issues[#issues+1]='EXPECT first cold '..kind..' report retains its established count'
  end
  if M.RunnerView().initialized~=false or calls~=0 or #H.frames~=frames then
   issues[#issues+1]='EXPECT cold '..kind..' diagnostics initialize, query and write nothing'
  end
  check(R.Same(R.SavedRow('orbRecoveryArchive'),before),'GUARD first cold report preserves raw owned archive')
  check(not report:find('SYNTHETIC_COLD_ARCHIVE',1,true),'GUARD cold malformed payload is not dumped')
  check(H.Count('orb-spend')==0 and H.Count('take')==0,'GUARD first cold report sends no gameplay action')
 end
 if #issues>0 then error(table.concat(issues,'\n'),0)end
end)

if #failures>0 then error(#failures..' section(s) failed:\n'..table.concat(failures,'\n'),0) end
print('PASS Orb recovery window: explicit Check and Continue, withdrawn on change, cancelled on close checks='..checks)
