-- Nexus: ui/OrbHistory.lua
-- Presentation projection for the Orb run log. Pure: no frames, no WoW API,
-- no gameplay calls and no Orb runtime calls, so it loads under bare LuaJIT
-- for the offline suite and can be asserted directly.
--
-- It turns one RunLog view (the runtime's own structured record) into rows,
-- details and report text. It reads recorded fields only. It never infers a
-- result, an offer, a reason or a name that the runtime did not record, and it
-- never turns a runtime outcome into "success": every label below maps one
-- recorded state or one recorded selection kind, and anything else is stated
-- as unknown.

Nexus = Nexus or {}
local M = {}
Nexus.OrbHistory = M

-- The addon's Echo rarity mapping, the same words and colours the Wishlist
-- overlay and renderer use. Echo quality is its own scale: it is NOT mapped
-- through a WoW item-quality offset, and an unlisted value stays unknown.
M.QUALITY_NAMES = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare",
    [3] = "Epic", [4] = "Legendary",
}
M.QUALITY_COLORS = {
    [0] = { 1, 1, 1 },
    [1] = { 0.12, 1, 0.12 },
    [2] = { 0.2, 0.6, 1 },
    [3] = { 0.72, 0.36, 0.98 },
    [4] = { 1, 0.65, 0 },
}
local UNKNOWN_COLOR = { 0.68, 0.68, 0.70 }

-- One recorded runtime state, one plain label. "Confirmed" is the only label
-- that claims a replacement happened.
local RESULTS = {
    ["confirmed"] = { label = "Confirmed", confirmed = true },
    ["selected"] = { label = "Awaiting result", pending = true },
    ["offered"] = { label = "Waiting for choice", pending = true },
    ["requested"] = { label = "Waiting for offer", pending = true },
    ["submitted"] = { label = "Unconfirmed", pending = true },
    ["not sent"] = { label = "Not sent", refused = true },
    ["unknown"] = { label = "Unconfirmed", unresolved = true },
    ["paused"] = { label = "Paused", pending = true },
}
M.RESULTS = RESULTS

local FALLBACK_DETAIL =
    "Not a missing exact Wishlist target; chosen under the approved fallback "
    .. "rule. It may be replaced again only after the normal safety checks."

-- One recorded selection kind, one plain reason. "Manual choice" is only ever
-- produced from a recorded manual selection, so it cannot appear for a policy
-- decision.
local REASONS = {
    ["TARGET"] = { label = "Missing Wishlist target" },
    ["RECYCLE"] = { label = "Reusable fallback", detail = FALLBACK_DETAIL },
    ["FALLBACK"] = { label = "Reusable fallback", detail = FALLBACK_DETAIL },
    ["MANUAL"] = { label = "Manual choice" },
}
M.REASONS = REASONS

-- The run states the header shows as one sentence. The technical report keeps
-- the raw state and the runtime's own reason string.
local RUN_STATES = {
    IDLE = "Not started", READY = "Preparing next replacement",
    WAIT_OFFER = "Waiting for the Orb offer",
    WAIT_RESULT = "Waiting for result confirmation",
    PAUSED = "Paused", STOPPED = "Stopped",
    COMPLETE = "Targets complete", ROLLED_COMPLETE = "Rolled targets complete",
    LIMIT = "Maximum reached", OUT_OF_ORBS = "No Orbs remain",
    NO_SOURCES = "No safe surplus copies remain",
    RECOVERY = "Previous result is unresolved",
    FINISHED = "Finished - Orb limit reached",
}
M.RUN_STATES = RUN_STATES

M.SESSION_NOTE = "History clears on reload or logout."

-- Display-only sanitising for a recorded label. A pipe is doubled because a
-- FontString interprets pipe sequences; control characters become spaces. The
-- value itself is never rewritten, only its projection.
local function display(value, limit)
    return (tostring(value or ""):gsub("|", "||"):gsub("%c", " "))
        :sub(1, limit or 60)
end
M.Display = display

function M.Rarity(quality)
    local q = tonumber(quality)
    local label = q and M.QUALITY_NAMES[q]
    if not label then
        return { label = "Unknown quality", color = UNKNOWN_COLOR,
            known = false, quality = q }
    end
    return { label = label, color = M.QUALITY_COLORS[q], known = true,
        quality = q }
end

-- A recorded key is "<spellId>:<quality>". It is the identity the runtime
-- wrote down, so parsing it is reading, not guessing.
function M.Identity(key)
    if type(key) ~= "string" then return nil end
    local id, quality = key:match("^(%d+):(%d+)$")
    if not id then return nil end
    return tonumber(id), tonumber(quality)
end

-- The name the runtime recorded for this exact key, if it recorded one. The
-- offer list carries names for the three choices; sourceName carries the
-- source's. Nothing else is searched.
local function recordedName(entry, key, spellId)
    if type(entry) ~= "table" or not key then return nil end
    if entry.sourceKey == key and entry.sourceName then
        return tostring(entry.sourceName)
    end
    for _, offer in ipairs(entry.offered or {}) do
        if offer.spellId == spellId and offer.name then
            return tostring(offer.name)
        end
    end
    return nil
end

-- One Echo cell. resolve(spellId) is an optional bounded, read-only lookup of
-- that exact id supplied by the caller; it may return a label and an icon.
-- A name that cannot be resolved stays usable: "Unknown Echo (200728)".
function M.Echo(key, entry, resolve)
    local spellId, quality = M.Identity(key)
    if not spellId then
        return { known = false, label = "Not recorded",
            rarity = M.Rarity(nil), recorded = false }
    end
    local label, icon = recordedName(entry, key, spellId), nil
    local source = label and "recorded" or nil
    if not label and type(resolve) == "function" then
        local found, foundIcon = resolve(spellId)
        if found and found ~= "" then label, source = tostring(found), "looked up" end
        icon = foundIcon
    elseif type(resolve) == "function" then
        local _, foundIcon = resolve(spellId)
        icon = foundIcon
    end
    return {
        known = true, recorded = true, spellId = spellId, key = key,
        label = label and display(label) or ("Unknown Echo (" .. spellId .. ")"),
        resolved = label ~= nil, labelSource = source or "unresolved",
        icon = icon, rarity = M.Rarity(quality),
    }
end

local function resultOf(entry)
    local state = entry and entry.state
    local mapped = state and RESULTS[state]
    if mapped then
        return { label = mapped.label, confirmed = mapped.confirmed == true,
            pending = mapped.pending == true, refused = mapped.refused == true,
            unresolved = mapped.unresolved == true, state = state }
    end
    return { label = "Unconfirmed", unresolved = true,
        state = state and tostring(state) or "not recorded" }
end
M.Result = resultOf

local function reasonOf(entry)
    local kind = entry and entry.selectionKind
    local mapped = kind and REASONS[tostring(kind):upper()]
    if mapped then
        return { label = mapped.label, detail = mapped.detail,
            recorded = entry.selectionReason }
    end
    -- A recorded reason with no recognised kind is shown as it was recorded,
    -- never re-worded into one of the mapped labels.
    if entry and entry.selectionReason then
        return { label = display(entry.selectionReason, 40),
            recorded = entry.selectionReason, verbatim = true }
    end
    return { label = "Reason unavailable" }
end
M.Reason = reasonOf

-- One row per recorded operation on the page the caller asked the runtime for.
function M.Rows(view, resolve)
    local rows = {}
    for _, entry in ipairs(view and view.entries or {}) do
        local result = resultOf(entry)
        local replacement
        if entry.obtained then
            replacement = M.Echo(entry.obtained, entry, resolve)
            replacement.confirmed = true
        elseif entry.selectedKey then
            -- A selected choice is not a received result. It is labelled
            -- proposed until the runtime records a confirmation.
            replacement = M.Echo(entry.selectedKey, entry, resolve)
            replacement.proposed = true
            replacement.label = replacement.label .. " (proposed)"
        else
            replacement = { known = false, recorded = false,
                label = result.refused and "No replacement" or "Not recorded",
                rarity = M.Rarity(nil) }
        end
        rows[#rows + 1] = {
            ordinal = entry.ordinal, serial = entry.serial,
            source = M.Echo(entry.sourceKey, entry, resolve),
            replacement = replacement,
            reason = reasonOf(entry),
            result = result,
            entry = entry,
        }
    end
    return rows
end

-- The offers exactly as they were recorded. A missing offer list says so; it
-- is never reconstructed from current ownership or from the board.
function M.Offers(entry, resolve)
    if type(entry) ~= "table" or type(entry.offered) ~= "table"
        or #entry.offered == 0 then
        return nil
    end
    local offers = {}
    for index, offer in ipairs(entry.offered) do
        local key = tostring(offer.spellId) .. ":" .. tostring(offer.quality)
        local echo = M.Echo(key, entry, resolve)
        echo.index = index
        echo.selected = entry.selectedKey == key
        echo.confirmed = entry.obtained == key
        offers[#offers + 1] = echo
    end
    return offers
end

-- Everything recorded about one operation, for the details area. Nothing here
-- is computed from the present: no durations from a single timestamp, no
-- current ownership, no prediction.
function M.Details(entry, resolve, runStartedAt)
    if type(entry) ~= "table" then return nil end
    local result = resultOf(entry)
    local reason = reasonOf(entry)
    local details = {
        ordinal = entry.ordinal, serial = entry.serial,
        result = result, reason = reason,
        offers = M.Offers(entry, resolve),
        offersNote = (not entry.offered or #entry.offered == 0)
            and "Offer not recorded" or nil,
        source = M.Echo(entry.sourceKey, entry, resolve),
        -- sourceCopies is the eligible surplus the policy saw at selection.
        -- It is NOT a count of copies sacrificed, and is not labelled as one.
        eligibleSurplus = entry.sourceCopies,
        recycled = entry.recycle == true,
        note = entry.reason and display(entry.reason, 240) or nil,
        technical = {
            state = entry.state, sourceKey = entry.sourceKey,
            sourceQuality = entry.sourceQuality,
            selectedKey = entry.selectedKey, selectionKind = entry.selectionKind,
            selectionReason = entry.selectionReason,
            obtained = entry.obtained, recordedAt = entry.at,
            confirmedAt = entry.confirmedAt, reason = entry.reason,
        },
    }
    if entry.obtained then
        details.consumed = details.source
        details.received = M.Echo(entry.obtained, entry, resolve)
    elseif entry.selectedKey then
        details.proposedSource = details.source
        details.proposedReplacement = M.Echo(entry.selectedKey, entry, resolve)
    end
    -- A relative time only when both ends were recorded; one timestamp alone
    -- is never turned into a duration.
    local at, start = tonumber(entry.at), tonumber(runStartedAt)
    if at and start and at >= start then
        details.sinceStart = at - start
    end
    if tonumber(entry.confirmedAt) and at and tonumber(entry.confirmedAt) >= at then
        details.toConfirm = tonumber(entry.confirmedAt) - at
    end
    return details
end

function M.Header(view)
    if not view or not view.runId then
        return { empty = true, title = "Orb history",
            status = "No run has been started in this session.",
            sessionNote = M.SESSION_NOTE }
    end
    local spent, limit = tonumber(view.spent) or 0, tonumber(view.limit) or 0
    local reserved = tonumber(view.reserved) or 0
    return {
        title = "Orb history",
        which = view.which,
        runLabel = "Run " .. tostring(view.runId),
        wishlist = display(view.wishlist or "none", 48),
        status = RUN_STATES[view.state] or tostring(view.state or "unknown"),
        usage = "Orbs used: " .. spent .. " / " .. limit,
        increased = view.increased == true,
        pending = reserved > 0 and
            (reserved .. " unresolved operation" .. (reserved == 1 and "" or "s")
                .. ": the run is not settled.") or nil,
        truncated = view.truncated == true and
            "The history reached its bound; later operations are not listed."
            or nil,
        total = view.total or 0,
        hasPrevious = view.hasPrevious == true,
        hasCurrent = view.hasCurrent == true,
        sessionNote = M.SESSION_NOTE,
    }
end

function M.PageLabel(total, page, rows)
    total = tonumber(total) or 0
    rows = math.max(1, tonumber(rows) or 1)
    if total == 0 then return "No operations recorded" end
    local first = (math.max(1, tonumber(page) or 1) - 1) * rows + 1
    local last = math.min(total, first + rows - 1)
    return "Operations " .. first .. "-" .. last .. " of " .. total
end

function M.Pages(total, rows)
    return math.max(1, math.ceil((tonumber(total) or 0)
        / math.max(1, tonumber(rows) or 1)))
end

local function line(out, text) out[#out + 1] = text end

-- The report the player copies. Readable by default; technical adds the
-- identities and recorded state fields an error report needs. Both formats
-- describe the SAME recorded operations, and neither drops an operation.
function M.Report(view, resolve, technical)
    local out = {}
    local header = M.Header(view)
    if header.empty then
        line(out, "Nexus Orb history: no run has been started in this session.")
        return table.concat(out, "\n")
    end
    line(out, "Nexus Orb history (" .. tostring(view.which or "current")
        .. " run). " .. M.SESSION_NOTE)
    line(out, "Run " .. tostring(view.runId) .. "; build "
        .. tostring(view.build or "unknown"))
    line(out, "Assigned Wishlist at start: " .. tostring(view.wishlist or "none"))
    line(out, "Approved maximum: " .. tostring(view.limit)
        .. (header.increased and " (increased during the run)" or "")
        .. "; confirmed usage: " .. tostring(view.spent or 0)
        .. "; unresolved exposure: " .. tostring(view.reserved or 0))
    line(out, "Stopping state: " .. header.status
        .. (view.reason and ("; " .. tostring(view.reason)) or ""))
    line(out, "Operations recorded: " .. tostring(view.total or 0))
    if header.truncated then line(out, "Note: " .. header.truncated) end
    if technical then
        line(out, "Character: " .. tostring(view.character or "unknown")
            .. "; run identity " .. tostring(view.runId)
            .. "; revision " .. tostring(view.revision))
    end
    line(out, "")
    for _, row in ipairs(M.Rows(view, resolve)) do
        local entry = row.entry
        local text = tostring(row.ordinal) .. ". " .. row.source.label
            .. " (" .. row.source.rarity.label .. ")"
        if row.replacement.confirmed then
            text = text .. " -> " .. row.replacement.label
                .. " (" .. row.replacement.rarity.label .. ")"
        elseif row.replacement.proposed then
            text = text .. " -> " .. row.replacement.label
                .. " (" .. row.replacement.rarity.label .. ")"
        else
            text = text .. " -> " .. row.replacement.label
        end
        text = text .. ". " .. row.reason.label .. ". " .. row.result.label .. "."
        line(out, text)
        if entry.reason then line(out, "    " .. tostring(entry.reason)) end
        if technical then
            local offers = {}
            for _, offer in ipairs(entry.offered or {}) do
                offers[#offers + 1] = tostring(offer.spellId) .. ":"
                    .. tostring(offer.quality)
                    .. (offer.name and (" " .. tostring(offer.name)) or "")
            end
            line(out, "    serial=" .. tostring(entry.serial)
                .. " state=" .. tostring(entry.state)
                .. " source=" .. tostring(entry.sourceKey)
                .. " eligible surplus=" .. tostring(entry.sourceCopies)
                .. " recycle=" .. tostring(entry.recycle == true))
            line(out, "    offered=" .. (#offers > 0 and table.concat(offers, ", ")
                or "not recorded")
                .. "; selected=" .. tostring(entry.selectedKey)
                .. " (" .. tostring(entry.selectionKind) .. "/"
                .. tostring(entry.selectionReason) .. ")"
                .. "; obtained=" .. tostring(entry.obtained))
            line(out, "    recordedAt=" .. tostring(entry.at)
                .. " confirmedAt=" .. tostring(entry.confirmedAt))
        end
    end
    return table.concat(out, "\n")
end

return M
