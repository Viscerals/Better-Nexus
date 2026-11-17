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

-- Full-UI localization (issues #143-#148): the code-owned words of the lines
-- below resolve through Nexus.Localization when the tooltip is built (never
-- cached at load); while the seam is absent or a key answers "unavailable"
-- the exact English is shown. Player names, build titles, versions and
-- numbers are data and are inserted unchanged.
local function Say(key, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Text) == "function" then
        local text, source = localization.Text(key)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end
local function SayF(key, args, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Format) == "function" then
        local text, source = localization.Format(key, args)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function FmtDps(dps)
    if not dps or dps <= 0 then return nil end
    if dps >= 1000000 then return string.format("%.2fM", dps / 1000000) end
    if dps >= 1000 then return string.format("%dk", math.floor(dps / 1000)) end
    return tostring(math.floor(dps))
end

-- The rank as an ordinal. English chooses among four suffixes; the choice
-- stays here (four keys, no plural or ordinal grammar in the seam).
local function OrdinalSuffix(n)
    local m10, m100 = n % 10, n % 100
    local rank = tostring(n)
    if m10 == 1 and m100 ~= 11 then return SayF("unit_tooltip.value.rank_st", {rank = rank}, rank .. "st")
    elseif m10 == 2 and m100 ~= 12 then return SayF("unit_tooltip.value.rank_nd", {rank = rank}, rank .. "nd")
    elseif m10 == 3 and m100 ~= 13 then return SayF("unit_tooltip.value.rank_rd", {rank = rank}, rank .. "rd")
    else return SayF("unit_tooltip.value.rank_th", {rank = rank}, rank .. "th") end
end

-- Nexus's own badge line begins with this text. It is also the duplicate
-- marker: a name or guild line that merely contains "Nexus" is not it. It is
-- built once per augmentation in the shown language and the same value is
-- both written and compared, so a translated badge keeps the check.
local function Badge()
    return "|cff7fd5ff" .. Say("unit_tooltip.label.nexus_user", "Nexus user") .. "|r"
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

    -- Avoid duplicate augmentation if another tooltip event fires for the same
    -- unit: only the tooltip's current lines count, and only the badge marks
    -- them, so a cleared and reused tooltip keeps nothing from its last unit.
    local BADGE = Badge()
    for i = 1, (tooltip.NumLines and tooltip:NumLines() or 0) do
        local fs = _G[(tooltip:GetName() or "GameTooltip") .. "TextLeft" .. i]
        local text = fs and tostring(fs:GetText() or "") or ""
        if text:sub(1, #BADGE) == BADGE then return end
    end

    -- Badge line
    if peerInfo and peerInfo.version and peerInfo.version ~= "?" then
        tooltip:AddLine(BADGE .. "  |cff888888v" .. tostring(peerInfo.version) .. "|r")
    else
        tooltip:AddLine(BADGE)
    end

    -- Rank / DPS line
    if info then
        local rankStr  = OrdinalSuffix(info.rank)
        local dpsStr   = FmtDps(info.dps) or "?"
        local catStr   = info.category == "lk" and Say("unit_tooltip.value.category_lk", "LK")
            or Say("unit_tooltip.value.category_dummy", "Dummy")
        local rawTitle = info.title and tostring(info.title) or nil
        local truncate = Nexus and Nexus.LayoutMetrics
            and Nexus.LayoutMetrics.Truncate
        if rawTitle then
            rawTitle = truncate and truncate(rawTitle, 28)
                or rawTitle:sub(1, 28)
        end
        local displayText = Nexus and Nexus.Identity
            and Nexus.Identity.DisplaySafeText
        local safeTitle = rawTitle and displayText
            and displayText(rawTitle, 120, false) or nil
        local buildStr = safeTitle and ("|cff888888" .. safeTitle .. "|r  ") or ""
        -- The build title prefix and the colours stay code-owned around the
        -- translated sentence; rank, DPS and category arrive as slot values.
        local rank, dps = "|cffffd200" .. rankStr .. "|r", "|cff4dff80" .. dpsStr .. "|r"
        tooltip:AddLine(buildStr .. SayF("unit_tooltip.label.leaderboard_rank",
                {rank = rank, dps = dps, category = catStr},
                string.format("%s on leaderboard  %s  %s", rank, dps, catStr)),
            1, 1, 1, true)
    elseif isAuthor then
        tooltip:AddLine("|cff888888" .. Say("unit_tooltip.label.build_author", "Community build author") .. "|r",
            1, 1, 1)
    elseif peerInfo then
        tooltip:AddLine("|cff888888" .. Say("unit_tooltip.label.network_peer",
            "Nexus user seen on the build-sharing network") .. "|r", 1, 1, 1)
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
