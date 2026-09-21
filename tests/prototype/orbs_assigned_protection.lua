local H=dofile('tests/prototype/orbs_support.lua');local A,M=H.A,H.M
local entries={{spellId=410002,quality=2,stacks=2}}
assert(A.SetFirstLoadoutWishlistIdentity('Local permanent design',entries))
-- This is the real durable sidecar used by the editor's ordinary-only upload.
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
 s.lockDesignTargetsBySlot={[A.WishlistKey(entries)]={[410007]=true}}
end))
H.granted={Permanent={{spellId=410007,quality=2}}};H.Notify();A.Poll()
local s=M.Status();assert(s.progress.permanentMissing==1,'assigned target includes the saved permanent design')
assert(not M.Start() and H.Count('orb-spend')==0,'automatic pool protects the only future permanent copy')
H.granted.Permanent[2]={spellId=410007,quality=2};H.Notify();A.Poll()
assert(M.Exclude('410007:2',true));assert(not M.Start(),'automatic selection respects explicit exclusions')
assert(M.ClearExclusions());assert(M.Start(3));assert(H.O.source==410007,'only real excess reaches actual ID-only spend')
H.Offer();H.Result(410002,2);M.Pump()
assert(M.Status().state=='NO_SOURCES' and H.Count('orb-spend')==1,'post-result protection retains the required permanent copy')
M.Stop()
H.granted.Permanent[2]={spellId=410007,quality=1};H.Notify();A.Poll()
assert(not M.Start(),'mixed qualities still block ID-only sacrifice')
print('PASS automatic source pool includes durable permanent targets, exclusion and post-result protection')
