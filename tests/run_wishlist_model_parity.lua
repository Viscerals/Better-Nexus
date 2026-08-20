-- Golden and authority-isolation coverage for the pure Wishlist model.
Nexus = {}
dofile("core/Codec.lua")
dofile("core/WishlistModel.lua")

local W = assert(Nexus.WishlistModel and Nexus.WishlistModel.New)()
local checks = 0

local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Count(map)
    local count = 0
    for _ in pairs(map or {}) do count = count + 1 end
    return count
end

local function Clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, field in pairs(value) do out[Clone(key, seen)] = Clone(field, seen) end
    return out
end

local function Same(a, b, path, seen)
    path = path or "value"
    if type(a) ~= type(b) then error(path .. " type mismatch", 2) end
    if type(a) ~= "table" then
        if a ~= b then error(path .. " mismatch: " .. tostring(a) .. " ~= " .. tostring(b), 2) end
        return
    end
    seen = seen or {}
    if seen[a] == b then return end
    seen[a] = b
    for key, value in pairs(a) do
        if b[key] == nil and value ~= nil then error(path .. " missing key " .. tostring(key), 2) end
        Same(value, b[key], path .. "." .. tostring(key), seen)
    end
    for key, value in pairs(b) do
        if a[key] == nil and value ~= nil then error(path .. " unexpected key " .. tostring(key), 2) end
    end
end

local catalog = {rows={}}
local function Row(id, name, quality, groupId, maxStack)
    catalog.rows[id] = {
        spellId=id, name=name, quality=quality, groupId=groupId,
        maxStack=maxStack or 1,
    }
end
Row(1001, "|cff00ff00Alpha|r", 1, 10, 2)
Row(1002, "Alpha", 3, 10, 3)
Row(1003, "Twin", 2, 20, 1)
Row(1004, "Twin", 4, 21, 1)
Row(1005, "Beta", 2, 30, 1)
Row(1006, "Gamma", 4, 40, 1)
Row(1007, "Delta", 1, 50, 1)
Row(1010, "Old Lock", 3, 60, 1)

Check(W.NormalizeEchoName("  |cff00ff00AlPhA|r   Echo ") == "alpha echo",
    "name normalization drifted")
Check(W.Family(1001, catalog) == W.Family(1002, catalog),
    "quality siblings no longer share a family")
Check(W.Family(1003, catalog) ~= W.Family(1004, catalog),
    "same-name different-group Echoes collapsed")
Check(W.Family(9999, catalog) == "s:9999", "unknown spell fallback changed")
Check(W.MaxStack(1002, catalog) == 3 and W.EchoListTotal({{stacks=2},{stacks=3}}) == 5,
    "stack helpers changed")

local imported = {
    {spellId=1001, quality=0, stacks=2, future={keep=true}},
    {spellId=1002, quality=0, stacks=3},
    {spellId=1003, quality=2, stacks=1},
    {spellId=1004, quality=4, stacks=1},
    {spellId=1005, quality=0, stacks=1, locked=true},
    {spellId=1006, quality=0, stacks=1, locked=true},
}
local importedBefore = Clone(imported)
local basePrepared = W.NormalizeDraft(imported, {
    catalog=catalog,
    lockedBySpell={[1006]=1,[1010]=1},
    trustOrder=true,
})
local baseBeforeCommit = Clone(basePrepared)
local prepared = W.ApplyCommittedTargets(basePrepared, {[1007]=true}, {
    catalog=catalog,
    lockedBySpell={[1006]=1,[1010]=1},
})
Same(imported, importedBefore, "imported input")
Same(basePrepared, baseBeforeCommit, "base draft before committed-target application")
local alpha = prepared.pending[W.Family(1002, catalog)]
Check(alpha and alpha.spellId == 1002 and alpha.quality == 3 and alpha.stacks == 3,
    "quality-family canonicalization changed")
Check(prepared.pending[W.Family(1003, catalog)]
    and prepared.pending[W.Family(1004, catalog)],
    "same-name distinct groups were lost")
local beta = prepared.pending[W.Family(1005, catalog)]
Check(beta and beta.lockIntent and beta.replaces == 1010 and beta.stacks == 1,
    "explicit locked target or deterministic replacement pairing changed")
Check(prepared.fulfilledTargets[1006] == true,
    "fulfilled explicit lock target was lost")
Check(prepared.pendingLock[W.Family(1007, catalog)]
    and prepared.pendingLock[W.Family(1007, catalog)].spellId == 1007,
    "committed queued target was not reconstructed")
Check(prepared.metrics.lockedSkipped == 1 and prepared.metrics.swapPairs == 1,
    "normalization metrics changed")

local overflowCatalog = {rows={}}
local overflow = {}
for i = 1, 86 do
    local id = 2000 + i
    overflowCatalog.rows[id] = {spellId=id, name="Echo " .. tostring(i), quality=i % 5,
        groupId=id, maxStack=1}
    overflow[#overflow + 1] = {spellId=id, quality=i % 5, stacks=1, future="keep"}
end
local overflowBefore = Clone(overflow)
local untrusted = W.NormalizeDraft(overflow, {catalog=overflowCatalog, trustOrder=false})
Check(Count(untrusted.pending) == 79 and Count(untrusted.pendingLock) == 0
    and untrusted.metrics.untrustedOverflowSkipped == 7,
    "untrusted overflow no longer fails closed")
local trusted = W.NormalizeDraft(overflow, {catalog=overflowCatalog, trustOrder=true})
Check(Count(trusted.pending) == 79 and Count(trusted.pendingLock) == 6
    and trusted.metrics.overflowSkipped == 7
    and trusted.metrics.lockBudgetExceeded == 1,
    "trusted 79 plus 6 normalization changed")
Same(overflow, overflowBefore, "overflow input")

local collisionInput = {}
for i = 1, 79 do collisionInput[i] = overflow[i] end
collisionInput[80] = {spellId=1001, quality=0, stacks=1, locked=true}
collisionInput[81] = {spellId=1002, quality=0, stacks=1, locked=true}
local collision = W.NormalizeDraft(collisionInput, {catalog=catalog, trustOrder=true})
local collisionRow = collision.pendingLock[W.Family(1001, catalog)]
Check(collisionRow and collisionRow.spellId == 1002 and collisionRow.quality == 3
    and collision.metrics.lockDesignCollisions == 1,
    "locked family collision no longer keeps the higher catalog quality")

local typedOrdinary = {
    {spellId=1001,quality=1,stacks=2,future={keep=true}},
    {spellId=1003,quality=2,stacks=1},
}
local typedLocked = {
    {spellId=1001,quality=1,stacks=2,future={role="locked"}},
    {spellId=1002,quality=3,stacks=1},
}
local typedOrdinaryBefore, typedLockedBefore = Clone(typedOrdinary), Clone(typedLocked)
local typed = assert(W.NormalizeCandidateEvidence(typedOrdinary, typedLocked, {
    catalog=catalog,lockedBySpell={[1001]=1,[1010]=1},
}))
Check(typed.pending[W.Family(1001,catalog)]
    and typed.pending[W.Family(1001,catalog)].stacks == 2
    and typed.fulfilledTargets[1001] == true,
    "typed ordinary/locked overlap lost one role")
Check(Count(typed.pendingLock) == 1
    and typed.pendingLock["explicit:1002"]
    and typed.pendingLock["explicit:1002"].spellId == 1002,
    "typed locked family collision lost an explicit identity")
Check(typed.metrics.explicitLocked == 2
    and typed.metrics.explicitFulfilled == 1,
    "typed evidence metrics changed")
Same(typedOrdinary, typedOrdinaryBefore, "typed ordinary input")
Same(typedLocked, typedLockedBefore, "typed locked input")
local invalidTyped = {}
for index = 1, 80 do
    invalidTyped[index] = {spellId=5000+index,quality=0,stacks=1}
end
local invalidPrepared, invalidReason = W.NormalizeCandidateEvidence(
    invalidTyped, {}, {catalog={rows={}},lockedBySpell={}})
Check(invalidPrepared == nil
    and invalidReason == "ordinary Echo evidence exceeds the 79-copy limit",
    "ambiguous 80-copy typed evidence did not fail closed")
local scalarOk, scalarPrepared, scalarReason = pcall(
    W.NormalizeCandidateEvidence, {1001}, {},
    {catalog=catalog,lockedBySpell={}})
Check(scalarOk and scalarPrepared == nil
    and scalarReason == "ordinary Echo evidence is invalid",
    "malformed ordinary typed evidence escaped fail-closed handling")
local lockedScalarOk, lockedScalarPrepared, lockedScalarReason = pcall(
    W.NormalizeCandidateEvidence, typedOrdinary, {1002},
    {catalog=catalog,lockedBySpell={}})
Check(lockedScalarOk and lockedScalarPrepared == nil
    and lockedScalarReason == "locked Echo evidence is invalid",
    "malformed locked typed evidence escaped fail-closed handling")
local qualityPrepared, qualityReason = W.NormalizeCandidateEvidence(
    {{spellId=1001,quality=1.5,stacks=1}}, {},
    {catalog=catalog,lockedBySpell={}})
Check(qualityPrepared == nil and qualityReason == "ordinary Echo evidence is invalid",
    "fractional typed quality escaped fail-closed handling")
local collisionLocks = {
    ["explicit:1001"]={spellId=1001,family="collision",quality=1},
    ["explicit:1002"]={spellId=1002,family="collision",quality=3},
}
local _, remainingLocks, exactRemove = W.RemovePending(
    {}, collisionLocks, "explicit:1002")
Check(exactRemove == "removed_lock" and remainingLocks["explicit:1001"]
    and not remainingLocks["explicit:1002"],
    "explicit family collision removal lost exact draft identity")

local originalPending = {a={spellId=3001,family="a",quality=1,stacks=1,maxStack=3,future="keep"}}
local unchanged, invalidOutcome = W.AddPending(originalPending, nil, {})
Check(unchanged == originalPending and invalidOutcome == "invalid",
    "invalid add was not an identity-preserving no-op")
local adjusted, adjustedOutcome = W.AdjustStacks(originalPending, "a", 1)
Check(adjustedOutcome == "adjusted" and adjusted ~= originalPending
    and adjusted.a.stacks == 2 and originalPending.a.stacks == 1
    and adjusted.a.future == "keep",
    "immutable stack transition changed or dropped future fields")
local lockedReject, lockedOutcome = W.AddPending(originalPending,
    {spellId=3002,name="Locked",quality=2,maxStack=1},
    {catalog={rows={[3002]={spellId=3002,name="Locked",quality=2,groupId=3002,maxStack=1}}},
        lockedBySpell={[3002]=1}})
Check(lockedReject == originalPending and lockedOutcome == "already_locked",
    "already-locked add guard changed")

local sixLocked = {}
for i = 1, 6 do sixLocked[4000 + i] = 1 end
local togglePending = {a={spellId=3001,family="a",quality=1,stacks=1,maxStack=1}}
local toggleResult, _, replacement, toggleOutcome = W.ToggleDesignLock(
    togglePending, {}, "a", {lockedBySpell=sixLocked,replacingSpellId=nil})
Check(toggleResult == togglePending and replacement == nil and toggleOutcome == "lock_full",
    "six-slot lock budget guard changed")
local replacedResult, _, replacedNext, replacedOutcome = W.ToggleDesignLock(
    togglePending, {}, "a", {lockedBySpell=sixLocked,replacingSpellId=4001})
Check(replacedOutcome == "tagged" and replacedNext == nil
    and replacedResult.a.lockIntent and replacedResult.a.replaces == 4001
    and not togglePending.a.lockIntent,
    "full-budget replacement transition changed or mutated its input")

local canonical = W.CanonicalEchoes({
    b={spellId=3002,quality=2,stacks=9,maxStack=2},
    a={spellId=3001,quality=1,stacks=1,maxStack=1},
    c={spellId=3003,quality=3,stacks=1,maxStack=1,lockIntent=true},
})
Same(canonical, {
    {spellId=3001,quality=1,stacks=1},
    {spellId=3002,quality=2,stacks=2},
}, "canonical upload")

local exportCatalog = {rows={
    [3001]={quality=1}, [3003]={quality=3}, [4001]={quality=4},
}}
local exportEntries = W.ExportEntries(
    {a={spellId=3001,quality=1,stacks=2,maxStack=2}},
    {c={spellId=3003,quality=3,stacks=1}},
    {[4001]=1}, exportCatalog)
local encoded = Nexus.Codec.EncodeEBH1(exportEntries, "MAGE", "Golden")
Check(encoded == "EBH1:3001.1.2,3003.3.1.1,4001.4.1.1:MAGE:Golden",
    "EBH1 export bytes changed")
local overlapExport = W.ExportEntries(
    {ordinary={spellId=3001,quality=1,stacks=1,maxStack=1}},
    {locked={spellId=3001,quality=1,stacks=1}}, {}, exportCatalog)
Check(#overlapExport == 2 and overlapExport[1].spellId == 3001
    and not overlapExport[1].locked and overlapExport[2].spellId == 3001
    and overlapExport[2].locked,
    "export collapsed an ordinary/locked typed overlap")

local commitPending = {
    a={spellId=3001,lockIntent=true,replaces=4001},
}
local commitLock = {b={spellId=3002}}
local commitFresh = W.PlanLockCommit(commitPending, commitLock,
    {[4003]=true}, {[4001]=true,[4002]=true}, {[4001]=1,[4002]=1,[4003]=1})
Same(commitFresh, {[3001]=4001,[3002]=true,[4002]=true,[4003]=true}, "lock commit plan")
Check(not commitFresh[4001], "replaced fulfilled target survived commit planning")

local reconciledPending, reconciledLock, reconciledFulfilled = W.ReconcileLocked(
    {a={spellId=3001,lockIntent=true,replaces=4001},z={spellId=3999}},
    {b={spellId=3002,replaces=4002}}, {}, {[3001]=1,[3002]=1})
Check(not reconciledPending.a and reconciledPending.z and not reconciledLock.b
    and reconciledFulfilled[3001] == 4001 and reconciledFulfilled[3002] == 4002,
    "fulfilled lock reconciliation changed")

Check(W.TrimName("  Imported Golden  ") == "Imported Golden",
    "wishlist-name trim changed")

local modelSource = assert(io.open("core/WishlistModel.lua", "rb")):read("*a")
for _, forbidden in ipairs({
    "NexusDB", "Nexus.Store", "GameAdapter", "Adapter.", "ProjectEbonhold",
    "CreateFrame", "StaticPopup", "print(", "EncodeEBH1", "DecodeEBH1",
}) do
    Check(not modelSource:find(forbidden, 1, true),
        "WishlistModel acquired forbidden authority: " .. forbidden)
end

local editorSource = assert(io.open("ui/WishlistEditor.lua", "rb")):read("*a")
for _, removed in ipairs({
    "local function NormalizeEchoName", "local function PendingFamily",
    "local function PendingMaxStack", "local fresh, replaced = {}, {}",
    "table.sort(echoes, function(a, b)",
}) do
    Check(not editorSource:find(removed, 1, true),
        "WishlistEditor retained a parallel model body: " .. removed)
end
Check(select(2, editorSource:gsub("WishlistModelFactory%.New%(%)", "")) == 1,
    "WishlistEditor does not reuse exactly one model instance")
local controllerSource = assert(io.open("core/WishlistController.lua", "rb")):read("*a")
local loadStart = assert(controllerSource:find("function M.LoadPendingEchoes", 1, true))
local loadEnd = assert(controllerSource:find("function M.SeedPendingFromWishlist", loadStart, true))
local loadSource = controllerSource:sub(loadStart, loadEnd - 1)
local warningAt = assert(loadSource:find("PublishLoadMetrics()", 1, true))
local committedAt = assert(loadSource:find("DraftModel.ApplyCommittedTargets", 1, true))
Check(warningAt < committedAt,
    "legacy committed-target migration moved before normalization diagnostics")
local addStart = assert(controllerSource:find("function M.AddPending", 1, true))
local addEnd = assert(controllerSource:find("function M.RemovePending", addStart, true))
local addSource = controllerSource:sub(addStart, addEnd - 1)
Check(assert(addSource:find("if not row or not tonumber(row.spellId) then return", 1, true))
    < assert(addSource:find("local lockedBySpell = LockedBySpell()", 1, true)),
    "invalid add now reaches Adapter before its established no-op")
Check(assert(addSource:find("lockedBySpell[tonumber(row.spellId)]", 1, true))
    < assert(addSource:find("catalog = Catalog()", 1, true)),
    "already-locked add now reaches the catalog before its established rejection")

local toc = assert(io.open("Nexus.toc", "rb")):read("*a")
local modelAt = assert(toc:find("core\\WishlistModel.lua", 1, true))
local controllerAt = assert(toc:find("core\\WishlistController.lua", 1, true))
local editorAt = assert(toc:find("ui\\WishlistEditor.lua", 1, true))
Check(modelAt < controllerAt and controllerAt < editorAt,
    "Wishlist model/controller/editor TOC order changed")

print(string.format("wishlist model golden, immutability, authority, and facade parity -- OK (checks=%d)", checks))
