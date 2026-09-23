-- Manual update notices. This module performs no network request, downloads
-- nothing and installs nothing.
--
-- Release evidence has one source only:
--   "bundled-release"  release metadata shipped inside this package. Trusted.
--                      A fixed file cannot learn a release made after it.
-- A version stated by a Sync peer is a bounded session DIAGNOSTIC only
-- (Updates.PeerObservations). It never proves that a release exists, however
-- high it is, however many peers repeat it and whatever metadata it carries,
-- so it never becomes a release candidate, never replaces or hides bundled
-- evidence and is never saved (2026-09-21: a peer stating "1.96.6" was
-- announced as a newer release). Without bundled evidence the state is
-- "unknown" with the configured Releases page.
--
-- 2026-09-23, authorized narrowing of that rule for ONE labelled case: an
-- announcement with the exact public test shape, in the series this public
-- test installation is in, with a higher test number, is shown as a
-- session-only UNVERIFIED HINT (Updates.PublicTestHint). A hint is not release
-- evidence and says so: it never states that GitHub was checked, never asserts
-- that the build exists or is safe, never carries a peer-supplied link, never
-- raises the trusted HUD badge, never becomes the candidate, and is never
-- written to saved data. Everything else a peer can say stays silent.
-- The comparison is always against the actual installed identity
-- (Nexus.ReleaseIdentity): release series by standard SemVer precedence, then
-- the numeric test number inside one series. The commit suffix never orders.
-- The only link ever shown is the locally configured Releases page.

Nexus = Nexus or {}
local Updates = {}
Nexus.Updates = Updates

local callbacks = {}
-- Saved-data maintenance of the update keys (notice sanitation, the one-time
-- peer-advisory quarantine, the legacy dismissed-list conversion and a new
-- dismissal) happens only when saved data may really be written. Two
-- conditions must hold: the start-up that initialized this module stated that
-- its session may write, and the saved-data owner does not refuse writes at
-- that moment. A refused shared catalog and a read-only saved format therefore
-- keep every stored update key exactly as found, also through /nexus update,
-- which answers before start-up completes. An owner that is merely still
-- loading is an early state of a valid owner, not a refusal, so ordinary
-- upkeep is unchanged there. The bundled release notice is evaluated and shown
-- in every case.
local sessionPersists = true
local function CanPersist()
    if not sessionPersists then return false end
    local Store = Nexus.Store
    -- No saved-data owner is loaded at all (standalone package checks).
    if type(Store) ~= "table" or type(Store.StateWriteStatus) ~= "function" then
        return true
    end
    local ok, status = pcall(Store.StateWriteStatus)
    if not ok or type(status) ~= "table" then return false end
    return status.mode ~= "unavailable"
end
local notifiedTargets = {}            -- session only: one chat notice per target
local hintTarget = nil                -- session only: the highest reported public test
local hintNotified, hintDismissed = {}, {}
local hintNotices = 0
local peerObservations, peerObservationOrder = {}, {}
local MAX_PEER_OBSERVATIONS = 32
local MAX_SESSION_NOTICES = 3         -- chat lines about updates per session
local MAX_DISMISSED = 8
local sessionNotices = 0
local MAX_TEST = 2147483647
local BUNDLED_AUTHORITY = "bundled-release"
-- A public-test HINT is a peer report that has the exact public test shape and
-- is newer than this installation inside the same release series. It is shown
-- as an explicitly unverified hint, separately from bundled release
-- information, and it is never stored, never a candidate and never authority:
-- a syntactically perfect announcement can still be false.
local HINT_AUTHORITY = "peer-report-unverified"
local MAX_HINT_NOTICES = 2            -- chat lines about hints per session
-- The status is read in a chat line and in a popup, so it is kept to short
-- lines instead of one long sentence.
local LINE = "\n"
local BUNDLED_UNAVAILABLE = "bundled-release-unavailable"
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

-- Release series without build metadata, rebuilt from numbers and one fixed
-- word: "1.20.0" or "1.20.0-beta.1". nil for every other shape. Free-form
-- prerelease text (any other word, more identifiers, a host name) is never a
-- series, so no text chosen by a peer is ever shown or stored.
local SERIES_WORD = {alpha=true, beta=true, rc=true}
local function Series(parsed)
    local text = string.format("%d.%d.%d", parsed.major, parsed.minor, parsed.patch)
    local pre = parsed.prerelease
    if pre == nil then return text end
    if type(pre) ~= "table" or #pre ~= 2 or not SERIES_WORD[pre[1].text]
        or not pre[2].numeric or #pre[2].text > 4 then return nil end
    return text .. "-" .. pre[1].text .. "." .. pre[2].text
end

-- The two shapes in which a peer version states a release. Used only to
-- classify the diagnostic observation; it is never release evidence:
--   stable release     X.Y.Z             no prerelease, no build metadata
--   public test build  X.Y.Z-word.N+test.M
-- A prerelease without a public test number is not a public build: older
-- published lines (for example 1.20.0-beta.3.community-off), internal packages
-- and development checkouts all state one, and none of them is an upgrade.
local function PeerReportable(parsed, test)
    if not Series(parsed) then return false end
    if parsed.prerelease == nil then return parsed.build == nil end
    return test ~= nil
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
    local series = Series(parsed)
    if not series then return nil end
    local kind = NewerKind(parsed, test)
    if not kind or not (anyChannel or Wanted(kind)) then return nil end
    return {
        version=series, test=test, kind=kind, authority=authority,
        source=authority, observedAt=tonumber(observedAt) or 0,
        display=Display(series, test), key=TargetKey(series, test),
    }
end

local function BundledCandidate(anyChannel)
    local release = Release()
    local parsed = Parse(release.availableVersion)
    if not parsed then return nil end
    local test = TestNumber(parsed)
    local stated = tonumber(release.availableTest)
    if not test and stated and stated >= 1 and stated <= MAX_TEST
        and stated == math.floor(stated) then test = stated end
    return Candidate(parsed, test, BUNDLED_AUTHORITY, release.availableObservedAt, anyChannel)
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

-- A peer advisory stored by an earlier build (NexusDB.updateAdvisory) is not
-- release evidence. It is moved once into a bounded diagnostic record and is
-- never read for a notice. Nothing else is touched: settings, preference,
-- dismissals and bundled notices stay.
local function Bounded(value)
    if type(value) == "string" then return #value <= 64 and value or value:sub(1, 64) end
    if type(value) == "number" then return value end
    return nil
end
local function QuarantineStoredAdvisory()
    NexusDB = NexusDB or {}
    local stored = NexusDB.updateAdvisory
    if stored == nil then return end
    local record = {reason="peer report is not release evidence"}
    if type(stored) == "table" then
        for _, slot in ipairs({"testBuild", "stableRelease"}) do
            local row = stored[slot]
            if type(row) == "table" then
                record[slot] = {version=Bounded(row.version), test=Bounded(row.test),
                    observedAt=Bounded(row.observedAt)}
            end
        end
    end
    -- One earlier record is kept (one level), as SanitizeStoredNotice does.
    local previous = NexusDB.updateAdvisoryQuarantine
    if type(previous) == "table" then
        previous.previousQuarantine = nil
        record.previousQuarantine = previous
    end
    NexusDB.updateAdvisoryQuarantine = record
    NexusDB.updateAdvisory = nil
end

local function Current()
    local bundled = BundledCandidate()
    if CanPersist() then
        SanitizeStoredNotice(bundled)
        QuarantineStoredAdvisory()
    end
    return bundled
end

local function Message(candidate)
    local installed = Installed()
    return (candidate.kind == "stable" and "New Nexus release available: "
        or "New Nexus test build available: ") .. candidate.display .. "."
        .. " You have " .. installed.display .. "."
        .. " Installation is manual: /nexus update shows the Releases page."
end

-- Seen targets, newest last, bounded. A target that was dismissed stays
-- dismissed when a later one is dismissed too.
local function Dismissed(key)
    NexusDB = NexusDB or {}
    local list = NexusDB.updateDismissed
    if type(list) == "string" then
        list = {list}
        if CanPersist() then NexusDB.updateDismissed = list end
    end
    if type(list) ~= "table" then return false end
    for i = math.max(1, #list - MAX_DISMISSED + 1), #list do
        if list[i] == key then return true end
    end
    return false
end

local function MaybeNotify(candidate)
    if type(candidate) ~= "table" or not Updates.IsEnabled() then return false end
    if candidate.authority ~= BUNDLED_AUTHORITY then return false end
    if notifiedTargets[candidate.key] or Dismissed(candidate.key) then return false end
    if sessionNotices >= MAX_SESSION_NOTICES then return false end
    if type(callbacks.notify) == "function" then
        local ok = pcall(callbacks.notify, candidate.display, Updates.ReleaseUrl(), Message(candidate))
        if not ok then return false end
    end
    notifiedTargets[candidate.key] = true
    sessionNotices = sessionNotices + 1
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
    sessionPersists = callbacks.persist ~= false
    notifiedTargets = {}
    sessionNotices = 0
    hintTarget, hintNotified, hintDismissed, hintNotices = nil, {}, {}, 0
    peerObservations, peerObservationOrder = {}, {}
    local settings = Settings()
    if settings.updateNotifications == nil then settings.updateNotifications = true end
    Updates.Reevaluate()
end

-- The one shape that can become a hint: a public test build, in the series
-- this installation is in, with a higher test number than this installation.
-- Everything else is excluded here rather than later: a plain version, an
-- internal or development announcement, a malformed or out-of-range test
-- identifier, an older or equal test, and any announcement received by an
-- installation that is not itself a public test package - a development
-- checkout and an internal package are not placed in a public series by a peer.
-- The commit suffix never participates: the comparison is the release series by
-- SemVer precedence, then the numeric test number.
local function HintCandidate(parsed, test)
    if not test or not PeerReportable(parsed, test) then return nil end
    local series = Series(parsed)
    if not series then return nil end
    local installed = Installed()
    if installed.channel ~= "public-test" then return nil end
    if type(installed.test) ~= "number" then return nil end
    if Nexus.Version.Compare(parsed, installed.version) ~= 0 then return nil end
    if test <= installed.test then return nil end
    return {version=series, test=test, display=Display(series, test),
        key=TargetKey(series, test), authority=HINT_AUTHORITY, verified=false}
end

local function HintMessage(hint)
    return "Another player's client reports a newer public test build: "
        .. hint.display .. "."
        .. " UNVERIFIED: Nexus did not check GitHub and cannot confirm that this"
        .. " build exists or is safe."
        .. " Check the Releases page yourself: /nexus update."
end

-- Announced at most once per target and at most twice per session. A repeated
-- report of the same target adds nothing and never revives a dismissal.
local function MaybeHintNotice()
    if not hintTarget or not Updates.IsEnabled() then return false end
    if Updates.Preference() == "stable" then return false end
    if hintNotified[hintTarget.key] or hintDismissed[hintTarget.key] then return false end
    if hintNotices >= MAX_HINT_NOTICES then return false end
    if type(callbacks.notify) == "function" then
        local ok = pcall(callbacks.notify, hintTarget.display, Updates.ReleaseUrl(),
            HintMessage(hintTarget))
        if not ok then return false end
    end
    hintNotified[hintTarget.key] = true
    hintNotices = hintNotices + 1
    return true
end

-- The hint as the status, the menu and the popup may show it, or nil. Read
-- through the current preference and the current installed identity, so a
-- stable-only user never receives a test hint and a hint that this
-- installation has caught up with disappears by itself.
function Updates.PublicTestHint()
    if not hintTarget or not Updates.IsEnabled() then return nil end
    if Updates.Preference() == "stable" then return nil end
    local installed = Installed()
    if installed.channel ~= "public-test" or type(installed.test) ~= "number"
        or hintTarget.test <= installed.test then return nil end
    return {version=hintTarget.version, test=hintTarget.test,
        display=hintTarget.display, key=hintTarget.key,
        reports=hintTarget.reports, observedAt=hintTarget.observedAt,
        source=hintTarget.source, authority=HINT_AUTHORITY, verified=false,
        dismissed=hintDismissed[hintTarget.key] == true}
end

-- Seen. No further chat line for this hint in this session. Nothing is saved:
-- a hint is session state, so a read-only or failed start-up gains no write
-- from dismissing one.
function Updates.DismissHint()
    local hint = Updates.PublicTestHint()
    if not hint then return false end
    hintDismissed[hint.key] = true
    hintNotified[hint.key] = true
    return true
end


-- One accepted Sync peer version. `version` is the parsed table or the wire
-- text that the inbound validator already accepted; `source` is the sender and
-- stays in the bounded session list only. A DIAGNOSTIC observation: nothing is
-- written to saved data, nothing is reevaluated and no notice is shown.
-- `reported` states whether the version has one of the two release shapes and
-- is newer than this installation ("test" or "stable"); that is not evidence
-- that such a release exists.
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
    local test = TestNumber(parsed)
    local reported = nil
    if PeerReportable(parsed, test) then
        local candidate = Candidate(parsed, test, "peer-observation", 0, true)
        reported = candidate and candidate.kind or nil
    end
    local observedAt = time and tonumber(time()) or 0
    peerObservations[source] = {
        version=parsed.normalized,
        observedAt=observedAt,
        source=source,
        authority="peer-observation",
        reported=reported,
    }
    -- Same intake, no extra traffic: the hint is derived from the observation
    -- this client already accepted. Only the highest reported test is kept,
    -- and a repeat of the one already held is counted, not re-announced.
    local hint = HintCandidate(parsed, test)
    if hint then
        if not hintTarget or hint.test > hintTarget.test then
            hint.reports, hint.observedAt, hint.source = 1, observedAt, source
            hintTarget = hint
            MaybeHintNotice()
        elseif hint.key == hintTarget.key then
            hintTarget.reports = math.min((hintTarget.reports or 1) + 1, 9999)
            MaybeHintNotice()
        end
    end
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
                reported=row.reported,
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
    local hint = Updates.PublicTestHint()
    local status = {
        installed=installed.display, installedLabel=installed.label,
        channel=installed.channel,
        channelLabel=CHANNEL_LABEL[installed.channel] or installed.channel,
        preference=Updates.Preference(), enabled=enabled,
        url=Updates.ReleaseUrl(), candidate=enabled and candidate or nil,
        hint=enabled and hint or nil,
    }
    local have = "Installed: " .. installed.display .. " (" .. status.channelLabel
        .. (installed.label ~= "source" and (", " .. installed.label) or "") .. ")."
    -- Only an installation that can be placed in a public test series can
    -- receive a hint at all, so only it is told that none arrived.
    local listens = enabled and Updates.Preference() ~= "stable"
        and installed.channel == "public-test" and type(installed.test) == "number"
    if not enabled then
        status.state, status.menu = "disabled", "Update notices off - open Releases page"
        status.detail = have .. " Update notices are off."
    elseif not candidate and hint then
        -- A hint is never trusted release information, so it never becomes the
        -- candidate, never hides bundled evidence and says what it is.
        status.state = "hint"
        status.menu = "Newer public test reported: " .. hint.display .. " (unverified)"
        status.detail = have
            .. LINE .. "Newer public test reported: " .. hint.display .. "."
            .. LINE .. "Reported by another client; not checked against GitHub."
            .. LINE .. "Check the Better Nexus Releases page before updating."
    elseif not candidate then
        status.state, status.menu = "unknown", "Update status unknown - open Releases page"
        -- Bundled evidence that only the stable-only preference hides is named.
        local hidden = Updates.Preference() == "stable" and BundledCandidate(true) or nil
        status.detail = have .. (hidden
            and (" A newer test build (" .. hidden.display .. ") is not announced because notices are set to stable releases only.")
            or " This client has no release information about a newer build.")
            .. (listens and " No newer public-test announcement was received." or "")
            .. " Nexus does not check GitHub, and versions stated by other players' clients are not release information."
            .. " That is not proof that this build is the latest: check the Releases page."
    else
        status.state = "available"
        status.menu = "Update available: " .. candidate.display
        status.detail = have .. " " .. (candidate.kind == "stable" and "New Nexus release available: "
            or "New Nexus test build available: ") .. candidate.display .. "."
        -- Trusted information is never replaced or hidden by a hint; a hint
        -- that names something else is added after it, still unverified.
        if hint and hint.key ~= candidate.key then
            status.detail = status.detail
                .. LINE .. "Another client also reports " .. hint.display
                .. " (unverified, not checked against GitHub)."
        end
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
    notifiedTargets[candidate.key] = true
    -- Without a durable write the dismissal holds for this session only. The
    -- saved list is never replaced by a partial copy of itself, so a dismissal
    -- saved by an older client in the single-entry form is not dropped.
    if not CanPersist() then return true end
    if not Dismissed(candidate.key) then
        local list = NexusDB.updateDismissed
        -- Dismissed() has already converted a saved single-entry string when
        -- the owner allows it. The branch stays as the local guarantee that
        -- the older entry is carried over rather than replaced.
        if type(list) == "string" then list = {list} end
        if type(list) ~= "table" then list = {} end
        list[#list + 1] = candidate.key
        while #list > MAX_DISMISSED do table.remove(list, 1) end
        NexusDB.updateDismissed = list
    end
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
