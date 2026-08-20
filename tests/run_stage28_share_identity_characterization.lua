-- Stage 28.6 expected-red characterization for Share input and exact UTF-8
-- identity. Keep every failure named so the repair cannot hide one boundary
-- behind an earlier assertion.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local failures = {}
local function Check(ok, name)
    if not ok then failures[#failures + 1] = name end
end

local accented = "Valentin" .. string.char(0xC3, 0xA9)
local ascii = "Valentine"
local malformed = "Valentin" .. string.char(0xC3)
local mojibake = "Valentin" .. string.char(0xC3, 0x83, 0xC2, 0xA9)
local leadingAccent = string.char(0xC3, 0x89) .. "lodie"
local safeDescription = "Caf" .. string.char(0xC3, 0xA9) .. " priority"

UnitName = function() return accented end
GetNormalizedRealmName = function() return "Ebonhold" end

NexusDB = {
    settingsVersion=2, settings={}, chars={}, dpsCapture={},
    buildFilters={scope="all",sortMode="title"}, communityBuilds={},
}
Nexus.Store.Init()

local slot = {slot=1,name="UTF-8 Source",class="MAGE",echoes={
    {spellId=730001,quality=3,stacks=1},
}}
local Adapter = {
    Slots=function() return {bySlot={[1]=slot},activeSlot=1} end,
    GetWishlistCandidates=function() return {} end,
    Catalog=function() return {rows={
        [730001]={name="Exact Echo",classMask=128},
    }} end,
    Owned=function() return {bySpell={[730001]=1}} end,
    LockedOwned=function() return {bySpell={}} end,
    Wishlist=function() return slot end,
}
Nexus.DpsCapture = {
    GetLeaderboard=function() return {} end,
    GetLeaderboardForEchoes=function() return {} end,
    GetPersonalBest=function() return nil end,
    GetDpsBoard=function() return {} end,
    IsDetailsAvailable=function() return false end,
}
Nexus.Sync = {
    BroadcastBuildSummary=function() return true end,
    RequestLoadout=function() return true end,
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {received=0} end,
    RequestSync=function() return true end,
}

dofile("ui/CommunityBuilds.lua")
local Community = Nexus.CommunityBuilds
Community.Init(Adapter, nil)

Community.ShowPostBuild()
local post = assert(H.frames.NexusPostPopup)
local postDescription = assert(post._postDescBox)
local postMouse = postDescription:GetScript("OnMouseDown")
if postMouse then postMouse(postDescription) end
Check(postDescription:HasFocus(), "post description click did not focus")
Community.TogglePostPopup()
Check(not postDescription:HasFocus(), "post description cancel retained focus")

Community.ShowPostBuild()
post._postTitleBox:SetText("Exact UTF-8 owner")
postDescription:SetText(safeDescription)
assert(post._postGoBtn:GetScript("OnClick"))()
local shared
for _, build in pairs(NexusDB.communityBuilds) do shared = build break end
Check(shared and shared.author == accented,
    "Share changed exact UTF-8 author bytes")
Check(shared and shared.ownerKey == accented:lower() .. "@ebonhold",
    "Share changed exact UTF-8 owner-key bytes")
Check(shared and shared.description == safeDescription,
    "Share changed valid UTF-8 description bytes")
Check(not postDescription:HasFocus(),
    "successful Share retained description focus")

local sharedId = shared and shared.id
if sharedId then
    Community.ToggleEditPopup(sharedId)
    local edit = assert(H.frames.NexusEditPopup)
    local editDescription = assert(edit._editDescBox)
    local editMouse = editDescription:GetScript("OnMouseDown")
    if editMouse then editMouse(editDescription) end
    Check(editDescription:HasFocus(), "edit description click did not focus")
    editDescription:SetFocus()
    Community.ToggleEditPopup(sharedId)
    Check(not editDescription:HasFocus(), "edit description cancel retained focus")

    local before = Nexus.BuildCatalog.Get(sharedId).description
    local okPipe = Community.EditBuild(sharedId, shared.title, "unsafe|description")
    Check(not okPipe and Nexus.BuildCatalog.Get(sharedId).description == before,
        "pipe description mutated the build")
    local okControl = Community.EditBuild(sharedId, shared.title,
        "unsafe" .. string.char(1) .. "description")
    Check(not okControl and Nexus.BuildCatalog.Get(sharedId).description == before,
        "control description mutated the build")
    local okMalformed = Community.EditBuild(sharedId, shared.title, malformed)
    Check(not okMalformed and Nexus.BuildCatalog.Get(sharedId).description == before,
        "malformed UTF-8 description mutated the build")
    local okLong = Community.EditBuild(sharedId, shared.title,
        string.rep("x", 2001))
    Check(not okLong, "overlong description was accepted")
end

local Identity = Nexus.Identity
Check(type(Identity) == "table", "canonical identity module is missing")
if type(Identity) == "table" then
    Check(Identity.PlayerKey(accented) == accented:lower(),
        "exact UTF-8 player key changed bytes")
    Check(Identity.PlayerKey(leadingAccent) == leadingAccent,
        "valid leading UTF-8 player identity was rejected")
    Check(Identity.PlayerKey(ascii) ~= Identity.PlayerKey(accented),
        "distinct ASCII and UTF-8 names collapsed")
    Check(Identity.PlayerKey(malformed) == nil,
        "malformed UTF-8 player identity was accepted")
    Check(Identity.PlayerKey(mojibake) == nil,
        "mojibake player identity was accepted")
    Check(Identity.PlayerKey(accented .. "|x") == nil,
        "pipe player identity was accepted")
    Check(Identity.OwnerKeyMatchesAuthor(
        accented:lower() .. "@ebonhold", accented),
        "exact UTF-8 owner key did not match its author")
    Check(not Identity.OwnerKeyMatchesAuthor(
        ascii:lower() .. "@ebonhold", accented),
        "altered owner identity matched exact UTF-8 author")
    Check(Identity.SameTransportSender(accented .. "-Ebonhold",
        accented .. "-Ebonhold"),
        "exact realm-qualified transport identity did not match")
    Check(not Identity.SameTransportSender(accented .. "-Ebonhold",
        ascii .. "-Ebonhold"),
        "altered transport identity matched exact UTF-8 sender")
    Check(Identity.OwnerKey(accented, "Realm-Cluster")
            == accented:lower() .. "@realm-cluster",
        "hyphenated realm identity was rejected")
end

dofile("core/SyncProtocol.lua")
local protocol = Nexus.SyncInternals.Protocol.New({
    limits={maxTransferIdBytes=80,maxHashBytes=256,maxVersionBytes=40,
        maxBuildIdBytes=96,maxBuildEchoes=120,maxRequestIdBytes=80,
        bucketCount=8,maxWireFields=8},
    parseVersion=function() return {major=1} end,
    ownerKeyMatchesAuthor=Identity and Identity.OwnerKeyMatchesAuthor
        or function() return true end,
    isSafeTree=function() return true end,
})
Check(protocol.ValidPeerName(accented),
    "protocol rejected exact UTF-8 peer identity")
Check(not protocol.ValidPeerName(malformed),
    "protocol accepted malformed UTF-8 peer identity")
Check(not protocol.ValidPeerName(mojibake),
    "protocol accepted mojibake peer identity")
if Identity then
    local wireBuild = {
        id="utf8-wire",t="Exact identity",a=accented,
        o=accented:lower() .. "@ebonhold",c="MAGE",m=1,
        e={{730001,3,1}},
    }
    local decoded = protocol.ValidateNetworkPayload(wireBuild)
    Check(decoded and decoded.author == accented
            and decoded.ownerKey == accented:lower() .. "@ebonhold",
        "protocol changed exact UTF-8 author or owner bytes")
    wireBuild.o = ascii:lower() .. "@ebonhold"
    Check(protocol.ValidateNetworkPayload(wireBuild) == nil,
        "protocol accepted altered UTF-8 owner identity")
    wireBuild.a, wireBuild.o = malformed, nil
    Check(protocol.ValidateNetworkPayload(wireBuild) == nil,
        "protocol accepted malformed UTF-8 author identity")
end

dofile("core/PeerDebug.lua")
Nexus.PeerDebug.Start(accented)
Check(Nexus.PeerDebug.Stats().peer == accented,
    "PeerDebug changed exact UTF-8 filter bytes")
Check(Nexus.PeerDebug.Record("identity", {peer=accented,outcome="accepted"}),
    "PeerDebug rejected exact UTF-8 event peer")
Check(not Nexus.PeerDebug.Record("identity", {peer=ascii,outcome="rejected"}),
    "PeerDebug collapsed distinct player identities")
Nexus.PeerDebug.Stop()
Nexus.PeerDebug.Clear()
Check(not Nexus.PeerDebug.Start(malformed)
        and not Nexus.PeerDebug.Stats().enabled,
    "malformed PeerDebug target widened into an unfiltered session")

if #failures > 0 then
    error("EXPECTED RED Stage 28.6: " .. table.concat(failures, "; "))
end

print("Stage 28.6 Share input and exact UTF-8 identity characterization -- OK")
