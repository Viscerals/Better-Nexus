-- Nexus: automatic local roll recorder.
--
-- Records, on this computer only, what the rolling policy saw, what it chose
-- and what the game showed afterwards, so that private test runs can be
-- compared with the policy's assumptions. It is observation only:
--   * it adds no poll, retry, roll, selection or spend, and no caller waits on
--     it: every entry point is protected and answers nil on any failure;
--   * it sends nothing anywhere and keeps no account, character, realm,
--     Wishlist or build name, no chat and no credential;
--   * it keeps at most CAP records of at most RECORD_BYTES text each, replaces
--     the oldest first, and marks every truncation, drop and gap.
-- A record is a flat table of numbers and short strings (no nested tables), is
-- written once per decision, and is updated in place while that record is the
-- newest one. The data is NOT a draw model: a board and its successor are
-- observations, not proof of server odds. docs/ADAPTIVE_ROLLING.md.

Nexus = Nexus or {}

local R = {name = "RollRecorder"}
Nexus.RollRecorder = R

R.SCHEMA = 1
R.HISTORY = "rollTrace"
-- Fixed work and size bounds. CAP lives in DiagnosticLogs (the ring owner).
-- The targets text gets recordBytes minus reserveBytes. Every other text field has
-- its own cap; their worst case after all later updates is about 1170 bytes
-- (decision-time fields about 360, lifecycle 400, ownership changes about 195,
-- after offers 54, confirmation basis 73, fate 40, submitted action 12, charges
-- 20, survival 12, incompleteness list 12).
R.LIMITS = {
    targets = 32,        -- exact Wishlist targets kept per decision
    recordBytes = 2048,  -- string bytes of one saved record
    reserveBytes = 1200, -- worst case of every field except the targets (see below)
    ioBytes = 400,       -- action lifecycle text per decision
    deltaEntries = 16,   -- ownership changes kept per decision
    detailBytes = 48,    -- boundary detail text
}

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local config = {}
local session, pending = nil, nil
local planCache = {plan = nil, ids = nil, count = 0}
local catalogCache = {revision = nil, version = nil}
local stats = {recorded = 0, updated = 0, skipped = 0, failed = 0, dropped = 0,
    truncated = 0, late = 0, lastError = nil, droppedSinceRecord = 0}

local function Number(value, default)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return default or 0 end
    return n
end
local function Int(value)
    local n = Number(value, 0)
    return n >= 0 and math.floor(n) or -math.floor(-n)
end
local function Clip(text, limit)
    text = tostring(text or "")
    if #text > limit then return text:sub(1, limit) end
    return text
end
local function Base36(value)
    local n = math.floor(Number(value, 0))
    if n <= 0 then return "0" end
    local out = ""
    while n > 0 do
        local digit = n % 36
        out = DIGITS:sub(digit + 1, digit + 1) .. out
        n = math.floor(n / 36)
    end
    return out
end
local function SafeText(value)
    local history = Nexus.DiagnosticHistory
    if history and type(history.SafeText) == "function" then
        return history.SafeText(value, 160)
    end
    return Clip(value, 160)
end

local function Clock()
    local now = config.now or GetTime
    local ok, value = pcall(now)
    return ok and Number(value, 0) or 0
end
local function Epoch()
    local source = config.epoch or time
    if type(source) ~= "function" then return 0 end
    local ok, value = pcall(source)
    return ok and Number(value, 0) or 0
end

-- Recording is on unless the saved setting is exactly false.
local function Active()
    if not (Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Append) then return false end
    local getter = config.enabled
    if type(getter) == "function" then
        local ok, value = pcall(getter)
        if ok and value == false then return false end
    end
    return true
end

local function Guard(label, callback, ...)
    local ok, first = pcall(callback, ...)
    if ok then return first end
    stats.failed = stats.failed + 1
    stats.dropped = stats.dropped + 1
    stats.droppedSinceRecord = stats.droppedSinceRecord + 1
    stats.lastError = label .. ": " .. SafeText(first)
    return nil
end

local function Measure(name, callback, ...)
    local performance = Nexus.Performance
    if performance and type(performance.Begin) == "function" then
        local okBegin, started = pcall(performance.Begin, name)
        local first = callback(...)
        if okBegin then pcall(performance.Finish, name, started) end
        return first
    end
    return callback(...)
end

local function Session()
    if not session then
        session = {tag = Base36(Epoch()), n = 0, runN = 0}
        session.run = session.tag .. "r0"
    end
    return session
end
local function Seq()
    local s = Session()
    s.n = s.n + 1
    return s.n
end

-- ---------------------------------------------------------------- encoding

local FLAG_LETTERS = {{"isGuaranteed", "G"}, {"isFrozen", "F"}, {"isCarried", "C"}, {"justFrozen", "J"}}
local function OfferText(board)
    local cards = board and board.cards
    if type(cards) ~= "table" then return "" end
    local parts = {}
    for i = 1, math.min(#cards, 3) do
        local card = cards[i]
        local flags = ""
        for _, pair in ipairs(FLAG_LETTERS) do
            if card[pair[1]] then flags = flags .. pair[2] end
        end
        if card.banishEligible == false then flags = flags .. "b" end
        if card.freezeEligible == false then flags = flags .. "f" end
        if card.selectable == false then flags = flags .. "u" end
        parts[i] = Int(card.spellId) .. "." .. (card.quality == nil and "-" or Int(card.quality)) .. "." .. flags
    end
    return table.concat(parts, ";")
end

local function ChargeText(charges)
    if type(charges) ~= "table" then return "" end
    local function C(value) return value == nil and "-" or tostring(Int(value)) end
    return C(charges.banish) .. "." .. C(charges.reroll) .. "." .. C(charges.freeze)
        .. "." .. (charges.trustworthy == true and "1" or "0")
end

local function CapabilityText(state, owned, locked)
    local out = {}
    if state.pending or state.pendingAction then out[#out + 1] = "P" end
    if state.ordinaryBoardAllowed == false then out[#out + 1] = "O" end
    if not owned or owned.synced ~= true then out[#out + 1] = "S" end
    if locked and locked.synced == false then out[#out + 1] = "L" end
    if state.allowBanish == false then out[#out + 1] = "b" end
    if state.allowReroll == false then out[#out + 1] = "r" end
    if state.allowFreeze == false then out[#out + 1] = "f" end
    if state.canFreeze == false then out[#out + 1] = "z" end
    local refused = state.searchRefused
    if type(refused) == "table" then
        if refused.banish then out[#out + 1] = "B" end
        if refused.reroll then out[#out + 1] = "R" end
    end
    return table.concat(out)
end

-- Sorted exact target ids of a plan. The plan table is reused by the runtime
-- while it is unchanged, so the sort is repeated only for a new plan.
local function TargetIds(plan)
    if planCache.plan == plan and planCache.ids then return planCache.ids, planCache.count end
    local ids, count = {}, 0
    for id in pairs(plan.requestedCounts or {}) do
        local n = tonumber(id)
        if n then ids[#ids + 1] = n end
    end
    table.sort(ids)
    count = #ids
    planCache.plan, planCache.ids, planCache.count = plan, ids, count
    return ids, count
end

-- Known eligibility of one exact Echo: bit 1 class, 2 level, 4 not disabled
-- by a lever opt-out, 8 below its stack cap. "x" = not known (no catalog row
-- or no player class), never guessed.
local function Eligibility(catalog, id, level, disabled, ordinary)
    local row = catalog and type(catalog.rows) == "table" and catalog.rows[id]
    local mask = catalog and tonumber(catalog.playerMask)
    if type(row) ~= "table" or not mask or mask <= 0 then return "x", 0, 0 end
    local bits = 0
    local model = Nexus.Model
    if model and type(model.MaskMatch) == "function" and model.MaskMatch(row.classMask, mask) then bits = bits + 1 end
    if (tonumber(row.minLevel) or 0) <= (tonumber(level) or 0) then bits = bits + 2 end
    local lever = tonumber(row.requiredSpell) or 0
    local leverBlocked = lever ~= 0 and type(catalog.levers) == "table" and catalog.levers[lever] ~= nil
        and type(disabled) == "table" and disabled[lever]
    if not leverBlocked then bits = bits + 4 end
    local cap = tonumber(row.maxStack) or 1
    if ordinary < cap then bits = bits + 8 end
    return string.format("%x", bits), cap, lever
end

local function TargetText(ctx, ids, count, ordinaryOut)
    local plan, owned, locked = ctx.plan, ctx.owned, ctx.locked
    local requested = plan.requestedCounts or {}
    local lockedTargets = plan.lockedRequestedCounts or {}
    local ordinary = owned and owned.bySpell or {}
    local held = locked and locked.bySpell or {}
    local parts, used, kept = {}, 0, 0
    local budget = R.LIMITS.recordBytes - R.LIMITS.reserveBytes
    for i = 1, math.min(count, R.LIMITS.targets) do
        local id = ids[i]
        local own = Int(ordinary[id])
        ordinaryOut[i] = own
        local el, cap, lever = Eligibility(ctx.catalog, id, ctx.level, ctx.disabledLevers, own)
        local entry = id .. "," .. Int(requested[id]) .. "," .. Int(lockedTargets[id]) .. "," .. own
            .. "," .. Int(held[id]) .. "," .. cap .. "," .. el .. "," .. lever
        if used + #entry + 1 > budget then break end
        parts[#parts + 1] = entry
        used = used + #entry + 1
        kept = i
    end
    return table.concat(parts, ";"), kept
end

-- ---------------------------------------------------------------- recording

local function CatalogVersion(revision)
    if catalogCache.revision == revision and catalogCache.version then return catalogCache.version end
    local version = "unknown"
    local adapter = Nexus.GameAdapter
    if adapter and type(adapter.CatalogStatus) == "function" then
        local ok, status = pcall(adapter.CatalogStatus)
        if ok and type(status) == "table" and status.publishedHash then
            version = Clip(status.publishedHash, 24)
        end
    end
    catalogCache.revision, catalogCache.version = revision, version
    return version
end

local function BuildLabel()
    if type(Nexus.RuntimeBuildLabel) ~= "function" then return "source" end
    local ok, value = pcall(Nexus.RuntimeBuildLabel)
    return ok and Clip(value, 40) or "source"
end

local classCache = nil
local function ClassToken()
    if classCache then return classCache end
    if type(UnitClass) ~= "function" then return "?" end
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" and token ~= "" then
        classCache = Clip(token, 16)
        return classCache
    end
    return "?"
end

local function Store(record)
    local ok, why = Nexus.DiagnosticLogs.Append(R.HISTORY, record)
    if ok then
        stats.recorded = stats.recorded + 1
        stats.droppedSinceRecord = 0
        return true
    end
    stats.dropped = stats.dropped + 1
    stats.droppedSinceRecord = stats.droppedSinceRecord + 1
    stats.lastError = "append: " .. SafeText(why)
    return false
end

-- Update the pending decision's own record while it is the newest one. When
-- another record was written since, the late fact is written as its own small
-- record that names the decision (`ref`), so the link is never lost.
local function UpdatePending(p, fields)
    local logs = Nexus.DiagnosticLogs
    local applied = false
    if logs.UpdateLast then
        local ok = logs.UpdateLast(R.HISTORY, function(entry)
            if entry.s ~= p.s or entry.n ~= p.n then return false end
            for key, value in pairs(fields) do
                if key == "io" and type(entry.io) == "string" then
                    local joined = entry.io .. "," .. value
                    if #joined > R.LIMITS.ioBytes then
                        joined = joined:sub(1, R.LIMITS.ioBytes)
                        local inc = entry.inc or ""
                        if not inc:find("io", 1, true) then entry.inc = inc == "" and "io" or (inc .. ",io") end
                    end
                    entry.io = joined
                elseif key == "inc" then
                    local inc = entry.inc or ""
                    if not (("," .. inc .. ","):find("," .. value .. ",", 1, true)) then
                        entry.inc = inc == "" and value or (inc .. "," .. value)
                    end
                else
                    entry[key] = value
                end
            end
        end)
        applied = ok == true
    end
    if applied then
        stats.updated = stats.updated + 1
        return true
    end
    local late = {v = R.SCHEMA, k = "O", s = p.s, n = Seq(), run = p.run, t = Clock(), ref = p.n}
    for key, value in pairs(fields) do late[key] = value end
    stats.late = stats.late + 1
    return Store(late)
end

function R.Configure(options)
    config = {}
    if type(options) == "table" then
        for key, value in pairs(options) do config[key] = value end
    end
end

function R.Reset()
    session, pending = nil, nil
    planCache.plan, planCache.ids, planCache.count = nil, nil, 0
    catalogCache.revision, catalogCache.version = nil, nil
    classCache = nil
    for key in pairs(stats) do stats[key] = key == "lastError" and nil or 0 end
end

-- ctx: state (the policy input), action (its result), board, owned, locked,
-- plan, catalog, level, horizon, charges, disabledLevers, activeSlot,
-- catalogRevision. Returns the opaque decision id, or nil.
function R.Decision(ctx)
    return Guard("decision", function()
        if type(ctx) ~= "table" or type(ctx.plan) ~= "table" then return nil end
        if not Active() then stats.skipped = stats.skipped + 1; return nil end
        return Measure("rolltrace.decision", function()
            local s = Session()
            local state, action = ctx.state or {}, ctx.action or {}
            local ids, count = TargetIds(ctx.plan)
            local ordinary = {}
            local targets, kept = TargetText(ctx, ids, count, ordinary)
            local incomplete = {}
            if kept < count then incomplete[#incomplete + 1] = "tg" end
            if not ctx.owned or ctx.owned.synced ~= true then incomplete[#incomplete + 1] = "ow" end
            if not (ctx.catalog and tonumber(ctx.catalog.playerMask)) then incomplete[#incomplete + 1] = "el" end
            if not (ctx.charges and ctx.charges.trustworthy == true) then incomplete[#incomplete + 1] = "ch" end
            local n = Seq()
            local record = {
                v = R.SCHEMA, k = "D", s = s.tag, n = n, run = s.run, t = Clock(),
                b = BuildLabel(),
                pol = action.policyId or "none", prof = action.policyProfile or "none",
                req = action.policyRequested, fb = action.fallbackReason,
                cv = CatalogVersion(ctx.catalogRevision),
                lvl = Int(ctx.level), hz = ctx.horizon ~= nil and Int(ctx.horizon) or nil,
                cls = ClassToken(), slot = Int(ctx.activeSlot),
                cp = CapabilityText(state, ctx.owned, ctx.locked),
                ch = ChargeText(ctx.charges),
                of = OfferText(ctx.board),
                pr = Clip(tostring(action.type) .. ":" .. Int(action.index) .. ":" .. Int(action.spellId)
                    .. ":" .. tostring(action.reasonCode or action.reason or ""), 96),
                tg = targets, tn = count, ex = ctx.plan.explicitRoles and 1 or 0,
            }
            if stats.droppedSinceRecord > 0 then record.pd = stats.droppedSinceRecord end
            if #incomplete > 0 then record.inc = table.concat(incomplete, ","); stats.truncated = stats.truncated + (kept < count and 1 or 0) end
            if not Store(record) then pending = nil; return nil end
            local held, heldFirst = 0, nil
            for _, card in ipairs(ctx.board and ctx.board.cards or {}) do
                if card.isFrozen or card.isCarried or card.justFrozen then
                    held = held + 1
                    heldFirst = heldFirst or Int(card.spellId)
                end
            end
            pending = {s = s.tag, n = n, run = s.run, id = s.tag .. "-" .. n,
                sig = ctx.board and ctx.board.signature, ids = ids, kept = kept, ordinary = ordinary,
                kind = action.type, index = action.index, spell = Int(action.spellId),
                held = held, heldId = heldFirst, lastReason = nil}
            return pending.id
        end)
    end)
end

-- Compact identity of one action: kind letter, offer index, spell id.
local ACTION_CODES = {take = "t", banish = "b", freeze = "f", reroll = "r"}
local function ActionTag(info)
    if type(info) ~= "table" or ACTION_CODES[info.type] == nil then return nil end
    return ACTION_CODES[info.type] .. Int(info.index) .. "." .. Int(info.spellId)
end

-- One action-intent state change of the decision `id` (the runtime's own
-- lifecycle states: prepared, submitted, confirmed, uncertain, expired,
-- rejected, superseded).
function R.Intent(id, state, reason, info)
    return Guard("intent", function()
        if not id or not Active() then return nil end
        return Measure("rolltrace.intent", function()
            local p = pending
            local open = p ~= nil and p.id == id
            if not open then
                -- The decision is no longer the open one (boundary, reload):
                -- keep the fact with its link instead of dropping it.
                local s, n = tostring(id):match("^(.-)%-(%d+)$")
                if not s then return nil end
                p = {s = s, n = tonumber(n), run = Session().run}
            else
                p.lastReason = Clip(reason, 40)
            end
            info = type(info) == "table" and info or {}
            local tag = ActionTag(info)
            -- Every prepared intent names its own action; a later state of the same
            -- intent names it only when it differs. A late record has no context, so
            -- it always names it.
            local named = tag ~= nil and (not open or state == "prepared" or p.cur ~= tag)
            if open and tag ~= nil then p.cur = tag end
            local text = Clip(tostring(state) .. ":" .. tostring(reason or "") .. "@"
                .. string.format("%.1f", Number(info.elapsed, 0))
                .. (info.mutation and "!" or "") .. (named and ("=" .. tag) or ""), 100)
            local fields = {io = text}
            -- The action actually SUBMITTED is what the outcome is judged against, never
            -- the board's first proposal. Refused or superseded intents are not submissions.
            if state == "submitted" then
                if tag == nil then
                    fields.inc = "am"
                    if open then p.amb = true end
                else
                    fields.sa = tag
                    if open then
                        p.subs = (p.subs or 0) + 1
                        p.subKind, p.subSpell = info.type, Int(info.spellId)
                        if p.subs > 1 then fields.inc = "am" end
                    end
                end
            end
            return UpdatePending(p, fields)
        end)
    end)
end

-- The first observation after a decision: the next board, or no board. ctx:
-- board (nil when absent), owned, charges, basis ("next_board", "board_cleared").
function R.After(ctx)
    return Guard("after", function()
        local p = pending
        if not p or not Active() then return nil end
        pending = nil
        return Measure("rolltrace.after", function()
            ctx = type(ctx) == "table" and ctx or {}
            local fields = {cb = Clip(ctx.basis or "next_board", 32) .. ":" .. (p.lastReason or "no_intent")}
            if ctx.board then fields.af = OfferText(ctx.board) end
            if ctx.charges then fields.ac = ChargeText(ctx.charges) end
            if ctx.owned then
                local ordinary = ctx.owned.bySpell or {}
                local parts = {}
                for i = 1, p.kept do
                    local now = Int(ordinary[p.ids[i]])
                    if now ~= p.ordinary[i] then
                        if #parts >= R.LIMITS.deltaEntries then
                            fields.ao = table.concat(parts, ";") .. ";+"
                            parts = nil
                            break
                        end
                        parts[#parts + 1] = p.ids[i] .. ":" .. string.format("%+d", now - p.ordinary[i])
                    end
                end
                if parts then fields.ao = table.concat(parts, ";") end
            end
            if p.amb or (p.subs and p.subs > 1) then
                fields.inc = "am"
            elseif ctx.board then
                -- A first board that shows the spell as justFrozen (J) is "just frozen
                -- observed": neither kept (held F or carried C) nor gone, and not proof of
                -- the final result. Held and carried win when both are shown.
                if p.subKind == "freeze" then
                    local kept, just = false, false
                    for _, card in ipairs(ctx.board.cards or {}) do
                        if Int(card.spellId) == p.subSpell then
                            if card.isFrozen or card.isCarried then kept = true
                            elseif card.justFrozen then just = true end
                        end
                    end
                    fields.fz = kept and "set:kept" or (just and "set:just" or "set:gone")
                elseif p.held > 0 then
                    local kept, just = 0, 0
                    for _, card in ipairs(ctx.board.cards or {}) do
                        if Int(card.spellId) == p.heldId then
                            if card.isFrozen or card.isCarried then kept = kept + 1
                            elseif card.justFrozen then just = just + 1 end
                        end
                    end
                    fields.fz = "held:" .. (kept > 0 and "kept" or (just > 0 and "just" or "gone"))
                end
            end
            return UpdatePending(p, fields)
        end)
    end)
end

-- A boundary of the evidence: session start, run reset, loading screen, a
-- level change or the Auto switch. A run reset and a loading screen end the
-- open decision with an explicit fate; the others only mark the timeline.
function R.Boundary(kind, detail)
    return Guard("boundary", function()
        if not Active() then return nil end
        local s = Session()
        local closes = kind == "run" or kind == "world_leave" or kind == "world_enter"
        if closes and pending then
            local p = pending
            pending = nil
            UpdatePending(p, {fate = Clip("interrupted:" .. tostring(kind), 40)})
        end
        if kind == "run" then
            s.runN = s.runN + 1
            s.run = s.tag .. "r" .. s.runN
        end
        return Store({v = R.SCHEMA, k = "B", s = s.tag, n = Seq(), run = s.run, t = Clock(),
            kind = Clip(kind, 24), d = Clip(detail or "", R.LIMITS.detailBytes),
            b = kind == "session" and BuildLabel() or nil})
    end)
end

-- -------------------------------------------------------------------- report

function R.Status()
    local logs = Nexus.DiagnosticLogs
    local out = {schema = R.SCHEMA, enabled = Active(), limits = R.LIMITS,
        recorded = stats.recorded, updated = stats.updated, late = stats.late,
        skipped = stats.skipped, failed = stats.failed, dropped = stats.dropped,
        truncated = stats.truncated, lastError = stats.lastError,
        session = session and session.tag or nil, run = session and session.run or nil}
    -- Reading is passive: nothing is created or repaired here (DiagnosticLogs.Peek).
    if logs and logs.Peek then
        local records, info = logs.Peek(R.HISTORY)
        if records then
            out.retained, out.cap, out.evicted = #records, info.cap, info.dropped
        else
            out.unreadable = info
        end
    end
    return out
end

local function Esc(value)
    local text = tostring(value == nil and "" or value)
    return (text:gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("[\r\n]", " "))
end

local COLUMNS = {"k", "s", "n", "run", "t", "lvl", "hz", "cls", "slot", "pol", "prof", "req", "fb", "cv", "cp",
    "ch", "of", "pr", "tg", "tn", "ex", "io", "af", "ac", "ao", "fz", "cb", "fate", "sa", "inc", "pd", "ref",
    "kind", "d", "b"}

-- The lines a tester sends: a header, then one line per saved record; blank =
-- not recorded. Used by the Roll trace tab and by the prepared support report.
function R.ExportLines()
    local logs = Nexus.DiagnosticLogs
    local records, why = {}, nil
    if logs and logs.Peek then records, why = logs.Peek(R.HISTORY) end
    local unreadable = records == nil
    records = records or {}
    local status = R.Status()
    local out = {
        "NEXUS_ROLL_TRACE_" .. R.SCHEMA .. (unreadable and (" (record not read: " .. tostring(why) .. ")") or ""),
        "build=" .. Esc(BuildLabel()) .. "|retained=" .. #records .. "|cap=" .. tostring(status.cap)
            .. "|evicted=" .. tostring(status.evicted) .. "|failed=" .. status.failed
            .. "|dropped=" .. status.dropped .. "|late=" .. status.late,
        "LOCAL RECORD made by Nexus on this computer. No account, character or realm name, Wishlist name, chat or credential is kept. Nothing is sent anywhere. Send it only privately.",
        "NOT A DRAW MODEL. A board and the next board are observations. They do not prove server odds, and a proposed action is not a result.",
        "D=decision B=boundary O=late outcome. Offers id.quality.flags (G guaranteed F frozen C carried J justFrozen b no-Banish f no-Freeze u unselectable). Targets id,requested,lockedTarget,ordinary,locked,cap,eligibility,requiredSpell. Eligibility hex: 1 class 2 level 4 lever-ok 8 below-cap, x unknown. Charges banish.reroll.freeze.trusted. inc = parts known to be incomplete (am = the submitted action is ambiguous). io = lifecycle: each prepared intent is followed by =<action>; actions are t take, b banish, f freeze, r reroll as <letter><offer index>.<spell id>. sa = the action actually SUBMITTED (the last accepted one); the Freeze outcome fz is judged on it, not on the proposal pr (set:kept = held F or carried C, set:just = the first board showed it as J, just frozen observed, not proof of the final result, set:gone = not on the board; held:* is the same for a held offer after another action); af and ao are observations of the next board whatever was sent. When another record was written between two events, read the rows that name the same decision (ref) together. Ownership fields (tg, ao) cover the Wishlist targets only, not the full ownership.",
        table.concat(COLUMNS, "|"),
    }
    for _, record in ipairs(records) do
        if type(record) == "table" then
            local row = {}
            for i, column in ipairs(COLUMNS) do row[i] = Esc(record[column]) end
            out[#out + 1] = table.concat(row, "|")
        end
    end
    return out
end

-- The text a tester copies from the Roll trace tab.
function R.Export()
    return table.concat(R.ExportLines(), "\n")
end
