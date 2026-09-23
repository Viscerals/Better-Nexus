-- The first main HUD reaches the screen.
--
-- Reported, from test.9043: the minimap's left-click shows no HUD, right-click
-- opens the Wishlist editor, start-up is ready, and the panel's own counters
-- read "renders 0, commits 0, failures 0, hidden 16". Hidden sixteen times
-- while wanted and not suppressed, and never once rendered.
--
-- A left-click reaches Panel.Toggle, which asks for a first display. With no
-- panel input yet, that request only schedules a recompute and keeps the
-- panel hidden, so the HUD appears only when the next runtime step renders
-- something. At level 80, a run that has not reached 79 rolled Echoes -- or
-- whose ownership is not synchronized yet -- with no board and nothing in
-- flight ended its step with a status line and NO render at all. Every
-- other dispatch outcome renders: the no-catalog branch, level 1, levels
-- 2-79 with or without a board, and the completed run. So in that one state
-- no click could ever show the HUD, and each one added to "hidden".
--
-- Everything here goes through the real minimap button, the real Panel, the
-- real runtime and the real host. Nothing declares the panel ready.
--
-- Whether this is the reporter's own cause is NOT established: their level is
-- not in any evidence this suite may use. The counter signature matches it
-- exactly, which is why this state is the one tested first.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H

-- Rolled ownership of exactly n Echoes, spread across real harness Echoes.
local function Granted(n)
 local granted,id,left={},200001,n
 while left>0 do
  local stacks=math.min(5,left)
  local list={}
  for index=1,stacks do list[index]={spellId=id,quality=0} end
  granted['Echo '..(id-200000)]=list
  left=left-stacks;id=id+1
 end
 return granted
end

local function Boot(level,rolled,before)
 H=F.Boot(F.Database({}),function(h)
  h.playerLevel=level
  if rolled then h.granted=Granted(rolled) end
  if before then before(h) end
 end)
 check(Nexus.StartupStatus().coreReady==true,'fixture: start-up completed at level '..level)
 -- A first-run session opens the quick start; a player closes it.
 if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then
  _G.NexusQuickStart:Hide();H.Advance(.2)
 end
 return H
end

local function LeftClick()
 local button=assert(_G.NexusMinimapButton,'the real minimap button exists')
 button.scripts.OnClick(button,'LeftButton')
end
local function RightClick()
 local button=assert(_G.NexusMinimapButton,'the real minimap button exists')
 button.scripts.OnClick(button,'RightButton')
end
local function Facts() return Nexus.Panel.VisibilityFacts() end
local function Stats() return Nexus.Panel.RenderStats() end
local function Status()
 local model=Nexus.Panel._lastModel
 return model and tostring(model.status or '') or ''
end

-- Start-up settles; the runtime takes its ordinary steps. The panel is
-- wanted by default, so a HUD that can render is on screen WITHOUT a click.
local function Settle() H.Advance(2.5) end

-- The player's own interaction: left-click hides a HUD that is up and shows
-- one that is down. Asserted both ways, because "left-click does not display
-- the main HUD" is what was reported.
local function ClickCycle(label)
 LeftClick()
 check(Facts().shown==false and Facts().wanted==false,
  label..': a left-click hides the HUD it finds on screen')
 LeftClick();H.Advance(.5)
 check(Facts().shown==true,label..': and the next left-click shows it again')
end

-- 1. The reported state. Level 80, no Wishlist, Automation off, nothing
-- rolled yet, ownership synchronized, no board, nothing in flight.
do
 Boot(80,nil)
 local owned=Nexus.GameAdapter.Owned()
 check(owned.synced==true and (owned.total or 0)<79,
  'fixture: ownership is known and below 79: '..tostring(owned.total))
 check(Nexus.GameAdapter.Board()==nil,'fixture: there is no board')
 check(not Nexus.GameAdapter.InFlight(),'fixture: nothing is in flight')
 Settle()
 local stats,facts=Stats(),Facts()
 check(stats.calls>0,
  'at level 80 below 79 Echoes the runtime renders a HUD: renders='..stats.calls)
 check(stats.commits>0,'and that render commits: commits='..stats.commits)
 check(facts.shown==true,'so the main HUD is on screen after start-up')
 check(Status():find('0/79',1,true)~=nil,'showing where the run stands: '..Status())
 ClickCycle('level 80 below 79')
 check(#H.actions==0,
  'and none of this took an Echo, froze, banished, rerolled, saved, locked or spent')
end

-- 2. Known ownership AT 79 is a completed run: that path already rendered and
-- must go on rendering.
do
 Boot(80,79)
 local owned=Nexus.GameAdapter.Owned()
 check(owned.synced==true and owned.total==79,
  'fixture: 79 rolled Echoes, synchronized: '..tostring(owned.total))
 Settle()
 check(Stats().commits>0 and Facts().shown==true,'a completed run shows its HUD')
 ClickCycle('completed run')
 check(#H.actions==0,'without saving or spending anything on its own')
end

-- 3. Ownership NOT synchronized yet. A run boundary opens a new ownership
-- generation and the server has not answered. The count is not known, and
-- the HUD must say so rather than show a number it does not have.
do
 Boot(80,40)
 H.holdGrantedResponse=true
 Nexus.GameAdapter.RunBoundaryReset()
 check(Nexus.GameAdapter.Owned().synced==false,'fixture: ownership is waiting for the server')
 -- In the client this reset happens inside a step, which is followed by
 -- more steps. Ask for the next one through the product's own route.
 Nexus.RequestRecompute()
 Settle()
 check(Stats().commits>0 and Facts().shown==true,'an unsynchronized run still shows its HUD')
 check(Status():find('/79',1,true)==nil,
  'without claiming a count it does not know: '..Status())
 check(Status():lower():find('not synchronized',1,true)~=nil,
  'and saying the count is not known yet: '..Status())
 check(#H.actions==0,'and nothing is taken while the count is unknown')
end

-- 4. A selection the server has not answered yet: the client's own latch.
do
 -- The latch is in place before start-up's first step, so the in-flight
 -- wait is the branch that has to produce the FIRST display. Set after a
 -- first render, it would only relabel a HUD that was already there.
 Boot(80,10,function(h) h.perks.pendingSelectSpellId=200002 end)
 check(Nexus.GameAdapter.InFlight()==true,'fixture: a selection is in flight')
 check(Nexus.GameAdapter.Board()==nil,'fixture: with no board on screen')
 Settle()
 check(Stats().commits>0 and Facts().shown==true,
  'a run finishing its last selections shows its HUD')
 check(Status():find('final Echo selections',1,true)~=nil,
  'and says what it is waiting for: '..Status())
end

-- 5. The control that always worked: a level below 80.
do
 Boot(60,nil)
 Settle()
 check(Stats().commits>0 and Facts().shown==true,'at level 60 the HUD is shown, as it always was')
 ClickCycle('level 60')
end

-- 6. Deliberate hiding is still deliberate. Rendering the idle HUD on every
-- runtime step must never put back a panel the player closed.
do
 Boot(80,nil)
 Settle()
 check(Facts().shown==true,'fixture: the HUD is on screen')
 LeftClick()
 check(Facts().shown==false and Facts().wanted==false,'a left-click hides it')
 local before=Stats().commits
 H.Advance(4)
 check(Facts().shown==false,
  'and further runtime steps render without showing it again')
 check(Stats().commits>=before,'(the HUD may keep rendering while hidden: '..Stats().commits..')')
 LeftClick();H.Advance(.5)
 check(Facts().shown==true,'the next left-click shows it immediately')
end

-- 7. Right-click opens the Wishlist editor, and that editor is a menu: the
-- HUD steps aside while it is open and returns when it closes. This is also
-- the guarantee the old unassociated-editor regression protected: with an
-- active Saved Build that has no Wishlist, opening Wishlists must SHOW the
-- editor, or the HUD is suppressed with nothing on screen to explain why.
do
 Boot(80,nil)
 -- Saved Build 2: the shared fixture associates a Wishlist with Saved Build 1
 -- only, so 2 is the unassociated case the old regression was about.
 H.perks.serverBuildSlots[2]={name='Active Saved Build',verified=true,
  echoes={{spellId=200001,quality=0,stacks=1}}}
 H.perks.serverActiveSlot=2
 H.Notify();Nexus.GameAdapter.Poll()
 Settle()
 check(tonumber(Nexus.GameAdapter.Slots().activeSlot)==2,'fixture: a Saved Build is active')
 check(Nexus.GameAdapter.GetLoadoutWishlist(2)==nil,'fixture: and it has no Wishlist')
 check(Facts().shown==true,'fixture: the HUD is on screen')
 RightClick();H.Advance(.2)
 local editor=_G.NexusEditorFrame
 check(editor~=nil and editor:IsShown()==true,
  'right-click shows the Wishlist editor for a Saved Build with no Wishlist')
 check(Facts().menuSuppressed==true and Facts().shown==false,
  'and the HUD steps aside for it')
 H.Advance(3)
 check(Facts().shown==false,'runtime steps do not push the HUD back over the editor')
 editor:Hide();H.Advance(.5)
 check(Facts().menuSuppressed==false and Facts().shown==true,
  'closing the editor brings the HUD back')
end

-- 8. The video's order: local tools ready while shared builds are still
-- loading, the stock widget present, the loading view left open. At every
-- observation SOME Difficulty/Soul Ash display is on screen. Both may be up
-- for at most one scan while the stock widget stands aside -- replacement
-- first, original second is the order the handoff requires -- but never
-- neither.
do
 Boot(80,nil)
 local stock=CreateFrame('Frame','ProjectEbonholdPlayerRunFrame',UIParent)
 stock:Show()
 check(Nexus.ServerStatus.IsUsingNexusHud()==true,'fixture: the Nexus HUD is the preference')
 local loading=_G.NexusLoadingStatusFrame
 local loadingWas=loading and loading:IsShown() or false
 local gaps=0
 for tick=1,12 do
  H.Advance(.25)
  if Facts().shown~=true and stock:IsShown()~=true then gaps=gaps+1 end
 end
 check(gaps==0,'at no observation was neither display on screen: '..gaps..' gaps')
 check(Facts().shown==true,'the Nexus HUD is on screen once it has rendered')
 check(stock:IsShown()==false,
  'and the stock widget has stood aside for it, because the replacement can display')
 check((loading and loading:IsShown() or false)==loadingWas,
  'the loading view was left exactly as it was')
end

-- 9. A failure before the render is even counted, then recovery. The FIRST
-- render raises at the real Panel.Render's own pre-counter step -- while it
-- is converting the model's text -- so renders stays 0, failures stays 0 and
-- nothing is on screen, which is the counter signature the report carried.
-- The fault is installed through the fixture's own fault-injection hook, so
-- it is in place before start-up's first render. Once it is gone the HUD
-- must render and be shown with no reload.
do
 local faultOn=true
 F.fileHooks={['ui\\Panel.lua']=function()
  local panel=Nexus.Panel
  local realRender=panel.Render
  panel.Render=function(...)
   local text=Nexus.UserText
   local realMessage=text and text.Message
   if faultOn and text then
    text.Message=function() error('pre-counter failure') end
   end
   local ok,a,b=pcall(realRender,...)
   if text then text.Message=realMessage end
   if not ok then error(a,0) end
   return a,b
  end
 end}
 Boot(80,nil)
 F.fileHooks=nil
 Settle()
 check(Stats().calls==0 and Stats().failures==0 and Facts().shown==false,
  'fixture: the first render failed before it was counted, and nothing is on screen')
 faultOn=false
 Settle()
 if Facts().shown~=true then LeftClick();H.Advance(1.5) end
 check(Stats().calls>0 and Stats().commits>0 and Facts().shown==true,
  'once the fault is gone the HUD renders and is shown, with no reload')
 check(#H.actions==0,'and recovering took no gameplay action')
end

print('PASS first_hud_display: a left-click at level 80 reaches a committed HUD checks='..checks)
