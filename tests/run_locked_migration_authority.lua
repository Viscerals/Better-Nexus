-- Locked-baseline migration authority and recovery regressions.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")

UnitName = function(unit)
    if unit == "player" then return "Local" end
end
GetNormalizedRealmName = function() return "Ebonhold" end
GetRealmName = function() return "Ebonhold" end

local Codec = Nexus.Codec
local A, B, C = 200100, 200200, 200300

local function Echoes(...)
    local values = {...}
    local out = {}
    for index=1,#values,2 do
        out[#out+1] = {spellId=values[index],count=values[index+1]}
    end
    return out
end

local function Key(rows)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out+1] = tostring(row.spellId) .. "x" .. tostring(row.count)
    end
    return table.concat(out, ",")
end

local function Hash(rows)
    local key = Key(rows)
    local hash = 5381
    for index=1,#key do
        hash = ((hash * 33) + key:byte(index)) % 2147483648
    end
    return string.format("%x", hash)
end

local function Signature(value)
    return Codec.JSONEncode(H.CloneValue(value))
end

local function NewRow(player, ownerKey, rows, extra)
    local row = {
        dps=31415926,duration=67,ts=50000,player=player,level=80,
        class="MAGE",category="dummy",ownerKey=ownerKey,
        ownerVerified=true,echoes=H.CloneValue(rows),
        fingerprint=Key(rows),loadoutHash=Hash(rows),
        futureField={sentinel="keep"},
    }
    for key, value in pairs(extra or {}) do row[key] = H.CloneValue(value) end
    return row
end

local function LoadDps(database)
    NexusDB = database
    dofile("core/LoadoutEvidence.lua")
    dofile("core/DpsCapture.lua")
    return Nexus.DpsCapture
end

local function Adapter(lockedBySpell)
    return {
        LockedOwned=function()
            return {synced=true,bySpell=H.CloneValue(lockedBySpell or {})}
        end,
    }
end

local function EmptyDps(extra)
    local db = {
        personalBest={},buildBest={},
        characterBest={dummy={},lk={}},
    }
    for key, value in pairs(extra or {}) do db[key] = value end
    return db
end

-- The confirmed issue #39 red: local A must not be removed from remote A+B.
local remote = NewRow("Remote", "remote@otherrealm", Echoes(A,1,B,1))
local build = NewRow("Builder", "builder@otherrealm", Echoes(A,1,C,1))
local alt = NewRow("Alt", "alt@ebonhold", Echoes(A,1,B,1))
local localUnknown = NewRow("Local", "local@ebonhold", Echoes(A,1,B,1))
local prevention = EmptyDps()
prevention.buildBest[build.fingerprint]={dummy=build}
prevention.characterBest.dummy[remote.ownerKey]=remote
prevention.characterBest.dummy[alt.ownerKey]=alt
prevention.characterBest.dummy[localUnknown.ownerKey]=localUnknown
local preventionRoot = {loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=prevention}
local DPS = LoadDps(preventionRoot)
Nexus.LoadoutEvidence.Init(preventionRoot)
assert(Nexus.LoadoutEvidence.ReferenceDpsRow(build))
local remoteBefore, buildBefore = Signature(remote), Signature(build)
local altBefore, localBefore = Signature(alt), Signature(localUnknown)
local unrelatedBroadcasts = 0
DPS.Init(Adapter({[A]=1}),{
    BroadcastDpsRecord=function() unrelatedBroadcasts=unrelatedBroadcasts+1 end,
})
assert(Signature(remote)==remoteBefore,
    "current local locked baseline rewrote an unrelated remote DPS row")
assert(Signature(build)==buildBefore,
    "buildBest changed without record-specific historical proof")
assert(Signature(alt)==altBefore,
    "another local account character was treated as current-login history")
assert(Signature(localUnknown)==localBefore,
    "exact current owner was treated as proof of unknown historical locks")
assert(prevention.lockedMigrationVersion==1,
    "fail-closed prevention did not complete the one-time migration")
assert(unrelatedBroadcasts==0,
    "preserved fingerprints fabricated unrelated Sync churn")

-- Current locked metadata can arrive before the adapter declares its snapshot
-- authoritative. Backfilling that current state onto a historical local row
-- must not turn it into historical migration authority on a later retry.
local lateAuthority = NewRow("Local", "local@ebonhold", Echoes(A,1,B,1))
local lateDb = EmptyDps()
lateDb.characterBest.dummy[lateAuthority.ownerKey]=lateAuthority
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},dpsCapture=lateDb})
local lockedReady = false
local lateAdapter = {
    LockedOwned=function()
        return {synced=lockedReady,bySpell={[A]=1}}
    end,
}
DPS.Init(lateAdapter,{})
DPS.GetDpsBoard("dummy")
assert(type(lateAuthority.lockedEchoes)=="table",
    "fixture did not exercise late current-state metadata backfill")
lockedReady = true
DPS.GetDpsBoard("dummy")
assert(Signature(lateAuthority.echoes)==Signature(Echoes(A,1,B,1))
    and lateAuthority.fingerprint==Key(Echoes(A,1,B,1)),
    "late current-state backfill became historical migration authority")

-- Inline locked evidence does not prove when it was attached. Even an exact
-- content match must remain unchanged without a durable provenance bridge.
local provenSource = Echoes(A,2,B,1)
local provenFinal = Echoes(A,1,B,1)
local proven = NewRow("Proven", "proven@otherrealm", provenSource, {
    lockedEchoes=Echoes(A,1),
})
local provenDb = EmptyDps()
provenDb.personalBest[proven.fingerprint]={dummy=proven}
local provenBefore = Signature(proven)
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},dpsCapture=provenDb})
DPS.Init(Adapter({[C]=9}),{})
local provenKey = Key(provenFinal)
assert(provenDb.personalBest[Key(provenSource)]
    and provenDb.personalBest[Key(provenSource)].dummy == proven
    and not provenDb.personalBest[provenKey]
    and Signature(proven)==provenBefore,
    "unproven inline locked evidence authorized historical correction")
assert(proven.dps==31415926 and proven.duration==67
    and proven.category=="dummy" and proven.ownerKey=="proven@otherrealm"
    and proven.futureField.sentinel=="keep",
    "fail-closed preservation changed unrelated DPS or future metadata")

-- An interruption restores the immutable pre-pass source exactly, never the
-- partial output and never a fresh inference from attached locked metadata.
local interruptedSource = NewRow("Interrupted", "interrupted@otherrealm",
    provenSource, {lockedEchoes=Echoes(A,1)})
local partial = NewRow("Interrupted", "interrupted@otherrealm",
    provenFinal, {lockedEchoes=Echoes(A,1)})
local interrupted = EmptyDps({
    lockedMigrationSource={
        personalBest={[Key(provenSource)]={dummy=H.CloneValue(interruptedSource)}},
        buildBest={},characterBest={dummy={},lk={}},
    },
})
interrupted.personalBest[Key(provenFinal)]={dummy=partial}
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=interrupted})
DPS.Init(Adapter({[B]=5}),{})
local resumed = interrupted.personalBest[Key(provenSource)]
    and interrupted.personalBest[Key(provenSource)].dummy
assert(resumed and Signature(resumed.echoes)==Signature(provenSource)
    and interrupted.lockedMigrationSource==nil,
    "interrupted source was not restored exactly")
local resumedOnce = Signature(interrupted)
DPS.Init(Adapter({[A]=99}),{})
assert(Signature(interrupted)==resumedOnce,
    "repeated initialization double-transformed interrupted recovery")

-- The same local row can be referenced by personal and character stores.
-- Identity sharing must not authorize a second subtraction.
local shared = NewRow("Shared", "shared@ebonhold", provenSource, {
    lockedEchoes=Echoes(A,1),
})
local sharedDb = EmptyDps()
sharedDb.personalBest[shared.fingerprint]={dummy=shared}
sharedDb.buildBest[shared.fingerprint]={dummy=shared}
sharedDb.characterBest.dummy[shared.ownerKey]=shared
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},dpsCapture=sharedDb})
DPS.MigrateLegacyLeaderboard()
local sharedBefore = Signature(shared)
DPS.Init(Adapter({[C]=4}),{})
assert(sharedDb.personalBest[Key(provenSource)]
    and sharedDb.personalBest[Key(provenSource)].dummy==shared,
    "shared personal keyed alias changed")
assert(sharedDb.buildBest[Key(provenSource)]
    and sharedDb.buildBest[Key(provenSource)].dummy==shared,
    "shared build keyed alias changed")
assert(sharedDb.characterBest.dummy[shared.ownerKey]==shared,
    "shared character alias changed")
assert(Signature(shared)==sharedBefore,
    "shared row identity changed")

-- Conflicting inline and direct-reference locked evidence is content ambiguity,
-- not authority. The row and its keyed store must remain byte-for-byte stable.
local conflicting = NewRow("Conflicting", "conflicting@otherrealm",
    provenSource, {lockedEchoes=Echoes(A,1)})
local conflictDb = EmptyDps()
conflictDb.personalBest[conflicting.fingerprint]={dummy=conflicting}
local conflictRoot = {loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=conflictDb}
DPS = LoadDps(conflictRoot)
Nexus.LoadoutEvidence.Init(conflictRoot)
DPS.MigrateLegacyLeaderboard()
conflicting.lockedEvidenceKey = assert(Nexus.LoadoutEvidence.Intern(Echoes(B,1)))
local conflictBefore = Signature(conflicting)
DPS.Init(Adapter({[C]=4}),{})
assert(Signature(conflicting)==conflictBefore
    and conflictDb.personalBest[Key(provenSource)].dummy==conflicting,
    "conflicting inline/reference evidence authorized correction")

-- Completed v1 is ambiguous without a direct immutable pre-state relationship.
local ambiguous = NewRow("Ambiguous", "ambiguous@otherrealm", Echoes(B,1))
local ambiguousDb = EmptyDps({lockedMigrationVersion=1})
ambiguousDb.characterBest.dummy[ambiguous.ownerKey]=ambiguous
local ambiguousBefore = Signature(ambiguousDb)
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=ambiguousDb})
DPS.Init(Adapter({[A]=1}),{})
assert(Signature(ambiguousDb)==ambiguousBefore,
    "completed-v1 ambiguous inverse was reconstructed")

-- A direct pre-state reference plus an exact empty row baseline still does not
-- prove when either field was associated with the row. Completed v1 is kept.
local preState = Echoes(A,1,B,1)
local recoverable = NewRow("Recoverable", "recoverable@otherrealm",
    Echoes(B,1), {lockedEchoes={}})
local recoverDb = EmptyDps({lockedMigrationVersion=1})
recoverDb.characterBest.dummy[recoverable.ownerKey]=recoverable
local recoverRoot = {loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=recoverDb}
DPS = LoadDps(recoverRoot)
Nexus.LoadoutEvidence.Init(recoverRoot)
local preReference = assert(Nexus.LoadoutEvidence.Intern(preState))
recoverable.evidenceKey = preReference
local stablePeer = NewRow("Stable", "stable@otherrealm", Echoes(C,1))
recoverDb.characterBest.dummy[stablePeer.ownerKey]=stablePeer
local recoverableBefore = Signature(recoverable)
local stableBefore = Signature(stablePeer)
DPS.Init(Adapter({[C]=7}),{})
assert(Signature(recoverable)==recoverableBefore,
    "completed-v1 direct reference was treated as historical provenance")
assert(Signature(stablePeer)==stableBefore,
    "completed-v1 recovery changed an unrelated peer row")
local recoveredOnce = Signature(recoverDb)
DPS.Init(Adapter({[A]=99}),{})
assert(Signature(recoverDb)==recoveredOnce,
    "repeated init changed an exact completed-v1 recovery")

-- A completed row already equal to a plausible correction is likewise stable.
local legitimatePre = Echoes(A,2,B,1)
local legitimate = NewRow("Legitimate", "legitimate@otherrealm",
    Echoes(A,1,B,1), {lockedEchoes=Echoes(A,1)})
local legitimateDb = EmptyDps({lockedMigrationVersion=1})
legitimateDb.characterBest.dummy[legitimate.ownerKey]=legitimate
local legitimateRoot = {loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=legitimateDb}
DPS = LoadDps(legitimateRoot)
Nexus.LoadoutEvidence.Init(legitimateRoot)
legitimate.evidenceKey = assert(Nexus.LoadoutEvidence.Intern(legitimatePre))
local legitimateBefore = Signature(legitimateDb)
DPS.Init(Adapter({[C]=8}),{})
assert(Signature(legitimateDb)==legitimateBefore,
    "completed-v1 row already matching exact authority was reversed")

-- The same exact pool entry is not authority when it is orphaned.
local orphan = NewRow("Orphan", "orphan@otherrealm", Echoes(B,1), {
    lockedEchoes={},
})
local orphanDb = EmptyDps({lockedMigrationVersion=1})
orphanDb.characterBest.dummy[orphan.ownerKey]=orphan
local orphanRoot = {loadoutEvidence={schemaVersion=1,entries={}},
    dpsCapture=orphanDb}
DPS = LoadDps(orphanRoot)
Nexus.LoadoutEvidence.Init(orphanRoot)
assert(Nexus.LoadoutEvidence.Intern(preState))
local orphanBefore = Signature(orphanDb)
DPS.Init(Adapter({[A]=1}),{})
assert(Signature(orphanDb)==orphanBefore,
    "orphan LoadoutEvidence was similarity-attached to a completed row")

-- Current-login locks cannot make the result depend on login order.
local function LoginOrderResult(currentLocks)
    local first = NewRow("First", "first@ebonhold", Echoes(A,1,B,1))
    local second = NewRow("Second", "second@ebonhold", Echoes(A,1,B,1))
    local db = EmptyDps()
    db.characterBest.dummy[first.ownerKey]=first
    db.characterBest.dummy[second.ownerKey]=second
    local runner = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},
        dpsCapture=db})
    runner.Init(Adapter(currentLocks),{})
    return Signature(db)
end
assert(LoginOrderResult({[A]=1})==LoginOrderResult({[B]=1}),
    "two characters with different locks produced login-order-dependent history")

-- Authoritative no-lock readiness is a no-op for rows without exact proof.
local noLock = NewRow("NoLock", "nolock@otherrealm", Echoes(A,1,B,1))
local noLockDb = EmptyDps()
noLockDb.characterBest.dummy[noLock.ownerKey]=noLock
local noLockBefore = Signature(noLock)
DPS = LoadDps({loadoutEvidence={schemaVersion=1,entries={}},dpsCapture=noLockDb})
DPS.Init(Adapter({}),{})
assert(Signature(noLock)==noLockBefore,
    "authoritative no-lock state rewrote historical evidence")
local noLockOnce = Signature(noLockDb)
DPS.Init(Adapter({[A]=1}),{})
assert(Signature(noLockDb)==noLockOnce,
    "repeated no-lock initialization changed migration state")

-- Future-owned storage is read-only; migration may only use transient state.
local previousCatalog = Nexus.BuildCatalog
local futureDps = EmptyDps({futureField={sentinel="future"}})
local futureRow = NewRow("Future", "future@otherrealm", Echoes(A,1,B,1), {
    lockedEchoes=Echoes(A,1),
})
futureDps.characterBest.dummy[futureRow.ownerKey]=futureRow
local futureRoot = {
    dpsCapture=futureDps,futureOwner={sentinel="keep"},
    loadoutEvidence={schemaVersion=99,entries={},futureField="opaque"},
}
local futureBefore = Signature(futureRoot)
Nexus.BuildCatalog = {Status=function() return {readOnly=true} end}
DPS = LoadDps(futureRoot)
DPS.Init(Adapter({[A]=1}),{})
assert(Signature(futureRoot)==futureBefore,
    "future-schema/read-only state was mutated")
Nexus.BuildCatalog = previousCatalog

print("locked migration fails closed without historical provenance -- OK")
