-- Nexus: the one outbound permission decision for a saved Sync mode.
--
-- The player's own explicit choice (Build Library "Sync mode...", saved as an
-- optional account-level preference) comes first. Without one, accepted saved
-- formats 3-5 (Good Enough Nexus and the earlier Better Nexus test line) can
-- carry settings.syncMode "off" or "manual" (core/Store.lua
-- SavedFormat.SyncMode). Every other profile is "automatic": this module then
-- allows everything and nothing changes.
--
--   off     no Nexus-generated message: requests, responses, Share, handshakes
--           and the diagnostic probe whisper are all refused.
--   manual  only what the user explicitly started: a Sync Now (slash or either
--           button) for its own fixed lifetime, an explicitly confirmed Share
--           (or Share of an edited record), the answers to peers fetching that
--           shared record until the Share's own expiry, and the probe whisper.
--           Never the queue as a whole, never unrelated backlog.
--
-- The same decision is asked where work is created (queue admission) and at
-- the actual submission (SyncWire CanDispatch, SendPacket, PumpHandshake, the
-- probe whisper). It is distinct from combat waits, bandwidth pressure, a full
-- queue and a transport fault. It keeps no clock of its own: every grant ends
-- at a deadline the owning operation already had.
Nexus = Nexus or {}
local P = {}
Nexus.SyncModePolicy = P

local OFF_TEXT = "Sync is Off: your saved Sync mode is Off, so Nexus sends nothing. Local records are kept."
local MANUAL_TEXT = "Sync is Manual: your saved Sync mode is Manual, so Nexus sends only what you start (Sync Now or Share)."
local MAX_SHARE_GRANTS = 32
local shareGrants, shareGrantCount = {}, 0
local manualGrantSource, localName

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

function P.Mode()
    local internals = Nexus.MainInternals
    local read = type(internals) == "table" and internals.SavedSyncModeV1 or nil
    if type(read) ~= "function" then return "automatic" end
    local ok, mode = pcall(read)
    if ok and (mode == "off" or mode == "manual") then return mode end
    return "automatic"
end

function P.Text(mode)
    mode = mode or P.Mode()
    if mode == "off" then return OFF_TEXT end
    if mode == "manual" then return MANUAL_TEXT end
    return nil
end

local CHOICES = {automatic=true, manual=true, off=true}

-- Read-only status of the explicit choice (core/Store.lua
-- SavedFormat.ChoiceStatus): effective, explicit, inherited, writable,
-- reason and the token a draft carries. nil when the Store seam is absent.
function P.Choice()
    local internals = Nexus.MainInternals
    local read = type(internals) == "table" and internals.SyncModeChoiceV1 or nil
    if type(read) ~= "function" then return nil end
    local ok, status = pcall(read)
    return ok and type(status) == "table" and status or nil
end

-- Apply one explicit choice from a draft opened with `token`. The only new
-- caller of the counted-private Store entry UpdateSettingsV1. It validates
-- first, refuses a stale draft or unwritable storage with the reason, does
-- nothing when that exact explicit choice is already stored, and otherwise
-- writes it and reads it back. It starts, flushes, pumps, resets and extends
-- nothing: later traffic follows the new mode through the existing admission
-- and final-submit checks above, and already sent messages stay sent.
-- Returns ok, result ("saved" | "unchanged" | refusal reason), status after.
function P.ApplyChoice(mode, token)
    if not CHOICES[mode] then return false, "invalid-value", P.Choice() end
    local status = P.Choice()
    if not status then return false, "unavailable", nil end
    if type(token) == "table" and type(status.token) == "table"
        and (token.db ~= status.token.db or token.settings ~= status.token.settings) then
        return false, "stale", status
    end
    if not status.writable then return false, status.reason or "unavailable", status end
    if status.explicit == mode then return true, "unchanged", status end
    local internals = Nexus.MainInternals
    local owner = type(internals) == "table" and internals.StoreAuthorityOwner or nil
    if type(owner) ~= "table" or type(owner.UpdateSettingsV1) ~= "function" then
        return false, "unavailable", status
    end
    local called, result, why, detail = pcall(owner.UpdateSettingsV1, status.key, mode)
    if not called or type(result) ~= "table" or result.mode ~= "durable" then
        return false, called and (detail or why or "not saved") or "not saved", P.Choice()
    end
    local after = P.Choice()
    if not after or after.explicit ~= mode then return false, "not read back", after end
    return true, "saved", after
end

-- Sync binds the active manual Sync Now grant (a string or nil) and the local
-- player name. Both are read at decision time; nothing is cached here.
function P.Bind(grantSource, nameSource)
    manualGrantSource, localName = grantSource, nameSource
end

local function ActiveManualGrant()
    if type(manualGrantSource) ~= "function" then return nil end
    local ok, grant = pcall(manualGrantSource)
    return ok and type(grant) == "string" and grant or nil
end
P.ActiveManualGrant = ActiveManualGrant

-- An explicit Share was admitted. Peers fetch its Echo list with a follow-up
-- request; answering those for this build is part of the Share until the
-- Share's own expiry. The deadline is never extended by a later event.
function P.NoteExplicitShare(buildId, expiresAt)
    buildId, expiresAt = tostring(buildId or ""), tonumber(expiresAt)
    if buildId == "" or not expiresAt then return end
    if shareGrants[buildId] == nil then
        if shareGrantCount >= MAX_SHARE_GRANTS then
            local oldest, stamp
            for key, deadline in pairs(shareGrants) do
                if not stamp or deadline < stamp then oldest, stamp = key, deadline end
            end
            if oldest then shareGrants[oldest] = nil; shareGrantCount = shareGrantCount - 1 end
        end
        shareGrantCount = shareGrantCount + 1
    end
    -- A newer explicit Share of the same record has its own deadline.
    shareGrants[buildId] = expiresAt
end

local function ShareFollowUp(metadata)
    local buildId = metadata.buildId and tostring(metadata.buildId) or nil
    local deadline = buildId and shareGrants[buildId]
    if not deadline then return false end
    if Now() >= deadline then
        shareGrants[buildId] = nil; shareGrantCount = shareGrantCount - 1
        return false
    end
    local requester = metadata.requester
    local me = type(localName) == "function" and localName() or nil
    return type(requester) == "string" and requester ~= "" and requester ~= me
end

-- kind: "packet" (with its queue metadata), "handshake", "whisper".
-- Returns true, or false and the factual reason.
function P.Allows(kind, metadata)
    local mode = P.Mode()
    if mode == "automatic" then return true end
    if mode == "off" then return false, OFF_TEXT end
    if kind == "whisper" then return true end
    if kind ~= "packet" or type(metadata) ~= "table" then return false, MANUAL_TEXT end
    if metadata.operationKind == "share" and metadata.operationKey ~= nil then
        return true
    end
    local grant = metadata.manualGrant
    if grant ~= nil and grant == ActiveManualGrant() then return true end
    if ShareFollowUp(metadata) then return true end
    return false, MANUAL_TEXT
end

-- True when a refusal reason came from this policy (not combat, bandwidth,
-- a full queue or a fault).
function P.IsModeReason(reason)
    return reason == OFF_TEXT or reason == MANUAL_TEXT
end

function P.Reset()
    shareGrants, shareGrantCount = {}, 0
end
