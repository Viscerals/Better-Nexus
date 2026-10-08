-- Stage-1 finding F-S1-1, part 5 (repair phase): what the conversion or the
-- recovery cannot use is preserved, a conflict keeps the stronger served
-- record, and a recovery never makes a record without lineage.
-- U1. First start-up of an older root whose older map also holds what the
--     converter cannot convert (a row with a score of 0, a category this build
--     does not know, an entry that is not a table) and whose current rows hold
--     a category this build does not know. The converted records are served;
--     the served older map keeps exactly the unconverted parts; the unknown
--     category stays; none of them is shown; the legacy location is not
--     written; a reload starts no conversion or recovery and changes nothing.
-- U2. Recovery of the profile the defect converted, when the served payload
--     already holds a stronger Legacyone record (50000), and its older map also
--     holds a row the converted maps do not hold (Unbacked) and a row with a
--     negative score (Badrow). The stronger record is kept; Hintless and the
--     local record are recovered; Unbacked and Badrow stay in the older map and
--     no record is made for them; the receipt and the legacy location are not
--     written; a reload scans again and publishes nothing.
-- U3. No recovery without lineage: the legacy location still holds its older
--     map (never converted), or its converted maps hold none of the rows.
--     Nothing is recovered or written, and no older record is shown.
-- EXPECT: healthy behaviour that, by reading, does not hold at b704660. GUARD:
-- holds there too and must keep holding. Real TOC boot, Store, catalog,
-- migration, compaction and DPS reads; synthetic data; the saved inputs are
-- written before boot, nothing is forced afterwards.
local S=dofile('tests/prototype/legacy_dps_conversion_support.lua')
local F,L=S.F,S.L
local printable=S.printable
local C=S.Checker('legacy_dps_conversion_unsupported')

local function Ready(tag)
 C.setup(Nexus.StartupStatus().state=='ready',tag..': fixture: start-up reaches ready',Nexus.StartupStatus().state)
end
local function Runtime()
 local s=Nexus.LegacyDataMigration.Status(NexusDB)
 return type(s.runtime)=='table' and s.runtime or {},s
end
local function Row(name,dps,ts)
 return {dps=dps,ts=ts,duration=45,level=80,player=name,class='MAGE',realm='Ebonhold',echoes=L.Copy(S.ECHOES)}
end
-- The row keys of one category of the served older map, sorted.
local function OlderKeys(d,category)
 local lb=type(d)=='table' and type(d.leaderboard)=='table' and d.leaderboard[S.FP] or nil
 local rows=type(lb)=='table' and type(lb[category])=='table' and lb[category] or {}
 local keys={}
 for k in pairs(rows) do keys[#keys+1]=tostring(k) end
 table.sort(keys)
 return table.concat(keys,','),rows
end

-- U1. Unconvertible parts at the first start-up.
do
 local db=S.LegacyInput(S.Fixture(),function(d)
  local entry=d.dpsCapture.leaderboard[S.FP]
  entry.dummy.Zerorow=Row('Zerorow',0,1700000400)
  entry.heroic={Herorow=Row('Herorow',5555,1700000500)}
  d.dpsCapture.leaderboard['zq-odd-entry']='not a table'
  d.dpsCapture.characterBest.futureCategory={keep={note='future category'}}
 end)
 local rawIn=F.Serialize(db.dpsCapture)
 local H=F.Boot(db)
 Ready('U1')
 local done=S.Until(H,S.ConversionSettled,600)
 C.guard(done~=nil,'U1: the conversion completes within 300 s of play',Nexus.LegacyDataMigration.Status(NexusDB).state)
 C.setup(S.Until(H,S.CompactionSettled,2000)~=nil,'U1: fixture: the start-up compaction settles')
 S.Advance(H,20)
 S.Observe('U1 first start-up')
 local D=Nexus.DpsCapture
 local a=D.GetCharacterBest('dummy','Legacyone')
 C.expect(a~=nil and a.dps==12345,'U1: the converted older record is served',a and a.dps)
 local d=S.BundleDps() or {}
 local keys,rows=OlderKeys(d,'dummy')
 C.expect(keys=='Zerorow' and (rows.Zerorow or {}).dps==0,
  'U1: the served older map keeps exactly the row the converter could not convert',keys)
 local entry=type(d.leaderboard)=='table' and d.leaderboard[S.FP] or {}
 C.guard(type(entry)=='table' and type(entry.heroic)=='table' and (entry.heroic.Herorow or {}).dps==5555,
  'U1: and the category this build does not know')
 C.guard(type(d.leaderboard)=='table' and d.leaderboard['zq-odd-entry']=='not a table',
  'U1: and the entry that is not a table')
 C.guard(type(d.characterBest)=='table' and type(d.characterBest.futureCategory)=='table'
  and (d.characterBest.futureCategory.keep or {}).note=='future category',
  'U1: a category of the current rows this build does not know stays')
 local b=S.Board('dummy')
 C.guard(b.zerorow==nil and b.herorow==nil and D.GetCharacterBest('dummy','Herorow')==nil,
  'U1: none of the kept parts is shown',S.BoardText(b))
 C.guard(S.Once(b,'Steady',30000),'U1: Steady keeps its current record and is listed once',S.BoardText(b))
 C.expect(F.Serialize(S.RawDps())==rawIn,'U1: the legacy location is not written (byte-identical to the input)')
 H.Fire('PLAYER_LOGOUT')
 local olderMap,projection=F.Serialize((S.BundleDps() or {}).leaderboard),S.Projection(S.BundleDps())
 H=F.Reload()
 Ready('U1 reload')
 S.Advance(H,120)
 local rt=Runtime()
 C.guard(rt.jobs==0,'U1 reload: no conversion is started again',rt.jobs)
 C.expect(rt.recoveries==0,'U1 reload: no recovery starts: the legacy location holds no converted result',rt.recoveries)
 C.guard(F.Serialize((S.BundleDps() or {}).leaderboard)==olderMap and S.Projection(S.BundleDps())==projection,
  'U1 reload: the served payload is unchanged',S.Projection(S.BundleDps()))
 H.Fire('PLAYER_LOGOUT')
end

-- U2. Recovery conflicts.
do
 local text,made=S.AffectedProfile(S.Fixture())
 C.setup(made.ready and made.received and made.bundle,
  'U2: fixture: the affected profile was made on a settled profile of this build',printable(made.receiveWhy))
 local db=S.Load(text)
 local payload=db.authorityBundle.dpsCapture
 payload.leaderboard[S.FP].dummy.Unbacked=Row('Unbacked',22222,1700000600)
 payload.leaderboard[S.FP].dummy.Badrow=Row('Badrow',-5,1700000650)
 payload.characterBest.dummy['legacyone@ebonhold']={dps=50000,ts=1700000700,duration=60,level=80,player='Legacyone',
  class='MAGE',realm='ebonhold',ownerKey='legacyone@ebonhold',fingerprint=S.FP,echoes=L.Copy(S.ECHOES)}
 C.setup(type(db.legacyDataMigration)=='table' and db.legacyDataMigration.state=='complete'
  and db.dpsCapture.leaderboard==nil and S.StoredRow(db.dpsCapture,'dummy','Legacyone')~=nil,
  'U2: fixture: a complete receipt and the converted maps in the legacy location only')
 local rawIn,receiptIn=F.Serialize(db.dpsCapture),F.Serialize(db.legacyDataMigration)
 local H=F.Boot(db)
 Ready('U2')
 local function Recovered()
  local d=S.BundleDps()
  return d~=nil and S.StoredRow(d,'dummy','Hintless')~=nil
 end
 local at=S.Until(H,Recovered,240)
 S.Advance(H,60)
 print('OBSERVED','U2 recovery start-up','recovered after',printable(at),'steps (bound 240)')
 S.Observe('U2 recovery start-up')
 local D=Nexus.DpsCapture
 local a=D.GetCharacterBest('dummy','Legacyone')
 C.guard(a~=nil and a.dps==50000,
  'U2: the stronger served Legacyone record (50000) is kept; the converted 12345 does not replace it',a and a.dps)
 local h=D.GetCharacterBest('dummy','Hintless')
 C.expect(h~=nil and h.dps==23456 and h.class=='PRIEST' and h.legacyClassInferred==true,
  "U2: the converted Hintless record is recovered with the converter's class hint",
  h and (printable(h.dps)..'/'..printable(h.class)))
 local pb=D.GetPersonalBestForEchoes(L.Copy(S.ECHOES),'dummy')
 C.expect(pb~=nil and pb.dps==34567,'U2: the local record is recovered as its personal best',pb and pb.dps)
 local keys=OlderKeys(S.BundleDps(),'dummy')
 C.expect(keys=='Badrow,Unbacked','U2: the older map keeps exactly the rows nothing accounts for (Badrow, Unbacked)',keys)
 local b=S.Board('dummy')
 C.guard(D.GetCharacterBest('dummy','Unbacked')==nil and b.unbacked==nil and b.badrow==nil,
  'U2: no record is made for them',S.BoardText(b))
 C.guard(S.Once(b,'Legacyone',50000) and S.Once(b,'Steady',35000),
  'U2: Legacyone and Steady are listed once, with their stronger records',S.BoardText(b))
 C.guard(F.Serialize(S.RawDps())==rawIn,'U2: the legacy location is byte-identical')
 C.guard(F.Serialize(S.Receipt())==receiptIn,'U2: the receipt is byte-identical')
 H.Fire('PLAYER_LOGOUT')
 local olderMap,projection=F.Serialize((S.BundleDps() or {}).leaderboard),S.Projection(S.BundleDps())
 H=F.Reload()
 Ready('U2 reload')
 S.Advance(H,120)
 local rt,st=Runtime()
 C.expect(rt.recovered==0 and st.servedRecovery==nil,
  'U2 reload: the recovery scans the rows that remain and publishes nothing',
  printable(rt.recovered)..'/'..printable(st.servedRecovery))
 C.guard(F.Serialize((S.BundleDps() or {}).leaderboard)==olderMap and S.Projection(S.BundleDps())==projection,
  'U2 reload: the served payload is unchanged',S.Projection(S.BundleDps()))
 H.Fire('PLAYER_LOGOUT')
end

-- U3. No lineage, no recovery.
for _,case in ipairs({
 {'U3 legacy location never converted',function(db) db.dpsCapture=S.LegacyInput(S.Fixture()).dpsCapture end},
 {'U3 converted maps hold none of the rows',function(db)
   db.dpsCapture.characterBest={dummy={},lk={}};db.dpsCapture.personalBest={}
  end},
}) do
 local tag=case[1]
 local db=S.Load((S.AffectedProfile(S.Fixture())))
 case[2](db)
 local payload=db.authorityBundle.dpsCapture
 C.setup(type(payload.leaderboard)=='table' and S.StoredRow(payload,'dummy','Legacyone')==nil,
  tag..': fixture: the served payload holds the older map and no converted row')
 local olderIn,projectionIn=F.Serialize(payload.leaderboard),S.Projection(payload)
 local rawIn,receiptIn=F.Serialize(db.dpsCapture),F.Serialize(db.legacyDataMigration)
 local H=F.Boot(db)
 Ready(tag)
 S.Advance(H,120)
 local D=Nexus.DpsCapture
 local b=S.Board('dummy')
 C.guard(D.GetCharacterBest('dummy','Legacyone')==nil and b.legacyone==nil and b.hintless==nil,
  tag..': no older record is recovered or made',S.BoardText(b))
 C.guard(F.Serialize((S.BundleDps() or {}).leaderboard)==olderIn,tag..': the served older map is unchanged')
 C.guard(S.Projection(S.BundleDps())==projectionIn,tag..': the served rows are unchanged',S.Projection(S.BundleDps()))
 C.guard(F.Serialize(S.RawDps())==rawIn,tag..': the legacy location is byte-identical')
 C.guard(F.Serialize(S.Receipt())==receiptIn,tag..': the receipt is byte-identical')
 local rt=Runtime()
 C.guard((rt.recovered or 0)==0,tag..': nothing is published',rt.recovered)
 H.Fire('PLAYER_LOGOUT')
end

C.finish('(unconvertible data is kept, conflicts keep the stronger served record, and no record is made without lineage)')
