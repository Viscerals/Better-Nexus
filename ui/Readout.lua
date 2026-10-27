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

-- The quality token CardLine wrote: CardLine puts " (Quality)" directly after
-- the whole name and only an annotation after it, so the token is the LAST
-- known " (Quality)" in the line, never the first. A name that itself holds
-- " (Rare)" or similar keeps it ("Shard (Rare)" of Epic quality is
-- "Shard (Rare) (Epic)": name "Shard (Rare)", quality Epic). Residual
-- limits, stated rather than guessed around: the annotation words
-- (UserText.Annotation of the policy's annotation) are not expected to hold a
-- quality token, and from the text alone a card whose quality is unknown and
-- whose name ends in such a token reads as that quality. Callers that hold the
-- card's own facts (the HUD model's cards: CardFacts) pass them instead, and
-- then no quality is read from the text (LineFacts).
-- -> start, end, quality name; nil when the line has no known quality.
local function QualityToken(body, only)
    local first, last, quality
    for _, q in pairs(QUALITY_NAMES) do
        local token = " (" .. q .. ")"
        local from = 1
        while not only or q == only do
            local s, e = body:find(token, from, true)
            if not s then break end
            if not first or s > first then first, last, quality = s, e, q end
            from = s + 1
        end
    end
    return first, last, quality
end
M.QualityToken = QualityToken

-- The facts a CardLine is written from, for a display model to carry beside
-- its text: the whole name it prints and the card's own quality (nil when
-- unknown, as CardLine then prints none).
function M.CardFacts(card)
    if type(card) ~= "table" then return nil end
    return {name = NameOf(card), quality = QUALITY_NAMES[card.quality] and card.quality or nil}
end

-- A CardLine body (without the guarantee prefix) split with the card's own
-- facts (CardFacts): the whole name, the quality name or nil when unknown, and
-- the rest after them. A quality is never taken from the text: an unknown one
-- stays unknown whatever the name holds. When the body does not begin with
-- those facts, a known quality is found as its own last token, and an unknown
-- one leaves the whole body as the name.
local function LineFacts(body, facts)
    local name = facts.name ~= nil and tostring(facts.name) or "?"
    local quality = QUALITY_NAMES[facts.quality]
    local lead = name .. (quality and (" (" .. quality .. ")") or "")
    if body:sub(1, #lead) == lead and (#body == #lead or body:sub(#lead + 1, #lead + 1) == " ") then
        return name, quality, body:sub(#lead + 1)
    end
    if not quality then return body, nil, "" end
    local first, last = QualityToken(body, quality)
    if not first or first <= 1 then return body, quality, "" end
    return body:sub(1, first - 1), quality, body:sub(last + 1)
end

-- "Name (Quality)" from a CardLine text; nil when the line carries no known
-- quality, since the name then cannot be told from its annotation. With the
-- card's own facts (CardFacts), nil when they hold no quality.
function M.CardTarget(text, facts)
    text = tostring(text or ""):gsub("^%[Guaranteed offer%] ", "")
    if type(facts) == "table" then
        local name, quality = LineFacts(text, facts)
        return quality and (name .. " (" .. quality .. ")") or nil
    end
    local first, last = QualityToken(text)
    if not first or first <= 1 then return nil end
    return text:sub(1, last)
end

-- An unstepped recommendation with its definite target named:
-- "<reason>: <Name (Quality)>". A stepped plan (numbered lines) already
-- names each step and is returned unchanged, as is a line with no target.
-- `facts` (optional): the card's own CardFacts, as CardTarget.
function M.RecommendationWithTarget(recommendation, cardText, facts)
    local text = tostring(recommendation or "")
    if text:find("^%d+%. ") or text:find("\n%d+%. ") then return text end
    local target = M.CardTarget(cardText, facts)
    if not target then return text end
    if text == "" then return "Take: " .. target end
    return text .. ": " .. target
end

-- One offer card of the Play panel (Claude Design full UI, "Main panel
-- (Play)": the current offer first, three cards side by side). Without
-- `facts` (below) they are read from its CardLine text only (the CardTarget
-- rule): the name before the trailing quality token (QualityToken: the last
-- known " (Quality)"), that quality, and the annotation after it. A line
-- without a known quality keeps its whole text as the name and says the
-- quality is unknown, never blank. `marked` is Readout.MarkedCard's answer for
-- this card and `auto` the panel's Auto selection. The marked card is the
-- Wishlist pick with Auto OFF; with Auto ON it is the recommendation only,
-- since whether Auto takes it depends on its permissions and holds, which a
-- card does not know. `shown` is the tag line the card shows: the tag, except
-- that an unmarked guaranteed card names itself the current "[Guaranteed
-- offer]" (CardLine's own words) before its annotation, so a current offer is
-- never read as the predicted guaranteed queue (QueueLines). The guarantee is
-- said once: on that tag line, or, for a marked card whose tag line is the
-- pick, beside its quality ("Uncommon - guaranteed"). `facts` (optional):
-- the card's own CardFacts, which the HUD model carries beside the text; with
-- them the name is the whole name and the quality is the card's own, never
-- read from the text, so an unknown quality stays unknown even when the name
-- ends in " (Rare)" (LineFacts). Text only; it decides and chooses nothing.
-- -> {name, quality, tag, shown, full, marked, guaranteed}
M.OFFER_PICK_TAG = "> Wishlist pick"
M.OFFER_RECOMMENDED_TAG = "> Recommended"
M.OFFER_GUARANTEED_TAG = "[Guaranteed offer]"
function M.OfferCard(text, marked, auto, facts)
    local full = tostring(text or "")
    local body, guaranteed = full, false
    if body:find("^%[Guaranteed offer%] ") then
        guaranteed = true
        body = body:sub(#"[Guaranteed offer] " + 1)
    end
    local name, quality, rest
    if type(facts) == "table" then
        name, quality, rest = LineFacts(body, facts)
    else
        local first, last, q = QualityToken(body)
        if first and first > 1 then
            name, quality, rest = body:sub(1, first - 1), q, body:sub(last + 1)
        end
    end
    local card = {full = full, marked = marked == true, guaranteed = guaranteed}
    local note
    if quality then
        card.name = name
        note = rest:gsub("^%s+", ""):gsub("%s+$", "")
        if note == "" then note = nil end
        card.quality = quality .. ((guaranteed and card.marked) and " - guaranteed" or "")
    elseif name then
        -- The card's own facts hold no quality: the whole name, and what
        -- follows it is its annotation.
        card.name = name
        note = rest:gsub("^%s+", ""):gsub("%s+$", "")
        if note == "" then note = nil end
        card.quality = "? Quality unknown"
    else
        card.name = body
        card.quality = "? Quality unknown"
    end
    if card.marked then
        card.tag = auto == false and M.OFFER_PICK_TAG or M.OFFER_RECOMMENDED_TAG
        card.shown = card.tag
    else
        card.tag = note or ""
        card.shown = guaranteed and (M.OFFER_GUARANTEED_TAG .. (note and (" " .. note) or "")) or card.tag
    end
    return card
end

-- The offer heading: whose choice the current offer is. Auto unknown says
-- only "Current offer".
function M.OfferHeading(auto)
    if auto == false then return "Current offer - you choose" end
    if auto == true then return "Current offer - Auto ON" end
    return "Current offer"
end

-- The heading's forms, longest first, for a row that cannot hold the full
-- one: each still says whose choice the offer is ("you choose" or "Auto ON").
function M.OfferHeadingForms(auto)
    if auto == false then return {M.OfferHeading(false), "Offer - you choose", "You choose"} end
    if auto == true then return {M.OfferHeading(true), "Offer - Auto ON", "Auto ON"} end
    return {M.OfferHeading(nil), "Offer"}
end

-- The waiting state (design "Waiting for Echo data"): the runtime's
-- "unsynced" hold. Nothing is chosen while it lasts, and it is never "0
-- offers". The short form is the heading.
M.WAITING_OFFER_HEADING = "... Waiting for offer data"
M.WAITING_OFFER_NOTE = "... Waiting for current Echo data. Recommendations and automatic choices resume once "
    .. "the offer is read. Nothing is chosen meanwhile."
function M.WaitingForOffer(reason) return reason == "unsynced" end

-- The Auto ON line under the offer (design "Auto ON, active"), from the
-- permissions AutomationScopeLines lists: choosing is Auto's, saving needs its
-- own permission, and Saved Builds and Orb runs are never Auto's.
M.AUTO_ON_NOTE = "Auto may choose offers and, if its save permission is on, save a better finished run over "
    .. "this Saved Build. It never loads a build or starts Orbs."

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

-- One status vocabulary for every surface (issue #163, UI review P1): a
-- glyph and a word per state, so no state is told by colour alone. The words
-- of the Orb states are the Orb history's own labels (OrbHistory.RESULTS).
-- Glyphs are ASCII on purpose: which other symbols the client fonts draw is
-- not established, and "?" (unknown) and "~" (estimated) are the marks
-- ChargesLine already uses. A kind names what the caller read; this table
-- never decides it, and an unlisted kind is said as unknown, never as a
-- success or as zero.
local STATUS = {
    confirmed   = {glyph = "+",   word = "Confirmed"},
    requested   = {glyph = ">",   word = "Request prepared"},
    awaiting    = {glyph = "...", word = "Awaiting result"},
    choice      = {glyph = ">",   word = "Waiting for choice"},
    offer       = {glyph = "...", word = "Waiting for offer"},
    paused      = {glyph = "=",   word = "Paused"},
    unconfirmed = {glyph = "?",   word = "Unconfirmed"},
    spendUnconfirmed = {glyph = "?", word = "Spend not confirmed"},
    notSent     = {glyph = "-",   word = "Not sent"},
    sent        = {glyph = "->",  word = "Sent, not confirmed"},
    stored      = {glyph = "*",   word = "Stored on this client"},
    refused     = {glyph = "x",   word = "Refused"},
    unavailable = {glyph = "!",   word = "Unavailable"},
    estimated   = {glyph = "~",   word = "Estimated"},
    stale       = {glyph = "?",   word = "Stale"},
    loading     = {glyph = "...", word = "Loading"},
    ready       = {glyph = "+",   word = "Ready"},
    unknown     = {glyph = "?",   word = "Unknown"},
}
M.STATUS_KINDS = {"confirmed", "requested", "awaiting", "choice", "offer", "paused", "unconfirmed", "spendUnconfirmed", "notSent",
    "sent", "stored", "refused", "unavailable", "estimated", "stale", "loading", "ready", "unknown"}

-- {kind, glyph, word} for a kind (a new table; changing it changes nothing
-- here). An unlisted kind is "unknown". (M.Status above is the panel's
-- status sentence, a different builder.)
function M.StatusParts(kind)
    local entry = type(kind) == "string" and STATUS[kind] or nil
    if not entry then kind, entry = "unknown", STATUS.unknown end
    return {kind = kind, glyph = entry.glyph, word = entry.word}
end

-- "<glyph> <word>", or "<glyph> <word>: <detail>" with a nonempty detail.
function M.StatusText(kind, detail)
    local s = M.StatusParts(kind)
    local text = s.glyph .. " " .. s.word
    if detail ~= nil and tostring(detail) ~= "" then text = text .. ": " .. tostring(detail) end
    return text
end

-- A count as shown: a whole number, "~N" when the caller says it is
-- estimated, and "?" when it is missing, not a number, negative or infinite.
-- Unknown is never 0 (the ChargesLine rule).
function M.CountText(value, estimated)
    value = tonumber(value)
    if value == nil or value ~= value or value < 0 or value >= math.huge then return "?" end
    return (estimated and "~" or "") .. tostring(Round(value))
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
    if M.WaitingForOffer(reason) then return M.WAITING_OFFER_NOTE end
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
