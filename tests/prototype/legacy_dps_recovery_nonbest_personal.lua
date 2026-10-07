-- Standards review STD-1 (P2), regression-first: recovering a profile that the
-- defect converted must also serve the personal best of the local character's
-- weaker loadout.
-- The defect (b704660) wrote the one-time conversion into the RAW
-- NexusDB.dpsCapture only. When the older per-build map lists the local
-- character (ownerVerified, its own ownerKey) under two loadouts of one
-- category, the converter keeps the stronger row (FP_B) as the character best
-- and promotes BOTH rows as personal bests (LegacyDataMigration
-- ProcessLeaderboard: PutCharacter, then PutPersonal for every local row). At
-- 7013c49 the recovery (Served.Account) merges a personal best only together
-- with the converted character best it is the same record as: the weaker FP_A
-- row counts as accounted for by the stronger FP_B row and leaves the served
-- older map, and the raw FP_A personal best is never read. No read serves it,
-- and with the older map gone no later start-up can recover it.
-- P0 proves the fixture with the real converter: a first upgrade of an older
-- root with the same two local rows keeps FP_B as the character best and
-- promotes both personal bests, field for field the raw rows the affected
-- profile below holds (SETUP); that first upgrade serves the FP_A personal best
-- (GUARD).
-- R1. Healthy behaviour (EXPECT, fails at 7013c49): one start-up of the
-- affected profile serves the FP_A personal best (34567) through
-- GetPersonalBestForEchoes and the HUD projection (GetSharedHudProjection),
-- with its loadout, verified owner, class and the unknown field of its older
-- row; the same after logout and two reloads. Unchanged (GUARD, holds at
-- 7013c49): the FP_B personal best and the FP_B character best (45678) are
-- served and the weaker row never replaces the character best; the other
-- converted rows are recovered; Steady's newer 35000 and the other current rows
-- stay; unknown keys stay; no older map is left; the raw location (the rollback
-- copy) and the receipt stay byte-identical; reloads start no conversion,
-- publish nothing and change nothing.
-- S1 (GUARD): a stronger FP_A personal best that the served payload already
-- holds (40000) is kept.
-- M1-M3. The raw location holds no FP_A personal best, or one that is not the
-- converted form of the older FP_A row. No personal best is made for FP_A from
-- it (GUARD); the served older map keeps the local FP_A row instead of
-- consuming it (EXPECT, fails at 7013c49); the FP_B character best is
-- recovered; a reload publishes nothing and changes nothing (GUARD).
-- F1-F2 (GUARD): the same profile with a future settings format (read-only) or
-- with a receipt of a future schema is neither recovered nor written.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Real TOC boot, Store, catalog, migration, compaction and DPS reads; the saved
-- inputs are written before boot and nothing is forced afterwards. Synthetic
-- data only: the harness character, the support's artificial characters and
-- the harness Echoes 200001..200005.
local S=dofile('tests/prototype/legacy_dps_conversion_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local F,L=S.F,S.L
local printable=S.printable
local C=V.Checker('legacy_dps_recovery_nonbest_personal')

-- The local character's two loadouts in the Training Dummy category. FP_A is
-- the support's Echo set, whose older row is the local 34567 row; FP_B is a
-- second exact set with a stronger, later row.
local FP_A,E_A=S.FP,S.ECHOES
local FP_B,E_B='200004x1,200005x2',{{spellId=200004,count=1},{spellId=200005,count=2}}
local A_DPS,B_DPS=34567,45678
local NOTE_A,NOTE_B='local FP_A row','local FP_B row'

-- The older map's local rows, each with an unknown field.
local function OlderA()
 local row=S.LegacyRows()[S.LOCAL]
 row.localNote={keep=NOTE_A}
 return row
end
local function OlderB()
 return {dps=B_DPS,ts=1700000300,duration=60,level=80,player=S.LOCAL,class='MAGE',realm='Ebonhold',
  ownerKey=S.LOCAL_OWNER,ownerVerified=true,echoes=L.Copy(E_B),localNote={keep=NOTE_B}}
end
-- A local row as the converter stores it: the loadout of its older-map entry,
-- the canonical owner key and the realm taken from that key. P0 compares these
-- rows with the real converter's output.
local function Converted(row,fingerprint)
 local out=L.Copy(row)
 out.fingerprint=fingerprint
 out.ownerKey=S.LOCAL_OWNER
 out.realm=S.LOCAL_OWNER:match('@(.+)$')
 return out
end
local function RawA() return Converted(OlderA(),FP_A) end
local function RawB() return Converted(OlderB(),FP_B) end

-- What identifies a stored local row: score, time, loadout, player, owner,
-- verification, class, realm, duration, level and its unknown field.
local function Ident(r)
 if type(r)~='table' then return '<none>' end
 local note=type(r.localNote)=='table' and r.localNote.keep or nil
 local values={r.dps,r.ts,r.fingerprint,r.player,r.ownerKey,r.ownerVerified,r.class,r.realm,r.duration,r.level,note}
 local out={}
 for i=1,11 do out[i]=printable(values[i]) end
 return table.concat(out,'/')
end
-- Saved tables, read raw (no reader runs).
local function Personal(dps,fingerprint)
 local entry=type(dps)=='table' and type(dps.personalBest)=='table' and dps.personalBest[fingerprint] or nil
 local row=type(entry)=='table' and entry.dummy or nil
 return type(row)=='table' and row or nil
end
local function OlderRow(dps,fingerprint)
 local entry=type(dps)=='table' and type(dps.leaderboard)=='table' and dps.leaderboard[fingerprint] or nil
 local rows=type(entry)=='table' and entry.dummy or nil
 local row=type(rows)=='table' and rows[S.LOCAL] or nil
 return type(row)=='table' and row or nil
end
-- The real reads: the exact-set personal best and the HUD projection.
local function PersonalFor(echoes) return Nexus.DpsCapture.GetPersonalBestForEchoes(L.Copy(echoes),'dummy') end
local function HudPersonal(echoes)
 local value=Nexus.DpsCapture.GetSharedHudProjection(S.LOCAL,L.Copy(echoes))
 local dummy=type(value)=='table' and type(value.performance)=='table' and value.performance.dummy or nil
 return type(dummy)=='table' and dummy.personal or nil
end
local function Dps(r) return r and printable(r.dps) or '-' end
local function Ready(tag)
 C.setup(Nexus.StartupStatus().state=='ready',tag..': fixture: start-up reaches ready',Nexus.StartupStatus().state)
end
local function Runtime()
 local s=Nexus.LegacyDataMigration.Status(NexusDB)
 return type(s.runtime)=='table' and s.runtime or {}
end
-- The converted Legacyone row is served: the recovery has published.
local function Recovered() return S.StoredRow(S.BundleDps(),'dummy','Legacyone')~=nil end
local function ObserveLocal(tag)
 local d,raw=S.BundleDps(),S.RawDps()
 print('OBSERVED',tag,'served.characterBest.local='..Dps(S.StoredRow(d,'dummy',S.LOCAL)),
  'served.personal.A='..Dps(Personal(d,FP_A)),'served.personal.B='..Dps(Personal(d,FP_B)),
  'served.older.A='..Dps(OlderRow(d,FP_A)),'served.older.B='..Dps(OlderRow(d,FP_B)),
  'raw.personal.A='..Dps(Personal(raw,FP_A)),'raw.personal.B='..Dps(Personal(raw,FP_B)))
end

-- P0. The fixture's premise, from the real converter.
C.scenario('P0 the real converter on a first upgrade of the same older map',function()
 local db=S.LegacyInput(S.Fixture(),function(d)
  local older=d.dpsCapture.leaderboard
  older[FP_A].dummy[S.LOCAL]=OlderA()
  older[FP_B]={dummy={[S.LOCAL]=OlderB()}}
 end)
 C.setup(rawget(db,'authorityBundle')==nil and rawget(db,'legacyDataMigration')==nil
  and Ident(OlderRow(db.dpsCapture,FP_A))==Ident(OlderA()) and Ident(OlderRow(db.dpsCapture,FP_B))==Ident(OlderB()),
  'P0: fixture: an older saved root whose older map lists the local character under FP_A (34567) and FP_B (45678)')
 local H=F.Boot(db)
 Ready('P0')
 C.setup(S.Until(H,S.ConversionSettled,600)~=nil,'P0: fixture: the one-time conversion completes',
  Nexus.LegacyDataMigration.Status(NexusDB).state)
 C.setup(S.Until(H,S.ConvertedServed,240)~=nil,'P0: fixture: its result is served')
 S.Advance(H,20)
 ObserveLocal('P0 first upgrade')
 local d=S.BundleDps()
 local best,pa,pb=S.StoredRow(d,'dummy',S.LOCAL),Personal(d,FP_A),Personal(d,FP_B)
 C.setup(Ident(best)==Ident(RawB()),
  "P0: the converter keeps the stronger FP_B row as the local character best, as the affected profile's raw location holds it",
  Ident(best))
 C.setup(Ident(pa)==Ident(RawA()),
  'P0: it promotes the weaker FP_A row as the personal best of FP_A, as the raw location holds it',Ident(pa))
 C.setup(Ident(pb)==Ident(RawB()),'P0: and the FP_B row as the personal best of FP_B, as the raw location holds it',Ident(pb))
 local a,hudA,b=PersonalFor(E_A),HudPersonal(E_A),PersonalFor(E_B)
 C.guard(a~=nil and a.dps==A_DPS,'P0: a first upgrade serves the FP_A personal best (34567) through GetPersonalBestForEchoes',Dps(a))
 C.guard(hudA~=nil and hudA.dps==A_DPS,'P0: and through the HUD projection',Dps(hudA))
 C.guard(b~=nil and b.dps==B_DPS,'P0: and the FP_B personal best (45678)',Dps(b))
 local me=Nexus.DpsCapture.GetCharacterBest('dummy',S.LOCAL)
 C.guard(me~=nil and me.dps==B_DPS and me.fingerprint==FP_B,'P0: with the FP_B row as the character best',Ident(me))
 H.Fire('PLAYER_LOGOUT')
end)

-- The profile the defective start-up left (legacy_dps_conversion_support).
local text,made=S.AffectedProfile(S.Fixture())
C.setup(made.ready and made.noConversion,'fixture: the base profile of this build starts and owes no conversion')
C.setup(made.compacted and made.compactedAfter,'fixture: its start-up compaction completed before it was saved')
C.setup(made.readyAgain,'fixture: one more session of the saved base profile starts')
C.setup(made.received and made.servedSteady==35000,
 'fixture: a newer, stronger Steady record (35000) was accepted through the real receive path and served',
 printable(made.receiveWhy)..' / '..printable(made.servedSteady))
C.setup(made.bundle,'fixture: the saved profile has a served DPS payload')

-- That profile when the local character has rows on two loadouts: the served
-- older map lists both local rows, and the raw location holds what the
-- converter made of them (P0): character best FP_B, personal bests FP_A and
-- FP_B. The receipt's counts include the second personal best.
local function TwoLoadoutProfile()
 local db=S.Load(text)
 if type(db.authorityBundle)~='table' or type(db.authorityBundle.dpsCapture)~='table' then return db end
 local older=db.authorityBundle.dpsCapture.leaderboard
 older[FP_A].dummy[S.LOCAL]=OlderA()
 older[FP_B]={dummy={[S.LOCAL]=OlderB()}}
 local raw=db.dpsCapture
 raw.characterBest.dummy[S.LOCAL_OWNER]=RawB()
 raw.personalBest={[FP_A]={dummy=RawA()},[FP_B]={dummy=RawB()}}
 local receipt=db.legacyDataMigration
 receipt.stats.legacyRowsPromoted=4
 receipt.stats.personalRowsPromoted=2
 receipt.lastResult.personalFingerprints=2
 return db
end

-- The recovered state through the real reads. EXPECT: the FP_A personal best.
local function CheckRecovered(tag,rawIn,receiptIn)
 local D=Nexus.DpsCapture
 local a=PersonalFor(E_A)
 C.expect(a~=nil and a.dps==A_DPS,
  tag..': GetPersonalBestForEchoes serves the personal best of the weaker loadout FP_A (34567)',Dps(a))
 C.expect(a~=nil and a.fingerprint==FP_A and a.player==S.LOCAL and a.ownerKey==S.LOCAL_OWNER
  and a.ownerVerified==true and a.class=='MAGE',tag..': with its loadout, player, verified owner and class',Ident(a))
 C.expect(a~=nil and type(a.localNote)=='table' and a.localNote.keep==NOTE_A,
  tag..': and with the unknown field of its older row',a and type(a.localNote))
 local hudA=HudPersonal(E_A)
 C.expect(hudA~=nil and hudA.dps==A_DPS,
  tag..': the HUD projection (GetSharedHudProjection) shows it as the personal best of FP_A',Dps(hudA))
 local b,hudB=PersonalFor(E_B),HudPersonal(E_B)
 C.guard(b~=nil and b.dps==B_DPS and b.fingerprint==FP_B and b.ownerKey==S.LOCAL_OWNER and b.ownerVerified==true,
  tag..': the personal best of the stronger loadout FP_B (45678) is served with its verified owner',Ident(b))
 C.guard(hudB~=nil and hudB.dps==B_DPS,tag..': the HUD projection shows it for FP_B',Dps(hudB))
 local me=D.GetCharacterBest('dummy',S.LOCAL)
 C.guard(me~=nil and me.dps==B_DPS and me.fingerprint==FP_B,
  tag..': the local character best is the stronger FP_B row (45678); the weaker FP_A row does not replace it',Ident(me))
 local board=S.Board('dummy')
 C.guard(S.Once(board,S.LOCAL,B_DPS),tag..': GetDpsBoard lists the local character once, with 45678',S.BoardText(board))
 local lo=D.GetCharacterBest('dummy','Legacyone')
 C.guard(lo~=nil and lo.dps==12345 and type(lo.legacyNote)=='table' and lo.legacyNote.keep=='legacy row',
  tag..': the converted Legacyone record is recovered with its unknown field',Dps(lo))
 local hi=D.GetCharacterBest('dummy','Hintless')
 C.guard(hi~=nil and hi.dps==23456 and hi.class=='PRIEST' and hi.legacyClassInferred==true,
  tag..": the converted Hintless record is recovered with the converter's class hint",
  hi and (printable(hi.dps)..'/'..printable(hi.class)))
 S.GuardKept(C,tag,35000,board)
 local d=S.BundleDps()
 C.guard(d~=nil and d.leaderboard==nil,tag..': no older map is left: every older row is accounted for',d and type(d.leaderboard))
 C.guard(d~=nil and type(d.bundleOnly)=='table' and d.bundleOnly.keep=='bundle top level',
  tag..': an unknown key that only the served payload had stays',d and type(d.bundleOnly))
 C.guard(F.Serialize(S.RawDps())==rawIn,tag..': the raw location (the rollback copy) is byte-identical to the saved input')
 C.guard(F.Serialize(S.Receipt())==receiptIn,tag..': the receipt is byte-identical')
end

-- R1. The affected profile with two local loadouts: start-up, reload, reload.
C.scenario('R1 recovery of the affected profile with two local loadouts',function()
 local db=TwoLoadoutProfile()
 local payload=type(db.authorityBundle)=='table' and db.authorityBundle.dpsCapture or nil
 local raw,receipt=db.dpsCapture,db.legacyDataMigration
 C.setup(type(receipt)=='table' and receipt.state=='complete' and receipt.version==2,
  'R1: fixture: the receipt says the one-time conversion is complete (storage version 2)')
 C.setup(type(raw)=='table' and raw.leaderboard==nil and Ident(S.StoredRow(raw,'dummy',S.LOCAL))==Ident(RawB())
  and Ident(Personal(raw,FP_A))==Ident(RawA()) and Ident(Personal(raw,FP_B))==Ident(RawB()),
  'R1: fixture: the raw location holds the converted maps: character best FP_B, personal bests FP_A and FP_B')
 C.setup(Ident(OlderRow(payload,FP_A))==Ident(OlderA()) and Ident(OlderRow(payload,FP_B))==Ident(OlderB()),
  'R1: fixture: the served older map lists both local rows')
 C.setup(type(payload)=='table' and S.StoredRow(payload,'dummy',S.LOCAL)==nil and Personal(payload,FP_A)==nil
  and Personal(payload,FP_B)==nil and S.StoredRow(payload,'dummy','Legacyone')==nil,
  'R1: fixture: the served payload holds no converted row and no personal best of either loadout')
 C.setup((S.StoredRow(payload,'dummy','Steady') or {}).dps==35000 and (S.StoredRow(raw,'dummy','Steady') or {}).dps==30000,
  'R1: fixture: Steady is 35000 in the served payload and 30000 in the raw copy')
 local rawIn,receiptIn=F.Serialize(raw),F.Serialize(receipt)
 local H=F.Boot(db)
 Ready('R1')
 local at=S.Until(H,Recovered,240)
 S.Advance(H,60)
 print('OBSERVED','R1 recovery start-up','recovered after',printable(at),'steps (bound 240)')
 S.Observe('R1 recovery start-up')
 ObserveLocal('R1 recovery start-up')
 C.guard(at~=nil,'R1: the recovery publishes within the bound (the converted Legacyone row is served)')
 CheckRecovered('R1 recovery start-up',rawIn,receiptIn)

 H.Fire('PLAYER_LOGOUT')
 H=F.Reload()
 Ready('R1 reload')
 S.Advance(H,120)
 ObserveLocal('R1 reload')
 local rt=Runtime()
 C.guard(rt.jobs==0,'R1 reload: no conversion is started again',rt.jobs)
 C.guard((rt.recovered or 0)==0,'R1 reload: no recovery publishes again',rt.recovered)
 CheckRecovered('R1 reload',rawIn,receiptIn)
 local projection=S.Projection(S.BundleDps())

 H.Fire('PLAYER_LOGOUT')
 H=F.Reload()
 Ready('R1 second reload')
 S.Advance(H,120)
 ObserveLocal('R1 second reload')
 rt=Runtime()
 C.guard(rt.jobs==0 and (rt.recovered or 0)==0,'R1 second reload: nothing is converted or published',
  printable(rt.jobs)..'/'..printable(rt.recovered))
 C.guard(S.Projection(S.BundleDps())==projection,'R1 second reload: the served DPS payload is unchanged (idempotent)',
  S.Projection(S.BundleDps()))
 CheckRecovered('R1 second reload',rawIn,receiptIn)
 H.Fire('PLAYER_LOGOUT')
end)

-- S1. A stronger FP_A personal best is already served.
C.scenario('S1 a stronger FP_A personal best already served',function()
 local db=TwoLoadoutProfile()
 local payload=db.authorityBundle.dpsCapture
 payload.personalBest=type(payload.personalBest)=='table' and payload.personalBest or {}
 payload.personalBest[FP_A]={dummy={dps=40000,ts=1700000900,duration=60,level=80,player=S.LOCAL,class='MAGE',
  realm='ebonhold',ownerKey=S.LOCAL_OWNER,ownerVerified=true,fingerprint=FP_A,echoes=L.Copy(E_A)}}
 C.setup((Personal(payload,FP_A) or {}).dps==40000 and (Personal(db.dpsCapture,FP_A) or {}).dps==A_DPS,
  'S1: fixture: the served payload holds a stronger FP_A personal best (40000); the raw location the converted 34567')
 local rawIn,receiptIn=F.Serialize(db.dpsCapture),F.Serialize(db.legacyDataMigration)
 local H=F.Boot(db)
 Ready('S1')
 local at=S.Until(H,Recovered,240)
 S.Advance(H,60)
 ObserveLocal('S1 recovery start-up')
 C.guard(at~=nil,'S1: the recovery publishes within the bound')
 local a,b=PersonalFor(E_A),PersonalFor(E_B)
 C.guard(a~=nil and a.dps==40000,
  'S1: the stronger served FP_A personal best (40000) is kept; the converted 34567 does not replace it',Dps(a))
 C.guard(b~=nil and b.dps==B_DPS,'S1: the FP_B personal best is recovered',Dps(b))
 C.guard(F.Serialize(S.RawDps())==rawIn,'S1: the raw location is byte-identical')
 C.guard(F.Serialize(S.Receipt())==receiptIn,'S1: the receipt is byte-identical')
 H.Fire('PLAYER_LOGOUT')
end)

-- M1-M3. No raw personal best that is the converted FP_A row.
for _,case in ipairs({
 {tag='M1 no raw FP_A personal best',personalB=true,mutate=function(raw) raw.personalBest[FP_A]=nil end},
 {tag='M2 a raw FP_A personal best of another record',personalB=true,mutate=function(raw)
   local other=RawA()
   other.dps,other.ts,other.localNote=39999,1700000250,nil
   raw.personalBest[FP_A]={dummy=other}
  end},
 {tag='M3 no raw personal best of either loadout',personalB=false,mutate=function(raw) raw.personalBest={} end},
}) do
 local tag=case.tag
 C.scenario(tag,function()
  local db=TwoLoadoutProfile()
  case.mutate(db.dpsCapture)
  local raw,payload=db.dpsCapture,db.authorityBundle.dpsCapture
  local rawA=Personal(raw,FP_A)
  C.setup(rawA==nil or Ident(rawA)~=Ident(RawA()),
   tag..': fixture: the raw location holds no converted form of the older FP_A row as a personal best',Ident(rawA))
  C.setup(Ident(S.StoredRow(raw,'dummy',S.LOCAL))==Ident(RawB()) and OlderRow(payload,FP_A)~=nil
   and OlderRow(payload,FP_B)~=nil,tag..': fixture: the raw character best is FP_B and the served older map lists both local rows')
  local rawIn,receiptIn=F.Serialize(raw),F.Serialize(db.legacyDataMigration)
  local H=F.Boot(db)
  Ready(tag)
  local at=S.Until(H,Recovered,240)
  S.Advance(H,60)
  ObserveLocal(tag..' recovery start-up')
  C.guard(at~=nil,tag..': the recovery publishes within the bound')
  local kept=OlderRow(S.BundleDps(),FP_A)
  C.expect(Ident(kept)==Ident(OlderA()),
   tag..': the served older map keeps the local FP_A row: no converted personal best accounts for it, so it is not consumed',
   Ident(kept))
  local a=PersonalFor(E_A)
  C.guard(a==nil,tag..': no personal best is made for FP_A from data that is not its converted row',Dps(a))
  local me=Nexus.DpsCapture.GetCharacterBest('dummy',S.LOCAL)
  C.guard(me~=nil and me.dps==B_DPS and me.fingerprint==FP_B,tag..': the FP_B character best (45678) is recovered',Ident(me))
  if case.personalB then
   local b=PersonalFor(E_B)
   C.guard(b~=nil and b.dps==B_DPS,tag..': the FP_B personal best is recovered',Dps(b))
  end
  C.guard(F.Serialize(S.RawDps())==rawIn,tag..': the raw location is byte-identical')
  C.guard(F.Serialize(S.Receipt())==receiptIn,tag..': the receipt is byte-identical')
  H.Fire('PLAYER_LOGOUT')
  local olderMap,projection=F.Serialize((S.BundleDps() or {}).leaderboard),S.Projection(S.BundleDps())
  H=F.Reload()
  Ready(tag..' reload')
  S.Advance(H,120)
  ObserveLocal(tag..' reload')
  local rt=Runtime()
  C.guard((rt.recovered or 0)==0,tag..' reload: nothing is published again',rt.recovered)
  C.guard(F.Serialize((S.BundleDps() or {}).leaderboard)==olderMap and S.Projection(S.BundleDps())==projection,
   tag..' reload: the served payload is unchanged',S.Projection(S.BundleDps()))
  C.guard(PersonalFor(E_A)==nil,tag..' reload: still no personal best for FP_A')
  H.Fire('PLAYER_LOGOUT')
 end)
end

-- F1-F2. Saved data this build keeps read-only, or a receipt it refuses.
for _,case in ipairs({
 {tag='F1 the profile kept read-only (future settings format 6)',wholeRoot=true,
  mutate=function(db) db.settingsVersion=6 end},
 {tag='F2 the profile with a receipt of a future schema',wholeRoot=false,
  mutate=function(db) db.legacyDataMigration.schemaVersion=9 end},
}) do
 local tag=case.tag
 C.scenario(tag,function()
  local db=TwoLoadoutProfile()
  case.mutate(db)
  local input=F.Serialize(db)
  local rawIn,servedIn=F.Serialize(db.dpsCapture),F.Serialize(db.authorityBundle.dpsCapture)
  local receiptIn=F.Serialize(db.legacyDataMigration)
  local H=F.Boot(db)
  C.setup(Nexus.StartupStatus().state~='pending',tag..': fixture: start-up reaches a terminal state',
   Nexus.StartupStatus().state)
  S.Advance(H,120)
  local a,b=PersonalFor(E_A),PersonalFor(E_B)
  local me=Nexus.DpsCapture.GetCharacterBest('dummy',S.LOCAL)
  S.Advance(H,20)
  ObserveLocal(tag)
  C.guard(a==nil and b==nil and me==nil,
   tag..': nothing is recovered: no personal best and no character best of the local character is served',
   Dps(a)..'/'..Dps(b)..'/'..Dps(me))
  if case.wholeRoot then
   C.guard(F.Serialize(NexusDB)==input,tag..': the reads write nothing: the saved root is byte-identical')
  end
  C.guard(F.Serialize(S.Receipt())==receiptIn,tag..': the receipt is byte-identical')
  C.guard(F.Serialize(S.RawDps())==rawIn,tag..': the raw location is byte-identical')
  C.guard(F.Serialize(S.BundleDps())==servedIn,tag..': the served DPS payload is byte-identical')
  H.Fire('PLAYER_LOGOUT')
 end)
end

C.finish('(the recovery serves the personal best of every converted local loadout and keeps what it cannot account for)')
