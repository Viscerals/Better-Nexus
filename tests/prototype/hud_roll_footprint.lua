-- HUD footprint through an ordinary automatic-rolling cycle
-- (BN-CONTROL-CRIMSON-HUD-STABILITY-001). Reported: while Auto rolls, the
-- panel repeatedly collapses between Echo choices and expands again, moving
-- the title and the footer buttons. The recording was not received; these are
-- synthetic transitions through the real runtime, adapter, policy and Panel:
-- board -> Auto takes -> waiting for the game's answer -> answer and grant
-- (no board) -> next board. Between boards the runtime renders no cards and
-- no recommendation.
--
-- Required: the same footprint (height, anchor, roll block, footer) through
-- that cycle; no old card or recommendation shown as current; a truthful
-- line in the reserved space; the reservation released by Auto OFF, a new
-- assignment, a layout-metrics change and a finished build; pauses and the
-- render transaction kept; the same actions as without the change. Expected
-- geometry is the board state's own measured geometry, not a formula.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local PLAN={}
for i=1,12 do PLAN[#PLAN+1]={spellId=200000+i,quality=i%4,stacks=1} end
local BOARDS={
 {{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}},
 {{spellId=200002,quality=2},{spellId=200052,quality=0},{spellId=200053,quality=1}},
 {{spellId=200003,quality=3},{spellId=200054,quality=2},{spellId=200055,quality=3}},
}
local H,granted
local function Boot(plan)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil;NexusOrbPanel=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={[1]={name='Synthetic plan',verified=true,echoes=plan or PLAN}}
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#') then
   local chunk,err=loadfile((line:gsub('\\','/')));assert(chunk,err);chunk('Nexus',{})
  end
 end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(20,.05)
 assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Synthetic plan',plan or PLAN),'assign the plan')
 if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then _G.NexusQuickStart:Hide();H.Advance(.2) end
 granted={}
end
local function Plain(t) return (tostring(t or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
-- Final frame geometry after the last layout pass. The panel is anchored by a
-- point on its vertical centre line, so edges are the anchor offset +- h/2.
local function Geo()
 local f=NexusPanel
 local p,_,_,x,y=f:GetPoint(1)
 local h=f:GetHeight()
 local _,_,_,rx,ry=f._rollArea:GetPoint(1)
 local ap,_,_,ax,ay=f._autoBtn:GetPoint(1)
 return {h=h,anchor=tostring(p)..':'..tostring(x)..':'..tostring(y),top=y+h/2,bottom=y-h/2,
  roll=f._rollArea:IsShown(),rollAt=tostring(rx)..':'..tostring(ry),rollH=f._rollArea:GetHeight(),
  footer=tostring(ap)..':'..tostring(ax)..':'..tostring(ay),footerY=(y-h/2)+(tonumber(ay) or 0),auto=f._autoBtn:IsShown()}
end
local function Same(a,b)
 return a.h==b.h and a.anchor==b.anchor and a.roll==b.roll and a.rollAt==b.rollAt and a.rollH==b.rollH
  and a.footer==b.footer and a.auto==b.auto
end
local function Show(g) return string.format('h=%s top=%s footerY=%s roll=%s',g.h,g.top,g.footerY,tostring(g.roll)) end
local function Content()
 local f=NexusPanel
 local cards={}
 for _,r in ipairs(f._rollArea.regions or {}) do
  if r~=f._rollStatus and r~=f._rollRec and r.GetText and r:IsShown() and Plain(r:GetText())~='' then cards[#cards+1]=Plain(r:GetText()) end
 end
 return {head=Plain(f._rollStatus:GetText()),body=Plain(f._rollRec:GetText()),cards=cards,
  orbs=f._orbsBtn and f._orbsBtn:IsShown() or false}
end
local function Offer(cards) H.Board(cards);H.Notify() end
local function Answer()
 local last=H.actions[#H.actions]
 H.perks.pendingSelectSpellId=nil
 H.Board({});H.Notify()
 return last
end
local function Grant(id) granted['Echo '..(id-200000)]={{spellId=id}};H.granted=H.Clone(granted);H.Notify() end
local function Takes(from) local t={} for i=(from or 0)+1,#H.actions do if H.actions[i][1]=='take' then t[#t+1]=tostring(H.actions[i][2]) end end return table.concat(t,',') end
local NOTHING='No Echo choice is showing.'
-- A new board with a needed Echo not yet granted (plan Echoes 4..12) and two
-- Echoes outside the plan.
local fresh=3
local function Fresh()
 fresh=fresh+1
 return {{spellId=200000+fresh,quality=fresh%4},{spellId=200060+fresh,quality=1},{spellId=200070+fresh,quality=2}}
end

-- 1. Repeated board -> waiting -> no board -> next board cycles.
Boot()
SlashCmdList.NEXUS('auto');H.Advance(.5)
local base,previous
for cycle,cards in ipairs(BOARDS) do
 Offer(cards);H.Advance(1.2)
 local g,c=Geo(),Content()
 base=base or g
 check(g.roll and #c.cards==3 and c.body=='Take a needed Echo','cycle '..cycle..': the board shows its three choices and the recommendation')
 check(Same(g,base),'cycle '..cycle..': the board footprint is the first board\'s: '..Show(g)..' vs '..Show(base))
 check(c.cards[1]:find('Echo '..(cards[1].spellId-200000)..' ',1,true)==1,'cycle '..cycle..': the first card is this board\'s: '..c.cards[1])
 if previous then
  for _,old in ipairs(previous) do
   for _,line in ipairs(c.cards) do check(not line:find(old,1,true),'cycle '..cycle..': no card of the previous board remains: '..line) end
  end
 end
 previous={}
 for _,card in ipairs(cards) do previous[#previous+1]='Echo '..(card.spellId-200000)..' ' end
 local last=Answer();H.Advance(.5)
 local pg,pc=Geo(),Content()
 check(Same(pg,base),'cycle '..cycle..': waiting for the answer keeps the footprint: '..Show(pg))
 check(#pc.cards==0 and pc.body=='Waiting for the game to confirm the last Echo action.','cycle '..cycle..': while waiting, the waiting line and no card: '..pc.body)
 Grant(last[2]);H.Advance(.4)
 local gg,gc=Geo(),Content()
 check(Same(gg,base),'cycle '..cycle..': between boards the footprint stays: '..Show(gg)..' vs '..Show(base))
 check(#gc.cards==0 and gc.body==NOTHING and gc.head=='Roll status' and not gc.orbs,
  'cycle '..cycle..': between boards no old card, no old recommendation, only the plain line: ['..gc.head..'] ['..gc.body..'] '..#gc.cards)
end
check(Takes()=='200001,200002,200003' and Nexus.RecomputeStats().autoEnabled,'the same actions, in order, and Auto stays ON: '..Takes())

-- 2. A hidden panel stays hidden (the user's choice) and reopens with the
-- same reserved footprint and the cleared content.
Nexus.Panel.Hide();Nexus.RequestRecompute();H.Advance(.5)
check(not NexusPanel:IsShown(),'hidden by the user: the reserved gap does not show the panel')
Nexus.Panel.Show();H.Advance(.5)
local reopened=Geo()
check(NexusPanel:IsShown() and Same(reopened,base) and Content().body==NOTHING,'reopened: the same reserved footprint and the plain line: '..Show(reopened))

-- 3. Auto OFF releases the reservation: the existing inactive layout; Auto ON
-- again in the same gap does not bring back a released reservation.
do
 -- A status line set after the gap render stays current through the
 -- release render (checked before the runtime renders again).
 Nexus.Panel.SetStatus('Test status line after the gap render')
 local current=Nexus.Panel._lastModel.status
 SlashCmdList.NEXUS('auto')
 check(Nexus.Panel._lastModel.status==current and Nexus.Panel._lastModel.auto==false,
  'the release render keeps the current status line: '..tostring(Nexus.Panel._lastModel.status))
 H.Advance(.5)
 local off=Geo()
 check(not Nexus.RecomputeStats().autoEnabled and not off.roll and off.h<base.h,'Auto OFF between boards: the roll block is released: '..Show(off))
 SlashCmdList.NEXUS('auto');H.Advance(.5)
 local on=Geo()
 check(Nexus.RecomputeStats().autoEnabled and not on.roll and on.h==off.h,'Auto ON again in the gap: no released reservation returns: '..Show(on))
 Offer(Fresh());H.Advance(1.2)
 check(Same(Geo(),base),'the next board restores the roll block')
 local last=Answer();H.Advance(.5);Grant(last[2]);H.Advance(.4)
 check(Same(Geo(),base),'and the gap after it is reserved again')
 -- The Auto button (not only the command) releases it too.
 NexusPanel._autoBtn:Click();H.Advance(.5)
 local clicked=Geo()
 check(not Nexus.RecomputeStats().autoEnabled and not clicked.roll and clicked.h==off.h,'the Auto button OFF in the gap releases the block: '..Show(clicked))
 NexusPanel._autoBtn:Click();H.Advance(.5)
 check(Nexus.RecomputeStats().autoEnabled,'the Auto button turns Auto ON again')
 Offer(Fresh());H.Advance(1.2)
 local last2=Answer();H.Advance(.5);Grant(last2[2]);H.Advance(.4)
 check(Same(Geo(),base),'fixture: reserved gap again before the next section')
end

-- 4. A loading screen while the last Take is unanswered: the runtime's real
-- pause is shown in the same footprint; no action, no Orb window, no
-- completion. The grant later ends the hold and the gap stays reserved.
do
 Offer(Fresh());H.Advance(1.2)
 local takes=#H.actions
 check(H.actions[takes][1]=='take','fixture: a Take was sent')
 H.Fire('PLAYER_LEAVING_WORLD');H.Board({});H.Notify();H.Advance(.5)
 local g,c=Geo(),Content()
 check(Same(g,base) and c.head=='Auto ON — paused' and #c.cards==0
  and c.body=='Waiting for the game to confirm the last Echo action.','loading screen: the pause and the waiting line in the same footprint: ['..c.head..'] ['..c.body..'] '..Show(g))
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(6)
 local e,ec=Geo(),Content()
 check(Same(e,base) and ec.head=='Auto ON — paused' and #ec.cards==0,'after the world entry the unresolved hold stays visible: ['..ec.head..'] '..Show(e))
 check(#H.actions==takes and not (NexusOrbPanel and NexusOrbPanel:IsShown()),'no action and no Orb window during the hold')
 H.perks.pendingSelectSpellId=nil;Grant(H.actions[takes][2]);H.Advance(1)
 local r,rc=Geo(),Content()
 check(Same(r,base) and rc.body==NOTHING and rc.head=='Roll status','the grant ends the hold; the gap stays reserved: ['..rc.head..'] '..Show(r))
end

-- 5. A failed render commits nothing: Auto OFF is rendered with a failing
-- widget (the transaction hides the panel); Auto ON again is rendered normally
-- and the gap is still the committed reserved one.
do
 local header=NexusPanel._buildHeaderText
 local set=header.SetText
 local fail=true
 header.SetText=function(self,...) if fail then fail=false;error('injected render failure') end return set(self,...) end
 local before=Nexus.Panel.RenderStats().failures
 SlashCmdList.NEXUS('auto');H.Advance(.5)
 check(Nexus.Panel.RenderStats().failures>before,'fixture: the Auto OFF render failed')
 header.SetText=set
 SlashCmdList.NEXUS('auto');H.Advance(.5)
 local g=Geo()
 check(Nexus.RecomputeStats().autoEnabled and NexusPanel:IsShown() and Same(g,base) and Content().body==NOTHING,
  'after the failed render the committed reservation is unchanged: '..Show(g))
end

-- 6. A layout-metrics change (UI scale) is another layout context: the
-- reservation is released and the layout is computed for the new metrics.
do
 local scale=UIParent.GetEffectiveScale
 UIParent.GetEffectiveScale=function() return 1.25 end
 Nexus.RequestRecompute();H.Advance(.5)
 local g=Geo()
 check(not g.roll and g.h<base.h,'a UI-scale change releases the old context\'s reservation: '..Show(g))
 UIParent.GetEffectiveScale=scale
 Nexus.RequestRecompute();H.Advance(.5)
 Offer(Fresh());H.Advance(1.2)
 check(Geo().roll and #Content().cards==3,'the next board shows the roll block again')
 local last=Answer();H.Advance(.5);Grant(last[2]);H.Advance(.4)
 check(Same(Geo(),base) and Content().body==NOTHING,'in the new context the next gap is reserved again')
end

-- 7. A new assignment in the gap is another context: released.
do
 check(Same(Geo(),base),'fixture: reserved gap before the new assignment')
 local other={}
 for i=20,31 do other[#other+1]={spellId=200000+i,quality=i%4,stacks=1} end
 H.perks.serverBuildSlots[1]={name='Other plan',verified=true,echoes=other}
 check(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Other plan',other),'fixture: assign another plan')
 Nexus.RequestRecompute();H.Advance(.5)
 local g=Geo()
 check(not g.roll and Content().body~='Take a needed Echo','a new assignment releases the reservation: '..Show(g))
end

-- 8. A finished build: no reservation (the existing complete layout); only
-- current content may show a roll block.
do
 Boot({{spellId=200001,quality=1,stacks=1}})
 SlashCmdList.NEXUS('auto');H.Advance(.5)
 Offer(BOARDS[1]);H.Advance(1.2)
 check(Takes()=='200001','fixture: the last needed Echo is taken')
 local last=Answer();H.Advance(.5);Grant(last[2]);H.Advance(.6)
 local badge=false
 for _,r in ipairs(NexusPanel.regions or {}) do
  if r.GetText and r:IsShown() and Plain(r:GetText())=='Wishlist complete' then badge=true end
 end
 check(badge,'fixture: the build is finished (the complete layout is shown)')
 check(not NexusPanel._rollArea:IsShown(),'a finished build is not held open by a reservation: roll='..tostring(NexusPanel._rollArea:IsShown())..' body=['..Content().body..']')
end

print('PASS hud_roll_footprint checks='..checks)
