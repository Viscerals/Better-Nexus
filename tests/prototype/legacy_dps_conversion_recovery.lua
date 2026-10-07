-- Stage-1 finding F-S1-1, part 2 of 3 (regression-first): bounded recovery of a
-- profile that the defect already converted.
-- A saved root that went through the defective first start-up keeps a complete
-- conversion receipt, the converted maps in the RAW NexusDB.dpsCapture only, and
-- in the served authorityBundle.dpsCapture the older leaderboard map without the
-- converted rows. At b704660 nothing ever moves those rows: the receipt turns
-- both converters off (LegacyDataMigration.Init answers complete,
-- DpsCapture.MigrateLegacyLeaderboard returns early) and DpsCapture never reads
-- the raw location once the bundle exists.
-- Healthy behaviour (EXPECT, fails at b704660): one start-up of this build serves
-- the converted rows within a bounded wait, through the real DPS reads
-- (GetCharacterBest, GetPlayerInfo, GetPersonalBestForEchoes, GetDpsBoard), with
-- the converted maps' own results (the class hint of Hintless, the local
-- personal best, the row's unknown field), and the served payload no longer holds
-- the older map; the same after logout and two reloads.
-- Unchanged (GUARD, holds at b704660): the newer, stronger served record (Steady
-- 35000, received after the upgrade) is not replaced by the older converted
-- 30000; a record that exists only in the served payload stays (Newcomer); the
-- unknown keys of the served payload and of the root stay; the raw location (the
-- rollback copy) stays byte-identical; the receipt stays complete; after the
-- recovery no conversion starts again and a second reload changes nothing.
-- The affected profile (legacy_dps_conversion_support S.AffectedProfile): a real
-- settled profile of this build, a newer record received through the real
-- receive path, then the receipt, the raw maps and the served older map written
-- into the saved input exactly as the defective start-up left them. No served
-- row is written by the test and nothing is aliased: recovery must come from the
-- build. Real TOC boot, Store, catalog, migration, compaction and DPS reads;
-- synthetic data.
local S=dofile('tests/prototype/legacy_dps_conversion_support.lua')
local F=S.F
local printable=S.printable
local C=S.Checker('legacy_dps_conversion_recovery')

local text,made=S.AffectedProfile(S.Fixture())
C.setup(made.ready and made.noConversion,'fixture: the base profile of this build starts and owes no conversion')
C.setup(made.compacted and made.compactedAfter,'fixture: its start-up compaction completed before it was saved')
C.setup(made.readyAgain,'fixture: one more session of the saved base profile starts')
C.setup(made.received and made.servedSteady==35000,
 'fixture: a newer, stronger Steady record (35000) was accepted through the real receive path and served',
 printable(made.receiveWhy)..' / '..printable(made.servedSteady))
C.setup(made.bundle,'fixture: the saved profile has a served DPS payload')

local input=S.Load(text)
local payload=type(input.authorityBundle)=='table' and input.authorityBundle.dpsCapture or nil
local receipt=input.legacyDataMigration
C.setup(type(receipt)=='table' and receipt.state=='complete' and receipt.version==2,
 'fixture: the receipt says the one-time conversion is complete')
C.setup(S.StoredRow(input.dpsCapture,'dummy','Legacyone')~=nil and input.dpsCapture.leaderboard==nil,
 'fixture: the converted rows are in the raw location only')
C.setup(type(payload)=='table' and S.StoredRow(payload,'dummy','Legacyone')==nil and type(payload.leaderboard)=='table',
 'fixture: the served payload lacks them and still holds the older map')
C.setup(type(payload)=='table' and (S.StoredRow(payload,'dummy','Steady') or {}).dps==35000
 and (S.StoredRow(input.dpsCapture,'dummy','Steady') or {}).dps==30000,
 'fixture: Steady is 35000 in the served payload and 30000 in the raw copy')
local rawInput=F.Serialize(input.dpsCapture)

local H=F.Boot(input)
C.setup(Nexus.StartupStatus().state=='ready','fixture: start-up reaches ready',Nexus.StartupStatus().state)
-- Bounded wait for the recovered state; at b704660 it is never reached.
local recovered=S.Until(H,S.ConvertedServed,240)
S.Advance(H,60)
print('OBSERVED','recovery start-up','converted rows served after',printable(recovered),'steps (bound 240)')
S.Observe('recovery start-up')

local function Check(tag)
 local b=S.ExpectConverted(C,tag)
 S.GuardKept(C,tag,35000,b)
 local d=S.BundleDps()
 C.guard(d~=nil and type(d.bundleOnly)=='table' and d.bundleOnly.keep=='bundle top level',
  tag..': an unknown key that only the served payload had stays',d and type(d.bundleOnly))
 C.guard(F.Serialize(S.RawDps())==rawInput,tag..': the raw location (the rollback copy) is byte-identical to the saved input')
end
Check('recovery start-up')

H.Fire('PLAYER_LOGOUT')
H=F.Reload()
C.setup(Nexus.StartupStatus().state=='ready','reload: start-up reaches ready',Nexus.StartupStatus().state)
S.Advance(H,120)
S.Observe('reload')
local status=Nexus.LegacyDataMigration.Status(NexusDB)
C.guard(type(status.runtime)=='table' and status.runtime.jobs==0,
 'reload: no conversion is started again',type(status.runtime)=='table' and status.runtime.jobs)
Check('reload')
local projection,receiptText=S.Projection(S.BundleDps()),F.Serialize(S.Receipt())

H.Fire('PLAYER_LOGOUT')
H=F.Reload()
C.setup(Nexus.StartupStatus().state=='ready','second reload: start-up reaches ready',Nexus.StartupStatus().state)
S.Advance(H,120)
S.Observe('second reload')
status=Nexus.LegacyDataMigration.Status(NexusDB)
C.guard(type(status.runtime)=='table' and status.runtime.jobs==0,
 'second reload: no conversion is started again',type(status.runtime)=='table' and status.runtime.jobs)
C.guard(S.Projection(S.BundleDps())==projection,'second reload: the served DPS payload is unchanged (idempotent)',
 S.Projection(S.BundleDps()))
C.guard(F.Serialize(S.Receipt())==receiptText,'second reload: the receipt is byte-identical')
Check('second reload')
H.Fire('PLAYER_LOGOUT')

C.finish('(a profile converted by the defect is recovered into the authority bundle once, bounded, and stays recovered)')
