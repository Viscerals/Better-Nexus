-- Decision C for the ROOT_SLOT_LIMIT report: when the shared catalog refuses
-- its root purely on saved capacity, local Wishlist and Echo tools start, the
-- refusal and its reason stay reported, Community/Leaderboard/Sync stay
-- unavailable, and the Community data is neither evicted, migrated nor
-- replaced by a bundle. Local session writes (character rows, missing default
-- settings, local logs) happen as in any normal start-up.
-- Any other root refusal keeps the previous all-or-nothing behavior.
-- Real TOC boot and admission path; synthetic records; no Orb service call.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Record(id)
 return {id=id,title='Synthetic '..id,author='Other-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1}}}
end
local function Overlay(n)local m={};for i=1,n do m['syn-'..i]=Record('syn-'..i) end;return m end
local overlay=Overlay(2049)
local db={settingsVersion=2,settings={autoPick=false,communityRetentionEnabled=true},chars={},
 communityBuilds=overlay,unknownTop={keep=true}}
local H=F.Boot(db,function(H)
 H.perks.serverBuildSlots={[1]={name='Local plan',verified=true,echoes={{spellId=200001,quality=1,stacks=2}}}}
 H.perks.serverActiveSlot=1
end)
local s=Nexus.StartupStatus()

-- 1. The refusal is still reported, with its reason and facts.
check(s.state=='failed' and s.reason=='ROOT_SLOT_LIMIT','the refusal and its reason stay reported: '..tostring(s.reason))
check(s.failure and s.failure.map=='overlay' and s.failure.count==2049 and s.failure.limit==2048,'the refusal facts are available')
check(tostring(Nexus.lastError)=='ROOT_SLOT_LIMIT','the recorded error is unchanged')

-- 2. Local tools are ready and usable.
check(s.coreReady==true,'local tools start')
check(Nexus.Store.StateWriteStatus().mode=='durable','local saved data is writable')
Nexus.WishlistEditor.Show()
check(NexusEditorFrame and NexusEditorFrame:IsShown(),'the Wishlist editor opens')
local A=Nexus.GameAdapter
check(A.SetFirstLoadoutWishlistIdentity('Local plan',{{spellId=200001,quality=1,stacks=2}}),'a local Wishlist assignment is accepted')
H.Notify();A.Poll();H.Advance(1,.05)
check(A.AssignedWishlist().state=='ready','the local assignment resolves')
local chat=#H.chat;SlashCmdList.NEXUS('auto');H.Advance(1,.05)
check(Nexus.RecomputeStats().autoEnabled==true,'ordinary Automation can be switched on locally')
SlashCmdList.NEXUS('auto')
check(Nexus.RecomputeStats().autoEnabled==false,'and off again')

-- 3. Community, Leaderboard and Sync stay unavailable; nothing is sent.
check(Nexus.BuildCatalog.RootState().state~='ROOT_ADMITTED','the shared catalog stays refused')
local ok,why=Nexus.Sync.RequestSync()
check(ok==false,'Sync Now refuses while the shared catalog is unavailable: '..tostring(why))
Nexus.CommunityBuilds.Show();H.Advance(1,.05)
check(NexusSharedStartupFrame and NexusSharedStartupFrame:IsShown(),'the guarded shared placeholder is shown instead of the browser')
check(not NexusCommunityBuildsFrame or not NexusCommunityBuildsFrame:IsShown(),'no Community browser opens')
check(Nexus.LoadingStatus.PhaseText(s):find('Nothing was changed or deleted',1,true),'the shared view states the capacity refusal plainly')
chat=#H.chat;SlashCmdList.NEXUS('status')
local said=table.concat(H.chat,'\n',chat+1)
check(said:find('Community data unavailable',1,true) and said:find('count at refusal=2049',1,true),'/nexus status states the plain reason and the facts: '..said)
H.Advance(60,.05)
check(#H.sent==0,'no Sync message is sent while the shared catalog is refused')

-- 4. The Community data is untouched: no eviction, no migration, no bundle.
-- Local session writes (character rows, missing default settings, local logs,
-- the storage-migration receipt) happen as in any normal start-up.
local function CommunityState()
 return F.Serialize({builds=NexusDB.communityBuilds,tombstones=NexusDB.syncTombstones,
  evictions=NexusDB.communityRetentionEvictions,unknown=NexusDB.unknownTop,marker=NexusDB.settingsVersion})
end
local communityBefore=F.Serialize({builds=overlay,tombstones=nil,evictions=nil,unknown={keep=true},marker=2})
check(CommunityState()==communityBefore,'the Community list, markers and unknown data are unchanged after start-up and 60 seconds')
for _,key in ipairs({'authorityBundle','dataRetention','dataCompaction','legacyDataMigration'})do
 check(NexusDB[key]==nil,'no '..key..' state is created while the shared catalog is refused')
end
check(NexusDB.settings.autoPick==false,'saved settings values are kept')
F.Reload()
local r=Nexus.StartupStatus()
check(r.coreReady and r.state=='failed' and r.reason=='ROOT_SLOT_LIMIT','reload behaves the same')
check(CommunityState()==communityBefore,'the Community data is still unchanged after reload')
for _,key in ipairs({'authorityBundle','dataRetention','dataCompaction','legacyDataMigration'})do
 check(NexusDB[key]==nil,'reload creates no '..key..' state either')
end

-- 5. A non-capacity root refusal keeps the previous behavior: local tools wait.
local bad={settingsVersion=2,settings={autoPick=false},chars={},communityBuilds={ok=Record('ok')},
 buildCatalog={schemaVersion=1,catalogVersion='x',sourceVersion='x',unexpected='field'}}
F.Boot(bad)
local b=Nexus.StartupStatus()
check(b.state=='failed' and not b.coreReady and b.reason~='ROOT_SLOT_LIMIT',
 'a non-capacity refusal still withholds local start-up: '..tostring(b.reason)..' coreReady='..tostring(b.coreReady))
print('PASS catalog_capacity_local_ready: local tools ready on a capacity refusal; shared views and Sync withheld; saved data untouched; other refusals unchanged checks='..checks)
