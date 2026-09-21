-- Deterministic in-session revisions for represented data. Status text,
-- timers, visibility, and diagnostic logs deliberately do not use this bus.

Nexus = Nexus or {}
local Revisions = {}
Nexus.Revisions = Revisions

Revisions.BUILD_LIBRARY_CHANGED = "BUILD_LIBRARY_CHANGED"
Revisions.DPS_CHANGED = "DPS_CHANGED"
Revisions.SYNC_CHANGED = "SYNC_CHANGED"
Revisions.CATALOG_CHANGED = "CATALOG_CHANGED"

local EVENT_ORDER = {
    Revisions.BUILD_LIBRARY_CHANGED,
    Revisions.DPS_CHANGED,
    Revisions.SYNC_CHANGED,
    Revisions.CATALOG_CHANGED,
}
local counters, subscribers, nextSubscriberId = {}, {}, 0
for _, event in ipairs(EVENT_ORDER) do
    counters[event] = 0
    subscribers[event] = {}
end

local function ValidEvent(event)
    return type(event) == "string" and counters[event] ~= nil
end

local function RecordSubscriberError(event, err)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.Record) == "function" then
        pcall(errors.Record, "Revisions." .. tostring(event), err)
    end
end

function Revisions.Get(event)
    return ValidEvent(event) and counters[event] or nil
end

function Revisions.Snapshot()
    local out = {}
    for _, event in ipairs(EVENT_ORDER) do out[event] = counters[event] end
    return out
end

function Revisions.Subscribe(event, callback)
    if not ValidEvent(event) or type(callback) ~= "function" then
        return nil, "valid event and callback required"
    end
    nextSubscriberId = nextSubscriberId + 1
    local entry = { id=nextSubscriberId, callback=callback, active=true }
    local list = subscribers[event]
    list[#list + 1] = entry
    return function()
        if not entry.active then return false end
        entry.active = false
        return true
    end
end

function Revisions.Advance(event, detail)
    if not ValidEvent(event) then return nil, "unknown revision event" end
    counters[event] = counters[event] + 1
    local revision = counters[event]
    local list = subscribers[event]
    local lastAtStart = #list
    for i = 1, lastAtStart do
        local entry = list[i]
        if entry and entry.active then
            local ok, err = pcall(entry.callback, event, revision, detail)
            if not ok then RecordSubscriberError(event, err) end
        end
    end
    return revision
end

function Revisions.Events()
    local out = {}
    for i, event in ipairs(EVENT_ORDER) do out[i] = event end
    return out
end
