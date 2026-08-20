-- Durable diagnostic histories backed by the established NexusDB arrays.
--
-- These accessors retain observations only. They deliberately know nothing
-- about automation, represented-data revisions, or Sync queues. Existing
-- array names and record fields remain compatible with old saves and exports.

Nexus = Nexus or {}

local Logs = {}
Nexus.DiagnosticLogs = Logs

local DEFINITIONS = {
    decision = {key="decisionLog", cap=200},
    runAudit = {key="runAudit", cap=240},
    autoLock = {key="autoLockLog", cap=150},
    uiProbe = {key="uiProbeLog", cap=120},
}
local ORDER = {"decision", "runAudit", "autoLock", "uiProbe"}
local META_SCHEMA = 1
local STORAGE_SCHEMA = 1
local FUTURE_STORAGE_REASON =
    "future diagnostic history storage schema is read-only"
local MAX_COPY_DEPTH = 16
local cachedDB = nil
local cachedHistories = {}
local cachedStates = {}

for _, definition in pairs(DEFINITIONS) do
    definition.trimAt = definition.cap
        + math.max(1, math.floor(definition.cap / 4))
end

local function SafeError(value)
    local safe = Nexus.DiagnosticHistory and Nexus.DiagnosticHistory.SafeText
    if type(safe) == "function" then return safe(value, 512) end
    local ok, text = pcall(tostring, value)
    return ok and tostring(text or "") or "unprintable diagnostic error"
end

local function IsArrayIndex(key)
    return type(key) == "number" and key >= 1 and key == math.floor(key)
end

local function CopyValue(value, seen, depth)
    local kind = type(value)
    if kind == "nil" or kind == "string" or kind == "number"
        or kind == "boolean" then
        return value
    end
    if kind ~= "table" then return SafeError(value) end
    if seen[value] then return "<cycle>" end
    if depth >= MAX_COPY_DEPTH then return "<depth-limit>" end

    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local keyKind = type(key)
        local copiedKey = (keyKind == "string" or keyKind == "number"
            or keyKind == "boolean") and key or SafeError(key)
        if copy[copiedKey] == nil then
            copy[copiedKey] = CopyValue(child, seen, depth + 1)
        end
    end
    seen[value] = nil
    return copy
end

local function DefensiveCopy(value)
    local ok, copy = pcall(CopyValue, value, {}, 0)
    if not ok then return nil, SafeError(copy) end
    return copy
end

local function CurrentDB(database)
    if type(database) == "table" then return database end
    if type(NexusDB) ~= "table" then NexusDB = {} end
    return NexusDB
end

local function Number(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge then return 0 end
    return number
end

local function Metadata(database)
    local meta = database.diagnosticMeta
    if type(meta) ~= "table" then
        meta = {}
        database.diagnosticMeta = meta
    end
    if meta.schemaVersion == nil then meta.schemaVersion = META_SCHEMA end
    if type(meta.histories) ~= "table" then meta.histories = {} end
    return meta
end

local function HistoryMeta(database, name, definition)
    local histories = Metadata(database).histories
    local meta = histories[name]
    if type(meta) ~= "table" then
        meta = {}
        histories[name] = meta
    end
    meta.key = definition.key
    meta.cap = definition.cap
    return meta
end

local function ExistingHistoryMeta(database, name)
    local envelope = rawget(database, "diagnosticMeta")
    local histories = type(envelope) == "table"
        and rawget(envelope, "histories") or nil
    local meta = type(histories) == "table" and rawget(histories, name) or nil
    return type(meta) == "table" and meta or nil
end

local function FutureHistoryMeta(database, name)
    local meta = ExistingHistoryMeta(database, name)
    local storageSchema = meta and tonumber(rawget(meta, "storageSchema")) or nil
    if storageSchema and storageSchema > STORAGE_SCHEMA then
        return meta, storageSchema
    end
    return nil, nil
end

local function Bump(meta, key, amount)
    meta[key] = Number(meta[key]) + (tonumber(amount) or 1)
end

local function BindCache(database)
    if cachedDB ~= database then
        cachedDB, cachedHistories, cachedStates = database, {}, {}
    end
end

local function CopyExtensions(source, target)
    for key, value in pairs(source) do
        if not IsArrayIndex(key) then target[key] = value end
    end
end

local function WriteStorageMeta(meta, definition, state)
    meta.storageSchema = STORAGE_SCHEMA
    meta.storageHead = state.head
    meta.storageTail = state.tail
    meta.storageRetained = state.retained
    meta.trimAt = definition.trimAt
    meta.retained = state.retained
end

local function StoredState(meta, definition, source)
    if tonumber(meta.storageSchema) ~= STORAGE_SCHEMA then return nil end
    local head = tonumber(meta.storageHead)
    local tail = tonumber(meta.storageTail)
    local retained = tonumber(meta.storageRetained)
    if not head or not tail or not retained
        or head ~= math.floor(head) or tail ~= math.floor(tail)
        or retained ~= math.floor(retained) or head < 1 or tail < 0
        or retained < 0 or retained > definition.cap
        or tail >= definition.trimAt then return nil end
    if retained == 0 then
        if head ~= 1 or tail ~= 0 then return nil end
    elseif tail < head or tail - head + 1 ~= retained then
        return nil
    end

    local numeric = 0
    for key, value in pairs(source) do
        if IsArrayIndex(key) then
            if key < head or key > tail or type(value) ~= "table" then
                return nil
            end
            numeric = numeric + 1
        end
    end
    if numeric ~= retained then return nil end
    return {source=source,head=head,tail=tail,retained=retained}
end

local function RewriteDense(source, indexed, records, first)
    for _, item in ipairs(indexed) do source[item.key] = nil end
    local retained = 0
    for index = first, #records do
        retained = retained + 1
        source[retained] = records[index]
    end
    return retained
end

local function NormalizeUnsafe(name, database)
    local definition = DEFINITIONS[name]
    if not definition then error("unknown diagnostic history: " .. SafeError(name)) end
    local db = CurrentDB(database)
    BindCache(db)
    local source = rawget(db, definition.key)
    local existingMeta, existingStorageSchema = FutureHistoryMeta(db, name)
    if existingMeta then
        local state = {
            source=source,meta=existingMeta,readOnly=true,
            reason=FUTURE_STORAGE_REASON,
            storageSchema=existingStorageSchema,
        }
        cachedHistories[name] = source
        cachedStates[name] = state
        return db, source, existingMeta, definition, state
    end

    local meta = HistoryMeta(db, name, definition)
    if type(source) ~= "table" then
        db[definition.key] = {}
        Bump(meta, "repaired", 1)
        source = db[definition.key]
        local state = {source=source,head=1,tail=0,retained=0}
        WriteStorageMeta(meta, definition, state)
        cachedHistories[name] = source
        cachedStates[name] = state
        return db, source, meta, definition, state
    end

    local stored = StoredState(meta, definition, source)
    if stored then
        cachedHistories[name] = source
        cachedStates[name] = stored
        meta.retained = stored.retained
        return db, source, meta, definition, stored
    end

    local indexed = {}
    for key, value in pairs(source) do
        if IsArrayIndex(key) then
            indexed[#indexed + 1] = {key=key, value=value}
        end
    end
    table.sort(indexed, function(left, right) return left.key < right.key end)

    local records = {}
    local repairs = 0
    local malformed = 0
    for position, item in ipairs(indexed) do
        if item.key ~= position then repairs = repairs + 1 end
        if type(item.value) == "table" then
            records[#records + 1] = item.value
        else
            repairs = repairs + 1
            malformed = malformed + 1
        end
    end
    local overflow = math.max(0, #records - definition.cap)
    if overflow > 0 then repairs = repairs + overflow end

    local retained = #records - overflow
    if repairs > 0 then
        retained = RewriteDense(source, indexed, records, overflow + 1)
        Bump(meta, "repaired", repairs)
        if malformed + overflow > 0 then
            Bump(meta, "dropped", malformed + overflow)
        end
    end
    local state = {
        source=source,head=1,tail=retained,retained=retained,
    }
    WriteStorageMeta(meta, definition, state)
    cachedHistories[name] = source
    cachedStates[name] = state
    return db, source, meta, definition, state
end

local function EnsureUnsafe(name)
    local definition = DEFINITIONS[name]
    if not definition then error("unknown diagnostic history: " .. SafeError(name)) end
    local db = CurrentDB()
    local source = rawget(db, definition.key)
    local state = cachedStates[name]
    local futureMeta, futureStorageSchema = FutureHistoryMeta(db, name)
    if futureMeta then
        if cachedDB == db and cachedHistories[name] == source
            and state and state.readOnly and state.source == source
            and state.meta == futureMeta
            and state.storageSchema == futureStorageSchema then
            return db, source, futureMeta, definition, state
        end
        return NormalizeUnsafe(name, db)
    end
    if cachedDB == db and cachedHistories[name] == source
        and state and state.source == source and type(source) == "table" then
        if state.readOnly then
            return NormalizeUnsafe(name, db)
        end
        local meta = HistoryMeta(db, name, definition)
        meta.retained = state.retained
        return db, source, meta, definition, state
    end
    return NormalizeUnsafe(name, db)
end

local function CompactUnsafe(source, meta, definition, state)
    local destination = 1
    for index = state.head, state.tail do
        local record = source[index]
        if record ~= nil then
            source[destination] = record
            destination = destination + 1
        end
    end
    for index = destination, state.tail do source[index] = nil end
    state.head = 1
    state.tail = destination - 1
    state.retained = state.tail
    Bump(meta, "compactions", 1)
    WriteStorageMeta(meta, definition, state)
end

local function Protected(defaultValue, callback, ...)
    local ok, first, second = pcall(callback, ...)
    if not ok then return defaultValue, SafeError(first) end
    return first, second
end

function Logs.Init(database)
    return Protected(false, function()
        local db = CurrentDB(database)
        for _, name in ipairs(ORDER) do NormalizeUnsafe(name, db) end
        return true
    end)
end

function Logs.Append(name, record)
    return Protected(false, function()
        if type(record) ~= "table" then return false, "record must be a table" end
        local _, history, meta, definition, state = EnsureUnsafe(name)
        if state.readOnly then return false, state.reason end
        local copy, copyError = DefensiveCopy(record)
        if not copy then return false, copyError end
        local nextTail = state.tail + 1
        history[nextTail] = copy
        state.tail = nextTail
        state.retained = state.retained + 1
        Bump(meta, "appended", 1)
        if state.retained > definition.cap then
            history[state.head] = nil
            state.head = state.head + 1
            state.retained = state.retained - 1
            Bump(meta, "dropped", 1)
        end
        if state.tail >= definition.trimAt and state.head > 1 then
            CompactUnsafe(history, meta, definition, state)
        else
            WriteStorageMeta(meta, definition, state)
        end
        return true
    end)
end

function Logs.UpdateLast(name, updater)
    return Protected(false, function()
        if type(updater) ~= "function" then return false, "updater must be a function" end
        local _, history, meta, _, state = NormalizeUnsafe(name)
        if state.readOnly then return false, state.reason end
        if state.retained == 0 then return false, "history is empty" end
        local copy, copyError = DefensiveCopy(history[state.tail])
        if not copy then return false, copyError end
        local okUpdate, accepted = pcall(updater, copy)
        if not okUpdate then return false, SafeError(accepted) end
        if accepted == false then return false, "update rejected" end
        history[state.tail] = copy
        Bump(meta, "updated", 1)
        return true
    end)
end

function Logs.Snapshot(name)
    return Protected({}, function()
        local _, history, _, _, state = NormalizeUnsafe(name)
        if state.readOnly then return {}, state.reason end
        local logical = {}
        CopyExtensions(history, logical)
        for index = state.head, state.tail do
            logical[#logical + 1] = history[index]
        end
        local copy, copyError = DefensiveCopy(logical)
        if not copy then return {}, copyError end
        return copy
    end)
end

local function ClearUnsafe(name, database)
    local _, history, meta, definition, state =
        NormalizeUnsafe(name, database)
    if state.readOnly then return false, state.reason end
    local numeric = {}
    for key in pairs(history) do
        if IsArrayIndex(key) then numeric[#numeric + 1] = key end
    end
    for _, key in ipairs(numeric) do history[key] = nil end
    state.head, state.tail, state.retained = 1, 0, 0
    meta.retained, meta.appended, meta.dropped = 0, 0, 0
    meta.repaired, meta.updated, meta.compactions = 0, 0, 0
    Bump(meta, "clears", 1)
    WriteStorageMeta(meta, definition, state)
    cachedHistories[name], cachedStates[name] = history, state
    return true
end

function Logs.Clear(name)
    return Protected(false, function()
        if not DEFINITIONS[name] then return false, "unknown diagnostic history" end
        return ClearUnsafe(name, CurrentDB())
    end)
end

function Logs.ClearAll()
    return Protected(false, function()
        local db = CurrentDB()
        -- Preflight without normalizing a supported sibling. A future history
        -- owns its physical index semantics, so the all-history operation is
        -- refused before changing any array or metadata table.
        for _, name in ipairs(ORDER) do
            if FutureHistoryMeta(db, name) then
                return false, FUTURE_STORAGE_REASON
            end
        end
        for _, name in ipairs(ORDER) do ClearUnsafe(name, db) end
        return true
    end)
end

function Logs.Stats(name)
    return Protected({available=false, name=name}, function()
        local _, history, meta, definition, state = NormalizeUnsafe(name)
        if state.readOnly then
            return {
                available=false,name=name,key=definition.key,
                cap=definition.cap,readOnly=true,
                storageSchema=state.storageSchema,reason=state.reason,
            }
        end
        local storageSlots, maximum = 0, 0
        for key in pairs(history) do
            if IsArrayIndex(key) then
                storageSlots = storageSlots + 1
                if key > maximum then maximum = key end
            end
        end
        return {
            available=true,
            name=name,
            key=definition.key,
            cap=definition.cap,
            trimAt=definition.trimAt,
            retained=state.retained,
            head=state.head,
            tail=state.tail,
            storageSlots=storageSlots,
            maxIndex=maximum,
            appended=Number(meta.appended),
            dropped=Number(meta.dropped),
            compactions=Number(meta.compactions),
            repaired=Number(meta.repaired),
            updated=Number(meta.updated),
            clears=Number(meta.clears),
        }
    end)
end

function Logs.Definitions()
    local definitions = {}
    for _, name in ipairs(ORDER) do
        definitions[name] = {
            key=DEFINITIONS[name].key,cap=DEFINITIONS[name].cap,
            trimAt=DEFINITIONS[name].trimAt,
        }
    end
    return definitions
end
