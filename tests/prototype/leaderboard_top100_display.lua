-- Leaderboard top-100 display, regression-first. The Leaderboard shows the
-- first 100 rows of the ranked board after every filter. Ranking and the
-- filters see the entire eligible board: a class filter or a search brings in
-- rows beyond the overall top 100, and the combined board keeps only real
-- Dummy + Lich King pairs before the cut.
-- Healthy behaviour (EXPECT, fails at d14fa7eb): every Leaderboard path --
-- ViewProjections.Leaderboard (synchronous), RequestLeaderboard/PumpLeaderboard
-- (resumable), the real window and its no-projection fallback -- returns
-- exactly the first 100 rows of the old full output for that filter, in the
-- same order, with contiguous displayed ranks 1..100. A tie that straddles
-- position 100 is cut by the existing order (score, earlier record, name,
-- identity). Preparation stops at the cut: the projection prepares only the
-- rows up to the 100th match.
-- Unchanged (GUARD): the DPS owner's full board (GetDpsBoard and its cursor),
-- the unit-tooltip rank and score of a character below the cut and of tied
-- characters at the cut, the stored DPS records, and boards of 100 rows or
-- fewer.
-- Real TOC boot, DPS owner, projections and Leaderboard window; synthetic
-- players from leaderboard_fixture_support.lua; no game action.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('leaderboard_top100_display')
local LIMIT=100
local N=360
local CLASSES={'MAGE','PRIEST','DRUID'}
-- Every 4th player has no Lich King record and every 7th after the first 100
-- no Training Dummy record, so the combined board keeps only real pairs.
local players={}
for i=1,N do
 local p={name=string.format('Player%03d',i),class=CLASSES[(i-1)%3+1],dps={},ts={},locked=0}
 local d=500000-i*1000
 if not (i>100 and i%7==0) then p.dps.dummy=d end
 if i%4~=0 then p.dps.lk=d-50000 end
 players[i]=p
end
-- An equal-score cluster on positions 97..104 of each unfiltered board; inside
-- it two pairs share an earlier record time, so time and then name decide.
local function Cluster(has,get,put,tsKey)
 local list={};for i=1,N do if has(players[i]) then list[#list+1]=players[i] end end
 local value=get(list[100])
 for k=97,104 do
  put(list[k],value)
  if tsKey then local t=(k<=98) and L.STAMP+50 or (k<=100) and L.STAMP+40 or nil;if t then list[k].ts[tsKey]=t end end
 end
end
Cluster(function(p) return p.dps.dummy end,function(p) return p.dps.dummy end,function(p,v) p.dps.dummy=v end,'dummy')
Cluster(function(p) return p.dps.lk end,function(p) return p.dps.lk end,function(p,v) p.dps.lk=v end,'lk')
Cluster(function(p) return p.dps.lk and p.dps.dummy end,function(p) return p.dps.dummy end,function(p,v) p.dps.dummy=v end,nil)
local fx=L.New({players=players})
local H=F.Boot(fx:Install(F.Database()))
for _=1,200 do H.Advance(.05,.05) end
local D,P,LB=Nexus.DpsCapture,Nexus.ViewProjections,Nexus.Leaderboard
C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')

local function Id(name,dps) return tostring(name)..'|'..tostring(dps) end
local function RowIds(rows) local t={};for i,r in ipairs(rows or {}) do t[i]=Id(r.player,r.dps) end;return t end
local function Join(t,a,b) local o={};for i=a or 1,math.min(b or #t,#t) do o[#o+1]=t[i] end;return table.concat(o,',') end
-- The fixture's documented product order, filtered as the Leaderboard filters.
local function Expected(category,classFilter,search)
 local out,positions={},{}
 for position,e in ipairs(fx:Expected(category)) do
  local p=e.player
  if (classFilter=='ALL' or p.class==classFilter)
   and (search=='' or p.name:lower():find(search,1,true)) then
   out[#out+1]=Id(p.name,e.dps);positions[#positions+1]=position
  end
 end
 return out,positions
end
local function Slice(t,n) local o={};for i=1,math.min(n,#t) do o[i]=t[i] end;return o end
local function Prepared()
 local w=P.WorkStats()
 return w.classFromRecord+w.classFromBuild+w.classFromCurrentPlayer+w.classFromOwner+w.classUnavailable
end
local function Sync(category,filters) P.Reset();local rows=P.Leaderboard(category,filters);return rows,Prepared() end
local function Async(category,filters)
 P.Reset()
 local rows=P.RequestLeaderboard(category,filters)
 for _=1,100000 do
  if rows then break end
  P.PumpLeaderboard();rows=P.RequestLeaderboard(category,filters)
 end
 return rows,Prepared(),P.WorkStats()
end
local function Serialized() return F.Serialize(NexusDB.authorityBundle.dpsCapture) end
local storedBefore=Serialized()

-- Fixture facts the cases depend on.
do
 local dummy,lk,combined=fx:Expected('dummy'),fx:Expected('lk'),fx:Expected('combined')
 C.setup(#dummy>LIMIT and #lk>LIMIT and #combined>LIMIT,'fixture: every board is longer than 100 rows',#dummy..'/'..#lk..'/'..#combined)
 C.setup(dummy[100].dps==dummy[101].dps and dummy[97].dps==dummy[104].dps,'fixture: an equal-score cluster straddles Training Dummy position 100')
 C.setup(combined[100].dps==combined[101].dps,'fixture: an equal-score cluster straddles combined position 100')
 local _,positions=Expected('dummy','PRIEST','')
 C.setup(#positions>LIMIT and positions[LIMIT]>2*LIMIT,'fixture: the Priest filter has more than 100 rows, and its 100th lies far past overall position 100',#positions..' / '..tostring(positions[LIMIT]))
 local pairs=0;for _,p in ipairs(players) do if p.dps.lk and p.dps.dummy then pairs=pairs+1 end end
 C.setup(#combined==pairs and pairs<N,'fixture: the combined board keeps only players with both records',#combined..'/'..pairs)
end

local CASES={
 {'dummy','ALL',''},{'dummy','PRIEST',''},{'dummy','MAGE',''},{'dummy','ALL','player'},{'dummy','PRIEST','player2'},
 {'lk','ALL',''},{'lk','DRUID',''},
 {'combined','ALL',''},{'combined','PRIEST',''},{'combined','ALL','player1'},
}
C.scenario('S1 projections: the first 100 rows of the full filtered order',function()
 for _,c in ipairs(CASES) do
  local category,cf,search=c[1],c[2],c[3]
  local tag=category..'/'..cf..'/'..(search~='' and search or '-')
  local full,positions=Expected(category,cf,search)
  local want=Slice(full,LIMIT)
  local filters={classFilter=cf,search=search}
  local srows,sprep=Sync(category,filters)
  local arows,aprep=Async(category,filters)
  local s,a=RowIds(srows),RowIds(arows)
  C.expect(Join(s)==Join(want),tag..': the synchronous projection is the first '..#want..' of '..#full..' rows',#s..' rows; 100th '..printable(s[100]))
  C.expect(Join(a)==Join(want),tag..': the resumable projection is the same rows in the same order',#a..' rows')
  -- Rows are prepared in rank order up to the 100th match, never after it.
  local through=#full>LIMIT and positions[LIMIT] or #fx:Expected(category)
  C.expect(sprep==through,tag..': the synchronous projection prepares rows only up to the cut',sprep..' / '..through)
  C.expect(aprep==through,tag..': the resumable projection prepares rows only up to the cut',aprep..' / '..through)
  print('OBSERVED',tag,'rows '..#s..'/'..#full,'prepared '..sprep..'/'..aprep..' of '..#fx:Expected(category))
 end
end)

C.scenario('S2 the cut inside a tie keeps the existing order',function()
 local full=Expected('dummy','ALL','')
 local rows=RowIds((Sync('dummy',{classFilter='ALL'})))
 C.expect(rows[100]==full[100] and rows[101]==nil,'S2: position 100 is the last displayed row, taken from inside the tie by time and name',printable(rows[100]))
 C.guard(Join(full,97,104):find(rows[100],1,true)~=nil,'S2: the 100th row belongs to the equal-score cluster',Join(full,97,104))
 local combined=Expected('combined','ALL','')
 local crows=RowIds((Sync('combined',{classFilter='ALL'})))
 C.expect(crows[100]==combined[100] and crows[101]==nil,'S2: the combined cut inside its tie follows score, then name',printable(crows[100]))
end)

C.scenario('S3 the real window shows the first 100 with contiguous ranks',function()
 L.Open(H,'dummy')
 local rendered,total=L.RenderedRows(H)
 local want=Slice((Expected('dummy','ALL','')),LIMIT)
 local ids,contiguous={},true
 for i=1,total do local r=rendered[i];ids[i]=r and Id(r.data.player,r.data.dps) or '?';if not (r and r.rank==i) then contiguous=false end end
 C.expect(total==LIMIT and Join(ids)==Join(want),'S3: the window lists exactly the first 100 rows',total)
 C.guard(contiguous,'S3: the displayed ranks run 1..'..total..' without a gap')
 local since=tonumber(LB.VirtualStats().dataRefreshes) or 0
 LB.SetClassFilter('PRIEST')
 C.setup(V.LeaderboardSettled(H,since,4000,20)~=nil,'S3: fixture: the Priest filter publishes')
 rendered,total=L.RenderedRows(H)
 local priest,positions=Expected('dummy','PRIEST','')
 ids={};for i=1,total do local r=rendered[i];ids[i]=r and Id(r.data.player,r.data.dps) or '?' end
 C.expect(total==LIMIT and Join(ids)==Join(Slice(priest,LIMIT)),
  'S3: the Priest filter lists its first 100 Priests, the last from overall position '..positions[LIMIT],total)
 LB.SetClassFilter('ALL')
 LB.Hide()
end)

C.scenario('S4 the window fallback without ViewProjections',function()
 local saved=Nexus.ViewProjections
 Nexus.ViewProjections=nil
 local ok,err=pcall(function()
  LB.Show('combined')
  for _=1,40 do H.Advance(.05,.05) end
  local rendered,total=L.RenderedRows(H)
  local want=Slice((Expected('combined','ALL','')),LIMIT)
  local ids={};for i=1,total do local r=rendered[i];ids[i]=r and Id(r.data.player,r.data.dps) or '?' end
  C.expect(total==LIMIT and Join(ids)==Join(want),'S4: the fallback also lists the first 100 combined rows',total)
 end)
 Nexus.ViewProjections=saved
 LB.Hide()
 assert(ok,err)
end)

C.scenario('S5 the full board and tooltip ranks are not cut',function()
 for _,category in ipairs({'dummy','lk'}) do
  local full=fx:Expected(category)
  C.guard(#D.GetDpsBoard(category)==#full,'S5: GetDpsBoard keeps all '..#full..' '..category..' rows',#D.GetDpsBoard(category))
  local cursor=D.BeginDpsBoardCursor(category)
  repeat local done=D.DpsBoardCursorNext(cursor) until done
  C.guard(#(D.DpsBoardCursorResult(cursor) or {})==#full,'S5: the board cursor keeps all '..category..' rows')
 end
 local dummy=fx:Expected('dummy')
 local function FullRank(position) local higher=0;for _,e in ipairs(dummy) do if e.dps>dummy[position].dps then higher=higher+1 end end;return higher+1 end
 for _,position in ipairs({97,100,101,104,150,#dummy}) do
  local e=dummy[position]
  local info=D.GetPlayerInfo(e.player.name) or {}
  C.guard(info.rank==FullRank(position) and info.dps==e.dps and info.category=='dummy',
   'S5: '..e.player.name..' (board position '..position..') keeps its full-board rank and score',printable(info.rank)..'/'..printable(info.dps))
 end
 C.guard(Serialized()==storedBefore,'S5: reading every path changed no stored DPS record')
end)

C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(first 100 after filters and ranking on every path; full board, tooltip ranks and stored records unchanged)')
