-- Tester report on test.9033-487eaa9: "Saved format 5; Supported 2", after
-- Good Enough Nexus 1.96. Store treated every settings marker above 2 as a
-- newer owner: reads and writes used a temporary row, and Orb Start refused.
-- Verified format-5 data must be used durably, with its settings, the
-- character's own name-keyed row (Wishlist assignment, permanent-target design,
-- stacked copies), unknown fields and archives preserved, and the saved marker
-- unchanged. Real TOC boot, Store, adapter, Orb runtime; fake Orb service only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local db=F.Database()
local nameRowBefore=F.Serialize(db.chars[F.NAME])
local settingsBefore={};for k,v in pairs(db.settings)do settingsBefore[k]=F.Serialize(v)end
local ledgerBefore=F.Serialize(db.accountCharacters)
local H=F.Boot(db)
local S,A=Nexus.Store,Nexus.GameAdapter
check(Nexus.StartupStatus().coreReady,'local startup completes on verified format-5 data')

-- 1. Store reads and writes are durable, not the temporary row.
local write=S.StateWriteStatus()
check(write.mode=='durable','verified format-5 data is writable durably: '..tostring(write.mode)..' '..tostring(write.reason))
check(S.Settings()==NexusDB.settings,'settings are the saved settings, not temporary defaults')
for k,v in pairs(settingsBefore)do check(F.Serialize(NexusDB.settings[k])==v,'setting kept unchanged: '..k)end
check(NexusDB.settings.autoPick==false,'the stored Take preference (autoPick) is kept as saved')
check(Nexus.RecomputeStats().autoEnabled==false,'the session Automation master switch (autoEnabled) is OFF')
check(NexusDB.settingsVersion==5,'the saved marker is not lowered or rewritten')

-- 2. The character's own name-keyed row is used; it is copied, never moved.
local state=S.State()
check(type(state.loadoutWishlists)=='table' and type(state.loadoutWishlists[1])=='table'
 and state.loadoutWishlists[1].name=='Gen plan','the saved Wishlist assignment is read from the owned row')
check(state.unknownGenField and state.unknownGenField.keep=='row','unknown row fields are kept')
local ok=Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)row.format5Probe=1 end)
check(ok and type(NexusDB.chars[F.OWNER])=='table' and NexusDB.chars[F.OWNER].format5Probe==1,'the first write creates the canonical row')
local canonical=NexusDB.chars[F.OWNER]
check(canonical.loadoutWishlists[1].name=='Gen plan' and canonical.loadoutWishlists[1].echoes[1].stacks==2
 and canonical.loadoutWishlists[1].echoes[2].stacks==3,'assignment and stacked copies are carried into the canonical row')
check(canonical.lockDesignTargetsBySlot[F.Key(F.PLAN)][F.PERMANENT]==true,'the exact locked-target design is carried')
check(canonical.tomeTogglePending[7].want==true and canonical.recordedPicks[200001]==1,'other row state is carried')
check(canonical~=NexusDB.chars[F.NAME],'the canonical row is a copy, not the same table')
check(F.Serialize(NexusDB.chars[F.NAME])==nameRowBefore,'the original name-keyed row is unchanged')
check(F.Serialize(NexusDB.accountCharacters)==ledgerBefore,'the account ledger is unchanged')
check(NexusDB.genUnknownTopLevel.keep=='top' and NexusDB.nexusNativeRecoveryArchiveF5.chars[F.NAME].archived,'unknown data and the recovery archive are kept')

-- 3. The assignment resolves with its permanent target.
H.perks.serverBuildSlots={[1]={name='Gen plan',verified=true,echoes=F.PLAN}};H.perks.serverActiveSlot=1
H.Advance(1,.05)
local assigned=A.AssignedWishlist()
check(assigned.state=='ready','the carried assignment resolves: '..tostring(assigned.state)..' '..tostring(assigned.note))
local permanent=0
for _,e in ipairs(assigned.entries or {})do if e.locked and e.spellId==F.PERMANENT then permanent=permanent+e.stacks end end
check(permanent==1,'the carried design adds its locked target')
print('PASS format5_known_transition part 1: durable Store, owned row carried, originals kept checks='..checks)

-- 4. Reload: the carried row is kept and not copied again; Orb Start and the
-- window agree with durable eligibility; one explicit Start writes a durable
-- receipt (fake Orb service: a counted call, not a game action).
local carried=F.Serialize(NexusDB.chars[F.OWNER].savedFormatCarry)
local function Owned(H)
 H.perks.serverBuildSlots={[1]={name='Gen plan',verified=true,echoes=F.PLAN}};H.perks.serverActiveSlot=1
 local granted={}
 for _,e in ipairs({{spellId=200001,quality=1,stacks=2},{spellId=200002,quality=2,stacks=3},{spellId=200010,quality=2,stacks=2}})do
  granted[H.names[e.spellId]]={{spellId=e.spellId,quality=e.quality,stacks=e.stacks}}
 end
 H.granted=granted;H.locked={}
 H.Notify();Nexus.GameAdapter.Poll();H.Advance(1,.05)
end
H=F.Reload(F.OrbService);Owned(H)
check(Nexus.StartupStatus().coreReady and NexusDB.settingsVersion==5,'reload keeps the saved marker')
check(F.Serialize(NexusDB.chars[F.OWNER].savedFormatCarry)==carried,'the carry is not repeated on reload')
check(F.Serialize(NexusDB.chars[F.NAME])==nameRowBefore,'the original row is still unchanged after reload')
Nexus.OrbPanel.Show()
local snap=NexusOrbPanel.snapshot
local status=S.StateWriteStatus()
check(status.mode=='durable' and snap.persistence and snap.persistence.mode=='durable','the window reports the real durable eligibility')
check(snap.assignment and snap.assignment.state=='ready','the carried assignment is the Orb target: '..tostring(snap.assignment and snap.assignment.note))
check(snap.canStart==true and NexusOrbPanel.start:IsEnabled(),'Start is available only because the data is durable: '..tostring(snap.startReason))
local M=Nexus.OrbRuntime
check(M.SetLimit(1) and M.Start(),'one explicit Start')
local spends=0;for _,a in ipairs(H.actions)do if a[1]=='orb-spend' then spends=spends+1 end end
check(spends==1 and H.orbs.source==200010,'one fake spend of the surplus copy only')
check(NexusDB.chars[F.OWNER].orbRefinement and NexusDB.chars[F.OWNER].orbRefinement.pending,'the receipt is durable in the canonical row')
check(NexusDB.chars[F.NAME].orbRefinement==nil,'nothing is written into the original row')

-- 5. Reload with the pending receipt: kept, not replayed; repeated start-up is idempotent.
local pending=F.Serialize(NexusDB.chars[F.OWNER].orbRefinement)
H=F.Reload(F.OrbService)
check(F.Serialize(NexusDB.chars[F.OWNER].orbRefinement)==pending,'the pending receipt survives reload unchanged')
local actions=#H.actions;H.Advance(3,.05)
local replay=0;for i=actions+1,#H.actions do if H.actions[i][1]=='orb-spend' then replay=replay+1 end end
check(replay==0,'a pending action is never replayed on reload')
local function Durable()
 return F.Serialize({chars=NexusDB.chars,settings=NexusDB.settings,ledger=NexusDB.accountCharacters,
  version=NexusDB.settingsVersion,top=NexusDB.genUnknownTopLevel,archive=NexusDB.nexusNativeRecoveryArchiveF5})
end
local once=Durable()
F.Reload(F.OrbService)
check(Durable()==once,'a further start-up changes none of the carried, settings, ledger or archive data')
check(NexusDB.settings.autoPick==false,'the stored Take preference (autoPick) is still as saved')
check(Nexus.RecomputeStats().autoEnabled==false,'the session Automation master switch (autoEnabled) is still OFF')
print('PASS format5_known_transition: durable Store, owned row carried once, Orb eligibility agrees, receipt kept, idempotent checks='..checks)
