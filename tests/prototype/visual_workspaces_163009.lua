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
-- Correction 3 adds W5c (the whole Orb run page flows, upper rows included),
-- a real eligible and genuinely incomplete build for W6 with physical card
-- reuse, the settled maintenance before W8's whole-saved-root snapshot, W8b
-- (Explore's fixed header over a scrolled body on a short UI, across
-- navigation), the Locked caption's real hover in W4 and a required catalog
-- row in W9.
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

-- Each player has a Dummy and a Lich King record on the same build, so its
-- build is listed under Explore's default "Require both DPS records" filter
-- (ViewProjections); W2 still ranks the sixteen Dummy records.
local players={}
for i=1,16 do players[i]={name='Player'..string.char(64+i),class=i%2==0 and 'MAGE' or 'PRIEST',dps={dummy=50000-i*1000,lk=52000-i*1000},locked=0} end
local fx=LF.New({players=players})
local H=F.Boot(fx:Install(F.Database()),function(h) F.OrbService(h) end)
for _=1,200 do H.Advance(.05,.05) end
C.setup(Nexus.StartupStatus().coreReady==true,'fixture: start-up reached core-ready')
G.UseFont(G.MODELS.default)
local function Quiet() return table.concat({#H.actions,#H.sent,tostring(Nexus.RecomputeStats().autoEnabled==true)},'/') end
-- The harness has no font engine: its font setters are no-ops. They are
-- observed here (each widget's last font object per setter, then the former
-- no-op), before any workspace window is built, so W7-W9 can read which font
-- object each widget was given. An observation only; no font is rendered.
local RM=G.RegionMethods()
local FONT_SETTERS={'SetFontObject','SetNormalFontObject','SetHighlightFontObject','SetDisabledFontObject'}
for _,setter in ipairs(FONT_SETTERS) do
 local prior=rawget(RM,setter)
 RM[setter]=function(self,font)
  self._seenFont=self._seenFont or {}
  self._seenFont[setter]=font
  if prior then return prior(self,font) end
 end
end
local function Font(r,setter) return r and r._seenFont and r._seenFont[setter or 'SetFontObject'] end
-- Every font a region outside `root` holds, in creation order (W8's guard
-- that one window's font pass leaves the others alone).
local function FontsOutside(root)
 local out={}
 local function Inside(r)
  local p=r
  for _=1,40 do
   if p==nil then return false end
   if p==root then return true end
   p=p:GetParent()
  end
  return false
 end
 for i,f in ipairs(H.frames) do
  for _,r in ipairs({f,unpack(f.regions or {})}) do
   if r._seenFont and not Inside(r) then
    for _,setter in ipairs(FONT_SETTERS) do
     if r._seenFont[setter] then out[#out+1]=i..':'..setter..'='..tostring(r._seenFont[setter]) end
    end
   end
  end
 end
 return table.concat(out,';')
end
-- A window's anchor in the form navigation and Details write (TOPLEFT of
-- UIParent's BOTTOMLEFT) answers GetLeft / GetTop from that anchor, as the
-- client resolves it; any other anchor answers the stated corner. The
-- harness otherwise answers 0 / 500 for every region.
local function Track(f,left,top,scale)
 f.GetLeft=function(self)
  local p=self.points[1]
  if p and p[1]=='TOPLEFT' and p[2]==UIParent and p[3]=='BOTTOMLEFT' then return p[4] end
  return left
 end
 f.GetTop=function(self)
  local p=self.points[1]
  if p and p[1]=='TOPLEFT' and p[2]==UIParent and p[3]=='BOTTOMLEFT' then return p[5] end
  return top
 end
 f.GetEffectiveScale=function() return scale or 1 end
end
local function Untrack(f) f.GetLeft,f.GetTop,f.GetEffectiveScale=nil,nil,nil end

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
  -- The checkbox itself, under the final common width (1040), with the
  -- longest Locked (n/m) caption and the default, 16 px and 2.0 font
  -- models: a hidden or tooltip-backed label must not hide a box that sits
  -- under My Builds. The box is where _fitAutoLock anchors it (no test
  -- re-anchor), and the Locked caption is cut, whole on its hover, when it
  -- would push the box there.
  local caption=locked:GetText()
  C.guard(f:GetWidth()==1040 and (Nexus.LayoutMetrics.WORKSPACE_WIDTH or 1040)==1040,'W4: Plan keeps the common 1040 width',f:GetWidth())
  for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.double}) do
   G.UseFont(model)
   for _,n in ipairs({6,8}) do
    locked:SetText(string.format('Locked (%d/%d):',n,n))
    f._fitAutoLock(n)
    local cr,lr,mr=G.Rect(check,f),G.Rect(label,f),G.Rect(myBuilds,f)
    local tag='W4 '..model.name..', '..n..' slots'
    C.expect(cr[3]<=mr[1]-8+0.5 and G.Apart(cr,mr) and f._autoLockClear==true,
     tag..': the Auto-manage checkbox ends 8 px left of My Builds (game)',G.Text(cr)..' / '..G.Text(mr))
    C.expect(not label:IsShown() or (lr[3]<=mr[1]-8+0.5 and lr[1]>=cr[3]),tag..': its label, when shown, lies between the box and My Builds',G.Text(lr))
    -- Owner-approved item 3 (#173): where the caption has no room beside the
    -- strip (larger text), the box and caption take their own line under it.
    -- Either way the box overlaps no slot.
    local sr=G.Rect(f._nexusLockedSlot(n),f)
    local clear=true
    for i=1,n do if not G.Apart(cr,G.Rect(f._nexusLockedSlot(i),f)) then clear=false end end
    C.expect(clear and (cr[1]>=sr[3]+6-0.5 or cr[2]>=sr[4]-0.5),
     tag..': the box stays at least 6 px right of the last slot, or on its own line under the strip, clear of every slot',G.Text(sr)..' / '..G.Text(cr))
    -- The caption's own hover (its real OnEnter), cut or not.
    local hit=f._lockedLabelHit
    local lines=hit and V.TooltipLines(hit:GetScript('OnEnter'),hit) or {}
    C.expect(hit~=nil and hit:IsShown() and lines[1]==locked:GetText(),
     tag..': hovering the Locked caption shows its whole text',tostring(lines[1])..' / '..locked:GetWidth())
   end
  end
  G.UseFont(G.MODELS.default)
  -- Correction 3 item 3: the hover does not depend on the client's width
  -- measurement. A measurement that fails, or one that reports only the
  -- clipped extent of an already narrowed caption, still leaves the whole
  -- caption on its hover, and the checkbox stays clear of My Builds.
  local hit=f._lockedLabelHit
  if C.setup(hit~=nil,'W4: fixture: the Locked caption\'s hover area') then
   for _,mode in ipairs({'failing','clipped'}) do
    locked:SetText('Locked (8/8):')
    locked:SetWidth(20)
    if mode=='failing' then locked.GetStringWidth=function() error('no width measurement') end
    else locked.GetStringWidth=function(self) return math.min(G.Length(V.Plain(self:GetText()))*G.model.char,self:GetWidth()) end end
    f._fitAutoLock(8)
    local lines=V.TooltipLines(hit:GetScript('OnEnter'),hit)
    C.expect(hit:IsShown() and lines[1]=='Locked (8/8):','W4: with a '..mode..' width measurement the Locked caption\'s hover has its whole text',lines[1])
    local cr,mr=G.Rect(check,f),G.Rect(myBuilds,f)
    C.guard(cr[3]<=mr[1]-8+0.5 and G.Apart(cr,mr),'W4: with a '..mode..' width measurement the checkbox stays 8 px left of My Builds',G.Text(cr)..' / '..G.Text(mr))
    locked.GetStringWidth=nil
   end
  end
  locked:SetText(caption)
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

-- The finish pass (CLAUDE_VISUAL_FINISH items A-D and the Explore owner-line
-- correction). EXPECT: predicted to fail at ce4e1f120 (fixed 445 Orb bands,
-- a cached pre-branch owner line, the window-wide font only, independently
-- centred titles and tabs, a cut save-result line without hover, an
-- ANCHOR_TOP hub tooltip over the panel). GUARD: no action, send, spend,
-- Auto or saved-data change; handlers, approval text and limits unchanged.

-- The visible height of a text in its box under the stated font model.
local function Content(fs)
 local text=V.Plain(fs:GetText() or '')
 if text=='' or not fs:IsShown() then return 0 end
 return math.min(fs:GetHeight(),G.Rows(text,fs:GetWidth(),G.model.char)*G.model.line)
end

C.scenario('W5b Orbs: the rows under Start take the room their text needs; no blank band over 16 px',function()
 local q=Quiet()
 local f=Nexus.OrbPanel.Show()
 if not C.setup(f~=nil and f.flowBands~=nil and f.approval~=nil,'W5b: fixture: the Orb window and its band flow') then return end
 Nexus.OrbPanel.Refresh()
 local approvalText=f.approval:GetText()
 local bands={}
 for _,fs in ipairs({f.startWhy,f.approval,f.usage,f.status,f.notice,f.closeNotice}) do
  local h=Content(fs)
  if h>0 then local r=G.Rect(fs,f);bands[#bands+1]={top=r[2],bottom=r[2]+h,text=V.Plain(fs:GetText())} end
 end
 for _,b in ipairs({f.cont,f.review}) do
  if b:IsShown() then local r=G.Rect(b,f);bands[#bands+1]={top=r[2],bottom=r[4],text=b:GetText()} end
 end
 local hr=G.Rect(f.help,f)
 bands[#bands+1]={top=hr[2],bottom=hr[4],text='buttons'}
 table.sort(bands,function(a,b) return a.top<b.top end)
 local sr=G.Rect(f.start,f)
 local worst,where=bands[1].top-sr[4],'Start row'
 for i=2,#bands do
  local gap=bands[i].top-math.max(bands[i-1].bottom,bands[i-1].top)
  if gap>worst then worst,where=gap,bands[i-1].text end
 end
 local tail=f:GetHeight()-hr[4]
 C.expect(worst<=16 and tail<=16,'W5b: no blank band over 16 px between Start, the rows, the buttons and the window bottom',
  string.format('%.0f after %s; %.0f below the buttons',worst,tostring(where),tail))
 C.guard(f.approval:GetHeight()>=34 and f.approval:GetText()==approvalText and approvalText:find('Start approves this maximum',1,true)~=nil,
  'W5b: the approval text keeps its 34 units and its words',f.approval:GetHeight())
 C.expect(f._bandsBottom~=nil and f._bandsBottom<=f:GetHeight() and f:GetHeight()<=445,'W5b: every row ends inside the window, at most the former 445',f:GetHeight())
 -- Start/Stop rework (2026-11-19): no Advanced exclusions; the closed window
 -- is the whole window. (Replaces the Advanced box geometry expectation.)
 C.expect(not f.advanced:IsShown() and not f.advancedToggle:IsShown(),'W5b: no Advanced box or toggle on the run page')
 Nexus.OrbPanel.Hide()
 C.guard(Quiet()==q and Nexus.OrbRuntime.Status().running~=true,'W5b: the band flow started, spent, sent and toggled nothing',Quiet())
end)

-- Correction 3 item 6: the whole run page flows, the upper rows included.
-- Every adjacent pair of visible sections (the Wishlist row, the targets,
-- the locked-targets line, the balance, the Start row, Start's reason, the
-- approval, usage, status, the notice row, the close notice and the
-- buttons) is at most 16 units apart, without overlap, and the window ends
-- at most 16 below the buttons: as the fixture reads it, with and without
-- locked targets, with long target text, with a refused Start and while
-- loading. The runtime read is wrapped for display only (a copy with the
-- stated progress, note or refusal); the approval text keeps its 34 units
-- and words and the locked-targets line its consequence. Nothing is
-- started, spent, sent or toggled. Font model: default; native NOT_RUN.
C.scenario('W5c Orbs: no blank band over 16 px anywhere on the run page, upper rows included',function()
 local q=Quiet()
 local f=Nexus.OrbPanel.Show()
 if not C.setup(f~=nil and f.flowBands~=nil and f.targets~=nil and f.permanent~=nil and f.balance~=nil and f.assigned~=nil,
  'W5c: fixture: the Orb window and its rows') then return end
 local R=Nexus.OrbRuntime
 local realStatus,realStartup=R.Status,Nexus.StartupStatus
 local LONG='Target progress note '..string.rep('with a long synthetic reason ',6)
 local function Sections()
  local out={}
  local function add(region,what,h)
   local r=G.Rect(region,f)
   out[#out+1]={rect={r[1],r[2],r[3],r[2]+(h or (r[4]-r[2]))},text=what}
  end
  add(f.plan,'Wishlist',Content(f.plan));add(f.assigned,'My Builds')
  for _,entry in ipairs({{f.targets,'targets'},{f.permanent,'locked targets'},{f.balance,'balance'},
   {f.startWhy,'Start reason'},{f.approval,'approval'},{f.usage,'usage'},{f.status,'status'},
   {f.notice,'notice'},{f.closeNotice,'close notice'}}) do
   local h=Content(entry[1])
   if h>0 then add(entry[1],entry[2],h) end
  end
  for _,b in ipairs({{f.limit,'maximum'},{f.max,'Max'},{f.start,'Start'},{f.pause,'Pause'},{f.resume,'Resume'},
   {f.stop,'Stop'},{f.cont,'Continue'},{f.review,'Review'},{f.help,'buttons'}}) do
   if b[1]:IsShown() then add(b[1],b[2]) end
  end
  return out
 end
 local function Check(tag)
  local s=Sections()
  table.sort(s,function(a,b) return a.rect[2]<b.rect[2] end)
  local worst,where,bottom=-math.huge,'',s[1].rect[4]
  for i=2,#s do
   local gap=s[i].rect[2]-bottom
   if gap>worst then worst,where=gap,s[i-1].text..' -> '..s[i].text end
   bottom=math.max(bottom,s[i].rect[4])
  end
  local hr=G.Rect(f.help,f)
  local tail=f:GetHeight()-hr[4]
  C.expect(worst<=16 and tail<=16,'W5c '..tag..': no blank band over 16 px from the Wishlist row to the window bottom',
   string.format('%.0f at %s; %.0f below the buttons',worst,where,tail))
  local overlaps={}
  for i=1,#s do for j=i+1,#s do
   if not G.Apart(s[i].rect,s[j].rect) then overlaps[#overlaps+1]=s[i].text..'/'..s[j].text end
  end end
  C.expect(#overlaps==0,'W5c '..tag..': no two sections overlap',table.concat(overlaps,', '))
  C.guard(f.approval:GetHeight()>=34 and (f.approval:GetText() or ''):find('Start approves this maximum',1,true)~=nil,
   'W5c '..tag..': the approval text keeps its 34 units and its words',f.approval:GetHeight())
 end
 local function With(change)
  R.Status=function(...)
   local s=realStatus(...)
   local c={}
   for k,v in pairs(s) do c[k]=v end
   change(c)
   return c
  end
  Nexus.OrbPanel.Refresh()
 end
 local ok,err=pcall(function()
  Nexus.OrbPanel.Refresh()
  Check('as the fixture reads it')
  With(function(c) c.progress={rolledMissing=3,permanentMissing=2} end)
  C.guard(V.Plain(f.permanent:GetText() or ''):find('Orbs cannot change locked Echo slots.',1,true)~=nil,
   'W5c: with locked targets their line keeps its consequence',f.permanent:GetText())
  Check('with locked targets')
  With(function(c) c.progress={rolledMissing=3,permanentMissing=0} end)
  if C.setup((f.permanent:GetText() or '')=='' and (f.targets:GetText() or '')~='','W5c: fixture: targets shown, no locked-targets line') then
   local tr,br=G.Rect(f.targets,f),G.Rect(f.balance,f)
   C.expect(br[2]-(tr[2]+Content(f.targets))<=16,'W5c: without locked targets the balance follows the targets line (no 50-unit band)',
    string.format('%.0f',br[2]-(tr[2]+Content(f.targets))))
  end
  Check('without locked targets')
  With(function(c)
   c.progress=nil
   local a={};for k,v in pairs(c.assignment or {}) do a[k]=v end
   a.state='ready';a.note=LONG;c.assignment=a
  end)
  C.setup(V.Plain(f.targets:GetText() or ''):find('Target progress unavailable',1,true)==1,'W5c: fixture: the long targets text',f.targets:GetText())
  Check('with long target text')
  With(function(c) c.canStart=false;c.startReason='Synthetic refusal: the assigned Wishlist is not ready.';c.running=false;c.pending=false end)
  C.setup(V.Plain(f.startWhy:GetText() or ''):find('^Start: ')~=nil,'W5c: fixture: Start says why it would not start',f.startWhy:GetText())
  Check('with a refused Start')
  R.Status=realStatus
  Nexus.StartupStatus=function() return {coreReady=false} end
  Nexus.OrbPanel.Refresh()
  C.setup(V.Plain(f.balance:GetText() or '')=='Orb balance: loading','W5c: fixture: the loading read',f.balance:GetText())
  Check('while loading')
 end)
 R.Status,Nexus.StartupStatus=realStatus,realStartup
 Nexus.OrbPanel.Refresh()
 Nexus.OrbPanel.Hide()
 C.setup(ok,'W5c: fixture: the scenario ran',err)
 C.guard(Quiet()==q and Nexus.OrbRuntime.Status().running~=true,'W5c: the measured flow started, spent, sent and toggled nothing',Quiet())
end)

-- Explore's owner line: a long owner on a build still waiting for its
-- Echoes is cut on the row; the card's own hover must show that final line,
-- the real waiting status included, and a reused card must show its new
-- build's line. The rows come from the real projection reader under the
-- default filters (every fixture build has both DPS records, so it is
-- listed); the first listed build is presented with a long, unestablished
-- owner. Its incompleteness is in the build the renderer itself resolves
-- (CommunityRenderer LoadBuild -> the Community controller's Build): while
-- "waiting", that read answers the catalog's own record in the shape of a
-- build whose full loadout has not arrived (no Echoes; loadoutAvailable
-- false, needsFullBuild true). The renderer, the card pool and the hover
-- are the production ones; the physical card that showed the waiting line
-- is checked again after the pool rebinds it.
C.scenario('W6 Explore: the hover owner line is the row as finally shown (waiting for Echoes), and a reused row refreshes it',function()
 local q=Quiet()
 local VP=Nexus.ViewProjections
 if not C.setup(type(VP)=='table' and type(VP.Builds)=='function' and type(VP.BuildsCurrent)=='function',
  'W6: fixture: the build projection reader') then return end
 -- The controller instance the renderer resolves builds through, read from
 -- the public facade's own upvalue (nothing is replaced by this read).
 local controller
 for i=1,60 do
  local name,value=debug.getupvalue(Nexus.CommunityBuilds.IsOwnBuild,i)
  if name==nil then break end
  if name=='ControllerInstance' and type(value)=='function' then controller=value() end
 end
 if not C.setup(type(controller)=='table' and type(rawget(controller,'Build'))=='function',
  'W6: fixture: the Community controller the renderer reads each build from') then return end
 local realRequest,realBuilds,realCurrent=rawget(VP,'RequestBuilds'),VP.Builds,VP.BuildsCurrent
 local realBuild=rawget(controller,'Build')
 local reader=realRequest or realBuilds
 local LONG=string.rep('Longowner',12)
 local target,mode
 VP.BuildsCurrent=function() return false end
 VP.RequestBuilds=function(filters)
  local rows,summary,err=reader(filters)
  if type(rows)~='table' then return rows,summary,err end
  local out={}
  for i,row in ipairs(rows) do
   local copy={}
   for k,v in pairs(row) do copy[k]=v end
   out[i]=copy
  end
  if out[1] then
   target=target or out[1].id
   for _,row in ipairs(out) do
    if row.id==target then row.displayAuthor=LONG;row.publicIdentityVerified=false end
   end
  end
  return out,summary
 end
 controller.Build=function(id,...)
  local b=realBuild(id,...)
  if mode~='waiting' or id~=target or type(b)~='table' then return b end
  local waiting={}
  for k,v in pairs(b) do waiting[k]=v end
  waiting.echoes={};waiting.lockedEchoes=nil;waiting.echoCount=0
  waiting.loadoutAvailable=false;waiting.needsFullBuild=true
  return waiting
 end
 local ok,err=pcall(function()
  Nexus.CommunityBuilds.Show()
  local function Bind(m)
   mode=m
   if Nexus.CommunityBuilds.MarkDataDirty then Nexus.CommunityBuilds.MarkDataDirty() end
   Nexus.CommunityBuilds.Refresh()
   for _=1,20 do H.Advance(.05,.05) end
   for _,c in ipairs(H.frames) do
    if c.buildId~=nil and c.buildId==target and c.author and c:IsShown() then return c end
   end
  end
  local card=Bind('complete')
  if not C.setup(card~=nil and target~=nil,'W6: fixture: a listed build is bound to a card',tostring(target)) then return end
  local resolved=realBuild(target)
  C.setup(type(resolved)=='table' and type(resolved.echoes)=='table' and #resolved.echoes>0,
   'W6: fixture: the catalog build the row resolves is complete',resolved and resolved.echoes and #resolved.echoes)
  local created=Nexus.CommunityBuilds.VirtualStats().created
  local completeLine=card.author:GetText() or ''
  C.setup(not V.Plain(completeLine):find('waiting for Echoes',1,true) and V.Plain(completeLine):find(LONG,1,true)~=nil,
   'W6: fixture: the complete row names its long owner',completeLine)
  local waiting=Bind('waiting')
  if not C.setup(waiting~=nil and V.Plain(waiting.author:GetText() or ''):find('waiting for Echoes',1,true)~=nil,
   'W6: fixture: the same build now waits for its Echoes',waiting and waiting.author:GetText()) then return end
  C.setup(G.Length(V.Plain(waiting.author:GetText()))*G.model.char>waiting.author:GetWidth(),'W6: fixture: the row cuts its owner line',waiting.author:GetWidth())
  local lines=V.TooltipLines(waiting:GetScript('OnEnter'),waiting)
  local tip=table.concat(lines,' | ')
  C.expect(tip:find('waiting for Echoes',1,true)~=nil and tip:find(LONG,1,true)~=nil,
   'W6: the hover shows the whole final line with the real waiting status',tip)
  local marked=V.Plain(completeLine):find('Owner not established',1,true)~=nil
  C.expect(not marked or (tip:find('Owner not established',1,true)~=nil and V.Plain(waiting.author:GetText()):find('Owner not established',1,true)~=nil),
   'W6: an owner that is not established is still said so, on the waiting row and its hover',tip)
  C.expect(not tip:find('Missing a DPS record',1,true) and not tip:find('Class not supplied',1,true)
   or V.Plain(waiting.author:GetText()):find('Missing a DPS record',1,true) or V.Plain(waiting.author:GetText()):find('Class not supplied',1,true),
   'W6: the hover carries no tag the waiting row does not show',tip)
  local again=Bind('complete')
  if C.setup(again~=nil,'W6: fixture: the build is complete again') then
   local after=table.concat(V.TooltipLines(again:GetScript('OnEnter'),again),' | ')
   C.expect(again._fullAuthor==again.author:GetText() and not after:find('waiting for Echoes',1,true),
    'W6: a re-bound row shows its new line on hover, not the earlier waiting one',after)
  end
  -- Physical reuse: no card frame was created by the two rebinds, so every
  -- row shown is a pooled card, and the very card object that showed the
  -- waiting line now shows (and hovers) its current build's line.
  C.expect(Nexus.CommunityBuilds.VirtualStats().created==created,'W6: the rebinds reused the pooled cards (no new card frame)',
   tostring(created)..' -> '..tostring(Nexus.CommunityBuilds.VirtualStats().created))
  print('OBSERVED','W6 the waiting card '..(waiting==again and 'shows the same build again' or 'was rebound to build '..tostring(waiting.buildId)))
  local reused=table.concat(V.TooltipLines(waiting:GetScript('OnEnter'),waiting),' | ')
  C.expect(waiting:IsShown() and waiting._fullAuthor==waiting.author:GetText()
   and not V.Plain(waiting.author:GetText() or ''):find('waiting for Echoes',1,true) and not reused:find('waiting for Echoes',1,true)
   and (waiting.buildId==target or not reused:find(LONG,1,true)),
   'W6: the physical card that showed the waiting line hovers its current line, not the earlier one',reused)
  C.guard(again==nil or again:GetScript('OnClick')~=nil,'W6: the row keeps its own click (select only)')
 end)
 controller.Build=realBuild
 VP.RequestBuilds,VP.Builds,VP.BuildsCurrent=realRequest,realBuilds,realCurrent
 if Nexus.CommunityBuilds.MarkDataDirty then Nexus.CommunityBuilds.MarkDataDirty() end
 Nexus.CommunityBuilds.Refresh()
 if NexusCommunityBuildsFrame then NexusCommunityBuildsFrame:Hide() end
 C.setup(ok,'W6: fixture: the scenario ran',err)
 C.guard(Quiet()==q,'W6: binding and hovering acted, sent and toggled nothing',Quiet())
end)

-- Explore's browse and action rows: every control's label in each button
-- state, the search text and hint, the check box label and the page line in
-- the Nexus normal font; the two row headings in the Nexus small font. Set
-- per widget on each layout pass (a new UI size re-lays the window); no
-- other window's widgets are given a font by that pass.
C.scenario('W7 Explore: one font for the control rows, per widget, on every layout; other windows untouched',function()
 local q=Quiet()
 local LM=Nexus.LayoutMetrics
 Nexus.CommunityBuilds.Show()
 for _=1,20 do H.Advance(.05,.05) end
 local f=NexusCommunityBuildsFrame
 if not C.setup(f~=nil and f:IsShown(),'W7: fixture: Explore is open') then return end
 local w,h=UIParent:GetWidth(),UIParent:GetHeight()
 local outside=FontsOutside(f)
 UIParent:SetSize(1180,760)
 Nexus.CommunityBuilds.Refresh()
 for _=1,10 do H.Advance(.05,.05) end
 local rows=f._nexusControlFonts
 if C.setup(type(rows)=='table' and #rows.buttons>=10 and #rows.texts>=5 and #rows.headings==2,'W7: fixture: the control rows',rows and #rows.buttons) then
  local N,S=LM.FontObject('normal'),LM.FontObject('small')
  local odd={}
  for i,b in ipairs(rows.buttons) do
   for _,setter in ipairs({'SetNormalFontObject','SetHighlightFontObject','SetDisabledFontObject'}) do
    if Font(b,setter)~=N then odd[#odd+1]='button '..i..' '..setter..'='..tostring(Font(b,setter)) end
   end
  end
  for i,t in ipairs(rows.texts) do if Font(t)~=N then odd[#odd+1]='text '..i..'='..tostring(Font(t)) end end
  for i,t in ipairs(rows.headings) do if Font(t)~=S then odd[#odd+1]='heading '..i..'='..tostring(Font(t)) end end
  C.expect(#odd==0,'W7: every control, its states, the texts and the headings have the Nexus fonts',table.concat(odd,', '))
  C.expect(Font(f._titleText)=='GameFontNormalLarge','W7: the title keeps the shared header\'s title font',Font(f._titleText))
 end
 C.guard(FontsOutside(f)==outside,'W7: the font pass gave no widget of another window a font')
 UIParent:SetSize(w,h)
 Nexus.CommunityBuilds.Refresh()
 f:Hide()
 C.guard(Quiet()==q,'W7: laying out Explore acted, sent and toggled nothing',Quiet())
end)

-- The shared header and its place across navigation (item A). The header's
-- tabs, Help, title and Reference stand at LayoutMetrics.WorkspaceHeader's
-- anchors from each window's top-left (Reference from its top-right), and
-- navigating keeps the window's top-left on screen: the tabs stay put. A
-- refused or loading destination moves nothing. Real tab clicks
-- (FullUIWorkspaces.NavigateFrom); window corners are read from their real
-- anchors (Track). Native pixels and effective scale are NOT_RUN.
local function Title(f)
 if f==_G.NexusCommunityBuildsFrame then return f._titleText end
 if f==_G.NexusLeaderboardFrame then return f._title end
 -- Plan's title: "Plan / Wishlist Editor", then "Plan / Create Wishlist" or
 -- "Plan / Edit Wishlist" after a refresh.
 for _,r in ipairs(f.regions or {}) do if r.kind=='FontString' and V.Plain(r:GetText() or ''):find('^Plan / ') then return r end end
end
local function PointsText(f)
 local out={}
 for i,p in ipairs(f.points) do
  local parts={}
  for j=1,5 do parts[j]=tostring(p[j]) end
  out[i]=table.concat(parts,',')
 end
 return table.concat(out,';')
end
local function Header(f)
 local out,tabs={},f._workspaceTabs or {}
 for _,key in ipairs({'plan','builds','records'}) do out[key]=tabs[key] and G.Rect(tabs[key],f) end
 out.help=f._helpNav and G.Rect(f._helpNav,f)
 out.reference=f._referenceNav and G.Rect(f._referenceNav,f)
 local t=Title(f);out.title=t and G.Rect(t,f)
 return out
end
local function AtAnchors(f,tag)
 local hd,box=Header(f),Nexus.LayoutMetrics.WorkspaceHeader(f:GetWidth()).boxes
 local bad={}
 for _,key in ipairs({'plan','builds','records','help','title'}) do
  local r,b=hd[key],box[key]
  if not (r and math.abs(r[1]-b.x)<0.5 and math.abs(r[2]-b.y)<0.5 and math.abs(r[3]-r[1]-b.w)<0.5 and math.abs(r[4]-r[2]-b.h)<0.5) then
   bad[#bad+1]=key..(r and G.Text(r) or ' missing')
  end
 end
 local rr=hd.reference
 if not (rr and math.abs(rr[3]-(f:GetWidth()-40))<0.5 and math.abs(rr[2]-box.reference.y)<0.5) then bad[#bad+1]='reference'..(rr and G.Text(rr) or ' missing') end
 if hd.title and hd.reference and not (G.Apart(hd.title,hd.reference) and G.Apart(hd.title,hd.help)) then bad[#bad+1]='title overlaps' end
 C.expect(#bad==0,tag..': the tabs, Help, title and Reference stand at the shared header\'s anchors',table.concat(bad,', '))
 local t=Title(f)
 C.expect(Font(t)=='GameFontNormalLarge',tag..': the title has the shared title font',tostring(Font(t)))
 return hd
end
local function Corner(f)
 local p=f.points[1]
 if not (p and #f.points==1 and p[1]=='TOPLEFT' and p[2]==UIParent and p[3]=='BOTTOMLEFT') then return nil end
 return p[4],p[5]
end
local function Tab(f,key) return f._workspaceTabs and f._workspaceTabs[key] end

-- Correction 3 item 5 (the W8 saved-state diagnosis). The fixture's own
-- saved-data maintenance (DataCompaction and LegacyQualificationRepair,
-- unchanged from the installed base) still has work pending when W8 starts:
-- three idle synthetic seconds alone pool the bundle's evidence, advance its
-- transaction generation and complete the repair for the current DPS
-- revision. A whole-saved-root comparison around navigation means something
-- only once that work is done. This waits, bounded by the harness clock,
-- until compaction is not pending; the repair has no pass or follow-up
-- pending and has completed the current DPS revision, in this session and
-- in its saved record; and the whole saved root has then stayed
-- byte-identical for three more synthetic seconds. It asserts that state as
-- SETUP. Nothing is excluded from the later whole-root comparison.
local function SettleMaintenance(tag)
 local DC,LR,RV,S=Nexus.DataCompaction,Nexus.LegacyQualificationRepair,Nexus.Revisions,Nexus.Scheduler
 local function Facts()
  local c=DC and DC.Stats and DC.Stats(NexusDB) or {}
  local r=LR and LR.Stats and LR.Stats() or {}
  local revision=RV and RV.Get and RV.Get(RV.DPS_CHANGED)
  local record=type(NexusDB.legacyQualificationRepair)=='table' and NexusDB.legacyQualificationRepair or {}
  local followUp=S and S.Pending and S.Pending('legacy-qualification-repair.follow-up') or false
  local done=c.pending~=true and r.pending~=true and r.followUpPending~=true and not followUp
   and revision~=nil and tonumber(r.completedDpsRevision)==tonumber(revision)
   and tonumber(record.completedDpsRevision)==tonumber(revision)
  return done,string.format('compaction pending=%s phase=%s; repair pending=%s follow-up=%s/%s completed=%s saved=%s; DPS revision=%s',
   tostring(c.pending),tostring(c.phase),tostring(r.pending),tostring(r.followUpPending),tostring(followUp),
   tostring(r.completedDpsRevision),tostring(record.completedDpsRevision),tostring(revision))
 end
 local stable,last,facts=0,nil,''
 for _=1,1200 do
  local done
  done,facts=Facts()
  if done then
   local now=F.Serialize(NexusDB)
   if now==last then stable=stable+1 else stable=0 end
   last=now
  else
   stable,last=0,nil
  end
  if stable>=60 then break end
  H.Advance(.05,.05)
 end
 return C.setup(stable>=60,tag..': fixture: saved-data maintenance (compaction, the repair and its current-revision follow-up) settled before the snapshot',facts)
end

C.scenario('W8 Plan, Explore and Records: one header at fixed anchors; navigation keeps the place',function()
 local q=Quiet()
 if not SettleMaintenance('W8') then return end
 local saved=F.Serialize(NexusDB)
 local LM,W=Nexus.LayoutMetrics,Nexus.FullUIWorkspaces
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 UIParent:SetSize(1366,768)
 local ok,err=pcall(function()
  Nexus.WishlistEditor.Show()
  local plan=NexusEditorFrame
  if not C.setup(plan and plan:IsShown(),'W8: fixture: Plan is open') then return end
  -- A top-left corner every workspace keeps whole on a 1366 x 768 UI
  -- (Plan is 680 high, Explore and Records at most 640).
  plan:ClearAllPoints();plan:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',200,760)
  Track(plan,200,760,1)
  local planHeader=AtAnchors(plan,'W8 Plan')
  -- Plan -> Explore by Plan's own tab.
  Tab(plan,'builds'):Click()
  for _=1,20 do H.Advance(.05,.05) end
  local explore=NexusCommunityBuildsFrame
  if not C.setup(explore and explore:IsShown() and not plan:IsShown(),'W8: fixture: Explore opened from Plan\'s tab') then return end
  local x,y=Corner(explore)
  C.expect(x==200 and y==760,'W8: Explore opens with its top-left where Plan\'s was',tostring(x)..','..tostring(y))
  Track(explore,0,500,1)
  local exploreHeader=AtAnchors(explore,'W8 Explore')
  local same=true
  for _,key in ipairs({'plan','builds','records','help','title'}) do
   local a,b=planHeader[key],exploreHeader[key]
   if not (a and b and math.abs(a[1]-b[1])<0.5 and math.abs(a[2]-b[2])<0.5) then same=false end
  end
  C.expect(same,'W8: Plan -> Explore: the tabs, Help and title stay at the same screen place')
  -- Explore -> Records.
  Tab(explore,'records'):Click()
  for _=1,20 do H.Advance(.05,.05) end
  local records=NexusLeaderboardFrame
  if not C.setup(records and records:IsShown() and not explore:IsShown(),'W8: fixture: Records opened from Explore\'s tab') then return end
  x,y=Corner(records)
  C.expect(x==200 and y==760 and records:GetWidth()==(LM.WORKSPACE_WIDTH or 1040),'W8: Records opens at the same top-left, at the common width',tostring(x)..','..tostring(y))
  Track(records,0,500,1)
  AtAnchors(records,'W8 Records')
  -- Records -> Plan, at another window scale: the corner is kept in screen
  -- units (0.9 x 200 = 180 and 0.9 x 760 = 684 units of a scale-1 window).
  records.GetEffectiveScale=function() return 0.9 end
  Tab(records,'plan'):Click()
  x,y=Corner(plan)
  C.expect(plan:IsShown() and x~=nil and math.abs(x-180)<0.01 and math.abs(y-684)<0.01,
   'W8: a different window scale keeps the corner on screen, in screen units',tostring(x)..','..tostring(y))
  records.GetEffectiveScale=function() return 1 end
  AtAnchors(plan,'W8 Plan again')
  -- A corner the destination cannot keep whole is kept on screen.
  plan:ClearAllPoints();plan:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',1300,760)
  Tab(plan,'records'):Click()
  x,y=Corner(records)
  C.expect(records:IsShown() and x~=nil and x>=0 and x+records:GetWidth()<=1366+0.01 and y<=768 and y-records:GetHeight()>=-0.01,
   'W8: near the screen edge the destination is kept whole on screen',tostring(x)..','..tostring(y))
  -- Refused: the destination stays closed and the source keeps its place.
  Tab(records,'plan'):Click()
  plan:ClearAllPoints();plan:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',240,690)
  records:Hide()
  local realShow=Nexus.Leaderboard.Show
  Nexus.Leaderboard.Show=function() return false,'refused for this check' end
  local navOk,why=W.NavigateFrom(plan,'records')
  Nexus.Leaderboard.Show=realShow
  x,y=Corner(plan)
  C.expect(navOk==false and plan:IsShown() and not records:IsShown() and x==240 and y==690,
   'W8: a refused destination leaves Plan open where it was',tostring(why))
  -- Loading: the shared-data window stands in for Explore; nothing moves.
  local existing=_G.NexusSharedStartupFrame
  local loading=existing or CreateFrame('Frame',nil,UIParent)
  local wasShown=existing and existing:IsShown()
  local before=PointsText(explore)
  local realExplore=Nexus.CommunityBuilds.Show
  Nexus.CommunityBuilds.Show=function() _G.NexusSharedStartupFrame=loading;loading:Show();return false,'pending' end
  local lOk,lWhy=W.NavigateFrom(plan,'builds')
  Nexus.CommunityBuilds.Show=realExplore
  if existing then if not wasShown then loading:Hide() end else _G.NexusSharedStartupFrame=nil;loading:Hide() end
  -- The real loading window would close Plan; this stand-in does not, so
  -- the draft protection it entered is released here.
  if Nexus.WishlistEditor.CancelWorkspaceSuspend then Nexus.WishlistEditor.CancelWorkspaceSuspend() end
  x,y=Corner(plan)
  C.expect(lOk==true and lWhy=='loading' and PointsText(explore)==before and x==240 and y==690,
   'W8: a loading transition reports loading and moves no window',tostring(lWhy))
  -- A narrower UI gives Explore a narrower window; the left-anchored header
  -- keeps its places and Reference keeps its distance from the right.
  plan:Hide()
  UIParent:SetSize(960,768)
  Nexus.CommunityBuilds.Show()
  for _=1,20 do H.Advance(.05,.05) end
  if C.setup(explore:IsShown(),'W8: fixture: Explore at a 960 px UI') then
   C.setup(explore:GetWidth()<1040,'W8: fixture: Explore is narrower there',explore:GetWidth())
   AtAnchors(explore,'W8 Explore at 960')
   explore:Hide()
  end
  -- Reopening a window directly keeps the same header.
  Nexus.Leaderboard.Show()
  AtAnchors(records,'W8 Records reopened')
  records:Hide()
 end)
 for _,name in ipairs({'NexusEditorFrame','NexusCommunityBuildsFrame','NexusLeaderboardFrame'}) do
  local f=_G[name]
  if f then Untrack(f);f:Hide() end
 end
 UIParent:SetSize(w0,h0)
 C.setup(ok,'W8: fixture: the scenario ran',err)
 C.guard(F.Serialize(NexusDB)==saved,'W8: navigating and placing saved nothing')
 C.guard(Quiet()==q,'W8: navigation acted, sent and toggled nothing',Quiet())
end)

-- Correction 3 item 1: Explore's header stays fixed while its body scrolls.
-- On a short UI (1366 x 480) Explore's layout is taller than its window, so
-- its body scrolls. The real mouse-wheel handler of the body (and the real
-- bar) move it to a nonzero scroll and to the end of its range; the title,
-- the tabs, Help and Reference stay where they were, at the shared anchors,
-- above the body viewport, and the body moves by exactly the scroll. After
-- scrolling, Explore -> Records -> Explore -> Plan by real tab clicks keeps
-- the window's top-left and the header's screen place, and a re-entered
-- Explore scrolls with the same fixed header. Corners are read from real
-- anchors (Track). Native pixels, clipping and wheel delivery are NOT_RUN.
C.scenario('W8b Explore on a short screen: the header stays put while the body scrolls, and across navigation',function()
 local q=Quiet()
 if not SettleMaintenance('W8b') then return end
 local saved=F.Serialize(NexusDB)
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local function Same(a,b)
  for _,key in ipairs({'plan','builds','records','help','reference','title'}) do
   local r,s=a[key],b[key]
   if not (r and s) then return false,key..' missing' end
   for i=1,4 do if math.abs(r[i]-s[i])>0.5 then return false,key..' '..G.Text(r)..' / '..G.Text(s) end end
  end
  return true
 end
 local function SamePlace(a,b)
  for _,key in ipairs({'plan','builds','records','help','title'}) do
   local r,s=a[key],b[key]
   if not (r and s and math.abs(r[1]-s[1])<0.5 and math.abs(r[2]-s[2])<0.5) then return false,key end
  end
  return true
 end
 local ok,err=pcall(function()
  UIParent:SetSize(1366,480)
  Nexus.CommunityBuilds.Show()
  for _=1,20 do H.Advance(.05,.05) end
  local explore=NexusCommunityBuildsFrame
  if not C.setup(explore and explore:IsShown(),'W8b: fixture: Explore is open on a 1366 x 480 UI') then return end
  explore:ClearAllPoints();explore:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',150,480)
  Track(explore,0,500,1)
  local layout=explore._responsiveLayout
  local scroll,content,bar=explore._contentScroll,explore._content,explore._contentBar
  local range=type(layout)=='table' and tonumber(layout.scrollRange) or 0
  if not C.setup(scroll and content and bar and scroll.scrollChild==content and range>0 and bar:IsShown(),
   'W8b: fixture: the layout is taller than the window, so the body scrolls',range) then return end
  C.guard(explore:GetHeight()<=480-24,'W8b: the window stays inside the short UI with its margin',explore:GetHeight())
  local wheel=scroll:GetScript('OnMouseWheel')
  if not C.setup(wheel~=nil,'W8b: fixture: the body\'s own mouse-wheel handler') then return end
  wheel(scroll,1000)
  local before=AtAnchors(explore,'W8b Explore at scroll 0')
  local view=G.Rect(scroll,explore)
  local lowest=0
  for _,r in pairs(before) do lowest=math.max(lowest,r[4]) end
  C.expect(lowest<=view[2]+0.5 and view[2]>0 and math.abs(view[4]-explore:GetHeight())<0.5 and view[1]==0,
   'W8b: the header ends above the body viewport, which fills the window below it',lowest..' / '..G.Text(view))
  local body0=G.Rect(explore._searchBox,explore)
  -- Three notches down through the real wheel handler.
  for _=1,3 do wheel(scroll,-1) end
  local at=scroll:GetVerticalScroll()
  if not C.setup(at>0 and at<=range and bar:GetValue()==at,'W8b: fixture: the wheel scrolled the body',at) then return end
  local same,why=Same(before,Header(explore))
  C.expect(same,'W8b: at a nonzero scroll the title, tabs, Help and Reference stand where they were',why)
  AtAnchors(explore,'W8b Explore scrolled '..at)
  local body1=G.Rect(explore._searchBox,explore)
  C.guard(math.abs((body0[2]-body1[2])-at)<0.5,'W8b: the body moved by exactly the scroll',(body0[2]-body1[2])..' / '..at)
  -- To the end of the range through the real bar.
  bar:SetValue(range)
  local changed=bar:GetScript('OnValueChanged')
  if changed then changed(bar,range) end
  same,why=Same(before,Header(explore))
  C.expect(scroll:GetVerticalScroll()==range and same,'W8b: at the end of the range the header still stands where it was',why)
  local list=G.Rect(explore._listClip,explore)
  C.guard(list[4]<=explore:GetHeight()+0.5,'W8b: at the end of the range the list ends inside the window',G.Text(list))
  wheel(scroll,-1)
  -- Out of the scrolled Explore to Records by its tab.
  Tab(explore,'records'):Click()
  for _=1,20 do H.Advance(.05,.05) end
  local records=NexusLeaderboardFrame
  if not C.setup(records and records:IsShown() and not explore:IsShown(),'W8b: fixture: Records opened from the scrolled Explore\'s tab') then return end
  local x,y=Corner(records)
  C.expect(x==150 and y==480,'W8b: Records opens with its top-left where the scrolled Explore\'s was',tostring(x)..','..tostring(y))
  Track(records,0,500,1)
  local rh=AtAnchors(records,'W8b Records after the scrolled Explore')
  same,why=SamePlace(before,rh)
  C.expect(same,'W8b: scrolled Explore -> Records: the tabs, Help and title stay at the same screen place',why)
  -- Back into Explore by Records' tab; it scrolls again under the same header.
  Tab(records,'builds'):Click()
  for _=1,20 do H.Advance(.05,.05) end
  if not C.setup(explore:IsShown() and not records:IsShown(),'W8b: fixture: Explore opened again from Records\' tab') then return end
  x,y=Corner(explore)
  C.expect(x==150 and y==480,'W8b: Explore opens again at the same top-left',tostring(x)..','..tostring(y))
  local again=explore._responsiveLayout
  local now=scroll:GetVerticalScroll()
  C.guard(type(again)=='table' and now>=0 and now<=(tonumber(again.scrollRange) or 0),'W8b: the re-entered body\'s scroll is inside its range',now)
  wheel(scroll,1000);wheel(scroll,-1);wheel(scroll,-1)
  same,why=Same(before,Header(explore))
  C.expect(scroll:GetVerticalScroll()>0 and same,'W8b: the re-entered Explore scrolls under the same fixed header',why)
  -- Out to Plan by Explore's tab, still scrolled.
  Tab(explore,'plan'):Click()
  for _=1,20 do H.Advance(.05,.05) end
  local plan=NexusEditorFrame
  if not C.setup(plan and plan:IsShown() and not explore:IsShown(),'W8b: fixture: Plan opened from the scrolled Explore\'s tab') then return end
  x,y=Corner(plan)
  C.expect(x==150 and y==480,'W8b: Plan opens at the scrolled Explore\'s top-left',tostring(x)..','..tostring(y))
  local ph=AtAnchors(plan,'W8b Plan after the scrolled Explore')
  same,why=SamePlace(before,ph)
  C.expect(same,'W8b: scrolled Explore -> Plan: the tabs, Help and title stay at the same screen place',why)
 end)
 for _,name in ipairs({'NexusEditorFrame','NexusCommunityBuildsFrame','NexusLeaderboardFrame'}) do
  local f=_G[name]
  if f then Untrack(f);f:Hide() end
 end
 local explore=NexusCommunityBuildsFrame
 if explore and explore._contentScroll then
  local wheel=explore._contentScroll:GetScript('OnMouseWheel')
  if wheel then wheel(explore._contentScroll,1000) end
 end
 UIParent:SetSize(w0,h0)
 C.setup(ok,'W8b: fixture: the scenario ran',err)
 C.guard(F.Serialize(NexusDB)==saved,'W8b: scrolling, navigating and placing saved nothing')
 C.guard(Quiet()==q,'W8b: scrolling and navigation acted, sent and toggled nothing',Quiet())
end)

-- Plan clarity (item C): the save-result line's hover always repeats the
-- whole line; the planned-copy footer keeps its whole text on hover with
-- 125% text; a catalog row's cut status column is repeated in its tooltip;
-- - and + are 22x22 with the large glyph fonts and the remove X keeps its
-- 22x22 click area with larger art; each says what it does and that nothing
-- is saved.
C.scenario('W9 Plan: full status and footer text, legible steppers with unchanged click areas',function()
 local q=Quiet()
 local saved=F.Serialize(NexusDB)
 Nexus.WishlistEditor.Show()
 local f=NexusEditorFrame
 if not C.setup(f~=nil and f:IsShown(),'W9: fixture: Plan is open') then return end
 -- The save-result row is built with the window (EnsureSaveResultRow).
 local text,hover=f._saveResultText,f._saveResultHover
 if C.setup(text~=nil and hover~=nil and hover:GetScript('OnEnter')~=nil,'W9: fixture: the save-result row') then
  local was,wasShown,hoverShown,detail=text:GetText(),text:IsShown(),hover:IsShown(),f._saveResultDetail
  local whole='Saved and assigned to '..string.rep('a long Saved Build name ',6)..'- nothing else changed'
  text:SetText(whole);text:Show();hover:Show()
  f._saveResultDetail=nil
  local lines=V.TooltipLines(hover:GetScript('OnEnter'),hover)
  C.expect(lines[1]==whole,'W9: the save-result hover repeats the whole line even without detail lines',lines[1])
  f._saveResultDetail={'Detail one'}
  lines=V.TooltipLines(hover:GetScript('OnEnter'),hover)
  C.guard(lines[1]==whole and lines[2]=='Detail one','W9: with details the whole line comes first, then each detail',table.concat(lines,' | '))
  text:SetText('')
  lines=V.TooltipLines(hover:GetScript('OnEnter'),hover)
  C.guard(#lines==0,'W9: an empty result line shows no tooltip',#lines)
  f._saveResultDetail=detail
  text:SetText(was or '')
  if not wasShown then text:Hide() end
  if not hoverShown then hover:Hide() end
 end
 local footerHit=f._pickFooterHit
 if C.expect(footerHit~=nil and footerHit._nexusText~=nil,'W9: the planned-copy footer has a full-text hover') then
  local footer=footerHit._nexusText
  local was,wasShown=footer:GetText(),footer:IsShown()
  G.UseFont(G.MODELS.px16)
  local long='Planned: 61 of 79 rolled copies  -  6 of 6 locked copies  -  2 Echoes over their copy limit'
  footer:SetText(long);footer:Show()
  C.setup(G.Rows(long,footer:GetWidth(),G.model.char)*G.model.line>footer:GetHeight(),'W9: fixture: the counts need more than the footer box',footer:GetHeight())
  local lines=V.TooltipLines(footerHit:GetScript('OnEnter'),footerHit)
  C.expect(lines[1]==long,'W9: with larger text the footer\'s whole counts are on its hover',lines[1])
  G.UseFont(G.MODELS.default)
  footer:SetText(was)
  if not wasShown then footer:Hide() end
 end
 local row
 for _,c in ipairs(H.frames) do
  if c.minus and c.plus and c.remove and c.text then row=c;break end
 end
 if C.setup(row~=nil,'W9: fixture: a Selected Echoes row') then
  C.expect(row.remove:GetWidth()==22 and row.remove:GetHeight()==22 and row.remove._nexusArtSize==28,
   'W9: the remove X keeps its 22x22 click area and draws larger art',row.remove:GetWidth()..'x'..row.remove:GetHeight())
  C.expect(row.minus:GetWidth()==22 and row.minus:GetHeight()==22 and row.plus:GetWidth()==22 and row.plus:GetHeight()==22
   and Font(row.minus,'SetNormalFontObject')=='GameFontNormalLarge' and Font(row.plus,'SetNormalFontObject')=='GameFontNormalLarge'
   and Font(row.plus,'SetDisabledFontObject')=='GameFontDisableLarge',
   'W9: - and + are 22x22 with the large glyph fonts',tostring(Font(row.minus,'SetNormalFontObject')))
  local rr={0,0,row:GetWidth(),row:GetHeight()}
  local m,p,x=G.Rect(row.minus,row),G.Rect(row.plus,row),G.Rect(row.remove,row)
  C.expect(G.Apart(m,p) and G.Apart(p,x) and G.Apart(m,x) and G.Inside(m,rr,1) and G.Inside(p,rr,1) and G.Inside(x,rr,1),
   'W9: the three click areas are apart and inside the row',G.Text(m)..' '..G.Text(p)..' '..G.Text(x))
  for _,entry in ipairs({{row.minus,'One copy fewer'},{row.plus,'One copy more'},{row.remove,'Remove from the plan'}}) do
   local lines=V.TooltipLines(entry[1]:GetScript('OnEnter'),entry[1])
   C.expect(lines[1]==entry[2] and (lines[2] or ''):find('Nothing is saved until you save the Wishlist',1,true)~=nil,
    'W9: '..entry[2]..' says what it does and that nothing is saved',table.concat(lines,' | '))
  end
 end
 -- A catalog row's status column (110 units) is repeated in its tooltip.
 -- The row is one of this Plan window's own catalog rows (the fixture's
 -- harness Echoes list there with at least their quality as status); the
 -- scenario requires it rather than passing without it.
 local function InPlan(r)
  local p=r
  for _=1,10 do
   if p==nil then return false end
   if p==f then return true end
   p=p:GetParent()
  end
  return false
 end
 local catalog
 for _,c in ipairs(H.frames) do
  if c.status and c.data and c.icon and c.text and c:IsShown() and InPlan(c) and (c.status:GetText() or '')~='' then catalog=c;break end
 end
 if C.setup(catalog~=nil,'W9: fixture: a listed catalog row with its status in Plan') then
  local lines=V.TooltipLines(catalog:GetScript('OnEnter'),catalog)
  local found=false
  for _,l in ipairs(lines) do if l==catalog.status:GetText() then found=true end end
  C.expect(found,'W9: a catalog row\'s tooltip repeats its whole status',catalog.status:GetText())
 end
 f:Hide()
 C.guard(F.Serialize(NexusDB)==saved and Quiet()==q,'W9: hovering and fitting saved, acted, sent and toggled nothing',Quiet())
end)

-- The hub tooltip (item D): beside the panel, never over it, with every
-- line whole; right when the screen has room, else left, else above, else
-- below; with no room anywhere it stays right and the client keeps it on
-- screen. The panel's screen box is stated per case.
C.scenario('W10 the hub tooltips stand outside the panel with their whole text',function()
 local q=Quiet()
 local P=Nexus.Panel
 P.Show();H.Advance(.2)
 local saved=F.Serialize(NexusDB)
 local panel=NexusPanel
 local hub=panel and panel._orbsHubBtn
 if not C.setup(panel and panel:IsShown() and hub~=nil and type(P.ShowHubTooltip)=='function','W10: fixture: the panel and its Orbs hub') then return end
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local pw,ph=panel:GetWidth(),panel:GetHeight()
 local function At(l,t)
  panel.GetLeft=function() return l end;panel.GetRight=function() return l+pw end
  panel.GetTop=function() return t end;panel.GetBottom=function() return t-ph end
 end
 local tipH=GameTooltip:GetHeight()
 local cases={
  {'room on the right',1366,768,300,600,'right'},
  {'at the right edge',1366,768,1366-pw,600,'left'},
  {'no room at either side',pw+20,768,10,500,'above'},
  {'at the top, no side room',pw+20,768,10,768,'below'},
 }
 for _,case in ipairs(cases) do
  UIParent:SetSize(case[2],case[3]);At(case[4],case[5])
  local lines=V.TooltipLines(function() P.ShowHubTooltip('orbs',hub) end)
  local tr=G.Rect(GameTooltip,panel)
  C.expect(P._hubTipPlacement==case[6] and G.Apart(tr,{0,0,pw,ph}),'W10 '..case[1]..': the tooltip stands '..case[6]..' of the panel, apart from it',
   tostring(P._hubTipPlacement)..' '..G.Text(tr))
  local want=P.HubTooltipLines('orbs')
  C.expect(#want>0 and table.concat(lines,'\n')==table.concat(want,'\n'),'W10 '..case[1]..': every line is shown',#lines)
 end
 -- A tooltip taller than any free side: right, kept on screen by the client.
 GameTooltip:SetHeight(900);UIParent:SetSize(pw+20,768);At(10,500)
 P.ShowHubTooltip('orbs',hub)
 C.expect(P._hubTipPlacement=='right','W10: with no room anywhere it stays right of the panel',P._hubTipPlacement)
 GameTooltip:SetHeight(tipH)
 for _,kind in ipairs({'plan','explore'}) do
  UIParent:SetSize(1366,768);At(300,600)
  P.ShowHubTooltip(kind,hub)
  C.expect(G.Apart(G.Rect(GameTooltip,panel),{0,0,pw,ph}),'W10: the '..kind..' hub tooltip stands outside the panel too')
 end
 panel.GetLeft,panel.GetRight,panel.GetTop,panel.GetBottom=nil,nil,nil,nil
 GameTooltip:Hide()
 UIParent:SetSize(w0,h0)
 C.guard(not (NexusOrbPanel and NexusOrbPanel:IsShown()),'W10: hovering a hub opens nothing')
 C.guard(F.Serialize(NexusDB)==saved and Quiet()==q,'W10: hovering the hubs saved, acted, sent, spent and toggled nothing',Quiet())
end)

C.guard(#H.actions==0,'no game action anywhere in this test',#H.actions)
C.finish('(opaque bases and primary seam; Records title/scope/prompt/cue; Explore diagnostics on hover; Plan search/Save/label/checkbox; Orb Start reason and measured bands, upper rows included; Explore owner hover with card reuse and fonts; shared header and navigation place; Explore fixed header over a scrolled body; Plan clarity; hub tooltip; offline model only, native NOT_RUN)')
