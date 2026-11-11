-- Play panel summary after the Claude Design full UI ("Main panel (Play)"):
-- below the offer, a compact plan progress (the run's count, a bar, four
-- counts and Details for the Echo names), the original difficulty card (S3),
-- your DPS record beside the best known record for the same Echoes with what
-- best known means, and one line of Orb run status with Open. After
-- design/current "Nexus Main Panel - Compact Redesign" also: Details in place
-- (never Plan), the level-80 collapse and re-expand (S7), the card's hover,
-- Hardcore route and server-HUD hide (S8), the drag grip (S9) and the
-- Play geometry at 0.75-2.0 font scale (S10). Correction 3 adds the
-- difficulty appearance by validated mode (S3b) and the held Details top
-- across a fit-scale change (S12). The approved panel cleanup adds the
-- collapse of the DPS rows without a record, a measured 0 apart (S4b). Categories
-- (view_regression_support): EXPECT is behaviour added by this change (it
-- fails before it by design: no NexusPanel._play, no UI.PanelRunLine); GUARD
-- already held and must keep holding; SETUP is the fixture. Oracles: the real
-- Panel render and LayoutMetrics boxes, the real OrbPanel compact read over a
-- synthetic CompactStatus, the shown FontStrings' text, and the game-action,
-- send, saved-data and Auto counters. Real TOC boot; synthetic host services
-- and models only. Native pixels, font coverage, label fit at large font
-- scales and tooltip drawing are NOT RUN.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('play_panel_summary')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P=Nexus.Panel

-- `exceptPanelHidden`: the saved data without the one key a player's own hide
-- or show writes (issue #164), so every other saved field is still compared.
local function Effects(exceptPanelHidden)
 local saved=NexusDB
 if exceptPanelHidden then
  saved={}
  for k,v in pairs(NexusDB) do if k~='panelHidden' then saved[k]=v end end
 end
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'saved='..F.Serialize(saved),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
local function Model(o)
 o=o or {}
 local pr={wishlistName='Synthetic Play plan',total=o.total or 6,owned=o.owned,
  missing=o.missing or {},shed=o.shed or {},toLock=o.toLock or {},unknownTomes=o.unknownTomes or {},
  performance=o.performance}
 if o.owned==nil and not o.unknownOwned then pr.owned=2 end
 return {status='ready',level=o.level or 40,auto=false,cards=o.cards or {},recommendation=o.recommendation or '',
  progress=pr,serverStatus=o.serverStatus,bestDps=o.bestDps,orbGuidance=o.orbGuidance}
end
-- Visible text of every shown FontString of the HUD, in tree order.
local function ShownText()
 local out={}
 for _,r in ipairs(G.Shown(NexusPanel)) do
  if r.kind=='FontString' then out[#out+1]=V.Plain(r:GetText() or '') end
 end
 return table.concat(out,' | ')
end
local function Plain(fs) return fs and V.Plain(fs:GetText() or '') or '' end
local function StatusCard()
 for _,f in ipairs(H.frames) do if f._nexusThemeExempt and f:GetParent()==NexusPanel and f.intensityBar then return f end end
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()

C.scenario('S1 compact plan progress: count and bar; the four counts and their names only under Show details',function()
 local before=Effects()
 local m=Model({owned=2,missing={'Cinder Lattice x2 (Rare:x2)','Hollow Bell'},shed={'Ashen Tithe'},
  toLock={'Gravecall Chorus'},unknownTomes={'Frostwake Sigil'}})
 C.setup(P.Render(m)==true and NexusPanel:IsShown(),'S1: fixture: the HUD renders a build in progress')
 local p=NexusPanel._play
 C.expect(type(p)=='table' and NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.play==true,
  'S1: the Play summary exists in the Play layout')
 if type(p)~='table' then return end
 -- Native QA test.163008: the detail section (the four counts and the names
 -- behind them) starts collapsed; its counts are worded either way.
 C.expect(not p.needed:IsShown() and not p.tomes:IsShown() and not p.extra:IsShown() and not p.locked:IsShown(),
  'S1: the detail section starts collapsed')
 C.expect(Plain(p.needed)=='Still needed  4 copies','S1: still needed copies',Plain(p.needed))
 C.expect(Plain(p.tomes)=='Missing tomes  1 Echo','S1: Echoes blocked by missing tomes',Plain(p.tomes))
 C.expect(Plain(p.extra)=='Extra copies  1 listed','S1: extra copies listed',Plain(p.extra))
 C.expect(Plain(p.locked)=='Locked targets  1 to lock','S1: locked targets still to lock',Plain(p.locked))
 local boxes=NexusPanel._responsiveLayout.boxes
 C.expect(p.track:IsShown() and p.fill:IsShown() and p.fill:GetWidth()==math.floor(boxes.planBar.w*2/6),
  'S1: the bar fills the share of planned rolled copies this run has',tostring(p.fill:GetWidth()))
 C.expect(p.details:IsShown() and Plain(p.details)=='Show details','S1: Show details is offered on the heading row')
 C.expect(boxes.planNeeded==nil and boxes.needed==nil,'S1: no detail rows are laid out while collapsed')
 local text=ShownText()
 C.expect(not text:find('Hollow Bell',1,true) and not text:find('Gravecall Chorus',1,true)
  and not text:find('Still needed',1,true) and not text:find('Missing tomes',1,true),
  'S1: the counts and Echo names stay behind Show details',text)
 C.expect(not text:find('MISSING TOMES',1,true),'S1: the former tomes row is not shown',text)
 C.guard(Effects()==before,'S1: rendering the summary makes no game action, send, saved-data or Auto change')
 -- Details is memory only. design/current "Nexus Main Panel - Compact
 -- Redesign" wires its web Details to Plan; the addon keeps the corrected
 -- behaviour: the detail section expands and collapses in place, the panel
 -- grows and shrinks with it, and Plan never opens.
 local clicked=Effects()
 local closedHeight=NexusPanel:GetHeight()
 -- Plan is the Wishlist Editor workspace (FullUIWorkspaces.ShowPlan).
 local function PlanShown()
  local editor=_G.NexusEditorFrame
  return editor~=nil and editor:IsShown()
 end
 C.setup(not PlanShown(),'S1: fixture: Plan is not open before Details')
 p.details:Click()
 C.setup(P.Render(m)==true,'S1: fixture: the same model rendered again after Show details')
 text=ShownText()
 C.expect(P._playDetails==true and text:find('Hollow Bell',1,true)~=nil and text:find('Gravecall Chorus',1,true)~=nil
  and Plain(p.details)=='Hide details','S1: Show details shows the names behind the counts',text)
 boxes=NexusPanel._responsiveLayout.boxes
 C.expect(boxes.needed~=nil and boxes.planNeeded~=nil,'S1: the counts and name columns are laid out under Show details')
 -- Every count box is inside the panel and apart from the others.
 local apart=true
 local names={'planNeeded','planTomes','planExtra','planLocked','planBar','progressHeader','progressValue','planDetails'}
 for i=1,#names do for j=i+1,#names do
  local a,b=boxes[names[i]],boxes[names[j]]
  if not (a and b) or Nexus.LayoutMetrics.Overlap(a,b) then apart=false end
 end end
 C.expect(apart,'S1: heading, bar and counts are disjoint boxes')
 local openHeight=NexusPanel:GetHeight()
 C.expect(openHeight>closedHeight and openHeight==NexusPanel._responsiveLayout.height,
  'S1: the panel grows to hold the detail section',closedHeight..' -> '..openHeight)
 C.expect(p.needed:IsShown() and p.tomes:IsShown() and p.extra:IsShown() and p.locked:IsShown()
  and Plain(p.needed)=='Still needed  4 copies','S1: the four counts show with details open',Plain(p.needed))
 C.expect(not PlanShown(),'S1: Show details never navigates to Plan')
 C.guard(Effects()==clicked,'S1: Show details changes no game action, send, saved data or Auto',Effects())
 p.details:Click()
 P.Render(m)
 text=ShownText()
 C.expect(P._playDetails==false and not text:find('Hollow Bell',1,true) and not text:find('Still needed',1,true),
  'S1: Hide details hides the counts and names again')
 C.expect(NexusPanel:GetHeight()==closedHeight and not p.needed:IsShown() and Plain(p.details)=='Show details',
  'S1: Hide details gives the whole section\'s height back',NexusPanel:GetHeight())
 C.expect(not PlanShown(),'S1: Hide details never navigates to Plan')
end)

C.scenario('S2 an unknown run count is "?", never 0, and fills no bar',function()
 P.Render(Model({unknownOwned=true}))
 local p=NexusPanel._play
 if not C.setup(type(p)=='table','S2: fixture: the summary exists') then return end
 C.expect(Plain(p.needed)=='Still needed  ?','S2: still needed is unknown',Plain(p.needed))
 C.expect(not p.fill:IsShown(),'S2: no bar fill without a known count')
 C.expect(not ShownText():find('0 copies',1,true),'S2: nothing says 0 copies',ShownText())
end)

-- design/current "Nexus Main Panel - Compact Redesign" reverses the earlier
-- flattened row: Play shows the original b0870929 difficulty card again.
C.scenario('S3 the original difficulty card in Play, not a flattened row; the card stays in the completed view',function()
 local ss={tier='Heroic +2',ash='1,240',gain='20',intensity=250,intensityMax=500}
 P.Render(Model({serverStatus=ss}))
 local p,card=NexusPanel._play,StatusCard()
 if not C.setup(type(p)=='table' and card~=nil,'S3: fixture: the summary and the protected card exist') then return end
 local box=NexusPanel._responsiveLayout.boxes.status
 -- Approved panel cleanup: the card is the Compact A card (S16: 48 units
 -- with its Intensity bar, where the original was 56). This status carries
 -- no validated Intensity thresholds, so there is no bar: its two text lines
 -- and insets are 39 units (5 + 15 + 14 + 5).
 C.expect(card:IsShown() and box~=nil and card:GetHeight()==box.h and box.h==39,
  'S3: the card is shown in the Play panel in its Compact A box',tostring(card:GetHeight()))
 C.expect(NexusPanel._responsiveLayout.boxes.serverLine==nil and not p.server:IsShown() and not p.serverHit:IsShown(),
  'S3: no flattened Difficulty / Soul Ash row')
 P.Render(Model({serverStatus=ss,owned=6}))
 C.guard(card:IsShown(),'S3: a completed build keeps the Difficulty / Soul Ash card')
 C.expect(not p.server:IsShown() and not p.needed:IsShown(),'S3: the completed view shows no Play summary rows')
end)

-- Correction 3 item 4: the card uses only the scanner's validated
-- distinction (ServerStatus: a Hardcore tier HC1-HC5, else mode "Normal",
-- else unknown). A Hardcore tier keeps the original red caption and red
-- hover heading; a known Normal is neutral, as the game's own widget shows
-- it; an unknown mode keeps the former red "Difficulty". The raw Soul Ash
-- and multiplier, the card's height and its theme exemption are the same in
-- every case, and no intensity scale is invented. Native colours and the
-- original art comparison are NOT RUN; #126 (the post-reload server tier) is
-- not addressed by this.
C.scenario('S3b the difficulty card: Hardcore red, a known Normal neutral, an unknown mode unchanged',function()
 local before=Effects()
 local function Heading(hit)
  local first
  local saved=rawget(GameTooltip,'AddLine')
  rawset(GameTooltip,'AddLine',function(_,text,r,g,b) if not first then first={tostring(text),r,g,b} end end)
  local ok=pcall(hit:GetScript('OnEnter'),hit)
  rawset(GameTooltip,'AddLine',saved)
  return ok and first or nil
 end
 local cases={
  {'a Hardcore tier',{tier='HC3',mode='HC3',ash='12,345',gain='+150%'},'|cffff6b5fHC3|r',{1,0.25,0.25}},
  {'a known Normal',{mode='Normal',ash='12,345',gain='+150%'},'|cffd9d9d9Normal|r',{0.85,0.85,0.85}},
  {'an unknown mode',{ash='12,345',gain='+150%'},'|cffff6b5fDifficulty|r',{1,0.25,0.25}},
 }
 local height
 for _,case in ipairs(cases) do
  local tag='S3b '..case[1]
  P.Render(Model({serverStatus=case[2]}))
  local card=StatusCard()
  if C.setup(card~=nil and card:IsShown(),tag..': fixture: the card is shown') then
   local caption=card.regions[1]
   C.expect(caption and caption:GetText()==case[3],tag..': the caption keeps the validated appearance',caption and caption:GetText())
   local hit
   for _,c in ipairs(card.children or {}) do if c.kind=='Button' and c:GetScript('OnClick') then hit=c end end
   if C.setup(hit~=nil,tag..': fixture: the card\'s full-card button') then
    local h=Heading(hit)
    local want=case[4]
    C.expect(h and h[1]==V.Plain(case[3]) and h[2]==want[1] and h[3]==want[2] and h[4]==want[3],
     tag..': the hover heading has the same appearance',h and table.concat({h[1],tostring(h[2]),tostring(h[3]),tostring(h[4])},','))
    local tip=table.concat(V.TooltipLines(hit:GetScript('OnEnter'),hit),' | ')
    C.guard(tip:find('Soul Ash: 12345',1,true) and tip:find('Multiplier: +150%',1,true) and not tip:find('Intensity',1,true),
     tag..': the raw Soul Ash and multiplier are kept; no intensity is invented',tip)
   end
   C.guard(card._nexusThemeExempt==true and not card.intensityBar:IsShown(),tag..': the card stays exempt from the theme; no bar without a validated scale')
   height=height or card:GetHeight()
   C.guard(card:GetHeight()==height,tag..': the card keeps its height',card:GetHeight())
  end
 end
 C.guard(Effects()==before,'S3b: rendering each mode changed no saved data, Auto, action or send',Effects())
end)

C.scenario('S4 your record and the best known record for the same Echoes are separate rows',function()
 local perf={dummy={global={dps=5130,player='Synthetic'}},lk={}}
 P.Render(Model({bestDps={dummy={dps=4812}},performance=perf}))
 local p=NexusPanel._play
 if not C.setup(type(p)=='table','S4: fixture: the summary exists') then return end
 local text=ShownText()
 C.expect(text:find('Yours · Training Dummy',1,true)~=nil and Plain(p.yoursValue)=='4,812 DPS',
  'S4: your record has its own row',Plain(p.yoursValue))
 C.expect(Plain(p.bestLabel)=='Best known · same build' and Plain(p.bestValue)=='5,130 DPS',
  'S4: the best known record for the same Echoes has its own row',Plain(p.bestValue))
 -- Approved panel cleanup: the DPS section is one line of entries, so what
 -- best known means is on the best known entry's hover, not a row of its own.
 local scope=table.concat(V.TooltipLines(p.bestHit:GetScript('OnEnter'),p.bestHit),' | ')
 C.expect(scope:find('server-wide ranking',1,true)~=nil,'S4: the best known hover says what best known is',scope)
 C.expect(not text:lower():find('rank #',1,true),'S4: no rank is claimed')
 -- No record at all while shared data loads. Approved panel cleanup ("Hide
 -- absent DPS/training sections completely"): the former "... shared data
 -- loading", "no record yet" and "none received yet" placeholders no longer
 -- stand in for rows that have no record (S4b); what is kept is that a
 -- missing record is never said as 0 or as "no records". The wait and the
 -- missing side are named on the hover of a row that does exist (S4c).
 -- A copy of the real snapshot with only its state changed, so nothing the
 -- start-up owner holds is touched.
 local status=Nexus.StartupStatus
 Nexus.StartupStatus=function()
  local s={};for k,v in pairs(status()) do s[k]=v end
  s.state='pending';return s
 end
 local ok,err=pcall(P.Render,Model({bestDps={},performance={dummy={},lk={}}}))
 Nexus.StartupStatus=status
 C.setup(ok,'S4: fixture: rendered while shared data loads',err)
 text=ShownText()
 C.expect(not p.bestValue:IsShown() and not p.yoursValue:IsShown() and not text:find('DPS',1,true),
  'S4: without a record no DPS row is shown while shared data loads',text)
 C.expect(not text:find('%f[%d,]0 DPS') and not text:lower():find('no records',1,true),
  'S4: a missing record is never said as 0 or as no records',text)
 P.Render(Model({bestDps={},performance={dummy={},lk={}},owned=3}))
 if C.setup(Nexus.StartupStatus().state=='ready','S4: fixture: shared data is ready after start-up',Nexus.StartupStatus().state) then
  text=ShownText()
  C.expect(not p.bestValue:IsShown() and not text:find('received yet',1,true) and not text:find('DPS',1,true),
   'S4: with shared data ready and no record the row is absent, not a placeholder',text)
 end
end)

-- Approved panel cleanup (requirement: "Hide absent DPS/training sections
-- completely, including dividers and reserved geometry. Measured zero is
-- valid."). Without any DPS record (none of yours, none best known for these
-- Echoes) the Play panel shows no DPS row, label, placeholder or note and
-- reserves nothing for them: no layout box follows the progress block, and
-- the footer follows it within 12 units (one 6-unit section gap and the
-- 6-unit footer gap of font scale 1). A record measured as 0 is a record: its
-- row says "0 DPS", never "no record yet", and takes a row's height. Records
-- arriving again give the rows and their height back. EXPECT fails before the
-- change by design: the three rows were always laid out with "no record yet"
-- and "none received yet", a records-only change took no layout pass, and a 0
-- read as no record. Oracles: the rendered layout's boxes, the shown
-- FontStrings' text and the panel height. Native pixels are NOT RUN.
C.scenario('S4b no DPS record: no row, word or reserved space; a measured 0 is a record',function()
 local before=Effects()
 local function Laid() return NexusPanel._responsiveLayout or {boxes={}} end
 -- The bottom of the progress block: its heading row, count and bar.
 local function ProgressBottom()
  local bottom
  for name,b in pairs(Laid().boxes) do
   if (name:find('^progress') or name:find('^plan')) and (not bottom or b.y+b.h>bottom) then bottom=b.y+b.h end
  end
  return bottom
 end
 -- The layout boxes below the progress block, the footer apart.
 local function Below()
  local bottom,names=ProgressBottom(),{}
  for name,b in pairs(Laid().boxes) do
   if bottom and name~='footer' and b.y>=bottom then names[#names+1]=name end
  end
  table.sort(names)
  return names
 end
 -- What the DPS rows say: their labels, values, placeholders and note.
 local function DpsWords(text)
  local found={}
  for _,word in ipairs({'DPS','Yours','Best known','record yet','received yet','shared data','server-wide'}) do
   if text:find(word,1,true) then found[#found+1]=word end
  end
  return found
 end
 local both=Model({bestDps={dummy={dps=4812}},performance={dummy={global={dps=5130,player='Synthetic'}},lk={}}})
 C.setup(P.Render(both)==true and NexusPanel:IsShown(),'S4b: fixture: a build in progress with both records renders')
 local l=Laid()
 if not C.setup(l.play==true and l.gap==6 and ProgressBottom()~=nil and l.boxes.footer~=nil and l.boxes.orbLine==nil
  and P._playDetails~=true,'S4b: fixture: the Play layout at font scale 1, Details closed, no Orb line',tostring(l.gap)) then return end
 local text=ShownText()
 C.guard(text:find('4,812 DPS',1,true)~=nil and text:find('5,130 DPS',1,true)~=nil,
  'S4b: your record and the best known record show while both exist',text)
 local withBoth=NexusPanel:GetHeight()
 -- No record at all, in both shapes a model carries it: no record fields,
 -- and the empty record tables of a build nobody has measured yet.
 local withNone
 for _,case in ipairs({{'no record fields',Model()},
  {'empty record tables',Model({bestDps={},performance={dummy={},lk={}}})}}) do
  local tag='S4b '..case[1]
  C.setup(P.Render(case[2])==true,tag..': fixture: rendered')
  local below=Below()
  C.expect(#below==0,tag..': nothing is laid out below the progress block',table.concat(below,','))
  local footer,bottom=Laid().boxes.footer,ProgressBottom()
  C.expect(footer~=nil and bottom~=nil and footer.y-bottom<=12,
   tag..': the footer follows the progress block; no row or divider is reserved',footer and bottom and footer.y-bottom)
  text=ShownText()
  local words=DpsWords(text)
  C.expect(#words==0,tag..': no DPS row, label, placeholder or note is shown',table.concat(words,',')..' in '..text)
  local height=NexusPanel:GetHeight()
  C.expect(height<withBoth,tag..': the panel is shorter than with records',height..' / '..withBoth)
  withNone=withNone or height
  C.guard(height==withNone,tag..': both empty shapes give the same panel',height..' / '..withNone)
 end
 -- A measured 0 is a record of yours (the test is "is there a record", not
 -- "is it above 0").
 C.setup(P.Render(Model({bestDps={dummy={dps=0}}}))==true,'S4b: fixture: a record of yours measured as 0 renders')
 text=ShownText()
 C.expect(text:find('Yours',1,true)~=nil and text:find('%f[%d,]0 DPS')~=nil,'S4b: a measured 0 shows as your record: 0 DPS',text)
 C.expect(not text:find('record yet',1,true),'S4b: a measured 0 is never said as no record',text)
 local below=Below()
 C.expect(#below>=1 and withNone~=nil and NexusPanel:GetHeight()>withNone,
  'S4b: the measured 0 has its row and that row\'s height',table.concat(below,',')..' '..NexusPanel:GetHeight()..' / '..tostring(withNone))
 C.setup(P.Render(both)==true,'S4b: fixture: both records again')
 text=ShownText()
 C.guard(NexusPanel:GetHeight()==withBoth and text:find('4,812 DPS',1,true)~=nil and text:find('5,130 DPS',1,true)~=nil,
  'S4b: records arriving again give the rows and their height back',NexusPanel:GetHeight()..' / '..withBoth..' '..text)
 C.guard(Effects()==before,'S4b: showing and hiding the DPS rows makes no game action, send, saved-data or Auto change',Effects())
end)

-- Approved panel cleanup ("Partial records show only actual rows"): with only
-- one of the two records, only that record's row exists; the other has no
-- row, box, placeholder, note or hover area. What the placeholders said is
-- kept on the hover of the row that does exist: that no best known record
-- was received yet, or that shared data is still loading (a wait, never
-- "none"), or that you have no record yet; and the best known row's hover
-- says what best known means. Reading a hover changes nothing.
C.scenario('S4c a partial DPS record shows only the row that exists; its hover names the missing side',function()
 local before=Effects()
 local function Tip(hit)
  if not (hit and hit:IsShown() and hit:GetScript('OnEnter')) then return nil end
  return table.concat(V.TooltipLines(hit:GetScript('OnEnter'),hit),' | ')
 end
 C.setup(P.Render(Model({bestDps={dummy={dps=4812}}}))==true,'S4c: fixture: only your record exists')
 local p=NexusPanel._play
 if not C.setup(type(p)=='table','S4c: fixture: the summary exists') then return end
 local text=ShownText()
 C.guard(text:find('Yours · Training Dummy',1,true)~=nil and text:find('4,812 DPS',1,true)~=nil,'S4c: your record keeps its row',text)
 C.expect(not text:find('Best known',1,true) and not text:find('received yet',1,true) and not text:find('server-wide',1,true),
  'S4c: no best known row, placeholder or note without a best known record',text)
 C.expect(NexusPanel._responsiveLayout.boxes.bestKnown==nil and not p.bestHit:IsShown(),
  'S4c: the absent best known row has no layout box and no hover area')
 local tip=Tip(p.yoursHit)
 C.expect(tip~=nil and tip:find('Best known',1,true)~=nil and tip:find('none received yet',1,true)~=nil,
  'S4c: your row\'s hover says no best known record was received yet',tostring(tip))
 local status=Nexus.StartupStatus
 Nexus.StartupStatus=function()
  local s={};for k,v in pairs(status()) do s[k]=v end
  s.state='pending';return s
 end
 local ok,loading=pcall(Tip,p.yoursHit)
 Nexus.StartupStatus=status
 C.expect(ok and loading~=nil and loading:find('shared data loading',1,true)~=nil and not loading:find('received yet',1,true),
  'S4c: while shared data loads that hover names the wait, never "none"',tostring(loading))
 C.setup(P.Render(Model({performance={dummy={global={dps=5130,player='Synthetic'}},lk={}}}))==true,
  'S4c: fixture: only a best known record exists')
 text=ShownText()
 C.guard(text:find('Best known · same build',1,true)~=nil and text:find('5,130 DPS',1,true)~=nil,
  'S4c: the best known record keeps its row',text)
 C.expect(not text:find('Yours',1,true) and not text:find('record yet',1,true),
  'S4c: no row or placeholder of yours without a record of yours',text)
 C.expect(NexusPanel._responsiveLayout.boxes.bestDps==nil and not (p.yoursHit and p.yoursHit:IsShown()),
  'S4c: the absent row of yours has no layout box and no hover area')
 tip=Tip(p.bestHit)
 C.expect(tip~=nil and tip:find('Yours',1,true)~=nil and tip:find('no record yet',1,true)~=nil,
  'S4c: the best known row\'s hover says you have no record yet',tostring(tip))
 C.guard(tip~=nil and tip:find('server-wide ranking',1,true)~=nil,
  'S4c: the best known row\'s hover says what best known means',tostring(tip))
 C.guard(Effects()==before,'S4c: partial records and their hovers make no game action, send, saved-data or Auto change',Effects())
end)

C.scenario('S5 one line of Orb run status from the Orb window read; Open opens and spends nothing',function()
 local runtime=Nexus.OrbRuntime
 C.setup(type(runtime)=='table' and type(Nexus.OrbPanel.PanelRunLine)=='function','S5: fixture: the Orb read exists')
 if type(runtime)~='table' or type(Nexus.OrbPanel.PanelRunLine)~='function' then return end
 C.guard(Nexus.OrbPanel.PanelRunLine()==nil,'S5: without an approved run there is no Orb line')
 P.Render(Model())
 local p=NexusPanel._play
 C.guard(p and not p.orb:IsShown(),'S5: no Orb line while no run is known')
 local compact=runtime.CompactStatus
 runtime.CompactStatus=function()
  return {state='WAIT_RESULT',spent=2,limit=5,reserved=1,running=true,pending=true,canResume=false,
   uncertain=0,unconfirmedResults=0,historyKnown=true,remaining=3,limitKnown=true}
 end
 local shown,full=Nexus.OrbPanel.PanelRunLine()
 C.expect(shown=='Orb run: Running - Waiting for result confirmation; Used 2 of 5 approved; ... 1 awaiting result',
  'S5: the line names the state, usage and the wait',shown)
 C.expect(type(full)=='string' and full:find('Pending: 1 Orb requested, not confirmed yet',1,true)~=nil,
  'S5: the hover keeps the full pending wording',full)
 local actions,sent=#H.actions,#H.sent
 P.Render(Model())
 C.expect(p.orb:IsShown() and Plain(p.orb)==shown and p.orbOpen:IsShown(),'S5: the HUD shows the line and Open',Plain(p.orb))
 C.expect(NexusPanel._responsiveLayout.boxes.orbLine~=nil,'S5: the layout holds its row')
 -- The synthetic run is withdrawn before Open, so the Orb window reads the
 -- real (no run) state.
 runtime.CompactStatus=compact
 p.orbOpen:Click()
 C.guard(NexusOrbPanel~=nil and NexusOrbPanel:IsShown(),'S5: Open shows the Orb window')
 -- Appearance is one shared Theme choice, reached from the panel's Options
 -- directly; the Orb window no longer repeats it (design/current).
 local repeated
 for _,c in ipairs(NexusOrbPanel and NexusOrbPanel.children or {}) do
  if c.kind=='Button' and V.Plain(c:GetText() or ''):find('Appearance',1,true) then repeated=c:GetText() end
 end
 C.expect(repeated==nil,'S5: the Orb window has no Appearance button of its own',repeated)
 C.guard(#H.actions==actions and #H.sent==sent and Nexus.RecomputeStats().autoEnabled~=true,
  'S5: showing the line and Open spend and send nothing and leave Auto OFF','actions='..#H.actions..' sent='..#H.sent)
 P.Render(Model())
 C.expect(not p.orb:IsShown(),'S5: the line goes when no run is known again')
end)

C.scenario('S6 the header X closes the panel as Hide does; closing is not pausing',function()
 P.Show()
 C.setup(P.Render(Model())==true and NexusPanel:IsShown(),'S6: fixture: the Play panel is shown')
 local close=NexusPanel._closeBtn
 C.expect(close~=nil and close:IsShown() and close:GetText()=='X','S6: the header has a visible X')
 if not close then return end
 local a,x=G.Rect(NexusPanel._autoBtn,NexusPanel),G.Rect(close,NexusPanel)
 C.expect(G.Apart(a,x) and G.Inside(x,{0,0,NexusPanel:GetWidth(),NexusPanel:GetHeight()}) and x[2]<=10,
  'S6: X sits in the header corner, apart from the Auto control',G.Text(a)..' '..G.Text(x))
 local lines=V.TooltipLines(close:GetScript('OnEnter'),close)
 local tip=table.concat(lines,' ')
 C.expect(lines[1]=='Close panel' and tip:find('does not turn Nexus off or change Auto',1,true)~=nil,
  'S6: its hover says closing does not pause Nexus or change Auto',tip)
 -- Issue #164: closing is the player's saved display choice. The only saved
 -- change it may make is panelHidden=true; Show clears it again.
 C.setup(NexusDB.panelHidden==nil and P.VisibilityFacts().wanted==true,
  'S6: fixture: no hide is saved before X',tostring(NexusDB.panelHidden))
 local before,beforeOthers=Effects(),Effects(true)
 close:Click()
 C.expect(not NexusPanel:IsShown(),'S6: X hides the panel')
 C.expect(NexusDB.panelHidden==true and P.VisibilityFacts().wanted==false,
  'S6: X saves the requested hidden choice (panelHidden=true)',tostring(NexusDB.panelHidden))
 C.guard(Effects(true)==beforeOthers,
  'S6: closing makes no game action, send, Auto change or saved-data change other than panelHidden',Effects(true))
 P.Show()
 C.expect(NexusPanel:IsShown() and NexusDB.panelHidden==nil and P.VisibilityFacts().wanted==true,
  'S6: Show brings the panel back and clears the saved hide',tostring(NexusDB.panelHidden))
 C.guard(Effects()==before,'S6: after Show every saved field, action, send and Auto is as before X',Effects())
end)

-- design/current "Nexus Main Panel - Compact Redesign", level 80 (R1-R3): the
-- runtime's finished guidance with no offer collapses the roll block to the
-- guidance and its inline Open Orbs...; a new offer gives the full block back;
-- the offer going again collapses it at once (Auto OFF: no held card rows).
-- The first render at level 80 is already collapsed (no 104 px flash). Layout
-- only: Auto, saved data and the guidance words are unchanged throughout.
C.scenario('S7 level 80: finished guidance with no offer collapses; a new offer re-expands; it collapses again',function()
 local guide={state='finished',text='Normal rolls finished. Review Orbs for remaining rolled targets.',openOrbs=true}
 local before=Effects()
 local function Laid() return NexusPanel._responsiveLayout or {} end
 local function Roll() return Laid().boxes and Laid().boxes.roll or nil end
 C.setup(P.Render(Model({level=80,orbGuidance=guide}))==true,'S7: fixture: a level-80 render with finished guidance')
 local roll=Roll()
 C.expect(Laid().noOffer==true and roll~=nil and roll.h<104,
  'S7: the first level-80 render is already collapsed: no 104 px offer minimum',roll and roll.h)
 C.expect(NexusPanel._orbsBtn~=nil and NexusPanel._orbsBtn:IsShown(),'S7: Open Orbs... stays, inline')
 C.expect(not (NexusPanel._orbMiniBtn and NexusPanel._orbMiniBtn:IsShown()),'S7: no separate Orb button row')
 C.expect(V.Plain(NexusPanel._rollRec:GetText() or '')==guide.text,'S7: the guidance is the runtime\'s own words',
  NexusPanel._rollRec:GetText())
 local collapsedHeight=NexusPanel:GetHeight()
 P.Render(Model({level=80,orbGuidance=guide,cards={{text='Frostwake Sigil (Rare)'}},recommendation='Take Frostwake Sigil.'}))
 roll=Roll()
 C.expect(not Laid().noOffer and roll~=nil and roll.h>=104 and NexusPanel:GetHeight()>collapsedHeight,
  'S7: a new offer re-expands the full offer block',roll and roll.h)
 P.Render(Model({level=80,orbGuidance=guide}))
 C.expect(Laid().noOffer==true and NexusPanel:GetHeight()==collapsedHeight,
  'S7: with the offer gone the block collapses again to the same height',NexusPanel:GetHeight())
 -- Another guidance (not "finished") keeps the full block.
 P.Render(Model({level=80,orbGuidance={state='waiting',text='An Echo choice is open.'}}))
 C.expect(not Laid().noOffer,'S7: other guidance keeps the full block')
 C.guard(Effects()==before,'S7: level-80 transitions make no game action, send, saved-data or Auto change',Effects())
end)

-- The original card's own interaction (b0870929 worldStatusHit): its hover
-- names tier, Soul Ash, multiplier and Intensity; a click calls the existing
-- ServerStatus.OpenHardcoreMenu route (stubbed here: the native toggle is NOT
-- RUN). With the server HUD (no mirrored status in the model) the card and
-- its layout box go; with the Nexus HUD they come back.
C.scenario('S8 the difficulty card: hover facts, Hardcore click route, and no card while the server HUD is the display',function()
 local ss={tier='Heroic +2',ash='1,240',gain='+45%',intensity=250,intensityMax=500,intensityLevel=2}
 P.Render(Model({serverStatus=ss}))
 local card=StatusCard()
 if not C.setup(card~=nil and card:IsShown(),'S8: fixture: the card is shown') then return end
 local hit
 for _,c in ipairs(card.children or {}) do if c.kind=='Button' and c:GetScript('OnClick') then hit=c end end
 if not C.setup(hit~=nil,'S8: fixture: the card\'s full-card button') then return end
 local tip=table.concat(V.TooltipLines(hit:GetScript('OnEnter'),hit),' | ')
 C.expect(tip:find('Heroic +2',1,true) and tip:find('Soul Ash: 1240',1,true) and tip:find('Multiplier: +45%',1,true)
  and tip:find('Intensity: 250 / 500',1,true) and tip:find('Hardcore',1,true),'S8: the hover names tier, Soul Ash, multiplier, Intensity and the click',tip)
 local status=Nexus.ServerStatus
 local real,calls=status.OpenHardcoreMenu,0
 status.OpenHardcoreMenu=function() calls=calls+1;return true end
 local before=Effects()
 hit:Click()
 status.OpenHardcoreMenu=real
 C.expect(calls==1,'S8: a click calls the existing Hardcore menu route once',calls)
 C.guard(Effects()==before,'S8: the click itself changes no saved data, Auto, action or send',Effects())
 local withCard=NexusPanel:GetHeight()
 P.Render(Model({serverStatus=nil}))
 C.expect(not card:IsShown() and NexusPanel._responsiveLayout.boxes.status==nil and NexusPanel:GetHeight()<withCard,
  'S8: with the server HUD the panel shows no card and gives its height back',NexusPanel:GetHeight())
 P.Render(Model({serverStatus=ss}))
 C.expect(card:IsShown() and NexusPanel:GetHeight()==withCard,'S8: with the Nexus HUD again the card is back',NexusPanel:GetHeight())
end)

-- The visible drag grip (design/current, D1-D4; issue #168 with the
-- requested Shift gate): a plain click does nothing; a left drag without
-- Shift starts no move and leaves panelX / panelY as they were; a left drag
-- while Shift is held moves the panel once through its one drag owner and
-- saves panelX / panelY. Native pointer capture is NOT RUN.
C.scenario('S9 the drag grip: visible, apart from the title and controls; only a Shift-held left drag moves',function()
 P.Render(Model())
 local grip=NexusPanel._dragGrip
 if not C.setup(grip~=nil and grip:IsShown(),'S9: fixture: the grip is shown') then return end
 local g=G.Rect(grip,NexusPanel)
 C.expect(g[3]-g[1]>=22 and g[4]-g[2]>=22,'S9: the grip is at least a 22 px target',G.Text(g))
 for _,other in ipairs({NexusPanel._contextTitle,NexusPanel._autoBtn,NexusPanel._menuBtn,NexusPanel._closeBtn}) do
  if other and other:IsShown() then
   C.expect(G.Apart(g,G.Rect(other,NexusPanel)),'S9: the grip is apart from a header control',G.Text(G.Rect(other,NexusPanel)))
  end
 end
 local tip=table.concat(V.TooltipLines(grip:GetScript('OnEnter'),grip),' ')
 C.expect(tip:find('Hold Shift and drag to move',1,true)~=nil
  and tip:find('Hold Shift and drag this grip, or any part of the panel that is not a button, to move it.',1,true)~=nil
  and tip:find('Release Shift to stop.',1,true)~=nil,
  'S9: its hover requires holding Shift to drag and says releasing Shift stops the move',tip)
 C.expect(grip:GetScript('OnClick')==nil,'S9: a plain click on the grip has no action')
 local moves,stops,cx=0,0,100
 NexusPanel.StartMoving=function() moves=moves+1 end
 NexusPanel.StopMovingOrSizing=function() stops=stops+1 end
 NexusPanel.GetCenter=function() return cx,50 end
 -- The saved position before the drags, read only, for the refusal below.
 local priorX,priorY=P.SavedLayoutRoot().panelX,P.SavedLayoutRoot().panelY
 local shift=IsShiftKeyDown
 IsShiftKeyDown=function() return false end
 grip:GetScript('OnDragStart')(grip,'LeftButton');cx=140;grip:GetScript('OnDragStop')(grip)
 C.expect(moves==0 and stops==0 and P._panelDrag==nil,'S9: a left drag without Shift neither moves the panel nor leaves a drag owner',moves..'/'..stops)
 local saved=P.SavedLayoutRoot()
 C.expect(saved.panelX==priorX and saved.panelY==priorY,'S9: a left drag without Shift leaves panelX / panelY as they were',
  tostring(saved.panelX)..','..tostring(saved.panelY)..' (was '..tostring(priorX)..','..tostring(priorY)..')')
 IsShiftKeyDown=function() return true end
 grip:GetScript('OnDragStart')(grip,'LeftButton');cx=150;grip:GetScript('OnDragStop')(grip)
 IsShiftKeyDown=shift
 NexusPanel.StartMoving,NexusPanel.StopMovingOrSizing,NexusPanel.GetCenter=nil,nil,nil
 C.expect(moves==1 and stops==1 and P._panelDrag==nil and tonumber(saved.panelX)==150 and tonumber(saved.panelY)==50,
  'S9: a Shift-held left drag moves it once and saves panelX / panelY',moves..'/'..stops..' '..tostring(saved.panelX)..','..tostring(saved.panelY))
 saved.panelX,saved.panelY=nil,nil
end)

-- The Play geometry at every supported font scale (LayoutMetrics clamps
-- 0.75-2; 1.25 is the 125% text of the design's L1): the 420 px panel's boxes
-- are disjoint and inside it, the card keeps at least its 56 px, Details adds
-- the named lists below the counts without moving the counts, and level 80
-- with no offer collapses the roll box under the 104 px minimum. Pure layout
-- model; native font measurement is NOT RUN.
C.scenario('S10 Play layout at 0.75-2.0 font scale: disjoint boxes, the card, Details and the level-80 collapse',function()
 local LM=Nexus.LayoutMetrics
 for _,scale in ipairs({0.75,1,1.25,1.5,2}) do
  local function Laid(extra)
   -- Both DPS records exist here (spec.recordYours / recordBest): their rows
   -- are laid out only for records that exist (approved cleanup, S4b).
   local spec={width=420,fontScale=scale,activeRoll=true,statusVisible=true,cardRows=true,toLockCount=1,orbLine=true,
    recordYours=true,recordBest=true}
   for k,v in pairs(extra or {}) do spec[k]=v end
   return LM.Panel(spec)
  end
  for _,o in ipairs({{},{planDetails=true},{cardRows=false,noOffer=true,orbButton=true,guidanceRows=2}}) do
   local l=Laid(o)
   local tag='S10 @'..scale..(o.planDetails and ' Details' or o.noOffer and ' level 80' or '')
   local names,apart,inside={},true,true
   for name in pairs(l.boxes) do names[#names+1]=name end
   table.sort(names)
   for i=1,#names do
    local a=l.boxes[names[i]]
    if a.x<0 or a.y<0 or a.x+a.w>420 or a.y+a.h>l.height then inside=false end
    for j=i+1,#names do if LM.Overlap(a,l.boxes[names[j]]) then apart=false end end
   end
   C.expect(apart and inside,tag..': every box is inside the panel and apart from the others',table.concat(names,','))
   -- Approved panel cleanup: the Compact A card, 48 units at font scale 1
   -- (5 + a 15-unit tier line + a 14-unit Soul Ash line + 3 + the 6-unit
   -- bar + 5), its two text lines following the font scale: 42, 48, 56, 63
   -- and 77 units at 0.75, 1, 1.25, 1.5 and 2. The original card was 56.
   local cardH=({[0.75]=42,[1]=48,[1.25]=56,[1.5]=63,[2]=77})[scale]
   C.expect(l.boxes.status~=nil and l.boxes.status.h==cardH and l.boxes.serverLine==nil,
    tag..': the Compact A card is '..cardH..' units; no flattened row',l.boxes.status and l.boxes.status.h)
   if o.noOffer then
    C.expect(l.noOffer==true and l.boxes.roll.h<104 and l.boxes.planBar~=nil,tag..': the roll box collapses below 104 px',l.boxes.roll.h)
    -- Finish pass item E: no blank band where the offers were; the gaps
    -- above and below the collapsed block are at most 8 px, and the block
    -- is exactly its two guidance rows (or the inline button) high.
    -- Approved order: the Orb run line follows the offer block, before the
    -- progress, so it is the block's next neighbour while a run is known.
    local s,r,h=l.boxes.status,l.boxes.roll,l.boxes.orbLine or l.boxes.progressHeader
    local _,line=LM.ConservativeText(scale)
    C.expect(r.y-(s.y+s.h)<=8 and h.y-(r.y+r.h)<=8,tag..': the gaps around the collapsed block are at most 8 px',
     (r.y-(s.y+s.h))..' / '..(h.y-(r.y+r.h)))
    C.expect(r.h==math.max(2*line,l.orbButtonH or 0),tag..': the block is as tall as its guidance, no padding',r.h)
   end
  end
  -- Native QA test.163008: Show details adds the whole detail section (the
  -- counts, then the named lists) below the bar; Hide details gives back
  -- exactly that height, and nothing above the bar moves.
  local closed,open=Laid(),Laid({planDetails=true})
  C.expect(open.height>closed.height and open.boxes.needed~=nil and closed.boxes.needed==nil
   and closed.boxes.planNeeded==nil and open.boxes.planNeeded~=nil
   and open.boxes.planBar.y==closed.boxes.planBar.y and open.boxes.planNeeded.y>open.boxes.planBar.y
   and open.boxes.needed.y>open.boxes.planLocked.y,
   'S10 @'..scale..': Show details adds the counts and lists below the bar and grows the panel; the bar stays put',
   closed.height..' -> '..open.height)
  C.expect(open.boxes.bestDps.y-closed.boxes.bestDps.y==open.height-closed.height,
   'S10 @'..scale..': the rows below move by exactly the section\'s height',
   (open.boxes.bestDps.y-closed.boxes.bestDps.y)..' / '..(open.height-closed.height))
 end
end)

-- Finish pass item E (design/current Lv80 and the Auto chip): the collapsed
-- level-80 block in the real render fills its box with the guidance and the
-- inline primary Open Orbs...; Auto OFF is said in words in a neutral light
-- grey, not an alarm red; Show / Hide details keeps the panel's top (and the
-- Details row) where the player sees it and grows or shrinks downward, and
-- near the bottom of the screen moves up only as far as needed and says so
-- (Panel._detailsGrowth). Memory only: no saved field, Auto or action
-- changes. The panel's screen corner is read from its real anchor (the
-- harness answers a fixed corner for any other anchor). Native pixels,
-- clamping and colour contrast are NOT RUN.
C.scenario('S11 level 80 block and Auto OFF; Details grows downward from a held top',function()
 local guide={state='finished',text='Normal rolls finished. Review Orbs for remaining rolled targets.',openOrbs=true}
 local ss={tier='Heroic +2',ash='1,240',gain='20',intensity=250,intensityMax=500}
 local before=Effects()
 C.setup(P.Render(Model({level=80,orbGuidance=guide,serverStatus=ss}))==true,'S11: fixture: a level-80 render with finished guidance')
 local l=NexusPanel._responsiveLayout
 if C.setup(l and l.noOffer==true and l.boxes.roll~=nil,'S11: fixture: the collapsed block') then
  local roll,rec=G.Rect(NexusPanel._rollArea,NexusPanel),G.Rect(NexusPanel._rollRec,NexusPanel)
  C.expect(G.Inside(rec,roll,0.5) and math.abs((rec[4]-rec[2])-l.boxes.roll.h)<0.5,
   'S11: the guidance fills the collapsed block, which has no padding below it',G.Text(rec)..' / '..G.Text(roll))
  local open=NexusPanel._orbsBtn
  C.expect(open and open:IsShown() and G.Inside(G.Rect(open,NexusPanel),roll,0.5) and open._nexusPrimary==true,
   'S11: Open Orbs... is inline in the block and is the primary action',open and tostring(open._nexusPrimary))
 end
 local auto=NexusPanel._autoBtn
 if C.setup(auto and auto:IsShown(),'S11: fixture: the Auto control is shown') then
  local text=auto:GetText() or ''
  C.expect(V.Plain(text)=='Auto OFF' and text:find('|cffd9d9d9',1,true)~=nil and not text:find('|cffe63c3c',1,true),
   'S11: Auto OFF is said in words, in a neutral light grey',text)
 end
 C.guard(Effects()==before,'S11: the level-80 render changed no saved data, Auto, action or send',Effects())

 -- Details: a held top. The test's refresh renders the same model.
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 UIParent:SetSize(1366,768)
 local m=Model({owned=2,missing={'Cinder Lattice x2 (Rare:x2)','Hollow Bell'},shed={'Ashen Tithe'},
  toLock={'Gravecall Chorus'},serverStatus=ss})
 local realRefresh=P.Refresh
 P.Refresh=function() return P.Render(m) end
 local function Corner()
  local pt=NexusPanel.points[1]
  if not (pt and #NexusPanel.points==1 and pt[1]=='TOPLEFT' and pt[2]==UIParent and pt[3]=='BOTTOMLEFT') then return nil end
  return pt[4],pt[5]
 end
 local function Track(left,top,scale)
  NexusPanel.GetLeft=function(self) local x=Corner();return x or left end
  NexusPanel.GetTop=function(self) local _,y=Corner();return y or top end
  NexusPanel.GetEffectiveScale=function() return scale end
 end
 local ok,err=pcall(function()
  P._playDetails=false
  P.Render(m)
  local p=NexusPanel._play
  if not C.setup(type(p)=='table' and p.details:IsShown(),'S11: fixture: Show details is offered') then return end
  local closedH=NexusPanel:GetHeight()
  local row=G.Rect(p.details,NexusPanel)
  -- The intended starting corner, set and read back before the hold is
  -- taken: earlier scenarios leave the panel at their own valid corner,
  -- which production rightly keeps.
  NexusPanel:ClearAllPoints();NexusPanel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',900,600)
  Track(900,600,1)
  local x0,y0=Corner()
  if not C.setup(x0==900 and y0==600,'S11: fixture: the panel starts with its top-left at 900,600',tostring(x0)..','..tostring(y0)) then return end
  local quiet=Effects()
  p.details:Click()
  local x,y=Corner()
  C.expect(P._playDetails==true and NexusPanel:GetHeight()>closedH and x==900 and y==600 and P._detailsGrowth
   and P._detailsGrowth.direction=='down','S11: Show details keeps the panel top where it was and grows downward',
   tostring(x)..','..tostring(y)..' h='..NexusPanel:GetHeight())
  local row2=G.Rect(p.details,NexusPanel)
  C.expect(row2[1]==row[1] and row2[2]==row[2],'S11: the Details button keeps its place under the held top',G.Text(row)..' / '..G.Text(row2))
  p.details:Click()
  x,y=Corner()
  C.expect(P._playDetails==false and NexusPanel:GetHeight()==closedH and x==900 and y==600,
   'S11: Hide details keeps the same top and gives the height back below it',tostring(x)..','..tostring(y))
  -- Near the bottom of the screen: the panel moves up just enough to stay
  -- whole, and says that its top moved.
  NexusPanel:ClearAllPoints();NexusPanel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',900,closedH+10)
  p.details:Click()
  x,y=Corner()
  local openH=NexusPanel:GetHeight()
  C.expect(openH>closedH+10 and x==900 and y==openH and P._detailsGrowth.direction=='clamped',
   'S11: with no room below, the panel rises only until its bottom meets the screen edge and reports clamped',
   tostring(y)..' / '..openH..' '..tostring(P._detailsGrowth and P._detailsGrowth.direction))
  p.details:Click()
  -- Another panel scale: the corner is kept in screen units.
  NexusPanel:ClearAllPoints();NexusPanel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',700,650)
  Track(700,650,0.8)
  p.details:Click()
  x,y=Corner()
  C.expect(x~=nil and math.abs(x-700)<0.01 and math.abs(y-650)<0.01 and P._detailsGrowth.direction=='down',
   'S11: at panel scale 0.8 the held top is the same place',tostring(x)..','..tostring(y))
  p.details:Click()
  C.guard(Effects()==quiet,'S11: Show / Hide details saved nothing (panelX / panelY included), changed no Auto, action or send',Effects())
 end)
 P.Refresh=realRefresh
 NexusPanel.GetLeft,NexusPanel.GetTop,NexusPanel.GetEffectiveScale=nil,nil,nil
 P._playDetails=false;P._detailsHold=nil
 NexusPanel:ClearAllPoints();NexusPanel:SetPoint('RIGHT',UIParent,'RIGHT',-40,0)
 UIParent:SetSize(w0,h0)
 C.setup(ok,'S11: fixture: the Details scenario ran',err)
end)

-- Correction 3 item 2: the held top across a change of fit scale. Here the
-- panel's effective scale follows its real SetScale (LayoutMetrics.
-- FitToScreen, run by every applied render) and its corner is read from its
-- real anchor; nothing holds the scale constant. At font scale 2 the
-- expanded Play layout is taller than the UI allows and is fitted below
-- scale 1, while the collapsed one fits at 1 (the review's 1366 x 768 case;
-- a UI height between the two heights is used if this model's heights do
-- not straddle 768). Show details must keep the physical top while the scale
-- drops, and Hide details while it returns to 1: the held corner used to be
-- installed at the old scale and then moved by the fit (to y 930 or the
-- clamp). Memory only: no saved field changes. Native scale and clamping are
-- NOT RUN.
C.scenario('S12 Details keeps the physical top while the fit scale changes with it',function()
 local ss={tier='Heroic +2',ash='1,240',gain='20',intensity=250,intensityMax=500}
 local m=Model({owned=2,missing={'Cinder Lattice x2 (Rare:x2)','Hollow Bell'},shed={'Ashen Tithe'},
  toLock={'Gravecall Chorus'},serverStatus=ss})
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local realRefresh=P.Refresh
 P.Refresh=function() return P.Render(m) end
 local function Corner()
  local pt=NexusPanel.points[1]
  if not (pt and #NexusPanel.points==1 and pt[1]=='TOPLEFT' and pt[2]==UIParent and pt[3]=='BOTTOMLEFT') then return nil end
  return pt[4],pt[5]
 end
 local ok,err=pcall(function()
  G.UseFont(G.MODELS.double)
  UIParent:SetSize(1366,768)
  NexusPanel:SetScale(1)
  NexusPanel:ClearAllPoints();NexusPanel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',100,700)
  NexusPanel.GetEffectiveScale=function(self) return self:GetScale() end
  NexusPanel.GetLeft=function() local x=Corner();return x end
  NexusPanel.GetTop=function() local _,y=Corner();return y end
  P._detailsHold=nil
  P._playDetails=true;P.Render(m)
  local openH=NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.height
  P._playDetails=false;P.Render(m)
  local closedH=NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.height
  local p=NexusPanel._play
  if not C.setup(type(p)=='table' and p.details:IsShown() and openH and closedH and openH>closedH+2,
   'S12: fixture: the expanded Play layout is taller than the collapsed one at font scale 2',tostring(closedH)..' / '..tostring(openH)) then return end
  local uiH=768
  if not (closedH+24<=uiH and uiH<openH+24) then uiH=math.max(480,math.floor((closedH+openH)/2)+24) end
  UIParent:SetSize(1366,uiH)
  P.Render(m)
  if not C.setup(closedH+24<=uiH and uiH<openH+24 and math.abs(NexusPanel:GetScale()-1)<0.001,
   'S12: fixture: the collapsed panel fits at scale 1 and the expanded one needs less',
   closedH..' / '..openH..' in '..uiH..' at '..tostring(NexusPanel:GetScale())) then return end
  print('OBSERVED','S12 collapsed='..closedH..' expanded='..openH..' ui=1366x'..uiH)
  -- A physical top under which both the collapsed and the fitted expanded
  -- panel lie whole.
  local top=uiH-12
  NexusPanel:ClearAllPoints();NexusPanel:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',100,top)
  local quiet=Effects()
  p.details:Click()
  local x,y=Corner()
  local s=NexusPanel:GetScale()
  C.setup(P._playDetails==true and s<0.999,'S12: fixture: Show details fitted the expanded panel below scale 1',s)
  C.expect(x~=nil and math.abs(x*s-100)<0.01 and math.abs(y*s-top)<0.01 and P._detailsGrowth
   and P._detailsGrowth.direction=='down' and math.abs(P._detailsGrowth.top-top)<0.01,
   'S12: Show details keeps the physical top (and says down) while the fit scale drops',
   tostring(x and x*s)..','..tostring(y and y*s)..' at '..s)
  C.expect(y~=nil and (y-openH)*s>=-0.01,'S12: the fitted expanded panel lies whole above the screen bottom',tostring(y and (y-openH)*s))
  p.details:Click()
  x,y=Corner();s=NexusPanel:GetScale()
  C.setup(P._playDetails==false and math.abs(s-1)<0.001,'S12: fixture: Hide details fitted the collapsed panel at scale 1',s)
  C.expect(x~=nil and math.abs(x*s-100)<0.01 and math.abs(y*s-top)<0.01 and P._detailsGrowth
   and P._detailsGrowth.direction=='down' and math.abs(P._detailsGrowth.top-top)<0.01,
   'S12: Hide details keeps the physical top while the fit scale returns to 1, not the old local offset',
   tostring(x and x*s)..','..tostring(y and y*s)..' at '..s)
  C.expect(NexusPanel:GetHeight()==closedH,'S12: and gives back the whole section',NexusPanel:GetHeight())
  C.guard(Effects()==quiet,'S12: Show / Hide details across the fit saved nothing (panelX / panelY included), changed no Auto, action or send',Effects())
 end)
 P.Refresh=realRefresh
 NexusPanel.GetLeft,NexusPanel.GetTop,NexusPanel.GetEffectiveScale=nil,nil,nil
 P._playDetails=false;P._detailsHold=nil
 G.UseFont(G.MODELS.default)
 UIParent:SetSize(w0,h0)
 NexusPanel:SetScale(1)
 NexusPanel:ClearAllPoints();NexusPanel:SetPoint('RIGHT',UIParent,'RIGHT',-40,0)
 C.setup(ok,'S12: fixture: the scale scenario ran',err)
end)

-- Approved panel cleanup (the DPS section is one line of whole entries:
-- "Training DPS entries each stay whole and wrap as units"; no ellipsis or
-- clipping). In a stated font model, your record and the best known record
-- are each a label followed by its value: both share one line while both fit
-- (default text), each takes its own line when they do not (2.0 text), and
-- an entry wider than the line puts its value under its label. Every label
-- and value box is as wide as its text, inside the panel and apart from the
-- others, so nothing is shortened. The scope note takes no row (it is on the
-- best known hover, S4c). A regression model, not native font measurement.
C.scenario('S13 the DPS entries share one line while they fit and wrap as whole entries when they do not',function()
 local function Texts()
  local out={}
  for _,r in ipairs(G.Shown(NexusPanel)) do
   if r.kind=='FontString' and r:GetParent()==NexusPanel then
    local plain=Plain(r)
    if plain:find('Yours',1,true) or plain:find('Best known',1,true) or plain:find('4,812',1,true) or plain:find('5,130',1,true) then
     out[#out+1]=r
    end
   end
  end
  return out
 end
 -- Every DPS text is whole in its box, inside the panel and apart from the others.
 local function Whole(tag)
  local texts,ok,detail=Texts(),true,{}
  local panel={0,0,NexusPanel:GetWidth(),NexusPanel:GetHeight()}
  for i,r in ipairs(texts) do
   local rect=G.Rect(r,NexusPanel)
   detail[#detail+1]=Plain(r)..' '..G.Text(rect)..' needs '..r:GetStringWidth()
   if rect[3]-rect[1]+0.5<r:GetStringWidth() or not G.Inside(rect,panel) then ok=false end
   for j=i+1,#texts do if not G.Apart(rect,G.Rect(texts[j],NexusPanel)) then ok=false end end
  end
  C.expect(ok and #texts==4,tag..': each label and value is whole, inside the panel and apart from the others',table.concat(detail,' ; '))
 end
 local both=Model({bestDps={dummy={dps=4812}},performance={dummy={global={dps=5130,player='Synthetic'}},lk={}}})
 local ok,err=pcall(function()
  G.UseFont(G.MODELS.default)
  C.setup(P.Render(both)==true,'S13: fixture: both records at default text')
  local b=NexusPanel._responsiveLayout.boxes
  C.expect(b.bestDps~=nil and b.bestKnown~=nil and b.bestDps.y==b.bestKnown.y and not Nexus.LayoutMetrics.Overlap(b.bestDps,b.bestKnown),
   'S13: at default text both entries share one line',b.bestDps and b.bestKnown and (b.bestDps.y..' / '..b.bestKnown.y))
  C.expect(b.recordNote==nil and not ShownText():find('server-wide',1,true),'S13: the scope note takes no row',ShownText())
  Whole('S13 default text')
  local oneLine=NexusPanel:GetHeight()
  G.UseFont(G.MODELS.double)
  C.setup(P.Render(both)==true,'S13: fixture: both records at 2.0 text')
  b=NexusPanel._responsiveLayout.boxes
  C.expect(b.bestDps~=nil and b.bestKnown~=nil and b.bestKnown.y>=b.bestDps.y+b.bestDps.h,
   'S13: at 2.0 text each entry takes its own line',b.bestDps and b.bestKnown and (b.bestDps.y..'+'..b.bestDps.h..' / '..b.bestKnown.y))
  Whole('S13 2.0 text')
  -- Both targets recorded: the best known entry is wider than the line.
  local wide=Model({bestDps={dummy={dps=4812},lk={dps=3300}},
   performance={dummy={global={dps=5130,player='Synthetic'}},lk={global={dps=3400,player='Synthetic'}}}})
  C.setup(P.Render(wide)==true,'S13: fixture: Training Dummy and Lich King records at 2.0 text')
  Whole('S13 2.0 text, both targets')
  G.UseFont(G.MODELS.default)
  C.setup(P.Render(both)==true and NexusPanel:GetHeight()==oneLine,'S13: fixture: default text gives the one-line panel back',NexusPanel:GetHeight())
 end)
 G.UseFont(G.MODELS.default)
 C.setup(ok,'S13: fixture: the DPS line scenario ran',err)
end)

-- Approved panel cleanup ("Actual Auto changes must update both chip and
-- offer heading/instruction. Selecting a recommendation mode does not imply
-- Auto started; stale Random Roll data must not claim resumed picking"). The
-- panel's own notice of a changed Auto selection (Panel.SetAuto, called by
-- the Auto button after the real toggle) draws the chip, the offer heading
-- and the marked card's tag from that one selection, in both directions. A
-- Random Roll "running" fact the runtime gave for an earlier selection is not
-- carried into the new one: after OFF and ON again the Wishlist line says the
-- mode waits, never "(ON)", until the runtime says so again. SetAuto only
-- presents: it toggles, sends, saves and spends nothing. EXPECT fails before
-- the change by design (only the chip changed; the heading stayed).
C.scenario('S14 an Auto change updates the chip, the offer heading and the tag together; stale Random Roll data claims nothing',function()
 local m=Model({cards={{text='Frostwake Sigil (Rare)',highlight=true},{text='Hollow Bell (Rare)'},{text='Ashen Tithe (Uncommon)'}},
  recommendation='Take Frostwake Sigil.'})
 m.progress.activeSlot=2
 C.setup(P.Render(m)==true,'S14: fixture: an offer with Auto OFF renders')
 local chip,head=NexusPanel._autoBtn,NexusPanel._rollStatus
 local tag=NexusPanel._offerCards and NexusPanel._offerCards[1] and NexusPanel._offerCards[1].tag
 if not C.setup(chip:IsShown() and V.Plain(chip:GetText())=='Auto OFF' and Plain(head):find('Auto OFF',1,true)~=nil and tag~=nil
  and Plain(tag)=='> Wishlist pick','S14: fixture: chip, heading and tag say Auto OFF',Plain(head)) then return end
 local before=Effects()
 P.SetAuto(true)
 C.expect(V.Plain(chip:GetText())=='Auto ON' and Plain(head):find('Auto ON',1,true)~=nil and not Plain(head):find('Auto OFF',1,true)
  and not Plain(head):find('you choose',1,true),'S14: Auto ON shows on the chip and in the offer heading together',
  V.Plain(chip:GetText())..' / '..Plain(head))
 C.expect(Plain(tag)=='> Recommended','S14: the marked offer\'s tag follows the same selection',Plain(tag))
 P.SetAuto(false)
 C.expect(V.Plain(chip:GetText())=='Auto OFF' and Plain(head):find('Auto OFF',1,true)~=nil and Plain(tag)=='> Wishlist pick',
  'S14: Auto OFF shows on the chip, in the heading and on the tag together',V.Plain(chip:GetText())..' / '..Plain(head)..' / '..Plain(tag))
 C.guard(Effects()==before,'S14: presenting the selection makes no game action, send, saved-data or Auto change',Effects())
 -- Random Roll: with no Wishlist, the option on and the runtime's own
 -- "running" fact. The settings read is a boundary double for this check.
 local settings=Nexus.Store.Settings
 Nexus.Store.Settings=function()
  local s={};for k,v in pairs(settings()) do s[k]=v end
  s.autoPickLeveling,s.autoPick=true,true;return s
 end
 local ok,err=pcall(function()
  local rolling={status='ready',level=40,auto=true,randomRoll=true,cards={},recommendation='',
   progress={total=0,missing={},shed={},toLock={},unknownTomes={}},assignment={state='unassigned',knownUnassigned=true}}
  C.setup(P.Render(rolling)==true,'S14: fixture: Random Roll running with no Wishlist renders')
  local line=NexusPanel._contextWishlist
  if not C.setup(Plain(line):find('(ON)',1,true)~=nil,'S14: fixture: the Wishlist line says the mode is ON from the runtime\'s fact',Plain(line)) then return end
  P.SetAuto(false)
  C.guard(not Plain(line):find('(ON)',1,true) and Plain(line):find('Auto OFF',1,true)~=nil,'S14: Auto OFF ends the running words at once',Plain(line))
  P.SetAuto(true)
  C.expect(V.Plain(chip:GetText())=='Auto ON' and not Plain(line):find('(ON)',1,true) and Plain(line):find('waiting',1,true)~=nil,
   'S14: Auto ON again says the mode waits, never ON from the earlier fact',V.Plain(chip:GetText())..' / '..Plain(line))
 end)
 Nexus.Store.Settings=settings
 C.setup(ok,'S14: fixture: the Random Roll check ran',err)
 P.SetAuto(false)
end)

-- Approved panel cleanup ("Compact Auto ON. Put long explanation behind
-- optional disclosure"). With Auto ON and an offer, the long Auto scope
-- sentence (Readout.AUTO_ON_NOTE) is no longer always on the panel: one
-- short control names it, a click shows the whole sentence under the offer
-- and grows the panel, and another click gives the height back. It is memory
-- only and only shows text: it toggles no Auto, asks no confirmation of its
-- own, and sends, saves and spends nothing. With Auto OFF there is no such
-- control. EXPECT fails before the change by design (the sentence was always
-- shown with Auto ON).
C.scenario('S15 Auto ON is compact: its long explanation opens from a disclosure and closes again',function()
 local note=Nexus.Readout.AUTO_ON_NOTE
 local m=Model({cards={{text='Frostwake Sigil (Rare)',highlight=true},{text='Hollow Bell (Rare)'},{text='Ashen Tithe (Uncommon)'}},
  recommendation='Take Frostwake Sigil.'})
 m.auto=true
 m.progress.activeSlot=2
 C.setup(type(note)=='string' and #note>40 and P.Render(m)==true,'S15: fixture: an offer with Auto ON renders')
 local text=ShownText()
 C.expect(not text:find(note,1,true),'S15: with Auto ON the long explanation is not shown until asked for',text)
 local toggle=NexusPanel._autoInfoBtn
 C.expect(toggle~=nil and toggle:IsShown() and V.Plain(toggle:GetText() or ''):find('Auto explained',1,true)~=nil,
  'S15: one short control names the explanation',toggle and toggle:GetText())
 if not toggle then return end
 local closed=NexusPanel:GetHeight()
 local before=Effects()
 toggle:Click()
 C.setup(P.Render(m)==true,'S15: fixture: the same model rendered again after the click')
 text=ShownText()
 C.expect(text:find(note,1,true)~=nil and NexusPanel:GetHeight()>closed,'S15: a click shows the whole explanation and grows the panel',
  NexusPanel:GetHeight()..' / '..closed..' '..text)
 toggle:Click()
 P.Render(m)
 C.expect(not ShownText():find(note,1,true) and NexusPanel:GetHeight()==closed,'S15: another click hides it and gives the height back',
  NexusPanel:GetHeight()..' / '..closed)
 C.guard(Effects()==before,'S15: opening and closing the explanation makes no game action, send, saved-data or Auto change',Effects())
 C.guard(toggle:GetScript('OnDragStart')==nil and toggle._nexusPassiveDrag~=true,'S15: the control is a button, not a drag surface')
 m.auto=false
 P.Render(m)
 C.expect(not toggle:IsShown() and not ShownText():find(note,1,true),'S15: with Auto OFF there is no such control and no explanation',ShownText())
end)

-- Approved panel cleanup ("Compact A difficulty card ... Target 48 units with
-- short text and grow for wrapping/completed/localized text"; the original
-- reference card was 56 active / 66 completed). With short text and its
-- validated Intensity bar the card is 48 units, active and completed: tier
-- and multiplier on the first line, Soul Ash under the tier, the 6-unit bar
-- under them, all inside the card. A long localized tier wraps and the card
-- grows by the extra lines, with nothing overlapping; without a validated
-- Intensity scale there is no bar and no room kept for it. The card keeps its
-- theme exemption (its original backdrop and colours are never repainted);
-- its hover and Hardcore click are S8's. A stated font model, not native
-- measurement. EXPECT fails before the change by design (56 units, fixed
-- one-line boxes).
C.scenario('S16 Compact A difficulty card: 48 units with short text, grows for a wrapped tier, no room for an absent bar',function()
 local function Status(tier,bar)
  return {tier=tier,mode=tier,ash='1,240',gain='+45%',intensity=bar and 250 or nil,intensityMax=bar and 500 or nil,
   intensityThresholds=bar and {100,200,300,400} or nil,intensityLevel=bar and 2 or nil}
 end
 -- The card's texts in creation order: tier, Soul Ash, multiplier.
 local function Parts(card)
  local strings={}
  for _,region in ipairs(card.regions or {}) do if region.kind=='FontString' then strings[#strings+1]=region end end
  return strings[1],strings[2],strings[3]
 end
 local function Check(tag,card,bar)
  local tier,ash,gain=Parts(card)
  local c,t,a,g=G.Rect(card,NexusPanel),G.Rect(tier,NexusPanel),G.Rect(ash,NexusPanel),G.Rect(gain,NexusPanel)
  local detail='card '..G.Text(c)..' tier '..G.Text(t)..' ash '..G.Text(a)..' gain '..G.Text(g)
  C.expect(G.Inside(t,c) and G.Inside(a,c) and G.Inside(g,c) and G.Apart(t,g) and a[2]>=t[4]-0.01,
   tag..': tier and multiplier share the first line, Soul Ash is under the tier, all inside the card',detail)
  C.expect(tier:GetWidth()>0 and tier:GetHeight()+0.5>=tier:GetStringHeight() and gain:GetWidth()+0.5>=gain:GetStringWidth()
   and ash:GetWidth()+0.5>=ash:GetStringWidth(),tag..': the tier, Soul Ash and multiplier are whole in their boxes',
   tier:GetWidth()..'x'..tier:GetHeight()..' needs '..tier:GetStringHeight())
  if bar then
   local b=G.Rect(card.intensityBar,NexusPanel)
   C.expect(card.intensityBar:IsShown() and b[4]-b[2]==6 and b[2]>=a[4]-0.01 and G.Inside(b,c),
    tag..': the 6-unit Intensity bar is under the texts, inside the card',detail..' bar '..G.Text(b))
  end
 end
 local ok,err=pcall(function()
  G.UseFont(G.MODELS.default)
  C.setup(P.Render(Model({serverStatus=Status('HC3',true)}))==true,'S16: fixture: a short tier with a validated Intensity scale')
  local card=StatusCard()
  if not C.setup(card~=nil and card:IsShown() and card.intensityBar:IsShown(),'S16: fixture: the card and its bar are shown') then return end
  local box=NexusPanel._responsiveLayout.boxes.status
  C.expect(box~=nil and box.h==48 and card:GetHeight()==48,'S16: with short text and its bar the active card is 48 units',box and box.h)
  Check('S16 short',card,true)
  C.guard(card._nexusThemeExempt==true,'S16: the card stays exempt from the theme')
  C.setup(P.Render(Model({serverStatus=Status('HC3',true),owned=6}))==true,'S16: fixture: the completed build')
  C.expect(card:IsShown() and card:GetHeight()==48,'S16: the completed card is 48 units too',card:GetHeight())
  local long='Stufe IV: Heroische Frostgrab-Herausforderung der zersplitterten Frostwacht-Konklave des Nordens'
  C.setup(P.Render(Model({serverStatus=Status(long,true)}))==true,'S16: fixture: a long localized tier')
  local tier=Parts(card)
  -- The 48-unit card holds a 15-unit tier line: it grows by what the
  -- wrapped tier needs beyond that line.
  C.expect(tier:GetStringHeight()>15 and card:GetHeight()==48-15+tier:GetStringHeight()
   and card:GetHeight()==NexusPanel._responsiveLayout.boxes.status.h,
   'S16: a long tier wraps and the card grows by its extra lines',card:GetHeight()..' tier needs '..tier:GetStringHeight())
  Check('S16 long tier',card,true)
  C.setup(P.Render(Model({serverStatus=Status('HC3',false)}))==true,'S16: fixture: no validated Intensity scale')
  C.expect(not card.intensityBar:IsShown() and card:GetHeight()<48,'S16: without a validated Intensity scale there is no bar and no room kept for it',card:GetHeight())
  Check('S16 no bar',card,false)
 end)
 G.UseFont(G.MODELS.default)
 C.setup(ok,'S16: fixture: the card scenario ran',err)
end)

-- Approved panel cleanup ("Full offer names, recommendation and reason text.
-- Wrap and grow at normal and 125% text ... No clipping, ellipsis or
-- arbitrary line cap"). In a stated font model, at default and at 2.0 text:
-- a long offer name is shown whole, wrapped in its name column, and its row
-- is as tall as the wrapped name; the other rows follow below it, apart and
-- inside the offer block; the recommendation under the rows is as tall as
-- its wrapped text, inside the block; and the block and the panel grow by
-- what they need. Cards stay display only (P2 of play_offer_cards). EXPECT
-- fails before the change by design (one-line name boxes, a fixed body box).
C.scenario('S17 a long offer name and a long recommendation wrap in full; their rows and the offer block grow',function()
 local long='Glutgitter der Neunfach Versiegelten Aschenkammer des Vergessenen Schwellenwaechters der Frostgrabhoehle'
 local reason='Wunschlisten-Empfehlung: schliesst eine fehlende geplante Kopie fuer den Frostwacht-Hybrid und stuetzt die '
  ..'Grabesruf-Variante, weil kein anderes Angebot dieser Wahl ein noch fehlendes Ziel des zugewiesenen Plans erfuellt und '
  ..'die verbleibenden Wahlen dieses Laufs dafuer nicht mehr ausreichen wuerden.'
 local function Offer(name,rec)
  return Model({cards={{text=name..' (Epic) wanted',highlight=true},{text='Hollow Bell (Rare)'},{text='Ashen Tithe (Uncommon)'}},recommendation=rec})
 end
 local ok,err=pcall(function()
  for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do
   local tag='S17 '..model.name
   G.UseFont(model)
   C.setup(P.Render(Offer('Cinder Lattice','Take Cinder Lattice.'))==true,tag..': fixture: a short offer renders')
   local cards,rec,area=NexusPanel._offerCards,NexusPanel._rollRec,NexusPanel._rollArea
   if not C.setup(type(cards)=='table' and cards[1]:IsShown(),tag..': fixture: the offer rows are shown') then return end
   local shortH=NexusPanel:GetHeight()
   C.setup(P.Render(Offer(long,reason))==true,tag..': fixture: a long name and a long recommendation render')
   local name=cards[1].name
   C.expect(G.Visible(name:GetText())==long,tag..': the long name is shown whole, not shortened',name:GetText())
   C.expect(name:GetStringHeight()>model.line and name:GetHeight()+0.5>=name:GetStringHeight() and cards[1]:GetHeight()+0.5>=name:GetStringHeight(),
    tag..': the name wraps in its column and its row is as tall as the wrapped name',
    name:GetWidth()..'x'..name:GetHeight()..' row '..cards[1]:GetHeight()..' needs '..name:GetStringHeight())
   local a=G.Rect(area,NexusPanel)
   local r1,r2,r3=G.Rect(cards[1],NexusPanel),G.Rect(cards[2],NexusPanel),G.Rect(cards[3],NexusPanel)
   C.expect(G.Inside(r1,a) and G.Inside(r2,a) and G.Inside(r3,a) and r2[2]>=r1[4] and r3[2]>=r2[4],
    tag..': the rows follow each other, apart and inside the offer block',G.Text(r1)..' '..G.Text(r2)..' '..G.Text(r3)..' in '..G.Text(a))
   -- This offer is the marked one, so its recommendation is its reason: the
   -- approved design puts that inside the selected offer's own row, under
   -- its name (S24), not under the rows.
   local rr,nr=G.Rect(rec,NexusPanel),G.Rect(name,NexusPanel)
   C.expect(G.Visible(rec:GetText()):find('wuerden.',1,true)~=nil and rec:GetHeight()+0.5>=rec:GetStringHeight()
    and rr[2]>=nr[4]-0.01 and G.Inside(rr,r1,0.01),tag..': the recommendation is whole inside the selected offer\'s row, under its name',
    G.Text(rr)..' needs '..rec:GetStringHeight()..' row '..G.Text(r1))
   C.expect(NexusPanel:GetHeight()>shortH,tag..': the panel grows for them',NexusPanel:GetHeight()..' / '..shortH)
  end
 end)
 G.UseFont(G.MODELS.default)
 C.setup(ok,'S17: fixture: the wrapping scenario ran',err)
end)

-- Approved panel cleanup ("Wrap and grow at normal and 125% text; include
-- Build, Wishlist ... No clipping, ellipsis or arbitrary line cap"). In a
-- stated font model, at default and at 2.0 text: a long Saved Build name and
-- a long Wishlist name are each shown whole, wrapped beside their button;
-- each line's box is as tall as its wrapped text, the Wishlist line starts
-- under the Build line, My Builds and Change stay at the top of their own
-- line, apart, the header the layout reserves holds both lines, and what
-- follows the header starts below it. EXPECT fails before the change by
-- design (one-line 20-unit boxes that the client shortened).
C.scenario('S18 long Build and Wishlist names wrap in full beside their buttons; the header grows',function()
 local build='Hohle Flut der zersplitterten Frostwacht-Konklave des Nordens (Heroisch, zweite Fassung)'
 local wishlist='Frostwacht-Hybrid mit Grabesruf-Chor, Prioritaetsvariante drei fuer die lange Winterkampagne'
 local function Named(b,w)
  local m=Model()
  m.progress.activeSlot,m.progress.activeSlotName,m.progress.wishlistName=2,b,w
  return m
 end
 local ok,err=pcall(function()
  for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do
   local tag='S18 '..model.name
   G.UseFont(model)
   C.setup(P.Render(Named('Hollow Tide','Frostwake Hybrid'))==true,tag..': fixture: short names render')
   local shortH=NexusPanel:GetHeight()
   C.setup(P.Render(Named(build,wishlist))==true,tag..': fixture: long names render')
   local b,w=NexusPanel._contextBuild,NexusPanel._contextWishlist
   C.expect(G.Visible(b:GetText()):find(build,1,true)~=nil and G.Visible(w:GetText()):find(wishlist,1,true)~=nil,
    tag..': both names are shown whole',b:GetText()..' | '..w:GetText())
   C.expect(b:GetStringHeight()>model.line and b:GetHeight()+0.5>=b:GetStringHeight()
    and w:GetStringHeight()>model.line and w:GetHeight()+0.5>=w:GetStringHeight(),
    tag..': each line wraps and its box is as tall as its wrapped text',
    b:GetHeight()..'/'..b:GetStringHeight()..' '..w:GetHeight()..'/'..w:GetStringHeight())
   local br,wr=G.Rect(b,NexusPanel),G.Rect(w,NexusPanel)
   local sr,cr=G.Rect(NexusPanel._switchBtn,NexusPanel),G.Rect(NexusPanel._contextChange,NexusPanel)
   C.expect(wr[2]>=br[4]-0.01 and G.Apart(sr,cr) and G.Apart(sr,br) and G.Apart(cr,wr)
    and sr[2]<=br[2] and sr[4]>br[2] and cr[2]<=wr[2] and cr[4]>wr[2],
    tag..': the Wishlist line is under the Build line; My Builds and Change sit at the top of their own line, apart',
    G.Text(br)..' '..G.Text(wr)..' '..G.Text(sr)..' '..G.Text(cr))
   local boxes=NexusPanel._responsiveLayout.boxes
   local header=boxes.header
   local below
   for name,box in pairs(boxes) do
    if name~='header' and (not below or box.y<below) then below=box.y end
   end
   C.expect(header~=nil and wr[4]<=header.y+header.h+0.01 and cr[4]<=header.y+header.h+0.01 and below~=nil and below>=header.y+header.h,
    tag..': the header holds both lines and their buttons; what follows starts below it',
    header and (header.y+header.h)..' lines end '..wr[4]..' next '..tostring(below))
   C.expect(NexusPanel:GetHeight()>shortH,tag..': the panel grows for them',NexusPanel:GetHeight()..' / '..shortH)
  end
 end)
 G.UseFont(G.MODELS.default)
 C.setup(ok,'S18: fixture: the header scenario ran',err)
end)

-- Approved panel cleanup ("Wrap and grow at normal and 125% text; include
-- ... Callboard. No clipping, ellipsis or arbitrary line cap"). In a stated
-- font model, at default and at 2.0 text: a long Callboard objective title
-- is shown whole, wrapped, and every objective line is shown (no first line
-- with "+N more"); each box is as tall as its wrapped text, the lines are
-- under the title, both inside the Callboard box, and what follows starts
-- below it. The summary read is a boundary double for this check. EXPECT
-- fails before the change by design (one 17-unit line each, "+2 more").
C.scenario('S19 a long Callboard objective and all its lines are shown in full; the Callboard box grows',function()
 local title='Besiegt den Raureifgebundenen Waechter und zwei echogebundene Schildwachen in der Frostgrabhoehle vor der dritten Flut'
 local lines={'Raureifgebundener Waechter: 0 / 1 besiegt','Echogebundene Schildwachen: 1 / 2 besiegt','Dritte Flut: noch nicht begonnen'}
 local board=Nexus.CallboardStatus
 local real=board.GetSummary
 board.GetSummary=function() return {observed=true,title=title,lines={lines[1],lines[2],lines[3]}} end
 local ok,err=pcall(function()
  for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do
   local tag='S19 '..model.name
   G.UseFont(model)
   C.setup(P.Render(Model())==true,tag..': fixture: a build in progress with a Callboard objective renders')
   local t,l=NexusPanel._callboardTitle,NexusPanel._callboardLine
   if not C.setup(t~=nil and l~=nil and t:IsShown() and l:IsShown(),tag..': fixture: the Callboard rows are shown') then return end
   local shown=G.Visible(l:GetText() or '')
   C.expect(G.Visible(t:GetText())==title and shown:find(lines[1],1,true)~=nil and shown:find(lines[2],1,true)~=nil
    and shown:find(lines[3],1,true)~=nil and not shown:find('more',1,true),
    tag..': the whole title and every objective line are shown, with no "+N more"',shown)
   C.expect(t:GetStringHeight()>model.line and t:GetHeight()+0.5>=t:GetStringHeight() and l:GetHeight()+0.5>=l:GetStringHeight(),
    tag..': each box is as tall as its wrapped text',t:GetHeight()..'/'..t:GetStringHeight()..' '..l:GetHeight()..'/'..l:GetStringHeight())
   local tr,lr=G.Rect(t,NexusPanel),G.Rect(l,NexusPanel)
   local boxes=NexusPanel._responsiveLayout.boxes
   local box=boxes.callboard
   local below
   for name,other in pairs(boxes) do
    if box and name~='callboard' and other.y>box.y and (not below or other.y<below) then below=other.y end
   end
   C.expect(box~=nil and lr[2]>=tr[4]-0.01 and tr[2]>=box.y and lr[4]<=box.y+box.h+0.01 and below~=nil and below>=box.y+box.h,
    tag..': the lines are under the title, both inside the Callboard box, and what follows starts below it',
    G.Text(tr)..' '..G.Text(lr)..' box '..tostring(box and box.y)..'+'..tostring(box and box.h)..' next '..tostring(below))
  end
 end)
 board.GetSummary=real
 G.UseFont(G.MODELS.default)
 P.Render(Model())
 C.setup(ok,'S19: fixture: the Callboard scenario ran',err)
end)

-- Shared by S20-S25: every shown FontString of the panel itself whose text
-- holds one of `words` is whole in its box (wide enough for one line, or tall
-- enough for its wrapped text), inside the panel and apart from the others.
local function WholeTexts(tag,words,want)
 local texts,ok,detail={},true,{}
 for _,r in ipairs(G.Shown(NexusPanel)) do
  if r.kind=='FontString' and r:GetParent()==NexusPanel then
   local plain=Plain(r)
   for _,word in ipairs(words) do if plain:find(word,1,true) then texts[#texts+1]=r;break end end
  end
 end
 local panel={0,0,NexusPanel:GetWidth(),NexusPanel:GetHeight()}
 for i,r in ipairs(texts) do
  local rect=G.Rect(r,NexusPanel)
  detail[#detail+1]=Plain(r)..' '..G.Text(rect)
  local whole=rect[3]-rect[1]+0.5>=r:GetStringWidth() or rect[4]-rect[2]+0.5>=r:GetStringHeight()
  if not whole or not G.Inside(rect,panel) then ok=false end
  for j=i+1,#texts do if not G.Apart(rect,G.Rect(texts[j],NexusPanel)) then ok=false end end
 end
 C.expect(ok and (want==nil or #texts==want),tag..': each of these texts is whole, inside the panel and apart from the others',
  #texts..': '..table.concat(detail,' ; '))
end
local function LongOffer(rec,tag)
 return {{text='Cinder Lattice (Epic)'..(tag and (' '..tag) or ' wanted'),highlight=true},{text='Hollow Bell (Rare)'},{text='Ashen Tithe'}},rec
end

-- Approved panel cleanup, the opt-in DPS RECORDS section (Options > Show DPS
-- records): "Hide absent DPS/training sections completely ... Measured zero
-- is valid. Partial records show only actual rows." With the section turned
-- on: no record at all means no section, heading, "-" placeholder or reserved
-- block; a record of yours alone shows only its row; a record measured as 0
-- shows as 0; a best known record alone is shown under its target's name;
-- every shown text is whole. The toggle is the real Options row; it is put
-- back afterwards. EXPECT fails before the change by design (a fixed block
-- with a dash for every missing record).
C.scenario('S20 the opt-in DPS RECORDS section shows only records that exist; none means no section',function()
 local function Toggle()
  for _,item in ipairs(P.MoreMenuItems()) do if item.nexusId=='dps_records' then item.func();return true end end
 end
 local function Shown(perf,o)
  o=o or {}
  o.performance=perf
  C.setup(P.Render(Model(o))==true,'S20: fixture: rendered')
  return ShownText(),NexusPanel._responsiveLayout.boxes.performance,NexusPanel:GetHeight()
 end
 local ok,err=pcall(function()
  G.UseFont(G.MODELS.default)
  local _,_,offH=Shown(nil)
  if not C.setup(Toggle()==true and P.SavedLayoutRoot().uiShowPerformance==true,'S20: fixture: Options > Show DPS records turned the section on') then return end
  local text,box,h=Shown(nil)
  C.expect(box==nil and h==offH and not text:find('DPS RECORDS',1,true) and not text:find('—',1,true),
   'S20: without any record there is no section, heading, placeholder or reserved block',tostring(h)..' / '..offH..' '..text)
  text,box=Shown({dummy={personal={dps=12000}},lk={}})
  local oneH=NexusPanel:GetHeight()
  C.expect(box~=nil and text:find('DPS RECORDS',1,true)~=nil and text:find('Your Dummy',1,true)~=nil and text:find('12k',1,true)~=nil,
   'S20: a Training Dummy record of yours shows its row under the section heading',text)
  C.expect(not text:find('Lich King',1,true) and not text:find('Best known',1,true) and not text:find('—',1,true),
   'S20: the records that do not exist have no row and no placeholder',text)
  WholeTexts('S20 yours only',{'DPS RECORDS','Your Dummy','12k','Target build'})
  text,box=Shown({dummy={personal={dps=0}},lk={}})
  C.expect(box~=nil and text:find('Your Dummy',1,true)~=nil and text:find('| 0 |',1,true)~=nil and not text:find('—',1,true),
   'S20: a record measured as 0 is shown as 0, not as missing',text)
  text,box=Shown({dummy={},lk={global={dps=31000,player='Synthetic'}}})
  C.expect(box~=nil and text:find('LICH KING',1,true)~=nil and text:find('31k',1,true)~=nil and not text:find('Your Lich King',1,true)
   and not text:find('Your Dummy',1,true) and not text:find('—',1,true),
   'S20: a best known record alone is shown under its target\'s name, with no row of yours',text)
  text,box=Shown({dummy={personal={dps=12000},global={dps=25000,player='A'}},lk={personal={dps=9000},global={dps=31000,player='B'}}})
  C.expect(box~=nil and NexusPanel:GetHeight()>oneH and text:find('25k',1,true)~=nil and text:find('9k',1,true)~=nil and text:find('31k',1,true)~=nil
   and not text:find('—',1,true),'S20: all four records show their rows and the section grows for them',NexusPanel:GetHeight()..' / '..oneH)
  WholeTexts('S20 all four',{'DPS RECORDS','Your Dummy','Your Lich King','12k','25k','9k','31k'})
  text,box=Shown({dummy={personal={dps=12000},global={dps=25000,player='A'}},lk={}},{owned=6})
  C.expect(box~=nil and text:find('TRAINING DUMMY',1,true)~=nil and not text:find('LICH KING',1,true) and not text:find('—',1,true),
   'S20: the completed view shows only the target that has records',text)
 end)
 if P.SavedLayoutRoot().uiShowPerformance==true then Toggle() end
 C.setup(ok and P.SavedLayoutRoot().uiShowPerformance~=true,'S20: fixture: the section scenario ran and the choice was put back',err)
 P.Render(Model())
end)

-- Approved panel cleanup, progress: the run's count is hidden with the other
-- four counts until Details is opened, and takes no row while it is; the bar
-- sits on the heading row between the heading and the Details button while
-- they fit; with Details open the count has its own whole row. EXPECT fails
-- before the change by design (the count had its own row above the bar).
C.scenario('S21 collapsed progress is one row: heading, bar and Details; the run count shows only with Details',function()
 local ok,err=pcall(function()
  G.UseFont(G.MODELS.default)
  P._playDetails=false
  C.setup(P.Render(Model())==true,'S21: fixture: a build in progress, Details closed')
  local b=NexusPanel._responsiveLayout.boxes
  local p=NexusPanel._play
  C.expect(b.progressValue==nil and not ShownText():find('rolled copies',1,true),
   'S21: with Details closed the run count is not shown and has no row',ShownText())
  C.expect(b.planBar~=nil and b.planDetails~=nil and b.progressHeader~=nil and b.progressHeader.y==b.planDetails.y
   and b.planBar.y>=b.planDetails.y and b.planBar.y+b.planBar.h<=b.planDetails.y+b.planDetails.h
   and b.planBar.x>=b.progressHeader.x+b.progressHeader.w and b.planBar.x+b.planBar.w<=b.planDetails.x,
   'S21: the bar is on the heading row, between the heading and the Details button',
   b.planBar and (b.planBar.x..','..b.planBar.y..' '..b.planBar.w..'x'..b.planBar.h))
  C.guard(p.details:IsShown() and Plain(p.details)=='Show details' and p.track:IsShown(),'S21: the bar and Show details stay')
  p.details:Click()
  C.setup(P.Render(Model())==true and P._playDetails==true,'S21: fixture: Details opened')
  b=NexusPanel._responsiveLayout.boxes
  C.expect(b.progressValue~=nil and ShownText():find('2 / 6 rolled copies this run',1,true)~=nil,
   'S21: with Details open the run count has its own row',ShownText())
  WholeTexts('S21 Details',{'rolled copies','Still needed','Missing tomes','Extra copies','Locked targets'},5)
  p.details:Click()
  P.Render(Model())
  C.expect(NexusPanel._responsiveLayout.boxes.progressValue==nil and not ShownText():find('rolled copies',1,true),
   'S21: Hide details hides the count again')
 end)
 P._playDetails=false
 C.setup(ok,'S21: fixture: the progress scenario ran',err)
end)

-- Approved panel cleanup, structure: compact 8-unit side insets for every
-- body block, and two-line footer hubs: each hub's name with, under it, what
-- it opens, in existing words (Wishlist Editor; Build Library and
-- Leaderboard; Orbs / Lost Memories). Explore's line carries the two names
-- its menu rows and the opened windows use, in full; it wraps inside its hub
-- rather than being shortened. The hubs keep their routes (their own click
-- handlers).
C.scenario('S22 body blocks keep one compact inset; the footer hubs are two-line with what each opens',function()
 G.UseFont(G.MODELS.default)
 local ss={tier='HC3',mode='HC3',ash='1,240',gain='+45%'}
 local cards,rec=LongOffer('Take Cinder Lattice.')
 C.setup(P.Render(Model({serverStatus=ss,cards=cards,recommendation=rec,bestDps={dummy={dps=4812}}}))==true,'S22: fixture: a Play panel with card, offer and a record')
 local l=NexusPanel._responsiveLayout
 local off={}
 for name,box in pairs(l.boxes) do
  if box.x<8 or box.x+box.w>l.width-8 then off[#off+1]=name end
 end
 for _,name in ipairs({'status','roll','progressHeader','bestDps','footer','header'}) do
  if not (l.boxes[name] and l.boxes[name].x==8) then off[#off+1]=name..' x='..tostring(l.boxes[name] and l.boxes[name].x) end
 end
 C.expect(#off==0,'S22: every block starts at the 8-unit inset and ends inside it',table.concat(off,', '))
 local hubs=NexusPanel._footerButtons or {}
 local want={plan='Wishlist Editor',explore='Build Library · Leaderboard',orbs='Orbs / Lost Memories'}
 local heights={}
 for key,words in pairs(want) do
  local hub=hubs[key]
  local sub
  for _,r in ipairs(hub and hub.regions or {}) do
   if r.kind=='FontString' and r:IsShown() and Plain(r)==words then sub=r end
  end
  C.expect(hub~=nil and hub:IsShown() and sub~=nil,'S22: the '..key..' hub says what it opens: '..words)
  if hub and sub then
   local hr,sr=G.Rect(hub,NexusPanel),G.Rect(sub,NexusPanel)
   C.expect(G.Inside(sr,hr,0.01) and (sr[3]-sr[1]+0.5>=sub:GetStringWidth() or sr[4]-sr[2]+0.5>=sub:GetStringHeight())
    and sr[2]-hr[2]>=12,'S22: the '..key..' hub\'s second line is whole inside the hub, under its name',G.Text(sr)..' in '..G.Text(hr))
   C.guard(type(hub:GetScript('OnClick'))=='function','S22: the '..key..' hub keeps its click route')
   heights[#heights+1]=hub:GetHeight()
  end
 end
 C.expect(#heights==3 and heights[1]==heights[2] and heights[2]==heights[3] and heights[1]==l.boxes.footer.h,
  'S22: the three hubs share the footer row\'s height',table.concat(heights,'/'))
end)

-- Approved panel cleanup, Auto ON takes no row of its own: the explanation
-- control shares the offer heading's row, so an Auto ON panel is as tall as
-- the same Auto OFF panel while the explanation is closed. At a text size
-- where it cannot share the row it takes its own, and nothing overlaps.
C.scenario('S23 the Auto explanation control adds no row at normal text',function()
 local ok,err=pcall(function()
  local function Offer(auto)
   local cards,rec=LongOffer('Take Cinder Lattice.')
   local m=Model({cards=cards,recommendation=rec})
   m.auto=auto
   m.progress.activeSlot=2
   return m
  end
  for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do
   G.UseFont(model)
   C.setup(P.Render(Offer(false))==true,'S23: fixture: Auto OFF offer at '..model.name)
   local offH=NexusPanel:GetHeight()
   C.setup(P.Render(Offer(true))==true,'S23: fixture: Auto ON offer at '..model.name)
   local toggle=NexusPanel._autoInfoBtn
   if C.setup(toggle~=nil and toggle:IsShown() and not (NexusPanel._autoScopeText and NexusPanel._autoScopeText:IsShown()),
    'S23: fixture: the control is shown and the explanation closed at '..model.name) then
    local tr,hr=G.Rect(toggle,NexusPanel),G.Rect(NexusPanel._rollStatus,NexusPanel)
    C.expect(G.Apart(tr,hr) and G.Inside(tr,{0,0,NexusPanel:GetWidth(),NexusPanel:GetHeight()}),
     'S23 '..model.name..': the control is apart from the heading, inside the panel',G.Text(tr)..' '..G.Text(hr))
    if model==G.MODELS.default then
     C.expect(NexusPanel:GetHeight()==offH and tr[2]<hr[4] and tr[4]>hr[2],
      'S23: at default text the control shares the heading row and Auto ON adds no height',NexusPanel:GetHeight()..' / '..offH..' '..G.Text(tr))
    end
   end
  end
 end)
 G.UseFont(G.MODELS.default)
 C.setup(ok,'S23: fixture: the Auto control scenario ran',err)
end)

-- Approved panel cleanup, the selected offer's reason: the complete
-- recommendation is inside the selected (marked) offer's own row, under its
-- name, and is not repeated under the rows; the row is as tall as its name
-- and reason, and the other rows follow it. Without an offer row the
-- recommendation stays under the heading, whole.
C.scenario('S24 the selected offer\'s reason is inside its row; a cardless recommendation stays whole under the heading',function()
 local reason='Wunschlisten-Empfehlung: schliesst eine fehlende geplante Kopie fuer den Frostwacht-Hybrid und stuetzt die Grabesruf-Variante.'
 local ok,err=pcall(function()
  for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do
   local tag='S24 '..model.name
   G.UseFont(model)
   for _,auto in ipairs({false,true}) do
    local cards=LongOffer()
    local m=Model({cards=cards,recommendation=reason})
    m.auto=auto
    C.setup(P.Render(m)==true,tag..': fixture: a marked offer with a recommendation, Auto '..tostring(auto))
    local c,rec=NexusPanel._offerCards,NexusPanel._rollRec
    local r1,r2,rr,nr=G.Rect(c[1],NexusPanel),G.Rect(c[2],NexusPanel),G.Rect(rec,NexusPanel),G.Rect(c[1].name,NexusPanel)
    C.expect(G.Visible(rec:GetText()):find('Grabesruf-Variante',1,true)~=nil and G.Inside(rr,r1,0.01) and rr[2]>=nr[4]-0.01
     and rec:GetHeight()+0.5>=rec:GetStringHeight() and r2[2]>=r1[4],
     tag..': Auto '..tostring(auto)..': the whole reason is inside the selected row under its name; the next row follows',
     G.Text(rr)..' in '..G.Text(r1)..' name '..G.Text(nr)..' needs '..rec:GetStringHeight())
    local count=0
    for _,r in ipairs(G.Shown(NexusPanel)) do
     if r.kind=='FontString' and G.Visible(r:GetText() or ''):find('Grabesruf-Variante',1,true) then count=count+1 end
    end
    C.expect(count==1,tag..': Auto '..tostring(auto)..': the reason is shown once',count)
   end
   C.setup(P.Render(Model({recommendation=reason}))==true,tag..': fixture: a recommendation without an offer row')
   local rec,head=NexusPanel._rollRec,NexusPanel._rollStatus
   local rr,hr,a=G.Rect(rec,NexusPanel),G.Rect(head,NexusPanel),G.Rect(NexusPanel._rollArea,NexusPanel)
   C.expect(rec:GetHeight()+0.5>=rec:GetStringHeight() and rr[2]>=hr[4]-0.01 and G.Inside(rr,a,0.01),
    tag..': a cardless recommendation is whole under the heading, inside the block',G.Text(rr)..' needs '..rec:GetStringHeight())
  end
 end)
 G.UseFont(G.MODELS.default)
 C.setup(ok,'S24: fixture: the reason scenario ran',err)
end)

-- Approved panel cleanup, full text at the supported sizes: the Orb run line,
-- an offer's tag and the charges are shown whole on the panel (wrapped where
-- they do not fit one line), not completed only by a hover; an offer whose
-- quality is not known still says so beside its uncoloured name.
C.scenario('S25 the Orb run line, a long offer tag and the charges are whole on the panel; an unknown quality is said',function()
 local runtime=Nexus.OrbRuntime
 local compact=runtime.CompactStatus
 local ok,err=pcall(function()
  runtime.CompactStatus=function()
   return {state='WAIT_RESULT',spent=2,limit=5,reserved=1,running=true,pending=true,canResume=false,
    uncertain=0,unconfirmedResults=0,historyKnown=true,remaining=3,limitKnown=true}
  end
  for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do
   local tag='S25 '..model.name
   G.UseFont(model)
   -- The long status words are on the second, unmarked offer (a marked
   -- offer's tag is its pick tag).
   local cards=LongOffer()
   cards[2]={text='Hollow Bell (Rare) Different quality from target (wants Legendary), owned 2 of 3 planned copies'}
   local m=Model({cards=cards,recommendation='Take Cinder Lattice.'})
   m.charges={banish=12,reroll=10,freeze=10,trustworthy=true,arrived=true}
   m.progress.activeSlot=2
   C.setup(P.Render(m)==true,tag..': fixture: an offer with a long tag, charges and an Orb run')
   local p,c=NexusPanel._play,NexusPanel._offerCards
   local orb,tagText,charges,head=p.orb,c[2] and c[2].tag,NexusPanel._chargesText,NexusPanel._rollStatus
   local function Whole(fs) return fs:IsShown() and (fs:GetWidth()+0.5>=fs:GetStringWidth() or fs:GetHeight()+0.5>=fs:GetStringHeight()) end
   C.expect(orb:IsShown() and Whole(orb),tag..': the Orb run line is whole',orb:GetWidth()..'x'..orb:GetHeight()..' needs '..orb:GetStringWidth()..' / '..orb:GetStringHeight())
   C.expect(tagText~=nil and G.Visible(tagText:GetText()):find('planned copies',1,true)~=nil and Whole(tagText),
    tag..': the long offer tag is whole in its column',tagText and (tagText:GetWidth()..'x'..tagText:GetHeight()..' needs '..tagText:GetStringWidth()..' / '..tagText:GetStringHeight()))
   C.expect(charges:IsShown() and Whole(charges) and Whole(head),tag..': the charges and the offer heading are whole',
    charges:GetWidth()..'x'..charges:GetHeight()..' needs '..charges:GetStringWidth()..'; heading '..head:GetWidth()..'x'..head:GetHeight()..' needs '..head:GetStringWidth())
   local rects={G.Rect(orb,NexusPanel),G.Rect(charges,NexusPanel),G.Rect(head,NexusPanel),G.Rect(c[1],NexusPanel),G.Rect(c[2],NexusPanel),G.Rect(c[3],NexusPanel)}
   local apart=true
   for i=1,#rects do for j=i+1,#rects do if not G.Apart(rects[i],rects[j]) then apart=false end end end
   C.expect(apart,tag..': the Orb line, the charges, the heading and the offer rows are apart')
   C.guard(G.Visible(c[3].quality:GetText() or ''):find('Quality unknown',1,true)~=nil and c[3].quality:IsShown(),
    tag..': an offer without a known quality says so beside its name',c[3].quality:GetText())
  end
 end)
 runtime.CompactStatus=compact
 G.UseFont(G.MODELS.default)
 P.Render(Model())
 C.setup(ok,'S25: fixture: the full-text scenario ran',err)
end)

-- Approved panel cleanup, the selected offer ("The selected row is a filled
-- band with a 2-unit accent bar, not an outline"): the one selected row (the
-- runtime's marked offer) shows a 2-unit bar along its left edge, as tall as
-- the row, just outside its icon; the other rows show none, and without a
-- selected offer no row does. No outline is drawn and the rows stay
-- display-only. EXPECT fails before the change by design (the selected row
-- was told by its tag alone).
C.scenario('S26 the selected offer row is a band with a 2-unit accent bar; no outline, no click',function()
 G.UseFont(G.MODELS.default)
 local function Bars()
  local c,shown=NexusPanel._offerCards,{}
  for i=1,3 do shown[i]=(c[i].accent~=nil and c[i].accent:IsShown()) and true or false end
  return c,shown
 end
 local cards=LongOffer('Take Cinder Lattice.')
 C.setup(P.Render(Model({cards=cards,recommendation='Take Cinder Lattice.'}))==true,'S26: fixture: an offer whose first row is selected')
 local c,shown=Bars()
 C.expect(shown[1] and not shown[2] and not shown[3],'S26: only the selected row shows the accent bar',
  tostring(shown[1])..'/'..tostring(shown[2])..'/'..tostring(shown[3]))
 if shown[1] then
  local bar,row,icon=G.Rect(c[1].accent,NexusPanel),G.Rect(c[1],NexusPanel),G.Rect(c[1]._nexusSlot.icon,NexusPanel)
  local area=G.Rect(NexusPanel._rollArea,NexusPanel)
  C.expect(bar[3]-bar[1]==2 and bar[2]==row[2] and bar[4]==row[4] and bar[3]<=icon[1] and G.Inside(bar,area,0.01),
   'S26: the bar is 2 units wide, as tall as the row, left of the icon and inside the offer block',G.Text(bar)..' row '..G.Text(row))
 end
 local clickable,outlined=false,false
 for i=1,3 do
  if c[i]:GetScript('OnClick') or c[i]:GetScript('OnMouseUp') or c[i]:GetScript('OnMouseDown') then clickable=true end
  if c[i].edges~=nil or (c[i]._nexusSlot and c[i]._nexusSlot.edges~=nil) then outlined=true end
 end
 C.guard(not clickable and not outlined,'S26: the rows stay display-only, with no outline')
 C.setup(P.Render(Model({cards={{text='Cinder Lattice (Epic)'},{text='Hollow Bell (Rare)'},{text='Ashen Tithe'}}}))==true,
  'S26: fixture: an offer with no selected row')
 c,shown=Bars()
 C.expect(not shown[1] and not shown[2] and not shown[3],'S26: without a selected offer no row shows the bar',
  tostring(shown[1])..'/'..tostring(shown[2])..'/'..tostring(shown[3]))
 P.Render(Model())
end)

-- Approved panel cleanup ("no empty reserved space for hidden sections in
-- any state"). With no Wishlist and an Echo board open, the setup view kept a
-- least height from the former fixed columns (428 units), which the compact
-- header, card and measured offer block no longer fill: an empty band stood
-- between Create Wishlist and the footer. Every view is as tall as its
-- content. EXPECT fails before the correction (the footer sat at the kept
-- least height); GUARD: without a board the footer already followed the
-- last setup button.
C.scenario('S27 no Wishlist with an Echo board: the footer follows the last setup button, with no kept least height',function()
 G.UseFont(G.MODELS.default)
 local function Setup(cards,server)
  return {status='ready',level=40,auto=false,cards=cards or {},recommendation=cards and 'Take Frostwake Sigil.' or '',
   progress={total=0,missing={},shed={},toLock={},unknownTomes={}},assignment={state='unassigned',knownUnassigned=true},
   serverStatus=server}
 end
 local BOARD={{text='Frostwake Sigil (Rare)',highlight=true},{text='Hollow Bell (Rare)'},{text='Ashen Tithe (Uncommon)'}}
 local SERVER={tier='HC3',ash='12,345',gain='+12.5%',intensity=40,intensityMax=100,intensityThresholds={20,40,60,80}}
 -- The footer against the last setup box: one layout gap (the gap between
 -- the two setup buttons) under it, and the panel ends 6 units under the footer.
 local function Tail(tag)
  local layout=NexusPanel._responsiveLayout
  local boxes=type(layout)=='table' and layout.boxes or {}
  local assign,create,footer=boxes.setupAssign,boxes.setupCreate,boxes.footer
  if not C.setup(assign and create and footer,tag..': fixture: the setup view lays out both buttons and the footer') then return nil end
  local gap=create.y-(assign.y+assign.h)
  local band=footer.y-(create.y+create.h)
  print('OBSERVED',tag,'create ends '..tostring(create.y+create.h),'footer '..tostring(footer.y),'band '..tostring(band),
   'gap '..tostring(gap),'height '..tostring(NexusPanel:GetHeight()))
  return band,gap,NexusPanel:GetHeight()==footer.y+footer.h+6 and NexusPanel:GetHeight()==layout.height
 end
 C.setup(P.Render(Setup())==true,'S27: fixture: the setup view with no board renders')
 local band,gap,closed=Tail('S27 no board')
 if band==nil then return end
 C.guard(band==gap and closed,'S27: without a board the footer follows Create Wishlist by one gap',tostring(band)..' / '..tostring(gap))
 for _,case in ipairs({{'with the difficulty card',SERVER},{'without the difficulty card',nil}}) do
  local tag='S27 board '..case[1]
  C.setup(P.Render(Setup(BOARD,case[2]))==true and NexusPanel._offerCards[1]:IsShown() and NexusPanel._offerCards[3]:IsShown(),
   tag..': fixture: the setup view shows the three offers')
  band,gap,closed=Tail(tag)
  if band==nil then return end
  C.expect(band==gap,tag..': the footer follows Create Wishlist by one gap (no empty band)',tostring(band)..' / '..tostring(gap))
  C.expect(closed,tag..': the panel ends 6 units under the footer, at the layout height',NexusPanel:GetHeight())
 end
 P.Render(Model())
end)

-- Approved panel cleanup ("actual Auto changes must update both chip and
-- offer heading/instruction; stale Random Roll data must not claim resumed
-- picking"). The runtime does not render for a toggle, so the panel draws the
-- new selection itself (S14). The host's display refresh then renders its own
-- last input again, which is from before the toggle: the chip, heading, tag
-- and Random Roll line went back to the superseded selection until the next
-- runtime step. A refresh render keeps the selection the panel was last told
-- (Panel.SetAuto) while the runtime's own counter agrees with it. EXPECT
-- fails before the correction; GUARD: a direct render is drawn as given, and
-- a notice the runtime's counter contradicts changes nothing.
-- The lifecycle callbacks are replaced for this last scenario (Panel.Init
-- keeps one table): RefreshDisplay renders `host`, the host's last input.
C.scenario('S28 a display refresh from before an Auto change keeps the actual selection on the chip, heading, tag and Wishlist line',function()
 G.UseFont(G.MODELS.default)
 local function Offer(auto)
  local m=Model({cards={{text='Frostwake Sigil (Rare)',highlight=true},{text='Hollow Bell (Rare)'},{text='Ashen Tithe (Uncommon)'}},
   recommendation='Take Frostwake Sigil.'})
  m.progress.activeSlot=2
  m.auto=auto
  return m
 end
 local host,refreshes=nil,0
 P.Init({RefreshDisplay=function() refreshes=refreshes+1;return P.Render(host) end})
 local stats=Nexus.RecomputeStats
 local actual=false
 -- Boundary double: the runtime's own selection counter, as this check sets it.
 Nexus.RecomputeStats=function()
  local s={};for k,v in pairs(stats()) do s[k]=v end
  s.autoEnabled=actual;return s
 end
 local chip,head=NexusPanel._autoBtn,NexusPanel._rollStatus
 local function Shown()
  local tag=NexusPanel._offerCards[1].tag
  return V.Plain(chip:GetText())..' / '..Plain(head)..' / '..Plain(tag)
 end
 local function Says(on)
  local tag=Plain(NexusPanel._offerCards[1].tag)
  local heading=Plain(head)
  if on then
   return V.Plain(chip:GetText())=='Auto ON' and heading:find('Auto ON',1,true)~=nil and not heading:find('Auto OFF',1,true)
    and tag=='> Recommended'
  end
  return V.Plain(chip:GetText())=='Auto OFF' and heading:find('Auto OFF',1,true)~=nil and not heading:find('Auto ON',1,true)
   and tag=='> Wishlist pick'
 end
 local ok,err=pcall(function()
  -- Auto was ON; the player turns it OFF; the host still holds the ON input.
  actual=true
  host=Offer(true)
  C.setup(P.Render(host)==true and Says(true),'S28: fixture: an offer with Auto ON renders',Shown())
  actual=false
  P.SetAuto(false)
  C.setup(Says(false),'S28: fixture: the Auto OFF notice is drawn at once',Shown())
  local before=Effects()
  local count=refreshes
  P.Refresh()
  C.setup(refreshes==count+1,'S28: fixture: the refresh rendered the host input from before the toggle',refreshes-count)
  C.expect(Says(false),'S28: after the refresh the chip, heading and tag still say Auto OFF',Shown())
  host.serverStatus={tier='HC3',ash='12,346',gain='+12.5%',intensity=41,intensityMax=100}
  P.Refresh()
  C.expect(Says(false),'S28: a second refresh with changed values keeps Auto OFF too',Shown())
  -- The mirror: Auto was OFF; it is turned ON; the host holds the OFF input.
  host=Offer(false)
  C.setup(P.Render(host)==true and Says(false),'S28: fixture: the offer with Auto OFF renders',Shown())
  actual=true
  P.SetAuto(true)
  C.setup(Says(true),'S28: fixture: the Auto ON notice is drawn at once',Shown())
  P.Refresh()
  C.expect(Says(true),'S28: after the refresh the chip, heading and tag still say Auto ON',Shown())
  -- A render that is not a refresh is the runtime's own and is drawn as given.
  C.guard(P.Render(Offer(false))==true and Says(false),'S28: a direct render is drawn with its own selection',Shown())
  -- A notice the runtime's counter contradicts is not applied to a refresh.
  host=Offer(false)
  actual=false
  P.Refresh()
  C.guard(Says(false),'S28: a refresh is not changed by a notice the runtime\'s own counter contradicts',Shown())
  -- Random Roll, no Wishlist: the host's "running" input after Auto OFF.
  local settings=Nexus.Store.Settings
  Nexus.Store.Settings=function()
   local s={};for k,v in pairs(settings()) do s[k]=v end
   s.autoPickLeveling,s.autoPick=true,true;return s
  end
  local rolled,why=pcall(function()
   actual=true
   P.SetAuto(true)
   host={status='ready',level=40,auto=true,randomRoll=true,cards={},recommendation='',
    progress={total=0,missing={},shed={},toLock={},unknownTomes={}},assignment={state='unassigned',knownUnassigned=true}}
   local line=NexusPanel._contextWishlist
   if not C.setup(P.Render(host)==true and Plain(line):find('(ON)',1,true)~=nil,
    'S28: fixture: Random Roll running with no Wishlist renders',Plain(line)) then return end
   actual=false
   P.SetAuto(false)
   C.setup(not Plain(line):find('(ON)',1,true),'S28: fixture: Auto OFF ends the running words at once',Plain(line))
   P.Refresh()
   C.expect(not Plain(line):find('(ON)',1,true) and Plain(line):find('Auto OFF',1,true)~=nil,
    'S28: after the refresh the Wishlist line still does not claim Random Roll is running',Plain(line))
  end)
  Nexus.Store.Settings=settings
  C.setup(rolled,'S28: fixture: the Random Roll check ran',why)
  C.guard(Effects()==before,'S28: refreshing makes no game action, send, saved-data or Auto change',Effects())
 end)
 Nexus.RecomputeStats=stats
 -- No host callback from here on: Panel.Refresh renders its last model.
 P.Init({})
 C.setup(ok,'S28: fixture: the refresh checks ran',err)
 P.SetAuto(false)
 P.Render(Model())
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(Play summary rows; native NOT RUN)')
