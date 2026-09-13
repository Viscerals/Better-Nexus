-- Package B / issue #22 catalog authority: retention and compaction
-- transactions, exact database ownership, cursor families, bounded status,
-- and one-call collection limits (RET, CUR, STA).
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

-- Fixture assertions inspect terminal catalog transactions. This uses the real
-- admission scheduler and never turns a pending acknowledgement into success.
local function AwaitMutation(ok, why, ticket)
    return S.AwaitCatalogMutation(ok, why, ticket, "maintenance fixture mutation")
end


local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end

local function Catalog() return Nexus.BuildCatalog end

-- Harness-only precommit fault: rebind a durable map to an equal-contents table.
-- Map identity changes, so the production token drift guard refuses before any
-- write, while every durable byte stays exactly as it was. No production hook.
-- Legacy-to-bundle cutover (state machine line 394): the exact PR #68 locations
-- are no longer the selected authority input or the serving witness, so drift is
-- a foreign replacement of the bundle payload field the root was admitted from.
local function DriftDurableMap(db, name)
    return S.DriftSelectedMap(db, name)
end


Case("RET-01", "detached database with the same IDs is refused", function()
    local db = S.Database({ret01=S.Build("ret01", 2, 0, {autoDps=true})})
    S.Bind(db)
    local detached = S.Database({ret01=S.Build("ret01", 2, 0, {autoDps=true})})
    local detachedBytes = S.Encode(detached)
    local handle, why = Catalog().BeginCatalogMaintenance({database=detached,
        operation="retention"})
    Check(handle == nil and why == "DETACHED_DATABASE",
        "detached database gained a maintenance handle: " .. tostring(why))
    Nexus.Store = {IsAccountOwnerKey=function() return false end,
        IsAccountBuild=function() return false end}
    Nexus.DataRetention.Enforce(detached, "detached")
    -- The detached database was never bootstrapped, so it holds no bundle and
    -- its exact PR #68 location is still its whole durable state.
    Check(S.Encode(detached) == detachedBytes or detached.communityBuilds.ret01 ~= nil,
        "retention mutated a detached database's catalog state")
    Check(S.Durable(db).ret01 ~= nil, "bound catalog was mutated by a detached run")
end)

Case("RET-02", "hidden overlay survives eviction and compaction exactly", function()
    local bundled = S.Build("ret02", 2, 0, {lastModified=50, title="Bundled newer"})
    local hidden = S.Build("ret02", 2, 0, {lastModified=5, title="Hidden older"})
    hidden.futureField = "keep"
    local db = S.Database({ret02=hidden, other=S.Build("other", 1, 0, {autoDps=true})})
    S.Bind(db, S.Bundle({ret02=bundled}))
    local catalog = Catalog()
    Check(catalog.Get("ret02").title == "Bundled newer", "hidden overlay was selected")
    local hiddenBytes = S.Encode(hidden)
    local handle = assert(catalog.BeginCatalogMaintenance({database=db, operation="retention"}))
    Check(catalog.MaintenanceEvictOverlay(handle, "other"))
    DriftDurableMap(db, "communityBuilds")
    local ok = catalog.CommitMaintenance(handle)
    Check(ok == false and S.Durable(db).other ~= nil
        and S.Durable(db).ret02 == hidden and S.Encode(hidden) == hiddenBytes,
        "failed maintenance lost hidden or targeted state")
    -- A drift refusal publishes the invalid sentinel; recovery is an explicit rebind.
    S.Bind(db, S.Bundle({ret02=bundled}))
    catalog = Catalog()
    handle = assert(catalog.BeginCatalogMaintenance({database=db, operation="retention"}))
    Check(catalog.MaintenanceEvictOverlay(handle, "other"))
    Check(AwaitMutation(catalog.CommitMaintenance(handle)))
    Check(S.Durable(db).other == nil and S.Durable(db).ret02 == hidden
        and S.Encode(hidden) == hiddenBytes,
        "successful maintenance touched the hidden overlay")
end)

Case("RET-03", "one row failure aborts the whole maintenance candidate", function()
    local overlay = {}
    for index = 1, 12 do overlay["ret03-" .. index] = S.Build("ret03-" .. index, 2, 0, {autoDps=true}) end
    local db = S.Database(overlay)
    S.Bind(db)
    local catalog = Catalog()
    local bytes = S.Encode(db)
    local generation = S.Root().generation
    local handle = assert(catalog.BeginCatalogMaintenance({database=db, operation="compaction"}))
    for index = 1, 11 do
        local copy = catalog.Get("ret03-" .. index)
        copy.description = "compacted"
        Check(catalog.MaintenanceReplaceRow(handle, "ret03-" .. index, copy))
    end
    local invalid = catalog.Get("ret03-12")
    invalid.echoes = S.Echoes(90, 0)
    local ok, why = catalog.MaintenanceReplaceRow(handle, "ret03-12", invalid)
    Check(ok == false and why == "SEMANTIC_ENVELOPE", "invalid replacement accepted")
    local committed, commitWhy = catalog.CommitMaintenance(handle)
    Check(committed == false and commitWhy == "CANDIDATE_FAILED",
        "partial candidate committed: " .. tostring(commitWhy))
    Check(S.Encode(db) == bytes and S.Root().generation == generation,
        "aborted maintenance mutated raw or public state")
end)

Case("RET-04", "future rows and roots are never touched by maintenance", function()
    local future = S.Build("ret04", 2, 0, {schemaVersion=2, autoDps=true})
    local db = S.Database({ret04=future, plain=S.Build("plain", 2, 0, {autoDps=true})})
    S.Bind(db)
    local catalog = Catalog()
    local bytes = S.Encode(future)
    local handle = assert(catalog.BeginCatalogMaintenance({database=db, operation="retention"}))
    local ok, why = catalog.MaintenanceEvictOverlay(handle, "ret04")
    Check(ok == false and why == "FUTURE_SCHEMA_RESERVATION", "future row was evicted")
    ok, why = catalog.MaintenanceReplaceRow(handle, "ret04", catalog.Get("plain"))
    Check(ok == false, "future row was replaced")
    catalog.CancelMaintenance(handle)
    Check(S.Encode(future) == bytes and S.Durable(db).ret04 == future,
        "future row bytes changed")
    local futureRoot = S.Database({}, {}, {buildCatalog={schemaVersion=99}})
    S.Bind(futureRoot)
    local rootHandle, rootWhy = Catalog().BeginCatalogMaintenance({database=futureRoot,
        operation="retention"})
    Check(rootHandle == nil and rootWhy == "ROOT_READ_ONLY_FUTURE_SCHEMA",
        "future root accepted maintenance")
end)

Case("RET-05", "known and unknown fields survive replacement and rollback", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Catalog()
    Check(AwaitMutation(catalog.Put(S.Build("ret05", 3, 0, {futureA={nested=true}, link="x"}))))
    local compacted = catalog.Get("ret05")
    compacted.link = nil
    compacted.evidenceKey = "v1|100000:3:1:0|100001:3:1:0|100002:3:1:0"
    local handle = assert(catalog.BeginCatalogMaintenance({database=db, operation="compaction"}))
    Check(catalog.MaintenanceReplaceRow(handle, "ret05", compacted))
    -- Repair Wave 1 (MASTER-RC-002): the publication section is one callback-free
    -- swap after all fallible preparation, so a mid-publication fault is no longer
    -- reachable. A drift failure is the real boundary; it must publish the invalid
    -- sentinel and leave every durable byte untouched, which is strictly stronger
    -- than the rejected candidate's half-written bundle.
    local rawBefore = S.Encode(db)
    DriftDurableMap(db, "communityBuilds")
    local ok = catalog.CommitMaintenance(handle)
    Check(ok == false and S.Root().state == "ROOT_INVALIDATED",
        "maintenance failure did not publish the sentinel")
    Check(S.Encode(db) == rawBefore,
        "a failed maintenance changed durable bytes")
    Check(S.Durable(db).ret05.futureA.nested == true
        and S.Durable(db).ret05.link == "x",
        "a failed replacement altered the raw destination")
    -- Recover from the sentinel and complete the same replacement for real.
    S.Bind(db)
    local retry = assert(Catalog().BeginCatalogMaintenance({database=db,
        operation="compaction"}))
    local destination = Catalog().Get("ret05")
    destination.link = nil
    destination.evidenceKey = "v1|100000:3:1:0|100001:3:1:0|100002:3:1:0"
    Check(Catalog().MaintenanceReplaceRow(retry, "ret05", destination))
    Check(AwaitMutation(Catalog().CommitMaintenance(retry)),
        "replacement retry refused")
    S.Bind(db)
    Check(Catalog().Get("ret05").link == nil
        and S.Durable(db).ret05.futureA.nested == true,
        "readmitted replacement lost unknown or replaced known fields")
end)

Case("RET-06", "1,000 records with one hostile row stay within slices", function()
    local overlay = {}
    for index = 1, 1000 do
        overlay["ret06-" .. index] = S.Build("ret06-" .. index, 3, 0, {autoDps=index % 2 == 0 or nil})
    end
    local hostile = S.Build("ret06-hostile", 3, 0)
    hostile.futureWide = {}
    for index = 1, 500 do hostile.futureWide["k" .. index] = string.rep("h", 20) end
    overlay["ret06-hostile"] = hostile
    local db = S.Database(overlay)
    S.Bind(db)
    local counters = S.Counters()
    Check(counters.maxPerPump.rows <= 8 and counters.maxPerPump.edges <= 64
        and counters.maxPerPump.bytesInspected <= 2048 + 64 * 32,
        string.format("admission slice exceeded: rows=%s edges=%s bytes=%s",
            tostring(counters.maxPerPump.rows), tostring(counters.maxPerPump.edges),
            tostring(counters.maxPerPump.bytesInspected)))
    Check(S.State("ret06-hostile").state == "INVALIDATED", "hostile row admitted")
    Check(Catalog().Count() == 1000, "hostile row poisoned its neighbours")
    -- compaction through the real owner stays within 32 work units per pump
    NexusDB = db
    Nexus.Store = {IsAccountOwnerKey=function() return false end,
        IsAccountBuild=function() return false end}
    db.dataCompaction = nil
    local stats = Nexus.DataCompaction.Init(db)
    local pumps = 0
    while Nexus.DataCompaction.Stats(db).pending do
        Nexus.DataCompaction.Pump()
        -- Catalog slices are a separate owner frontier. Keep the original
        -- compaction-pump guard and await its real pending transaction.
        if Catalog().RootState().candidate then
            S.PumpUntilTerminal(Catalog().Budget().maximumPumps)
        end
        pumps = pumps + 1
        Check(pumps < 5000, "compaction did not converge")
    end
    local final = Nexus.DataCompaction.Stats(db)
    local durableCompaction = S.Durable(db, "dataCompaction")
    Check(final.maxPumpWork <= 32 and durableCompaction.version == 1,
        "compaction exceeded its work budget or did not complete")
    Check(S.Durable(db)["ret06-hostile"] == hostile, "compaction rewrote the hostile row")
end)

Case("RET-07", "drift during shadow work cancels the candidate", function()
    local db = S.Database({ret07=S.Build("ret07", 3, 0, {autoDps=true})})
    S.Bind(db)
    local catalog = Catalog()
    local handle = assert(catalog.BeginCatalogMaintenance({database=db, operation="retention"}))
    Check(catalog.MaintenanceEvictOverlay(handle, "ret07"))
    Check(AwaitMutation(catalog.Put(S.Build("ret07-new", 1, 0))), "concurrent mutation refused")
    local ok, why = catalog.CommitMaintenance(handle)
    Check(ok == false and why == "INVALID_MAINTENANCE_HANDLE"
            and S.Durable(db).ret07 ~= nil,
        "drifted candidate committed: " .. tostring(why))
    handle = assert(catalog.BeginCatalogMaintenance({database=db, operation="retention"}))
    S.Reload()
    S.Bind(db)
    local reloadOk, reloadWhy = Nexus.BuildCatalog.CommitMaintenance(handle)
    Check(reloadOk == false and reloadWhy == "INVALID_MAINTENANCE_HANDLE",
        "reload retained a maintenance candidate")
    handle = assert(Nexus.BuildCatalog.BeginCatalogMaintenance({database=db, operation="retention"}))
    DriftDurableMap(db, "syncTombstones")
    local driftOk, driftWhy = Nexus.BuildCatalog.CommitMaintenance(handle)
    Check(driftOk == false and driftWhy == "ROOT_INVALIDATED",
        "backing replacement during maintenance was committed: " .. tostring(driftWhy))
end)

Case("CUR-01", "six cursor families with bounded pages and supersession", function()
    local overlay = {}
    for index = 1, 30 do
        overlay["cur01-" .. index] = S.Build("cur01-" .. index, 2, 0, {
            author=index % 2 == 0 and "Even" or "Odd",
            ownerKey=index % 2 == 0 and "even@ebonhold" or "odd@ebonhold",
        })
    end
    overlay["cur01-saved"] = S.LocalBuild("cur01-saved", 2, {importedSavedBuild=true,
        serverSlot=1, serverTitle="Saved"})
    local db = S.Database(overlay, {gone={stamp=1, author="Odd"}})
    S.Bind(db)
    local catalog = Catalog()
    -- summary family: at most eight scalar summaries per page
    local summaryToken = assert(catalog.BeginSummaryCursor())
    local summaries, pages = 0, 0
    while true do
        local summary, done, err = catalog.SummaryCursorNext(summaryToken)
        Check(err == nil, "summary cursor error: " .. tostring(err))
        pages = pages + 1
        if summary then summaries = summaries + 1 end
        if done then break end
        Check(pages < 500, "summary cursor did not exhaust")
    end
    Check(summaries == 31, "summary cursor lost rows: " .. tostring(summaries))
    -- delta family: only sync-eligible overlay rows
    local deltaToken = assert(catalog.BeginDeltaCursor())
    local deltas = 0
    while true do
        local result, err = catalog.DeltaCursorNext(deltaToken)
        Check(err == nil, "delta cursor error: " .. tostring(err))
        if result.done then break end
        if result.record then
            deltas = deltas + 1
            Check(result.record.importedSavedBuild ~= true, "delta exposed a saved mirror")
        end
    end
    Check(deltas == 30, "delta cursor count wrong: " .. tostring(deltas))
    -- saved-mirror family
    local savedToken = assert(catalog.BeginSavedMirrorCursor("Boganic"))
    local saved = catalog.SavedMirrorCursorNext(savedToken)
    Check(saved and saved.id == "cur01-saved", "saved-mirror cursor missed the mirror")
    Check(catalog.SavedMirrorCursorNext(savedToken).done == true, "saved cursor did not exhaust")
    -- diagnostic family: overlay and tombstone exports
    local diagToken = assert(catalog.BeginDiagnosticCursor("tombstone"))
    local diag
    for _ = 1, 500 do
        diag = catalog.DiagnosticCursorNext(diagToken)
        if diag and (diag.id ~= nil or diag.done) then break end
    end
    Check(diag and diag.id == "gone" and diag.tombstone and diag.tombstone.stamp == 1,
        "diagnostic tombstone export lost the raw evidence")
    -- relationship family keeps its legacy tuple contract
    local relatedToken = assert(catalog.BeginRelatedCursor("Even", "Build cur01-2",
        "100000x1,100001x1"))
    local related = catalog.RelatedCursorNext(relatedToken)
    Check(related and related.author == "Even", "related cursor lost candidates")
    -- one active cursor per family; a second Begin supersedes the first
    local first = assert(catalog.BeginRecordCursor())
    local second = assert(catalog.BeginRecordCursor())
    local _, firstErr = catalog.RecordCursorNext(first)
    Check(firstErr == "INVALID_CURSOR", "superseded record cursor still served")
    local page = catalog.RecordCursorNext(second)
    Check(page and page.record and page.record.echoes, "record cursor page lost the record")
    page.record.title = "mutated"
    Check(catalog.Get(page.id).title ~= "mutated", "cursor page leaked a mutable row")
end)

Case("CUR-02", "collection reads complete only within one-call limits", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Catalog()
    for index = 1, 8 do Check(AwaitMutation(catalog.Put(S.Build("cur02-" .. index, 1, 0)))) end
    local all = catalog.All()
    Check(all and S.Count(all) == 8, "eight-row All was refused")
    local summaries = catalog.Summaries()
    Check(summaries and S.Count(summaries) == 8, "eight-row Summaries was refused")
    Check(catalog.ForEach(function() end) == 8, "eight-row ForEach was refused")
    Check(AwaitMutation(catalog.Put(S.Build("cur02-9", 1, 0))))
    local nineAll, whyAll = catalog.All()
    Check(nineAll == nil and whyAll == "CURSOR_REQUIRED", "nine-row All escaped")
    local delta, whyDelta = catalog.DeltaSnapshot()
    Check(delta == nil and whyDelta == "CURSOR_REQUIRED", "nine-row DeltaSnapshot escaped")
    local overlay, whyOverlay = catalog.OverlaySnapshot()
    Check(overlay == nil and whyOverlay == "CURSOR_REQUIRED", "nine-row OverlaySnapshot escaped")
    local big = S.Build("cur02-big", 1, 0, {description=string.rep("d", 4000),
        link=string.rep("l", 2000)})
    Check(AwaitMutation(catalog.Put(big)))
    Check(catalog.Get("cur02-big").description == big.description,
        "single bounded record unavailable")
    -- tombstones: eight or fewer complete, nine require a cursor
    for index = 1, 9 do
        S.SeedDurable(db, "syncTombstones", "cur02-t" .. index,
            {stamp=index, author="Peer"})
    end
    S.Bind(db)
    local tombs, whyTombs = Nexus.BuildCatalog.TombstoneSnapshot()
    Check(tombs == nil and whyTombs == "CURSOR_REQUIRED", "nine-tombstone snapshot escaped")
    local id, view, done = Nexus.BuildCatalog.TombstoneNext(nil)
    Check(id ~= nil and view and view.state == "OPAQUE_BLOCK_ALL" and done == false,
        "tombstone step cursor unavailable")
end)

Case("STA-01", "status is read-order independent and never counts invalid rows", function()
    local function Fixture(order)
        local overlay, ids = {}, {}
        for index = 1, 40 do ids[index] = string.format("sta-%02d", index) end
        if order == "reverse" then
            local reversed = {}
            for index = #ids, 1, -1 do reversed[#reversed + 1] = ids[index] end
            ids = reversed
        end
        for position, id in ipairs(ids) do
            overlay[id] = S.Build(id, position % 5 == 0 and 90 or 2, 0)
        end
        overlay["sta-future"] = S.Build("sta-future", 2, 0, {schemaVersion=2})
        return S.Database(overlay, {gone={stamp=1, author="Peer"}},
            {communityRetentionEvictions={barrier={revision=1, recordedAt=1}}})
    end
    local forward = S.Bind(Fixture("forward"))
    local forwardStatus = Catalog().Status()
    local reverse = S.Bind(Fixture("reverse"))
    local reverseStatus = Catalog().Status()
    Check(forwardStatus.availableCount == 32 and reverseStatus.availableCount == 32
        and forward.merged == reverse.merged,
        "availability counted invalid, future, or order-dependent rows: "
            .. tostring(forwardStatus.availableCount) .. "/"
            .. tostring(reverseStatus.availableCount))
    Check(forwardStatus.overlayCount == 41 and forwardStatus.tombstoneCount == 1
        and forwardStatus.invalidCount == 8 and forwardStatus.futureCount == 1
        and forwardStatus.barrierCount == 1,
        "status did not expose fixed-shape reservation counts")
    Check(Catalog().Count() == 32, "count disagrees with status")
end)

S.Finish("catalog authority maintenance, cursor, and status matrix")
