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
-- across a fit-scale change (S12). Categories
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
 C.expect(card:IsShown() and box~=nil and card:GetHeight()==box.h and box.h>=56,
  'S3: the card is shown in the Play panel at its 56 px active height',tostring(card:GetHeight()))
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
 C.expect(Plain(p.note):find('not a server-wide ranking',1,true)~=nil,'S4: the note says what best known is',Plain(p.note))
 C.expect(not text:lower():find('rank #',1,true),'S4: no rank is claimed')
 -- No shared record yet: loading is a wait, never 0 or "no records".
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
 C.expect(Plain(p.bestValue)=='... shared data loading','S4: shared data loading is named as a wait',Plain(p.bestValue))
 C.expect(Plain(p.yoursValue):find('no record yet',1,true)~=nil and not Plain(p.yoursValue):find('0',1,true),
  'S4: no record of yours is said as none, never 0',Plain(p.yoursValue))
 P.Render(Model({bestDps={},performance={dummy={},lk={}},owned=3}))
 if C.setup(Nexus.StartupStatus().state=='ready','S4: fixture: shared data is ready after start-up',Nexus.StartupStatus().state) then
  C.expect(Plain(p.bestValue)=='none received yet','S4: with shared data ready and no record, none received yet',Plain(p.bestValue))
 end
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

-- The visible drag grip (design/current, D1-D4; issue #168 made plain-left
-- dragging the contract): a plain click does nothing; a plain left drag, with
-- or without Shift, moves the panel through its one drag owner and saves
-- panelX / panelY. Native pointer capture is NOT RUN.
C.scenario('S9 the drag grip: visible, apart from the title and controls; a plain left drag moves',function()
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
 C.expect(tip:find('Drag to move',1,true)~=nil and tip:find('Shift',1,true)==nil,'S9: its hover says Drag to move, without Shift',tip)
 C.expect(grip:GetScript('OnClick')==nil,'S9: a plain click on the grip has no action')
 local moves,stops,cx=0,0,100
 NexusPanel.StartMoving=function() moves=moves+1 end
 NexusPanel.StopMovingOrSizing=function() stops=stops+1 end
 NexusPanel.GetCenter=function() return cx,50 end
 local shift=IsShiftKeyDown
 IsShiftKeyDown=function() return false end
 grip:GetScript('OnDragStart')(grip,'LeftButton');cx=140;grip:GetScript('OnDragStop')(grip)
 C.expect(moves==1 and stops==1,'S9: a plain left drag moves the panel',moves..'/'..stops)
 local saved=P.SavedLayoutRoot()
 C.expect(tonumber(saved.panelX)==140 and tonumber(saved.panelY)==50,'S9: the position is saved as panelX / panelY',
  tostring(saved.panelX)..','..tostring(saved.panelY))
 IsShiftKeyDown=function() return true end
 grip:GetScript('OnDragStart')(grip,'LeftButton');cx=150;grip:GetScript('OnDragStop')(grip)
 IsShiftKeyDown=shift
 NexusPanel.StartMoving,NexusPanel.StopMovingOrSizing,NexusPanel.GetCenter=nil,nil,nil
 C.expect(moves==2 and stops==2 and tonumber(saved.panelX)==150,'S9: a Shift-drag still moves it',moves..'/'..stops)
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
   local spec={width=420,fontScale=scale,activeRoll=true,statusVisible=true,cardRows=true,toLockCount=1,orbLine=true}
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
   C.expect(l.boxes.status~=nil and l.boxes.status.h>=56 and l.boxes.serverLine==nil,
    tag..': the original card keeps at least 56 px; no flattened row',l.boxes.status and l.boxes.status.h)
   if o.noOffer then
    C.expect(l.noOffer==true and l.boxes.roll.h<104 and l.boxes.planBar~=nil,tag..': the roll box collapses below 104 px',l.boxes.roll.h)
    -- Finish pass item E: no blank band where the offers were; the gaps
    -- above and below the collapsed block are at most 8 px, and the block
    -- is exactly its two guidance rows (or the inline button) high.
    local s,r,h=l.boxes.status,l.boxes.roll,l.boxes.progressHeader
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

Nexus.DisableOrdinaryAutomation()
C.finish('(Play summary rows; native NOT RUN)')
