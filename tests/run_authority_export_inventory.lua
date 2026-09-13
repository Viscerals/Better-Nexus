-- Package B / issue #22: the authority export inventory (EXP).
--
-- Architecture RAW-01 (line ~4849) fixes the authority API surface exactly:
--
--   "...exact Store 9, Retention 8, and Compaction 8 API inventories plus two
--    counted private Store mutation entries route every mutation through the
--    coordinator..."
--
-- and architecture line 1912 states the obligation this file discharges
-- literally:
--
--   "The nine-export public Store inventory therefore remains exact. Contract
--    tests count these two private entries separately and reject a public
--    alias, direct table write, or unlisted caller."
--
-- This path was allowlisted for the wave in the governing packet
-- (`newTestFiles`) and had never been created; it was carried as a disclosed
-- residual through every prior checkpoint. MASTER-RC-001's second reopening
-- makes it load-bearing, because that root adds the two private mutation
-- entries and the inventory is the thing that proves they were added WITHOUT
-- widening any public facade.
--
-- Scope, stated so this file is not mistaken for a whole-codebase inventory:
-- it covers the three authority facades RAW-01 names, the two counted private
-- mutation entries, and the Nexus.MainInternals seam. It is not a general
-- export audit of `core/`.

local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
-- The harness boots DataRetention/DataCompaction/BuildCatalog but not Store;
-- the Store facade and its coordinator seam are the subject here, so load them
-- the same way tests/run_catalog_authority_bootstrap.lua does.
dofile("core/Store.lua")
local Case, Check = S.Case, S.Check

-- Exact expected inventories. These are CONTRACTS, not observations: each list
-- is the architecture's fixed count, so a new export fails here rather than
-- silently enlarging a facade.
local INVENTORIES = {
    {
        name="Store", count=9, module=function() return Nexus.Store end,
        clause="RAW-01 \"exact Store 9\"; line 1912 \"remains exact\"",
        names={
            "Init", "CurrentOwnerKey", "RegisterCurrentCharacter",
            "IsAccountOwnerKey", "IsAccountBuild", "AccountCharacters",
            "SettingsVersion", "Settings", "State",
        },
    },
    {
        name="DataRetention", count=8,
        module=function() return Nexus.DataRetention end,
        clause="RAW-01 \"Retention 8\"",
        names={
            "Enforce", "Init", "Request", "AllowsRemoteRevision",
            "ReleaseSupersededAutoBuild", "Limits", "Stats", "SchemaVersion",
        },
    },
    {
        name="DataCompaction", count=8,
        module=function() return Nexus.DataCompaction end,
        clause="RAW-01 \"Compaction 8\"",
        names={
            "Enabled", "CompactBuildRow", "CompactDpsRow", "Pump", "Init",
            "CollectGarbage", "Stats", "Version",
        },
    },
}

local function CallableKeys(module)
    local out = {}
    for key, value in pairs(module) do
        if type(value) == "function" then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

local function SetOf(list)
    local set = {}
    for _, name in ipairs(list) do set[name] = true end
    return set
end

Case("EXP-01", "the three authority facades hold their exact fixed inventories",
function()
    for _, spec in ipairs(INVENTORIES) do
        local module = spec.module()
        Check(type(module) == "table",
            spec.name .. " is not loaded, so its inventory cannot be proved")
        local actual = CallableKeys(module)
        local expected, found = SetOf(spec.names), SetOf(actual)
        -- Missing: the facade lost a contracted export.
        for _, name in ipairs(spec.names) do
            Check(found[name] == true,
                spec.name .. "." .. name .. " is missing from the facade ("
                    .. spec.clause .. ")")
        end
        -- Extra: the facade grew. This is the assertion that actually binds a
        -- repair -- a new public entry point fails here by construction.
        for _, name in ipairs(actual) do
            Check(expected[name] == true,
                spec.name .. "." .. name .. " is an UNLISTED public export; "
                    .. spec.clause .. " fixes the inventory at "
                    .. tostring(spec.count) .. ". A new authority entry point "
                    .. "belongs on the internals seam, not on this facade.")
        end
        Check(#actual == spec.count,
            spec.name .. " exposes " .. tostring(#actual)
                .. " callable exports; " .. spec.clause .. " fixes it at "
                .. tostring(spec.count))
    end
end)

-- CORRECTED after the sixth consultation. An earlier revision of this case
-- asserted that the coordinator's `BeginStoreMutationV1`/`PumpStoreMutationV1`
-- ARE "the two counted private Store mutation entries" of RAW-01. That was
-- wrong, and the wrong claim is recorded here so it is not reintroduced.
--
-- Architecture lines 1907-1912 name them explicitly, and they are
-- `StoreAuthorityOwnerV1.UpdateSettingsV1` and `StoreAuthorityOwnerV1.UpdateStateV1`
-- -- "callable only by the static internal caller inventory... The nine-export
-- public Store inventory therefore remains exact". The coordinator methods are
-- internal implementation detail of the post-ready machine and do not
-- substitute for, or count as, those two named entries.
--
-- STILL OWED by MASTER-RC-001, and deliberately NOT asserted present here:
-- `UpdateSettingsV1`/`UpdateStateV1` themselves. `UpdateStateV1` is the
-- authorized write path that would replace `Store.State()`'s direct
-- `db.chars[ownerKey]` durable write, and that repair is blocked pending an
-- operator decision, because 32 callers in two PROTECTED files
-- (core/GameAdapter.lua, core/Main.lua) and two files outside the packet's
-- allowedMutations (core/AutomationRuntime.lua, core/WishlistController.lua)
-- write through the live table `Store.State()` returns. Asserting an
-- unimplementable requirement here would produce a permanent red rather than
-- evidence, so the gap is disclosed in the checkpoint instead.
--
-- What this case DOES still bind, and what makes it worth keeping: line 1912's
-- "reject a public alias" clause. No mutation entry, named or internal, may
-- leak onto a public facade.
Case("EXP-02",
    "no Store mutation entry is exposed as a public alias",
function()
    local seam = Nexus.MainInternals and Nexus.MainInternals.AuthorityBootstrap
    Check(type(seam) == "table" and type(seam.New) == "function",
        "the AuthorityBootstrap coordinator factory is unavailable")
    local coordinator = seam.New()
    Check(type(coordinator) == "table", "the coordinator factory returned no object")

    -- The internal machine exists and is reachable only from a coordinator
    -- instance. Named as INTERNAL, not as a counted architecture entry.
    local INTERNAL = {"BeginStoreMutationV1", "PumpStoreMutationV1"}
    for _, name in ipairs(INTERNAL) do
        Check(type(coordinator[name]) == "function",
            "internal post-ready mutation method " .. name .. " is absent from "
                .. "the coordinator")
    end

    -- Line 1912: reject a public alias, on every facade a caller could reach.
    -- This covers the internal methods AND the two architecture-named counted
    -- entries, so that if UpdateSettingsV1/UpdateStateV1 are added later they
    -- cannot be added as public exports.
    -- The architecture's two COUNTED private entries (1907-1912) live on
    -- StoreAuthorityOwnerV1, not on the coordinator and not on the facade.
    -- UpdateStateV1 exists now (MASTER-RC-001's read-purity repair);
    -- UpdateSettingsV1 is still owed and is asserted absent-or-private, never
    -- public, so it cannot later arrive as an export.
    local owner = Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner
    Check(type(owner) == "table",
        "StoreAuthorityOwnerV1 is not registered on the internals seam")
    Check(type(owner.UpdateStateV1) == "function",
        "the counted private entry StoreAuthorityOwnerV1.UpdateStateV1 is absent")
    Check(owner.owner == Nexus.Store,
        "StoreAuthorityOwnerV1 is not bound to this exact Store module, so a "
            .. "stub Store could resolve a real durable writer")

    local NEVER_PUBLIC = {"BeginStoreMutationV1", "PumpStoreMutationV1",
        "UpdateSettingsV1", "UpdateStateV1"}
    for _, name in ipairs(NEVER_PUBLIC) do
        Check(Nexus.Store[name] == nil,
            "Store." .. name .. " is a PUBLIC ALIAS of a private mutation "
                .. "entry; architecture line 1912 rejects exactly this")
        Check(seam[name] == nil,
            "AuthorityBootstrap." .. name .. " is a module-level alias of a "
                .. "per-coordinator private entry; these entries are owned by "
                .. "the coordinator instance, not by the factory")
    end
end)

Case("EXP-03", "the Nexus.MainInternals seam inventory is exact",
function()
    -- Closes a residual disclosed unchanged through every checkpoint of this
    -- wave: "internals seam factories: 7, uninventoried". They are inventoried
    -- here. MASTER-RC-001's two private mutation entries are instance methods
    -- on the object AuthorityBootstrap.New() returns, NOT new seam factories,
    -- so this count is 7 both before and after that repair.
    -- Inventory raised 7 -> 8 by MASTER-RC-001's Store.State() read-purity
    -- repair, which registers StoreAuthorityOwnerV1 on this seam to own the two
    -- architecture-named counted private mutation entries (lines 1907-1912).
    -- It is on the seam and NOT on the Store facade precisely because RAW-01
    -- fixes the public Store inventory at nine. This case went red on the
    -- addition, exactly as designed, and the contract and the wave's disclosed
    -- residual were updated together rather than the count being quietly bumped.
    -- Inventory raised 8 -> 9 by MASTER-W2-010's shared counter guard:
    -- BuildCatalog registers CatalogAuthorityCounters on this seam so Store,
    -- DPS, Sync, and evidence counters resolve one deny-only exhaustion latch
    -- at each increment. It is on the seam and NOT on a public facade because
    -- RAW-01 fixes every public owner inventory. This case went red on the
    -- addition, exactly as designed, and the count is raised by that one
    -- named entry together with the wave's evidence.
    local EXPECTED = {
        "AuthorityBootstrap", "AutomationRuntime", "CatalogAuthorityCounters",
        "Commands", "Diagnostics", "DpsAuthority", "Lifecycle",
        "StoreAuthorityOwner", "ViewModel",
    }
    -- SOURCE-BACKED, deliberately. Reading the live table would only inventory
    -- whatever this one fixture happens to load, so a new factory registered by
    -- an unloaded module would pass unnoticed. The registration sites are read
    -- from the exact production module list in Nexus.toc instead, which is the
    -- same scan basis DEP-01 uses.
    local toc = io.open("Nexus.toc", "rb")
    Check(toc ~= nil, "Nexus.toc could not be read, so the seam cannot be scanned")
    local manifest = toc:read("*a")
    toc:close()

    local found, files = {}, 0
    for line in manifest:gmatch("[^\r\n]+") do
        -- Nexus.toc uses Windows separators; normalize to the forward slashes
        -- io.open wants from the repository root.
        local path = line:match("^%s*([%w_\\/%-%.]+%.lua)%s*$")
        if path then
            path = path:gsub("\\", "/")
            local handle = io.open(path, "rb")
            if handle then
                files = files + 1
                local source = handle:read("*a")
                handle:close()
                for name in source:gmatch("Nexus%.MainInternals%.([%w_]+)%s*=") do
                    found[name] = (found[name] or 0) + 1
                end
            end
        end
    end
    Check(files > 0,
        "no production module files were read from Nexus.toc, so this scan "
            .. "would be vacuous")

    local actual = {}
    for name in pairs(found) do actual[#actual + 1] = name end
    table.sort(actual)
    local expected = SetOf(EXPECTED)
    for _, name in ipairs(EXPECTED) do
        Check(found[name] ~= nil,
            "Nexus.MainInternals." .. name .. " is no longer registered by any "
                .. "module in Nexus.toc")
    end
    for _, name in ipairs(actual) do
        Check(expected[name] == true,
            "Nexus.MainInternals." .. name .. " is an UNINVENTORIED internals "
                .. "factory. The seam is inventoried at " .. #EXPECTED
                .. " entries; adding one requires updating this contract and "
                .. "the wave's disclosed residual together.")
    end
    Check(#actual == #EXPECTED,
        "Nexus.toc registers " .. tostring(#actual)
            .. " Nexus.MainInternals factories across " .. tostring(files)
            .. " modules; the inventoried contract is " .. tostring(#EXPECTED))
end)

Case("EXP-04", "core/ exports no production fault-injection surface",
function()
    -- Asserted ad hoc by grep repeatedly during this wave and by ATOM-01 for
    -- one name. Pinned here so it cannot regress silently: every fault used by
    -- the Package B fixtures is a harness-only collaborator substitution, never
    -- a shipped hook.
    local FORBIDDEN = {
        "InstallFaultInjector", "PoisonDurableField", "RunFault",
        "InjectFault", "SetFaultInjector", "FaultInjector",
    }
    local MODULES = {"BuildCatalog", "Store", "DataRetention", "DataCompaction",
        "LoadoutEvidence", "Sync"}
    for _, moduleName in ipairs(MODULES) do
        local module = Nexus[moduleName]
        if type(module) == "table" then
            for _, name in ipairs(FORBIDDEN) do
                Check(module[name] == nil,
                    "Nexus." .. moduleName .. "." .. name .. " is a PRODUCTION "
                        .. "fault-injection export; Package B permits only "
                        .. "harness-only collaborator substitution")
            end
        end
    end
    -- Source-level control, so a differently named export cannot slip past the
    -- name list above.
    local handle = io.open("core/BuildCatalog.lua", "rb")
    Check(handle ~= nil, "core/BuildCatalog.lua could not be read")
    local source = handle:read("*a")
    handle:close()
    Check(not source:lower():find("function catalog%.[%w_]*fault"),
        "core/BuildCatalog.lua declares a public fault-named export")
    Check(not source:lower():find("function catalog%.[%w_]*inject"),
        "core/BuildCatalog.lua declares a public injection-named export")
end)

S.Finish("authority export inventory")
