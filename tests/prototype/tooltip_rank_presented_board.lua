-- F-S2-3 (P3), regression-first: the unit-tooltip rank agrees with the
-- Leaderboard the player sees. DpsCapture.GetPlayerInfo (the tooltip's rank
-- API, read by ui/Nameplate.lua) ranks a character by counting every stored
-- row of the category with a higher score, while the presented board keeps
-- one row per public identity and hides an unverified row whose name has a
-- verified row. An upgraded profile keeps a realm-less legacy row under the
-- plain character key beside that character's verified realm row, so the
-- hidden legacy row still pushes everyone below it down a place: Bob is
-- ranked below his own old record.
-- Healthy behaviour (EXPECT, fails at the baseline): with a hidden realm-less
-- legacy row in the bucket, GetPlayerInfo ranks equal the presented board
-- (GetDpsBoard, and the real Leaderboard window), and the real annotation
-- body prints those ranks on a fake unit tooltip.
-- Unchanged (GUARD, holds at the baseline): the lookup itself (the verified
-- realm row is a character's record, its score and build); reading ranks
-- deletes or changes no stored row; a realm-less legacy row without a
-- verified namesake stays visible and ranked (identity and visibility); tied
-- scores keep sharing one rank, one above the presented entries with a
-- higher score, while the board orders them by the earlier record (tie
-- semantics); an unknown player has no rank; no game action.
-- Real TOC boot, DPS owner, Leaderboard window and annotation body; saved data
-- from leaderboard_fixture_support.lua. Like the frozen repro, the hidden
-- legacy row is written into the served bucket as an artificial saved row
-- (no production function is replaced), and the public revision bus then
-- announces the change. The unit tooltip is a fake boundary.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('tooltip_rank_presented_board')
local fx=L.New({players={
 {name='Bob',class='MAGE',dps={dummy=40000},locked=0},
 {name='Alice',class='MAGE',dps={dummy=30000},locked=0},
 -- Dana starts with a Lich King record only; an equal Training Dummy record
 -- arrives later through the real receive path (scenario R3).
 {name='Dana',class='PRIEST',dps={lk=20000},locked=0},
}})
local H=F.Boot(fx:Install(F.Database()))
for _=1,200 do H.Advance(.05,.05) end
local D,LB=Nexus.DpsCapture,Nexus.Leaderboard

local function Bucket() return NexusDB.authorityBundle.dpsCapture.characterBest.dummy end

-- An artificial realm-less legacy row derived from a stored verified row.
local function Legacy(from,player,dps)
 local row=H.Clone(from)
 row.ownerKey,row.ownerVerified,row.realm,row.protocolVersion=nil,nil,nil,nil
 row.player,row.dps,row.duration=player,dps,40
 return row
end

local function Refreshes() return tonumber(LB.VirtualStats().dataRefreshes) or 0 end

-- Announce an artificial saved-row change through the public revision bus
-- and let the real Leaderboard window publish it.
local function Announce(reason)
 local since=Refreshes()
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source='artificial fixture: '..reason})
 return V.LeaderboardSettled(H,since,2000,20)
end

-- The presented board: GetDpsBoard and the rendered window rows.
local function Board()
 local out={}
 for i,e in ipairs(D.GetDpsBoard('dummy')) do
  out[i]={player=e.player,dps=e.dps,verified=e.ownerVerified==true,ts=e.ts}
 end
 return out
end
local function Names(list)
 local out={}
 for i,e in ipairs(list) do out[i]=V.Plain(e.player) end
 return table.concat(out,',')
end
local function WindowNames()
 local rows=L.RenderedRows(H)
 return Names(rows)
end

-- The rank the presented board gives `name`: one more than the presented
-- entries with a strictly higher score, so tied entries share a rank.
local function BoardRank(board,name)
 local own
 for _,e in ipairs(board) do
  if e.player==name and (own==nil or e.verified) then own=e end
 end
 if not own then return nil end
 local higher=0
 for _,e in ipairs(board) do if e.dps>own.dps then higher=higher+1 end end
 return higher+1
end

local tip=V.Tooltip('ArtificialRankTooltip')
local function TooltipRank(name,n)
 tip:SetUnitLines(name,{name,'Level 80'})
 local added=V.Annotate(tip)
 return V.ShowsRank(added,n),V.RankLine(added)
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
C.setup(type(Bucket()['bob@ebonhold'])=='table' and type(Bucket()['alice@ebonhold'])=='table',
 'fixture: the verified Training Dummy rows of Bob and Alice are served')

-- R1. A hidden realm-less legacy Bob row with a higher score.
C.scenario('R1 a hidden realm-less legacy row',function()
 Bucket().bob=Legacy(Bucket()['bob@ebonhold'],'Bob',50000)
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source='artificial fixture: legacy Bob row'})
 L.Open(H,'dummy')
 local board=Board()
 C.setup(Names(board)=='Bob,Alice' and board[1].dps==40000 and board[1].verified,
  'R1: fixture: the presented board shows the verified Bob 40000, then Alice; the older realm-less Bob row is shadowed',Names(board))
 C.setup(WindowNames()=='Bob,Alice','R1: fixture: the Leaderboard window presents the same rows',WindowNames())
 local bob,alice=D.GetPlayerInfo('Bob'),D.GetPlayerInfo('Alice')
 C.setup(type(bob)=='table' and type(alice)=='table','R1: fixture: both players have tooltip info')
 bob,alice=bob or {},alice or {}
 print('OBSERVED','R1 board Bob=1 Alice=2','tooltip Bob='..printable(bob.rank),'Alice='..printable(alice.rank))
 C.expect(bob.rank==BoardRank(board,'Bob') and bob.rank==1,'R1: Bob ranks 1st, as the board presents him',bob.rank)
 C.expect(alice.rank==BoardRank(board,'Alice') and alice.rank==2,'R1: Alice ranks 2nd, as the board presents her',alice.rank)
 local shown,line=TooltipRank('Bob',1)
 C.expect(shown,'R1: the unit tooltip says "1st on leaderboard" for Bob',line)
 shown,line=TooltipRank('Alice',2)
 C.expect(shown,'R1: and "2nd on leaderboard" for Alice',line)
 local verified=Bucket()['bob@ebonhold'] or {}
 C.guard(bob.dps==40000 and bob.category=='dummy' and bob.buildId~=nil and bob.buildId==verified.buildId,
  "R1: the lookup still returns Bob's verified record, score and build",printable(bob.dps)..'/'..printable(bob.buildId))
 C.guard(alice.dps==30000 and alice.category=='dummy','R1: and Alice\'s',alice.dps)
 local legacy=Bucket().bob
 C.guard(type(legacy)=='table' and legacy.dps==50000 and legacy.ownerKey==nil,
  'R1: reading ranks deletes or changes no stored row')
end)

-- R2. Without the hidden row: a realm-less legacy row whose name has no
-- verified row stays on the board and is ranked where it is shown.
C.scenario('R2 a visible realm-less legacy row',function()
 Bucket().bob=nil
 Bucket().carol=Legacy(Bucket()['alice@ebonhold'],'Carol',35000)
 Bucket().carol.class,Bucket().carol.buildId='PRIEST',nil
 C.setup(Announce('legacy Carol row')~=nil,'R2: fixture: the Leaderboard window publishes the change')
 local board=Board()
 C.guard(Names(board)=='Bob,Carol,Alice' and board[2].verified==false,
  'R2: the unverified Carol row stays on the board between Bob and Alice',Names(board))
 C.setup(WindowNames()==Names(board),'R2: fixture: the Leaderboard window presents the same rows',WindowNames())
 local ranks={}
 for _,name in ipairs({'Bob','Carol','Alice'}) do
  local info=D.GetPlayerInfo(name) or {}
  ranks[#ranks+1]=name..'='..printable(info.rank)
  C.guard(info.rank~=nil and info.rank==BoardRank(board,name),'R2: '..name..' ranks where the board presents '..name,info.rank)
 end
 print('OBSERVED','R2 tooltip',table.concat(ranks,' '))
 local carol=D.GetPlayerInfo('Carol') or {}
 C.guard(carol.dps==35000 and carol.category=='dummy','R2: the legacy row is Carol\'s record',carol.dps)
 local shown,line=TooltipRank('Carol',2)
 C.guard(shown,'R2: the unit tooltip says "2nd on leaderboard" for Carol',line)
end)

-- R3. A tie: Dana's equal record, received later through the real path.
C.scenario('R3 tied scores',function()
 local since=Refreshes()
 local ok,why=fx:Receive('Dana','dummy',{dps=30000})
 C.setup(ok==true,'R3: fixture: Dana\'s equal Training Dummy record is received through the real receive path',why)
 C.setup(V.LeaderboardSettled(H,since,2000,20)~=nil,'R3: fixture: the Leaderboard window publishes the change')
 local board=Board()
 C.guard(Names(board)=='Bob,Carol,Alice,Dana','R3: the board orders the tied records by the earlier one',Names(board))
 C.setup(WindowNames()==Names(board),'R3: fixture: the Leaderboard window presents the same rows',WindowNames())
 local alice,dana=D.GetPlayerInfo('Alice') or {},D.GetPlayerInfo('Dana') or {}
 print('OBSERVED','R3 tooltip Alice='..printable(alice.rank),'Dana='..printable(dana.rank))
 C.guard(alice.rank==3 and dana.rank==3 and BoardRank(board,'Dana')==3,
  'R3: tied scores share one rank, one above the two higher presented entries',printable(alice.rank)..'/'..printable(dana.rank))
 C.guard(dana.dps==30000 and dana.category=='dummy','R3: Dana\'s best record is her Training Dummy record',dana.dps)
 local shown,line=TooltipRank('Dana',3)
 C.guard(shown,'R3: the unit tooltip says "3rd on leaderboard" for Dana',line)
 C.guard(D.GetPlayerInfo('Zed')==nil,'R3: an unknown player has no rank')
end)

tip:Release()
C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(the tooltip rank agrees with the presented board; lookup, visibility, identity and ties unchanged)')
