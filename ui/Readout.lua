-- Nexus: ui/Readout.lua
-- Pure string builders for the panel and journal tab. No frames, no IO,
-- no WoW API: loadable under bare LuaJIT for the offline suite. Names
-- arrive pre-bridged (spellId -> name) by the caller; a missing name
-- falls back to the spellId so a line is never blank.

Nexus = Nexus or {}
local M = {}
Nexus.Readout = M

local QUALITY_NAMES = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare",
    [3] = "Epic", [4] = "Legendary",
}

-- %d on a raw float truncates silently on this toolchain; round first.
local function Round(x)
    return math.floor(x + 0.5)
end

local function NameOf(t)
    if type(t) ~= "table" then return "?" end
    if t.name ~= nil then return tostring(t.name) end
    if t.spellId ~= nil then return "spell " .. tostring(t.spellId) end
    return "?"
end

-- One honest sentence. model = { text=s|nil (verbatim main clause),
-- level=n|nil, advisorOnly=b, synced=b|nil, charges=charges|nil }.
-- Derived fallbacks cover the states Main may not phrase itself;
-- charges append as "B:n R:n F:n", "(approx)" when not trustworthy.
function M.Status(model)
    if type(model) ~= "table" then return "" end
    local main
    if model.text ~= nil then
        main = Nexus.UserText and Nexus.UserText.Message(model.text) or tostring(model.text)
    elseif model.advisorOnly then
        main = "No Wishlist assigned - recommendations only"
    elseif model.synced == false then
        main = "Waiting for current Echo data - automatic choices paused"
    else
        main = "idle"
    end
    if type(model.level) == "number" then
        main = string.format("Lv %d - %s", Round(model.level), main)
    end
    local c = model.charges
    if type(c) == "table" then
        local s = string.format("Banish:%d Reroll:%d Freeze:%d",
            Round(tonumber(c.banish) or 0),
            Round(tonumber(c.reroll) or 0),
            Round(tonumber(c.freeze) or 0))
        if c.trustworthy == false then s = s .. " (estimated)" end
        main = main .. " | " .. s
    end
    return main
end

-- "[G] Name (Epic) +100 wanted". card = board card (+ bridged .name),
-- annotation = Policy annotation word or nil, delta = number or nil.
function M.CardLine(card, annotation, delta)
    if type(card) ~= "table" then return "" end
    local parts = {}
    if card.isGuaranteed then parts[#parts + 1] = "[Guaranteed offer]" end
    parts[#parts + 1] = NameOf(card)
    local q = QUALITY_NAMES[card.quality]
    if q then parts[#parts + 1] = "(" .. q .. ")" end
    -- Scores remain available in diagnostics; they are priorities, not DPS.
    -- The "[Guaranteed offer]" prefix already states EchoWeaver's
    -- "guaranteed" annotation.
    if annotation ~= nil and annotation ~= ""
        and not (annotation == "guaranteed" and card.isGuaranteed) then
        parts[#parts + 1] = Nexus.UserText and Nexus.UserText.Annotation(annotation) or tostring(annotation)
    end
    return table.concat(parts, " ")
end

-- The card the current recommendation takes: exactly one card that the
-- runtime marked as the Take target (card.highlight). None, or several (the
-- same Echo offered twice), gives nil, so no card is guessed.
function M.MarkedCard(cards)
    if type(cards) ~= "table" then return nil end
    local found
    for i = 1, math.min(#cards, 3) do
        local c = cards[i]
        if type(c) == "table" and c.highlight == true then
            if found then return nil end
            found = i
        end
    end
    return found
end

-- "Name (Quality)" from a CardLine text; nil when the line carries no known
-- quality, since the name then cannot be told from its annotation.
function M.CardTarget(text)
    text = tostring(text or ""):gsub("^%[Guaranteed offer%] ", "")
    local first, last
    for _, q in pairs(QUALITY_NAMES) do
        local s, e = text:find(" (" .. q .. ")", 1, true)
        if s and (not first or s < first) then first, last = s, e end
    end
    if not first or first <= 1 then return nil end
    return text:sub(1, last)
end

-- An unstepped recommendation with its definite target named:
-- "<reason>: <Name (Quality)>". A stepped plan (numbered lines) already
-- names each step and is returned unchanged, as is a line with no target.
function M.RecommendationWithTarget(recommendation, cardText)
    local text = tostring(recommendation or "")
    if text:find("^%d+%. ") or text:find("\n%d+%. ") then return text end
    local target = M.CardTarget(cardText)
    if not target then return text end
    if text == "" then return "Take: " .. target end
    return text .. ": " .. target
end

-- Compact charges for the roll heading, "B:2 R:1 F:0". A count the game has
-- not reported (charges.arrived == false, or no number) is "?", never 0;
-- counts the adapter does not trust are marked "~" (estimated). Without a
-- charges table there is nothing to show (""). Formatting only: it reads no
-- service and changes no count. Issue #142: each count is normalized here to
-- a whole number or unknown and rendered by the named template
-- "readout.charge_counts" (Nexus.Localization.Format); the " ~" marker is
-- appended after the complete row. Without the seam the English row is built
-- here, as before.
function M.ChargesLine(charges)
    if type(charges) ~= "table" then return "" end
    local arrived = charges.arrived ~= false
    local function Count(value)
        value = tonumber(value)
        if not arrived or value == nil or value ~= value or value < 0
            or value >= math.huge then return nil end
        return Round(value)
    end
    local banish, reroll, freeze = Count(charges.banish), Count(charges.reroll),
        Count(charges.freeze)
    local suffix = (arrived and charges.trustworthy == false) and " ~" or ""
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Format) == "function" then
        local function Slot(count)
            if count == nil then return {known = false} end
            return {known = true, value = count}
        end
        local text, source = localization.Format("readout.charge_counts",
            {banish = Slot(banish), reroll = Slot(reroll), freeze = Slot(freeze)})
        if type(text) == "string" and source ~= "unavailable" then
            return text .. suffix
        end
        -- Format already recorded the bounded failure. Its generic status
        -- cannot replace available counts: use the reviewed legacy row below.
    end
    local function Shown(count) return count == nil and "?" or tostring(count) end
    return "B:" .. Shown(banish) .. " R:" .. Shown(reroll) .. " F:" .. Shown(freeze) .. suffix
end

-- The legend of that line (its hover). Text only, from GameAdapter.Charges'
-- own rules: counts the runtime last read for its decision; "?" before the
-- game reports them; "~" when they look like the game's placeholder format.
function M.ChargesLegend()
    return {
        "B, R and F: the Banish, Reroll and Freeze charges left this run, as the game reported them when "
            .. "Nexus made its last decision.",
        "?: the game has not reported that count yet. It is unknown, not zero.",
        "~: estimated. The counts look like the placeholder the game sends without real counts, so they may "
            .. "be wrong.",
        "Shown with Auto OFF, where you choose; with Auto ON Nexus uses these charges itself.",
    }
end

-- Plain words for why a selected Auto is not acting (the runtime's
-- AutoAllowed and effective-state reasons). Anything else keeps the
-- player wording of UserText. Text only; it changes no gate.
local HOLD_TEXT = {
    ["manual mode"] = "Auto is OFF: Nexus only recommends.",
    ["loading screen (waiting for world entry)"] = "A loading screen is in progress; Nexus waits until you "
        .. "are in the world.",
    ["settling after world entry"] = "Nexus waits a few seconds after a loading screen before it acts.",
    ["user acting"] = "You made an Echo choice in the game's window; Nexus waits about 3 seconds before it "
        .. "acts again.",
    ["Another Echo automation addon is loaded -- disable it"] = "Another Echo automation addon is loaded; "
        .. "Nexus does not act while it is enabled. Disable that addon to let Nexus act.",
    ["client auto-accept re-enabled"] = "The game's own option to accept loadout Echoes automatically is on; "
        .. "Nexus does not act while it is on. Turn it off in the game's options.",
}
function M.AutoHoldText(reason)
    local s = tostring(reason or "")
    if HOLD_TEXT[s] then return HOLD_TEXT[s] end
    local text = Nexus.UserText and Nexus.UserText.Message
    return type(text) == "function" and text(s) or s
end

-- What the player can do about a hold, for the same reasons. A reason whose
-- own text already says what to do (an unresolved action across a loading
-- screen) gets none. Text only.
local HELP_HINT = {
    ["loading screen (waiting for world entry)"] = "What helps: nothing; it continues by itself.",
    ["settling after world entry"] = "What helps: nothing; it continues by itself.",
    ["user acting"] = "What helps: wait without choosing; it continues by itself.",
    ["Another Echo automation addon is loaded -- disable it"] = "What helps: disable the other addon in the "
        .. "AddOns list at character selection.",
    ["client auto-accept re-enabled"] = "What helps: turn off the game's option to accept loadout Echoes "
        .. "automatically.",
}
function M.AutoHelpHint(reason)
    local s = tostring(reason or "")
    if HELP_HINT[s] then return HELP_HINT[s] end
    if s == "" or s == "manual mode" or s:find("no confirmed result for", 1, true) then return nil end
    if s:find("Orb", 1, true) or s:find("orb", 1, true) then
        return "What helps: finish, pause or stop the Orb run in Orbs (... menu), or wait until Nexus can "
            .. "read the Orb state."
    end
    return "What helps: point at the Auto button for details."
end

-- The inline line for a selected Auto that is not acting: the plain reason
-- and, when there is one, what helps.
function M.AutoHoldNote(reason)
    local hint = M.AutoHelpHint(reason)
    return "Paused: " .. M.AutoHoldText(reason) .. (hint and (" " .. hint) or "")
end

-- The inline line for an Auto click that left Auto OFF without opening the
-- warning. `kind`: "orb" (an Orb operation blocks ordinary Automation),
-- "warning" (the warning is unavailable), else the runtime's status line.
function M.AutoRefusalText(kind, status)
    if kind == "orb" then
        return "Auto stayed OFF: an Orb run is active or unresolved. What helps: finish or stop it in "
            .. "Orbs (... menu, Orbs / Lost Memories)."
    elseif kind == "warning" then
        return "Auto stayed OFF: its overwrite warning is unavailable, and Auto never turns ON without it. "
            .. "What helps: type /nexus report and report it."
    end
    local s = tostring(status or "")
    if s == "" then
        return "Auto stayed OFF. What helps: point at the Auto button for details."
    end
    return "Auto stayed OFF: " .. s
end

-- The Automation scope in plain lines, from facts the caller read without
-- acting: `selected` (the session's Auto selection), `held` (why it is not
-- acting, if it is not), `settings` (Store.Settings) and `readOnly` (saved
-- data is read-only). Each line names a permission the runtime actually
-- gates on, its current value and the existing control that changes it.
-- Reading it changes nothing.
-- How each gate reads a permission that was never saved: Reroll and Freeze
-- are blocked only by a saved false; every other gate needs a saved true.
local UNSET_ACTS_ON = {autoReroll = true, autoFreeze = true}
local function OnOff(settings, key, raw)
    -- Not `settings[key] or nil`: that turns a saved false into "not set".
    local value
    if type(settings) == "table" then value = settings[key] end
    if value == true then return "on" elseif value == false then return "off" end
    if raw then return "not set" end
    return UNSET_ACTS_ON[key] and "not set (acts as on)" or "not set (acts as off)"
end
function M.AutomationScopeLines(facts)
    facts = type(facts) == "table" and facts or {}
    local s = facts.settings
    local lines = {}
    lines[#lines + 1] = facts.selected
        and "Auto: ON for this session. The selection is OFF again after every login or reload."
        or "Auto: OFF. Nexus only recommends; it takes, banishes, rerolls, freezes, saves and locks nothing."
    if facts.selected and facts.held then
        lines[#lines + 1] = "Paused because: " .. M.AutoHoldText(facts.held)
    end
    lines[#lines + 1] = "With Auto ON, Nexus may only do what these permissions allow:"
    lines[#lines + 1] = "- Take needed Echoes (autoPick): " .. OnOff(s, "autoPick")
    lines[#lines + 1] = "- Banish (autoBanish): " .. OnOff(s, "autoBanish")
    lines[#lines + 1] = "- Reroll (autoReroll): " .. OnOff(s, "autoReroll") .. "; change with /nexus reroll on|off"
    lines[#lines + 1] = "- Freeze (autoFreeze): " .. OnOff(s, "autoFreeze") .. "; change with /nexus freeze on|off"
    lines[#lines + 1] = "- Echo availability controls (tomes) (autoDisable): " .. OnOff(s, "autoDisable")
        .. "; disables off-Wishlist and re-enables Wishlist controls"
    lines[#lines + 1] = "- Save a better finished level-80 run over the active Saved Build (autoSave): "
        .. OnOff(s, "autoSave") .. "; no in-game control, and Auto OFF stops it"
    lines[#lines + 1] = "- Lock Wishlist Echoes into locked slots (autoLockEchoes): " .. OnOff(s, "autoLockEchoes")
        .. "; its own option in the Wishlist editor"
    lines[#lines + 1] = "- Activate a Saved Build: never. Nexus does not activate or load Saved Builds; the "
        .. "saved autoActivate value (" .. OnOff(s, "autoActivate", true) .. ") is not used by any action."
    lines[#lines + 1] = "- Orb runs: never by Auto; each one needs its own approval in the Orb window."
    if facts.readOnly then
        lines[#lines + 1] = "Saved data is read-only: a permission counts as on only when it was saved as on, "
            .. "and a change lasts this session only."
    end
    return lines
end

-- What the tome permission (autoDisable) does, from AutomationRuntime StepArm:
-- with Auto acting it turns off tomes the Wishlist does not use and turns
-- needed ones back on; nothing turns them back on when Auto stops. Shared by
-- the Auto warning; Help carries the same paragraph.
M.TOME_PARAGRAPH = "Tomes: with Auto ON and the tome permission (autoDisable) on, once the game's tome data is "
    .. "ready Nexus turns off Echo tomes your Wishlist does not use and turns back on tomes it needs, one change "
    .. "about every half second. It never turns off a tome you opted out of. Nexus does not turn tomes back on "
    .. "when you turn Auto OFF, log out or change the Wishlist: it turns back on only tomes a Wishlist needs (or "
    .. "that you opted out of), and only while Auto is ON. The tome list in the Echo Journal shows their state."

-- The rows of the Automation settings menu, from facts the caller read
-- without acting (as AutomationScopeLines). Each row: `text`; `kind` "title",
-- "info" (shown, not changeable here), "toggle" (an existing setter:
-- `command` is the /nexus argument to run, `checked` the current value),
-- "editor" (the option lives in the Wishlist editor) or "help". Pure.
function M.AutomationSettingsRows(facts)
    facts = type(facts) == "table" and facts or {}
    local s = facts.settings
    local rows = {}
    local function Add(kind, text, extra)
        local row = extra or {}
        row.kind, row.text = kind, text
        rows[#rows + 1] = row
    end
    local function Value(key)
        if type(s) == "table" then return s[key] end
        return nil
    end
    Add("title", "Automation settings")
    Add("info", facts.selected and "Auto: ON for this session (the Auto button turns it OFF)"
        or "Auto: OFF (the Auto button turns it ON after its warning)")
    -- The two permissions that have an in-game setter (/nexus reroll|freeze).
    for _, item in ipairs({{"autoReroll", "Allow Reroll", "reroll"}, {"autoFreeze", "Allow Freeze", "freeze"}}) do
        local on = Value(item[1]) ~= false
        Add("toggle", item[2] .. " (" .. item[1] .. "): " .. OnOff(s, item[1]),
            {key = item[1], checked = on, command = item[3] .. (on and " off" or " on")})
    end
    Add("info", "Take needed Echoes (autoPick): " .. OnOff(s, "autoPick") .. "; no in-game switch")
    Add("info", "Banish (autoBanish): " .. OnOff(s, "autoBanish") .. "; no in-game switch")
    Add("info", "Turn tomes off and on (autoDisable): " .. OnOff(s, "autoDisable") .. "; no in-game switch")
    Add("info", "Save a better finished run over the active Saved Build (autoSave): " .. OnOff(s, "autoSave")
        .. "; no in-game switch; Auto OFF stops it")
    Add("editor", "Lock Wishlist Echoes (autoLockEchoes): " .. OnOff(s, "autoLockEchoes")
        .. "; set in the Wishlist Editor...", {key = "autoLockEchoes"})
    Add("info", "Activate a Saved Build: never (the saved autoActivate value is not used)")
    Add("info", "Orb runs: never by Auto; each needs its own approval in Orbs")
    if facts.readOnly then
        Add("info", "Saved data is read-only: a change lasts this session only")
    end
    Add("help", "What Auto may do (Help)...")
    return rows
end

-- Next n predicted guaranteed arrivals, "(predicted)" suffixed --
-- injection order is measured but not version-stable, never state it
-- as fact. queue = Ratchet.PredictQueue output (entries pre-bridged).
function M.QueueLines(queue, n)
    local out = {}
    if type(queue) ~= "table" then return out end
    local entries = queue.entries
    if type(entries) ~= "table" then return out end
    local limit = tonumber(n) or 3
    for i = 1, math.min(#entries, limit) do
        local e = entries[i]
        if type(e) == "table" then
            out[#out + 1] = string.format("%d. %s%s (predicted)",
                i, NameOf(e), e.wanted and " [wanted]" or "")
        end
    end
    return out
end
