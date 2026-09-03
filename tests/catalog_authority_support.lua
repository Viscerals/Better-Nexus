-- Shared fixture and case-runner support for the Package B catalog authority
-- matrix (issue #22). Test data only; not loaded by Nexus.toc.
local S = {}

S.results, S.failures, S.passed = {}, {}, 0

function S.Case(id, name, callback)
    local ok, err = pcall(callback)
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

function S.Bind(db, bundle)
    NexusDB = db
    Nexus.LoadoutEvidence.Init(db)
    return Nexus.BuildCatalog.Init(db, bundle or S.Bundle())
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

return S
