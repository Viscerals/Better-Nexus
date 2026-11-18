-- #21 Stage A, Community Builds: a scroll that keeps the exact virtual window
-- of the current publication does not release and rebind its cards.
--
-- Baseline (9bfb2bb9): every scroll, including a repeated scroll clamped at
-- the top or bottom and a sub-row ScrollTo inside one window, entered the
-- binder, which released every visible card and bound the window again
-- (ui/CommunityRenderer.lua renderBuildWindow: ReleaseAllCards first).
-- Healthy behaviour (EXPECT, fails at the baseline): such a scroll moves the
-- ScrollFrame only; the same card frames keep their anchors, no scroll bind
-- is counted and no card frame is created.
-- Unchanged (GUARD): an ordinary wheel notch still changes the window and is
-- bound exactly once (the 3-card wheel step is not changed); clamping stays
-- exact; a data revision, a dirty mark, a layout change, a resize, a failed
-- bind and a publication still rebind; the selection highlight stays right;
-- no duplicate or missing card after rapid wheel input; the card pool stays
-- bounded; scrolling saves, sends and does nothing in the game.
-- Limit: ordinary full-step wheel input changes the window, so this stage does
-- not remove most wheel binds and makes no claim about visible flicker.
--
-- Real TOC boot, catalog, DPS owner, projection, controller and Community
-- window; the real ScrollTo, wheel and size scripts and real card clicks.
-- Synthetic players (leaderboard_fixture_support.lua). Offline model only;
-- native frame timing and visuals are NOT_RUN.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('community_scroll_same_window')

local NAMES={'Alpha','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel',
 'India','Juliet','Kilo','Lima','Mike','November'}
local players={}
for i,name in ipairs(NAMES) do
 players[i]={name=name,class='MAGE',variant=i,dps={dummy=40000+i*100,lk=30000+i*100}}
end
local fx=L.New({players=players})
local H=F.Boot(fx:Install(F.Database({version=2})),function(h) h.playerLevel=60 end)
for _=1,400 do H.Advance(.05,.05) end
local CB=Nexus.CommunityBuilds
CB.Show()
local frame=assert(NexusCommunityBuildsFrame,'Community window')
local scroll=assert(frame._virtualListScrollFrame,'Community list')
local child=assert(scroll.scrollChild,'Community list child')

local function Click(b)
 if b.kind=='CheckButton' then b:SetChecked(not b:GetChecked()) end
 b:Click()
end
local function Settle()
 for _=1,4000 do
  local d=CB.DiagnosticSnapshot()
  if d.projectionCurrent and not d.projectionPending and not d.projectionDirty then return d end
  H.Advance(.05,.05)
 end
 return nil
end
if frame._classDropBtn:GetText()~='All Classes' then Click(frame._classDropBtn) end
if frame._scopeBtn:IsEnabled() then Click(frame._scopeBtn) end
C.setup(Settle()~=nil,'fixture: the Community projection settles')
local function Stats() return CB.VirtualStats() end
C.setup((tonumber(Stats().results) or 0)>=#NAMES,'fixture: every fixture build is listed',Stats().results)

-- The cards the window has checked out: shown, parented to the list child.
-- Each entry keeps the frame and its anchor table; ClearAllPoints replaces
-- that table, so an unchanged table means the card was not released/rebound.
local function Bound()
 local out={}
 for _,f in ipairs(H.frames) do
  if f.buildId~=nil and f.selectedHighlight and f:IsShown() and f:GetParent()==child then
   local p=f.points[1]
   out[#out+1]={frame=f,id=f.buildId,points=f.points,y=p and -(tonumber(p[5]) or 0) or 0,
    width=f:GetWidth(),selected=f.selectedHighlight:IsShown(),title=f.title:GetText()}
  end
 end
 table.sort(out,function(a,b) return a.y<b.y end)
 return out
end
local function Ids(list)
 local t={}
 for i,c in ipairs(list) do t[i]=tostring(c.id) end
 return table.concat(t,',')
end
local function Unchanged(a,b)
 if #a~=#b or #a==0 then return false end
 for i=1,#a do
  if a[i].frame~=b[i].frame or a[i].points~=b[i].points or a[i].id~=b[i].id then return false end
 end
 return true
end
local function Rebound(a,b)
 if #b==0 then return false end
 local old={}
 for _,c in ipairs(a) do old[c.points]=true end
 for _,c in ipairs(b) do if old[c.points] then return false end end
 return true
end
local function Distinct(list)
 local seen={}
 for _,c in ipairs(list) do
  if seen[c.id] then return false end
  seen[c.id]=true
 end
 return true
end
-- The renderer's own window inputs (card row 92, overscan 2, viewport at
-- least 100), read only to choose offsets that keep or leave a window.
local function Window(offset)
 local h=math.max(100,scroll:GetHeight() or 458)
 return Nexus.VirtualList.Window(Stats().results,92,h,offset,2)
end
local function SameWindowOffsets(base)
 local w0,out=Window(base),{}
 for _,d in ipairs({1,2,3,5,8,13,23,45,71,91}) do
  local w=Window(base+d)
  if w.first==w0.first and w.last==w0.last and w.offset==base+d then out[#out+1]=base+d end
 end
 return out
end
local function Wheel(delta) scroll:GetScript('OnMouseWheel')(scroll,delta) end
local function Resize() scroll:GetScript('OnSizeChanged')(scroll) end

-- Side effects of scrolling (no Advance between the counted operations).
local calls={}
local function Count(owner,names)
 for _,n in ipairs(names) do
  local real=owner and owner[n]
  if type(real)=='function' then owner[n]=function(...) calls[#calls+1]=n;return real(...) end end
 end
end
Count(Nexus.Sync,{'RequestSync','RequestLoadout','BroadcastBuild','BroadcastMine','BroadcastDpsRecord','BroadcastDps','BroadcastDelete'})
Count(Nexus.BuildCatalog,{'Put','Delete','Remove'})
Count(Nexus.DpsCapture,{'ReceiveRecord','Record','Clear'})
Count(Nexus.GameAdapter,{'SetLoadoutWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity','Take','Banish','Reroll','Freeze','Activate','Save','LockPerk','UnlockPerk'})

C.scenario('S1 repeated scrolls inside one window',function()
 CB.ScrollTo(0)
 local offsets=SameWindowOffsets(0)
 C.setup(#offsets>=3,'S1: fixture: several offsets keep the first window',#offsets)
 local before,v0=Bound(),Stats()
 C.setup(#before>0 and Distinct(before),'S1: fixture: the first window is bound',Ids(before))
 local saved,sent,actions,n=F.Serialize(NexusDB),#H.sent,#H.actions,#calls
 for _,o in ipairs(offsets) do
  CB.ScrollTo(o)
  C.guard(scroll:GetVerticalScroll()==o,'S1: the view moves to '..o,scroll:GetVerticalScroll())
  C.guard(Stats().offset==o,'S1: the reported offset follows to '..o,Stats().offset)
 end
 local after,v1=Bound(),Stats()
 print('OBSERVED','S1','offsets='..table.concat(offsets,','),'scrollBinds='..(v1.scrollBinds-v0.scrollBinds),
  'created='..(v1.created-v0.created),'same='..tostring(Unchanged(before,after)))
 C.expect(v1.scrollBinds==v0.scrollBinds,'S1: no scroll bind inside the same window',v1.scrollBinds-v0.scrollBinds)
 C.expect(Unchanged(before,after),'S1: the same cards keep their anchors (no release or rebind)',Ids(after))
 C.guard(v1.created==v0.created,'S1: no card frame is created',v1.created-v0.created)
 C.guard(Ids(after)==Ids(before),'S1: the same builds are shown',Ids(after))
 C.guard(F.Serialize(NexusDB)==saved and #H.sent==sent and #H.actions==actions and #calls==n,
  'S1: scrolling saves, sends, requests and acts nothing',table.concat(calls,','))
end)

C.scenario('S2 repeated scrolls clamped at the top and the bottom',function()
 CB.ScrollTo(0)
 local v0,before=Stats(),Bound()
 CB.ScrollTo(-50);CB.ScrollTo(-500)
 local v1,after=Stats(),Bound()
 C.guard(scroll:GetVerticalScroll()==0 and v1.offset==0,'S2: the top clamp stays exact',scroll:GetVerticalScroll())
 C.expect(v1.scrollBinds==v0.scrollBinds and Unchanged(before,after),'S2: a clamped scroll at the top does not rebind',
  v1.scrollBinds-v0.scrollBinds)
 CB.ScrollTo(1e9)
 local v2,bottom=Stats(),Bound()
 C.guard(v2.scrollBinds==v1.scrollBinds+1 and Rebound(after,bottom),'S2: reaching the bottom binds the new window once',
  v2.scrollBinds-v1.scrollBinds)
 local maxOffset=v2.maxOffset
 C.setup(maxOffset>0 and scroll:GetVerticalScroll()==maxOffset,'S2: fixture: the list ends below the view',maxOffset)
 CB.ScrollTo(1e9);CB.ScrollTo(maxOffset+400);Wheel(-1)
 local v3,again=Stats(),Bound()
 C.guard(scroll:GetVerticalScroll()==maxOffset and v3.offset==maxOffset,'S2: the bottom clamp stays exact',scroll:GetVerticalScroll())
 C.expect(v3.scrollBinds==v2.scrollBinds and Unchanged(bottom,again),'S2: clamped scrolls at the bottom do not rebind',
  v3.scrollBinds-v2.scrollBinds)
 C.guard(again[#again].id==bottom[#bottom].id and v3.last==v3.results,'S2: the last build stays bound at the bottom',v3.last)
 CB.ScrollTo(0)
end)

C.scenario('G1 an ordinary wheel notch changes the window and binds once',function()
 CB.ScrollTo(0)
 local v0,before=Stats(),Bound()
 Wheel(-1)
 local v1,after=Stats(),Bound()
 C.guard(scroll:GetVerticalScroll()==math.min(v1.maxOffset,88*3),'G1: one notch still moves three card heights',
  scroll:GetVerticalScroll())
 C.guard(v1.scrollBinds==v0.scrollBinds+1,'G1: exactly one scroll bind',v1.scrollBinds-v0.scrollBinds)
 C.guard((v1.first~=v0.first or v1.last~=v0.last) and Rebound(before,after),'G1: the new window is bound',
  v0.first..'-'..v0.last..' -> '..v1.first..'-'..v1.last)
 C.guard(Distinct(after) and #after==v1.last-v1.first+1,'G1: no duplicate or missing card',Ids(after))
end)

C.scenario('G2 rapid wheel input keeps the bound rows exact',function()
 CB.ScrollTo(0)
 for _,d in ipairs({-1,-1,1,-1,-1,-1,1,1,-1,-1,-1,-1,1}) do Wheel(d) end
 local v,quick=Stats(),Bound()
 local offset=scroll:GetVerticalScroll()
 Resize()
 local fresh=Bound()
 C.guard(Distinct(quick) and #quick==v.last-v.first+1,'G2: no duplicate or missing card after rapid input',Ids(quick))
 C.guard(Ids(quick)==Ids(fresh) and scroll:GetVerticalScroll()==offset,
  'G2: the same builds as a fresh bind at that offset',Ids(quick)..' / '..Ids(fresh))
 C.guard(v.peakActive<=v.last-v.first+1+4,'G2: the visible pool stays bounded',v.peakActive)
 CB.ScrollTo(0)
end)

C.scenario('G3 a represented-data revision rebinds the same window',function()
 CB.ScrollTo(0)
 local o=SameWindowOffsets(0)[1]
 local v0,before=Stats(),Bound()
 Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED,{source='artificial scroll fixture'})
 CB.ScrollTo(o)
 local v1,after=Stats(),Bound()
 C.guard(v1.scrollBinds==v0.scrollBinds+1 and Rebound(before,after),'G3: the scroll after a revision rebinds',
  v1.scrollBinds-v0.scrollBinds)
 C.setup(Settle()~=nil,'G3: fixture: the view publishes the revision')
 CB.ScrollTo(0)
end)

C.scenario('G4 a dirty mark rebinds the same window',function()
 C.setup(Settle()~=nil,'G4: fixture: settled')
 CB.ScrollTo(0)
 local o=SameWindowOffsets(0)[1]
 local v0,before=Stats(),Bound()
 CB.MarkDataDirty()
 CB.ScrollTo(o)
 local v1,after=Stats(),Bound()
 C.guard(v1.scrollBinds==v0.scrollBinds+1 and Rebound(before,after),'G4: the scroll after a dirty mark rebinds',
  v1.scrollBinds-v0.scrollBinds)
 C.setup(Settle()~=nil,'G4: fixture: the view publishes again')
 CB.ScrollTo(0)
end)

C.scenario('G5 a layout change rebinds the same window',function()
 C.setup(Settle()~=nil,'G5: fixture: settled')
 CB.ScrollTo(0)
 local o=SameWindowOffsets(0)[1]
 local layout=frame._responsiveLayout
 C.setup(type(layout)=='table' and type(layout.card)=='table','G5: fixture: the window has a responsive layout')
 -- A new layout table, as ApplyResponsiveLayout assigns on a font, size or
 -- status-row change, with a narrower card.
 local narrow={}
 for k,v in pairs(layout) do narrow[k]=v end
 narrow.card={}
 for k,v in pairs(layout.card) do narrow.card[k]=v end
 narrow.card.width=layout.card.width-40
 local v0,before=Stats(),Bound()
 frame._responsiveLayout=narrow
 CB.ScrollTo(o)
 local v1,after=Stats(),Bound()
 C.guard(v1.scrollBinds==v0.scrollBinds+1 and Rebound(before,after),'G5: the scroll after a layout change rebinds',
  v1.scrollBinds-v0.scrollBinds)
 C.guard(#after>0 and after[1].width==narrow.card.width,'G5: the cards take the new width',after[1] and after[1].width)
 frame._responsiveLayout=layout
 CB.ScrollTo(0)
 local back=Bound()
 C.guard(#back>0 and back[1].width==layout.card.width,'G5: and the restored width after it',back[1] and back[1].width)
end)

C.scenario('G6 a resize rebinds even when the window is unchanged',function()
 CB.ScrollTo(0)
 local v0,before=Stats(),Bound()
 Resize()
 local v1,after=Stats(),Bound()
 C.guard(v1.resizeBinds==v0.resizeBinds+1 and Rebound(before,after),'G6: a resize rebinds',v1.resizeBinds-v0.resizeBinds)
 local h=scroll:GetHeight()
 scroll:SetHeight(math.max(100,h)+92*3)
 Resize()
 local v2=Stats()
 C.guard(v2.resizeBinds==v1.resizeBinds+1 and v2.last>v1.last,'G6: a taller view binds a longer window',v1.last..'->'..v2.last)
 scroll:SetHeight(h)
 Resize()
end)

C.scenario('G7 a failed bind is never skipped afterwards',function()
 CB.ScrollTo(0)
 local o=SameWindowOffsets(0)[1]
 local identity=Nexus.Identity
 local real=identity.DisplaySafeText
 identity.DisplaySafeText=function() error('artificial card bind failure',0) end
 local ok=pcall(CB.ScrollTo,92*4)
 identity.DisplaySafeText=real
 C.setup(not ok,'G7: fixture: the scroll bind failed')
 C.guard(#Bound()==0 and Stats().active==0,'G7: the failure reclaims every card',#Bound())
 local v0=Stats()
 CB.ScrollTo(o)
 local v1,after=Stats(),Bound()
 C.guard(#after>0 and v1.scrollBinds==v0.scrollBinds+1,'G7: the next scroll binds the window again',#after)
 C.setup(Settle()~=nil,'G7: fixture: the view recovers')
 CB.ScrollTo(0)
end)

C.scenario('G8 selection stays highlighted through skipped and bound scrolls',function()
 C.setup(Settle()~=nil,'G8: fixture: settled')
 CB.ScrollTo(0)
 local cards=Bound()
 C.setup(#cards>=2,'G8: fixture: two cards are bound',#cards)
 local target=cards[2].id
 cards[2].frame:Click()
 C.setup(Settle()~=nil and Stats().selectedId==target,'G8: fixture: a real card click selects the build',Stats().selectedId)
 local function Highlighted()
  local out={}
  for _,c in ipairs(Bound()) do if c.selected then out[#out+1]=tostring(c.id) end end
  return table.concat(out,',')
 end
 C.guard(Highlighted()==tostring(target),'G8: the selected card is highlighted',Highlighted())
 for _,o in ipairs(SameWindowOffsets(0)) do CB.ScrollTo(o) end
 C.guard(Highlighted()==tostring(target),'G8: still only that card after same-window scrolls',Highlighted())
 CB.ScrollTo(1e9)
 local shown=false
 for _,c in ipairs(Bound()) do if c.id==target then shown=true end end
 C.guard(Highlighted()==(shown and tostring(target) or ''),'G8: and correct in another window',Highlighted())
 CB.ScrollTo(0)
 C.guard(Highlighted()==tostring(target),'G8: and back in the first window',Highlighted())
end)

C.scenario('G9 a publication rebinds the current window',function()
 C.setup(Settle()~=nil,'G9: fixture: settled')
 CB.ScrollTo(0)
 local v0,before=Stats(),Bound()
 CB.Refresh()
 local v1,after=Stats(),Bound()
 C.guard(v1.dataBinds==v0.dataBinds+1 and Rebound(before,after),'G9: a refresh publishes and rebinds',v1.dataBinds-v0.dataBinds)
end)

C.guard(#calls==0,'no Sync, catalog, DPS or game call from scrolling or selecting a complete build',table.concat(calls,','))
C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(same-window scrolls keep their cards; every invalidation still rebinds; native NOT_RUN)')
