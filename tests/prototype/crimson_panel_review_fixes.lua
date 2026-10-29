-- Independent review corrections for the main panel (issues #168, #170,
-- #171, #169), each through the real Panel handlers and controls:
-- V1 (#168, D11) while a move is active, a render's own hide-and-show of the
--    panel does not end it or write a position, even when the hide reaches
--    the shown descendants (the drag origin among them); a real hide of the
--    panel, or the origin's removal by a render, still ends it and saves
--    once; another label disappearing does not;
-- V2 (#168) the visible passive hovers the earlier fit missed (Charges, the
--    recommendation, the Details headings and Extra copies list) fit the text
--    they show, from their own edge, after a font change too; a shortened
--    or overflowing text keeps its whole box; the hidden destination row
--    takes no input;
-- V3 (#168) during a move, hovering the Callboard title (shortened, so its
--    complete-text hover would open) or the objective leaves no tooltip of
--    theirs open; without a move both still show their complete text; a
--    tooltip another frame owns stays open;
-- V4 (#170) a centre saved while the chosen size is reduced to fit is where
--    the panel is placed after a fresh load at that fitted size;
-- V5 (#170) the public FitToScreen refuses infinite frame or screen sizes
--    (and keeps the panel's scale) instead of exceeding the ceiling;
-- V6 (#171) after a confirmed pause, a Status that fails or is malformed is
--    shown as unknown, never as "nothing is paused" or as paused;
-- V7 (#171, #169) with a committed model of Auto selected ON and ready, a
--    confirmed pause through the Options row makes the Auto hover and the
--    details say the session pause holds it (no "Now: ready"); Resume runs
--    no refresh step and restores the model's own state words.
-- Native seams modelled by the test, not client proof: the propagation of a
-- hide to shown descendants (as the client documents for OnHide), effective
-- scale as the product of own scales, the root's centre and corner reads,
-- the shared tooltip's owner, and UIParent's size. Nexus.SessionPause is a
-- boundary double of its frozen API. Categories (view_regression_support):
-- EXPECT fails at 4358349 by design, GUARD already held, SETUP is the
-- fixture. Native NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('crimson_panel_review_fixes')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P,LM=Nexus.Panel,Nexus.LayoutMetrics
local RM=G.RegionMethods()
RM.EnableMouse=function(self,v) self._mouse=v and true or false end
RM.IsMouseEnabled=function(self) return self._mouse==true end
RM.SetJustifyH=function(self,v) self._justify=v end
RM.GetJustifyH=function(self) return self._justify or 'LEFT' end
RM.GetEffectiveScale=function(self)
 local parent=self.parent
 return (self.scale or 1)*(parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1)
end
UIParent:SetSize(1920,1080)
G.UseFont(G.MODELS.default)

local board={observed=true,title='Ember Watch '..string.rep('Long ',30),lines={'Light 4 braziers','Guard the Ember Gate'},rewards={}}
Nexus.CallboardStatus.GetSummary=function() return board end

local function Model(o)
 o=o or {}
 return {status='ready',level=40,auto=o.auto==nil and false or o.auto,paused=o.paused,effective=o.effective,
  cards=o.cards or {{text='Frostwake Sigil (Rare)'}},recommendation=o.recommendation or 'Take Frostwake Sigil.',
  charges=not o.noCharges and (o.charges or {banish=2,reroll=3,freeze=1,arrived=true}) or nil,
  progress={wishlistName='Review plan',total=6,owned=2,missing={'Cinder Lattice x2 (Rare:x2)','Hollow Bell'},
   shed={'Ashen Tithe'},toLock={'Gravecall Chorus'},unknownTomes={'Frostwake Sigil'}}}
end
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'granted='..tostring(H.grantedRequests or 0),
  'slots='..tostring(H.slotRequests or 0),'saved='..F.Serialize(NexusDB),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()
C.setup(P.Render(Model())==true and NexusPanel:IsShown(),'fixture: the panel renders')
local root=NexusPanel

-- The client's hide reaches every shown descendant (OnHide), and a show
-- brings their OnShow back; the harness fires only the frame's own script.
local function Propagate(f,script,seen)
 for _,c in ipairs(f.children or {}) do
  if c.shown and not seen[c] then
   seen[c]=true
   local fn=c.scripts and c.scripts[script]
   if fn then fn(c) end
   Propagate(c,script,seen)
  end
 end
end
rawset(root,'Hide',function(self) local was=self.shown;RM.Hide(self);if was then Propagate(self,'OnHide',{}) end end)
rawset(root,'Show',function(self) local was=self.shown;RM.Show(self);if not was then Propagate(self,'OnShow',{}) end end)

local Move={starts=0,stops=0,x=400,y=300}
rawset(root,'StartMoving',function() Move.starts=Move.starts+1 end)
rawset(root,'StopMovingOrSizing',function() Move.stops=Move.stops+1 end)
rawset(root,'GetCenter',function() return Move.x,Move.y end)
rawset(UIParent,'GetCenter',function() return 960,540 end)
local function Saved() local s=P.SavedLayoutRoot();return s.panelX,s.panelY end
local function Reset() Move.starts,Move.stops,Move.x,Move.y=0,0,400,300;local s=P.SavedLayoutRoot();s.panelX,s.panelY=nil,nil end
local function Start(hit) hit:GetScript('OnDragStart')(hit,'LeftButton') end
local function Stop(hit) hit:GetScript('OnDragStop')(hit) end

C.scenario('V1 a render keeps an active move; a real hide or the origin removal ends it once',function()
 local build=root._contextBuildHit
 Reset();Start(build)
 Move.x=430
 C.setup(P._panelDrag~=nil and Move.starts==1,'V1: fixture: a move from the Build line is active')
 P.Render(Model())
 C.expect(P._panelDrag~=nil and Move.stops==0 and Saved()==nil,
  'V1: a render (its hide reaches the Build line) neither ends the move nor saves',Move.stops..' '..tostring(Saved()))
 board.observed=false
 P.Render(Model())
 board.observed=true
 C.expect(P._panelDrag~=nil and Move.stops==0,'V1: a Callboard row disappearing in a render does not end it')
 P.Render(Model())
 Move.y=320
 root:Hide()
 local x,y=Saved()
 C.expect(P._panelDrag==nil and Move.stops==1 and x==-530 and y==-220,'V1: a real hide of the panel ends it and saves once',
  Move.stops..' '..tostring(x)..','..tostring(y))
 root:Show();P.Render(Model())
 local title=root._callboardTitleHit
 Reset()
 C.setup(title:IsShown(),'V1: fixture: the Callboard title is shown')
 Start(title)
 Move.x=410
 board.observed=false
 P.Render(Model())
 board.observed=true
 C.expect(P._panelDrag==nil and Move.stops==1 and Saved()==-550,'V1: a render that removes the origin ends the move and saves once',
  Move.stops..' '..tostring(Saved()))
 P.Render(Model())
 Reset()
 Start(build);Stop(build)
 C.guard(Move.starts==1 and Move.stops==1,'V1: the next move still works')
end)

local function Rect(r) return G.Rect(r,root) end
local function Width(fs) return G.Length(G.Visible(fs:GetText() or ''))*G.model.char end

C.scenario('V2 Charges, recommendation and Details headings fit their text; the destination row takes no input',function()
 for _,model in ipairs({G.MODELS.default,G.MODELS.px16}) do
  G.UseFont(model)
  P.TogglePlanDetails()
  if not P._playDetails then P.TogglePlanDetails() end
  P.Render(Model({recommendation='Take it.'}))
  local tag=' ('..model.name..')'
  local charges,cHit=root._chargesText,root._chargesHover
  if C.setup(charges:IsShown() and cHit:IsShown() and V.Plain(charges:GetText())~='','V2: fixture: the Charges line is shown'..tag) then
   local t,h=Rect(charges),Rect(cHit)
   local w=math.min(t[3]-t[1],Width(charges)+4)
   C.expect(math.abs(h[3]-t[3])<0.01 and math.abs((h[3]-h[1])-w)<0.01 and h[2]==t[2],
    'V2: the Charges hover ends at its right edge and is as wide as its text plus 4'..tag,G.Text(h)..' in '..G.Text(t))
  end
  local rec,rHit=root._rollRec,root._recommendationHover
  if C.setup(rec:IsShown() and rHit:IsShown(),'V2: fixture: the recommendation is shown'..tag) then
   local t,h=Rect(rec),Rect(rHit)
   C.expect(h[1]==t[1] and h[2]==t[2] and h[3]-h[1]<t[3]-t[1] and h[3]-h[1]>=Width(rec)
    and h[4]-h[2]<=t[4]-t[2] and h[4]-h[2]>=model.line,
    'V2: a one-line recommendation hover covers its line, not the whole box'..tag,G.Text(h)..' in '..G.Text(t))
  end
  -- The Details headings (shown with Show details): each hover is fitted
  -- to its heading's text, never wider than the heading.
  for _,hit in ipairs({root._needLabelHit,root._shedLabelHit}) do
   if C.setup(hit and hit:IsShown(),'V2: fixture: a Details heading hover is shown'..tag) then
    local label=#hit.points==1 and hit.points[1][2] or nil
    local ok=label~=nil and type(label)=='table' and label.kind=='FontString'
    if ok then
     local t,h=Rect(label),Rect(hit)
     ok=h[1]==t[1] and h[3]<=t[3] and h[3]-h[1]>=math.min(t[3]-t[1],Width(label))
    end
    C.expect(ok,'V2: a shown Details heading hover is fitted to its heading'..tag)
   end
  end
 end
 G.UseFont(G.MODELS.default)
 local long=string.rep('Take the needed Echo when it is offered. ',8)
 P.Render(Model({recommendation=long}))
 local t,h=Rect(root._rollRec),Rect(root._recommendationHover)
 C.expect(h[1]==t[1] and h[3]==t[3] and h[4]==t[4],'V2: an overflowing recommendation keeps its whole box',G.Text(h)..' in '..G.Text(t))
 local tip=table.concat(V.TooltipLines(root._recommendationHover:GetScript('OnEnter'),root._recommendationHover),' ')
 C.guard(tip:find('Take the needed Echo when it is offered.',1,true)~=nil,'V2: its hover still shows the complete text')
 P.Render(Model({noCharges=true}))
 C.guard(not root._chargesHover:IsShown(),'V2: without a Charges line its hover is hidden')
 local row=root._destinationRow
 C.guard(row and not row:IsVisible(),'V2: the destination row is not shown in this layout, so its hovers take no input')
 if P._playDetails then P.TogglePlanDetails() end
 P.Render(Model())
end)

-- The shared tooltip with an owner (the harness keeps none).
local function WithTip(fn)
 local tip=GameTooltip
 local set,get=rawget(tip,'SetOwner'),rawget(tip,'GetOwner')
 rawset(tip,'SetOwner',function(self,owner) self._owner=owner end)
 rawset(tip,'GetOwner',function(self) return self._owner end)
 local ok,err=pcall(fn,tip)
 rawset(tip,'SetOwner',set);rawset(tip,'GetOwner',get);tip._owner=nil;tip:Hide()
 assert(ok,err)
end

C.scenario('V3 during a move the Callboard title and objective leave no tooltip of theirs open',function()
 P.Render(Model())
 local title,line,build=root._callboardTitleHit,root._callboardLineHit,root._contextBuildHit
 C.setup(title:IsShown() and LM.Shortened(root._callboardTitle),'V3: fixture: the Callboard title is shown shortened')
 WithTip(function(tip)
  tip:Hide();title:GetScript('OnEnter')(title)
  C.guard(tip:IsShown() and tip._owner==title,'V3: without a move the shortened title shows its complete text')
  title:GetScript('OnLeave')(title)
  tip:Hide();line:GetScript('OnEnter')(line)
  C.guard(tip:IsShown() and tip._owner==line,'V3: without a move the objective shows its complete lines')
  line:GetScript('OnLeave')(line)
  Reset();Start(build)
  tip:Hide();title:GetScript('OnEnter')(title)
  C.expect(not (tip:IsShown() and tip._owner==title),'V3: during a move the title leaves no tooltip open')
  tip:Hide();line:GetScript('OnEnter')(line)
  C.expect(not (tip:IsShown() and tip._owner==line),'V3: during a move the objective leaves no tooltip open')
  -- A title that fits opens no tooltip of its own: another frame's stays.
  local long=board.title
  board.title='Ember Watch'
  P.Render(Model())
  local other=CreateFrame('Frame','FixtureForeignTipOwner',UIParent)
  tip:SetOwner(other);tip:Show()
  title:GetScript('OnEnter')(title)
  C.guard(tip:IsShown() and tip._owner==other,'V3: a tooltip another frame owns stays open while hovering the title during a move')
  board.title=long
  Stop(build)
  P.Render(Model())
 end)
end)

C.scenario('V5 FitToScreen refuses infinite sizes and keeps the scale',function()
 local f=CreateFrame('Frame','FixtureInfiniteWindow',UIParent)
 f:SetSize(420,400);f:SetScale(1)
 UIParent:SetSize(1920,824)
 C.guard(LM.FitToScreen(f,nil,1.5)==1.5,'V5: a finite 420x400 window on 1920x824 fits at the 1.5 ceiling')
 f:SetScale(1)
 for _,case in ipairs({{'an infinite frame and screen width',math.huge,400,math.huge,824},
  {'an infinite frame width',math.huge,400,1920,824},{'an infinite screen height',420,400,1920,math.huge},
  {'an infinite frame height',420,math.huge,1920,824}}) do
  f:SetSize(case[2],case[3]);UIParent:SetSize(case[4],case[5]);f:SetScale(1)
  local got=LM.FitToScreen(f,nil,1.5)
  C.expect(got==nil and f:GetScale()==1,'V5: '..case[1]..' is not acted on and keeps the scale',tostring(got)..' '..tostring(f:GetScale()))
 end
 UIParent:SetSize(1920,1080)
end)

-- The frozen pause API as a boundary double.
local D
local function Double()
 D={paused=false,epoch=0,pauses=0,resumes=0}
 Nexus.SessionPause={
  IsPaused=function() return D.paused end,
  Status=function() return {paused=D.paused,epoch=D.epoch,reason=D.paused and 'session_pause' or nil} end,
  Pause=function() D.pauses=D.pauses+1;if not D.paused then D.paused=true;D.epoch=D.epoch+1 end
   return {paused=D.paused,epoch=D.epoch,reason='session_pause'} end,
  Resume=function() D.resumes=D.resumes+1;if D.paused then D.paused=false;D.epoch=D.epoch+1 end
   return {paused=D.paused,epoch=D.epoch} end,
 }
end
local CB={refresh=0,toggle=0}
P.Init({RefreshDisplay=function() CB.refresh=CB.refresh+1;return true end,
 ToggleAuto=function() CB.toggle=CB.toggle+1;return false end})
local function Row(prefix)
 for _,item in ipairs(P.MoreMenuItems(root._menuBtn)) do
  if type(item.text)=='string' and V.Plain(item.text):sub(1,#prefix)==prefix then return item end
 end
end
local function Hover()
 local b=root._autoBtn
 local lines=V.TooltipLines(b:GetScript('OnEnter'),b)
 for i,l in ipairs(lines) do lines[i]=V.Plain(l) end
 return table.concat(lines,'\n')
end
local function Details()
 local row=Row('Auto explained')
 row.func(row)
 local body=V.Plain(NexusHelpWindow.body:GetText())
 Nexus.Help.Hide()
 return body
end

C.scenario('V6 after a confirmed pause an unreadable Status is shown as unknown',function()
 Double()
 P.Render(Model())
 local pause=Row('Pause Nexus for this session')
 pause.func(pause)
 C.setup(D.paused and V.Plain(root._contextTitle:GetText()):find('Nexus paused',1,true)==1,'V6: fixture: Nexus is confirmed paused')
 local before=Effects()
 for _,case in ipairs({{'fails',function() error('status read failed') end},{'is malformed',function() return {paused='?'} end}}) do
  Nexus.SessionPause.Status=case[2]
  P.Render(Model())
  local row=Row('Pause Nexus') or Row('Resume Nexus') or Row('Session pause')
  local text=row and (V.Plain(row.text)..' '..tostring(row.tooltipText)) or ''
  C.expect(row and row.disabled==true and row.func==nil,'V6: when Status '..case[1]..' the control is disabled',text)
  C.expect(text~='' and not text:find('nothing is paused',1,true) and not text:find('not paused',1,true)
   and (text:find('cannot be read',1,true) or text:find('unknown',1,true)),
   'V6: when Status '..case[1]..' it says the pause state cannot be read, not that nothing is paused',text)
  C.expect(not V.Plain(root._contextTitle:GetText()):find('paused',1,true),'V6: the title claims neither paused nor unpaused')
  C.expect(Hover():find('cannot be read',1,true)~=nil,'V6: the Auto hover says the session pause cannot be read',Hover())
 end
 C.guard(Effects()==before and D.resumes==0,'V6: reading an unknown status changes nothing and resumes nothing',Effects())
 Nexus.SessionPause=nil
 P.Render(Model())
end)

C.scenario('V7 a confirmed pause overrides the committed Auto state words; Resume restores them',function()
 Double()
 P.Render(Model({auto=true,effective={state='ready'}}))
 C.setup(Hover():find('Now: ready',1,true)~=nil,'V7: fixture: the committed model says Now: ready')
 local before=Effects()
 local cb={CB.refresh,CB.toggle}
 local pause=Row('Pause Nexus for this session')
 pause.func(pause)
 local hover=Hover()
 C.expect(hover:find('Now: ready',1,true)==nil and hover:find('Now: paused for this session',1,true)~=nil,
  'V7: the hover says the session pause holds Auto, not Now: ready',hover)
 local body=Details()
 C.expect(body:find('Now: ready',1,true)==nil and body:find('Paused because: Nexus is paused for this session',1,true)~=nil
  and body:find('(autoPick): ',1,true)~=nil,'V7: the details give the session pause as the hold and keep every permission',body:sub(-500))
 local resume=Row('Resume Nexus')
 resume.func(resume)
 C.expect(Hover():find('Now: ready',1,true)~=nil,'V7: after Resume the model\'s own state words return')
 C.guard(CB.refresh==cb[1] and CB.toggle==cb[2],'V7: neither Pause nor Resume ran a refresh step or an Auto toggle')
 C.guard(Effects()==before,'V7: no action, send, ownership or slot request, saved change or Auto change',Effects())
 Nexus.SessionPause=nil
 P.Render(Model())
end)

-- V4 last: it loads the addon again (a fresh load) with the saved data.
C.scenario('V4 a centre saved at a fitted size is kept on a fresh load',function()
 UIParent:SetSize(640,1080)
 P.SetPanelScale(1.5)
 P.Render(Model())
 local r=616/420
 C.setup(math.abs(root:GetScale()-r)<0.0005,'V4: fixture: 150% is reduced to fit a 640-wide screen',root:GetScale())
 Reset()
 Start(root._contextBuildHit)
 Move.x,Move.y=300,330
 Stop(root._contextBuildHit)
 local sx,sy=Saved()
 C.setup(sx==math.floor(300*r-960+0.5) and sy==math.floor(330*r-540+0.5),'V4: fixture: the drag saved its centre in UIParent units',
  tostring(sx)..','..tostring(sy))
 local db=NexusDB
 H=F.Boot(db,function(h) F.OrbService(h) end)
 P,LM=Nexus.Panel,Nexus.LayoutMetrics
 RM=G.RegionMethods()
 RM.GetEffectiveScale=function(self)
  local parent=self.parent
  return (self.scale or 1)*(parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1)
 end
 UIParent:SetSize(640,1080)
 local saved=F.Serialize(NexusDB)
 P.Show()
 C.setup(P.Render(Model())==true,'V4: fixture: the panel renders after the fresh load')
 local fresh=NexusPanel
 local s=fresh:GetScale()
 local p,rel,relP,x,y=fresh:GetPoint(1)
 C.expect(math.abs(s-r)<0.0005 and fresh:GetNumPoints()==1 and p=='CENTER' and rel==UIParent and relP=='CENTER'
  and math.abs(x*s-sx)<0.5 and math.abs(y*s-sy)<0.5,
  'V4: after a fresh load the saved centre is the centre at the fitted size',
  tostring(p)..' '..tostring(x and x*s)..','..tostring(y and y*s)..' at '..s)
 C.guard(F.Serialize(NexusDB)==saved,'V4: the fresh load writes no position, size or other saved data')
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(review corrections over the harness with modelled hide propagation, effective scale and tooltip owner; native NOT RUN)')
