-- Manual update detection from already accepted Nexus Sync peer versions.
-- This module performs no network or release-page requests.

Nexus = Nexus or {}
local Updates = {}
Nexus.Updates = Updates

local callbacks = {}
local sessionNotified = false

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

local function Candidate()
    NexusDB = NexusDB or {}
    return type(NexusDB.updateNotice) == "table" and NexusDB.updateNotice or nil
end

local function BaseVersion()
    local release = Release()
    return tostring(release.baseVersion or release.version or "0.0.0")
end

local function Refresh()
    if type(callbacks.refresh) == "function" then pcall(callbacks.refresh) end
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
    local candidate = Candidate()
    if not candidate then return nil end
    local parsed = Nexus.Version and Nexus.Version.Parse
        and Nexus.Version.Parse(candidate.version) or nil
    local comparison = parsed and Nexus.Version.Compare(parsed, BaseVersion()) or nil
    if not parsed or not parsed.publishedCandidate or comparison ~= 1 then
        NexusDB.updateNotice = nil
        return nil
    end
    candidate.version = parsed.normalized
    candidate.observedAt = tonumber(candidate.observedAt) or 0
    candidate.source = type(candidate.source) == "string" and candidate.source or nil
    return candidate
end

function Updates.Init(nextCallbacks)
    callbacks = type(nextCallbacks) == "table" and nextCallbacks or {}
    sessionNotified = false
    local settings = Settings()
    if settings.updateNotifications == nil then settings.updateNotifications = true end
    local candidate = SanitizeCandidate()
    MaybeNotify(candidate)
    Refresh()
end

function Updates.Observe(version, source)
    local parsed = type(version) == "table" and version
        or (Nexus.Version and Nexus.Version.Parse and Nexus.Version.Parse(version))
    if not parsed or not parsed.publishedCandidate then return false, "not published" end
    if Nexus.Version.Compare(parsed, BaseVersion()) ~= 1 then return false, "not newer" end

    local current = SanitizeCandidate()
    if current then
        local comparison = Nexus.Version.Compare(parsed, current.version)
        if comparison ~= 1 then
            MaybeNotify(current)
            return true, "already have same or newer"
        end
    end

    NexusDB.updateNotice = {
        version = parsed.normalized,
        observedAt = time and tonumber(time()) or 0,
        source = type(source) == "string" and source or nil,
    }
    MaybeNotify(NexusDB.updateNotice)
    Refresh()
    return true, "new candidate"
end

function Updates.GetCandidate()
    local candidate = SanitizeCandidate()
    if not candidate then return nil end
    return {
        version = candidate.version,
        observedAt = candidate.observedAt,
        source = candidate.source,
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
