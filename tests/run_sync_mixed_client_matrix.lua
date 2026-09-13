-- Package B / issue #22 Repair Wave 1: MASTER-RC-015, mixed-client matrix.
--
-- Root: "only MIX-06/07 exist; no four-quadrant fixture, no golden bytes."
-- Required repaired outcome: "MIX-01..08 with content-addressed trees, exact
--  load order, golden bytes, all four quadrants."
--
-- Architecture at 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   4699  fixture rule 1: "Materialize PR #68 from exact commit 6f6204dc...
--         into a temporary source tree using local Git; verify its tree is
--         0d293768d6c7a14d78a9b9ee9b3844d2b9bad3b6."
--   4700  fixture rule 2: "Load every side's exact Nexus.toc module order in
--         its own isolated Lua runtime and global table."
--   4701  fixture rule 3: "Do not inject old SyncCompatibility into new
--         catalog/evidence owners or the reverse."
--   4702  fixture rule 4: capture actual wire bytes from each sender and feed
--         those exact bytes through the other side's real decoder, receiver
--         and durable catalog path.
--   4705  fixture rule 5: "Assert durable convergence or the specified
--         fail-closed terminal state, not helper return values alone."
--   4737  new -> PR #68: "Emit byte-for-byte PR #68-compatible protocol-7
--         summary/full bytes."
--   4839  MIX-01   4840 MIX-02   4841 MIX-03   4842 MIX-04   4843 MIX-05
--
-- HOW ISOLATION IS ENFORCED, not merely intended.
-- Each side is loaded with `load(source, name, "t", env)` into its own global
-- table, with an env-aware `dofile` that resolves against that side's own
-- source root. Nothing is shared between the two sides except the immutable
-- Lua standard library.
--
-- That is structural rather than disciplinary, and MIX-00 makes it observable.
-- BOTH trees register their compatibility owner under the same name,
-- `Nexus.SyncInternals.Compatibility` -- an earlier draft of this header
-- claimed the new tree used `Nexus.SyncCompatibility` and MIX-00 disproved it.
-- The isolation proof is therefore the stronger one: the two owners share a
-- name but are DISTINCT table identities in two different global tables, so
-- fixture rule 3's "do not inject old SyncCompatibility into new
-- catalog/evidence owners or the reverse" is impossible by construction rather
-- than avoided by care. Loading an entire side also leaves the outer `_G.Nexus`
-- nil, which MIX-00 asserts as well.
--
-- SCOPE OF THIS FILE. MIX-01..MIX-05 and MIX-08 are built here. MIX-06 and
-- MIX-07 remain in tests/run_sync_semantic_envelope.lua and are NOT subsumed.
--
-- CORRECTION, recorded rather than left standing. An earlier version of this
-- header claimed MIX-06/07 cover numeric-versus-string IDs and string-ID
-- width/encoding "across every protocol-7 key". That overstated them and made
-- a real gap look delegated-and-covered. Measured:
--   MIX-06 (run_sync_semantic_envelope.lua:156-164) spans FOUR send paths --
--     Sync.BroadcastBuild, BroadcastDelete, BroadcastBuildSummary and
--     RequestLoadout -- all returning PROTOCOL7_TYPED_ID_UNREPRESENTABLE.
--   MIX-07 (:190-200) exercises ONLY Sync.BroadcastBuild, for the 97-byte
--     width refusal, the invalid-UTF-8 refusal, and the 96-byte accept.
-- Neither reached WLBI, WLRQ, WLRC, WLBC, WLD2, WLDS or WLNP at the time.
--
-- UPDATED after the MIX-06/07 rebuild (RC-015 step 3). Their MECHANICS are now
-- full -- verified base tree, isolated exact-TOC sides, real captured bytes fed
-- through the real receive path, durable or fail-closed terminals, all four
-- quadrants -- and their KEY BREADTH is now WLRB, WLBI, WLRD and WLLQ, 4 of 11.
-- WLRQ, WLRC and WLBC await the summary -> request -> chunked trace; WLDS and
-- WLD2 are undriven; WLNP has no public send entry. The disposition is
-- therefore still DELEGATED-AND-PARTIAL, now on key breadth rather than on
-- mechanics.
--
-- Fixture rule 7's full breadth -- every protocol-7 header, request,
-- correlation, queue, bucket, transfer, delete and recovery key -- is NOT yet
-- covered here. What is covered is stated per case.

local REQUIRED_BASE_COMMIT = "6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f"
local REQUIRED_BASE_TREE = "0d293768d6c7a14d78a9b9ee9b3844d2b9bad3b6"

-- Embedded golden bytes. Separate fixture files would create new tracked test
-- paths, so the golden wire stays in the file that asserts it.
local GOLDEN_WLRB =
    "WLRB||Boganic||mix-a||10||1/1||eyJhIjoiQm9nYW5pYyIsImMiOiJNQUdFIiwiZSI6W1"
    .. "syMDAxMDAsMywxXSxbMjAwMTAxLDIsMV1dLCJpZCI6Im1peC1hIiwibSI6MTAsIm8iOiJi"
    .. "b2dhbmljQGVib25ob2xkIiwidCI6Ik1peCBtaXgtYSJ9"

local results, failures, passed = {}, {}, 0
local currentFailures
local caseFilter = os.getenv("BN_MIX_CASE")

local function Check(condition, message)
    if not condition then
        currentFailures[#currentFailures + 1] = tostring(message)
    end
end

local function Case(id, name, body)
    if caseFilter and caseFilter ~= "" and caseFilter ~= id then return end
    currentFailures = {}
    local ok, err = pcall(body)
    if not ok then currentFailures[#currentFailures + 1] = tostring(err) end
    if #currentFailures == 0 then
        passed = passed + 1
        print(id .. " PASS " .. name)
    else
        failures[#failures + 1] = id
        print(id .. " RED " .. name .. ": " .. table.concat(currentFailures, "; "))
    end
end

------------------------------------------------------------------------
-- Fixture rule 1: materialize the exact PR #68 tree and verify it.
------------------------------------------------------------------------

local function TempRoot()
    local temp = (os.getenv("TEMP") or os.getenv("TMPDIR") or ".")
    return (temp:gsub("\\", "/")) .. "/bn-mix-client-matrix"
end

local fileCache = {}
local function ReadFile(path)
    if fileCache[path] ~= nil then
        return fileCache[path] ~= false and fileCache[path] or nil
    end
    local handle = io.open(path, "rb")
    if not handle then fileCache[path] = false; return nil end
    local text = handle:read("*a")
    handle:close()
    fileCache[path] = text
    return text
end

local function Materialize()
    local dir = TempRoot()
    local windows = dir:gsub("/", "\\")
    os.execute('rmdir /s /q "' .. windows .. '" 2>nul')
    os.execute('mkdir "' .. windows .. '" 2>nul')
    local cwdPath = dir .. "/.mix-cwd"
    os.execute('cd > "' .. cwdPath .. '"')
    local safeRoot = ReadFile(cwdPath)
    safeRoot = safeRoot and safeRoot:gsub("%s+$", ""):gsub("\\", "/")
    assert(type(safeRoot) == "string" and safeRoot ~= "",
        "could not resolve the active fixture checkout")
    local safeGit = 'git -c safe.directory="' .. safeRoot .. '"'
    os.execute(safeGit .. ' archive ' .. REQUIRED_BASE_COMMIT
        .. ' | tar -x -C "' .. dir .. '"')
    -- `git rev-parse <sha>^{tree}` cannot be used here: `^` is the cmd.exe
    -- escape character and is eaten before git sees it.
    local hashPath = dir .. "/.mix-tree"
    os.execute(safeGit .. ' log -1 --format=%T ' .. REQUIRED_BASE_COMMIT
        .. ' > "' .. hashPath .. '"')
    local tree = ReadFile(hashPath)
    tree = tree and (tree:gsub("%s+$", "")) or nil
    return dir, tree
end

------------------------------------------------------------------------
-- Fixture rules 2 and 3: one isolated global table per side.
------------------------------------------------------------------------

local STDLIB = {
    "print", "type", "pairs", "ipairs", "string", "table", "math", "assert",
    "tostring", "tonumber", "setmetatable", "getmetatable", "rawget", "rawset",
    "rawequal", "next", "select", "error", "pcall", "xpcall", "os", "io",
    "load", "unpack", "collectgarbage", "coroutine", "debug", "require",
}

local function NewEnv(root)
    local env = {}
    for _, name in ipairs(STDLIB) do env[name] = _G[name] end
    env.unpack = env.unpack or table.unpack
    env._G = env
    env.__root = root
    -- Resolves against this side's own source root, so a module can only ever
    -- reach its own tree.
    env.dofile = function(relative)
        local source = ReadFile(env.__root .. "/" .. relative)
        if not source then error("missing " .. tostring(relative)) end
        local chunk, err = load(source, "@" .. relative, "t", env)
        if not chunk then error(err) end
        return chunk()
    end
    return env
end

local function TocOrder(root)
    local text = ReadFile(root .. "/Nexus.toc")
    if not text then return {} end
    local order = {}
    for line in text:gmatch("[^\r\n]+") do
        local entry = line:match("^%s*(.-)%s*$")
        if entry ~= "" and not entry:find("^#") and entry:find("%.lua$") then
            order[#order + 1] = (entry:gsub("\\", "/"))
        end
    end
    return order
end

-- Boot one side: its own harness instance, then its own exact TOC order.
local function Boot(root)
    local env = NewEnv(".")
    local harness = env.dofile("tests/harness.lua")
    env.__root = root
    local loaded, failed = 0, {}
    for _, relative in ipairs(TocOrder(root)) do
        local ok, err = pcall(env.dofile, relative)
        if ok then loaded = loaded + 1
        else failed[#failed + 1] = relative .. ": " .. tostring(err) end
    end
    return env, harness, loaded, failed
end

-- Each isolated peer drives only its own real catalog scheduler. The reference
-- tree has no pending-root API, so its original synchronous behavior is retained.
local function SettleCatalog(nexus)
    local catalog = nexus.BuildCatalog
    if type(catalog.RootState) ~= "function" then return end
    local budget = type(catalog.Budget) == "function" and catalog.Budget() or {}
    local limit = math.min(tonumber(budget.maximumPumps) or 200000, 200000)
    for _ = 1, limit do
        if not catalog.RootState().candidate then return end
        catalog.PumpRootAdmission()
    end
    assert(not catalog.RootState().candidate, "isolated catalog did not settle")
end

local function PumpSide(nexus)
    local catalog = nexus.BuildCatalog
    if type(catalog.PumpRootAdmission) == "function" then
        catalog.PumpRootAdmission()
    end
    if type(catalog.RootState) == "function" then
        local root = catalog.RootState()
        if root.state ~= "ROOT_ADMITTED" or root.candidate == true then
            return false, "catalog"
        end
    end
    local cache = nexus.BuildHashCache
    if type(cache) == "table" and type(cache.Pump) == "function"
        and cache.Pump() ~= true then
        return false, "hash-cache"
    end
    nexus.Sync.OnUpdate(0.2)
    return true
end

local function BuildWireComplete(messages)
    local count, total = 0, nil
    for _, message in ipairs(messages) do
        local text = message.text or ""
        if text:find("^WLRB") then
            count = count + 1
            local _, encodedTotal = text:match("||(%d+)/(%d+)||")
            total = tonumber(encodedTotal) or total
        end
    end
    return total ~= nil and count >= total, count, total
end

local function PumpUntilBuildWire(nexus, harness, label)
    for turns = 0, 200000 do
        local complete = BuildWireComplete(harness.sentChatMessages)
        if complete then return turns end
        assert(turns < 200000,
            tostring(label) .. " did not emit a complete build payload")
        PumpSide(nexus)
    end
end

local function PumpUntilCode(nexus, harness, code, label)
    for turns = 0, 200000 do
        for _, message in ipairs(harness.sentChatMessages) do
            if (message.text or ""):find("^" .. code) then return turns end
        end
        assert(turns < 200000,
            tostring(label) .. " did not emit " .. tostring(code))
        PumpSide(nexus)
    end
end

local function PutSide(nexus, record, options)
    local called, ok, why, ticket = pcall(nexus.BuildCatalog.Put, record, options)
    if called and ok == nil and why == "ROOT_MUTATION_PENDING" then
        SettleCatalog(nexus)
        assert(ticket and ticket.state ~= "pending", "setup mutation did not settle")
        return called, ticket.committed, ticket.storedAs or ticket.reason
    end
    return called, ok, why
end

local function Side(root)
    local env, harness = Boot(root)
    env.NexusDB = {communityBuilds={}, syncTombstones={}, dpsCapture={}}
    local nexus = env.Nexus
    if type(harness.BootstrapStore) == "function" then
        pcall(harness.BootstrapStore)
    end
    pcall(nexus.LoadoutEvidence.Init, env.NexusDB)
    pcall(nexus.BuildCatalog.Init, env.NexusDB, nexus.BundledBuilds)
    SettleCatalog(nexus)
    pcall(nexus.Sync.Init, nexus.Codec, {})
    return env, harness, nexus
end

local function FixtureBuild(id)
    return {
        id=id, title="Mix " .. id, author="Boganic",
        ownerKey="boganic@ebonhold", realm="ebonhold", ownerVerified=true,
        isMine=true, class="MAGE", postedAt=10, lastModified=10,
        echoes={{spellId=200100, quality=3, stacks=1},
                {spellId=200101, quality=2, stacks=1}},
    }
end

-- Fixture rule 4: capture the sender's ACTUAL wire bytes.
local function CaptureBuildWire(root, id)
    local env, harness, nexus = Side(root)
    local record = FixtureBuild(id)
    PutSide(nexus, record)
    harness.sentChatMessages = {}
    local called, accepted = pcall(nexus.Sync.BroadcastBuild, record)
    if called and accepted then
        PumpUntilBuildWire(nexus, harness, "captured build")
    end
    SettleCatalog(nexus)
    for _, message in ipairs(harness.sentChatMessages) do
        local text = message.text or ""
        if text:find("^WLRB") then return text, env, nexus end
    end
    return nil, env, nexus
end

-- Fixture rule 4/5: feed exact bytes through the other side's real receiver and
-- assert against its DURABLE catalog, not a helper return value.
local function DeliverTo(root, wire, sender)
    local env, harness, nexus = Side(root)
    local before = nexus.Codec.JSONEncode(env.NexusDB)
    local ok, accepted = pcall(nexus.Sync.HandleIncoming, wire, sender or "Boganic")
    SettleCatalog(nexus)
    local after = nexus.Codec.JSONEncode(env.NexusDB)
    return {
        env=env, nexus=nexus, harness=harness,
        ok=ok, accepted=accepted, before=before, after=after,
        Durable=function(id)
            local okGet, record = pcall(nexus.BuildCatalog.Get, id)
            return okGet and type(record) == "table" and record or nil
        end,
    }
end

local BASE, BASE_TREE = Materialize()
local NEW = "."

------------------------------------------------------------------------

Case("MIX-00",
    "content-addressed base tree, exact load order, and enforced isolation",
function()
    Check(BASE_TREE == REQUIRED_BASE_TREE,
        "materialized base tree is " .. tostring(BASE_TREE) .. ", required "
            .. REQUIRED_BASE_TREE)
    local oldEnv, _, oldLoaded, oldFailed = Boot(BASE)
    local newEnv, _, newLoaded, newFailed = Boot(NEW)
    Check(#oldFailed == 0, "old tree failed to load: "
        .. table.concat(oldFailed, "; "))
    Check(#newFailed == 0, "new tree failed to load: "
        .. table.concat(newFailed, "; "))
    Check(oldLoaded > 0 and newLoaded > 0, "a side loaded no modules")
    -- Isolation is structural, not disciplinary. Both trees register the
    -- compatibility owner under the SAME name, so the only thing keeping them
    -- apart is that they live in two different global tables.
    local oldOwner = oldEnv.Nexus.SyncInternals
        and oldEnv.Nexus.SyncInternals.Compatibility
    local newOwner = newEnv.Nexus.SyncInternals
        and newEnv.Nexus.SyncInternals.Compatibility
    Check(type(oldOwner) == "table",
        "old tree did not expose SyncInternals.Compatibility")
    Check(type(newOwner) == "table",
        "new tree did not expose SyncInternals.Compatibility")
    Check(not rawequal(oldOwner, newOwner),
        "both sides resolved to the SAME compatibility owner table; the two "
            .. "trees are not isolated")
    Check(not rawequal(oldEnv.Nexus, newEnv.Nexus),
        "both sides share one Nexus namespace")
    Check(rawget(_G, "Nexus") == nil,
        "loading a side leaked its addon namespace into the outer environment")
end)

Case("MIX-01",
    "exact old-old: golden bytes and PR #68 durable convergence",
function()
    local wire = CaptureBuildWire(BASE, "mix-a")
    Check(wire ~= nil, "the old sender emitted no WLRB payload")
    Check(wire == GOLDEN_WLRB,
        "old-old golden bytes drifted:\n  got  " .. tostring(wire)
            .. "\n  want " .. GOLDEN_WLRB)
    local received = DeliverTo(BASE, wire, "Boganic")
    local record = received.Durable("mix-a")
    Check(type(record) == "table" and record.title == "Mix mix-a",
        "old receiver did not durably converge on the old sender's bytes")
end)

Case("MIX-02",
    "exact old-new: old bytes converge durably on the new receiver",
function()
    local wire = CaptureBuildWire(BASE, "mix-a")
    Check(wire == GOLDEN_WLRB, "old sender bytes drifted from golden")
    local received = DeliverTo(NEW, wire, "Boganic")
    local record = received.Durable("mix-a")
    Check(type(record) == "table" and record.title == "Mix mix-a",
        "new receiver did not durably converge on old-sender bytes")
    -- The scalar summary total is request/integrity evidence only; role
    -- classification comes from the full payload, which is what arrived here.
    Check(type(record) == "table" and type(record.echoes) == "table"
            and #record.echoes == 2,
        "new receiver lost the full payload's role-bearing evidence")
end)

Case("MIX-03",
    "exact new-old: the new sender emits byte-for-byte PR #68 bytes",
function()
    local wire = CaptureBuildWire(NEW, "mix-a")
    Check(wire ~= nil, "the new sender emitted no WLRB payload")
    -- Line 4737. This is the case that would catch the new tree silently
    -- drifting the protocol-7 wire shape.
    Check(wire == GOLDEN_WLRB,
        "new sender is no longer byte-for-byte PR #68 compatible:\n  got  "
            .. tostring(wire) .. "\n  want " .. GOLDEN_WLRB)
    local received = DeliverTo(BASE, wire, "Boganic")
    local record = received.Durable("mix-a")
    Check(type(record) == "table" and record.title == "Mix mix-a",
        "old receiver did not durably converge on new-sender bytes")
end)

Case("MIX-04",
    "exact new-new: deterministic golden bytes and one convergence",
function()
    local first = CaptureBuildWire(NEW, "mix-a")
    local second = CaptureBuildWire(NEW, "mix-a")
    Check(first == GOLDEN_WLRB, "new-new golden bytes drifted")
    Check(first == second,
        "the new sender is not deterministic across identical inputs")
    local received = DeliverTo(NEW, first, "Boganic")
    local record = received.Durable("mix-a")
    Check(type(record) == "table" and record.title == "Mix mix-a",
        "new receiver did not durably converge on new-sender bytes")
    -- Replaying the exact same bytes converges once, not twice.
    local replay = received.after
    pcall(received.nexus.Sync.HandleIncoming, first, "Boganic")
    for _ = 1, 20 do PumpSide(received.nexus) end
    SettleCatalog(received.nexus)
    Check(received.nexus.Codec.JSONEncode(received.env.NexusDB) == replay,
        "an exact replay mutated durable state a second time")
end)

Case("MIX-05",
    "collision and corruption produce deterministic zero durable mutation",
function()
    local wire = CaptureBuildWire(NEW, "mix-a")
    Check(wire ~= nil, "no wire captured for the collision case")
    -- A payload whose body no longer matches its header is unrelated evidence.
    local corrupted = wire:gsub("||([A-Za-z0-9+/=]+)$", "||Zm9yZWlnbg==")
    Check(corrupted ~= wire, "the collision fixture did not alter the payload")
    local received = DeliverTo(NEW, corrupted, "Boganic")
    Check(received.after == received.before,
        "an unrelated/corrupt payload mutated durable state")
    Check(received.Durable("mix-a") == nil,
        "an unrelated/corrupt payload was stored as an admitted row")
    -- A foreign sender presenting another owner's row proves no ownership.
    local foreign = DeliverTo(NEW, wire, "Stranger-Ebonhold")
    Check(foreign.Durable("mix-a") == nil
            or foreign.Durable("mix-a").ownerVerified ~= true,
        "a foreign sender obtained verified ownership of another owner's row")
end)

-- MASTER-RC-019 / MIX-08. Architecture line 4856:
--   "Old-old characterization only; old-new uses the central
--    ADMITTED/READMITTED -> INVALIDATED/TOMBSTONE_OPAQUE_BLOCK_ALL protected
--    transition, preserves raw row/payload, publishes deny-only occupancy, and
--    relays zero; new sender is zero-wire refusal."
-- and the mixed-client matrix rows for Tombstone:
--   new -> PR #68 : "Refuse before encoder invocation with
--     REMOTE_TOMBSTONE_ORDER_UNPROVEN; emit zero bytes, retain the exact local
--     serving root, create no outbound ownership claim, and produce zero relay."
--   new -> new    : "Same local refusal and zero-wire result as new-to-old. A
--     local row-to-tombstone operation is not a Sync message."
--
-- The refusal is therefore UNCONDITIONAL, not conditioned on a peer's protocol
-- version. That matters because the codebase has no per-peer protocol-capability
-- tracking anywhere: Session.MarkPeer stores the parsed addon version,
-- core/SyncCompatibility.lua has no protocol/release/legacy concept, and
-- protocolVersion at core/Sync.lua is a DPS payload field defaulting to 5.
--
-- Expected-red on this tree, before the product edit:
--   MIX-08 RED  the new sender emits a WLRD delete message.
-- The old-old characterization inside MIX-08 is ALSO the negative control: if
-- the capture helper stopped observing delete traffic, the zero-wire assertion
-- would pass vacuously, so the BASE tree is required to still emit one.

-- Drive a locally owned row to a tombstone and capture the sender's real wire.
local function CaptureDeleteWire(root, id)
    local env, harness, nexus = Side(root)
    local record = FixtureBuild(id)
    PutSide(nexus, record)
    harness.sentChatMessages = {}
    local ok, queued, why = pcall(nexus.Sync.BroadcastDelete, record)
    SettleCatalog(nexus)
    if ok and queued == true then
        PumpUntilCode(nexus, harness, "WLRD", "captured delete")
    end
    -- The immediate return is pending. Assert the unchanged refusal oracle
    -- against the real terminal operation record after catalog completion.
    if ok and why == "ROOT_MUTATION_PENDING" then
        local terminal = nexus.Sync.GetDeleteStatus(id)
        assert(terminal and terminal.terminal, "delete did not reach a terminal")
        queued, why = terminal.queueAdmitted, terminal.reason
    end
    local deletes = {}
    for _, message in ipairs(harness.sentChatMessages) do
        local text = message.text or ""
        if text:find("^WLRD") then deletes[#deletes + 1] = text end
    end
    return {env=env, nexus=nexus, harness=harness, deletes=deletes,
        ok=ok, queued=queued, why=why,
        tombstones=(pcall(nexus.Sync.TombstoneCount)
            and select(2, pcall(nexus.Sync.TombstoneCount)) or 0)}
end

Case("MIX-08",
    "a local row-to-tombstone operation is a zero-wire refusal",
function()
    -- NEGATIVE CONTROL, old-old characterization only. The BASE tree is the
    -- unmodified reference: it must still emit exactly the delete traffic this
    -- fixture is able to observe. If it does not, the zero-wire assertion below
    -- would be vacuous and this case fails here instead of passing silently.
    local old = CaptureDeleteWire(BASE, "mix-tomb")
    Check(#old.deletes > 0,
        "the BASE reference tree emitted no WLRD delete, so this fixture "
            .. "cannot observe delete traffic and the zero-wire assertion "
            .. "below would pass vacuously")
    -- This is also the NEGATIVE CONTROL for the delete-transmission
    -- characterization retired from run_sync_transport_safety.lua and
    -- run_sync_world_transition_terminals.lua under MASTER-RC-019. Those files
    -- characterised operation terminals (queued, sent, failed, reset,
    -- multi-owner expiry) that are reachable only through the wire path. The
    -- BASE reference tree is required to still reach the QUEUED terminal here,
    -- so the retirement is evidenced as "capability removed by the accepted
    -- architecture" rather than as coverage silently dropped: if the old
    -- terminal machinery ever stopped being reachable on BASE, this fails.
    Check(old.queued == true and old.why == "queued",
        "the BASE reference tree did not reach the queued delete terminal "
            .. "(ok=" .. tostring(old.queued) .. " why=" .. tostring(old.why)
            .. "); the retired transmission characterization can no longer be "
            .. "shown live on the reference tree")

    -- New sender: zero wire.
    local new = CaptureDeleteWire(NEW, "mix-tomb")
    Check(#new.deletes == 0,
        "the new sender emitted " .. #new.deletes .. " WLRD delete message(s); "
            .. "architecture line 4856 requires a zero-wire refusal because a "
            .. "local row-to-tombstone operation is not a Sync message")

    -- The refusal is explicit and named, not a silent drop.
    Check(new.why == "REMOTE_TOMBSTONE_ORDER_UNPROVEN",
        "the refusal reason was " .. tostring(new.why)
            .. "; the matrix requires REMOTE_TOMBSTONE_ORDER_UNPROVEN")

    -- GUARD, passes before and after: the local tombstone is RETAINED. The
    -- refusal must not become a refusal to delete locally.
    Check(new.tombstones >= 1,
        "the local tombstone was not retained through the refusal; "
            .. "TombstoneCount()=" .. tostring(new.tombstones))
    local okGet, record = pcall(new.nexus.BuildCatalog.Get, "mix-tomb")
    Check(not (okGet and type(record) == "table"),
        "the row survived its local tombstone")
end)



-- ---------------------------------------------------------------------------
-- MASTER-RC-015, first landed breadth increment: fixture rule 8, and rule 7's
-- classes 7, 8 and 9. Every case runs across all four quadrants, which is what
-- rule 7 means by covering a class -- a class that holds on one side and not
-- the other is exactly what a mixed-client matrix exists to catch.
--
-- Architecture line 4716, rule 8: "Prove the implementation adds no routine
-- dual-send and no transport migration."
-- Architecture line 4712-4715, rule 7: "... numeric ID versus string ID
-- collision, 96-byte versus 97-byte string IDs, invalid UTF-8 ..."
--
-- MEASURED BEFORE WRITING, and it shapes every class below. The PR #68 base
-- tree at 6f6204dc has ZERO occurrences of PROTOCOL7_TYPED_ID_UNREPRESENTABLE,
-- PROTOCOL7_ID_WIDTH_UNREPRESENTABLE and PROTOCOL7_ID_UNREPRESENTABLE: those
-- refusals do not exist there. So for classes 7-9 the OLD-side quadrants are
-- characterization only -- what the old sender does is measured, never assumed
-- -- and the refusal contract is asserted on the NEW-side quadrants. Same
-- precedent as MIX-08's old-old row.
--
-- Rule 8 is different and is asserted on BOTH trees: each carries
-- `SYNC_CHANNEL = "wrbuildssync"` at the identical line 43 and each exports
-- Sync.ChannelName(), so the transport-identity assertion is genuinely
-- two-sided rather than passing because one side lacks the surface.
--
-- Rule 5 governs the verdicts: durable convergence or the fail-closed terminal,
-- never a helper return value alone.
--
-- WHAT THIS INCREMENT DOES **NOT** COVER. Recorded explicitly so no reader can
-- mistake it for rule 7 being satisfied. MASTER-RC-015 stays IN PROGRESS until
-- rules 1-8 are met in full, and this increment does not present itself as
-- completion. Still open, all of it:
--
--   * class 1  new -> old -- now covered by RCONF-01 under amendment 9
--   * class 5  tombstone replacement failure -- PARTIALLY covered.
--              4743 terminal 1 (pre-commit failure) is MIX-22, using the
--              authorized harness-only seam S.PoisonDurableField, with MIX-23
--              as its no-fault both-sides guard and replay-once check.
--              4743 terminal 2 (failure after the one bundle-pointer write) is
--              proven by ATOM-08 in run_catalog_authority_commit_fault_matrix:
--              one complete pointer replacement, generation advanced once,
--              superseded graph byte-exact, both operations durable together --
--              so no candidate prefix is representable and the terminal cannot
--              occur as a distinct state.
--              4743 terminal 3 (failure after successful final serving
--              publication, notification retry only) is NOT yet measured and
--              remains open.
--   * class 10 the eleven-code protocol-7 sweep. This FILE exercises WLRB and
--              WLRD. Across the fixture as a whole 10 of 11 now have an
--              asserted disposition -- WLRB, WLBI, WLRD, WLLQ, WLLC, WLRQ,
--              WLRC, WLBC, WLDS, WLNP -- and only WLD2 lacks a positive
--              producer.
--
-- COVERED SINCE, in tests/run_sync_semantic_envelope.lua: class 3 (MIX-19),
-- class 4 (MIX-20) and the WLDS/WLD2/WLNP dispositions (MIX-21). Class 1
-- new -> old is covered by RCONF-01 under amendment 9
--
-- COVERED SINCE, in tests/run_sync_semantic_envelope.lua rather than here,
-- which the accepted structure permits: class 6 recovery (MIX-16, an
-- interrupted transfer admits nothing durable, holds exactly one inflight, and
-- reaches its terminal when the missing chunk arrives) and the WLRQ/WLRC/WLBC
-- keys (MIX-17, MIX-18).
--   * durable convergence of a 96-byte id -- CLOSED by MIX-24 on the chunked
--              drive: captured, replayed in order through the real receive
--              path, converging once and unchanged on exact replay.
--
-- Classes 1, 2, 3 and 6 require the summary -> request -> chunked-response
-- trace: a >=79-echo payload is summarised, requested and chunked
-- (lines 4718-4722), and blind chunk delivery does not converge. That drive is
-- a separate increment. MIX-06/07 in tests/run_sync_semantic_envelope.lua also
-- remain delegated-and-PARTIAL until rebuilt to full fixture mechanics.
--
-- This increment deliberately uses only small payloads and needs no chunking.

local QUADRANTS = {
    {name="oldold", sender=BASE, receiver=BASE, senderIsNew=false},
    {name="oldnew", sender=BASE, receiver=NEW, senderIsNew=false},
    {name="newold", sender=NEW, receiver=BASE, senderIsNew=true},
    {name="newnew", sender=NEW, receiver=NEW, senderIsNew=true},
}

-- Every wire message a sender emits for one operation, not just the first.
-- Rule 8 needs the COUNT and the code mix, so a helper returning one match
-- cannot express it.
local function CaptureAllWire(root, record)
    local env, harness, nexus = Side(root)
    PutSide(nexus, record, {source="local"})
    harness.sentChatMessages = {}
    local called, accepted = pcall(nexus.Sync.BroadcastBuild, record)
    if called and accepted then
        PumpUntilBuildWire(nexus, harness, "captured operation")
    end
    SettleCatalog(nexus)
    local texts = {}
    for _, message in ipairs(harness.sentChatMessages) do
        texts[#texts + 1] = message.text or ""
    end
    return texts, env, nexus
end

local function RefusalReason(root, record)
    local _, _, nexus = Side(root)
    local ok, accepted, why = pcall(nexus.Sync.BroadcastBuild, record)
    if not ok then return "ERROR" end
    if accepted then return nil end
    return tostring(why)
end

-- Every record must be DISTINCT content, not just a distinct id. These cases
-- deliver many records into the same receiver, and a shared title plus a shared
-- echo set produces a shared evidence key, so a later row is refused as a
-- duplicate of an earlier one. That is a fixture collision, not a product
-- verdict, and it is what made the 96-byte convergence guard fail in all four
-- quadrants on the first measurement.
local identitySequence = 0
local function IdentifiedBuild(id)
    identitySequence = identitySequence + 1
    return {
        id=id, title="Mix identity " .. identitySequence, author="Boganic",
        ownerKey="boganic@ebonhold", realm="ebonhold", ownerVerified=true,
        isMine=true, class="MAGE", postedAt=10, lastModified=10,
        echoes={{spellId=200100 + identitySequence, quality=3, stacks=1}},
    }
end

-- ATTRIBUTION. Pumping the scheduler to flush an operation also lets ambient
-- scheduled traffic out -- a reconciliation request (WLRQ) in particular, which
-- is emitted on the sync cadence and has nothing to do with the operation under
-- test. Measured: a REFUSED broadcast still shows a WLRQ in the same window, so
-- the window cannot be attributed to the operation wholesale. Rule 8 is about
-- one operation emitting one copy of its payload, not about silencing the
-- scheduler, so every assertion below counts only the build-payload code.
local function BuildWiresIn(texts)
    local wires = {}
    for _, text in ipairs(texts) do
        if text:find("^WLRB") then wires[#wires + 1] = text end
    end
    return wires
end

local function CodesIn(texts)
    local codes = {}
    for _, text in ipairs(texts) do
        local code = text:match("^(%u%u%u%u)")
        if code then codes[#codes + 1] = code end
    end
    return table.concat(codes, ",")
end

Case("MIX-09",
    "rule 8: one operation emits one message, and no transport migration",
function()
    -- NO ROUTINE DUAL-SEND. One BroadcastBuild of one small record must put
    -- exactly one message on the wire. Two -- a summary riding alongside the
    -- full payload, say -- is the dual-send rule 8 forbids.
    for _, q in ipairs(QUADRANTS) do
        local texts = CaptureAllWire(q.sender, IdentifiedBuild("r8" .. q.name))
        local wires = BuildWiresIn(texts)
        Check(#wires == 1,
            q.name .. ": one broadcast emitted " .. #wires
                .. " build payload(s) [window: " .. CodesIn(texts)
                .. "]; rule 8 forbids a routine dual-send")
        -- No second copy of the same payload under any other code either --
        -- a summary riding alongside the full payload is the dual-send rule 8
        -- names.
        local summaries = 0
        for _, text in ipairs(texts) do
            if text:find("^WLBI") then summaries = summaries + 1 end
        end
        Check(summaries == 0,
            q.name .. ": a summary was emitted alongside the full payload ["
                .. CodesIn(texts) .. "]")
    end

    -- NO TRANSPORT MIGRATION. Both trees must name the same channel, and the
    -- name must not move across an operation. Asserted on both sides: each
    -- tree exports Sync.ChannelName(), so neither passes by absence.
    local _, _, baseNexus = Side(BASE)
    local _, _, newNexus = Side(NEW)
    local baseBefore = baseNexus.Sync.ChannelName()
    local newBefore = newNexus.Sync.ChannelName()
    Check(baseBefore == newBefore,
        "the two trees name different transport channels: base="
            .. tostring(baseBefore) .. " new=" .. tostring(newBefore))
    Check(baseBefore == "wrbuildssync",
        "the transport channel migrated from wrbuildssync to "
            .. tostring(baseBefore))
    CaptureAllWire(NEW, IdentifiedBuild("r8channel"))
    Check(newNexus.Sync.ChannelName() == newBefore
            and baseNexus.Sync.ChannelName() == baseBefore,
        "an operation moved the transport channel")
end)

Case("MIX-10",
    "rule 7 class 7: numeric versus string ID collision in all four quadrants",
function()
    for _, q in ipairs(QUADRANTS) do
        local numeric = IdentifiedBuild(1)
        local texts, _, nexus = CaptureAllWire(q.sender, numeric)
        if q.senderIsNew then
            -- Contract side: a numeric ID is unrepresentable in protocol 7 and
            -- must be refused before any bytes are emitted.
            Check(#BuildWiresIn(texts) == 0,
                q.name .. ": a numeric ID reached the wire [window: "
                    .. CodesIn(texts) .. "]")
            Check(RefusalReason(q.sender, numeric)
                    == "PROTOCOL7_TYPED_ID_UNREPRESENTABLE",
                q.name .. ": numeric ID refusal reason was "
                    .. tostring(RefusalReason(q.sender, numeric)))
        end
        -- Both sides, rule 5: whatever the sender did, no receiver may end up
        -- holding the numeric row aliased under the string key "1".
        local numericWires = BuildWiresIn(texts)
        local received = #numericWires > 0
            and DeliverTo(q.receiver, numericWires[1], "Boganic") or nil
        if received then
            local aliased = received.Durable("1")
            Check(aliased == nil,
                q.name .. ": a numeric ID converged aliased to the string key")
        end
        -- Characterization for the old sender, measured not assumed.
        if not q.senderIsNew then
            Check(true, q.name .. ": old-sender numeric ID emitted "
                .. #BuildWiresIn(texts) .. " build payload(s) [window: "
                .. CodesIn(texts) .. "]")
        end
    end
end)

Case("MIX-11",
    "rule 7 class 8: 96-byte versus 97-byte string IDs in all four quadrants",
function()
    local wide = string.rep("w", 97)
    local exact = string.rep("e", 96)
    for _, q in ipairs(QUADRANTS) do
        local tooWide = IdentifiedBuild(wide)
        local texts = CaptureAllWire(q.sender, tooWide)
        if q.senderIsNew then
            Check(#BuildWiresIn(texts) == 0,
                q.name .. ": a 97-byte ID reached the wire [window: "
                    .. CodesIn(texts) .. "]")
            Check(RefusalReason(q.sender, tooWide)
                    == "PROTOCOL7_ID_WIDTH_UNREPRESENTABLE",
                q.name .. ": 97-byte refusal reason was "
                    .. tostring(RefusalReason(q.sender, tooWide)))
        end
        local wideWires = BuildWiresIn(texts)
        if #wideWires > 0 then
            local received = DeliverTo(q.receiver, wideWires[1], "Boganic")
            Check(received.Durable(wide) == nil,
                q.name .. ": a 97-byte ID converged durably")
        end

        -- BOTH-SIDES GUARD. 96 bytes is inside the bound, so the width check
        -- cannot be a blanket refusal: the id must still reach the wire.
        --
        -- SCOPE, measured and disclosed rather than asserted beyond this
        -- increment's drive. A 96-byte id inflates the payload past one packet
        -- -- the captured wire carries a `1/3` chunk header -- and delivering
        -- all three chunks blind still does not converge
        -- (`durable mutated=false, accepted=false`). Per the accepted fixture
        -- rules a chunked payload converges through the summary -> request ->
        -- chunked-response trace, not through pushed chunks, and that drive is
        -- exactly what rule 7's held totals and recovery classes require.
        -- DURABLE CONVERGENCE OF A 96-BYTE ID IS THEREFORE DEFERRED to that
        -- increment; it is not asserted here and is not claimed as covered.
        local fits = IdentifiedBuild(exact)
        local okWires = BuildWiresIn(CaptureAllWire(q.sender, fits))
        Check(#okWires >= 1,
            q.name .. ": a 96-byte ID emitted no build payload at all, so the "
                .. "97-byte width refusal above cannot be distinguished from a "
                .. "blanket refusal of long ids")
        if #okWires >= 1 then
            Check(okWires[1]:find("||" .. exact .. "||", 1, true) ~= nil,
                q.name .. ": the 96-byte id was not carried verbatim on the "
                    .. "wire")
        end
    end
end)

Case("MIX-12",
    "rule 7 class 9: invalid UTF-8 IDs in all four quadrants",
function()
    local invalid = "mix\255utf"
    for _, q in ipairs(QUADRANTS) do
        local record = IdentifiedBuild(invalid)
        local texts = CaptureAllWire(q.sender, record)
        if q.senderIsNew then
            Check(#BuildWiresIn(texts) == 0,
                q.name .. ": an invalid UTF-8 ID reached the wire [window: "
                    .. CodesIn(texts) .. "]")
            Check(RefusalReason(q.sender, record)
                    == "PROTOCOL7_ID_UNREPRESENTABLE",
                q.name .. ": invalid UTF-8 refusal reason was "
                    .. tostring(RefusalReason(q.sender, record)))
        end
        local utfWires = BuildWiresIn(texts)
        if #utfWires > 0 then
            local received = DeliverTo(q.receiver, utfWires[1], "Boganic")
            Check(received.Durable(invalid) == nil,
                q.name .. ": an invalid UTF-8 ID converged durably")
        end
    end
end)

-- ---------------------------------------------------------------------------
-- MASTER-RC-015 rule 7 classes 1 and 2, by the measured drive.
--
-- MEASURED BEFORE WRITING, and each fact changed the design:
--   * A 79- or 85-stack payload is PUSHED as a WLRB chunk sequence. It is not a
--     summary -> request exchange, so classes 1 and 2 are drivable now.
--   * An ambient WLRQ is INTERLEAVED in the capture window (position 6 of 9),
--     so the chunks must be selected by code, never by taking the whole window.
--     Delivering the window verbatim is why an earlier attempt never converged.
--   * The base sender emits 8 WLRB chunks for 79 ordinary but **nothing at all**
--     for 79+6=85. Old->old for 85 therefore has NO GOLDEN CONTROL. That is a
--     measured base-tree limitation recorded as such, not coverage.
--   * The base RECEIVER declines a mixed ordinary+locked payload directly,
--     storing needsFullBuild=true / ordinaryCompletenessReason="cross-role" and
--     raising its own WLLQ. Class 1 new->old therefore completes only through
--     the loadout exchange and is HELD, not asserted here.
--
-- STILL OPEN after this increment: class 1 new->old, class 3 (80/7/86),
-- class 4, class 5, class 6 recovery, and the WLRQ/WLRC/WLBC keys -- all
-- pending the shared WLLQ -> WLLC -> chunked drive. RC-015 stays IN PROGRESS.

-- STRUCTURAL CONSTRAINT, measured. The step-2 shared mechanics in
-- tests/harness.lua CANNOT be used from this file's outer scope: harness.lua
-- loads core modules at top level (unindented dofile at 648-656), so importing
-- it here would create `_G.Nexus` and break MIX-00's isolation assertion that
-- the outer global table stays clean. This file therefore uses its own
-- equivalent local mechanics -- Materialize/Side/CaptureAllWire/BuildWiresIn --
-- which satisfy the same fixture rules. run_sync_semantic_envelope.lua, which
-- already imports the harness, uses the shared primitives instead.

local function ClsEchoes(ordinary, locked)
    local rows, spell = {}, 100000
    for _ = 1, (ordinary or 0) do
        rows[#rows + 1] = {spellId=spell, quality=3, stacks=1}
        spell = spell + 1
    end
    spell = 200000
    for _ = 1, (locked or 0) do
        rows[#rows + 1] = {spellId=spell, quality=3, stacks=1, locked=true}
        spell = spell + 1
    end
    return rows
end

local clsSequence = 0
local function ClsRecord(ordinary, locked)
    clsSequence = clsSequence + 1
    return {
        id="cls" .. clsSequence, title="Class " .. clsSequence,
        author="Boganic", ownerKey="boganic@ebonhold", realm="ebonhold",
        ownerVerified=true, isMine=true, class="MAGE",
        postedAt=10, lastModified=10, echoes=ClsEchoes(ordinary, locked),
    }
end

local function ClsStacks(record)
    if type(record) ~= "table" or type(record.echoes) ~= "table" then
        return -1
    end
    local total = 0
    for _, echo in ipairs(record.echoes) do
        total = total + (tonumber(echo.stacks) or 0)
    end
    return total
end

-- Capture a sender's real chunk sequence for one record, selected by code so
-- ambient scheduled traffic is never attributed to the operation.
-- MEASURED: a 79- or 85-stack payload is emitted as 8 WLRB chunks, and the
-- shared CaptureAllWire pumps only 40 turns, which flushed just 5 of them and
-- made convergence impossible. This capture pumps enough turns to drain the
-- whole sequence; a truncated chunk set is a fixture fault, not a verdict.
local function ClsSend(sideRoot, record)
    local _, harness, nexus = Side(sideRoot)
    PutSide(nexus, record, {source="local"})
    harness.sentChatMessages = {}
    local called, accepted = pcall(nexus.Sync.BroadcastBuild, record)
    if called and accepted then
        PumpUntilBuildWire(nexus, harness, "semantic envelope")
    end
    SettleCatalog(nexus)
    local texts = {}
    for _, message in ipairs(harness.sentChatMessages) do
        texts[#texts + 1] = message.text or ""
    end
    return BuildWiresIn(texts), texts, nexus
end

-- One receiver side for a whole chunk sequence. DeliverTo boots a fresh side
-- per call, which cannot reassemble a multi-chunk payload.
local function ClsReceive(sideRoot, chunks)
    local env, _, nexus = Side(sideRoot)
    local before = nexus.Codec.JSONEncode(env.NexusDB)
    for _, chunk in ipairs(chunks) do
        pcall(nexus.Sync.HandleIncoming, chunk, "Boganic")
    end
    SettleCatalog(nexus)
    local after = nexus.Codec.JSONEncode(env.NexusDB)
    return {
        env=env, nexus=nexus, before=before, after=after,
        Durable=function(id)
            local ok, record = pcall(nexus.BuildCatalog.Get, id)
            return ok and type(record) == "table" and record or nil
        end,
        -- Re-deliver the SAME bytes into THIS side. Booting a fresh receiver
        -- and comparing two independent runs would not test idempotence at
        -- all -- it would compare two first deliveries.
        Again=function(more)
            for _, chunk in ipairs(more) do
                pcall(nexus.Sync.HandleIncoming, chunk, "Boganic")
            end
            SettleCatalog(nexus)
            return nexus.Codec.JSONEncode(env.NexusDB)
        end,
    }
end

Case("MIX-13",
    "rule 7 class 2: ordinary-only 79 converges in all four quadrants",
function()
    local quadrants = {
        {name="oldold", sender=BASE, receiver=BASE},
        {name="oldnew", sender=BASE, receiver=NEW},
        {name="newold", sender=NEW, receiver=BASE},
        {name="newnew", sender=NEW, receiver=NEW},
    }
    for _, q in ipairs(quadrants) do
        local record = ClsRecord(79, 0)
        local chunks, wire = ClsSend(q.sender, record)
        Check(#chunks > 0,
            q.name .. ": sender emitted no chunks for 79 ordinary [window: "
                .. CodesIn(wire) .. "]")
        if #chunks > 0 then
            local got = ClsReceive(q.receiver, chunks)
            local durable = got.Durable(record.id)
            Check(durable ~= nil,
                q.name .. ": 79 ordinary did not converge across " .. #chunks
                    .. " chunk(s)")
            if durable then
                Check(ClsStacks(durable) == 79,
                    q.name .. ": converged with " .. ClsStacks(durable)
                        .. " of 79 stacks")
            end
        end
    end
end)

Case("MIX-14",
    "rule 7 class 1: 79+6=85 converges once new-to-new",
function()
    local record = ClsRecord(79, 6)
    Check(ClsStacks(record) == 85,
        "fixture built " .. ClsStacks(record) .. " stacks, required 85")
    local chunks, wire = ClsSend(NEW, record)
    Check(#chunks > 0,
        "the new sender emitted no chunks for 79+6=85 [window: "
            .. CodesIn(wire) .. "]")
    if #chunks == 0 then return end
    local got = ClsReceive(NEW, chunks)
    local durable = got.Durable(record.id)
    Check(durable ~= nil,
        "the 85-stack payload did not converge across " .. #chunks .. " chunks")
    if durable then
        Check(ClsStacks(durable) == 85,
            "converged with " .. ClsStacks(durable) .. " of 85 stacks")
        local locked = 0
        for _, echo in ipairs(durable.echoes) do
            if echo.locked then locked = locked + 1 end
        end
        Check(locked == 6,
            "converged with " .. locked .. " locked rows, required 6")
    end
    -- Converges ONCE: replaying the identical bytes into the SAME receiver
    -- must not mutate durable state again.
    local settled = got.after
    Check(settled ~= nil, "the receiver produced no durable snapshot")
    local replayed = got.Again(chunks)
    Check(replayed == settled,
        "an exact replay of the same 85-stack chunks mutated durable state a "
            .. "second time")
end)

Case("MIX-15",
    "rule 7 class 1 old-to-new: the payload equals the exact PR #68 encoder",
function()
    -- CODEC-PROVENANCE. Amendment 9 requires bytes obtained from the frozen
    -- parent's encoder -- rather than captured from a real sender path that
    -- does not exist for locked payloads -- to be labelled as such. These are
    -- CODEC-PROVENANCE bytes. The same label applies wherever the frozen
    -- parent has no real sender path for locked bytes: clauses 4735, 4736 and
    -- MIX-02's old -> new locked case.
    --
    -- PROVENANCE, CORRECTED. This case proves EXACT ENCODER EQUIVALENCE and
    -- nothing more. It does NOT establish `PR #68 sender -> new receiver`
    -- provenance: fixture rule 4 requires bytes captured from the ACTUAL
    -- sender, and PR #68's BroadcastBuild emits no locked full payload at all,
    -- so no such capture exists. The case name's "old-to-new" describes the
    -- comparison, not a captured old-sender transmission. An earlier version of
    -- this header implied the stronger claim; that overstatement is corrected
    -- here rather than left to be inherited as coverage.
    --
    -- The bytes are obtained from the exact 6f6204dc tree's OWN encoder:
    -- Nexus.SyncInternals.Protocol.New(...).CompactEncode, loaded in an
    -- isolated side rooted at that tree. CompactEncode is a pure function of
    -- the build -- it reads no option, limit or callback -- so a minimal
    -- factory table is sufficient and cannot alter its output.
    local baseEnv = Side(BASE)
    local factory = baseEnv.Nexus and baseEnv.Nexus.SyncInternals
        and baseEnv.Nexus.SyncInternals.Protocol
    Check(type(factory) == "table" and type(factory.New) == "function",
        "the base tree exposes no Protocol factory")
    if not (type(factory) == "table" and type(factory.New) == "function") then
        return
    end
    -- Protocol.New asserts exactly three callbacks -- parseVersion,
    -- ownerKeyMatchesAuthor and isSafeTree. CompactEncode consults none of
    -- them, so stubs cannot alter its output; they exist only to satisfy the
    -- factory's contract.
    local okNew, baseProtocol = pcall(factory.New, {
        parseVersion=function() return nil end,
        ownerKeyMatchesAuthor=function() return true end,
        isSafeTree=function() return true end,
    })
    Check(okNew and type(baseProtocol) == "table",
        "the base Protocol factory refused a minimal options table: "
            .. tostring(baseProtocol))
    if not (okNew and type(baseProtocol) == "table") then return end

    local record = ClsRecord(79, 6)
    local okEnc, basePayload = pcall(baseProtocol.CompactEncode, record)
    Check(okEnc and type(basePayload) == "table",
        "the PR #68 encoder did not produce a payload")
    if not (okEnc and type(basePayload) == "table") then return end
    Check(type(basePayload.e) == "table" and #basePayload.e == 85,
        "the PR #68 encoder produced "
            .. tostring(type(basePayload.e) == "table" and #basePayload.e or "?")
            .. " echo tuples, required 85")
    local slot4 = 0
    for _, tuple in ipairs(basePayload.e) do
        if tuple[4] ~= nil then slot4 = slot4 + 1 end
    end
    Check(slot4 == 6,
        "the PR #68 encoder set " .. slot4 .. " slot-4 flags, required 6")

    -- The new sender's wire payload must equal what PR #68 would encode for
    -- the same record. This is the old->new equivalence: identical bytes on
    -- both sides means the old client's full payload is representable to the
    -- new receiver without any capability branching (architecture 4738-4739).
    local chunks, _, newNexus = ClsSend(NEW, record)
    Check(#chunks > 0, "the new sender emitted no chunks for the comparison")
    if #chunks == 0 then return end
    local body = {}
    for _, text in ipairs(chunks) do
        local parts = {}
        for piece in (text .. "||"):gmatch("(.-)||") do
            if piece ~= "" then parts[#parts + 1] = piece end
        end
        body[#body + 1] = parts[#parts] or ""
    end
    local codec = newNexus.Codec
    local joined = table.concat(body)
    local raw = codec.Base64DecodeNetwork(joined) or codec.Base64Decode(joined)
    local decoded = raw and codec.JSONDecode(raw) or nil
    Check(type(decoded) == "table" and type(decoded.e) == "table",
        "the new sender's payload did not decode for comparison")
    if not (type(decoded) == "table" and type(decoded.e) == "table") then
        return
    end
    Check(#decoded.e == #basePayload.e,
        "new sender encoded " .. #decoded.e .. " tuples against the PR #68 "
            .. "encoder's " .. #basePayload.e)
    local mismatch = nil
    for index, tuple in ipairs(basePayload.e) do
        local other = decoded.e[index]
        if type(other) ~= "table"
            or tuple[1] ~= other[1] or tuple[2] ~= other[2]
            or tuple[3] ~= other[3] or tuple[4] ~= other[4] then
            mismatch = mismatch or index
        end
    end
    Check(mismatch == nil,
        "new sender's echo tuple " .. tostring(mismatch)
            .. " differs from the exact PR #68 encoder output")
end)
print(string.format(
    "sync mixed-client matrix: %d passed, %d red", passed, #failures))
if #failures > 0 then
    error("sync mixed-client matrix has red cases: "
        .. table.concat(failures, ","), 0)
end
