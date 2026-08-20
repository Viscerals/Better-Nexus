-- Characterize ProjectEbonhold hook ownership for independent UI/service
-- initialization and duplicate-hook prevention across repeated polls.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

local rawHooksecurefunc = hooksecurefunc
local installs = {}
local invocations = {}

local function HookKey(tbl, name)
    if _G.ProjectEbonhold and (tbl == _G.ProjectEbonhold.PerkUI
        or tbl == _G.ProjectEbonhold.EchoJournal) then
        return "ui:" .. name
    end
    if _G.ProjectEbonhold and tbl == _G.ProjectEbonhold.PerkService then
        return "service:" .. name
    end
    return "other:" .. name
end

hooksecurefunc = function(tbl, name, callback)
    local key = HookKey(tbl, name)
    installs[key] = (installs[key] or 0) + 1
    local wrapped = function(...)
        invocations[key] = (invocations[key] or 0) + 1
        return callback(...)
    end
    return rawHooksecurefunc(tbl, name, wrapped)
end

local function ResetCounters()
    installs = {}
    invocations = {}
end

local function BuildPerkUI()
    return {
        Show = function() end,
        UpdateSinglePerk = function() end,
    }
end

local function BuildEchoJournal()
    return { OnDataChanged = function() end }
end

local function BuildPerkService()
    return {
        SelectPerk = function() end,
        BanishPerk = function() end,
        FreezePerk = function() end,
        RequestReroll = function() end,
    }
end

local function ReinitAdapter()
    Nexus.Store.Init()
    dofile("core/GameAdapter.lua")
    return Nexus.GameAdapter
end

local function LabelFromName(name)
    if name == "Show" or name == "UpdateSinglePerk"
        or name == "OnDataChanged" then return "ui"
    end
    return "service"
end

local function ExpectUniqueHookInstall(expected)
    for name, expectedCount in pairs(expected) do
        local key = LabelFromName(name) .. ":" .. name
        Check(installs[key] == expectedCount,
            "unexpected hook-install count for " .. key)
    end
end

local function ExpectInvocations(expected)
    for name, expectedCount in pairs(expected) do
        local key = LabelFromName(name) .. ":" .. name
        Check(invocations[key] == expectedCount,
            "unexpected hook-invocation count for " .. key)
    end
end

-- UI arrives first, service later.
ResetCounters()
_G.ProjectEbonhold = {
    PerkUI = BuildPerkUI(),
    EchoJournal = BuildEchoJournal(),
}
local Adapter = ReinitAdapter()
Adapter.Init(function() end, Store)
Adapter.Poll(); Adapter.Poll()
ExpectUniqueHookInstall({
    Show = 1, UpdateSinglePerk = 1, OnDataChanged = 1,
})

_G.ProjectEbonhold.PerkService = BuildPerkService()
Adapter.Poll()
ExpectUniqueHookInstall({
    Show = 1, UpdateSinglePerk = 1, OnDataChanged = 1,
    SelectPerk = 1, BanishPerk = 1, FreezePerk = 1, RequestReroll = 1,
})
Adapter.Poll()
ExpectUniqueHookInstall({
    Show = 1, UpdateSinglePerk = 1, OnDataChanged = 1,
    SelectPerk = 1, BanishPerk = 1, FreezePerk = 1, RequestReroll = 1,
})

-- Trigger each hook once and confirm no duplicated callback execution.
_G.ProjectEbonhold.PerkUI.Show()
_G.ProjectEbonhold.PerkUI.UpdateSinglePerk(1)
_G.ProjectEbonhold.EchoJournal.OnDataChanged()
_G.ProjectEbonhold.PerkService.SelectPerk(200100)
_G.ProjectEbonhold.PerkService.BanishPerk(1)
_G.ProjectEbonhold.PerkService.FreezePerk(1)
_G.ProjectEbonhold.PerkService.RequestReroll()
ExpectInvocations({
    Show = 1, UpdateSinglePerk = 1, OnDataChanged = 1,
    SelectPerk = 1, BanishPerk = 1, FreezePerk = 1, RequestReroll = 1,
})

-- Service arrives first, UI later.
ResetCounters()
_G.ProjectEbonhold = { PerkService = BuildPerkService() }
local ServiceFirst = ReinitAdapter()
ServiceFirst.Init(function() end, Store)
ServiceFirst.Poll()
ExpectUniqueHookInstall({
    SelectPerk = 1, BanishPerk = 1, FreezePerk = 1, RequestReroll = 1,
})
_G.ProjectEbonhold.PerkUI = BuildPerkUI()
_G.ProjectEbonhold.EchoJournal = BuildEchoJournal()
ServiceFirst.Poll()
ExpectUniqueHookInstall({
    Show = 1, UpdateSinglePerk = 1, OnDataChanged = 1,
    SelectPerk = 1, BanishPerk = 1, FreezePerk = 1, RequestReroll = 1,
})
ServiceFirst.Poll()
ExpectUniqueHookInstall({
    Show = 1, UpdateSinglePerk = 1, OnDataChanged = 1,
    SelectPerk = 1, BanishPerk = 1, FreezePerk = 1, RequestReroll = 1,
})

_G.ProjectEbonhold.PerkUI.Show()
_G.ProjectEbonhold.PerkUI.UpdateSinglePerk(1)
_G.ProjectEbonhold.EchoJournal.OnDataChanged()
_G.ProjectEbonhold.PerkService.SelectPerk(200100)
_G.ProjectEbonhold.PerkService.BanishPerk(1)
_G.ProjectEbonhold.PerkService.FreezePerk(1)
_G.ProjectEbonhold.PerkService.RequestReroll()
ExpectInvocations({
    Show = 1, UpdateSinglePerk = 1, OnDataChanged = 1,
    SelectPerk = 1, BanishPerk = 1, FreezePerk = 1, RequestReroll = 1,
})

if #failures > 0 then
    error("EXPECTED RED Stage 36.7 hook installation: "
        .. table.concat(failures, "; "))
end

print("ProjectEbonhold hook ownership is independent, late-safe, and idempotent")
