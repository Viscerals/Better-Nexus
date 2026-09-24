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
-- Saved update keys of an older client are part of the data this session must
-- leave alone: a stored peer-authority notice, a stored peer advisory and a
-- legacy dismissed entry would all be rewritten by ordinary start-up upkeep.
local updateKeys={updateNotice={version='9.9.9',test=1,authority='peer-observation',source='Peer-Realm'},
 updateAdvisory={testBuild={version='9.9.9',test=2,observedAt=1}},updateDismissed='9.9.9#1'}
local db={settingsVersion=2,settings={autoPick=false,communityRetentionEnabled=true},chars={},
 communityBuilds=overlay,unknownTop={keep=true},
 updateNotice=updateKeys.updateNotice,updateAdvisory=updateKeys.updateAdvisory,
 updateDismissed=updateKeys.updateDismissed}
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
local function UpdateState()
 return F.Serialize({notice=NexusDB.updateNotice,advisory=NexusDB.updateAdvisory,
  dismissed=NexusDB.updateDismissed,noticeQuarantine=NexusDB.updateNoticeQuarantine,
  advisoryQuarantine=NexusDB.updateAdvisoryQuarantine})
end
local updateBefore=F.Serialize({notice=updateKeys.updateNotice,advisory=updateKeys.updateAdvisory,
 dismissed=updateKeys.updateDismissed,noticeQuarantine=nil,advisoryQuarantine=nil})
check(UpdateState()==updateBefore,'the saved update keys are not rewritten, quarantined or removed')
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
check(UpdateState()==updateBefore,'the saved update keys are unchanged after reload as well')

-- 5. Every saved-capacity refusal behaves the same way. Saved markers reserve
-- keys in the same budget as the builds, so the reason names only the map in
-- which counting stopped. The sentence follows the recorded counter: a map
-- above its own limit is named; a combined overflow names no single map.
local function Markers(prefix,from,to)
 local m={};for i=from,to do m[prefix..i]={at=1} end;return m
end
-- The shapes an older retention owner wrote: a numeric retention marker (the
-- evicted build's stamp) and a {stamp, author} removal marker.
local function OldMarkers(prefix,from,to)
 local m={};for i=from,to do m[prefix..i]=1700000000+i end;return m
end
local function OldRemovals(prefix,from,to)
 local m={};for i=from,to do m[prefix..i]={stamp=1700000000+i,author='OldPeer'} end;return m
end
local single={
 removal='Community data unavailable: the saved removal markers exceed the limit (2048). Nothing was changed or deleted.',
 retention='Community data unavailable: the saved retention markers exceed the limit (2048). Nothing was changed or deleted.'}
-- A combined overflow names only the maps read up to the stop.
local together={
 builds='Community data unavailable: your saved Community builds and the builds shipped with this version together use more than the 2048 entries this build opens. Nothing was changed or deleted.',
 removal='Community data unavailable: your saved Community builds and removal markers together use more than the 2048 entries this build opens. Nothing was changed or deleted.',
 retention='Community data unavailable: your saved Community builds, removal markers and retention markers together use more than the 2048 entries this build opens. Nothing was changed or deleted.'}
local capacityCases={
 {'10 builds, 2039 removal markers and 1500 retention markers','TOMBSTONE_SET_LIMIT','distinct-slots',together.removal,
   'builds 10, shipped 0, removal markers 2039, retention markers not read',function()
   local d={settingsVersion=2,settings={},chars={},communityBuilds=Overlay(10)}
   d.syncTombstones=Markers('tomb-',1,2039);d.communityRetentionEvictions=Markers('ev-',1,1500);return d
  end},
 {'10 builds and 2039 retention markers','BARRIER_SET_LIMIT','distinct-slots',together.retention,'builds 10, shipped 0, removal markers 0, retention markers 2039',function()
   local d={settingsVersion=2,settings={},chars={},communityBuilds=Overlay(10)}
   d.communityRetentionEvictions=Markers('ev-',1,2039);return d
  end},
 {'older-shape maps, each below 2048: 1200 builds, 100 removal and 800 retention markers','BARRIER_SET_LIMIT','distinct-slots',together.retention,
   'builds 1200, shipped 0, removal markers 100, retention markers 749',function()
   local d={settingsVersion=5,settings={},chars={},communityBuilds=Overlay(1200)}
   d.syncTombstones=OldRemovals('gone-',1,100);d.communityRetentionEvictions=OldMarkers('evicted-',1,800);return d
  end},
 {'2049 retention markers alone','BARRIER_SET_LIMIT','map-keys',single.retention,'builds 0, shipped 0, removal markers 0, retention markers 2049',function()
   local d={settingsVersion=2,settings={},chars={}}
   d.communityRetentionEvictions=Markers('ev-',1,2049);return d
  end},
 {'2049 removal markers alone','TOMBSTONE_SET_LIMIT','map-keys',single.removal,'builds 0, shipped 0, removal markers 2049, retention markers not read',function()
   local d={settingsVersion=2,settings={},chars={}}
   d.syncTombstones=Markers('tomb-',1,2049);return d
  end},
 {'1500 saved and 549 shipped builds, no markers','ROOT_SLOT_LIMIT','distinct-slots',together.builds,
   'builds 1500, shipped 549, removal markers not read, retention markers not read',function()
   return {settingsVersion=2,settings={},chars={},communityBuilds=Overlay(1500)}
  end,(function()local m={};for i=1,549 do m['base-'..i]=Record('base-'..i) end;return m end)()},
}
for _,case in ipairs(capacityCases)do
 local label,reason,counter,sentence,counted,build,shipped=case[1],case[2],case[3],case[4],case[5],case[6],case[7]
 local d=build()
 local savedBefore=F.Serialize({d.communityBuilds,d.syncTombstones,d.communityRetentionEvictions})
 F.fileHooks=shipped and {[ [[data\BundledBuilds.lua]] ]=function()Nexus.BundledBuilds.builds=shipped end} or nil
 local CH=F.Boot(d);F.fileHooks=nil
 local c=Nexus.StartupStatus()
 check(c.state=='failed' and c.reason==reason and c.coreReady==true,
  label..': the shared catalog is refused and local tools start: '..tostring(c.reason)..' coreReady='..tostring(c.coreReady))
 check(c.failure and c.failure.counter==counter,label..': the catalog recorded counter '..counter..': '..tostring(c.failure and c.failure.counter))
 local text=Nexus.LoadingStatus.CapacityText(c)
 check(text==sentence,label..': the sentence matches the recorded counter: '..tostring(text))
 check(Nexus.LoadingStatus.PhaseText(c)==sentence,label..': the shared-button tooltip text (PhaseText) uses the same sentence')
 local at=#CH.chat;SlashCmdList.NEXUS('status')
 local said=table.concat(CH.chat,'\n',at+1)
 check(said:find(sentence,1,true) and said:find('counter='..counter,1,true)
  and said:find('keys counted before the stop (at least)='..counted,1,true),label..': /nexus status states the sentence, the counter and the counted keys: '..said)
 check(Nexus.BuildCatalog.RootState().state~='ROOT_ADMITTED',label..': the shared catalog stays refused')
 check(F.Serialize({NexusDB.communityBuilds,NexusDB.syncTombstones,NexusDB.communityRetentionEvictions})==savedBefore,
  label..': the saved builds and markers are unchanged')
end

-- The class itself is fixed: exactly these four saved-capacity refusals.
-- Without a recorded counter no sentence names one map; ROOT_MAP_LIMIT has
-- only one counter and keeps its own sentence. Everything else keeps the
-- previous behavior.
local reasons=Nexus.MainInternals.CapacityRefusalReasonsV1()
check(table.concat(reasons,',')=='BARRIER_SET_LIMIT,ROOT_MAP_LIMIT,ROOT_SLOT_LIMIT,TOMBSTONE_SET_LIMIT',
 'the capacity class holds exactly the four saved-capacity refusals: '..table.concat(reasons,','))
for _,reason in ipairs(reasons)do
 local text=Nexus.LoadingStatus.CapacityText({state='failed',coreReady=true,reason=reason})
 check(type(text)=='string' and text:find('Community data unavailable',1,true)
  and text:find('Nothing was changed or deleted',1,true),reason..': it has a plain sentence: '..tostring(text))
 if reason~='ROOT_MAP_LIMIT' then
  check(not text:find('exceed the limit',1,true) and not text:find('holds more builds',1,true),
   reason..': without a recorded counter no single map is named: '..tostring(text))
 end
 check(Nexus.LoadingStatus.CapacityText({state='failed',coreReady=false,reason=reason})==nil,
  reason..': no capacity sentence before local tools are ready')
end

-- 6. Non-capacity root refusals keep the previous behavior: local tools wait,
-- and no capacity sentence is offered for them.
local nonCapacity={
 {'unknown catalog metadata field',{settingsVersion=2,settings={autoPick=false},chars={},
   communityBuilds={ok=Record('ok')},
   buildCatalog={schemaVersion=1,catalogVersion='x',sourceVersion='x',unexpected='field'}}},
 {'a malformed saved map',{settingsVersion=2,settings={autoPick=false},chars={},
   communityBuilds={ok=Record('ok')},syncTombstones='not a map'}},
}
for _,case in ipairs(nonCapacity)do
 local label,bad=case[1],case[2]
 F.Boot(bad)
 local b=Nexus.StartupStatus()
 check(b.state=='failed' and not b.coreReady,
  label..': still withholds local start-up: '..tostring(b.reason)..' coreReady='..tostring(b.coreReady))
 check(Nexus.LoadingStatus.CapacityText(b)==nil,label..': no capacity sentence is shown for it')
end

-- 7. Invalid local saved data stays blocked when an oversized catalog also
-- exists: the malformed marker keeps saved data read-only, the shared catalog
-- stays refused, and neither is altered.
local both={settingsVersion={version=5},settings={autoPick=false},chars={},communityBuilds=Overlay(2049)}
local bothBefore=F.Serialize({builds=both.communityBuilds,marker=both.settingsVersion})
F.Boot(both)
local w=Nexus.Store.StateWriteStatus()
check(w.mode=='unavailable' and w.format=='malformed','invalid local data stays read-only next to an oversized catalog: '..tostring(w.mode))
check(Nexus.BuildCatalog.RootState().state~='ROOT_ADMITTED','the oversized catalog stays refused as well')
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)row.probe=true end))
local row=NexusDB.chars and NexusDB.chars['PrototypeTester']
check(row==nil or row.probe==nil,'a local write reaches no saved character row')
check(F.Serialize({builds=NexusDB.communityBuilds,marker=rawget(NexusDB,'settingsVersion')})==bothBefore,
 'the marker and the oversized Community list are both unchanged')
print('PASS catalog_capacity_local_ready: local tools ready on every capacity refusal; shared views and Sync withheld; saved and update data untouched; other refusals and invalid local data unchanged checks='..checks)
