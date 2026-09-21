-- Manual update notices. This module performs no network request, downloads
-- nothing and installs nothing.
--
-- Two kinds of evidence, never mixed:
--   "bundled-release"  release metadata shipped inside this package. Trusted.
--                      A fixed file cannot learn a release made after it.
--   "peer-advisory"    a valid newer version stated by a Sync peer in the
--                      existing request version field. It is an unverified
--                      report. It never proves that a release exists, however
--                      high it is and however many peers repeat it.
-- The comparison is always against the actual installed identity
-- (Nexus.ReleaseIdentity): release series by standard SemVer precedence, then
-- the numeric test number inside one series. The commit suffix never orders.
-- The only link ever shown is the locally configured Releases page.

Nexus = Nexus or {}
local Updates = {}
Nexus.Updates = Updates

local callbacks = {}
local notifiedTargets = {}            -- session only: one chat notice per target
local sessionBest = {}                -- best peer report of this session, per kind
local peerObservations, peerObservationOrder = {}, {}
local MAX_PEER_OBSERVATIONS = 32
local MAX_TEST = 2147483647
local BUNDLED_AUTHORITY = "bundled-release"
local BUNDLED_UNAVAILABLE = "bundled-release-unavailable"
local PEER_ADVISORY = "peer-advisory"
local DEFAULT_URL = "https://github.com/Viscerals/Better-Nexus/releases"

local function Release()
    return type(Nexus.Release) == "table" and Nexus.Release or {}
end

local function Settings()
    if Nexus.Store and Nexus.Store.Settings then
        return Nexus.Store.Settings()
    end
    NexusDB = NexusDB or {}
    NexusDB.settings = type(NexusDB.settings) == "table" and NexusDB.settings or {}
    return NexusDB.settings
end

local function Refresh()
    if type(callbacks.refresh) == "function" then pcall(callbacks.refresh) end
end

local function Parse(value)
    if type(value) == "table" then return value end
    return Nexus.Version and Nexus.Version.Parse and Nexus.Version.Parse(value) or nil
end

local function Installed()
    if type(Nexus.ReleaseIdentity) == "function" then
        local ok, identity = pcall(Nexus.ReleaseIdentity)
        if ok and type(identity) == "table" then return identity end
    end
    local version = tostring(Release().version or "0.0.0")
    return {version=version, label="source", test=nil, channel="development",
        announce=version, display=version}
end

-- Release series without build metadata: "1.20.0-beta.1".
local function Series(parsed)
    local text = string.format("%d.%d.%d", parsed.major, parsed.minor, parsed.patch)
    if parsed.prereleaseText then text = text .. "-" .. parsed.prereleaseText end
    return text
end

-- Exactly "test.<number>" as build metadata states a public test number.
-- Anything else (a commit, a longer list, a huge number) states none.
local function TestNumber(parsed)
    local build = parsed.build
    if type(build) ~= "table" or #build ~= 2 then return nil end
    if build[1].text ~= "test" or not build[2].numeric then return nil end
    if #build[2].text > 10 or (#build[2].text > 1 and build[2].text:sub(1, 1) == "0") then return nil end
    local number = build[2].value
    if not number or number < 1 or number > MAX_TEST then return nil end
    return number
end

local CHANNEL_LABEL = {
    stable="stable release", ["public-test"]="public test build",
    internal="internal test package", development="development source",
}

function Updates.Preference()
    local stored = Settings().updateChannel
    if stored == "stable" or stored == "test" then return stored end
    local installed = Installed()
    -- Public testers get stable and test notices. A stable installation is
    -- never pushed toward a test build unless its user asks for that.
    return installed.channel == "stable" and "stable" or "test"
end

function Updates.SetPreference(value)
    if value ~= "stable" and value ~= "test" then return Updates.Preference() end
    Settings().updateChannel = value
    Updates.Reevaluate()
    return value
end

-- "test" | "stable" | nil: is this newer than the installed identity at all?
local function NewerKind(parsed, test)
    local installed = Installed()
    local order = Nexus.Version.Compare(parsed, installed.version)
    if order == nil or order < 0 then return nil end
    if order == 0 then
        -- Same release series: only a higher test number is newer. An
        -- installation without a test number cannot be placed in the series.
        if not (test and installed.test and test > installed.test) then return nil end
        return "test"
    end
    return parsed.prerelease and "test" or "stable"
end

-- The channel preference filters what is shown. It does not erase evidence.
local function Wanted(kind)
    return kind == "stable" or (kind == "test" and Updates.Preference() ~= "stable")
end

local function Display(series, test)
    return test and (series .. " test." .. tostring(test)) or series
end

local function TargetKey(series, test)
    return series .. "#" .. tostring(test or 0)
end

-- Higher release series first, then higher test number.
local function Better(a, b)
    if not b then return true end
    local order = Nexus.Version.Compare(a.version, b.version)
    if order ~= 0 then return order == 1 end
    return (a.test or 0) > (b.test or 0)
end

local function Candidate(parsed, test, authority, observedAt, anyChannel)
    local kind = NewerKind(parsed, test)
    if not kind or not (anyChannel or Wanted(kind)) then return nil end
    local series = Series(parsed)
    return {
        version=series, test=test, kind=kind, authority=authority,
        source=authority, observedAt=tonumber(observedAt) or 0,
        display=Display(series, test), key=TargetKey(series, test),
    }
end

local function BundledCandidate()
    local release = Release()
    local parsed = Parse(release.availableVersion)
    if not parsed then return nil end
    local test = TestNumber(parsed)
    local stated = tonumber(release.availableTest)
    if not test and stated and stated >= 1 and stated <= MAX_TEST
        and stated == math.floor(stated) then test = stated end
    return Candidate(parsed, test, BUNDLED_AUTHORITY, release.availableObservedAt)
end

-- A stored notice from an older client that took a peer version as release
-- authority is quarantined, exactly as before.
local function SanitizeStoredNotice(bundled)
    NexusDB = NexusDB or {}
    local stored = type(NexusDB.updateNotice) == "table" and NexusDB.updateNotice or nil
    if stored and stored.authority ~= BUNDLED_AUTHORITY
        and stored.authority ~= BUNDLED_UNAVAILABLE then
        stored.quarantinedReason = "unverified peer release authority"
        local previous = NexusDB.updateNoticeQuarantine
        if type(previous) == "table" and previous ~= stored then
            stored.previousQuarantine = previous
        end
        NexusDB.updateNoticeQuarantine = stored
        NexusDB.updateNotice = nil
        stored = nil
    end
    if not bundled then
        if stored then
            stored.authority = BUNDLED_UNAVAILABLE
            stored.source = BUNDLED_AUTHORITY
            stored.quarantinedReason = "bundled release metadata unavailable"
        end
        return
    end
    stored = stored or {}
    local changed = stored.version ~= bundled.version or stored.test ~= bundled.test
    stored.version, stored.test = bundled.version, bundled.test
    stored.observedAt = changed and bundled.observedAt
        or tonumber(stored.observedAt) or bundled.observedAt
    stored.source, stored.authority = BUNDLED_AUTHORITY, BUNDLED_AUTHORITY
    stored.quarantinedReason = nil
    NexusDB.updateNotice = stored
    bundled.observedAt = stored.observedAt
end

-- The stored advisory has one slot for the best reported test build and one
-- for the best reported stable release, so a stable-only user is never shown
-- a test build and never loses a stable report behind one. A slot holds a
-- validated version, a number and fixed words: no peer name, no peer text, no
-- link. Every read checks it again against the installed identity, so a manual
-- update clears it.
local SLOT = {test="testBuild", stable="stableRelease"}
local function StoredSlot(kind, anyChannel)
    NexusDB = NexusDB or {}
    local root = NexusDB.updateAdvisory
    if type(root) ~= "table" or root.authority ~= PEER_ADVISORY then
        NexusDB.updateAdvisory = nil
        return nil
    end
    local stored = root[SLOT[kind]]
    if stored == nil then return nil end
    local parsed = type(stored) == "table" and type(stored.version) == "string"
        and Parse(stored.version) or nil
    local test = type(stored) == "table" and tonumber(stored.test) or nil
    if test and (test < 1 or test > MAX_TEST or test ~= math.floor(test)) then parsed = nil end
    local candidate = parsed and not parsed.build
        and Candidate(parsed, test, PEER_ADVISORY, stored.observedAt, true) or nil
    if not candidate or candidate.kind ~= kind then
        root[SLOT[kind]] = nil               -- malformed, or no longer newer than this installation
        return nil
    end
    if not anyChannel and not Wanted(kind) then return nil end
    return candidate
end

local function StoredAdvisory()
    local test, stable = StoredSlot("test"), StoredSlot("stable")
    -- What peers state in this session is shown before a report that was only
    -- kept from an earlier session: an old false report must not hide it.
    local liveTest = test and sessionBest.test and sessionBest.test.key == test.key
    local liveStable = stable and sessionBest.stable and sessionBest.stable.key == stable.key
    if liveTest ~= liveStable then return liveTest and test or stable end
    if test and stable then return Better(test, stable) and test or stable end
    return test or stable
end

local function Current()
    local bundled = BundledCandidate()
    SanitizeStoredNotice(bundled)
    local advisory = StoredAdvisory()
    -- Trusted evidence wins unless the unverified report is strictly newer.
    if bundled and not (advisory and Better(advisory, bundled)) then return bundled end
    return advisory or bundled
end

local function Message(candidate)
    local installed = Installed()
    local you = " You have " .. installed.display .. "."
    if candidate.authority == BUNDLED_AUTHORITY then
        return (candidate.kind == "stable" and "New Nexus release available: "
            or "New Nexus test build available: ") .. candidate.display .. "." .. you
            .. " Installation is manual: /nexus update shows the Releases page."
    end
    return (candidate.kind == "stable" and "A newer Nexus release was reported: "
        or "A newer Nexus test build was reported: ") .. candidate.display .. "." .. you
        .. " Check GitHub Releases before updating. This report is not verified."
        .. " /nexus update shows the Releases page."
end

local function MaybeNotify(candidate)
    if type(candidate) ~= "table" or not Updates.IsEnabled() then return false end
    if notifiedTargets[candidate.key] then return false end
    NexusDB = NexusDB or {}
    if NexusDB.updateDismissed == candidate.key then return false end
    if type(callbacks.notify) == "function" then
        local ok = pcall(callbacks.notify, candidate.display, Updates.ReleaseUrl(), Message(candidate))
        if not ok then return false end
    end
    notifiedTargets[candidate.key] = true
    return true
end

function Updates.Reevaluate()
    local candidate = Current()
    MaybeNotify(candidate)
    Refresh()
    return candidate
end

function Updates.Init(nextCallbacks)
    callbacks = type(nextCallbacks) == "table" and nextCallbacks or {}
    notifiedTargets, sessionBest = {}, {}
    peerObservations, peerObservationOrder = {}, {}
    local settings = Settings()
    if settings.updateNotifications == nil then settings.updateNotifications = true end
    Updates.Reevaluate()
end

-- One accepted Sync peer version. `version` is the parsed table or the wire
-- text that the inbound validator already accepted; `source` is the sender and
-- stays in the bounded session list only.
function Updates.Observe(version, source)
    local parsed = Parse(version)
    if type(parsed) ~= "table" or type(parsed.major) ~= "number" then
        return false, "invalid version"
    end
    source = type(source) == "string" and source or "unknown"
    if #source > 80 then source = source:sub(1, 80) end
    if peerObservations[source] == nil then
        peerObservationOrder[#peerObservationOrder + 1] = source
        if #peerObservationOrder > MAX_PEER_OBSERVATIONS then
            local removed = table.remove(peerObservationOrder, 1)
            peerObservations[removed] = nil
        end
    end
    peerObservations[source] = {
        version=parsed.normalized,
        observedAt=time and tonumber(time()) or 0,
        source=source,
        authority="peer-observation",
    }

    local test = TestNumber(parsed)
    local candidate = Candidate(parsed, test, PEER_ADVISORY, time and time() or 0, true)
    if not candidate then return true, "peer observation" end
    -- The best report of THIS session replaces a report kept from an earlier
    -- session, also a higher one: an old false report must not hide what
    -- peers state now. The same or an older target changes nothing.
    local best = sessionBest[candidate.kind]
    if best and not Better(candidate, best) then
        return true, "peer observation"
    end
    sessionBest[candidate.kind] = candidate
    NexusDB = NexusDB or {}
    local root = type(NexusDB.updateAdvisory) == "table"
        and NexusDB.updateAdvisory.authority == PEER_ADVISORY and NexusDB.updateAdvisory or {}
    root.authority = PEER_ADVISORY
    root[SLOT[candidate.kind]] = {
        version=candidate.version, test=candidate.test, observedAt=candidate.observedAt,
    }
    NexusDB.updateAdvisory = root
    Updates.Reevaluate()
    return true, "peer advisory"
end

function Updates.PeerObservations()
    local out = {}
    for _, source in ipairs(peerObservationOrder) do
        local row = peerObservations[source]
        if row then
            out[#out + 1] = {
                version=row.version,observedAt=row.observedAt,
                source=row.source,authority=row.authority,
            }
        end
    end
    return out
end

function Updates.GetCandidate()
    local candidate = Current()
    if not candidate then return nil end
    return {
        version=candidate.version, test=candidate.test, kind=candidate.kind,
        display=candidate.display, key=candidate.key,
        observedAt=candidate.observedAt, source=candidate.source,
        authority=candidate.authority,
        verified=candidate.authority == BUNDLED_AUTHORITY,
    }
end

function Updates.GetVisibleNotice()
    if not Updates.IsEnabled() then return nil end
    return Updates.GetCandidate()
end

-- Everything the menu, the popup, /nexus update and Help show. It needs no
-- Community catalog and no peer. "unknown" means no evidence was received; it
-- is never a statement that this installation is the latest.
function Updates.Status()
    local installed = Installed()
    local enabled = Updates.IsEnabled()
    local candidate = Updates.GetCandidate()
    local status = {
        installed=installed.display, installedLabel=installed.label,
        channel=installed.channel,
        channelLabel=CHANNEL_LABEL[installed.channel] or installed.channel,
        preference=Updates.Preference(), enabled=enabled,
        url=Updates.ReleaseUrl(), candidate=enabled and candidate or nil,
    }
    local have = "Installed: " .. installed.display .. " (" .. status.channelLabel
        .. (installed.label ~= "source" and (", " .. installed.label) or "") .. ")."
    if not enabled then
        status.state, status.menu = "disabled", "Update notices off - open Releases page"
        status.detail = have .. " Update notices are off."
    elseif not candidate then
        status.state, status.menu = "unknown", "Update status unknown - open Releases page"
        status.detail = have .. " No newer build was reported to this client. That is not proof that this build is the latest."
    elseif candidate.verified then
        status.state = "available"
        status.menu = "Update available: " .. candidate.display
        status.detail = have .. " " .. (candidate.kind == "stable" and "New Nexus release available: "
            or "New Nexus test build available: ") .. candidate.display .. "."
    else
        status.state = "reported"
        status.menu = "Newer build reported (unverified): " .. candidate.display
        status.detail = have .. " " .. (candidate.kind == "stable" and "A newer Nexus release was reported: "
            or "A newer Nexus test build was reported: ") .. candidate.display
            .. ". This report comes from another player's client and is not verified. Check GitHub Releases before updating."
    end
    status.detail = status.detail .. " Notices: "
        .. (status.preference == "stable" and "stable releases only." or "stable releases and public test builds.")
    return status
end

-- The user has seen this target. No further chat notice for it, in this or a
-- later session. The menu status stays. A newer target is announced again.
function Updates.Dismiss()
    local candidate = Current()
    if not candidate then return false end
    NexusDB = NexusDB or {}
    NexusDB.updateDismissed = candidate.key
    notifiedTargets[candidate.key] = true
    return true
end

function Updates.IsEnabled()
    return Settings().updateNotifications ~= false
end

function Updates.SetEnabled(enabled)
    Settings().updateNotifications = enabled and true or false
    Updates.Reevaluate()
    return Updates.IsEnabled()
end

-- Always the locally configured page. Nothing a peer sends can reach this.
function Updates.ReleaseUrl()
    local url = Release().releasesUrl
    if type(url) ~= "string" or not url:match("^https://github%.com/[%w%-%._]+/[%w%-%._]+/releases$") then
        return DEFAULT_URL
    end
    return url
end
