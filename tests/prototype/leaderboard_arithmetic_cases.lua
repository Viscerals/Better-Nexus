-- Leaderboard arithmetic and selection: the seven L-gap cases, with small fixtures whose expected
-- numbers are worked by hand below and are NOT computed by the code under test.
--
-- Contract (repository and UI text, not a ranking invented here):
--   * a record counts only if its category's minimum session length is met (Training Dummy 30 s,
--     Lich King 20 s; DpsCapture.IsDurationEligible: finite and >= the minimum) and its score is a
--     positive finite number; the board shows the integer floor of the score;
--   * a category tab ranks eligible records by score, highest first, then earlier record time, then
--     player name, then public identity;
--   * "Both records" requires one character's own Training Dummy AND Lich King record on the same
--     ordinary Echo evidence and the same exact locked combat identity, owner proved; it ranks by the
--     HIGHEST single eligible result (UI: "ranked by strongest single DPS ... the displayed average
--     does not set the rank"); the average, (dummy + lich king) / 2, is display-only and is shown
--     with the fractional part dropped (ui/Leaderboard.lua DpsText).
-- Real TOC boot, real saved-data admission, real DpsCapture board, real CandidateEvidence pairing and
-- the real Leaderboard window. Synthetic players only.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0
local function check(ok,msg) checks=checks+1; assert(ok,msg) end
local S=L.STAMP

local function Boot(spec,mutate)
 local fx=L.New(spec)
 local db=fx:Install(F.Database({version=2}))
 if mutate then mutate(db,fx) end
 local H=F.Boot(db,function(h) h.playerLevel=60 end)
 for _=1,400 do H.Advance(.05,.05) end
 return fx,H
end
local function Plain(text) return (tostring(text):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
local function Short(name) return (tostring(name):gsub('%-ebonhold$','')) end
-- 'Name:score' lists, in board order.
local function BoardList(category)
 local out={}
 for _,r in ipairs(Nexus.DpsCapture.GetDpsBoard(category)) do out[#out+1]=Short(r.player)..':'..tostring(r.dps) end
 return table.concat(out,' ')
end
local function Settle(H,category)
 local LB=Nexus.Leaderboard
 for _=1,2000 do
  H.Advance(.05,.05)
  local v,d=LB.VirtualStats(),LB.DiagnosticSnapshot()
  if v.dataReady and d.projectionCurrent and not d.projectionPending and v.category==category
   and d.blockedReason=='none' then return end
 end
 error('Leaderboard did not publish '..category)
end
local function Rendered(H,category)
 L.Open(H,category)
 local rows=L.RenderedRows(H)
 local out={}
 for i,r in ipairs(rows) do
  out[i]={name=Short(r.player),dps=Plain(r.dps),extra=Plain(r.extra),data=r.data}
 end
 return out
end
local function Ranks(rows)
 local out={}
 for _,r in ipairs(rows) do out[#out+1]=r.name..':'..r.dps:gsub(' DPS','') end
 return table.concat(out,' ')
end
local function Copy(v,seen)
 if type(v)~='table' then return v end
 seen=seen or {}
 if seen[v] then return seen[v] end
 local out={};seen[v]=out
 for k,x in pairs(v) do out[Copy(k,seen)]=Copy(x,seen) end
 return out
end
local function Pairs(d,k) return Nexus.CandidateEvidence.RealDpsPairs(d,k) end

-- ================================================================== boot 1
-- Hand-worked fixture. Defaults: Dummy duration 180 s, Lich King 120 s (both eligible).
--   name      class    Dummy (s)     Lich King (s)
--   Alpha     MAGE     100           100
--   Bravo     PRIEST   150           1
--   Charlie   MAGE     80            120
--   Delta     ROGUE    700           -          (Dummy only)
--   Echo      DRUID    -             600        (Lich King only)
--   P1 below  HUNTER   910 (29.999)  920 (19.999)   both just under their minimum
--   P2 at     WARRIOR  810 (30)      820 (20)       exactly at the minimum
--   P3 above  MAGE     510 (30.001)  520 (20.001)   just above
--   P4 cross  SHAMAN   410 (25)      420 (25)       25 s: below Dummy's 30, above Lich King's 20
--   P5 bad    PALADIN  310 (NaN)     320 (inf)      non-finite durations
local fx1,H=Boot({players={
 {name='Alpha',class='MAGE',dps={dummy=100,lk=100}},
 {name='Bravo',class='PRIEST',dps={dummy=150,lk=1}},
 {name='Charlie',class='MAGE',dps={dummy=80,lk=120}},
 {name='Delta',class='ROGUE',dps={dummy=700}},
 {name='Echo',class='DRUID',dps={lk=600}},
 {name='P1below',class='HUNTER',dps={dummy=910,lk=920},duration={dummy=29.999,lk=19.999}},
 {name='P2at',class='WARRIOR',dps={dummy=810,lk=820},duration={dummy=30,lk=20}},
 {name='P3above',class='MAGE',dps={dummy=510,lk=520},duration={dummy=30.001,lk=20.001}},
 {name='P4cross',class='SHAMAN',dps={dummy=410,lk=420},duration={dummy=25,lk=25}},
 {name='P5bad',class='PALADIN',dps={dummy=310,lk=320},duration={dummy=0/0,lk=1/0}},
}})
local D=Nexus.DpsCapture

-- ---------------------------------------------------------------- 1. category eligibility
check(D.MinimumDuration('dummy')==30 and D.MinimumDuration('lk')==20,'declared minimums: Training Dummy 30 s, Lich King 20 s')
check(D.MinimumDuration('other')==nil and D.IsDurationEligible('other',1000)==false,'an unknown category has no minimum and nothing is eligible in it')
for _,case in ipairs({
 {'dummy',29.999,false},{'dummy',30,true},{'dummy',30.001,true},
 {'lk',19.999,false},{'lk',20,true},{'lk',20.001,true},
 {'dummy',25,false},{'lk',25,true},
 {'dummy',0/0,false},{'lk',0/0,false},{'dummy',1/0,false},{'lk',1/0,false},{'dummy',-1/0,false},
 {'dummy',nil,false},{'lk','abc',false},{'dummy',0,false},{'lk',-20,false},
})do
 check(D.IsDurationEligible(case[1],case[2])==case[3],'IsDurationEligible('..case[1]..', '..tostring(case[2])..') is '..tostring(case[3]))
end
-- Board contents by hand: Dummy needs >= 30 s -> P2 810, Delta 700, P3 510, Bravo 150, Alpha 100, Charlie 80;
-- P1 (29.999), P4 (25 s) and P5 (NaN) are out. Lich King needs >= 20 s -> P2 820, Echo 600, P3 520, P4 420,
-- Charlie 120, Alpha 100, Bravo 1; P1 (19.999) and P5 (inf) are out.
check(BoardList('dummy')=='P2at:810 Delta:700 P3above:510 Bravo:150 Alpha:100 Charlie:80','Dummy board: '..BoardList('dummy'))
check(BoardList('lk')=='P2at:820 Echo:600 P3above:520 P4cross:420 Charlie:120 Alpha:100 Bravo:1','Lich King board: '..BoardList('lk'))
check(#D.GetDpsBoard('other')==0,'an unknown category lists nothing')

-- ---------------------------------------------------------------- 2. highest single versus average
-- Both records (hand): P2 820/810 -> best 820, avg 815; P3 520/510 -> best 520, avg 515;
-- Bravo 150/1 -> best 150, avg 75.5; Charlie 120/80 -> best 120, avg 100; Alpha 100/100 -> best 100, avg 100.
-- Order by best: P2 820, P3 520, Bravo 150, Charlie 120, Alpha 100. Bravo's average (75.5) is the LOWEST of
-- the five and it still ranks above Charlie and Alpha (average 100 each).
-- The synchronous projection (the one-shot reader, before the window has cached anything) ranks the same way
-- as the window's incremental one.
local direct=Nexus.ViewProjections.Leaderboard('combined',{search='',classFilter='ALL'})
local directList={}
for _,r in ipairs(direct or {}) do directList[#directList+1]=Short(r.player)..':'..r.dps..'/'..r.average end
check(table.concat(directList,' ')=='P2at:820/815 P3above:520/515 Bravo:150/75.5 Charlie:120/100 Alpha:100/100','synchronous Both records: '..table.concat(directList,' '))
local combined=Rendered(H,'combined')
check(Ranks(combined)=='P2at:820 P3above:520 Bravo:150 Charlie:120 Alpha:100','Both records order: '..Ranks(combined))
local expectExtra={
 P2at='Avg 815  •  Dummy 810  •  LK 820',P3above='Avg 515  •  Dummy 510  •  LK 520',
 Bravo='Avg 75  •  Dummy 150  •  LK 1',Charlie='Avg 100  •  Dummy 80  •  LK 120',Alpha='Avg 100  •  Dummy 100  •  LK 100',
}
local expectAverage={P2at=815,P3above=515,Bravo=75.5,Charlie=100,Alpha=100}
for _,r in ipairs(combined) do
 check(r.extra==expectExtra[r.name],r.name..' row text: '..r.extra)
 check(r.data.average==expectAverage[r.name],r.name..' average is unrounded (the display drops the fraction): '..tostring(r.data.average))
 check(r.data.dps==r.data.bestDps and r.data.dps==math.max(r.data.dummyDps,r.data.lkDps),r.name..' ranking score is the highest single result')
end

-- ---------------------------------------------------------------- 5. missing counterpart
-- Delta (Dummy only) and Echo (Lich King only) stay in their own tab and are absent from Both records:
-- no pair and no zero-score record is fabricated for them.
local inCombined={}
for _,r in ipairs(combined) do inCombined[r.name]=true end
check(not inCombined.Delta and not inCombined.Echo,'single-category characters have no combined row')
check(not inCombined.P1below and not inCombined.P4cross and not inCombined.P5bad,'characters without two eligible records have no combined row')
for _,r in ipairs(combined) do check(r.data.dummyDps>0 and r.data.lkDps>0,r.name..': both records are real scores, not a placeholder zero') end
local dummyRows,lkRows=D.GetDpsBoard('dummy'),D.GetDpsBoard('lk')
local function RowOf(rows,name) for _,r in ipairs(rows) do if r.player==name then return r end end end
check(#Pairs({RowOf(dummyRows,'Delta')},lkRows)==0,'Delta (no Lich King record) has no pair even against every Lich King row')
check(#Pairs(dummyRows,{RowOf(lkRows,'Echo')})==0,'Echo (no Dummy record) has no pair even against every Dummy row')

-- ---------------------------------------------------------------- 3. several records per identity (pair layer)
-- One character can have several eligible records per category in the pair inputs (the board keeps one per
-- character, the retention and qualification readers pass more). Alpha's identity, hand arithmetic:
local Ad,Ak=RowOf(dummyRows,'Alpha'),RowOf(lkRows,'Alpha')
local function Variant(row,dps,ts,duration)
 local out=Copy(row);out.dps=dps;out.ts=ts or row.ts;out.duration=duration or row.duration;return out
end
local D1,D2=Variant(Ad,100,Ad.ts),Variant(Ad,120,Ad.ts+1)
local K1,K2=Variant(Ak,90,Ak.ts),Variant(Ak,110,Ak.ts+1)
local result=Pairs({D1,D2},{K1,K2})
check(#result==1,'two records per category of one identity form ONE pair: '..#result)
check(result[1].dummyDps==120 and result[1].lkDps==110,'the category maxima form the pair: '..result[1].dummyDps..'/'..result[1].lkDps)
check(result[1].bestDps==120 and result[1].average==115,'best 120, average (120+110)/2 = 115: '..result[1].bestDps..'/'..result[1].average)
result=Pairs({D2,D1},{K2,K1}) -- reversed input order
check(#result==1 and result[1].dummyDps==120 and result[1].lkDps==110,'input order does not change the pair')
result=Pairs({D1},{K1}) -- the winning records removed: the replacements form the pair
check(#result==1 and result[1].dummyDps==100 and result[1].lkDps==90,'with the winners removed the replacements pair up: '..result[1].dummyDps..'/'..result[1].lkDps)
check(result[1].bestDps==100 and result[1].average==95,'best 100, average (100+90)/2 = 95')
-- Equal-authority duplicates (the same record held twice, differing only in an excluded clock) count once.
local D3=Variant(Ad,100,Ad.ts+777)
result=Pairs({D1,D3},{K1})
check(#result==1 and result[1].dummyDps==100,'a duplicate record is not double-counted: '..result[1].dummyDps)
check(result[1].average==95 and #result[1].dummySources==2,'the average stays 95 and both retention sources are kept: '..#result[1].dummySources)
-- Equal score, different recorded duration (an explicit tie key): the selected row does not depend on order.
local Da,Db=Variant(Ad,100,Ad.ts,180),Variant(Ad,100,Ad.ts,190)
local first=Pairs({Da,Db},{K1})[1].dummy.duration
local second=Pairs({Db,Da},{K1})[1].dummy.duration
check(first==second and (first==180 or first==190),'equal-score records of unequal tie key: one stable selection regardless of order: '..tostring(first)..'/'..tostring(second))

-- ---------------------------------------------------------------- 6. owner and combat separation (pair layer)
local function Rebind(row,owner,realm)
 local out=Copy(row);out.ownerKey=owner;out.realm=realm;return out
end
check(#Pairs({Ad},{Ak})==1,'positive control: the same proved owner with matching ordinary and locked evidence pairs')
local otherOwner=Rebind(Ak,'alpha@otherrealm','otherrealm') -- same display name, same ordinary fingerprint, another proved owner
check(otherOwner.player==Ak.player and otherOwner.fingerprint==Ak.fingerprint,'fixture: same name and ordinary evidence')
check(#Pairs({Ad},{otherOwner})==0,'a different proved owner never cross-pairs')
local unproved=Copy(Ak);unproved.ownerVerified=false
check(#Pairs({Ad},{unproved})==0,'a record whose owner is not proved cannot pair, and does not become proof')
check(#Pairs({unproved},{Ak})==0 and #Pairs({unproved},{unproved})==0,'nor can it pair as the Dummy side or with itself')
local otherLocked=Copy(Ak);otherLocked.lockedFingerprint=nil
otherLocked.lockedEchoes[1].spellId=otherLocked.lockedEchoes[#otherLocked.lockedEchoes].spellId+1
check(#Pairs({Ad},{otherLocked})==0,'a different locked spell under the same owner and ordinary evidence does not pair')
local moreCopies=Copy(Ak);moreCopies.lockedFingerprint=nil
moreCopies.lockedEchoes[1].count=(moreCopies.lockedEchoes[1].count or 1)+1
check(#Pairs({Ad},{moreCopies})==0,'a different locked copy total does not pair')
local otherOrdinary=Copy(Ak)
table.remove(otherOrdinary.echoes)
otherOrdinary.fingerprint=L.Fingerprint(otherOrdinary.echoes)
check(#Pairs({Ad},{otherOrdinary})==0,'different ordinary evidence under the same owner does not pair')

-- ---------------------------------------------------------------- 7. filter, detail and display
-- Class filter MAGE (Alpha, Charlie, P3 are MAGE): Both records -> P3 520, Charlie 120, Alpha 100, ranks 1-3.
L.Open(H,'combined')
Nexus.Leaderboard.SetClassFilter('MAGE');Settle(H,'combined')
local rows=L.RenderedRows(H)
local mage={}
for i,r in ipairs(rows) do mage[#mage+1]=Short(r.player)..':'..Plain(r.dps):gsub(' DPS','') end
check(table.concat(mage,' ')=='P3above:520 Charlie:120 Alpha:100','class filter keeps the order and renumbers: '..table.concat(mage,' '))
check(#rows==3,'three rows pass the MAGE filter')
local detail=L.Select(H,1)
check(Plain(detail.record)=='Strongest 520 DPS\nAverage 515  •  Dummy 510  •  LK 520','detail of the selected row: '..Plain(detail.record))
check(detail.row.average==515 and detail.row.dps==520,'and it is the same row the list shows')
detail=L.Select(H,3)
check(Plain(detail.record)=='Strongest 100 DPS\nAverage 100  •  Dummy 100  •  LK 100','detail of the third row: '..Plain(detail.record))
-- Class filter PRIEST: Bravo only; the displayed average drops the fraction of 75.5, the row keeps it.
Nexus.Leaderboard.SetClassFilter('PRIEST');Settle(H,'combined')
rows=L.RenderedRows(H)
check(#rows==1 and Short(rows[1].player)=='Bravo','PRIEST leaves Bravo')
detail=L.Select(H,1)
check(Plain(detail.record)=='Strongest 150 DPS\nAverage 75  •  Dummy 150  •  LK 1','Bravo detail: '..Plain(detail.record))
check(detail.row.average==75.5,'the average behind the display is 75.5, which is not a ranking input')
-- Category tabs with the same filter agree with their own boards.
Nexus.Leaderboard.SetClassFilter('MAGE')
rows=Rendered(H,'dummy')
check(Ranks(rows)=='P3above:510 Alpha:100 Charlie:80','Dummy tab, MAGE: '..Ranks(rows))
detail=L.Select(H,1)
check(Plain(detail.record):find('510 DPS',1,true) and Plain(detail.record):find('Training Dummy',1,true),'Dummy detail: '..Plain(detail.record))
rows=Rendered(H,'lk')
check(Ranks(rows)=='P3above:520 Charlie:120 Alpha:100','Lich King tab, MAGE: '..Ranks(rows))
Nexus.Leaderboard.SetClassFilter('ALL');Settle(H,'lk')

-- ================================================================== boot 2: ties, a counterpart added, owner separation
-- Hand-worked: all three of Alpha, Bravo, Charlie have best 100 and different averages
--   Alpha 100/40 -> avg 70    Bravo 60/100 -> avg 80    Charlie 100/100 -> avg 100
-- Delta now has BOTH records (the matching counterpart added): 700/200 -> best 700, avg 450.
-- Dummy timestamps: Alpha S+300, Charlie S+200 (equal score 100 -> earlier record first: Charlie, Alpha).
-- Lich King timestamps: Bravo S+150, Charlie S+150 (equal score and time -> name: Bravo, Charlie).
-- A second proved owner 'alpha@otherrealm' with the SAME display name and ordinary evidence holds a Lich King
-- record of 5000 and no Dummy record: it must never pair with Alpha of ebonhold.
local fx2
fx2,H=Boot({players={
 {name='Alpha',class='MAGE',dps={dummy=100,lk=40},ts={dummy=S+300,lk=S+140}},
 {name='Bravo',class='PRIEST',dps={dummy=60,lk=100},ts={dummy=S+120,lk=S+150}},
 {name='Charlie',class='MAGE',dps={dummy=100,lk=100},ts={dummy=S+200,lk=S+150}},
 {name='Delta',class='ROGUE',dps={dummy=700,lk=200}},
}},function(db,fx)
 local alpha=fx.players[1]
 local row=Copy(fx.rows.lk[alpha.owner])
 row.ownerKey='alpha@otherrealm';row.realm='otherrealm';row.dps=5000;row.ts=S+400
 db.dpsCapture.characterBest.lk['alpha@otherrealm']=row
end)
-- 4. ties
check(BoardList('dummy')=='Delta:700 Charlie:100 Alpha:100 Bravo:60','Dummy board, equal 100: earlier record first: '..BoardList('dummy'))
local lkBoard=BoardList('lk')
check(lkBoard=='Alpha:5000 Delta:200 Bravo:100 Charlie:100 Alpha:40','Lich King board, equal 100 and equal time: by name: '..lkBoard)
combined=Rendered(H,'combined')
check(Ranks(combined)=='Delta:700 Alpha:100 Bravo:100 Charlie:100','Both records: three-way tie of best 100 by player name, average not a key: '..Ranks(combined))
expectExtra={Delta='Avg 450  •  Dummy 700  •  LK 200',Alpha='Avg 70  •  Dummy 100  •  LK 40',Bravo='Avg 80  •  Dummy 60  •  LK 100',Charlie='Avg 100  •  Dummy 100  •  LK 100'}
for _,r in ipairs(combined) do check(r.extra==expectExtra[r.name],r.name..' row text: '..r.extra) end
-- 5. the added counterpart produced one real pair for Delta
local deltaRows=0
for _,r in ipairs(combined) do if r.name=='Delta' then deltaRows=deltaRows+1 end end
check(deltaRows==1,'adding the matching counterpart gives Delta exactly one pair row')
-- 6. the other owner's Lich King record is listed on its own board and pairs with nobody
local alphaRows=0
for _,r in ipairs(combined) do if r.name=='Alpha' then alphaRows=alphaRows+1;check(r.data.lkDps==40,'Alpha of ebonhold keeps his own Lich King score 40, not the other owner\'s 5000') end end
check(alphaRows==1,'only one Alpha pair exists')
-- 4. pair layer ties, reversed input
local board1,board2=D.GetDpsBoard('dummy'),D.GetDpsBoard('lk')
local function Order(pairsList)
 local out={}
 for _,p in ipairs(pairsList) do out[#out+1]=p.identity:match('^([^|]+)') end
 return table.concat(out,' ')
end
local function Reverse(list) local out={} for i=#list,1,-1 do out[#out+1]=list[i] end return out end
local ranked=Pairs(board1,board2)
check(Order(ranked)=='delta@ebonhold alpha@ebonhold bravo@ebonhold charlie@ebonhold','pair order: best score, then identity: '..Order(ranked))
check(Order(Pairs(Reverse(board1),Reverse(board2)))==Order(ranked),'reversing the input rows keeps the pair order')

-- ================================================================== boot 3: score admission and flooring
-- Hand-worked Dummy scores: Frac 150.9 -> 150; Frac2 1.9 -> 1; One 1 -> 1 (equal score 1: earlier record first,
-- One S+110 before Frac2 S+120); Zero 0, Half 0.5 (floor 0), Neg -5 are not records; Inf, Nan are not valid scores.
-- Both-records control: 'Both' has Dummy 150.9 and Lich King 1.9 -> floors 150 and 1 -> best 150, average 75.5.
fx2,H=Boot({players={
 {name='Frac',class='MAGE',dps={dummy=150.9}},
 {name='Frac2',class='MAGE',dps={dummy=1.9},ts={dummy=S+120}},
 {name='One',class='MAGE',dps={dummy=1},ts={dummy=S+110}},
 {name='Zero',class='MAGE',dps={dummy=0}},
 {name='Half',class='MAGE',dps={dummy=0.5}},
 {name='Neg',class='MAGE',dps={dummy=-5}},
 {name='Inf',class='MAGE',dps={dummy=1/0,lk=300}},
 {name='Nan',class='MAGE',dps={dummy=0/0,lk=310}},
 {name='Both',class='MAGE',dps={dummy=150.9,lk=1.9}},
}})
D=Nexus.DpsCapture
local dummy=BoardList('dummy')
check(dummy:find('Frac:150',1,true) and dummy:find('Both:150',1,true),'fractional scores are floored on the board: '..dummy)
check(dummy:find('One:1 Frac2:1',1,true),'equal floored scores 1 and 1: earlier record first: '..dummy)
check(not dummy:find('Zero',1,true) and not dummy:find('Neg',1,true),'zero and negative scores are not records: '..dummy)
check(not dummy:find('Half',1,true),'a score below 1 (it would be listed as 0) is not a record: '..dummy)
check(not dummy:find('Inf',1,true) and not dummy:find('Nan',1,true),'non-finite scores are not records (the pair arithmetic already refuses them): '..dummy)
combined=Rendered(H,'combined')
check(Ranks(combined)=='Both:150','Both records: only Both, 150 (floor of 150.9): '..Ranks(combined))
check(combined[1].extra=='Avg 75  •  Dummy 150  •  LK 1' and combined[1].data.average==75.5,'floored inputs: average (150+1)/2 = 75.5, shown as 75: '..combined[1].extra)

print('PASS leaderboard_arithmetic_cases: '..checks..' checks (eligibility; highest single vs average; several records; ties; counterpart; owner/combat; filter/detail; score admission)')
