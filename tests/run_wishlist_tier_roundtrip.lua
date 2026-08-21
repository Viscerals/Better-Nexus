-- WP4 #43: ordinary Wishlist rows are exact spell/tier identities. Family is
-- grouping metadata and must never collapse or retarget a sibling row.
Nexus = {}
dofile("core/Codec.lua")
dofile("core/WishlistModel.lua")

local Model = assert(Nexus.WishlistModel and Nexus.WishlistModel.New)()
local checks = 0

local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Count(map)
    local count = 0
    for _ in pairs(type(map) == "table" and map or {}) do count = count + 1 end
    return count
end

local function KeyFor(pending, spellId)
    local found
    for key, row in pairs(type(pending) == "table" and pending or {}) do
        if tonumber(row and row.spellId) == spellId then
            assert(found == nil, "exact spell appears under multiple draft keys")
            found = key
        end
    end
    return found
end

local catalog = {rows={}}
local function Row(id, quality, maxStack)
    catalog.rows[id] = {
        spellId=id,name="Shared Echo",quality=quality,groupId=77,
        maxStack=maxStack or 79,
    }
end
Row(7101, 1)
Row(7102, 2)
Row(7103, 3)

local source = {
    {spellId=7101,quality=1,stacks=1},
    {spellId=7102,quality=2,stacks=2},
    {spellId=7103,quality=3,stacks=3},
}
local prepared = Model.NormalizeDraft(source, {
    catalog=catalog,lockedBySpell={},trustOrder=false,
})
Check(Count(prepared.pending) == 3,
    "same-family exact tiers collided during draft normalization")

local commonKey = KeyFor(prepared.pending, 7101)
local uncommonKey = KeyFor(prepared.pending, 7102)
local rareKey = KeyFor(prepared.pending, 7103)
Check(commonKey ~= nil and uncommonKey ~= nil and rareKey ~= nil
    and commonKey ~= uncommonKey and uncommonKey ~= rareKey
    and commonKey ~= rareKey,
    "same-family exact tiers do not have independent draft identities")

local ambiguous, ambiguousOutcome = Model.AdjustStacks(
    prepared.pending, Model.Family(7101, catalog), 1)
Check(ambiguous == prepared.pending and ambiguousOutcome == "unchanged",
    "ambiguous compatibility family handle selected an arbitrary exact tier")

local adjusted, adjustOutcome = Model.AdjustStacks(
    prepared.pending, uncommonKey, 1)
Check(adjustOutcome == "adjusted"
    and adjusted[uncommonKey].stacks == 3
    and adjusted[commonKey].stacks == 1
    and adjusted[rareKey].stacks == 3,
    "adjusting one exact tier modified or lost a sibling tier")

local remaining, remainingLocks, removeOutcome = Model.RemovePending(
    adjusted, prepared.pendingLock, commonKey)
Check(removeOutcome == "removed" and remainingLocks == prepared.pendingLock
    and remaining[commonKey] == nil
    and remaining[uncommonKey] and remaining[rareKey],
    "removing one exact tier modified or lost a sibling tier")

local canonical = Model.CanonicalEchoes(prepared.pending)
Check(#canonical == 3
    and canonical[1].spellId == 7101 and canonical[1].stacks == 1
    and canonical[2].spellId == 7102 and canonical[2].stacks == 2
    and canonical[3].spellId == 7103 and canonical[3].stacks == 3,
    "no-op canonical round-trip lost exact same-family tiers")

local exported = Model.ExportEntries(prepared.pending, {}, {}, catalog)
local encoded = Nexus.Codec.EncodeEBH1(exported, "MAGE", "Exact tiers")
local decoded = assert(Nexus.Codec.DecodeEBH1(encoded))
local reloaded = Model.NormalizeCandidateEvidence(decoded.entries, {}, {
    catalog=catalog,lockedBySpell={},
})
Check(reloaded and Count(reloaded.pending) == 3
    and KeyFor(reloaded.pending, 7101)
    and KeyFor(reloaded.pending, 7102)
    and KeyFor(reloaded.pending, 7103),
    "supported export/import round-trip collapsed same-family tiers")

local budgetRows, budgetCatalog = {}, {rows={}}
for index = 1, 79 do
    local id = 8000 + index
    budgetCatalog.rows[id] = {
        spellId=id,name="Budget " .. tostring(index),quality=1,
        groupId=id,maxStack=1,
    }
    budgetRows[index] = {spellId=id,quality=1,stacks=1}
end
local budget = Model.NormalizeDraft(budgetRows, {
    catalog=budgetCatalog,lockedBySpell={},trustOrder=false,
})
Check(Model.PendingTotal(budget.pending) == 79,
    "ordinary exact-row total no longer preserves the 79-copy budget")
local full, fullOutcome = Model.AddPending(budget.pending, catalog.rows[7101], {
    catalog=catalog,lockedBySpell={},
})
Check(full == budget.pending and fullOutcome == "full",
    "ordinary exact-row add exceeded the 79-copy budget")

-- The frame-free editor controller must carry the exact action handle through
-- its public draft/action surface; UI buttons consume these same map keys.
dofile("core/WishlistController.lua")
local Controller = assert(Nexus.WishlistInternals.Controller)
local controller = Controller.New({
    model=Model,
    store={State=function() return {} end},
    accountRoot=function() return {} end,
    notify=function() end,
})
controller.Initialize({
    Catalog=function() return catalog end,
    LockedOwned=function() return {bySpell={}} end,
    WishlistKey=function(echoes) return "tiers:" .. tostring(#echoes) end,
})
Check(controller.BeginCandidate({title="Exact tiers",echoes=source}),
    "controller rejected representable exact-tier candidate")
local controllerRows = controller.PendingRows()
local controllerCommon = KeyFor(controllerRows, 7101)
local controllerUncommon = KeyFor(controllerRows, 7102)
local controllerRare = KeyFor(controllerRows, 7103)
Check(Count(controllerRows) == 3 and controllerCommon and controllerUncommon
    and controllerRare,
    "controller open collapsed same-family exact tiers")
Check(controller.AdjustStacks(controllerUncommon, 1) == "adjusted",
    "controller could not adjust one exact tier")
controller.RemovePending(controllerCommon)
local controllerCanonical = controller.CanonicalEchoes()
Check(#controllerCanonical == 2
    and controllerCanonical[1].spellId == 7102
    and controllerCanonical[1].stacks == 3
    and controllerCanonical[2].spellId == 7103
    and controllerCanonical[2].stacks == 3,
    "controller exact action modified or lost a sibling tier")

print(string.format("wishlist exact-tier round-trip -- OK (checks=%d)", checks))
