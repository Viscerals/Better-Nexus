-- Package B / issue #22 Repair Wave 1: MASTER-RC-006 admission work budget.
--
-- Architecture 3b5de54f, line 1715 requires Catalog.Init to process no more
-- than one V1 slice. An incomplete call returns pending, and later calls with
-- the same exact source resume the private handle instead of restarting it.
--
-- Expected red before the product edit:
--   WB-01: one Init drains a wide source through many pumps.
--   WB-02: source still contains an admission-pump drain loop.
--   WB-03: negative control proves the source scanner can fail.
--   WB-04: guard proves a one-slice source still admits.
--   WB-05: guard proves the Store coordinator still converges.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("core/Store.lua")
local Case, Check = S.Case, S.Check

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end

local function ReadSource(path)
    local handle = assert(io.open(path, "rb"), "cannot open " .. path)
    local source = handle:read("*a")
    handle:close()
    return source
end

local WIDE_ROWS = 64

local function WideDatabase(rows)
    local builds = {}
    for index = 1, rows do
        local id = "wb" .. index
        builds[id] = {id=id, title="Build " .. index, author="A",
            postedAt=index, lastModified=index,
            echoes={{spellId=310000 + index, stacks=1}}}
    end
    return {settingsVersion=2, settings={autoPick=false, anchorNames={}},
        chars={}, communityBuilds=builds, syncTombstones={}, dpsCapture={}}
end

local function AdmissionPumpsForOneInit(database)
    NexusDB, WishlistRealizerDB = database, nil
    local catalog = Nexus.BuildCatalog
    local before = catalog.DebugStats().rootPumps
    if Nexus.LoadoutEvidence and Nexus.LoadoutEvidence.Init then
        Nexus.LoadoutEvidence.Init(database)
    end
    local summary = catalog.Init(database, Nexus.BundledBuilds)
    return catalog.DebugStats().rootPumps - before, summary, catalog
end

Case("WB-01", "Catalog.Init processes no more than one V1 slice", function()
    local pumps, summary = AdmissionPumpsForOneInit(WideDatabase(WIDE_ROWS))
    Check(pumps == 1,
        "one Catalog.Init call ran " .. pumps .. " admission pump(s) over a "
            .. WIDE_ROWS .. "-row source; architecture line 1715 allows exactly "
            .. "one V1 slice per call")
    if pumps == 1 then
        Check(type(summary) == "table" and summary.state == "pending",
            "an incomplete admission returned "
                .. tostring(type(summary) == "table" and summary.state or summary)
                .. "; line 1715 requires pending while frontier work remains")
    end
end)

local function DrainSites(source)
    local sites, lineNumber = {}, 0
    local loopLine = nil
    for line in (source .. "\n"):gmatch("(.-)\r?\n") do
        lineNumber = lineNumber + 1
        local trimmed = line:match("^%s*(.-)%s*$")
        if not trimmed:find("^%-%-") then
            if trimmed:find("^for%s") or trimmed:find("^while%s") then
                loopLine = lineNumber
            elseif trimmed:find("^end") then
                loopLine = nil
            elseif loopLine and trimmed:find("PumpRootAdmission%s*%(") then
                sites[#sites + 1] = "line " .. loopLine
                loopLine = nil
            end
        end
    end
    return sites
end

Case("WB-02", "no unbounded admission drain remains", function()
    local sites = DrainSites(ReadSource("core/BuildCatalog.lua"))
    Check(#sites == 0,
        "an admission drain loop remains at " .. table.concat(sites, ", ")
            .. "; line 1715 forbids Init running more than one V1 slice")
end)

Case("WB-03", "NEGATIVE CONTROL: the drain scanner detects a violation", function()
    local planted = table.concat({
        "local function Init(db)",
        "    Catalog.BeginRootAdmission(db, nil)",
        "    for _ = 1, 100000000 do",
        "        result = Catalog.PumpRootAdmission()",
        "    end",
        "end",
    }, "\n")
    Check(#DrainSites(planted) == 1,
        "the scanner did not detect exactly one planted drain")
    Check(#DrainSites("    local result = Catalog.PumpRootAdmission()") == 0,
        "the scanner reported one bounded pump as an unbounded drain")
    Check(#DrainSites("-- for _ = 1, 100 do Catalog.PumpRootAdmission() end") == 0,
        "the scanner reported a commented-out drain as a violation")
end)

Case("WB-04", "GUARD: a one-slice source still admits through Init", function()
    local pumps, _, catalog = AdmissionPumpsForOneInit(WideDatabase(1))
    Check(pumps == 1, "a one-row source did not use exactly one admission pump")
    Check(catalog.Status().state == "ROOT_ADMITTED",
        "a one-row source did not reach ROOT_ADMITTED: "
            .. tostring(catalog.Status().state))
    Check(catalog.Count() >= 1, "the admitted one-row source serves no records")
end)

Case("WB-05", "GUARD: the startup coordinator converges on a wide source", function()
    NexusDB, WishlistRealizerDB = WideDatabase(WIDE_ROWS), nil
    local result = H.BootstrapStore()
    Check(type(result) == "table" and result.state == "ready",
        "the coordinator did not reach STORE_READY over a " .. WIDE_ROWS
            .. "-row source: " .. tostring(type(result) == "table"
                and (result.reason or result.state) or result))
    local catalog = Nexus.BuildCatalog
    Check(catalog.Status().state == "ROOT_ADMITTED",
        "the catalog root is not admitted after coordinator startup: "
            .. tostring(catalog.Status().state))
    Check(catalog.Count() == WIDE_ROWS,
        "the coordinator served " .. catalog.Count() .. " of " .. WIDE_ROWS
            .. " rows; a bounded frontier must still admit every row")
end)

Case("WB-06", "maximum sparse root advances by a persistent bounded frontier", function()
    local rows = {}
    for index = 1, 2048 do
        rows[string.format("sparse-%04d", index)] = {schemaVersion=99}
    end
    local summary = S.Bind(S.Database(rows))
    Check(type(summary) == "table" and summary.state == "ROOT_ADMITTED",
        "the exact 2,048-slot root did not admit")
    local catalog = Nexus.BuildCatalog
    local token = catalog.BeginRecordCursor()
    Check(type(token) == "table", "record cursor unavailable on maximum root")
    local before = catalog.DebugStats()
    local first, firstError = catalog.RecordCursorNext(token)
    local after = catalog.DebugStats()
    Check(firstError == nil and type(first) == "table"
        and first.done == false and first.state == "COPY_PENDING",
        "one sparse Next scanned the complete maximum root instead of returning "
            .. "COPY_PENDING")
    Check((after.maxCursorRowsPerCall or math.huge) <= 8
        and (after.cursorRowsInspected or 0) - (before.cursorRowsInspected or 0) == 8,
        "one sparse Next did not expose the exact eight-row frontier")
    local calls, page = 1, first
    while type(page) == "table" and not page.done and calls < 300 do
        page = catalog.RecordCursorNext(token)
        calls = calls + 1
    end
    Check(type(page) == "table" and page.done == true,
        "the persistent sparse frontier did not exhaust")
    Check(calls == 257,
        "the 2,048-slot sparse frontier used " .. calls
            .. " calls instead of 256 bounded scans plus one done result")
end)

Case("WB-07", "mid-record defensive copy returns COPY_PENDING and resumes", function()
    local db = S.Database({copyWide=S.Build("copyWide", 79, 0)})
    S.Bind(db)
    local catalog = Nexus.BuildCatalog
    local token = assert(catalog.BeginRecordCursor())
    local first, firstError = catalog.RecordCursorNext(token)
    Check(firstError == nil and type(first) == "table"
        and first.done == false and first.state == "COPY_PENDING"
        and first.record == nil,
        "a record larger than one copy slice escaped without COPY_PENDING")
    local page, calls = first, 1
    while type(page) == "table" and page.state == "COPY_PENDING"
        and calls < 100 do
        page = catalog.RecordCursorNext(token)
        calls = calls + 1
    end
    Check(type(page) == "table" and page.done == false
        and page.id == "copyWide" and type(page.record) == "table",
        "the copy frontier did not resume to one complete record")
    Check(#page.record.echoes == 79,
        "the resumed defensive copy returned a partial record")
    local stats = catalog.DebugStats()
    Check((stats.maxCursorCopyNodesPerCall or math.huge) <= 64
        and (stats.maxCursorCopyBytesPerCall or math.huge) <= 2048,
        "the defensive-copy frontier exceeded its V1 slice")
end)

local function FunctionBody(source, name)
    local startAt = assert(source:find(name, 1, true), "missing " .. name)
    local nextFunction = source:find("\nfunction Catalog.", startAt + #name, true)
        or #source + 1
    return source:sub(startAt, nextFunction - 1)
end

Case("WB-08", "cursor Begin and legacy steps contain no whole-vector work", function()
    local source = ReadSource("core/BuildCatalog.lua")
    local offenders = {}
    local saved = FunctionBody(source, "function Catalog.BeginSavedMirrorCursor")
    local related = FunctionBody(source, "function Catalog.BeginRelatedCursor")
    local vector = source:match("local function VectorStep%b()%s*(.-)\nend") or ""
    if saved:find("SavedMirrorKeys", 1, true)
        or saved:find("pairs(", 1, true) or saved:find("table.sort", 1, true) then
        offenders[#offenders + 1] = "BeginSavedMirrorCursor"
    end
    if related:find("for ", 1, true) or related:find("pairs(", 1, true)
        or related:find("table.sort", 1, true) then
        offenders[#offenders + 1] = "BeginRelatedCursor"
    end
    if vector:find("for ", 1, true) or vector:find("while ", 1, true)
        or vector:find("pairs(", 1, true) or vector:find("ipairs(", 1, true) then
        offenders[#offenders + 1] = "VectorStep"
    end
    Check(#offenders == 0,
        "whole-vector cursor work remains in " .. table.concat(offenders, ", "))
end)

local function ProtectedCommitOffenders(source)
    local beginAt = assert(source:find("-- Protected section:", 1, true),
        "protected commit marker missing")
    local endAt = assert(source:find("\n    if not ok then", beginAt, true),
        "protected commit end missing")
    local block = source:sub(beginAt, endAt - 1)
    local offenders = {}
    for _, pattern in ipairs({"for ", "while ", "pairs(", "ipairs(",
        "CaptureToken("}) do
        if block:find(pattern, 1, true) then offenders[#offenders + 1] = pattern end
    end
    return offenders
end

Case("WB-09", "protected commit contains only fixed assignments", function()
    local offenders = ProtectedCommitOffenders(ReadSource("core/BuildCatalog.lua"))
    Check(#offenders == 0,
        "protected commit still contains variable work: "
            .. table.concat(offenders, ", "))
end)

Case("WB-10", "NEGATIVE CONTROL: protected scan detects variable work", function()
    local planted = table.concat({
        "-- Protected section:",
        "local ok = pcall(function()",
        "    for _, item in ipairs(items) do use(item) end",
        "end)",
        "    if not ok then",
    }, "\n")
    local offenders = ProtectedCommitOffenders(planted)
    Check(#offenders >= 2,
        "the protected-commit scanner no longer detects a planted loop")
end)

Case("WB-11", "missing bundle preserves one multi-slice admission handle", function()
    local db = WideDatabase(WIDE_ROWS)
    NexusDB, Nexus.BundledBuilds = db, nil
    Nexus.LoadoutEvidence.Init(db)
    local catalog = Nexus.BuildCatalog
    local result, calls = catalog.Init(db), 1
    while type(result) == "table" and result.state == "pending"
        and calls < 128 do
        calls = calls + 1
        result = catalog.Init(db)
    end
    Check(calls > 1 and calls < 128
        and type(result) == "table" and result.state == "ROOT_ADMITTED",
        "a missing optional bundle restarted multi-slice admission: calls="
            .. calls .. " state=" .. tostring(type(result) == "table"
                and result.state or result))
end)

S.Finish("catalog authority work budget")
