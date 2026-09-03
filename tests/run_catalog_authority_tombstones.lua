-- Package B / issue #22 catalog authority: tombstone reservations, eviction
-- barriers, allocation claims, mutation transactions, and the exhaustive
-- row-state transition table (TMB, EVC, ALC, MUT, ROOT, TRN).
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

local DAY = 24 * 60 * 60
local now = 2000000000
time = function() return now end

local function Catalog() return Nexus.BuildCatalog end
local function LocalTomb(stamp)
    return {stamp=stamp or now, author="Boganic", ownerKey="boganic@ebonhold",
        ownerVerified=true}
end

-- Tombstones ----------------------------------------------------------------

Case("TMB-01", "current-session, persisted V1, and legacy tombstones", function()
    local legacy = {stamp=5, author="Boganic", ownerKey="boganic@ebonhold",
        ownerVerified=true}
    local db = S.Database({tmb01=S.LocalBuild("tmb01", 3)}, {legacy=legacy})
    S.Bind(db)
    local catalog = Catalog()
    Check(catalog.SetTombstone("tmb01", LocalTomb(), {source="local"}),
        "local row-to-tombstone refused")
    local state = S.State("tmb01")
    Check(state.state == "TOMBSTONED"
        and state.reservation == "TOMBSTONE_CURRENT_DENY",
        "current-session tombstone state wrong: " .. tostring(state.state)
            .. "/" .. tostring(state.reservation))
    local view = catalog.TombstoneState("tmb01")
    Check(view.state == "CURRENT_DENY" and view.localOwned == true
        and view.stamp == now and view.author == "Boganic",
        "current-session tombstone view lost derived fields")
    Check(db.communityBuilds.tmb01 == nil and type(db.syncTombstones.tmb01) == "table"
        and db.syncTombstones.tmb01.schemaVersion == 1,
        "row-to-tombstone did not publish the V1 durable shape")
    local legacyState = S.State("legacy")
    Check(legacyState.reservation == "TOMBSTONE_OPAQUE_BLOCK_ALL"
        and catalog.TombstoneState("legacy").localOwned == false,
        "legacy tombstone regained owner authority")
    Check(db.syncTombstones.legacy == legacy and legacy.ownerVerified == true,
        "legacy tombstone was rewritten")
    S.Reload()
    S.Bind(db)
    local reloaded = Nexus.BuildCatalog.TombstoneState("tmb01")
    Check(reloaded.state == "RELOADED_BLOCK_ALL" and reloaded.localOwned == false,
        "exact-shaped persisted tombstone regained session authority")
    Check(S.State("tmb01").state == "INVALIDATED"
        and S.State("tmb01").reservation == "TOMBSTONE_RELOADED_BLOCK_ALL",
        "reloaded tombstone did not project deny-only INVALIDATED")
    Check(Nexus.BuildCatalog.Get("tmb01") == nil, "reloaded tombstone exposed a row")
end)

Case("TMB-02", "malformed and opaque tombstones grant nothing", function()
    local hostile = setmetatable({stamp=1, author="Boganic",
        ownerKey="boganic@ebonhold", ownerVerified=true}, {})
    local db = S.Database({}, {
        scalar=7, flag=true, text="x",
        payload={stamp=1, author="Boganic", ownerKey="boganic@ebonhold",
            ownerVerified=true, pending={deep=true}},
        meta=hostile,
    })
    local bytes = S.Encode({db.syncTombstones.scalar, db.syncTombstones.flag,
        db.syncTombstones.text, db.syncTombstones.payload})
    S.Bind(db)
    for _, id in ipairs({"scalar", "flag", "text", "payload", "meta"}) do
        local state = S.State(id)
        Check(state.reservation == "TOMBSTONE_OPAQUE_BLOCK_ALL"
            and state.occupancy == "BLOCKED",
            "opaque tombstone gained authority: " .. id)
        local view = Catalog().TombstoneState(id)
        Check(view.state == "OPAQUE_BLOCK_ALL" and view.localOwned == false
            and view.pending == nil, "opaque tombstone exposed pending or ownership: " .. id)
        local ok, why = Catalog().Put(S.LocalBuild(id, 1), {source="local"})
        Check(ok == false and why == "TOMBSTONE_RESERVATION",
            "opaque reservation accepted a row: " .. id)
    end
    Check(S.Encode({db.syncTombstones.scalar, db.syncTombstones.flag,
        db.syncTombstones.text, db.syncTombstones.payload}) == bytes
        and db.syncTombstones.meta == hostile,
        "opaque tombstones were rewritten")
end)

Case("TMB-03", "2,049 tombstones fail the whole root in every order", function()
    local function Fixture(order)
        local tombstones = {}
        local ids = {}
        for index = 1, 2049 do ids[index] = "tmb03-" .. index end
        if order == "reverse" then
            local reversed = {}
            for index = #ids, 1, -1 do reversed[#reversed + 1] = ids[index] end
            ids = reversed
        elseif order == "shuffled" then
            local shuffled, seed = {}, 7
            for index = 1, #ids do
                seed = (seed * 1103515245 + 12345) % 2147483648
                local slot = (seed % index) + 1
                shuffled[index] = shuffled[slot]
                shuffled[slot] = ids[index]
            end
            ids = shuffled
        end
        for _, id in ipairs(ids) do tombstones[id] = LocalTomb(1) end
        return S.Database({valid=S.Build("valid", 2, 0)}, tombstones)
    end
    for _, order in ipairs({"forward", "reverse", "shuffled"}) do
        local db = Fixture(order)
        S.Bind(db)
        Check(S.Root().state == "ROOT_INVALIDATED"
            and S.Root().reason == "TOMBSTONE_SET_LIMIT",
            "2,049 tombstones did not fail the root in " .. order .. " order: "
                .. tostring(S.Root().reason))
        Check(Catalog().Count() == 0 and Catalog().Get("valid") == nil,
            "over-limit tombstone set exposed partial authority")
        Check(S.Count(db.syncTombstones) == 2049, "tombstones were pruned")
        S.Reload()
        S.Bind(db)
        Check(S.Root().state == "ROOT_INVALIDATED", "reload chose a winner subset")
    end
end)

Case("TMB-04", "durable pending markers are opaque; pending is session-only", function()
    local persisted = LocalTomb(1)
    persisted.pending = true
    local db = S.Database({}, {tmb04=persisted})
    S.Bind(db)
    local view = Catalog().TombstoneState("tmb04")
    Check(view.state == "OPAQUE_BLOCK_ALL" and view.pending == nil
        and view.localOwned == false,
        "durable pending marker granted pending or delete authority")
    Check(persisted.pending == true, "durable pending marker was rewritten")
end)

Case("TMB-05", "row to tombstone is one prepared root publish", function()
    local db = S.Database({tmb05=S.LocalBuild("tmb05", 3)})
    S.Bind(db)
    local catalog = Catalog()
    local generation = S.Root().generation
    local observed
    local unsubscribe = Nexus.Revisions.Subscribe(
        Nexus.Revisions.BUILD_LIBRARY_CHANGED, function()
            observed = {
                row=catalog.Get("tmb05"),
                tombstone=catalog.TombstoneState("tmb05").state,
                count=catalog.Count(),
            }
        end)
    Check(catalog.SetTombstone("tmb05", LocalTomb(), {source="local"}))
    unsubscribe()
    Check(observed and observed.row == nil and observed.tombstone == "CURRENT_DENY"
        and observed.count == 0,
        "notification observed an intermediate catalog state")
    Check(S.Root().generation == generation + 1,
        "row-to-tombstone did not publish exactly one generation")
    Check(db.communityBuilds.tmb05 == nil, "overlay slot survived the tombstone")
end)

Case("TMB-06", "failure and termination boundaries preserve one coherent state", function()
    local db = S.Database({tmb06=S.LocalBuild("tmb06", 3)})
    S.Bind(db)
    local catalog = Catalog()
    local rawBytes = S.Encode(db)
    local generation = S.Root().generation
    catalog.InstallFaultInjector(function(boundary)
        if boundary == "before-commit" then error("injected before commit") end
    end)
    local ok = catalog.SetTombstone("tmb06", LocalTomb(), {source="local"})
    Check(ok == false and S.Encode(db) == rawBytes
        and S.Root().generation == generation and catalog.Get("tmb06") ~= nil,
        "pre-commit failure changed raw or public state")
    catalog.InstallFaultInjector(function(boundary)
        if boundary == "after-raw-write" then error("injected after raw write") end
    end)
    ok = catalog.SetTombstone("tmb06", LocalTomb(), {source="local"})
    Check(ok == false and S.Root().state == "ROOT_INVALIDATED",
        "protected failure did not publish the invalid sentinel")
    Check(catalog.Get("tmb06") == nil and catalog.Count() == 0,
        "invalid sentinel served stale products")
    Check(type(db.syncTombstones.tmb06) == "table" and db.communityBuilds.tmb06 == nil,
        "durable state is not one complete new bundle")
    catalog.InstallFaultInjector(nil)
    S.Reload()
    S.Bind(db)
    Check(Nexus.BuildCatalog.TombstoneState("tmb06").state == "RELOADED_BLOCK_ALL",
        "reload did not admit the complete durable state from cursor zero")
    -- notification failure keeps the new root final
    local db2 = S.Database({tmb06b=S.LocalBuild("tmb06b", 3)})
    S.Bind(db2)
    local unsubscribe = Nexus.Revisions.Subscribe(
        Nexus.Revisions.BUILD_LIBRARY_CHANGED, function() error("subscriber failed") end)
    Nexus.BuildCatalog.InstallFaultInjector(function(boundary)
        if boundary == "notify" then error("injected notification failure") end
    end)
    local before = Nexus.BuildCatalog.DebugStats().notificationFailures or 0
    Check(Nexus.BuildCatalog.SetTombstone("tmb06b", LocalTomb(), {source="local"}),
        "notification failure undid the mutation")
    unsubscribe()
    Nexus.BuildCatalog.InstallFaultInjector(nil)
    Check(Nexus.BuildCatalog.TombstoneState("tmb06b").state == "CURRENT_DENY"
        and db2.syncTombstones.tmb06b ~= nil
        and Nexus.BuildCatalog.DebugStats().notificationFailures == before + 1,
        "notification failure was not recorded as replay-only")
end)

Case("TMB-07", "backing replacement invalidates suppression until recovery", function()
    local db = S.Database({tmb07=S.LocalBuild("tmb07", 3)})
    S.Bind(db)
    Check(Catalog().SetTombstone("tmb07", LocalTomb(), {source="local"}))
    db.syncTombstones = S.DeepCopy(db.syncTombstones)
    Check(S.Root().state == "ROOT_INVALIDATED",
        "tombstone backing replacement was not detected")
    Check(Catalog().TombstoneState("tmb07").state == "NONE"
        and Catalog().Count() == 0,
        "invalidated root served tombstone suppression")
    S.Bind(db)
    Check(S.Root().state == "ROOT_ADMITTED"
        and Catalog().TombstoneState("tmb07").state == "RELOADED_BLOCK_ALL",
        "explicit recovery did not readmit from cursor zero")
end)

Case("TMB-08", "replay, refresh, local claim, and remote resurrection", function()
    local db = S.Database({tmb08=S.LocalBuild("tmb08", 3)})
    S.Bind(db)
    local catalog = Catalog()
    local tomb = LocalTomb()
    Check(catalog.SetTombstone("tmb08", tomb, {source="local"}))
    local generation = S.Root().generation
    local okReplay, whyReplay = catalog.SetTombstone("tmb08", LocalTomb(), {source="local"})
    Check(okReplay == true and whyReplay == "TOMBSTONE_REPLAY_NOOP"
        and S.Root().generation == generation,
        "exact replay was not a no-op: " .. tostring(whyReplay))
    local okRefresh, whyRefresh = catalog.SetTombstone("tmb08", LocalTomb(now + 5),
        {source="local"})
    Check(okRefresh == false and whyRefresh == "TOMBSTONE_REPLAY_CONFLICT"
        and catalog.TombstoneState("tmb08").stamp == now,
        "changed replay refreshed the tombstone: " .. tostring(whyRefresh))
    -- remote resurrection always fails closed
    local okRemote, whyRemote = catalog.Put(S.Build("tmb08", 3, 0, {lastModified=now + 9}),
        {source="remote", sender="Boganic-Ebonhold"})
    Check(okRemote == false and whyRemote == "TOMBSTONE_RESERVATION",
        "remote row resurrected a tombstone: " .. tostring(whyRemote))
    -- copied, fabricated, stale, and twice-used claims refuse
    local claim = assert(catalog.BeginTombstoneReadmissionClaim("tmb08"))
    local copied = {}
    for key, value in pairs(claim) do copied[key] = value end
    local okCopy, whyCopy = catalog.PutWithClaim(copied, S.LocalBuild("tmb08", 2),
        {source="local"})
    Check(okCopy == false and whyCopy == "INVALID_CLAIM", "copied claim accepted")
    Check(catalog.Put(S.Build("tmb08-other", 1, 0)))
    local okStale, whyStale = catalog.PutWithClaim(claim, S.LocalBuild("tmb08", 2),
        {source="local"})
    Check(okStale == false and whyStale == "STALE_CLAIM", "stale claim accepted: "
        .. tostring(whyStale))
    claim = assert(catalog.BeginTombstoneReadmissionClaim("tmb08"))
    Check(catalog.PutWithClaim(claim, S.LocalBuild("tmb08", 2), {source="local"}),
        "trusted local claim could not readmit")
    Check(S.State("tmb08").state == "READMITTED"
        and catalog.TombstoneState("tmb08").state == "NONE"
        and db.syncTombstones.tmb08 == nil and db.communityBuilds.tmb08 ~= nil,
        "readmission did not atomically replace the tombstone")
    local okTwice, whyTwice = catalog.PutWithClaim(claim, S.LocalBuild("tmb08", 2),
        {source="local"})
    Check(okTwice == false and whyTwice == "INVALID_CLAIM", "claim consumed twice")
    local okNone, whyNone = catalog.BeginTombstoneReadmissionClaim("tmb08")
    Check(okNone == nil and whyNone == "TOMBSTONE_RESERVATION_ABSENT",
        "claim issued without a reservation")
end)

Case("TMB-09", "only current-session tombstones retire by trusted age", function()
    local persisted = {schemaVersion=1, typedId={luaType="string", exactValue="old"},
        ownerKey="boganic@ebonhold", sourceKind="local", sourceIdentity="local",
        targetRowGeneration=1, targetRowProvenance={author="Boganic"},
        receiptRevision=1, receiptAtServerTime=now - 400 * DAY,
        remoteStampEvidence=now - 400 * DAY}
    local db = S.Database({tmb09=S.LocalBuild("tmb09", 3)}, {old=persisted})
    S.Bind(db)
    local catalog = Catalog()
    Check(catalog.SetTombstone("tmb09", LocalTomb(), {source="local"}))
    local function Retire(id)
        local handle = catalog.BeginCatalogMaintenance({database=db, operation="retention"})
        Check(handle, "maintenance handle unavailable")
        local ok, why = catalog.MaintenanceRetireTombstone(handle, id)
        if ok then
            local committed, commitWhy = catalog.CommitMaintenance(handle)
            return committed, commitWhy
        end
        catalog.CancelMaintenance(handle)
        return ok, why
    end
    local okEarly, whyEarly = Retire("tmb09")
    Check(okEarly == false and whyEarly == "TOMBSTONE_NOT_EXPIRED",
        "current tombstone retired early: " .. tostring(whyEarly))
    now = now + 180 * DAY + 1
    local okAged = Retire("tmb09")
    Check(okAged and catalog.TombstoneState("tmb09").state == "NONE"
        and db.syncTombstones.tmb09 == nil,
        "aged current-session tombstone did not retire")
    local okReloaded, whyReloaded = Retire("old")
    Check(okReloaded == false and whyReloaded == "TOMBSTONE_RESERVATION_BLOCK_ALL"
        and db.syncTombstones.old == persisted,
        "reloaded tombstone expired: " .. tostring(whyReloaded))
    -- clock rollback makes trusted time unavailable for the session
    Check(catalog.Put(S.LocalBuild("tmb09b", 2), {source="local"}))
    Check(catalog.SetTombstone("tmb09b", LocalTomb(now), {source="local"}))
    now = now - 10
    Check(catalog.TrustedServerTime() == nil, "clock rollback was trusted")
    now = now + 200 * DAY
    local okRollback, whyRollback = Retire("tmb09b")
    Check(okRollback == false and whyRollback == "TIME_UNTRUSTED",
        "untrusted clock retired a tombstone: " .. tostring(whyRollback))
end)

-- Eviction barriers ---------------------------------------------------------

local function Evict(db, id)
    local catalog = Catalog()
    local handle = catalog.BeginCatalogMaintenance({database=db, operation="retention"})
    Check(handle, "maintenance handle unavailable")
    local ok, why = catalog.MaintenanceEvictOverlay(handle, id)
    if not ok then catalog.CancelMaintenance(handle); return ok, why end
    return catalog.CommitMaintenance(handle)
end

local function Expire(db, id)
    local catalog = Catalog()
    local handle = catalog.BeginCatalogMaintenance({database=db, operation="retention"})
    Check(handle, "maintenance handle unavailable")
    local ok, why = catalog.MaintenanceExpireBarrier(handle, id)
    if not ok then catalog.CancelMaintenance(handle); return ok, why end
    return catalog.CommitMaintenance(handle)
end

Case("EVC-01", "exact typed keys: numeric 1 and string \"1\" are distinct", function()
    local db = S.Database({[1]=S.Build(1, 2, 0, {autoDps=true}),
        ["1"]=S.Build("1", 2, 0, {autoDps=true})})
    S.Bind(db)
    local catalog = Catalog()
    Check(Evict(db, 1), "numeric eviction refused")
    Check(catalog.BarrierState(1).blocked == true
        and catalog.BarrierState("1").blocked == false,
        "typed barrier keys were coerced")
    Check(db.communityBuilds[1] == nil and db.communityBuilds["1"] ~= nil
        and type(db.communityRetentionEvictions[1]) == "table",
        "eviction touched the wrong typed slot")
    local _, _, advisory = catalog.AllocationOccupancy(1)
    Check(advisory.blocked == true, "barrier-only ID reported vacant")
    Check(S.State(1).occupancy == "BLOCKED" and S.State("1").occupancy == "OCCUPIED",
        "occupancy verdicts disagree with typed reservations")
    local ok, why = catalog.Put(S.Build(1, 2, 0, {lastModified=99}),
        {source="remote", sender="Peer-Ebonhold"})
    Check(ok == false and why == "BARRIER_RESERVATION", "barrier admitted an inbound row")
end)

Case("EVC-02", "legacy markers load as opaque block-all", function()
    local db = S.Database({}, {}, {communityRetentionEvictions={
        legacyTable={revision=200, recordedAt=1}, legacyNumber=200,
    }})
    S.Bind(db)
    for _, id in ipairs({"legacyTable", "legacyNumber"}) do
        Check(Catalog().BarrierState(id).state == "BARRIER_OPAQUE_BLOCK_ALL",
            "legacy marker was interpreted: " .. id)
        local ok = Catalog().Put(S.Build(id, 1, 0, {lastModified=999}),
            {source="remote", sender="Peer-Ebonhold"})
        Check(ok == false, "legacy marker admitted a newer revision: " .. id)
    end
    now = now + 400 * DAY
    local ok, why = Expire(db, "legacyTable")
    Check(ok == false and why == "BARRIER_RESERVATION_BLOCK_ALL",
        "opaque barrier expired: " .. tostring(why))
end)

Case("EVC-03", "malformed, future, unknown, metatable, and mismatched barriers", function()
    local db = S.Database({}, {}, {communityRetentionEvictions={
        text="x",
        future={schemaVersion=2, typedId={luaType="string", exactValue="future"}},
        unknown={schemaVersion=1, typedId={luaType="string", exactValue="unknown"},
            evictedCatalogGeneration=1, evictedSourceIdentity="overlay",
            evictedProvenanceIdentity="p", receiptRevision=1,
            receiptAtServerTime=now, extra=true},
        meta=setmetatable({schemaVersion=1}, {}),
        mismatch={schemaVersion=1, typedId={luaType="string", exactValue="other"},
            evictedCatalogGeneration=1, evictedSourceIdentity="overlay",
            evictedProvenanceIdentity="p", receiptRevision=1,
            receiptAtServerTime=now},
    }})
    S.Bind(db)
    for _, id in ipairs({"text", "future", "unknown", "meta", "mismatch"}) do
        Check(Catalog().BarrierState(id).state == "BARRIER_OPAQUE_BLOCK_ALL",
            "barrier was interpreted as current: " .. id)
    end
    local fatal = S.Database({}, {}, {communityRetentionEvictions={[{}]=1}})
    S.Bind(fatal)
    Check(S.Root().state == "ROOT_INVALIDATED", "unrepresentable barrier key was tolerated")
end)

Case("EVC-04", "exact replay is a no-op; conflicts stay deny-only", function()
    local db = S.Database({evc04=S.Build("evc04", 2, 0, {autoDps=true})})
    S.Bind(db)
    Check(Evict(db, "evc04"))
    local generation = S.Root().generation
    local barrier = db.communityRetentionEvictions.evc04
    local okReplay = Evict(db, "evc04")
    Check(okReplay and S.Root().generation == generation
        and db.communityRetentionEvictions.evc04 == barrier,
        "exact replay mutated the barrier")
end)

Case("EVC-05", "reload classifies exact V1 as reloaded and others as opaque", function()
    local db = S.Database({evc05=S.Build("evc05", 2, 0, {autoDps=true})}, {}, {
        communityRetentionEvictions={legacy={revision=1, recordedAt=1}}})
    S.Bind(db)
    Check(Evict(db, "evc05"))
    Check(Catalog().BarrierState("evc05").state == "BARRIER_CURRENT_DENY")
    S.Reload()
    S.Bind(db)
    Check(Nexus.BuildCatalog.BarrierState("evc05").state == "BARRIER_RELOADED_BLOCK_ALL"
        and Nexus.BuildCatalog.BarrierState("legacy").state == "BARRIER_OPAQUE_BLOCK_ALL",
        "reload recreated session barrier authority")
end)

Case("EVC-06", "30-day expiry uses trusted local observation only", function()
    local db = S.Database({evc06=S.Build("evc06", 2, 0, {autoDps=true})})
    S.Bind(db)
    local created = now
    Check(Evict(db, "evc06"))
    now = created + 30 * DAY - 1
    local okEarly, whyEarly = Expire(db, "evc06")
    Check(okEarly == false and whyEarly == "BARRIER_NOT_EXPIRED",
        "barrier expired early: " .. tostring(whyEarly))
    now = created + 30 * DAY
    Check(Expire(db, "evc06") and db.communityRetentionEvictions.evc06 == nil,
        "current barrier did not expire at 30 days")
    -- reloaded barriers restart their interval at each reload
    Check(Catalog().Put(S.Build("evc06b", 2, 0, {autoDps=true})))
    Check(Evict(db, "evc06b"))
    S.Reload()
    local reloadedAt = now
    S.Bind(db)
    now = reloadedAt + 30 * DAY - 1
    local okReloadEarly = Expire(db, "evc06b")
    Check(okReloadEarly == false, "reloaded barrier expired before its own interval")
    S.Reload()
    now = now + 20 * DAY
    S.Bind(db)
    now = now + 15 * DAY
    local okRestart = Expire(db, "evc06b")
    Check(okRestart == false, "second reload did not restart the interval")
    now = now + 30 * DAY
    Check(Expire(db, "evc06b"), "reloaded barrier never expired")
end)

Case("EVC-07", "authenticated inbound rows never clear a barrier", function()
    local db = S.Database({evc07=S.Build("evc07", 2, 0, {autoDps=true})})
    S.Bind(db)
    Check(Evict(db, "evc07"))
    for _, stamp in ipairs({5, 10, 999999}) do
        local ok = Catalog().Put(S.Build("evc07", 2, 0, {lastModified=stamp}),
            {source="remote", sender="Peer-Ebonhold"})
        Check(ok == false and db.communityBuilds.evc07 == nil,
            "authenticated inbound revision cleared a barrier: " .. stamp)
    end
    Check(Catalog().BarrierState("evc07").blocked == true, "barrier was cleared")
end)

Case("EVC-08", "2,049 barriers are root-fatal", function()
    local barriers = {}
    for index = 1, 2049 do barriers["evc08-" .. index] = {revision=index, recordedAt=1} end
    local db = S.Database({valid=S.Build("valid", 1, 0)}, {},
        {communityRetentionEvictions=barriers})
    S.Bind(db)
    Check(S.Root().state == "ROOT_INVALIDATED" and S.Root().reason == "BARRIER_SET_LIMIT",
        "2,049 barriers did not fail the root: " .. tostring(S.Root().reason))
    Check(S.Count(db.communityRetentionEvictions) == 2049, "barriers were pruned")
end)

-- Allocation claims -----------------------------------------------------------

Case("ALC-01", "advisory vacancy never authorizes a write", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Catalog()
    local _, _, advisory = catalog.AllocationOccupancy("alc01")
    Check(advisory.blocked == false, "fresh typed ID was blocked")
    local claim = assert(catalog.BeginAllocationClaim("alc01"))
    Check(catalog.Put(S.Build("alc01-other", 1, 0)), "intervening mutation refused")
    local ok, why = catalog.PutWithClaim(claim, S.Build("alc01", 1, 0))
    Check(ok == false and why == "STALE_CLAIM", "stale claim authorized a write: "
        .. tostring(why))
    claim = assert(catalog.BeginAllocationClaim("alc01"))
    Check(catalog.PutWithClaim(claim, S.Build("alc01", 1, 0)), "fresh claim refused")
    -- create/remove/create ABA: a stale occupancy result cannot reuse the slot
    local stale = select(3, catalog.AllocationOccupancy("alc01"))
    Check(catalog.RemoveOverlay("alc01"))
    local vacant = select(3, catalog.AllocationOccupancy("alc01"))
    Check(stale.blocked == true and vacant.blocked == false
        and vacant.generation ~= stale.generation,
        "occupancy did not bind generation")
end)

Case("ALC-02", "copied, fabricated, mutated, wrong-ID, and reused claims refuse", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Catalog()
    local claim = assert(catalog.BeginAllocationClaim("alc02"))
    local copied = {}
    for key, value in pairs(claim) do copied[key] = value end
    Check(select(2, catalog.PutWithClaim(copied, S.Build("alc02", 1, 0))) == "INVALID_CLAIM",
        "copied claim accepted")
    Check(select(2, catalog.PutWithClaim({typedKey="s:5:alc02"}, S.Build("alc02", 1, 0)))
        == "INVALID_CLAIM", "fabricated claim accepted")
    claim.typedKey = "s:5:other"
    Check(select(2, catalog.PutWithClaim(claim, S.Build("other", 1, 0))) == "TYPED_ID_MISMATCH",
        "mutated claim field selected another ID")
    Check(select(2, catalog.PutWithClaim(claim, S.Build("alc02-wrong", 1, 0)))
        == "TYPED_ID_MISMATCH", "wrong-ID claim accepted")
    Check(catalog.PutWithClaim(claim, S.Build("alc02", 1, 0)), "exact claim refused")
    Check(select(2, catalog.PutWithClaim(claim, S.Build("alc02", 1, 0))) == "INVALID_CLAIM",
        "claim consumed twice")
    local second = assert(catalog.BeginAllocationClaim("alc02b"))
    local okBusy, whyBusy = catalog.BeginAllocationClaim("alc02c")
    Check(okBusy == nil and whyBusy == "CLAIM_ACTIVE", "two claims were active")
    Check(catalog.CancelAllocationClaim(second))
    Check(select(2, catalog.PutWithClaim(second, S.Build("alc02b", 1, 0))) == "INVALID_CLAIM",
        "cancelled claim accepted")
end)

-- Mutation transactions -----------------------------------------------------

Case("MUT-03", "row replacement requires complete readmission", function()
    local db = S.Database({mut03=S.Build("mut03", 3, 0)})
    S.Bind(db)
    local catalog = Catalog()
    local oldKey = "100000x1,100001x1,100002x1"
    Check(catalog.FindExactFingerprintId(oldKey) == "mut03")
    Check(catalog.Put(S.Build("mut03", 2, 0, {firstSpell=300000, lastModified=20})))
    local replacement = S.Build("mut03", 2, 0, {lastModified=20})
    replacement.echoes = S.Echoes(2, 0, {firstSpell=300000})
    Check(catalog.Put(replacement))
    Check(catalog.FindExactFingerprintId(oldKey) == nil
        and catalog.FindExactFingerprintId("300000x1,300001x1") == "mut03",
        "replacement inherited a stale index membership")
    Check(catalog.Get("mut03").echoCount == 2, "replacement inherited stale status")
end)

Case("MUT-04", "backing-table replacement fails the token", function()
    local db = S.Database({mut04=S.Build("mut04", 3, 0)})
    S.Bind(db)
    db.communityBuilds = S.DeepCopy(db.communityBuilds)
    Check(S.Root().state == "ROOT_INVALIDATED" and Catalog().Get("mut04") == nil,
        "overlay replacement was served from a stale root")
    local ok, why = Catalog().Put(S.Build("mut04b", 1, 0))
    Check(ok == false and why == "ROOT_INVALIDATED", "invalid root accepted a write")
    S.Bind(db)
    Check(Catalog().Get("mut04") ~= nil, "explicit recovery did not restart at zero")
end)

Case("MUT-05", "provenance collision refuses without tie-break", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Catalog()
    Check(catalog.Put(S.Build("mut05", 3, 0), {source="remote", sender="Peer-Ebonhold"}))
    local ok, why = catalog.Put(S.Build("mut05", 3, 0, {ownerKey="other@ebonhold",
        author="Other", lastModified=99, title="Newer title"}),
        {source="remote", sender="Other-Ebonhold"})
    Check(ok == false and why == "PROVENANCE_COLLISION",
        "different verified owner replaced a row by newer stamp: " .. tostring(why))
    Check(catalog.Get("mut05").author == "Peer", "collision changed the row")
end)

Case("MUT-06", "explicit readmission publishes exactly one generation", function()
    local db = S.Database({mut06=S.Build("mut06", 3, 0)})
    S.Bind(db)
    local generation = S.Root().generation
    Check(Catalog().Put(S.Build("mut06", 4, 0, {lastModified=11})))
    Check(S.Root().generation == generation + 1 and S.State("mut06").state == "READMITTED",
        "readmission did not publish exactly once")
end)

Case("MUT-07", "reload reproduces the complete proof deterministically", function()
    local overlay = {}
    for index = 1, 50 do overlay["mut07-" .. index] = S.Build("mut07-" .. index, index % 7 + 1, 0) end
    local db = S.Database(overlay)
    S.Bind(db)
    local before = {count=Catalog().Count(), status=Catalog().Status(),
        exact=Catalog().FindExactFingerprintId("100000x1")}
    S.Reload()
    S.Bind(db)
    local after = {count=Nexus.BuildCatalog.Count(), status=Nexus.BuildCatalog.Status(),
        exact=Nexus.BuildCatalog.FindExactFingerprintId("100000x1")}
    Check(before.count == after.count and before.exact == after.exact
        and before.status.availableCount == after.status.availableCount,
        "reload produced a different proof")
end)

Case("ROOT-01", "one public pointer, no mixed generations", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Catalog()
    for index = 1, 20 do
        Check(catalog.Put(S.Build("root01-" .. index, 1, 0)))
        local generation = S.Root().generation
        local count, status = catalog.Count(), catalog.Status()
        Check(count == index and status.availableCount == index
            and S.Root().generation == generation,
            "count, status, and generation disagree")
    end
end)

-- Exhaustive transition table -------------------------------------------------

Case("TRN-01", "row-state transition table: legal edges only", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Catalog()
    local function Prepare(state)
        local id = "trn-" .. state:lower()
        if state == "UNADMITTED" then
            return id
        elseif state == "ADMITTED" then
            db.communityBuilds[id] = S.LocalBuild(id, 2)
        elseif state == "INVALIDATED" then
            db.communityBuilds[id] = S.LocalBuild(id, 90)
        elseif state == "READ_ONLY_FUTURE_SCHEMA" then
            db.communityBuilds[id] = S.LocalBuild(id, 2, {schemaVersion=2})
        elseif state == "TOMBSTONED" then
            db.communityBuilds[id] = S.LocalBuild(id, 2)
        end
        return id
    end
    local states = {"UNADMITTED", "ADMITTED", "INVALIDATED",
        "READ_ONLY_FUTURE_SCHEMA", "TOMBSTONED", "READMITTED"}
    local ids = {}
    for _, state in ipairs(states) do ids[state] = Prepare(state) end
    S.Bind(db)
    catalog = Catalog()
    Check(catalog.SetTombstone(ids.TOMBSTONED, LocalTomb(), {source="local"}))
    Check(catalog.Put(S.LocalBuild(ids.READMITTED, 3), {source="local"}))
    Check(catalog.Put(S.LocalBuild(ids.READMITTED, 4, {lastModified=12}), {source="local"}))
    local expected = {
        UNADMITTED={state="UNADMITTED"},
        ADMITTED={state="ADMITTED"},
        INVALIDATED={state="INVALIDATED"},
        READ_ONLY_FUTURE_SCHEMA={state="READ_ONLY_FUTURE_SCHEMA"},
        TOMBSTONED={state="TOMBSTONED"},
        READMITTED={state="READMITTED"},
    }
    for state, id in pairs(ids) do
        Check(S.State(id).state == expected[state].state,
            "fixture for " .. state .. " reached " .. tostring(S.State(id).state))
    end
    -- Operation matrix: {operation, from -> expected to}
    local matrix = {
        {name="local put", op=function(id) return catalog.Put(S.LocalBuild(id, 5,
            {lastModified=50}), {source="local"}) end,
            UNADMITTED="ADMITTED", ADMITTED="READMITTED", INVALIDATED="READMITTED",
            READ_ONLY_FUTURE_SCHEMA="READ_ONLY_FUTURE_SCHEMA", TOMBSTONED="TOMBSTONED",
            READMITTED="READMITTED"},
        {name="remote put", op=function(id) return catalog.Put(S.Build(id, 5, 0,
            {lastModified=60}), {source="remote", sender="Peer-Ebonhold"}) end,
            UNADMITTED="ADMITTED", ADMITTED="PROVENANCE", INVALIDATED="READMITTED",
            READ_ONLY_FUTURE_SCHEMA="READ_ONLY_FUTURE_SCHEMA", TOMBSTONED="TOMBSTONED",
            READMITTED="PROVENANCE"},
        {name="remove overlay", op=function(id) return catalog.RemoveOverlay(id) end,
            UNADMITTED="UNADMITTED", ADMITTED="UNADMITTED", INVALIDATED="INVALIDATED",
            READ_ONLY_FUTURE_SCHEMA="READ_ONLY_FUTURE_SCHEMA", TOMBSTONED="TOMBSTONED",
            READMITTED="UNADMITTED"},
        {name="local tombstone", op=function(id) return catalog.SetTombstone(id,
            LocalTomb(now + 1), {source="local"}) end,
            UNADMITTED="UNADMITTED", ADMITTED="TOMBSTONED", INVALIDATED="INVALIDATED",
            READ_ONLY_FUTURE_SCHEMA="READ_ONLY_FUTURE_SCHEMA", TOMBSTONED="TOMBSTONED",
            READMITTED="TOMBSTONED"},
    }
    for _, row in ipairs(matrix) do
        for _, state in ipairs(states) do
            local prepared = S.Database({})
            S.Bind(prepared)
            catalog = Catalog()
            db = prepared
            local id = "trn-" .. state:lower()
            if state ~= "UNADMITTED" then
                if state == "INVALIDATED" then
                    prepared.communityBuilds[id] = S.LocalBuild(id, 90)
                    S.Bind(prepared)
                elseif state == "READ_ONLY_FUTURE_SCHEMA" then
                    prepared.communityBuilds[id] = S.LocalBuild(id, 2, {schemaVersion=2})
                    S.Bind(prepared)
                else
                    Check(catalog.Put(S.LocalBuild(id, 2), {source="local"}))
                    if state == "READMITTED" then
                        Check(catalog.Put(S.LocalBuild(id, 3, {lastModified=12}),
                            {source="local"}))
                    elseif state == "TOMBSTONED" then
                        Check(catalog.SetTombstone(id, LocalTomb(), {source="local"}))
                    end
                end
            end
            catalog = Catalog()
            Check(S.State(id).state == state, row.name .. ": fixture " .. state
                .. " reached " .. tostring(S.State(id).state))
            local generation = S.Root().generation
            local ok, why = row.op(id)
            local target = row[state]
            local after = S.State(id).state
            if target == "PROVENANCE" then
                Check(ok == false and why == "PROVENANCE_COLLISION" and after == state
                    and S.Root().generation == generation,
                    row.name .. " from " .. state .. " should refuse as provenance collision, got "
                        .. tostring(why) .. "/" .. tostring(after))
            elseif target == state then
                Check(after == state and S.Root().generation == generation
                    or (ok and after == state),
                    row.name .. " from " .. state .. " changed state or generation illegally: "
                        .. tostring(ok) .. "/" .. tostring(why) .. "/" .. tostring(after))
            else
                Check(ok and after == target and S.Root().generation == generation + 1,
                    row.name .. " from " .. state .. " expected " .. target .. " got "
                        .. tostring(after) .. " (" .. tostring(why) .. ")")
            end
        end
    end
end)

S.Finish("catalog authority tombstone, barrier, claim, and mutation matrix")
