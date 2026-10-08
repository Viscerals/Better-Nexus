-- F-S3-2 (P3), regression-first: a populated Leaderboard category does not
-- show the previous category's "no records" instruction. The detail pane's
-- empty text is written only when a category has no rows (ui/Leaderboard.lua
-- RefreshData); with rows and no selection the pane shows that same font
-- string again without resetting it. After the empty "Both records" category,
-- the populated Training Dummy list therefore sits beside "No builds have both
-- Training Dummy and Lich King records yet."
-- Healthy behaviour (EXPECT, fails at the baseline): after a real category
-- change from an empty category (Both records, Lich King) to the populated
-- Training Dummy category, with nothing selected, the detail pane does not
-- show an empty-category instruction (hidden, blank or neutral).
-- Unchanged (GUARD, holds at the baseline): a genuinely empty category still
-- says so with its own instruction; a selected record hides the instruction
-- and shows the record; the category change clears the selection; the rows
-- listed; no game action.
-- Real TOC boot, DPS owner, projection and Leaderboard window; real tab
-- clicks and the public SetCategory control; saved data from
-- leaderboard_fixture_support.lua (no Lich King record, so no Both records
-- pair). Artificial names and scores.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('leaderboard_empty_detail_text')
local fx=L.New({players={
 {name='Alpha',class='MAGE',dps={dummy=40000},locked=0},
 {name='Bravo',class='PRIEST',dps={dummy=30000},locked=0},
}})
local H=F.Boot(fx:Install(F.Database()))
for _=1,200 do H.Advance(.05,.05) end
local LB=Nexus.Leaderboard
C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
L.Open(H,'combined')
local frame=NexusLeaderboardFrame
local pane=frame and frame._leaderboardDetail
C.setup(pane~=nil and pane.empty~=nil,'fixture: the real detail pane and its empty text exist')

local function Refreshes() return tonumber(LB.VirtualStats().dataRefreshes) or 0 end
local function Tab(label)
 return V.Frame(H,function(f)
  return f:GetParent()==frame and f.text~=nil and f.active~=nil and V.Plain(f.text:GetText())==label
 end)
end
-- Click a real category tab and wait for its publication.
local function Click(tag,label)
 local tab=Tab(label)
 C.setup(tab~=nil,tag..': fixture: the "'..label..'" tab exists')
 if not tab then return false end
 local since=Refreshes()
 tab:Click()
 return C.setup(V.LeaderboardSettled(H,since,2000,20)~=nil,tag..': fixture: the window publishes the "'..label..'" category')
end
local function Text() return V.Plain(pane.empty:GetText()) end
local function Instruction(text)
 local l=V.Plain(text):lower()
 return l:find('no builds have both',1,true)~=nil or l:find('records are known yet',1,true)~=nil
end
-- What the pane says for a populated category with nothing selected.
local function Neutral(tag)
 local v=LB.VirtualStats()
 C.setup(v.publishedRows==2 and v.category=='dummy','['..tag..'] fixture: the Training Dummy list holds its two records',v.publishedRows)
 C.guard(v.selectedKey==nil and L.Detail().row==nil,tag..': nothing is selected after the category change')
 print('OBSERVED',tag,'empty shown='..printable(pane.empty:IsShown()),'text='..Text())
 C.expect(not (pane.empty:IsShown() and Instruction(Text())),
  tag..': the populated list shows no empty-category instruction',Text())
end

-- E1. Both records (empty) to Training Dummy (populated).
C.scenario('E1 from Both records to Training Dummy',function()
 local v=LB.VirtualStats()
 C.guard(v.publishedRows==0 and pane.empty:IsShown() and Text():find('No builds have both',1,true)==1,
  'E1: the empty Both records category says that no build has both records',Text())
 if Click('E1','Training Dummy') then Neutral('E1') end
end)

-- E2. Lich King (empty) to Training Dummy (populated).
C.scenario('E2 from Lich King to Training Dummy',function()
 if Click('E2','Lich King') then
  C.guard(LB.VirtualStats().publishedRows==0 and pane.empty:IsShown()
   and Text():find('No Lich King records are known yet',1,true)==1,
   'E2: the empty Lich King category says that no Lich King record is known',Text())
 end
 if Click('E2','Training Dummy') then Neutral('E2') end
end)

-- E3. The public SetCategory control, from Both records to Training Dummy.
C.scenario('E3 the public category control',function()
 local since=Refreshes()
 LB.SetCategory('combined')
 C.setup(V.LeaderboardSettled(H,since,2000,20)~=nil,'E3: fixture: the window publishes Both records')
 C.guard(LB.VirtualStats().publishedRows==0 and pane.empty:IsShown() and Instruction(Text()),
  'E3: the empty category keeps its instruction',Text())
 since=Refreshes()
 LB.SetCategory('dummy')
 C.setup(V.LeaderboardSettled(H,since,2000,20)~=nil,'E3: fixture: the window publishes Training Dummy')
 Neutral('E3')
end)

-- G1. A selected record hides the instruction; an empty category shows its own.
C.scenario('G1 a selection, then an empty category',function()
 local d=L.Select(H,2)
 C.setup(d.row~=nil and d.row.player=='Bravo','G1: fixture: a real row click selects Bravo')
 C.guard(not pane.empty:IsShown() and d.title~=nil and d.title~='','G1: the selected record replaces the empty text',Text())
 if Click('G1','Both records') then
  C.guard(LB.VirtualStats().publishedRows==0 and LB.VirtualStats().selectedKey==nil and L.Detail().row==nil,
   'G1: the category change clears the selection')
  C.guard(pane.empty:IsShown() and Text():find('No builds have both',1,true)==1,
   'G1: and the empty category says that no build has both records',Text())
 end
end)

C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(a populated category shows no stale empty-category instruction; genuine empty states keep theirs)')
