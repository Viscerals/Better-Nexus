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
-- The visual corrections of the main panel:
-- the panel's width follows the text scale (S13), the plan progress is a
-- caption with the compact Details button at its right and a full-width bar
-- below (S21), the three footer hubs are one width and span the footer row,
-- with Help reached from Options (S22), the selected offer row is told by a
-- thin accent outline around a dark fill (S26), and the difficulty card's
-- tier and multiplier start on one line (S16). Each assertion of the former
-- look that these replace is marked where it stood; it is replaced by the
-- new look's own assertion, not relaxed.
-- Count disclosure: the compact banish, reroll and freeze charges are counts
-- and are on the panel only while Details is open (S32; S25 checks them
-- whole with Details open).
-- The approved compact panel (design draft "Nexus compact panel": 420
-- reference pixels wide, where the reference panel is 284 units; difficulty
-- band B with its bar and ticks; one-line footer hubs). EXPECT, failing at
-- eef1608f by design: the difficulty card is the band (S3, S10, S16); the
-- plan progress is one row, its bar between the caption and Details (S21);
-- the body's inset is the draft's and the three footer hubs are one line,
-- "Wishlist", "Builds" and "Orbs", each saying what it opens on its hover
-- (S22); with Auto OFF the offer heading is "Your offers" with the
-- destination in a cell of its own, and a selected row's tag stands after a
-- star (S14, S28, S32); an offer whose model card carries a "different
-- quality" annotation code shows the short "Wrong quality" on its row, with
-- the complete annotation whole on the row's hover, while a card that
-- carries only its line keeps its complete annotation (S30); the widths
-- are the approved reference width's (S13); the setup view's footer follows
-- by the draft's gaps (S27). Each assertion of the former look that these
-- replace is marked where it stood; it is replaced by the draft's own
-- assertion, not relaxed.
-- The approved compact Callboard (the draft's Callboard addendum, choice C1;
-- S19b): a short objective is one line with its progress at the right end, a
-- real 0 stays, a long progress line stands whole under the title, Details
-- does not move the block, and no objective leaves no block or gap. No rule
-- stands between the offer block and the progress row (S21b: the draft draws
-- none).
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
-- The approved draft's lengths. It is drawn in reference pixels, 420 across
-- the panel that is 284 units wide at the reference text size, so one of
-- its pixels is 284 / 420 unit x the font scale. Design: such a length in
-- whole units (1 at least). DesignY: a place the draft gives from the
-- panel's top. Drawn: whether `units` is such a length where it stands (a
-- block's own place decides whether it rounds down or up).
local function Unit(scale) return 284/420*(scale or 1) end
local function Design(px,scale) return math.max(1,math.floor(px*Unit(scale)+0.5)) end
local function DesignY(px,scale) return math.floor(px*Unit(scale)+0.5) end
local function Drawn(px,units,scale) return units==math.floor(px*Unit(scale)) or units==math.ceil(px*Unit(scale)) end
-- What the compact offer heading row keeps at its right end for the
-- destination cell: the cell's words in the font model in use (after a dot
-- while the charges stand before it) and the draft's 10 pixels before them.
-- Without a Saved Build slot the destination is the preview tag.
local function SlotRoom(open,words)
 words=(open and '\194\183 ' or '')..(words or (Nexus.Localization.Text('panel.label.preview_tag')))
 return math.ceil(G.Length(words)*(G.model or G.MODELS.default).char)+Design(10)
end
-- What the panel says about the Auto selection over an offer whose first
-- row is the marked one: the chip; the heading, which with Auto ON says
-- "Auto ON" itself and with Auto OFF is the player's "Your offers", with
-- the destination in the cell beside it; and the marked row's tag, whose
-- words the row shows after its star while the whole tag (the code-owned
-- mark and the words) stays the row's own for its hover.
local function AutoSays(on)
 local chip,head,cell=NexusPanel._autoBtn,NexusPanel._rollStatus,NexusPanel._offerSlot
 local card=NexusPanel._offerCards and NexusPanel._offerCards[1]
 if not (chip and head and card) then return false end
 local heading=V.Plain(head:GetText() or '')
 local starred=card.star~=nil and card.star:IsShown()
 local tag=V.Plain(card.tag:GetText() or '')
 if on then
  return V.Plain(chip:GetText())=='Auto ON' and heading:find('Auto ON',1,true)~=nil and not heading:find('Auto OFF',1,true)
   and not (cell and cell:IsShown()) and tag=='Recommended' and starred and card._nexusTag=='> Recommended'
 end
 return V.Plain(chip:GetText())=='Auto OFF' and heading==(Nexus.Localization.Text('panel.heading.your_offers'))
  and cell~=nil and cell:IsShown() and tag=='Wishlist pick' and starred and card._nexusTag=='> Wishlist pick'
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
 -- The approved compact panel: the card is the difficulty band (S16). This
 -- status carries no validated Intensity thresholds, so there is no bar and
 -- no room is kept for one: the band is its text between its 3-pixel insets,
 -- or the draft's 26 pixels when the text needs no more. Its text is one
 -- line, or the tier with Soul Ash under it where they do not fit one (this
 -- plain harness measures the colour codes too, so here they do not). The
 -- check that stood here asked for the Compact A card's 39 units.
 local tier,ash=card.regions[1],card.regions[2]
 local tierRect,ashRect=G.Rect(tier,NexusPanel),G.Rect(ash,NexusPanel)
 local lines=ashRect[2]>=tierRect[4]-0.01 and (tier:GetStringHeight()+ash:GetStringHeight())
  or math.max(tier:GetStringHeight(),ash:GetStringHeight())
 local need=2*Design(3)+lines
 C.expect(card:IsShown() and box~=nil and card:GetHeight()==box.h and not card.intensityBar:IsShown()
  and (box.h==need or (box.h>need and Drawn(26,box.h))),
  'S3: the card is shown in the Play panel as the difficulty band: no bar, as tall as its text needs or the draft\'s 26 pixels',
  tostring(card:GetHeight())..' for '..tostring(need))
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
 local perf={dummy={global={dps=9077790,player='Synthetic'}},lk={}}
 P.Render(Model({bestDps={dummy={dps=4812}},performance=perf}))
 local p=NexusPanel._play
 if not C.setup(type(p)=='table','S4: fixture: the summary exists') then return end
 local text=ShownText()
 C.expect(text:find('Yours · Training Dummy',1,true)~=nil and Plain(p.yoursValue)=='4k DPS',
  'S4: your record has its own row',Plain(p.yoursValue))
 C.expect(Plain(p.bestLabel)=='Best known · same build' and Plain(p.bestValue)=='9.08M DPS',
  'S4: the best known record for the same Echoes has its own row',Plain(p.bestValue))
 -- Approved panel cleanup: the DPS section is one line of entries, so what
 -- best known means is on the best known entry's hover, not a row of its own.
 local scope=table.concat(V.TooltipLines(p.bestHit:GetScript('OnEnter'),p.bestHit),' | ')
 C.expect(scope:find('server-wide ranking',1,true)~=nil,'S4: the best known hover says what best known is',scope)
 C.expect(scope:find('9,077,790',1,true)~=nil and not scope:find('9.08M',1,true),
  'S4: the best known hover keeps the exact DPS',scope)
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
 C.guard(text:find('4k DPS',1,true)~=nil and text:find('5k DPS',1,true)~=nil,
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
 C.guard(NexusPanel:GetHeight()==withBoth and text:find('4k DPS',1,true)~=nil and text:find('5k DPS',1,true)~=nil,
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
 C.guard(text:find('Yours · Training Dummy',1,true)~=nil and text:find('4k DPS',1,true)~=nil,'S4c: your record keeps its row',text)
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
 C.guard(text:find('Best known · same build',1,true)~=nil and text:find('5k DPS',1,true)~=nil,
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
 local shown,full,words=Nexus.OrbPanel.PanelRunLine()
 C.expect(shown=='Orb run: Running - Waiting for result confirmation; Used 2 of 5 approved; ... 1 awaiting result',
  'S5: the line names the state, usage and the wait',shown)
 C.expect(type(full)=='string' and full:find('Pending: 1 Orb requested, not confirmed yet',1,true)~=nil,
  'S5: the hover keeps the full pending wording',full)
 local actions,sent=#H.actions,#H.sent
 P.Render(Model())
 -- Counts only inside expanded Details (S29): the strip on the panel is the
 -- Orb window's numberless words for the same state and wait, not the
 -- numbered line; that line stays on the strip's hover.
 C.expect(p.orb:IsShown() and words=='Orb run: Running - Waiting for result confirmation; ... awaiting Orb result'
  and Plain(p.orb)==words and p.orbOpen:IsShown() and p.orbHit._nexusFull==full,
  'S5: the HUD shows the run\'s state and wait in words, with Open, and the complete line on its hover',Plain(p.orb))
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
-- 0.75-2; 1.25 is the 125% text of the design's L1): the panel's boxes are
-- disjoint and inside it, the difficulty band is the draft's, Details adds
-- the named lists below the counts without moving the counts, and level 80
-- with no offer collapses the roll box under the 104 px minimum. Pure layout
-- model; native font measurement is NOT RUN.
-- The approved compact panel: the panel is laid out at the width its text
-- scale gives it (LayoutMetrics.PanelWidth: 284 units x the scale, 1 to 2;
-- it was laid out 420 units wide at every scale here), and the band stands
-- where the draft draws it, from 82 to 116 of its pixels under the panel's
-- top.
C.scenario('S10 Play layout at 0.75-2.0 font scale: disjoint boxes, the card, Details and the level-80 collapse',function()
 local LM=Nexus.LayoutMetrics
 for _,scale in ipairs({0.75,1,1.25,1.5,2}) do
  local function Laid(extra)
   -- Both DPS records exist here (spec.recordYours / recordBest): their rows
   -- are laid out only for records that exist (approved cleanup, S4b).
   local spec={width=LM.PanelWidth(scale),fontScale=scale,activeRoll=true,statusVisible=true,cardRows=true,toLockCount=1,orbLine=true,
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
    if a.x<0 or a.y<0 or a.x+a.w>l.width or a.y+a.h>l.height then inside=false end
    for j=i+1,#names do if LM.Overlap(a,l.boxes[names[j]]) then apart=false end end
   end
   C.expect(apart and inside,tag..': every box is inside the panel and apart from the others',table.concat(names,','))
   -- The difficulty band with its bar: the draft's 34 pixels, from 82 to
   -- 116 under the panel's top, which are 17, 23, 29, 35 and 46 units at
   -- 0.75, 1, 1.25, 1.5 and 2. (The check that stood here asked for the
   -- Compact A card's 42, 48, 56, 63 and 77.) The panel is the width the
   -- rule gives this scale.
   local cardH=({[0.75]=17,[1]=23,[1.25]=29,[1.5]=35,[2]=46})[scale]
   C.expect(l.width==math.floor(284*math.max(1,scale)+0.5) and l.boxes.status~=nil and l.boxes.status.h==cardH
    and cardH==DesignY(116,scale)-DesignY(82,scale) and l.boxes.status.x==Design(7,scale)
    and l.boxes.status.w==l.width-2*Design(7,scale) and l.boxes.serverLine==nil,
    tag..': the difficulty band is the draft\'s 34 pixels, '..cardH..' units, between the body\'s insets; no flattened row',l.boxes.status and l.boxes.status.h)
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
  -- The approved draft's panel heights (difficulty B, with its bar): 319
  -- pixels with Details closed and no Callboard (the header to 76, the band
  -- 82 to 116, the offer heading and its three rows, the first with its
  -- reason's line, 121 to 248, the progress row 253 to 275, the footer hubs
  -- 287 to 313); 25 more with the one-line Callboard (its 20 and one gap of
  -- 5); 140 more with Details open (the run count 20, the four counts in
  -- two rows of 18, the lists' heading 18 and their three lines of 18, with
  -- the gaps 3, 3, 1 and 5). A layout whose texts all fit their design rows
  -- (no measured need is given here) is exactly those heights in units, and
  -- a part that comes and goes adds whole units of its own. The one
  -- exception is stated with it: header line 1 is never under the 24-unit
  -- grip less the pixel it stands out above and below, which at a text
  -- scale under about 1.5 is more than the draft's 22 pixels.
  -- EXPECT, failing at eef1608f by design (there: 420 units wide at scale
  -- 1, the Compact A card, two-line rows, a bar row and two-line hubs).
  local function Draft(extra)
   local spec={width=LM.PanelWidth(scale),fontScale=scale,activeRoll=true,statusVisible=true,cardRows=true,measured=true,
    offerRowsH={0,0,0},offerReason={row=1,top=0,h=0}}
   for k,v in pairs(extra or {}) do spec[k]=v end
   return LM.Panel(spec)
  end
  local grip=math.max(0,math.max(24,Design(24,scale))-2*Design(1,scale)-(DesignY(27,scale)-DesignY(5,scale)))
  local plain,board=Draft(),Draft({callboard=true,callboardInline=true})
  local details=Draft({callboard=true,callboardInline=true,planDetails=true})
  C.expect(plain.height==DesignY(319,scale)+grip and board.height-plain.height==DesignY(25,scale)
   and details.height-board.height==DesignY(140,scale) and plain.boxes.callboard==nil and board.boxes.callboard~=nil
   and board.boxes.callboard.h==Design(20,scale),
   'S10 @'..scale..': the panel is the draft\'s 319 pixels high, 25 more with the one-line Callboard and 140 more with Details open',
   plain.height..' / '..board.height..' / '..details.height..' (grip '..grip..')')
  -- The open Details' name columns (the draft: name columns of two names and
  -- a "more" line). Without a To lock list there are two, with one three:
  -- side by side between the body's insets, apart, and of one height. A
  -- column is then a half or a third of the block, so a row wider than it
  -- wraps and needs more than the draft's three lines; the caller measures
  -- that (detailNamesH for Still needed and Extra copies, toLockH for To
  -- lock). Every column is then as tall as the tallest one needs and the
  -- panel is taller by exactly that: no row is cut to keep a height. A To
  -- lock height counts for nothing without a To lock column.
  -- EXPECT, failing at eef1608f by design (there: To lock a row of its own
  -- across the block under two columns).
  local two,three=Draft({planDetails=true}),Draft({planDetails=true,toLockCount=1})
  local function Side(l)
   local b=l.boxes
   return b.toLock~=nil and b.needed.x==l.inset and b.needed.x+b.needed.w<=b.shed.x and b.shed.x+b.shed.w<=b.toLock.x
    and b.toLock.x+b.toLock.w==l.width-l.inset and b.shed.y==b.needed.y and b.toLock.y==b.needed.y
    and b.shed.h==b.needed.h and b.toLock.h==b.needed.h
  end
  local names=three.boxes.needed.h-(tonumber(three.detailHeadingH) or 0)
  local grownNames=Draft({planDetails=true,toLockCount=1,detailNamesH=names+30})
  local grownLock=Draft({planDetails=true,toLockCount=1,detailNamesH=names+10,toLockH=names+40})
  local noLock=Draft({planDetails=true,toLockH=names+40})
  C.expect(two.boxes.toLock==nil and two.boxes.needed.x==two.inset and two.boxes.shed.x>=two.boxes.needed.x+two.boxes.needed.w
   and two.boxes.shed.y==two.boxes.needed.y and two.boxes.shed.h==two.boxes.needed.h
   and Side(three) and three.boxes.needed.w<two.boxes.needed.w and three.height==two.height,
   'S10 @'..scale..': the Details name columns are two side by side, and three with To lock, between the insets, apart and of one height',
   two.boxes.needed.w..' / '..three.boxes.needed.w..(three.boxes.toLock and (' / '..three.boxes.toLock.x..'+'..three.boxes.toLock.w) or ' / no To lock column'))
  C.expect(Side(grownNames) and grownNames.boxes.needed.h==three.boxes.needed.h+30 and grownNames.height==three.height+30
   and Side(grownLock) and grownLock.boxes.needed.h==three.boxes.needed.h+40 and grownLock.height==three.height+40,
   'S10 @'..scale..': rows that need more than the draft\'s three lines make every column as tall as the tallest one needs, and the panel taller by exactly that',
   three.height..' -> '..grownNames.height..' / '..grownLock.height)
  C.expect(noLock.boxes.toLock==nil and noLock.height==two.height and noLock.boxes.needed.h==two.boxes.needed.h,
   'S10 @'..scale..': without a To lock column a To lock height adds nothing',two.height..' / '..noLock.height)
  -- The headings over the columns share one row: one line while every
  -- heading fits its column on one line, and the tallest heading's measured
  -- height when a heading wraps there (listHeadingH, which the caller
  -- measures in the column's own width). The names start under the whole
  -- row, in the same place across the block, and the panel is taller by
  -- exactly what the row gained: no heading is cut to keep a height. A
  -- heading that measures one line changes nothing.
  -- EXPECT, failing at eef1608f and while the heading row was held to one
  -- line (the one-line heading rule of issue #143, which the approved
  -- no-cut rule now comes before in these columns).
  local headRow=tonumber(three.detailHeadingH) or 0
  local tallHead=Draft({planDetails=true,toLockCount=1,listHeadingH=headRow+17})
  local oneLineHead=Draft({planDetails=true,toLockCount=1,listHeadingH=three.lineSmall})
  C.expect(headRow>0 and three.detailHeadingTall==false
   and Side(tallHead) and tallHead.detailHeadingH==headRow+17 and tallHead.detailHeadingTall==true
   and tallHead.boxes.needed.y==three.boxes.needed.y and tallHead.boxes.needed.h==three.boxes.needed.h+17
   and tallHead.height==three.height+17
   and oneLineHead.detailHeadingH==headRow and oneLineHead.detailHeadingTall==false and oneLineHead.height==three.height,
   'S10 @'..scale..': a heading that needs more than one line makes the heading row as tall as it needs, with the names under it and the panel taller by exactly that; a one-line heading changes nothing',
   headRow..' -> '..tostring(tallHead.detailHeadingH)..', panel '..three.height..' -> '..tallHead.height..' / '..oneLineHead.height)
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
-- Main-panel visual correction: the panel's width follows the text scale
-- (LayoutMetrics.PanelWidth), so at 2.0 text the 420-unit panel is what a
-- screen too narrow for more leaves (here a 640-unit screen at the chosen
-- 150%). The 2.0-text checks that stood here run there, unchanged: they were
-- written for 420 units, which was the width at every text size. On a screen
-- with the room the panel is 840 units wide at 2.0 text, and the two entries
-- share one line again when their measured widths fit it: EXPECT, failing at
-- aca67cf4 by design (420 units at every text size).
C.scenario('S13 the DPS entries share one line while they fit and wrap as whole entries when they do not',function()
 local function Texts()
  local out={}
  for _,r in ipairs(G.Shown(NexusPanel)) do
   if r.kind=='FontString' and r:GetParent()==NexusPanel then
    local plain=Plain(r)
    if plain:find('Yours',1,true) or plain:find('Best known',1,true) or r==NexusPanel._play.yoursValue or r==NexusPanel._play.bestValue then
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
 -- The screen and the chosen size this scenario sets, put back below.
 local w0,h0=UIParent:GetWidth(),UIParent:GetHeight()
 local ok,err=pcall(function()
  G.UseFont(G.MODELS.default)
  C.setup(P.Render(both)==true,'S13: fixture: both records at default text')
  local b=NexusPanel._responsiveLayout.boxes
  -- The rule is unchanged: the two entries share a line while both, two
  -- gaps apart, fit the block (GUARD; stated from the layout's measured
  -- entries as below). In the approved 284-unit reference panel these two
  -- need more than its 274-unit block in this font model, so each takes its
  -- own line (EXPECT: they shared one line of the former 404-unit block,
  -- which the check here asked for). Two entries that do fit the block
  -- still share one line: asked of the layout itself with short entries.
  local l0=NexusPanel._responsiveLayout
  local yours0,best0=l0.recordYours,l0.recordBest
  if C.setup(type(yours0)=='table' and type(best0)=='table' and b.bestDps~=nil and b.bestKnown~=nil,
   'S13: fixture: both entries are measured and laid out at default text') then
   local need0=math.ceil(yours0[1]+l0.gap+yours0[2])+l0.gap*2+math.ceil(best0[1]+l0.gap+best0[2])
   local shared0=b.bestDps.y==b.bestKnown.y and not Nexus.LayoutMetrics.Overlap(b.bestDps,b.bestKnown)
   C.guard(shared0==(need0<=l0.full),'S13: at default text the entries share one line exactly when their measured widths fit the block',
    need0..' of '..tostring(l0.full))
   C.expect(l0.width==284 and l0.full==284-2*Design(7) and need0>l0.full and b.bestKnown.y>=b.bestDps.y+b.bestDps.h,
    'S13: at default text in the 284-unit reference panel each entry takes its own line',
    need0..' of '..tostring(l0.full)..'; '..b.bestDps.y..' / '..b.bestKnown.y)
  end
  local short=Nexus.LayoutMetrics.Panel({width=284,fontScale=1,activeRoll=true,recordYours={60,30},recordBest={70,30}})
  C.guard(short.boxes.bestDps~=nil and short.boxes.bestKnown~=nil and short.boxes.bestDps.y==short.boxes.bestKnown.y
   and not Nexus.LayoutMetrics.Overlap(short.boxes.bestDps,short.boxes.bestKnown),
   'S13: two entries that fit the block share one line',short.boxes.bestDps and short.boxes.bestKnown and (short.boxes.bestDps.y..' / '..short.boxes.bestKnown.y))
  C.expect(b.recordNote==nil and not ShownText():find('server-wide',1,true),'S13: the scope note takes no row',ShownText())
  Whole('S13 default text')
  local oneLine=NexusPanel:GetHeight()
  G.UseFont(G.MODELS.double)
  -- The panel a 640-unit screen leaves at the chosen 150% at 2.0 text: 410
  -- units of the 568 its text scale asks for (it was the 420-unit floor of
  -- the former reference width).
  UIParent:SetSize(640,4000)
  P.SetPanelScale(1.5)
  C.setup(P.Render(both)==true and NexusPanel:GetWidth()==410,'S13: fixture: both records at 2.0 text, in the 410-unit panel',NexusPanel:GetWidth())
  b=NexusPanel._responsiveLayout.boxes
  C.expect(b.bestDps~=nil and b.bestKnown~=nil and b.bestKnown.y>=b.bestDps.y+b.bestDps.h,
   'S13: at 2.0 text each entry takes its own line',b.bestDps and b.bestKnown and (b.bestDps.y..'+'..b.bestDps.h..' / '..b.bestKnown.y))
  Whole('S13 2.0 text')
  -- Both targets recorded: the best known entry is wider than the line.
  local wide=Model({bestDps={dummy={dps=4812},lk={dps=3300}},
   performance={dummy={global={dps=5130,player='Synthetic'}},lk={global={dps=3400,player='Synthetic'}}}})
  C.setup(P.Render(wide)==true,'S13: fixture: Training Dummy and Lich King records at 2.0 text')
  Whole('S13 2.0 text, both targets')
  -- With the room for it (a 1920-unit screen at 100%) the panel is 568 units
  -- wide at 2.0 text: the approved 284-unit reference width x the text scale
  -- (it was 840: the former 420 x 2).
  P.ResetPanelScale()
  UIParent:SetSize(1920,4000)
  C.setup(P.Render(both)==true,'S13: fixture: both records at 2.0 text on a 1920-unit screen')
  local l=NexusPanel._responsiveLayout
  b=l.boxes
  C.expect(NexusPanel:GetWidth()==568 and l.width==568,
   'S13: at 2.0 text on a screen with the room the panel is 568 units wide (284 x the text scale)',NexusPanel:GetWidth())
  local yours,best=l.recordYours,l.recordBest
  if C.setup(type(yours)=='table' and type(best)=='table' and b.bestDps~=nil and b.bestKnown~=nil,
   'S13: fixture: both entries are measured and laid out there') then
   -- The rule the layout states: each entry is its label, one gap and its
   -- value; the two share a line while both, two gaps apart, fit the block.
   local need=math.ceil(yours[1]+l.gap+yours[2])+l.gap*2+math.ceil(best[1]+l.gap+best[2])
   local shared=b.bestDps.y==b.bestKnown.y and not Nexus.LayoutMetrics.Overlap(b.bestDps,b.bestKnown)
   print('OBSERVED','S13 2.0 text at '..tostring(l.width)..' units: the entries need '..need..' of '..tostring(l.full)..' units; shared='..tostring(shared))
   C.guard(shared==(need<=l.full),'S13: the entries share one line exactly when their measured widths fit the block',need..' of '..tostring(l.full))
   -- Where they fit, that they share the line follows from the rule above
   -- (GUARD: the rule held at the former widths too). The red-ready check
   -- of this part is the 568-unit width.
   if need<=l.full then
    C.guard(shared,'S13: with the room 568 units give, the two entries share one line again at 2.0 text',need..' of '..tostring(l.full))
   end
  end
  Whole('S13 2.0 text, 568 units')
  UIParent:SetSize(w0,h0)
  G.UseFont(G.MODELS.default)
  C.setup(P.Render(both)==true and NexusPanel:GetHeight()==oneLine,'S13: fixture: default text gives the same panel back',NexusPanel:GetHeight())
 end)
 -- The chosen size (taken back while the screen is readable), the screen,
 -- the font model, the applied size and the default anchor return.
 UIParent:SetSize(1920,4000)
 P.ResetPanelScale()
 UIParent:SetSize(w0,h0)
 G.UseFont(G.MODELS.default)
 NexusPanel:SetScale(1)
 NexusPanel:ClearAllPoints();NexusPanel:SetPoint('RIGHT',UIParent,'RIGHT',-40,0)
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
 -- The approved compact panel (AutoSays above): with Auto OFF the heading
 -- is the player's "Your offers" (the Auto state is the chip's own word)
 -- and the marked row's tag stands after its star. The checks that stood
 -- here asked for "Auto OFF" in the heading's own text and for the tag with
 -- its code-owned mark as the row's text.
 if not C.setup(chip:IsShown() and tag~=nil and AutoSays(false),'S14: fixture: chip, heading and tag say Auto OFF',Plain(head)) then return end
 local before=Effects()
 P.SetAuto(true)
 C.expect(V.Plain(chip:GetText())=='Auto ON' and Plain(head):find('Auto ON',1,true)~=nil and not Plain(head):find('Auto OFF',1,true)
  and not Plain(head):find('you choose',1,true) and Plain(head)~=(Nexus.Localization.Text('panel.heading.your_offers')),
  'S14: Auto ON shows on the chip and in the offer heading together',
  V.Plain(chip:GetText())..' / '..Plain(head))
 C.expect(AutoSays(true),'S14: the marked offer\'s tag follows the same selection',Plain(tag))
 P.SetAuto(false)
 C.expect(AutoSays(false),
  'S14: Auto OFF shows on the chip, the heading is the player\'s "Your offers" again and the tag follows',
  V.Plain(chip:GetText())..' / '..Plain(head)..' / '..Plain(tag))
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
C.scenario('S16 the difficulty band: the draft\'s 34 pixels with short text and its bar, grows for a wrapped tier, no room for an absent bar',function()
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
 -- The band (the approved compact panel, presentation B): between its
 -- 8-pixel side insets the tier, a dot and Soul Ash stand on one line, left
 -- of the multiplier's own cell and the draft's 10 pixels from it, while the
 -- tier, the dot (5 pixels either side), Soul Ash and 10 pixels of room for
 -- a value that gains a digit fit there; otherwise the tier wraps in that
 -- room and Soul Ash stands on a line of its own under it. Which of the two
 -- a status needs is worked out here from its words in this font model.
 -- Returns the band's own need: its text block, the 3-pixel insets, and
 -- with a bar the 1 pixel above it, its 4 pixels and the 3 under it.
 local function Check(tag,card,bar)
  local tier,ash,gain=Parts(card)
  local c,t,a,g=G.Rect(card,NexusPanel),G.Rect(tier,NexusPanel),G.Rect(ash,NexusPanel),G.Rect(gain,NexusPanel)
  local detail='card '..G.Text(c)..' tier '..G.Text(t)..' ash '..G.Text(a)..' gain '..G.Text(g)
  local char=G.model.char
  local room=(c[3]-c[1])-2*Design(8)-(g[3]-g[1])-Design(10)
  local tierW,ashW=math.ceil(G.Length(Plain(tier))*char),math.ceil(G.Length(Plain(ash))*char)
  local oneLine=tierW+2*Design(5)+math.ceil(char)+ashW+Design(10)<=room
  -- EXPECT: at eef1608f Soul Ash stood under the tier whatever their widths.
  C.expect(G.Inside(t,c) and G.Inside(a,c) and G.Inside(g,c) and G.Apart(t,g) and t[1]==c[1]+Design(8) and g[3]==c[3]-Design(8)
   and a[3]<=g[1]-Design(10)+0.01
   and ((oneLine and a[1]>=t[3]-0.01 and math.abs(a[2]-t[2])<=0.01 and math.abs(g[2]-t[2])<=0.01)
    or (not oneLine and a[2]>=t[4]-0.01 and a[1]==t[1])),
   tag..': the tier and Soul Ash share the band\'s line beside the multiplier while they fit it, else Soul Ash is under the tier; all inside the band',
   detail..' one line '..tostring(oneLine))
  C.expect(tier:GetWidth()>0 and tier:GetHeight()+0.5>=tier:GetStringHeight() and gain:GetWidth()+0.5>=gain:GetStringWidth()
   and ash:GetWidth()+0.5>=ash:GetStringWidth(),tag..': the tier, Soul Ash and multiplier are whole in their boxes',
   tier:GetWidth()..'x'..tier:GetHeight()..' needs '..tier:GetStringHeight())
  if bar then
   local b=G.Rect(card.intensityBar,NexusPanel)
   -- (EXPECT: the bar was 6 units; it is the draft's 4 pixels, across the
   -- band between its side insets, 3 pixels above its inner edge.)
   C.expect(card.intensityBar:IsShown() and b[4]-b[2]==Design(4) and b[2]>=math.max(t[4],a[4])-0.01 and G.Inside(b,c)
    and b[1]==c[1]+Design(8) and b[3]==c[3]-Design(8) and c[4]-b[4]==2*Design(3),
    tag..': the Intensity bar, the draft\'s 4 pixels, is under the texts across the band, inside it',detail..' bar '..G.Text(b))
  end
  local text=oneLine and math.max(tier:GetStringHeight(),ash:GetStringHeight()) or (tier:GetStringHeight()+ash:GetStringHeight())
  return 2*Design(3)+text+(bar and (Design(1)+Design(4)+Design(3)) or 0),oneLine
 end
 -- Main-panel visual correction: the tier and the multiplier stand on one
 -- line (the multiplier was centred in its cell beside a tier at the top of
 -- its own). In the approved band that line also holds Soul Ash in its
 -- smaller role, so on a one-line band each text takes the line's whole
 -- height and stands in its middle, and they share one centre; where the
 -- tier wraps, the tier and the multiplier start at the top again. The
 -- harness keeps no vertical justification, so the requests are recorded
 -- for this scenario (as native_details_measurement records them) and the
 -- method is put back below.
 local regions=G.RegionMethods()
 local hadJustify=rawget(regions,'SetJustifyV')
 regions.SetJustifyV=function(self,v)
  rawset(self,'_justifyV',v)
  if hadJustify then return hadJustify(self,v) end
 end
 local ok,err=pcall(function()
  G.UseFont(G.MODELS.default)
  C.setup(P.Render(Model({serverStatus=Status('HC3',true)}))==true,'S16: fixture: a short tier with a validated Intensity scale')
  local card=StatusCard()
  if not C.setup(card~=nil and card:IsShown() and card.intensityBar:IsShown(),'S16: fixture: the card and its bar are shown') then return end
  local box=NexusPanel._responsiveLayout.boxes.status
  local need,oneLine=Check('S16 short',card,true)
  -- EXPECT: the Compact A card was 48 units here. The band is the draft's 34
  -- pixels (23 units at this size) while its line needs no more.
  C.expect(box~=nil and card:GetHeight()==box.h and oneLine and need<=box.h and Drawn(34,box.h) and box.h==23
   and box.x==Design(7) and box.w==NexusPanel:GetWidth()-2*Design(7),
   'S16: with short text and its bar the active band is the draft\'s 34 pixels, 23 units, between the body\'s insets',box and box.h)
  local activeH=card:GetHeight()
  local tierText,ashText,gainText=Parts(card)
  local tierRect,gainRect=G.Rect(tierText,NexusPanel),G.Rect(gainText,NexusPanel)
  -- EXPECT: at eef1608f the tier and the multiplier asked for the top of
  -- two cells over a Soul Ash line.
  C.expect(rawget(tierText,'_justifyV')=='MIDDLE' and rawget(ashText,'_justifyV')=='MIDDLE' and rawget(gainText,'_justifyV')=='MIDDLE'
   and tierRect[2]==gainRect[2] and tierText:GetHeight()==gainText:GetHeight() and tierText:GetHeight()==ashText:GetHeight(),
   'S16: on the one-line band the tier, Soul Ash and the multiplier share the line\'s height and its middle',
   tostring(rawget(tierText,'_justifyV'))..' / '..tostring(rawget(gainText,'_justifyV'))..' at '..tostring(tierRect[2])..' / '..tostring(gainRect[2]))
  C.guard(card._nexusThemeExempt==true,'S16: the card stays exempt from the theme')
  C.setup(P.Render(Model({serverStatus=Status('HC3',true),owned=6}))==true,'S16: fixture: the completed build')
  C.expect(card:IsShown() and card:GetHeight()==activeH,'S16: the completed band is as tall as the active one',card:GetHeight())
  local long='Stufe IV: Heroische Frostgrab-Herausforderung der zersplitterten Frostwacht-Konklave des Nordens'
  C.setup(P.Render(Model({serverStatus=Status(long,true)}))==true,'S16: fixture: a long localized tier')
  local tier=Parts(card)
  -- A tier that does not fit the line wraps beside the multiplier, with
  -- Soul Ash under it, and the band is exactly its insets, those lines and
  -- its bar. (It was the 48-unit card grown by what the tier needed beyond
  -- a 15-unit line.)
  local longNeed,longOneLine=Check('S16 long tier',card,true)
  C.expect(tier:GetStringHeight()>15 and not longOneLine and card:GetHeight()==longNeed and card:GetHeight()>activeH
   and card:GetHeight()==NexusPanel._responsiveLayout.boxes.status.h
   and rawget(tier,'_justifyV')=='TOP' and rawget(select(3,Parts(card)),'_justifyV')=='TOP',
   'S16: a long tier wraps and the band grows to exactly its lines',card:GetHeight()..' needs '..tostring(longNeed)..', tier '..tier:GetStringHeight())
  C.setup(P.Render(Model({serverStatus=Status('HC3',false)}))==true,'S16: fixture: no validated Intensity scale')
  local plainNeed=Check('S16 no bar',card,false)
  C.expect(not card.intensityBar:IsShown() and card:GetHeight()<activeH
   and (card:GetHeight()==plainNeed or (card:GetHeight()>plainNeed and Drawn(26,card:GetHeight()))),
   'S16: without a validated Intensity scale there is no bar and no room kept for it: the draft\'s 26 pixels',card:GetHeight())
 end)
 regions.SetJustifyV=hadJustify
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

-- The approved compact Callboard (the design draft's Callboard addendum,
-- choice C1: the progress on the title's line when it fits). A short
-- objective is one line: its icon (the draft's 16 pixels), 6 after it the
-- label, 8 after the label the title and, at the right end of that line, its
-- one progress line, while the label, the title, the draft's gaps and that
-- line fit the row beside the icon. The block is then the draft's 20 pixels,
-- 5 under the difficulty band and 5 above the offer block, with no rule, and
-- the panel is taller by exactly the block and its one gap. The words are
-- the objective's own: a real 0 ("0/40") is shown as it is. A progress line
-- too long for the title's line stands whole under the title, from the
-- label's left edge, wrapped, and the block and the panel grow for it.
-- Details does not move or change the block. Without an objective there is
-- no block, text, rule or gap: the panel is exactly as tall as it was.
-- The summary read is a boundary double, as in S19; what fits is worked out
-- here from the words in the stated font model, not read from the panel.
-- EXPECT, failing at eef1608f by design: there the progress line always
-- stood under the title, in the former insets. GUARD: what already held (the
-- objective's own words with their 0, the panel's exact growth, no rule, the
-- hover area and its complete line, Details, no objective).
C.scenario('S19b a short Callboard objective is one line with its progress at the right end and a real 0 stays; a long progress line stands under the title; Details does not move the block; no objective leaves no block or gap',function()
 local TITLE,ZERO='Trade Goods: Felweed','Felweed: 0/40'
 local LONG='Raureifgebundener Waechter und echogebundene Schildwachen in der Frostgrabhoehle besiegt: 0/3'
 local board=Nexus.CallboardStatus
 local real=board.GetSummary
 local summary
 board.GetSummary=function() return summary end
 local function Play()
  return Model({serverStatus={tier='HC3',mode='HC3',ash='1,240',gain='+45%',intensity=250,intensityMax=500,
    intensityThresholds={100,200,300,400},intensityLevel=2},
   cards={{text='Frostwake Sigil (Rare)',highlight=true},{text='Hollow Bell (Rare)'},{text='Ashen Tithe (Uncommon)'}},
   recommendation='Take Frostwake Sigil.'})
 end
 -- The end of what stands above the block and the start of what stands
 -- under it, from the layout's other boxes.
 local function Around(boxes,box)
  local above,below
  for name,other in pairs(boxes) do
   if name~='callboard' then
    if other.y+other.h<=box.y and (not above or other.y+other.h>above) then above=other.y+other.h end
    if other.y>=box.y+box.h and (not below or other.y<below) then below=other.y end
   end
  end
  return above,below
 end
 -- The shown textures of the panel that are a rule (at most one unit high,
 -- at least half the body wide) between two heights.
 local function Rules(from,to,full)
  local found={}
  for _,r in ipairs(G.Shown(NexusPanel)) do
   if r.kind=='Texture' then
    local okRect,rect=pcall(G.Rect,r,NexusPanel)
    if okRect and rect[4]-rect[2]<=1.01 and rect[3]-rect[1]>=full/2 and rect[2]>=from-0.01 and rect[4]<=to+0.01 then
     found[#found+1]=G.Text(rect)
    end
   end
  end
  return found
 end
 local ok,err=pcall(function()
  for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do
   local tag='S19b '..model.name
   local scale,char=model.size/12,model.char
   G.UseFont(model)
   P._playDetails=false
   summary=nil
   C.setup(P.Render(Play())==true and NexusPanel._responsiveLayout.boxes.callboard==nil,
    tag..': fixture: a build in progress without a Callboard objective')
   local bare=NexusPanel:GetHeight()
   local bareRoll=NexusPanel._responsiveLayout.boxes.roll and NexusPanel._responsiveLayout.boxes.roll.y
   summary={observed=true,title=TITLE,lines={ZERO}}
   C.setup(P.Render(Play())==true,tag..': fixture: the same panel with a short objective whose progress is 0 of 40')
   local l=NexusPanel._responsiveLayout
   local box=l.boxes.callboard
   local icon,label,t,line=NexusPanel._callboardIcon,NexusPanel._callboardLabel,NexusPanel._callboardTitle,NexusPanel._callboardLine
   local hit=NexusPanel._callboardLineHit
   if not C.setup(box~=nil and icon~=nil and label~=nil and t~=nil and line~=nil and hit~=nil and label:IsShown() and t:IsShown()
     and line:IsShown() and l.boxes.status~=nil and l.boxes.roll~=nil and bareRoll~=nil,
    tag..': fixture: the Callboard block is laid out between the difficulty band and the offer block') then return end
   local labelW,titleW,lineW=G.Length(Plain(label))*char,G.Length(TITLE)*char,G.Length(ZERO)*char
   -- The row beside the icon (the draft's 16 pixels and 6): the label, 8,
   -- the title, 10 and the progress line fit it, with room to spare.
   local room=box.w-Design(16,scale)-Design(6,scale)
   C.setup(labelW+Design(8,scale)+titleW+Design(10,scale)+lineW+Design(8,scale)<=room and model.line<=math.floor(20*Unit(scale)),
    tag..': fixture: the label, the title, the draft\'s gaps and the progress line fit one row, and a line of text fits the draft\'s 20 pixels',
    tostring(labelW+titleW+lineW)..' in '..room)
   local ir,lr,tr,pr=G.Rect(icon,NexusPanel),G.Rect(label,NexusPanel),G.Rect(t,NexusPanel),G.Rect(line,NexusPanel)
   local detail='box '..box.x..','..box.y..' '..box.w..'x'..box.h..' label '..G.Text(lr)..' title '..G.Text(tr)..' progress '..G.Text(pr)
   C.guard(Plain(t)==TITLE and Plain(line)==ZERO,
    tag..': the title and the progress are the objective\'s own words, whole, the real 0 included',Plain(t)..' | '..Plain(line))
   C.expect(pr[2]==tr[2] and pr[4]==tr[4] and tr[2]==box.y and tr[4]==box.y+box.h and pr[3]==box.x+box.w
     and pr[1]>=tr[1]+titleW+Design(10,scale)-0.01 and tr[3]<=pr[1]+0.01 and pr[3]-pr[1]+0.5>=lineW
     and t:GetHeight()+0.5>=t:GetStringHeight() and line:GetHeight()+0.5>=line:GetStringHeight(),
    tag..': the progress stands on the title\'s line, at the row\'s right end, the draft\'s 10 pixels or more after the title\'s words; both are whole',
    detail)
   C.expect(ir[1]==box.x and ir[3]-ir[1]==Design(16,scale) and ir[4]-ir[2]==Design(16,scale) and ir[2]>=box.y and ir[4]<=box.y+box.h
     and lr[1]==box.x+Design(16,scale)+Design(6,scale) and lr[3]-lr[1]+0.01>=labelW and lr[3]-lr[1]<=labelW+2
     and lr[2]>=box.y and lr[4]<=box.y+box.h and tr[1]==lr[3]+Design(8,scale),
    tag..': the icon is the draft\'s 16 pixels at the block\'s left, the label 6 after it and the title 8 after the label, all on that line',
    'icon '..G.Text(ir)..' '..detail)
   local above,below=Around(l.boxes,box)
   C.expect(Drawn(20,box.h,scale) and above==l.boxes.status.y+l.boxes.status.h and below==l.boxes.roll.y
     and Drawn(5,box.y-above,scale) and Drawn(5,below-(box.y+box.h),scale),
    tag..': the block is the draft\'s 20 pixels, 5 under the difficulty band and 5 above the offer block',
    detail..' above '..tostring(above)..' below '..tostring(below))
   local grown=NexusPanel:GetHeight()-bare
   C.guard(grown==box.h+(below-(box.y+box.h)) and l.boxes.roll.y-bareRoll==grown,
    tag..': the panel is taller by exactly the block and its one gap, and what is under the block moved by that',
    bare..' -> '..NexusPanel:GetHeight()..' block '..box.h)
   C.guard(#Rules(above,below,l.full)==0,tag..': no rule stands above, in or under the block',table.concat(Rules(above,below,l.full),' '))
   C.guard(hit:IsShown() and type(hit._nexusFullLines)=='table' and #hit._nexusFullLines==1 and hit._nexusFullLines[1]==ZERO,
    tag..': the progress keeps its hover area and its complete line')
   -- Details: the block is the same with Details open, and closing gives
   -- the height back.
   local closed=NexusPanel:GetHeight()
   NexusPanel._play.details:Click()
   C.setup(P.Render(Play())==true and P._playDetails==true,tag..': fixture: Details opened')
   local openBox=NexusPanel._responsiveLayout.boxes.callboard
   local tr2,pr2=G.Rect(t,NexusPanel),G.Rect(line,NexusPanel)
   C.guard(openBox~=nil and openBox.x==box.x and openBox.y==box.y and openBox.w==box.w and openBox.h==box.h
     and tr2[1]==tr[1] and tr2[2]==tr[2] and pr2[1]==pr[1] and pr2[2]==pr[2] and pr2[3]==pr[3] and Plain(t)==TITLE and Plain(line)==ZERO
     and NexusPanel:GetHeight()>closed,
    tag..': with Details open the block and its words stand where they stood',G.Text(tr2)..' '..G.Text(pr2))
   NexusPanel._play.details:Click()
   C.setup(P.Render(Play())==true and P._playDetails==false,tag..': fixture: Details closed again')
   C.guard(NexusPanel:GetHeight()==closed,tag..': closing Details gives the height back',NexusPanel:GetHeight()..' / '..closed)
   -- A progress line too long for the title's line.
   summary={observed=true,title=TITLE,lines={LONG}}
   C.setup(P.Render(Play())==true,tag..': fixture: the same objective with a long progress line')
   l=NexusPanel._responsiveLayout
   box=l.boxes.callboard
   if not C.setup(box~=nil and l.boxes.roll~=nil,tag..': fixture: the block is laid out again') then return end
   local longW=G.Length(LONG)*char
   C.setup(labelW+Design(8,scale)+titleW+Design(10,scale)+longW>room+2 and longW>box.w,
    tag..': fixture: that line does not fit beside the title, nor on one line under it',longW..' in '..room)
   lr,tr,pr=G.Rect(label,NexusPanel),G.Rect(t,NexusPanel),G.Rect(line,NexusPanel)
   above,below=Around(l.boxes,box)
   C.expect(Plain(t)==TITLE and Plain(line)==LONG and tr[2]==box.y and pr[2]>=tr[4]-0.01 and pr[1]==lr[1]
     and lr[1]==box.x+Design(16,scale)+Design(6,scale) and pr[3]<=box.x+box.w+0.01
     and line:GetStringHeight()>model.line and line:GetHeight()+0.5>=line:GetStringHeight()
     and box.h==(tr[4]-tr[2])+(pr[4]-pr[2]) and pr[4]<=box.y+box.h+0.01,
    tag..': a long progress line stands whole under the title, from the label\'s left edge, wrapped, in a block as tall as both',
    'box '..box.y..'+'..box.h..' title '..G.Text(tr)..' progress '..G.Text(pr))
   C.expect(below==l.boxes.roll.y and NexusPanel:GetHeight()-bare==box.h+(below-(box.y+box.h)) and Drawn(5,below-(box.y+box.h),scale),
    tag..': the panel grows by exactly that block and its gap',bare..' -> '..NexusPanel:GetHeight()..' block '..box.h)
   -- No objective again.
   summary=nil
   C.setup(P.Render(Play())==true,tag..': fixture: the objective ends')
   C.guard(NexusPanel._responsiveLayout.boxes.callboard==nil and not label:IsShown() and not t:IsShown() and not line:IsShown()
     and not icon:IsShown() and not hit:IsShown() and NexusPanel:GetHeight()==bare
     and NexusPanel._responsiveLayout.boxes.roll.y==bareRoll,
    tag..': without an objective there is no block, text or gap: the panel is exactly as tall as before',NexusPanel:GetHeight()..' / '..bare)
  end
 end)
 board.GetSummary=real
 G.UseFont(G.MODELS.default)
 P._playDetails=false
 P.Render(Model())
 C.setup(ok,'S19b: fixture: the compact Callboard scenario ran',err)
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
  -- The heading's "Target build - N rolled copies" is a plan count
  -- (DESIGN_NOTES 4 and 8: counts only inside expanded Details): with
  -- Details closed the heading is "DPS RECORDS" alone; with Details open it
  -- carries the total again, whole. EXPECT fails before the correction (the
  -- total showed with Details closed).
  C.expect(not text:find('Target build',1,true) and not text:find('rolled copies',1,true),
   'S20: with Details closed the DPS RECORDS heading carries no plan total',text)
  WholeTexts('S20 yours only',{'DPS RECORDS','Your Dummy','12k'},3)
  local closedDetails=P._playDetails
  P._playDetails=true
  text=Shown({dummy={personal={dps=12000}},lk={}})
  C.expect(text:find('Target build · 6 rolled copies',1,true)~=nil,'S20: with Details open the heading shows the plan total',text)
  WholeTexts('S20 yours only, Details open',{'DPS RECORDS','Your Dummy','12k','Target build'},4)
  P._playDetails=closedDetails
  text=Shown({dummy={personal={dps=12000}},lk={}})
  C.expect(not text:find('Target build',1,true),'S20: closing Details takes the total off the heading again',text)
  text,box=Shown({dummy={personal={dps=0}},lk={}})
  -- (A shown text that is exactly "0". It was followed by the footer hubs'
  -- second lines, which the approved one-line hubs no longer have, so it can
  -- be the last shown text now.)
  C.expect(box~=nil and text:find('Your Dummy',1,true)~=nil and (text..' |'):find('| 0 |',1,true)~=nil and not text:find('—',1,true),
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
-- four counts until Details is opened, and takes no row while it is; with
-- Details open the count has its own whole row.
-- Main-panel visual correction: the caption stands at the left of its row
-- with the compact Details button at the row's right end, and the bar is a
-- full-width row of its own under them. The check that stood here asked for
-- the bar on the heading row, between the heading and the Details button
-- (the approved cleanup's one-row progress); that squeezed bar is
-- intentionally gone, so the check is replaced by the two rows' own checks,
-- not relaxed. The Details button is as wide as the wider of its two labels
-- needs and keeps that width and its place whichever label it shows, and
-- the bar does not move when Details opens. EXPECT fails at aca67cf4 by
-- design: the bar's own full-width row. GUARD, because the one-row progress
-- had them too: the caption at the row's left with Details at its right end,
-- the drawn bar and button standing in their boxes, a Details button of at
-- most half the row, and its unmoved place and the bar's when Details opens.
C.scenario('S21 collapsed progress is one row: its caption, the bar and Details at its right; the run count shows only with Details',function()
 local ok,err=pcall(function()
  G.UseFont(G.MODELS.default)
  P._playDetails=false
  C.setup(P.Render(Model())==true,'S21: fixture: a build in progress, Details closed')
  local l=NexusPanel._responsiveLayout
  local b=l.boxes
  local p=NexusPanel._play
  C.expect(b.progressValue==nil and not ShownText():find('rolled copies',1,true),
   'S21: with Details closed the run count is not shown and has no row',ShownText())
  C.guard(b.planBar~=nil and b.planDetails~=nil and b.progressHeader~=nil and b.progressHeader.y==b.planDetails.y
   and b.progressHeader.x==l.inset and b.planDetails.x>=b.progressHeader.x+b.progressHeader.w
   and b.planDetails.x+b.planDetails.w==l.inset+l.full,
   'S21: the caption is at the left of its row and the Details button at the row\'s right end',
   b.progressHeader and b.planDetails and (b.progressHeader.x..'+'..b.progressHeader.w..' / '..b.planDetails.x..'+'..b.planDetails.w))
  -- The approved inline progress row: the bar stands on the caption's own
  -- row, between the caption and the Details button and the draft's 8
  -- pixels from each, 6 pixels high in the row's middle, and never under 40
  -- pixels long (a caption or label that left it less would put it on a row
  -- of its own under them). EXPECT: at eef1608f the bar was a full-width
  -- row of its own under the caption and the button, which the check here
  -- asked for.
  C.expect(b.planBar~=nil and b.progressHeader~=nil and b.planDetails~=nil and l.inset==Design(7)
   and b.planBar.x==b.progressHeader.x+b.progressHeader.w+Design(8) and b.planBar.x+b.planBar.w==b.planDetails.x-Design(8)
   and b.planBar.h==Design(6) and b.planBar.w>=Design(40)
   and b.planBar.y>=b.progressHeader.y and b.planBar.y+b.planBar.h<=b.progressHeader.y+b.progressHeader.h
   and math.abs((b.planBar.y-b.progressHeader.y)-(b.progressHeader.y+b.progressHeader.h-b.planBar.y-b.planBar.h))<=1,
   'S21: the bar stands on the caption\'s row, between the caption and the Details button, 8 pixels from each, in the row\'s middle',
   b.planBar and (b.planBar.x..','..b.planBar.y..' '..b.planBar.w..'x'..b.planBar.h))
  local track,button=G.Rect(p.track,NexusPanel),G.Rect(p.details,NexusPanel)
  C.guard(b.planBar~=nil and track[1]==b.planBar.x and track[2]==b.planBar.y and track[3]-track[1]==b.planBar.w
   and button[1]==b.planDetails.x and button[2]==b.planDetails.y and button[3]-button[1]==b.planDetails.w,
   'S21: the drawn bar and the Details button stand in those boxes',G.Text(track)..' '..G.Text(button))
  -- Compact: as wide as the wider of its two labels needs with the
  -- template's end caps (measured by the panel, so not restated here), and
  -- never more than half of the row.
  C.guard(b.planDetails.w>0 and b.planDetails.w*2<=l.full,'S21: the Details button is compact: at most half of the row',b.planDetails.w)
  C.guard(p.details:IsShown() and Plain(p.details)=='Show details' and p.track:IsShown(),'S21: the bar and Show details stay')
  local closedBar,closedButton=b.planBar,b.planDetails
  p.details:Click()
  C.setup(P.Render(Model())==true and P._playDetails==true,'S21: fixture: Details opened')
  b=NexusPanel._responsiveLayout.boxes
  C.expect(b.progressValue~=nil and ShownText():find('2 / 6 rolled copies this run',1,true)~=nil,
   'S21: with Details open the run count has its own row',ShownText())
  C.guard(Plain(p.details)=='Hide details' and b.planDetails.x==closedButton.x and b.planDetails.y==closedButton.y
   and b.planDetails.w==closedButton.w and b.planBar.x==closedBar.x and b.planBar.y==closedBar.y and b.planBar.w==closedBar.w,
   'S21: Hide details has the same width and place as Show details, and the bar does not move',
   b.planDetails.x..'+'..b.planDetails.w..' / '..closedButton.x..'+'..closedButton.w..'; bar '..b.planBar.y..' / '..closedBar.y)
  WholeTexts('S21 Details',{'rolled copies','Still needed','Missing tomes','Extra copies','Locked targets'},5)
  p.details:Click()
  P.Render(Model())
  C.expect(NexusPanel._responsiveLayout.boxes.progressValue==nil and not ShownText():find('rolled copies',1,true),
   'S21: Hide details hides the count again')
 end)
 P._playDetails=false
 C.setup(ok,'S21: fixture: the progress scenario ran',err)
end)

-- The approved compact panel draws no rule between its blocks (the draft's
-- decision D6: the one-unit line under the offer block, above the progress
-- row, is gone; the block gap separates them). With three offers, the first
-- of them the selected one (so the last row has no outline of its own): no
-- shown texture of the panel is a rule (at most one unit high, at least half
-- the body wide) from the last offer row's end to the progress row, and the
-- progress row follows the offer block by the draft's 5 pixels. EXPECT,
-- failing at eef1608f by design (the rule stood on the block's last unit).
C.scenario('S21b no rule is drawn between the offer block and the progress row',function()
 local ok,err=pcall(function()
  for _,model in ipairs({G.MODELS.default,G.MODELS.double}) do
   local tag='S21b '..model.name
   local scale=model.size/12
   G.UseFont(model)
   P._playDetails=false
   C.setup(P.Render(Model({cards={{text='Frostwake Sigil (Rare)',highlight=true},{text='Hollow Bell (Rare)'},{text='Ashen Tithe (Uncommon)'}},
    recommendation='Take Frostwake Sigil.'}))==true,tag..': fixture: three offers, the first selected, Details closed')
   local l=NexusPanel._responsiveLayout
   local b=l.boxes
   local cards=NexusPanel._offerCards
   if not C.setup(b.roll~=nil and b.progressHeader~=nil and cards~=nil and cards[3]~=nil and cards[3]:IsShown(),
    tag..': fixture: the offer block, its third row and the progress row are laid out') then return end
   local last=G.Rect(cards[3],NexusPanel)
   local rules={}
   for _,r in ipairs(G.Shown(NexusPanel)) do
    if r.kind=='Texture' then
     local okRect,rect=pcall(G.Rect,r,NexusPanel)
     if okRect and rect[4]-rect[2]<=1.01 and rect[3]-rect[1]>=l.full/2 and rect[2]>=last[4]-2 and rect[4]<=b.progressHeader.y+0.01 then
      rules[#rules+1]=G.Text(rect)
     end
    end
   end
   C.expect(#rules==0,tag..': no rule stands from the last offer row\'s end to the progress row',table.concat(rules,' '))
   C.expect(last[4]<=b.roll.y+b.roll.h+0.01 and Drawn(5,b.progressHeader.y-(b.roll.y+b.roll.h),scale),
    tag..': the progress row follows the offer block by the draft\'s 5 pixels',(b.roll.y+b.roll.h)..' -> '..b.progressHeader.y)
  end
 end)
 G.UseFont(G.MODELS.default)
 P._playDetails=false
 P.Render(Model())
 C.setup(ok,'S21b: fixture: the rule scenario ran',err)
end)

-- Approved panel cleanup, structure: compact 8-unit side insets for every
-- body block, and two-line footer hubs: each hub's name with, under it, what
-- it opens, in existing words (Wishlist Editor; Build Library and
-- Leaderboard; Orbs / Lost Memories). Explore's line carries the two names
-- its menu rows and the opened windows use, in full; it wraps inside its hub
-- rather than being shortened. The hubs keep their routes (their own click
-- handlers).
-- Main-panel visual correction: the three hubs are one width and together
-- span the footer row from its left inset to its right one (they were three
-- 120-unit hubs with a 24-unit "?" after them, which left the row uneven).
-- No help button stands in the footer; Help is reached from Options
-- (owner14_panel_usability F1). EXPECT fails at aca67cf4 by design.
C.scenario('S22 body blocks keep one compact inset; the footer hubs are one line, of one width, each saying what it opens on its hover',function()
 G.UseFont(G.MODELS.default)
 local ss={tier='HC3',mode='HC3',ash='1,240',gain='+45%'}
 local cards,rec=LongOffer('Take Cinder Lattice.')
 C.setup(P.Render(Model({serverStatus=ss,cards=cards,recommendation=rec,bestDps={dummy={dps=4812}}}))==true,'S22: fixture: a Play panel with card, offer and a record')
 local l=NexusPanel._responsiveLayout
 -- The approved compact body: every block stands between the draft's
 -- 7-pixel insets (5 units at this size; they were 8 units).
 local inset=Design(7)
 local off={}
 for name,box in pairs(l.boxes) do
  if box.x<inset or box.x+box.w>l.width-inset then off[#off+1]=name end
 end
 for _,name in ipairs({'status','roll','progressHeader','bestDps','footer','header'}) do
  if not (l.boxes[name] and l.boxes[name].x==inset) then off[#off+1]=name..' x='..tostring(l.boxes[name] and l.boxes[name].x) end
 end
 C.expect(#off==0 and inset==5 and l.inset==inset,'S22: every block starts at the body\'s inset, the draft\'s 7 pixels, and ends inside it',table.concat(off,', '))
 -- The approved one-line footer: each hub shows its own short title and
 -- nothing under it (the draft's 26-pixel hubs: "Wishlist", "Builds",
 -- "Orbs"), and what it opens, which was its second line, is on its hover
 -- in the same words. EXPECT: at eef1608f each hub had that second line on
 -- its face, which the checks here asked for.
 local hubs=NexusPanel._footerButtons or {}
 local want={plan={'panel.button.hub_wishlist','Wishlist Editor'},explore={'panel.button.hub_builds','Build Library','Leaderboard'},
  orbs={'panel.button.orbs','Lost Memories'}}
 local heights={}
 for key,spec in pairs(want) do
  local hub=hubs[key]
  local under,tip,says={},'',true
  for _,r in ipairs(hub and hub.regions or {}) do
   if r.kind=='FontString' and r:IsShown() and Plain(r)~='' then under[#under+1]=Plain(r) end
  end
  if hub then tip=table.concat(V.TooltipLines(hub:GetScript('OnEnter'),hub),' | ') end
  for i=2,#spec do if not tip:find(spec[i],1,true) then says=false end end
  C.expect(hub~=nil and hub:IsShown() and V.Plain(hub:GetText() or '')==(Nexus.Localization.Text(spec[1])) and #under==0,
   'S22: the '..key..' hub is one line: its own title and no second line',tostring(hub and hub:GetText())..' / '..table.concat(under,', '))
  C.expect(says,'S22: the '..key..' hub says what it opens on its hover: '..table.concat(spec,', ',2),tip)
  if hub then
   C.guard(type(hub:GetScript('OnClick'))=='function','S22: the '..key..' hub keeps its click route')
   heights[#heights+1]=hub:GetHeight()
  end
 end
 C.expect(#heights==3 and heights[1]==heights[2] and heights[2]==heights[3] and heights[1]==l.boxes.footer.h
  and Drawn(26,heights[1]),
  'S22: the three hubs share the footer row\'s height, the draft\'s 26 pixels',table.concat(heights,'/'))
 local footer=l.boxes.footer
 local rects,spans={}, {}
 for i,key in ipairs({'plan','explore','orbs'}) do
  rects[i]=hubs[key] and G.Rect(hubs[key],NexusPanel) or nil
  spans[i]=rects[i] and G.Text(rects[i]) or 'no hub'
 end
 if C.setup(rects[1]~=nil and rects[2]~=nil and rects[3]~=nil and footer~=nil,'S22: fixture: the three hubs and the footer box are laid out') then
  local w1,w2,w3=rects[1][3]-rects[1][1],rects[2][3]-rects[2][1],rects[3][3]-rects[3][1]
  local g1,g2=rects[2][1]-rects[1][3],rects[3][1]-rects[2][3]
  C.expect(w1==w2 and w2==w3 and rects[1][1]==footer.x and rects[3][3]==footer.x+footer.w and g1>0 and g2>0 and math.abs(g1-g2)<=1,
   'S22: the three hubs are one width and span the footer row, with one gap between them (to a unit)',
   table.concat(spans,' ')..' in '..footer.x..'+'..footer.w)
  -- Every shown button of the panel itself that lies in the footer row is
  -- one of the three hubs: no help button stands there.
  local extra={}
  for _,child in ipairs(NexusPanel.children or {}) do
   if child.kind=='Button' and child:IsShown() and child~=hubs.plan and child~=hubs.explore and child~=hubs.orbs then
    local okRect,r=pcall(G.Rect,child,NexusPanel)
    if okRect and r and r[2]>=rects[1][2]-0.01 and r[4]<=rects[1][4]+0.01 then extra[#extra+1]=tostring(V.Plain(child:GetText() or ''))..' '..G.Text(r) end
   end
  end
  C.expect(#extra==0 and not (NexusPanel._faqBtn and NexusPanel._faqBtn:IsShown()),
   'S22: no other button stands in the footer row (no "?" beside the hubs)',table.concat(extra,' ; '))
 end
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
-- Count disclosure (S32): the banish, reroll and freeze charges are counts
-- and are on the panel only while Details is open. This scenario asked for
-- them whole on a panel with Details closed; that always-visible row is
-- intentionally gone, so the same checks run with Details open, where the
-- row is shown. S32 has the closed panel.
C.scenario('S25 the Orb run line, a long offer tag and the charges are whole on the panel; an unknown quality is said',function()
 local runtime=Nexus.OrbRuntime
 local compact=runtime.CompactStatus
 local wasDetails=P._playDetails
 local ok,err=pcall(function()
  P._playDetails=true
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
 P._playDetails=wasDetails
 G.UseFont(G.MODELS.default)
 P.Render(Model())
 C.setup(ok,'S25: fixture: the full-text scenario ran',err)
end)

-- Main-panel visual correction, the selected offer (a selected accent
-- outline around a dark fill): the one selected row (the runtime's marked
-- offer) shows a thin outline along its own four edges, in the appearance's
-- accent (ui_theme_appearance), around a dark ground; the other rows show
-- neither, without a selected offer no row does, and a row that goes leaves
-- neither behind. No icon has an outline and the rows stay display-only.
-- The check that stood here asked for a filled band with a 2-unit accent bar
-- and no outline (the approved cleanup's look, which this correction
-- replaces); it is replaced by the outline's own checks, not relaxed. EXPECT
-- fails at aca67cf4 by design (a band and a bar, no outline).
C.scenario('S26 the selected offer row has a thin accent outline around a dark fill; the other rows have neither; no click',function()
 G.UseFont(G.MODELS.default)
 -- Per row: how many of its outline's edges are shown, and its fill.
 local function Marks()
  local c,shown,notes=NexusPanel._offerCards,{},{}
  for i=1,3 do
   local edges=0
   for _,edge in ipairs(c[i].outline or {}) do if edge:IsShown() then edges=edges+1 end end
   shown[i]={edges=edges,fill=(c[i].fill~=nil and c[i].fill:IsShown()) and true or false}
   notes[i]=edges..' edges, fill '..tostring(shown[i].fill)
  end
  return c,shown,table.concat(notes,' / ')
 end
 local cards=LongOffer('Take Cinder Lattice.')
 C.setup(P.Render(Model({cards=cards,recommendation='Take Cinder Lattice.'}))==true,'S26: fixture: an offer whose first row is selected')
 local c,shown,notes=Marks()
 C.expect(shown[1].edges==4 and shown[1].fill and shown[2].edges==0 and not shown[2].fill and shown[3].edges==0 and not shown[3].fill,
  'S26: only the selected row shows its four-edge outline and its fill',notes)
 C.expect(c[1].accent==nil and c[2].accent==nil and c[3].accent==nil,'S26: no row has the former accent bar')
 if shown[1].edges==4 then
  local row,area=G.Rect(c[1],NexusPanel),G.Rect(NexusPanel._rollArea,NexusPanel)
  local sides,drawn,onRow={},{},true
  for _,edge in ipairs(c[1].outline) do
   local r=G.Rect(edge,NexusPanel)
   local w,h=r[3]-r[1],r[4]-r[2]
   drawn[#drawn+1]=G.Text(r)
   -- One unit thin, on one side of the row's own box, as long as that side.
   if h==1 and w==row[3]-row[1] and r[1]==row[1] and r[2]==row[2] then sides.top=true
   elseif h==1 and w==row[3]-row[1] and r[1]==row[1] and r[4]==row[4] then sides.bottom=true
   elseif w==1 and h==row[4]-row[2] and r[2]==row[2] and r[1]==row[1] then sides.left=true
   elseif w==1 and h==row[4]-row[2] and r[2]==row[2] and r[3]==row[3] then sides.right=true
   else onRow=false end
  end
  local fill=G.Rect(c[1].fill,NexusPanel)
  C.expect(onRow and sides.top and sides.bottom and sides.left and sides.right
   and fill[1]==row[1] and fill[2]==row[2] and fill[3]==row[3] and fill[4]==row[4] and G.Inside(row,area,0.01),
   'S26: the outline is four 1-unit edges on the row\'s own box, around the fill, inside the offer block',
   table.concat(drawn,' ')..' row '..G.Text(row)..' fill '..G.Text(fill))
  -- The selected offer's reason is the offer block's own text inside the
  -- row: the fill must be drawn under it, so it is a texture of the offer
  -- block (under that block's texts), not of the row above them.
  C.expect(c[1].fill:GetParent()==NexusPanel._rollArea,'S26: the fill is drawn under the reason, as a texture of the offer block')
 end
 local clickable,iconOutlined=false,false
 for i=1,3 do
  if c[i]:GetScript('OnClick') or c[i]:GetScript('OnMouseUp') or c[i]:GetScript('OnMouseDown') then clickable=true end
  if c[i].edges~=nil or (c[i]._nexusSlot and (c[i]._nexusSlot.edges~=nil or c[i]._nexusSlot.interior~=nil)) then iconOutlined=true end
 end
 C.guard(not clickable and not iconOutlined,'S26: the rows stay display-only and no icon has an outline')
 C.setup(P.Render(Model({cards={{text='Cinder Lattice (Epic)'},{text='Hollow Bell (Rare)'},{text='Ashen Tithe'}}}))==true,
  'S26: fixture: an offer with no selected row')
 c,shown,notes=Marks()
 C.expect(shown[1].edges==0 and not shown[1].fill and shown[2].edges==0 and not shown[2].fill and shown[3].edges==0 and not shown[3].fill,
  'S26: without a selected offer no row shows an outline or a fill',notes)
 C.setup(P.Render(Model({cards=cards,recommendation='Take Cinder Lattice.'}))==true,'S26: fixture: the selected offer again')
 P.Render(Model())
 c,shown,notes=Marks()
 C.expect(not c[1]:IsShown() and shown[1].edges==0 and not shown[1].fill and shown[2].edges==0 and not shown[2].fill
  and shown[3].edges==0 and not shown[3].fill,'S26: with the offer gone no outline or fill stays behind',notes)
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
 -- The footer against the last setup box, as the approved draft spaces the
 -- body: the two setup buttons one 5-pixel block gap apart, the footer its
 -- own 12 pixels under the last of them, and the panel ending 6 pixels
 -- under the footer. (It was one layout gap, the gap between the two setup
 -- buttons, under the last button, and 6 units under the footer.) No least
 -- height is kept: the footer follows the last button whatever stands above.
 local function Tail(tag)
  local layout=NexusPanel._responsiveLayout
  local boxes=type(layout)=='table' and layout.boxes or {}
  local assign,create,footer=boxes.setupAssign,boxes.setupCreate,boxes.footer
  if not C.setup(assign and create and footer,tag..': fixture: the setup view lays out both buttons and the footer') then return nil end
  local gap=create.y-(assign.y+assign.h)
  local band=footer.y-(create.y+create.h)
  print('OBSERVED',tag,'create ends '..tostring(create.y+create.h),'footer '..tostring(footer.y),'band '..tostring(band),
   'gap '..tostring(gap),'height '..tostring(NexusPanel:GetHeight()))
  return band,gap,Drawn(6,NexusPanel:GetHeight()-(footer.y+footer.h)) and NexusPanel:GetHeight()==layout.height
 end
 C.setup(P.Render(Setup())==true,'S27: fixture: the setup view with no board renders')
 local band,gap,closed=Tail('S27 no board')
 if band==nil then return end
 -- (EXPECT: the distances are the draft's; the guard that stood here asked
 -- for the layout's own gap.)
 C.expect(Drawn(12,band) and Drawn(5,gap) and closed,'S27: without a board the footer follows Create Wishlist by its 12-pixel gap',tostring(band)..' / '..tostring(gap))
 for _,case in ipairs({{'with the difficulty card',SERVER},{'without the difficulty card',nil}}) do
  local tag='S27 board '..case[1]
  C.setup(P.Render(Setup(BOARD,case[2]))==true and NexusPanel._offerCards[1]:IsShown() and NexusPanel._offerCards[3]:IsShown(),
   tag..': fixture: the setup view shows the three offers')
  band,gap,closed=Tail(tag)
  if band==nil then return end
  C.expect(Drawn(12,band) and Drawn(5,gap),tag..': the footer follows Create Wishlist by its 12-pixel gap (no empty band)',tostring(band)..' / '..tostring(gap))
  C.expect(closed,tag..': the panel ends 6 pixels under the footer, at the layout height',NexusPanel:GetHeight())
 end
 -- Independent review of the first candidate of the main-panel visual
 -- corrections (A1): the setup hint had two modelled lines whatever it said,
 -- so a longer one lost its end. It is as tall as its wrapped text now (its
 -- lines are counted here from the note's words in the stated font model,
 -- not read from the row), and the buttons and the footer follow it as
 -- before. EXPECT fails at aca67cf4 (22 units for a three-line note).
 local NOTE='Synthetic setup note that is long enough to need several lines in the panel at every supported text size, '
  ..'so a hint held to two modelled lines would lose its end.'
 local noted=Setup()
 noted.assignment={state='unavailable',note=NOTE}
 C.setup(P.Render(noted)==true,'S27: fixture: the setup view with a long note renders')
 band,gap,closed=Tail('S27 long note')
 if band==nil then return end
 local hintBox=NexusPanel._responsiveLayout.boxes.setupHint
 local noteLines=hintBox and G.Rows(NOTE,hintBox.w,G.MODELS.default.char) or 0
 C.setup(hintBox~=nil and noteLines>2,'S27: fixture: the note needs more than the two modelled lines of the hint',noteLines)
 C.expect(hintBox~=nil and hintBox.h==noteLines*G.MODELS.default.line,
  'S27: the hint row holds every line of a long note',tostring(hintBox and hintBox.h)..' for '..tostring(noteLines)..' lines')
 C.expect(Drawn(12,band) and Drawn(5,gap) and closed,'S27: under a long note the footer still follows Create Wishlist by its 12-pixel gap and the panel ends 6 pixels under it',
  tostring(band)..' / '..tostring(gap))
 P.Render(Model())
end)

-- Approved panel cleanup (DESIGN_NOTES 4 and 8 and the owner-accepted
-- preview): "Counts (plan, per-offer ownership, Orb run) appear only inside
-- expanded Details." The Orb run strip under the offer keeps the run's state
-- and its wait in words, with Open, and carries no number; the Orb window's
-- complete line (Orbs used of the approved maximum, what awaits a result, the
-- rolled copies still missing) is drawn whole, wrapped, inside the open
-- Details block. The numberless words come from the Orb window's own read: a
-- third value of PanelRunLine beside the two it always returned, which keep
-- their numbers. EXPECT fails before the correction (the strip was the
-- numbered line, Details held no Orb row and there was no third value);
-- GUARD: the two established values, the hover and the effect counters.
C.scenario('S29 the Orb run strip outside Details carries no number; the run\'s numbers are whole inside Details',function()
 G.UseFont(G.MODELS.default)
 local runtime=Nexus.OrbRuntime
 if not C.setup(type(runtime)=='table' and type(Nexus.OrbPanel.PanelRunLine)=='function','S29: fixture: the Orb read exists') then return end
 local compact,status=runtime.CompactStatus,nil
 runtime.CompactStatus=function() return status end
 local wasDetails=P._playDetails
 local function Digits(text) return tostring(text or ''):find('%d')~=nil end
 local function Run(o)
  local s={state='WAIT_RESULT',spent=2,limit=5,reserved=1,running=true,pending=true,canResume=false,
   uncertain=0,unconfirmedResults=0,historyKnown=true,remaining=3,limitKnown=true}
  for k,v in pairs(o or {}) do s[k]=v end
  return s
 end
 local ok,err=pcall(function()
  -- The producer. {what, status, the wait mark the numbered line shows}.
  local CASES={
   {'a requested Orb',Run(),'; ... '},
   {'an unsettled result',Run({reserved=0}),'; ... '},
   {'an unconfirmed spend',Run({uncertain=1}),'; ? '},
   {'a pause that an earlier action must settle',Run({state='PAUSED',reserved=0,running=false,pending=false}),nil},
   {'a recovery being checked',Run({state='RECOVERY',reserved=0,running=false,pending=false,recoveryPhase='checking',recoveryKind='automatic'}),nil},
  }
  for _,case in ipairs(CASES) do
   status=case[2]
   local shown,full,strip=Nexus.OrbPanel.PanelRunLine()
   -- The state words: what the numbered line says before its usage.
   local state=type(shown)=='string' and shown:match('^(.-); Used ') or nil
   if C.setup(type(full)=='string' and state~=nil,'S29: fixture: '..case[1]..': the numbered line names its state, then its usage',tostring(shown)) then
    C.guard(Digits(shown) and Digits(full) and (shown:find('; ? ',1,true)~=nil or shown:find('; ... ',1,true)~=nil)==(case[3]~=nil)
     and (case[3]==nil or shown:find(case[3],1,true)~=nil),
     'S29: '..case[1]..': the two established values keep the run\'s numbers and wait mark',shown)
    C.expect(type(strip)=='string' and strip~='' and not Digits(strip),'S29: '..case[1]..': the third value has no number',tostring(strip))
    if type(strip)=='string' then
     local rest=strip:sub(#state+1)
     C.expect(strip:sub(1,#state)==state,'S29: '..case[1]..': the third value keeps the complete state words',strip..' / '..state)
     C.expect((case[3]==nil and rest=='') or (case[3]~=nil and rest:sub(1,#case[3])==case[3] and #rest>#case[3]),
      'S29: '..case[1]..': the third value '..(case[3] and 'says the wait in words after the same mark' or 'adds nothing to the state'),'"'..rest..'"')
    end
   end
  end
  -- The panel.
  status=Run()
  local shown,full,strip=Nexus.OrbPanel.PanelRunLine()
  local cards,rec=LongOffer('Take Cinder Lattice.')
  local function Draw(details)
   P._playDetails=details
   return P.Render(Model({cards=cards,recommendation=rec,missing={'Hollow Bell'}}))==true
  end
  -- Every shown text that names an Orb and carries a digit.
  local function Numbered()
   local hits={}
   for _,r in ipairs(G.Shown(NexusPanel)) do
    if r.kind=='FontString' then
     local plain=Plain(r)
     if plain:find('Orb',1,true) and Digits(plain) then hits[#hits+1]=plain end
    end
   end
   return hits
  end
  local before=Effects()
  if not C.setup(Draw(false) and NexusPanel._play.orb:IsShown(),'S29: fixture: a Play panel with an Orb run, Details closed') then return end
  local p=NexusPanel._play
  C.expect(type(strip)=='string' and Plain(p.orb)==strip and p.orbOpen:IsShown(),
   'S29: Details closed: the strip is the run\'s state and wait in words, with Open',Plain(p.orb))
  local hits=Numbered()
  C.expect(#hits==0,'S29: Details closed: no shown text carries an Orb run number',table.concat(hits,' | '))
  C.guard(p.orbHit._nexusFull==full,'S29: the strip\'s hover still gives the Orb window\'s complete line')
  local closedHeight=NexusPanel:GetHeight()
  C.setup(Draw(true),'S29: fixture: the same panel with Details open')
  local boxes=NexusPanel._responsiveLayout.boxes
  local detail=p.orbDetail
  C.expect(detail~=nil and detail:IsShown() and Plain(detail)==full and Digits(Plain(detail)),
   'S29: Details open: the Orb window\'s complete line, with its numbers, is shown',detail and Plain(detail) or 'no Details Orb text')
  if detail and detail:IsShown() and boxes.planLocked and boxes.needed then
   local rect=G.Rect(detail,NexusPanel)
   C.expect(rect[4]-rect[2]+0.5>=detail:GetStringHeight() and rect[3]-rect[1]>=boxes.needed.w
    and rect[2]>=boxes.planLocked.y+boxes.planLocked.h-0.01 and rect[4]<=boxes.needed.y+0.01,
    'S29: Details open: that line is whole (wrapped in its measured height), under the four counts and above the name columns',
    G.Text(rect)..' needs '..tostring(detail:GetStringHeight()))
  end
  C.expect(type(strip)=='string' and Plain(p.orb)==strip,'S29: Details open: the strip outside Details still carries no number',Plain(p.orb))
  C.setup(Draw(false),'S29: fixture: Details closed again')
  hits=Numbered()
  C.expect(#hits==0 and not (detail and detail:IsShown()) and NexusPanel:GetHeight()==closedHeight,
   'S29: closing Details hides the numbers again and gives their row\'s height back',table.concat(hits,' | ')..' '..NexusPanel:GetHeight()..'/'..closedHeight)
  C.guard(Effects()==before,'S29: showing the strip and the Details line makes no game action, send, saved-data or Auto change',Effects())
 end)
 runtime.CompactStatus=compact
 P._playDetails=wasDetails
 P.Render(Model())
 C.setup(ok,'S29: fixture: the Orb scenario ran',err)
end)

-- Per-offer ownership (the third family of counts in DESIGN_NOTES 4 and 8).
-- The real producer gives an offer one annotation from a fixed set of words
-- (Readout.CardLine with a Policy annotation code, worded by
-- UserText.Annotation); none of them is an ownership count, so an offer row
-- shows no such number outside Details and nothing is taken off it. GUARD
-- (holds before and after): every real annotation is numberless on its row,
-- and the row still names the offer and its quality.
C.scenario('S30 a real offer annotation is words only: no ownership number on an offer row',function()
 G.UseFont(G.MODELS.default)
 local words=Nexus.UserText and Nexus.UserText.Annotation
 if not C.setup(type(words)=='function','S30: fixture: the annotation wording exists') then return end
 for _,code in ipairs({'wanted','returns later','banked','filler','low quality','target met','wrong quality','target satisfied','frozen'}) do
  local note=words(code)
  C.guard(type(note)=='string' and note~='' and note~=code and not note:find('%d'),'S30: the "'..code..'" annotation is worded without a number',tostring(note))
  C.setup(P.Render(Model({cards={{text='Hollow Bell (Rare) '..tostring(note)},{text='Cinder Lattice (Epic)'},{text='Ashen Tithe'}}}))==true,
   'S30: fixture: an offer with the "'..code..'" annotation renders')
  local card=NexusPanel._offerCards[1]
  -- These model cards carry only their line: a card whose producer gave it
  -- no annotation code. The row shows such a card's annotation exactly as
  -- it is, the "different quality" one included: the panel reads no meaning
  -- out of a shown text. The annotation is also the row's own tag, on its
  -- hover. (The runtime's render carries the code beside the line:
  -- tests/prototype/automation.lua, OFFER_ANNOTATION.)
  local tip=table.concat(V.TooltipLines(card:GetScript('OnEnter'),card),' | ')
  C.guard(Plain(card.name)=='Hollow Bell' and Plain(card.quality):find('Rare',1,true)~=nil and Plain(card.tag)==note
   and card._nexusTag==note and tip:find(note,1,true)~=nil
   and not Plain(card.tag):find('%d'),'S30: the "'..code..'" row names its offer and quality and shows the annotation, with no number',
   Plain(card.name)..' | '..Plain(card.quality)..' | '..Plain(card.tag)..' | hover '..tip)
 end
 -- The approved short status (decision D3, "Wrong quality") is worded from a
 -- fact, not from the row's text: it stands only on a model card that itself
 -- carries a "different quality" annotation code (`annotation`: the Policy's
 -- own 'wrong quality' or 'low quality', the word its line was written
 -- from). The complete annotation stays the row's own tag and is whole on
 -- its hover. EXPECT (at eef1608f the row shows the complete annotation).
 local short=(Nexus.Localization.Text('panel.label.offer_wrong_quality'))
 C.setup(type(short)=='string' and short~='' and short~=words('wrong quality'),'S30: fixture: the short status is worded and is not the complete annotation',tostring(short))
 for _,code in ipairs({'wrong quality','low quality'}) do
  local note=words(code)
  C.setup(P.Render(Model({cards={{text='Hollow Bell (Rare) '..tostring(note),annotation=code},{text='Cinder Lattice (Epic)'},{text='Ashen Tithe'}}}))==true,
   'S30: fixture: an offer whose card carries the "'..code..'" code renders')
  local card=NexusPanel._offerCards[1]
  local tip=table.concat(V.TooltipLines(card:GetScript('OnEnter'),card),' | ')
  C.expect(Plain(card.name)=='Hollow Bell' and Plain(card.quality):find('Rare',1,true)~=nil and Plain(card.tag)==short
   and card._nexusTag==note and tip:find(note,1,true)~=nil and not (card.star and card.star:IsShown())
   and not Plain(card.tag):find('%d'),'S30: a card that carries the "'..code..'" code shows the short status, with its complete annotation on the hover',
   Plain(card.name)..' | '..Plain(card.quality)..' | '..Plain(card.tag)..' | hover '..tip)
 end
 -- GUARD (each holds before and after): the code alone decides, and only
 -- for an unselected, ordinary offer. Another code keeps its annotation; a
 -- guaranteed offer keeps its guaranteed tag before the annotation; the
 -- selected offer keeps its own status and is never the short one.
 local wrong=words('wrong quality')
 C.setup(P.Render(Model({cards={{text='Hollow Bell (Rare) '..tostring(words('wanted')),annotation='wanted'},
  {text='[Guaranteed offer] Cinder Lattice (Epic) '..tostring(wrong),annotation='wrong quality'},
  {text='Ashen Tithe (Uncommon) '..tostring(wrong),annotation='wrong quality',highlight=true}}}))==true,
  'S30: fixture: three offers whose cards carry codes render')
 local rows=NexusPanel._offerCards
 C.guard(Plain(rows[1].tag)==words('wanted'),'S30: a card that carries another code keeps its own annotation',Plain(rows[1].tag))
 C.guard(Plain(rows[2].tag)~=short and Plain(rows[2].tag):find(wrong,1,true)~=nil and Plain(rows[2].tag):find('Guaranteed offer',1,true)~=nil,
  'S30: a guaranteed offer keeps its guaranteed tag and its complete annotation',Plain(rows[2].tag))
 C.guard(rows[3]._nexusMarked==true and Plain(rows[3].tag)~=short and not Plain(rows[3].tag):find(wrong,1,true),
  'S30: the selected offer keeps its own status, never the short one',Plain(rows[3].tag))
 P.Render(Model())
end)

-- Independent Spec review of 24a40301, required finding: the Orb controls
-- strip attached under the main panel (NexusPanel._orbControls, a child of
-- the panel, shown with it) is a surface the panel owns, so the count rule
-- applies to it too: "Counts (plan, per-offer ownership, Orb run) appear only
-- inside expanded Details." It drew "Orbs used: N / M approved", the pending
-- or remaining-copies count and "Paused - N Orbs pending" whatever Details
-- was. It keeps its own state and wait words, the paused target's whole name
-- and kind, and its Pause / Resume / Stop / Details controls and gates; the
-- run's numbers are in the open Details row (S29) and on the strip's hover.
-- The strip is reached as the player gets it: the real panel is rendered and
-- time is advanced, so the strip's own scheduled read (four times a second)
-- draws it. S29 never advanced time and so never saw it.
-- The count fields of the synthetic run are numbers that appear nowhere else
-- (41 used, 97 approved, 13 pending, 58 remaining, 29 unknown exposure, 31
-- unconfirmed outcomes); the target's name contains a digit of its own, which
-- is identity and must stay whole. EXPECT fails before the correction; GUARD:
-- the words, the name and kind, the controls' gates, the hover and the effect
-- counters.
C.scenario('S31 the Orb controls strip attached under the panel draws no run count, with Details closed or open',function()
 G.UseFont(G.MODELS.default)
 local runtime=Nexus.OrbRuntime
 if not C.setup(type(runtime)=='table' and type(runtime.CompactStatus)=='function','S31: fixture: the Orb runtime read exists') then return end
 local compact,status=runtime.CompactStatus,nil
 runtime.CompactStatus=function() return status end
 local wasDetails=P._playDetails
 -- Time is advanced below, and the host's own schedule then refreshes the
 -- panel: the refresh renders `shown`, the model this scenario last drew
 -- (Panel.Init keeps one table; S28, the last scenario, installs its own).
 local shown
 P.Init({RefreshDisplay=function() return shown and P.Render(shown) or false end})
 local NAME='Rank 2 Covenant'
 local COUNTS={41,97,13,58,29,31}
 local function Run(o)
  local s={state='WAIT_RESULT',spent=41,limit=97,reserved=13,running=true,pending=true,canResume=false,
   uncertain=0,unconfirmedResults=0,historyKnown=true,remaining=58,limitKnown=true}
  for k,v in pairs(o or {}) do s[k]=v end
  return s
 end
 local function Paused(target,o)
  local s=Run({state='PAUSED',running=false,pending=false,reserved=0,canResume=true,resumeTarget=target})
  for k,v in pairs(o or {}) do s[k]=v end
  return s
 end
 -- {what, the run, words the strip already said and must keep, numberless
 -- words that replace a counted line (nil: none), the target's kind word
 -- (nil: no target row), {Pause, Resume, Stop} enabled}. The gates are the
 -- strip's established ones: Pause while running; Resume for a paused run
 -- that may resume and whose target did not change; Stop while running,
 -- pending or paused.
 local CASES={
  {'running with requested Orbs',Run(),{'Waiting for result confirmation'},{'awaiting Orb result'},nil,{true,false,true}},
  {'running with an unsettled result',Run({reserved=0}),{'Waiting for result confirmation','Last Orb action is not settled'},nil,nil,{true,false,true}},
  {'running with an unknown spend',Run({reserved=0,pending=false,uncertain=29,unconfirmedResults=31}),
   {'Waiting for result confirmation'},{'spend not confirmed'},nil,{true,false,true}},
  {'paused, Resume uses the same target',Paused({kind='same',name=NAME}),{'Paused'},nil,'(same)',{false,true,true}},
  {'paused, the target is new',Paused({kind='changed',name=NAME}),{'Paused - review it in the Orb window'},nil,'(new)',{false,false,true}},
  {'paused, the target came back',Paused({kind='changed',name=NAME,returned=true}),{'Paused - review it in the Orb window'},nil,'(back)',{false,false,true}},
  {'paused with requested Orbs',Paused({kind='same',name=NAME},{reserved=13,pending=true,canResume=false}),
   {'Paused'},{'awaiting Orb result'},'(same)',{false,false,true}},
  {'a recovery being checked',Run({state='RECOVERY',running=false,pending=false,reserved=0,recoveryPhase='checking',recoveryKind='automatic'}),
   {'Recovery: Checking','Previous result is unresolved'},nil,nil,{false,false,false}},
 }
 local cards,rec=LongOffer('Take Cinder Lattice.')
 local function Has(text,words)
  for _,word in ipairs(words or {}) do if not text:find(word,1,true) then return false end end
  return true
 end
 local ok,err=pcall(function()
  -- Time is advanced here, and the host's own schedule writes its saved
  -- bookkeeping as time passes, so the saved data is not compared across
  -- this scenario: game actions, sends and the Auto selection are.
  local function Acts()
   return 'actions='..#H.actions..' sent='..#H.sent..' auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)
  end
  local before=Acts()
  for _,case in ipairs(CASES) do
   for _,details in ipairs({false,true}) do
    local tag='S31 '..case[1]..(details and ', Details open' or ', Details closed')
    status=case[2]
    P._playDetails=details
    shown=Model({cards=cards,recommendation=rec,missing={'Hollow Bell'}})
    C.setup(P.Render(shown)==true,tag..': fixture: the Play panel renders')
    H.Advance(.3)
    local bar=NexusPanel._orbControls
    if C.setup(bar~=nil and bar:GetParent()==NexusPanel and bar:IsVisible() and bar.summary~=nil and bar.summary:IsVisible(),
     tag..': fixture: the attached strip is shown under the panel after its scheduled read') then
     -- Everything the strip draws: its label and the text of each shown control.
     local drawn={}
     for _,r in ipairs(G.Shown(bar)) do
      if r.kind=='FontString' then drawn[#drawn+1]=Plain(r) end
     end
     local all=table.concat(drawn,'\n')
     local label=Plain(bar.summary)
     -- A count field: its number standing alone, or any of the count labels.
     local counted={}
     for _,n in ipairs(COUNTS) do
      if all:find('%f[%d]'..n..'%f[%D]') then counted[#counted+1]=tostring(n) end
     end
     for _,word in ipairs({'Orbs used','approved','pending','remaining','copies left','copy left','exposure','outcomes:'}) do
      if all:find(word,1,true) then counted[#counted+1]=word end
     end
     C.expect(#counted==0,tag..': the strip draws no usage, approved, pending, remaining or exposure count',table.concat(counted,', ')..' in: '..all)
     -- Apart from the target's own name, nothing drawn on the strip is a number.
     local rest=all:gsub(NAME:gsub('%p','%%%0'),'')
     C.expect(not rest:find('%d'),tag..': apart from the target\'s name, the strip draws no digit',all)
     C.guard(Has(label,case[3]),tag..': the strip still says its state in its own words ('..table.concat(case[3],' / ')..')',label)
     if case[4] then
      C.expect(Has(label,case[4]),tag..': the wait a count used to state is said in words ('..table.concat(case[4],' / ')..')',label)
     end
     if case[5] then
      -- Identity: the name is whole, digit included, with its kind after it.
      C.expect(label:find("'"..NAME.."' "..case[5],1,true)~=nil,
       tag..': the paused target is named whole, digit included, with its kind '..case[5],label)
      C.guard(label:find(case[5],1,true)~=nil and label:find("'Rank 2",1,true)~=nil,
       tag..': the paused target row names the target and its kind',label)
     end
     local rect=G.Rect(bar.summary,NexusPanel)
     C.expect(rect[4]-rect[2]+0.5>=bar.summary:GetStringHeight() and not label:find('...',1,true),
      tag..': the strip\'s words are whole: not cut, in a box as tall as its lines',
      G.Text(rect)..' needs '..tostring(bar.summary:GetStringHeight())..': '..label)
     -- The controls: shown, in one row under the words, inside the strip, with their gates.
     -- Start/Stop surfaces (2026-11-19, 9106 field report): the earlier
     -- runtime's run is history here. Its Pause and Resume (and a Stop of a
     -- run that is not running) are not offered; a run of it that is actually
     -- running keeps its real Stop; Details stays.
     local stopShown=case[2].running==true
     local strip=G.Rect(bar,NexusPanel)
     local row,inside,below=nil,true,true
     for _,b in ipairs(stopShown and {bar.stop,bar.details} or {bar.details}) do
      local r=b:IsVisible() and G.Rect(b,NexusPanel) or nil
      if not r then inside=false else
       row=row or r[2]
       if r[2]~=row or not G.Inside(r,strip,0.01) then inside=false end
       if r[2]<rect[4]-0.01 then below=false end
      end
     end
     C.guard(inside and below,tag..': the shown controls (Stop of a running run, Details) are in one row inside the strip, under its words',
      G.Text(strip)..' words '..G.Text(rect))
     C.guard(not bar.pause:IsShown() and not bar.resume:IsShown() and not bar.primary:IsShown()
      and bar.stop:IsShown()==stopShown and (not stopShown or bar.stop:IsEnabled())
      and (bar.details:IsEnabled() and true or false)==true
      and (not stopShown or V.Plain(bar.stop:GetText() or '')=='Stop') and V.Plain(bar.details:GetText() or '')=='Details',
      tag..': no Pause or Resume; Stop only for a running run; Details kept',
      tostring(bar.pause:IsShown())..'/'..tostring(bar.resume:IsShown())..'/'..tostring(bar.stop:IsShown())..'/'..tostring(bar.stop:IsEnabled()))
     -- The numbers are not lost. They are on the strip's hover (the strip
     -- drew them itself before the correction, so this hover is new)...
     local whole=tostring(bar.summary._nexusFullText or '')
     C.expect(whole:find('%f[%d]41%f[%D]')~=nil and whole:find('%f[%d]97%f[%D]')~=nil,
      tag..': the strip\'s hover gives the run\'s complete numbered text',whole)
     -- ...and in the open Details row, which is the panel's place for them.
     local detail=NexusPanel._play and NexusPanel._play.orbDetail
     if details then
      local text=detail and detail:IsShown() and Plain(detail) or ''
      C.guard(text:find('%f[%d]41%f[%D]')~=nil and text:find('%f[%d]97%f[%D]')~=nil,
       tag..': the open Details row shows the run\'s numbers',text)
     else
      C.guard(not (detail and detail:IsShown()),tag..': with Details closed there is no Details Orb row')
     end
    end
   end
  end
  C.guard(Acts()==before,'S31: drawing the strip takes no game action, sends nothing and leaves Auto as it was',Acts())
 end)
 status=nil
 shown=Model()
 P.Render(shown)
 H.Advance(.3)
 runtime.CompactStatus=compact
 P._playDetails=wasDetails
 -- No host callback from here on: Panel.Refresh renders its last model.
 P.Init({})
 P.Render(Model())
 C.setup(ok,'S31: fixture: the attached strip scenario ran',err)
end)

-- Count disclosure, the charges (approved cleanup: "Counts stay hidden until
-- Details is opened"; the counts are read broadly). The compact banish,
-- reroll and freeze row beside the offer heading is a count too, and it was
-- the one count Details did not govern: it showed whenever the model carried
-- charge facts. With Details closed it is not on the panel now: no row, no
-- hover and no cell kept for it, so the heading has its whole row and the
-- panel is exactly the panel of the same offer without charge facts. With
-- Details open it is the row it was: the Readout's own wording of the real
-- charge facts (an unknown count as the Readout says it, never a 0 in its
-- place), whole in its cell at the right end of the heading row, once, with
-- its legend on hover. Closing Details takes it away again. Details belongs
-- to a build in progress, so the setup view (design/DESIGN_NOTES.md: no plan,
-- counts "none") and the completed view, which have no Details control, show
-- no charge counts whatever Details was left at. The difficulty card is not
-- a count: its tier, Soul Ash, multiplier and Intensity bar stay.
-- EXPECT fails at aca67cf4 by design: there the row was shown with Details
-- closed and in the setup and completed views. GUARD: what the open panel
-- shows, which is the row aca67cf4 always showed; the difficulty card; and
-- that showing, hiding and pointing at the row takes no game action and
-- saves nothing. The expected geometry is stated here (the heading row is
-- the offer block less 4 units; the cell is 72 units at the reference text
-- size, 4 units after the heading), not read from the layout engine. Native
-- drawing: NOT RUN.
C.scenario('S32 the banish, reroll and freeze charges are counts: no row, hover or cell with Details closed; the whole row, once, with its hover while Details is open',function()
 local R=Nexus.Readout
 local KNOWN={banish=2,reroll=1,freeze=0,trustworthy=true,arrived=true}
 local wasDetails=P._playDetails
 local before=Effects()
 local ok,err=pcall(function()
  G.UseFont(G.MODELS.default)
  P._playDetails=false
  local cards,rec=LongOffer('Take Cinder Lattice.')
  local function Offer(charges)
   local m=Model({cards=cards,recommendation=rec})
   m.charges=charges
   return m
  end
  local charges,hover,head=NexusPanel._chargesText,NexusPanel._chargesHover,NexusPanel._rollStatus
  -- How many shown texts of the whole panel carry a line.
  local function Count(line)
   local n=0
   for _,r in ipairs(G.Shown(NexusPanel)) do
    if r.kind=='FontString' and V.Plain(r:GetText() or ''):find(line,1,true) then n=n+1 end
   end
   return n
  end
  local function Shape()
   local roll=NexusPanel._responsiveLayout.boxes.roll
   return {rollW=roll.w,rollH=roll.h,rollY=roll.y,panel=NexusPanel:GetHeight(),headW=head:GetWidth(),headH=head:GetHeight()}
  end
  local function Say(s)
   return 'heading '..tostring(s.headW)..'x'..tostring(s.headH)..' in an offer block '..tostring(s.rollW)..'x'..tostring(s.rollH)
    ..', panel '..tostring(s.panel)
  end
  local function Whole(fs) return fs:IsShown() and (fs:GetWidth()+0.5>=fs:GetStringWidth() or fs:GetHeight()+0.5>=fs:GetStringHeight()) end
  -- The same offer without any charge fact: what the closed panel must equal.
  C.setup(P.Render(Offer(nil))==true and NexusPanel._offerCards[1]:IsShown(),'S32: fixture: the offer with no charge facts')
  local bare=Shape()
  local line=R.ChargesLine(KNOWN)
  local words=type(line)=='string' and V.Plain(line) or ''
  -- (The heading's whole row: the offer block's width less the destination
  -- cell at its right end, SlotRoom; the block has no inner insets now, so
  -- the 4 units that were taken off here are gone.)
  if not C.setup(words~='' and bare.headW==bare.rollW-SlotRoom(false) and not charges:IsShown(),
   'S32: fixture: the Readout words the charge facts; without charge facts the heading has the whole row',words..'; '..Say(bare)) then return end

  -- Details closed.
  C.setup(P.Render(Offer(KNOWN))==true and P._playDetails~=true,'S32: fixture: the same offer with real charge facts, Details closed')
  local closed=Shape()
  C.expect(not charges:IsShown() and not hover:IsShown() and Count(words)==0,
   'S32: with Details closed the charge counts are not on the panel: no row and no hover',ShownText())
  C.expect(closed.headW==closed.rollW-SlotRoom(false) and closed.headH==bare.headH and closed.rollH==bare.rollH and closed.rollY==bare.rollY
   and closed.panel==bare.panel,
   'S32: and no room is kept for them: the heading has its whole row and the panel is the panel without charge facts',
   Say(closed)..' / '..Say(bare))
  -- The disclosure hides counts, not every number on the panel. The original
  -- difficulty card is not a count: with Details closed it still shows its
  -- tier, its Soul Ash (1,240 in the card's own short form, 1.2k), its
  -- multiplier and, with a validated scale, its Intensity bar. GUARD: the
  -- card is untouched; the charge counts beside it stay off the panel.
  local carded=Offer(KNOWN)
  carded.serverStatus={tier='HC3',mode='HC3',ash='1,240',gain='+45%',intensity=250,intensityMax=500,
   intensityThresholds={100,200,300,400},intensityLevel=2}
  C.setup(P.Render(carded)==true and P._playDetails~=true,'S32: fixture: the same offer with the difficulty card, Details closed')
  local card,parts=StatusCard(),{}
  for _,region in ipairs(card and card.regions or {}) do if region.kind=='FontString' then parts[#parts+1]=region end end
  C.guard(card~=nil and card:IsShown() and card.intensityBar:IsShown() and #parts>=3
   and parts[1]:IsShown() and Plain(parts[1])=='HC3' and parts[2]:IsShown() and Plain(parts[2]):find('1.2k',1,true)~=nil
   and parts[3]:IsShown() and Plain(parts[3])=='+45%',
   'S32: with Details closed the difficulty card still shows its tier, Soul Ash, multiplier and Intensity bar: the disclosure hides counts, not every number',
   Plain(parts[1])..' | '..Plain(parts[2])..' | '..Plain(parts[3]))
  C.expect(not charges:IsShown() and not hover:IsShown() and Count(words)==0,
   'S32: and beside that card the charge counts stay off the panel',ShownText())
  C.setup(P.Render(Offer(KNOWN))==true and P._playDetails~=true,'S32: fixture: the offer without the card again')

  -- Details open.
  local p=NexusPanel._play
  p.details:Click()
  C.setup(P.Render(Offer(KNOWN))==true and P._playDetails==true and Plain(p.details)=='Hide details','S32: fixture: Details opened')
  local open=Shape()
  local c=NexusPanel._offerCards
  local hr,cr,area=G.Rect(head,NexusPanel),G.Rect(charges,NexusPanel),G.Rect(NexusPanel._rollArea,NexusPanel)
  C.guard(charges:IsShown() and Plain(charges)==words and Count(words)==1,
   'S32: with Details open the charge counts are shown as the Readout words them, once on the whole panel',
   Plain(charges)..' / '..words..' x'..Count(words))
  C.guard(charges:GetWidth()==72 and cr[2]==hr[2] and hr[3]<=cr[1]-4+0.01
   and G.Inside(cr,area,0.01) and Whole(charges) and Whole(head),
   'S32: in their 72-unit cell on the heading row, 4 units after the heading, both whole',
   G.Text(hr)..' '..G.Text(cr)..' in '..G.Text(area))
  -- (EXPECT: the cell ended 2 units from the block's right and the heading
  -- kept the row less 4 and 76. In the compact row the destination cell
  -- follows the charges after a dot at the row's right end, so the charges
  -- cell ends where that cell's room starts and the heading keeps the rest
  -- less the 76.)
  local slot=NexusPanel._offerSlot
  local sr=slot and slot:IsShown() and G.Rect(slot,NexusPanel) or nil
  C.expect(open.headW==open.rollW-SlotRoom(true)-76 and cr[3]==area[3]-SlotRoom(true) and sr~=nil and sr[3]==area[3]
   and sr[1]>=cr[3]-0.01 and Plain(slot)=='\194\183 '..(Nexus.Localization.Text('panel.label.preview_tag')),
   'S32: the charges cell stands before the destination cell, which ends the row after a dot; the heading keeps the rest of the row',
   G.Text(hr)..' '..G.Text(cr)..' '..(sr and G.Text(sr) or 'no cell')..' in '..G.Text(area))
  local apart=true
  for i=1,3 do if not (c[i]:IsShown() and G.Apart(cr,G.Rect(c[i],NexusPanel)) and G.Apart(hr,G.Rect(c[i],NexusPanel))) then apart=false end end
  C.guard(apart and open.rollH-bare.rollH==open.headH-bare.headH and open.rollY==bare.rollY,
   'S32: the row overlaps no offer row, and the offer block is taller only by what its heading row needs',Say(open)..' / '..Say(bare))
  local tipLines=V.TooltipLines(hover:GetScript('OnEnter'),hover)
  C.guard(hover:IsShown() and tipLines[2]==charges:GetText() and #tipLines==2+#R.ChargesLegend(),
   'S32: their hover gives its heading, the complete row and the legend',table.concat(tipLines,' | '))

  -- v9 (Root's ruling SPEC-A2: "allocate enough measured right-cell width
  -- for whole charges/slot on one line when physically available; left text
  -- can wrap"). Larger counts make the same row wider than the 72 units a
  -- cell had. The row is worded by the Readout from these facts; its width
  -- is stated here from its words and the default font model, and the cell
  -- from the rule: that width in whole units, never under 72, in the row
  -- less the destination cell, the 4-unit gap and the 72 units the heading
  -- keeps. Nothing is read from the layout engine. EXPECT: at eef1608f the
  -- cell was 72 units at the reference text size whatever the row said, so
  -- this row was wider than its cell.
  local WIDE={banish=12,reroll=10,freeze=100,trustworthy=true,arrived=true}
  local wideLine=R.ChargesLine(WIDE)
  local wideWords=type(wideLine)=='string' and V.Plain(wideLine) or ''
  local wideNatural=G.Length(wideWords)*G.MODELS.default.char
  local wideRow=open.rollW-SlotRoom(true)
  if C.setup(wideWords~='' and wideNatural>72 and math.ceil(wideNatural)<=wideRow-76,
   'S32: fixture: charge facts whose row is wider than 72 units and fits its heading row beside the heading\'s 72',
   wideWords..' '..tostring(wideNatural)..' in a row of '..tostring(wideRow)) then
   local oneLine=charges:GetStringHeight()
   C.setup(P.Render(Offer(WIDE))==true and P._playDetails==true,'S32: fixture: the same offer with the wider charge row, Details open')
   local wide=Shape()
   local whr,wcr=G.Rect(head,NexusPanel),G.Rect(charges,NexusPanel)
   local wideCell=math.max(72,math.ceil(wideNatural))
   C.expect(charges:IsShown() and Plain(charges)==wideWords and Count(wideWords)==1 and charges:GetWidth()==wideCell
    and charges:GetStringWidth()<=charges:GetWidth()+0.01 and charges:GetStringHeight()==oneLine,
    'S32: a charge row wider than 72 units has a cell of its own one-line width and is whole there on one line',
    Plain(charges)..' '..tostring(charges:GetWidth())..' of '..wideCell..', '..tostring(charges:GetStringHeight())..' / '..tostring(oneLine))
   C.expect(wide.headW==wideRow-wideCell-4 and wide.headW>=72 and Whole(head) and wcr[2]==whr[2] and whr[3]<=wcr[1]-4+0.01
    and wcr[3]==area[3]-SlotRoom(true) and G.Inside(wcr,area,0.01),
    'S32: beside it the heading keeps the rest of the row, whole, 4 units before the cell, which still ends where the destination cell\'s room starts',
    G.Text(whr)..' '..G.Text(wcr)..' in '..G.Text(area))
   C.expect(wide.headH==open.headH and wide.rollH==open.rollH and wide.panel==open.panel,
    'S32: and the wider row adds no line: the heading row, the offer block and the panel are as tall as with the short row',
    Say(wide)..' / '..Say(open))
   C.setup(P.Render(Offer(KNOWN))==true and P._playDetails==true,'S32: fixture: the offer with the short charge row again, Details open')
  end

  -- Unknown counts stay unknown. The facts tried are the ways a count can be
  -- missing; the first the Readout words with "?" is used.
  local unknown,unknownWords
  for _,facts in ipairs({{banish=2,trustworthy=true,arrived=true},{banish=2,reroll=1,freeze=0,trustworthy=true,arrived=false},
   {trustworthy=true,arrived=false},{arrived=false},{}}) do
   local said=R.ChargesLine(facts)
   if type(said)=='string' and V.Plain(said):find('?',1,true) then unknown,unknownWords=facts,V.Plain(said) break end
  end
  if C.setup(unknown~=nil,'S32: fixture: charge facts the Readout words with "?" for a count it does not know') then
   C.setup(P.Render(Offer(unknown))==true and P._playDetails==true,'S32: fixture: the offer with an unknown charge count, Details open')
   C.guard(charges:IsShown() and Plain(charges)==unknownWords and Plain(charges):find('?',1,true)~=nil and Count(unknownWords)==1 and Whole(charges),
    'S32: an unknown count is shown as the Readout says it, with its "?", whole and once',Plain(charges)..' / '..unknownWords)
   p.details:Click()
   C.setup(P.Render(Offer(unknown))==true and P._playDetails~=true,'S32: fixture: Details closed over the unknown count')
   C.expect(not charges:IsShown() and not hover:IsShown() and Count(unknownWords)==0,
    'S32: with Details closed an unknown count is not on the panel either',ShownText())
   p.details:Click()
   C.setup(P.Render(Offer(KNOWN))==true and P._playDetails==true,'S32: fixture: Details open over the known counts again')
  end

  -- Details closed again.
  p.details:Click()
  C.setup(P.Render(Offer(KNOWN))==true and P._playDetails~=true and Plain(p.details)=='Show details','S32: fixture: Details closed again')
  local again=Shape()
  C.expect(not charges:IsShown() and not hover:IsShown() and Count(words)==0 and again.headW==bare.headW and again.headH==bare.headH
   and again.rollH==bare.rollH and again.panel==bare.panel,
   'S32: closing Details takes the charge counts, their hover and their cell away again: the panel without charge facts is back',
   Say(again)..' / '..Say(bare))

  -- The setup view has no Details control: no charge counts, whatever
  -- Details was left at.
  P._playDetails=true
  local setup={status='ready',level=40,auto=false,cards=cards,recommendation=rec,charges=KNOWN,
   progress={total=0,missing={},shed={},toLock={},unknownTomes={}},assignment={state='unassigned',knownUnassigned=true}}
  if C.setup(P.Render(setup)==true and NexusPanel._offerCards[1]:IsShown() and NexusPanel._responsiveLayout.boxes.planDetails==nil,
   'S32: fixture: the setup view with an Echo board and charge facts has no Details control') then
   C.expect(not charges:IsShown() and not hover:IsShown() and Count(words)==0
    and head:GetWidth()==NexusPanel._responsiveLayout.boxes.roll.w-SlotRoom(false),
    'S32: the setup view, which has no Details, shows no charge counts and keeps no cell for them',ShownText())
  end
  -- The completed view (every target owned, none left to lock) has no
  -- Details control either, and can still show an Echo board.
  local done=Model({cards=cards,recommendation=rec,owned=6})
  done.charges=KNOWN
  if C.setup(P.Render(done)==true and NexusPanel._offerCards[1]:IsShown() and NexusPanel._responsiveLayout.play~=true
   and NexusPanel._responsiveLayout.boxes.planDetails==nil,
   'S32: fixture: the completed view with an Echo board and charge facts has no Details control') then
   C.expect(not charges:IsShown() and not hover:IsShown() and Count(words)==0
    and head:GetWidth()==NexusPanel._responsiveLayout.boxes.roll.w-SlotRoom(false),
    'S32: the completed view, which has no Details, shows no charge counts and keeps no cell for them',ShownText())
  end
 end)
 P._playDetails=wasDetails
 G.UseFont(G.MODELS.default)
 P.Render(Model())
 C.setup(ok,'S32: fixture: the charge counts scenario ran',err)
 C.guard(Effects()==before,'S32: showing, hiding and pointing at the charge counts takes no game action, sends and saves nothing and leaves Auto as it was',Effects())
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
 -- (The approved compact panel: AutoSays above. With Auto OFF the heading
 -- is "Your offers" and says no Auto state itself; the tag's words stand
 -- after the row's star. The helper that stood here asked for "Auto OFF"
 -- in the heading and for the tag with its code-owned mark.)
 local function Says(on) return AutoSays(on) end
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
