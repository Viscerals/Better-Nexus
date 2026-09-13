-- Package B / issue #22 catalog authority: tombstone reservations, eviction
-- barriers, allocation claims, mutation transactions, and the exhaustive
-- row-state transition table (TMB, EVC, ALC, MUT, ROOT, TRN).
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

-- Fixture assertions inspect terminal catalog transactions. This uses the real
-- admission scheduler and never turns a pending acknowledgement into success.
local function AwaitMutation(ok, why, ticket)
    return S.AwaitCatalogMutation(ok, why, ticket, "tombstone fixture mutation")
end


local DAY = 24 * 60 * 60
local now = 2000000000
time = function() return now end

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
    Check(AwaitMutation(catalog.SetTombstone("tmb01", LocalTomb(), {source="local"})),
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
    Check(S.Durable(db).tmb01 == nil and type(S.Durable(db, "syncTombstones").tmb01) == "table"
        and S.Durable(db, "syncTombstones").tmb01.schemaVersion == 1,
        "row-to-tombstone did not publish the V1 durable shape")
    local legacyState = S.State("legacy")
    Check(legacyState.reservation == "TOMBSTONE_OPAQUE_BLOCK_ALL"
        and catalog.TombstoneState("legacy").localOwned == false,
        "legacy tombstone regained owner authority")
    Check(S.Durable(db, "syncTombstones").legacy == legacy and legacy.ownerVerified == true,
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
        local ok, why = AwaitMutation(Catalog().Put(S.LocalBuild(id, 1), {source="local"}))
        Check(ok == false and why == "TOMBSTONE_RESERVATION",
            "opaque reservation accepted a row: " .. id)
    end
    Check(S.Encode({S.Durable(db, "syncTombstones").scalar, S.Durable(db, "syncTombstones").flag,
        S.Durable(db, "syncTombstones").text, S.Durable(db, "syncTombstones").payload}) == bytes
        and S.Durable(db, "syncTombstones").meta == hostile,
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
    Check(AwaitMutation(catalog.SetTombstone("tmb05", LocalTomb(), {source="local"})))
    unsubscribe()
    Check(observed and observed.row == nil and observed.tombstone == "CURRENT_DENY"
        and observed.count == 0,
        "notification observed an intermediate catalog state")
    Check(S.Root().generation == generation + 1,
        "row-to-tombstone did not publish exactly one generation")
    Check(S.Durable(db).tmb05 == nil, "overlay slot survived the tombstone")
end)

Case("TMB-06", "failure and termination boundaries preserve one coherent state", function()
    local db = S.Database({tmb06=S.LocalBuild("tmb06", 3)})
    S.Bind(db)
    local catalog = Catalog()
    local rawBytes = S.Encode(db)
    local generation = S.Root().generation
    -- Repair Wave 1 (MASTER-RC-002): the only reachable failure boundary is now
    -- precommit, because publication is one callback-free swap after all fallible
    -- preparation. Drift is that real boundary.
    DriftDurableMap(db, "communityBuilds")
    local ok = AwaitMutation(catalog.SetTombstone("tmb06", LocalTomb(), {source="local"}))
    Check(ok == false and S.Encode(db) == rawBytes
        and S.Root().generation == generation,
        "pre-commit failure changed raw or public state")
    Check(S.Root().state == "ROOT_INVALIDATED",
        "drift failure did not publish the invalid sentinel")
    Check(catalog.Get("tmb06") == nil and catalog.Count() == 0,
        "invalid sentinel served stale products")
    Check(S.Encode(db) == rawBytes,
        "a failed mutation left a half-written durable bundle")
    S.Reload()
    S.Bind(db)
    Check(Nexus.BuildCatalog.TombstoneState("tmb06").state == "NONE",
        "reload did not admit the complete unchanged durable state")
    -- notification failure keeps the new root final
    local db2 = S.Database({tmb06b=S.LocalBuild("tmb06b", 3)})
    S.Bind(db2)
    local unsubscribe = Nexus.Revisions.Subscribe(
        Nexus.Revisions.BUILD_LIBRARY_CHANGED, function() error("subscriber failed") end)
    -- Harness-only collaborator substitution: only the notification method is
    -- swapped, so the callback owner identity the production token records is
    -- unchanged and this is a notification failure rather than drift. No
    -- production authority export and no shipped instrumentation.
    local realAdvance = Nexus.Revisions.Advance
    Nexus.Revisions.Advance = function() error("notification collaborator failed") end
    local before = Nexus.BuildCatalog.DebugStats().notificationFailures or 0
    local committed = AwaitMutation(Nexus.BuildCatalog.SetTombstone("tmb06b", LocalTomb(),
        {source="local"}))
    Nexus.Revisions.Advance = realAdvance
    unsubscribe()
    Check(committed, "notification failure undid the mutation")
    Check(Nexus.BuildCatalog.TombstoneState("tmb06b").state == "CURRENT_DENY"
        and S.Durable(db2, "syncTombstones").tmb06b ~= nil
        and Nexus.BuildCatalog.DebugStats().notificationFailures == before + 1,
        "notification failure was not recorded as replay-only")
end)

-- Class 5 terminal 3 -- catalog tombstone notification-only replay (NTF)
--
-- MASTER-RC-015. Governing architecture:
--   line 650: a catalog-root notification fault keeps the new root final,
--             records bounded NOTIFICATION_FAILED, and schedules
--             notification-only replay.
--   lines 2391-2394 and 2550-2630: BuildCatalog owns the atomic tombstone
--             transaction; replay is bound to the published root generation,
--             never reruns raw writes or the authority transaction, and becomes
--             stale after a newer root publishes.
--   line 4743: the tombstone-replacement fixture keeps the new root final,
--             retries notification only, emits no false-success relay, and
--             never replays the mutation.
--
-- Line 628 states the same publication invariant for DPS, evidence, recovery,
-- registry, and provider publication. It is corroborative, not this seam.
-- Line 1598 is not applicable. It specifies the separate StoreMutationTokenV1
-- completion result for Store-owned post-ready mutations.
--
-- The withdrawn citation is recorded here on purpose so no future reader
-- repeats it: an earlier revision of these cases read line 1598 as requiring a
-- notification="PENDING" field on Catalog.RootState(). It does not. Line 1598
-- is one row of core/Store.lua's own exhaustive table (1538-1540), reachable
-- only from STORE_READY for RegisterCurrentCharacter, Retention, and
-- Compaction -- a pipeline that is unimplemented and belongs to MASTER-RC-001.
-- Catalog.SetTombstone is named at 1720-1727 as BuildCatalog's own mutation
-- API, refusing "with a bounded reason" (its actual (bool, string) shape), and
-- never returns a {state=,result=} table. The tombstone replay requirement is
-- fully grounded without 1598, so nothing was lost by withdrawing it: the
-- replay is observable as the delayed Nexus.Revisions.Advance effect itself,
-- which is exactly what NTF-01 asserts.
--
-- TMB-06 above proves only that the commit is not undone and that exactly one
-- NOTIFICATION_FAILED receipt is recorded. Both are independently proved by the
-- not-undone pattern used for terminals 1 and 2, and TMB-06 stays green with
-- every replay and staleness mechanism deleted. It is therefore not a
-- fail-capable oracle for terminal 3. The two cases below are.
--
-- Fault technique: the harness-only Nexus.Revisions.Advance substitution TMB-06
-- already uses, extended to count calls. Only the notification collaborator is
-- swapped, so the callback owner identity the production token records is
-- unchanged and this is a notification failure rather than drift. No production
-- fault-injection export exists or is added.

-- One counting collaborator for both cases. `failures` is how many of the
-- leading calls raise; every later call is delivered to the real Revisions.
local function CountingAdvance(failures)
    local attempts = {}
    local realAdvance = Nexus.Revisions.Advance
    S.pendingRestores[#S.pendingRestores + 1] = function()
        Nexus.Revisions.Advance = realAdvance
    end
    Nexus.Revisions.Advance = function(event, detail)
        attempts[#attempts + 1] = {event=event, reason=detail and detail.reason,
            scope=detail and detail.scope, id=detail and detail.id}
        if #attempts <= failures then
            error("notification collaborator failed")
        end
        return realAdvance(event, detail)
    end
    return attempts, function() Nexus.Revisions.Advance = realAdvance end
end

-- One ordinary turn of the existing shared scheduler -- exactly what the
-- Scheduler frame's OnUpdate handler runs (core/Scheduler.lua Init). No new
-- pump, no new export, and no clock movement, so nothing else in the fixture is
-- perturbed by the dispatch.
local function SchedulerTurn()
    return Nexus.Scheduler.Tick(GetTime())
end

Case("NTF-01",
    "tombstone post-publication failure replays only the failed notification",
function()
    local db = S.Database({ntf01=S.LocalBuild("ntf01", 3)})
    S.Bind(db)
    local catalog = Catalog()
    local attempts, restore = CountingAdvance(1)

    local relayBefore = #H.sentChatMessages
    local committed = AwaitMutation(catalog.SetTombstone("ntf01", LocalTomb(), {source="local"}))
    Check(committed, "notification failure undid the mutation")
    Check(catalog.TombstoneState("ntf01").state == "CURRENT_DENY"
        and S.Durable(db, "syncTombstones").ntf01 ~= nil,
        "notification failure did not keep the new root final")

    -- Step 1: exactly one attempt has been made at commit time.
    Check(#attempts == 1,
        "expected exactly one notification attempt at commit, got " .. tostring(#attempts))
    local committedRoot = S.Root()
    local committedBytes = S.Encode(db)

    -- Step 2: the replay is not synchronous with the commit. It is dispatched by
    -- a LATER ordinary scheduler turn (architecture 628/650: "schedule").
    SchedulerTurn()
    Check(#attempts == 2,
        "the scheduler turn did not dispatch a notification replay; attempts="
            .. tostring(#attempts))

    -- Step 3: the replay carries the exact failed notification -- same event,
    -- reason, scope, and id -- not a fresh generic refresh.
    Check(attempts[2].event == attempts[1].event
        and attempts[2].reason == attempts[1].reason
        and attempts[2].scope == attempts[1].scope
        and attempts[2].id == attempts[1].id,
        "the replay did not carry the exact failed notification")
    Check(attempts[2].event == Nexus.Revisions.BUILD_LIBRARY_CHANGED
        and attempts[2].scope == "record" and attempts[2].id == "ntf01",
        "the replayed notification lost its exact event, scope, or id: "
            .. tostring(attempts[2].event) .. "/" .. tostring(attempts[2].scope)
            .. "/" .. tostring(attempts[2].id))

    -- Step 4: notification only. No durable byte, serving-root identity (which
    -- moves if and only if servingGeneration moves), catalog generation, durable
    -- bundle generation, committed-mutation revision, or relay changed.
    local replayedRoot = S.Root()
    Check(S.Encode(db) == committedBytes, "the replay changed a durable byte")
    Check(replayedRoot.servingGeneration == committedRoot.servingGeneration
        and replayedRoot.generation == committedRoot.generation
        and replayedRoot.durableBundleGeneration == committedRoot.durableBundleGeneration
        and replayedRoot.committedMutationRevision == committedRoot.committedMutationRevision
        and replayedRoot.state == committedRoot.state,
        "the replay moved a published generation, the serving root, or the root state")
    Check(#H.sentChatMessages == relayBefore, "the replay emitted a relay")

    -- Step 5: bounded. Further ordinary turns deliver no duplicate.
    SchedulerTurn()
    SchedulerTurn()
    Check(#attempts == 2,
        "a later scheduler turn delivered a duplicate notification; attempts="
            .. tostring(#attempts))
    restore()
end)

Case("NTF-03",
    "tombstone notification replay is discarded after a newer root publication",
function()
    local db = S.Database({ntf03a=S.LocalBuild("ntf03a", 3),
        ntf03b=S.LocalBuild("ntf03b", 3)})
    S.Bind(db)
    local catalog = Catalog()
    local attempts, restore = CountingAdvance(1)
    local before = catalog.DebugStats()

    -- Generation G: the notification fails and a replay is queued for it.
    Check(AwaitMutation(catalog.SetTombstone("ntf03a", LocalTomb(), {source="local"})),
        "notification failure undid the mutation")
    Check(#attempts == 1 and attempts[1].id == "ntf03a",
        "the failed notification was not the ntf03a commit")
    local staleGeneration = S.Root().servingGeneration
    Check(catalog.DebugStats().notificationFailures == before.notificationFailures + 1,
        "the failed notification recorded no bounded NOTIFICATION_FAILED receipt")

    -- Generation G+1 publishes BEFORE the queued replay dispatches.
    Check(AwaitMutation(catalog.SetTombstone("ntf03b", LocalTomb(), {source="local"})),
        "the superseding mutation refused")
    Check(#attempts == 2 and attempts[2].id == "ntf03b",
        "the newer publication did not notify for itself")
    Check(S.Root().servingGeneration > staleGeneration,
        "the second commit did not publish a newer serving root")

    -- Architecture 2618-2630: replay "becomes stale if a newer root publishes".
    -- The queued G notification is discarded unnotified, never delivered.
    SchedulerTurn()
    SchedulerTurn()
    Check(#attempts == 2,
        "a replay bound to a superseded generation was delivered; attempts="
            .. tostring(#attempts))
    for index = 3, #attempts do
        Check(attempts[index].id ~= "ntf03a",
            "the stale ntf03a notification was replayed after a newer root published")
    end
    -- NON-VACUITY. Silence alone cannot distinguish "queued, then correctly
    -- discarded as stale" from "never queued at all", and a case that passes
    -- when the whole mechanism is absent is not evidence for the reason it is
    -- named for. DebugStats is the normative catalog diagnostic surface
    -- (architecture line 1721), and it proves an item really was queued for
    -- generation G and really was discarded unnotified.
    Check(catalog.DebugStats().notificationReplaysStale
            == (before.notificationReplaysStale or 0) + 1,
        "no notification replay was queued and discarded as stale; the silence "
            .. "above would then be vacuous. stale="
            .. tostring(catalog.DebugStats().notificationReplaysStale))
    Check(catalog.DebugStats().notificationReplays
            == (before.notificationReplays or 0),
        "a stale-bound replay was counted as delivered")
    Check(catalog.TombstoneState("ntf03a").state == "CURRENT_DENY"
        and catalog.TombstoneState("ntf03b").state == "CURRENT_DENY",
        "the stale discard disturbed a committed mutation")
    restore()
end)

Case("TMB-07", "backing replacement invalidates suppression until recovery", function()
    local db = S.Database({tmb07=S.LocalBuild("tmb07", 3)})
    S.Bind(db)
    Check(AwaitMutation(Catalog().SetTombstone("tmb07", LocalTomb(), {source="local"})))
    S.DriftSelectedMap(db, "syncTombstones", true)
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
    Check(AwaitMutation(catalog.SetTombstone("tmb08", tomb, {source="local"})))
    local generation = S.Root().generation
    local okReplay, whyReplay = AwaitMutation(catalog.SetTombstone("tmb08", LocalTomb(), {source="local"}))
    Check(okReplay == true and whyReplay == "TOMBSTONE_REPLAY_NOOP"
        and S.Root().generation == generation,
        "exact replay was not a no-op: " .. tostring(whyReplay))
    local okRefresh, whyRefresh = AwaitMutation(catalog.SetTombstone("tmb08", LocalTomb(now + 5),
        {source="local"}))
    Check(okRefresh == false and whyRefresh == "TOMBSTONE_REPLAY_CONFLICT"
        and catalog.TombstoneState("tmb08").stamp == now,
        "changed replay refreshed the tombstone: " .. tostring(whyRefresh))
    -- remote resurrection always fails closed
    local okRemote, whyRemote = AwaitMutation(catalog.Put(S.Build("tmb08", 3, 0, {lastModified=now + 9}),
        {source="remote", sender="Boganic-Ebonhold"}))
    Check(okRemote == false and whyRemote == "TOMBSTONE_RESERVATION",
        "remote row resurrected a tombstone: " .. tostring(whyRemote))
    -- copied, fabricated, stale, and twice-used claims refuse
    local claim = assert(catalog.BeginTombstoneReadmissionClaim("tmb08"))
    local copied = {}
    for key, value in pairs(claim) do copied[key] = value end
    local okCopy, whyCopy = catalog.PutWithClaim(copied, S.LocalBuild("tmb08", 2),
        {source="local"})
    Check(okCopy == false and whyCopy == "INVALID_CLAIM", "copied claim accepted")
    Check(AwaitMutation(catalog.Put(S.Build("tmb08-other", 1, 0))))
    local okStale, whyStale = catalog.PutWithClaim(claim, S.LocalBuild("tmb08", 2),
        {source="local"})
    Check(okStale == false and whyStale == "STALE_CLAIM", "stale claim accepted: "
        .. tostring(whyStale))
    claim = assert(catalog.BeginTombstoneReadmissionClaim("tmb08"))
    Check(AwaitMutation(catalog.PutWithClaim(claim,
        S.LocalBuild("tmb08", 2), {source="local"})),
        "trusted local claim could not readmit")
    Check(S.State("tmb08").state == "READMITTED"
        and catalog.TombstoneState("tmb08").state == "NONE"
        and S.Durable(db, "syncTombstones").tmb08 == nil and S.Durable(db).tmb08 ~= nil,
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
    Check(AwaitMutation(catalog.SetTombstone("tmb09", LocalTomb(), {source="local"})))
    local function Retire(id)
        local handle = catalog.BeginCatalogMaintenance({database=db, operation="retention"})
        Check(handle, "maintenance handle unavailable")
        local ok, why = catalog.MaintenanceRetireTombstone(handle, id)
        if ok then
            local committed, commitWhy = AwaitMutation(
                catalog.CommitMaintenance(handle))
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
        and S.Durable(db, "syncTombstones").tmb09 == nil,
        "aged current-session tombstone did not retire")
    local okReloaded, whyReloaded = Retire("old")
    Check(okReloaded == false and whyReloaded == "TOMBSTONE_RESERVATION_BLOCK_ALL"
        and S.Durable(db, "syncTombstones").old == persisted,
        "reloaded tombstone expired: " .. tostring(whyReloaded))
    -- clock rollback makes trusted time unavailable for the session
    Check(AwaitMutation(catalog.Put(S.LocalBuild("tmb09b", 2), {source="local"})))
    Check(AwaitMutation(catalog.SetTombstone("tmb09b", LocalTomb(now), {source="local"})))
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
    return AwaitMutation(catalog.CommitMaintenance(handle))
end

local function Expire(db, id)
    local catalog = Catalog()
    local handle = catalog.BeginCatalogMaintenance({database=db, operation="retention"})
    Check(handle, "maintenance handle unavailable")
    local ok, why = catalog.MaintenanceExpireBarrier(handle, id)
    if not ok then catalog.CancelMaintenance(handle); return ok, why end
    return AwaitMutation(catalog.CommitMaintenance(handle))
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
    Check(S.Durable(db)[1] == nil and S.Durable(db)["1"] ~= nil
        and type(S.Durable(db, "communityRetentionEvictions")[1]) == "table",
        "eviction touched the wrong typed slot")
    local _, _, advisory = catalog.AllocationOccupancy(1)
    Check(advisory.blocked == true, "barrier-only ID reported vacant")
    Check(S.State(1).occupancy == "BLOCKED" and S.State("1").occupancy == "OCCUPIED",
        "occupancy verdicts disagree with typed reservations")
    local ok, why = AwaitMutation(catalog.Put(S.Build(1, 2, 0, {lastModified=99}),
        {source="remote", sender="Peer-Ebonhold"}))
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
        local ok = AwaitMutation(Catalog().Put(S.Build(id, 1, 0, {lastModified=999}),
            {source="remote", sender="Peer-Ebonhold"}))
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
    local barrier = S.Durable(db, "communityRetentionEvictions").evc04
    local okReplay = Evict(db, "evc04")
    Check(okReplay and S.Root().generation == generation
        and S.Durable(db, "communityRetentionEvictions").evc04 == barrier,
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
    Check(Expire(db, "evc06") and S.Durable(db, "communityRetentionEvictions").evc06 == nil,
        "current barrier did not expire at 30 days")
    -- reloaded barriers restart their interval at each reload
    Check(AwaitMutation(Catalog().Put(S.Build("evc06b", 2, 0, {autoDps=true}))))
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
        local ok = AwaitMutation(Catalog().Put(S.Build("evc07", 2, 0, {lastModified=stamp}),
            {source="remote", sender="Peer-Ebonhold"}))
        Check(ok == false and S.Durable(db).evc07 == nil,
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
    Check(AwaitMutation(catalog.Put(S.Build("alc01-other", 1, 0))), "intervening mutation refused")
    local ok, why = catalog.PutWithClaim(claim, S.Build("alc01", 1, 0))
    Check(ok == false and why == "STALE_CLAIM", "stale claim authorized a write: "
        .. tostring(why))
    claim = assert(catalog.BeginAllocationClaim("alc01"))
    Check(AwaitMutation(catalog.PutWithClaim(claim, S.Build("alc01", 1, 0))),
        "fresh claim refused")
    -- create/remove/create ABA: a stale occupancy result cannot reuse the slot
    local stale = select(3, catalog.AllocationOccupancy("alc01"))
    Check(AwaitMutation(catalog.RemoveOverlay("alc01")))
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
    Check(AwaitMutation(catalog.PutWithClaim(claim, S.Build("alc02", 1, 0))),
        "exact claim refused")
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
    Check(AwaitMutation(catalog.Put(S.Build("mut03", 2, 0, {firstSpell=300000, lastModified=20}))))
    local replacement = S.Build("mut03", 2, 0, {lastModified=20})
    replacement.echoes = S.Echoes(2, 0, {firstSpell=300000})
    Check(AwaitMutation(catalog.Put(replacement)))
    Check(catalog.FindExactFingerprintId(oldKey) == nil
        and catalog.FindExactFingerprintId("300000x1,300001x1") == "mut03",
        "replacement inherited a stale index membership")
    Check(catalog.Get("mut03").echoCount == 2, "replacement inherited stale status")
end)

Case("MUT-04", "backing-table replacement fails the token", function()
    local db = S.Database({mut04=S.Build("mut04", 3, 0)})
    S.Bind(db)
    DriftDurableMap(db, "communityBuilds")
    Check(S.Root().state == "ROOT_INVALIDATED" and Catalog().Get("mut04") == nil,
        "overlay replacement was served from a stale root")
    local ok, why = AwaitMutation(Catalog().Put(S.Build("mut04b", 1, 0)))
    Check(ok == false and why == "ROOT_INVALIDATED", "invalid root accepted a write")
    S.Bind(db)
    Check(Catalog().Get("mut04") ~= nil, "explicit recovery did not restart at zero")
end)

Case("MUT-05", "provenance collision refuses without tie-break", function()
    local db = S.Database({})
    S.Bind(db)
    local catalog = Catalog()
    Check(AwaitMutation(catalog.Put(S.Build("mut05", 3, 0), {source="remote", sender="Peer-Ebonhold"})))
    local ok, why = AwaitMutation(catalog.Put(S.Build("mut05", 3, 0, {ownerKey="other@ebonhold",
        author="Other", lastModified=99, title="Newer title"}),
        {source="remote", sender="Other-Ebonhold"}))
    Check(ok == false and why == "PROVENANCE_COLLISION",
        "different verified owner replaced a row by newer stamp: " .. tostring(why))
    Check(catalog.Get("mut05").author == "Peer", "collision changed the row")
end)

Case("MUT-06", "explicit readmission publishes exactly one generation", function()
    local db = S.Database({mut06=S.Build("mut06", 3, 0)})
    S.Bind(db)
    local generation = S.Root().generation
    Check(AwaitMutation(Catalog().Put(S.Build("mut06", 4, 0, {lastModified=11}))))
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
        Check(AwaitMutation(catalog.Put(S.Build("root01-" .. index, 1, 0))))
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
            S.SeedDurable(db, "communityBuilds", id, S.LocalBuild(id, 2))
        elseif state == "INVALIDATED" then
            S.SeedDurable(db, "communityBuilds", id, S.LocalBuild(id, 90))
        elseif state == "READ_ONLY_FUTURE_SCHEMA" then
            S.SeedDurable(db, "communityBuilds", id,
                S.LocalBuild(id, 2, {schemaVersion=2}))
        elseif state == "TOMBSTONED" then
            S.SeedDurable(db, "communityBuilds", id, S.LocalBuild(id, 2))
        end
        return id
    end
    local states = {"UNADMITTED", "ADMITTED", "INVALIDATED",
        "READ_ONLY_FUTURE_SCHEMA", "TOMBSTONED", "READMITTED"}
    local ids = {}
    for _, state in ipairs(states) do ids[state] = Prepare(state) end
    S.Bind(db)
    catalog = Catalog()
    Check(AwaitMutation(catalog.SetTombstone(ids.TOMBSTONED, LocalTomb(), {source="local"})))
    Check(AwaitMutation(catalog.Put(S.LocalBuild(ids.READMITTED, 3), {source="local"})))
    Check(AwaitMutation(catalog.Put(S.LocalBuild(ids.READMITTED, 4, {lastModified=12}), {source="local"})))
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
        {name="local put", op=function(id) return AwaitMutation(catalog.Put(S.LocalBuild(id, 5,
            {lastModified=50}), {source="local"})) end,
            UNADMITTED="ADMITTED", ADMITTED="READMITTED", INVALIDATED="READMITTED",
            READ_ONLY_FUTURE_SCHEMA="READ_ONLY_FUTURE_SCHEMA", TOMBSTONED="TOMBSTONED",
            READMITTED="READMITTED"},
        {name="remote put", op=function(id) return AwaitMutation(catalog.Put(S.Build(id, 5, 0,
            {lastModified=60}), {source="remote", sender="Peer-Ebonhold"})) end,
            UNADMITTED="ADMITTED", ADMITTED="PROVENANCE", INVALIDATED="READMITTED",
            READ_ONLY_FUTURE_SCHEMA="READ_ONLY_FUTURE_SCHEMA", TOMBSTONED="TOMBSTONED",
            READMITTED="PROVENANCE"},
        {name="remove overlay", op=function(id) return AwaitMutation(catalog.RemoveOverlay(id)) end,
            UNADMITTED="UNADMITTED", ADMITTED="UNADMITTED", INVALIDATED="INVALIDATED",
            READ_ONLY_FUTURE_SCHEMA="READ_ONLY_FUTURE_SCHEMA", TOMBSTONED="TOMBSTONED",
            READMITTED="UNADMITTED"},
        {name="local tombstone", op=function(id) return AwaitMutation(catalog.SetTombstone(id,
            LocalTomb(now + 1), {source="local"})) end,
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
                    S.SeedDurable(prepared, "communityBuilds", id,
                        S.LocalBuild(id, 90))
                    S.Bind(prepared)
                elseif state == "READ_ONLY_FUTURE_SCHEMA" then
                    S.SeedDurable(prepared, "communityBuilds", id,
                        S.LocalBuild(id, 2, {schemaVersion=2}))
                    S.Bind(prepared)
                else
                    Check(AwaitMutation(catalog.Put(S.LocalBuild(id, 2), {source="local"})))
                    if state == "READMITTED" then
                        Check(AwaitMutation(catalog.Put(S.LocalBuild(id, 3, {lastModified=12}),
                            {source="local"})))
                    elseif state == "TOMBSTONED" then
                        Check(AwaitMutation(catalog.SetTombstone(id, LocalTomb(), {source="local"})))
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
