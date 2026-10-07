-- Shared fixtures of the regressions for stage-1 finding F-S1-1 (the one-time
-- legacy DPS conversion and the DPS data this build serves):
-- legacy_dps_conversion_served, legacy_dps_conversion_recovery and
-- legacy_dps_conversion_refusals. Not a test itself: the name ends in
-- _support, so tools/ci_check.py does not list it.
--
-- Synthetic data only: artificial character names and scores, the harness
-- Echoes 200001..200090. Current builds and DPS rows come from
-- leaderboard_fixture_support.lua (the shapes of the addon's own writers, with
-- content keys from the product's LoadoutEvidence). The older per-fingerprint
-- leaderboard rows (leaderboard[fingerprint][category][player]) have the shape
-- an older writer left, as in readonly_saved_dps_visibility: no protocol
-- version, no evidence key, inline {spellId,count} Echoes, and no owner
-- verification except on the local character's own row.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local S={F=F,L=L}
S.FP='200001x2,200002x3,200003x1'
S.ECHOES={{spellId=200001,count=2},{spellId=200002,count=3},{spellId=200003,count=1}}
S.LOCAL,S.LOCAL_OWNER=F.NAME,F.OWNER
-- One settle step of play time.
S.STEP=.5

local function printable(v)
 local ok,s=pcall(tostring,v)
 return ok and type(s)=='string' and s or '<unprintable '..type(v)..'>'
end
S.printable=printable

function S.Load(text) return assert(loadstring('return '..text))() end

-- Every check is evaluated and reported; finish() fails at the end if any did
-- not hold. SETUP: the fixture reached its state. EXPECT: healthy behaviour
-- that does not hold at b704660 (the reproduced defect). GUARD: behaviour that
-- already holds at b704660 and must keep holding.
function S.Checker(name)
 local C={failures={},n={setup=0,expect=0,guard=0},bad={setup=0,expect=0,guard=0}}
 local function check(kind,ok,label,detail)
  C.n[kind]=C.n[kind]+1
  if ok then return true end
  C.bad[kind]=C.bad[kind]+1
  local line=kind:upper()..' '..label..(detail~=nil and (' ['..printable(detail)..']') or '')
  C.failures[#C.failures+1]=line
  print('FAIL '..line)
  return false
 end
 function C.setup(ok,label,detail) return check('setup',ok and true or false,label,detail) end
 function C.expect(ok,label,detail) return check('expect',ok and true or false,label,detail) end
 function C.guard(ok,label,detail) return check('guard',ok and true or false,label,detail) end
 function C.finish(note)
  print(string.format('SUMMARY %s: expectations held %d of %d; guards held %d of %d; setup held %d of %d',
   name,C.n.expect-C.bad.expect,C.n.expect,C.n.guard-C.bad.guard,C.n.guard,C.n.setup-C.bad.setup,C.n.setup))
  if #C.failures>0 then
   error(name..': '..#C.failures..' check(s) failed ('..C.bad.expect..' expectation, '..C.bad.guard..' guard, '
    ..C.bad.setup..' setup); first: '..C.failures[1],0)
  end
  print('PASS '..name..(note and (' '..note) or '')..' checks='..(C.n.setup+C.n.expect+C.n.guard))
 end
 return C
end

-- Steady: a current, verified Training Dummy record (30000); the older map also
-- lists Steady, with a weaker and older score. Newcomer: a current, verified
-- Lich King record. Hintless: a build only; its author and class (PRIEST) are
-- the converter's class hint for Hintless's classless older row.
function S.Fixture()
 return L.New({players={
  {name='Steady',class='MAGE',dps={dummy=30000}},
  {name='Newcomer',class='PALADIN',dps={lk=40000}},
  {name='Hintless',class='PRIEST'},
 }})
end

-- The older per-fingerprint rows, one exact Echo set, Training Dummy only.
function S.LegacyRows()
 local function E() return L.Copy(S.ECHOES) end
 return {
  Legacyone={dps=12345,ts=1700000000,duration=45,level=80,player='Legacyone',class='MAGE',
   realm='Ebonhold',echoes=E(),legacyNote={keep='legacy row'}},
  Hintless={dps=23456,ts=1700000100,duration=50,level=80,player='Hintless',realm='Ebonhold',echoes=E()},
  Steady={dps=11111,ts=1690000000,duration=40,level=80,player='Steady',class='MAGE',realm='Ebonhold',echoes=E()},
  [S.LOCAL]={dps=34567,ts=1700000200,duration=60,level=80,player=S.LOCAL,class='MAGE',realm='Ebonhold',
   ownerKey=S.LOCAL_OWNER,ownerVerified=true,echoes=E()},
 }
end

-- A saved root of an older release: settings format 2, no authority bundle,
-- the fixture's builds and current rows, the older leaderboard map, and an
-- unknown key in the DPS table (F.Database also carries unknown root keys).
function S.LegacyInput(fx,mutate)
 local db=F.Database({version=2})
 fx:Install(db)
 db.dpsCapture.leaderboard={[S.FP]={dummy=S.LegacyRows()}}
 db.dpsCapture.futureDpsKey={keep='dps top level'}
 if mutate then mutate(db) end
 return db
end

-- Raw accessors (rawget only; no reader runs).
function S.Bundle()
 local b=type(NexusDB)=='table' and rawget(NexusDB,'authorityBundle') or nil
 return type(b)=='table' and b or nil
end
function S.BundleDps()
 local b=S.Bundle()
 local d=b and rawget(b,'dpsCapture') or nil
 return type(d)=='table' and d or nil
end
function S.RawDps()
 local d=type(NexusDB)=='table' and rawget(NexusDB,'dpsCapture') or nil
 return type(d)=='table' and d or nil
end
function S.Receipt()
 local m=type(NexusDB)=='table' and rawget(NexusDB,'legacyDataMigration') or nil
 return type(m)=='table' and m or nil
end
-- The row of one player in one character-best bucket of a DPS table.
function S.StoredRow(dps,category,name)
 local cb=type(dps)=='table' and type(dps.characterBest)=='table' and dps.characterBest[category] or nil
 if type(cb)~='table' then return nil end
 for _,row in pairs(cb) do
  if type(row)=='table' and type(row.player)=='string' and row.player:lower()==name:lower() then return row end
 end
 return nil
end
-- Does the raw legacy location still hold this record, converted or as the
-- older map had it? (The rollback copy.)
function S.RawHolds(name,score)
 local raw=S.RawDps()
 if not raw then return false end
 local row=S.StoredRow(raw,'dummy',name)
 if type(row)=='table' and row.dps==score then return true end
 local lb=type(raw.leaderboard)=='table' and raw.leaderboard[S.FP] or nil
 local old=type(lb)=='table' and type(lb.dummy)=='table' and lb.dummy[name] or nil
 return type(old)=='table' and old.dps==score
end

function S.Until(H,done,limit)
 for i=1,limit do
  if done() then return i end
  H.Advance(S.STEP,S.STEP)
 end
 return done() and limit or nil
end
function S.Advance(H,n) for _=1,n do H.Advance(S.STEP,S.STEP) end end
function S.ConversionSettled()
 local s=Nexus.LegacyDataMigration.Status(NexusDB)
 return s.state=='complete' and not s.pending
end
-- The served payload holds the converted Legacyone row and no older map.
function S.ConvertedServed()
 local d=S.BundleDps()
 return d~=nil and d.leaderboard==nil and S.StoredRow(d,'dummy','Legacyone')~=nil
end
function S.CompactionSettled()
 local m=(S.Bundle() or {}).dataCompaction
 return type(m)=='table' and m.version~=nil and m.inProgress==nil
  and not Nexus.Scheduler.Pending('data-compaction')
end

-- The real public board of one category: player (lower case) -> scores listed.
function S.Board(category)
 local out={}
 for _,r in ipairs(Nexus.DpsCapture.GetDpsBoard(category or 'dummy') or {}) do
  local k=type(r.player)=='string' and r.player:lower() or '?'
  out[k]=out[k] or {}
  out[k][#out[k]+1]=r.dps
 end
 return out
end
function S.BoardText(b)
 local keys={}
 for k in pairs(b or {}) do keys[#keys+1]=k end
 table.sort(keys)
 local out={}
 for _,k in ipairs(keys) do
  local v={}
  for i,x in ipairs(b[k]) do v[i]=printable(x) end
  out[#out+1]=k..'='..table.concat(v,'/')
 end
 return table.concat(out,' ')
end
function S.Once(b,name,score)
 local l=type(b)=='table' and b[name:lower()] or nil
 return type(l)=='table' and #l==1 and l[1]==score
end

-- A semantic projection of one DPS table: per category and row key the player,
-- score, time, class and inferred-class mark; the personal bests; whether an
-- older map is present; the top-level keys.
function S.Projection(dps)
 if type(dps)~='table' then return '<none>' end
 local out={}
 for _,cat in ipairs({'dummy','lk'}) do
  local cb=type(dps.characterBest)=='table' and dps.characterBest[cat] or nil
  local rows={}
  for k,r in pairs(type(cb)=='table' and cb or {}) do
   if type(r)=='table' then
    rows[#rows+1]=printable(k)..'='..printable(r.player)..'/'..printable(r.dps)..'/'..printable(r.ts)
     ..'/'..printable(r.class)..'/'..printable(r.legacyClassInferred)
   end
  end
  table.sort(rows)
  out[#out+1]=cat..'{'..table.concat(rows,';')..'}'
 end
 local personal={}
 for fp,cats in pairs(type(dps.personalBest)=='table' and dps.personalBest or {}) do
  if type(cats)=='table' then
   for cat,r in pairs(cats) do
    if type(r)=='table' then personal[#personal+1]=printable(fp)..':'..printable(cat)..'='..printable(r.dps) end
   end
  end
 end
 table.sort(personal)
 out[#out+1]='personal{'..table.concat(personal,';')..'}'
 out[#out+1]='leaderboard='..printable(dps.leaderboard~=nil)
 local keys={}
 for k in pairs(dps) do keys[#keys+1]=printable(k) end
 table.sort(keys)
 out[#out+1]='keys='..table.concat(keys,',')
 return table.concat(out,' ')
end

-- One bounded line of what the saved tables hold (evidence for the record).
function S.Observe(tag)
 local d,raw,m=S.BundleDps(),S.RawDps(),S.Receipt()
 local status=Nexus.LegacyDataMigration.Status(NexusDB)
 local runtime=type(status.runtime)=='table' and status.runtime or {}
 local function score(t,name)
  local r=S.StoredRow(t,'dummy',name)
  return r and printable(r.dps) or '-'
 end
 print('OBSERVED',tag,'receipt='..printable(m and m.state)..'/'..printable(m and m.version),
  'served.leaderboard='..printable(d and d.leaderboard~=nil),'served.Legacyone='..score(d,'Legacyone'),
  'served.Hintless='..score(d,'Hintless'),'served.Steady='..score(d,'Steady'),
  'raw.leaderboard='..printable(raw and raw.leaderboard~=nil),'raw.Legacyone='..score(raw,'Legacyone'),
  'raw==served='..printable(raw~=nil and raw==d),'jobs='..printable(runtime.jobs),
  'completed='..printable(runtime.completed))
end

-- The converted records, through the real DPS reads (EXPECT checks: at
-- b704660 none of them is served).
function S.ExpectConverted(C,tag)
 local D=Nexus.DpsCapture
 local d=S.BundleDps()
 C.expect(d~=nil and d.leaderboard==nil,
  tag..': the served DPS payload (authorityBundle.dpsCapture) holds no older leaderboard map',d and type(d.leaderboard))
 local a=D.GetCharacterBest('dummy','Legacyone')
 C.expect(a~=nil and a.dps==12345 and a.class=='MAGE',
  tag..': GetCharacterBest serves the converted older record of Legacyone (12345, MAGE)',
  a and (printable(a.dps)..'/'..printable(a.class)))
 C.expect(a~=nil and type(a.legacyNote)=='table' and a.legacyNote.keep=='legacy row',
  tag..': with the unknown field of its older row',a and type(a.legacyNote))
 local info=D.GetPlayerInfo('Legacyone')
 C.expect(info~=nil and info.dps==12345 and info.category=='dummy',tag..': GetPlayerInfo serves it',
  info and (printable(info.dps)..'/'..printable(info.category)))
 local h=D.GetCharacterBest('dummy','Hintless')
 C.expect(h~=nil and h.dps==23456 and h.class=='PRIEST' and h.legacyClassInferred==true,
  tag..": the classless older record of Hintless is served with the converter's class hint (23456, PRIEST, inferred)",
  h and (printable(h.dps)..'/'..printable(h.class)..'/'..printable(h.legacyClassInferred)))
 local me=D.GetCharacterBest('dummy',S.LOCAL)
 C.expect(me~=nil and me.dps==34567,tag..': the local older record is served as its character best (34567)',me and me.dps)
 local pb=D.GetPersonalBestForEchoes(L.Copy(S.ECHOES),'dummy')
 C.expect(pb~=nil and pb.dps==34567,tag..': and as the personal best of its exact Echo set (34567)',pb and pb.dps)
 local b=S.Board('dummy')
 C.expect(S.Once(b,'Legacyone',12345) and S.Once(b,'Hintless',23456) and S.Once(b,S.LOCAL,34567),
  tag..': GetDpsBoard lists each converted record once',S.BoardText(b))
 return b
end

-- What every correct path keeps (GUARD checks: they hold at b704660).
function S.GuardKept(C,tag,steady,b)
 local D=Nexus.DpsCapture
 local st=D.GetCharacterBest('dummy','Steady')
 C.guard(st~=nil and st.dps==steady,
  tag..': Steady keeps its current record ('..steady..'); a weaker or older score is never served instead',st and st.dps)
 C.guard(st~=nil and st.ownerVerified==true and st.ownerKey=='steady@ebonhold',tag..': with its verified owner',
  st and (printable(st.ownerVerified)..'/'..printable(st.ownerKey)))
 b=b or S.Board('dummy')
 C.guard(S.Once(b,'Steady',steady),tag..': and is listed once on the board',S.BoardText(b))
 local nc=D.GetCharacterBest('lk','Newcomer')
 C.guard(nc~=nil and nc.dps==40000,tag..': Newcomer keeps its Lich King record (40000)',nc and nc.dps)
 local d=S.BundleDps()
 C.guard(d~=nil and type(d.futureDpsKey)=='table' and d.futureDpsKey.keep=='dps top level',
  tag..': an unknown key of the served DPS payload stays',d and type(d.futureDpsKey))
 local top=rawget(NexusDB,'genUnknownTopLevel')
 C.guard(type(top)=='table' and top.keep=='top',tag..': an unknown root key stays')
 -- Storage version 2 is the receipt version that older builds read; a higher
 -- one makes them treat the receipt as future and refuse account writes.
 local s=Nexus.LegacyDataMigration.Status(NexusDB)
 local m=S.Receipt()
 C.guard(s.state=='complete' and m~=nil and m.version==2,
  tag..': the conversion receipt says complete, at storage version 2, which older builds read (rollback)',
  printable(s.state)..'/'..printable(m and m.version))
end

-- The profile that the defective first start-up leaves behind, built on a real
-- settled profile of this build. Returns its saved text and facts about how it
-- was made. Steps:
-- 1. A profile of this build that owes no conversion (no older map, no
--    classless row) starts, settles and finishes its compaction.
-- 2. After that upgrade a newer, stronger Steady record (35000) arrives through
--    the real receive path (DpsCapture.ReceiveRecord from Steady's own sender)
--    and is served; then the session logs out and is saved.
-- 3. One more session of that saved data starts and logs out, so the saved
--    profile is one that a further start-up leaves unchanged (a field the DPS
--    owner adds lazily on its first read is then already present).
-- 4. Into that saved input go the three things the defective start-up wrote,
--    exactly where it wrote them (LegacyDataMigration Finish, BuildCatalog
--    admission): the complete receipt; the converted maps in the RAW
--    NexusDB.dpsCapture only, as of that start-up (Steady still 30000; no
--    Newcomer, which exists only in the served payload); and, in the served
--    payload, the older map that admission had copied there and nothing
--    converted. Unknown keys ride along in both tables.
function S.AffectedProfile(fx)
 local made={}
 local base=F.Database({version=2})
 fx:Install(base)
 local H=F.Boot(base)
 made.ready=Nexus.StartupStatus().state=='ready'
 made.noConversion=S.Receipt()==nil
 made.compacted=S.Until(H,S.CompactionSettled,2000)~=nil
 local ok,why=fx:Receive('Steady','dummy',{dps=35000,ts=L.STAMP+900})
 made.received,made.receiveWhy=ok==true,why
 S.Advance(H,40)
 local served=S.StoredRow(S.BundleDps(),'dummy','Steady')
 made.servedSteady=served and served.dps or nil
 H.Fire('PLAYER_LOGOUT')
 H=F.Reload()
 made.readyAgain=Nexus.StartupStatus().state=='ready'
 S.Advance(H,60)
 Nexus.DpsCapture.GetDpsBoard('dummy')
 S.Advance(H,20)
 made.compactedAfter=S.CompactionSettled()
 H.Fire('PLAYER_LOGOUT')
 local db=S.Load(F.Serialize(NexusDB))
 made.bundle=type(rawget(db,'authorityBundle'))=='table' and type(db.authorityBundle.dpsCapture)=='table'
 if not made.bundle then return F.Serialize(db),made end
 local legacy=S.LegacyRows()
 local function Converted(row,owner,extra)
  local out=L.Copy(row)
  out.fingerprint=out.fingerprint or S.FP
  out.ownerKey=owner
  out.realm=owner:match('@(.+)$')
  for k,v in pairs(extra or {}) do out[k]=v end
  return out
 end
 local me=Converted(legacy[S.LOCAL],S.LOCAL_OWNER)
 db.legacyDataMigration={schemaVersion=1,version=2,state='complete',reason='startup',sourceSettingsVersion=2,
  workUnits=9,completedAt=1700001020,
  stats={accountRowsCopied=1,characterRowsCopied=1,legacyRowsPromoted=3,personalRowsPromoted=1,legacyClassesInferred=1},
  lastResult={schemaVersion=1,version=2,accountCharacters=1,personalFingerprints=1,buildFingerprints=0,
   dummyCharacters=4,lkCharacters=0,quarantined=0}}
 db.dpsCapture={
  personalBest={[S.FP]={dummy=L.Copy(me)}},
  buildBest={},
  characterBest={dummy={
   ['steady@ebonhold']=L.Copy(fx.rows.dummy['steady@ebonhold']),
   ['legacyone@ebonhold']=Converted(legacy.Legacyone,'legacyone@ebonhold'),
   ['hintless@ebonhold']=Converted(legacy.Hintless,'hintless@ebonhold',
    {class='PRIEST',legacyClassInferred=true,legacyClassSource='migration-author-consensus'}),
   [S.LOCAL_OWNER]=me,
  },lk={}},
  futureDpsKey={keep='dps top level'},
  rawOnly={keep='raw top level'},
 }
 local payload=db.authorityBundle.dpsCapture
 payload.leaderboard={[S.FP]={dummy=S.LegacyRows()}}
 payload.futureDpsKey={keep='dps top level'}
 payload.bundleOnly={keep='bundle top level'}
 return F.Serialize(db),made
end

return S
