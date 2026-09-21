local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(80,40);T.Load()
local restarts=0;local base=Nexus.CommunityBuilds.Init
Nexus.CommunityBuilds.Init=function(...)
 local r=base(...);if r and r.phase=='source-changed'then restarts=restarts+1 end;return r
end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().coreReady end)
T.Until(H,function()return Nexus.startupTiming.communityPhase=='scan'end)
local authority=Nexus.MainInternals.StoreAuthorityOwner
local ok,why=authority.UpdateStateV1(function(row)row.changedDuringStartup='kept'end)
assert(ok,'local Store update must remain supported: '..tostring(why))
local changed=H.Clone(NexusDB.authorityBundle.communityBuilds['synthetic-startup-1'])
changed.title='Updated during preparation'
local put,reason,ticket=Nexus.BuildCatalog.Put(changed,{source='sync'})
assert(put==true or put==nil and reason=='ROOT_MUTATION_PENDING','real catalog update accepted: '..tostring(reason))
T.Until(H,function()return Nexus.StartupStatus().state=='ready'end)
assert(Nexus.Store.State().changedDuringStartup=='kept','local update lost after background completion')
assert(T.Count(NexusDB.authorityBundle.communityBuilds)==80,'background lost catalog rows')
assert(restarts>0,'generation-change restart branch was not exercised')
assert(NexusDB.authorityBundle.communityBuilds['synthetic-startup-1'].title=='Updated during preparation','catalog edit lost')
assert(Nexus.lastError==nil,'source change should not latch shared startup failure: '..tostring(Nexus.lastError))
print('PASS legitimate local edit during shared startup; restart observations='..restarts)
