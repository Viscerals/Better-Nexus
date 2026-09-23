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

-- A bounded 32-bit sum over at most the first MAX_SUMMED bytes. It exists so
-- that a value which had to be shortened still describes itself: without it
-- two readings that differ only beyond the retained length are retained as the
-- same text, and identity then merges two failures that were not the same.
-- A value longer than MAX_SUMMED that differs only after that point still
-- collides; the length is part of the marker, so that needs both.
local MAX_SUMMED = 4096
local function sum32(value)
    local a, b = 1, 0
    for index = 1, math.min(#value, MAX_SUMMED) do
        a = (a + value:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%04x%04x", b, a)
end

local function text(value)
    if value == nil then return nil end
    -- tostring runs a caller-supplied __tostring, which could raise or return
    -- anything. A retained field is never allowed to depend on that.
    local ok, converted = pcall(tostring, value)
    if not ok or type(converted) ~= "string" then
        converted = "unreadable " .. type(value)
    end
    -- A control character is written as the byte it is rather than replaced by
    -- a space: a report line cannot carry a raw newline, and mapping every
    -- control character onto one space made two different values identical.
    converted = (converted:gsub("%c", function(char)
        return string.format("\\%03d", char:byte())
    end))
    if #converted > MAX_TEXT then
        -- The marker opens with a RAW control byte. Every control character a
        -- caller supplies was just escaped above, so no value this function
        -- returns can carry one - which means a caller cannot hand over the
        -- retained form of a longer value and be merged with it.
        local marker = string.char(1) .. "(" .. #converted .. "B#"
            .. sum32(converted) .. ")"
        converted = converted:sub(1, math.max(1, MAX_TEXT - #marker)) .. marker
    end
    return converted
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
        -- Recorded on the COPY, so a caller's own map is never modified and a
        -- caller key of this name cannot be overwritten.
        out["(omitted keys)"], any = omitted, true
    end
    return any and out or nil
end

-- Two occurrences are the SAME incident only when the same producer refused
-- the same condition for the same operation with the same counts. Different
-- failures are never merged by their reason code alone.
-- A short, order-stable description of a retained sub-table, used only to tell
-- two incidents apart. It is never shown to anyone.
-- Every part carries its own byte length, so no separator, brace or equals
-- sign inside a retained value can make two different tables describe
-- themselves identically. A readiness value really can contain them: it is
-- text the failing boundary supplied.
local function piece(key, entry)
    local k, v = tostring(key), tostring(entry)
    -- The TYPE is part of the value: a readiness field read as the number 1 is
    -- not the same reading as the text "1", and tostring() alone erases that.
    return #k .. ":" .. k .. "=" .. type(entry):sub(1, 1) .. #v .. ":" .. v
end
local function signature(value)
    if type(value) ~= "table" then return "-" end
    local parts = {}
    for key, entry in pairs(value) do
        if type(entry) == "table" then
            local row = {}
            for k, v in pairs(entry) do row[#row + 1] = piece(k, v) end
            table.sort(row)
            local joined = table.concat(row, ",")
            parts[#parts + 1] = #tostring(key) .. ":" .. tostring(key)
                .. "{" .. #joined .. ":" .. joined .. "}"
        else
            parts[#parts + 1] = piece(key, entry)
        end
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

local function sameCounts(a, b)
    if (a == nil) ~= (b == nil) then return false end
    if a and b then
        if a.ordinary ~= b.ordinary or a.locked ~= b.locked
            or a.total ~= b.total then return false end
    end
    return true
end

-- Only a genuine repeat is one incident with a count. A write that did NOT
-- commit is never folded into one that did, a deferral on one encounter is not
-- a deferral on another, and two explanations, limits, source readings or
-- affected lists that differ are two incidents.
local function sameIncident(a, b)
    if a.kind ~= b.kind or a.reason ~= b.reason
        or a.producer ~= b.producer or a.operation ~= b.operation
        or a.origin ~= b.origin or a.ticket ~= b.ticket
        or a.category ~= b.category or a.detail ~= b.detail
        or a.build ~= b.build or a.representation ~= b.representation
        or a.scope ~= b.scope or a.committed ~= b.committed then return false end
    if not sameCounts(a.counts, b.counts) then return false end
    if not sameCounts(a.limits, b.limits) then return false end
    if signature(a.readiness) ~= signature(b.readiness) then return false end
    if signature(a.affected) ~= signature(b.affected) then return false end
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
