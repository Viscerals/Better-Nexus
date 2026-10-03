-- Optional, failure-isolated StutterAlert diagnostic-provider integration.

Nexus = Nexus or {}

local Integration = {}
Nexus.StutterAlertIntegration = Integration

local ADDON_NAME = "Nexus"
local API_VERSION = 1
local MAX_OPERATIONS = 5
local PRIORITY = {
    ["automation.fallback.repair"] = 4,
    ["automation.step"] = 3,
    ["gameadapter.poll"] = 2,
    ["automation.update"] = 1,
}

local registeredApi = nil

local function FiniteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge then return nil end
    return number
end

local function CorrelationWindow(context)
    if type(context) ~= "table" then return nil end
    if context.addonName ~= nil and context.addonName ~= ADDON_NAME then return nil end
    local windowStart = FiniteNumber(context.hitchStartTime)
    local windowEnd = FiniteNumber(context.hitchEndTime)
    if not windowStart or not windowEnd or windowEnd < windowStart then return nil end

    local profilingAt = FiniteNumber(context.profilingTimestamp)
    local profileWindowMs = FiniteNumber(context.profileWindowMs)
    if profilingAt and profileWindowMs and profileWindowMs >= 0 then
        windowStart = math.min(windowStart, profilingAt - (profileWindowMs / 1000))
        windowEnd = math.max(windowEnd, profilingAt)
    end
    return windowStart, windowEnd
end

local function CopyProviderFields(fields)
    local copied = {}
    for index = 1, math.min(4, type(fields) == "table" and #fields or 0) do
        local field = fields[index]
        if type(field) == "table" and type(field.key) == "string"
            and (type(field.value) == "string" or type(field.value) == "number"
                or type(field.value) == "boolean") then
            copied[#copied + 1] = {key=field.key, value=field.value}
        end
    end
    return copied
end

local function CollectUnsafe(context)
    local windowStart, windowEnd = CorrelationWindow(context)
    if not windowStart then return nil end
    local performance = Nexus and Nexus.Performance
    if not (performance and type(performance.RecentOperations) == "function") then
        return nil
    end
    local recent = performance.RecentOperations(windowStart, windowEnd, windowEnd)
    if type(recent) ~= "table" or #recent == 0 then return nil end

    local ranked = {}
    for index, operation in ipairs(recent) do
        if type(operation) == "table" and type(operation.name) == "string"
            and FiniteNumber(operation.durationMs) then
            ranked[#ranked + 1] = {operation=operation, order=index}
        end
    end
    table.sort(ranked, function(left, right)
        local a, b = left.operation, right.operation
        local aPriority, bPriority = PRIORITY[a.name] or 0, PRIORITY[b.name] or 0
        if aPriority ~= bPriority then return aPriority > bPriority end
        if a.endTime ~= b.endTime then return (a.endTime or 0) > (b.endTime or 0) end
        if a.startTime ~= b.startTime then return (a.startTime or 0) > (b.startTime or 0) end
        if a.name ~= b.name then return a.name < b.name end
        return left.order < right.order
    end)

    local operations = {}
    for index = 1, math.min(MAX_OPERATIONS, #ranked) do
        local operation = ranked[index].operation
        operations[index] = {
            name=operation.name,
            durationMs=operation.durationMs,
            fields=CopyProviderFields(operation.fields),
        }
    end
    if #operations == 0 then return nil end
    local summary = operations[1].name == "automation.fallback.repair"
        and "A recent Nexus automation repair overlaps the attributed hitch."
        or "Recent bounded Nexus operations overlap the attributed hitch."
    return {summary=summary, operations=operations}
end

local function Collect(context)
    local ok, result = pcall(CollectUnsafe, context)
    -- StutterAlert's provider contract distinguishes a valid empty table from
    -- malformed non-table output. Internal failures remain isolated, but must
    -- still report the valid empty shape so the consumer records "empty".
    return ok and type(result) == "table" and result or {}
end

function Integration.Unregister()
    local api = registeredApi
    registeredApi = nil
    if not (api and type(api.UnregisterDiagnosticProvider) == "function") then
        return false
    end
    local ok, removed = pcall(api.UnregisterDiagnosticProvider, ADDON_NAME)
    return ok and removed == true
end

function Integration.Register()
    local api = _G and _G.StutterAlert
    if type(api) ~= "table" or api.DIAGNOSTIC_PROVIDER_API ~= API_VERSION
        or type(api.RegisterDiagnosticProvider) ~= "function" then
        if registeredApi then Integration.Unregister() end
        return false, "unsupported or unavailable API"
    end
    if registeredApi == api then return true end
    if registeredApi then Integration.Unregister() end
    local ok, registered, reason = pcall(api.RegisterDiagnosticProvider,
        ADDON_NAME, Collect)
    if not ok or registered ~= true then
        return false, ok and reason or "registration failed"
    end
    registeredApi = api
    return true
end

function Integration.IsRegistered()
    return registeredApi ~= nil
end

Integration.Collect = Collect
