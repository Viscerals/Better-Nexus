-- F-S3-1 (P3), regression-first: the Leaderboard keeps the selected record
-- across an ordinary publication. A row click stores the window's own record
-- key (ui/Leaderboard.lua RecordKey with its local typed encoding), while the
-- published projection indexes its rows by the projection's record key
-- (core/ViewProjections.lua, Identity.TypedIdentity). The two never agree, so
-- every publication that binds the index finds no selected row, clears the
-- selection, blanks the detail pane and drops the row highlight, even when the
-- selected record is still listed.
-- Healthy behaviour (EXPECT, fails at the baseline): after a real publication
-- in which the selected record is still listed, the same selected key, its
-- detail pane and its row highlight remain. Publications: a represented-data
-- revision with unchanged rows (the public revision bus, then ViewRefresh), a
-- record received for another character that reorders the board, a search
-- that still matches, clearing that search, and a better score on the same
-- record (the detail then shows the new score).
-- Unchanged (GUARD, holds at the baseline): a search that excludes the record
-- clears its selection and detail, and clearing the search does not bring it
-- back; a record replaced by the same character's record on another loadout
-- (a different record under the current identity contract) is no longer
-- selected; a class filter clears the selection; the rows listed; no game
-- action.
-- Real TOC boot, DPS owner, projection, ViewRefresh and Leaderboard window;
-- real row clicks, search box and receive path; saved data and readers from
-- leaderboard_fixture_support.lua. Artificial names and scores.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('leaderboard_selection_publication')
local fx=L.New({players={
 {name='Alpha',class='MAGE',dps={dummy=40000},locked=0},
 {name='Bravo',class='PRIEST',dps={dummy=30000},locked=0},
 -- Charlie has no Training Dummy record until scenario S2.
 {name='Charlie',class='MAGE',dps={lk=20000},locked=0},
}})
local H=F.Boot(fx:Install(F.Database()))
for _=1,200 do H.Advance(.05,.05) end
local LB=Nexus.Leaderboard
C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
L.Open(H,'dummy')
local search=NexusLeaderboardSearch
C.setup(search~=nil,'fixture: the real search box exists')

local function Refreshes() return tonumber(LB.VirtualStats().dataRefreshes) or 0 end
local function Settle(since) return V.LeaderboardSettled(H,since,2000,20) end
local function Order()
 local out={}
 for i,r in ipairs((L.RenderedRows(H))) do out[i]=V.Plain(r.player) end
 return table.concat(out,',')
end
-- Click the rendered row of `name` (a real row click).
local function Select(name)
 for _,r in ipairs((L.RenderedRows(H))) do
  if V.Plain(r.player)==name then return L.Select(H,r.index) end
 end
 return nil
end
-- The names of the bound rows whose selection mark is shown.
local function Highlighted()
 local out={}
 local child=NexusLeaderboardFrame._virtualListScrollFrame.scrollChild
 for _,b in ipairs(child.children) do
  if b:IsShown() and b.data~=nil and b.sel and b.sel:IsShown() then out[#out+1]=V.Plain(b.player:GetText()) end
 end
 return table.concat(out,',')
end
local function Type(text)
 search:SetFocus();search:SetText('');search:Insert(text)
end

-- Select Bravo with a real row click; returns the selected key.
local function Begin(tag)
 local d=Select('Bravo')
 C.setup(d~=nil and d.row~=nil and d.row.player=='Bravo','['..tag..'] fixture: a real row click selects Bravo')
 local key=LB.VirtualStats().selectedKey
 C.setup(key~=nil and Highlighted()=='Bravo','['..tag..'] fixture: the window holds the selection and highlights Bravo',key)
 return key
end

local function Survives(tag,key)
 local v,d=LB.VirtualStats(),L.Detail()
 print('OBSERVED',tag,'selectedKey='..printable(v.selectedKey),'detail='..printable(d.row and d.row.player),
  'highlighted='..Highlighted())
 C.expect(v.selectedKey~=nil and v.selectedKey==key,tag..': the still-listed record keeps its selection',v.selectedKey)
 C.expect(d.row~=nil and d.row.player=='Bravo','['..tag..'] the detail pane still shows the selected record',
  d.row and d.row.player)
 C.expect(Highlighted()=='Bravo' and v.selectedVisible==true,tag..': and its row is still highlighted',Highlighted())
 return d
end

local function Cleared(tag)
 local v,d=LB.VirtualStats(),L.Detail()
 C.guard(v.selectedKey==nil and d.row==nil and Highlighted()=='',
  tag..': the selection, its detail and its highlight are cleared',printable(v.selectedKey))
end

C.scenario('S1 a represented-data revision with unchanged rows',function()
 local key=Begin('S1')
 local since=Refreshes()
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source='artificial selection fixture'})
 C.setup(Settle(since)~=nil,'S1: fixture: the window publishes again (ViewRefresh)')
 C.guard(Order()=='Alpha,Bravo','S1: the same two records are listed',Order())
 Survives('S1',key)
end)

C.scenario('S2 a record received for another character reorders the board',function()
 local key=Begin('S2')
 local since=Refreshes()
 local ok,why=fx:Receive('Charlie','dummy',{dps=35000})
 C.setup(ok==true,'S2: fixture: Charlie\'s record is received through the real receive path',why)
 C.setup(Settle(since)~=nil,'S2: fixture: the window publishes the received record')
 C.guard(Order()=='Alpha,Charlie,Bravo','S2: the received record is ranked above Bravo',Order())
 Survives('S2',key)
end)

C.scenario('S3 a search that still matches, then clearing it',function()
 local key=Begin('S3')
 local since=Refreshes()
 Type('bra')
 C.setup(Settle(since)~=nil,'S3: fixture: the window publishes the search result')
 C.guard(Order()=='Bravo','S3: the search lists Bravo only',Order())
 Survives('S3 search',key)
 since=Refreshes()
 search:SetText('')
 C.setup(Settle(since)~=nil,'S3: fixture: the window publishes the cleared search')
 C.guard(Order()=='Alpha,Charlie,Bravo','S3: every record is listed again',Order())
 Survives('S3 cleared',key)
end)

C.scenario('S4 a better score on the same record',function()
 local key=Begin('S4')
 local since=Refreshes()
 local ok,why=fx:Receive('Bravo','dummy',{dps=33000})
 C.setup(ok==true,'S4: fixture: Bravo\'s better record on the same loadout is received',why)
 C.setup(Settle(since)~=nil,'S4: fixture: the window publishes it')
 local d=Survives('S4',key)
 C.expect(d.row~=nil and d.row.dps==33000,'S4: the detail shows the better score',d.row and d.row.dps)
end)

C.scenario('G1 a search that excludes the selected record',function()
 Begin('G1')
 local since=Refreshes()
 Type('alp')
 C.setup(Settle(since)~=nil,'G1: fixture: the window publishes the search result')
 C.setup(Order()=='Alpha','G1: fixture: the search lists Alpha only',Order())
 Cleared('G1 excluded')
 since=Refreshes()
 search:SetText('')
 C.setup(Settle(since)~=nil,'G1: fixture: the window publishes the cleared search')
 Cleared('G1 cleared search')
end)

C.scenario('G2 the selected record is replaced by another loadout',function()
 Begin('G2')
 local since=Refreshes()
 local ordinary=L.OrdinaryRows(70)
 local bravo=fx.players[2]
 local ok,why=Nexus.DpsCapture.ReceiveRecord({v=7,c='dummy',d=34000,u=180,t=L.STAMP+900,p='Bravo',l=80,k='PRIEST',
  o=bravo.owner,r=fx.realm,e=L.DpsRows(ordinary),f=L.Fingerprint(ordinary)},'Bravo-'..fx.realm)
 C.setup(ok==true,'G2: fixture: Bravo\'s better record on another loadout is received through the real receive path',why)
 C.setup(Settle(since)~=nil,'G2: fixture: the window publishes it')
 local replaced
 for _,r in ipairs((L.RenderedRows(H))) do
  if V.Plain(r.player)=='Bravo' then replaced=r.data end
 end
 C.setup(replaced~=nil and replaced.fingerprint==L.Fingerprint(ordinary),'G2: fixture: Bravo\'s row is now the other loadout\'s record')
 Cleared('G2 replaced record')
end)

C.scenario('G3 a class filter',function()
 Begin('G3')
 local since=Refreshes()
 LB.SetClassFilter('MAGE')
 C.setup(Settle(since)~=nil,'G3: fixture: the window publishes the filtered list')
 C.guard(Order()=='Alpha,Charlie','G3: the class filter lists the Mage records',Order())
 Cleared('G3 class filter')
 since=Refreshes()
 LB.SetClassFilter('ALL')
 C.setup(Settle(since)~=nil,'G3: fixture: the window publishes every class again')
end)

C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(a still-listed selected record survives publication; removal and exclusion clear it)')
