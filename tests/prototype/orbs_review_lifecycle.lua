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
