-- Stage 48.2: locked candidate evidence is counted by copies, not rows, and
-- survives the public CandidateEvidence -> Wishlist draft -> export path.
Nexus = {}
dofile("core/Codec.lua")
dofile("core/CandidateEvidence.lua")
dofile("core/WishlistModel.lua")

local Evidence = assert(Nexus.CandidateEvidence)
local Model = assert(Nexus.WishlistModel and Nexus.WishlistModel.New)()
local checks = 0

local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local ordinary = {
    {spellId=710001,quality=1,stacks=2,future={role="ordinary"}},
}
local duplicateSix = {
    {spellId=720001,quality=3,stacks=2,future={part="a"}},
    {spellId=720001,quality=3,stacks=2,future={part="b"}},
    {spellId=720001,quality=3,stacks=2,future={part="c"}},
}

local candidate, candidateReason = Evidence.Build({
    title="Counted locks",
    sourceIdentity="locked-copy-total",
    sourceRevision="1",
    ordinaryEchoes=ordinary,
    lockedEchoes=duplicateSix,
})
Check(candidate and candidateReason == nil
        and #candidate.lockedEchoes == 3,
    "valid duplicate exact rows did not survive candidate normalization")
Check(candidate.lockedEchoes[1].stacks == 2
        and candidate.lockedEchoes[3].future.part == "c"
        and candidate.lockedEchoes[1].locked == true
        and candidate.lockedEchoes[1].sourceRole == "locked",
    "candidate normalization lost stacks, provenance, or future fields")

local validated, validateReason = Evidence.Validate(candidate)
Check(validated and validateReason == nil
        and validated.lockedEchoes[2].future.part == "b",
    "counted candidate did not survive public validation")

local immutableCandidate = assert(Evidence.Build({
    title="Immutable future evidence",
    sourceIdentity="immutable-future",
    sourceRevision="1",
    ordinaryEchoes=ordinary,
    lockedEchoes={{spellId=720030,quality=2,stacks=1,
        future={provenance="original"}}},
}))
immutableCandidate.lockedEchoes[1].future.provenance = "mutated"
local immutableValidated = Evidence.Validate(immutableCandidate)
Check(immutableValidated
        and immutableValidated.lockedEchoes[1].future.provenance == "original",
    "candidate validation accepted mutated future/provenance evidence")

local categoryConflict = Evidence.ResolveLocked({
    ordinaryEchoes=ordinary,
    buildId="quality-conflict",
    fingerprint="710001x2",
    records={
        dummy={category="dummy",buildId="quality-conflict",
            fingerprint="710001x2",echoes=ordinary,
            lockedEchoes={{spellId=720031,quality=2,stacks=1}}},
        lk={category="lk",buildId="quality-conflict",
            fingerprint="710001x2",echoes=ordinary,
            lockedEchoes={{spellId=720031,quality=3,stacks=1}}},
    },
})
Check(categoryConflict.status == "conflict",
    "category resolver accepted contradictory exact locked quality")

local prepared, preparedReason = Model.NormalizeCandidateEvidence(
    validated.ordinaryEchoes, validated.lockedEchoes, {
        catalog={rows={
            [710001]={name="Ordinary",quality=1,maxStack=6},
            [720001]={name="Locked",quality=3,maxStack=6},
        }},
        lockedBySpell={},
    })
Check(prepared and preparedReason == nil
        and prepared.metrics.explicitLocked == 6,
    "Wishlist draft did not count six locked copies")
Check(prepared.pendingLock["explicit:720001:1"].future.part == "a"
        and prepared.pendingLock["explicit:720001:2"].stacks == 2
        and prepared.pendingLock["explicit:720001:3"].future.part == "c",
    "Wishlist draft collapsed duplicate evidence or dropped future fields")

local exported = Model.ExportEntries(
    prepared.pending, prepared.pendingLock, {}, {rows={}})
local lockedTotal, lockedRows, ordinaryTotal = 0, 0, 0
local futureParts = {}
for _, row in ipairs(exported) do
    if row.locked then
        lockedRows = lockedRows + 1
        lockedTotal = lockedTotal + row.stacks
        futureParts[row.future and row.future.part] = true
    else
        ordinaryTotal = ordinaryTotal + row.stacks
    end
end
Check(lockedRows == 3 and lockedTotal == 6
        and futureParts.a and futureParts.b and futureParts.c,
    "draft export changed locked stacks, duplicates, or future fields")
Check(ordinaryTotal == 2,
    "ordinary and locked copy totals were not kept separate")

local partialPending, partialLocks, partialFulfilled = Model.ReconcileLocked(
    prepared.pending, prepared.pendingLock, prepared.fulfilledTargets,
    {[720001]=1})
local partialCopies = 0
for _, row in pairs(partialLocks) do partialCopies = partialCopies + row.stacks end
Check(partialPending and partialCopies == 6
        and partialFulfilled[720001] == nil,
    "one locked copy fulfilled a six-copy exact requirement")
local countedCommit = Model.PlanLockCommit(
    partialPending, partialLocks, partialFulfilled, {}, {[720001]=1})
Check(type(countedCommit[720001]) == "table"
        and countedCommit[720001].copies == 6
        and #countedCommit[720001].rows == 3,
    "committed lock target collapsed counted duplicate evidence")
local reopened = Model.ApplyCommittedTargets({
    pending={ordinary={spellId=720001,quality=3,stacks=1}},
    pendingLock={},fulfilledTargets={},metrics={},
}, countedCommit, {catalog={rows={
    [720001]={name="Locked",quality=3,maxStack=6},
}},lockedBySpell={[720001]=1}})
local reopenedCopies, reopenedParts = 0, {}
for _, row in pairs(reopened.pendingLock) do
    reopenedCopies = reopenedCopies + row.stacks
    reopenedParts[row.future and row.future.part] = true
end
Check(reopened.pending.ordinary and not reopened.pending.ordinary.lockIntent
        and reopenedCopies == 6 and reopenedParts.a and reopenedParts.b
        and reopenedParts.c,
    "reopened counted target collapsed roles or provenance")

local fulfilledPrepared = assert(Model.NormalizeCandidateEvidence(
    validated.ordinaryEchoes, validated.lockedEchoes, {
        catalog={rows={
            [710001]={name="Ordinary",quality=1,maxStack=6},
            [720001]={name="Locked",quality=3,maxStack=6},
        }},
        lockedBySpell={[720001]=6},
    }))
local fulfilledExport = Model.ExportEntries(
    fulfilledPrepared.pending, fulfilledPrepared.pendingLock,
    {[720001]=6}, {rows={}}, fulfilledPrepared.fulfilledTargets)
local fulfilledRows, fulfilledParts = 0, {}
for _, row in ipairs(fulfilledExport) do
    if row.locked and row.spellId == 720001 then
        fulfilledRows = fulfilledRows + 1
        fulfilledParts[row.future and row.future.part] = true
    end
end
Check(fulfilledRows == 3 and fulfilledParts.a and fulfilledParts.b
        and fulfilledParts.c,
    "fulfilled locked evidence lost duplicate provenance/future rows on export")

local wire = Nexus.Codec.EncodeEBH1(exported, "MAGE", "Counted locks")
local decoded = Nexus.Codec.DecodeEBH1(wire)
local decodedLockedTotal, decodedLockedRows = 0, 0
for _, row in ipairs(decoded and decoded.entries or {}) do
    if row.locked then
        decodedLockedRows = decodedLockedRows + 1
        decodedLockedTotal = decodedLockedTotal + row.stacks
    end
end
Check(decodedLockedRows == 3 and decodedLockedTotal == 6,
    "EBH1 import/export lost duplicate locked rows or copy counts")

local oneSix = assert(Evidence.Build({
    title="One six-stack lock",sourceIdentity="one-six",sourceRevision="1",
    ordinaryEchoes=ordinary,
    lockedEchoes={{spellId=720002,quality=2,stacks=6}},
}))
Check(#oneSix.lockedEchoes == 1 and oneSix.lockedEchoes[1].stacks == 6,
    "one exact six-copy locked row was rejected or clamped")

local sevenRows = {
    {spellId=720010,quality=1,stacks=2},
    {spellId=720011,quality=1,stacks=2},
    {spellId=720012,quality=1,stacks=2},
    {spellId=720013,quality=1,stacks=1},
}
local seven, sevenReason = Evidence.Build({
    title="Seven copies",sourceIdentity="seven",sourceRevision="1",
    ordinaryEchoes=ordinary,lockedEchoes=sevenRows,
})
Check(seven == nil and tostring(sevenReason):find("six", 1, true),
    "seven locked copies were accepted because they used only four rows")
local sevenDraft, sevenDraftReason = Model.NormalizeCandidateEvidence(
    ordinary, sevenRows, {catalog={rows={}},lockedBySpell={}})
Check(sevenDraft == nil
        and tostring(sevenDraftReason):find("six", 1, true),
    "Wishlist accepted seven locked copies")

for label, stacks in pairs({zero=0,fraction=1.5,nan=0/0,infinite=math.huge}) do
    local malformed, reason = Evidence.Build({
        title=label,sourceIdentity=label,sourceRevision="1",
        ordinaryEchoes=ordinary,
        lockedEchoes={{spellId=720020,quality=1,stacks=stacks}},
    })
    Check(malformed == nil and tostring(reason):find("invalid", 1, true),
        "malformed locked stack escaped fail-closed validation: " .. label)
end

local budget = Model.LockBudgetUsed(
    {intent={spellId=730001,stacks=1,lockIntent=true}},
    {evidence={spellId=730002,stacks=3,explicitEvidence=true}},
    {[730003]=2})
Check(budget == 6,
    "locked budget counted identities instead of copies")

-- Persisted counted targets are an authority boundary.  Scalar legacy values
-- remain one-copy compatible, but table records must match the current dense
-- schema exactly rather than degrading to a one-copy action.
Check(Model.TargetCopies(true) == 1 and Model.TargetCopies(720099) == 1,
    "legacy scalar lock targets lost one-copy compatibility")
for label, record in pairs({
    future={version=2,copies=1,rows={{spellId=720099,stacks=1}}},
    missingVersion={copies=1,rows={{spellId=720099,stacks=1}}},
    fractional={version=1,copies=1.5,rows={{spellId=720099,stacks=1}}},
    sparse={version=1,copies=1,rows={[2]={spellId=720099,stacks=1}}},
    mismatched={version=1,copies=2,rows={{spellId=720099,stacks=1}}},
}) do
    Check(Model.TargetCopies(record) == nil,
        "malformed/future persisted target failed open: " .. label)
end

print(string.format(
    "locked copy totals: duplicate=2+2+2 one=6 rejected=7/malformed roles=separate checks=%d -- OK",
    checks))
