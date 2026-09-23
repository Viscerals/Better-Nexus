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
        local seed = tostring(clock() or 0) .. tostring(GetTime and GetTime() or 0)
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
    return (tostring(value):gsub("%c", " ")):sub(1, limit or 200)
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
    local evidence = Nexus and Nexus.LoadoutEvidence
    if evidence and type(evidence.SemanticLimits) == "function" then
        local ok, value = pcall(evidence.SemanticLimits)
        -- A partial answer is reported as far as it goes, never as "nil".
        if ok and type(value) == "table" then
            return {ordinary = value.ordinary or "not stated",
                locked = value.locked or "not stated",
                total = value.total or "not stated"}
        end
    end
    return nil
end

local function buildLabel()
    local release = Nexus and Nexus.Release
    return release and release.buildLabel or "unknown"
end

local function counts(line, label, value, limit)
    if type(value) ~= "table" then
        line[#line + 1] = label .. ": not retained"
        return
    end
    local text = label .. ": " .. tostring(value.ordinary or "?") .. " ordinary, "
        .. tostring(value.locked or "?") .. " locked, "
        .. tostring(value.total or "?") .. " total"
    if type(limit) == "table" then
        text = text .. " (limits " .. tostring(limit.ordinary) .. "/"
            .. tostring(limit.locked) .. "/" .. tostring(limit.total) .. ")"
    end
    line[#line + 1] = text
end

-- One incident, said plainly, with the failure-time facts first. Anything the
-- owner did not retain says so instead of being filled in.
function M.IncidentLines(incident, options)
    options = type(options) == "table" and options or {}
    local out = {}
    if type(incident) ~= "table" then
        out[#out + 1] = "No incident was retained in this session."
        return out
    end
    out[#out + 1] = "Incident: " .. (plain(incident.kind) or "not retained")
        .. " / " .. (plain(incident.reason) or "not retained")
    out[#out + 1] = "Producer: " .. (plain(incident.producer) or "not retained")
        .. "; origin: " .. (plain(incident.origin) or "unknown")
    if incident.operation or incident.ticket then
        out[#out + 1] = "Operation: " .. (plain(incident.operation) or "not retained")
            .. (incident.ticket and ("; ticket " .. plain(incident.ticket)) or "")
    end
    out[#out + 1] = "Build at failure: " .. (plain(incident.build) or "not retained")
        .. (incident.category and ("; category " .. plain(incident.category)) or "")
    out[#out + 1] = "Representation: " .. (plain(incident.representation) or "unknown")
    counts(out, "Counted at refusal", incident.counts, incident.limits)
    if incident.readiness then
        local parts = {}
        for key, value in pairs(incident.readiness) do
            parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
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
    if incident.scope then out[#out + 1] = "Scope: " .. plain(incident.scope, 240) end
    if incident.detail then out[#out + 1] = "Detail: " .. plain(incident.detail, 240) end
    out[#out + 1] = "Occurrences: " .. tostring(incident.occurrences or 1)
        .. (incident.firstAt and (" (first " .. tostring(incident.firstAt)
            .. ", last " .. tostring(incident.lastAt) .. ")") or "")
    if options.tuples ~= false and type(incident.affected) == "table"
        and #incident.affected > 0 then
        local rows = {}
        for _, tuple in ipairs(incident.affected) do
            rows[#rows + 1] = tostring(tuple.spellId or "?")
                .. "." .. tostring(tuple.quality or "?")
                .. "x" .. tostring(tuple.stacks or 1)
                .. (tuple.locked and "P" or "")
        end
        out[#out + 1] = "Affected copies retained at the boundary ("
            .. #rows .. (incident.affectedOmitted
                and (" shown, " .. incident.affectedOmitted .. " omitted") or "")
            .. "): " .. table.concat(rows, " ")
    elseif options.tuples ~= false then
        out[#out + 1] = "Affected copies: not retained"
    end
    return out
end

-- The compact report. It is BUILT at this size: the incident and its context
-- come first, and sections stop being added when the budget is reached. It is
-- never a truncated copy of the extended report.
function M.Summary(selection)
    local support = Nexus and Nexus.SupportIncidents
    local incidents = support and support.History() or {}
    local incident = nil
    if type(selection) == "table" then incident = selection
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
    add("Build: " .. buildLabel() .. "; character alias: "
        .. alias((UnitName and UnitName("player")) or "unknown"))
    local semantic = limits()
    if semantic then
        add("Supported envelope: " .. tostring(semantic.ordinary) .. " ordinary, "
            .. tostring(semantic.locked) .. " locked, "
            .. tostring(semantic.total) .. " total copies")
    end
    add("Session incidents retained: " .. #incidents)
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
            context[#context + 1] = "  " .. tostring(entry.id) .. ". "
                .. plain(entry.kind) .. "/" .. plain(entry.reason)
                .. " from " .. (plain(entry.producer) or "unknown producer")
                .. " x" .. tostring(entry.occurrences or 1)
        end
    end
    -- Every owner read here is protected: this summary is the route a player
    -- uses when something else is already broken, so one failing owner must
    -- not take it away.
    local okStartup, startup = pcall(function()
        return Nexus and Nexus.StartupStatus and Nexus.StartupStatus() or nil
    end)
    if not okStartup then startup = nil end
    if type(startup) == "table" then
        context[#context + 1] = ""
        context[#context + 1] = "Startup: state " .. tostring(startup.state)
            .. (startup.coreReady ~= nil and ("; core ready " .. tostring(startup.coreReady)) or "")
    end
    local errors = Nexus and Nexus.Errors
    local okHistory, history = pcall(function()
        return errors and type(errors.History) == "function" and errors.History() or {}
    end)
    if not okHistory or type(history) ~= "table" then history = {} end
    context[#context + 1] = "Recorded Lua errors this session: " .. #history
        .. (#history == 0 and " (a refusal is not an error; the incident above is retained separately)" or "")
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
    local incidents = support and support.History() or {}
    local incident = nil
    if type(options.incident) == "table" then incident = options.incident
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
        topic = incident and (incident.kind .. "/" .. incident.reason)
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
            "extended=" .. tostring(job.extended),
            "captureStart=" .. tostring(job.startedAt),
            "characterAlias=" .. alias((UnitName and UnitName("player")) or "unknown"),
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
            pushLines(job, {"[" .. tostring(entry.id) .. "]"})
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
                local status = Nexus.StartupStatus and Nexus.StartupStatus() or {}
                local out = {"-- startup --"}
                for _, key in ipairs({"state", "coreReady", "storeReady", "reason"}) do
                    if status[key] ~= nil then
                        out[#out + 1] = key .. "=" .. tostring(status[key])
                    end
                end
                return out
            end},
            {name = "errors", build = function()
                local errors = Nexus.Errors
                local history = errors and type(errors.History) == "function"
                    and errors.History() or {}
                local out = {"-- recorded Lua errors (" .. #history .. ") --"}
                for index = 1, math.min(#history, job.extended and 20 or 5) do
                    out[#out + 1] = plain(history[index], 240)
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
                out[#out + 1] = "run=" .. tostring(view.runId)
                    .. "; state=" .. tostring(view.state)
                    .. "; spent=" .. tostring(view.spent)
                    .. "/" .. tostring(view.limit)
                    .. "; operations=" .. tostring(view.total)
                local history = Nexus.OrbHistory
                if history and type(history.Rows) == "function" then
                    for _, row in ipairs(history.Rows(view, nil)) do
                        out[#out + 1] = "  " .. tostring(row.ordinal) .. ". "
                            .. row.source.label .. " -> " .. row.replacement.label
                            .. " [" .. row.result.label .. "]"
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
function M.Store(report)
    local storage = _G.NexusSupportStorage
    if type(storage) ~= "table" or type(storage.Replace) ~= "function" then
        return nil, "the support component is not loaded"
    end
    if type(report) ~= "table" or type(report.chunks) ~= "table"
        or #report.chunks == 0 then
        return nil, "the report was not completed, so the previous one was kept"
    end
    return storage.Replace(report)
end

function M.StorageStatus()
    local storage = _G.NexusSupportStorage
    if type(storage) ~= "table" or type(storage.Status) ~= "function" then
        return {loaded = false, ready = false,
            reason = "the support component is not loaded"}
    end
    local ok, status = pcall(storage.Status)
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
    return "Report " .. tostring(id) .. " is prepared in memory. WoW writes the "
        .. "file when you reload, log out, or exit normally. It is not yet "
        .. "verified on disk."
end

function M.FilePathHint()
    return "WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua"
end

return M
