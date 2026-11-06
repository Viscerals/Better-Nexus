-- Player-facing terminology only. Stable policy/reason codes and protocol data
-- remain unchanged; diagnostics may retain original codes for support.
-- Issue #123: three status reasons resolve their English text through the
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
    ["waiting for three-card board"]="Waiting for the next three Echo choices",
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
            return text
        end
    end
    return "This action is not available yet. Check the status or diagnostics. Details: "..code
end
function T.Message(value)
    local s=tostring(value or "")
    if reasons[s] then return reasons[s] end
    if localizedReasons[s] then return LocalizedReason(localizedReasons[s],s) end
    local prefix,body=s:match("^(L%d+ %-%- )(.*)$")
    if prefix then return prefix..T.Message(body) end
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
function T.DestinationLines(d)
    d = type(d) == "table" and d or {}
    local lines = {}
    local character = T.SafeName(d.character)
    if character then lines[#lines + 1] = "Character: " .. character end
    if d.kind == "savedBuild" then
        local label = T.SavedBuildLabel(d.slot, d.name) or "the selected Saved Build"
        local state
        if d.unavailable then
            state = "not available right now"
        elseif d.empty then
            state = "empty: it holds no Echoes, so assigning to it is refused"
        elseif d.active == true then
            state = "active in the game"
        elseif d.active == false then
            state = "not active in the game"
        elseif d.unconfirmed then
            state = "not confirmed as the active Saved Build"
        end
        lines[#lines + 1] = "Destination: " .. label .. (state and (" - " .. state) or "")
    elseif d.kind == "firstRun" then
        lines[#lines + 1] = "Destination: first-run target (no Saved Build in use)"
    elseif d.kind == "unknown" then
        lines[#lines + 1] = d.reason == "restoring"
            and "Destination: not known yet (the saved assignment is being restored)"
            or "Destination: Saved Build data is not loaded yet"
    elseif d.kind == "unconfirmed" then
        lines[#lines + 1] = "Destination: not confirmed right now"
    else
        lines[#lines + 1] = "Destination: none captured"
    end
    local wishlist = T.SafeName(d.wishlist)
    local state = d.wishlistState
    if state == "assigned" then
        lines[#lines + 1] = "Wishlist: " .. (wishlist and (wishlist .. " (assigned)") or "assigned")
    elseif state == "unassigned" then
        lines[#lines + 1] = "Wishlist: none assigned"
    elseif state == "unavailable" then
        lines[#lines + 1] = "Wishlist: " .. (wishlist and (wishlist .. " - ") or "") .. "unavailable right now"
    elseif state == "restoring" then
        lines[#lines + 1] = "Wishlist: restoring the saved assignment"
    elseif wishlist then
        lines[#lines + 1] = "Wishlist: " .. wishlist
    end
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
    menuAndStatus = "Menu and status",
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
    .. "shared listings. Menu and status: the ... button on the Nexus panel."
