-- Nexus: ui/Nameplate.lua
-- Adds a non-intrusive Nexus badge and leaderboard rank to the unit
-- tooltip (GameTooltip) when you mouse over another player.
--
-- Based on the confirmed-working EbonBuilds pattern for 3.3.5:
--   • GameTooltip:HookScript("OnTooltipSetUnit", fn) — fn receives only
--     the tooltip frame as self, NOT the unit token
--   • tooltip:GetUnit() returns name, unitToken — that's how we get the unit
--   • tooltip:AddLine(...) + tooltip:Show() to make lines appear
--
-- What triggers this: any mouseover that causes GameTooltip to call
-- SetUnit — nameplates, unit frames, raid frames, the target frame, etc.
--
-- Shows for:
--   • Nexus peers seen on the live sync mesh
--   • Players with a DPS record in the local Nexus leaderboard
--   • Players who authored a build in the local community library
-- Shows nothing for NPCs, yourself, or unknown players.

Nexus = Nexus or {}
local M = {}
Nexus.Nameplate = M

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function FmtDps(dps)
    if not dps or dps <= 0 then return nil end
    if dps >= 1000000 then return string.format("%.2fM", dps / 1000000) end
    return string.format("%dk", math.floor(dps / 1000))
end

local function OrdinalSuffix(n)
    local m10, m100 = n % 10, n % 100
    if m10 == 1 and m100 ~= 11 then return tostring(n) .. "st"
    elseif m10 == 2 and m100 ~= 12 then return tostring(n) .. "nd"
    elseif m10 == 3 and m100 ~= 13 then return tostring(n) .. "rd"
    else return tostring(n) .. "th" end
end

local function IsCommunityAuthor(name)
    if not name or name == "" then return false end
    local catalog = Nexus and Nexus.BuildCatalog
    return catalog and type(catalog.IsAuthor) == "function"
        and catalog.IsAuthor(name) == true or false
end

------------------------------------------------------------------------
-- Core tooltip augmentation
-- Called by the HookScript handler with `tooltip` as self.
-- We use tooltip:GetUnit() to get the unit — do NOT rely on any
-- argument being passed as the unit (3.3.5 HookScript doesn't do that).
------------------------------------------------------------------------

local function AugmentUnitTooltip(tooltip)
    -- GetUnit returns: name (display), unitToken ("target", "mouseover", etc.)
    local _, unit = tooltip:GetUnit()
    if not unit then return end
    if not (UnitIsPlayer and UnitIsPlayer(unit)) then return end

    local name = UnitName and UnitName(unit)
    if not name or name == "" then return end

    -- Don't annotate yourself
    local me = UnitName and UnitName("player") or ""
    if name == me then return end

    local D = Nexus.DpsCapture
    if not D then return end

    local info     = D.GetPlayerInfo and D.GetPlayerInfo(name)
    local isAuthor = IsCommunityAuthor(name)
    local peerInfo = Nexus.Sync and Nexus.Sync.GetPeerInfo and Nexus.Sync.GetPeerInfo(name) or nil

    if not info and not isAuthor and not peerInfo then return end

    -- Avoid duplicate augmentation if another tooltip event fires for the same unit.
    local marker = "Nexus"
    for i = 1, (tooltip.NumLines and tooltip:NumLines() or 0) do
        local fs = _G[(tooltip:GetName() or "GameTooltip") .. "TextLeft" .. i]
        if fs and tostring(fs:GetText() or ""):find(marker, 1, true) then return end
    end

    -- Badge line
    if peerInfo and peerInfo.version and peerInfo.version ~= "?" then
        tooltip:AddLine("|cff7fd5ffNexus user|r  |cff888888v" .. tostring(peerInfo.version) .. "|r")
    else
        tooltip:AddLine("|cff7fd5ffNexus user|r")
    end

    -- Rank / DPS line
    if info then
        local rankStr  = OrdinalSuffix(info.rank)
        local dpsStr   = FmtDps(info.dps) or "?"
        local catStr   = info.category == "lk" and "LK" or "Dummy"
        local buildStr = info.title and ("|cff888888" .. info.title:sub(1, 28) .. "|r  ") or ""
        tooltip:AddLine(
            string.format("%s|cffffd200%s|r on leaderboard  |cff4dff80%s|r  %s",
                buildStr, rankStr, dpsStr, catStr),
            1, 1, 1, true)
    elseif isAuthor then
        tooltip:AddLine("|cff888888Community build author|r", 1, 1, 1)
    elseif peerInfo then
        tooltip:AddLine("|cff888888Connected to the Nexus sync mesh|r", 1, 1, 1)
    end

    -- Required: AddLine alone doesn't resize the tooltip on 3.3.5
    tooltip:Show()
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

local hooked = false

function M.Init()
    if hooked then return end
    if not GameTooltip then return end

    -- Primary hook: OnTooltipSetUnit fires whenever a unit tooltip is
    -- populated. This is the same approach EbonBuilds uses and is
    -- confirmed working on this 3.3.5 core.
    if GameTooltip.HookScript then
        local ok, err = pcall(
            GameTooltip.HookScript, GameTooltip,
            "OnTooltipSetUnit",
            function(self)
                pcall(AugmentUnitTooltip, self)
            end)
        if ok then
            hooked = true
            return
        end
        -- HookScript failed — fall through to the manual wrap
    end

    -- Fallback: wrap GameTooltip:SetUnit directly. Less ideal because
    -- we must call orig first so GetUnit() works inside the callback.
    if GameTooltip.SetUnit then
        local orig = GameTooltip.SetUnit
        GameTooltip.SetUnit = function(self, unit, ...)
            pcall(orig, self, unit, ...)
            if unit then pcall(AugmentUnitTooltip, self) end
        end
        hooked = true
    end
end

-- Expose the core function for testing without GameTooltip
M._AugmentUnitTooltip = AugmentUnitTooltip
