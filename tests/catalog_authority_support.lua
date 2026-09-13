-- Shared fixture and case-runner support for the Package B catalog authority
-- matrix (issue #22). Test data only; not loaded by Nexus.toc.
local S = {}

S.results, S.failures, S.passed = {}, {}, 0

-- Outstanding fixture fault occupants. Every case restores them, whether it
-- passes or fails, so a hostile durable occupant can never leak into a later
-- case or into a reported pass.
S.pendingRestores = {}

local function RestoreAll()
    for index = #S.pendingRestores, 1, -1 do
        pcall(S.pendingRestores[index])
        S.pendingRestores[index] = nil
    end
end

function S.Case(id, name, callback)
    local ok, err = pcall(callback)
    RestoreAll()
    if ok then
        S.passed = S.passed + 1
        S.results[#S.results + 1] = string.format("%s PASS %s", id, name)
    else
        S.failures[#S.failures + 1] = id
        S.results[#S.results + 1] = string.format("%s RED %s: %s", id, name,
            tostring(err))
    end
end

function S.Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

function S.Finish(label)
    for _, line in ipairs(S.results) do print(line) end
    print(string.format("%s: %d passed, %d red", label, S.passed, #S.failures))
    if #S.failures > 0 then
        error(label .. " has red cases: " .. table.concat(S.failures, ","), 0)
    end
end

function S.Rows(copies, options)
    options = options or {}
    local rows, remaining = {}, copies or 0
    local spell = options.firstSpell or 100000
    local perRow = options.perRow or 1
    while remaining > 0 do
        local stacks = math.min(perRow, remaining)
        rows[#rows + 1] = {
            spellId=spell, quality=options.quality or 3, stacks=stacks,
            locked=options.locked and true or nil,
        }
        spell = spell + 1
        remaining = remaining - stacks
    end
    return rows
end

function S.Echoes(ordinary, locked, options)
    options = options or {}
    local rows = S.Rows(ordinary, {firstSpell=options.firstSpell or 100000,
        perRow=options.perRow})
    for _, row in ipairs(S.Rows(locked or 0, {firstSpell=(options.lockedSpell
        or 200000), perRow=options.lockedPerRow, locked=true})) do
        rows[#rows + 1] = row
    end
    return rows
end

function S.Build(id, ordinary, locked, extra)
    local build = {
        id=id, title="Build " .. tostring(id), author="Peer", class="MAGE",
        ownerKey="peer@ebonhold", realm="ebonhold", ownerVerified=true,
        postedAt=10, lastModified=10, echoes=S.Echoes(ordinary, locked),
    }
    for key, value in pairs(extra or {}) do build[key] = value end
    return build
end

function S.LocalBuild(id, ordinary, extra)
    local build = S.Build(id, ordinary, 0, {
        author="Boganic", ownerKey="boganic@ebonhold", realm="ebonhold",
        ownerVerified=true, isMine=true,
    })
    for key, value in pairs(extra or {}) do build[key] = value end
    return build
end

function S.Bundle(builds, version)
    return {
        schemaVersion=1, catalogVersion=version or "authority-test",
        sourceVersion="test", builds=builds or {},
    }
end

function S.Database(overlay, tombstones, extra)
    local db = {communityBuilds=overlay or {}, syncTombstones=tombstones or {}}
    for key, value in pairs(extra or {}) do db[key] = value end
    return db
end

-- The durable authority payload (MASTER-RC-001; architecture 3b5de54f state
-- machine lines 374/394/4849). After the accepted legacy-to-bundle cutover the
-- one durable payload write is `authorityDatabase.authorityBundle`, and the
-- exact PR #68 locations are read-only preserved input: never written and never
-- read again once a bundle exists. A fixture that inspected `db.communityBuilds`
-- as storage inspects this seam instead; `db.communityBuilds` keeps its separate
-- meaning as the preserved legacy bootstrap input.
function S.Durable(db, field)
    local database = db or NexusDB
    if type(database) ~= "table" then return {} end
    local bundle = rawget(database, "authorityBundle")
    if type(bundle) ~= "table" then return {} end
    return rawget(bundle, field or "communityBuilds") or {}
end

-- Fixture-only fault surface for the durable authority payload. No production
-- fault seam exists or may exist (MASTER-RC-002): after the legacy-to-bundle
-- cutover the one durable payload write is the bundle pointer, so the only
-- durable state a fixture can make hostile is a bundle payload field. Returns a
-- restore function; every caller restores it, including on failure.
function S.PoisonDurableField(db, field, value)
    local bundle = rawget(db or NexusDB, "authorityBundle")
    if type(bundle) ~= "table" then
        return function() end
    end
    local previous = rawget(bundle, field)
    rawset(bundle, field, value)
    local done = false
    local function restore()
        if done then return end
        done = true
        rawset(bundle, field, previous)
    end
    S.pendingRestores[#S.pendingRestores + 1] = restore
    return restore
end

-- A raw write behind the published root grants no authority. After the
-- legacy-to-bundle cutover the durable location is the bundle payload, so a
-- fixture that used to seed SavedVariables directly seeds the payload and then
-- performs one explicit supported readmission from cursor zero.
function S.SeedDurable(db, field, key, value)
    local payload = S.Durable(db, field)
    payload[key] = value
    return payload
end

-- Current-source drift on the selected authority input: a foreign replacement
-- of the exact payload field the serving witness is bound to. Before bundle
-- occupancy that is still the exact PR #68 location (state machine line 374);
-- after occupancy it is the bundle payload field (line 394).
-- `deep` reproduces a reload-shaped replacement in which no record table
-- identity survives, which is what distinguishes a current-session reservation
-- from a reloaded one.
function S.DriftSelectedMap(db, field, deep)
    local database = db or NexusDB
    local bundle = rawget(database, "authorityBundle")
    local owner = type(bundle) == "table" and bundle or database
    local current = rawget(owner, field) or {}
    local replacement = deep and S.DeepCopy(current) or nil
    if not replacement then
        replacement = {}
        for key, value in pairs(current) do replacement[key] = value end
    end
    rawset(owner, field, replacement)
    return replacement
end

function S.Bind(db, bundle)
    NexusDB = db
    Nexus.LoadoutEvidence.Init(db)
    local catalog = Nexus.BuildCatalog
    local selected = bundle or S.Bundle()
    -- A historical catalog (the PR58 expected-red oracle binds one) has no
    -- pump budget and admits in its single synchronous Init call.
    local budget = type(catalog.Budget) == "function" and catalog.Budget() or {}
    local limit = tonumber(budget.maximumPumps) or 1
    local result = catalog.Init(db, selected)
    local pumps = 1
    while type(result) == "table" and result.state == "pending"
        and pumps < limit do
        pumps = pumps + 1
        result = catalog.Init(db, selected)
    end
    return result
end

-- Simulate a client reload: every session table, cursor, claim, and root
-- disappears while SavedVariables bytes stay exactly where they were.
function S.Reload()
    dofile("core/LoadoutEvidence.lua")
    dofile("core/BuildCatalog.lua")
    return Nexus.BuildCatalog, Nexus.LoadoutEvidence
end

function S.Encode(value)
    return Nexus.Codec.JSONEncode(value)
end

function S.DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[S.DeepCopy(key, seen)] = S.DeepCopy(child, seen)
    end
    return out
end

function S.Count(source)
    local n = 0
    for _ in pairs(source or {}) do n = n + 1 end
    return n
end

function S.State(id)
    local catalog = Nexus.BuildCatalog
    S.Check(type(catalog.AuthorityState) == "function",
        "Catalog.AuthorityState export unavailable")
    return catalog.AuthorityState(id)
end

function S.Root()
    local catalog = Nexus.BuildCatalog
    S.Check(type(catalog.RootState) == "function",
        "Catalog.RootState export unavailable")
    return catalog.RootState()
end

function S.Counters()
    local catalog = Nexus.BuildCatalog
    S.Check(type(catalog.BudgetCounters) == "function",
        "Catalog.BudgetCounters export unavailable")
    return catalog.BudgetCounters()
end

function S.PumpUntilTerminal(limit)
    local catalog = Nexus.BuildCatalog
    local pumps, result = 0, nil
    while true do
        result = catalog.PumpRootAdmission()
        pumps = pumps + 1
        if result.state ~= "pending" then break end
        S.Check(pumps < (limit or 200000), "root admission did not converge")
    end
    return result, pumps
end

-- Ordinary catalog writes may spend several scheduler turns constructing and
-- publishing one detached candidate. Drive exactly one owner slice per loop,
-- retain the exact ticket, and fail visibly if the bounded fixture does not
-- reach its own terminal receipt. A pending result is never treated as success.
function S.AwaitCatalogMutation(first, reason, ticket, label, limit)
    if first == true then return true, reason, ticket, 0 end
    if first == false then return false, reason, ticket, 0 end
    if type(first) == "table" and first.state == "pending" then
        ticket = first
    end
    S.Check(reason == "ROOT_MUTATION_PENDING" and type(ticket) == "table"
            and ticket.state == "pending",
        (label or "catalog mutation") .. " returned neither terminal nor pending")
    local catalog = Nexus and Nexus.BuildCatalog
    S.Check(type(catalog) == "table"
            and type(catalog.PumpRootAdmission) == "function",
        (label or "catalog mutation") .. " has no catalog owner pump")
    local bound = limit or 200000
    for pumps = 1, bound do
        catalog.PumpRootAdmission()
        if ticket.state ~= "pending" then
            return ticket.committed == true,
                ticket.committed == true and ticket.storedAs or ticket.reason,
                ticket, pumps
        end
    end
    error((label or "catalog mutation")
        .. " did not reach a terminal ticket within " .. tostring(bound)
        .. " owner slices", 2)
end

function S.CatalogMutation(callback, label, limit)
    local first, reason, ticket = callback()
    return S.AwaitCatalogMutation(first, reason, ticket, label, limit)
end

function S.PumpCatalogToIdle(label, limit)
    local catalog = Nexus and Nexus.BuildCatalog
    S.Check(type(catalog) == "table"
            and type(catalog.PumpRootAdmission) == "function",
        (label or "catalog work") .. " has no catalog owner pump")
    local bound, last = limit or 200000, nil
    for pumps = 0, bound do
        local root = catalog.RootState()
        if not root.candidate then return last, pumps end
        S.Check(pumps < bound,
            (label or "catalog work") .. " did not become idle")
        last = catalog.PumpRootAdmission()
    end
end

-- Direct Sync fixtures have no MainLifecycle scheduler. Stand in for its one
-- BuildHashCache slice per turn until the exact compatibility view is ready.
-- This helper never drains more than one cache slice in one simulated turn.
function S.CompatibilityHashes(sync, limit)
    local cache = Nexus and Nexus.BuildHashCache
    local bound = limit or 200000
    for pumps = 0, bound do
        local buildHash, dpsHash = sync.GetCompatibilityHashes()
        if type(buildHash) == "string" and type(dpsHash) == "string" then
            return buildHash, dpsHash, pumps
        end
        local stats = type(cache) == "table" and type(cache.Stats) == "function"
            and cache.Stats() or {}
        S.Check(pumps < bound,
            "compatibility hash work did not converge: initialized="
                .. tostring(stats.initialized) .. " pending="
                .. tostring(stats.pending) .. " warmPumps="
                .. tostring(stats.warmPumps) .. " warmRestarts="
                .. tostring(stats.warmRestarts) .. " revision="
                .. tostring(stats.revision))
        S.Check(type(cache) == "table" and type(cache.Pump) == "function",
            "compatibility hash work has no cache owner pump")
        cache.Pump()
    end
end

-- Community facade posts save through one retained catalog mutation and
-- report `false, "ROOT_MUTATION_PENDING", outcome` until it commits. Drive that
-- exact retained outcome to its terminal local save through the public catalog
-- scheduler seam. A pending acknowledgement is never treated as a saved post,
-- and a terminal refusal is returned as the refusal it is.
function S.PostWishlist(post, title, description, wishlist, class, label)
    local ok, id, outcome = post(title, description, wishlist, class)
    local retained = type(outcome) == "table" and outcome.localSaved ~= true
        and outcome.queueReason == "ROOT_MUTATION_PENDING"
        and (ok == true or id == "ROOT_MUTATION_PENDING")
    if not retained then return ok, id, outcome end
    S.PumpCatalogToIdle(label or "shared build admission")
    if outcome.localSaved == true then return true, outcome.id, outcome end
    return false, outcome.queueReason or "local save failed", outcome
end

-- Inbound Sync traffic that stores a row returns false until its retained
-- catalog mutation commits. Deliver one wire text, settle the catalog through
-- the public scheduler seam, and report whether the delivery was accepted
-- immediately and whether catalog work was pending. Callers assert the durable
-- terminal state themselves; pending is neither acceptance nor refusal.
function S.DeliverInbound(sync, text, sender, label)
    local accepted = sync.HandleIncoming(text, sender)
    local catalog = Nexus and Nexus.BuildCatalog
    local pending = type(catalog) == "table"
        and type(catalog.RootState) == "function"
        and catalog.RootState().candidate == true
    if pending then S.PumpCatalogToIdle(label or "inbound catalog mutation") end
    return accepted, pending
end

-- Cold Community projection reads are retained pending jobs (MASTER-W2-006).
-- Drive the exact retained job through the public pump with a finite guard and
-- serve the published cache through the same entry point. A job failure is
-- returned as the failure it is; pending is never treated as a result.
function S.ProjectBuilds(projections, filters)
    local rows, summary, why = projections.Builds(filters)
    if rows then return rows, summary end
    for _ = 1, 100000 do
        local _, pumpError = projections.PumpBuilds()
        if pumpError then return nil, nil, pumpError end
        rows, summary, why = projections.Builds(filters)
        if rows then return rows, summary end
        if why ~= "pending" then return nil, nil, why end
    end
    error("build projection did not terminate: " .. tostring(why))
end

function S.ProjectList(projection, projections, filters)
    local rows, summary, why = projection.List(filters)
    if rows then return rows, summary end
    for _ = 1, 100000 do
        local _, pumpError = projections.PumpBuilds()
        if pumpError then return nil, nil, pumpError end
        rows, summary, why = projection.List(filters)
        if rows then return rows, summary end
        if why ~= "pending" then return nil, nil, why end
    end
    error("Community list projection did not terminate: " .. tostring(why))
end

-- The Community browser pumps its retained projection job one bounded slice
-- per real frame. Drive the frame's own OnUpdate until the predicate holds.
function S.PumpCommunityFrame(frame, predicate, label, limit)
    local onUpdate = frame and frame.GetScript and frame:GetScript("OnUpdate")
    S.Check(type(onUpdate) == "function",
        (label or "Community frame") .. " has no OnUpdate script")
    local bound = limit or 100000
    for turns = 0, bound do
        if predicate() then return turns end
        S.Check(turns < bound, (label or "Community frame") .. " did not publish")
        onUpdate(frame, 0.05)
    end
end

return S
