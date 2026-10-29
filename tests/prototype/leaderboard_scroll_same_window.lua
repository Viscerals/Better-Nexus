-- #21 Stage A, Leaderboard: a scroll that keeps the exact virtual window of
-- the bound rows does not release and rebind them.
--
-- Baseline (9bfb2bb9): every scroll, including a repeated scroll clamped at
-- the top or bottom and a sub-row ScrollTo inside one window, entered
-- BindRows, which released every visible row and bound the window again
-- (ui/Leaderboard.lua BindRows: ReleaseRows first).
-- Healthy behaviour (EXPECT, fails at the baseline): such a scroll moves the
-- ScrollFrame and its overflow cue only; the same row frames keep their
-- anchors, no scroll bind is counted and no row frame is created.
-- Unchanged (GUARD): an ordinary wheel notch still changes the window and is
-- bound exactly once (the 4-row wheel step is not changed); clamping and the
-- overflow cue stay exact; a dirty mark, a received record, a category or
-- class change, a selection, a resize and a failed bind still rebind; no
-- duplicate or missing row after rapid wheel input; the row pool stays
-- bounded; scrolling saves, sends and does nothing in the game.
-- Limit: ordinary full-step wheel input changes the window, so this stage does
-- not remove most wheel binds and makes no claim about visible flicker.
--
-- Real TOC boot, DPS owner, projection, ViewRefresh and Leaderboard window;
-- the real ScrollTo, wheel and size scripts, real row clicks and the real
-- receive path. Synthetic players (leaderboard_fixture_support.lua). Offline
-- model only; native frame timing and visuals are NOT_RUN.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('leaderboard_scroll_same_window')

local NAMES={'Alpha','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel',
 'India','Juliet','Kilo','Lima','Mike','November'}
local players={}
for i,name in ipairs(NAMES) do
 players[i]={name=name,class=(i%2==0) and 'PRIEST' or 'MAGE',dps={dummy=50000-i*1000},locked=0}
end
local fx=L.New({players=players})
local H=F.Boot(fx:Install(F.Database()))
for _=1,200 do H.Advance(.05,.05) end
local LB=Nexus.Leaderboard
C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
L.Open(H,'dummy')
local frame=assert(NexusLeaderboardFrame,'Leaderboard window')
local scroll=assert(frame._virtualListScrollFrame,'Leaderboard list')
local child=assert(scroll.scrollChild,'Leaderboard list child')
local function Stats() return LB.VirtualStats() end
local function Refreshes() return tonumber(Stats().dataRefreshes) or 0 end
local function Settle(since) return V.LeaderboardSettled(H,since,2000,20) end
C.setup(Stats().publishedRows==#NAMES,'fixture: every fixture record is listed',Stats().publishedRows)

-- The rows the window has checked out: shown children holding a record. Each
-- entry keeps the frame and its anchor table; ClearAllPoints replaces that
-- table, so an unchanged table means the row was not released/rebound.
-- The harness keeps SetPoint's arguments verbatim. A row has exactly one
-- TOPLEFT anchor in one of the two supported forms: (point, x, y), which
-- the Leaderboard uses, or (point, relativeTo, relativePoint, x, y). The
-- distance below the list top is -y; any other shape reads as nil.
local function AnchorTop(points)
 if type(points)~='table' or #points~=1 then return nil end
 local p=points[1]
 if type(p)~='table' or p[1]~='TOPLEFT' then return nil end
 local n=table.maxn(p)
 if n==3 and type(p[2])=='number' and type(p[3])=='number' then return -p[3] end
 if n==5 and type(p[4])=='number' and type(p[5])=='number' then return -p[5] end
 return nil
end
local function Bound()
 local out={}
 for _,b in ipairs(child.children) do
  if b:IsShown() and b.data~=nil and b.rank and b.sel then
   out[#out+1]={frame=b,points=b.points,y=AnchorTop(b.points),rank=tonumber(V.Plain(b.rank:GetText())),
    player=V.Plain(b.player:GetText()),dps=V.Plain(b.dps:GetText()),selected=b.sel:IsShown()}
  end
 end
 -- A malformed anchor sorts first; Positions() reports it.
 table.sort(out,function(a,b) return (a.y or -1)<(b.y or -1) end)
 return out
end
-- The decoded anchors are usable as the displayed order: every row has one,
-- they are distinct and increasing, and each row sits at its own rank's
-- place (40 per row) with consecutive ranks. Returns ok and a description.
local function Positions(list)
 local t={}
 local ok=#list>0
 for i,r in ipairs(list) do
  t[i]=tostring(r.rank)..'@'..tostring(r.y)
  if r.y==nil or r.rank==nil or r.y~=(r.rank-1)*40 then ok=false end
  if i>1 and (list[i-1].y==nil or r.y==nil or r.y<=list[i-1].y
   or list[i-1].rank==nil or r.rank~=list[i-1].rank+1) then ok=false end
 end
 return ok,table.concat(t,',')
end
local function Names(list)
 local t={}
 for i,r in ipairs(list) do t[i]=r.player end
 return table.concat(t,',')
end
local function Unchanged(a,b)
 if #a~=#b or #a==0 then return false end
 for i=1,#a do
  if a[i].frame~=b[i].frame or a[i].points~=b[i].points or a[i].player~=b[i].player then return false end
 end
 return true
end
local function Rebound(a,b)
 if #b==0 then return false end
 local old={}
 for _,r in ipairs(a) do old[r.points]=true end
 for _,r in ipairs(b) do if old[r.points] then return false end end
 return true
end
local function Distinct(list)
 local seen={}
 for _,r in ipairs(list) do
  if seen[r.player] then return false end
  seen[r.player]=true
 end
 return true
end
local function Highlighted()
 local out={}
 for _,r in ipairs(Bound()) do if r.selected then out[#out+1]=r.player end end
 return table.concat(out,',')
end
-- The thumb's offset from the top of its track (UpdateScrollCue).
local function Thumb()
 local thumb=frame._scrollThumb
 local p=thumb and thumb.points[1]
 return p and tonumber(p[5]) or nil,thumb and thumb:IsShown()
end
-- The window's own inputs (row 40, overscan 2, viewport at least 100), read
-- only to choose offsets that keep a window.
local function Window(offset)
 local h=math.max(100,scroll:GetHeight() or 458)
 return Nexus.VirtualList.Window(Stats().publishedRows,40,h,offset,2)
end
local function SameWindowOffsets(base)
 local w0,out=Window(base),{}
 for _,d in ipairs({1,2,3,5,8,13,21,31,39}) do
  local w=Window(base+d)
  if w.first==w0.first and w.last==w0.last and w.offset==base+d then out[#out+1]=base+d end
 end
 return out
end
local function Wheel(delta) scroll:GetScript('OnMouseWheel')(scroll,delta) end
local function Resize() scroll:GetScript('OnSizeChanged')(scroll) end

local calls={}
local function Count(owner,names)
 for _,n in ipairs(names) do
  local real=owner and owner[n]
  if type(real)=='function' then owner[n]=function(...) calls[#calls+1]=n;return real(...) end end
 end
end
Count(Nexus.Sync,{'RequestSync','RequestLoadout','BroadcastBuild','BroadcastMine','BroadcastDpsRecord','BroadcastDps','BroadcastDelete'})
Count(Nexus.BuildCatalog,{'Put','Delete','Remove'})
Count(Nexus.GameAdapter,{'SetLoadoutWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity','Take','Banish','Reroll','Freeze','Activate','Save','LockPerk','UnlockPerk'})

C.scenario('S1 repeated scrolls inside one window',function()
 LB.ScrollTo(0)
 local offsets=SameWindowOffsets(0)
 C.setup(#offsets>=3,'S1: fixture: several offsets keep the first window',#offsets)
 local before,v0=Bound(),Stats()
 C.setup(#before>0 and Distinct(before),'S1: fixture: the first window is bound',Names(before))
 C.setup(Positions(before),'S1: fixture: the row anchors decode to distinct ordered places',select(2,Positions(before)))
 local saved,sent,actions,n=F.Serialize(NexusDB),#H.sent,#H.actions,#calls
 for _,o in ipairs(offsets) do
  LB.ScrollTo(o)
  C.guard(scroll:GetVerticalScroll()==o and Stats().offset==o,'S1: the view and the reported offset move to '..o,
   scroll:GetVerticalScroll())
  local y,shown=Thumb()
  Resize()
  local fresh=Thumb()
  C.guard(shown and y~=nil and y==fresh,'S1: the overflow cue at '..o..' is the one a full bind draws',
   tostring(y)..' / '..tostring(fresh))
 end
 -- The resizes above rebind on purpose; measure the plain scrolls again.
 LB.ScrollTo(0)
 before,v0=Bound(),Stats()
 for _,o in ipairs(offsets) do LB.ScrollTo(o) end
 local after,v1=Bound(),Stats()
 print('OBSERVED','S1','offsets='..table.concat(offsets,','),'scrollBinds='..(v1.scrollBinds-v0.scrollBinds),
  'created='..(v1.created-v0.created),'same='..tostring(Unchanged(before,after)))
 C.expect(v1.scrollBinds==v0.scrollBinds,'S1: no scroll bind inside the same window',v1.scrollBinds-v0.scrollBinds)
 C.expect(Unchanged(before,after),'S1: the same rows keep their anchors (no release or rebind)',Names(after))
 C.guard(v1.created==v0.created,'S1: no row frame is created',v1.created-v0.created)
 C.guard(Names(after)==Names(before),'S1: the same records are shown',Names(after))
 C.guard(F.Serialize(NexusDB)==saved and #H.sent==sent and #H.actions==actions and #calls==n,
  'S1: scrolling saves, sends, requests and acts nothing',table.concat(calls,','))
end)

C.scenario('S2 repeated scrolls clamped at the top and the bottom',function()
 LB.ScrollTo(0)
 local v0,before=Stats(),Bound()
 LB.ScrollTo(-40);LB.ScrollTo(-400);Wheel(1)
 local v1,after=Stats(),Bound()
 C.guard(scroll:GetVerticalScroll()==0 and v1.offset==0,'S2: the top clamp stays exact',scroll:GetVerticalScroll())
 C.expect(v1.scrollBinds==v0.scrollBinds and Unchanged(before,after),'S2: clamped scrolls at the top do not rebind',
  v1.scrollBinds-v0.scrollBinds)
 LB.ScrollTo(math.huge)
 local v2,bottom=Stats(),Bound()
 C.guard(v2.scrollBinds==v1.scrollBinds+1 and Rebound(after,bottom),'S2: reaching the bottom binds the new window once',
  v2.scrollBinds-v1.scrollBinds)
 local maxOffset=v2.maxOffset
 C.setup(maxOffset>0 and scroll:GetVerticalScroll()==maxOffset,'S2: fixture: the list ends below the view',maxOffset)
 LB.ScrollTo(math.huge);LB.ScrollTo(maxOffset+400);Wheel(-1)
 local v3,again=Stats(),Bound()
 C.guard(scroll:GetVerticalScroll()==maxOffset and v3.offset==maxOffset,'S2: the bottom clamp stays exact',scroll:GetVerticalScroll())
 C.expect(v3.scrollBinds==v2.scrollBinds and Unchanged(bottom,again),'S2: clamped scrolls at the bottom do not rebind',
  v3.scrollBinds-v2.scrollBinds)
 C.guard(not frame._scrollCue:IsShown(),'S2: "More below" stays hidden at the bottom')
 LB.ScrollTo(0)
 C.guard(frame._scrollCue:IsShown(),'S2: and is shown again at the top')
end)

C.scenario('G1 an ordinary wheel notch changes the window and binds once',function()
 LB.ScrollTo(0)
 local v0,before=Stats(),Bound()
 Wheel(-1)
 local v1,after=Stats(),Bound()
 C.guard(scroll:GetVerticalScroll()==math.min(v1.maxOffset,40*4),'G1: one notch still moves four rows',
  scroll:GetVerticalScroll())
 C.guard(v1.scrollBinds==v0.scrollBinds+1,'G1: exactly one scroll bind',v1.scrollBinds-v0.scrollBinds)
 C.guard((v1.first~=v0.first or v1.last~=v0.last) and Rebound(before,after),'G1: the new window is bound',
  v0.first..'-'..v0.last..' -> '..v1.first..'-'..v1.last)
 C.guard(Distinct(after) and #after==v1.last-v1.first+1,'G1: no duplicate or missing row',Names(after))
 C.guard(Positions(after),'G1: each row sits at its own rank place, in order',select(2,Positions(after)))
end)

C.scenario('G2 rapid wheel input keeps the bound rows exact',function()
 LB.ScrollTo(0)
 for _,d in ipairs({-1,-1,1,-1,-1,-1,1,1,-1,-1,1,-1}) do Wheel(d) end
 local v,quick=Stats(),Bound()
 local offset=scroll:GetVerticalScroll()
 Resize()
 local fresh=Bound()
 C.guard(Distinct(quick) and #quick==v.last-v.first+1,'G2: no duplicate or missing row after rapid input',Names(quick))
 C.guard(Names(quick)==Names(fresh) and scroll:GetVerticalScroll()==offset,
  'G2: the same records as a fresh bind at that offset',Names(quick)..' / '..Names(fresh))
 C.guard(Positions(quick) and Positions(fresh),'G2: both bindings place each row at its own rank, in order',
  select(2,Positions(quick))..' / '..select(2,Positions(fresh)))
 C.guard(v.peakActive<=v.last-v.first+1+4,'G2: the visible pool stays bounded',v.peakActive)
 LB.ScrollTo(0)
end)

C.scenario('G3 a dirty mark rebinds the same window',function()
 LB.ScrollTo(0)
 local o=SameWindowOffsets(0)[1]
 local since=Refreshes()
 local v0,before=Stats(),Bound()
 LB.MarkDataDirty()
 LB.ScrollTo(o)
 local v1,after=Stats(),Bound()
 C.guard(v1.scrollBinds==v0.scrollBinds+1 and Rebound(before,after),'G3: the scroll after a dirty mark rebinds',
  v1.scrollBinds-v0.scrollBinds)
 LB.Refresh()
 C.setup(Settle(since)~=nil,'G3: fixture: the window publishes again')
 LB.ScrollTo(0)
end)

C.scenario('G4 a received record is shown and then kept by skipped scrolls',function()
 LB.ScrollTo(0)
 local since=Refreshes()
 local ok,why=fx:Receive('Bravo','dummy',{dps=48900})
 C.setup(ok==true,'G4: fixture: Bravo\'s better record is received through the real receive path',why)
 C.setup(Settle(since)~=nil,'G4: fixture: the window publishes it')
 local function BravoDps()
  for _,r in ipairs(Bound()) do if r.player=='Bravo' then return r.dps end end
 end
 C.guard(BravoDps()~=nil and BravoDps():find('48.9k',1,true)~=nil,'G4: the published row shows the new score',BravoDps())
 for _,o in ipairs(SameWindowOffsets(0)) do LB.ScrollTo(o) end
 C.guard(BravoDps()~=nil and BravoDps():find('48.9k',1,true)~=nil,'G4: and still after same-window scrolls',BravoDps())
 LB.ScrollTo(0)
end)

C.scenario('G5 a selection rebinds once and stays highlighted',function()
 local d=L.Select(H,2)
 C.setup(d and d.row~=nil,'G5: fixture: a real row click selects the second record')
 local name=d.row and d.row.player
 LB.ScrollTo(0)
 C.guard(Highlighted()==name and Stats().selectedVisible==true,'G5: the selected row is highlighted',Highlighted())
 local v0,before=Stats(),Bound()
 for _,o in ipairs(SameWindowOffsets(0)) do LB.ScrollTo(o) end
 local v1,after=Stats(),Bound()
 C.guard(Highlighted()==name and Stats().selectedKey~=nil,'G5: still only that row after same-window scrolls',Highlighted())
 C.expect(v1.scrollBinds==v0.scrollBinds and Unchanged(before,after),'G5: with the selection bound, same-window scrolls do not rebind',
  v1.scrollBinds-v0.scrollBinds)
 LB.ScrollTo(math.huge)
 local shown=false
 for _,r in ipairs(Bound()) do if r.player==name then shown=true end end
 C.guard(Highlighted()==(shown and name or ''),'G5: and correct in another window',Highlighted())
 LB.ScrollTo(0)
 C.guard(Highlighted()==name,'G5: and back in the first window',Highlighted())
end)

C.scenario('G6 a class filter and a category change rebind',function()
 LB.ScrollTo(0)
 local since=Refreshes()
 local v0,before=Stats(),Bound()
 LB.SetClassFilter('MAGE')
 C.setup(Settle(since)~=nil,'G6: fixture: the filtered list is published')
 local v1,after=Stats(),Bound()
 C.guard(v1.dataBinds>v0.dataBinds and Rebound(before,after),'G6: the class filter rebinds',v1.dataBinds-v0.dataBinds)
 local priests=false
 for _,r in ipairs(after) do if r.player=='Bravo' or r.player=='Delta' then priests=true end end
 C.guard(not priests,'G6: no Priest record stays bound',Names(after))
 since=Refreshes()
 LB.SetClassFilter('ALL')
 C.setup(Settle(since)~=nil,'G6: fixture: every class is published again')
 since=Refreshes()
 v0,before=Stats(),Bound()
 LB.SetCategory('lk')
 C.setup(Settle(since)~=nil,'G6: fixture: the Lich King board is published')
 C.guard(Stats().publishedRows==0 and #Bound()==0,'G6: no Training Dummy row stays bound on the empty Lich King board',Names(Bound()))
 since=Refreshes()
 LB.SetCategory('dummy')
 C.setup(Settle(since)~=nil,'G6: fixture: the Training Dummy board is published again')
 C.guard(#Bound()>0,'G6: its rows are bound again',#Bound())
end)

C.scenario('G7 a resize rebinds even when the window is unchanged',function()
 LB.ScrollTo(0)
 local v0,before=Stats(),Bound()
 Resize()
 local v1,after=Stats(),Bound()
 C.guard(v1.resizeBinds==v0.resizeBinds+1 and Rebound(before,after),'G7: a resize rebinds',v1.resizeBinds-v0.resizeBinds)
 local h=scroll:GetHeight()
 scroll:SetHeight(math.max(100,h)+40*3)
 Resize()
 local v2=Stats()
 C.guard(v2.resizeBinds==v1.resizeBinds+1 and v2.last>v1.last,'G7: a taller view binds a longer window',v1.last..'->'..v2.last)
 scroll:SetHeight(h)
 Resize()
end)

C.scenario('G8 a failed bind is never skipped afterwards',function()
 LB.ScrollTo(0)
 local o=SameWindowOffsets(0)[1]
 local identity=Nexus.Identity
 local real=identity.DisplaySafeText
 identity.DisplaySafeText=function() error('artificial row bind failure',0) end
 local ok=pcall(LB.ScrollTo,40*6)
 identity.DisplaySafeText=real
 C.setup(not ok,'G8: fixture: the scroll bind failed')
 C.guard(#Bound()==0 and Stats().active==0,'G8: the failure reclaims every row',#Bound())
 local v0=Stats()
 LB.ScrollTo(o)
 local v1,after=Stats(),Bound()
 C.guard(#after>0 and v1.scrollBinds==v0.scrollBinds+1,'G8: the next scroll binds the window again',#after)
 C.guard(Distinct(after) and #after==v1.last-v1.first+1,'G8: with no duplicate or missing row',Names(after))
 C.guard(Positions(after),'G8: and each row at its own rank place, in order',select(2,Positions(after)))
 LB.ScrollTo(0)
end)

C.guard(#calls==0,'no Sync, catalog or game call from scrolling or selecting a complete record',table.concat(calls,','))
C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(same-window scrolls keep their rows; every invalidation still rebinds; native NOT_RUN)')
