-- Nexus: core/SupportIncidents.lua
-- Session-only retention of EXPECTED refusals: a catalog validation refusal or
-- a deferred capture is a business-rule outcome, not a Lua exception, so it
-- never reaches Errors.History() and a support report built from errors alone
-- shows "no errors recorded" while the player is looking at a failure message.
--
-- This owner keeps a small bounded list of those incidents with the facts that
-- were true AT THE FAILING BOUNDARY. It stores plain scalars and short lists
-- only: no frames, no live records, no functions, no userdata, no gameplay
-- state, and nothing is written to saved variables from here. It performs no
-- catalog scan, registers no event, and is only called by the owners that
-- already hold the failure.
--
-- An unobserved field is absent, and the report prints "not retained" for it.
-- Nothing here reconstructs a past candidate from later data.

Nexus = Nexus or {}
local M = {}
Nexus.SupportIncidents = M

-- Bounds. A support report is one incident plus context, so the list is small
-- on purpose: the newest incidents are the ones a player is reporting.
local MAX_INCIDENTS = 20
local MAX_TUPLES = 24
local MAX_TEXT = 240

local incidents = {}
local sequence = 0

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" then return value end
    end
    return nil
end

local function text(value)
    if value == nil then return nil end
    -- tostring runs a caller-supplied __tostring, which could raise or return
    -- anything. A retained field is never allowed to depend on that.
    local ok, converted = pcall(tostring, value)
    if not ok or type(converted) ~= "string" then
        converted = "unreadable " .. type(value)
    end
    return (converted:gsub("%c", " ")):sub(1, MAX_TEXT)
end

local function count(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge
        or value == -math.huge then return nil end
    return math.floor(value)
end

-- Copy only the scalar fields of a counts table, so a caller cannot hand a
-- live record or a table with a metatable into the retained incident.
local function counts(value)
    if type(value) ~= "table" then return nil end
    local out = {ordinary=count(value.ordinary), locked=count(value.locked),
        total=count(value.total)}
    if out.ordinary == nil and out.locked == nil and out.total == nil then
        return nil
    end
    return out
end

-- Affected tuples are retained ONLY when the caller already has them at the
-- failing boundary, and only up to the per-incident limit. There is no lookup
-- and no scan here; a longer list is truncated and says so.
local function tuples(value)
    if type(value) ~= "table" or #value == 0 then return nil, nil end
    local out, omitted = {}, 0
    for index = 1, #value do
        local tuple = value[index]
        if type(tuple) == "table" then
            if #out < MAX_TUPLES then
                out[#out + 1] = {
                    spellId = count(tuple.spellId or tuple.id),
                    quality = count(tuple.quality),
                    stacks = count(tuple.stacks or tuple.count) or 1,
                    locked = tuple.locked == true or nil,
                }
            else
                omitted = omitted + 1
            end
        end
    end
    if #out == 0 then return nil, nil end
    return out, omitted > 0 and omitted or nil
end

local MAX_READINESS_KEYS = 12
local function generations(value)
    if type(value) ~= "table" then return nil end
    -- Bounded like everything else here: a caller cannot turn one incident
    -- into a large retained table by handing over a big map.
    local keys = {}
    for key in pairs(value) do
        if type(key) == "string" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local out, any, omitted = {}, false, 0
    for index = 1, #keys do
        local key = keys[index]
        local entry = value[key]
        if index > MAX_READINESS_KEYS then
            omitted = omitted + 1
        else
            -- Keys are bounded as well as values: a long key is as much
            -- retained text as a long value.
            local name = key:sub(1, 48)
            if type(entry) == "number" then out[name], any = count(entry), true
            elseif type(entry) == "boolean" then out[name], any = entry, true
            elseif type(entry) == "string" then out[name], any = text(entry), true
            end
        end
    end
    if omitted > 0 then
        out.omittedKeys, any = omitted, true
    end
    return any and out or nil
end

-- Two occurrences are the SAME incident only when the same producer refused
-- the same condition for the same operation with the same counts. Different
-- failures are never merged by their reason code alone.
local function sameIncident(a, b)
    if a.kind ~= b.kind or a.reason ~= b.reason
        or a.producer ~= b.producer or a.operation ~= b.operation
        or a.origin ~= b.origin or a.ticket ~= b.ticket
        -- A deferral on one encounter is not a deferral on another, and two
        -- refusals with different explanations are two incidents even when
        -- their copy counts happen to match.
        or a.category ~= b.category or a.detail ~= b.detail
        or a.build ~= b.build or a.representation ~= b.representation
        or a.scope ~= b.scope then return false end
    local ac, bc = a.counts, b.counts
    if (ac == nil) ~= (bc == nil) then return false end
    if ac and bc then
        if ac.ordinary ~= bc.ordinary or ac.locked ~= bc.locked
            or ac.total ~= bc.total then return false end
    end
    return true
end

-- fields (all optional except kind and reason):
--   kind        "catalog-refusal" | "capture-deferred" | another owner's kind
--   reason      the refusal code as the owner produced it
--   producer    the operation label the owner already uses
--   origin      "local" | "received" | "unknown"
--   operation   the owner's operation label; ticket: its identity when it has one
--   build       source build label; category: the owner's own category
--   representation "inline" | "referenced" | "unknown"
--   counts/limits  {ordinary, locked, total}
--   readiness   scalar map of capture-time source generations/readiness
--   affected    tuples already available at the boundary
--   committed   true/false: whether the write this incident describes committed
--   scope       what the outcome covers, in the owner's own words
function M.Record(kind, fields)
    if type(kind) ~= "string" or kind == "" then return nil end
    fields = type(fields) == "table" and fields or {}
    local stamp = now()
    local affected, omitted = tuples(fields.affected)
    -- false is a real answer here ("this write did not commit"), so it cannot
    -- be folded into an `or` chain, which would turn it back into nil.
    local committed = nil
    if fields.committed == true then committed = true
    elseif fields.committed == false then committed = false end
    local candidate = {
        kind = kind,
        reason = text(fields.reason) or "unspecified",
        producer = text(fields.producer),
        origin = text(fields.origin) or "unknown",
        operation = text(fields.operation),
        ticket = text(fields.ticket),
        build = text(fields.build),
        category = text(fields.category),
        representation = text(fields.representation) or "unknown",
        counts = counts(fields.counts),
        limits = counts(fields.limits),
        readiness = generations(fields.readiness),
        affected = affected,
        affectedOmitted = omitted,
        committed = committed,
        scope = text(fields.scope),
        detail = text(fields.detail),
        occurrences = 1,
        firstAt = stamp, lastAt = stamp,
    }
    for index = #incidents, 1, -1 do
        local existing = incidents[index]
        if sameIncident(existing, candidate) then
            -- The same condition repeating is one incident with a count, not
            -- a new record on every poll.
            existing.occurrences = existing.occurrences + 1
            existing.lastAt = stamp or existing.lastAt
            if existing.affected == nil and candidate.affected then
                existing.affected = candidate.affected
                existing.affectedOmitted = candidate.affectedOmitted
            end
            return existing
        end
    end
    sequence = sequence + 1
    candidate.id = sequence
    incidents[#incidents + 1] = candidate
    while #incidents > MAX_INCIDENTS do table.remove(incidents, 1) end
    return candidate
end

local function copyIncident(incident)
    local out = {}
    for key, value in pairs(incident) do
        if type(value) == "table" then
            local inner = {}
            for k, v in pairs(value) do
                if type(v) == "table" then
                    local row = {}
                    for rk, rv in pairs(v) do row[rk] = rv end
                    inner[k] = row
                else inner[k] = v end
            end
            out[key] = inner
        else out[key] = value end
    end
    return out
end

-- Newest last, like the log pages: a report quotes the selected incident and
-- the ones around it in the order they happened.
function M.History(limit)
    limit = count(limit)
    local first = 1
    if limit and limit > 0 and #incidents > limit then
        first = #incidents - limit + 1
    end
    local out = {}
    for index = first, #incidents do
        out[#out + 1] = copyIncident(incidents[index])
    end
    return out
end

function M.Latest()
    local incident = incidents[#incidents]
    return incident and copyIncident(incident) or nil
end

function M.Count() return #incidents end

function M.Clear()
    incidents = {}
    return true
end

M.MAX_INCIDENTS = MAX_INCIDENTS
M.MAX_TUPLES = MAX_TUPLES

return M
