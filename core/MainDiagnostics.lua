-- Nexus: core/MainDiagnostics.lua
-- Passive diagnostic page, audit-history, clear-routing, and export owner.

Nexus = Nexus or {}
if type(Nexus.MainInternals) ~= "table" then Nexus.MainInternals = {} end

local Diagnostics = {}
Nexus.MainInternals.Diagnostics = Diagnostics

function Diagnostics.New(options)
    options = options or {}
    local Nexus = assert(options.nexus, "MainDiagnostics requires Nexus")
    local Adapter = assert(options.adapter, "MainDiagnostics requires GameAdapter")
    local Model = assert(options.model, "MainDiagnostics requires Model")
    local Strategy = assert(options.strategy, "MainDiagnostics requires Strategy")
    local Store = assert(options.store, "MainDiagnostics requires Store")
    local WishlistWithLockTargets = assert(options.wishlistWithLockTargets,
        "MainDiagnostics requires wishlist projection")
    local LockDesignTargetsFor = assert(options.lockDesignTargetsFor,
        "MainDiagnostics requires lock-design projection")
    local EffectiveFlags = assert(options.effectiveFlags,
        "MainDiagnostics requires effective flags")
    local ErrorText = options.errorText or function(value) return tostring(value) end
    local GetTime = options.now or function() return 0 end

    local function AppendAudit(kind, fields)
        local logs = Nexus.DiagnosticLogs
        if not (logs and type(logs.Append) == "function") then return false end
        local entry = {}
        if type(fields) == "table" then
            for key, value in pairs(fields) do entry[key] = value end
        end
        entry.kind = kind
        entry.t = date and date("%H:%M:%S") or ""
        entry.run = options.getAuditRunId and options.getAuditRunId() or 0
        return logs.Append("runAudit", entry)
    end

    local function AppendAutoLockEvent(fields)
        local logs = Nexus.DiagnosticLogs
        if not (logs and type(logs.Append) == "function") then return false end
        local entry = {}
        if type(fields) == "table" then
            for key, value in pairs(fields) do entry[key] = value end
        end
        entry.t = date and date("%H:%M:%S") or ""
        return logs.Append("autoLock", entry)
    end

local function LogText_AutoLock()
    local lastAutoLockTrace = options.getAutoLockTrace and options.getAutoLockTrace() or {}
    if type(lastAutoLockTrace) ~= "table" then lastAutoLockTrace = {} end
    local age = lastAutoLockTrace.at and (GetTime() - lastAutoLockTrace.at) or nil
    local out = { string.format("AUTO-LOCK TRACE (last run %s ago)",
        age and string.format("%.1fs", age) or "never") , "" }
    for _, line in ipairs(lastAutoLockTrace.lines or {}) do
        out[#out + 1] = line
    end
    if #(lastAutoLockTrace.lines or {}) == 0 then
        out[#out + 1] = "(no trace recorded yet -- Step() may not have run; check /nexus err)"
    end
    out[#out + 1] = ""

    -- The raw committed table TryAutoLock actually reads (see
    -- LockDesignTargetsFor/CommitLockDesignTargets) -- LogText_Locked shows
    -- a live re-derivation from LockedOwned()/Wishlist(), which is close but
    -- not the same thing as what automation is actually keyed off.
    out[#out + 1] = "COMMITTED LOCK-DESIGN TARGETS (what TryAutoLock is actually working from):"
    local wl = Adapter.Wishlist()
    if wl then
        local targets = LockDesignTargetsFor(wl)
        local catalog = Adapter.Catalog()
        local ids = {}
        for spellIdKey in pairs(type(targets) == "table" and targets or {}) do
            ids[#ids + 1] = tonumber(spellIdKey)
        end
        table.sort(ids)
        if #ids == 0 then
            out[#out + 1] = "  (none committed for this wishlist)"
        else
            -- Fulfilled (already really locked) entries are deliberately
            -- kept in this table now, not deleted -- see TryAutoLock's
            -- comment. Flagged here so a fulfilled design doesn't read as
            -- "still pending" in the log.
            local lockedNow = Adapter.LockedOwned and Adapter.LockedOwned()
            local lockedBySpellNow = (lockedNow and lockedNow.bySpell) or {}
            for _, id in ipairs(ids) do
                local target = targets[id]
                local copies = type(target) == "table"
                    and (tonumber(target.copies) or 1) or 1
                local replaces = type(target) == "table"
                    and target.replaces or target
                local row = catalog and catalog.rows and catalog.rows[id]
                local name = (row and row.name) or ("spell " .. tostring(id))
                local fulfilled = (tonumber(lockedBySpellNow[id]) or 0) >= copies
                local suffix = fulfilled and " [FULFILLED -- already locked]"
                    or string.format(" [copies %d]", copies)
                if type(replaces) == "number" then
                    local rrow = catalog and catalog.rows and catalog.rows[replaces]
                    out[#out + 1] = string.format("  %s (id=%d) -- replaces %s (id=%d)%s",
                        name, id, (rrow and rrow.name) or ("spell " .. tostring(replaces)), replaces,
                        suffix)
                else
                    out[#out + 1] = string.format(
                        "  %s (id=%d) -- fresh target, no replacement pairing%s", name, id, suffix)
                end
            end
        end
    else
        out[#out + 1] = "  (no wishlist resolved)"
    end
    out[#out + 1] = ""

    -- lastAutoLockTrace above is a single-tick snapshot, overwritten every
    -- poll -- by the time a full diagnostic export is taken, it only reflects
    -- whatever the last tick looked like. This is the durable history: every
    -- actual LockPerk/UnlockPerk attempt this session, oldest first.
    out[#out + 1] = "LOCK/UNLOCK EVENT HISTORY (actual write attempts only, oldest first):"
    local hist = Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Snapshot
        and Nexus.DiagnosticLogs.Snapshot("autoLock") or {}
    if #hist == 0 then
        out[#out + 1] = "  (empty -- no LockPerk/UnlockPerk attempts recorded yet this session)"
    else
        for _, e in ipairs(hist) do
            if e.action == "lock" then
                out[#out + 1] = string.format("  [%s] LOCK %s (id=%s) ok=%s%s",
                    tostring(e.t), tostring(e.name), tostring(e.spellId), tostring(e.ok),
                    e.ok and "" or (" err=" .. tostring(e.err)))
            else
                out[#out + 1] = string.format("  [%s] UNLOCK %s (id=%s) for %s [%s pairing] ok=%s%s",
                    tostring(e.t), tostring(e.name), tostring(e.spellId), tostring(e.forName),
                    tostring(e.pairing), tostring(e.ok), e.ok and "" or (" err=" .. tostring(e.err)))
            end
        end
    end
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------
-- Log viewer data providers (/wr log). Pure text assembly; the viewer
-- renders whatever these return, one tab each.
-- ---------------------------------------------------------------------

local function FamLabel(catalog, fam)
    local nm = catalog and catalog.familyName and catalog.familyName[fam]
    return nm and (tostring(fam) .. " '" .. tostring(nm) .. "'") or tostring(fam)
end

local function DiagnosticTable(value)
    return type(value) == "table" and value or {}
end

local function DiagnosticScalar(value)
    local kind = type(value)
    if kind == "nil" then return "" end
    if kind == "string" or kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    return "<" .. kind .. ">"
end

local function LogText_Automation()
    local stats = {}
    if type(Adapter.LevelBurstStats) == "function" then
        local ok, value = pcall(Adapter.LevelBurstStats)
        if ok and type(value) == "table" then stats = value end
    end
    local function N(key)
        local value = tonumber(stats[key]) or 0
        if value ~= value or value >= math.huge or value <= -math.huge then
            return 0
        end
        return math.max(0, math.min(2147483647, math.floor(value)))
    end
    return table.concat({
        "AUTOMATION DIAGNOSTICS (bounded sanitized scalars)",
        string.format(
            "level burst events=%d bursts=%d coalesced=%d pending=%d queue_high_water=%d",
            N("events"),N("bursts"),N("coalesced"),N("pending"),
            N("queueHighWater")),
        string.format(
            "level burst pumps=%d recomputes=%d renders=%d actions=%d last_events=%d last_level=%d work_last=%d work_max=%d",
            N("pumps"),N("recomputes"),N("renders"),N("actions"),
            N("lastEvents"),N("lastLevel"),N("lastWorkPerPump"),
            N("maxWorkPerPump")),
    }, "\n")
end

local function RuntimeBuildLabel()
    if type(Nexus.RuntimeBuildLabel) ~= "function" then return "source" end
    local ok, value = pcall(Nexus.RuntimeBuildLabel)
    return ok and type(value) == "string" and value or "source"
end

local function LogText_Boards()
    local log = Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Snapshot
        and Nexus.DiagnosticLogs.Snapshot("decision") or {}
    local out = { string.format("DECISION LOG -- %d boards (v%s)",
        #log, Nexus.VERSION), "" }
    local first = math.max(1, #log - 39)
    if first > 1 then
        out[#out + 1] = string.format("(showing newest 40 of %d boards; use Clear Log in this window)", #log)
        out[#out + 1] = ""
    end
    for i = first, #log do
        local e = DiagnosticTable(log[i])
        local proposal = DiagnosticTable(e.proposal)
        local charges = DiagnosticTable(e.charges)
        local cards = DiagnosticTable(e.cards)
        local users = DiagnosticTable(e.user)
        out[#out + 1] = string.format("== #%d [%s] L%s H:%s%s  charges B:%s R:%s F:%s%s",
            i, DiagnosticScalar(e.t), DiagnosticScalar(e.level),
            DiagnosticScalar(e.horizon),
            proposal.endgame and " [FINAL]" or "",
            DiagnosticScalar(charges.b),
            DiagnosticScalar(charges.r),
            DiagnosticScalar(charges.f),
            charges.ok == false and " (untrusted)" or "")
        for ci = 1, #cards do
            local c = DiagnosticTable(cards[ci])
            out[#out + 1] = string.format(
                "  %d%s %s id=%s fam=%s q=%s/cat:%s wishQ=%s max=%s own=%s d=%s %s%s",
                ci, c.g and "[G]" or "", DiagnosticScalar(c.name), DiagnosticScalar(c.id),
                DiagnosticScalar(c.fam), DiagnosticScalar(c.cardQ), DiagnosticScalar(c.catQ),
                DiagnosticScalar(c.wishQ), DiagnosticScalar(c.maxStack), DiagnosticScalar(c.owned),
                DiagnosticScalar(c.delta), DiagnosticScalar(c.ann),
                (c.wished and "" or " OFF-WISHLIST"))
            if c.frozen then out[#out] = out[#out] .. " FROZEN" end
        end
        out[#out + 1] = string.format("  proposal: %s %s (%s)",
            DiagnosticScalar(proposal.type),
            DiagnosticScalar(proposal.spellId or proposal.index or ""),
            DiagnosticScalar(proposal.reason))
        if #users > 0 then
            for _, rawUser in ipairs(users) do
                local u = DiagnosticTable(rawUser)
                out[#out + 1] = string.format("  USER: %s(%s)",
                    DiagnosticScalar(u.kind), DiagnosticScalar(u.arg))
            end
        end
        if e.pending and e.pending ~= "" then
            out[#out + 1] = "  pending guarantee: " .. DiagnosticScalar(e.pending)
        end
        out[#out + 1] = ""
    end
    return table.concat(out, "\n")
end

-- A user action "matches" the proposal when it is the same verb aimed at
-- the same thing; anything else is a training mismatch worth reading.
local function UserMatchesProposal(u, p)
    if type(u) ~= "table" or type(p) ~= "table" then return false end
    local k, a = tostring(u.kind), tonumber(u.arg)
    if k == "SelectPerk" then
        return p.type == "take" and a ~= nil and a == tonumber(p.spellId)
    elseif k == "BanishPerk" then
        return p.type == "banish" and a ~= nil and (a + 1) == tonumber(p.index)
    elseif k == "FreezePerk" then
        return p.type == "freeze" and a ~= nil and (a + 1) == tonumber(p.index)
    elseif k == "RequestReroll" then
        return p.type == "reroll"
    end
    return false
end

-- Complete, compact diagnostic export. The normal Boards/Mismatch tabs stay
-- bounded so opening /nexus log is cheap; this export includes every decision
-- still retained in SavedVariables (currently up to 200) in one copy operation.
-- Strings are dictionary-encoded to keep the single EditBox comfortably below
-- the client-freeze range without dropping any decision or mismatch fields.
local function NewAIExportCoroutine()
    return coroutine.create(function()
        local logs = Nexus.DiagnosticLogs
        local log = logs and logs.Snapshot and logs.Snapshot("decision") or {}
        local audits = logs and logs.Snapshot and logs.Snapshot("runAudit") or {}
        local probes = logs and logs.Snapshot and logs.Snapshot("uiProbe") or {}
        local errors = {}
        if Nexus.Errors and type(Nexus.Errors.History) == "function" then
            local okErrors, retained = pcall(Nexus.Errors.History)
            if okErrors and type(retained) == "table" then errors = retained end
        end
        local performance = {rows={}}
        if Nexus.Performance and type(Nexus.Performance.Snapshot) == "function" then
            local okPerformance, retained = pcall(Nexus.Performance.Snapshot)
            if okPerformance and type(retained) == "table" then performance = retained end
        end
        local dict, dictIndex = {}, {}
        local function Esc(v)
            local s = v and DiagnosticScalar(v) or ""
            s = s:gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A"):gsub("\r", "")
            return s
        end
        local function Ref(v)
            if v == nil or v == "" then return 0 end
            local s = DiagnosticScalar(v)
            local idx = dictIndex[s]
            if not idx then idx = #dict + 1; dict[idx] = s; dictIndex[s] = idx end
            return idx
        end
        local function B(v) if v == nil then return 0 elseif v then return 1 else return -1 end end
        local function N(v) return tonumber(v) or 0 end
        local function V(v) return DiagnosticScalar(v) end
        local function Mismatch(e)
            e = DiagnosticTable(e)
            local p = DiagnosticTable(e.proposal)
            for _, u in ipairs(DiagnosticTable(e.user)) do
                if not UserMatchesProposal(u, p) then return 1 end
            end
            return 0
        end
        local function Counts(map)
            local a = {}
            for fam, n in pairs(type(map) == "table" and map or {}) do
                local kind = type(fam)
                if kind == "string" or kind == "number" or kind == "boolean" then
                    a[#a + 1] = { Ref(fam), N(n) }
                end
            end
            table.sort(a, function(x,y)
                if x[1] == y[1] then return x[2] < y[2] end
                return x[1] < y[1]
            end)
            local rows = {}
            for _, x in ipairs(a) do rows[#rows + 1] = x[1] .. ":" .. x[2] end
            return table.concat(rows, ",")
        end

        local out = {
            "NEXUS_DIAGNOSTIC_LOG_5",
            "version=" .. Esc(Nexus.VERSION) .. "|build="
                .. Esc(RuntimeBuildLabel()) .. "|boards=" .. #log
                .. "|audits=" .. #audits .. "|probes=" .. #probes
                .. "|errors=" .. #errors,
            "B=board|C=card|U=user action|Q=predicted guarantee queue head|A=run/save audit|D=dictionary",
            "B|i|time|level|horizon|endgame|guaranteedIndex|banish|reroll|freeze|trusted|actionRef|spellId|cardIndex|reasonRef|pendingRef|mismatch|activeSlot|run|queueN",
            "C|board|card|spellId|familyRef|cardQ|catalogQ|wishQ|maxStack|owned|delta|annotationRef|flags(G,F,W)",
            "Q|board|position|spellId|familyRef|wished",
            "A|kindRef|time|run|level|activeSlot|targetSlot|resultRef|reasonRef|incumbentCounts|candidateCounts|summaryRef|exactRef|exactGained|exactLost|excessForced|excessAvoidable|excessShed|wrongQForced|wrongQAvoidable|wrongQShed|wrongQDetailRef|pollutionScoreRef",
            "P|time|eventRef|detailRef",
            "E|index|time|sourceRef|messageRef",
            "L|pageRef|line|textRef",
            "F|pathRef|count|totalMs|maximumMs|lastMs",
            "String refs use D lines. Counts are familyRef:stacks. This is observational logging only.",
        }
        for i, rawEntry in ipairs(log) do
            local e = DiagnosticTable(rawEntry)
            local p = DiagnosticTable(e.proposal); local ch = DiagnosticTable(e.charges)
            out[#out + 1] = table.concat({"B",i,Esc(e.t),V(e.level),V(e.horizon),B(p.endgame),V(e.gIndex),V(ch.b),V(ch.r),V(ch.f),B(ch.ok),Ref(p.type),V(p.spellId),V(p.index),Ref(p.reason),Ref(e.pending),Mismatch(e),N(e.activeSlot),N(e.run),N(e.queueN)}, "|")
            for ci, rawCard in ipairs(DiagnosticTable(e.cards)) do
                local c = DiagnosticTable(rawCard)
                local flags = (c.g and "G" or "-") .. (c.frozen and "F" or "-") .. (c.wished and "W" or "-")
                out[#out + 1] = table.concat({"C",i,ci,V(c.id),Ref(c.fam),V(c.cardQ),V(c.catQ),V(c.wishQ),V(c.maxStack),V(c.owned),V(c.delta),Ref(c.ann),flags}, "|")
            end
            for ui, rawUser in ipairs(DiagnosticTable(e.user)) do
                local u = DiagnosticTable(rawUser)
                out[#out + 1] = table.concat({"U",i,ui,Ref(u.kind),Esc(u.arg)}, "|")
            end
            for qi, rawQueue in ipairs(DiagnosticTable(e.queueHead)) do
                local q = DiagnosticTable(rawQueue)
                out[#out + 1] = table.concat({"Q",i,qi,V(q.id),Ref(q.fam),q.wished and 1 or 0}, "|")
            end
            if i % 5 == 0 then coroutine.yield("Encoding decisions " .. i .. "/" .. #log) end
        end
        for i, rawAudit in ipairs(audits) do
            local a = DiagnosticTable(rawAudit)
            local exact = {}
            for _, rawExact in ipairs(DiagnosticTable(a.exact)) do
                local x = DiagnosticTable(rawExact)
                exact[#exact + 1] = table.concat({N(x.id),Ref(x.fam),N(x.q),N(x.n)}, ":")
            end
            out[#out + 1] = table.concat({"A",Ref(a.kind),Esc(a.t),N(a.run),N(a.level),N(a.activeSlot),N(a.targetSlot),Ref(a.result),Ref(a.reason),Counts(a.incumbent),Counts(a.candidate),Ref(a.summary),Ref(table.concat(exact, ",")),N(a.exactGained),N(a.exactLost),N(a.excessForced),N(a.excessAvoidable),N(a.excessShed),N(a.wrongQForced),N(a.wrongQAvoidable),N(a.wrongQShed),Ref(a.wrongQDetail),Ref(a.pollutionScore)}, "|")
            if i % 8 == 0 then coroutine.yield("Encoding run audits " .. i .. "/" .. #audits) end
        end
        for i, rawProbe in ipairs(probes) do
            local p = DiagnosticTable(rawProbe)
            out[#out + 1] = table.concat({"P",Esc(p.t),Ref(p.event),Ref(p.detail)}, "|")
            if i % 10 == 0 then coroutine.yield("Encoding UI probes " .. i .. "/" .. #probes) end
        end
        for i, rawError in ipairs(errors) do
            local e = DiagnosticTable(rawError)
            out[#out + 1] = table.concat({"E",i,Esc(e.timestamp),Ref(e.source),Ref(e.message)}, "|")
        end
        -- Include every human-readable /nexus log page in the same export.
        -- This makes the export self-contained: compact event rows plus the exact
        -- State/Wishlist/Sync/DPS pages the player can see in the log window.
        local pageKeys = {"state", "wishlist", "boards", "mismatch", "sync", "dps", "autolock", "errors", "perf"}
        local pageProvider = options.getPageProvider and options.getPageProvider()
        if type(pageProvider) == "function" then
            for _, pageKey in ipairs(pageKeys) do
                local okPage, pageText = pcall(pageProvider, pageKey)
                pageText = okPage and tostring(pageText or "") or ("provider error: " .. tostring(pageText))
                local lineNo = 0
                for line in (pageText .. "\n"):gmatch("(.-)\n") do
                    lineNo = lineNo + 1
                    out[#out + 1] = table.concat({"L",Ref(pageKey),lineNo,Ref(line)}, "|")
                    if lineNo % 40 == 0 then coroutine.yield("Encoding " .. pageKey .. " page line " .. lineNo) end
                end
            end
        end
        for index, rawRow in ipairs(DiagnosticTable(performance.rows)) do
            local row = DiagnosticTable(rawRow)
            out[#out + 1] = table.concat({
                "F", Ref(row.name), N(row.count),
                string.format("%.3f", N(row.total)),
                string.format("%.3f", N(row.maximum)),
                string.format("%.3f", N(row.last)),
            }, "|")
            if index % 4 == 0 then
                coroutine.yield("Encoding performance aggregates " .. index
                    .. "/" .. #DiagnosticTable(performance.rows))
            end
        end
        out[#out + 1] = "DICTIONARY"
        for i, v in ipairs(dict) do
            out[#out + 1] = "D|" .. i .. "|" .. Esc(v)
            if i % 40 == 0 then coroutine.yield("Encoding dictionary " .. i .. "/" .. #dict) end
        end
        out[#out + 1] = "END|boards=" .. #log .. "|audits=" .. #audits .. "|probes=" .. #probes .. "|errors=" .. #errors .. "|dict=" .. #dict
        coroutine.yield("Finalizing copy text")
        return table.concat(out, "\n")
    end)
end

local function LogText_AIExport()
    return "Press Copy Full Diagnostic Log. Nexus builds the complete export gradually to avoid a frame hitch."
end

local function LogText_Mismatch()
    local log = Nexus.DiagnosticLogs and Nexus.DiagnosticLogs.Snapshot
        and Nexus.DiagnosticLogs.Snapshot("decision") or {}
    local out = { "MISMATCHES -- boards where your manual play differed", "" }
    local nMis = 0
    local first = math.max(1, #log - 99)
    if first > 1 then out[#out + 1] = "(scanning newest 100 boards)"; out[#out + 1] = "" end
    for i = first, #log do
        local e = DiagnosticTable(log[i])
        local users = DiagnosticTable(e.user)
        local proposal = DiagnosticTable(e.proposal)
        if #users > 0 then
            local anyMismatch = false
            for _, u in ipairs(users) do
                if not UserMatchesProposal(u, proposal) then anyMismatch = true end
            end
            if anyMismatch then
                nMis = nMis + 1
                out[#out + 1] = string.format("== board #%d [%s] L%s",
                    i, DiagnosticScalar(e.t), DiagnosticScalar(e.level))
                local cards = DiagnosticTable(e.cards)
                for ci = 1, #cards do
                    local c = DiagnosticTable(cards[ci])
                    out[#out + 1] = string.format(
                        "  %d%s %s id=%s fam=%s q=%s wishQ=%s own=%s d=%s %s%s",
                        ci, c.g and "[G]" or "", DiagnosticScalar(c.name), DiagnosticScalar(c.id),
                        DiagnosticScalar(c.fam), DiagnosticScalar(c.cardQ), DiagnosticScalar(c.wishQ),
                        DiagnosticScalar(c.owned), DiagnosticScalar(c.delta), DiagnosticScalar(c.ann),
                        (c.wished and "" or " OFF-WISHLIST"))
                end
                out[#out + 1] = string.format("  addon: %s %s (%s)",
                    DiagnosticScalar(proposal.type),
                    DiagnosticScalar(proposal.spellId or proposal.index or ""),
                    DiagnosticScalar(proposal.reason))
                for _, rawUser in ipairs(users) do
                    local u = DiagnosticTable(rawUser)
                    out[#out + 1] = string.format("  you:   %s(%s)",
                        DiagnosticScalar(u.kind), DiagnosticScalar(u.arg))
                end
                out[#out + 1] = ""
            end
        end
    end
    if nMis == 0 then out[#out + 1] = "(none recorded yet)" end
    return table.concat(out, "\n")
end

-- Reconciliation view for the "imported an 85-Echo build" scenario: Nexus has
-- no server API to lock/unlock an Echo (GameAdapter only exposes the
-- read-only LockedOwned), so this cannot swap anything automatically -- it
-- exists to tell the player exactly what to change by hand in the native
-- lock UI: which of their current locked Echoes this wishlist doesn't want,
-- and which wishlist Echoes don't fit the 79 cap because of it.
local function LogText_Locked()
    local catalog = Adapter.Catalog()
    local lockedOwned = Adapter.LockedOwned and Adapter.LockedOwned()
    local lockedBySpell = (lockedOwned and lockedOwned.bySpell) or {}
    local out = {}

    local lockedIds = {}
    for id in pairs(lockedBySpell) do lockedIds[#lockedIds + 1] = id end
    table.sort(lockedIds)
    out[#out + 1] = string.format(
        "LOCKED ECHOES -- %d total (permanent; Nexus can only read these, never lock/unlock them)",
        #lockedIds)
    for _, id in ipairs(lockedIds) do
        local row = catalog and catalog.rows and catalog.rows[id]
        out[#out + 1] = string.format("  %s (id=%d)", (row and row.name) or "?", id)
    end
    out[#out + 1] = ""

    local wl = Adapter.Wishlist()
    if not wl then
        out[#out + 1] = "no wishlist resolved -- nothing to compare against"
        return table.concat(out, "\n")
    end

    local entries = wl.entries or {}
    local wishedIds, total = {}, 0
    for _, e in ipairs(entries) do
        local id = tonumber(e and e.spellId)
        if id then wishedIds[id] = true end
        total = total + math.max(1, tonumber(e and e.stacks) or 1)
    end
    out[#out + 1] = string.format("WISHLIST '%s' -- %d total Echo copies (%d distinct entries)",
        tostring(wl.name), total, #entries)
    out[#out + 1] = ""

    local unwantedLocked = {}
    for _, id in ipairs(lockedIds) do
        if not wishedIds[id] then unwantedLocked[#unwantedLocked + 1] = id end
    end
    if #unwantedLocked > 0 then
        out[#out + 1] = string.format(
            "Locked but NOT on this wishlist (%d) -- swap candidates if you want to lock "
                .. "something this build actually asks for instead:", #unwantedLocked)
        for _, id in ipairs(unwantedLocked) do
            local row = catalog and catalog.rows and catalog.rows[id]
            out[#out + 1] = "  " .. ((row and row.name) or ("spell " .. tostring(id)))
        end
    else
        out[#out + 1] = "Every locked Echo is also on this wishlist -- no obvious swap candidates."
    end
    out[#out + 1] = ""

    -- Mirrors WishlistEditor.LoadPendingEchoes: already-locked matches don't
    -- consume the 79 cap, so overflow is whatever's left over after those.
    local remaining, overflow = 79, {}
    for _, e in ipairs(entries) do
        local id = tonumber(e and e.spellId)
        if id then
            if (tonumber(lockedBySpell[id]) or 0) > 0 then
                -- already locked; does not consume the cap
            elseif remaining <= 0 then
                overflow[#overflow + 1] = id
            else
                remaining = remaining - math.min(math.max(1, tonumber(e.stacks) or 1), remaining)
            end
        end
    end
    if #overflow > 0 then
        out[#out + 1] = string.format(
            "Doesn't fit in the 79-slot cap even after excluding locked matches (%d) -- "
                .. "lock one of these in-game to free a slot, or trim the wishlist:", #overflow)
        for _, id in ipairs(overflow) do
            local row = catalog and catalog.rows and catalog.rows[id]
            out[#out + 1] = "  " .. ((row and row.name) or ("spell " .. tostring(id)))
        end
    else
        out[#out + 1] = "No overflow -- everything on this wishlist fits within the 79-slot cap."
    end

    return table.concat(out, "\n")
end

local function LogText_Wishlist()
    local catalog = Adapter.Catalog()
    local wl = Adapter.Wishlist()
    local out = {}
    if not wl then
        return "no wishlist resolved" ..
            (Adapter.WishlistNote and (" -- " .. tostring(Adapter.WishlistNote())) or "")
    end
    local plan = Strategy.Compile(catalog, WishlistWithLockTargets(wl, catalog), Store.Settings())
    local owned = Adapter.Owned()
    out[#out + 1] = string.format("WISHLIST '%s' source=%s -- %d entries",
        tostring(wl.name), tostring(wl.source), #wl.entries)
    local nFam = 0
    for _ in pairs(plan.wishedFamilies or {}) do nFam = nFam + 1 end
    out[#out + 1] = string.format("plan.wishedFamilies: %d families", nFam)
    out[#out + 1] = ""
    local orphans = {}
    for _, e in ipairs(wl.entries) do
        local row = catalog and catalog.rows[e.spellId]
        local fam = e.family
        local members = catalog and catalog.familyMembers
            and catalog.familyMembers[fam] or {}
        local mq = {}
        for _, mid in ipairs(members) do
            local mr = catalog.rows[mid]
            mq[#mq + 1] = tostring(mid) .. ":q" .. tostring(mr and mr.quality)
        end
        local inPlan = plan.wishedFamilies and plan.wishedFamilies[fam] and true or false
        local ownedFamLog = (owned and owned.byFamily and fam and owned.byFamily[fam]) or 0
        local effQ = Model.EffectiveWishedQuality
            and Model.EffectiveWishedQuality(plan, catalog, fam, ownedFamLog, owned and owned.bySpell) or "?"
        out[#out + 1] = string.format(
            "%s id=%s q=%s stacks=%s fam=%s effWishQ=%s own=%s%s",
            tostring(row and row.name or ("spell " .. tostring(e.spellId))),
            tostring(e.spellId), tostring(e.quality), tostring(e.stacks),
            FamLabel(catalog, fam), tostring(effQ),
            tostring(owned.byFamily and owned.byFamily[fam] or 0),
            inPlan and "" or "  <-- NOT IN PLAN")
        out[#out + 1] = "    variants: " .. (next(mq) and table.concat(mq, ", ")
            or "(sole variant)")
        if not inPlan then orphans[#orphans + 1] = tostring(row and row.name or e.spellId) end
    end
    out[#out + 1] = ""
    if #orphans > 0 then
        out[#out + 1] = "!! ENTRIES MISSING FROM PLAN (this is the ST/AB bug surface):"
        out[#out + 1] = "   " .. table.concat(orphans, ", ")
    else
        out[#out + 1] = "all wishlist entries resolved into the plan"
    end
    return table.concat(out, "\n")
end

local VIEW_CLASSES = {
    ALL=true,UNAVAILABLE=true,UNKNOWN=true,
    DEATHKNIGHT=true,DRUID=true,HUNTER=true,MAGE=true,PALADIN=true,
    PRIEST=true,ROGUE=true,SHAMAN=true,WARLOCK=true,WARRIOR=true,
}
local VIEW_SCOPES = {all=true,mine=true}
local VIEW_SORTS = {dps=true,recent=true,title=true}
local VIEW_CATEGORIES = {builds=true,dummy=true,lk=true,combined=true}
local VIEW_PHASES = {idle=true,slots=true,cleanup=true,unknown=true}
local VIEW_REASONS = {
    none=true,hidden=true,["saved-import"]=true,
    ["projection-pending"]=true,["projection-error"]=true,
    ["sync-receiving"]=true,dirty=true,["not-published"]=true,
    unavailable=true,unknown=true,
}

local function ViewToken(value, allowed, fallback)
    return type(value) == "string" and allowed[value] and value or fallback
end

local function ViewInteger(value, minimum)
    value = tonumber(value)
    if not value or value ~= value or value >= math.huge
        or value <= -math.huge then return minimum or 0 end
    return math.max(minimum or 0,
        math.min(2147483647, math.floor(value)))
end

local function ViewVersion(value)
    if type(value) ~= "string" or #value < 1 or #value > 64
        or not value:match("^[%w%._%-]+$") then return "unversioned" end
    return value
end

local function ViewSnapshot(owner, expectedView)
    local value = {}
    if type(owner) == "table"
        and type(owner.DiagnosticSnapshot) == "function" then
        local ok, result = pcall(owner.DiagnosticSnapshot)
        if ok and type(result) == "table" then value = result end
    end
    local age = tonumber(value.lastPublicationAge)
    if not age or age ~= age or age >= math.huge or age <= -math.huge then
        age = -1
    else age = math.max(-1, math.min(2147483647, age)) end
    return {
        schema=ViewInteger(value.schema, 0),view=expectedView,
        catalogCount=ViewInteger(value.catalogCount, 0),
        bundledCount=ViewInteger(value.bundledCount, 0),
        overlayCount=ViewInteger(value.overlayCount, 0),
        availableCount=ViewInteger(value.availableCount, 0),
        filterMatchedCount=ViewInteger(value.filterMatchedCount, 0),
        qualifyingCount=ViewInteger(value.qualifyingCount, 0),
        resultCount=ViewInteger(value.resultCount, 0),
        displayedCount=ViewInteger(value.displayedCount, 0),
        searchActive=value.searchActive == true,
        catalogVersion=ViewVersion(value.catalogVersion),
        requestedPage=ViewInteger(value.requestedPage, 0),
        publishedPage=ViewInteger(value.publishedPage, 0),
        pageCount=ViewInteger(value.pageCount, 0),
        publishedRows=ViewInteger(value.publishedRows, 0),
        filterScope=ViewToken(value.filterScope, VIEW_SCOPES, "all"),
        filterClass=ViewToken(value.filterClass, VIEW_CLASSES, "UNAVAILABLE"),
        filterCurrentClassOnly=value.filterCurrentClassOnly == true,
        filterQualifiedOnly=value.filterQualifiedOnly == true,
        filterSearchActive=value.filterSearchActive == true,
        filterSort=ViewToken(value.filterSort, VIEW_SORTS, "dps"),
        filterCategory=ViewToken(value.filterCategory,
            VIEW_CATEGORIES, expectedView == "community" and "builds" or "lk"),
        projectionCurrent=value.projectionCurrent == true,
        projectionPending=value.projectionPending == true,
        projectionDirty=value.projectionDirty ~= false,
        savedImportPending=value.savedImportPending == true,
        savedImportPhase=ViewToken(value.savedImportPhase,
            VIEW_PHASES, "unknown"),
        syncReceiving=value.syncReceiving == true,lastPublicationAge=age,
        blockedReason=ViewToken(value.blockedReason,
            VIEW_REASONS, "unavailable"),
    }
end

local function AddViewSnapshot(out, owner, expectedView)
    local state = ViewSnapshot(owner, expectedView)
    out[#out + 1] = string.format(
        "%s catalog=%d page=requested:%d published:%d count:%d rows:%d",
        expectedView, state.catalogCount, state.requestedPage,
        state.publishedPage, state.pageCount, state.publishedRows)
    if expectedView == "community" then
        out[#out + 1] = string.format(
            "  catalog_status bundled=%d overlay=%d available=%d filter_matched=%d qualifying=%d results=%d displayed=%d search=%s version=%s",
            state.bundledCount,state.overlayCount,state.availableCount,
            state.filterMatchedCount,state.qualifyingCount,state.resultCount,
            state.displayedCount,tostring(state.searchActive),
            state.catalogVersion)
    end
    out[#out + 1] = string.format(
        "  filters scope=%s class=%s current=%s qualified=%s search=%s sort=%s category=%s",
        state.filterScope, state.filterClass,
        tostring(state.filterCurrentClassOnly),
        tostring(state.filterQualifiedOnly),
        tostring(state.filterSearchActive), state.filterSort,
        state.filterCategory)
    local age = state.lastPublicationAge < 0 and "never"
        or string.format("%.1fs", state.lastPublicationAge)
    out[#out + 1] = string.format(
        "  projection=current:%s pending:%s dirty:%s import=pending:%s phase:%s receiving=%s publication_age=%s blocked=%s",
        tostring(state.projectionCurrent),tostring(state.projectionPending),
        tostring(state.projectionDirty),tostring(state.savedImportPending),
        state.savedImportPhase,tostring(state.syncReceiving),age,
        state.blockedReason)
end

local function LogText_State()
    local catalog = Adapter.Catalog()
    local wl = Adapter.Wishlist()
    local plan = wl and Strategy.Compile(catalog, WishlistWithLockTargets(wl, catalog), Store.Settings())
        or { advisorOnly = true }
    local slots = Adapter.Slots()
    local owned = Adapter.Owned()
    local charges = Adapter.Charges()
    local out = {}
    out[#out + 1] = string.format("v%s  build=%s  level=%s  auto=%s",
        Nexus.VERSION, RuntimeBuildLabel(), tostring(Adapter.Level()),
        tostring(options.getAutoEnabled and options.getAutoEnabled() or false))
    out[#out + 1] = string.format("charges B:%s R:%s F:%s trustworthy=%s",
        tostring(charges.banish), tostring(charges.reroll),
        tostring(charges.freeze), tostring(charges.trustworthy))
    for k, v in pairs(EffectiveFlags()) do
        out[#out + 1] = "flag " .. tostring(k) .. " = " .. tostring(v)
    end
    local s = Store.Settings()
    out[#out + 1] = string.format(
        "settings: autoPick=%s autoActivate=%s autoBanish=%s autoSave=%s autoDisable=%s autoLockEchoes=%s",
        tostring(s.autoPick), tostring(s.autoActivate), tostring(s.autoBanish),
        tostring(s.autoSave), tostring(s.autoDisable), tostring(s.autoLockEchoes))
    out[#out + 1] = ""
    out[#out + 1] = "PERSISTED VIEW DIAGNOSTICS (bounded sanitized scalars):"
    AddViewSnapshot(out, Nexus.CommunityBuilds, "community")
    AddViewSnapshot(out, Nexus.Leaderboard, "leaderboard")
    out[#out + 1] = ""
    local database = options.getDatabase and options.getDatabase() or nil
    local refusal = database and database.lastSaveRefusal
    if refusal then
        out[#out + 1] = string.format(
            "LAST SAVE REFUSAL [%s] L%s slot %s: %s",
            tostring(refusal.t), tostring(refusal.level),
            tostring(refusal.incumbentSlot), tostring(refusal.detail))
        out[#out + 1] = "  (\"coverage lost: X\" = a wished family X the active loadout"
        out[#out + 1] = "   already has is missing from this run. \"no net gain\" = coverage"
        out[#out + 1] = "   held even but this run picked up more off-wishlist filler than"
        out[#out + 1] = "   the active loadout carries -- not a coverage regression.)"
        out[#out + 1] = ""
    end
    if slots then
        out[#out + 1] = "SLOTS (activeSlot=" .. tostring(slots.activeSlot) .. "):"
        local ids = {}
        for id in pairs(slots.bySlot or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local row = slots.bySlot[id]
            out[#out + 1] = string.format("  slot %s '%s' verified=%s echoes=%d%s",
                tostring(id), tostring(row.name), tostring(row.verified),
                #(row.echoes or {}), row.suspectParse and " SUSPECT" or "")
            if id == slots.activeSlot then
                for _, e in ipairs(row.echoes or {}) do
                    out[#out + 1] = string.format(
                        "      id=%s fam=%s q=%s stacks=%s%s wished=%s",
                        tostring(e.spellId), tostring(e.family), tostring(e.quality),
                        tostring(e.stacks), e.locked and " locked" or "",
                        tostring(plan.wishedFamilies
                            and plan.wishedFamilies[e.family] or false))
                end
            end
        end
    else
        out[#out + 1] = "SLOTS: not loaded"
    end
    out[#out + 1] = ""
    out[#out + 1] = "OWNED byFamily:"
    local fams = {}
    for fam in pairs(owned.byFamily or {}) do fams[#fams + 1] = fam end
    table.sort(fams, function(a, b) return tostring(a) < tostring(b) end)
    for _, fam in ipairs(fams) do
        out[#out + 1] = string.format("  %s x%s", FamLabel(catalog, fam),
            tostring(owned.byFamily[fam]))
    end
    out[#out + 1] = string.format("owned synced=%s", tostring(owned.synced))
    return table.concat(out, "\n")
end

local function LogText_Sync()
    local s = Nexus.Sync
    if not s then return "sync module not loaded" end
    local out = {}
    local function Add(fmt, ...)
        local ok, line = pcall(string.format, fmt, ...)
        out[#out + 1] = ok and line or tostring(fmt)
    end

    Add("SYNC DIAGNOSTICS -- Nexus v%s", tostring(Nexus.VERSION))
    Add("")
    Add("-- connection --")
    Add("channel name   : %s", s.ChannelName())
    Add("connected      : %s", tostring(s.IsConnected()))
    Add("channel index  : %s", tostring(s.ChannelIndex()))
    Add("my name        : %s", tostring((UnitName and UnitName("player")) or "?"))
    Add("receiving now  : %s (%.0fs left)", tostring(s.IsReceiving()), s.ReceiveTimeLeft())
    Add("last sync new  : %d build(s)", s.LastSyncNewCount())
    local st = s.Stats()
    Add("request outcome: id=%s useful=%s new=%d updated=%d share=%d",
        tostring(st.requestId or "none"), tostring(st.useful == true),
        st.requestNew or 0, st.requestUpdated or 0, st.requestShares or 0)
    Add("request non-useful: baseline=%d duplicate=%d rejected=%d unrelated=%d",
        st.requestBaseline or 0, st.requestDuplicates or 0,
        st.requestRejected or 0, st.requestUnrelated or 0)
    Add("request terminal: reason=%s queue=%s last=%s",
        tostring(st.terminalReason or "none"),
        tostring(st.queueOutcome or "none"),
        tostring(st.requestLastReason or "none"))
    Add("operation flow: queued=%d attempted=%d requeued=%d sent-attempted=%d",
        st.operationQueued or 0, st.operationAttempted or 0,
        st.operationRequeued or 0, st.operationSentAttempted or 0)
    Add("operation terminal: expired=%d dropped=%d superseded=%d reset=%d throttle-exhausted=%d accepted=%d rejected=%d",
        st.operationExpired or 0, st.operationDropped or 0,
        st.operationSuperseded or 0, st.operationReset or 0,
        st.operationThrottleExhausted or 0, st.operationAccepted or 0,
        st.operationRejected or 0)
    Add("")

    Add("-- counters --")
    Add("messages sent          : %d", st.sent or 0)
    Add("builds stored (new)    : %d", (st.received or 0) - (st.updated or 0))
    Add("builds updated         : %d", st.updated or 0)
    Add("skipped (peer up2date) : %d", st.skippedUpToDate or 0)
    Add("duplicates skipped     : %d", st.duplicatesSkipped or 0)
    Add("malformed rejected     : %d", st.malformedRejected or 0)
    Add("storage rejected       : %d", st.storageRejected or 0)
    Add("ignored (no sync open) : %d", st.ignoredOutsideWindow or 0)
    Add("oversize dropped       : %d", st.oversizeDropped or 0)
    Add("deleted (tombstoned)   : %d", s.TombstoneCount and s.TombstoneCount() or 0)
    Add("")

    Add("-- builds in my library --")
    local mine, theirs, listed, scanned = 0, 0, 0, 0
    local catalog = Nexus and Nexus.BuildCatalog
    local total = 0
    if catalog and type(catalog.Count) == "function" then
        local ok, value = pcall(catalog.Count)
        if ok then total = math.max(0, tonumber(value) or 0) end
    end
    local cursor
    if catalog and type(catalog.BeginSummaryCursor) == "function" then
        local ok, value = pcall(catalog.BeginSummaryCursor)
        if ok then cursor = value end
    end
    if type(cursor) == "table"
        and type(catalog.SummaryCursorNext) == "function" then
        while scanned < 100 do
            local ok, b, done, err = pcall(catalog.SummaryCursorNext, cursor)
            scanned = scanned + 1
            if not ok or err then
                Add("  (bounded summary unavailable)")
                break
            end
            if type(b) == "table" then
                listed = listed + 1
                if b.isMine then
                    mine = mine + 1
                    Add("  [MINE]  %-28s %2d echoes  stamp=%s",
                        tostring(b.title), tonumber(b.echoCount) or 0,
                        tostring(b.lastModified or b.postedAt))
                else
                    theirs = theirs + 1
                    Add("  [THEIRS] %-27s %2d echoes  by %s",
                        tostring(b.title), tonumber(b.echoCount) or 0,
                        tostring(b.author))
                end
            end
            if done then break end
        end
    end
    if mine + theirs == 0 then Add("  (none)") end
    if total > listed then Add("  (list capped at 100 summary reads for client safety)") end
    Add("  library total: %d; listed: %d mine, %d from others",
        total, mine, theirs)
    Add("")

    Add("-- event log (newest last) --")
    local log = s.EventLog()
    if #log == 0 then
        Add("  (empty -- no sync activity yet this session)")
        Add("  If you pressed Sync Now and this is still empty, the addon")
        Add("  is not seeing ANY traffic on the channel.")
    else
        local first = math.max(1, #log - 99)
        local t0 = log[first].t or 0
        if first > 1 then Add("  (showing newest 100 of %d events)", #log) end
        for i = first, #log do
            local e = log[i]
            Add("  [%7.2fs] %-5s %s", (e.t or 0) - t0, e.cat or "?", e.text or "")
        end
    end
    return table.concat(out, "\n")
end

local function LogText_Errors()
    local errors = Nexus.Errors
    if not errors or type(errors.Format) ~= "function" then
        return "error history unavailable"
    end
    local ok, text = pcall(errors.Format)
    return ok and tostring(text or "")
        or ("error history render failed: " .. ErrorText(text))
end

local function LogText_Performance()
    local performance = Nexus.Performance
    if not performance or type(performance.Snapshot) ~= "function" then
        return "performance diagnostics unavailable"
    end
    local ok, snapshot = pcall(performance.Snapshot)
    if not ok or type(snapshot) ~= "table" then
        return "performance diagnostics unavailable"
    end
    local out = {
        "PERFORMANCE AGGREGATES -- this session only",
        "Observational milliseconds; no per-call samples or SavedVariables history.",
        string.format("enabled=%s clockAvailable=%s clockFailures=%d",
            tostring(snapshot.enabled == true),
            tostring(snapshot.clockAvailable == true),
            tonumber(snapshot.clockFailures) or 0),
        "",
        "path                         count    total ms      max ms     last ms",
    }
    for _, rawRow in ipairs(DiagnosticTable(snapshot.rows)) do
        local row = DiagnosticTable(rawRow)
        out[#out + 1] = string.format("%-28s %7d %11.3f %11.3f %11.3f",
            DiagnosticScalar(row.name), tonumber(row.count) or 0,
            tonumber(row.total) or 0, tonumber(row.maximum) or 0,
            tonumber(row.last) or 0)
    end
    return table.concat(out, "\n")
end

local function ClearDiagnosticLogs(tabKey)
    if tabKey == "peer" then
        local peerDebug = Nexus.PeerDebug
        if not (peerDebug and type(peerDebug.Clear) == "function") then
            return false
        end
        local ok, cleared = pcall(peerDebug.Clear)
        return ok and cleared ~= false
    end
    if tabKey == "perf" then
        if Nexus.Performance and type(Nexus.Performance.Reset) == "function" then
            local ok, cleared = pcall(Nexus.Performance.Reset)
            return ok and cleared ~= false
        end
        return false
    end
    if tabKey == "errors" then
        if Nexus.Errors and type(Nexus.Errors.Clear) == "function" then
            local ok, cleared = pcall(Nexus.Errors.Clear)
            return ok and cleared ~= false
        end
        return false
    end
    local durable = Nexus.DiagnosticLogs
    if not (durable and type(durable.ClearAll) == "function") then
        return false
    end
    local okDurable, clearedDurable = pcall(durable.ClearAll)
    if not okDurable or not clearedDurable then return false end

    local database = options.ensureDatabase and options.ensureDatabase() or {}
    database.lastSaveRefusal = nil
    database.lastSaveStatus = nil
    database.auditRunCounter = 0
    if options.resetAuditState then options.resetAuditState() end
    if Nexus.Sync and type(Nexus.Sync.ClearLog) == "function" then
        pcall(Nexus.Sync.ClearLog)
    end
    if Nexus.DpsCapture and type(Nexus.DpsCapture.ClearDebugLog) == "function" then
        pcall(Nexus.DpsCapture.ClearDebugLog)
    end
    if Nexus.Errors and type(Nexus.Errors.Clear) == "function" then
        pcall(Nexus.Errors.Clear)
    end
    return true
end

local function LogViewerProvider(tabKey)
    if tabKey == "peer" then
        local peerDebug = Nexus.PeerDebug
        if not (peerDebug and type(peerDebug.Report) == "function") then
            return "Peer Test diagnostics unavailable"
        end
        local ok, report = pcall(peerDebug.Report)
        return ok and tostring(report or "")
            or "Peer Test diagnostics unavailable"
    end
    if tabKey == "boards" then return LogText_Boards() end
    if tabKey == "mismatch" then return LogText_Mismatch() end
    if tabKey == "ai_export" then return LogText_AIExport() end
    if tabKey == "wishlist" then return LogText_Wishlist() end
    if tabKey == "locked" then return LogText_Locked() end
    if tabKey == "state" then return LogText_State() end
    if tabKey == "sync" then return LogText_Sync() end
    if tabKey == "dps" then
        local D = Nexus.DpsCapture
        return D and D.GetDebugLog and D.GetDebugLog() or "DPS module unavailable"
    end
    if tabKey == "autolock" then return LogText_AutoLock() end
    if tabKey == "automation" then return LogText_Automation() end
    if tabKey == "errors" then return LogText_Errors() end
    if tabKey == "perf" then return LogText_Performance() end
    return "unknown tab: " .. tostring(tabKey)
end

    local M = {}
    M.AppendAudit = AppendAudit
    M.AppendAutoLockEvent = AppendAutoLockEvent
    M.NewAIExportCoroutine = NewAIExportCoroutine
    M.GetPageText = LogViewerProvider
    M.Clear = ClearDiagnosticLogs
    return M
end
