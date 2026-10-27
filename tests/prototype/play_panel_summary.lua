-- Play panel summary after the Claude Design full UI ("Main panel (Play)"):
-- below the offer, a compact plan progress (the run's count, a bar, four
-- counts and Details for the Echo names), Difficulty and Soul Ash on one line,
-- your DPS record beside the best known record for the same Echoes with what
-- best known means, and one line of Orb run status with Open. Categories
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
 return {status='ready',level=40,auto=false,cards=o.cards or {},recommendation=o.recommendation or '',
  progress=pr,serverStatus=o.serverStatus,bestDps=o.bestDps}
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
 for _,f in ipairs(H.frames) do if f._nexusThemeExempt and f:GetParent()==NexusPanel then return f end end
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()

C.scenario('S1 compact plan progress: count, bar and four counts; names only under Details',function()
 local before=Effects()
 local m=Model({owned=2,missing={'Cinder Lattice x2 (Rare:x2)','Hollow Bell'},shed={'Ashen Tithe'},
  toLock={'Gravecall Chorus'},unknownTomes={'Frostwake Sigil'}})
 C.setup(P.Render(m)==true and NexusPanel:IsShown(),'S1: fixture: the HUD renders a build in progress')
 local p=NexusPanel._play
 C.expect(type(p)=='table' and NexusPanel._responsiveLayout and NexusPanel._responsiveLayout.play==true,
  'S1: the Play summary exists in the Play layout')
 if type(p)~='table' then return end
 C.expect(p.needed:IsShown() and Plain(p.needed)=='Still needed  4 copies','S1: still needed copies',Plain(p.needed))
 C.expect(Plain(p.tomes)=='Missing tomes  1 Echo','S1: Echoes blocked by missing tomes',Plain(p.tomes))
 C.expect(Plain(p.extra)=='Extra copies  1 listed','S1: extra copies listed',Plain(p.extra))
 C.expect(Plain(p.locked)=='Locked targets  1 to lock','S1: locked targets still to lock',Plain(p.locked))
 local boxes=NexusPanel._responsiveLayout.boxes
 C.expect(p.track:IsShown() and p.fill:IsShown() and p.fill:GetWidth()==math.floor(boxes.planBar.w*2/6),
  'S1: the bar fills the share of planned rolled copies this run has',tostring(p.fill:GetWidth()))
 C.expect(p.details:IsShown() and Plain(p.details)=='Details','S1: Details is offered on the heading row')
 local text=ShownText()
 C.expect(not text:find('Hollow Bell',1,true) and not text:find('Gravecall Chorus',1,true),
  'S1: the Echo names stay behind Details',text)
 C.expect(not text:find('MISSING TOMES',1,true),'S1: the former tomes row is one of the counts here',text)
 -- Every count box is inside the panel and apart from the others.
 local apart=true
 local names={'planNeeded','planTomes','planExtra','planLocked','planBar','progressHeader','progressValue','planDetails'}
 for i=1,#names do for j=i+1,#names do
  local a,b=boxes[names[i]],boxes[names[j]]
  if not (a and b) or Nexus.LayoutMetrics.Overlap(a,b) then apart=false end
 end end
 C.expect(apart,'S1: heading, bar and counts are disjoint boxes')
 C.guard(Effects()==before,'S1: rendering the summary makes no game action, send, saved-data or Auto change')
 -- Details shows the names; it is memory only.
 local clicked=Effects()
 p.details:Click()
 C.setup(P.Render(m)==true,'S1: fixture: the same model rendered again after Details')
 text=ShownText()
 C.expect(P._playDetails==true and text:find('Hollow Bell',1,true)~=nil and text:find('Gravecall Chorus',1,true)~=nil
  and Plain(p.details)=='Hide details','S1: Details shows the names behind the counts',text)
 C.expect(NexusPanel._responsiveLayout.boxes.needed~=nil,'S1: the name columns are laid out under Details')
 C.guard(Effects()==clicked,'S1: Details changes no game action, send, saved data or Auto',Effects())
 p.details:Click()
 P.Render(m)
 C.expect(P._playDetails==false and not ShownText():find('Hollow Bell',1,true),'S1: Hide details hides them again')
end)

C.scenario('S2 an unknown run count is "?", never 0, and fills no bar',function()
 P.Render(Model({unknownOwned=true}))
 local p=NexusPanel._play
 if not C.setup(type(p)=='table','S2: fixture: the summary exists') then return end
 C.expect(Plain(p.needed)=='Still needed  ?','S2: still needed is unknown',Plain(p.needed))
 C.expect(not p.fill:IsShown(),'S2: no bar fill without a known count')
 C.expect(not ShownText():find('0 copies',1,true),'S2: nothing says 0 copies',ShownText())
end)

C.scenario('S3 Difficulty and Soul Ash on one line in Play; the card stays in the completed view',function()
 local ss={tier='Heroic +2',ash='1,240',gain='20',intensity=250,intensityMax=500}
 P.Render(Model({serverStatus=ss}))
 local p,card=NexusPanel._play,StatusCard()
 if not C.setup(type(p)=='table' and card~=nil,'S3: fixture: the summary and the protected card exist') then return end
 C.expect(p.server:IsShown() and Plain(p.server)=='Difficulty  Heroic +2   Soul Ash  1,240   Multiplier  20   Intensity  250 / 500',
  'S3: one line names difficulty, Soul Ash, multiplier and intensity',Plain(p.server))
 C.expect(not card:IsShown(),'S3: the card is not drawn over the Play panel')
 C.expect(p.serverHit:IsShown() and p.serverHit:GetScript('OnClick')~=nil,'S3: the line keeps the card hover and click')
 P.Render(Model({serverStatus=ss,owned=6}))
 C.guard(card:IsShown(),'S3: a completed build keeps the Difficulty / Soul Ash card')
 C.expect(not p.server:IsShown() and not p.needed:IsShown(),'S3: the completed view shows no Play summary rows')
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

Nexus.DisableOrdinaryAutomation()
C.finish('(Play summary rows; native NOT RUN)')
