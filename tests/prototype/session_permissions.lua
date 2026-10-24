-- EXPECT semantic replacement from a43cf27: classified loading preserves only
-- existing authorization; unclassified entry/reload still revoke it (GUARD).
local H=dofile('tests/prototype/orbs_support.lua');local M=H.M
assert(not Nexus.RecomputeStats().autoEnabled and not M.Status().running,'startup permissions OFF')
SlashCmdList.NEXUS('auto');assert(Nexus.RecomputeStats().autoEnabled,'explicit ordinary permission control')
-- A loading screen inside this session keeps the ordinary selection; its
-- actions are held (automation_world_transition). No Orb run is started.
H.Fire('PLAYER_LEAVING_WORLD');assert(Nexus.RecomputeStats().autoEnabled,'leaving world keeps the ordinary selection')
H.Fire('PLAYER_ENTERING_WORLD');assert(Nexus.RecomputeStats().autoEnabled and H.Count('orb-spend')==0 and not M.Status().running,'world entry starts no Orb run')
H.Fire('PLAYER_ENTERING_WORLD')
assert(not Nexus.RecomputeStats().autoEnabled,'reconnect without a leave notification is OFF')
SlashCmdList.NEXUS('auto');H.Fire('PLAYER_LOGOUT');assert(not Nexus.RecomputeStats().autoEnabled,'logout revokes ordinary permission')
H.OrbPlan();assert(M.Start(2));H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD')
assert(M.Status().running and M.Status().pending and H.Count('orb-spend')==1,'a classified loading screen retains only the approved Orb run')
SlashCmdList.NEXUS('auto');assert(not Nexus.RecomputeStats().autoEnabled,'ordinary Auto stays OFF while the Orb receipt is unresolved')
H.Fire('PLAYER_ENTERING_WORLD')
assert(not M.Status().running and M.Status().pending,'world entry without a preceding leave revokes Orb authorization')
H.Offer();assert(H.Count('take')==0 and H.Count('orb-spend')==1)
print('PASS session-only ordinary/Orb permissions: kept across a loading screen, revoked on logout and unclassified entry, pending exposure retained')
