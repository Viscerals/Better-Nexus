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
H.Advance(3.1)
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
-- 6. Early lifecycle observation before Store admission. MainLifecycle
-- installs the Orb observer at addon load, so the startup enter reaches it
-- while Store.State does not yet expose a plain-name row. The receipt that
-- the explicit Start above created is round-tripped (no invented shape).
-- Control: that receipt in the existing canonical row. Regression: the same
-- receipt only in the plain name-keyed row, with no canonical row.
local orbBefore=assert(loadstring('return '..pending))()
local function Identity(p)
 if type(p)~='table' then return nil end
 return F.Serialize({removed=p.removed,chargesBefore=p.chargesBefore,before=p.before,lockedKey=p.lockedKey,
  originalSlot=p.originalSlot,logSerial=p.logSerial,beforeStamp=p.beforeStamp,guid=p.guid})
end
local identity=Identity(orbBefore.pending)
check(identity and type(orbBefore.pending.removed)=='string' and orbBefore.maxOrbs==1,
 'fixture: the round-tripped receipt is the pending action of the explicit Start above')
local canonicalSaved=F.Serialize(NexusDB.chars[F.OWNER])
check(Identity(NexusDB.chars[F.OWNER].orbRefinement.pending)==identity,'fixture: the existing canonical row holds that receipt')
local function Sent(H,kind)local n=0;for _,a in ipairs(H.actions)do if a[1]==kind then n=n+1 end end;return n end
-- Read-only facts at the startup enter, before any scheduler turn.
local function EarlyFacts(into)
 return function()
  local st=Nexus.Store.State()
  into.coreReady=Nexus.StartupStatus().coreReady
  into.write=Nexus.Store.StateWriteStatus().mode
  into.orb=type(st)=='table' and st.orbRefinement or nil
  into.view=Nexus.OrbRuntime.RunnerView()
  into.hidden=type(NexusOrbRuntime)=='table' and NexusOrbRuntime:IsShown()==false
 end
end
local function EnterBeforeAdmission(seen,label)
 check(seen.coreReady==false and seen.write=='loading',label..': the actual startup enter is dispatched before Store admission')
 check(type(seen.view)=='table' and seen.view.lifecycleObserved==true and type(seen.view.epoch)=='number'
  and seen.view.epoch>=1 and seen.view.phase=='r',label..': the observer installed at addon load records that enter as lifecycle facts')
 check(Nexus.StartupStatus().coreReady and Nexus.Store.StateWriteStatus().mode=='durable',label..': Store admission then completes and writes are durable')
end
local function ReceiptHeld(H,label,nameRow)
 local R,St=Nexus.OrbRuntime,Nexus.Store
 local saved=St.State().orbRefinement
 check(type(saved)=='table' and Identity(saved.pending)==identity,label..': after admission Store.State exposes the saved pending receipt')
 check(R.BlocksOrdinary()==true,label..': once Store admission is ready the saved pending receipt blocks ordinary rolling')
 local view=R.RecoveryView()
 check(view.pending==true and view.restored==true and R.RunnerView().pending==true,
  label..': the runtime holds the saved receipt as an unresolved restored Orb action')
 local okLimit,whyLimit=R.SetLimit(orbBefore.maxOrbs+6)
 check(okLimit~=true and type(whyLimit)=='string',label..': an explicit maximum edit is refused while the receipt is unresolved')
 local okRecycle,whyRecycle=R.SetRecycle(orbBefore.recycle~=true)
 check(okRecycle~=true and type(whyRecycle)=='string',label..': an explicit recycling edit is refused while the receipt is unresolved')
 saved=St.State().orbRefinement
 check(type(saved)=='table' and Identity(saved.pending)==identity and saved.maxOrbs==orbBefore.maxOrbs
  and saved.recycle==orbBefore.recycle,label..': refused edits replace neither the saved receipt nor its preferences')
 local row=NexusDB.chars[F.OWNER]
 check(row==nil or (type(row.orbRefinement)=='table' and Identity(row.orbRefinement.pending)==identity),
  label..': a canonical row carries the receipt; no canonical Orb state is written without it')
 check(F.Serialize(NexusDB.chars[F.NAME])==nameRow,label..': the original name-keyed row is unchanged')
 local st=St.State()
 check(st.unknownGenField and st.unknownGenField.keep=='row' and NexusDB.genUnknownTopLevel.keep=='top'
  and NexusDB.nexusNativeRecoveryArchiveF5.chars[F.NAME].archived and NexusDB.settingsVersion==5,
  label..': unknown fields, the recovery archive and the saved marker are kept')
 check(Sent(H,'orb-spend')==0 and Sent(H,'take')==0 and H.orbs.source==nil,label..': no Orb spend or Echo choice is sent')
 check(R.BlocksOrdinary()==true,label..': the receipt still blocks ordinary rolling after the refused edits')
end
local control=F.Database({mutate=function(db)db.chars[F.OWNER]=assert(loadstring('return '..canonicalSaved))()end})
check(control.chars[F.NAME].orbRefinement==nil and Identity(control.chars[F.OWNER].orbRefinement.pending)==identity,
 'control: the receipt is only in the existing canonical row')
local seen={}
H=F.Boot(control,F.OrbService,EarlyFacts(seen))
EnterBeforeAdmission(seen,'control')
ReceiptHeld(H,'control',nameRowBefore)
seen={}
local legacy=F.Database({mutate=function(db)db.chars[F.NAME].orbRefinement=assert(loadstring('return '..pending))()end})
local legacyRow=F.Serialize(legacy.chars[F.NAME])
check(legacy.chars[F.OWNER]==nil and Identity(legacy.chars[F.NAME].orbRefinement.pending)==identity,
 'name row: the receipt is only in the plain name-keyed row; no canonical row exists')
H=F.Boot(legacy,F.OrbService,EarlyFacts(seen))
EnterBeforeAdmission(seen,'name row')
check(seen.orb==nil and seen.hidden==true,
 'name row: at that enter Store.State does not expose the unadmitted row, and the idle observer stays hidden')
ReceiptHeld(H,'name row',legacyRow)
check(seen.view.initialized==false,
 'name row: the passive startup enter kept lifecycle facts only; it did not initialize or cache Orb runner state from the unadmitted row')
print('PASS format5_known_transition early enter: name-keyed and canonical receipts admitted after the enter block rolling and edits checks='..checks)
print('PASS format5_known_transition: durable Store, owned row carried once, Orb eligibility agrees, receipt kept, idempotent checks='..checks)
