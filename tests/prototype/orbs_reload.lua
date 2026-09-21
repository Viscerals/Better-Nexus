local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false);H.Offer()
check(H.Count('orb-spend')==1 and H.Count('take')==1,'one accepted transaction before reload')
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and receipt.selectedKey=='410002:2' and receipt.spent==1,'passive recovery data records original result and usage')
H.Fire('PLAYER_LOGOUT')
check(not M.Status().running,'logout stops automatic intent')
-- Simulate fresh addon owners with the preserved passive saved receipt.
-- No previous runtime OnUpdate survives a real client reload.
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;H.M=M
local current=M.Status()
check(current.state=='RECOVERY' and current.pending and not current.running,'fresh owners begin in passive recovery, never spending')
check(M.BlocksOrdinary() and not M.Prepare(),'unresolved earlier operation blocks competing actions/new start')
local calls=H.Count('orb-spend');M.Pump();check(H.Count('orb-spend')==calls,'recovery Pump is read-only')
-- The original accepted target result arrives later through the real raw snapshot.
local source=O.source;local out=H.Clone(H.granted)
local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll()
M.Pump()
check(M.Status().state=='STOPPED' and not M.Status().pending,'fresh matching response can resolve previous transaction')
check(M.Status().spent==1 and H.Count('orb-spend')==calls,'recovery keeps exact spent accounting and no new spend')
check(not Nexus.Store.State().orbRefinement.pending,'settled receipt cleared')
check(Nexus.RecomputeStats().autoEnabled==false,'reload recovery does not enable ordinary auto')
check(not M.Resume(),'stopped recovered run needs new review')
print('PASS Orb reload passive receipt/fresh result/no automatic restart controls='..checks)
