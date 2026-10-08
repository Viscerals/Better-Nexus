-- Stage-1 finding F-S1-1, part 3 of 3: controls for a repair of the conversion
-- target. Saved data that this build keeps read-only, or whose conversion
-- receipt or catalog it refuses, is never converted or recovered, and is never
-- written: neither the older root (as in legacy_dps_conversion_served) nor the
-- profile the defect already converted (as in legacy_dps_conversion_recovery).
-- All checks are GUARD checks: they hold at b704660 and must keep holding.
-- Cases: an older root with a future settings format (6) or a malformed format
-- marker (6.5): the whole saved root stays byte-identical, nothing is converted,
-- and the current rows are still shown. The converted profile with a future
-- settings format: the same. The converted profile whose receipt has a future
-- schema, or whose served catalog has a future schema; an older root whose legacy
-- catalog has a future schema, or whose unfinished receipt has a future storage
-- version: the receipt, the raw DPS location and the served DPS payload stay
-- byte-identical and no older record is served.
-- In every case the real DPS reads run (GetDpsBoard, GetCharacterBest,
-- GetPlayerInfo, GetPersonalBestForEchoes): a read is where an older writer
-- converted. Real TOC boot, Store, catalog, migration and DPS reads; synthetic
-- data; nothing is forced or aliased.
local S=dofile('tests/prototype/legacy_dps_conversion_support.lua')
local F,L=S.F,S.L
local printable=S.printable
local C=S.Checker('legacy_dps_conversion_refusals')

local affected,made=S.AffectedProfile(S.Fixture())
C.setup(made.ready and made.readyAgain and made.compacted and made.received and made.bundle,
 'fixture: the converted profile was made on a settled profile of this build',printable(made.receiveWhy))

local function Run(label,db,want)
 local input=F.Serialize(db)
 local rawIn=F.Serialize(rawget(db,'dpsCapture'))
 local bundleIn=type(rawget(db,'authorityBundle'))=='table' and rawget(db.authorityBundle,'dpsCapture') or nil
 local servedIn=F.Serialize(bundleIn)
 local receiptIn=F.Serialize(rawget(db,'legacyDataMigration'))
 local H=F.Boot(db)
 C.setup(Nexus.StartupStatus().state~='pending',label..': fixture: start-up reaches a terminal state',Nexus.StartupStatus().state)
 if want.catalogReadOnly then
  C.setup(Nexus.BuildCatalog.Status().readOnly==true,label..': fixture: the catalog keeps this saved data read-only',
   Nexus.BuildCatalog.Status().state)
 end
 S.Advance(H,120)
 local D=Nexus.DpsCapture
 local board=S.Board('dummy')
 S.Board('lk')
 local older=D.GetCharacterBest('dummy','Legacyone')
 D.GetPlayerInfo('Hintless')
 D.GetPersonalBestForEchoes(L.Copy(S.ECHOES),'dummy')
 S.Advance(H,20)
 S.Observe(label)
 C.guard(older==nil and board.legacyone==nil,label..': no older record is converted or recovered into what is shown',
  S.BoardText(board))
 if want.steady then
  local st=D.GetCharacterBest('dummy','Steady')
  C.guard(st~=nil and st.dps==want.steady,label..': the current Steady record is still shown ('..want.steady..')',st and st.dps)
 end
 if want.wholeRoot then
  C.guard(F.Serialize(NexusDB)==input,label..': the reads write nothing: the saved root is byte-identical')
 end
 if want.noReceipt then
  C.guard(S.Receipt()==nil,label..': no conversion receipt is created',F.Serialize(S.Receipt()))
 else
  C.guard(F.Serialize(S.Receipt())==receiptIn,label..': the receipt is byte-identical')
 end
 C.guard(F.Serialize(S.RawDps())==rawIn,label..': the raw DPS location is byte-identical')
 if bundleIn~=nil then
  C.guard(F.Serialize(S.BundleDps())==servedIn,label..': the served DPS payload is byte-identical')
 end
 H.Fire('PLAYER_LOGOUT')
 if want.wholeRoot then
  C.guard(F.Serialize(NexusDB)==input,label..': after logout the saved root is still byte-identical')
 end
end

-- An older root this build keeps read-only (future format, malformed marker).
Run('older root, future settings format 6',S.LegacyInput(S.Fixture(),function(d) d.settingsVersion=6 end),
 {wholeRoot=true,noReceipt=true,steady=30000})
Run('older root, malformed settings marker 6.5',S.LegacyInput(S.Fixture(),function(d) d.settingsVersion=6.5 end),
 {wholeRoot=true,noReceipt=true,steady=30000})
-- The converted profile, kept read-only.
do
 local db=S.Load(affected);db.settingsVersion=6
 Run('converted profile, future settings format 6',db,{wholeRoot=true,steady=35000})
end
-- The converted profile with a receipt of a future schema: the receipt is not
-- this build's, so nothing it describes is recovered.
do
 local db=S.Load(affected);db.legacyDataMigration.schemaVersion=9
 Run('converted profile, receipt of a future schema',db,{steady=35000})
end
-- The converted profile whose served catalog has a future schema.
do
 local db=S.Load(affected);db.authorityBundle.buildCatalog.schemaVersion=2
 Run('converted profile, served catalog of a future schema',db,{catalogReadOnly=true})
end
-- An older root whose legacy catalog has a future schema.
Run('older root, legacy catalog of a future schema',S.LegacyInput(S.Fixture(),function(d) d.buildCatalog={schemaVersion=2} end),
 {catalogReadOnly=true,noReceipt=true})
-- An older root with an unfinished receipt of a future storage version.
Run('older root, unfinished receipt of a future storage version',S.LegacyInput(S.Fixture(),function(d)
  d.legacyDataMigration={schemaVersion=1,version=9,state='staging',phase='leaderboard',futureStage={keep='receipt'}}
 end),{steady=30000})

C.finish('(read-only, future and refused saved data is never converted, recovered or written)')
