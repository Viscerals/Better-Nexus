-- B2 exact pre-offer reproduction changed into a fail-capable regression.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
H.OrbPlan({{spellId=410002,quality=2,stacks=2}});H.Approve(3,false)
O.charges=O.charges-1;H.granted=H.Clone(H.granted);H.Notify();A.Poll()
for i=1,3 do M.Pump() end
assert(M.Status().pending and H.Count('orb-spend')==1 and H.Count('take')==0,'B2: pre-offer clone and charge update cannot complete operation')
assert(M.Status().spent+M.Status().reserved==1,'unresolved exposure is retained')
assert(not M.Prepare(),'pending ownership blocks a new run')
-- Delayed offer after early charge and ownership notifications.
O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410008,quality=1},{spellId=410004,quality=3}})
M.Pump();assert(H.Count('take')==1,'one selection after actual delayed offer')
-- Ownership can arrive before board/host/offer closure: do not settle early.
local out=H.Clone(H.granted)
for _,es in pairs(out)do for i=#es,1,-1 do if es[i].spellId==O.source then table.remove(es,i);break end end end
out['Desired A']={{spellId=410002,quality=2}};H.granted=out;H.Notify();A.Poll();M.Pump()
assert(M.Status().pending,'ownership delta alone before lifecycle closure cannot settle')
M.Pause();H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;M.Pump()
assert(not M.Status().pending and M.Status().spent==1 and H.Count('orb-spend')==1,'late closure settles matching result passively')
assert(M.Status().state=='PAUSED','settlement does not resume paused intent')
M.Stop()
print('PASS B2 pre-offer, early ownership, late closure, pending exposure and passive settlement')

-- R6a1: observed completion can precede the exact settlement of the last
-- receipt. A later matching replacement must not turn that terminal approval
-- into a paused, resumable run. Real Store/adapter/runtime; only game services
-- and their ownership snapshots are synthetic. No private run state is set.
local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
local failures,checks={},0
local function terminalCase(name,changed,locked,stopped)
 local H,M,A,O=S.Fresh()
 H.perks.currentChoice={}
 local targets={{spellId=410002,quality=2,stacks=2}}
 if locked then targets[2]={spellId=410007,quality=2,stacks=1,locked=true} end
 H.OrbPlan(targets)
 local original=H.Clone(H.granted)
 H.Approve(6,false)
 assert(H.Count('orb-spend')==1,'SETUP '..name..': one real submitted spend')
 H.Offer()
 assert(H.Count('take')==1,'SETUP '..name..': the actual offer selected once')
 -- A separate ownership observation shows the requested rolled targets,
 -- but not the matching source removal. It cannot settle this receipt.
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.granted=H.Clone(original)
 H.granted['Desired A']={{spellId=410002,quality=2},{spellId=410002,quality=2}}
 H.Notify();A.Poll();M.Pump()
 local completed=locked and 'ROLLED_COMPLETE' or 'COMPLETE'
 local before=M.Status(false)
 assert(before.state==completed and before.pending and not before.running,
  'SETUP '..name..': real observed completion retains the unresolved receipt')
 assert(A.Orbs.IsOwned() and Nexus.Store.State().orbRefinement.pending,
  'SETUP '..name..': pending receipt retains durable evidence and operation ownership')
 if changed then
  assert(A.SetFirstLoadoutWishlistIdentity('Changed after completion',{{spellId=410004,quality=3,stacks=1}}))
  M.Pump()
 end
 if stopped then assert(M.Stop(),'SETUP '..name..': explicit Stop after completion') end
 -- The later game snapshot is the exact replacement for the original
 -- selected offer. It has only one desired copy: the transient earlier
 -- completion does not authorize adopting a new target or spending again.
 local late=H.Clone(original);local removed=false
 for _,entries in pairs(late)do for i=#entries,1,-1 do
  if not removed and entries[i].spellId==O.source then table.remove(entries,i);removed=true end
 end end
 assert(removed,'SETUP '..name..': exact late result removes the actual source')
 late['Desired A']={{spellId=410002,quality=2}}
 H.granted=late;H.Notify();A.Poll();M.Pump()
 assert(#H.granted['Desired A']==1,'SETUP '..name..': one of two requested rolled copies remains missing')
 print('SETUP R6a1 '..name..' PASS')
 local function expect(value,message)
  checks=checks+1
  if not value then failures[#failures+1]=name..': '..message end
 end
 local view=M.Status(false)
 expect(view.state==(stopped and 'STOPPED' or completed),'EXPECT terminal state survives exact settlement')
 expect(not view.pending and Nexus.Store.State().orbRefinement.pending==nil,'EXPECT receipt clears in memory and durable Store')
 expect(view.spent==1 and view.reserved==0 and (view.uncertain or 0)==0,'GUARD actual known spend remains one with no phantom exposure')
 expect(not A.Orbs.IsOwned(),'EXPECT settled terminal releases operation ownership')
 expect(not view.running and not view.canResume,'EXPECT no running or Resume affordance for the terminal approval')
 expect(not view.reason:find('different targets',1,true),'EXPECT ended approval asks for current review without assuming targets changed')
 if locked and not stopped then
  expect(view.reason:find('locked targets',1,true),'EXPECT rolled completion retains the remaining locked-target limitation')
 end
 local resumed=M.Resume()
 expect(not resumed,'EXPECT a completed or deliberately stopped approval cannot resume')
 expect(not M.PrepareLimitIncrease(7),'GUARD completed/stopped approval cannot reopen a limit increase')
 H.Advance(.5)
 expect(H.Count('orb-spend')==1 and H.Count('take')==1,'EXPECT no second host spend or selection after terminal settlement')
 M.Stop()
end
for _,case in ipairs({
 {'changed assignment',true,false,false},
 {'same assignment with missing copy',false,false,false},
 {'rolled complete with missing locked target',false,true,false},
 {'explicit Stop wins',true,false,true},
})do
 local ok,err=pcall(terminalCase,unpack(case))
 if not ok then failures[#failures+1]='SETUP '..case[1]..': '..tostring(err) end
end
if #failures>0 then error(table.concat(failures,'\n'),0) end
print('PASS R6a1 terminal late-settlement cases; checks='..checks)

-- R6a2: an exception from the final pre-host guard is known-unsent, not
-- ambiguous spending. Inject only at the real adapter callback boundary,
-- after the real runtime has durably saved its reservation.
local guardFailures,guardChecks={},0
local function guardCase(name,ownerGetter,single,recordFault)
 local H,M,A,O=S.Fresh()
 H.perks.currentChoice={};H.OrbPlan({{spellId=410002,quality=2,stacks=2}})
 local B=A.Orbs;local spend=B.Spend;local ownerKey=Nexus.Store.CurrentOwnerKey
 local inGuard=false;local sawSaved=false;local sourceKey;local returnedKind,returnedStatus
 local record=Nexus.Errors.Record;local recordAttempts=0
 if recordFault then Nexus.Errors.Record=function()
  recordAttempts=recordAttempts+1;error('synthetic diagnostic recorder failure')
 end end
 Nexus.Store.CurrentOwnerKey=function(...)
  if inGuard then error('synthetic final-guard owner lookup failure') end
  return ownerKey(...)
 end
 B.Spend=function(token,key,expected,guard)
  sourceKey=key
  local accepted,kind,reason,status=spend(token,key,expected,function(live)
   local saved=Nexus.Store.State().orbRefinement.pending
   sawSaved=saved~=nil and saved.spendConfirmed~=true
    and M.CompactStatus().reserved==1 and H.Count('orb-spend')==0
   assert(sawSaved,'SETUP '..name..': real durable unsent reservation precedes guard')
   if not ownerGetter then error('synthetic final-guard callback failure') end
   -- Restore the injected getter before rethrowing, so runtime cleanup has
   -- its normal Store boundary. The actual production guard is still called.
   inGuard=true
   local ok,allowed,why=pcall(guard,live)
   inGuard=false
   if not ok then error(allowed,0) end
   return allowed,why
  end)
  returnedKind,returnedStatus=kind,status
  return accepted,kind,reason,status
 end
 local ok=pcall(H.Approve,6,false,single)
 inGuard=false;Nexus.Store.CurrentOwnerKey=ownerKey;B.Spend=spend;Nexus.Errors.Record=record
 assert(sawSaved,'SETUP '..name..': guard-only exception reached after durable save')
 print('SETUP R6a2 '..name..' PASS')
 local function expect(value,message)
  guardChecks=guardChecks+1
  if not value then guardFailures[#guardFailures+1]=name..': '..message end
 end
 local view=M.Status(false)
 expect(ok,'EXPECT guard exception is contained at the adapter boundary')
 expect(returnedKind=='REJECTED' and returnedStatus=='GUARD_ERROR','EXPECT typed known-unsent guard rejection')
 expect(not view.pending and Nexus.Store.State().orbRefinement.pending==nil,'EXPECT unsent receipt clears in memory and durable Store')
 expect(view.spent==0 and view.reserved==0 and (view.uncertain or 0)==0,'EXPECT no phantom known or uncertain exposure')
 expect(H.Count('orb-spend')==0 and H.Count('take')==0,'EXPECT no host spend or selection before guard acceptance')
 expect(view.state=='PAUSED' and not view.running,'GUARD rejection pauses without automatic retry')
 if recordFault then
  expect(recordAttempts==1,'EXPECT real guarded diagnostic recording was attempted once despite recorder failure')
 else
  local entry=Nexus.Errors.Latest()
  local marker=ownerGetter and 'synthetic final-guard owner lookup failure' or 'synthetic final-guard callback failure'
  expect(entry and entry.source=='OrbAdapter.SpendGuard' and entry.message:find(marker,1,true)
   and #entry.message<=2003,'EXPECT the real bounded Errors owner retains the original guard failure cause')
 end
 local resumed=M.Resume()
 local first
 for _,action in ipairs(H.actions)do if action[1]=='orb-spend' then first=action[2];break end end
 expect(resumed and H.Count('orb-spend')==1,'EXPECT explicit Resume can make the first actual submission after the fault is removed')
 expect(first==tonumber(sourceKey:match('^(%d+):')),'GUARD known-unsent rejection restores the original manual source quota')
 M.Stop()
end
for _,case in ipairs({{'callback exception',false,false},{'runtime owner getter exception',true,true},
 {'diagnostic recorder failure',false,false,true}})do
 local ok,err=pcall(guardCase,unpack(case))
 if not ok then guardFailures[#guardFailures+1]='SETUP '..case[1]..': '..tostring(err) end
end
if #guardFailures>0 then error(table.concat(guardFailures,'\n'),0) end
print('PASS R6a2 known-unsent guard cases; checks='..guardChecks)

-- The same exception class can occur after an actual bounded archive granted
-- a one-use post-recovery permit. An unavailable final transport check must
-- not publish a classified empty choice or a ready Resume affordance.
do
 local R=dofile('tests/prototype/orb_recovery_support.lua')
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
 local B=A.Orbs;local spend=B.Spend;local hit=false;local boundary;local guardSaved,actualGuardThrew
 B.Spend=function(token,key,expected,guard)
  local accepted,kind,reason,status=spend(token,key,expected,function(live)
   local archive=R.SavedRow('orbRecoveryArchive')
   if H.Count('orb-spend')==1 and archive and #archive==1 then
    guardSaved=R.Saved()~=nil and M.CompactStatus().reserved==1
    hit=true
    local original=B.TransportStatus;B.TransportStatus=function()return nil end
    local ok,allowed,why=pcall(guard,live)
    B.TransportStatus=original
    actualGuardThrew=not ok
    if not ok then error(allowed,0) end
    return allowed,why
   end
   return guard(live)
  end)
  if hit then boundary=status end
  return accepted,kind,reason,status
 end
 assert(M.Start(6))
 local server=R.Server(H)
 H.service.RequestChoice=function()
  SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME)
  server.queue[#server.queue+1]={op=16,body=''}
 end
 H.Offer();H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 for _=1,100 do if hit then break end;H.Advance(.25) end
 B.Spend=spend
 assert(hit,'SETUP actual admitted recovery reached the next final guard')
 assert(guardSaved,'SETUP real next unsent receipt follows the actual unconfirmed archive')
 assert(actualGuardThrew,'SETUP actual production postCheck threw; this assertion is outside adapter containment')
 print('SETUP R6a2 post-recovery final guard PASS')
 local view=M.CompactStatus()
 assert(boundary=='GUARD_ERROR' and view.state=='PAUSED' and not view.pending and R.Saved()==nil,
  'GUARD post-recovery fault is typed known-unsent and clears its new receipt')
 assert(view.reserved==0 and view.spent==1 and view.uncertain==0 and view.recoveries==1
  and view.unconfirmedResults==1 and #R.SavedRow('orbRecoveryArchive')==1,
  'GUARD failed guard does not invent another exposure, result, check or archive')
 assert(H.Count('orb-spend')==1 and H.Count('take')==1,'GUARD failed final check invokes no second host action')
 assert(not view.canResume,'EXPECT final guard failure withholds unclassified post-recovery Resume')
 assert(not M.Resume() and H.Count('orb-spend')==1,'EXPECT no permit progress is inferred from the guard exception')
 server.Push(16,'')
 assert(H.Count('orb-spend')==1,'GUARD fresh observation alone does not restart the paused run')
 assert(M.Resume() and H.Count('orb-spend')==2,
  'GUARD a genuinely newer exact empty observation permits one explicit fresh submission')
 M.Stop()
 print('PASS R6a2 post-recovery guard classification and fresh-observation control')
end

-- R6a3: identical passive holds must not invalidate the session history on
-- every pump. The actual completion and older-result attribution paths run;
-- no private Runtime state or log data is assigned by these checks.
local logFailures={}
local function heldLog(name,setup)
 local H,M,A,O=setup()
 M.Pump(true)
 local before=M.RunLog()
 assert(before and before.revision>0 and M.CompactStatus().pending,
  'SETUP '..name..': an actual pending operation has a live session history')
 print('SETUP R6a3 '..name..' PASS revision='..before.revision)
 for _=1,12 do M.Pump(true) end
 local after=M.RunLog()
 if after.revision~=before.revision then
  logFailures[#logFailures+1]='EXPECT '..name..': unchanged hold preserves history revision ('..before.revision..' -> '..after.revision..')'
 end
 assert(H.Count('orb-spend')==before.spent+(before.reserved or 0),
  'GUARD passive repeated hold submits no new Orb')
 assert(after.state==before.state and after.reason==before.reason and after.total==before.total,
  'GUARD repeated observation retains the same visible history')
 local revision=after.revision
 assert(M.Stop(),'GUARD deliberate Stop remains accepted')
 local stopped=M.RunLog()
 assert(stopped.state=='STOPPED' and stopped.revision>revision,
  'GUARD a real Stop transition still invalidates history')
end
local function completionHold()
 local H,M,A,O=S.Fresh();H.perks.currentChoice={}
 H.OrbPlan({{spellId=410002,quality=2,stacks=2}});H.Approve(6,false);H.Offer()
 H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
 H.granted=H.Clone(H.granted)
 H.granted['Desired A']={{spellId=410002,quality=2},{spellId=410002,quality=2}}
 H.Notify();A.Poll();M.Pump(true)
 assert(M.CompactStatus().state=='COMPLETE' and M.CompactStatus().pending,
  'SETUP real completed target observation retains the unresolved receipt')
 return H,M,A,O
end
local function attributionHold()
 local R=dofile('tests/prototype/orb_recovery_support.lua')
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
 assert(M.Start(6));local server=R.Server(H)
 H.service.RequestChoice=function()
  SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME)
  server.queue[#server.queue+1]={op=16,body=''}
 end
 H.Offer();H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
 for _=1,100 do if H.Count('orb-spend')==2 then break end;H.Advance(.25) end
 assert(H.Count('orb-spend')==2 and #R.SavedRow('orbRecoveryArchive')==1,
  'SETUP real bounded recovery archives the first receipt and submits the next')
 H.granted=H.Clone(H.granted)
 local oldKey=R.SavedRow('orbRecoveryArchive')[1].receipt.removed;local removed=false
 for _,entries in pairs(H.granted)do for i=#entries,1,-1 do
  if not removed and entries[i].spellId..':'..entries[i].quality==oldKey then
   table.remove(entries,i);removed=true
  end
 end end
 assert(removed,'SETUP actual archived source disappears in the later ownership observation')
 H.granted['Desired A']={{spellId=410002,quality=2}}
 H.Notify();A.Poll();M.Pump(true)
 local saved=R.Saved();local log=M.RunLog();local entry=log.entries[#log.entries]
 assert(saved and saved.attributionAmbiguous and entry.state=='unknown'
  and entry.reason:find('earlier unconfirmed',1,true),
  'SETUP actual older-result ambiguity reaches the persistent attribution hold')
 return H,M,A,O
end
-- Actual final-review F1: the first changed binding/context is recorded, but
-- the subsequent identical held pumps must not alternate writer reasons.
local function changedHold(setup,native)
 local H,M,A,O=setup();local revision=M.RunLog().revision
 if native then H.perks.serverActiveSlot=2;H.Notify();A.Poll()
 elseif H.perks.serverBuildSlots and H.perks.serverBuildSlots[1]
  and #(H.perks.serverBuildSlots[1].echoes or {})>0 then
  assert(A.SetLoadoutWishlistIdentity(1,'Changed while held',{{spellId=410004,quality=3,stacks=1}}))
 else assert(A.SetFirstLoadoutWishlistIdentity('Changed while held',{{spellId=410004,quality=3,stacks=1}}))end
 H.Advance(.25);M.Pump(true)
 local view=M.CompactStatus()
 assert(M.RunLog().revision>revision and view.pending and not view.running and not view.canResume,
  'SETUP first real binding/context change records a hold and removes Resume authority')
 return H,M,A,O
end
for _,case in ipairs({
 {'completion hold',completionHold},{'attribution hold',attributionHold},
 {'completed hold then assignment change',function()return changedHold(completionHold)end},
 {'attribution hold then assignment change',function()return changedHold(attributionHold)end},
 {'attribution hold then native slot change',function()return changedHold(attributionHold,true)end},
})do
 local ok,err=pcall(heldLog,case[1],case[2])
 if not ok then logFailures[#logFailures+1]=tostring(err) end
end
if #logFailures>0 then error(table.concat(logFailures,'\n'),0)end
print('PASS R6a3 persistent hold revision stability and real Stop transitions')

-- R6a4: a temporary assignment display failure is not an observation of the
-- choice getter. Keep an already classified post-archive fact across that
-- failure; a real unavailable state read must still withhold spending.
local statusFailures={}
for _,fault in ipairs({'assignment','state'})do
 local ok,err=pcall(function()
  local R=dofile('tests/prototype/orb_recovery_support.lua')
  local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
  assert(M.Start(6));local server=R.Server(H)
  H.service.RequestChoice=function()
   SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME)
   server.queue[#server.queue+1]={op=16,body=''}
  end
  H.Offer();H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
  for _=1,100 do
   local archive=R.SavedRow('orbRecoveryArchive')
   if archive and #archive==1 then break end
   H.Advance(.25)
  end
  assert(H.Count('orb-spend')==1 and #R.SavedRow('orbRecoveryArchive')==1,
   'SETUP pause in actual archive-to-next-command gap')
  assert(M.Pause());assert(M.CompactStatus().canResume,
   'SETUP a classified quiet post-recovery observation offers explicit Resume')
  local assignment,read=A.AssignedWishlist,A.Orbs.Read;local reads=0
  A.Orbs.Read=function(...)
   reads=reads+1
   if fault=='state' then return nil,'Synthetic unavailable state read','state' end
   return read(...)
  end
  if fault=='assignment' then
   A.AssignedWishlist=function()return{state='restoring',note='Synthetic assignment restore wait'}end
  end
  local called,view=pcall(M.Status,false)
  A.AssignedWishlist=assignment;A.Orbs.Read=read
  assert(called and view.error and not view.canStart and not view.canResume,
   'SETUP display reports the actual temporary refusal without a start/resume affordance')
  assert(reads==(fault=='assignment' and 0 or 1),
   'SETUP only the real state failure attempted to sample the choice getter')
  print('SETUP R6a4 '..fault..' display failure PASS')
  local requests=server.requests
  if fault=='assignment' then
   assert(M.Resume() and H.Count('orb-spend')==2,
    'EXPECT assignment-only display failure does not erase the retained choice observation')
  else
   assert(not M.Resume() and H.Count('orb-spend')==1,
    'GUARD actual state read failure still withholds the unclassified permit')
   server.Push(16,'')
   assert(H.Count('orb-spend')==1 and M.Resume() and H.Count('orb-spend')==2,
    'GUARD only a genuinely new exact empty observation restores explicit Resume')
  end
  assert(server.requests==requests,'GUARD display failure/Resume creates no replacement observation query')
  assert(M.CompactStatus().recoveries==1 and #R.SavedRow('orbRecoveryArchive')==1,
   'GUARD display handling does not fabricate recovery or archive progress')
  M.Stop()
 end)
 if not ok then statusFailures[#statusFailures+1]=fault..': '..tostring(err)end
end
if #statusFailures>0 then error(table.concat(statusFailures,'\n'),0)end
print('PASS R6a4 non-observation display failure and actual state-failure control')

-- R6a5: legacy explicit Continue retains the original raw entry/archive caps.
-- Optional future diagnostics may stop at those caps; they cannot remove the
-- only existing exit for a genuine restored no-choice receipt.
do
 local R=dofile('tests/prototype/orb_recovery_support.lua')
 local function bytes(t)
  local n=0
  for k,v in pairs(t)do
   n=n+#tostring(k)
   if type(v)=='table' then n=n+bytes(v)
   elseif type(v)=='string' then n=n+#v
   elseif type(v)=='number' or type(v)=='boolean' then n=n+8 end
  end
  return n
 end
 local function ready(padding,history)
  local H,M,A,O=R.S.Fresh();R.S.SpendOfferNoChoice(H,M,A,O)
  M=R.Reload(H,function()
   assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)
    if padding then row.orbRefinement.pending.legacyData=string.rep('x',padding)end
    if history then row.orbRecoveryArchive=H.Clone(history)end
   end))
  end)
  H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
  local server=R.Server(H);R.S.Pass(H,M,A,2)
  assert(M.ContinueView().eligible,'SETUP genuine restored spent/no-choice receipt has its original explicit exit')
  local original=H.Clone(R.Saved());assert(M.ContinueBegin())
  for _=1,100 do if M.ContinueView().stage=='ready' then break end;H.Advance(.25)end
  assert(M.ContinueView().stage=='ready','SETUP actual quiet two-refresh check reaches explicit consent')
  return H,M,A,O,server,original
 end
 local H,M,A,O,server,original=ready()
 assert(M.ContinueConfirm(M.ContinueView().token),'SETUP small genuine legacy entry archives through production')
 local seed=H.Clone(R.SavedRow('orbRecoveryArchive')[1]);local baseBytes=bytes(seed)
 server.Push(16,'late observation');H.Advance(2);M.Pump(true)
 assert(R.SavedRow('orbRecoveryArchive')[1].lateN==1,
  'EXPECT positive control actually executes the late-annotation producer after an unpadded exit')
 assert(baseBytes<5500,'SETUP production envelope leaves room for meaningful legacy boundary cases')
 local issues={}
 for _,case in ipairs({'near-entry','near-archive','raw-too-large'})do
  local ok,err=pcall(function()
   local history,padding
   if case=='near-entry' then padding=6100-baseBytes-#'legacyData'
   elseif case=='raw-too-large' then padding=6300-baseBytes-#'legacyData'
   else
    history={};local target=math.floor((28672-baseBytes-#'legacyData'-1-200)/5)
    for i=1,5 do
     history[i]=H.Clone(seed)
     history[i].legacyEnvelope=string.rep('e',target-baseBytes-#'legacyEnvelope')
     assert(bytes(history[i])==target and target<6144,'SETUP genuine older entry retains opaque bounded envelope')
    end
    padding=1
   end
   local H,M,A,O,server,original=ready(padding,history)
   local expected=baseBytes+#'legacyData'+padding
   assert((case=='raw-too-large' and expected>6144) or (case~='raw-too-large' and expected<=6144),
    'SETUP exact raw entry lies on the intended original-cap side')
   if history then
    local total=expected;for _,e in ipairs(history)do total=total+bytes(e)end
    assert(#history==5 and total<=28672 and total>28100,
     'SETUP original total byte bound admits this near-full legacy archive')
   end
   print('SETUP R6a5 '..case..' PASS raw-entry='..expected)
   local accepted,reason=M.ContinueConfirm(M.ContinueView().token)
   if case=='raw-too-large' then
    assert(not accepted and reason=='entry_too_large' and R.Same(R.Saved(),original)
     and M.BlocksOrdinary(),'GUARD actual raw oversize still preserves/refuses the original receipt')
   else
    assert(accepted,'EXPECT '..case..' explicit legacy exit preserves original caps: '..tostring(reason))
    assert(not R.Saved() and not M.BlocksOrdinary(),'EXPECT durable explicit exit releases the pending hold')
    local archive=R.SavedRow('orbRecoveryArchive');local added=archive[#archive]
    assert(#archive==(history and 6 or 1) and bytes(added)<=6144,
     'GUARD archive stays within original entry count and raw entry bytes')
    assert(R.Same(added.receipt,original),'GUARD original opaque receipt remains exact and unconfirmed')
    if history then for i,e in ipairs(history)do
     assert(R.Same(archive[i],e),'GUARD explicit exit neither evicts nor rewrites older records')
    end end
    local before=H.Clone(archive)
    for _=1,4 do server.Push(1220,'bad',{sender='OtherSender'})end
    M.Pump(true)
    local after=R.SavedRow('orbRecoveryArchive');local total=0
    for _,e in ipairs(after)do total=total+bytes(e);assert(bytes(e)<=6144,'GUARD optional late evidence remains entry bounded')end
    assert(total<=28672 and R.Same(after[#after].receipt,original),
     'GUARD later optional annotations cannot exceed archive caps or rewrite the receipt')
    assert(R.Same(after,before),'GUARD actual rejected late-evidence envelope cannot overrun near-cap entries or total')
   end
   assert(H.Count('orb-spend')==1 and H.Count('take')==0,'GUARD explicit exit and passive annotations send no gameplay action')
  end)
  if not ok then issues[#issues+1]=case..': '..tostring(err)end
 end
 if #issues>0 then error(table.concat(issues,'\n'),0)end
 print('PASS R6a5 original explicit legacy byte caps and bounded optional late evidence')
end

-- R6a6: count actual archive/capacity traversal function calls, not global
-- table.sort lookups. The hook observes production functions by identity,
-- never replaces/calls them, and proves itself on each cold positive control.
do
 local R=dofile('tests/prototype/orb_recovery_support.lua')
 local H,M,A,O=R.S.Fresh();R.S.SpendOfferNoChoice(H,M,A,O)
 M=R.Reload(H);H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
 R.Server(H);R.S.Pass(H,M,A,2);assert(M.ContinueBegin())
 for _=1,100 do if M.ContinueView().stage=='ready' then break end;H.Advance(.25)end
 assert(M.ContinueConfirm(M.ContinueView().token),'SETUP real validated archive seed')
 local seed=H.Clone(R.SavedRow('orbRecoveryArchive')[1])
 local function upvalue(fn,want)
  for i=1,100 do local name,value=debug.getupvalue(fn,i)
   if name==want then return value end;if not name then break end
  end
  error('SETUP missing real traversal boundary '..want)
 end
 local function measured(M,fn)
  local rc=upvalue(M.Pump,'RC')
  local canon=upvalue(rc.memory,'canonText');local measure=upvalue(rc.entryBudget,'measure')
  local capacity=rc.receiptCapacity;local counts={canonical=0,measure=0,capacity=0}
  local getinfo=debug.getinfo;local wasJit=jit.status();jit.off();jit.flush()
  debug.sethook(function()
   local f=getinfo(2,'f').func
   if f==canon then counts.canonical=counts.canonical+1
   elseif f==measure then counts.measure=counts.measure+1
   elseif f==capacity then counts.capacity=counts.capacity+1 end
  end,'c')
  local ok,err=pcall(fn)
  debug.sethook();if wasJit then jit.on()end
  assert(ok,err);return counts
 end
 local issues={}
 for _,kind in ipairs({'assigned-live-pending','idle-preflight'})do
  local ok,err=pcall(function()
   local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
   if kind=='assigned-live-pending' then assert(M.Start(6))end
   local archive={};for i=1,(kind=='assigned-live-pending' and 8 or 1)do archive[i]=H.Clone(seed)end
   assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)row.orbRecoveryArchive=archive end))
   assert(A.AssignedWishlist().state=='ready','SETUP actual assigned Wishlist reaches the status/preflight boundary')
   local cold=measured(M,function()M.Pump(true);M.Status(false)end)
   assert(cold.canonical>0 and cold.measure>0,
    'SETUP positive traversal control observes actual cold validation/measurement')
   if kind=='idle-preflight' then assert(cold.capacity>0 and M.Status(false).canStart,
    'SETUP actual idle preflight reaches prospective receipt capacity')end
   print('SETUP R6a6 '..kind..' PASS cold='..cold.canonical..'/'..cold.measure..'/'..cold.capacity)
   local hot=measured(M,function()for _=1,8 do M.Pump(true);M.Status(false);H.Advance(.25)end end)
   print('WORK R6a6 '..kind..' canonical='..hot.canonical..' measure='..hot.measure..' capacity='..hot.capacity)
   if hot.canonical~=0 or hot.measure~=0 or hot.capacity~=0 then
    issues[#issues+1]='EXPECT '..kind..': stable interleaved Status/Pump avoids repeated canonical/capacity traversals'
   end
   if kind=='idle-preflight' then
    local approval
    local action=measured(M,function()approval=M.Prepare('assigned')end)
    assert(approval and action.capacity>0,
     'GUARD actual new approval performs fresh prospective capacity despite the display cache')
    assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)row.orbRecoveryArchive[1].cd='damaged'end))
    local view;local revised=measured(M,function()view=M.Status(false)end)
    assert(revised.canonical>0 and not view.canStart and view.startReason:find('cannot be verified',1,true),
     'GUARD a real archive mutation invalidates validation and refuses new approval')
    assert(R.SavedRow('orbRecoveryArchive')[1].cd=='damaged',
     'GUARD invalid history is preserved, never repaired or evicted by observation')
    local damagedHot=measured(M,function()for _=1,8 do M.Pump(true);M.Status(false);H.Advance(.25)end end)
    print('WORK R6b7 invalid-history canonical='..damagedHot.canonical..' measure='..damagedHot.measure)
    if damagedHot.canonical~=0 or damagedHot.measure~=0 then
     issues[#issues+1]='EXPECT stable bounded invalid history reuses its negative verdict instead of repeatedly hashing'
    end
    assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)row.orbRecoveryArchive[1].cd=seed.cd end))
    local restored;local repaired=measured(M,function()restored=M.Status(false)end)
    assert(repaired.canonical>0 and restored.canStart,
     'GUARD real corrected history invalidates the negative verdict and revalidates from contents')
   end
   assert(H.Count('orb-spend')==(kind=='assigned-live-pending' and 1 or 0) and H.Count('take')==0,
    'GUARD observation work changes no gameplay actions')
  end)
  if not ok then issues[#issues+1]=kind..': '..tostring(err)end
 end
 if #issues>0 then error(table.concat(issues,'\n'),0)end
 print('PASS R6a6 real assigned interleaving, positive traversal counters and fresh action/mutation controls')
end

-- R6a9a: the next same-pair decision after a real automatic archive is already
-- attribution-ambiguous, before any ownership result arrives. That possibility
-- is not observed progress and does not promise another available recovery.
do
 local R=dofile('tests/prototype/orb_recovery_support.lua')
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
 local original=H.Clone(H.granted);assert(M.Start(6));local server=R.Server(H)
 H.service.RequestChoice=function()
  SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME)
  server.queue[#server.queue+1]={op=16,body=''}
 end
 H.Offer();H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
 for _=1,100 do if H.Count('orb-spend')==2 then break end;H.Advance(.25)end
 assert(H.Count('orb-spend')==2 and #R.SavedRow('orbRecoveryArchive')==1,
  'SETUP actual lost-result archive reaches a fresh second submission')
 H.Offer();H.Advance(.25);M.Pump(true)
 assert(R.Saved().attributionAmbiguous and H.Count('take')==2 and R.Same(H.granted,original),
  'SETUP actual same-pair selection is ambiguous with no ownership progress at all')
 local before=M.Status(false);local issues={}
 assert(before.state=='WAIT_RESULT' and before.progress.rolledMissing==2,
  'SETUP real waiting result still lacks both required copies')
 print('SETUP R6a9a ambiguity before any observed gain PASS')
 if before.reason:find('show progress',1,true) or before.reason:find('recorded gain',1,true)then
  issues[#issues+1]='EXPECT pre-attributed ambiguity does not claim observed ownership progress'
 end
 if before.reason:find('Waiting for bounded recovery',1,true)then
  issues[#issues+1]='EXPECT status does not promise another recovery solely from an ambiguity flag'
 end
 H.Result(410002,2);M.Pump(true)
 local observed=M.Status(false)
 assert(observed.pending and observed.progress.rolledMissing==1 and H.Count('orb-spend')==2,
  'SETUP actual ownership gain remains unattributed with the receipt and exposure retained')
 if not observed.reason:find('recorded gain',1,true)then
  issues[#issues+1]='EXPECT actual attribution hold accurately names the now-observed gain'
 end
 assert(observed.spent+observed.reserved+observed.uncertain>=2,
  'GUARD text change does not refund or hide exposure')
 M.Stop();assert(H.Count('orb-spend')==2 and H.Count('take')==2,
  'GUARD truthful status neither repeats a spend/choice nor erases Stop authority')
 if #issues>0 then error(table.concat(issues,'\n'),0)end
 print('PASS R6a9a potential ambiguity versus real observed ownership gain')
end

-- R6a9b: a compact Resume affordance cannot claim an old classified permit
-- while a newer real transport event is still unclassified. Compact reads
-- themselves remain scalar/passive; the full view/action classify the backlog.
do
 local R=dofile('tests/prototype/orb_recovery_support.lua')
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
 assert(M.Start(6));local server=R.Server(H)
 H.service.RequestChoice=function()
  SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME)
  server.queue[#server.queue+1]={op=16,body=''}
 end
 H.Offer();H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
 for _=1,100 do local a=R.SavedRow('orbRecoveryArchive');if a and #a==1 then break end;H.Advance(.25)end
 assert(H.Count('orb-spend')==1 and #R.SavedRow('orbRecoveryArchive')==1 and M.Pause(),
  'SETUP actual archive-to-command gap is deliberately paused')
 assert(M.CompactStatus().canResume,'SETUP a classified quiet permit initially offers Resume')
 server.Push(16,'malformed choice data')
 local read,status=A.Orbs.Read,A.Orbs.TransportStatus;local reads,copies=0,0
 A.Orbs.Read=function(...)reads=reads+1;return read(...)end
 A.Orbs.TransportStatus=function(...)copies=copies+1;return status(...)end
 local view
 for _=1,8 do view=M.CompactStatus()end
 A.Orbs.Read=read;A.Orbs.TransportStatus=status
 assert(reads==0 and copies==0,'BOUND compact backlog guard performs no full state/status-map reads')
 print('SETUP R6a9b newer unclassified real choice event PASS')
 local issues={}
 if view.canResume then issues[#issues+1]='EXPECT compact view withholds Resume while its retained backlog is unclassified'end
 assert(not M.Resume() and H.Count('orb-spend')==1,
  'GUARD the actual action already rejects the newer malformed observation without consuming a spend')
 server.Push(16,'')
 assert(H.Count('orb-spend')==1,'GUARD newer observation alone never resumes the paused run')
 assert(M.Status(false).canResume and M.CompactStatus().canResume,
  'GUARD actual full classification restores the affordance after a genuinely newer exact empty reply')
 assert(M.Resume() and H.Count('orb-spend')==2,
  'GUARD one explicit action still uses a quiet classified permit at most once')
 M.Stop()
 if #issues>0 then error(table.concat(issues,'\n'),0)end
 print('PASS R6a9b compact backlog truth with passive bounds and fresh explicit-action control')
end

-- R6b4: these faults occur AFTER real durable admission but BEFORE either
-- protected host invocation. Spend cleanup must not invent uncertain use;
-- selection rejection must retain the actual preceding spend and no reselect.
do
 local R=dofile('tests/prototype/orb_recovery_support.lua');local failures={}
 local function expect(v,message)if not v then failures[#failures+1]=message end end
 local function quiet(H)
  local server=R.Server(H)
  H.service.RequestChoice=function()
   SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME)
   server.queue[#server.queue+1]={op=16,body=''}
  end
  return server
 end
 local ok,err=pcall(function()
  local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={};quiet(H);assert(M.UseAssignedWishlist())
  local read=A.Orbs.Read;local hit,admitted,removed=false,false
  A.Orbs.Read=function(...)
   local saved=R.Saved()
   if not hit and saved and H.Count('orb-spend')==0 then
    hit=true;removed=saved.removed
    admitted=M.CompactStatus().reserved==1 and saved.spendConfirmed~=true
    error('synthetic pre-host validation read failure')
   end
   return read(...)
  end
  local contained=pcall(H.Approve,6,false)
  A.Orbs.Read=read
  assert(hit and admitted,'SETUP actual Adapter validation reads after saving an unsent reservation')
  print('SETUP R6b4 known-unsent spend validation failure PASS')
  local v=M.Status(false)
  expect(contained,'EXPECT pre-host validation throw does not escape the public action')
  expect(not v.pending and not R.Saved() and v.state=='PAUSED',
   'EXPECT known-unsent validation failure clears the receipt and deliberately pauses')
  expect(v.spent==0 and v.reserved==0 and v.uncertain==0,
   'EXPECT pre-host validation failure produces no known or uncertain spending exposure')
  local diagnostic=Nexus.Errors.Latest()
  expect(diagnostic and diagnostic.source=='OrbAdapter.SpendValidation'
   and diagnostic.message:find('synthetic pre-host validation read failure',1,true),
   'EXPECT validation cause is retained by the actual bounded diagnostic owner')
  H.Advance(20)
  v=M.CompactStatus();local archive=R.SavedRow('orbRecoveryArchive')
  expect(H.Count('orb-spend')==0 and not R.Saved() and (not archive or #archive==0)
   and v.uncertain==0 and v.recoveries==0,
   'EXPECT definitely-unsent validation cannot later become a fabricated uncertain archive or automatic spend')
  local resumed=M.Resume();local first
  for _,a in ipairs(H.actions)do if a[1]=='orb-spend'then first=a[2];break end end
  expect(resumed and H.Count('orb-spend')==1 and first==tonumber(removed:match('^(%d+):')),
   'EXPECT explicit Resume uses the restored original source quota for the first actual host invocation')
  M.Stop()
 end)
 if not ok then failures[#failures+1]='SETUP spend validation: '..tostring(err)end
 for _,fault in ipairs({'throw','unavailable'})do
  local ok,err=pcall(function()
   local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={};quiet(H)
   local spend=A.Orbs.Spend;local hit,admitted=false,false
   A.Orbs.Spend=function(...)
    local archive=R.SavedRow('orbRecoveryArchive')
    if not hit and H.Count('orb-spend')==1 and archive and #archive==1 then
     hit=true;admitted=R.Saved()~=nil and M.CompactStatus().reserved==1
     local read=A.Orbs.Read;A.Orbs.Read=function()
      if fault=='throw'then error('synthetic post-recovery validation read failure')end
      return nil,'synthetic post-recovery unavailable read','state'
     end
     local ok,accepted,kind,reason,status=pcall(spend,...);A.Orbs.Read=read
     if not ok then error(accepted,0)end
     return accepted,kind,reason,status
    end
    return spend(...)
   end
   assert(M.Start(6));H.Offer();H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
   for _=1,100 do if hit then break end;H.Advance(.25)end
   A.Orbs.Spend=spend
   assert(hit and admitted,'SETUP actual post-archive next receipt precedes the failing validation read')
   print('SETUP R6b4 post-recovery '..fault..' validation PASS')
   local v=M.CompactStatus()
   expect(not v.pending and not R.Saved() and not v.canResume,
    'EXPECT post-recovery '..fault..' observation failure clears unsent receipt without claiming fresh permission')
   expect(v.spent==1 and v.reserved==0 and v.uncertain==0 and v.recoveries==1
    and v.unconfirmedResults==1 and #R.SavedRow('orbRecoveryArchive')==1 and H.Count('orb-spend')==1,
    'EXPECT post-recovery '..fault..' validation creates no exposure, progress, duplicate archive or host call')
   M.Stop()
  end)
  if not ok then failures[#failures+1]='SETUP post-recovery '..fault..': '..tostring(err)end
 end
 local ok,err=pcall(function()
  local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={};assert(M.UseAssignedWishlist());H.Approve(6,false)
  local select=A.Orbs.Select;local hit,admitted,actualThrow=false,false,false
  A.Orbs.Select=function(token,index,board,id,guard)
   return select(token,index,board,id,function(live)
    local saved=R.Saved();hit=true
    admitted=saved and saved.spendConfirmed==true and saved.selectionAttempted==true
     and H.Count('orb-spend')==1 and H.Count('take')==0
    local assigned=A.AssignedWishlist
    A.AssignedWishlist=function()error('synthetic pre-host selection guard failure')end
    local ok,allowed,why=pcall(guard,live);A.AssignedWishlist=assigned
    actualThrow=not ok
    if not ok then error(allowed,0)end
    return allowed,why
   end)
  end
  local contained=pcall(H.Offer);A.Orbs.Select=select
  assert(hit and admitted and actualThrow,'SETUP real selection guard throws after persisting a choice proposal and a real spend')
  print('SETUP R6b4 known-unsent selection guard failure PASS')
  local v=M.Status(false);local saved=R.Saved()
  expect(contained,'EXPECT selection guard exception is contained before SelectPerk')
  expect(v.pending and saved and saved.spendConfirmed and saved.selectionRefused==true
   and saved.choiceMayHaveBeenSent==false and saved.selectionAmbiguous==false,
   'EXPECT known-unsent selection is recorded distinctly while retaining the actual spend receipt')
  expect(v.spent==1 and v.reserved==0 and v.uncertain==0 and H.Count('orb-spend')==1 and H.Count('take')==0,
   'EXPECT selection guard failure neither erases real spend nor invents a selection/exposure')
  local diagnostic=Nexus.Errors.Latest()
  expect(diagnostic and diagnostic.source=='OrbAdapter.SelectGuard'
   and diagnostic.message:find('synthetic pre-host selection guard failure',1,true),
   'EXPECT actual bounded diagnostic owner retains the selection guard cause')
  H.Advance(20)
  expect(not M.Resume() and H.Count('orb-spend')==1 and H.Count('take')==0,
   'EXPECT held known-unsent selection is not automatically retried or resumed')
  M.Stop()
 end)
 if not ok then failures[#failures+1]='SETUP selection guard: '..tostring(err)end
 if #failures>0 then error(table.concat(failures,'\n'),0)end
 print('PASS R6b4 exact pre-host containment and no invented exposure/progress or automatic selection')
end

-- R6b5: an inert loading hold must exist before the lazy full receipt owner.
-- Its observations must not be relabeled as retained receipt lifecycle epochs.
do
 local S=dofile('tests/prototype/orb_loadout_hold_support.lua');local failures={}
 local function expect(v,msg)if not v then failures[#failures+1]=msg end end
 for _,mode in ipairs({'cold','warm','pause','stop','expired'})do
  local H,M,A,O=S.Fresh()
  if mode=='warm'then
   H.OrbPlan();H.Approve(1,false);H.Offer();H.Result(410002,2);M.Stop()
   H.OrbPlan({{spellId=410004,quality=3,stacks=1}})
  else H.OrbPlan({{spellId=410002,quality=2,stacks=1}})end
  local before=M.BoundaryDiagnostics();local actions=H.Count('orb-spend')
  assert(before.lifecycleObserved==(mode=='warm'),'SETUP lazy owner versus warm receipt owner')
  H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(.5)
  local observed=M.BoundaryDiagnostics()
  assert(observed.lifecycleObserved==(mode=='warm'),'SETUP passive hold does not activate full receipt owner')
  if mode~='warm'then assert(observed.epoch==0,'SETUP no fabricated full-owner epoch')end
  if mode=='expired'then H.Advance(3)end
  assert(M.Start(1),'SETUP R6 retains explicit approval rather than changing Start acceptance')
  print('SETUP R6b5 '..mode..' actual loading event and explicit approval PASS')
  if mode=='expired'then
   expect(H.Count('orb-spend')==actions+1,'expired cold hold permits one explicitly approved host submission')
  else
   expect(H.Count('orb-spend')==actions,'no host submission at half-second after '..mode..' entry')
   if mode=='pause'then assert(M.Pause())elseif mode=='stop'then assert(M.Stop())end
   H.Advance(2)
   expect(H.Count('orb-spend')==actions,'no host submission before three-second '..mode..' hold expires')
   H.Advance(.6)
   if mode=='pause'or mode=='stop'then
    expect(H.Count('orb-spend')==actions,'loading hold expiry does not undo deliberate '..mode)
    if mode=='pause'then
     expect(M.Resume()==true and H.Count('orb-spend')==actions+1,'only explicit Resume restarts paused approval')
    else expect(not M.Resume(),'Stop does not become resumable when loading hold expires')end
   else
    expect(H.Count('orb-spend')==actions+1,'same explicit '..mode..' approval submits once after hold')
   end
  end
  M.Stop()
 end
 if #failures>0 then error(table.concat(failures,'\n'),0)end
 print('PASS R6b5 cold and warm loading hold, truthful lazy receipt epochs, expiry and deliberate Pause/Stop')
end
