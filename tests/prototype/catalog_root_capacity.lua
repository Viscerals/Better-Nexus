-- Reporter on test.9033: saved format 2, start-up failed, ROOT_SLOT_LIMIT.
-- Root collection refuses before any record is validated when one map holds
-- more than rootMapKeys (2048) keys, or when the distinct build identities
-- across overlay and bundled exceed rows (2048). Removal and retention markers
-- have their own limits (capacity envelope V2). The active overlay is the saved
-- bundle's communityBuilds when a bundle exists, the legacy table only when it
-- does not. Real TOC boot and admission path; synthetic records only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Record(id,valid)
 if not valid then return {} end
 return {id=id,title='Synthetic '..id,author='Other-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
end
local function Map(prefix,from,to,valid)
 local m={};for i=from,to do local id=prefix..i;m[id]=Record(id,valid~=false) end;return m
end
local function Db(overlay)
 return {settingsVersion=2,settings={autoPick=false,communityRetentionEnabled=true},chars={},communityBuilds=overlay}
end
local function Boot(db,bundled)
 F.fileHooks=bundled and {[ [[data\BundledBuilds.lua]] ]=function()Nexus.BundledBuilds.builds=bundled end} or nil
 local H=F.Boot(db);F.fileHooks=nil
 return Nexus.StartupStatus(),H
end
local function Ready(label,s)check(s.coreReady and s.state~='failed',label..': starts with the shared catalog admitted: '..tostring(s.reason))end
local function Refused(label,s,map,counter,source)
 check(s.state=='failed' and s.reason=='ROOT_SLOT_LIMIT',label..': refused with ROOT_SLOT_LIMIT: '..tostring(s.reason))
 check(s.coreReady==true,label..': local tools still start (the shared catalog stays refused)')
 local f=s.failure or {}
 check(f.component=='catalog' and f.phase=='collect' and f.map==map and f.counter==counter
  and f.count==2049 and f.limit==2048 and f.source==source,
  label..': facts '..tostring(f.map)..'/'..tostring(f.counter)..'/'..tostring(f.count)..'/'..tostring(f.limit)..'/'..tostring(f.source))
end

-- 1. Legacy overlay alone (no bundle): 2047 and 2048 start; 2049 is refused,
-- even with retention enabled, and the saved overlay is kept byte for byte.
Ready('legacy 2047',Boot(Db(Map('syn-',1,2047))))
Ready('legacy 2048',Boot(Db(Map('syn-',1,2048))))
local big=Db(Map('syn-',1,2049));local before=F.Serialize(big.communityBuilds)
local s,H=Boot(big)
Refused('legacy 2049',s,'overlay','map-keys','legacy')
check(F.Serialize(NexusDB.communityBuilds)==before,'legacy 2049: the overlay is unchanged; retention could not act first')
local c=#H.chat;SlashCmdList.NEXUS('status')
check(table.concat(H.chat,'\n',c+1):find('count at refusal=2049 (limit 2048; counting stopped here)',1,true),'legacy 2049: /nexus status states map, counter and count')
F.Reload()
local r=Nexus.StartupStatus()
Refused('legacy 2049 reload',r,'overlay','map-keys','legacy')
check(F.Serialize(NexusDB.communityBuilds)==before,'legacy 2049 reload: the overlay is still unchanged')

-- 2. Saved bundle: its overlay is the active one; a larger stale legacy table is not counted.
local s2=Boot(Db(Map('syn-',1,2048)))
Ready('bundle fixture',s2)
check(type(NexusDB.authorityBundle)=='table','fixture: a saved bundle exists')
NexusDB.communityBuilds=Map('stale-',1,3000,false)
Ready('bundle 2048 with 3000 stale legacy keys',(function()F.Reload();return Nexus.StartupStatus()end)())
NexusDB.authorityBundle.communityBuilds['syn-2049']=Record('syn-2049',true)
local bundleBefore=F.Serialize(NexusDB.authorityBundle.communityBuilds)
F.Reload()
Refused('bundle 2049',Nexus.StartupStatus(),'overlay','map-keys','bundle')
check(F.Serialize(NexusDB.authorityBundle.communityBuilds)==bundleBefore,'bundle 2049: the saved overlay is unchanged')

-- 3. Bundled (shipped) map alone.
Ready('bundled 2048',Boot(Db(nil),Map('base-',1,2048)))
Refused('bundled 2049',Boot(Db(nil),Map('base-',1,2049)),'bundled','map-keys','legacy')

-- 4. Overlapping typed keys count once.
Ready('overlay 2048 + bundled 2048 same ids',Boot(Db(Map('same-',1,2048)),Map('same-',1,2048)))

-- 5. Disjoint union: refused while scanning bundled, on the distinct-build counter.
Ready('disjoint 1500 + 548',Boot(Db(Map('ov-',1,1500)),Map('base-',1,548)))
Refused('disjoint 1500 + 549',Boot(Db(Map('ov-',1,1500)),Map('base-',1,549)),'bundled','distinct-builds','legacy')

-- 6. Record content does not matter: the refusal comes before validation.
Ready('2048 invalid records',Boot(Db(Map('bad-',1,2048,false))))
Refused('2049 invalid records',Boot(Db(Map('bad-',1,2049,false))),'overlay','map-keys','legacy')
-- 7. At run time the overlay cannot grow past the limit: a received record
-- for a 2049th build identity is refused before any catalog work, the refusal
-- is retained as saturation facts, and the saved overlay stays at 2048.
do
 local s7,H7=Boot(Db(Map('syn-',1,2048)))
 Ready('runtime fixture',s7)
 local C=Nexus.BuildCatalog
 for i=1,400 do H7.Advance(.05,.05) if C.ManualPreparationStatus().ready then break end end
 local ok,why,ticket=C.Put(Record('syn-2049',true),{source='sync'})
 local final=why
 if ok==nil and type(ticket)=='table' then
  for i=1,4000 do H7.Advance(.05,.05) if ticket.state~='pending' then break end end
  final=ticket.reason or ticket.state
 end
 check(ok~=true and final=='ROOT_SLOT_LIMIT','runtime: the 2049th record is refused: '..tostring(ok)..' '..tostring(why)..' '..tostring(final))
 check(ticket==nil,'runtime: it is refused before any catalog candidate starts')
 local n=0;for _ in pairs(NexusDB.authorityBundle.communityBuilds)do n=n+1 end
 check(n==2048,'runtime: the saved overlay stays at 2048: '..n)
 local full=C.SaturationSummary()
 check(full and full.reason=='ROOT_SLOT_LIMIT' and full.counter=='distinct-builds' and full.count==2049
  and full.limit==2048 and full.refused==1,'runtime: the refusal is retained as saturation facts')
 check(C.RootState().state=='ROOT_ADMITTED' and C.Status().availableCount==2048,'runtime: the admitted root is unchanged')
 F.Reload()
 Ready('runtime reload',Nexus.StartupStatus())
end
-- 8. Removal and retention markers have their own limits (2048 each, envelope
-- V2): marker keys that the overlay does not hold no longer reduce the builds
-- this build can open. A marker map above its own limit is still refused, names
-- its own map and keeps the saved data.
local function Markers(prefix,from,to)
 local m={};for i=from,to do m[prefix..i]={at=1} end;return m
end
local function RefusedAs(label,s,reason,map,counter,count,limit,source)
 check(s.state=='failed' and s.reason==reason,label..': refused with '..reason..': '..tostring(s.reason))
 check(s.coreReady==true,label..': local tools still start (the shared catalog stays refused)')
 local f=s.failure or {}
 check(f.component=='catalog' and f.phase=='collect' and f.map==map and f.counter==counter
  and f.count==count and f.limit==limit and f.source==source,
  label..': facts '..tostring(f.map)..'/'..tostring(f.counter)..'/'..tostring(f.count)..'/'..tostring(f.limit)..'/'..tostring(f.source))
end
do
 -- Markers over ids the overlay already holds reserve no additional key.
 local shared=Db(Map('syn-',1,2048))
 shared.syncTombstones=Markers('syn-',1,2048)
 shared.communityRetentionEvictions=Markers('syn-',1,2048)
 Ready('2048 builds with the same 2048 removal and retention markers',Boot(shared))

 -- Markers over other ids have their own budget: 10 builds and 2039 unrelated
 -- removal markers are admitted, unchanged.
 local disjoint=Db(Map('syn-',1,10));disjoint.syncTombstones=Markers('tomb-',1,2039)
 local beforeTombs=F.Serialize(disjoint.syncTombstones)
 Ready('10 builds and 2039 unrelated removal markers',Boot(disjoint))
 check(F.Serialize(NexusDB.syncTombstones)==beforeTombs,'removal markers: they are unchanged, and none was dropped to fit')
 check(Nexus.BuildCatalog.Status().availableCount==10,'removal markers: all 10 builds are available')

 -- A retention map above its own limit is still refused, on the map-key counter.
 local barOver=Db(Map('syn-',1,2048))
 barOver.syncTombstones=Markers('syn-',1,2048)
 barOver.communityRetentionEvictions=Markers('syn-',1,2048)
 barOver.communityRetentionEvictions['syn-2049']={at=1}
 local beforeAll=F.Serialize({builds=barOver.communityBuilds,tombstones=barOver.syncTombstones,
  barriers=barOver.communityRetentionEvictions})
 RefusedAs('2049 retention markers',Boot(barOver),
  'BARRIER_SET_LIMIT','barrier','map-keys',2049,2048,'legacy')
 check(F.Serialize({builds=NexusDB.communityBuilds,tombstones=NexusDB.syncTombstones,
  barriers=NexusDB.communityRetentionEvictions})==beforeAll,'retention marker: all three saved maps are unchanged')
end
print('PASS catalog_root_capacity: 2047/2048/2049 boundaries, bundle vs stale legacy, bundled, overlap, disjoint union, invalid content, separate marker limits, runtime refusal before work, preservation and reload checks='..checks)
