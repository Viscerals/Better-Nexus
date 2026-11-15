-- Native QA test.163037 (source 328868e8): after every start-up the main
-- panel's three static labels (the Wishlist caption, the CALLBOARD label and
-- the PROGRESS caption) are shortened by the client, and they are whole only
-- after the first later layout pass (Show details). Nothing but that pass
-- measures them again.
--
-- What native showed (public numbers only):
--   * a text measured in a frame that was hidden and never yet shown reports
--     another width than the same text once that frame has been shown: a new
--     hidden frame's plain text in the owned secondary font read 85.333339,
--     and 88.888889 after the frame's first Show in the same script, and
--     88.888889 from then on, also after hiding that frame again;
--   * the panel is such a frame during its first render: ui/Panel.lua creates
--     it, hides it at once (EnsureFrame) and shows it only after the commit
--     (M.Render, ApplyWantedVisibility), and the three labels' boxes are
--     measured in that first render;
--   * after start-up the released CALLBOARD width was 90.370369 in a box of
--     88, and the Wishlist caption's 63.703709 in a box of 61.
-- What native did NOT show: the widths the three labels reported inside the
-- first render (only their boxes are known), and why the client reports
-- another width for a never-shown frame. Nothing here states either.
--
-- This fixture models only the observed behaviour, as a client rule and not
-- as a product rule: a text whose owning frame chain holds a frame that is
-- hidden and has never been shown reports its own width times one stable
-- ratio; every other text reports its own width. The ratio is the one
-- measured pair above (85.333339 / 88.888889). It is a FIXTURE value for the
-- three labels: their own first widths were never measured, and the probe
-- used a plain text, not the panel's labels. The character width, the font
-- size (16 high native text, font scale 1.6) and the 0.72 UI scale follow
-- the synthetic model of panel_native_font_metrics; they are a model, not
-- native glyph widths.
--
-- The test reaches the real start-up code: a TOC boot, then the first
-- Panel.Render of that boot (EnsureFrame, the first layout pass, the commit
-- and the first Show), with no Show call, no Details click and no second
-- model from the test.
--
-- The model input (fixture correction, v52). In this harness the host makes
-- that first render itself during the boot (core/Main.lua, RenderPreparedPanel:
-- pcall(Panel.Render, prepared), through the Nexus.Panel table), with its
-- own start-up model, which shows no plan progress: the first version of
-- this test therefore never rendered its own model and found no PROGRESS
-- caption. The first render must be of a Wishlist in progress, as it was
-- natively, and it must stay the first render: nothing may be rendered
-- before or after it to prepare the panel. So the test controls the PUBLIC
-- INPUT only: right after ui/Panel.lua loads (format5_support's own per-file
-- hook), Nexus.Panel.Render is wrapped so that every model table the host
-- passes is replaced by this file's one Play model, and the real Render runs
-- with it. Nothing of the panel's output is set, measured or computed by the
-- test, the host's calls, their order and their count are its own, and the
-- same model on every call means no model change follows the first render.
-- The checks below state that every counted render went through that seam
-- and that the panel's first Show came straight after exactly one Render
-- call and one layout pass.
--
-- EXPECT, failing at 328868e8 by design: on the never-shown client, once the
-- panel is shown after its first render and a few frames have passed, each of
-- the three labels has a box at least as wide as the width the client then
-- reports for it.
-- GUARD: on a client whose never-shown width equals the shown one (ratio 1)
-- the same holds today, and that client takes no further layout pass at all
-- after the first Show (v53). On both clients a label's box is never wider
-- than its own measured width allows (no padding), at most one further
-- layout pass follows the first render and none follows while the panel
-- idles, the labels are not measured while it idles, and the frames after
-- the first render send nothing, act on nothing, set no font or scale and
-- change no saved panel choice.
-- Native pixels, glyph widths and frame timing: NOT RUN.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('panel_first_render_label_widths')

----------------------------------------------------------------------------
-- Synthetic client.
----------------------------------------------------------------------------
-- Font model (as panel_native_font_metrics at native 16): the runtime font
-- scale is 1.6, a character of secondary text is 0.55 of its 17.6 height.
local SCALE=1.6
local FONT={name='native 16 (fixture)',char=0.55*11*SCALE,line=math.ceil(11*SCALE*1.15),size=12*SCALE}
local UI_SCALE=0.72
-- The one measured never-shown / shown pair (a plain text in the owned
-- secondary font). A fixture value for the panel's labels, see above.
local NEVER_SHOWN_RATIO=85.333339169044/88.888889132044

-- Installs the font model and the never-shown rule on the harness's region
-- methods, and counts what the checks below read: `client.early` (a text's
-- reads while never shown), `client.reads`, `client.fontSets` and
-- `client.scaleSets` (since the test last cleared them).
local function Install(client)
 G.UseFont(FONT)
 local m=G.RegionMethods()
 local show,own,setScale=m.Show,m.GetStringWidth,m.SetScale
 -- A frame in the owner chain that is hidden and was never shown. A frame
 -- is created shown; only a Show call makes it one that has been shown.
 local function NeverShown(region)
  local owner,guard=rawget(region,'parent'),0
  while type(owner)=='table' and guard<32 do
   if rawget(owner,'shown')==false and not rawget(owner,'_everShown') then return true end
   owner,guard=rawget(owner,'parent'),guard+1
  end
  return false
 end
 client.neverShown=NeverShown
 -- What the client reports for a text now (no count).
 client.report=function(region)
  local width=own(region)
  if NeverShown(region) then return width*client.ratio end
  return width
 end
 m.Show=function(self,...)
  -- The panel's first Show: what had been rendered by then (read only).
  if not rawget(self,'_everShown') and rawget(self,'name')=='NexusPanel' and not client.firstShow
   and type(Nexus)=='table' and type(Nexus.Panel)=='table' then
   local ok,stats=pcall(Nexus.Panel.RenderStats)
   client.firstShow=ok and stats or nil
  end
  rawset(self,'_everShown',true)
  return show(self,...)
 end
 m.GetStringWidth=function(self)
  client.reads[self]=(client.reads[self] or 0)+1
  if NeverShown(self) then client.early[self]=(client.early[self] or 0)+1 end
  return client.report(self)
 end
 m.SetFont=function(self)
  client.fontSets[self]=(client.fontSets[self] or 0)+1
  return true
 end
 m.SetFontObject=function(self)
  client.fontSets[self]=(client.fontSets[self] or 0)+1
 end
 m.SetScale=function(self,value)
  client.scaleSets=client.scaleSets+1
  return setScale(self,value)
 end
 -- A client fault, for the fault scenarios only (`client.fault`; the other
 -- start-ups have none and these two wrappers only pass through). It is a
 -- property of the client's own widget calls, stated without naming any
 -- function of the panel:
 --   * once, after the panel's first Show, the first time the Callboard
 --     label is given a width again while its box is released (width 0),
 --     SetWidth raises and the box stays released;
 --   * with `failPlacement`, from that moment until the test ends the fault,
 --     giving that label a size (SetSize) raises too, so a layout pass that
 --     would place it cannot complete.
 local setWidth,setSize=m.SetWidth,m.SetSize
 m.SetWidth=function(self,value)
  local fault=client.fault
  if fault and fault.injected==0 and type(NexusPanel)=='table' and rawget(NexusPanel,'_everShown')
   and self==NexusPanel._callboardLabel and tonumber(value) and tonumber(value)>0
   and tonumber(rawget(self,'width'))==0 then
   fault.injected=fault.injected+1
   error('client SetWidth fault (fixture)',0)
  end
  if client.widthSets then client.widthSets[self]=(client.widthSets[self] or 0)+1 end
  return setWidth(self,value)
 end
 m.SetSize=function(self,width,height)
  local fault=client.fault
  if fault and fault.failPlacement and fault.injected>0 and type(NexusPanel)=='table'
   and self==NexusPanel._callboardLabel then
   fault.placements=fault.placements+1
   error('client SetSize fault (fixture)',0)
  end
  return setSize(self,width,height)
 end
 rawset(UIParent,'GetEffectiveScale',function() return UI_SCALE end)
end

-- A Callboard objective for the real Callboard owner to observe (the
-- l10n_ui_hud fixture's objective; synthetic).
local function Objective()
 ProjectEbonhold.ObjectivesService={GetActiveObjective=function()
  return {title='Callboard Quest',questId=77,objectiveText='Bring the tome',normalSoulAshes=1200,normalXp=900,
   hc1SoulAshes=2500000,hc1Money=45000,hc2Xp=1500}
 end}
 GetNumQuestLogEntries=function() return 1 end
 GetQuestLogTitle=function(i) if i==1 then return 'Callboard Quest',80,nil,nil,nil,nil,1,nil,77 end end
end

-- The Play model of panel_native_font_metrics (a named Wishlist with targets
-- left, a Saved Build slot, Auto OFF, no offer).
local function Model()
 return {status='ready',level=40,auto=false,cards={},recommendation='',character='SyntheticHero',
  progress={wishlistName='Synthetic Play plan',total=6,owned=1,missing={},shed={},toLock={},unknownTomes={},
   activeSlot=2}}
end

-- The public render input seam (see the header). `seam.renders` counts the
-- model tables given to Panel.Render; each is replaced by Model() and the
-- real Render runs. Installed once per boot, by the first per-file hook that
-- finds Nexus.Panel.Render, which is the one right after ui/Panel.lua.
local function InputSeam(seam)
 return function()
  local P=type(Nexus)=='table' and Nexus.Panel or nil
  if seam.installed or type(P)~='table' or type(P.Render)~='function' then return end
  local render=P.Render
  seam.installed=true
  P.Render=function(input,...)
   if type(input)~='table' then return render(input,...) end
   seam.renders=seam.renders+1
   local index=seam.renders
   local result=render(Model(),...)
   -- (Fault scenarios: what each call that returned answered, and what the
   -- panel was as it returned. A call that raises records nothing.)
   if seam.after then
    local facts,stats=P.VisibilityFacts(),P.RenderStats()
    seam.after[index]={result=result,committed=facts.committed==true,shown=facts.shown==true,layouts=stats.layouts}
   end
   return result
  end
 end
end

-- The three labels and the Build caption, from the panel itself. The
-- PROGRESS caption is the shown text of the panel that holds the heading's
-- own words; failing that, the text its hover area is anchored to (as
-- panel_native_font_metrics finds it), so a hidden caption is reported as
-- hidden, not as absent.
local function Labels()
 local panel=NexusPanel
 if type(panel)~='table' then return {} end
 local words=Nexus.Localization.Text('panel.heading.progress')
 local progress
 for _,region in ipairs(panel.regions or {}) do
  if not progress and region.kind=='FontString' and region:IsShown() and region:GetText()==words then progress=region end
 end
 if not progress then
  local hit=panel._progressLabelHit
  local anchor=type(hit)=='table' and type(hit.points)=='table' and hit.points[1] and hit.points[1][2]
  if type(anchor)=='table' and anchor.kind=='FontString' then progress=anchor end
 end
 return {callboard=panel._callboardLabel,wishlist=panel._contextWishlistCaption,
  build=panel._contextBuildCaption,progress=progress}
end

local function Shown(label)
 return type(label)=='table' and label:IsShown() and (label:GetText() or '')~=''
end
local function Box(label) return tonumber(label:GetWidth()) or 0 end
local function Describe(client,label)
 if type(label)~='table' then return 'no label' end
 return string.format('"%s" box %.2f, the client reports %.2f',tostring(label:GetText()),Box(label),client.report(label))
end
-- The label's box holds the width the client reports for it now.
local function Fits(client,label)
 return Shown(label) and Box(label)+0.01>=client.report(label)
end
local function Count(counts,labels)
 local n=0
 for _,label in pairs(labels) do n=n+(counts[label] or 0) end
 return n
end
-- The panel's own saved choices that a size, position or visibility change
-- would write (ui/Panel.lua: panelScale, panelX, panelY, panelHidden). Read
-- only; an absent key reads nil.
local function Choices(P)
 local root=P.SavedLayoutRoot()
 local parts={}
 for _,key in ipairs({'panelScale','panelX','panelY','panelHidden'}) do
  parts[#parts+1]=key..'='..tostring(type(root)=='table' and root[key])
 end
 return table.concat(parts,' ')
end
local function Boxes(labels)
 local parts={}
 for _,key in ipairs({'callboard','wishlist','build','progress'}) do
  parts[#parts+1]=key..'='..tostring(labels[key] and Box(labels[key]))
 end
 return table.concat(parts,' ')
end

----------------------------------------------------------------------------
-- One start-up on one client.
----------------------------------------------------------------------------
local function Startup(tag,ratio)
 local client={ratio=ratio,reads={},early={},fontSets={},scaleSets=0}
 -- On the lenient client the fit already holds (GUARD); on the never-shown
 -- client it is the reproduced defect (EXPECT).
 local fit=ratio==1 and C.guard or C.expect
 NexusPanel=nil
 -- The input seam goes in right after ui/Panel.lua loads, before any event
 -- or scheduler turn, so the host's own first render already carries the
 -- Play model. The per-file hook table answers every TOC line with the same
 -- installer, which acts once.
 local seam={installed=false,renders=0}
 local installer=InputSeam(seam)
 F.fileHooks=setmetatable({},{__index=function() return installer end})
 local booted,H=pcall(F.Boot,F.Database(),function(h) Install(client);F.OrbService(h);Objective() end)
 F.fileHooks=nil
 if not booted then error(H,0) end
 local P=Nexus.Panel
 C.setup(Nexus.StartupStatus().coreReady==true,tag..': fixture: local start-up is ready')
 Nexus.DisableOrdinaryAutomation()
 H.Fire('QUEST_LOG_UPDATE');H.Advance(.25);H.Advance(1)
 local summary=Nexus.CallboardStatus and Nexus.CallboardStatus.GetSummary and Nexus.CallboardStatus.GetSummary() or nil
 C.setup(type(summary)=='table' and summary.observed==true,tag..': fixture: the Callboard owner reports an observed objective')

 -- The first render is the host's own, made during the boot through the
 -- input seam. Only if no render has run at all does the test make it, once,
 -- through the same public call. (A frame that exists but was never rendered
 -- is still hidden and never shown.)
 local before=P.RenderStats()
 local own=before.calls==0
 local savedChoices=Choices(P)
 local actions,sent=#H.actions,#H.sent
 if own then
  local ok,result=pcall(P.Render,Model())
  C.setup(ok and result==true,tag..': fixture: the first Panel.Render of this start-up commits',tostring(result))
 end
 local first=P.RenderStats()
 local facts=P.VisibilityFacts()
 -- Every render the panel counted was given the Play model by the seam: the
 -- host's own start-up model reached no render.
 C.setup(seam.installed and first.calls>=1 and seam.renders==first.calls,
  tag..': fixture: every Panel.Render call of this start-up went through the public input seam with the one Play model',
  'seam '..tostring(seam.installed)..' model tables '..tostring(seam.renders)..' counted renders '..tostring(first.calls))
 C.setup(first.calls>=1 and first.layouts>=1 and facts.exists and facts.committed and facts.shown and NexusPanel~=nil
   and NexusPanel:IsShown(),
  tag..': fixture: the panel is committed and shown after its first render, with no Show call from the test',
  'calls '..tostring(first.calls)..' layouts '..tostring(first.layouts)..' first render by '..(own and 'this test' or 'the host'))
 -- The first Show came straight after the first render: one Render call and
 -- one layout pass had run, so nothing was rendered again to prepare it.
 local atShow=client.firstShow
 C.setup(type(atShow)=='table' and atShow.calls==1 and atShow.layouts==1,
  tag..': fixture: the panel\'s first Show follows exactly one Panel.Render call and one layout pass',
  type(atShow)=='table' and ('calls '..tostring(atShow.calls)..' layouts '..tostring(atShow.layouts)) or 'no first Show seen')
 if type(NexusPanel)~='table' or type(atShow)~='table' then return end
 local labels=Labels()
 local layout=NexusPanel._responsiveLayout
 C.setup(Shown(labels.callboard) and Shown(labels.wishlist) and Shown(labels.progress),
  tag..': fixture: the CALLBOARD label, the Wishlist caption and the PROGRESS caption are shown with their words',
  Describe(client,labels.callboard)..' | '..Describe(client,labels.wishlist)..' | '..Describe(client,labels.progress))
 if not (Shown(labels.callboard) and Shown(labels.wishlist) and Shown(labels.progress)) then return end
 C.setup(type(layout)=='table' and layout.progressInline==true,
  tag..': fixture: the PROGRESS caption has its own measured width beside the bar')
 -- The fixture reached the first measurement: each label was measured while
 -- the panel was hidden and had never been shown.
 C.setup((client.early[labels.callboard] or 0)>0 and (client.early[labels.wishlist] or 0)>0
   and (client.early[labels.progress] or 0)>0,
  tag..': fixture: each of the three labels was measured in the first render, while the panel had never been shown',
  'callboard '..tostring(client.early[labels.callboard])..' wishlist '..tostring(client.early[labels.wishlist])
   ..' progress '..tostring(client.early[labels.progress]))
 C.setup(not client.neverShown(labels.callboard) and not client.neverShown(labels.wishlist)
   and not client.neverShown(labels.progress),
  tag..': fixture: after the first Show the three labels are no longer in a never-shown frame')

 -- From here on: what happens after the first render.
 client.reads,client.fontSets,client.scaleSets={},{},0
 for _=1,6 do H.Advance(.05,.05) end
 local settled=P.RenderStats()

 -- The three labels, with no Details click and no other model.
 fit(Fits(client,labels.callboard),
  tag..': after the first Show the CALLBOARD label\'s box holds the width the client reports for it',
  Describe(client,labels.callboard))
 local captions=Fits(client,labels.wishlist) and (not Shown(labels.build) or Fits(client,labels.build))
 fit(captions,
  tag..': after the first Show the Wishlist caption (and the Build caption beside it) is as wide as the client reports',
  Describe(client,labels.wishlist)..' | '..Describe(client,labels.build))
 fit(Fits(client,labels.progress),
  tag..': after the first Show the PROGRESS caption\'s box holds the width the client reports for it',
  Describe(client,labels.progress))

 -- No padding: a box is its text's own measured width, rounded up, with the
 -- one unit the Callboard label always had; the captions share the wider
 -- caption's column.
 local widest=client.report(labels.wishlist)
 if Shown(labels.build) then widest=math.max(widest,client.report(labels.build)) end
 C.guard(Box(labels.callboard)<=math.ceil(client.report(labels.callboard))+1.01
   and Box(labels.wishlist)<=math.ceil(widest)+0.01
   and Box(labels.progress)<=math.ceil(client.report(labels.progress))+0.01,
  tag..': no label\'s box is wider than its own measured words need (no added room)',
  Describe(client,labels.callboard)..' | '..Describe(client,labels.wishlist)..' | '..Describe(client,labels.progress))

 -- Bounded work: at most one further layout pass, then none while idle, and
 -- no label is measured while the panel idles.
 C.guard(settled.layouts<=atShow.layouts+1,
  tag..': at most one layout pass follows the first render',
  tostring(atShow.layouts)..' -> '..tostring(settled.layouts))
 -- (v53) A client whose never-shown width is already the shown one gives no
 -- reason for another pass: there the first layout pass is the only one.
 if ratio==1 then
  C.guard(settled.layouts==atShow.layouts,
   tag..': a client whose first widths already stand takes no further layout pass after the first Show',
   tostring(atShow.layouts)..' -> '..tostring(settled.layouts))
 end
 local settledReads,settledBoxes=Count(client.reads,labels),Boxes(labels)
 H.Advance(10,.05)
 local idle=P.RenderStats()
 C.guard(idle.layouts==settled.layouts and Count(client.reads,labels)==settledReads and Boxes(labels)==settledBoxes,
  tag..': while the panel idles for 200 frames no layout pass runs, no label is measured and no box moves',
  'layouts '..tostring(settled.layouts)..' -> '..tostring(idle.layouts)..'; reads '..tostring(settledReads)..' -> '
   ..tostring(Count(client.reads,labels))..'; '..settledBoxes..' -> '..Boxes(labels))

 -- Nothing else changed: no Details, no resource action, no font, no scale,
 -- no saved panel choice.
 C.guard(P._playDetails~=true and #H.actions==actions and #H.sent==sent,
  tag..': Details stays closed and nothing is sent or acted on',
  'details '..tostring(P._playDetails)..' actions '..tostring(#H.actions-actions)..' sent '..tostring(#H.sent-sent))
 C.guard(Count(client.fontSets,labels)==0 and client.scaleSets==0 and NexusPanel:GetScale()==1
   and (UIParent:GetScale() or 1)==1,
  tag..': after the first render no label is given a font and no scale is set',
  'font sets '..tostring(Count(client.fontSets,labels))..' scale sets '..tostring(client.scaleSets)
   ..' panel scale '..tostring(NexusPanel:GetScale()))
 C.guard(Choices(P)==savedChoices,tag..': no saved panel size, position or visibility choice changed',
  savedChoices..' -> '..Choices(P))
end

----------------------------------------------------------------------------
-- A client fault at the first Show (v54).
-- The panel reads its first-pass widths again right after its first Show,
-- which means releasing and restoring a text's box on a panel that is
-- already committed and shown. A client call that fails there must not
-- leave a text changed under that commit. The acceptable ends are two: the
-- panel is laid out again through its ordinary transaction and is whole, or
-- its commit is withdrawn (hidden, uncommitted, the render answering false)
-- and an ordinary refresh brings it back.
-- The fault is the client's (Install: client.fault), on the lenient client,
-- where every reading agrees and the read reaches every text, so without the
-- fault nothing at all follows the first Show.
--   `transient`: one SetWidth failure. A layout pass can run.
--   `failing placement`: the same, and the Callboard label cannot be placed
--   until the test ends the fault, so that layout pass cannot complete.
-- EXPECT, failing at the first repair (v53) by design: there the failure was
-- passed over and the label stayed shown under a commit with its box
-- released, also after an ordinary refresh.
----------------------------------------------------------------------------
local function Whole(client,labels)
 return Fits(client,labels.callboard) and Fits(client,labels.wishlist)
  and (not Shown(labels.build) or Fits(client,labels.build)) and Fits(client,labels.progress)
end

local function FaultStartup(tag,failPlacement)
 local client={ratio=1,reads={},early={},fontSets={},scaleSets=0,widthSets={},
  fault={injected=0,placements=0,failPlacement=failPlacement and true or false}}
 NexusPanel=nil
 local seam={installed=false,renders=0,after={}}
 local installer=InputSeam(seam)
 F.fileHooks=setmetatable({},{__index=function() return installer end})
 local booted,H=pcall(F.Boot,F.Database(),function(h) Install(client);F.OrbService(h);Objective() end)
 F.fileHooks=nil
 if not booted then error(H,0) end
 local P=Nexus.Panel
 C.setup(Nexus.StartupStatus().coreReady==true,tag..': fixture: local start-up is ready')
 Nexus.DisableOrdinaryAutomation()
 H.Fire('QUEST_LOG_UPDATE');H.Advance(.25);H.Advance(1)
 local savedChoices=Choices(P)
 local actions,sent=#H.actions,#H.sent
 local atShow,firstCall=client.firstShow,seam.after[1]
 C.setup(seam.installed and type(atShow)=='table' and atShow.calls==1 and atShow.layouts==1 and type(firstCall)=='table',
  tag..': fixture: the host\'s first render went through the input seam and returned, and the first Show followed one render and one layout pass',
  type(atShow)=='table' and ('calls '..tostring(atShow.calls)..' layouts '..tostring(atShow.layouts)..' first call returned '
   ..tostring(type(firstCall)=='table')) or 'no first Show seen')
 C.setup(client.fault.injected==1,
  tag..': fixture: the client raised exactly once, on the Callboard label\'s first width after its box was released at the first Show',
  'raised '..tostring(client.fault.injected))
 if type(NexusPanel)~='table' or type(atShow)~='table' or type(firstCall)~='table' then return end
 local labels=Labels()
 C.setup(type(labels.callboard)=='table' and type(labels.wishlist)=='table' and type(labels.progress)=='table',
  tag..': fixture: the CALLBOARD label, the Wishlist caption and the PROGRESS caption exist')
 if not (type(labels.callboard)=='table' and type(labels.wishlist)=='table' and type(labels.progress)=='table') then return end

 -- The end state: never a released box shown under a commit.
 local facts=P.VisibilityFacts()
 local standing=facts.committed==true and facts.shown==true
 local withdrawn=facts.committed~=true and facts.shown~=true
 C.expect((standing and Whole(client,labels)) or withdrawn,
  tag..': a client fault at the first Show leaves the panel either committed, shown and whole, or hidden and uncommitted',
  'committed '..tostring(facts.committed)..' shown '..tostring(facts.shown)..' | '..Describe(client,labels.callboard))
 -- Truthful answers: a render that returned said true exactly when the
 -- panel was committed as it returned.
 local truthful,answers=true,{}
 for index=1,seam.renders do
  local record=seam.after[index]
  if record then
   if (record.result==true)~=(record.committed==true) then truthful=false end
   answers[#answers+1]=index..':'..tostring(record.result)..'/'..tostring(record.committed)
  else
   answers[#answers+1]=index..':raised'
  end
 end
 C.guard(truthful,tag..': every Panel.Render call that returned answered true exactly when the panel was committed as it returned',
  table.concat(answers,' '))
 -- Bounded: the first render ends with at most one layout pass more than
 -- the one before the first Show, fault or not.
 C.guard(firstCall.layouts<=atShow.layouts+1,
  tag..': the first render takes at most one further layout pass for the fault',
  tostring(atShow.layouts)..' -> '..tostring(firstCall.layouts))

 -- Recovery through an ordinary refresh, once the client's fault is over.
 client.fontSets,client.scaleSets={},0
 if failPlacement then
  client.fault.failPlacement=false
  pcall(P.Refresh)
  if P.VisibilityFacts().committed~=true and type(Nexus.RefreshHudView)=='function' then pcall(Nexus.RefreshHudView) end
  for _=1,6 do H.Advance(.05,.05) end
  local now=P.VisibilityFacts()
  C.expect(now.committed==true and now.shown==true and Whole(client,labels),
   tag..': once the client fault is over an ordinary refresh shows the panel committed and whole',
   'committed '..tostring(now.committed)..' shown '..tostring(now.shown)..' | '..Describe(client,labels.callboard)
    ..' | '..Describe(client,labels.wishlist)..' | '..Describe(client,labels.progress))
 end

 -- No added room, whatever the end state.
 local widest=client.report(labels.wishlist)
 if Shown(labels.build) then widest=math.max(widest,client.report(labels.build)) end
 C.guard(Box(labels.callboard)<=math.ceil(client.report(labels.callboard))+1.01
   and Box(labels.wishlist)<=math.ceil(widest)+0.01
   and Box(labels.progress)<=math.ceil(client.report(labels.progress))+0.01,
  tag..': no label\'s box is wider than its own measured words need (no added room)',
  Describe(client,labels.callboard)..' | '..Describe(client,labels.wishlist)..' | '..Describe(client,labels.progress))

 -- Nothing is retried while the panel idles: no layout pass, no reading, no
 -- width set on a label, no further fault, no box moving.
 client.reads,client.widthSets={},{}
 local before,raised,placements,boxes=P.RenderStats(),client.fault.injected,client.fault.placements,Boxes(labels)
 H.Advance(10,.05)
 local idle=P.RenderStats()
 C.guard(idle.layouts==before.layouts and Count(client.reads,labels)==0 and Count(client.widthSets,labels)==0
   and client.fault.injected==raised and client.fault.placements==placements and Boxes(labels)==boxes,
  tag..': while the panel idles for 200 frames nothing is retried: no layout pass, no label read or sized, no box moves',
  'layouts '..tostring(before.layouts)..' -> '..tostring(idle.layouts)..'; reads '..tostring(Count(client.reads,labels))
   ..'; width sets '..tostring(Count(client.widthSets,labels))..'; raised '..tostring(raised)..' -> '
   ..tostring(client.fault.injected)..'; '..boxes..' -> '..Boxes(labels))
 C.guard(P._playDetails~=true and #H.actions==actions and #H.sent==sent,
  tag..': Details stays closed and nothing is sent or acted on',
  'details '..tostring(P._playDetails)..' actions '..tostring(#H.actions-actions)..' sent '..tostring(#H.sent-sent))
 C.guard(Count(client.fontSets,labels)==0 and client.scaleSets==0 and NexusPanel:GetScale()==1
   and (UIParent:GetScale() or 1)==1 and Choices(P)==savedChoices,
  tag..': no label is given a font, no scale is set and no saved panel choice changes',
  'font sets '..tostring(Count(client.fontSets,labels))..' scale sets '..tostring(client.scaleSets)
   ..' panel scale '..tostring(NexusPanel:GetScale())..' | '..savedChoices..' -> '..Choices(P))
end

C.scenario('lenient client',function() Startup('lenient client',1) end)
C.scenario('never-shown client',function() Startup('never-shown client',NEVER_SHOWN_RATIO) end)
C.scenario('transient width fault',function() FaultStartup('transient width fault',false) end)
C.scenario('width fault with a failing placement',function() FaultStartup('width fault with a failing placement',true) end)

C.finish('native NOT_RUN')
