-- Issue #169: a short Auto hover (current state, next action, essential
-- consequence) with the complete permission and safety explanation one
-- deliberate click away (Options > Auto explained, the Help Auto page with
-- the current values), and an optional passive Questions (FAQ) page.
-- A1 Auto OFF: the hover is short, says OFF / what to click / what ON may
--    do, and names the details route; the permission list is not in it;
-- A2 Auto selected ON: says selected ON and how to turn it OFF, never that
--    it is acting; the effective state line (Now:) stays;
-- A3 a held Auto says why, in the runtime's plain hold words;
-- A4 a refused click says the last click left Auto OFF and why;
-- A5 a confirmed session pause says Nexus is paused and how to resume;
-- A6 Options > Auto explained opens the Help Auto page with every existing
--    disclosure and each permission's current value and the hold reason;
-- A7 Options > Questions (FAQ) opens a FAQ page with short answers; its tab
--    fits the window;
-- A8 hovering and opening, moving through and closing Help, FAQ and details
--    change no setting, consent, tutorial state, assignment, action or send.
-- Categories (view_regression_support): EXPECT fails at e1183fd (long
-- hover, no details route, no FAQ), GUARD already held, SETUP is the
-- fixture. Native tooltip drawing NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('crimson_panel_auto_help')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P=Nexus.Panel
local function Model(o)
 o=o or {}
 return {status='ready',level=40,auto=o.auto==nil and false or o.auto,paused=o.paused,effective=o.effective,
  cards={},recommendation='',
  progress={wishlistName=o.wishlist or 'Auto plan',total=6,owned=2,missing={'Hollow Bell'},shed={},toLock={},unknownTomes={}}}
end
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'saved='..F.Serialize(NexusDB),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
local function Hover()
 local b=NexusPanel._autoBtn
 local lines=V.TooltipLines(b:GetScript('OnEnter'),b)
 for i,l in ipairs(lines) do lines[i]=V.Plain(l) end
 return lines,table.concat(lines,'\n')
end
local function Item(text)
 for _,item in ipairs(P.MoreMenuItems(NexusPanel._menuBtn)) do
  if type(item.text)=='string' and V.Plain(item.text)==text then return item end
 end
end
local function Short(lines,text,tag)
 C.expect(#lines<=6 and #text<=420,tag..': the hover is short (at most 6 lines, 420 characters)',#lines..' / '..#text)
 C.expect(text:find('(autoPick)',1,true)==nil and text:find('(autoBanish)',1,true)==nil,
  tag..': the permission list is not in the first hover',text)
 C.expect(text:find('Options > Auto explained',1,true)~=nil,tag..': it names the details route',text)
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()
local start=Effects()

C.scenario('A1 Auto OFF: short state, next action and consequence',function()
 P.Render(Model({auto=false}))
 local lines,text=Hover()
 Short(lines,text,'A1')
 C.expect(text:find('Auto is OFF',1,true)~=nil and text:find('you choose',1,true)~=nil,'A1: it says Auto is OFF and you choose',text)
 C.expect(text:find('Click Auto to turn it ON',1,true)~=nil,'A1: it says what to click',text)
 C.expect(text:find('spend charges',1,true)~=nil and text:find('Saved Build',1,true)~=nil,'A1: it says what ON may do',text)
end)

C.scenario('A2 Auto selected ON: selected, how to turn it OFF; never acting; Now line kept',function()
 P.Render(Model({auto=true,effective={state='ready'}}))
 local lines,text=Hover()
 Short(lines,text,'A2')
 C.expect(text:find('Auto is selected ON',1,true)~=nil and text:find('Click Auto to turn it OFF',1,true)~=nil,'A2: selected ON and how to turn it OFF',text)
 C.expect(text:find('running',1,true)==nil and text:find('Active',1,true)==nil,'A2: it never claims Auto is running',text)
 C.guard(text:find('Now: ready',1,true)~=nil,'A2: the effective state line stays',text)
end)

C.scenario('A3 a held Auto says why in plain words',function()
 P.Render(Model({auto=true,paused='user acting',effective={state='paused',hold=true,reason='user acting'}}))
 local lines,text=Hover()
 Short(lines,text,'A3')
 local plain=V.Plain(Nexus.Readout.AutoHoldText('user acting'))
 C.expect(text:find('Auto is selected ON but held',1,true)~=nil and text:find(plain,1,true)~=nil,'A3: held, with the plain hold words',text)
end)

C.scenario('A4 a refused click says the last click left Auto OFF',function()
 P.Render(Model({auto=false}))
 P.NoteAutoClick(false,true,false)
 local lines,text=Hover()
 Short(lines,text,'A4')
 C.expect(text:find('Your last click left Auto OFF',1,true)~=nil,'A4: the refusal is said',text)
 P.NoteAutoClick(true,true,true)
end)

C.scenario('A5 a confirmed session pause says Nexus is paused and how to resume',function()
 Nexus.SessionPause={IsPaused=function() return true end,Status=function() return {paused=true,epoch=1,reason='session_pause'} end,
  Pause=function() error('not called') end,Resume=function() error('not called') end}
 P.Render(Model({auto=true}))
 local lines,text=Hover()
 Short(lines,text,'A5')
 C.expect(text:find('Nexus is paused for this session',1,true)~=nil and text:find('Resume Nexus',1,true)~=nil,'A5: paused, and Resume Nexus',text)
 Nexus.SessionPause=nil
 P.Render(Model({auto=false}))
end)

C.scenario('A6 Options > Auto explained opens every disclosure with the current values',function()
 P.Render(Model({auto=true,paused='user acting',effective={state='paused',hold=true,reason='user acting'}}))
 local row=Item('Auto explained (full details)')
 if not C.expect(row~=nil and type(row.func)=='function','A6: Options offers Auto explained (full details)') then return end
 row.func(row)
 local f=NexusHelpWindow
 C.expect(f and f:IsShown() and V.Plain(f.title:GetText()):find('Auto',1,true)~=nil,'A6: it opens the Help Auto page',f and f.title:GetText())
 local body=V.Plain(f.body:GetText())
 for _,want in ipairs({'Automation and enabled actions','consume charges or change saved-build state',
  'Locked-Echo slot','management is a separate opt-in','Orb runs require separate approval',
  'OFF keeps recommendations visible; it does not turn off Sync','Later improvement is not guaranteed',
  '(autoPick): ','(autoBanish): ','(autoReroll): ','(autoFreeze): ','(autoDisable): ','re-enables Wishlist controls',
  '(autoSave): ','(autoLockEchoes): ','Activate a Saved Build: never','Orb runs: never by Auto',
  'Paused because: '..V.Plain(Nexus.Readout.AutoHoldText('user acting')),'Now: paused'}) do
  C.expect(body:find(want,1,true)~=nil,'A6: the details include: '..want)
 end
 local page=Nexus.Help.Pages
 local rolling
 for _,p in ipairs(page) do if p.id=='rolling' then rolling=p end end
 C.guard(rolling and body:find(V.Plain(rolling.text),1,true)==1,'A6: the complete Auto reference stays, first')
 Nexus.Help.Hide()
end)

C.scenario('A7 Options > Questions (FAQ) opens short answers; its tab fits',function()
 local row=Item('Questions (FAQ)')
 if not C.expect(row~=nil and type(row.func)=='function','A7: Options offers Questions (FAQ)') then return end
 row.func(row)
 local f=NexusHelpWindow
 local body=V.Plain(f.body:GetText())
 C.expect(f:IsShown() and V.Plain(f.title:GetText()):find('Questions',1,true)~=nil,'A7: it opens the FAQ page',f.title:GetText())
 for _,want in ipairs({'What do I do next?','assigned Wishlist','example','Auto','Sync','Pause Nexus for this session',
  'Hide Nexus Panel','get back','memory','Main panel size'}) do
  C.expect(body:find(want,1,true)~=nil,'A7: the FAQ answers: '..want)
 end
 local last=f.tabs[#f.tabs]
 local r=G.Rect(last,f)
 C.expect(V.Plain(last:GetText())=='FAQ' and r[3]<=f:GetWidth()-20,'A7: the FAQ tab is inside the window',G.Text(r))
 Nexus.Help.Hide()
end)

C.scenario('A8 hovering and Help, FAQ and details change nothing',function()
 Hover()
 Nexus.Help.Show('faq');Nexus.Help.Show('rolling');Nexus.Help.Show('start');Nexus.Help.Hide()
 C.guard(Effects()==start,'A8: no setting, consent, tutorial state, assignment, action, send or Auto changed',Effects())
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(Auto hover summary, details route and FAQ over the harness; native tooltip drawing NOT RUN)')
