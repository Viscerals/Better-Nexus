-- Keyed noncritical scheduler. Critical automation/FSM work must not be
-- registered here; Main keeps that work on its direct 0.2-second tick.

Nexus = Nexus or {}
local Scheduler = {}
Nexus.Scheduler = Scheduler

local tasks = {}
local generation = 0
local frame
local MAX_CALLBACKS_PER_TICK = 32
local taskCount = 0
local nextDue
local deadlineDirty = false
local ready = {}
local readyCount = 0
local tickDepth = 0

local function Finite(value)
    return type(value) == "number" and value == value
        and value < math.huge and value > -math.huge
end

local function Clock()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        value = ok and tonumber(value) or nil
        if Finite(value) then return value end
    end
    return 0
end

local function ValidKey(key)
    return type(key) == "string" and key ~= "" and #key <= 128
end

local function RecordError(key, err)
    local errors = Nexus and Nexus.Errors
    if errors and type(errors.Record) == "function" then
        pcall(errors.Record, "Scheduler." .. tostring(key), err)
    end
end

local function ReadyBefore(left, right)
    if left.due ~= right.due then return left.due < right.due end
    return left.key < right.key
end

-- Retain only the earliest callback-sized window. The task tables themselves
-- are the immutable generation snapshots used by the old per-Tick due rows;
-- scheduling the same key replaces the table, so the generation guard below
-- still rejects a superseded ready entry. The array grows to at most the
-- callback cap once, then is cleared and reused.
local function InsertReady(task)
    local full = readyCount >= MAX_CALLBACKS_PER_TICK
    if full and not ReadyBefore(task, ready[readyCount]) then return true end
    if not full then readyCount = readyCount + 1 end
    local index = readyCount
    while index > 1 and ReadyBefore(task, ready[index - 1]) do
        ready[index] = ready[index - 1]
        index = index - 1
    end
    ready[index] = task
    return full
end

local function CollectReady(now, snapshotGeneration)
    for index = 1, readyCount do ready[index] = nil end
    readyCount = 0
    local futureDue, overflowDue
    for _, task in pairs(tasks) do
        if task.generation <= snapshotGeneration and task.due <= now then
            if InsertReady(task) then overflowDue = true end
        elseif futureDue == nil or task.due < futureDue then
            futureDue = task.due
        end
    end
    nextDue, deadlineDirty = futureDue, false
    return overflowDue == true
end

local function RunReady(snapshot, now)
    local task = snapshot and tasks[snapshot.key]
    if not (task and task.generation == snapshot.generation
        and task.due <= now) then return false end
    local oldDue = task.due
    if task.kind == "after" then
        tasks[snapshot.key] = nil
        taskCount = taskCount - 1
        if nextDue == oldDue and taskCount > 0 then deadlineDirty = true end
    else
        local skipped = math.floor((now - task.due) / task.interval) + 1
        task.due = task.due + skipped * task.interval
        if nextDue == oldDue then
            -- Another callback may have scheduled a deferred generation at
            -- this exact old deadline. Preserve it and force one recompute;
            -- replacing it with the repeating cadence would hide that work.
            deadlineDirty = true
        elseif nextDue == nil or task.due < nextDue then
            nextDue = task.due
        end
    end
    local ok, err = pcall(task.callback, snapshot.key, now)
    if not ok then RecordError(snapshot.key, err) end
    return true
end

-- The normal path owns the single reusable ready buffer. A callback may still
-- invoke Tick recursively; the legacy local-snapshot implementation consumed
-- remaining due work in that nested call. Preserve that rare behavior with a
-- bounded selection scan so the nested call cannot overwrite the outer buffer.
local function TickReentrant(now)
    local snapshotGeneration = generation
    local ran = 0
    while ran < MAX_CALLBACKS_PER_TICK do
        local selected
        for _, task in pairs(tasks) do
            if task.generation <= snapshotGeneration and task.due <= now
                and (not selected or ReadyBefore(task, selected)) then
                selected = task
            end
        end
        if not selected or not RunReady(selected, now) then break end
        ran = ran + 1
    end
    if taskCount == 0 then
        nextDue, deadlineDirty = nil, false
    else
        deadlineDirty = true
    end
    return ran
end

local function Schedule(kind, key, delay, callback)
    delay = tonumber(delay)
    if not ValidKey(key) or not Finite(delay)
        or delay < 0 or type(callback) ~= "function" then
        return false, "valid key, delay, and callback required"
    end
    if kind == "every" and delay <= 0 then
        return false, "repeating interval must be positive"
    end
    local previous = tasks[key]
    local previousWasNext = previous ~= nil and nextDue == previous.due
    local due = Clock() + delay
    generation = generation + 1
    tasks[key] = {
        key=key, kind=kind, callback=callback, generation=generation,
        due=due, interval=kind == "every" and delay or nil,
    }
    if previous == nil then taskCount = taskCount + 1 end
    if previousWasNext and due > previous.due then deadlineDirty = true end
    if nextDue == nil or due < nextDue then nextDue = due end
    return true
end

function Scheduler.After(key, delay, callback)
    return Schedule("after", key, delay, callback)
end

function Scheduler.Every(key, interval, callback)
    return Schedule("every", key, interval, callback)
end

function Scheduler.Cancel(key)
    if not ValidKey(key) or tasks[key] == nil then return false end
    local cancelled = tasks[key]
    tasks[key] = nil
    taskCount = taskCount - 1
    if taskCount == 0 then
        nextDue, deadlineDirty = nil, false
    elseif nextDue == cancelled.due then
        deadlineDirty = true
    end
    return true
end

function Scheduler.Tick(now)
    if taskCount == 0 then return 0 end
    now = tonumber(now) or Clock()
    if not Finite(now) then return 0 end
    if tickDepth > 0 then return TickReentrant(now) end
    if not deadlineDirty and nextDue ~= nil and now < nextDue then return 0 end

    tickDepth = tickDepth + 1
    local snapshotGeneration = generation
    local ran, pendingSnapshot = 0, false
    while ran < MAX_CALLBACKS_PER_TICK do
        local overflowDue = CollectReady(now, snapshotGeneration)
        if readyCount == 0 then break end
        local batchCount = readyCount
        for index = 1, batchCount do
            local snapshot = ready[index]
            ready[index] = nil
            if ran < MAX_CALLBACKS_PER_TICK then
                if RunReady(snapshot, now) then
                    ran = ran + 1
                end
            else
                pendingSnapshot = true
            end
        end
        readyCount = 0
        if ran >= MAX_CALLBACKS_PER_TICK then
            pendingSnapshot = pendingSnapshot or overflowDue
            break
        end
        if not overflowDue then break end
    end
    if taskCount == 0 then
        nextDue, deadlineDirty = nil, false
    elseif pendingSnapshot and (nextDue == nil or now < nextDue) then
        nextDue = now
    end
    tickDepth = tickDepth - 1
    return ran
end

function Scheduler.Pending(key)
    if key ~= nil then
        local task = tasks[key]
        if not task then return nil end
        return {key=task.key,kind=task.kind,due=task.due,interval=task.interval}
    end
    local out = {}
    for taskKey, task in pairs(tasks) do
        out[#out + 1] = {
            key=taskKey,kind=task.kind,due=task.due,interval=task.interval,
        }
    end
    table.sort(out, function(left, right)
        if left.due ~= right.due then return left.due < right.due end
        return left.key < right.key
    end)
    return out
end

function Scheduler.Init()
    if frame then return frame end
    if type(CreateFrame) ~= "function" then return nil end
    local candidate = CreateFrame("Frame")
    candidate:SetScript("OnUpdate", function()
        Scheduler.Tick()
    end)
    -- Publish initialized state only after the frame owns its update handler.
    -- A transient frame/API failure can then be recorded by Main and retried.
    frame = candidate
    return frame
end

function Scheduler.IsInitialized()
    return frame ~= nil
end

function Scheduler.MaxCallbacksPerTick()
    return MAX_CALLBACKS_PER_TICK
end
