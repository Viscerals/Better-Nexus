-- Stage-1 finding F-S1-1, part 1 of 3 (regression-first): the one-time legacy
-- DPS conversion must reach the DPS data this build serves.
-- At b704660 the first start-up of an older saved root (settings format 2, no
-- authority bundle, an older per-fingerprint leaderboard map) admits the
-- catalog first: BuildCatalog writes authorityBundle, whose dpsCapture is a new
-- top-level table over the raw dpsCapture's child tables. Store then starts
-- LegacyDataMigration, which converts into the RAW NexusDB.dpsCapture
-- (DpsStore, Begin, Finish) and stamps its receipt complete. DpsCapture reads
-- only authorityBundle.dpsCapture once the bundle exists, and the complete
-- receipt makes DpsCapture.MigrateLegacyLeaderboard return early, so the
-- converted rows are never served and the older map stays in the served payload.
-- Healthy behaviour (EXPECT, fails at b704660): once the receipt says complete,
-- the real DPS reads (GetCharacterBest, GetPlayerInfo, GetPersonalBestForEchoes,
-- GetDpsBoard) serve the converted rows with the converter's own results (the
-- staged class hint, the local personal best, the row's unknown field), and the
-- served payload holds no older leaderboard map; the same after logout and two
-- reloads.
-- Unchanged (GUARD, holds at b704660): the conversion completes within a bounded
-- time and is not started again after a reload; a stronger current record is
-- not replaced by a weaker older row; other current rows stay; unknown keys of
-- the root and of the served DPS payload stay; the raw legacy location still
-- holds the record (the rollback copy); a second reload changes nothing
-- (idempotent): served payload, receipt and raw location.
-- Real TOC boot (format5_support F.Boot), Store, BuildCatalog, LegacyDataMigration,
-- DataCompaction and DPS reads; synthetic data; nothing is forced, aliased or
-- written by the test after the saved input is made.
local S=dofile('tests/prototype/legacy_dps_conversion_support.lua')
local F=S.F
local printable=S.printable
local C=S.Checker('legacy_dps_conversion_served')

local db=S.LegacyInput(S.Fixture())
C.setup(rawget(db,'authorityBundle')==nil and db.settingsVersion==2 and type(db.dpsCapture.leaderboard)=='table'
 and next(db.dpsCapture.leaderboard)~=nil and rawget(db,'legacyDataMigration')==nil,
 'fixture: an older saved root (settings format 2) with no authority bundle, no receipt and an older leaderboard map')

local H=F.Boot(db)
C.setup(Nexus.StartupStatus().state=='ready','fixture: start-up reaches ready',Nexus.StartupStatus().state)
C.setup(S.Bundle()~=nil,'fixture: start-up wrote the authority bundle')
local completed=S.Until(H,S.ConversionSettled,600)
C.guard(completed~=nil,'first start-up: the one-time conversion reports complete within 300 s of play',
 Nexus.LegacyDataMigration.Status(NexusDB).state)
-- Bounded wait for the healthy state; at b704660 it is never reached.
local served=S.Until(H,S.ConvertedServed,240)
S.Advance(H,60)
print('OBSERVED','first start-up','conversion complete after',printable(completed),'steps; converted rows served after',
 printable(served),'steps (bound 240)')
S.Observe('first start-up')

local function Check(tag)
 local b=S.ExpectConverted(C,tag)
 S.GuardKept(C,tag,30000,b)
 C.guard(S.RawHolds('Legacyone',12345),
  tag..': the raw legacy location still holds Legacyone (converted or as it was): the rollback copy is kept')
end
Check('first start-up')
local first=S.Receipt() or {}
local firstKey=printable(first.state)..'/'..printable(first.version)..'/'..printable(first.completedAt)
 ..'/'..F.Serialize(first.lastResult)

-- Saved at logout, then two offline reloads of the saved literal data.
H.Fire('PLAYER_LOGOUT')
H=F.Reload()
C.setup(Nexus.StartupStatus().state=='ready','reload: start-up reaches ready',Nexus.StartupStatus().state)
S.Advance(H,120)
S.Observe('reload')
local status=Nexus.LegacyDataMigration.Status(NexusDB)
C.guard(type(status.runtime)=='table' and status.runtime.jobs==0,
 'reload: the completed conversion is not started again',type(status.runtime)=='table' and status.runtime.jobs)
local again=S.Receipt() or {}
C.guard(printable(again.state)..'/'..printable(again.version)..'/'..printable(again.completedAt)
 ..'/'..F.Serialize(again.lastResult)==firstKey,'reload: the receipt keeps its state, version, time and result')
Check('reload')
local projection,receipt,raw=S.Projection(S.BundleDps()),F.Serialize(S.Receipt()),F.Serialize(S.RawDps())

H.Fire('PLAYER_LOGOUT')
H=F.Reload()
C.setup(Nexus.StartupStatus().state=='ready','second reload: start-up reaches ready',Nexus.StartupStatus().state)
S.Advance(H,120)
S.Observe('second reload')
status=Nexus.LegacyDataMigration.Status(NexusDB)
C.guard(type(status.runtime)=='table' and status.runtime.jobs==0,
 'second reload: the completed conversion is not started again',type(status.runtime)=='table' and status.runtime.jobs)
C.guard(S.Projection(S.BundleDps())==projection,'second reload: the served DPS payload is unchanged (idempotent)',
 S.Projection(S.BundleDps()))
C.guard(F.Serialize(S.Receipt())==receipt,'second reload: the receipt is byte-identical')
C.guard(F.Serialize(S.RawDps())==raw,'second reload: the raw legacy location is byte-identical')
Check('second reload')
H.Fire('PLAYER_LOGOUT')

C.finish('(the one-time legacy DPS conversion is served from the authority bundle and survives reloads)')
