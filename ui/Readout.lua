-- Nexus: ui/Readout.lua
-- Pure string builders for the panel and journal tab. No frames, no IO,
-- no WoW API: loadable under bare LuaJIT for the offline suite. Names
-- arrive pre-bridged (spellId -> name) by the caller; a missing name
-- falls back to the spellId so a line is never blank.

-- Full-UI localization (issues #143-#148): the visible copy built here is
-- resolved through Nexus.Localization at call time (never cached at load, so
-- the session's pack, or a test's swapped seam, applies). Each call carries
-- the exact English this file built before; while the seam is absent or a key
-- answers "unavailable" that English is returned unchanged. What another
-- builder parses or matches stays raw: CardLine text (its quality tokens and
-- guarantee prefix are read back by CardTarget and OfferCard), raw hold
-- reasons and the QUALITY_NAMES tokens. Translation happens only in the
-- display values built from them.

Nexus = Nexus or {}
local M = {}
Nexus.Readout = M

-- Static text for `key`, or `english` when the seam cannot answer it.
local function T(key, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Text) == "function" then
        local text, source = localization.Text(key)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end

-- A template with code-supplied slot values, or `english` (the legacy
-- composition of the same values) when the seam cannot answer it.
local function TF(key, args, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Format) == "function" then
        local text, source = localization.Format(key, args)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end

local QUALITY_NAMES = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare",
    [3] = "Epic", [4] = "Legendary",
}
-- The shown word of each quality token (display only; the tokens above
-- stay the parse vocabulary of CardLine text).
local QUALITY_KEYS = {
    Common = "readout.value.quality_common", Uncommon = "readout.value.quality_uncommon",
    Rare = "readout.value.quality_rare", Epic = "readout.value.quality_epic",
    Legendary = "readout.value.quality_legendary",
}
local function QualityShown(quality)
    local key = QUALITY_KEYS[quality]
    return key and T(key, quality) or quality
end

-- "Name (Quality)" as shown, from a whole name and a quality token.
local function TargetShown(name, quality)
    return TF("readout.value.echo_with_quality", {name = name, quality = QualityShown(quality)},
        name .. " (" .. quality .. ")")
end

-- The code-owned "[Guaranteed offer]" marker as shown.
local function GuaranteedShown()
    return "[" .. T("readout.label.guaranteed_offer", "Guaranteed offer") .. "]"
end

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
-- The name a reader sees: a supplied name as it is; the generated fallback
-- of a card without one (NameOf's "spell <id>", which the line text and its
-- parsing keep raw) through main.value.unknown_spell. Display only.
local function ShownNameOf(t)
    if type(t) == "table" and t.name == nil and t.spellId ~= nil then
        return TF("main.value.unknown_spell", {id = tostring(t.spellId)}, "spell " .. tostring(t.spellId))
    end
    return NameOf(t)
end
-- A name parsed from a line with the card's facts: the generated fallback
-- (facts.generated, carried from CardFacts) is shown through its key; a
-- supplied name, even one that reads like "spell 123", stays as it is.
local function DisplayName(name, facts)
    if type(facts) == "table" and facts.generated == true and name == facts.name and facts.spellId ~= nil then
        return TF("main.value.unknown_spell", {id = tostring(facts.spellId)}, name)
    end
    return name
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
        main = T("readout.status.no_wishlist_advisor", "No Wishlist assigned - recommendations only")
    elseif model.synced == false then
        main = T("readout.status.waiting_echo_data", "Waiting for current Echo data - automatic choices paused")
    else
        main = T("readout.status.idle", "idle")
    end
    if type(model.level) == "number" then
        local level = string.format("%d", Round(model.level))
        main = TF("readout.status.level_prefixed", {level = level, status = main},
            string.format("Lv %d - %s", Round(model.level), main))
    end
    local c = model.charges
    if type(c) == "table" then
        -- This legacy line keeps its own knownness contract: a count the
        -- game has not reported is written 0 here (unlike ChargesLine).
        local banish = string.format("%d", Round(tonumber(c.banish) or 0))
        local reroll = string.format("%d", Round(tonumber(c.reroll) or 0))
        local freeze = string.format("%d", Round(tonumber(c.freeze) or 0))
        local s = TF("readout.status.charges_full", {banish = banish, reroll = reroll, freeze = freeze},
            "Banish:" .. banish .. " Reroll:" .. reroll .. " Freeze:" .. freeze)
        if c.trustworthy == false then
            s = TF("readout.status.charges_estimated", {charges = s}, s .. " (estimated)")
        end
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

-- The card the current recommendation freezes: exactly one card that the
-- runtime marked as offering the Freeze target's Echo (card.freeze, display
-- metadata only, apart from the Take highlight that automation reads). None,
-- or several (the same Echo offered twice), gives nil, so no card is guessed.
function M.FreezeCard(cards)
    if type(cards) ~= "table" then return nil end
    local found
    for i = 1, math.min(#cards, 3) do
        local c = cards[i]
        if type(c) == "table" and c.freeze == true then
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
-- its text: the whole name it prints, the card's own quality (nil when
-- unknown, as CardLine then prints none) and the card's own spell id exactly
-- as the board gave it (nil when it gave none), by which the panel looks up
-- the offer's icon (Panel.OfferIcon).
function M.CardFacts(card)
    if type(card) ~= "table" then return nil end
    -- generated: the card had no name, so NameOf wrote its fallback; the
    -- display says that fallback through its key (DisplayName). The spell id
    -- beside a supplied name names nothing: `generated` alone decides that.
    local generated = card.name == nil and card.spellId ~= nil or nil
    return {name = NameOf(card), quality = QUALITY_NAMES[card.quality] and card.quality or nil,
        generated = generated, spellId = card.spellId}
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
-- The whole name and quality token CardTarget names, or nil.
local function TargetParts(text, facts)
    text = tostring(text or ""):gsub("^%[Guaranteed offer%] ", "")
    if type(facts) == "table" then
        local name, quality = LineFacts(text, facts)
        if quality then return name, quality end
        return nil
    end
    local first, _, quality = QualityToken(text)
    if not first or first <= 1 then return nil end
    return text:sub(1, first - 1), quality
end

function M.CardTarget(text, facts)
    local name, quality = TargetParts(text, facts)
    return name and (name .. " (" .. quality .. ")") or nil
end

-- An unstepped recommendation with its definite target named:
-- "<reason>: <Name (Quality)>". A stepped plan (numbered lines) already
-- names each step and is returned unchanged, as is a line with no target.
-- `facts` (optional): the card's own CardFacts, as CardTarget. The returned
-- text is display copy only (its quality word is the shown one).
function M.RecommendationWithTarget(recommendation, cardText, facts)
    local text = tostring(recommendation or "")
    if text:find("^%d+%. ") or text:find("\n%d+%. ") then return text end
    local name, quality = TargetParts(cardText, facts)
    if not name then return text end
    local target = TargetShown(DisplayName(name, facts), quality)
    if text == "" then return TF("readout.body.take_target", {target = target}, "Take: " .. target) end
    return TF("readout.body.recommendation_target", {recommendation = text, target = target},
        text .. ": " .. target)
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
-- ends in " (Rare)" (LineFacts). `freeze` (optional): this unmarked card is
-- the one the recommendation freezes (Readout.FreezeCard); its tag says
-- Freeze, never the pick, since the pick means Take. Text only; it decides
-- and chooses nothing.
-- -> {name, quality, tag, shown, full, marked, freeze, guaranteed}
-- The shown tags and notes below (OFFER_*_TAG, WAITING_OFFER_*, AUTO_ON_NOTE,
-- TOME_PARAGRAPH) are fields that Panel, the Auto warning and the tests read
-- when they draw. M holds none of them itself: each read comes through the
-- metatable at the end of this file and is resolved at that moment, so the
-- session's language applies without a caller change. Their code-owned marks
-- ("> ", "[...]", "... ") stay outside the translated words.

-- One offer card's parse of its CardLine text (the CardTarget rule; see
-- OfferCard): whether it is guaranteed, the body after that prefix, and the
-- whole name, quality token and rest when they are known.
local function ParseOfferLine(full, facts)
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
    return guaranteed, body, name, quality, rest
end

-- A CardLine text as shown: the same line with its guarantee marker and
-- quality word in the shown language. Only a line whose parse rebuilds the
-- exact text is re-rendered; any other line (and its annotation words, which
-- UserText owns) is kept as it is. Display only: never parse its result.
-- `facts` (optional): the card's own CardFacts.
function M.CardLineShown(text, facts)
    local full = tostring(text or "")
    local guaranteed, body, name, quality, rest = ParseOfferLine(full, facts)
    local shown = body
    if quality and name and rest and (name .. " (" .. quality .. ")" .. rest) == body then
        shown = TargetShown(DisplayName(name, facts), quality) .. rest
    elseif name and rest and (name .. rest) == body and DisplayName(name, facts) ~= name then
        shown = DisplayName(name, facts) .. rest
    end
    return (guaranteed and (GuaranteedShown() .. " ") or "") .. shown
end

function M.OfferCard(text, marked, auto, facts, freeze)
    local full = tostring(text or "")
    local guaranteed, body, name, quality, rest = ParseOfferLine(full, facts)
    -- `full` is the complete line for the card's hover: display copy.
    local card = {full = M.CardLineShown(full, facts), marked = marked == true, guaranteed = guaranteed}
    card.freeze = freeze == true and not card.marked
    local note
    local unknown = "? " .. T("readout.value.quality_unknown", "Quality unknown")
    if quality then
        card.name = DisplayName(name, facts)
        note = rest:gsub("^%s+", ""):gsub("%s+$", "")
        if note == "" then note = nil end
        local word = QualityShown(quality)
        if guaranteed and (card.marked or card.freeze) then
            word = TF("readout.value.quality_guaranteed", {quality = word}, word .. " - guaranteed")
        end
        card.quality = word
    elseif name then
        -- The card's own facts hold no quality: the whole name, and what
        -- follows it is its annotation.
        card.name = DisplayName(name, facts)
        note = rest:gsub("^%s+", ""):gsub("%s+$", "")
        if note == "" then note = nil end
        card.quality = unknown
    else
        card.name = body
        card.quality = unknown
    end
    if card.marked then
        card.tag = auto == false and M.OFFER_PICK_TAG or M.OFFER_RECOMMENDED_TAG
        card.shown = card.tag
    elseif card.freeze then
        card.tag = M.OFFER_FREEZE_TAG
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
    if auto == false then return T("readout.heading.offer_you_choose", "Current offer - you choose") end
    if auto == true then return T("readout.heading.offer_auto_on", "Current offer - Auto ON") end
    return T("readout.heading.offer", "Current offer")
end

-- The heading's forms, longest first, for a row that cannot hold the full
-- one: each still says whose choice the offer is ("you choose" or "Auto ON").
function M.OfferHeadingForms(auto)
    if auto == false then
        return {M.OfferHeading(false), T("readout.heading.offer_you_choose_short", "Offer - you choose"),
            T("readout.heading.you_choose", "You choose")}
    end
    if auto == true then
        return {M.OfferHeading(true), T("readout.heading.offer_auto_on_short", "Offer - Auto ON"),
            T("readout.heading.auto_on", "Auto ON")}
    end
    return {M.OfferHeading(nil), T("readout.heading.offer_short", "Offer")}
end

-- The waiting state (design "Waiting for Echo data"): the runtime's
-- "unsynced" hold. Nothing is chosen while it lasts, and it is never "0
-- offers". The short form is the heading. WAITING_OFFER_HEADING and
-- WAITING_OFFER_NOTE are shown fields (see SHOWN below).
function M.WaitingForOffer(reason) return reason == "unsynced" end

-- The Auto ON line under the offer (design "Auto ON, active"), from the
-- permissions AutomationScopeLines lists: choosing is Auto's, saving needs its
-- own permission, and Saved Builds and Orb runs are never Auto's. It is the
-- shown field AUTO_ON_NOTE (see SHOWN below).

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
-- The first line explains the abbreviations of the shown row, so it is
-- translated together with "readout.charge_counts" (the same letters); the
-- "?" and "~" marks are ChargesLine's own code-owned marks and stay here.
function M.ChargesLegend()
    return {
        T("readout.tooltip.charges_legend_letters", "B, R and F: the Banish, Reroll and Freeze charges left "
            .. "this run, as the game reported them when Nexus made its last decision."),
        "?: " .. T("readout.tooltip.charges_legend_unknown",
            "the game has not reported that count yet. It is unknown, not zero."),
        "~: " .. T("readout.tooltip.charges_legend_estimated", "estimated. The counts look like the "
            .. "placeholder the game sends without real counts, so they may be wrong."),
        T("readout.tooltip.charges_legend_auto",
            "Shown with Auto OFF, where you choose; with Auto ON Nexus uses these charges itself."),
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
    confirmed   = {glyph = "+",   word = "Confirmed", key = "readout.status.state_confirmed"},
    requested   = {glyph = ">",   word = "Request prepared", key = "readout.status.state_requested"},
    awaiting    = {glyph = "...", word = "Awaiting result", key = "readout.status.state_awaiting"},
    choice      = {glyph = ">",   word = "Waiting for choice", key = "readout.status.state_choice"},
    offer       = {glyph = "...", word = "Waiting for offer", key = "readout.status.state_offer"},
    paused      = {glyph = "=",   word = "Paused", key = "readout.status.state_paused"},
    unconfirmed = {glyph = "?",   word = "Unconfirmed", key = "readout.status.state_unconfirmed"},
    spendUnconfirmed = {glyph = "?", word = "Spend not confirmed", key = "readout.status.state_spend_unconfirmed"},
    notSent     = {glyph = "-",   word = "Not sent", key = "readout.status.state_not_sent"},
    sent        = {glyph = "->",  word = "Sent, not confirmed", key = "readout.status.state_sent"},
    stored      = {glyph = "*",   word = "Stored on this client", key = "readout.status.state_stored"},
    refused     = {glyph = "x",   word = "Refused", key = "readout.status.state_refused"},
    unavailable = {glyph = "!",   word = "Unavailable", key = "readout.status.state_unavailable"},
    estimated   = {glyph = "~",   word = "Estimated", key = "readout.status.state_estimated"},
    stale       = {glyph = "?",   word = "Stale", key = "readout.status.state_stale"},
    loading     = {glyph = "...", word = "Loading", key = "readout.status.state_loading"},
    ready       = {glyph = "+",   word = "Ready", key = "readout.status.state_ready"},
    unknown     = {glyph = "?",   word = "Unknown", key = "readout.status.state_unknown"},
}
M.STATUS_KINDS = {"confirmed", "requested", "awaiting", "choice", "offer", "paused", "unconfirmed", "spendUnconfirmed", "notSent",
    "sent", "stored", "refused", "unavailable", "estimated", "stale", "loading", "ready", "unknown"}

-- {kind, glyph, word} for a kind (a new table; changing it changes nothing
-- here). An unlisted kind is "unknown". (M.Status above is the panel's
-- status sentence, a different builder.)
function M.StatusParts(kind)
    local entry = type(kind) == "string" and STATUS[kind] or nil
    if not entry then kind, entry = "unknown", STATUS.unknown end
    -- The word is display copy in the shown language; the kind and glyph
    -- are code-owned. OrbHistory.RESULTS holds the same English words as
    -- its own labels (orb family); both must say the same state.
    return {kind = kind, glyph = entry.glyph, word = T(entry.key, entry.word)}
end

-- "<glyph> <word>", or "<glyph> <word>: <detail>" with a nonempty detail.
function M.StatusText(kind, detail)
    local s = M.StatusParts(kind)
    if detail ~= nil and tostring(detail) ~= "" then
        local words = s.word .. ": " .. tostring(detail)
        return s.glyph .. " " .. TF("readout.status.state_with_detail",
            {state = s.word, detail = tostring(detail)}, words)
    end
    return s.glyph .. " " .. s.word
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
-- player wording of UserText. Text only; it changes no gate. The raw reason
-- is only the lookup input here; it is never translated or matched again.
local HOLD_TEXT = {
    ["manual mode"] = {"readout.status.hold_manual", "Auto is OFF: Nexus only recommends."},
    ["loading screen (waiting for world entry)"] = {"readout.status.hold_loading_screen", "A loading screen is "
        .. "in progress; Nexus waits until you are in the world."},
    ["settling after world entry"] = {"readout.status.hold_settling",
        "Nexus waits a few seconds after a loading screen before it acts."},
    ["user acting"] = {"readout.status.hold_user_acting", "You made an Echo choice in the game's window; Nexus "
        .. "waits about 3 seconds before it acts again."},
    ["Another Echo automation addon is loaded -- disable it"] = {"readout.status.hold_other_addon", "Another Echo "
        .. "automation addon is loaded; Nexus does not act while it is enabled. Disable that addon to let Nexus act."},
    ["client auto-accept re-enabled"] = {"readout.status.hold_client_auto_accept", "The game's own option to "
        .. "accept loadout Echoes automatically is on; Nexus does not act while it is on. Turn it off in the "
        .. "game's options."},
}
function M.AutoHoldText(reason)
    local s = tostring(reason or "")
    local entry = HOLD_TEXT[s]
    if entry then return T(entry[1], entry[2]) end
    local text = Nexus.UserText and Nexus.UserText.Message
    return type(text) == "function" and text(s) or s
end

-- What the player can do about a hold, for the same reasons. A reason whose
-- own text already says what to do (an unresolved action across a loading
-- screen) gets none. Text only.
local HINT_BY_ITSELF = {"readout.status.help_continues", "What helps: nothing; it continues by itself."}
local HELP_HINT = {
    ["loading screen (waiting for world entry)"] = HINT_BY_ITSELF,
    ["settling after world entry"] = HINT_BY_ITSELF,
    ["user acting"] = {"readout.status.help_wait_without_choosing",
        "What helps: wait without choosing; it continues by itself."},
    ["Another Echo automation addon is loaded -- disable it"] = {"readout.status.help_disable_addon",
        "What helps: disable the other addon in the AddOns list at character selection."},
    ["client auto-accept re-enabled"] = {"readout.status.help_client_auto_accept",
        "What helps: turn off the game's option to accept loadout Echoes automatically."},
}
function M.AutoHelpHint(reason)
    local s = tostring(reason or "")
    local entry = HELP_HINT[s]
    if entry then return T(entry[1], entry[2]) end
    if s == "" or s == "manual mode" or s:find("no confirmed result for", 1, true) then return nil end
    if s:find("Orb", 1, true) or s:find("orb", 1, true) then
        return T("readout.status.help_orb", "What helps: finish, pause or stop the Orb run in Orbs (... menu), "
            .. "or wait until Nexus can read the Orb state.")
    end
    return T("readout.status.help_point_auto", "What helps: point at the Auto button for details.")
end

-- The inline line for a selected Auto that is not acting: the plain reason
-- and, when there is one, what helps.
function M.AutoHoldNote(reason)
    if M.WaitingForOffer(reason) then return M.WAITING_OFFER_NOTE end
    local hint = M.AutoHelpHint(reason)
    local text = M.AutoHoldText(reason)
    if hint then
        return TF("readout.status.paused_with_hint", {reason = text, hint = hint},
            "Paused: " .. text .. " " .. hint)
    end
    return TF("readout.status.paused_reason", {reason = text}, "Paused: " .. text)
end

-- The inline line for an Auto click that left Auto OFF without opening the
-- warning. `kind`: "orb" (an Orb operation blocks ordinary Automation),
-- "warning" (the warning is unavailable), else the runtime's status line.
function M.AutoRefusalText(kind, status)
    if kind == "orb" then
        return T("readout.status.auto_refused_orb", "Auto stayed OFF: an Orb run is active or unresolved. "
            .. "What helps: finish or stop it in Orbs (... menu, Orbs / Lost Memories).")
    elseif kind == "warning" then
        local command = "/nexus report"
        return TF("readout.status.auto_refused_warning", {command = command}, "Auto stayed OFF: its overwrite "
            .. "warning is unavailable, and Auto never turns ON without it. What helps: type " .. command
            .. " and report it.")
    end
    local s = tostring(status or "")
    if s == "" then
        return T("readout.status.auto_refused", "Auto stayed OFF. What helps: point at the Auto button for details.")
    end
    return TF("readout.status.auto_refused_status", {status = s}, "Auto stayed OFF: " .. s)
end

-- The Automation scope in plain lines, from facts the caller read without
-- acting: `selected` (the session's Auto selection), `held` (why it is not
-- acting, if it is not), `settings` (Store.Settings) and `readOnly` (saved
-- data is read-only). Each line names a permission the runtime actually
-- gates on, its current value and the existing control that changes it.
-- Reading it changes nothing. Setting names (autoPick ...) and slash
-- commands are code-owned slot values, never translated.
-- How each gate reads a permission that was never saved: Reroll and Freeze
-- are blocked only by a saved false; every other gate needs a saved true.
local UNSET_ACTS_ON = {autoReroll = true, autoFreeze = true}
local function OnOff(settings, key, raw)
    -- Not `settings[key] or nil`: that turns a saved false into "not set".
    local value
    if type(settings) == "table" then value = settings[key] end
    if value == true then return T("readout.value.setting_on", "on") end
    if value == false then return T("readout.value.setting_off", "off") end
    if raw then return T("readout.value.setting_not_set", "not set") end
    if UNSET_ACTS_ON[key] then return T("readout.value.setting_unset_acts_on", "not set (acts as on)") end
    return T("readout.value.setting_unset_acts_off", "not set (acts as off)")
end
-- One permission line: `key` its template over the saved setting name, its
-- shown value and (for two lines) the slash command; `english` the legacy
-- line built from the same values.
local function Permission(key, setting, value, english, command)
    return TF(key, {setting = setting, value = value, command = command}, english)
end
function M.AutomationScopeLines(facts)
    facts = type(facts) == "table" and facts or {}
    local s = facts.settings
    local lines = {}
    lines[#lines + 1] = facts.selected
        and T("readout.body.scope_auto_on", "Auto: ON for this session. The selection is OFF again after every "
            .. "login or reload.")
        or T("readout.body.scope_auto_off", "Auto: OFF. Nexus only recommends; it takes, banishes, rerolls, "
            .. "freezes, saves and locks nothing.")
    if facts.selected and facts.held then
        local held = M.AutoHoldText(facts.held)
        lines[#lines + 1] = TF("readout.body.scope_paused_because", {reason = held}, "Paused because: " .. held)
    end
    lines[#lines + 1] = T("readout.body.scope_intro", "With Auto ON, Nexus may only do what these permissions allow:")
    local v = OnOff(s, "autoPick")
    lines[#lines + 1] = "- " .. Permission("readout.body.scope_take", "autoPick", v,
        "Take needed Echoes (autoPick): " .. v)
    v = OnOff(s, "autoPickLeveling")
    -- Its rule and limits are two reviewed texts passed as text slots (as the
    -- shown OnOff word is), so each part stays within the single-line contract.
    lines[#lines + 1] = "- " .. TF("readout.body.scope_random_roll", {value = v, command = "/nexus leveling on|off",
            rule = T("readout.body.scope_random_roll_rule", "with no Wishlist at levels 2-79 it takes the"
                .. " highest-rarity offer (first current offer on a tie), not a random one"),
            limits = T("readout.body.scope_random_roll_limits", "needs Auto ON and autoPick; no reroll or"
                .. " spending; no new pick at level 80")},
        "Random Roll: " .. v
        .. "; optional; with no Wishlist at levels 2-79 it takes the highest-rarity offer (first current"
        .. " offer on a tie), not a random one; needs Auto ON and autoPick; no reroll or spending; no new"
        .. " pick at level 80; change with /nexus leveling on|off")
    v = OnOff(s, "autoBanish")
    lines[#lines + 1] = "- " .. Permission("readout.body.scope_banish", "autoBanish", v, "Banish (autoBanish): " .. v)
    v = OnOff(s, "autoReroll")
    lines[#lines + 1] = "- " .. Permission("readout.body.scope_reroll", "autoReroll", v,
        "Reroll (autoReroll): " .. v .. "; change with /nexus reroll on|off", "/nexus reroll on|off")
    v = OnOff(s, "autoFreeze")
    lines[#lines + 1] = "- " .. Permission("readout.body.scope_freeze", "autoFreeze", v,
        "Freeze (autoFreeze): " .. v .. "; change with /nexus freeze on|off", "/nexus freeze on|off")
    v = OnOff(s, "autoDisable")
    lines[#lines + 1] = "- " .. Permission("readout.body.scope_tomes", "autoDisable", v,
        "Echo availability controls (tomes) (autoDisable): " .. v
        .. "; disables off-Wishlist and re-enables Wishlist controls")
    v = OnOff(s, "autoSave")
    lines[#lines + 1] = "- " .. Permission("readout.body.scope_save", "autoSave", v,
        "Save a better finished level-80 run over the active Saved Build (autoSave): " .. v
        .. "; no in-game control, and Auto OFF stops it")
    v = OnOff(s, "autoLockEchoes")
    lines[#lines + 1] = "- " .. Permission("readout.body.scope_lock", "autoLockEchoes", v,
        "Lock Wishlist Echoes into locked slots (autoLockEchoes): " .. v .. "; its own option in the Wishlist editor")
    v = OnOff(s, "autoActivate", true)
    lines[#lines + 1] = "- " .. Permission("readout.body.scope_activate", "autoActivate", v,
        "Activate a Saved Build: never. Nexus does not activate or load Saved Builds; the saved autoActivate value ("
        .. v .. ") is not used by any action.")
    lines[#lines + 1] = "- " .. T("readout.body.scope_orbs",
        "Orb runs: never by Auto; each one needs its own approval in the Orb window.")
    if facts.readOnly then
        lines[#lines + 1] = T("readout.body.scope_read_only", "Saved data is read-only: a permission counts as on "
            .. "only when it was saved as on, and a change lasts this session only.")
    end
    return lines
end

-- What the tome permission (autoDisable) does, from AutomationRuntime StepArm:
-- with Auto acting it turns off tomes the Wishlist does not use and turns
-- needed ones back on; nothing turns them back on when Auto stops. Shared by
-- the Auto warning; Help carries the same paragraph. It is the shown field
-- TOME_PARAGRAPH (see SHOWN below).

-- The rows of the Automation settings menu, from facts the caller read
-- without acting (as AutomationScopeLines). Each row: `text`; `kind` "title",
-- "info" (shown, not changeable here), "toggle" (`checked` is the current
-- value; `command` is present for toggles backed by an existing /nexus setter),
-- "editor" (the option lives in the Wishlist editor) or "help". Pure. `text`
-- is display copy; `kind`, `key` and `command` are the row's identity.
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
    Add("title", T("readout.menu.auto_settings_title", "Automation settings"))
    Add("info", facts.selected and T("readout.menu.auto_selected_on", "Auto: ON for this session (the Auto button "
        .. "turns it OFF)") or T("readout.menu.auto_selected_off", "Auto: OFF (the Auto button turns it ON after "
        .. "its warning)"))
    -- The two permissions that have an in-game setter (/nexus reroll|freeze).
    for _, item in ipairs({{"autoReroll", "Allow Reroll", "reroll", "readout.menu.allow_reroll"},
        {"autoFreeze", "Allow Freeze", "freeze", "readout.menu.allow_freeze"}}) do
        local on = Value(item[1]) ~= false
        local v = OnOff(s, item[1])
        Add("toggle", Permission(item[4], item[1], v, item[2] .. " (" .. item[1] .. "): " .. v),
            {key = item[1], checked = on, command = item[3] .. (on and " off" or " on")})
    end
    -- The optional leveling pick: off unless saved exactly on. Its caption is
    -- shown through its own key over the shown value and its two reviewed
    -- detail texts (text slots); the English is the legacy row.
    do
        local on = Value("autoPickLeveling") == true
        local lv = OnOff(s, "autoPickLeveling")
        Add("toggle", TF("readout.menu.random_roll", {value = lv,
                rule = T("readout.menu.random_roll_rule", "no Wishlist, levels 2-79: takes the highest-rarity"
                    .. " offer (first current offer on a tie)"),
                limits = T("readout.menu.random_roll_limits", "needs Auto ON and autoPick; optional, off by"
                    .. " default; no new pick at 80; no reroll or spending")},
            "Random Roll: " .. lv
            .. "; no Wishlist, levels 2-79: takes the highest-rarity offer (first current offer on a tie);"
            .. " needs Auto ON and autoPick; optional, off by default; no new pick at 80; no reroll or spending"),
            {key = "autoPickLeveling", checked = on, command = on and "leveling off" or "leveling on"})
    end
    local v = OnOff(s, "autoPick")
    Add("info", Permission("readout.menu.take_needed", "autoPick", v,
        "Take needed Echoes (autoPick): " .. v .. "; no in-game switch"))
    v = OnOff(s, "autoBanish")
    Add("info", Permission("readout.menu.banish", "autoBanish", v, "Banish (autoBanish): " .. v .. "; no in-game switch"))
    Add("toggle", T("readout.menu.auto_manage_tomes", "Auto-manage Tome Echoes"),
        {key = "autoDisable", checked = not not Value("autoDisable")})
    v = OnOff(s, "autoSave")
    Add("info", Permission("readout.menu.save_run", "autoSave", v,
        "Save a better finished run over the active Saved Build (autoSave): " .. v
        .. "; no in-game switch; Auto OFF stops it"))
    v = OnOff(s, "autoLockEchoes")
    Add("editor", Permission("readout.menu.lock_echoes", "autoLockEchoes", v,
        "Lock Wishlist Echoes (autoLockEchoes): " .. v .. "; set in the Wishlist Editor..."), {key = "autoLockEchoes"})
    Add("info", TF("readout.menu.activate_never", {setting = "autoActivate"},
        "Activate a Saved Build: never (the saved autoActivate value is not used)"))
    Add("info", T("readout.menu.orb_never", "Orb runs: never by Auto; each needs its own approval in Orbs"))
    if facts.readOnly then
        Add("info", T("readout.menu.read_only", "Saved data is read-only: a change lasts this session only"))
    end
    -- The manual's Auto page, named Reference (Help is the guided coach).
    Add("help", T("readout.menu.auto_reference", "What Auto may do (Reference)..."))
    return rows
end

-- Next n predicted guaranteed arrivals, "(predicted)" suffixed --
-- injection order is measured but not version-stable, never state it
-- as fact. queue = Ratchet.PredictQueue output (entries pre-bridged).
-- The wanted and the plain form are two keys, chosen here as before.
function M.QueueLines(queue, n)
    local out = {}
    if type(queue) ~= "table" then return out end
    local entries = queue.entries
    if type(entries) ~= "table" then return out end
    local limit = tonumber(n) or 3
    for i = 1, math.min(#entries, limit) do
        local e = entries[i]
        if type(e) == "table" then
            local index, name = string.format("%d", i), ShownNameOf(e)
            if e.wanted then
                out[#out + 1] = TF("readout.value.queue_wanted", {index = index, name = name},
                    index .. ". " .. name .. " [wanted] (predicted)")
            else
                out[#out + 1] = TF("readout.value.queue_entry", {index = index, name = name},
                    index .. ". " .. name .. " (predicted)")
            end
        end
    end
    return out
end

-- The shown fields (see the note above OfferCard): a code-owned mark, the
-- key and its English words, and a code-owned closing mark. M holds none of
-- these names, so each read resolves here, in the session's language.
local SHOWN = {
    OFFER_PICK_TAG = {"> ", "readout.label.offer_pick", "Wishlist pick", ""},
    OFFER_RECOMMENDED_TAG = {"> ", "readout.label.offer_recommended", "Recommended", ""},
    OFFER_FREEZE_TAG = {"> ", "readout.label.offer_freeze", "Freeze", ""},
    OFFER_GUARANTEED_TAG = {"[", "readout.label.guaranteed_offer", "Guaranteed offer", "]"},
    WAITING_OFFER_HEADING = {"... ", "readout.heading.waiting_offer_data", "Waiting for offer data", ""},
    WAITING_OFFER_NOTE = {"... ", "readout.note.waiting_offer_data", "Waiting for current Echo data. "
        .. "Recommendations and automatic choices resume once the offer is read. Nothing is chosen meanwhile.", ""},
    AUTO_ON_NOTE = {"", "readout.note.auto_on_scope", "Auto may choose offers and, if its save permission is on, "
        .. "save a better finished run over this Saved Build. It never loads a build or starts Orbs.", ""},
    TOME_PARAGRAPH = {"", "readout.body.tome_permission", "Tomes: with Auto ON and the tome permission "
        .. "(autoDisable) on, once the game's tome data is ready Nexus turns off Echo tomes your Wishlist does not "
        .. "use and turns back on tomes it needs, one change about every half second. It never turns off a tome you "
        .. "opted out of. Nexus does not turn tomes back on when you turn Auto OFF, log out or change the Wishlist: "
        .. "it turns back on only tomes a Wishlist needs (or that you opted out of), and only while Auto is ON. The "
        .. "tome list in the Echo Journal shows their state.", ""},
}
setmetatable(M, {__index = function(_, name)
    local entry = SHOWN[name]
    if entry then return entry[1] .. T(entry[2], entry[3]) .. entry[4] end
    return nil
end})

------------------------------------------------------------------------
-- Auto-pick by rarity: the optional leveling pick (settings.autoPickLeveling,
-- "Random Roll" in Options and /nexus leveling) offered in Plan as the
-- alternative to a Wishlist. Words only: nothing here reads a setting, an
-- assignment or the runtime, and nothing here grants or starts anything.
-- English only for now: these sentences have no reviewed catalog key (the
-- catalog is a few entries under its 4096 cap; only the Plan button, the
-- chooser row and the Play line are keys), so translations are deferred and
-- a session in another language shows them in English.
------------------------------------------------------------------------
local RARITY = {
    name = "Auto-pick by rarity",
    rule = "Used instead of a Wishlist: at levels 2 to 79, Auto takes the highest-rarity Echo of an ordinary "
        .. "level-up offer, the first current offer on a tie. It is not random (Options calls it Random Roll). "
        .. "It never rerolls, banishes, freezes, spends, saves or uses Orbs.",
    -- state = {short words for the Wishlist line, the whole reason}
    states = {
        off = {"off", "Not selected."},
        running = {"ON", "Running: Auto is ON and takes the next eligible offer. Press Auto to stop."},
        assigned = {"not in use", "Not in use: a Wishlist is assigned here, so that Wishlist is followed."},
        unknown = {"not known", "Not in use yet: Nexus does not know whether a Wishlist is assigned here, and assumes nothing."},
        level = {"levels 2-79 only", "Selected, not running: it picks only at levels 2 to 79."},
        no_permission = {"autoPick off", "Selected, not running: the autoPick permission is off, and Nexus does not turn it on for you."},
        paused = {"paused", "Selected, not running: Nexus is paused for this session."},
        auto_off = {"Auto OFF", "Selected, not running: Auto is OFF. Press Auto on the main panel to start it; selecting this never starts Auto."},
        waiting = {"waiting", "Selected and Auto is ON, but it is not picking right now (waiting or on hold)."},
    },
    text = {
        popup_unassign = "Stop using '{wishlist}' on {target} and auto-pick by rarity instead?",
        popup_keep = "The Wishlist stays saved; only this assignment is removed. No other Saved Build changes.",
        popup_select = "Use auto-pick by rarity on {target}? No Wishlist is assigned there.",
        popup_auto_off = "This does not start Auto. Press Auto on the main panel when you want it to pick.",
        popup_auto_on = "Auto is ON: choosing this turns Auto OFF. Press Auto again when you want it to pick by rarity.",
        button_confirm = "Use auto-pick",
        button_cancel = "Cancel",
        target_saved_build = "Saved Build '{name}' (slot {slot})",
        target_slot = "Saved Build slot {slot}",
        target_first_run = "your first run (no Saved Build in use)",
        target_unknown = "the current Saved Build",
        chat_selected = "Auto-pick by rarity is selected for {target}. {status}",
        chat_deselected = "Auto-pick by rarity is turned off. Nothing was assigned or unassigned.",
        chat_unknown = "Nothing was changed: Nexus cannot confirm right now whether a Wishlist is assigned to {target} "
            .. "({reason}). Try again when it has loaded, or use Unassign Wishlist in the Echo Journal.",
        chat_changed = "Nothing was changed: the Saved Build or its assignment changed while the question was open. "
            .. "Check it and choose again.",
        chat_owner_changed = "Nothing was changed: this character's saved data changed after you were asked.",
        chat_write_failed = "Nothing was changed: the assignment could not be removed.",
        chat_option_failed = "Auto-pick by rarity could not be turned on. Turn Random Roll on in Options.",
        chat_option_failed_removed = "The assignment was removed, but auto-pick by rarity could not be turned on. "
            .. "Turn Random Roll on in Options.",
        chat_auto_stopped = "Auto was turned OFF. Press Auto when you want it to pick.",
        chat_auto_not_stopped = "Nothing was changed: Auto could not be turned OFF, so auto-pick by rarity was not selected.",
        chat_pending_save = "Nothing was changed: finish or cancel the pending Save first.",
        chat_unconfirmed = "The assignment was removed. Nexus is still waiting to confirm that no Wishlist is assigned to {target}.",
        chat_consent_unavailable = "Nothing was changed: the confirmation could not be shown.",
        tip_heading = "Use auto-pick instead of a Wishlist",
        tip_select = "Click to select it for {target}. It asks before it removes an assignment, and it never starts Auto.",
        tip_deselect = "Click to turn it off. Nothing is assigned or unassigned.",
        reason_loading = "still loading",
        reason_restoring = "restoring",
        reason_unavailable = "temporarily unavailable",
        reason_empty_slot = "this Saved Build holds no Echoes",
        reason_first_run_plan = "this Saved Build follows the first-run plan",
        reason_first_run_plan_pending = "a first-run plan is stored and would be assigned here in its place",
        reason_no_saved_build = "no Saved Build is selected",
        reason_owner = "the character is not known",
        reason_not_confirmed = "not confirmed",
        reason_unreadable = "not readable",
    },
}

-- The state of the mode from facts the caller read (all optional, anything
-- but the exact value counts as absent): `option` the setting exactly true,
-- `running` the runtime's own display fact as the panel admits it
-- (Panel.RandomRollShown), `assignment` "unassigned" (positively known),
-- "assigned" or anything else for unknown, `levelOk`, `autoPick`,
-- `sessionPaused` and `auto` (selected ON). A selected option alone is never
-- "running": only the runtime's fact is. The first reason that keeps it from
-- picking is the one named, so "Auto OFF" is said only where pressing Auto
-- would start it. Returns {state, selected, running, name, short, reason,
-- rule}; `selected` is true only where the mode is what this destination uses.
function M.RarityMode(f)
    f = type(f) == "table" and f or {}
    local state
    if f.option ~= true then state = "off"
    elseif f.running == true then state = "running"
    elseif f.assignment == "assigned" then state = "assigned"
    elseif f.assignment ~= "unassigned" then state = "unknown"
    elseif f.levelOk ~= true then state = "level"
    elseif f.autoPick ~= true then state = "no_permission"
    elseif f.sessionPaused == true then state = "paused"
    elseif f.auto ~= true then state = "auto_off"
    else state = "waiting" end
    local words = RARITY.states[state]
    return {state = state, running = state == "running",
        selected = state ~= "off" and state ~= "assigned" and state ~= "unknown",
        name = RARITY.name, short = words[1], reason = words[2], rule = RARITY.rule}
end

-- One of the mode's sentences with its {slots} filled from `args` (values
-- the caller already made safe to show); an unknown id or reason code is
-- shown as it is, never as an empty line.
function M.RarityText(id, args)
    local text = RARITY.text[id]
    if type(text) ~= "string" then return tostring(id or "") end
    return (text:gsub("{(%w+)}", function(slot)
        local value = type(args) == "table" and args[slot] or nil
        return value ~= nil and tostring(value) or ""
    end))
end
