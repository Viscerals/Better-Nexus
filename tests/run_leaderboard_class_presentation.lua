local H = dofile("tests/harness.lua")

local P = Nexus.ViewProjections
local Revisions = Nexus.Revisions
local NEUTRAL = "Interface\\Icons\\INV_Misc_Note_01"

UnitName = function() return "Currenthero" end
local currentClassToken = "DRUID"
UnitClass = function() return currentClassToken and "Druid" or nil, currentClassToken end
GetNormalizedRealmName = function() return "Ebonhold" end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
    return out
end

local function Signature(value, seen)
    if type(value) ~= "table" then return type(value)..":"..tostring(value) end
    seen = seen or {}
    if seen[value] then return "cycle" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        return type(a)..":"..tostring(a) < type(b)..":"..tostring(b)
    end)
    local out = {"{"}
    for _, key in ipairs(keys) do
        out[#out + 1] = Signature(key, seen).."="..Signature(value[key], seen)..";"
    end
    out[#out + 1] = "}"; seen[value] = nil
    return table.concat(out)
end

local function Build(id, spellId, class, author, realm, verified)
    local fingerprint = tostring(spellId).."x1"
    return {id=id,title=id,class=class,author=author,
        ownerKey=author and realm and Nexus.Identity.OwnerKey(author,realm) or nil,
        ownerVerified=verified == true or nil,fingerprint=fingerprint,
        echoes={{spellId=spellId,stacks=1}}}
end

local bundle = {schemaVersion=1,catalogVersion="class-test",sourceVersion="test",builds={
    exact=Build("exact",810001,"WARRIOR"),
    recovered=Build("recovered",810002,"PALADIN"),
    tombstoned=Build("tombstoned",810003,"PRIEST"),
    ambiguousA=Build("ambiguousA",810004,"SHAMAN"),
    ambiguousB=Build("ambiguousB",810004,"SHAMAN"),
    ownerOnly=Build("ownerOnly",810005,"HUNTER","Owneronly","RealmA",true),
    staleSavedClass={id="staleSavedClass",title="Stale Saved Class",
        class="ROGUE",author="Owneronly",ownerKey="owneronly@realma",
        ownerVerified=true,realm="realma",importedSavedBuild=true,
        fingerprint="810005x1",echoes={{spellId=810005,stacks=1}}},
    ownerAliasPoison={id="ownerAliasPoison",title="ownerAliasPoison",
        class="WARLOCK",author="Owneronly",ownerKey="owneronly@realma",
        ownerVerified=true,realm="realma",o="other@realma",
        fingerprint="810105x1",echoes={{spellId=810105,stacks=1}}},
    ownerClaimPoison={id="ownerClaimPoison",title="ownerClaimPoison",
        class="DRUID",author="Owneronly",ownerKey="owneronly@realma",
        ownerVerified=true,realm="realma",claimedOwnerKey="other@realma",
        fingerprint="810106x1",echoes={{spellId=810106,stacks=1}}},
    ownerConflictA=Build("ownerConflictA",810006,"MAGE","Ownerconflict","RealmA",true),
    ownerConflictB=Build("ownerConflictB",810007,"ROGUE","Ownerconflict","RealmA",true),
    sameNameA=Build("sameNameA",810009,"MAGE","Sameperson","RealmA",true),
    sameNameB=Build("sameNameB",810010,"ROGUE","Sameperson","RealmB",true),
    unverifiedOnly=Build("unverifiedOnly",810011,"PRIEST","Unverified","RealmA",false),
}}
local db = {communityBuilds={},syncTombstones={tombstoned={stamp=50,author="Owner"}}}
Nexus.BuildCatalog.Init(db,bundle)
local ownerKey = Nexus.Identity.OwnerKey("Owneronly","RealmA")
local ownerRequest = {player="Owneronly",ownerKey=ownerKey,
    ownerVerified=true,realm="realma"}
local ownerClass, ownerSource = Nexus.BuildCatalog.ResolveOwnerClass(ownerRequest)
assert(ownerClass=="HUNTER" and ownerSource=="owner-consensus",
    "verified owner class index did not resolve its single class")
local unverifiedOwnerRequest = Copy(ownerRequest)
unverifiedOwnerRequest.ownerVerified = false
assert(Nexus.BuildCatalog.ResolveOwnerClass(unverifiedOwnerRequest)==nil,
    "unverified requester gained owner class authority")
local conflictBuild = Build(
    "ownerOnlyConflict",810008,"MAGE","Owneronly","RealmA",true)
assert(Nexus.BuildCatalog.Put(conflictBuild))
local conflictedClass, conflictReason =
    Nexus.BuildCatalog.ResolveOwnerClass(ownerRequest)
assert(conflictedClass==nil and conflictReason=="owner class evidence conflicts",
    "incremental owner class conflict did not fail closed")
assert(Nexus.BuildCatalog.RemoveOverlay(conflictBuild.id))
assert(Nexus.BuildCatalog.ResolveOwnerClass(ownerRequest)=="HUNTER",
    "owner class index did not recover after incremental removal")

local rows = {
    {player="Protocolmage",class="MAGE",dps=1000000,duration=60,ts=1,
        buildId="row-mage",fingerprint="820001x1",echoes={{spellId=820001,stacks=1}}},
    {player="Exactwarrior",dps=999000,duration=60,ts=2,
        buildId="exact",fingerprint="810001x1"},
    {player="Currenthero",ownerKey="currenthero@ebonhold",ownerVerified=true,
        dps=998000,duration=60,ts=3,
        buildId="current",fingerprint="820003x1",echoes={{spellId=820003,stacks=1}}},
    {player="Recoveredpaladin",protocolVersion=6,dps=997000,duration=60,ts=4,
        buildId="missing",fingerprint="810002x1"},
    {player="Unknownlegacy",dps=996000,duration=60,ts=5,
        buildId="unknown",fingerprint="820005x1",echoes={{spellId=820005,stacks=1}}},
    {player="Invalidlegacy",class="NOT_A_CLASS",dps=995000,duration=60,ts=6,
        buildId="invalid",fingerprint="820006x1",echoes={{spellId=820006,stacks=1}}},
    {player="Mismatchedrow",dps=994000,duration=60,ts=7,
        buildId="mismatch",fingerprint="820007x1",buildIdentityMismatch=true,
        build={id="other",class="WARLOCK",fingerprint="820007x1"},
        echoes={{spellId=820007,stacks=1}}},
    {player="Laterrogue",dps=993000,duration=60,ts=8,
        buildId="later",fingerprint="820008x1",echoes={{spellId=820008,stacks=1}}},
    {player="Tombstonedpriest",dps=992000,duration=60,ts=9,
        buildId="tombstoned",fingerprint="810003x1"},
    {player="Ambiguousshaman",dps=991000,duration=60,ts=10,
        buildId="missing-ambiguous",fingerprint="810004x1"},
    {player="Stalehunter",dps=990000,duration=60,ts=11,
        buildId="stale",fingerprint="820011x1",resolvedIdentityMismatch=true,
        build={id="stale",class="HUNTER",fingerprint="820011x1"},
        echoes={{spellId=820011,stacks=1}}},
    {player="Categoryconflict",class="MAGE",dps=989000,duration=60,ts=12,
        buildId="conflict",fingerprint="820012x1",classEvidenceMismatch=true,
        echoes={{spellId=820012,stacks=1}}},
    {player="Owneronly",ownerKey="owneronly@realma",ownerVerified=true,
        dps=988000,duration=60,ts=13,
        buildId="missing-owner",fingerprint="820013x1",
        echoes={{spellId=820013,stacks=1}}},
    {player="Ownerconflict",ownerKey="ownerconflict@realma",ownerVerified=true,
        dps=987000,duration=60,ts=14,
        buildId="missing-owner-conflict",fingerprint="820014x1",
        echoes={{spellId=820014,stacks=1}}},
    {player="Sameperson-RealmA",ownerKey="sameperson@realma",ownerVerified=true,
        dps=986000,duration=60,ts=15,buildId="missing-same-a",
        fingerprint="820015x1",echoes={{spellId=820015,stacks=1}}},
    {player="Sameperson-RealmB",ownerKey="sameperson@realmb",ownerVerified=true,
        dps=985000,duration=60,ts=16,buildId="missing-same-b",
        fingerprint="820016x1",echoes={{spellId=820016,stacks=1}}},
    {player="Sameperson",dps=984000,duration=60,ts=17,
        buildId="missing-same-realm",fingerprint="820017x1",
        echoes={{spellId=820017,stacks=1}}},
    {player="Sameperson-RealmC",ownerKey="sameperson@realmc",ownerVerified=true,
        dps=983000,duration=60,ts=18,buildId="missing-same-c",
        fingerprint="820018x1",echoes={{spellId=820018,stacks=1}}},
    {player="Unverified",ownerKey="unverified@realma",ownerVerified=false,
        dps=982000,duration=60,ts=19,buildId="missing-unverified",
        fingerprint="820019x1",echoes={{spellId=820019,stacks=1}}},
    {player="Currenthero-OtherRealm",ownerKey="currenthero@otherrealm",
        ownerVerified=true,dps=981000,duration=60,ts=20,
        buildId="missing-current-other",fingerprint="820020x1",
        echoes={{spellId=820020,stacks=1}}},
}
for index = 21, 200 do
    local spellId = 820000 + index
    rows[index] = {player=string.format("Bulk%03d",index),
        class=index%2==0 and "MAGE" or "ROGUE",
        dps=1000000-index*1000,duration=60,ts=index,
        buildId="bulk-"..index,fingerprint=tostring(spellId).."x1",
        echoes={{spellId=spellId,stacks=1}}}
end
rows[21] = {player="Ownerclaim",ownerKey="owneronly@realma",
    ownerVerified=true,claimedOwnerKey="other@realma",
    dps=979000,duration=60,ts=21,buildId="missing-owner-claim",
    fingerprint="820021x1",echoes={{spellId=820021,stacks=1}}}
local sourceSignature = Signature(rows)
local boardReads = 0
Nexus.DpsCapture = {GetDpsBoard=function(category)
    boardReads = boardReads + 1
    return category == "dummy" and rows or {}
end}

local function ByPlayer(projected)
    local out = {}
    for _, row in ipairs(projected or {}) do out[row.player] = row end
    return out
end

P.Reset()
local all = assert(P.Leaderboard("dummy",{classFilter="ALL"}))
local byPlayer = ByPlayer(all)
assert(#all==196 and byPlayer.Protocolmage.resolvedClass=="MAGE"
    and byPlayer.Protocolmage.classSource=="record",
    "valid DPS row class did not remain authoritative")
assert(byPlayer.Exactwarrior.resolvedClass=="WARRIOR"
    and byPlayer.Exactwarrior.classSource=="exact-build"
    and byPlayer.Recoveredpaladin.resolvedClass=="PALADIN"
    and byPlayer.Recoveredpaladin.classSource=="exact-build",
    "exact current/recovered catalog class resolution failed")
assert(byPlayer.Currenthero.resolvedClass=="DRUID"
    and byPlayer.Currenthero.classSource=="current-player",
    "proven current-player class repair failed")
assert(byPlayer.Owneronly.resolvedClass=="HUNTER"
    and byPlayer.Owneronly.classSource=="owner-consensus"
    and byPlayer["Sameperson-RealmA"].resolvedClass=="MAGE"
    and byPlayer["Sameperson-RealmB"].resolvedClass=="ROGUE",
    "verified realm-qualified owner class was not recovered")
for _, player in ipairs({"Mismatchedrow","Tombstonedpriest",
        "Ambiguousshaman","Stalehunter"}) do
    assert(byPlayer[player] == nil,
        player.." reached the public Leaderboard without complete ordinary evidence")
end
for _, player in ipairs({"Unknownlegacy","Invalidlegacy",
        "Laterrogue","Categoryconflict","Ownerconflict","Sameperson",
        "Sameperson-RealmC","Unverified","Currenthero-OtherRealm",
        "Ownerclaim"}) do
    assert(byPlayer[player].resolvedClass==nil
        and byPlayer[player].classUnavailable==true,
        player.." gained unproven class authority")
end
assert(Signature(rows)==sourceSignature,
    "class projection mutated stored DPS rows")

local coldStats = P.WorkStats()
local coldReads = boardReads
local warm = assert(P.Leaderboard("dummy",{classFilter="ALL"}))
local warmStats = P.WorkStats()
assert(#warm==196 and boardReads==coldReads
    and warmStats.sourceRows==coldStats.sourceRows
    and warmStats.copies==coldStats.copies
    and warmStats.classFromRecord==coldStats.classFromRecord
    and warmStats.classFromBuild==coldStats.classFromBuild
    and warmStats.classFromCurrentPlayer==coldStats.classFromCurrentPlayer
    and warmStats.classFromOwner==coldStats.classFromOwner
    and warmStats.classUnavailable==coldStats.classUnavailable,
    "warm Leaderboard projection repeated source/class work")
for key, value in pairs(warmStats) do
    assert(type(value)=="number", "diagnostic retained non-scalar field: "..tostring(key))
end

local paladin = assert(P.Leaderboard("dummy",{classFilter="PALADIN"}))
assert(#paladin==1 and paladin[1].player=="Recoveredpaladin",
    "exact recovered class did not pass its filter")
local hunter = assert(P.Leaderboard("dummy",{classFilter="HUNTER"}))
assert(#hunter==1 and hunter[1].player=="Owneronly",
    "owner-consensus class did not pass its filter")
local unavailableFiltered = assert(P.Leaderboard("dummy",{classFilter="PRIEST"}))
assert(#unavailableFiltered==0,
    "tombstoned/unavailable class passed a specific filter")

rows[8].class = "ROGUE"
Revisions.Advance(Revisions.DPS_CHANGED,{source="same-record class enrichment"})
local enriched = ByPlayer(assert(P.Leaderboard("dummy",{classFilter="ALL"})))
assert(enriched.Laterrogue.resolvedClass=="ROGUE"
    and enriched.Laterrogue.classSource=="record",
    "same-record class enrichment did not publish on DPS revision")

currentClassToken = nil
P.Reset()
local earlyLogin = ByPlayer(assert(P.Leaderboard("dummy",{classFilter="ALL"})))
assert(earlyLogin.Currenthero.resolvedClass==nil,
    "unavailable login class was guessed")
local readsBeforeClassRecovery = boardReads
currentClassToken = "DRUID"
local loginRecovered = ByPlayer(assert(P.Leaderboard(
    "dummy",{classFilter="ALL"})))
assert(loginRecovered.Currenthero.resolvedClass=="DRUID"
    and loginRecovered.Currenthero.classSource=="current-player"
    and boardReads==readsBeforeClassRecovery+1,
    "current-player class token did not invalidate the projection without DPS mutation")

local madeFrames = {}
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    local frame = realCreateFrame(...)
    madeFrames[#madeFrames + 1] = frame
    return frame
end
dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")
Nexus.Leaderboard.Init(nil)
Nexus.Leaderboard.Show("dummy")
local bound = {}
for _, frame in ipairs(madeFrames) do
    if type(frame.data)=="table" and frame.icon then bound[frame.data.player]=frame end
end
assert(bound.Unknownlegacy and bound.Unknownlegacy.icon:GetTexture()==NEUTRAL
    and bound.Unknownlegacy.classLabel=="Class unavailable",
    "Leaderboard did not bind neutral unavailable presentation")
NexusLeaderboardSearch:SetText("Mismatchedrow")
Nexus.Leaderboard.RefreshData()
bound = {}
for _, frame in ipairs(madeFrames) do
    if type(frame.data)=="table" and frame.icon then bound[frame.data.player]=frame end
end
assert(not bound.Mismatchedrow or not bound.Mismatchedrow:IsShown(),
    "mismatched ordinary evidence retained a visible Leaderboard row")
NexusLeaderboardSearch:SetText("")
Nexus.Leaderboard.RefreshData()
local beforeReopen = Nexus.Leaderboard.VirtualStats().dataRefreshes
Nexus.Leaderboard.Hide(); Nexus.Leaderboard.Show("dummy")
assert(Nexus.Leaderboard.VirtualStats().results==196
    and Nexus.Leaderboard.VirtualStats().dataRefreshes==beforeReopen,
    "close/reopen rebuilt or lost the class projection")

local finalStats = P.WorkStats()
print(string.format(
    "leaderboard class presentation: rows=%d record=%d build=%d current=%d owner=%d unavailable=%d warm_delta=0 -- OK",
    #all,finalStats.classFromRecord,finalStats.classFromBuild,
    finalStats.classFromCurrentPlayer,finalStats.classFromOwner,
    finalStats.classUnavailable))
