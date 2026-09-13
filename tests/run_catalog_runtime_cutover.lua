-- Runtime legacy-to-bundle cutover (MASTER-RC-001).
--
-- Architecture 3b5de54f, docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   line 374       `authorityBundle` absent -> LEGACY_BUNDLE_MIGRATION_REQUIRED;
--                  admit exact PR #68 legacy inputs and build the first complete
--                  bundle.
--   line 394       Exact PR #68 authority/Store/retention/compaction locations:
--                  "No Package B writer ... Legacy admission only ... Preserved
--                  legacy input when the bundle is absent. Never used as fallback
--                  after bundle occupancy."
--   lines 398-401  Existing PR #68 direct writers must be routed into detached
--                  bundle candidates or disabled before bootstrap.
--   line 4849      RAW-01: one complete `authorityBundle` pointer is the sole
--                  durable payload write; legacy payload locations are read-only
--                  inputs.
--
-- Expected-red measured on the tree that still shipped the legacy compatibility
-- mirror (bundle write plus byte-equal legacy rawsets in CommitBatch/PublishRoot):
--   CUT-02  RED   the first bootstrap rewrote `buildCatalog` in the legacy
--                 location instead of only inside the bundle
--   CUT-03  RED   EditBuild mirrored the replacement into NexusDB.communityBuilds
--   CUT-04  RED   DeleteBuild mirrored overlay removal and the tombstone write
--   CUT-05  RED   Catalog.Put mirrored the created row
--   CUT-06  RED   a conflicting legacy row injected after occupancy was admitted
--                 by the next rebind and overrode bundle authority
--   CUT-08  RED   the legacy graph was not byte-identical to bootstrap input
-- CUT-01b was also RED on that tree ("collision row replaced"): startup identity
-- repair rewrote the legacy overlay row in place.
-- CUT-01 and CUT-07 were GUARD on that tree (bootstrap admission and restart
-- idempotence already held) and are kept as regressions.
local H = dofile("tests/harness.lua")
local S = dofile("tests/catalog_authority_support.lua")
dofile("ui/CommunityBuilds.lua")

UnitName = function(unit) return unit == "player" and "Boganic" or nil end
GetNormalizedRealmName = function() return "Ebonhold" end
time = function() return 50000 end

local failures = 0
local function Check(name, ok, why)
    if ok then
        print(name .. " -- OK")
    else
        failures = failures + 1
        print(name .. " -- RED: " .. tostring(why))
    end
end

local bundled = {
    schemaVersion=1, catalogVersion="runtime-cutover-1", sourceVersion="test",
    builds={
        collision={id="collision",title="Immutable bundled title",author="Remote",
            postedAt=100,lastModified=100,echoes={{spellId=200100,stacks=1}}},
        remote={id="remote",title="Bundled remote",author="Alice",
            postedAt=10,lastModified=10,echoes={{spellId=200101,stacks=1}}},
        bundledOnly={id="bundledOnly",title="Bundled only",author="Carol",
            postedAt=15,lastModified=15,echoes={{spellId=200104,stacks=1}}},
    },
}
Nexus.BundledBuilds = bundled
NexusDB = {
    communityBuilds={
        collision={id="collision",title="My personal override",author="Boganic",
            ownerKey="boganic@ebonhold",realm="ebonhold",
            ownerVerified=true,isMine=true,postedAt=1,lastModified=1,
            echoes={{spellId=200100,stacks=2}}},
        remote={id="remote",title="Newer remote overlay",author="Alice",
            postedAt=20,lastModified=20,echoes={{spellId=200101,stacks=2}}},
        personal={id="personal",title="Personal only",author="Boganic",
            ownerKey="boganic@ebonhold",realm="ebonhold",
            ownerVerified=true,isMine=true,postedAt=5,lastModified=5,
            echoes={{spellId=200102,stacks=1}}},
    },
    syncTombstones={},
    -- The evidence payload location is one of the exact PR #68 locations state
    -- machine line 394 covers. It is seeded here so CUT-09 can prove it is
    -- preserved input and never a Package B write target after occupancy.
    loadoutEvidence={schemaVersion=1, entries={
        ["v1|200109:3:1:0"]={{spellId=200109,quality=3,stacks=1}},
    }},
}

local Catalog = Nexus.BuildCatalog
local Builds = Nexus.CommunityBuilds
local function AwaitMutation(ok, why, ticket)
    return S.AwaitCatalogMutation(ok, why, ticket,
        "runtime-cutover catalog mutation")
end
local function AwaitControllerMutation(ok, why)
    -- A retained pending controller write is accepted once and reports the
    -- retained state through its reason or its outcome table; settle it to the
    -- exact terminal ticket before any durable assertion.
    local pending = why == "ROOT_MUTATION_PENDING"
        or type(why) == "table"
            and (why.storageReason == "ROOT_MUTATION_PENDING"
                or why.queueReason == "ROOT_MUTATION_PENDING")
    if pending then
        local terminal = S.PumpCatalogToIdle(
            "runtime-cutover controller mutation")
        return type(terminal) == "table" and terminal.committed == true,
            type(terminal) == "table" and terminal.reason or why,
            terminal
    end
    return ok, why
end

-- The exact legacy input graph, captured before bootstrap. Every identity and
-- every scalar below must survive the whole cutover untouched: after the bundle
-- exists these locations are read-only preserved input, never storage.
local legacyOverlay = NexusDB.communityBuilds
local legacyTombstones = NexusDB.syncTombstones
local legacyCollision = legacyOverlay.collision
local legacyRemote = legacyOverlay.remote
local legacyPersonal = legacyOverlay.personal
local legacyCollisionTitle = legacyCollision.title
local legacyCollisionEchoes = legacyCollision.echoes
local legacyEvidence = NexusDB.loadoutEvidence
local legacyEvidenceEntries = legacyEvidence.entries
local legacyEvidenceSeedKey = "v1|200109:3:1:0"
local legacyEvidenceSeedRow = legacyEvidenceEntries[legacyEvidenceSeedKey]
local function CountKeys(map)
    local n = 0
    for _ in pairs(map or {}) do n = n + 1 end
    return n
end
local legacyEvidenceCount = CountKeys(legacyEvidenceEntries)

local function LegacyPreserved()
    if NexusDB.communityBuilds ~= legacyOverlay then return "overlay map replaced" end
    if NexusDB.syncTombstones ~= legacyTombstones then return "tombstone map replaced" end
    if legacyOverlay.collision ~= legacyCollision then return "collision row replaced" end
    if legacyOverlay.remote ~= legacyRemote then return "remote row replaced" end
    if legacyOverlay.personal ~= legacyPersonal then return "personal row replaced" end
    if legacyCollision.title ~= legacyCollisionTitle then return "collision title rewritten" end
    if legacyCollision.echoes ~= legacyCollisionEchoes then return "collision echoes replaced" end
    local extra = 0
    for _ in pairs(legacyOverlay) do extra = extra + 1 end
    if extra ~= 3 then return "legacy overlay gained or lost a key: " .. extra end
    for _ in pairs(legacyTombstones) do return "legacy tombstone map was written" end
    -- Line 394 covers the evidence payload location exactly as it covers the
    -- catalog maps: no Package B writer, legacy admission only, never a
    -- fallback after bundle occupancy.
    if rawget(NexusDB, "loadoutEvidence") ~= legacyEvidence then
        return "legacy evidence store replaced"
    end
    if legacyEvidence.entries ~= legacyEvidenceEntries then
        return "legacy evidence entries map replaced"
    end
    if legacyEvidenceEntries[legacyEvidenceSeedKey] ~= legacyEvidenceSeedRow then
        return "legacy evidence seed row replaced"
    end
    if CountKeys(legacyEvidenceEntries) ~= legacyEvidenceCount then
        return "legacy evidence entries map gained or lost a key: "
            .. CountKeys(legacyEvidenceEntries)
    end
    return nil
end

local function Bundle()
    return rawget(NexusDB, "authorityBundle")
end

assert(Bundle() == nil, "fixture started with a durable bundle already occupied")

------------------------------------------------------------------------
-- CUT-01  first bootstrap admits the supported PR #68 legacy inputs and
--         publishes the first complete bundle at generation 1
------------------------------------------------------------------------
H.AdmitCatalogV1(NexusDB, bundled)
local first = Bundle()
do
    local payload = type(first) == "table" and first.communityBuilds or nil
    local root = Catalog.RootState()
    Check("CUT-01 first bootstrap migrates legacy inputs into one complete bundle",
        type(first) == "table"
            and first.schemaVersion == 1
            and first.transactionGeneration == 1
            and root.durableBundleGeneration == 1
            and type(payload) == "table"
            and payload.collision ~= nil and payload.remote ~= nil
            and payload.personal ~= nil and payload.bundledOnly == nil
            -- The bundle owns its own payload map. Admitted PR #68 rows are
            -- carried by reference, which stays safe because a row is only ever
            -- replaced wholesale inside a replacement map, never rewritten in
            -- place; CUT-08 proves the legacy graph never changes.
            and payload ~= legacyOverlay
            and Catalog.Count() == 4,
        "bundle=" .. tostring(first) .. " gen="
            .. tostring(root.durableBundleGeneration)
            .. " count=" .. tostring(Catalog.Count()))
end

-- Startup identity repair is an ordinary authorized publication: it runs after
-- bootstrap, so every row it rewrites must land in a replacement bundle and
-- nowhere else.
Builds.Init({}, {})
S.PumpCatalogToIdle("startup identity repair")
do
    local all = H.CatalogAll()
    local count = 0
    for _ in pairs(all) do count = count + 1 end
    Check("CUT-01b merged runtime view after startup identity repair",
        count == 4 and Catalog.Count() == 4
            and all.collision.title == "My personal override"
            and all.remote.title == "Newer remote overlay"
            and all.personal.title == "Personal only"
            and Builds.IsOwnBuild("collision") and Builds.IsOwnBuild("personal")
            and not Builds.IsOwnBuild("remote")
            and Bundle().transactionGeneration >= 1,
        "count=" .. count)
end

------------------------------------------------------------------------
-- CUT-02  bootstrap performs no write to any legacy payload location: the
--         schema/catalog-version migration lands in the bundle's buildCatalog
------------------------------------------------------------------------
do
    local why = LegacyPreserved()
    local meta = type(first) == "table" and first.buildCatalog or nil
    Check("CUT-02 bootstrap writes no legacy payload location",
        why == nil
            and rawget(NexusDB, "buildCatalog") == nil
            and type(meta) == "table"
            and meta.catalogVersion == "runtime-cutover-1"
            and meta.schemaVersion == Catalog.SchemaVersion(),
        (why or "legacy buildCatalog=" .. tostring(rawget(NexusDB, "buildCatalog"))
            .. " bundleMeta=" .. tostring(meta)))
end

------------------------------------------------------------------------
-- CUT-03  an edit publishes a replacement through the bundle only
------------------------------------------------------------------------
local immutableTitle = bundled.builds.collision.title
do
    local before = Bundle()
    local ok = AwaitControllerMutation(
        Builds.EditBuild("collision", "Edited personal overlay", "Changed"))
    local after = Bundle()
    local why = LegacyPreserved()
    Check("CUT-03 edit publishes through the bundle and never the legacy overlay",
        ok
            and why == nil
            and after ~= before
            and after.transactionGeneration == before.transactionGeneration + 1
            and after.communityBuilds.collision.title == "Edited personal overlay"
            and before.communityBuilds.collision.title == "My personal override"
            and Catalog.Get("collision").title == "Edited personal overlay"
            and bundled.builds.collision.title == immutableTitle,
        (why or "legacyTitle=" .. tostring(legacyOverlay.collision.title)
            .. " bundleTitle=" .. tostring(after.communityBuilds.collision.title)))
end

------------------------------------------------------------------------
-- CUT-04  a delete removes the bundle overlay row and publishes the tombstone
--         inside the same bundle; the legacy locations stay untouched
------------------------------------------------------------------------
do
    local before = Bundle()
    local ok = AwaitControllerMutation(Builds.DeleteBuild("collision"))
    local after = Bundle()
    local why = LegacyPreserved()
    Check("CUT-04 delete publishes overlay removal and tombstone in the bundle",
        ok
            and why == nil
            and after ~= before
            and after.communityBuilds.collision == nil
            and after.syncTombstones.collision ~= nil
            and before.communityBuilds.collision ~= nil
            and before.syncTombstones.collision == nil
            and Catalog.Get("collision") == nil
            and bundled.builds.collision.title == immutableTitle,
        (why or "bundleOverlay=" .. tostring(after.communityBuilds.collision)
            .. " bundleTomb=" .. tostring(after.syncTombstones.collision)))
end

------------------------------------------------------------------------
-- CUT-05  a create enters the bundle only, and the caller keeps no aliasing
------------------------------------------------------------------------
local created = {id="created",title="Created locally",author="Boganic",
    ownerKey="boganic@ebonhold",realm="ebonhold",ownerVerified=true,
    isMine=true,postedAt=30,lastModified=30,
    echoes={{spellId=200103,stacks=1}}}
do
    local ok = AwaitMutation(Catalog.Put(created))
    local after = Bundle()
    created.title = "caller mutation"
    local why = LegacyPreserved()
    Check("CUT-05 create enters the bundle payload only",
        ok
            and why == nil
            and after.communityBuilds.created ~= nil
            and after.communityBuilds.created ~= created
            and Catalog.Get("created").title == "Created locally",
        (why or "bundleCreated=" .. tostring(after.communityBuilds.created)))
end

------------------------------------------------------------------------
-- CUT-06  stale or conflicting legacy data never overrides an occupied bundle
------------------------------------------------------------------------
do
    local before = Bundle()
    local publishedRemote = before.communityBuilds.remote
    -- A raw write behind the published root grants no authority. After bundle
    -- occupancy the legacy location is not even an admission input, so an
    -- explicit complete readmission from cursor zero must still ignore it.
    rawset(legacyOverlay, "injected", {id="injected",title="Injected legacy row",
        author="Mallory",postedAt=1,lastModified=1,
        echoes={{spellId=200109,stacks=1}}})
    rawset(legacyOverlay, "remote", {id="remote",title="Stale legacy remote",
        author="Alice",postedAt=999,lastModified=999,
        echoes={{spellId=200101,stacks=9}}})
    H.RebindCatalog(NexusDB, bundled)
    local after = Bundle()
    local remote = Catalog.Get("remote")
    Check("CUT-06 occupied bundle refuses stale/conflicting legacy input",
        Catalog.Get("injected") == nil
            and after.communityBuilds.injected == nil
            and after.communityBuilds.remote == publishedRemote
            and remote ~= nil and remote.title == "Newer remote overlay"
            and Catalog.Get("created") ~= nil,
        "injected=" .. tostring(Catalog.Get("injected"))
            .. " remoteTitle=" .. tostring(remote and remote.title))
    rawset(legacyOverlay, "injected", nil)
    rawset(legacyOverlay, "remote", legacyRemote)
end

------------------------------------------------------------------------
-- CUT-07  restart is idempotent: a fresh session over the same durable bytes
--         adopts the complete bundle with no bundle write and no generation
--         advance (the architecture's zero-delta route)
------------------------------------------------------------------------
do
    local before = Bundle()
    local generation = before.transactionGeneration
    H.RebindCatalog(NexusDB, bundled)
    local after = Bundle()
    local why = LegacyPreserved()
    Check("CUT-07 restart adopts the bundle with no write and no advance",
        why == nil
            and after == before
            and after.transactionGeneration == generation
            and Catalog.RootState().durableBundleGeneration == generation
            and Catalog.Get("collision") == nil
            and Catalog.Get("created").title == "Created locally"
            and Catalog.Get("personal").title == "Personal only",
        (why or "before=" .. tostring(before) .. " after=" .. tostring(after)))
end

------------------------------------------------------------------------
-- CUT-09  the evidence payload location follows the same rule as the catalog
--         maps. RAW-01 (line 4849) makes "one complete `authorityBundle`
--         pointer ... the sole durable payload write" and leaves "legacy
--         payload locations ... read-only inputs"; line 394 gives
--         `loadoutEvidence` no Package B writer and forbids using it as a
--         fallback after bundle occupancy. The architecture also forbids
--         mutating a live nested bundle field, so the bundle's evidence store
--         must not alias the legacy table either.
------------------------------------------------------------------------
do
    local before = Bundle()
    local evidenceBuild = {id="withEvidence",title="Evidence carrier",
        author="Boganic",ownerKey="boganic@ebonhold",realm="ebonhold",
        ownerVerified=true,isMine=true,postedAt=40,lastModified=40,
        echoes={{spellId=200107,quality=3,stacks=2}}}
    local ok = AwaitMutation(Catalog.Put(evidenceBuild))
    local after = Bundle()
    local why = LegacyPreserved()
    local bundleEvidence = after and after.loadoutEvidence or nil
    Check("CUT-09 evidence interning writes the bundle, never the legacy store",
        ok
            and why == nil
            and type(bundleEvidence) == "table"
            -- the durable evidence store lives in the bundle ...
            and bundleEvidence ~= legacyEvidence
            -- ... and is not an alias of the live legacy table, so a later
            -- legacy write can never mutate a live nested bundle field
            and bundleEvidence.entries ~= legacyEvidenceEntries
            -- ... and it carried the admitted legacy input forward
            and bundleEvidence.entries[legacyEvidenceSeedKey] ~= nil
            and after ~= before,
        (why or "bundleEvidence=" .. tostring(bundleEvidence)
            .. " legacyEvidence=" .. tostring(rawget(NexusDB, "loadoutEvidence"))
            .. " aliased=" .. tostring(bundleEvidence == legacyEvidence)))
end

------------------------------------------------------------------------
-- CUT-08  the whole run wrote exactly one durable payload location: the legacy
--         graph is byte-identical to the pre-bootstrap capture
------------------------------------------------------------------------
do
    local why = LegacyPreserved()
    Check("CUT-08 legacy payload locations are byte-identical to bootstrap input",
        why == nil
            and legacyOverlay.collision.title == "My personal override"
            and legacyOverlay.remote.title == "Newer remote overlay"
            and legacyOverlay.personal.title == "Personal only"
            and rawget(NexusDB, "buildCatalog") == nil,
        why or "legacy graph drifted")
end

assert(failures == 0, failures .. " runtime cutover case(s) RED")
print("runtime legacy-to-bundle cutover -- OK")
