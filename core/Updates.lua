-- Manual update notices from bundled release authority only. Accepted Sync
-- peer versions remain bounded diagnostic observations and never prove that a
-- corresponding release exists. This module performs no network requests.

Nexus = Nexus or {}
local Updates = {}
Nexus.Updates = Updates

local callbacks = {}
local sessionNotified = false
local peerObservations, peerObservationOrder = {}, {}
local MAX_PEER_OBSERVATIONS = 32
local BUNDLED_AUTHORITY = "bundled-release"
local BUNDLED_UNAVAILABLE = "bundled-release-unavailable"

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

local function BaseVersion()
    local release = Release()
    return tostring(release.baseVersion or release.version or "0.0.0")
end

local function Refresh()
    if type(callbacks.refresh) == "function" then pcall(callbacks.refresh) end
end

local function ParsePublishedNewer(value)
    local parsed = type(value) == "table" and value
        or (Nexus.Version and Nexus.Version.Parse and Nexus.Version.Parse(value))
    if not parsed or parsed.publishedCandidate ~= true then return nil end
    if Nexus.Version.Compare(parsed, BaseVersion()) ~= 1 then return nil end
    return parsed
end

local function BundledCandidate()
    local release = Release()
    local parsed = ParsePublishedNewer(release.availableVersion)
    if not parsed then return nil end
    return {
        version=parsed.normalized,
        observedAt=tonumber(release.availableObservedAt) or 0,
        source=BUNDLED_AUTHORITY,
        authority=BUNDLED_AUTHORITY,
    }
end

local function MaybeNotify(candidate)
    if sessionNotified or not Updates.IsEnabled() or type(candidate) ~= "table" then return end
    if type(callbacks.notify) == "function" then
        local ok = pcall(callbacks.notify, candidate.version, Updates.ReleaseUrl())
        if not ok then return end
    end
    sessionNotified = true
end

local function SanitizeCandidate()
    NexusDB = NexusDB or {}
    local candidate = type(NexusDB.updateNotice) == "table"
        and NexusDB.updateNotice or nil
    if candidate and candidate.authority ~= BUNDLED_AUTHORITY
        and candidate.authority ~= BUNDLED_UNAVAILABLE then
        candidate.quarantinedReason = "unverified peer release authority"
        local previous = NexusDB.updateNoticeQuarantine
        if type(previous) == "table" and previous ~= candidate then
            candidate.previousQuarantine = previous
        end
        NexusDB.updateNoticeQuarantine = candidate
        NexusDB.updateNotice = nil
        candidate = nil
    end

    local bundled = BundledCandidate()
    if not bundled then
        if candidate then
            candidate.authority = BUNDLED_UNAVAILABLE
            candidate.source = BUNDLED_AUTHORITY
            candidate.quarantinedReason = "bundled release metadata unavailable"
            NexusDB.updateNotice = candidate
        end
        return nil
    end

    if not candidate then candidate = {} end
    local changedVersion = candidate.version ~= bundled.version
    candidate.version = bundled.version
    candidate.observedAt = changedVersion and bundled.observedAt
        or tonumber(candidate.observedAt) or bundled.observedAt
    candidate.source = BUNDLED_AUTHORITY
    candidate.authority = BUNDLED_AUTHORITY
    candidate.quarantinedReason = nil
    NexusDB.updateNotice = candidate
    return candidate
end

function Updates.Init(nextCallbacks)
    callbacks = type(nextCallbacks) == "table" and nextCallbacks or {}
    sessionNotified = false
    peerObservations, peerObservationOrder = {}, {}
    local settings = Settings()
    if settings.updateNotifications == nil then settings.updateNotifications = true end
    local candidate = SanitizeCandidate()
    MaybeNotify(candidate)
    Refresh()
end

function Updates.Observe(version, source)
    local parsed = type(version) == "table" and version
        or (Nexus.Version and Nexus.Version.Parse and Nexus.Version.Parse(version))
    if not parsed then return false, "invalid version" end
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
    return true, "peer observation"
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
    local candidate = SanitizeCandidate()
    if not candidate then return nil end
    return {
        version = candidate.version,
        observedAt = candidate.observedAt,
        source = candidate.source,
        authority = candidate.authority,
    }
end

function Updates.GetVisibleNotice()
    if not Updates.IsEnabled() then return nil end
    return Updates.GetCandidate()
end

function Updates.IsEnabled()
    return Settings().updateNotifications ~= false
end

function Updates.SetEnabled(enabled)
    Settings().updateNotifications = enabled and true or false
    if enabled then MaybeNotify(SanitizeCandidate()) end
    Refresh()
    return Updates.IsEnabled()
end

function Updates.ReleaseUrl()
    return tostring(Release().releasesUrl
        or "https://github.com/Viscerals/Better-Nexus/releases")
end
