local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
H.OrbPlan({{spellId=410004,quality=3,stacks=1}});H.Approve(2,true)
local id=O.source;local q=H.db[id].quality
H.Offer({{spellId=id,quality=q},{spellId=410008,quality=1},{spellId=410001,quality=1}})
assert(H.Count('take')==1)
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
H.granted=H.Clone(H.granted);H.Notify();A.Poll();M.Pump()
local s=M.Status()
assert(s.pending and s.state=='PAUSED' and not s.running,'B2: equal-content same-ID result must pause unresolved')
assert(s.reason:find('same-ID',1,true) and s.reason:find('stale',1,true),'specific missing confirmation evidence explained')
assert(s.spent+s.reserved==1 and Nexus.Store.State().orbRefinement.pending,'budget exposure and recovery receipt preserved')
for i=1,3 do H.now=H.now+4;assert(M.Recheck());M.Pump() end
assert(not M.Resume() and not M.Prepare(),'ambiguity never permits retry or another run')
M.Stop();H.now=H.now+4;M.Recheck();M.Pump()
assert(M.Status().pending and H.Count('orb-spend')==1 and H.Count('take')==1,'Stop and repeated fresh-table refresh cannot erase exposure or retry')
print('PASS B2 post-selection same-ID stale snapshots remain unresolved without mutation')
