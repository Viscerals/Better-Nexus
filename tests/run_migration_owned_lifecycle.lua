-- Locked-Echo migration and current-run ownership generation regressions.
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/DpsCapture.lua")

local Codec = Nexus.Codec
local oldKey = "200100x2,200200x1"
local sourceRow = {
    dps=25000000, duration=65, ts=50000, player="Boganic", level=80,
    class="MAGE", fingerprint=oldKey,
    echoes={{spellId=200100,count=2},{spellId=200200,count=1}},
    lockedEchoes={{spellId=200100,count=1}},
}
local function FreshDpsDb()
    return {
        personalBest={ [oldKey]={dummy={
            dps=sourceRow.dps, duration=sourceRow.duration, ts=sourceRow.ts,
            player=sourceRow.player, level=sourceRow.level, class=sourceRow.class,
            fingerprint=sourceRow.fingerprint,
            echoes={{spellId=200100,count=2},{spellId=200200,count=1}},
            lockedEchoes={{spellId=200100,count=1}},
        }}},
        buildBest={},
        characterBest={dummy={},lk={}},
    }
end

NexusDB={communityBuilds={},dpsCapture=FreshDpsDb()}
local lockedReady = false
local adapter = {
    LockedOwned=function()
        -- Readiness still gates the pass, but neither this current-login set
        -- nor sourceRow's unproven lockedEchoes is historical authority.
        return {synced=lockedReady,bySpell=lockedReady and {[299999]=1} or {}}
    end,
    Owned=function() return {synced=true,bySpell={},byFamily={}} end,
}
local DPS=Nexus.DpsCapture
DPS.Init(adapter,{})
assert(not NexusDB.dpsCapture.lockedMigrationVersion
    and NexusDB.dpsCapture.personalBest[oldKey],
    "migration ran before locked data was authoritative")

lockedReady=true
DPS.Init(adapter,{})
assert(NexusDB.dpsCapture.lockedMigrationVersion==1,
    "successful locked migration did not persist its version")
assert(NexusDB.dpsCapture.personalBest[oldKey]
    and NexusDB.dpsCapture.personalBest[oldKey].dummy.echoes[1].count==2,
    "unproven locked baseline changed historical data")
local once=Codec.JSONEncode(NexusDB.dpsCapture)
DPS.Init(adapter,{})
assert(Codec.JSONEncode(NexusDB.dpsCapture)==once,
    "repeated initialization changed completed migration data")

-- Simulate a reload interrupt after one row was already modified. The saved
-- immutable source must win, so retrying cannot subtract the baseline twice.
local original=FreshDpsDb()
local interrupted=FreshDpsDb()
local partialEvidenceTouches=0
local revisionBumps=0
Nexus.LoadoutEvidence={
    Init=function() end,
    ReferenceDpsRow=function(row)
        if row and row.partialOnly then
            partialEvidenceTouches=partialEvidenceTouches+1
        end
        return false
    end,
}
Nexus.Revisions={
    DPS_CHANGED="dps",
    Advance=function() revisionBumps=revisionBumps+1 end,
}
interrupted.personalBest={ ["200100x1,200200x1"]={dummy={
    dps=sourceRow.dps,duration=65,ts=50000,player="Boganic",level=80,
    class="MAGE",fingerprint="200100x1,200200x1",
    echoes={{spellId=200100,count=1},{spellId=200200,count=1}},
    lockedEchoes={{spellId=200100,count=1}},
}}}
local partialRow={
    dps=sourceRow.dps,duration=65,ts=50000,player="Partial",level=80,
    class="MAGE",fingerprint="299999x1",ownerKey="partial@ebonhold",
    ownerVerified=true,echoes={{spellId=299999,count=1}},partialOnly=true,
}
interrupted.buildBest={ [partialRow.fingerprint]={dummy=partialRow} }
interrupted.characterBest={dummy={ [partialRow.ownerKey]=partialRow },lk={}}
interrupted.lockedMigrationSource={
    personalBest=original.personalBest,
    buildBest=original.buildBest,
    characterBest=original.characterBest,
}
NexusDB.dpsCapture=interrupted
lockedReady=false
dofile("core/DpsCapture.lua")
DPS=Nexus.DpsCapture
DPS.Init(adapter,{})
local retried=NexusDB.dpsCapture.personalBest[oldKey]
assert(retried and retried.dummy.echoes[1].spellId==200100
    and retried.dummy.echoes[1].count==2
    and NexusDB.dpsCapture.lockedMigrationSource==nil,
    "unsynced restart did not restore and retire its immutable source")
assert(not NexusDB.dpsCapture.lockedMigrationVersion,
    "unsynced source restoration prematurely completed the migration")
assert(partialEvidenceTouches==0,
    "partial live rows produced evidence before immutable source restoration")
assert(revisionBumps>0,
    "represented interrupted-source restoration did not advance DPS revision")
lockedReady=true
DPS.Init(adapter,{})
assert(NexusDB.dpsCapture.lockedMigrationVersion==1,
    "authoritative retry did not complete restored migration")
local retryOnce=Codec.JSONEncode(NexusDB.dpsCapture)
dofile("core/DpsCapture.lua")
Nexus.DpsCapture.Init(adapter,{})
assert(Codec.JSONEncode(NexusDB.dpsCapture)==retryOnce,
    "reload after resumed migration changed data again")

-- Run ownership: a successful prior generation must not authorize the next.
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
local A=Nexus.GameAdapter
NexusDB=NexusDB or {}
Nexus.Store.Init()
A.Init({},Nexus.Store)
H.granted={ ["Alpha Strike"]={{spellId=200100,stack=1,quality=3}} }
A.OnEvent("PLAYER_ENTERING_WORLD")
local runOne=A.Owned()
assert(runOne.synced and runOne.generation==0 and runOne.bySpell[200100]==1,
    "first run did not confirm its ownership response")
local requestsBefore=H.grantedRequests or 0

H.granted=nil
A.RunBoundaryReset()
local runTwo=A.Owned()
assert(not runTwo.synced and runTwo.generation==1
    and (H.grantedRequests or 0)>requestsBefore,
    "new run reused the prior generation or failed to request ownership")
for _=1,6 do
    H.now=H.now+6
    A.Poll()
    assert(not A.Owned().synced,
        "elapsed time incorrectly made missing ownership authoritative")
end
assert((H.grantedRequests or 0)>requestsBefore+1,
    "new-run ownership did not retry boundedly")

-- A fresh empty table is the explicit, authoritative empty response.
H.granted={}
A.RequestGranted()
local confirmedEmpty=A.Owned()
assert(confirmedEmpty.synced and confirmedEmpty.generation==1
    and confirmedEmpty.total==0,
    "confirmed empty current-run ownership was not supported")

print("locked migration and owned-state generations are idempotent -- OK")
