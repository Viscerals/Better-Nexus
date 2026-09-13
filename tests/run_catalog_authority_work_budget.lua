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
UnitName = function() return "Boganic" end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = GetNormalizedRealmName

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

-- Count every table-iteration step reached from one public call. This observes
-- the complete call graph, including helpers reached through Gate or commit
-- preparation, instead of scanning only selected source blocks.
local function CountedCall(call)
    local oldPairs, oldIpairs, oldNext = pairs, ipairs, next
    local steps = 0
    next = function(value, key)
        local nextKey, nextValue = oldNext(value, key)
        if nextKey ~= nil then steps = steps + 1 end
        return nextKey, nextValue
    end
    pairs = function(value)
        local iterator, state, key = oldPairs(value)
        return function(innerState, innerKey)
            local nextKey, nextValue = iterator(innerState, innerKey)
            if nextKey ~= nil then steps = steps + 1 end
            return nextKey, nextValue
        end, state, key
    end
    ipairs = function(value)
        local iterator, state, key = oldIpairs(value)
        return function(innerState, innerKey)
            local nextKey, nextValue = iterator(innerState, innerKey)
            if nextKey ~= nil then steps = steps + 1 end
            return nextKey, nextValue
        end, state, key
    end
    local results = {pcall(call)}
    pairs, ipairs, next = oldPairs, oldIpairs, oldNext
    if not results[1] then error(results[2], 2) end
    return steps, unpack(results, 2)
end

local function MaximumDatabase()
    local rows = {
        wbRead=S.LocalBuild("wbRead", 1),
        wbPut=S.LocalBuild("wbPut", 1),
        wbRemove=S.LocalBuild("wbRemove", 1),
        wbTomb=S.LocalBuild("wbTomb", 1),
        wbMaintain=S.LocalBuild("wbMaintain", 1),
    }
    for index = 6, 2048 do
        local id = string.format("wb-future-%04d", index)
        rows[id] = {id=id, schemaVersion=99}
    end
    return S.Database(rows)
end

-- This observer counts every fixed-schema helper loop in addition to raw source
-- edges. 8,192 is a conservative fixed ceiling below one complete maximum-root
-- clone; the V1 ledgers below remain the normative 64/64/2,048 slice proof.
local PUBLIC_STEP_MAXIMUM = 8192

Case("WB-12",
    "maximum-root admission finalization stays inside one measured slice",
function()
    local db = MaximumDatabase()
    NexusDB, WishlistRealizerDB = db, nil
    Nexus.LoadoutEvidence.Init(db)
    local catalog = Nexus.BuildCatalog
    local result, calls, maximum = nil, 0, 0
    repeat
        local steps
        steps, result = CountedCall(function()
            return catalog.Init(db, Nexus.BundledBuilds)
        end)
        calls = calls + 1
        if steps > maximum then maximum = steps end
    until type(result) == "table" and result.state ~= "pending" or calls >= 4096
    Check(type(result) == "table" and result.state == "ROOT_ADMITTED",
        "maximum-root admission did not reach a terminal admitted root")
    Check(maximum <= PUBLIC_STEP_MAXIMUM,
        "one admission call performed " .. maximum
            .. " table-iteration steps; finalization or witness work escaped "
            .. "the persistent slice")
end)

Case("WB-13",
    "maximum-root reads, Begin, mutations, and maintenance stay bounded",
function()
    local db = MaximumDatabase()
    S.Bind(db)
    local catalog = Nexus.BuildCatalog
    local offenders = {}
    local function Measure(name, call)
        local steps, first, second, third = CountedCall(call)
        if steps > PUBLIC_STEP_MAXIMUM then
            offenders[#offenders + 1] = name .. "=" .. steps
        end
        return first, second, third
    end
    local function Drain(name, result, why, ticket)
        Check(result == nil and why == "ROOT_MUTATION_PENDING"
                and type(ticket) == "table" and ticket.state == "pending",
            name .. " did not return the explicit nil/reason/ticket pending contract")
        local callbacks = 0
        Check(catalog.BindMutationCompletion(ticket, function(settled)
            callbacks = callbacks + 1
            Check(settled == ticket and settled.state == "committed",
                name .. " completion callback received the wrong ticket state")
        end) == true, name .. " pending ticket rejected its owner callback")
        local calls = 0
        while ticket.state == "pending"
            and calls < 4096 do
            local pumped = Measure(name .. ".pump", function()
                return catalog.PumpRootAdmission()
            end)
            Check(pumped == ticket,
                name .. " pump did not return the retained completion ticket")
            calls = calls + 1
        end
        Check(calls < 4096, name .. " candidate did not reach a terminal state")
        Check(ticket.state == "committed" and ticket.committed == true,
            name .. " did not preserve and settle one explicit completion ticket")
        Check(callbacks == 1,
            name .. " completion callback count was " .. tostring(callbacks))
        return ticket.state == "committed"
    end

    Measure("Get", function() return catalog.Get("wbRead") end)
    Measure("Count", function() return catalog.Count() end)
    local token = Measure("BeginRecordCursor", function()
        return catalog.BeginRecordCursor()
    end)
    Check(type(token) == "table", "bounded cursor Begin was refused")
    Check(Drain("Put", Measure("Put", function()
        return catalog.Put(S.LocalBuild("wbPut", 2, {lastModified=2}),
            {source="local"})
    end)), "bounded Put was refused")
    Check(Drain("RemoveOverlay", Measure("RemoveOverlay", function()
        return catalog.RemoveOverlay("wbRemove")
    end)), "bounded overlay removal was refused")
    Check(Drain("SetTombstone", Measure("SetTombstone", function()
        return catalog.SetTombstone("wbTomb", {
            stamp=now, author="Boganic", ownerKey="boganic@ebonhold",
            ownerVerified=true,
        }, {source="local"})
    end)), "bounded tombstone was refused")
    local handle = Measure("BeginCatalogMaintenance", function()
        return catalog.BeginCatalogMaintenance({database=db,
            operation="retention"})
    end)
    Check(type(handle) == "table", "bounded maintenance Begin was refused")
    Check(Measure("MaintenanceEvictOverlay", function()
        return catalog.MaintenanceEvictOverlay(handle, "wbMaintain")
    end), "bounded maintenance staging was refused")
    Check(Drain("CommitMaintenance", Measure("CommitMaintenance", function()
        return catalog.CommitMaintenance(handle)
    end)), "bounded maintenance commit was refused")
    Check(#offenders == 0,
        "public maximum-root calls performed proportional work: "
            .. table.concat(offenders, ", "))
end)

Case("WB-14", "NEGATIVE CONTROL: public-call meter detects a planted root scan", function()
    local values = {}
    for index = 1, 16384 do values[index] = index end
    local steps = CountedCall(function()
        local total = 0
        for _, value in ipairs(values) do total = total + value end
        return total
    end)
    Check(steps > PUBLIC_STEP_MAXIMUM,
        "public-call meter did not detect a planted maximum-root scan")
end)

Case("WB-15", "bundle copy splits a long scalar across byte slices", function()
    S.Reload()
    local db = WideDatabase(9)
    db.dataRetention = {note=string.rep("x", 8193)}
    local summary = S.Bind(db)
    local catalog = Nexus.BuildCatalog
    Check(summary.state == "ROOT_ADMITTED", "long-scalar fixture did not admit")
    local counters = catalog.BudgetCounters()
    Check(counters.maxPerPump.bytesInspected <= 2048,
        "bundle copy exceeded byte slice: " .. tostring(counters.maxPerPump.bytesInspected))
    Check(rawget(db, "authorityBundle").dataRetention.note == db.dataRetention.note,
        "bounded copy changed the long scalar")
end)

Case("WB-16", "baseline pruning does not drain full rows inside finalization", function()
    S.Reload()
    local rows, baseline = {}, {}
    for index = 1, 32 do
        local id = "prune-budget-" .. index
        local row = S.Build(id, 79, 6)
        rows[id], baseline[id] = row, row
    end
    local db, bundle = S.Database(rows), S.Bundle(baseline)
    NexusDB = db
    Nexus.LoadoutEvidence.Init(db)
    local catalog, maximum, result = Nexus.BuildCatalog, 0, nil
    for _ = 1, catalog.Budget().maximumPumps do
        local steps
        steps, result = CountedCall(function() return catalog.Init(db, bundle) end)
        maximum = math.max(maximum, steps)
        if result.state ~= "pending" then break end
    end
    Check(result.state == "ROOT_ADMITTED", "redundant overlay fixture did not admit")
    Check(maximum <= PUBLIC_STEP_MAXIMUM,
        "baseline pruning performed unbounded work in one pump: " .. maximum)
    Check(S.Count(S.Durable(db)) == 0 and catalog.Count() == 32,
        "bounded pruning changed the visible baseline or retained redundant rows")
end)

Case("WB-17", "rich-row index construction obeys every index slice", function()
    S.Reload()
    local row = S.Build("index-budget", 79, 0, {title=string.rep("t", 1024)})
    local db = S.Database({[row.id]=row})
    local result = S.Bind(db)
    local catalog = Nexus.BuildCatalog
    Check(result.state == "ROOT_ADMITTED" and catalog.Count() == 1,
        "valid rich index fixture was not admitted")
    local counters = catalog.BudgetCounters().maxPerPump
    Check(counters.indexEdges <= 64 and counters.indexNodes <= 64
            and counters.indexBytes <= 2048,
        string.format("rich row exceeded index slice: edges=%d nodes=%d bytes=%d",
            counters.indexEdges, counters.indexNodes, counters.indexBytes))
    Check(catalog.FindExactFingerprintId(catalog.AuthorityState(row.id).fingerprint) == row.id,
        "bounded index construction lost exact lookup")
end)

Case("WB-18", "small rich roots cannot bypass the public mutation work bound", function()
    S.Reload()
    local rows = {}
    for index = 1, 8 do
        local id = "small-rich-" .. index
        rows[id] = S.LocalBuild(id, 79)
    end
    local db = S.Database(rows)
    Check(S.Bind(db).state == "ROOT_ADMITTED", "small rich source did not admit")
    local catalog, maximum = Nexus.BuildCatalog, 0
    local steps, ok, why, ticket = CountedCall(function()
        return catalog.Put(S.LocalBuild("small-rich-1", 1, {title="updated"}),
            {source="local"})
    end)
    maximum = math.max(maximum, steps)
    Check(ok == nil and why == "ROOT_MUTATION_PENDING" and type(ticket) == "table",
        "eight rich source rows bypassed the aggregate one-call bounds")
    Check(catalog.Get("small-rich-1").title ~= "updated",
        "pending rich-source mutation exposed a partial replacement")
    if ok == nil and why == "ROOT_MUTATION_PENDING" then
        Check(type(ticket) == "table", "small rich mutation omitted its ticket")
        for _ = 1, catalog.Budget().maximumPumps do
            if ticket.state ~= "pending" then break end
            steps = CountedCall(function() return catalog.PumpRootAdmission() end)
            maximum = math.max(maximum, steps)
        end
        ok = ticket.committed
    end
    Check(ok == true and catalog.Get("small-rich-1").title == "updated",
        "small rich mutation did not publish the complete replacement")
    Check(maximum <= PUBLIC_STEP_MAXIMUM,
        "small rich mutation escaped the public work bound: " .. maximum)
end)

Case("WB-19", "evidence pool size cannot escape the public mutation work bound", function()
    for _, poolSize in ipairs({100,10000}) do
        S.Reload()
        local entries={}
        for index=1,poolSize do
            local key,normalized=Nexus.LoadoutEvidence.Fingerprint({
                {spellId=700000+index,quality=1,stacks=1},
            })
            Check(key~=nil,"canonical pool fixture was refused")
            entries[key]=normalized
        end
        local db=S.Database({poolSource=S.LocalBuild("poolSource",1)})
        db.loadoutEvidence={schemaVersion=1,entries=entries}
        Check(S.Bind(db).state=="ROOT_ADMITTED","evidence pool fixture did not admit")
        local catalog,maximum=Nexus.BuildCatalog,0
        local steps,ok,why,ticket=CountedCall(function()
            return catalog.Put(S.LocalBuild("poolSource",1,{title="pool updated"}),{source="local"})
        end)
        maximum=math.max(maximum,steps)
        if ok==nil and why=="ROOT_MUTATION_PENDING" then
            Check(type(ticket)=="table","evidence mutation omitted its ticket")
            for _=1,catalog.Budget().maximumPumps do
                if ticket.state~="pending" then break end
                steps=CountedCall(function() return catalog.PumpRootAdmission() end)
                maximum=math.max(maximum,steps)
            end
            ok=ticket.committed
        end
        Check(ok==true and catalog.Get("poolSource").title=="pool updated",
            "evidence mutation did not publish the complete replacement")
        local selected=rawget(db,"authorityBundle").loadoutEvidence.entries
        for key,value in pairs(entries) do
            Check(S.Encode(selected[key])==S.Encode(value),"evidence mutation lost or changed a retained entry")
        end
        print("WB-19 OBSERVED pool="..poolSize.." maximum="..maximum)
        Check(maximum<=PUBLIC_STEP_MAXIMUM,
            "evidence pool escaped the public work bound: "..maximum.." for "..poolSize.." entries")
    end
end)

Case("WB-20", "rich incoming rows cannot drain preparation synchronously", function()
    S.Reload()
    local rows = {}
    for index = 1, 8 do
        local id = "small-rich-" .. index
        rows[id] = S.LocalBuild(id, 79)
    end
    local db = S.Database(rows)
    Check(S.Bind(db).state == "ROOT_ADMITTED", "small rich source did not admit")
    local catalog, maximum = Nexus.BuildCatalog, 0
    local steps, ok, why, ticket = CountedCall(function()
        return catalog.Put(S.LocalBuild("small-rich-1", 79, {title="updated"}),
            {source="local"})
    end)
    maximum = math.max(maximum, steps)
    Check(ok == nil and why == "ROOT_MUTATION_PENDING" and type(ticket) == "table",
        "eight rich source rows bypassed the aggregate one-call bounds")
    Check(catalog.Get("small-rich-1").title ~= "updated",
        "pending rich-source mutation exposed a partial replacement")
    if ok == nil and why == "ROOT_MUTATION_PENDING" then
        Check(type(ticket) == "table", "small rich mutation omitted its ticket")
        for _ = 1, catalog.Budget().maximumPumps do
            if ticket.state ~= "pending" then break end
            steps = CountedCall(function() return catalog.PumpRootAdmission() end)
            maximum = math.max(maximum, steps)
        end
        ok = ticket.committed
    end
    Check(ok == true and catalog.Get("small-rich-1").title == "updated",
        "small rich mutation did not publish the complete replacement")
    Check(maximum <= PUBLIC_STEP_MAXIMUM,
        "small rich mutation escaped the public work bound: " .. maximum)
end)

-- Wave 3 MASTER-W2-004. A small catalog can still carry a large independent
-- bundle domain. Row count cannot select a synchronous mutation path.
Case("WB-21", "small roots with a large independent bundle domain retain one slice ledger", function()
    S.Reload()
    local db = S.Database({smallDomain=S.LocalBuild("smallDomain", 1)})
    db.dataRetention = {}
    for index = 1, 10000 do
        db.dataRetention[string.format("domain-%05d", index)] = index
    end
    Check(S.Bind(db).state == "ROOT_ADMITTED", "large domain fixture did not admit")
    local maximum = 0
    local steps, ok, why, ticket = CountedCall(function()
        return Nexus.BuildCatalog.Put(S.LocalBuild("smallDomain", 2),
            {source="local"})
    end)
    maximum = math.max(maximum, steps)
    Check(ok == nil and why == "ROOT_MUTATION_PENDING" and type(ticket) == "table",
        "small row count bypassed persistent construction for a large bundle domain")
    for _ = 1, Nexus.BuildCatalog.Budget().maximumPumps do
        if ticket.state ~= "pending" then break end
        steps = CountedCall(function() return Nexus.BuildCatalog.PumpRootAdmission() end)
        maximum = math.max(maximum, steps)
    end
    Check(ticket.state == "committed" and Nexus.BuildCatalog.Get("smallDomain") ~= nil,
        "large-domain mutation did not publish its complete candidate")
    Check(maximum <= PUBLIC_STEP_MAXIMUM,
        "large independent bundle domain escaped the slice ledger: " .. maximum)
end)

-- Wave 3 MASTER-W2-006. Legacy collection wrappers must stop on traversal,
-- even when a maximum root has fewer than eight matching rows.
Case("WB-22", "sparse legacy collections stop before scanning a maximum root", function()
    S.Reload()
    local rows = {zzSparse=S.LocalBuild("zzSparse", 1)}
    for index = 1, 2047 do
        local id = string.format("aa-future-%04d", index)
        rows[id] = {id=id, schemaVersion=99}
    end
    Check(S.Bind(S.Database(rows)).state == "ROOT_ADMITTED",
        "sparse maximum-root fixture did not admit")
    local steps, result, why = CountedCall(function()
        return Nexus.BuildCatalog.All()
    end)
    Check(result == nil and why == "CURSOR_REQUIRED",
        "sparse legacy collection drained the complete root instead of requiring a cursor")
    Check(steps <= 256,
        "sparse legacy collection inspected proportional root work: " .. steps)
end)

Case("WB-23", "concentrated hash buckets retain collection, sort, and byte frontiers", function()
    S.Reload()
    dofile("core/BuildHashCache.lua")
    local cache = Nexus.BuildHashCache
    local rows, candidate, admitted = {}, 1, 0
    while admitted < 64 do
        local id = string.format("hash-concentrated-%05d", candidate)
        candidate = candidate + 1
        if cache.Bucket(id) == 1 then
            admitted = admitted + 1
            rows[id] = S.LocalBuild(id, 1, {
                lastModified=admitted,
                fingerprintHash=string.format("fp-%04d", admitted),
            })
        end
    end
    Check(S.Bind(S.Database(rows)).state == "ROOT_ADMITTED",
        "concentrated hash fixture did not admit")
    Check(cache.Legacy() == nil,
        "concentrated hash bucket completed inside one compatibility call")

    local maximum, pumps, ready = 0, 0, false
    while not ready and pumps < 10000 do
        local steps
        steps, ready = CountedCall(function() return cache.Pump() end)
        maximum = math.max(maximum, steps)
        pumps = pumps + 1
    end
    local digest, stats = cache.Legacy(), cache.Stats()
    Check(ready == true and type(digest) == "string" and digest ~= "",
        "concentrated hash bucket did not publish a complete digest")
    Check(pumps > 1 and stats.hashPumps > 1
            and stats.maxHashWorkPerPump <= 64,
        "concentrated hash work did not retain its incremental frontier")
    Check(maximum <= PUBLIC_STEP_MAXIMUM,
        "one hash-cache pump escaped the public work bound: " .. maximum)
end)

S.Finish("catalog authority work budget")
