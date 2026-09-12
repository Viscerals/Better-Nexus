-- Package B / issue #22 catalog authority: admission, budgets, provenance,
-- future schema, unknown fields, and API state matrix (ADM, BUD, PROV, FUT,
-- UNK, API, IDX). Every case names its architecture ID.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

-- Fixture assertions inspect terminal catalog transactions. This uses the real
-- admission scheduler and never turns a pending acknowledgement into success.
local function AwaitMutation(ok, why, ticket)
    if ok == nil and why == "ROOT_MUTATION_PENDING" then
        assert(type(ticket) == "table", "pending mutation returned no ticket")
        local catalog = Nexus.BuildCatalog
        for _ = 1, catalog.Budget().maximumPumps do
            if ticket.state ~= "pending" then break end
            catalog.PumpRootAdmission()
        end
        assert(ticket.state ~= "pending", "fixture mutation did not settle")
        return ticket.committed, ticket.storedAs or ticket.reason, ticket
    end
    return ok, why, ticket
end


local now = 2000000000
time = function() return now end

local function Catalog() return Nexus.BuildCatalog end

-- Semantic envelope ---------------------------------------------------------

Case("ADM-01", "79 ordinary copies admit", function()
    local db = S.Database({adm01=S.Build("adm01", 79, 0)})
    local summary = S.Bind(db)
    local state = S.State("adm01")
    Check(state.state == "ADMITTED", "79 ordinary row not admitted: "
        .. tostring(state.state) .. "/" .. tostring(state.reason))
    Check(Catalog().Count() == 1 and summary.merged == 1,
        "79 ordinary row not counted exactly once")
    local record = Catalog().Get("adm01")
    Check(record and record.echoCount == 79, "79 ordinary copies not represented")
    Check(state.semantic and state.semantic.ordinary == 79
        and state.semantic.locked == 0 and state.semantic.total == 79,
        "semantic counts were not exposed")
end)

Case("ADM-02", "79 ordinary plus 6 explicit locked admit", function()
    local db = S.Database({adm02=S.Build("adm02", 79, 6)})
    S.Bind(db)
    local state = S.State("adm02")
    Check(state.state == "ADMITTED", "79/6 row not admitted: "
        .. tostring(state.reason))
    Check(state.semantic.ordinary == 79 and state.semantic.locked == 6
        and state.semantic.total == 85, "79/6/85 counts wrong")
end)

Case("ADM-03", "80 ordinary rejects before durable or public state", function()
    local raw = S.Build("adm03", 80, 0)
    local db = S.Database({adm03=raw})
    local bytes = S.Encode(raw)
    S.Bind(db)
    local state = S.State("adm03")
    Check(state.state == "INVALIDATED" and state.reason == "SEMANTIC_ENVELOPE",
        "80 ordinary gained a state other than INVALIDATED/SEMANTIC_ENVELOPE: "
        .. tostring(state.state) .. "/" .. tostring(state.reason))
    Check(Catalog().Get("adm03") == nil and Catalog().Count() == 0
        and Catalog().Status().availableCount == 0,
        "80 ordinary reached a public surface")
    Check(Catalog().FindExactFingerprintId(state.fingerprint or "") == nil,
        "exact index served an invalid row")
    Check(S.Durable(db).adm03 == raw and S.Encode(raw) == bytes,
        "raw row was mutated or removed")
    Check(state.occupancy == "BLOCKED", "invalid typed ID was not deny-only")
end)

Case("ADM-04", "7 locked rejects", function()
    local db = S.Database({adm04=S.Build("adm04", 10, 7)})
    S.Bind(db)
    local state = S.State("adm04")
    Check(state.state == "INVALIDATED" and state.reason == "SEMANTIC_ENVELOPE",
        "7 locked was not rejected")
end)

Case("ADM-05", "86 total rejects", function()
    local db = S.Database({adm05=S.Build("adm05", 79, 7)})
    S.Bind(db)
    Check(S.State("adm05").state == "INVALIDATED", "86 total was not rejected")
    local stacked = S.Build("adm05b", 1, 0)
    stacked.echoes[1].stacks = 86
    S.Bind(S.Database({adm05b=stacked}))
    Check(S.State("adm05b").state == "INVALIDATED",
        "one oversized stack crossed the envelope")
end)

Case("ADM-06", "sparse array rejects without #table authority", function()
    local sparse = S.Build("adm06", 3, 0)
    sparse.echoes[7] = {spellId=999, quality=3, stacks=1}
    S.Bind(S.Database({adm06=sparse}))
    local state = S.State("adm06")
    Check(state.state == "INVALIDATED" and state.reason == "DENSE_ARRAY",
        "sparse array was admitted: " .. tostring(state.reason))
end)

Case("ADM-07", "fractional, nonfinite, nonpositive values reject", function()
    for label, stacks in pairs({fractional=1.5, nan=0/0, inf=math.huge,
            zero=0, negative=-1}) do
        local row = S.Build("adm07-" .. label, 2, 0)
        row.echoes[1].stacks = stacks
        local bytes = S.Encode({echoes=row.echoes})
        S.Bind(S.Database({[row.id]=row}))
        Check(S.State(row.id).state == "INVALIDATED",
            "unsafe stack value admitted: " .. label)
        Check(S.Encode({echoes=row.echoes}) == bytes,
            "unsafe value was rewritten: " .. label)
    end
end)

-- Bounded traversal ---------------------------------------------------------

Case("ADM-08", "attacker-sized row stops at exact slice counters", function()
    local hostile = S.Build("adm08", 5, 0)
    local nested = {}
    local cursor = nested
    for depth = 1, 12 do cursor.child = {depth=depth}; cursor = cursor.child end
    hostile.futureNested = nested
    hostile.futureBlob = string.rep("x", 5000)
    local wide = {}
    for index = 1, 3000 do wide["k" .. index] = index end
    hostile.futureWide = wide
    local bytes = S.Encode(hostile)
    S.Bind(S.Database({adm08=hostile}))
    Check(S.State("adm08").state == "INVALIDATED", "hostile row was admitted")
    Check(S.Encode(hostile) == bytes, "hostile row was truncated or copied back")
    local counters = S.Counters()
    Check(counters.maxPerPump.edges <= 64 and counters.maxPerPump.nodes <= 64
        and counters.maxPerPump.bytesInspected <= 2048 + 5200
        and counters.maxPerPump.unknownBytes <= 512
        and counters.maxPerPump.tableIdentities <= 8,
        string.format("slice exceeded: edges=%s nodes=%s bytes=%s unknown=%s tables=%s",
            tostring(counters.maxPerPump.edges), tostring(counters.maxPerPump.nodes),
            tostring(counters.maxPerPump.bytesInspected),
            tostring(counters.maxPerPump.unknownBytes),
            tostring(counters.maxPerPump.tableIdentities)))
    Check(counters.totals.unknownBytes <= 4096 + 5120,
        "unmetered unknown clone: " .. tostring(counters.totals.unknownBytes))
end)

Case("ADM-09", "1,001-record catalog exposes no partial authority", function()
    local overlay = {}
    for index = 1, 1001 do
        local id = string.format("adm09-%04d", index)
        overlay[id] = S.Build(id, 3, 0, {postedAt=index, lastModified=index})
    end
    local db = S.Database(overlay)
    NexusDB = db
    Nexus.LoadoutEvidence.Init(db)
    local begun = Catalog().BeginRootAdmission(db, S.Bundle())
    Check(begun and begun.state == "pending", "admission did not start pending")
    local generationBefore = S.Root().generation
    local pumps = 0
    while true do
        local result = Catalog().PumpRootAdmission()
        pumps = pumps + 1
        if result.state ~= "pending" then
            Check(result.state == "ROOT_ADMITTED",
                "admission ended " .. tostring(result.state) .. "/"
                    .. tostring(result.reason))
            break
        end
        if pumps % 500 == 0 then
            Check(Catalog().Get("adm09-0001") == nil and Catalog().Count() == 0
                and Catalog().Status().availableCount == 0
                and Catalog().FindExactFingerprintId("100000x1,100001x1,100002x1") == nil,
                "partial authority escaped during pending admission")
            Check(S.Root().generation == generationBefore,
                "generation advanced before one complete publish")
        end
        Check(pumps < 400000, "1,001-record admission did not converge")
    end
    Check(Catalog().Count() == 1001, "complete root did not admit all rows: "
        .. tostring(Catalog().Count()))
    Check(S.Root().generation == generationBefore + 1,
        "root publish did not advance exactly one generation")
    local counters = S.Counters()
    Check(counters.maxPerPump.rows <= 8, "more than 8 rows started in one pump")
    Check(counters.pumps == pumps, "pump accounting disagrees with caller")
end)

Case("ADM-10", "one generation-bound resumable admission", function()
    local overlay = {}
    for index = 1, 40 do
        local id = "adm10-" .. index
        overlay[id] = S.Build(id, 20, 0, {lastModified=index})
    end
    local db = S.Database(overlay)
    NexusDB = db
    Nexus.LoadoutEvidence.Init(db)
    Catalog().BeginRootAdmission(db, S.Bundle())
    local first = Catalog().PumpRootAdmission()
    Check(first.state == "pending", "single pump completed a 40-row root")
    local token = S.Root()
    Catalog().PumpRootAdmission()
    local again = S.Root()
    Check(token.bindingGeneration == again.bindingGeneration
        and token.generation == again.generation
        and again.candidate == true,
        "resumable handle did not retain its exact token between pumps")
    local result = S.PumpUntilTerminal()
    Check(result.state == "ROOT_ADMITTED" and S.Root().candidate == false,
        "resumed admission did not publish once")
end)

Case("ADM-11", "drift, supersession, and cancellation during scan", function()
    local overlay = {}
    for index = 1, 30 do
        local id = "adm11-" .. index
        overlay[id] = S.Build(id, 30, 0)
    end
    local db = S.Database(overlay)
    NexusDB = db
    Nexus.LoadoutEvidence.Init(db)
    -- owner-routed mutation during initial admission is refused, never mixed
    Catalog().BeginRootAdmission(db, S.Bundle())
    Catalog().PumpRootAdmission()
    local ok, why = AwaitMutation(Catalog().Put(S.Build("adm11-new", 1, 0)))
    Check(ok == false and why == "ROOT_ADMISSION_PENDING",
        "mutation during admission was not refused: " .. tostring(why))
    -- backing-table replacement is current-source drift
    db.communityBuilds = S.DeepCopy(overlay)
    local drifted = S.PumpUntilTerminal()
    Check(drifted.state == "ROOT_INVALIDATED",
        "backing replacement did not invalidate: " .. tostring(drifted.state))
    Check(Catalog().Get("adm11-1") == nil and Catalog().Count() == 0,
        "invalidated root still served rows")
    -- explicit cancellation of an initial bind returns to ROOT_UNBOUND
    Catalog().BeginRootAdmission(db, S.Bundle())
    Catalog().PumpRootAdmission()
    local cancelled = Catalog().CancelRootAdmission()
    Check(cancelled.state == "ROOT_UNBOUND", "cancellation did not unbind")
    -- No bundle was ever published on this path, so the exact PR #68 location
    -- is still the selected durable state (state machine line 374).
    Check(S.Count(db.communityBuilds) == 30, "cancellation changed raw storage")
    -- candidate supersession restarts at cursor zero
    Catalog().BeginRootAdmission(db, S.Bundle())
    for _ = 1, 5 do Catalog().PumpRootAdmission() end
    local superseded = Catalog().BeginRootAdmission(db, S.Bundle())
    Check(superseded.state == "pending" and S.Counters().pumps == 0,
        "supersession did not restart the candidate at cursor zero")
    local final = S.PumpUntilTerminal()
    Check(final.state == "ROOT_ADMITTED" and Catalog().Count() == 30,
        "superseding candidate did not publish a complete root")
end)

Case("ADM-12", "reload during admission discards the handle only", function()
    local overlay = {}
    for index = 1, 20 do overlay["adm12-" .. index] = S.Build("adm12-" .. index, 40, 0) end
    local db = S.Database(overlay)
    NexusDB = db
    Nexus.LoadoutEvidence.Init(db)
    local bytes = S.Encode(db)
    Catalog().BeginRootAdmission(db, S.Bundle())
    Catalog().PumpRootAdmission()
    S.Reload()
    Check(S.Root().state == "ROOT_UNBOUND", "reload retained a session root")
    Check(S.Encode(db) == bytes, "reload changed raw SavedVariables")
    -- Without the exact global rebind seam, an unbound root serves nothing.
    NexusDB = nil
    Check(Nexus.BuildCatalog.Get("adm12-1") == nil
        and Nexus.BuildCatalog.Count() == 0, "unbound root served a row")
    NexusDB = db
end)

Case("BUD-01", "2,049 slots and 65-key objects are fatal, never pruned", function()
    local overlay = {}
    for index = 1, 2049 do overlay["bud01-" .. index] = S.Build("bud01-" .. index, 1, 0) end
    local db = S.Database(overlay)
    local summary = S.Bind(db)
    Check(S.Root().state == "ROOT_INVALIDATED"
        and S.Root().reason == "ROOT_SLOT_LIMIT",
        "2,049 selected slots did not fail the whole root: "
            .. tostring(S.Root().state) .. "/" .. tostring(S.Root().reason))
    Check(summary.merged == 0 and Nexus.BuildCatalog.Count() == 0,
        "over-limit root exposed partial authority")
    -- The over-limit root never published, so no bundle exists and the exact
    -- PR #68 legacy input is still the selected durable state.
    Check(S.Count(db.communityBuilds) == 2049, "over-limit root pruned raw rows")
    local wide = S.Build("bud01-wide", 1, 0)
    for index = 1, 65 do wide["extra" .. index] = index end
    S.Bind(S.Database({["bud01-wide"]=wide}))
    Check(S.State("bud01-wide").state == "INVALIDATED"
        and S.State("bud01-wide").reason == "OBJECT_KEY_LIMIT",
        "65-key object was admitted")
end)

Case("BUD-02", "continuous mutation keeps one candidate and monotonic epochs", function()
    local db = S.Database({})
    S.Bind(db)
    local root = S.Root()
    local lastEpoch, lastGeneration = root.reservationEpoch, root.generation
    for index = 1, 60 do
        Check(AwaitMutation(Nexus.BuildCatalog.Put(S.Build("bud02-" .. index, 2, 0))),
            "mutation " .. index .. " refused")
        local state = S.Root()
        Check(state.candidate == false, "candidate retained after commit")
        Check(state.reservationEpoch > lastEpoch
            and state.generation == lastGeneration + 1,
            "epoch or generation did not advance monotonically")
        lastEpoch, lastGeneration = state.reservationEpoch, state.generation
    end
    Check(Nexus.BuildCatalog.Count() == 60, "continuous mutations lost rows")
end)

-- Provenance ----------------------------------------------------------------

Case("PROV-01", "spoofed ownership tuples grant zero privilege", function()
    S.Bind(S.Database({}))
    local catalog = Nexus.BuildCatalog
    -- remote row claiming verification without transport proof
    Check(AwaitMutation(catalog.Put(S.Build("prov-remote", 3, 0, {
        ownerKey="peer@ebonhold", ownerVerified=true, isMine=true,
    }), {source="remote", sender="Other-Ebonhold"})),
        "remote row refused outright")
    local remote = catalog.Get("prov-remote")
    Check(remote.ownerVerified == false and remote.isMine == false
        and remote.claimedOwnerKey == "peer@ebonhold" and remote.ownerKey == nil,
        "spoofed remote ownership survived admission")
    Check(Nexus.Identity.VerifiedOwnerKey(remote) == nil,
        "spoofed remote row became a verified owner")
    -- exact transport owner proves ownership
    Check(AwaitMutation(catalog.Put(S.Build("prov-owner", 3, 0), {source="remote",
        sender="Peer-Ebonhold"})), "owned remote row refused")
    Check(Nexus.Identity.VerifiedOwnerKey(catalog.Get("prov-owner"))
        == "peer@ebonhold", "transport-owned row was not verified")
    -- local row belonging to another character is never mine
    Check(AwaitMutation(catalog.Put(S.Build("prov-local", 3, 0, {
        ownerKey="peer@ebonhold", ownerVerified=true, isMine=true,
    }), {source="local"})), "local row refused")
    local localRow = catalog.Get("prov-local")
    Check(localRow.isMine == false and localRow.ownerVerified == false,
        "foreign local row claimed local ownership")
    Check(AwaitMutation(catalog.Put(S.LocalBuild("prov-mine", 3), {source="local"})),
        "own local row refused")
    Check(catalog.Get("prov-mine").isMine == true
        and catalog.Get("prov-mine").ownerVerified == true,
        "own local row lost its proof")
    -- bundled author text never proves local ownership
    S.Bind(S.Database({}), S.Bundle({bundledMine={
        id="bundledMine", title="Bundled", author="Boganic",
        ownerKey="boganic@ebonhold", isMine=true, ownerVerified=true,
        postedAt=1, lastModified=1, echoes=S.Echoes(2, 0),
    }}))
    local bundled = Nexus.BuildCatalog.Get("bundledMine")
    Check(bundled and bundled.isMine ~= true,
        "bundled row claimed local ownership")
end)

-- Future schema -------------------------------------------------------------

Case("FUT-01", "future row is deny-only and byte-preserved", function()
    local future = S.Build("fut01", 3, 0, {schemaVersion=2, futureField={keep=true}})
    local db = S.Database({fut01=future, sibling=S.Build("sibling", 2, 0)})
    local bytes = S.Encode(future)
    S.Bind(db)
    local catalog = Nexus.BuildCatalog
    local state = S.State("fut01")
    Check(state.state == "READ_ONLY_FUTURE_SCHEMA" and state.schemaVersion == 2,
        "future row state wrong: " .. tostring(state.state))
    Check(catalog.Get("fut01") == nil and catalog.Count() == 1
        and catalog.FindExactFingerprintId("100000x1,100001x1,100002x1") == nil,
        "future row gained current authority")
    Check(select(1, AwaitMutation(catalog.Put(S.Build("fut01", 1, 0)))) == false,
        "future row slot accepted a current write")
    Check(select(1, AwaitMutation(catalog.RemoveOverlay("fut01"))) == false
        and select(1, AwaitMutation(catalog.SetTombstone("fut01", {stamp=1,author="Peer"},
            {source="local"}))) == false,
        "future row accepted deletion or tombstone")
    Check(S.Durable(db).fut01 == future and S.Encode(future) == bytes,
        "future row was cloned, pruned, or normalized")
    Check(state.occupancy == "BLOCKED", "future row slot reported free")
    local summaries = catalog.Summaries()
    Check(summaries and summaries.fut01 == nil, "summary exposed a future row")
end)

Case("FUT-02", "future root reserves the whole catalog deny-only", function()
    local meta = {schemaVersion=99, catalogVersion="future", futureOwner={marker="keep"}}
    local row = S.Build("fut02", 3, 0)
    local tomb = {stamp=50, author="Peer", futureOnly=true}
    local db = S.Database({fut02=row}, {gone=tomb}, {buildCatalog=meta})
    local bytes = S.Encode(db)
    local summary = S.Bind(db)
    local catalog = Nexus.BuildCatalog
    Check(summary.readOnly == true and S.Root().state == "ROOT_READ_ONLY_FUTURE_SCHEMA",
        "future root was not reserved: " .. tostring(S.Root().state))
    Check(catalog.Get("fut02") == nil and catalog.Count() == 0
        and catalog.Status().availableCount == 0 and catalog.Status().readOnly == true,
        "future root served current authority")
    for _, call in ipairs({
        function() return AwaitMutation(catalog.Put(S.Build("blocked", 1, 0))) end,
        function() return AwaitMutation(catalog.RemoveOverlay("fut02")) end,
        function() return AwaitMutation(catalog.SetTombstone("fut02", {stamp=99}, {source="local"})) end,
        function() return catalog.ClearTombstone("gone") end,
    }) do
        local ok, reason = call()
        Check(ok == false and reason == "ROOT_READ_ONLY_FUTURE_SCHEMA",
            "future root accepted a mutation: " .. tostring(reason))
    end
    Check(S.Encode(db) == bytes and db.buildCatalog == meta,
        "future root bytes were rewritten")
    -- strict discriminator precedence: non-numeric or metatable is invalid, not future
    local malformed = S.Database({}, {}, {buildCatalog={schemaVersion="2"}})
    S.Bind(malformed)
    Check(S.Root().state == "ROOT_INVALIDATED", "string discriminator became future")
    local hostileMeta = setmetatable({schemaVersion=2}, {__index=function() error("trap") end})
    S.Bind(S.Database({}, {}, {buildCatalog=hostileMeta}))
    Check(S.Root().state == "ROOT_INVALIDATED", "metatable-backed meta became future")
    Check(catalog.Count() == 0, "invalid root served counts")
end)

-- Unknown fields ------------------------------------------------------------

Case("UNK-01", "unknown scalar survives update, restart, and maintenance", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Nexus.BuildCatalog
    Check(AwaitMutation(catalog.Put(S.Build("unk01", 3, 0, {futureScalar="keep me"}))))
    Check(S.Durable(db).unk01.futureScalar == "keep me",
        "unknown scalar was dropped on store")
    Check(AwaitMutation(catalog.Put(S.Build("unk01", 4, 0, {title="Updated"}))))
    Check(S.Durable(db).unk01.futureScalar == "keep me"
        and S.Durable(db).unk01.title == "Updated",
        "unknown scalar was lost on update")
    S.Reload()
    S.Bind(db)
    Check(S.Durable(NexusDB).unk01.futureScalar == "keep me"
        and Nexus.BuildCatalog.Get("unk01").title == "Updated",
        "unknown scalar was lost on restart")
    local handle = Nexus.BuildCatalog.BeginCatalogMaintenance({
        database=db, operation="compaction"})
    Check(handle, "maintenance handle unavailable")
    local copy = Nexus.BuildCatalog.Get("unk01")
    copy.description = "compacted"
    Check(Nexus.BuildCatalog.MaintenanceReplaceRow(handle, "unk01", copy))
    Check(Nexus.BuildCatalog.CommitMaintenance(handle))
    Check(S.Durable(db).unk01.futureScalar == "keep me"
        and S.Durable(db).unk01.description == "compacted",
        "maintenance replacement erased the unknown scalar")
end)

Case("UNK-02", "nested unknown scope follows its tuple or refuses", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Nexus.BuildCatalog
    local row = S.Build("unk02", 3, 0)
    row.echoes[2].futureTag = {kind="rune", level=3}
    Check(AwaitMutation(catalog.Put(row)))
    local stored = S.Durable(db).unk02
    local owner
    for _, echo in ipairs(stored.echoes) do
        if echo.futureTag then owner = echo end
    end
    Check(owner and owner.spellId == 100001 and owner.futureTag.level == 3,
        "unique-tuple unknown scope did not survive")
    -- reorder the same rows: scope moves with the tuple
    local reordered = S.Build("unk02", 3, 0)
    reordered.echoes = {reordered.echoes[3], reordered.echoes[1], reordered.echoes[2]}
    Check(AwaitMutation(catalog.Put(reordered)))
    owner = nil
    for _, echo in ipairs(S.Durable(db).unk02.echoes) do
        if echo.futureTag then owner = echo end
    end
    Check(owner and owner.spellId == 100001 and owner.futureTag.level == 3,
        "reorder relocated or dropped the tuple-scoped unknown")
    -- duplicate tuples with any unknown subtree are ambiguous
    local ambiguous = S.Build("unk02b", 2, 0)
    ambiguous.echoes[2] = {spellId=100000, quality=3, stacks=1, futureTag={a=1}}
    local okAmbiguous, whyAmbiguous = AwaitMutation(catalog.Put(ambiguous))
    Check(okAmbiguous == false and whyAmbiguous == "AMBIGUOUS_NESTED_UNKNOWN_SCOPE",
        "duplicate unknown-owning tuples were merged: " .. tostring(whyAmbiguous))
    -- removing an unknown-owning tuple requires a schema migration
    local removal = S.Build("unk02", 3, 0)
    removal.echoes = {removal.echoes[1], removal.echoes[3]}
    local okRemoval, whyRemoval = AwaitMutation(catalog.Put(removal))
    Check(okRemoval == false
        and whyRemoval == "UNKNOWN_TUPLE_SCHEMA_MIGRATION_REQUIRED",
        "unknown-owning tuple was removed: " .. tostring(whyRemoval))
    Check(#S.Durable(db).unk02.echoes == 3, "refused update changed storage")
end)

Case("UNK-03", "over-budget unknown evidence invalidates without truncation", function()
    local row = S.Build("unk03", 3, 0, {futureBlob=string.rep("z", 4097)})
    local db = S.Database({unk03=row})
    local bytes = S.Encode(row)
    S.Bind(db)
    local state = S.State("unk03")
    Check(state.state == "INVALIDATED" and state.reason == "UNKNOWN_EVIDENCE_BUDGET",
        "over-budget unknown was admitted: " .. tostring(state.reason))
    Check(S.Encode(row) == bytes and S.Durable(db).unk03 == row,
        "over-budget row was truncated or replaced")
    local inbound = S.Build("unk03b", 3, 0, {futureBlob=string.rep("z", 4097)})
    local ok, why = AwaitMutation(Nexus.BuildCatalog.Put(inbound))
    Check(ok == false and why == "UNKNOWN_EVIDENCE_BUDGET"
        and S.Durable(db).unk03b == nil,
        "over-budget inbound row reached durable storage")
end)

Case("UNK-04", "baseline-equivalent overlay with unknown field survives", function()
    local bundledRow = {id="unk04", title="Same", author="A", postedAt=10,
        lastModified=10, echoes={{spellId=1,quality=0,stacks=1}}}
    local overlayRow = S.DeepCopy(bundledRow)
    overlayRow.futureOwner = {marker="keep"}
    local plain = S.DeepCopy(bundledRow)
    plain.id = "unk04-plain"
    local bundledPlain = S.DeepCopy(plain)
    local db = S.Database({unk04=overlayRow, ["unk04-plain"]=plain},
        {}, {buildCatalog={schemaVersion=1, catalogVersion="old", sourceVersion="x"}})
    S.Bind(db, S.Bundle({unk04=bundledRow, ["unk04-plain"]=bundledPlain}, "new"))
    Check(S.Durable(db).unk04 == overlayRow
        and overlayRow.futureOwner.marker == "keep",
        "baseline pruning removed an unknown-owning overlay")
    Check(S.Durable(db)["unk04-plain"] == nil,
        "known-only baseline-equivalent overlay was not pruned")
    Check(Nexus.BuildCatalog.Get("unk04") ~= nil, "overlay row unavailable")
end)

Case("UNK-05", "update replaces known fields exactly and keeps unknown scope", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Nexus.BuildCatalog
    Check(AwaitMutation(catalog.Put(S.Build("unk05", 3, 0, {
        link="https://example/x", description="d", futureA="a",
    }))))
    local update = S.Build("unk05", 3, 0, {futureB="b"})
    update.link, update.description = nil, nil
    Check(AwaitMutation(catalog.Put(update)))
    local stored = S.Durable(db).unk05
    Check(stored.link == nil and stored.description == nil,
        "omitted known fields retained stale authority")
    Check(stored.futureA == "a" and stored.futureB == "b",
        "unknown fields were lost or not added")
    Check(catalog.Get("unk05").link == nil, "public copy retained stale known field")
end)

-- API and index state ---------------------------------------------------------

Case("API-01", "unbound and invalid roots serve fixed non-valid results", function()
    S.Reload()
    local catalog = Nexus.BuildCatalog
    NexusDB = nil
    Check(S.Root().state == "ROOT_UNBOUND", "fresh module is not unbound")
    Check(catalog.Count() == 0 and catalog.Get("x") == nil
        and catalog.GetSummary("x") == nil and catalog.IsAuthor("A") == false
        and catalog.FindExactFingerprintId("1x1") == nil
        and catalog.HasBaseline("x") == false,
        "unbound root granted authority")
    local ok, why = AwaitMutation(catalog.Put(S.Build("api", 1, 0)))
    Check(ok == false and why == "ROOT_UNBOUND", "unbound Put not refused: " .. tostring(why))
    local occupancy, represented, advisory = catalog.AllocationOccupancy("api")
    Check(occupancy == "opaque" and represented == nil and advisory.blocked == true,
        "unbound occupancy reported free")
    local cursor, cursorWhy = catalog.BeginRecordCursor()
    Check(cursor == nil and cursorWhy == "ROOT_UNBOUND", "unbound cursor allocated")
    -- defensive copies
    local db = S.Database({})
    S.Bind(db)
    catalog = Nexus.BuildCatalog
    Check(AwaitMutation(catalog.Put(S.Build("api-copy", 2, 0))))
    local copy = catalog.Get("api-copy")
    copy.title = "mutated"; copy.echoes[1].stacks = 99
    Check(catalog.Get("api-copy").title == "Build api-copy"
        and catalog.Get("api-copy").echoes[1].stacks == 1,
        "returned record was not defensive")
    -- maximum-root legacy collections return only CURSOR_REQUIRED
    for index = 1, 9 do Check(AwaitMutation(catalog.Put(S.Build("api-" .. index, 1, 0)))) end
    local all, allWhy = catalog.All()
    Check(all == nil and allWhy == "CURSOR_REQUIRED",
        "All returned a partial or complete over-limit collection")
    local summaries, summariesWhy = catalog.Summaries()
    Check(summaries == nil and summariesWhy == "CURSOR_REQUIRED",
        "Summaries returned an over-limit collection")
    local visited, visitWhy = catalog.ForEach(function() end)
    Check(visited == 0 and visitWhy == "CURSOR_REQUIRED", "ForEach ran a partial walk")
    -- record cursor: one defensive record per step, idempotent exhaustion
    local token = assert(catalog.BeginRecordCursor())
    local seen, steps = 0, 0
    while true do
        local result, err = catalog.RecordCursorNext(token)
        Check(err == nil, "record cursor error: " .. tostring(err))
        steps = steps + 1
        if result.done then break end
        if result.record then seen = seen + 1 end
        Check(steps < 100, "record cursor did not exhaust")
    end
    Check(seen == 10, "record cursor lost rows: " .. tostring(seen))
    local again = catalog.RecordCursorNext(token)
    Check(again and again.done == true, "exhaustion was not idempotent")
    -- supersession invalidates the older token; drift returns STALE once
    local older = assert(catalog.BeginRecordCursor())
    local newer = assert(catalog.BeginRecordCursor())
    local _, olderErr = catalog.RecordCursorNext(older)
    Check(olderErr == "INVALID_CURSOR", "superseded cursor still served")
    Check(AwaitMutation(catalog.Put(S.Build("api-drift", 1, 0))))
    local _, driftErr = catalog.RecordCursorNext(newer)
    Check(driftErr == "STALE_CURSOR", "root drift did not stale the cursor")
    local _, afterErr = catalog.RecordCursorNext(newer)
    Check(afterErr == "INVALID_CURSOR", "stale cursor survived a second use")
    local forged = {kind="record", cursorId=1, generation=S.Root().generation}
    local _, forgedErr = catalog.RecordCursorNext(forged)
    Check(forgedErr == "INVALID_CURSOR", "fabricated cursor was accepted")
end)

Case("IDX-01", "index parity, winner promotion, and stale invalidation", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Nexus.BuildCatalog
    local key = "100000x1,100001x1,100002x1"
    for index = 1, 300 do
        Check(AwaitMutation(catalog.Put(S.Build(string.format("idx-%03d", index), 3, 0, {
            autoDps=index > 1 or nil,
        }))))
    end
    Check(catalog.FindExactFingerprintId(key) == "idx-001",
        "explicit build did not win the exact bucket")
    Check(AwaitMutation(catalog.RemoveOverlay("idx-001")))
    Check(catalog.FindExactFingerprintId(key) == "idx-002",
        "stale representative was not promoted deterministically")
    local related = catalog.BeginRelatedCursor("Peer", "Build idx-002", key)
    Check(related, "related cursor unavailable")
    Check(AwaitMutation(catalog.Put(S.Build("idx-mutate", 1, 0))))
    local _, done, err = catalog.RelatedCursorNext(related)
    Check(done == true and err == "catalog changed",
        "mutation did not invalidate the related cursor")
    Check(catalog.ResolveOwnerClass({ownerKey="peer@ebonhold", realm="ebonhold",
        author="Peer", ownerVerified=true}) == "MAGE",
        "owner class index lost parity")
    Check(catalog.IsAuthor("Peer") == true and catalog.IsAuthor("Nobody") == false,
        "author index lost parity")
    local status = catalog.Status()
    Check(status.availableCount == catalog.Count() and status.availableCount == 300,
        "status count disagrees with count")
end)

Check(#S.results > 0, "no selected admission case ran")
S.Finish("catalog authority admission matrix")
