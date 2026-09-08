-- Package B / issue #22 Repair Wave 1: MASTER-RC-016, tombstone replacement.
--
-- Root: "row-to-tombstone replacement drops top-level and tuple-scoped unknown
--  fields."
-- Required repaired outcome: "unknown evidence carried in the atomic
--  transaction and restored by scope, or fail closed."
--
-- Measured defect before the repair: a durable overlay row carrying
-- futureTopLevel and echoes[1].futureTuple lost both when it was tombstoned --
-- the durable row disappeared entirely and the tombstone record's keys were
-- exactly schemaVersion, typedId, ownerKey, sourceKind, sourceIdentity,
-- targetRowGeneration, targetRowProvenance, receiptRevision,
-- receiptAtServerTime and remoteStampEvidence, with no unknown evidence at all.
-- A delete therefore destroyed future-owned evidence.
--
-- UNK-04 and UNK-05 are guards: they pass before the repair and after it.
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

local function BindRowWithUnknown(id)
    local row = S.LocalBuild(id, 2)
    row.futureTopLevel = {keep="top", ordinal=7}
    row.echoes[1].futureTuple = {keep="tuple"}
    local db = S.Database({[id]=row})
    S.Bind(db)
    Check(Catalog().RootState().state == "ROOT_ADMITTED",
        "fixture did not admit a root")
    local durable = H.DurableBuilds(db)[id]
    Check(type(durable) == "table"
            and durable.futureTopLevel ~= nil
            and durable.echoes[1].futureTuple ~= nil,
        "fixture row did not retain its unknown evidence before the delete")
    return db, row
end

-- UNK-01 EXPECTED RED: top-level unknown evidence must survive the delete.
Case("UNK-01",
    "top-level unknown evidence survives a row-to-tombstone replacement",
function()
    local db = BindRowWithUnknown("unk01")
    Check(Catalog().SetTombstone("unk01", {stamp=5}, {source="local"}),
        "the fixture delete was refused")
    local record = H.DurableTombstones(db)["unk01"]
    Check(type(record) == "table", "no durable tombstone was written")
    Check(type(record.unknownEvidence) == "table"
            and type(record.unknownEvidence.top) == "table"
            and record.unknownEvidence.top.futureTopLevel ~= nil
            and record.unknownEvidence.top.futureTopLevel.keep == "top",
        "the tombstone dropped the row's top-level unknown evidence")
end)

-- UNK-02 EXPECTED RED: tuple-scoped unknown evidence must survive, scoped.
Case("UNK-02",
    "tuple-scoped unknown evidence survives and stays at tuple scope",
function()
    local db = BindRowWithUnknown("unk02")
    Check(Catalog().SetTombstone("unk02", {stamp=5}, {source="local"}),
        "the fixture delete was refused")
    local record = H.DurableTombstones(db)["unk02"]
    Check(type(record) == "table" and type(record.unknownEvidence) == "table",
        "no unknown evidence was carried")
    local tuples = record.unknownEvidence.tuples
    Check(type(tuples) == "table", "tuple-scoped unknown evidence was dropped")
    local found = false
    for _, subtree in pairs(tuples) do
        if type(subtree) == "table" and subtree.futureTuple ~= nil
            and subtree.futureTuple.keep == "tuple" then
            found = true
        end
    end
    Check(found, "the exact tuple unknown subtree was not carried at its scope")
    -- Scope is preserved: a tuple subtree is not promoted to top level.
    Check(record.unknownEvidence.top == nil
            or record.unknownEvidence.top.futureTuple == nil,
        "tuple-scoped unknown evidence was promoted to top-level scope")
end)

-- UNK-03 EXPECTED RED: restored by scope on readmission.
Case("UNK-03",
    "readmission restores carried unknown evidence at its original scope",
function()
    local db = BindRowWithUnknown("unk03")
    Check(Catalog().SetTombstone("unk03", {stamp=5}, {source="local"}),
        "the fixture delete was refused")
    local claim, why = Catalog().BeginTombstoneReadmissionClaim("unk03")
    Check(claim ~= nil, "readmission claim was refused: " .. tostring(why))
    local replacement = S.LocalBuild("unk03", 2)
    local ok, putWhy = Catalog().PutWithClaim(claim, replacement,
        {source="local"})
    Check(ok, "readmission was refused: " .. tostring(putWhy))
    local durable = H.DurableBuilds(db)["unk03"]
    Check(type(durable) == "table", "readmission wrote no durable row")
    Check(durable.futureTopLevel ~= nil
            and durable.futureTopLevel.keep == "top",
        "top-level unknown evidence was not restored on readmission")
    Check(type(durable.echoes) == "table" and durable.echoes[1] ~= nil
            and durable.echoes[1].futureTuple ~= nil
            and durable.echoes[1].futureTuple.keep == "tuple",
        "tuple-scoped unknown evidence was not restored at tuple scope")
end)

-- UNK-04 GUARD: the tombstone's fixed known shape is unchanged.
Case("UNK-04",
    "GUARD: the tombstone keeps its exact fixed known shape",
function()
    local db = BindRowWithUnknown("unk04")
    Check(Catalog().SetTombstone("unk04", {stamp=9}, {source="local"}),
        "the fixture delete was refused")
    local record = H.DurableTombstones(db)["unk04"]
    Check(type(record) == "table", "no durable tombstone was written")
    for _, field in ipairs({"schemaVersion", "typedId", "ownerKey",
        "sourceKind", "sourceIdentity", "targetRowGeneration",
        "targetRowProvenance", "receiptRevision", "receiptAtServerTime",
        "remoteStampEvidence"}) do
        Check(record[field] ~= nil,
            "the tombstone lost its known field " .. field)
    end
    Check(record.remoteStampEvidence == 9,
        "the tombstone lost its exact remote stamp evidence")
end)

-- UNK-05 GUARD: a row with no unknown evidence carries none.
Case("UNK-05",
    "GUARD: a row owning no unknown evidence carries none",
function()
    local db = S.Database({unk05=S.LocalBuild("unk05", 2)})
    S.Bind(db)
    Check(Catalog().SetTombstone("unk05", {stamp=3}, {source="local"}),
        "the fixture delete was refused")
    local record = H.DurableTombstones(db)["unk05"]
    Check(type(record) == "table", "no durable tombstone was written")
    Check(record.unknownEvidence == nil,
        "a row with no unknown evidence invented an unknown carriage")
end)

S.Finish("catalog authority unknown field carriage")
