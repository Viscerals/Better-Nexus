-- Workspace presentation of the #163 composition pass (gap map
-- NEXUS_VISUAL_GAP_MAP_20261028 and design/current "Nexus Main Panel -
-- Compact Redesign"), offline:
-- W1 a styled window gets an opaque base one level below it, inside its
--    border, repainted with the style; the shared tooltip gets one only for
--    an owner inside a styled window; a primary action is filled while
--    enabled and drawn as any disabled button otherwise;
-- W2 Records is titled Records, says its scope (best known, from shared
--    records received), asks for a selection when rows are listed and none
--    is selected, and shows a scroll track and "More below" while rows lie
--    below the view;
-- W3 Explore keeps its pinned count sentence but puts the catalog version on
--    hover, and a list with nothing selected says what the detail area is for;
-- W4 Plan's search shows "Search Echoes" while empty, the Save/Create action
--    is the filled primary, and the Auto-manage label ends clear of My Builds
--    (game) at six and eight locked slots;
-- W5 the Orb window says why Start would not start on the line right under
--    the Start row, clear of the approval text.
-- EXPECT: added by this pass (predicted to fail at 9bf92559: no base, no
-- primary seam use, "Explore / Leaderboard", a blank pane, no cue, the
-- catalog in the line, no placeholder, an unbounded label, the reason only in
-- the status block). GUARD: navigation and reading act, send, spend and
-- toggle nothing. SETUP: fixture state. Geometry is the harness anchor model
-- (layout_geometry_support) and its stated font model; textures, effective
-- opacity, fonts, scale and hit testing are native NOT_RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local LF=dofile('tests/prototype/leaderboard_fixture_support.lua')
local C=V.Checker('visual_workspaces_163009')

local players={}
for i=1,16 do players[i]={name='Player'..string.char(64+i),class=i%2==0 and 'MAGE' or 'PRIEST',dps={dummy=50000-i*1000},locked=0} end
local fx=LF.New({players=players})
local H=F.Boot(fx:Install(F.Database()),function(h) F.OrbService(h) end)
for _=1,200 do H.Advance(.05,.05) end
C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
G.UseFont(G.MODELS.default)
local function Quiet() return table.concat({#H.actions,#H.sent,tostring(Nexus.RecomputeStats().autoEnabled==true)},'/') end

C.scenario('W1 opaque bases under styled windows and Nexus tooltips; the primary fill',function()
 local T=Nexus.Theme
 local w=CreateFrame('Frame',nil,UIParent);w:SetSize(300,200);w:SetPoint('CENTER');w:SetFrameLevel(6)
 T.StyleWindow(w,0.96)
 local base=w._nexusWindowBase
 if not C.setup(base~=nil and base._nexusFill~=nil,'W1: fixture: the styled window has its base') then return end
 C.expect(base:GetFrameLevel()==5 and base:GetParent()==w and base:IsShown(),'W1: the base sits one level below the window',base:GetFrameLevel())
 local r,wr=G.Rect(base,w),G.Rect(w,w)
 C.expect(G.Inside(r,wr) and r[1]>0 and r[2]>0,'W1: the base lies inside the window border',G.Text(r))
 local painted
 local fill=base._nexusFill
 local real=fill.SetVertexColor
 fill.SetVertexColor=function(self,r,g,b,a) painted={r,g,b,a};if real then return real(self,r,g,b,a) end end
 T.SetStyle('slate');T.Reapply()
 local slate=painted and painted[4]
 T.SetStyle('vista');T.Reapply()
 fill.SetVertexColor=real
 C.expect(slate==1 and painted and painted[4]==1,'W1: the base is opaque in both styles and repainted with the style',
  tostring(slate)..' / '..tostring(painted and painted[4]))
 -- The shared tooltip: a base only for an owner inside a styled window.
 local tip=GameTooltip
 local tbase=tip and tip._nexusSolidBase
 if C.setup(tbase~=nil,'W1: fixture: the tooltip base exists') then
  local owner
  local realOwner=tip.GetOwner
  tip.GetOwner=function() return owner end
  tip:SetFrameLevel(3)
  local child=CreateFrame('Button',nil,w)
  owner=child;tip:Hide();tip:Show()
  C.expect(tbase:IsShown(),'W1: a Nexus tooltip (owner inside a styled window) gets the opaque base')
  owner=CreateFrame('Button',nil,UIParent);tip:Hide();tip:Show()
  C.guard(not tbase:IsShown(),'W1: any other owner\'s tooltip gets none')
  tip:Hide()
  C.guard(not tbase:IsShown(),'W1: the base hides with the tooltip')
  tip.GetOwner=realOwner
 end
 -- The primary seam.
 local b=CreateFrame('Button',nil,w,'UIPanelButtonTemplate');b:SetSize(120,22);b:SetText('Save');b.GetFontString=function() return b end
 b:Enable()
 local fills={}
 b.SetBackdropColor=function(_,r,g,bb,a) fills[#fills+1]={r,g,bb,a} end
 T.SetPrimary(b,true)
 local hover=T.PALETTES[T.Current().palette].hover
 local last=fills[#fills]
 C.expect(b._nexusPrimary==true and last and last[1]==hover[1] and last[2]==hover[2] and last[4]==1,'W1: an enabled primary is filled with the palette\'s hover colour')
 b:Disable();T._OnDisable(b);T._OnMouseUp(b)
 last=fills[#fills]
 local bg=T.STYLES[T.Current().style].buttonBg
 C.expect(last and last[1]==bg[1] and last[2]==bg[2],'W1: a disabled primary is drawn as any disabled button')
 T.SetPrimary(b,false)
 C.guard(b._nexusPrimary==nil,'W1: off returns it to an ordinary button')
end)

C.scenario('W2 Records: its title, scope, selection prompt and scroll cue',function()
 local q=Quiet()
 LF.Open(H,'dummy')
 local f=NexusLeaderboardFrame
 if not C.setup(f~=nil and f:IsShown(),'W2: fixture: Records is open') then return end
 local LB=Nexus.Leaderboard
 local v=LB.VirtualStats()
 C.setup(v.publishedRows==16 and v.selectedKey==nil,'W2: fixture: sixteen Training Dummy records, none selected',v.publishedRows)
 C.expect(f._title and V.Plain(f._title:GetText())=='Records','W2: the window is titled Records',f._title and f._title:GetText())
 local count
 for _,r in ipairs(f.regions or {}) do
  local t=r.kind=='FontString' and V.Plain(r:GetText() or '') or ''
  if t:find(' ranked ',1,true) then count=t end
 end
 C.guard(count and count:find('16 ranked Training Dummy',1,true)~=nil,'W2: the count line keeps its count and category',count)
 C.expect(count and count:find('best known, from shared records received',1,true)~=nil,'W2: and says what the ranking covers',count)
 local pane=f._leaderboardDetail
 C.expect(pane and pane.empty:IsShown() and V.Plain(pane.empty:GetText())==LB.SELECT_PROMPT,
  'W2: with records listed and none selected the pane asks for a selection',pane and pane.empty:GetText())
 C.expect(v.maxOffset>0 and f._scrollTrack:IsShown() and f._scrollThumb:IsShown() and f._scrollCue:IsShown(),
  'W2: a longer list shows its track, thumb and More below',v.maxOffset)
 LB.ScrollTo(math.huge)
 C.expect(f._scrollTrack:IsShown() and not f._scrollCue:IsShown(),'W2: at the end of the list More below goes, the track stays')
 local d=LF.Select(H,2)
 C.guard(d.row~=nil and not pane.empty:IsShown(),'W2: a selected record replaces the prompt')
 LB.Hide()
 C.guard(Quiet()==q,'W2: reading Records acted, sent and toggled nothing',Quiet())
end)

C.scenario('W3 Explore: the catalog version on hover; the empty detail says what it is for',function()
 local q=Quiet()
 Nexus.CommunityBuilds.Show()
 for _=1,100 do H.Advance(.05,.05) end
 local f=NexusCommunityBuildsFrame
 if not C.setup(f~=nil and f:IsShown() and f._syncStatusText~=nil,'W3: fixture: Explore is open') then return end
 local line=V.Plain(f._syncStatusText:GetText() or '')
 C.guard(line:find(' bundled + ',1,true)~=nil or line:find('Preparing sync data',1,true)~=nil,'W3: the pinned count sentence stays in the line',line)
 C.expect(not line:lower():find('catalog ',1,true),'W3: the catalog version is not in the line',line)
 C.expect(V.Plain(f._syncStatusText._nexusFullText or ''):find('Catalog version:',1,true)~=nil and f._syncStatusHit~=nil,
  'W3: the catalog version is on the line\'s hover',f._syncStatusText._nexusFullText)
 local sel=Nexus.CommunityBuilds.GetSelectedBuildForPanel and Nexus.CommunityBuilds.GetSelectedBuildForPanel() or nil
 local p=f._detailPanel
 local status=p and p._nexusStatus
 if sel==nil then
  C.expect(status~=nil and status:IsShown() and status.kind=='none' and not p:IsShown(),
   'W3: with nothing selected the detail area says to select a build',status and status.kind)
 else
  print('OBSERVED','W3 a build was selected on open; the no-selection placeholder was not reached here')
 end
 f:Hide()
 C.guard(Quiet()==q,'W3: reading Explore acted, sent and toggled nothing',Quiet())
end)

C.scenario('W4 Plan: search placeholder, primary Save, Auto-manage label clear of My Builds',function()
 local q=Quiet()
 Nexus.WishlistEditor.Show()
 local f=NexusEditorFrame
 if not C.setup(f~=nil and f:IsShown(),'W4: fixture: Plan is open') then return end
 local search=_G.NexusEditorSearch
 local hint=search and search._nexusHint
 if C.setup(hint~=nil,'W4: fixture: the search box') then
  local was=search:GetText() or ''
  search:SetText('')
  C.expect(hint:IsShown() and V.Plain(hint:GetText())=='Search Echoes','W4: an empty search shows Search Echoes')
  search:SetText('ember')
  C.expect(not hint:IsShown(),'W4: typed text hides it')
  search:SetText(was)
 end
 local apply
 for _,c in ipairs(f.children or {}) do
  local t=c.kind=='Button' and V.Plain(c:GetText() or '') or ''
  if t=='Create & assign' or t=='Create unassigned' or t=='Save changes' or t=='Save & assign' then apply=apply or c end
 end
 C.expect(apply~=nil and apply._nexusPrimary==true,'W4: the Save/Create action is the filled primary',apply and apply:GetText())
 -- Synthetic geometry: the Locked label takes its text width (the harness
 -- gives a FontString a 100 px box), then the label is fitted for six and
 -- for eight slots with the checkbox where the refresh anchors it.
 local check
 for _,c in ipairs(f.children or {}) do
  local pt=c.points and c.points[1]
  if c.kind=='CheckButton' and pt and type(pt[2])=='table' and pt[2].kind=='Button' then check=c end
 end
 local label=f._autoLockLabel
 local first=f._nexusLockedSlot and f._nexusLockedSlot(1)
 local locked=first and first.points and first.points[1] and first.points[1][2]
 local myBuilds=f._workspaceMyBuildsBtn
 if C.setup(check and label and locked and myBuilds and f._fitAutoLock,'W4: fixture: the locked strip, its checkbox, label and My Builds') then
  locked:SetWidth(G.Length(V.Plain(locked:GetText() or 'Locked (0/6):'))*G.model.char)
  for _,n in ipairs({6,8}) do
   local icon=f._nexusLockedSlot(n)
   check:ClearAllPoints();check:SetPoint('LEFT',icon,'RIGHT',26,0)
   f._fitAutoLock(n)
   local lr,mr=G.Rect(label,f),G.Rect(myBuilds,f)
   C.expect(not label:IsShown() or lr[3]<=mr[1]-8+0.5,'W4: with '..n..' slots the Auto-manage label ends 8 px left of My Builds (game)',
    G.Text(lr)..' / '..G.Text(mr))
   C.expect(label._nexusFullText=='Auto-manage locked Echo slots','W4: its whole name is on hover ('..n..' slots)')
  end
  f._fitAutoLock(check._nexusAnchorSlot or 6)
 end
 f:Hide()
 C.guard(Quiet()==q,'W4: reading Plan acted, sent and toggled nothing',Quiet())
end)

C.scenario('W5 Orbs: why Start would not start, on the line under Start',function()
 local q=Quiet()
 local f=Nexus.OrbPanel.Show()
 if not C.setup(f~=nil and f.startWhy~=nil and f.start~=nil,'W5: fixture: the Orb window') then return end
 Nexus.OrbPanel.Refresh()
 local s=Nexus.OrbRuntime.Status()
 local text=V.Plain(f.startWhy:GetText() or '')
 if s.canStart==false and s.startReason then
  C.expect(text:find('^Start: ')~=nil,'W5: Start\'s reason is said beside it',text)
  local sr,wr,ar=G.Rect(f.start,f),G.Rect(f.startWhy,f),G.Rect(f.approval,f)
  C.expect(wr[2]-sr[4]<=2 and wr[2]>=sr[4] and G.Apart(wr,ar) and wr[4]-wr[2]<=12,
   'W5: on the one line right under the Start row, clear of the approval text',G.Text(wr)..' / '..G.Text(sr)..' / '..G.Text(ar))
  C.guard(f.approval:GetHeight()>=34,'W5: the approval text keeps room for its two lines',f.approval:GetHeight())
 else
  C.guard(text=='','W5: a Start that can start has no refusal line',text)
 end
 Nexus.OrbPanel.Hide()
 C.guard(Quiet()==q and Nexus.OrbRuntime.Status().running~=true,'W5: opening the Orb window started, spent, sent and toggled nothing',Quiet())
end)

C.guard(#H.actions==0,'no game action anywhere in this test',#H.actions)
C.finish('(opaque bases and primary seam; Records title/scope/prompt/cue; Explore diagnostics on hover; Plan search/Save/label; Orb Start reason; offline model only, native NOT_RUN)')
