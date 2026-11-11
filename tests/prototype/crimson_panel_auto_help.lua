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
-- Random Roll (settings.autoPickLeveling) needs the master Auto with no
-- Wishlist assigned, so "Click Auto" must have a button to click there:
-- A9  no Wishlist, the option exactly on, levels 2-79: the real Auto button
--     is shown instead of a plain label, and its click is what turns Auto ON
--     and OFF; turning the option on turns nothing on;
-- A10 no Wishlist without the exact option (false, absent, a string, a
--     number): no button, as before;
-- A11 an Auto already ON without a Wishlist keeps the button at levels 1 and
--     80 and after the option is turned OFF, so it can be turned OFF;
-- A12 a view with a Wishlist does not depend on the option;
-- A13 a named Wishlist with no target is still a Wishlist: no button and the
--     plain label for every option value, Auto value and level, as before.
-- With no Wishlist the Play header's Wishlist line says "Random rolling" while
-- Random Roll is what picks, and "None assigned" otherwise:
-- A14 the runtime's own display fact (model.randomRoll, exactly true) with a
--     selected Auto, a known unassigned destination, the option and levels
--     2-79: "Wishlist: Random rolling"; the hover gives that line whole and
--     keeps "Wishlist: None assigned" below it;
-- A15 the option, a selected Auto, a recommendation or a missing Wishlist
--     name without that fact, and that fact without each of them: "None
--     assigned";
-- A16 a pause, a hold, an Orb hold, a session pause and levels 1 and 80:
--     never "Random rolling", whatever the model's fact says;
-- A17 an assignment that is loading, restoring, unavailable or not stated
--     keeps its own words;
-- A18 a named Wishlist, a named Wishlist with no target and an empty Saved
--     Build keep their own words;
-- A19 a change either way is shown by the next render without a layout
--     pass, an unchanged line is not set again, Auto turned OFF ends the
--     words at once, and the words fit the line at every font model.
-- Categories (view_regression_support): EXPECT fails at e1183fd (long
-- hover, no details route, no FAQ; A9 and A11 at 18f2ecaf: the no-Wishlist
-- view had no Auto button; A14 and A19 before the Wishlist line had the
-- words), GUARD already held, SETUP is the
-- fixture. Native tooltip drawing NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('crimson_panel_auto_help')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P=Nexus.Panel
local function Model(o)
 o=o or {}
 local progress={wishlistName=o.wishlist or 'Auto plan',total=6,owned=2,missing={'Hollow Bell'},shed={},toLock={},unknownTomes={}}
 -- No Wishlist assigned: no name and no target (the panel's setup view).
 if o.noWishlist then progress={total=0,owned=0,missing={},shed={},toLock={},unknownTomes={}} end
 -- A named Wishlist with no target: an assigned Wishlist, not "no Wishlist".
 if o.emptyWishlist then progress={wishlistName=o.wishlist or 'Auto plan',total=0,owned=0,missing={},shed={},toLock={},unknownTomes={}} end
 -- assignment and randomRoll: as Main and the runtime give them (absent unless a scenario states them).
 return {status='ready',level=o.level or 40,auto=o.auto==nil and false or o.auto,paused=o.paused,effective=o.effective,
  cards={},recommendation='',progress=progress,assignment=o.assignment,randomRoll=o.randomRoll}
end
local function Effects()
 -- Outbound ownership and slot refreshes are counted apart from H.sent.
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'granted='..tostring(H.grantedRequests or 0),
  'slots='..tostring(H.slotRequests or 0),'saved='..F.Serialize(NexusDB),
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

-- Random Roll: the real button (NexusPanel._autoBtn) and its real click, in
-- the view without a Wishlist. The option is read where the game reads it
-- (Nexus.Store.Settings); only /nexus leveling and the click change anything.
local actions=#H.actions
local function AutoOn() return Nexus.RecomputeStats().autoEnabled==true end
local function Button() return NexusPanel._autoBtn:IsShown() and true or false end
local function Label() local l=NexusPanel._contextAutoState;return l~=nil and l:IsShown() and true or false end
local function Bare(level,auto) P.Render(Model({noWishlist=true,level=level,auto=auto}));return Button(),Label() end
local function Click() if Button() then NexusPanel._autoBtn:Click() end end

C.scenario('A9 no Wishlist with Random Roll on: the real Auto button is the control',function()
 SlashCmdList.NEXUS('leveling on')
 C.setup(Nexus.Store.Settings().autoPickLeveling==true,'A9: fixture: /nexus leveling on set the option')
 C.guard(not AutoOn() and #H.actions==actions,'A9: turning the option on leaves Auto OFF and performs nothing')
 for _,level in ipairs({2,40,79}) do
  local button,label=Bare(level,false)
  C.expect(button,'A9: level '..level..': the Auto button is shown without a Wishlist')
  C.expect(not label,'A9: level '..level..': no plain Auto label stands in for the button')
 end
 C.guard(not AutoOn() and #H.actions==actions,'A9: showing the button turns nothing on')
 Bare(40,false);Click()
 local on=AutoOn()
 C.expect(on,'A9: one explicit click on the shown button turns Auto ON')
 Bare(40,on);Click()
 C.expect(on and not AutoOn(),'A9: a second click on the button turns Auto OFF')
 C.guard(#H.actions==actions,'A9: no Echo action was performed')
end)

C.scenario('A10 no Wishlist without the exact option: no Auto button, as before',function()
 for _,case in ipairs({{false,'false'},{nil,'absent'},{'on','the string on'},{1,'the number 1'}}) do
  Nexus.Store.Settings().autoPickLeveling=case[1]
  C.setup(Nexus.Store.Settings().autoPickLeveling==case[1],'A10: fixture: the option is '..case[2])
  local button,label=Bare(40,false)
  C.guard(not button and label,'A10: option '..case[2]..': no button and the plain label, as before')
 end
 SlashCmdList.NEXUS('leveling off')
 C.guard(not AutoOn() and #H.actions==actions,'A10: Auto stayed OFF and nothing was performed')
end)

C.scenario('A11 an Auto already ON without a Wishlist keeps its OFF control',function()
 SlashCmdList.NEXUS('leveling on')
 for _,level in ipairs({1,80}) do
  C.guard(not (Bare(level,false)),'A11: Auto OFF at level '..level..': no button (Random Roll does not pick there)')
  C.expect((Bare(level,true)),'A11: Auto ON at level '..level..': the button stays, to turn Auto OFF')
 end
 Bare(40,false);Click()
 SlashCmdList.NEXUS('leveling off')
 C.setup(Nexus.Store.Settings().autoPickLeveling==false,'A11: fixture: the option is OFF again')
 local on=AutoOn()
 C.expect(on and (Bare(40,on)),'A11: Auto ON after the option is turned OFF: the button stays')
 Click()
 C.expect(on and not AutoOn(),'A11: its click turns Auto OFF')
 C.guard(not (Bare(40,false)),'A11: Auto OFF and the option OFF: no button again')
 C.guard(#H.actions==actions,'A11: no Echo action was performed')
end)

C.scenario('A12 a view with a Wishlist does not depend on the option',function()
 local function Views()
  local parts={}
  for _,level in ipairs({40,80}) do
   for _,auto in ipairs({false,true}) do
    P.Render(Model({level=level,auto=auto}))
    parts[#parts+1]=level..':'..tostring(auto)..'='..tostring(Button())..'/'..tostring(Label())
   end
  end
  return table.concat(parts,' ')
 end
 local off=Views()
 SlashCmdList.NEXUS('leveling on')
 local on=Views()
 SlashCmdList.NEXUS('leveling off')
 C.guard(on==off,'A12: the same Auto button and label with the option on and off',off..' | '..on)
 C.guard(off:find('40:false=true/false',1,true)~=nil,'A12: level 40 with a Wishlist and Auto OFF shows the button',off)
 P.Render(Model({auto=false}))
 C.guard(not AutoOn() and #H.actions==actions,'A12: Auto is OFF and nothing was performed')
end)

C.scenario('A13 a named Wishlist with no target keeps its view for every option and Auto value',function()
 local function Views()
  local parts={}
  for _,level in ipairs({1,40,80}) do
   for _,auto in ipairs({false,true}) do
    P.Render(Model({emptyWishlist=true,level=level,auto=auto}))
    parts[#parts+1]=level..':'..tostring(auto)..'='..tostring(Button())..'/'..tostring(Label())
   end
  end
  return table.concat(parts,' ')
 end
 -- button/label: no button and the plain label, in every case.
 local before='1:false=false/true 1:true=false/true 40:false=false/true 40:true=false/true 80:false=false/true 80:true=false/true'
 SlashCmdList.NEXUS('leveling on')
 C.setup(Nexus.Store.Settings().autoPickLeveling==true,'A13: fixture: the option is on')
 local on=Views()
 SlashCmdList.NEXUS('leveling off')
 C.setup(Nexus.Store.Settings().autoPickLeveling==false,'A13: fixture: the option is off')
 local off=Views()
 C.guard(on==before,'A13: option on: no button and the plain label at levels 1, 40 and 80, Auto OFF and ON',on)
 C.guard(off==before,'A13: option off: no button and the plain label at levels 1, 40 and 80, Auto OFF and ON',off)
 C.guard(on==off,'A13: the same view with the option on and off',on..' | '..off)
 P.Render(Model({auto=false}))
 C.guard(not AutoOn() and #H.actions==actions,'A13: Auto is OFF and nothing was performed')
end)

-- The Play header's Wishlist line (NexusPanel._contextWishlist) and its hover,
-- in the view without a Wishlist. Rolling(): the model the runtime gives while
-- Random Roll picks (its display fact, a selected Auto, a known unassigned
-- destination, level 40), with one scenario's changes; ABSENT removes a field.
-- The running words are "Auto-pick by rarity (ON)" since the mode is offered
-- as the alternative to a Wishlist (rarity_auto_pick_mode): honest rarity
-- wording in place of "Wishlist: Random rolling", and the whole line, so it
-- still fits at every font model. These synthetic models carry no
-- positive unassigned fact, so every state but running stays None assigned.
local ACTIVE,NONE='Auto-pick by rarity (ON)','Wishlist: None assigned'
local ABSENT={}
local function Line() return V.Plain(NexusPanel._contextWishlist:GetText()) end
local function LineHover() return V.Plain(NexusPanel._contextWishlistHit._nexusFull) end
local function Rolling(o)
 local m={noWishlist=true,level=40,auto=true,assignment={state='unassigned'},randomRoll=true}
 for k,v in pairs(o or {}) do if v==ABSENT then m[k]=nil else m[k]=v end end
 return Model(m)
end
local function Shows(o) P.Render(Rolling(o));return Line() end
local function Option(value)
 Nexus.Store.Settings().autoPickLeveling=value
 return Nexus.Store.Settings().autoPickLeveling==value
end

C.scenario('A14 no Wishlist while Random Roll picks: the Wishlist line says Random rolling',function()
 SlashCmdList.NEXUS('leveling on')
 C.setup(Nexus.Store.Settings().autoPickLeveling==true,'A14: fixture: /nexus leveling on set the option')
 for _,level in ipairs({2,40,79}) do
  C.expect(Shows({level=level})==ACTIVE,'A14: level '..level..': the line says Random rolling',Line())
 end
 local hover=LineHover()
 C.expect(hover:sub(1,#ACTIVE+1)==ACTIVE..'\n' and hover:sub(-#NONE-1)=='\n'..NONE and hover:find('Running: Auto is ON',1,true)~=nil
  and hover:find('highest-rarity',1,true)~=nil,'A14: the hover gives the line whole, why it runs and the rule, then the fact: no Wishlist is assigned',hover)
 Shows({randomRoll=ABSENT})
 C.guard(LineHover()==NONE,'A14: without Random rolling the hover is the fact alone, as before',LineHover())
 Shows()
 C.guard(Button() and not Label(),'A14: the Auto button is still the control')
 C.guard(not AutoOn() and #H.actions==actions,'A14: showing the words turns nothing on and performs nothing')
end)

C.scenario('A15 no single fact is enough: None assigned without the runtime fact or without any of the others',function()
 C.setup(Option(true),'A15: fixture: the option is on')
 C.guard(Shows({randomRoll=ABSENT})==NONE,'A15: the option, a selected Auto and no Wishlist without the runtime fact',Line())
 for _,case in ipairs({{false,'false'},{'true','the string true'},{1,'the number 1'}}) do
  C.guard(Shows({randomRoll=case[1]})==NONE,'A15: a runtime fact that is '..case[2]..' is not the fact',Line())
 end
 C.guard(Shows({auto=false})==NONE,'A15: Auto OFF (a recommendation only), with the runtime fact',Line())
 local unstated=Rolling()
 unstated.auto=nil
 P.Render(unstated)
 C.guard(Line()==NONE,'A15: an Auto selection that is not stated, with the runtime fact',Line())
 for _,case in ipairs({{false,'false'},{ABSENT,'absent'},{'on','the string on'},{1,'the number 1'}}) do
  C.setup(Option(case[1]~=ABSENT and case[1] or nil),'A15: fixture: the option is '..case[2])
  C.guard(Shows()==NONE,'A15: option '..case[2]..', with the runtime fact',Line())
 end
 C.setup(Option(true),'A15: fixture: the option is on again')
 C.expect(Shows()==ACTIVE,'A15: with every fact again the line says Random rolling',Line())
 C.guard(not AutoOn() and #H.actions==actions,'A15: Auto stayed OFF and nothing was performed')
end)

C.scenario('A16 a pause, a hold, an Orb hold, a session pause and the level limits never say Random rolling',function()
 C.setup(Option(true),'A16: fixture: the option is on')
 local orb='Orb state active or unknown'
 for _,case in ipairs({
  {'a pause the model names',{paused='user acting',effective={state='paused',hold=true,reason='user acting'}}},
  {'pause words alone',{paused='user acting'}},
  {'an Orb hold',{paused=orb,effective={state='paused',hold=true,reason=orb}}},
  {'a wait for a sent action that became a hold',{paused='waiting',effective={state='waiting',hold=true,reason='waiting'}}},
  {'a hold without pause words',{effective={state='waiting',hold=true,reason='waiting'}}},
  {'level 1',{level=1}},{'level 80',{level=80}},{'level 81',{level=81}},{'level 79.5',{level=79.5}},
 }) do
  C.guard(Shows(case[2])==NONE,'A16: '..case[1]..': None assigned, with the runtime fact',Line())
 end
 local unleveled=Rolling()
 unleveled.level=nil
 P.Render(unleveled)
 C.guard(Line()==NONE,'A16: a level that is not stated: None assigned, with the runtime fact',Line())
 Nexus.SessionPause={IsPaused=function() return true end,Status=function() return {paused=true,epoch=1,reason='session_pause'} end,
  Pause=function() error('not called') end,Resume=function() error('not called') end}
 C.guard(Shows()==NONE,'A16: a confirmed session pause: None assigned, with the runtime fact',Line())
 Nexus.SessionPause=nil
 C.expect(Shows()==ACTIVE,'A16: after the pause the same model says Random rolling again',Line())
 C.guard(not AutoOn() and #H.actions==actions,'A16: Auto stayed OFF and nothing was performed')
end)

C.scenario('A17 an assignment that is not positively unassigned keeps its own words',function()
 C.setup(Option(true),'A17: fixture: the option is on')
 for _,case in ipairs({{'loading',{state='loading'}},{'restoring',{state='restoring'}},{'unavailable',{state='unavailable'}},
  {'ready without a name',{state='ready'}},{'not stated',ABSENT}}) do
  local with=Shows({assignment=case[2]})
  local without=Shows({assignment=case[2],randomRoll=ABSENT})
  C.guard(with==without and with~=ACTIVE and with~=NONE,'A17: assignment '..case[1]..': the same words with and without the runtime fact',with..' | '..without)
 end
 C.guard(Shows({assignment={state='loading'}})=='Wishlist: Restoring the saved assignment','A17: a loading assignment is said as being restored',Line())
 C.guard(Shows({assignment=ABSENT})=='Wishlist: Not known','A17: an assignment that is not stated is said as not known',Line())
end)

C.scenario('A18 a named Wishlist, a named Wishlist with no target and an empty Saved Build keep their own words',function()
 C.setup(Option(true),'A18: fixture: the option is on')
 local named={state='ready',name='Auto plan'}
 for _,case in ipairs({
  {'a named Wishlist',{noWishlist=ABSENT,assignment=named},'Wishlist: Auto plan (assigned)'},
  {'a named Wishlist with no target',{noWishlist=ABSENT,emptyWishlist=true,assignment=named},'Wishlist: Auto plan (assigned)'},
  {'a Wishlist name beside an unassigned destination',{noWishlist=ABSENT},NONE},
  {'an empty Saved Build',{assignment={state='unassigned',emptySlot=true}},'Wishlist: Refused'},
 }) do
  for _,level in ipairs({40,80}) do
   local o={level=level}
   for k,v in pairs(case[2]) do o[k]=v end
   local with=Shows(o)
   o.randomRoll=ABSENT
   local without=Shows(o)
   C.guard(with==case[3] and without==case[3],'A18: '..case[1]..' at level '..level..': its own words, with and without the runtime fact',with..' | '..without)
  end
 end
end)

C.scenario('A19 a change is shown by the next render without a layout pass; the words fit the line',function()
 C.setup(Option(true),'A19: fixture: the option is on')
 local label=NexusPanel._contextWishlist
 local sets,set=0,label.SetText
 label.SetText=function(self,...) sets=sets+1;return set(self,...) end
 local function Pass(o) local before=P.RenderStats().layouts;sets=0;P.Render(Rolling(o));return P.RenderStats().layouts-before,sets end
 Pass({randomRoll=ABSENT})
 C.setup(Line()==NONE,'A19: fixture: the line says None assigned',Line())
 local layouts,applied=Pass()
 C.expect(Line()==ACTIVE and layouts==0 and applied>=1,'A19: inactive to active: the next render sets the line, without a layout pass',Line()..' layouts='..layouts..' sets='..applied)
 layouts,applied=Pass()
 C.expect(Line()==ACTIVE and layouts==0 and applied==0,'A19: an unchanged active line is not set again',Line()..' layouts='..layouts..' sets='..applied)
 layouts,applied=Pass({randomRoll=ABSENT})
 C.expect(Line()==NONE and layouts==0 and applied>=1,'A19: active to inactive: the next render sets the line, without a layout pass',Line()..' layouts='..layouts..' sets='..applied)
 Pass()
 Pass({paused='user acting'})
 C.guard(Line()==NONE,'A19: a pause after Random rolling sets the line back to None assigned',Line())
 Pass()
 C.setup(Option(false),'A19: fixture: the option is turned OFF')
 layouts,applied=Pass()
 C.expect(Line()==NONE and applied>=1,'A19: the option turned OFF: the same model is set back to None assigned',Line()..' sets='..applied)
 C.setup(Option(true),'A19: fixture: the option is on again')
 -- The runtime renders nothing for an Auto toggle: P.SetAuto(false) is the
 -- panel's only notice of it.
 Pass()
 local before,rendered=Line(),P.RenderStats().calls
 sets=0
 P.SetAuto(false)
 C.expect(before==ACTIVE and Line()==NONE and sets>=1 and P.RenderStats().calls==rendered+1,
  'A19: Auto turned OFF: the line is set back to None assigned at once, by one render of the last model',before..' > '..Line()..' sets='..sets)
 sets=0
 P.SetAuto(false)
 C.guard(Line()==NONE and sets==0 and P.RenderStats().calls==rendered+1,'A19: a second Auto OFF notice renders nothing more',Line()..' sets='..sets)
 P.SetAuto(true)
 C.guard(Line()==NONE and P.RenderStats().calls==rendered+1,'A19: an Auto ON notice alone never says Random rolling (the runtime states it)',Line())
 label.SetText=nil
 local change=NexusPanel._contextChange
 local function Rect(r) return G.Rect(r,NexusPanel) end
 for _,model in ipairs({G.MODELS.default,G.MODELS.px16,G.MODELS.small,G.MODELS.double}) do
  G.UseFont(model)
  local tag=' ('..model.name..')'
  for _,case in ipairs({{ACTIVE,nil,C.expect},{NONE,{randomRoll=ABSENT},C.guard}}) do
   local shown=Shows(case[2])
   local width=G.Length(G.Visible(label:GetText()))*model.char
   local l,c,p=Rect(label),Rect(change),Rect(NexusPanel)
   case[3](shown==case[1] and label:IsShown() and not Nexus.LayoutMetrics.Shortened(label) and width<=l[3]-l[1]
    and G.Inside(l,p) and G.Apart(l,c),
    'A19: '..case[1]..' is shown whole on one line, inside the panel and clear of Change Wishlist'..tag,
    shown..' '..width..' in '..G.Text(l)..' / '..G.Text(c))
  end
 end
 G.UseFont(G.MODELS.default)
 P.Render(Model({auto=false}))
 C.guard(not AutoOn() and #H.actions==actions,'A19: Auto is OFF and nothing was performed')
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(Auto hover summary, details route and FAQ over the harness; native tooltip drawing NOT RUN)')
