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
local function guardCase(name,ownerGetter,manual)
 local H,M,A,O=S.Fresh()
 H.perks.currentChoice={};H.OrbPlan({{spellId=410002,quality=2,stacks=2}})
 local B=A.Orbs;local spend=B.Spend;local ownerKey=Nexus.Store.CurrentOwnerKey
 local inGuard=false;local sawSaved=false;local sourceKey;local returnedKind,returnedStatus
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
 local ok=pcall(H.Approve,6,false,manual)
 inGuard=false;Nexus.Store.CurrentOwnerKey=ownerKey;B.Spend=spend
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
 local resumed=M.Resume()
 local first
 for _,action in ipairs(H.actions)do if action[1]=='orb-spend' then first=action[2];break end end
 expect(resumed and H.Count('orb-spend')==1,'EXPECT explicit Resume can make the first actual submission after the fault is removed')
 expect(first==tonumber(sourceKey:match('^(%d+):')),'GUARD known-unsent rejection restores the original manual source quota')
 M.Stop()
end
for _,case in ipairs({{'callback exception',false,false},{'runtime owner getter exception',true,true}})do
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
 local B=A.Orbs;local spend=B.Spend;local hit=false;local boundary
 B.Spend=function(token,key,expected,guard)
  local accepted,kind,reason,status=spend(token,key,expected,function(live)
   local archive=R.SavedRow('orbRecoveryArchive')
   if H.Count('orb-spend')==1 and archive and #archive==1 then
    assert(R.Saved() and M.CompactStatus().reserved==1,
     'SETUP real next unsent receipt follows the actual unconfirmed archive')
    hit=true
    local original=B.TransportStatus;B.TransportStatus=function()return nil end
    local ok,allowed,why=pcall(guard,live)
    B.TransportStatus=original
    assert(not ok,'SETUP real postCheck rejects unavailable transport inside the final guard')
    error(allowed,0)
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
