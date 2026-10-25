-- M3 (Automation clarity; M2 N3/N4/N5/N7/N9): the Auto button's hover states
-- what Auto may do, from the permissions the runtime actually gates on
-- (autoPick, autoBanish, autoReroll, autoFreeze, autoDisable, autoSave,
-- autoLockEchoes; autoActivate is read by no action) with the existing
-- control that changes each, and why a selected Auto is held, in plain words.
-- Reading it, Help and the Setup / Welcome replay performs no action, request,
-- send or setting change; only the existing explicit setter changes a
-- permission. The charges line explains "?" and "~"; the Journal coach claims
-- an open Echoes page only when Nexus sees its strip; the replay's routes wait
-- for start-up as Help's do; Setup / Welcome keeps an open first-time Welcome
-- first-time; the Panel route closes other windows only when it opens; an
-- Auto ON board shows its three cards and no charges.
-- Categories (view_regression_support): EXPECT is behaviour added in M3 (it
-- fails on the accepted predecessor ea3268a8); GUARD already holds there and
-- must keep holding; SETUP is the fixture. The exact Close caption of the
-- Welcome's dismissal (P10, P11, WelcomeDismissal) is also an EXPECT, of the
-- newer Close label (formerly Later), and only identifies that control. Real
-- TOC boot, runtime, Panel,
-- Help, QuickStart and Journal controls; synthetic host services only.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_automation_scope')
local H,A
local PLAN={}
for i=1,12 do PLAN[#PLAN+1]={spellId=200000+i,quality=i%4,stacks=1} end
local E1={{spellId=201172,quality=0,stacks=1}}

local function Reset()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 NexusHelpWindow=nil;NexusQuickStart=nil;NexusPanel=nil;NexusEditorFrame=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil;NexusOverwriteWarning=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusLoadoutAssociationPanel=nil
end
-- A plan assigned to Saved Build 1 and the HUD shown (as ux_manual_recommendation).
local function BootPlan()
 Reset()
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={[1]={name='Synthetic plan',verified=true,echoes=PLAN}}
 H.Boot();A=Nexus.GameAdapter
 assert(A.SetLoadoutWishlistIdentity(1,'Synthetic plan',PLAN),'assign the plan')
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
 Nexus.Panel.Show();H.Advance(.5)
end
-- Saved Build One with no Wishlist assigned (the HUD's setup row), as
-- ux_help_navigation boots it.
local function BootSetup()
 Reset()
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 H.AddEcho(201172,'Echo One',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes=E1}}
 H.perks.serverActiveSlot=1
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
end
local function JournalHost()
 local journal=_G.ProjectEbonholdEchoJournal or CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:Hide()
 local micro=_G.EchoJournalMicroButton or CreateFrame('Button','EchoJournalMicroButton',UIParent)
 micro:SetScript('OnClick',function() journal:Show() end)
 return journal,micro
end
local function Counters()
 return {actions=#H.actions,sent=#H.sent,granted=H.grantedRequests,slots=H.slotRequests}
end
local function Same(a,b)
 return a.actions==b.actions and a.sent==b.sent and a.granted==b.granted and a.slots==b.slots
end
local function Show(c) return 'actions='..c.actions..' sent='..c.sent..' granted='..tostring(c.granted)..' slots='..tostring(c.slots) end
-- Every scalar saved setting, as one comparable string, and as a map.
local function SettingsMap()
 local out={}
 for k,v in pairs(Nexus.Store.Settings() or {}) do
  if type(v)~='table' and type(v)~='function' then out[tostring(k)]=tostring(v) end
 end
 return out
end
local function Settings()
 local keys={}
 for k,v in pairs(SettingsMap()) do keys[#keys+1]=k..'='..v end
 table.sort(keys)
 return table.concat(keys,';')
end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function AutoTooltip()
 local button=NexusPanel and NexusPanel._autoBtn
 if not button then return '' end
 local lines=V.TooltipLines(function() button:GetScript('OnEnter')(button) end)
 return V.Plain(table.concat(lines,'\n'))
end
-- A print listener that never raises into the scenario: what was said and
-- whether the action completed.
local function Said(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 return V.Plain(table.concat(heard,' / ')),ok,err
end
local function ChildButton(parent,text)
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and parent and f:GetParent()==parent and V.Plain(f:GetText() or '')==text then return f end
 end
 return nil
end
-- The Welcome's dismissal (P10, P11), found by its label only to identify
-- it: its exact Close caption is a collected EXPECT, never a gate or skip.
-- Only after that EXPECT failed may the real legacy Later control of an
-- earlier cut stand in, so the original closing checks still run on a real
-- control there; the failed Close EXPECT stays in the failure set. A Welcome
-- with neither control is a collected SETUP failure, not a silent skip.
local function WelcomeDismissal(where)
 local close=ChildButton(NexusQuickStart,'Close')
 if C.expect(close~=nil,where..': its dismissal reads exactly Close') then return close end
 local later=ChildButton(NexusQuickStart,'Later')
 C.setup(later~=nil,where..': fixture: it has a dismissal control (Close, or legacy Later after the failed Close EXPECT)')
 return later
end
local function Offer(cards) H.Board(cards);H.Notify();H.Advance(1.2) end
-- The HUD's card rows as shown.
local function CardRows()
 local f=NexusPanel
 local cards={}
 if f and f._rollArea:IsVisible() then
  for _,r in ipairs(f._rollArea.regions or {}) do
   if r.kind=='FontString' and r~=f._rollStatus and r~=f._rollRec and r~=f._chargesText
    and r:IsShown() and V.Plain(r:GetText() or '')~='' then cards[#cards+1]=V.Plain(r:GetText()) end
  end
 end
 return cards
end

C.scenario('P1 the Auto hover states the scope in plain words; hovering acts, requests and writes nothing',function()
 BootPlan()
 C.setup(not Auto() and NexusPanel and NexusPanel._autoBtn~=nil,'P1: fixture: the HUD is shown with Auto OFF')
 local before,settings=Counters(),Settings()
 local text=AutoTooltip()
 print('OBSERVED','P1 tooltip='..text)
 C.guard(text:find('Automation and enabled actions',1,true)~=nil,'P1: the existing tooltip is still shown')
 C.expect(text:find('Auto: OFF',1,true)~=nil and text:find('(autoPick): on',1,true)~=nil
  and text:find('(autoBanish): on',1,true)~=nil and text:find('(autoReroll): on',1,true)~=nil
  and text:find('/nexus reroll on|off',1,true)~=nil and text:find('(autoFreeze): on',1,true)~=nil
  and text:find('(autoDisable): on',1,true)~=nil and text:find('(autoSave): on',1,true)~=nil
  and text:find('(autoLockEchoes): off',1,true)~=nil,
  'P1: each permission the runtime gates on is named with its value and its existing control',text)
 C.expect(text:find('Activate a Saved Build: never',1,true)~=nil and text:find('Orb runs: never by Auto',1,true)~=nil,
  'P1: it says Nexus never activates a Saved Build and never runs Orbs by Auto',text)
 C.guard(Same(Counters(),before),'P1: hovering acts, requests and sends nothing',Show(Counters()))
 C.guard(Settings()==settings and not Auto(),'P1: and changes no setting and no Auto state')
end)

C.scenario('P2 a selected but held Auto: the hover says why, in plain words',function()
 BootPlan()
 SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true)
 Nexus.RequestRecompute();H.Advance(1)
 local model=Nexus.Panel._lastModel
 local held=type(model)=='table' and model.auto==true and type(model.paused)=='string' and model.paused or nil
 C.setup(Auto() and held~=nil,'P2: fixture: Auto is ON and held at its last update',held)
 local before=Counters()
 local text=AutoTooltip()
 print('OBSERVED','P2 tooltip='..text)
 local R=Nexus.Readout
 local plain=R and R.AutoHoldText and held and V.Plain(R.AutoHoldText(held)) or nil
 C.expect(text:find('Auto: ON for this session',1,true)~=nil and plain~=nil
  and text:find('Paused because: '..plain,1,true)~=nil,
  'P2: the hover says Auto is ON for this session and why it is held, in plain words',text)
 C.guard(Same(Counters(),before) and Auto(),'P2: hovering acts, requests and sends nothing; Auto stays selected',Show(Counters()))
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',false)
end)

C.scenario('P3 only the explicit setter changes a permission, and only that one',function()
 BootPlan()
 local before,map=Counters(),SettingsMap()
 C.setup(map.autoReroll=='true','P3: fixture: the Reroll permission is on')
 SlashCmdList.NEXUS('reroll off')
 local after=SettingsMap()
 local changed={}
 for k,v in pairs(after) do if map[k]~=v then changed[#changed+1]=k end end
 for k in pairs(map) do if after[k]==nil then changed[#changed+1]=k end end
 C.guard(after.autoReroll=='false' and #changed==1 and changed[1]=='autoReroll',
  'P3: /nexus reroll off changes the Reroll permission and nothing else',table.concat(changed,','))
 C.guard(Same(Counters(),before),'P3: the setter acts, requests and sends nothing',Show(Counters()))
 local text=AutoTooltip()
 C.expect(text:find('(autoReroll): off',1,true)~=nil,'P3: the hover shows the changed permission',text)
 SlashCmdList.NEXUS('reroll on')
 C.guard(SettingsMap().autoReroll=='true','P3: the same setter turns it back on')
end)

C.scenario('P4 the scope facts: read-only saved data, unset permissions and plain hold reasons',function()
 BootPlan()
 local R=Nexus.Readout
 local lines=R.AutomationScopeLines and R.AutomationScopeLines({selected=false,settings={autoPick=true},readOnly=true}) or {}
 local text=table.concat(lines,'\n')
 C.expect(text:find('Saved data is read-only',1,true)~=nil and text:find('(autoPick): on',1,true)~=nil
  and text:find('(autoBanish): not set',1,true)~=nil,
  'P4: read-only saved data is said, and an unset permission is not shown as on',text)
 local hold=R.AutoHoldText and R.AutoHoldText('user acting') or ''
 C.expect(hold:find('about 3 seconds',1,true)~=nil,'P4: "user acting" is explained in plain words',hold)
 local other=R.AutoHoldText and R.AutoHoldText('waiting for three-card board') or ''
 C.expect(other=='Waiting for the next three Echo choices','P4: other reasons keep their player wording',other)
end)

C.scenario('P5 M2 N9: the charges line explains "?" and "~" on hover; hovering changes nothing',function()
 BootPlan()
 C.setup(not Auto(),'P5: fixture: Auto is OFF')
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 local charges=NexusPanel._chargesText
 C.setup(charges~=nil and charges:IsShown(),'P5: fixture: the charges line is shown on the Auto OFF board')
 local hover=NexusPanel._chargesHover
 local before=Counters()
 local text=''
 if hover and hover:GetScript('OnEnter') then
  text=V.Plain(table.concat(V.TooltipLines(function() hover:GetScript('OnEnter')(hover) end),'\n'))
 end
 print('OBSERVED','P5 legend='..text)
 C.expect(hover~=nil and hover:IsShown() and text:find('?: the game has not reported that count yet',1,true)~=nil
  and text:find('~: estimated',1,true)~=nil,'P5: hovering the charges line explains "?" and "~"',text)
 C.guard(Same(Counters(),before),'P5: hovering acts, requests and sends nothing',Show(Counters()))
end)

C.scenario('P6 M2 N7: the Panel route closes the open editor only when it opens; it requests nothing',function()
 BootSetup()
 local journal=JournalHost()
 Nexus.Panel.Show()
 Nexus.WishlistEditor.Show()
 local button=ChildButton(NexusPanel,'Assign Wishlist')
 C.setup(button~=nil and NexusEditorFrame and NexusEditorFrame:IsShown(),'P6: fixture: the setup Assign Wishlist button with the editor open')
 if not button then return end
 local before=Counters()
 button:Click()
 C.guard(not NexusEditorFrame:IsShown() and journal:IsShown(),'P6: the route closes the editor and opens the Echo Journal')
 C.guard(Same(Counters(),before),'P6: opening the route acts, requests and sends nothing',Show(Counters()))
end)

C.scenario('P7 M2 N7: an Auto ON board shows its three cards and no charges line',function()
 BootPlan()
 SlashCmdList.NEXUS('auto');H.Advance(.5)
 C.setup(Auto(),'P7: fixture: Auto is ON')
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 local cards=CardRows()
 C.guard(#cards==3 and cards[1]:find('Echo 1 ',1,true)==1,'P7: the Auto ON board renders its three card rows',table.concat(cards,' | '))
 C.guard(not (NexusPanel._chargesText and NexusPanel._chargesText:IsShown()) and Nexus.Panel._lastModel.charges==nil,
  'P7: and carries and shows no charges')
end)

C.scenario('P8 M2 N3: the Journal coach claims an open Echoes page only when Nexus sees its strip',function()
 BootSetup()
 local journal,micro=JournalHost()
 -- The game's button toggles the page: here it was open and closes again.
 micro:SetScript('OnClick',function() journal:Hide() end)
 Nexus.Help.Show('start')
 local assign=ChildButton(NexusHelpWindow,'Assign Wishlist...')
 C.setup(assign~=nil,'P8: fixture: Help offers Assign Wishlist...')
 local before=Counters()
 local said=Said(function() if assign then assign:Click() end end)
 print('OBSERVED','P8 said='..said)
 C.expect(said:find('could not confirm that the Echoes page is open',1,true)~=nil
  and not said:find('The Echoes page is open.',1,true),'P8: no claim that the page is open when Nexus cannot see it',said)
 C.guard(Same(Counters(),before),'P8: the route acts, requests and sends nothing',Show(Counters()))
end)

C.scenario('P9 M2 N4: the replay\'s routes wait for start-up as Help\'s do; the replay stays open',function()
 Reset()
 H=dofile('tests/prototype/harness.lua')
 local T=dofile('tests/prototype/startup_support.lua');T.Load()
 local sent,actions=#H.sent,#H.actions
 C.setup(type(Nexus.StartupStatus)~='function' or not Nexus.StartupStatus().coreReady,'P9: fixture: start-up is not ready')
 local shown=Nexus.QuickStart and Nexus.QuickStart.ShowSetup and Nexus.QuickStart.ShowSetup()
 C.setup(shown and NexusQuickStart and NexusQuickStart:IsShown(),'P9: fixture: the informational replay is open')
 local said,ok=Said(function() local b=ChildButton(NexusQuickStart,'Set up current build');if b then b:Click() end end)
 print('OBSERVED','P9 assign said='..said)
 C.expect(ok and NexusQuickStart:IsShown() and said:find('after start-up finishes',1,true)~=nil,
  'P9: Set up current build says it waits for start-up and keeps the replay open',said)
 said,ok=Said(function() local b=ChildButton(NexusQuickStart,'Import / Create Wishlist');if b then b:Click() end end)
 print('OBSERVED','P9 editor said='..said)
 C.expect(ok and NexusQuickStart:IsShown() and not (NexusEditorFrame and NexusEditorFrame:IsShown())
  and said:find('after start-up finishes',1,true)~=nil,'P9: Import / Create Wishlist waits too; no editor opens',said)
 C.guard(#H.sent==sent and #H.actions==actions,'P9: nothing is performed or sent')
end)

C.scenario('P10 M2 N5: Setup / Welcome keeps an open first-time Welcome first-time; closing it records it',function()
 Reset()
 local F=dofile('tests/prototype/format5_support.lua')
 H=F.Boot(F.Database())
 for _=1,40 do
  if NexusQuickStart and NexusQuickStart:IsShown() then break end
  if Nexus.RequestRecompute then Nexus.RequestRecompute() end
  H.Advance(.05,.05)
 end
 local function Title() return NexusQuickStart and NexusQuickStart.title and V.Plain(NexusQuickStart.title:GetText() or '') or '' end
 C.setup(NexusQuickStart and NexusQuickStart:IsShown() and Title()=='Welcome to Nexus','P10: fixture: the first-time Welcome is open',Title())
 local sent,actions=#H.sent,#H.actions
 local shown=Nexus.QuickStart.ShowSetup()
 C.expect(shown and NexusQuickStart:IsShown() and Title()=='Welcome to Nexus',
  'P10: Setup / Welcome leaves the open first-time Welcome as it is',Title())
 local dismiss=WelcomeDismissal('P10: the first-time Welcome')
 if dismiss then dismiss:Click() end
 C.expect(rawget(NexusDB,'hasSeenQuickStart')==true,'P10: closing it records the first-time acknowledgement')
 C.guard(#H.sent==sent and #H.actions==actions and not Auto(),'P10: nothing is performed, sent or enabled')
end)

C.scenario('P11 reading Help and the replay acts, requests, sends and writes nothing',function()
 BootPlan()
 local before,settings=Counters(),Settings()
 local seen=rawget(NexusDB,'hasSeenQuickStart')
 Nexus.Help.Show('rolling');Nexus.Help.Hide()
 local shown=Nexus.QuickStart.ShowSetup()
 C.setup(shown,'P11: fixture: the replay opens')
 local dismiss=WelcomeDismissal('P11: the replay')
 if dismiss then dismiss:Click() end
 C.guard(Same(Counters(),before) and Settings()==settings and rawget(NexusDB,'hasSeenQuickStart')==seen and not Auto(),
  'P11: Help and the replay leave actions, requests, sends, settings, seen state and Auto unchanged',Show(Counters()))
end)

-- The Panel's ... menu as EasyMenu receives it (the client draws it; the
-- items and their handlers are the product's own).
local function OpenMoreMenu()
 local captured
 EasyMenu=function(items) captured=items end
 CloseDropDownMenus=CloseDropDownMenus or function() end
 local button=NexusPanel and NexusPanel._menuBtn
 if button then button:GetScript('OnClick')(button) end
 return captured
end
local function MenuItem(items,prefix)
 for _,item in ipairs(items or {}) do
  if type(item.text)=='string' and item.text:sub(1,#prefix)==prefix then return item end
 end
 return nil
end
local function MenuTexts(items)
 local t={}
 for _,item in ipairs(items or {}) do t[#t+1]=tostring(item.text) end
 return table.concat(t,'\n')
end
local function Body() return V.Plain(NexusPanel and NexusPanel._rollRec and NexusPanel._rollRec:GetText() or '') end
local function Head() return V.Plain(NexusPanel and NexusPanel._rollStatus and NexusPanel._rollStatus:GetText() or '') end
local function RollShown() return NexusPanel~=nil and NexusPanel._rollArea:IsShown() end

C.scenario('P12 UX-10 the Automation settings submenu shows every permission; only the existing setters change one',function()
 BootPlan()
 local before,settings=Counters(),Settings()
 local items=OpenMoreMenu()
 local sub=MenuItem(items,'Automation settings')
 C.expect(sub~=nil and sub.hasArrow==true and type(sub.menuList)=='table',
  'P12: the ... menu has an Automation settings submenu',MenuTexts(items))
 local list=sub and sub.menuList or {}
 local text=MenuTexts(list)
 print('OBSERVED','P12 submenu='..text:gsub('\n',' / '))
 C.expect(text:find('Auto: OFF',1,true)~=nil and text:find('Allow Reroll (autoReroll): on',1,true)~=nil
  and text:find('Allow Freeze (autoFreeze): on',1,true)~=nil and text:find('Take needed Echoes (autoPick): on',1,true)~=nil
  and text:find('Banish (autoBanish): on',1,true)~=nil and text:find('(autoDisable): on',1,true)~=nil
  and text:find('(autoSave): on',1,true)~=nil and text:find('Lock Wishlist Echoes (autoLockEchoes): off',1,true)~=nil
  and text:find('Activate a Saved Build: never',1,true)~=nil and text:find('autoActivate value is not used',1,true)~=nil
  and text:find('Orb runs: never by Auto',1,true)~=nil,
  'P12: it lists each permission with its saved value, the separate locked-Echo option, autoActivate as unused and Orb runs',text)
 local reroll,freeze=MenuItem(list,'Allow Reroll'),MenuItem(list,'Allow Freeze')
 local take,activate=MenuItem(list,'Take needed Echoes'),MenuItem(list,'Activate a Saved Build')
 C.expect(reroll and reroll.checked==true and type(reroll.func)=='function' and freeze and freeze.checked==true
  and type(freeze.func)=='function' and take and take.disabled==true and take.func==nil
  and activate and activate.disabled==true and activate.func==nil,
  'P12: Reroll and Freeze are checkable; permissions without an in-game setter are shown, not changeable')
 C.guard(Same(Counters(),before) and Settings()==settings and not Auto(),
  'P12: opening the menu acts, requests, sends and changes nothing',Show(Counters()))
 if not (reroll and type(reroll.func)=='function') then return end
 local map=SettingsMap()
 reroll.func()
 local after=SettingsMap()
 local changed={}
 for k,v in pairs(after) do if map[k]~=v then changed[#changed+1]=k end end
 for k in pairs(map) do if after[k]==nil then changed[#changed+1]=k end end
 C.expect(after.autoReroll=='false' and #changed==1 and changed[1]=='autoReroll',
  'P12: the Reroll row turns the Reroll permission off through its existing setter, and nothing else',table.concat(changed,','))
 C.guard(Same(Counters(),before) and not Auto(),'P12: the setter acts, requests and sends nothing',Show(Counters()))
 local again=MenuItem((MenuItem(OpenMoreMenu(),'Automation settings') or {}).menuList,'Allow Reroll')
 C.expect(again and again.checked==false and again.text:find('(autoReroll): off',1,true)~=nil,
  'P12: reopened, the row shows Reroll off',again and again.text)
 if again then again.func() end
 C.guard(SettingsMap().autoReroll=='true','P12: the same row turns it back on')
 -- The locked-Echo option is set in the editor: its row opens it, changing nothing.
 local sub2=MenuItem(OpenMoreMenu(),'Automation settings')
 local lock=sub2 and MenuItem(sub2.menuList,'Lock Wishlist Echoes')
 local mid=Settings()
 if lock and type(lock.func)=='function' then lock.func() end
 C.expect(lock~=nil and NexusEditorFrame~=nil and NexusEditorFrame:IsShown() and Settings()==mid,
  'P12: Lock Wishlist Echoes opens the Wishlist Editor and changes no setting')
 if NexusEditorFrame and NexusEditorFrame:IsShown() then Nexus.WishlistEditor.Toggle() end
 local help=sub2 and MenuItem(sub2.menuList,'What Auto may do')
 if help and type(help.func)=='function' then help.func() end
 C.expect(help~=nil and NexusHelpWindow~=nil and NexusHelpWindow:IsShown()
  and V.Plain(NexusHelpWindow.title:GetText() or ''):find('Auto, rolling and saving',1,true)~=nil,
  'P12: the Help row opens the Auto page')
 if NexusHelpWindow then NexusHelpWindow:Hide() end
 C.guard(Same(Counters(),before) and not Auto(),'P12: the editor and Help rows act, request and send nothing',Show(Counters()))
end)

C.scenario('P13 UX-09 a selected but held Auto says why in the roll block, with what helps',function()
 BootPlan()
 SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true)
 Nexus.RequestRecompute();H.Advance(1)
 local model=Nexus.Panel._lastModel
 local held=type(model)=='table' and model.auto==true and type(model.paused)=='string' and model.paused or nil
 C.setup(Auto() and held~=nil,'P13: fixture: Auto is ON and held',held)
 local R=Nexus.Readout
 local plain=R and R.AutoHoldText and held and V.Plain(R.AutoHoldText(held)) or nil
 local before=Counters()
 local body=Body()
 print('OBSERVED','P13 head='..Head()..' body='..body)
 C.expect(RollShown() and Head()=='Auto ON — paused' and plain~=nil and body:find('Paused: '..plain,1,true)~=nil
  and body:find('What helps:',1,true)~=nil,
  'P13: without an Echo choice the roll block shows the paused heading, the plain reason and what helps',body)
 C.guard(Auto() and Same(Counters(),before),'P13: showing it acts, requests and sends nothing; Auto stays selected',Show(Counters()))
 local acted=#H.actions
 Offer({{spellId=200001,quality=1},{spellId=200050,quality=2},{spellId=200051,quality=3}})
 local cards=CardRows()
 local rec=V.Plain(Nexus.Panel._lastModel.recommendation or '')
 body=Body()
 print('OBSERVED','P13 board body='..body)
 C.expect(#cards==3 and rec~='' and body:find(rec,1,true)==1 and body:find('Paused: ',1,true)~=nil,
  'P13: with an Echo choice the reason follows the recommendation below the three cards',body)
 C.guard(#H.actions==acted and Auto(),'P13: the held board takes no action',Show(Counters()))
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',false)
 Nexus.RequestRecompute();H.Advance(1)
 -- A hidden roll block keeps its last text; only a shown one is read.
 C.guard(not (RollShown() and Body():find('Paused: ',1,true)),'P13: when the hold ends no reason line stays',Body())
end)

C.scenario('P14 UX-09 an Auto click that leaves Auto OFF says why, inline; no warning, action or retry',function()
 BootPlan()
 C.setup(not Auto(),'P14: fixture: Auto is OFF')
 local orb=Nexus.OrbRuntime
 local real=orb and orb.BlocksOrdinary
 C.setup(type(real)=='function','P14: fixture: the Orb runtime is loaded')
 if type(real)~='function' then return end
 -- An Orb operation that blocks ordinary Automation (the runtime's own gate).
 orb.BlocksOrdinary=function() return true end
 local before=Counters()
 NexusPanel._autoBtn:Click();H.Advance(.2)
 local body=Body()
 print('OBSERVED','P14 head='..Head()..' body='..body)
 C.guard(not Auto() and not (NexusOverwriteWarning and NexusOverwriteWarning:IsShown()),
  'P14: Auto stays OFF and no warning opens')
 C.expect(RollShown() and body:find('Auto stayed OFF: an Orb run is active or unresolved',1,true)~=nil
  and body:find('What helps:',1,true)~=nil and body:find('Orbs',1,true)~=nil,
  'P14: the roll block says why Auto stayed OFF and what helps',body)
 C.guard(Same(Counters(),before),'P14: the refused click acts, requests, sends and retries nothing',Show(Counters()))
 orb.BlocksOrdinary=real
 NexusPanel._autoBtn:Click();H.Advance(.5)
 Nexus.RequestRecompute();H.Advance(1)
 C.guard(Auto() and not (RollShown() and Body():find('Auto stayed OFF',1,true)),
  'P14: once Auto turns ON no refusal line stays',Body())
end)

C.scenario('P15 UX-10 the Auto warning lists what Auto may do and what it does to tomes; No keeps Auto OFF',function()
 BootPlan()
 local prefs=type(NexusDB)=='table' and rawget(NexusDB,'overwriteWarnings') or nil
 if type(prefs)=='table' then prefs.auto=nil end
 C.setup(not Auto(),'P15: fixture: Auto is OFF and the Auto warning is not suppressed')
 local before,settings=Counters(),Settings()
 NexusPanel._autoBtn:Click()
 local f=NexusOverwriteWarning
 C.setup(f~=nil and f:IsShown(),'P15: fixture: the Auto click opens the Auto warning')
 if not (f and f:IsShown()) then return end
 local text=V.Plain(f.body:GetText() or '')
 print('OBSERVED','P15 warning='..text:gsub('\n',' / '))
 C.guard(text:find('Auto can overwrite your active game Saved Build.',1,true)==1,'P15: it still begins with the overwrite warning',text)
 C.expect(text:find('(autoPick): on',1,true)~=nil and text:find('(autoReroll): on',1,true)~=nil
  and text:find('(autoDisable): on',1,true)~=nil and text:find('(autoSave): on',1,true)~=nil
  and text:find('(autoLockEchoes): off',1,true)~=nil and text:find('Activate a Saved Build: never',1,true)~=nil
  and text:find('Automation settings',1,true)~=nil,
  'P15: it lists each permission Auto acts within, with its value and where to see them',text)
 local R=Nexus.Readout
 C.expect(R and type(R.TOME_PARAGRAPH)=='string' and text:find(V.Plain(R.TOME_PARAGRAPH),1,true)~=nil
  and text:find('does not turn tomes back on when you turn Auto OFF',1,true)~=nil,
  'P15: it says what Auto does to tomes, and that turning Auto OFF does not turn them back on',text)
 C.guard(text:sub(-#'Choose No to keep Auto OFF. Opening this warning does not enable Auto.')
  =='Choose No to keep Auto OFF. Opening this warning does not enable Auto.','P15: the closing choice is still last',text)
 C.guard(not Auto() and Same(Counters(),before) and Settings()==settings,'P15: opening the warning enables and changes nothing')
 f.no:Click()
 C.guard(not Auto() and not f:IsShown() and not (RollShown() and Body():find('Auto stayed OFF',1,true)),
  'P15: No keeps Auto OFF; an answered warning is not reported as a refusal')
end)

C.scenario('P16 UX-10 Help lists the Automation scope and the tome paragraph; the editor actions are named as shown',function()
 BootPlan()
 local before,settings=Counters(),Settings()
 Nexus.Help.Show('rolling');local rolling=V.Plain(NexusHelpWindow.body:GetText() or '')
 Nexus.Help.Show('start');local start=V.Plain(NexusHelpWindow.body:GetText() or '')
 Nexus.Help.Show('wishlists');local lists=V.Plain(NexusHelpWindow.body:GetText() or '')
 Nexus.Help.Hide()
 local R=Nexus.Readout
 C.expect(rolling:find('What Auto may do:',1,true)~=nil and rolling:find('(autoLockEchoes) is off by default',1,true)~=nil
  and rolling:find('autoActivate value is not used by any action',1,true)~=nil
  and rolling:find('then Automation settings',1,true)~=nil,
  'P16: the Auto page lists the permissions, the separate locked-Echo option, unused autoActivate and the settings menu',rolling)
 C.expect(R and type(R.TOME_PARAGRAPH)=='string' and rolling:find(V.Plain(R.TOME_PARAGRAPH),1,true)~=nil,
  'P16: the Auto page has the same tome paragraph as the Auto warning',rolling)
 C.expect(start:find('Click Create & assign for a new or imported plan.',1,true)~=nil
  and start:find('Create unassigned saves the plan without a target.',1,true)~=nil
  and start:find('For an existing Wishlist, click Save changes.',1,true)~=nil
  and lists:find('also offers Save & assign',1,true)~=nil,
  'P16: Help names the editor actions as they are shown',start)
 C.guard(Same(Counters(),before) and Settings()==settings and not Auto(),'P16: reading Help acts, requests, sends and changes nothing')
end)

C.finish('(Automation scope and hold reasons in plain words; passive reads; setter-only permissions; settings submenu; inline reason; warning/Help scope and tomes; M2 notes)')
