-- Player-facing terminology only. Stable policy/reason codes and protocol data
-- remain unchanged; diagnostics may retain original codes for support.
-- Issue #123/#142: five reasons resolve their English text through the
-- Nexus.Localization seam (localizedReasons below); every other text here is
-- unchanged.
Nexus=Nexus or {}
local T={};Nexus.UserText=T
local reasons={
    ["unsynced"]="Waiting for current Echo data from the server - automatic choices paused",
    ["waiting for owned-echo sync"]="Waiting for current Echo data from the server - automatic choices paused",
    ["waiting for owned-state sync"]="Waiting for current Echo data from the server - automatic choices paused",
    ["no wishlist set - advisor only"]="No Wishlist assigned - recommendations only",
    ["no wishlist"]="Assign a Wishlist to use its targets",
    ["pending-pick count"]="Waiting for the remaining-choice count",
    ["Orb state active or unknown"]="Ordinary rolling paused while the Orb choice is active or cannot be confirmed",
    ["orb state not yet known"]="Ordinary rolling paused: the server's Orb state is not confirmed yet",
    ["orb state unknown"]="Ordinary rolling paused: the game's Orb state could not be read",
    ["orb state unavailable"]="Ordinary rolling paused: the game's Orb service does not expose its pending-offer state",
    ["orb state capability missing"]="Ordinary rolling paused: the game's Orb service does not report whether its state is known, so Nexus cannot confirm that no Orb choice is open",
    ["Orb offer active -- manual action required"]="An Orb offer is active; use Orb mode or resolve it in the game",
    ["Take wanted Echo (EchoWeaver)"]="Take a needed Echo",
    ["Take available Echo (EchoWeaver)"]="Take an available Echo",
    ["Freeze wanted Echo before search (EchoWeaver)"]="Freeze a needed Echo before searching for another target",
    ["Banish to find Wishlist targets (EchoWeaver)"]="Banish to find Wishlist targets",
    ["Reroll: no requested Echo on board (EchoWeaver)"]="Reroll: no requested Echo on board",
    ["Reroll: no needed Echo on board (EchoWeaver)"]="Reroll: no Echo on this board is still needed",
    ["Take available filler (EchoWeaver)"]="Take an available Echo outside the Wishlist",
    ["Take filler; search unavailable (EchoWeaver)"]="Take an Echo outside the Wishlist; no permitted Banish or Reroll action",
    ["Wishlist complete; take filler (EchoWeaver)"]="Wishlist complete; take an Echo outside the Wishlist",
    ["Take wanted Echo"]="Take a needed Echo",
    ["invalid wishlist"]="This Wishlist cannot be used yet. Open it in the editor to check its targets",
    ["invalid loadout"]="This Saved Build is unavailable or not valid for this action. Check My Builds",
    ["ROOT_PENDING"]="The build library is still being prepared",
    ["SOURCE_KEY_WIDTH_EXCEEDED"]="A saved record has an unsupported long key. Keep your backup and report this code",
    ["preparing"]="Preparing shared-build data",
    ["cleaning"]="Removing expired requests",
    ["throttled"]="Waiting for the permitted network send rate",
    ["armed (guaranteed queue live)"]="The server marked a current offer guaranteed; no future offer is assumed",
    ["Activate did not guarantee -- treating as unarmed"]="No guaranteed offer was shown after activation; no future guarantee is assumed",
    ["bracket fishing: reroll filler guarantee"]="Reroll the unneeded guaranteed offer under the enabled policy",
    ["tight horizon"]="Few selections remain",
    ["drain guaranteed queue"]="Use the offer shown on this board; no future offer is assumed",
    ["Tome levers"]="Echo availability controls",
    ["flag demotions cleared (they re-arm on fresh evidence)"]="Temporary safety-assumption disablements cleared; new evidence can disable them again",
}
-- Reasons whose English text comes from Nexus.Localization (issue #123). The
-- raw reason stays the lookup key and is never rewritten; the value is the
-- stable semantic key of its reviewed text (data/LocalizationEnglish.lua).
local localizedReasons={
    ["ROOT_MUTATION_PENDING"]="reason.save_in_progress",
    ["CURSOR_REQUIRED"]="reason.list_preparing",
    ["STORE_PENDING"]="reason.saved_data_reading",
    -- Issue #142: the two planner wait reasons. The older "pending-pick count"
    -- mapping above is a different reason and stays as it is.
    ["waiting for three-card board"]="reason.wait_three_choices",
    ["waiting for pending-pick count"]="reason.wait_pending_pick_count",
}
-- Without the seam, the two wait reasons keep the exact English they showed
-- before they moved to it (issue #142).
local legacyWaitText={
    ["waiting for three-card board"]="Waiting for the next three Echo choices",
    ["waiting for pending-pick count"]="waiting for pending-pick count",
}
local function availabilityName(id)
    local a=Nexus.GameAdapter
    local catalog=a and a.Catalog and a.Catalog()
    local lever=catalog and catalog.levers and catalog.levers[tonumber(id)]
    local name=lever and lever.tomeName
    return name and (tostring(name).." (control #"..id..")") or ("Echo-availability control #"..id)
end
-- One of those reasons through the seam. When the seam has no reviewed text
-- for the key it returns its documented safe status and the raw code is kept
-- as the support detail; without the seam the reason reads like any other
-- unrecognized code (the generic line in T.Message below).
local function LocalizedReason(key,code)
    local localization=Nexus.Localization
    if type(localization)=="table" and type(localization.Text)=="function" then
        local text,source=localization.Text(key)
        if type(text)=="string" and text~="" then
            if source=="unavailable" then return text.." "..T.Details(code) end
            -- Only an actual validated base/candidate result carries this
            -- presentation provenance. Arbitrary raw strings never do.
            return text, (source=="base" or source=="candidate")
                and type(localization.IsText)=="function" and localization.IsText(text)==true
        end
    end
    if legacyWaitText[code] then return legacyWaitText[code] end -- issue #142, seam absent
    return "This action is not available yet. Check the status or diagnostics. Details: "..code
end
function T.Message(value)
    local s=tostring(value or "")
    if reasons[s] then return reasons[s] end
    if localizedReasons[s] then return LocalizedReason(localizedReasons[s],s) end
    local prefix,body=s:match("^(L%d+ %-%- )(.*)$")
    if prefix then
        local text,localized=T.Message(body)
        local combined=prefix..text
        local localization=Nexus.Localization
        return combined, localized==true and type(localization)=="table"
            and type(localization.IsText)=="function" and localization.IsText(combined)==true
    end
    body=s:match("^waiting: (.*)$")
    if body then return T.Message(body) end
    local id=s:match("^disabling off%-wishlist tome lever (%d+)$")
    if id then return "Disabling off-Wishlist "..availabilityName(id) end
    id=s:match("^re%-enabling wishlist tome lever (%d+)$")
    if id then return "Enabling Wishlist "..availabilityName(id) end
    local detail
    id,detail=s:match("^lever (%d+): (.*)$")
    if id then return availabilityName(id)..": "..detail:gsub("non%-conformant data","unsupported availability data") end
    if s:find("locked roles remain unknown",1,true) or s:find("awaiting authoritative lock evidence",1,true)
        or s:find("waiting for authoritative locked%-Echo evidence") then
        return "Choose this Wishlist's locked Echo targets in the editor. Your planned build does not have to match the equipped build. Details: "..s
    end
    if s:find("waiting for synchronized permanent locked%-Echo evidence") then
        return "Waiting for the server's current locked Echo list. Details: "..s
    end
    if s:find("waiting for the server mirror",1,true) then
        return "The saved Wishlist is not available from the server yet. Details: "..s
    end
    if s:find("payload changed",1,true) or s:find("preview is stale",1,true) then
        return "This draft changed. Reopen it and review the current targets before saving. Details: "..s
    end
    local lost,gain,fewer=s:match("exact wishlist progress regressed (%d+) %(gained (%d+), shed (%d+) exact stacks%)")
    if lost then return "Not saved: this run matches "..lost.." fewer Wishlist copies ("..gain.." gained, "..fewer.." fewer than the saved build)." end
    if s:find("cleanup-only save added new excess/wrong-quality pollution",1,true) then
        return "Not saved: this run adds excess or wrong-quality copies compared with the saved build."
    end
    if s:find("no net gain",1,true) then return "Not saved: no additional matching Wishlist copies were confirmed." end
    if s:find("coverage lost:",1,true) then return "Not saved: some previously matched Wishlist targets would be lost. See diagnostics for the exact targets." end
    if s:match("^[A-Z][A-Z0-9_]+$") then return "This action is not available yet. Check the status or diagnostics. Details: "..s end
    s=s:gsub("Take wanted Echo %(EchoWeaver%)","Take a needed Echo")
        :gsub("Wishlist identity found; ","")
        :gsub("TARGET:","WISHLIST:")
        :gsub("OWNED this run:","Rolled Echoes this run:")
        :gsub(" %(synced%)"," (server confirmed)")
        :gsub(" %(not synced yet%)"," (waiting for current Echo data from the server)")
        :gsub("UNARMED","No guaranteed offer observed")
        :gsub("ARMED","Guaranteed current offer observed; no future offer is assumed")
         :gsub("tight horizon","few selections remain")
        :gsub("bracket fishing","searching with the enabled Banish/Reroll actions")
        :gsub("tome lever ","Echo-availability control #")
        :gsub("search unavailable","no permitted Banish or Reroll action")
        :gsub("before search","before searching for another target")
        :gsub("waiting for owned%-echo sync","waiting for current Echo data from the server")
    return s
end
function T.Annotation(value)
    return ({wanted="Needed",["returns later"]="Not taken now; a later offer is not guaranteed",
        banked="Held offer",filler="Not on Wishlist",["low quality"]="Different quality from target",
        ["target met"]="Target already met",["wrong quality"]="Different quality from target",
        -- EchoWeaver's own words for the same states.
        ["target satisfied"]="Target already met",frozen="Frozen offer"})[value] or T.Message(value)
end
function T.Details(code) return "Details: "..tostring(code or "unknown") end

------------------------------------------------------------------------
-- M4 (UX-04/13/14/15): shared player-facing presentation of destinations,
-- counts, record scope and terms. Every function below is a pure function of
-- the facts its caller already holds: it reads no state, calls no service,
-- writes nothing and schedules nothing. An unknown is said as unknown or
-- unavailable, never as 0, and a planned or partial state is never called
-- complete. Names pass through the existing display sanitizer (UTF-8 safe).
------------------------------------------------------------------------

-- A whole, finite, non-negative number, else nil (unknown).
local function Whole(value)
    value = tonumber(value)
    if value and value == value and value >= 0 and value < math.huge then
        return math.floor(value)
    end
    return nil
end

-- Cut at a character boundary (UTF-8 lead bytes), never inside a letter.
local function Utf8Cut(text, maxChars)
    maxChars = tonumber(maxChars)
    if not maxChars or maxChars < 1 then return text end
    local count, index, length = 0, 1, #text
    while index <= length do
        local byte = text:byte(index)
        local width = (byte < 0xC0 and 1) or (byte < 0xE0 and 2) or (byte < 0xF0 and 3) or 4
        count = count + 1
        if count > maxChars then return text:sub(1, index - 1) .. "..." end
        index = index + width
    end
    return text
end

-- A name as it may be shown (the existing display sanitizer), optionally
-- shortened at a character boundary; nil when there is nothing to show.
function T.SafeName(value, maxChars)
    if value == nil then return nil end
    local text = tostring(value)
    local identity = Nexus.Identity
    if identity and type(identity.DisplaySafeText) == "function" then
        local ok, shown = pcall(identity.DisplaySafeText, text, 1024, false)
        text = ok and shown or nil
    end
    if type(text) ~= "string" or text == "" then return nil end
    return Utf8Cut(text, maxChars)
end

-- "Saved Build 'Fire PvE' (slot 2)", "Saved Build 2" or nil.
function T.SavedBuildLabel(slot, name, maxChars)
    slot = Whole(slot)
    local shown = T.SafeName(name, maxChars)
    if slot and slot >= 1 then
        return shown and ("Saved Build '" .. shown .. "' (slot " .. slot .. ")")
            or ("Saved Build " .. slot)
    end
    return shown and ("Saved Build '" .. shown .. "'") or nil
end

-- Shared wording of the destination descriptor documented below, used by
-- both DestinationLines and DestinationFields so that they cannot disagree.
-- Pure: these only word the facts they are given.
local SAVED_BUILD_STATE_WORDS = {
    unavailable = "not available right now",
    empty = "empty: it holds no Echoes, so assigning to it is refused",
    active = "active in the game",
    inactive = "not active in the game",
    unconfirmed = "not confirmed as the active Saved Build",
}
-- The other destinations: their Saved Build cell and destination words.
local DESTINATION_WORDS = {
    firstRun = {build = "none in use", state = "first-run target (no Saved Build in use)"},
    restoring = {build = "not known yet", state = "not known yet (the saved assignment is being restored)"},
    unknown = {build = "not loaded yet", state = "Saved Build data is not loaded yet"},
    unconfirmed = {build = "not confirmed right now", state = "not confirmed right now"},
    none = {build = "none captured", state = "none captured"},
}
local WISHLIST_STATES = {assigned = true, unassigned = true, unavailable = true, restoring = true}

-- Compact alternatives (DestinationFields only). Display metadata: the value
-- and tooltip stay the authoritative disclosure and grant no assignment.
-- compact is a complete shorter value (a bare name stays whole); the state
-- and Wishlist cells' minimum is their shortest atomic alternative, for a
-- cell too narrow for compact. Both are chosen from the descriptor codes,
-- never cut from or parsed out of the worded value, and a state label is
-- shown whole. A Wishlist meaning word precedes its name, so a shortened name
-- never reads as assigned; only an assigned Wishlist shows its name alone.
-- A Wishlist minimum is that assigned name, else its meaning marker alone.
-- Compressed markers (each disclosed in full by the tooltip):
--   "?"        not known or not confirmed (never unassigned, first-run or active)
--   "#2 Name"  Saved Build slot 2, then its name
--   "On"/"Off" the Saved Build is / is not active in the game
--   "N/A"      unavailable right now
--   "Empty"    the Saved Build holds no Echoes, so any assignment is refused
--   "1st"      first-run target (no Saved Build in use)
--   "Wait"     the saved assignment is being restored
--   "None"     nothing captured
--   "P"        Preview (d.preview): a Community Build preview is shown
-- One-glyph marks, for a captured or Preview state (state) and for a
-- Wishlist minimum without a shown name (Wishlist); "?" keeps the meaning
-- above:
--   "+"  state: active in the game      Wishlist: assigned
--   "-"  state: not active in the game  Wishlist: none assigned
--   "x"  state and Wishlist: unavailable right now
--   "~"  state and Wishlist: the saved assignment is being restored
--   "0"  state: empty, the Saved Build holds no Echoes
--   "1"  state: first-run target (no Saved Build in use)
--   "!"  Wishlist: refused, the Saved Build is explicitly empty (no Echoes)
--   "_"  state: nothing captured ("none"), in a Preview minimum only
-- A captured state minimum is "C:" then its state record's mark, 3 glyphs
-- ("C:+", "C:0", "C:?", ...): the capture and each state stay visible, and
-- being captured is not evidence of the current assignment. A Preview
-- state minimum is its own atomic alternative, at most 3 glyphs: "P",
-- then "C" when captured, then that mark ("P+", "P1", "PC0", "PC?", ...),
-- so Preview, the capture and each state stay visible. A "none"
-- destination is never captured; its only mark is "_", in that Preview
-- minimum ("P_"). No mark is a pipe or a control character; each is
-- chosen from the descriptor codes, never cut from or parsed out of the
-- worded value.
local SAVED_BUILD_STATE_COMPACT = {
    unavailable = {compact = "Unavailable", minimum = "N/A", mark = "x"},
    empty = {compact = "Empty", minimum = "Empty", mark = "0"},
    active = {compact = "Active", minimum = "On", mark = "+"},
    inactive = {compact = "Inactive", minimum = "Off", mark = "-"},
    unconfirmed = {compact = "Unconfirmed", minimum = "?", mark = "?"},
    notStated = {compact = "Not known", minimum = "?", mark = "?"},
}
local DESTINATION_COMPACT = {
    firstRun = {build = "None", compact = "First run", minimum = "1st", mark = "1"},
    restoring = {build = "?", compact = "Restoring", minimum = "Wait", mark = "~"},
    unknown = {build = "?", compact = "Not loaded", minimum = "?", mark = "?"},
    unconfirmed = {build = "?", compact = "Unconfirmed", minimum = "?", mark = "?"},
    none = {build = "?", compact = "None", minimum = "None"},
}
-- The one-glyph minimum mark of a stated Wishlist assignment state; an
-- assigned Wishlist with a name shows that name instead (see
-- DestinationFields). Refused is "!" and not known is "?" (see above).
local WISHLIST_MINIMUM = {
    assigned = "+", unassigned = "-", unavailable = "x", restoring = "~",
}
-- A stated Wishlist assignment state in compact words.
local function WishlistCompact(wishlist, state)
    if state == "assigned" then
        return wishlist or "Assigned"
    elseif state == "unassigned" then
        return "None"
    elseif state == "unavailable" then
        return wishlist and ("N/A: " .. wishlist) or "N/A"
    elseif state == "restoring" then
        return "Restoring"
    end
    return wishlist and ("?: " .. wishlist) or "?"
end

-- A fixed phrase with its first letter raised when asked (ASCII words only,
-- never a name).
local function Lead(text, capital)
    return capital and (text:sub(1, 1):upper() .. text:sub(2)) or text
end

-- The descriptor's facts as codes and display-safe names. The Saved Build
-- state keeps one order: unavailable, empty, active, not active,
-- unconfirmed, else not stated.
local function DestinationParts(d)
    local p = {character = T.SafeName(d.character)}
    if d.kind == "savedBuild" then
        p.kind = "savedBuild"
        p.label = T.SavedBuildLabel(d.slot, d.name)
        if d.unavailable then
            p.state = "unavailable"
        elseif d.empty then
            p.state = "empty"
        elseif d.active == true then
            p.state = "active"
        elseif d.active == false then
            p.state = "inactive"
        elseif d.unconfirmed then
            p.state = "unconfirmed"
        end
    elseif d.kind == "firstRun" or d.kind == "unconfirmed" then
        p.kind = d.kind
    elseif d.kind == "unknown" then
        p.kind = d.reason == "restoring" and "restoring" or "unknown"
    else
        p.kind = "none"
    end
    p.wishlist = T.SafeName(d.wishlist)
    return p
end

-- The Wishlist words for one assignment state, or the name alone when no
-- known state is given (nil when there is neither).
local function WishlistWords(wishlist, state, capital)
    if state == "assigned" then
        return wishlist and (wishlist .. " (assigned)") or Lead("assigned", capital)
    elseif state == "unassigned" then
        return Lead("none assigned", capital)
    elseif state == "unavailable" then
        return wishlist and (wishlist .. " - unavailable right now")
            or Lead("unavailable right now", capital)
    elseif state == "restoring" then
        return Lead("restoring the saved assignment", capital)
    end
    return wishlist
end

-- The captured destination of a view, confirmation or result, as lines.
-- d.kind: "savedBuild", "firstRun", "unknown" (Saved Build data not loaded;
-- d.reason "restoring": the saved assignment is being restored),
-- "unconfirmed" (neither first-run nor a Saved Build can be confirmed) or
-- anything else (nothing captured). d.slot / d.name: the Saved Build.
-- d.active: true or false only when the caller knows it. d.unconfirmed: a
-- Saved Build's plan whose Saved Build is not confirmed as the active one
-- (no verified active row). d.empty: a numbered Saved Build that holds no
-- Echoes. d.unavailable: it cannot be read now.
-- d.character: an owner/character label the caller holds. d.wishlist and
-- d.wishlistState ("assigned", "unassigned", "unavailable", "restoring" or
-- nil when unknown). The destination is always the one the caller captured;
-- this function never looks up a currently active slot.
-- d.captured is read only by DestinationFields (below), never here.
function T.DestinationLines(d)
    d = type(d) == "table" and d or {}
    local lines = {}
    local p = DestinationParts(d)
    if p.character then lines[#lines + 1] = "Character: " .. p.character end
    if p.kind == "savedBuild" then
        local state = SAVED_BUILD_STATE_WORDS[p.state]
        lines[#lines + 1] = "Destination: " .. (p.label or "the selected Saved Build")
            .. (state and (" - " .. state) or "")
    else
        lines[#lines + 1] = "Destination: " .. DESTINATION_WORDS[p.kind].state
    end
    local wishlist = WishlistWords(p.wishlist, d.wishlistState)
    if wishlist then lines[#lines + 1] = "Wishlist: " .. wishlist end
    return lines
end

-- The same descriptor as four cells for a one-line strip, always in this
-- order: character, savedBuild, wishlist, state. Each record is
-- {key, label, value}; the second result is the complete tooltip, one
-- labeled line per cell (and a note when captured). Every cell has a value:
-- an unknown is "not known", never unassigned, first-run or active, and a
-- Wishlist name alone is never called assigned. An empty Saved Build has no
-- valid assignment, whatever Wishlist state is passed.
-- d.captured == true (explicit only; never inferred, for example from a
-- missing active slot): the caller shows a destination it captured earlier,
-- with d.wishlist the captured Wishlist name when it has one. That states
-- only that it was captured, not that it is assigned now: unless
-- d.wishlistState states the assignment, the state says it is not checked.
-- Value contract: each value is the complete display-safe text (whole
-- SafeName output, in which a literal pipe is already the escaped pair
-- "||"). A later fitting step shows it as it is, or shortens it only at a
-- UTF-8 character boundary that does not split an escaped pipe pair; it
-- never sanitizes or escapes it again, and the tooltip keeps the whole text.
-- Each record also has compact, a complete shorter value, and the state and
-- Wishlist records have minimum, their shortest atomic alternative (see the
-- compact markers above).
function T.DestinationFields(d)
    d = type(d) == "table" and d or {}
    local p = DestinationParts(d)
    local captured = d.captured == true and p.kind ~= "none"
    local build, stateWords, buildCompact, stateShort
    if p.kind == "savedBuild" then
        local name, slot = T.SafeName(d.name), Whole(d.slot)
        if slot and slot < 1 then slot = nil end
        if name and slot then
            build = name .. " (slot " .. slot .. ")"
            buildCompact = "#" .. slot .. " " .. name
        elseif slot then
            build = "Slot " .. slot
            buildCompact = "#" .. slot
        else
            build = name or Lead("the selected Saved Build", true)
            buildCompact = name or "Selected"
        end
        stateWords = SAVED_BUILD_STATE_WORDS[p.state] or "active state not known"
        stateShort = SAVED_BUILD_STATE_COMPACT[p.state] or SAVED_BUILD_STATE_COMPACT.notStated
    else
        build = Lead(DESTINATION_WORDS[p.kind].build, true)
        stateWords = DESTINATION_WORDS[p.kind].state
        buildCompact = DESTINATION_COMPACT[p.kind].build
        stateShort = DESTINATION_COMPACT[p.kind]
    end
    local noAssignment = p.kind == "savedBuild" and d.empty and true or false
    local stated = WISHLIST_STATES[d.wishlistState] == true
    -- minimum: the refusal, stated or unknown marker alone (unknown is "?",
    -- never unassigned); only a stated assigned Wishlist keeps its
    -- display-safe name, which is never cut or sanitized again here.
    local wishlist, wishlistCompact, wishlistMinimum
    if noAssignment then
        local words = "no valid assignment (the Saved Build holds no Echoes)"
        wishlist = p.wishlist and (p.wishlist .. " - " .. words) or Lead(words, true)
        wishlistCompact = p.wishlist and ("Refused: " .. p.wishlist) or "Refused"
        wishlistMinimum = "!"
    elseif stated then
        wishlist = WishlistWords(p.wishlist, d.wishlistState, true)
        wishlistCompact = WishlistCompact(p.wishlist, d.wishlistState)
        wishlistMinimum = d.wishlistState == "assigned" and p.wishlist
            or WISHLIST_MINIMUM[d.wishlistState]
    elseif p.wishlist then
        wishlist = p.wishlist .. (captured and " (captured)" or " (assignment not known)")
        wishlistCompact = "?: " .. p.wishlist
        wishlistMinimum = "?"
    else
        wishlist = "Not known"
        wishlistCompact = "?"
        wishlistMinimum = "?"
    end
    local state, stateCompact, stateMinimum
    if captured then
        state = "Captured; " .. stateWords
            .. ((noAssignment or stated) and "" or "; assignment not checked")
        -- "C:" keeps the capture visible; the state record's one-glyph mark
        -- keeps each state distinct, 3 glyphs in all (see the markers above).
        -- A captured first-run plan keeps its whole "first-run target" label
        -- (T.Terms.firstRun) in compact; its minimum stays "C:1".
        stateCompact = p.kind == "firstRun" and "Captured: first-run target"
            or ("Captured: " .. stateShort.compact)
        stateMinimum = "C:" .. stateShort.mark
    else
        state = Lead(stateWords, true)
        stateCompact, stateMinimum = stateShort.compact, stateShort.minimum
    end
    -- d.preview == true (explicit only): the view shows a Community Build
    -- preview, not this destination's plan. Presentation only: the full and
    -- compact state keep the underlying state whole after a Preview
    -- designation, so the preview stays visible at every width and is
    -- never called assigned; the other facts are worded as given. The
    -- minimum is its own atomic alternative (see the markers above), chosen
    -- from the codes alone: "P", then "C" when captured, then the state
    -- record's mark, or "_" for a "none" destination (never captured).
    local preview = d.preview == true
    if preview then
        state = "Preview; " .. state
        stateCompact = "Preview: " .. stateCompact
        stateMinimum = (captured and "PC" or "P")
            .. (p.kind == "none" and "_" or stateShort.mark)
    end
    local fields = {
        {key = "character", label = "Character", value = p.character or "Not known",
            compact = p.character or "?"},
        {key = "savedBuild", label = "Saved Build", value = build, compact = buildCompact},
        {key = "wishlist", label = "Wishlist", value = wishlist, compact = wishlistCompact,
            minimum = wishlistMinimum},
        {key = "state", label = "State", value = state, compact = stateCompact,
            minimum = stateMinimum},
    }
    local tooltip = {}
    for index = 1, #fields do
        tooltip[index] = fields[index].label .. ": " .. fields[index].value
    end
    if captured then
        tooltip[#tooltip + 1] = "Captured: shown as captured earlier; being captured is not evidence of the current assignment."
    end
    if preview then
        tooltip[#tooltip + 1] = "Preview: a Community Build preview is shown; it is not this destination's assignment."
    end
    return fields, tooltip
end

-- M7: the setup checklist, worded from current facts only (Panel.SetupFacts).
-- Steps: start-up, the destination Nexus would act on and its Wishlist. Each
-- row is {key, label, status, text}; status is "done", "todo", "waiting" or
-- "unknown". Loading, restoring, unavailable and not-known are never "done",
-- and whether the Welcome was seen or closed is not a fact here. complete is
-- true only when all three steps are done now.
T.CHECK_MARKS = {done = "[done]", todo = "[to do]", waiting = "[waiting]", unknown = "[not known]", info = "[info]"}
function T.SetupChecklist(f)
    f = type(f) == "table" and f or {}
    local rows = {}
    local function row(key, label, status, text)
        rows[#rows + 1] = {key = key, label = label, status = status, text = text}
    end
    if f.startup == "ready" then
        row("startup", "Start-up", "done", "Local saved data is restored.")
    elseif f.startup == "loading" then
        row("startup", "Start-up", "waiting", "Local saved data is still being restored (see the loading panel).")
    else
        row("startup", "Start-up", "unknown", "Start-up status cannot be read.")
    end
    local d = type(f.destination) == "table" and f.destination or nil
    if f.startup ~= "ready" then
        row("destination", "Destination", "unknown", "Not known until start-up finishes.")
        row("wishlist", "Wishlist", "unknown", "Not known until start-up finishes.")
        return {rows = rows, complete = false}
    end
    if not d then
        row("destination", "Destination", "unknown", "The Nexus panel has not shown a run yet.")
        row("wishlist", "Wishlist", "unknown", "The Nexus panel has not shown a run yet.")
        return {rows = rows, complete = false}
    end
    local label = T.SavedBuildLabel(d.slot, d.name)
    local destinationDone = false
    if d.kind == "savedBuild" and d.empty then
        row("destination", "Destination", "todo", (label or "The selected Saved Build")
            .. " holds no Echoes, so a Wishlist cannot be assigned to it. Load a Saved Build that holds Echoes in the game's build window.")
    elseif d.kind == "savedBuild" and d.unavailable then
        row("destination", "Destination", "unknown", (label or "The Saved Build") .. " is not available right now.")
    elseif d.kind == "savedBuild" and d.active == true then
        destinationDone = true
        row("destination", "Destination", "done", (label or "A Saved Build") .. " is active in the game.")
    elseif d.kind == "savedBuild" then
        row("destination", "Destination", "unknown", "A Saved Build's plan is in use, but which Saved Build is active is not confirmed.")
    elseif d.kind == "firstRun" then
        destinationDone = true
        row("destination", "Destination", "done", "The first-run target (no Saved Build in use).")
    elseif d.kind == "unknown" then
        row("destination", "Destination", "waiting", d.reason == "restoring"
            and "Not known yet: the saved assignment is being restored."
            or "Not known yet: Saved Build data is not loaded.")
    else
        row("destination", "Destination", "unknown", "Not confirmed right now.")
    end
    local wishlist = T.SafeName(d.wishlist)
    local state = d.wishlistState
    local wishlistDone = false
    if d.empty then
        row("wishlist", "Wishlist", "todo", "Needs a Saved Build that holds Echoes first.")
    elseif state == "assigned" then
        wishlistDone = true
        row("wishlist", "Wishlist", "done", (wishlist and ("'" .. wishlist .. "'") or "A Wishlist") .. " is assigned.")
    elseif state == "unassigned" then
        row("wishlist", "Wishlist", "todo", "None assigned. Assign Wishlist... opens the chooser; nothing is assigned until you choose. No Wishlist yet? Create one in the Wishlist Editor.")
    elseif state == "restoring" then
        row("wishlist", "Wishlist", "waiting", "The saved assignment is being restored.")
    elseif state == "unavailable" then
        row("wishlist", "Wishlist", "unknown", (wishlist and ("'" .. wishlist .. "' is ") or "The assignment is ") .. "unavailable right now.")
    else
        row("wishlist", "Wishlist", "unknown", "Not known right now.")
    end
    return {rows = rows, complete = f.startup == "ready" and destinationDone and wishlistDone}
end

-- M7: Auto, Sync and Orb status as information lines (not setup steps). OFF
-- and no Orb run are complete answers; an unread fact says it is not known.
local SYNC_MODE_LINES = {
    automatic = "Sync: Automatic. Nexus may send shared builds and DPS records without a click; what is sent may reach no one.",
    manual = "Sync: Manual. Nexus sends only what you start (Sync Now or Share).",
    off = "Sync: Off. Nexus sends nothing; local records are kept.",
}
-- The Orb line. orb: false (an observed owner with no approved run), nil
-- (unknown; observed false: the owner was not read this session, so an
-- unresolved earlier action is not ruled out) or the plain facts of
-- Panel.SetupFacts. The reason is the text the Orb owner last recorded for its
-- run, said as that and never as a fresh check; the operation is the run's
-- recorded name, never a Resume target. Open Orbs reviews the current state.
local ORB_STATE_WORDS = {PAUSED = "run paused", STOPPED = "run stopped",
    LIMIT = "run stopped at its approved maximum", FINISHED = "run finished",
    COMPLETE = "run ended: its selected targets were met",
    ROLLED_COMPLETE = "run ended: its rolled targets were met",
    OUT_OF_ORBS = "run ended: no Orbs were left", NO_SOURCES = "run ended: no safe source copies were left"}
local ORB_UNRESOLVED = "an earlier Orb action is unresolved"
local ORB_REASON_CHARS, ORB_NAME_CHARS = 280, 60
local function OrbLine(orb, observed)
    if orb == false then return "Orbs (optional): no Orb run approved this session." end
    if type(orb) ~= "table" then
        if observed == false then
            return "Orbs (optional): not known. Orb status has not been read this session, so an unresolved earlier Orb action is not ruled out. Open Orbs to check."
        end
        return "Orbs (optional): status not known right now."
    end
    local state = type(orb.state) == "string" and orb.state:match("^[%u_]+$") or nil
    local head
    if orb.running == true then head = "run running"
    elseif orb.restored == true or state == "RECOVERY" then head = ORB_UNRESOLVED
    elseif state and ORB_STATE_WORDS[state] then head = ORB_STATE_WORDS[state]
    elseif state then head = "run in state " .. state
    else head = "run state not known" end
    local line = "Orbs (optional): " .. head
        .. ((orb.pending == true and head ~= ORB_UNRESOLVED) and "; a result is pending." or ".")
    local operation = orb.pending == true and type(orb.operation) == "string"
        and T.SafeName(orb.operation, ORB_NAME_CHARS) or nil
    if operation then line = line .. " Original operation (as recorded): '" .. operation .. "'." end
    local reason = type(orb.reason) == "string" and T.SafeName(Utf8Cut(orb.reason, ORB_REASON_CHARS)) or nil
    if reason then
        if not reason:find("[%.!?]$") then reason = reason .. "." end
        line = line .. " Last reason Nexus recorded: " .. reason
    end
    return line .. " Open Orbs to review it now and see the actions available there."
end
function T.StatusLines(f)
    f = type(f) == "table" and f or {}
    local lines = {}
    if f.auto == true then
        local held = T.SafeName(f.autoNote or f.paused, 200)
        lines[#lines + 1] = "Auto: ON" .. (held and (" - not acting now: " .. held) or "")
    elseif f.auto == false then
        lines[#lines + 1] = "Auto: OFF. Recommendations only; turning Auto ON is your choice (read its warning first)."
    else
        lines[#lines + 1] = "Auto: not known right now."
    end
    local sync = SYNC_MODE_LINES[f.syncMode]
    if sync then
        lines[#lines + 1] = sync .. (f.syncExplicit == false and " (Not a choice you saved.)" or "")
    else
        lines[#lines + 1] = "Sync: mode not known right now."
    end
    lines[#lines + 1] = OrbLine(f.orb, f.orbObserved)
    return lines
end

-- One count vocabulary. These are different units and are never merged:
-- planned copies (the plan), rolled copies this run, the Wishlist's copies
-- found in a Saved Build, locked targets, and Echo families represented (a
-- family counts once whatever its copies).
local COUNT_UNITS = {
    planned = "rolled copies planned",
    run = "rolled copies this run",
    savedBuild = "Wishlist copies in this Saved Build",
    locked = "locked targets",
    families = "Echo families represented",
}
T.COUNT_UNITS = COUNT_UNITS

-- "12 / 79 rolled copies this run", or "Rolled copies this run: unavailable"
-- when either side is unknown (never 0 / 0 or a guessed total).
function T.CountText(kind, have, want)
    local unit = COUNT_UNITS[kind] or "copies"
    local h, w = Whole(have), Whole(want)
    if h == nil or w == nil or w <= 0 then
        return unit:sub(1, 1):upper() .. unit:sub(2) .. ": unavailable"
    end
    return h .. " / " .. w .. " " .. unit
end

-- The run's own progress line. Locked targets still to lock are said; the
-- word "complete" is never used here (ProgressComplete decides that).
-- `compact` gives the short form for a narrow line (still qualified).
function T.RunProgressText(have, want, lockedOutstanding, compact)
    local h, w, outstanding = Whole(have), Whole(want), Whole(lockedOutstanding)
    if h == nil or w == nil or w <= 0 then
        return compact and "Rolled: unavailable" or "Rolled copies this run: unavailable"
    end
    if outstanding and outstanding > 0 then
        return h .. " / " .. w .. " rolled, " .. outstanding .. (compact and " to lock" or " still to lock")
    end
    return h .. " / " .. w .. (compact and " rolled" or " rolled copies this run")
end

-- Complete only when the rolled copies are met AND no locked target is
-- outstanding; an unknown on either side is not complete.
function T.ProgressComplete(have, want, lockedOutstanding)
    local h, w, outstanding = Whole(have), Whole(want), Whole(lockedOutstanding)
    return h ~= nil and w ~= nil and w > 0 and h >= w and outstanding ~= nil and outstanding == 0
end

-- Record scope (DPS records and leaderboards): what this client holds, not a
-- complete or server-wide ranking.
T.BEST_KNOWN = "Best known"
T.RECORD_SCOPE = "Best known: the best shared record this client holds for these exact Echoes. "
    .. "It is not a complete or server-wide ranking."
T.LEADERBOARD_SCOPE = "Best known exact loadout per character"

function T.CategoryName(category)
    if category == "lk" then return "Lich King" end
    if category == "dummy" then return "Training Dummy" end
    if category == "combined" then return "Both records" end
    return nil
end

-- The facts a record genuinely carries: its category, a positive fight
-- duration, a positive level and a recorded date. A missing or zero value is
-- left out, never shown as 0 or as a dash that reads like a value.
function T.RecordDetailParts(row)
    row = type(row) == "table" and row or {}
    local parts = {}
    local category = T.CategoryName(row.category)
    if category then parts[#parts + 1] = category end
    local duration = Whole(row.duration)
    if duration and duration > 0 then
        parts[#parts + 1] = string.format("%d:%02d fight", math.floor(duration / 60), duration % 60)
    end
    local level = Whole(row.level)
    if level and level > 0 then parts[#parts + 1] = "Level " .. level end
    local stamp = Whole(row.ts)
    local formatDate = (type(date) == "function" and date) or (type(os) == "table" and os.date) or nil
    if stamp and stamp > 0 and formatDate then
        local ok, text = pcall(formatDate, "!%Y-%m-%d", stamp)
        if ok and type(text) == "string" and text ~= "" then
            parts[#parts + 1] = "Recorded " .. text .. " (UTC)"
        end
    end
    return parts
end

-- The record's own owner flag: verified, not established, or nothing when
-- the record does not say (unknown is not presented as either).
function T.OwnerLine(row)
    if type(row) ~= "table" then return nil end
    if row.ownerVerified == true then return "Owner verified" end
    if row.ownerVerified == false then return "Owner identity not established" end
    return nil
end

-- One user meaning per label (UX-15). Internal identifiers, protocol fields
-- and saved-data names keep their own spelling and are not listed here.
T.Terms = {
    -- Issue #165: the panel's menu button shows "Options" (ui/Panel.lua
    -- OptionsLabel, localized as panel.button.options); its hover carries the
    -- status. The old key name is kept for existing readers; it now holds the
    -- visible name, never the retired "Menu and status" or a bare ellipsis.
    options = "Options",
    menuAndStatus = "Options",
    bestKnown = T.BEST_KNOWN,
    showRecords = "Show DPS records",
    -- The game's own page that lists your Saved Builds.
    myBuildsPage = "My Builds",
    -- The Build Library scope that lists your Saved Builds and shared listings
    -- (internal scope key "mine").
    mineScope = "Mine",
    firstRun = "first-run target",
}
T.GLOSSARY = "Counts: planned copies (the plan), rolled copies this run, the Wishlist's copies in a Saved Build "
    .. "and locked targets are different counts, and Echo families represented counts a family once. "
    .. "Unavailable is not 0, and a plan is not a finished build. Best known: the best shared DPS record this "
    .. "client holds for the exact same Echoes; it is not a complete or server-wide ranking. My Builds is the "
    .. "game's page of your Saved Builds; in Build Library, the Mine scope lists your Saved Builds and "
    .. "shared listings. Options: the Options button on the Nexus panel header opens its menu, with Manage; "
    .. "point at it for the current status."

------------------------------------------------------------------------
-- Guided setup coach copy (ui/GuidedSetup.lua, issue #131), from the Claude
-- Design guided-setup copy deck. English only: the localization packs do not
-- cover these strings, and no language coverage is claimed for them. Glyphs
-- are printable ASCII, always beside a word. Plain data; nothing here reads
-- or acts.
------------------------------------------------------------------------
T.Guide = {
    title = 'Nexus setup',
    charLine = '%s - Saved Builds read from Nexus',
    charUnknown = 'Character not read yet',
    kicker = 'Step %d of %d',
    kickerOptional = ' - OPTIONAL',
    labels = {welcome = 'Welcome', wishlist = 'Choose a Wishlist', target = 'Pick the Saved Build',
        assign = 'Assign & confirm', manual = 'Read a recommendation', auto = 'Auto (optional)', summary = 'Finish'},
    -- One word-plus-glyph status language (never colour alone).
    status = {
        ['not'] = {glyph = 'o', word = 'Not started'}, waiting = {glyph = '*', word = 'Needs you'},
        checking = {glyph = '...', word = 'Checking...'}, verified = {glyph = '+', word = 'Done - confirmed'},
        skipped = {glyph = '-', word = 'Skipped'}, unavailable = {glyph = '!', word = 'Unavailable'},
        stale = {glyph = '?', word = 'Unknown - re-check'}, rejected = {glyph = 'x', word = 'Declined'}},
    words = {chosen = 'Chosen', tried = 'Tried', linked = 'Already linked', draft = 'Draft - not saved',
        cancelled = 'Cancelled', review = 'Review & close', summary = 'Summary',
        leftOn = 'Left ON', leftOff = 'Left OFF', leftUnknown = 'Left alone - mode unknown', modeUnknown = 'Mode unknown'},
    -- The guide's place is kept for this character (core/GuidedSetup.lua,
    -- PlaceKept "saved"); while saved data cannot be written it is kept for
    -- this session only, and the Session words say so.
    checklistTitle = 'CHECKLIST',
    -- Setup Alternative: the header's Reference opens the optional Reference
    -- view in place of the step (help is that view's flag); All steps opens
    -- the step list; Continue later closes exactly as X does.
    buttons = {help = 'Reference', close = 'X', closeTip = 'Close (Esc) - your place is kept',
        closeTipSession = 'Close (Esc) - your place is kept until you reload or log out: saved data cannot be written right now',
        back = 'Back', later = 'Continue later',
        skip = 'Skip for now', next = 'Continue', finish = 'Close guide',
        checklistShow = 'All steps v', checklistHide = 'All steps ^', helpClose = 'X', fullHelp = 'Open full Help',
        refBack = '< Back to step %d - %s', dismissDraft = 'Pick a saved Wishlist',
        open = 'Open the Wishlist chooser', openAgain = 'Open the Wishlist chooser again', check = 'Check again',
        replace = 'Replace and continue', cancel = 'Choose another', retry = 'Try again',
        goWishlist = 'Choose a Wishlist', goTarget = 'Pick a Saved Build', goStep = 'Go to step',
        keep = 'Keep Auto %s', leave = 'Leave Auto alone', review = 'Review on the Nexus panel...', reread = 'Try reading it again',
        autoMore = '> What does Auto do?', autoLess = 'v What Auto does',
        read = 'Read', hide = 'Hide', replay = 'Run the guide again',
        checkCode = 'Check code', openDraft = 'Open it as a draft', openBuilds = 'Open My Builds',
        returnPlan = 'Return to Plan draft', planChanged = 'Keep or discard Plan draft',
        -- The bounded window's body controls (ui/GuidedSetup.lua ScreenCap).
        scrollUp = 'Scroll up (or use the mouse wheel)', scrollDown = 'Scroll down (or use the mouse wheel)'},
    safety = 'Moving between steps never assigns, spends Orbs, sends data, or changes Auto.',
    -- Setup Alternative: one short reason per step, the action under DO
    -- THIS, then the outcome slot. Only a result the guide read is OBSERVED;
    -- before that the slot says what to expect, never that it happened.
    whyLabel = 'WHY THIS MATTERS', doLabel = 'DO THIS',
    why = {welcome = 'Nexus points at Echoes from a Wishlist you choose. Nothing changes in game until you confirm a step.',
        wishlist = 'A Wishlist is the Echoes you want. Recommendations and Orb runs work from it.',
        target = 'A Saved Build is the build slot the game loads. It is the build your Wishlist will follow.',
        assign = 'Once they are linked, recommendations follow your Wishlist for the build you play.',
        manual = 'This is what Nexus points at while you roll. Nothing is chosen in game here.',
        auto = 'Auto can act for you. It only changes when you change it yourself.',
        summary = 'Only steps Nexus confirmed are marked done. Anything else stays open for later.'},
    outcome = {expectLabel = 'WHAT YOU WILL SEE', observedLabel = 'OBSERVED', summaryLabel = 'SUMMARY',
        expect = {welcome = 'Seven short steps. Back, Skip and Continue later never change anything.',
            wishlist = 'One Wishlist lights up and the footer shows the same name.',
            target = 'One Saved Build lights up. Nexus does not edit it.',
            assign = 'After you confirm, Nexus reads the result back. Only a confirmed result counts as done.',
            manual = 'A sample recommendation appears. Nothing is chosen in game.',
            auto = 'Auto stays as it is unless you change it yourself.',
            summary = 'Only steps Nexus confirmed are marked done. Skipped, unknown and declined steps stay open.'},
        extra = {skipped = 'Nothing was changed; this step stays open.',
            rejected = 'Nothing was changed; this step stays open.',
            unavailable = 'Nothing is marked done.', stale = 'The earlier result no longer counts.',
            waiting = 'Nothing is marked done yet.'}},
    -- The optional Reference view: a topic list, each topic one Help page
    -- opened in place of the guide (U.OpenHelp); never shown under a step.
    reference = {title = 'Reference', tag = 'Reference - optional',
        lead = 'More detail for after setup. One topic at a time.',
        full = 'Each topic opens its full reference page (/nexus reference) in place of this guide; close it to come back to this step.',
        topics = {{page = 'start', title = 'Getting started'}, {page = 'wishlists', title = 'Wishlists and locked targets'},
            {page = 'rolling', title = 'Auto, rolling and saving'}, {page = 'orbs', title = 'Orbs / Lost Memories'},
            {page = 'sharing', title = 'Shared builds and DPS'}, {page = 'troubleshooting', title = 'Problems and bug reports'}}},
    welcome = {title = 'Welcome to Nexus', titleReplay = 'Welcome back',
        body = 'Nexus recommends Echoes from a Wishlist you choose. This guide links one Wishlist to one Saved Build and shows you what a recommendation looks like.',
        bodyReplay = 'Replaying the guide resets nothing. It re-checks what is already set and lets you change anything safely.',
        paths = {
            {id = 'new', title = 'New to Nexus', desc = 'Start a Wishlist and give it a build slot. About 3 minutes.'},
            {id = 'existing', title = 'I already have a Saved Build', desc = 'Point one of your Saved Builds at a Wishlist. You will see what gets replaced first.'},
            {id = 'explore', title = 'Just look around', desc = 'See how recommendations and Auto work. Nothing is set up or changed.'}}},
    wishlist = {title = 'Choose a Wishlist',
        conceptWish = 'Wishlist - what you want', conceptWishBody = 'The Echoes you are aiming for. Nexus uses it to point at good picks.',
        conceptBuild = 'Saved Build - what you play', conceptBuildBody = 'A build slot the game loads. Each one follows one Wishlist.',
        yours = 'Yours on the server', needsRoles = 'Yours - needs locked targets; the chooser asks for them',
        importTitle = 'Paste a Wishlist code', importDesc = 'From a friend or a guide. Check it here first; checking imports and saves nothing.',
        -- The in-step check (WishlistEditor.CheckImportCode) reads the code
        -- only; Open it as a draft hands that same code to the editor's import.
        importLabel = 'Paste the whole code',
        importOk = '+ Code read: %s - %d Echo entries (%d rolled copies, %d locked targets).',
        importOkBody = 'Nothing is imported or saved yet. Open it as a draft: the Wishlist Editor asks for a name, checks the Echoes again and shows the draft. It counts only after you save it there.',
        importRoles = 'It has more than 79 rolled copies, so the editor asks you to choose locked targets before the draft opens.',
        importSuspended = 'An unsaved Plan draft is open in another workspace. Return to Plan and finish it before opening this code.',
        importUnnamed = 'an unnamed code',
        importBad = "x That code didn't work.",
        importBadBody = "It looks cut off or isn't a Nexus Wishlist code. Copy the whole code again from where you got it. Nothing was imported.",
        importLong = "It filled this field's %d-letter limit, so it may be cut off. Copy the whole code again from where you got it. Nothing was imported.",
        importEmpty = '! Not checked: paste a code first.',
        importUnavailable = '! Not checked: the code reader is not available yet. Nothing was read or imported.',
        createTitle = 'Start an empty Wishlist', createDesc = 'Opens the Wishlist Editor. Add Echoes there, then save.',
        -- While an unsaved Plan draft is set aside (Setup Alternative): the
        -- row reads unavailable before it is clicked; a click shows one note.
        createBlocked = 'Start an empty Wishlist (unavailable: unsaved Plan draft)',
        createBlockedDesc = 'An empty Wishlist would replace your unsaved Plan draft. Return to it or pick a saved Wishlist.',
        -- The footer's one name, the same Wishlist the single chosen card shows.
        selected = 'Selected: %s', selectedNone = 'Selected: nothing yet',
        -- Start an empty Wishlist while an unsaved Plan draft is set aside in
        -- another workspace (WishlistEditor.SuspendedPlanDraft); the editor
        -- never replaces that draft, and Return to Plan draft reopens it.
        -- Under another character or Saved Build it cannot be reopened as it
        -- is: Keep or discard Plan draft asks the editor's own question, whose
        -- Discard draft opens Plan for the current context without it.
        planHead = '! An unsaved Plan draft is waiting in Plan.',
        planBody = 'You left it in Plan to open another workspace. An empty Wishlist would replace it, so none was opened. Nothing was saved or changed.',
        planSame = 'Return to Plan draft to finish and save it there, or close it if you do not need it. Then start an empty Wishlist here.',
        planContext = 'It was set aside under another character or Saved Build, so it cannot be reopened here. Keep or discard Plan draft asks you first: Keep draft leaves it set aside as it is; Discard draft deletes that unsaved draft and opens Plan for the current character and Saved Build, without it.',
        -- A kept Wishlist that more than one listed Wishlist matches after a
        -- reload (core/GuidedSetup.lua Readopt): none is picked for the player.
        reselect = '! Choose your Wishlist again: more than one of your Wishlists holds the same Echoes as the one you chose, so none was picked for you.',
        chosen = 'Chosen: %s.', saved = 'Saved in the Wishlist Editor: %s.',
        draft = 'A draft is open in the Wishlist Editor. It counts only after you save it there.',
        partial = 'The plan was uploaded, but the save did not finish. See the result in the Wishlist Editor.',
        uncertain = 'The game reported an error while sending it; it may or may not exist now. Check the Wishlist list before saving again.',
        notSaved = 'The Wishlist Editor did not save it. Your edits are kept there.',
        more = 'More Wishlists are listed in the Wishlist Editor.',
        none = 'No Wishlist is listed yet. Paste a code or start an empty one.',
        notLoaded = 'Your Wishlists could not be read yet. Try again in a moment.'},
    target = {title = 'Which Saved Build should follow it?',
        read = 'Read from Nexus just now. Picking one changes nothing yet.',
        unavailable = "! Couldn't read your Saved Builds.", unavailableBody = 'Nexus did not answer. It may still be loading after login. Nothing has changed.',
        slot = 'Slot %d - %s', slotUnnamed = 'Slot %d', first = 'First-run target',
        firstDesc = 'Used until a Saved Build with Echoes is active.',
        active = 'Active now', follows = 'Follows %s', followsNone = 'Follows no Wishlist yet',
        followsUnknown = 'What it follows could not be read', empty = 'Empty - holds no Echoes, so it cannot follow a Wishlist yet',
        -- An empty slot is offered (the original guided design); it can
        -- follow a Wishlist only after the player saves Echoes into it in the
        -- game's own build window, which asks before it saves.
        emptyOffer = 'Empty - holds no Echoes yet. Save your current Echoes into it in My Builds first',
        missing = 'Not available right now',
        ifAssign = 'If you assign %s here',
        cAlready = '%s already follows %s.', cAlready2 = 'Nothing will change. The next step just confirms it with Nexus.',
        cReplace = '%s follows %s now. Assigning switches it to %s.', cKept = '%s stays in your Wishlists. Nothing is deleted.',
        cEchoes = 'Echoes in this slot are not touched.',
        cActive = 'The Echo Journal targets this slot now, so recommendations change right away.',
        cAutoOn = 'Auto is ON: a later finished run that fits the new Wishlist better may replace this Saved Build.',
        cNew = 'Nothing is linked here yet, so no link is replaced.',
        cUnknown = 'What this slot follows could not be read, so the consequence is unknown. Try again later.',
        -- Routes the Echo Journal chooser cannot take now (core/GuidedSetup.lua
        -- TargetOptions route). Each names the player's own game step; the
        -- guide saves, loads, activates and assigns nothing.
        cEmpty = '%s is empty: it holds no Echoes, so it cannot follow a Wishlist yet.',
        cEmptySave = 'To use it, open My Builds, select this slot and save your current Echoes into it there. The game asks you to confirm before it saves; Nexus never saves a Saved Build for you.',
        cSelect = 'The Echo Journal chooser assigns only to the Saved Build that is active in the game, and %s is not active now.',
        cSelectHow = 'To use it, open My Builds and choose it there yourself. Choosing a different Saved Build there changes your active loadout; Nexus never does that for you.',
        cFirst = 'The Echo Journal chooser does not assign to the first-run target while a Saved Build is selected in the game. Choose the Saved Build it assigns to, or another.',
        cReturn = 'Then reopen this guide (Setup / Welcome, or /nexus guide). It reads your Saved Builds again; nothing is assumed.',
        accepted = 'Replacement accepted for this choice only. Nothing changes until you choose in the Echo Journal.',
        shortAlready = 'Already linked. This only checks it; nothing is written.',
        shortReplace = 'Replaces the %s link on this slot. Nothing is deleted.', shortNew = 'Links this slot. Nothing is replaced.'},
    assign = {title = 'Assign, then let Nexus confirm',
        missing = 'Choose a Wishlist and a Saved Build first. Nothing to assign yet.',
        openNote = 'Opens the Echo Journal Wishlist chooser. Nothing changes until you choose %s there.',
        waiting = '* Waiting for you to choose %s in the Wishlist chooser. Nothing is assigned yet.',
        verified = '+ Nexus confirmed it', readback = 'Read back from Nexus',
        evCharacter = 'Character', evBuild = 'Saved Build', evWishlist = 'Wishlist', evRequest = 'Request',
        evRead = 'Read back', evRequestValue = '#%d - this session', evSave = 'Your save in the Wishlist Editor',
        evReadValue = 'Just now - after your choice',
        observed = '+ Already linked.', observedBody = '%s already follows %s. Nexus read it back just now; this guide did not change it.',
        rejected = 'x Nexus declined.', rejectedBody = 'The assignment was refused (%s). Nothing was assigned.',
        cancelled = 'x Cancelled.', cancelledBody = 'The choice in the Wishlist chooser was cancelled. Nothing was assigned.',
        unavailable = '! No answer from Nexus.', unavailableBody = 'The slot may or may not have changed - the guide will not guess. Check again, or skip and look in the Echo Journal later.',
        stale = '? The earlier check no longer counts.',
        staleBody = {stale = 'The assignment of %s changed after your choice. Check again so the result belongs to what is set now.',
            changed = 'The assignment of %s changed through another route, not through this guide. Check again.',
            other = 'Another Wishlist (%s) was assigned instead. Open the chooser and choose your Wishlist.',
            mismatch = '%s follows another Wishlist (%s). Open the chooser and choose your Wishlist.',
            outdated = 'This result belongs to another character or session. Assign again to confirm it here.',
            partial = '%s follows your Wishlist, but its locked targets are still unconfirmed.'}},
    sim = {title = 'Reading a recommendation',
        body = 'When the game offers Echoes, Nexus marks the one your Wishlist wants. You still choose. Try it below.',
        banner = 'SIMULATED PREVIEW - NOTHING IS CHOSEN IN GAME',
        cards = {{name = 'Sample Ember', desc = 'Rare - on the sample Wishlist, 2 copies missing'},
            {name = 'Sample Frost', desc = 'Common - not on the sample Wishlist'},
            {name = 'Sample Ash', desc = 'Uncommon - not on the sample Wishlist'}},
        mark = '>> Wishlist pick',
        why = 'Sample Ember is marked because it is on the sample Wishlist and you do not have it yet.',
        picked = 'Preview only: you picked %s. Nothing was chosen in game.',
        match = ' That matches the recommendation.', differ = ' Nexus marked Sample Ember, but your pick always wins.',
        autoOn = ' Auto is ON for this character, so in game Nexus may act without asking. More on the next step.'},
    auto = {title = 'Auto is up to you',
        modeOn = 'Auto is ON right now', modeOff = 'Auto is OFF right now', modeUnknown = 'Auto mode unknown',
        subRead = 'Read from Nexus just now.', subUnknown = 'Nexus did not report it. The guide will leave it alone.',
        lead = 'Most players start with Auto OFF and just follow the recommendations. This guide will not change it unless you do.',
        moreOn = 'With Auto ON, Nexus may choose offers and may replace your active Saved Build with a better finished run, without asking. It never loads a build or starts Orbs.',
        moreOff = 'With Auto OFF, Nexus only recommends. Slots change only when you change them.',
        reviewNote = 'Turning Auto ON or OFF is done with the Auto button on the Nexus panel, after its own warning.',
        keptOn = 'Left ON. Nothing changed.', keptOff = 'Left OFF. Nothing changed.',
        keptUnknown = 'Left alone. Its mode is still unknown, and this guide did not touch it.'},
    finish = {titleDone = "You're set up", titleOpen = 'Not finished: %d step%s still open', titleExplore = "You've had a look around",
        subDone = 'Nexus confirmed the assignment. Nothing else was changed by this guide.',
        subTrue = 'Nexus read back that the assignment was already in place. This guide changed nothing.',
        subOpen = "You can close now. Your place is kept, but setup won't be marked complete. Skipped steps stay skipped.",
        subOpenSession = "You can close now. Your place is kept until you reload or log out, but setup won't be marked complete. Skipped steps stay skipped.",
        subExplore = 'Nothing was set up or changed. Run the guide again to set up for real.',
        explore = 'Not part of a look-around',
        rows = {wishlist = 'Choose a Wishlist', target = 'Pick the Saved Build', assign = 'Assign & confirm',
            manual = 'Read a recommendation', auto = 'Auto (optional)'},
        wishDone = '%s', wishSkipped = 'Skipped. No Wishlist chosen.', wishNot = 'Not chosen',
        wishDraft = 'A draft is open, not saved', wishPartial = 'The save did not finish', wishUncertain = 'The save may or may not have happened',
        targetSkipped = 'Skipped', targetNot = 'Not chosen',
        assignDone = '%s follows %s. Confirmed by read back.', assignTrue = '%s already follows %s. Read back; not changed by this guide.',
        assignSkipped = 'Skipped. Nothing was assigned.', assignWaiting = 'Chooser opened, nothing chosen yet.',
        assignRejected = 'Nexus declined the assignment.', assignUnknown = "Not confirmed. Nexus didn't answer.",
        assignStale = 'It was confirmed, but something changed since. Needs a fresh check.', assignNot = 'Not assigned',
        manualDone = 'Tried the preview', manualSkipped = 'Skipped', manualNot = 'Not tried',
        autoUnknown = "Mode not reported. This guide didn't touch it.", autoMode = '%s, unchanged by this guide',
        autoNotReviewed = '%s - not reviewed',
        sent = 'This guide sent nothing and used no Orbs.',
        more = 'Want more?', moreSub = "Separate and optional - setup doesn't need them.",
        lessons = {
            {id = 'orbs', title = 'Orbs & Lost Memories', open = 'Open Orbs / Lost Memories',
                lines = {"Orb runs can refine a build after you've played it. They're optional and separate from setup.",
                    'Reading this spends nothing. Every Orb run asks you first.'}},
            {id = 'sharing', title = 'Sharing & Sync', open = 'Open Reference: Sharing',
                lines = {'Sync can send shared builds and DPS records; Reference - Sharing lists exactly what goes out and when.',
                    'This guide never sends anything.'}}}},
    -- The design's aside: full Help is the reference pages /nexus reference
    -- opens (/nexus help and /nexus tutorial open this coach).
    help = {title = 'About: %s', full = 'Full guide: the Nexus reference pages (/nexus reference). They open in place of this guide; close them to come back to this step.',
        lines = {
            welcome = {"Nexus watches the Echoes you're offered and points at the ones on your Wishlist.",
                'Each change in this guide has its own button and tells you what it does first.'},
            wishlist = {'One Saved Build follows one Wishlist at a time. A Wishlist can serve several builds.',
                'Codes come from friends or guides. Nexus checks them before using them.'},
            target = {'Slots are read fresh from Nexus each time you open this step.',
                'Replacing a link never deletes the old Wishlist.'},
            assign = {'"Done" appears only after Nexus reports the same character, slot and Wishlist for this request.',
                "If Nexus doesn't answer, the guide says so instead of guessing."},
            manual = {'The preview uses made-up Echoes. Nothing is chosen in game.'},
            auto = {'Auto stays as it was unless you change it with the Auto button on the Nexus panel.',
                'You can turn it off any time with that same button.'},
            summary = {'Closing never marks skipped or unconfirmed steps as done.', 'Orbs and Sharing are separate and optional.'}}},
    gate = {welcome = 'Pick how you want to start.', wishlist = 'Choose a Wishlist to continue.',
        wishlistDraft = 'Save the draft in the Wishlist Editor, pick another Wishlist, or skip.',
        wishlistImport = 'Paste a code and check it, choose another Wishlist, or skip.',
        wishlistChecked = 'Open the checked code as a draft and save it there, choose another Wishlist, or skip.',
        target = 'Pick a Saved Build to continue.', targetUnavailable = "Saved Builds couldn't be read. Try again or skip.",
        targetReplace = 'Accept the replacement or choose another.',
        targetSelect = 'Make it your active Saved Build in My Builds, or choose another.',
        targetSave = 'Save your current Echoes into it in My Builds, or choose another.',
        targetFirst = 'Choose the Saved Build the Echo Journal assigns to, or skip.',
        assign = 'Continues once Nexus confirms.', assignWaiting = 'Choose your Wishlist in the Wishlist chooser.',
        assignRejected = 'Nexus declined. Try again or skip.', assignUnknown = 'Not confirmed. Check again or skip.',
        assignStale = 'Needs a fresh check.', manual = 'Try one pick in the preview, or skip.',
        auto = 'Keep Auto as it is, or review it.', autoUnknown = 'Leave Auto alone or retry reading it.'},
    chat = {paused = '[Nexus] Setup guide closed at "%s". Closing changed nothing.',
        -- Both routes open the coach itself (the design's "Reopen: Nexus
        -- menu > Setup / Welcome"). A resumed guide reads every result again.
        reopen = '[Nexus] Reopen it from the Options menu: Manage > Setup / Welcome, or type /nexus help. It resumes at this step and checks every result again.',
        reopenSession = '[Nexus] Reopen it from the Options menu: Manage > Setup / Welcome, or type /nexus help. Saved data cannot be written right now, so your place is kept only until you reload or log out.',
        complete = '[Nexus] Setup confirmed: %s follows %s.',
        auto = '[Nexus] Auto is %s (this guide did not change it).',
        explore = '[Nexus] Look-around finished. Nothing was set up or changed.',
        incomplete = '[Nexus] Setup guide closed with %d step%s open. Not marked complete.'},
    notice = {owner = 'The character changed, so earlier guide results were cleared.',
        epoch = 'Saved data changed, so earlier guide results were cleared.',
        session = 'A new world session started, so earlier guide results were cleared and must be checked again.',
        restored = 'Resumed where you left off. Earlier results are not kept: each one is read again now.',
        reselect = 'Resumed where you left off. More than one of your Wishlists holds the same Echoes as the one you chose, so the guide cannot tell which it was. Choose your Wishlist again; nothing was chosen for you.'},
    notes = {startup = 'Start-up is still running (see the loading panel). Nothing was opened.',
        unavailable = 'The game Character Progression button was not found. Nothing was opened or assigned.',
        noEditor = 'The Wishlist Editor is not available. Nothing was opened.',
        importChanged = 'That code no longer reads as a Wishlist code. Check it again. Nothing was opened.',
        importSuspended = 'An unsaved Plan draft is open in another workspace. Return to Plan before opening this code. Nothing was imported.',
        planRefused = 'Plan did not reopen the draft; a Save there may still be pending. Nothing was changed. Try again in a moment.',
        planDiscarded = 'You discarded the Plan draft. Plan did not open over this guide; open it from the Nexus panel when you need it. Nothing else was changed.',
        gone ='That Wishlist is no longer listed. Choose again.',
        notLoaded = 'Saved Build data is not loaded yet. Try again in a moment.',
        empty = 'That Saved Build holds no Echoes, so it cannot follow a Wishlist yet.',
        missing = 'That Saved Build is not available right now.',
        notReady = 'Choose a Wishlist and a ready Saved Build first.', blocked = 'an empty Saved Build',
        buildsUnavailable = 'My Builds did not open: the game Character Progression button was not found. Nothing was opened, saved or changed.',
        -- The game's button was used, but Nexus did not see My Builds after it
        -- (ui/JournalTab.lua OpenBuilds onSettled), so the coach stays.
        buildsUnconfirmed = 'Nexus could not confirm that My Builds opened, so this guide stays open. If My Builds is not on screen, open it in Character Progression yourself. Nothing was saved or changed.',
        route = 'The Echo Journal assigns to %s, not to your target %s. Select your target in the game build window, or go Back and choose the Saved Build the Journal targets. Nothing was opened or assigned.'},
}
