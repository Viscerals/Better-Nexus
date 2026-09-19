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
