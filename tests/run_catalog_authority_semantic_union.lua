-- Package B / issue #22 Repair Wave 1: MASTER-RC-003, evidence union.
--
-- Root: "origin array participates in tuple identity; protocol-7 encoders omit
--  separate locked rows; 79/6/85 envelope not preserved."
-- Required repaired outcome: "one LoadoutEvidence-owned canonical union;
--  canonical grouping independent of source array; exact 79/6/85 and n=85
--  through every summary/full path."
--
-- Measured defect: a record carrying the SAME semantic tuple
-- (spellId 200100, quality 3, locked) in both the inline echoes array and the
-- lockedEchoes array produced TWO grouped members, stacks 2 and stacks 3,
-- because core/BuildCatalog.lua CompareTuples ranked
--     left.origin == "lockedArray"
-- and TupleKey concatenated (row.origin or "inline"). The canonical union must
-- be one member with stacks 5: which source array a tuple arrived in is
-- transport shape, not identity.
--
-- SEM-04 and SEM-05 are guards: they pass before the repair and after it, so
-- the fix cannot collapse the locked role or loosen the semantic envelope.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Codec.lua")
local S = dofile("tests/catalog_authority_support.lua")
local Case, Check = S.Case, S.Check

local now = 2000000000
time = function() return now end
UnitClass = function() return "Mage", "MAGE" end
UnitName = function() return "Boganic" end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = GetNormalizedRealmName

local function Catalog() return Nexus.BuildCatalog end

-- Assertions below inspect terminal mutations. Drive only the exact public
-- ticket returned by Put, and fail if the scheduler changes tickets, stalls,
-- exhausts its bound, or returns an unknown outcome.
local function AwaitMutation(ok, why, ticket)
    if ok == nil then
        assert(why == "ROOT_MUTATION_PENDING",
            "fixture mutation returned unknown pending result: " .. tostring(why))
        assert(type(ticket) == "table" and ticket.state == "pending",
            "pending mutation returned no live ticket")
        local previous = tonumber(ticket.pumps) or -1
        for _ = 1, Catalog().Budget().maximumPumps do
            if ticket.state ~= "pending" then break end
            local observed = Catalog().PumpRootAdmission()
            assert(observed == ticket, "fixture mutation changed tickets")
            local current = tonumber(ticket.pumps)
            assert(current and current > previous,
                "fixture mutation made no scheduler progress")
            previous = current
        end
        assert(ticket.state ~= "pending", "fixture mutation exhausted its pump bound")
        assert(ticket.state == "committed" or ticket.state == "failed",
            "fixture mutation ended in unknown state: " .. tostring(ticket.state))
        return ticket.committed, ticket.storedAs or ticket.reason, ticket
    end
    assert(ok == true or ok == false,
        "fixture mutation returned unknown result: " .. tostring(ok))
    return ok, why, ticket
end

local function PutTerminal(record, options)
    return AwaitMutation(Catalog().Put(record, options))
end

local function LocalRecord(id, echoes, lockedEchoes)
    return {
        id=id, title="Union " .. id, author="Boganic",
        ownerKey="boganic@ebonhold", realm="ebonhold", ownerVerified=true,
        isMine=true, class="MAGE", postedAt=10, lastModified=10,
        echoes=echoes, lockedEchoes=lockedEchoes,
    }
end

-- Every canonical member of the published union, keyed by role-bearing identity.
local function UnionMembers(record)
    local members = {}
    for _, source in ipairs({record.echoes or {}, record.lockedEchoes or {}}) do
        for _, echo in ipairs(source) do
            local key = tostring(echo.spellId) .. ":" .. tostring(echo.quality)
                .. ":" .. (echo.locked and "1" or "0")
            members[key] = (members[key] or 0) + (tonumber(echo.stacks) or 0)
        end
    end
    return members
end

local function MemberCount(members)
    local n = 0
    for _ in pairs(members) do n = n + 1 end
    return n
end

-- Entries actually PUBLISHED across both transport arrays. Aggregating by
-- identity would hide the defect, because a duplicate emitted twice sums to the
-- same total as one canonical member.
local function PublishedEntries(record)
    return #(record.echoes or {}) + #(record.lockedEchoes or {})
end

-- SEM-01 EXPECTED RED: cross-array duplicate must canonicalize to one member.
Case("SEM-01",
    "a cross-array duplicate canonicalizes to exactly one union member",
function()
    S.Bind(S.Database())
    Check(PutTerminal(LocalRecord("sem01",
        {{spellId=200100, quality=3, stacks=2, locked=true}},
        {{spellId=200100, quality=3, stacks=3}})),
        "the cross-array fixture was refused")
    local stored = Catalog().Get("sem01")
    Check(type(stored) == "table", "the cross-array record was not admitted")
    local published = PublishedEntries(stored)
    Check(published == 1,
        "the same semantic tuple was published as " .. published
            .. " separate entries; the source array is not identity")
    local members = UnionMembers(stored)
    Check(MemberCount(members) == 1 and members["200100:3:1"] == 5,
        "the canonical union did not merge the duplicate into one member of "
            .. "5 stacks: got " .. tostring(members["200100:3:1"]))
end)

-- SEM-02 EXPECTED RED: the canonical union rule must be LoadoutEvidence-owned.
Case("SEM-02",
    "the canonical union rule is owned by LoadoutEvidence",
function()
    local evidence = Nexus.LoadoutEvidence
    Check(type(evidence.CanonicalTupleOrder) == "function",
        "LoadoutEvidence does not own a canonical tuple order")
    local inline = {spellId=200100, quality=3, locked=true, origin="inline"}
    local lockedArray = {spellId=200100, quality=3, locked=true,
        origin="lockedArray"}
    Check(evidence.CanonicalTupleOrder(inline, lockedArray) == 0,
        "the canonical order distinguished two tuples by source array alone")
end)

-- SEM-03 EXPECTED RED: no tuple identity may rank the source array.
Case("SEM-03",
    "no tuple identity in the catalog ranks the source array",
function()
    local handle = assert(io.open("core/BuildCatalog.lua", "rb"))
    local text = handle:read("*a")
    handle:close()
    Check(not text:find('left.origin == "lockedArray"', 1, true),
        "CompareTuples still ranks tuples by their source array")
    Check(not text:find('(row.origin or "inline")', 1, true),
        "TupleKey still folds the source array into tuple identity")
end)

-- SEM-04 GUARD: the locked role is identity and must stay distinguished.
Case("SEM-04",
    "GUARD: the locked role remains part of canonical identity",
function()
    S.Bind(S.Database())
    Check(PutTerminal(LocalRecord("sem04",
        {{spellId=200200, quality=3, stacks=1}},
        {{spellId=200200, quality=3, stacks=1}})),
        "the mixed-role fixture was refused")
    local stored = Catalog().Get("sem04")
    Check(type(stored) == "table", "the mixed-role record was not admitted")
    Check(PublishedEntries(stored) == 2 and MemberCount(UnionMembers(stored)) == 2,
        "an ordinary and a locked tuple of the same spell collapsed into one "
            .. "member; the locked role is identity")
end)

-- SEM-05 GUARD: the exact 79/6/85 semantic envelope.
Case("SEM-05",
    "GUARD: exactly 79 ordinary and 6 locked admit, and 80 ordinary refuses",
function()
    S.Bind(S.Database())
    Check(PutTerminal(LocalRecord("sem05",
            S.Echoes(79, 0), S.Rows(6, {firstSpell=300000}))),
        "the exact 79/6/85 envelope was refused")
    local stored = Catalog().Get("sem05")
    Check(type(stored) == "table", "the 79/6/85 record was not admitted")
    local ok = PutTerminal(LocalRecord("sem05over",
        S.Echoes(80, 0), S.Rows(6, {firstSpell=300000})))
    Check(ok == false,
        "80 ordinary stacks were admitted past the 79/6/85 envelope")
end)

S.Finish("catalog authority semantic union")
