local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")
dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")

local Version, Updates, Sync = Nexus.Version, Nexus.Updates, Nexus.Sync
local function Parsed(value)
    local parsed = Version.Parse(value)
    assert(parsed, "expected valid version: " .. tostring(value))
    return parsed
end

assert(Parsed("v2").normalized == "2.0.0", "optional v/missing components failed")
assert(Parsed("1.20").normalized == "1.20.0", "missing patch did not normalize")
assert(Parsed("1.20.3-rc.2").prereleaseText == "rc.2", "prerelease parse failed")
assert(Parsed("1.20.3+local.5").buildText == "local.5", "build metadata parse failed")
assert(Version.Compare("1.20", "1.19.99") == 1, "numeric comparison failed")
assert(Version.Compare("1.20.0-rc.2", "1.20.0-rc.10") == -1,
    "numeric prerelease ordering failed")
assert(Version.Compare("1.20.0", "1.20.0-rc.10") == 1,
    "stable release did not outrank prerelease")
assert(Version.Compare("1.20.0+one", "1.20.0+two") == 0,
    "build metadata incorrectly changed precedence")
for _, invalid in ipairs({"", "v", "01.2.3", "1..2", "1.2.3-", "1.2.3+",
    "1.2.3-01", "1.2.3_beta", "1.2.3.4", string.rep("9", 33)}) do
    assert(Version.Parse(invalid) == nil, "malformed version accepted: " .. tostring(invalid))
end

assert(Nexus.Release.version == "1.20.0-beta.1"
    and Nexus.Release.baseVersion == "1.19.5"
    and Nexus.Release.buildLabel == "source"
    and Nexus.RuntimeBuildLabel() == "source"
    and Nexus.Release.published == false,
    "beta release identity does not retain the actual stable base")
UnitName = function() return "Local" end
GetNormalizedRealmName = function() return "Ebonhold" end
NexusDB = {
    settingsVersion=1,
    settings={autoPick=false,customPreference="keep"},
    buildFilters={classFilter="MAGE",futureFilter="keep"},
    chars={},communityBuilds={},syncTombstones={},dpsCapture={},
    updateNotice={version="99.0.0-rc.1",observedAt="bad",source=42},
}
Nexus.Store.Init()
assert(NexusDB.settings.autoPick == false
    and NexusDB.settings.customPreference == "keep"
    and NexusDB.settings.updateNotifications == true
    and NexusDB.buildFilters.qualifiedOnly == false
    and NexusDB.buildFilters.futureFilter == "keep",
    "additive update setting reset unrelated preferences")

local notices, refreshes = {}, 0
local function InitUpdates()
    Updates.Init({
        notify=function(version,url) notices[#notices+1]={version=version,url=url} end,
        refresh=function() refreshes=refreshes+1 end,
    })
end
InitUpdates()
assert(NexusDB.updateNotice == nil and #notices == 0,
    "persisted prerelease poison survived sanitation or notified")
assert(not Updates.Observe("1.19.4", "Older") and not Updates.Observe("1.19.5", "Equal"),
    "older/equal version created an update")
assert(not Updates.Observe("9.0.0-dev", "Dev")
    and not Updates.Observe("9.0.0-rc.1", "Prerelease")
    and not Updates.Observe("9.0.0+local", "Metadata"),
    "development/prerelease/build metadata created a published notice")
assert(Updates.Observe("1.20.0", "Newer"))
assert(Updates.Observe("1.19.9", "LaterOlder"))
assert(Updates.Observe("v2", "Highest"))
assert(Updates.Observe("1.21.0", "LastOlder"))
local candidate = Updates.GetCandidate()
assert(candidate and candidate.version == "2.0.0" and candidate.source == "Highest",
    "highest candidate was downgraded by later peers")
candidate.version = "0.0.0"
assert(Updates.GetCandidate().version == "2.0.0",
    "candidate query exposed mutable persisted update state")
assert(#notices == 1 and notices[1].version == "1.20.0",
    "update chat was not limited to one per session")
assert(notices[1].url == Nexus.Release.releasesUrl,
    "notice did not expose the stable releases page")

Updates.SetEnabled(false)
assert(Updates.Observe("3.0.0", "OptedOut") and Updates.GetVisibleNotice() == nil,
    "opt-out stopped retention or left the visible notice enabled")
assert(#notices == 1 and Updates.GetCandidate().version == "3.0.0",
    "opt-out erased the candidate or printed chat")
InitUpdates() -- new session/reload while disabled
assert(#notices == 1 and Updates.GetVisibleNotice() == nil,
    "disabled persisted candidate notified on reload")
Updates.SetEnabled(true)
assert(#notices == 2 and Updates.GetVisibleNotice().version == "3.0.0",
    "re-enabling did not expose the retained candidate exactly once")
assert(Updates.Observe("4.0.0", "SameSession") and #notices == 2,
    "higher candidate printed a second chat notice in one session")

-- Only accepted recognized traffic may create peer/update state.
NexusDB.communityBuilds, NexusDB.syncTombstones = {}, {}
Sync.Init(Nexus.Codec,{})
local chars, builds, dps, tombstones = NexusDB.chars, NexusDB.communityBuilds,
    NexusDB.dpsCapture, NexusDB.syncTombstones
assert(Sync.HandleIncoming("WLNP|StablePeer|5.0.0", "StablePeer"))
assert(Sync.GetPeerInfo("StablePeer").version == "5.0.0"
    and Updates.GetCandidate().version == "5.0.0",
    "accepted stable presence did not update peer/candidate state")
assert(Sync.HandleIncoming("WLNP|Local|99.0.0", "Local")
    and Sync.GetPeerInfo("Local") == nil and Updates.GetCandidate().version == "5.0.0",
    "self traffic created peer or update state")
assert(Sync.HandleIncoming("WLNP|DevPeer|v9.0.0-dev.1", "DevPeer"))
assert(Sync.GetPeerInfo("DevPeer").version == "9.0.0-dev.1"
    and Updates.GetCandidate().version == "5.0.0",
    "valid development peer became a published candidate")
assert(not Sync.HandleIncoming("WLNP|Malformed|1..2", "Malformed")
    and Sync.GetPeerInfo("Malformed") == nil,
    "malformed version entered peer state")
assert(not Sync.HandleIncoming("WLNP|Oversized|" .. string.rep("9", 80), "Oversized")
    and Sync.GetPeerInfo("Oversized") == nil,
    "oversized version entered peer state")
assert(not Sync.HandleIncoming("WLNP|Overflow|2147483648.0.0", "Overflow")
    and Sync.GetPeerInfo("Overflow") == nil,
    "overflowing numeric version entered peer state")
assert(not Sync.HandleIncoming("WLNP|Declared|6.0.0", "Different")
    and Sync.GetPeerInfo("Declared") == nil and Sync.GetPeerInfo("Different") == nil,
    "sender-mismatched traffic entered peer/update state")
assert(not Sync.HandleIncoming("UNKNOWN|Unknown|7.0.0", "Unknown")
    and Sync.GetPeerInfo("Unknown") == nil,
    "unknown traffic entered peer/update state")
assert(Sync.HandleIncoming("WLRQ|LegacyPeer|0|0|legacy-no-version", "LegacyPeer")
    and Sync.GetPeerInfo("LegacyPeer") and Sync.GetPeerInfo("LegacyPeer").version == nil,
    "older versionless request lost compatibility")
assert(NexusDB.chars == chars and NexusDB.communityBuilds == builds
    and NexusDB.dpsCapture == dps and NexusDB.syncTombstones == tombstones,
    "update detection mutated character/build/DPS/tombstone state")

print("semantic version and accepted-Sync update detection -- OK")
