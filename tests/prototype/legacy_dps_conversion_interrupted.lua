-- Stage-1 finding F-S1-1, part 4 (repair phase): a first conversion that ended
-- before completion, on a profile that start-up had already moved into the
-- authority bundle.
-- A. A first start-up can end (logout, crash, reload) after the catalog
-- admitted the older root into authorityBundle and before the one-time
-- conversion completed: the receipt says staging and holds that session's
-- partial staging, the served payload (authorityBundle.dpsCapture) still holds
-- the older leaderboard map, and the legacy NexusDB.dpsCapture still holds the
-- older input (nothing writes it before completion). Before the next start-up
-- the served payload changed: a newer, stronger Steady record (35000) was
-- accepted and compaction completed. The partial staging still holds Steady's
-- older 30000 and a row (Ghost) whose source no longer exists.
-- Healthy behaviour (EXPECT; by reading, b704660 resumes that staging from the
-- legacy location and writes only there): the next start-up converts the served
-- payload as it is then, publishes the result into it and completes the
-- receipt; the converted records are served; the legacy location is not
-- written. Unchanged (GUARD): the newer Steady record is kept, a row only the
-- stale staging held is not published, unknown keys stay, and after completion
-- a reload starts no conversion and changes nothing.
-- B. The window between the served commit and the receipt stamp: the served
-- payload already holds the conversion, and the receipt says staging, phase
-- commit, with no staging (what this build leaves there). The next start-up
-- completes the receipt and the served records stay as they were: no duplicate
-- row, no older map (idempotent).
-- Real TOC boot, Store, catalog, migration, compaction and DPS reads; synthetic
-- data. The saved inputs are written before boot; nothing is forced afterwards.
local S=dofile('tests/prototype/legacy_dps_conversion_support.lua')
local F,L=S.F,S.L
local printable=S.printable
local C=S.Checker('legacy_dps_conversion_interrupted')

local function Ready(tag)
 C.setup(Nexus.StartupStatus().state=='ready',tag..': fixture: start-up reaches ready',Nexus.StartupStatus().state)
end
local function Jobs()
 local s=Nexus.LegacyDataMigration.Status(NexusDB)
 return type(s.runtime)=='table' and s.runtime.jobs or nil
end

-- A. Interrupted before publication.
local fx=S.Fixture()
local text,made=S.AffectedProfile(fx)
C.setup(made.ready and made.compacted and made.compactedAfter and made.bundle,
 'A: fixture: a settled profile of this build whose compaction completed')
C.setup(made.received and made.servedSteady==35000,
 'A: fixture: a newer, stronger Steady record (35000) was accepted and served',
 printable(made.receiveWhy)..' / '..printable(made.servedSteady))
local input=S.Load(text)
-- The legacy location as the first start-up found it.
input.dpsCapture=S.LegacyInput(S.Fixture()).dpsCapture
input.legacyDataMigration={schemaVersion=1,version=0,state='staging',inProgress=true,reason='startup',
 sourceSettingsVersion=2,workUnits=7,phase='leaderboard',stats={accountRowsCopied=1,characterRowsCopied=2},
 staging={accountCharacters=L.Copy(input.accountCharacters),personalBest={},buildBest={},
  characterBest={dummy={
   ['steady@ebonhold']=L.Copy(fx.rows.dummy['steady@ebonhold']),
   ['ghost@ebonhold']={dps=99999,ts=1700000300,duration=60,level=80,player='Ghost',class='WARRIOR',
    realm='ebonhold',ownerKey='ghost@ebonhold',fingerprint=S.FP,echoes=L.Copy(S.ECHOES)},
  },lk={['newcomer@ebonhold']=L.Copy(fx.rows.lk['newcomer@ebonhold'])}},
  classHints={hintless={class='PRIEST'}}}}
local payload=type(input.authorityBundle)=='table' and input.authorityBundle.dpsCapture or {}
C.setup(type(payload.leaderboard)=='table' and S.StoredRow(payload,'dummy','Legacyone')==nil
 and (S.StoredRow(payload,'dummy','Steady') or {}).dps==35000,
 'A: fixture: the served payload holds the older map, no converted row and the newer Steady record')
C.setup(type(input.dpsCapture.leaderboard)=='table' and (S.StoredRow(input.dpsCapture,'dummy','Steady') or {}).dps==30000,
 'A: fixture: the legacy location holds the older input')
C.setup(input.legacyDataMigration.staging.characterBest.dummy['steady@ebonhold'].dps==30000,
 'A: fixture: the unfinished receipt stages the older Steady row and a row whose source is gone')
local rawInput=F.Serialize(input.dpsCapture)

local H=F.Boot(input)
Ready('A')
local completed=S.Until(H,S.ConversionSettled,600)
C.expect(completed~=nil,'A: the unfinished conversion completes within 300 s of play',
 Nexus.LegacyDataMigration.Status(NexusDB).state)
local served=S.Until(H,S.ConvertedServed,240)
S.Advance(H,60)
print('OBSERVED','A resumed start-up','complete after',printable(completed),'steps; served after',printable(served),'steps')
S.Observe('A resumed start-up')

local function CheckA(tag)
 local b=S.ExpectConverted(C,tag)
 S.GuardKept(C,tag,35000,b)
 C.guard(Nexus.DpsCapture.GetCharacterBest('dummy','Ghost')==nil and b.ghost==nil,
  tag..': a row that only the unfinished staging held is not published',S.BoardText(b))
 local d=S.BundleDps()
 C.guard(d~=nil and type(d.bundleOnly)=='table' and d.bundleOnly.keep=='bundle top level',
  tag..': an unknown key that only the served payload had stays')
 C.expect(F.Serialize(S.RawDps())==rawInput,tag..': the legacy location is not written (byte-identical to the saved input)')
 local m=S.Receipt() or {}
 C.guard(m.staging==nil and m.inProgress==nil and m.phase==nil,tag..': the completed receipt keeps no staging',
  printable(m.staging~=nil)..'/'..printable(m.inProgress)..'/'..printable(m.phase))
end
CheckA('A resumed start-up')

H.Fire('PLAYER_LOGOUT')
local savedA=F.Serialize(NexusDB)
H=F.Reload()
Ready('A reload')
S.Advance(H,120)
S.Observe('A reload')
C.guard(Jobs()==0,'A reload: the completed conversion is not started again',Jobs())
CheckA('A reload')
local projection,receipt,raw=S.Projection(S.BundleDps()),F.Serialize(S.Receipt()),F.Serialize(S.RawDps())

H.Fire('PLAYER_LOGOUT')
H=F.Reload()
Ready('A second reload')
S.Advance(H,120)
C.guard(Jobs()==0,'A second reload: the completed conversion is not started again',Jobs())
C.guard(S.Projection(S.BundleDps())==projection,'A second reload: the served DPS payload is unchanged (idempotent)',
 S.Projection(S.BundleDps()))
C.guard(F.Serialize(S.Receipt())==receipt,'A second reload: the receipt is byte-identical')
C.guard(F.Serialize(S.RawDps())==raw,'A second reload: the legacy location is byte-identical')
H.Fire('PLAYER_LOGOUT')

-- B. Published, receipt not yet stamped.
local inB=S.Load(savedA)
local served0=type(inB.authorityBundle)=='table' and inB.authorityBundle.dpsCapture or {}
local receiptA=type(inB.legacyDataMigration)=='table' and inB.legacyDataMigration or {}
C.setup(receiptA.state=='complete' and served0.leaderboard==nil and S.StoredRow(served0,'dummy','Legacyone')~=nil,
 'B: fixture: the served payload already holds the conversion')
local before=S.Projection(served0)
inB.legacyDataMigration={schemaVersion=1,version=0,state='staging',inProgress=true,reason='startup',
 sourceSettingsVersion=2,workUnits=receiptA.workUnits,phase='commit',stats=L.Copy(receiptA.stats or {})}
local rawB=F.Serialize(inB.dpsCapture)
H=F.Boot(inB)
Ready('B')
local doneB=S.Until(H,S.ConversionSettled,600)
C.guard(doneB~=nil,'B: the unstamped conversion completes within 300 s of play',
 Nexus.LegacyDataMigration.Status(NexusDB).state)
S.Advance(H,60)
S.Observe('B start-up')
local m=S.Receipt() or {}
C.guard(m.state=='complete' and m.version==2 and m.staging==nil,'B: the receipt completes at storage version 2',
 printable(m.state)..'/'..printable(m.version))
C.guard(S.Projection(S.BundleDps())==before,
 'B: the served payload is unchanged: no duplicate row and no older map (idempotent)',S.Projection(S.BundleDps()))
local b=S.Board('dummy')
C.guard(S.Once(b,'Legacyone',12345) and S.Once(b,'Hintless',23456) and S.Once(b,S.LOCAL,34567)
 and S.Once(b,'Steady',35000),'B: each record is listed once',S.BoardText(b))
C.expect(F.Serialize(S.RawDps())==rawB,'B: the legacy location is not written (byte-identical)')
H.Fire('PLAYER_LOGOUT')

C.finish('(an unfinished conversion of an admitted profile resumes from the served payload, never from stale staging)')
