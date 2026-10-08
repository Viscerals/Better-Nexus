-- F-S3-3 (P3), regression-first: the Leaderboard's class list closes with its
-- window. The class list is a separate UIParent frame at TOOLTIP strata
-- (ui/Leaderboard.lua EnsureFrame); only explicit calls and the public Hide
-- close it. The window's close button and Escape (UISpecialFrames) hide the
-- window frame itself, and Panel.CloseOtherWindows hides it when another
-- Nexus window opens; in all of these the class list stays on screen over the
-- game UI and keeps taking clicks for the hidden window.
-- Healthy behaviour (EXPECT, fails at the baseline): after a real class-button
-- click, a raw NexusLeaderboardFrame:Hide() (the operation of the close
-- button and of Escape) closes the class list, and reopening the window does
-- not bring it back; opening the Build Library (whose public Show closes other
-- Nexus windows) closes it too.
-- Unchanged (GUARD, holds at the baseline): the public Leaderboard.Hide closes
-- the window and the list and is idempotent; the class button toggles the
-- list; choosing a class filters the rows, closes the list and "All Classes"
-- lists every class again; no game action.
-- Real TOC boot, DPS owner, projection, Leaderboard and Build Library windows;
-- real button clicks; saved data from leaderboard_fixture_support.lua. The
-- class list is found by its rows, without hooking CreateFrame.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('leaderboard_class_menu_close')
local fx=L.New({players={
 {name='Alpha',class='MAGE',dps={dummy=40000},locked=0},
 {name='Bravo',class='PRIEST',dps={dummy=30000},locked=0},
}})
local H=F.Boot(fx:Install(F.Database()))
for _=1,200 do H.Advance(.05,.05) end
local LB=Nexus.Leaderboard
C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
L.Open(H,'dummy')
local frame=NexusLeaderboardFrame

-- The labels of a frame's button children.
local function Rows(menu)
 local rows={}
 for _,child in ipairs(menu.children or {}) do
  if child.kind=='Button' then
   for _,region in ipairs(child.regions or {}) do
    if region.kind=='FontString' then rows[V.Plain(region:GetText())]=child end
   end
  end
 end
 return rows
end
local classButton=V.Frame(H,function(f)
 return f:GetParent()==frame and f.arrow~=nil and f:GetScript('OnClick')~=nil
end)
local menu=V.Frame(H,function(f)
 local rows=f:GetParent()==UIParent and Rows(f) or {}
 return rows['All Classes']~=nil and rows['Priest']~=nil and rows['Mage']~=nil
end)
C.setup(classButton~=nil,'fixture: the real class button is found')
C.setup(menu~=nil and menu:GetFrameStrata()=='TOOLTIP','fixture: the real class list is a UIParent frame at TOOLTIP strata')

local function Open(tag)
 if not LB.IsShown() then L.Open(H,'dummy') end
 C.setup(frame:IsShown(),tag..': fixture: the Leaderboard window is open')
 if not menu:IsShown() then classButton:Click() end
 return C.setup(menu:IsShown(),tag..': fixture: a class-button click opens the class list')
end
local function Order()
 local out={}
 for i,r in ipairs((L.RenderedRows(H))) do out[i]=V.Plain(r.player) end
 return table.concat(out,',')
end

C.scenario('K1 the close button and Escape (raw window Hide)',function()
 if not (classButton and menu and Open('K1')) then return end
 frame:Hide()
 C.setup(not frame:IsShown(),'K1: fixture: the window is hidden')
 print('OBSERVED','K1 class list shown after window Hide='..printable(menu:IsShown()))
 C.expect(not menu:IsShown(),'K1: the class list closes with its window')
 L.Open(H,'dummy')
 C.setup(frame:IsShown(),'K1: fixture: the window is reopened')
 C.expect(not menu:IsShown(),'K1: reopening the window does not bring the old class list back')
 LB.Hide()
 C.guard(not frame:IsShown() and not menu:IsShown(),'K1: the public Hide closes the window and the list')
end)

C.scenario('K2 another Nexus window opens',function()
 if not (classButton and menu and Open('K2')) then return end
 Nexus.CommunityBuilds.Show()
 C.setup(NexusCommunityBuildsFrame~=nil and NexusCommunityBuildsFrame:IsShown() and not frame:IsShown(),
  'K2: fixture: opening the Build Library closes the Leaderboard window')
 C.expect(not menu:IsShown(),'K2: the class list closes with the Leaderboard window')
 Nexus.CommunityBuilds.Hide()
 LB.Hide()
 C.guard(not frame:IsShown() and not menu:IsShown(),'K2: the public Hide leaves both closed')
end)

C.scenario('G1 the public Hide, twice',function()
 if not (classButton and menu and Open('G1')) then return end
 local ok,err=pcall(LB.Hide)
 C.guard(ok and not frame:IsShown() and not menu:IsShown(),'G1: the public Hide closes the window and its open list',err)
 ok,err=pcall(LB.Hide)
 C.guard(ok and not frame:IsShown() and not menu:IsShown(),'G1: a second public Hide is harmless',err)
 L.Open(H,'dummy')
 C.guard(frame:IsShown() and not menu:IsShown(),'G1: reopening after the public Hide shows no class list')
end)

C.scenario('G2 the class button and the class filter',function()
 if not (classButton and menu) then return end
 if not LB.IsShown() then L.Open(H,'dummy') end
 classButton:Click()
 C.guard(menu:IsShown(),'G2: the class button opens the list')
 classButton:Click()
 C.guard(not menu:IsShown(),'G2: and a second click closes it')
 classButton:Click()
 local priest=Rows(menu)['Priest']
 local since=tonumber(LB.VirtualStats().dataRefreshes) or 0
 if priest then priest:Click() end
 C.setup(priest~=nil and V.LeaderboardSettled(H,since,2000,20)~=nil,'G2: fixture: choosing Priest publishes the filtered list')
 C.guard(not menu:IsShown() and LB.VirtualStats().classFilter=='PRIEST' and Order()=='Bravo',
  'G2: choosing a class closes the list and lists that class only',Order())
 classButton:Click()
 local all=Rows(menu)['All Classes']
 since=tonumber(LB.VirtualStats().dataRefreshes) or 0
 if all then all:Click() end
 C.setup(all~=nil and V.LeaderboardSettled(H,since,2000,20)~=nil,'G2: fixture: choosing All Classes publishes the list')
 C.guard(not menu:IsShown() and LB.VirtualStats().classFilter=='ALL' and Order()=='Alpha,Bravo',
  'G2: "All Classes" lists every class again',Order())
 LB.Hide()
end)

C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(the class list closes with its window; the public Hide and the class filter are unchanged)')
