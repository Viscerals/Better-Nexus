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
for label, key in pairs({fractional=1.5,infinite=math.huge,zero=0,negative=-1}) do
    Check(Model.TargetCopies(true, key) == nil,
        "invalid containing target key authorized legacy value: " .. label)
end
for label, scalar in pairs({
    falseValue=false,stringValue="future",fraction=1.5,
    nan=0/0,infinite=math.huge,negative=-1,zero=0,
}) do
    Check(Model.TargetCopies(scalar) == nil,
        "unsupported legacy scalar target failed open: " .. label)
end
for label, record in pairs({
    future={version=2,copies=1,rows={{spellId=720099,stacks=1}}},
    missingVersion={copies=1,rows={{spellId=720099,stacks=1}}},
    fractional={version=1,copies=1.5,rows={{spellId=720099,stacks=1}}},
    sparse={version=1,copies=1,rows={[2]={spellId=720099,stacks=1}}},
    mismatched={version=1,copies=2,rows={{spellId=720099,stacks=1}}},
    mixedSpell={version=1,copies=2,rows={
        {spellId=720099,stacks=1},{spellId=720098,stacks=1},
    }},
    stringReplacement={version=1,copies=1,replaces="720098",
        rows={{spellId=720099,stacks=1}}},
}) do
    Check(Model.TargetCopies(record) == nil,
        "malformed/future persisted target failed open: " .. label)
end

local validTargetEntries, validTargetTotal = Model.TargetMapEntries({
    [750001]={version=1,copies=3,rows={{spellId=750001,stacks=3}}},
    [750002]={version=1,copies=3,rows={{spellId=750002,stacks=3}}},
})
Check(validTargetEntries and #validTargetEntries == 2
        and validTargetTotal == 6,
    "valid six-copy target map failed shared admission")
Check(Model.TargetMapEntries({
    [750001]={version=1,copies=4,rows={{spellId=750001,stacks=4}}},
    [750002]={version=1,copies=3,rows={{spellId=750002,stacks=3}}},
}) == nil, "seven-copy target map escaped shared admission")
Check(Model.TargetMapEntries({[750001]=true,["750001"]=true}) == nil,
    "canonical target-key aliases escaped shared admission")
Check(Model.TargetCopies(750001, 750001) == nil
        and Model.TargetCopies({version=1,copies=1,replaces=750001,
            rows={{spellId=750001,stacks=1}}}, 750001) == nil,
    "self replacement escaped target validation")
for label, replacement in pairs({
    stringValue="750010",fraction=1.5,nan=0/0,
    infinite=math.huge,zero=0,negative=-1,
}) do
    Check(Model.TargetCopies({version=1,copies=1,replaces=750010,
        rows={{spellId=750001,stacks=1,replaces=replacement}}}, 750001) == nil,
        "invalid row replacement escaped validation: " .. label)
end
Check(Model.TargetCopies({version=1,copies=1,replaces=750010,
        rows={{spellId=750001,stacks=1,replaces=750011}}}, 750001) == nil,
    "top-level replacement absent from row evidence escaped validation")

local multiReplacement = {version=1,copies=3,replaces=750010,rows={
    {spellId=750001,stacks=1,replaces=750010},
    {spellId=750001,stacks=1,replaces=750011},
    {spellId=750001,stacks=1,replaces=750012},
}}
local replacementList = Model.TargetReplacements(multiReplacement, 750001)
Check(replacementList and #replacementList == 3
        and replacementList[1] == 750010
        and replacementList[2] == 750011
        and replacementList[3] == 750012,
    "counted target lost its ordered replacement set: "
        .. tostring(replacementList and #replacementList) .. "/"
        .. tostring(replacementList and replacementList[1]) .. "/"
        .. tostring(replacementList and replacementList[2]) .. "/"
        .. tostring(replacementList and replacementList[3]))
local permutedReplacement = {version=1,copies=3,replaces=750010,rows={
    {spellId=750001,stacks=1,replaces=750012},
    {spellId=750001,stacks=1,replaces=750010},
    {spellId=750001,stacks=1,replaces=750011},
}}
local permutedList = Model.TargetReplacements(permutedReplacement, 750001)
Check(Model.TargetCopies(permutedReplacement, 750001) == 3
        and permutedList[1] == 750010 and permutedList[2] == 750011
        and permutedList[3] == 750012,
    "replacement identity depended on counted-row order")
local tokenSource = {[750001]={version=1,copies=1,
    rows={{spellId=750001,stacks=1}}}}
local tokenOne = Model.TargetMapToken(tokenSource)
tokenSource[750001].copies = 3
tokenSource[750001].rows[1].stacks = 3
local tokenThree = Model.TargetMapToken(tokenSource)
Check(tokenOne and tokenThree and tokenOne ~= tokenThree,
    "semantic target token missed an in-place copy mutation")
local segmentedToken = Model.TargetMapToken({[750001]={version=1,copies=2,rows={
    {spellId=750001,stacks=1},{spellId=750001,stacks=1},
}}})
local consolidatedToken = Model.TargetMapToken({[750001]={version=1,copies=2,
    rows={{spellId=750001,stacks=2}}}})
Check(segmentedToken == consolidatedToken,
    "semantic target token changed across equivalent row segmentation")
Check(Model.TargetMapToken({[750001]=multiReplacement})
        == Model.TargetMapToken({[750001]=permutedReplacement}),
    "semantic target token changed across replacement-row permutation")
local targetCatalog = {rows={[750001]={name="Known"}},familyOf={[750001]=75}}
Check(Model.TargetMapEntries({[750001]=true,[759999]=true},targetCatalog) == nil,
    "catalog-aware target admission partially accepted an unknown identity")
local admissionSource = {[750001]={version=1,copies=1,future={keep=true},
    rows={{spellId=750001,stacks=1,futureRow={keep=true}}}}}
targetCatalog.rows[750001].futureCatalog = {keep=true}
local admitted = Model.TargetMapEntries(admissionSource, targetCatalog)
admitted[1].value.future.keep = false
admitted[1].value.rows[1].futureRow.keep = false
admitted[1].row.futureCatalog.keep = false
Check(admissionSource[750001].future.keep == true
        and admissionSource[750001].rows[1].futureRow.keep == true
        and targetCatalog.rows[750001].futureCatalog.keep == true,
    "target admission exposed caller-owned record, row, or catalog references")
local multiPlan = Model.PlanLockCommit({}, {}, {[750001]=multiReplacement}, {
    [750010]=true,[750011]=true,[750012]=true,
}, {[750001]=3,[750010]=1,[750011]=1,[750012]=1})
Check(multiPlan[750001] and multiPlan[750001] ~= multiReplacement
        and multiPlan[750001].copies == 3
        and multiPlan[750010] == nil and multiPlan[750011] == nil
        and multiPlan[750012] == nil,
    "commit suppression retained a per-copy replacement as desired")

local futureEnvelope = {version=1,copies=2,futureOwner={keep=true},rows={
    {spellId=750020,stacks=2,futureRow={keep=true}},
}}
local mutationApplied = Model.ApplyCommittedTargets({
    pending={},pendingLock={},fulfilledTargets={},metrics={},
}, {[750020]=futureEnvelope}, {lockedBySpell={}})
local reopenedEnvelope = mutationApplied.pendingLock["committed:750020:1"]
reopenedEnvelope.futureRow.keep = false
reopenedEnvelope.__nexusTargetEnvelope.futureOwner.keep = false
Check(futureEnvelope.futureOwner.keep == true
        and futureEnvelope.rows[1].futureRow.keep == true,
    "reopened counted target retained caller-owned provenance references")
local fulfilledEnvelope = Model.ApplyCommittedTargets({
    pending={},pendingLock={},fulfilledTargets={},metrics={},
}, {[750020]=futureEnvelope}, {lockedBySpell={[750020]=2}})
fulfilledEnvelope.fulfilledTargets[750020].futureOwner.keep = false
fulfilledEnvelope.fulfilledTargets[750020].rows[1].futureRow.keep = false
Check(futureEnvelope.futureOwner.keep == true
        and futureEnvelope.rows[1].futureRow.keep == true,
    "fulfilled counted target retained caller-owned provenance references")
local appliedEnvelope = Model.ApplyCommittedTargets({
    pending={},pendingLock={},fulfilledTargets={},metrics={},
}, {[750020]=futureEnvelope}, {lockedBySpell={}})
local reconciledPending, reconciledLock, reconciledTargets =
    Model.ReconcileLocked(appliedEnvelope.pending, appliedEnvelope.pendingLock,
        appliedEnvelope.fulfilledTargets, {[750020]=2})
Model.ExportEntries(reconciledPending, reconciledLock, {[750020]=2},
    {rows={}}, reconciledTargets)
local envelopePlan = Model.PlanLockCommit(reconciledPending, reconciledLock,
    reconciledTargets, {}, {[750020]=2})
Check(envelopePlan[750020] and envelopePlan[750020].futureOwner.keep
        and envelopePlan[750020].rows[1].futureRow.keep,
    "reconcile/commit/export dropped unknown counted-target envelope fields")
envelopePlan[750020].futureOwner.keep = false
envelopePlan[750020].rows[1].futureRow.keep = false
Check(reconciledTargets[750020].futureOwner.keep == true
        and reconciledTargets[750020].rows[1].futureRow.keep == true
        and futureEnvelope.futureOwner.keep == true,
    "committed counted target retained historical provenance references")

local validRetained = {version=1,copies=1,
    rows={{spellId=740003,stacks=1}}}
local wrongKeyReplacement = {version=1,copies=1,replaces=740003,
    rows={{spellId=740002,stacks=1}}}
local replacementPlan = Model.PlanLockCommit({}, {},
    {[740001]=wrongKeyReplacement}, {[740003]=validRetained},
    {[740003]=1})
Check(replacementPlan[740001] == nil
        and replacementPlan[740003] ~= validRetained
        and replacementPlan[740003].copies == 1,
    "wrong-key fulfilled target suppressed a valid replacement target")
local invalidKeyPlan = Model.PlanLockCommit({}, {}, {}, {
    [1.5]=true,
    [math.huge]={version=1,copies=1,rows={{spellId=740003,stacks=1}}},
}, {[1.5]=1,[math.huge]=1})
Check(next(invalidKeyPlan) == nil,
    "invalid containing map key entered the committed target plan")

print(string.format(
    "locked copy totals: duplicate=2+2+2 one=6 rejected=7/malformed roles=separate checks=%d -- OK",
    checks))
