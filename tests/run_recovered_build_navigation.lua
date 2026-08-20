-- Recovered Leaderboard navigation preserves the historical raw DPS identity
-- while publishing and opening only a separately proven catalog identity.

local H=dofile("tests/harness.lua")

local function Equal(left,right,seen)
    if left==right then return true end
    if type(left)~=type(right) or type(left)~="table" then return false end
    seen=seen or {}
    if seen[left] then return seen[left]==right end
    seen[left]=right
    for key,value in pairs(left) do
        if not Equal(value,right[key],seen) then return false end
    end
    for key in pairs(right) do if left[key]==nil then return false end end
    return true
end

local builds={}
local rows={}
for index=1,200 do
    local rawId=string.format("raw-collision-%03d",index)
    local resolvedId=string.format("legacy-dps-resolved-%03d",index)
    local spellId=880000+index
    local fingerprint=tostring(spellId).."x1"
    builds[rawId]={id=rawId,title="Current collision",class="WARRIOR",
        fingerprint=tostring(890000+index).."x1",
        echoes={{spellId=890000+index,stacks=1}},lastModified=20}
    builds[resolvedId]={id=resolvedId,title="Recovered exact",class="PALADIN",
        fingerprint=fingerprint,echoes={{spellId=spellId,stacks=1}},
        autoDps=true,legacyRecovered=true,lastModified=10}
    local player=string.format("Recovered%03d",index)
    rows[player:lower()]={player=player,dps=1000000-index,duration=60,
        level=80,ts=index,category="dummy",protocolVersion=6,
        buildId=rawId,fingerprint=fingerprint,
        echoes={{spellId=spellId,stacks=1}},
        lockedEchoes=index==80 and {{spellId=980080,stacks=1}} or nil}
end

Nexus.BundledBuilds={schemaVersion=1,catalogVersion="stage35-navigation",
    sourceVersion="test",generatedAt=0,builds=builds}
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={
    characterBest={dummy=rows,lk={}},personalBest={},buildBest={}}}
Nexus.BuildCatalog.Init(NexusDB,Nexus.BundledBuilds)
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init({}, {})

local allCalls=0
local originalAll=Nexus.BuildCatalog.All
Nexus.BuildCatalog.All=function()
    allCalls=allCalls+1
    error("full catalog traversal is forbidden")
end

Nexus.ViewProjections.Reset()
local projected,summary,reason=Nexus.ViewProjections.RequestLeaderboard(
    "dummy",{classFilter="ALL",search=""})
assert(projected==nil and reason=="pending",
    "cold Leaderboard projection did not start incrementally")
local pumps=0
while not Nexus.ViewProjections.PumpLeaderboard() do
    pumps=pumps+1
    assert(pumps<1000,"Leaderboard projection did not terminate")
end
projected,summary=Nexus.ViewProjections.RequestLeaderboard(
    "dummy",{classFilter="ALL",search=""})
assert(#projected==200 and summary.filtered==200,
    "assembled recovered projection did not publish all rows")

local target
for _,row in ipairs(projected) do
    if row.player=="Recovered080" then target=row; break end
end
assert(target and target.buildId=="raw-collision-080",
    "projection rewrote the preserved historical raw build ID")
assert(target.resolvedBuildId=="legacy-dps-resolved-080",
    "projection did not publish the exact fingerprint-resolved catalog ID")
assert(target.buildIdentityMismatch==true,
    "collided raw identity was not retained as an explicit mismatch")

local coldStats=Nexus.BuildCatalog.DebugStats()
local warmRows=Nexus.ViewProjections.RequestLeaderboard(
    "dummy",{classFilter="ALL",search=""})
local warmStats=Nexus.BuildCatalog.DebugStats()
assert(warmRows==projected and allCalls==0
        and warmStats.relatedIndexRebuilds==coldStats.relatedIndexRebuilds
        and warmStats.exactLookups==coldStats.exactLookups
        and warmStats.identityResolutions==coldStats.identityResolutions,
    "warm 200-row projection repeated catalog resolution or traversal")

dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
Nexus.Sync={GetLeaderboardSyncStatus=function() return "idle",0,0,{} end}
local opened
Nexus.CommunityBuilds={ShowBuild=function(id) opened=id; return true end}
local copied
Nexus.WishlistEditor={OpenForCandidate=function(candidate)
    copied=candidate
    return true
end}
local L=Nexus.Leaderboard
L.Init(nil)
L.Show("dummy")
assert(L.SelectKey("recovered080|string:880080x1"),
    "recovered row was not selectable by stable fingerprint key")
local detail=NexusLeaderboardFrame._leaderboardDetail
local savedBefore=H.CloneValue(NexusDB)
detail.open:GetScript("OnClick")()
assert(opened=="legacy-dps-resolved-080",
    "Open Build forwarded the obsolete raw DPS build ID")
local firstOpened=opened
detail.copy:GetScript("OnClick")()
assert(copied and copied.evidenceKind=="candidate-typed-v1"
        and #copied.ordinaryEchoes==1
        and copied.ordinaryEchoes[1].spellId==880080,
    "Copy into Editor rejected exact recovered evidence")
for _=1,20 do
    detail.open:GetScript("OnClick")()
    detail.copy:GetScript("OnClick")()
end
local actionStats=Nexus.BuildCatalog.DebugStats()
assert(allCalls==0 and actionStats.relatedIndexRebuilds==warmStats.relatedIndexRebuilds
        and actionStats.exactLookups==warmStats.exactLookups
        and actionStats.identityResolutions==warmStats.identityResolutions,
    "warm Open/Copy repeated catalog traversal or identity resolution")

-- A recovered projection borrows only its already-proven exact identity. Its
-- current locked pool still comes from the live selected DPS record and must
-- invalidate the stale candidate before the click.
L.Show("dummy")
L.RefreshData()
assert(L.SelectKey("recovered080|string:880080x1"),
    "recovered locked-freshness row was not selectable")
detail=NexusLeaderboardFrame._leaderboardDetail
assert(detail.copy:IsEnabled(),
    "recovered locked-freshness candidate was unavailable")
local storedTarget=NexusDB.dpsCapture.characterBest.dummy.recovered080
local lockedInlineBefore=H.CloneValue(storedTarget.lockedEchoes)
storedTarget.lockedEchoes={{spellId=980081,stacks=1}}
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
    {source="recovered locked evidence changed"})
copied=nil
detail.copy:GetScript("OnClick")()
assert(copied==nil and not detail.copy:IsEnabled()
        and detail.more:GetText():find("evidence changed",1,true),
    "recovered current locked change did not stale the candidate")
storedTarget.lockedEchoes=lockedInlineBefore
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,
    {source="recovered locked evidence restored"})
assert(Equal(NexusDB,savedBefore),
    "display, Open, or Copy mutated SavedVariables")

-- A represented catalog revision invalidates the projection exactly once.
Nexus.BuildCatalog.All=originalAll
assert(Nexus.BuildCatalog.Put({id="legacy-dps-resolved-080",
    title="Changed identity",class="PALADIN",fingerprint="999999x1",
    echoes={{spellId=999999,stacks=1}},lastModified=30}))
opened=nil
detail.open:GetScript("OnClick")()
assert(opened==nil and not detail.open:IsEnabled()
        and detail.more:GetText():find("identity changed",1,true),
    "already-rendered stale recovered identity remained navigable")
local afterChange=Nexus.ViewProjections.RequestLeaderboard(
    "dummy",{classFilter="ALL",search=""})
assert(afterChange==nil,"catalog revision reused a stale resolved projection")
while not Nexus.ViewProjections.PumpLeaderboard() do end
afterChange=Nexus.ViewProjections.RequestLeaderboard(
    "dummy",{classFilter="ALL",search=""})
local changed
for _,row in ipairs(afterChange) do
    if row.player=="Recovered080" then changed=row; break end
end
assert(changed==nil,
    "stale fingerprint identity remained public after revision")

local missing,missingReason=Nexus.BuildCatalog.ResolveFingerprintIdentity(
    "missing-raw","missing-fingerprint")
local malformed,malformedReason=Nexus.BuildCatalog.ResolveFingerprintIdentity(
    "missing-raw","")
assert(missing==nil and missingReason=="exact build identity is unavailable"
        and malformed==nil
        and malformedReason=="record fingerprint is unavailable",
    "missing or malformed navigation identity did not fail closed")

local ambiguousFingerprint="881000x1"
assert(Nexus.BuildCatalog.Put({id="ambiguous-a",title="Ambiguous A",
    fingerprint=ambiguousFingerprint,echoes={{spellId=881000,stacks=1}},
    lastModified=40})
    and Nexus.BuildCatalog.Put({id="ambiguous-b",title="Ambiguous B",
        fingerprint=ambiguousFingerprint,
        echoes={{spellId=881000,stacks=1}},lastModified=40}))
local ambiguous,ambiguousReason=Nexus.BuildCatalog.ResolveFingerprintIdentity(
    "obsolete-ambiguous",ambiguousFingerprint)
assert(ambiguous==nil
        and ambiguousReason=="exact build identity is ambiguous",
    "equally authoritative exact identities did not fail closed")

assert(Nexus.BuildCatalog.SetTombstone("legacy-dps-resolved-081",
    {author="fixture",stamp=50}))
local tombstoned,tombstoneReason=Nexus.BuildCatalog.ResolveFingerprintIdentity(
    "raw-collision-081","880081x1")
assert(tombstoned==nil
        and tombstoneReason=="exact build identity is unavailable",
    "tombstoned resolved identity remained navigable")

assert(Nexus.BuildCatalog.Put({id="tombstone-fallback",
    title="Tombstone fallback",fingerprint="881001x1",
    echoes={{spellId=881001,stacks=1}},lastModified=50})
    and Nexus.BuildCatalog.SetTombstone("raw-tombstoned",
        {author="fixture",stamp=51}))
local rawTombstoned,rawTombstoneReason=
    Nexus.BuildCatalog.ResolveFingerprintIdentity(
        "raw-tombstoned","881001x1")
assert(rawTombstoned==nil
        and rawTombstoneReason=="historical build identity is tombstoned",
    "tombstoned historical raw ID fell through to another exact identity")

-- Reload reconstructs the same bounded index without changing stored rows.
dofile("core/BuildCatalog.lua")
Nexus.BuildCatalog.Init(NexusDB,Nexus.BundledBuilds)
local reloaded=Nexus.BuildCatalog.ResolveFingerprintIdentity(
    "raw-collision-082","880082x1")
assert(reloaded=="legacy-dps-resolved-082",
    "reload did not reconstruct recovered navigation identity")

-- Current protocol and injected non-recovered rows keep their established ID.
local currentRow={protocolVersion=7,buildId="current-seven",
    fingerprint="882007x1",echoes={{spellId=882007,stacks=1}},
    buildIdentityMismatch=nil}
local legacyCompatible={buildId="legacy-compatible",
    fingerprint="882006x1",echoes={{spellId=882006,stacks=1}},
    buildIdentityMismatch=nil}
assert(L.ResolveOpenBuildId(currentRow)=="current-seven"
        and L.ResolveOpenBuildId(legacyCompatible)=="legacy-compatible",
    "current or established non-recovered navigation changed")

print(string.format(
    "recovered navigation: rows=%d pumps=%d resolved=%s warmLookups=%d scans=%d mutations=0 revision=invalidated -- OK",
    #projected,pumps,tostring(firstOpened),warmStats.exactLookups,allCalls))
