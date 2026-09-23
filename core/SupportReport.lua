-- Nexus: core/SupportReport.lua
-- Builds the two things a player can hand to support: a compact summary they
-- select and copy, and a detached report snapshot the isolated NexusSupport
-- component can store so WoW writes it to its own file at the next normal save
-- boundary.
--
-- What this file does NOT do: it opens no file, touches no clipboard, sends
-- nothing anywhere, never reloads or logs out, and writes nothing into NexusDB.
-- Preparing a report changes a value in memory inside the helper addon; the
-- client writes the file later, and this code never claims otherwise.
--
-- Privacy: the default report is ONE incident plus the context that incident
-- needs. Character identity is carried as a session alias unless the report is
-- the extended one, which is labelled private before it is prepared. No
-- credentials, account names, chat transcripts, unrelated profiles or other
-- players' records are collected here.

Nexus = Nexus or {}
local M = {}
Nexus.SupportReport = M

local FORMAT = 1
local SUMMARY_MAX_BYTES = 8000
local CHUNK_BYTES = 8 * 1024
local TOTAL_BYTES = 1024 * 1024
local STEP_LINES = 60

M.FORMAT = FORMAT
M.SUMMARY_MAX_BYTES = SUMMARY_MAX_BYTES
M.CHUNK_BYTES = CHUNK_BYTES
M.TOTAL_BYTES = TOTAL_BYTES

local sessionSalt = nil
local reportSequence = 0

local function clock()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return nil
end

-- A stable per-session alias, so two lines about the same character can be
-- correlated without carrying the character and realm into an ordinary report.
local function alias(value)
    if sessionSalt == nil then
        sessionSalt = 0
        local okSeed, seed = pcall(function()
            return tostring(clock() or 0) .. tostring(GetTime and GetTime() or 0)
        end)
        if not okSeed or type(seed) ~= "string" then seed = "session" end
        for index = 1, #seed do
            sessionSalt = (sessionSalt * 31 + seed:byte(index)) % 2147483647
        end
    end
    local hash = sessionSalt
    local text = tostring(value or "")
    for index = 1, #text do
        hash = (hash * 33 + text:byte(index)) % 2147483647
    end
    return string.format("session-%06d", hash % 1000000)
end
M.Alias = alias

local function plain(value, limit)
    if value == nil then return nil end
    -- tostring runs a caller-supplied __tostring, which can raise. A field of
    -- a status table is not allowed to take this report away.
    local ok, converted = pcall(tostring, value)
    if not ok or type(converted) ~= "string" then
        converted = "unreadable " .. type(value)
    end
    return (converted:gsub("%c", " ")):sub(1, limit or 200)
end

-- plain() for a value that is going into a concatenation: never nil.
local function shown(value, limit)
    local text = plain(value, limit)
    if text == nil or text == "" then return "unknown" end
    return text
end

-- A retained incident value. The incident owner marks a value it had to
-- shorten with a byte no caller can supply, because it escapes every control
-- character a caller hands it; that byte is an IDENTITY device and must never
-- reach a ticket, so it is read back here as the printable marker it stands
-- for. Everything else goes through plain() exactly as before.
local function retained(value, limit)
    -- nil is "not retained", exactly as plain() reports it: the callers here
    -- fall back on that, and "nil" is not a value anyone retained.
    if value == nil then return nil end
    -- The same rule safeText applies: a heap address is not a retained value.
    local kind = type(value)
    if kind == "table" or kind == "function" or kind == "userdata"
        or kind == "thread" then
        return "unreadable " .. kind
    end
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= "string" then text = "unreadable " .. type(value) end
    limit = limit or 200
    local marker = text:match(string.char(1) .. ".*$")
    if not marker then return plain(text, limit) end
    -- The marker is the only statement that this value was shortened at all,
    -- so it is the part that must survive this bound. The body yields to it.
    local printable = plain("..." .. marker:sub(2), limit)
    if #printable >= limit then return printable end
    return plain(text:sub(1, #text - #marker), limit - #printable) .. printable
end

-- The report is copied out of an edit box and pasted into a ticket, so a pipe
-- must survive as one pipe: an edit box shows its text literally, and a doubled
-- pipe would reach support as part of a recorded label. Escaping belongs to the
-- font strings on the page, which DO interpret pipe sequences.
local function escape(value)
    return (tostring(value or ""):gsub("|", "||"))
end
M.Escape = escape

-- Simple, bounded, dependency-free checksum over the chunk texts in order. It
-- detects a truncated or reordered copy. It is NOT authenticity and NOT proof
-- that a server ever saw this report.
local function checksum(chunks)
    local a, b = 1, 0
    for index = 1, #chunks do
        local chunk = chunks[index]
        for position = 1, #chunk do
            a = (a + chunk:byte(position)) % 65521
            b = (b + a) % 65521
        end
        a = (a + index) % 65521
        b = (b + a) % 65521
    end
    return string.format("%04x%04x", b, a)
end
M.Checksum = checksum

local function limits()
    local okOwner, evidence = pcall(function()
        local owner = Nexus and Nexus.LoadoutEvidence
        return type(owner) == "table" and type(owner.SemanticLimits) == "function"
            and owner.SemanticLimits or nil
    end)
    if okOwner and evidence then
        local ok, value = pcall(evidence)
        -- A partial answer is reported as far as it goes, never as "nil".
        if ok and type(value) == "table" then
            return {ordinary = value.ordinary or "not stated",
                locked = value.locked or "not stated",
                total = value.total or "not stated"}
        end
    end
    return nil
end

-- The converter for a value going into a concatenation: never nil, never
-- raising, always bounded, never carrying a control byte. `shown` and
-- `retained` below give the same guarantees for their own cases. Any NEW
-- concatenation in this file takes one of the three; a segment appended
-- without one is how three separate reviews found the same defect.
local function safeText(value, limit)
    local kind = type(value)
    -- A table, function or userdata converts to its heap address, which is
    -- noise in a ticket and an implementation detail in a saved file.
    if kind == "table" or kind == "function" or kind == "userdata"
        or kind == "thread" then
        return "unreadable " .. kind
    end
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= "string" then text = "unreadable " .. type(value) end
    return (text:gsub("%c", " ")):sub(1, limit or 200)
end

-- The build label is an owner field like every other one, and it reaches the
-- copied summary, the payload and the stored header. It gets the same
-- treatment, not an exception for being "ours".
-- A replaced UnitName can raise; the alias is not worth the summary.
local function playerName()
    local ok, name = pcall(function()
        return UnitName and UnitName("player") or nil
    end)
    if not ok or type(name) ~= "string" or name == "" then return "unknown" end
    return name
end

local function buildLabel()
    -- The READ is protected, not only the value: a metatable on the owner
    -- table can raise on the index itself.
    local ok, label = pcall(function()
        local release = Nexus and Nexus.Release
        return release and release.buildLabel or nil
    end)
    if not ok or label == nil or label == "" then return "unknown" end
    return safeText(label, 64)
end

local function counts(line, label, value, limit)
    if type(value) ~= "table" then
        line[#line + 1] = label .. ": not retained"
        return
    end
    local text = label .. ": " .. safeText(value.ordinary or "?", 16) .. " ordinary, "
        .. safeText(value.locked or "?", 16) .. " locked, "
        .. safeText(value.total or "?", 16) .. " total"
    if type(limit) == "table" then
        text = text .. " (limits " .. safeText(limit.ordinary or "not stated", 16) .. "/"
            .. safeText(limit.locked or "not stated", 16) .. "/"
            .. safeText(limit.total or "not stated", 16) .. ")"
    end
    line[#line + 1] = text
end

-- A caller's incident, copied into the shape this file reads. Every field is
-- taken inside one pcall, so a table whose own __index raises costs the
-- incident, never the report. The owner's incidents are already plain tables;
-- this exists because M.Summary and M.IncidentLines are public.
local INCIDENT_FIELDS = {"id", "kind", "reason", "producer", "origin",
    "operation", "ticket", "build", "category", "representation", "scope",
    "detail", "occurrences", "firstAt", "lastAt", "committed", "affectedOmitted"}
local COUNT_FIELDS = {"ordinary", "locked", "total"}
local function incidentShape(value)
    if type(value) ~= "table" then return nil end
    local out = {}
    local ok = pcall(function()
        for _, field in ipairs(INCIDENT_FIELDS) do out[field] = value[field] end
        for _, name in ipairs({"counts", "limits"}) do
            local source = value[name]
            if type(source) == "table" then
                local copy = {}
                for _, field in ipairs(COUNT_FIELDS) do copy[field] = source[field] end
                out[name] = copy
            end
        end
        if type(value.readiness) == "table" then
            local copy = {}
            -- pairs() uses next(), which no metamethod can reach in 5.1.
            for key, entry in pairs(value.readiness) do copy[key] = entry end
            out.readiness = copy
        end
        if type(value.affected) == "table" then
            local copy = {}
            for index, tuple in ipairs(value.affected) do
                if type(tuple) == "table" then
                    copy[index] = {spellId=tuple.spellId, quality=tuple.quality,
                        stacks=tuple.stacks, locked=tuple.locked == true or nil}
                end
            end
            out.affected = copy
        end
    end)
    if not ok then return nil end
    return out
end

-- One incident, said plainly, with the failure-time facts first. Anything the
-- owner did not retain says so instead of being filled in.
function M.IncidentLines(incident, options)
    options = type(options) == "table" and options or {}
    incident = incidentShape(incident)
    local out = {}
    if type(incident) ~= "table" then
        out[#out + 1] = "No incident was retained in this session."
        return out
    end
    out[#out + 1] = "Incident: " .. (retained(incident.kind, 240) or "not retained")
        .. " / " .. (retained(incident.reason, 240) or "not retained")
    out[#out + 1] = "Producer: " .. (retained(incident.producer, 240) or "not retained")
        .. "; origin: " .. (retained(incident.origin, 64) or "unknown")
    if incident.operation or incident.ticket then
        out[#out + 1] = "Operation: " .. (retained(incident.operation, 240) or "not retained")
            .. (incident.ticket and ("; ticket " .. retained(incident.ticket, 240)) or "")
    end
    out[#out + 1] = "Build at failure: " .. (retained(incident.build, 240) or "not retained")
        .. (incident.category and ("; category " .. retained(incident.category, 240)) or "")
    out[#out + 1] = "Representation: " .. (retained(incident.representation, 64) or "unknown")
    counts(out, "Counted at refusal", incident.counts, incident.limits)
    if incident.readiness then
        local parts = {}
        for key, value in pairs(incident.readiness) do
            parts[#parts + 1] = retained(key, 64) .. "=" .. retained(value, 240)
        end
        table.sort(parts)
        out[#out + 1] = "Capture-time sources: " .. (#parts > 0
            and table.concat(parts, ", ") or "not retained")
    else
        out[#out + 1] = "Capture-time sources: not retained"
    end
    if incident.committed == false then
        out[#out + 1] = "Result: this write did not commit."
    elseif incident.committed == true then
        out[#out + 1] = "Result: this write committed."
    else
        out[#out + 1] = "Result: not retained."
    end
    if incident.scope then out[#out + 1] = "Scope: " .. retained(incident.scope, 240) end
    if incident.detail then out[#out + 1] = "Detail: " .. retained(incident.detail, 240) end
    out[#out + 1] = "Occurrences: " .. safeText(incident.occurrences or 1, 16)
        .. (incident.firstAt and (" (first " .. safeText(incident.firstAt, 24)
            .. ", last " .. safeText(incident.lastAt, 24) .. ")") or "")
    if options.tuples ~= false and type(incident.affected) == "table"
        and #incident.affected > 0 then
        local rows = {}
        for _, tuple in ipairs(incident.affected) do
            rows[#rows + 1] = safeText(tuple.spellId or "?", 16)
                .. "." .. safeText(tuple.quality or "?", 8)
                .. "x" .. safeText(tuple.stacks or 1, 8)
                .. (tuple.locked and "P" or "")
        end
        out[#out + 1] = "Affected copies retained at the boundary ("
            .. #rows .. (incident.affectedOmitted
                and (" shown, " .. safeText(incident.affectedOmitted, 16) .. " omitted") or "")
            .. "): " .. table.concat(rows, " ")
    elseif options.tuples ~= false then
        out[#out + 1] = "Affected copies: not retained"
    end
    return out
end

-- The compact report. It is BUILT at this size: the incident and its context
-- come first, and sections stop being added when the budget is reached. It is
-- never a truncated copy of the extended report.
-- What is guaranteed, exactly: every value that enters a line goes through
-- safeText, shown or retained; the STORAGE COMPONENT - a separate addon, the
-- one owner treated as adversarial here - is read only inside a pcall, one
-- lookup and call at a time, and NOTHING it returns reaches a caller: its
-- header is copied field by field and its verdict comes back as a boolean.
-- A caller's incident is copied the same way. A poison sweep in the prototype
-- suite checks all three, and the page escapes what it displays.
-- What is NOT guaranteed: a table an owner RETURNS is read as an ordinary
-- table. A status, a limits table, a start-up snapshot or an incident row
-- whose own fields raise on __index is out of scope here, because the owners
-- of those tables build them from scalars in this addon. The two exceptions
-- are the storage component, which is a separate addon and whose returned
-- tables ARE copied into a shape this file owns, and every value that reaches
-- a line, which is converted whatever it is.
function M.StartupSnapshot()
    local ok, status = pcall(function()
        return Nexus and Nexus.StartupStatus and Nexus.StartupStatus() or nil
    end)
    if not ok or type(status) ~= "table" then return nil end
    return status
end

-- ONE projection of what the passive start-up owner retained, used by the
-- copyable summary and by the prepared file. It reads that owner only: it
-- initializes nothing, pumps nothing, rescans nothing and writes nothing.
-- A start-up refusal is not a Lua error and not an incident, so it must be
-- legible with zero of both.
function M.StartupLines(status, extended)
    if type(status) ~= "table" then return {} end
    local failed = status.state == "failed"
    local out = {}
    out[#out + 1] = (failed and "STARTUP FAILED: state " or "Startup: state ")
        .. shown(status.state, 32)
        .. (status.coreReady ~= nil and ("; core ready " .. shown(status.coreReady, 16)) or "")
        .. (status.phase ~= nil and ("; phase " .. shown(status.phase, 48)) or "")
    if status.reason ~= nil then
        out[#out + 1] = "  reason: " .. shown(status.reason, 96)
    end
    local facts = type(status.failure) == "table" and status.failure or nil
    if facts then
        local row = {}
        for _, field in ipairs({"stage", "detail", "cause", "component", "owner"}) do
            if facts[field] ~= nil then
                row[#row + 1] = field .. "=" .. shown(facts[field], 64)
            end
        end
        if #row > 0 then out[#out + 1] = "  " .. table.concat(row, "; ") end
        if facts.formatClass ~= nil or facts.formatVersion ~= nil then
            out[#out + 1] = "  saved format: " .. shown(facts.formatClass, 24)
                .. (facts.formatVersion ~= nil
                    and (" version " .. shown(facts.formatVersion, 16)) or "")
                .. (extended and facts.formatField ~= nil
                    and (" (" .. shown(facts.formatField, 64) .. ")") or "")
        end
        local width = type(facts.keyWidth) == "table" and facts.keyWidth or nil
        if width then
            out[#out + 1] = "  refused key: " .. shown(width.path, 64)
                .. ", depth " .. shown(width.depth, 8)
                .. ", " .. shown(width.keyType, 16) .. " key of "
                .. shown(width.keyBytes, 16) .. " bytes, limit "
                .. shown(width.limit, 16)
                .. ", path exception " .. shown(width.exception, 24)
            out[#out + 1] = "  (the key, the character and the record contents are not included)"
        end
        if extended then
            if facts.error ~= nil then
                out[#out + 1] = "  owner error: " .. shown(facts.error, 160)
            end
            if facts.row ~= nil then
                out[#out + 1] = "  selection row: " .. shown(facts.row, 16)
            end
            if facts.legacyClass ~= nil then
                out[#out + 1] = "  legacy class: " .. shown(facts.legacyClass, 32)
            end
        end
    end
    if failed then
        out[#out + 1] = "  A start-up refusal is a business rule, not a Lua error"
            .. " and not an incident: both histories can be empty."
    end
    return out
end

function M.Summary(selection)
    local support = Nexus and Nexus.SupportIncidents
    -- Protected like every other owner read here: an incident owner that
    -- raises must not take away the start-up reason, which is the one fact a
    -- player with a failed start-up came to copy.
    local okIncidents, incidents = pcall(function()
        return support and type(support.History) == "function" and support.History() or {}
    end)
    if not okIncidents or type(incidents) ~= "table" then incidents = {} end
    local incident = nil
    if type(selection) == "table" then incident = incidentShape(selection)
    elseif type(selection) == "number" then
        for _, entry in ipairs(incidents) do
            if entry.id == selection then incident = entry end
        end
    else
        incident = incidents[#incidents]
    end
    local out = {}
    local function add(line)
        out[#out + 1] = line
    end
    add("Nexus support summary (report format " .. FORMAT .. ")")
    add("Build: " .. buildLabel() .. "; character alias: " .. alias(playerName()))
    local semantic = limits()
    if semantic then
        add("Supported envelope: " .. safeText(semantic.ordinary, 16) .. " ordinary, "
            .. safeText(semantic.locked, 16) .. " locked, "
            .. safeText(semantic.total, 16) .. " total copies")
    end
    add("Session incidents retained: " .. #incidents)
    -- A failed start-up goes ABOVE the incident and inside the kept part of the
    -- summary: it is the reason the player is here, and it is exactly the case
    -- in which no incident and no Lua error exists to carry it.
    local startup = M.StartupSnapshot()
    if type(startup) == "table" and startup.state == "failed" then
        add("")
        for _, line in ipairs(M.StartupLines(startup, false)) do add(line) end
    end
    add("")
    for _, line in ipairs(M.IncidentLines(incident)) do add(line) end
    local budget = SUMMARY_MAX_BYTES
    local used = 0
    for _, line in ipairs(out) do used = used + #escape(line) + 1 end
    -- Context after the incident, and only while it fits.
    local context = {}
    context[#context + 1] = ""
    context[#context + 1] = "Other retained incidents this session (newest last):"
    if #incidents == 0 then
        context[#context + 1] = "  (none)"
    end
    for _, entry in ipairs(incidents) do
        if not incident or entry.id ~= incident.id then
            context[#context + 1] = "  " .. safeText(entry.id, 16) .. ". "
                .. shown(retained(entry.kind, 64), 64) .. "/"
                .. shown(retained(entry.reason, 96), 96)
                .. " from " .. (retained(entry.producer, 96) or "unknown producer")
                .. " x" .. safeText(entry.occurrences or 1, 16)
        end
    end
    -- Every owner read here is protected: this summary is the route a player
    -- uses when something else is already broken, so one failing owner must
    -- not take it away.
    if type(startup) == "table" and startup.state ~= "failed" then
        context[#context + 1] = ""
        for _, line in ipairs(M.StartupLines(startup, false)) do
            context[#context + 1] = line
        end
    end
    local errors = Nexus and Nexus.Errors
    local okHistory, history = pcall(function()
        return errors and type(errors.History) == "function" and errors.History() or {}
    end)
    if not okHistory or type(history) ~= "table" then history = {} end
    context[#context + 1] = "Recorded Lua errors this session: " .. #history
        .. (#history == 0 and (#incidents > 0
            and " (a refusal is not an error; the incident above is retained separately)"
            or " (a refusal is not an error, and nothing was retained in either history)") or "")
    local omitted = 0
    for _, line in ipairs(context) do
        local size = #escape(line) + 1
        if used + size <= budget - 80 then
            add(line)
            used = used + size
        else
            omitted = omitted + 1
        end
    end
    if omitted > 0 then
        add("[" .. omitted .. " context line(s) omitted to keep this summary under "
            .. SUMMARY_MAX_BYTES .. " bytes; use Prepare report file for the full retained report]")
    end
    -- The copyable size is measured on the text the player selects, and the
    -- backstop drops WHOLE LINES: cutting mid-line could leave a partial
    -- escape or half a recorded identifier in the ticket.
    local cut = false
    while true do
        local text = table.concat(out, "\n")
        local note = "\n[summary shortened to stay under " .. SUMMARY_MAX_BYTES
            .. " bytes; use Prepare report file for everything retained]"
        if #text + (cut and #note or 0) <= SUMMARY_MAX_BYTES or #out <= 3 then
            if cut then text = text .. note end
            return text, {bytes = #text, incidents = #incidents,
                cut = cut or nil,
                incidentId = incident and incident.id or nil}
        end
        table.remove(out)
        cut = true
    end
end

------------------------------------------------------------------------
-- Detached preparation for the file route
------------------------------------------------------------------------

local function sectionLines(name, builder)
    local ok, lines = pcall(builder)
    if not ok or type(lines) ~= "table" then
        return {"[section " .. name .. " was unavailable and is omitted]"}, false
    end
    return lines, true
end

-- Build the report in bounded steps so a large history cannot stall a frame.
-- The caller pumps Step() until it returns "done". Nothing is handed to the
-- helper until the whole snapshot exists.
function M.NewPreparation(options)
    options = type(options) == "table" and options or {}
    reportSequence = reportSequence + 1
    local support = Nexus and Nexus.SupportIncidents
    -- Protected exactly like the summary route: an incident owner that raises
    -- must not take the prepared file away as well.
    local okIncidents, incidents = pcall(function()
        return support and type(support.History) == "function" and support.History() or {}
    end)
    if not okIncidents or type(incidents) ~= "table" then incidents = {} end
    local incident = nil
    if type(options.incident) == "table" then incident = incidentShape(options.incident)
    else incident = incidents[#incidents] end
    local job = {
        extended = options.extended == true,
        stage = "header",
        lines = {},
        omissions = {},
        chunks = {},
        startedAt = clock(),
        id = string.format("%s-%03d", tostring(clock() or 0), reportSequence),
        incident = incident,
        incidents = incidents,
        cursor = 0,
        topic = incident and (shown(retained(incident.kind, 64), 64) .. "/"
                .. shown(retained(incident.reason, 96), 96))
            or "session report",
    }
    return job
end

local function pushLines(job, lines)
    for _, line in ipairs(lines) do job.lines[#job.lines + 1] = line end
end

function M.Step(job)
    if type(job) ~= "table" then return "done" end
    if job.stage == "header" then
        pushLines(job, {
            "Nexus support report",
            "format=" .. FORMAT .. "; id=" .. job.id,
            "build=" .. buildLabel(),
            "topic=" .. job.topic,
            "extended=" .. safeText(job.extended, 16),
            "captureStart=" .. safeText(job.startedAt, 24),
            "characterAlias=" .. alias(playerName()),
            "",
        })
        job.stage = "incident"
        return "pending"
    end
    if job.stage == "incident" then
        pushLines(job, {"-- selected incident --"})
        pushLines(job, M.IncidentLines(job.incident))
        pushLines(job, {""})
        job.stage = "incidents"
        return "pending"
    end
    if job.stage == "incidents" then
        if job.cursor == 0 then
            pushLines(job, {"-- retained incidents (" .. #job.incidents .. ") --"})
        end
        local done = 0
        while job.cursor < #job.incidents and done < 4 do
            job.cursor = job.cursor + 1
            local entry = job.incidents[job.cursor]
            pushLines(job, {"[" .. safeText(entry.id, 16) .. "]"})
            pushLines(job, M.IncidentLines(entry, {tuples = job.extended}))
            pushLines(job, {""})
            done = done + 1
        end
        if job.cursor >= #job.incidents then
            job.stage = "sections"
            job.sectionIndex = 0
        end
        return "pending"
    end
    if job.stage == "sections" then
        local sections = {
            {name = "startup", build = function()
                local status = M.StartupSnapshot() or {}
                local out = {"-- startup --"}
                -- The scalars this section has always carried, then the same
                -- retained failure facts the copyable summary shows.
                for _, key in ipairs({"state", "coreReady", "storeReady", "reason"}) do
                    if status[key] ~= nil then
                        out[#out + 1] = key .. "=" .. safeText(status[key], 96)
                    end
                end
                for _, line in ipairs(M.StartupLines(status, true)) do
                    out[#out + 1] = line
                end
                return out
            end},
            {name = "errors", build = function()
                local errors = Nexus.Errors
                local history = errors and type(errors.History) == "function"
                    and errors.History() or {}
                local out = {"-- recorded Lua errors (" .. #history .. ") --"}
                for index = 1, math.min(#history, job.extended and 20 or 5) do
                    out[#out + 1] = safeText(history[index], 240)
                end
                return out
            end},
            {name = "orb", build = function()
                local out = {"-- Orb history (diagnostic copy; it restores nothing) --"}
                local runtime = Nexus.OrbRuntime
                if not (runtime and type(runtime.RunLog) == "function") then
                    return {out[1], "not available"}
                end
                local view = runtime.RunLog("current", 1, job.extended and 40 or 8)
                if not view or not view.runId then
                    return {out[1], "no run in this session"}
                end
                out[#out + 1] = "run=" .. safeText(view.runId, 24)
                    .. "; state=" .. safeText(view.state, 32)
                    .. "; spent=" .. safeText(view.spent, 16)
                    .. "/" .. safeText(view.limit, 16)
                    .. "; operations=" .. safeText(view.total, 16)
                local history = Nexus.OrbHistory
                if history and type(history.Rows) == "function" then
                    for _, row in ipairs(history.Rows(view, nil)) do
                        out[#out + 1] = "  " .. safeText(row.ordinal, 16) .. ". "
                            .. safeText(row.source.label, 64) .. " -> "
                            .. safeText(row.replacement.label, 64)
                            .. " [" .. safeText(row.result.label, 64) .. "]"
                    end
                end
                return out
            end},
        }
        job.sectionIndex = (job.sectionIndex or 0) + 1
        local section = sections[job.sectionIndex]
        if not section then
            job.stage = "chunks"
            return "pending"
        end
        local lines, ok = sectionLines(section.name, section.build)
        if not ok then job.omissions[#job.omissions + 1] = section.name end
        pushLines(job, lines)
        pushLines(job, {""})
        return "pending"
    end
    if job.stage == "chunks" then
        local text = table.concat(job.lines, "\n")
        job.rawBytes = #text
        if #text > TOTAL_BYTES then
            -- Truthful refusal: the essential incident is preserved, the rest
            -- is declared, and the previous stored report is left alone.
            local essential = table.concat(M.IncidentLines(job.incident), "\n")
            job.omissions[#job.omissions + 1] = "context beyond the selected incident"
            local header = "Nexus support report (partial)\nformat=" .. FORMAT
                .. "; id=" .. job.id .. "; build=" .. buildLabel()
                .. "\nThe full retained report is larger than the supported "
                .. TOTAL_BYTES .. " bytes, so only the selected incident is included.\n\n"
            -- The replacement is checked against the same bound it exists to
            -- satisfy. A selected incident that still does not fit is cut on a
            -- line boundary and says so, instead of being handed over oversized.
            local room = TOTAL_BYTES - #header - 120
            if #essential > room then
                local kept, used = {}, 0
                for _, line in ipairs(M.IncidentLines(job.incident)) do
                    if used + #line + 1 > room then break end
                    kept[#kept + 1] = line
                    used = used + #line + 1
                end
                essential = table.concat(kept, "\n")
                    .. "\n[the selected incident itself exceeds the supported size; later lines are omitted]"
                job.omissions[#job.omissions + 1] = "part of the selected incident"
            end
            text = header .. essential
            job.partial = true
        end
        local position = 1
        while position <= #text do
            job.chunks[#job.chunks + 1] = text:sub(position, position + CHUNK_BYTES - 1)
            position = position + CHUNK_BYTES
        end
        job.stage = "done"
        job.report = {
            meta = {
                format = FORMAT,
                id = job.id,
                build = buildLabel(),
                topic = job.topic,
                extended = job.extended,
                partial = job.partial == true,
                omissions = #job.omissions > 0
                    and table.concat(job.omissions, ",") or "none",
                captureStart = job.startedAt,
                captureEnd = clock(),
                rawBytes = job.rawBytes,
                -- The header declares what the chunks are, so a reader can
                -- check the copy it received against it.
                chunkCount = #job.chunks,
                bytes = (function()
                    local total = 0
                    for _, chunk in ipairs(job.chunks) do total = total + #chunk end
                    return total
                end)(),
                checksum = checksum(job.chunks),
                incidentCount = #job.incidents,
            },
            chunks = job.chunks,
        }
        return "done"
    end
    return "done"
end

function M.Prepare(options, maxSteps)
    local job = M.NewPreparation(options)
    local steps = 0
    while M.Step(job) ~= "done" do
        steps = steps + 1
        if steps > (tonumber(maxSteps) or 500) then
            return nil, "preparation did not finish within its step budget"
        end
    end
    return job.report, nil, job
end

-- Hand a COMPLETE report to the isolated component. This is the only call in
-- Nexus that writes support data, and it writes nothing else: no profile, no
-- catalog, no receipt, no assignment.
-- The component is a separate addon, so the READ of it is protected too: a
-- broken or hostile storage owner must not take the page away.
local function storageOwner(entry)
    local ok, owner = pcall(function()
        local storage = _G.NexusSupportStorage
        return type(storage) == "table" and type(storage[entry]) == "function"
            and storage or nil
    end)
    if not ok then return nil end
    return owner
end

function M.Store(report)
    local storage = storageOwner("Replace")
    if not storage then
        return nil, "the support component is not loaded"
    end
    if type(report) ~= "table" or type(report.chunks) ~= "table"
        or #report.chunks == 0 then
        return nil, "the report was not completed, so the previous one was kept"
    end
    -- The LOOKUP and the call in one pcall: a component whose __index answers
    -- once and then raises must not raise out of the route that offered it.
    -- What it returns is copied into a shape this file owns, so a caller never
    -- holds the component's table.
    local copied = {}
    local ok, stored, why = pcall(function()
        local value, meta = storage.Replace(report)
        if type(meta) ~= "table" then
            -- A component that answered with a note rather than a header:
            -- the note is kept, converted, instead of being discarded.
            if meta ~= nil then copied.note = safeText(meta, 240) end
            return value, nil
        end
        -- The header the component accepted, field by field, into a table
        -- this file owns. Numbers stay numbers; text is converted.
        for _, field in ipairs({"bytes", "rawBytes", "chunkCount",
            "captureStart", "captureEnd", "incidentCount", "format"}) do
            copied[field] = tonumber(meta[field])
        end
        for _, field in ipairs({"id", "build", "topic", "checksum", "omissions"}) do
            if meta[field] ~= nil then copied[field] = safeText(meta[field], 120) end
        end
        copied.partial = meta.partial == true or nil
        copied.extended = meta.extended == true or nil
        return value, nil
    end)
    if not ok then
        return nil, "the support component refused the report"
    end
    if not stored then
        return nil, why ~= nil and safeText(why, 240)
            or "the support component refused the report"
    end
    -- `true`, not their table: the first return value is a verdict, and a
    -- caller holding the component's table is the thing this route avoids.
    return true, copied
end

-- The LAST prepared report, as scalars this file owns. The component's own
-- table is never handed to a caller, and never read outside this pcall.
function M.StoredSummary()
    local storage = storageOwner("Latest")
    if not storage then return nil end
    local out = {}
    local ok, found = pcall(function()
        local latest = storage.Latest()
        if type(latest) ~= "table" then return false end
        out.id = safeText(latest.id, 48)
        out.bytes = safeText(latest.bytes, 24)
        out.chunkCount = safeText(latest.chunkCount, 16)
        out.checksum = safeText(latest.checksum, 24)
        return true
    end)
    if not ok or not found then return nil end
    return out
end

-- What the stored copy says about ITSELF, checked against this session's own
-- checksum of it. The page never touches the component: it asks for this.
function M.StoredReport()
    local storage = storageOwner("Read")
    local summary = M.StoredSummary()
    if not storage or not summary then return nil end
    local ok, recomputed = pcall(function()
        local stored = storage.Read()
        if type(stored) ~= "table" or type(stored.chunks) ~= "table" then return nil end
        local chunks = {}
        for index, chunk in ipairs(stored.chunks) do
            if type(chunk) ~= "string" then return nil end
            chunks[index] = chunk
        end
        return checksum(chunks)
    end)
    summary.recomputed = ok and recomputed or nil
    -- NOT `a and b or nil`: the answer that matters here is `false`, and that
    -- form collapses it to nil - which silently retired the mismatch warning.
    if summary.recomputed ~= nil then
        summary.matches = summary.recomputed == summary.checksum
    end
    return summary
end

function M.StorageStatus()
    local storage = storageOwner("Status")
    if not storage then
        return {loaded = false, ready = false,
            reason = "the support component is not loaded"}
    end
    local ok, status = pcall(function()
        local value = storage.Status()
        if type(value) ~= "table" then return nil end
        -- Copied into a shape this file owns: a caller reading the result
        -- never touches the component's table or its metamethods.
        -- false is an answer, not a value to print: a component saying it is
        -- NOT incompatible must not be read as incompatible with the reason
        -- "false", which would disable the file route for good.
        local incompatible = value.incompatible
        local reason = value.reason
        -- Reaching here means the component answered, so it is loaded
        -- whatever it says about itself; `ready` stays its own statement.
        return {loaded = true,
            ready = value.ready == true,
            incompatible = (incompatible ~= nil and incompatible ~= false)
                and safeText(incompatible, 120) or nil,
            reason = (reason ~= nil and reason ~= false)
                and safeText(reason, 240) or nil}
    end)
    if not ok or type(status) ~= "table" then
        return {loaded = false, ready = false,
            reason = "the support component did not answer"}
    end
    return status
end

-- What the player is told after a successful preparation. It states exactly
-- what has and has not happened.
function M.WrittenNotice(meta)
    local id = type(meta) == "table" and meta.id or "?"
    return "Report " .. safeText(id, 48) .. " is prepared in memory. WoW writes the "
        .. "file when you reload, log out, or exit normally. It is not yet "
        .. "verified on disk."
end

function M.FilePathHint()
    return "WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua"
end

return M
