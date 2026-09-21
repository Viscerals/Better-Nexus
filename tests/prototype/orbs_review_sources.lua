-- B1: actual source suggestion, approval and ID-only adapter submission.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local function owned(n)
 H.granted={Permanent={}};for i=1,n do H.granted.Permanent[i]={spellId=410007,quality=2}end
 H.Notify();A.Poll()
end
H.OrbPlan({{spellId=410002,quality=2,stacks=2},{spellId=410007,quality=2,stacks=1,locked=true}})
owned(1);assert(M.SuggestSources())
assert(not M.Status().config.sources['410007:2'],'B1: acquired future permanent copy must not be suggested')
assert(not M.SetSource('410007:2',1),'B1: manual approval cannot waive required-copy protection')
assert(not M.Prepare() and H.Count('orb-spend')==0,'B1: no safe source means no approval or submission')
-- One rolled copy and one future permanent copy require two separate copies.
H.OrbPlan({{spellId=410002,quality=2,stacks=2},{spellId=410007,quality=2,stacks=1},
 {spellId=410007,quality=2,stacks=1,locked=true}})
owned(2);assert(M.SuggestSources());assert(not M.Prepare(),'one copy cannot satisfy both roles')
owned(3);assert(M.SuggestSources());assert(M.Status().config.sources['410007:2']==1,'only real excess approved')
assert(not M.SetSource('410007:2',2),'cannot overapprove excess')
assert(M.Exclude('410007:2',true));assert(M.SuggestSources());assert(not M.Prepare(),'explicit exclusion retained')
assert(M.ClearExclusions());assert(M.SuggestSources())
local p=assert(M.Prepare());owned(2)
assert(not M.Confirm(p.token) and H.Count('orb-spend')==0,'approval rechecks ownership')
owned(3);H.Approve(3,false)
assert(O.source==410007 and H.Count('orb-spend')==1,'real excess reaches actual ID-only adapter')
H.Offer();H.Result(410002,2);M.Pump()
assert(H.Count('orb-spend')==1 and M.Status().state=='NO_SOURCES','after result required copies remain protected')
M.Stop()
-- Same ID at multiple qualities cannot be selected by the ID-only spend API.
H.granted={Permanent={{spellId=410007,quality=1},{spellId=410007,quality=2},{spellId=410007,quality=2}}}
H.Notify();A.Poll();H.OrbPlan({{spellId=410002,quality=2,stacks=2}});assert(M.SuggestSources())
assert(not M.Prepare(),'ID-only source must not guess which quality is consumed')
print('PASS B1 exact roles/copies/quality, exclusion, real excess, approval and post-result spend guard')
