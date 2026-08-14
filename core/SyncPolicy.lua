-- Saved Sync mode and gameplay-safety policy.
--
-- The wire protocol owns transport state; this module only answers whether
-- transport may run in the current context. Keeping the policy separate makes
-- Off/Manual/Automatic behavior deterministic and cheap to test.

Nexus = Nexus or {}
local Policy = {}
Nexus.SyncPolicy = Policy

local VALID_MODES = { off=true, manual=true, automatic=true }

local function Settings()
    if Nexus.Store and type(Nexus.Store.Settings) == "function" then
        return Nexus.Store.Settings()
    end
    NexusDB = type(NexusDB) == "table" and NexusDB or {}
    NexusDB.settings = type(NexusDB.settings) == "table" and NexusDB.settings or {}
    return NexusDB.settings
end

local function NormalizeMode(value)
    value = type(value) == "string" and value:lower() or "automatic"
    if value == "auto" then value = "automatic" end
    return VALID_MODES[value] and value or "automatic"
end

function Policy.Mode()
    return NormalizeMode(Settings().syncMode)
end

function Policy.SetMode(value)
    local mode = NormalizeMode(value)
    Settings().syncMode = mode
    return mode
end

local function InCombat(settings)
    if settings.syncSuspendInCombat == false then return false end
    if type(InCombatLockdown) == "function" then
        local ok, active = pcall(InCombatLockdown)
        if ok and active then return true end
    end
    if type(UnitAffectingCombat) == "function" then
        local ok, active = pcall(UnitAffectingCombat, "player")
        if ok and active then return true end
    end
    return false
end

local function BlockedInstance(settings)
    if type(IsInInstance) ~= "function" then return nil end
    local ok, inside, instanceType = pcall(IsInInstance)
    if not ok or not inside then return nil end
    instanceType = tostring(instanceType or "unknown"):lower()
    local configured = settings.syncSuspendedInstanceTypes
    if type(configured) ~= "table" then
        return (instanceType == "party" or instanceType == "raid"
            or instanceType == "pvp" or instanceType == "arena"
            or instanceType == "scenario") and instanceType or nil
    end
    return configured[instanceType] == true and instanceType or nil
end

function Policy.ContextBlock()
    local settings = Settings()
    if InCombat(settings) then return "in combat" end
    local instanceType = BlockedInstance(settings)
    if instanceType then return "in " .. instanceType end
    if settings.syncOnlyWhileResting ~= false and type(IsResting) == "function" then
        local ok, resting = pcall(IsResting)
        if ok and not resting then return "not resting" end
    end
    return nil
end

function Policy.Allows(manualSessionActive)
    local mode = Policy.Mode()
    if mode == "off" then return false, "sync mode is Off" end
    if mode == "manual" and not manualSessionActive then
        return false, "manual mode is idle"
    end
    local blocked = Policy.ContextBlock()
    if blocked then return false, blocked end
    return true
end

function Policy.ValidModes()
    return { "automatic", "manual", "off" }
end
