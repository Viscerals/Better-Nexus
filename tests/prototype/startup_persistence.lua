local T=dofile('tests/prototype/startup_support.lua')
local function serialize(v,parents)
 if type(v)=='string'then return string.format('%q',v)end
 if type(v)=='number'or type(v)=='boolean'then return tostring(v)end
 assert(type(v)=='table','only serializable synthetic data')
 parents=parents or {};assert(not parents[v],'cycle cannot be saved');parents[v]=true
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b)end)
 local out={'{'};for _,k in ipairs(keys)do out[#out+1]='['..serialize(k,parents)..']='..serialize(v[k],parents)..','end
 out[#out+1]='}';parents[v]=nil;return table.concat(out)
end
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(12,40)
NexusDB.nexusNativeRecoveryRelayPairs764={chars={Synthetic={relayPairs={[string.rep('r',764)]={preserved=true}}}}}
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().coreReady end)
local authority=Nexus.MainInternals.StoreAuthorityOwner
assert(authority.UpdateStateV1(function(row)row.prototypePersistence={value=53}end))
local saved=serialize(NexusDB)
-- Fresh runtime state, like an offline module reload, with round-tripped
-- literal data. This is NOT a real client reload or historical-backup test.
Nexus=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H2=dofile('tests/prototype/harness.lua')
NexusDB=assert(loadstring('return '..saved))()
T.Load();H2.Fire('ADDON_LOADED','Nexus');H2.Fire('PLAYER_ENTERING_WORLD')
T.Until(H2,function()return Nexus.StartupStatus().state=='ready'end)
assert(Nexus.Store.State().prototypePersistence.value==53,'local save before shared-ready survives reload')
assert(T.Count(NexusDB.authorityBundle.communityBuilds)==12,'catalog retained through occupied-bundle reload')
assert(NexusDB.nexusNativeRecoveryRelayPairs764.chars.Synthetic.relayPairs[string.rep('r',764)].preserved,'existing archive untouched')
for i=1,40 do assert(NexusDB.authorityBundle.loadoutEvidence.entries['synthetic-preserved-'..i].keep==i)end
assert(Nexus.BuildCatalog.RootState().state=='ROOT_ADMITTED','real root re-admitted after reload')
print('PASS pre-background-ready save, fresh module reload, complete catalog and unknown archive preservation')
