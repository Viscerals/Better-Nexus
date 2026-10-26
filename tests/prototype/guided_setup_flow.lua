-- Guided setup coach (issue #131): first-use and existing paths, every
-- navigation control (Next, Back, Skip, Close, Escape, Help, resume, replay),
-- replace consequences with Cancel, Auto already ON with its consent, the
-- SIMULATED lesson, optional lessons, and 420 px / 125% / long UTF-8 layout,
-- through the real Setup / Welcome entry, coach window, Echo Journal chooser
-- and StaticPopup handlers (synthetic host services).
-- EXPECT: added behaviour; at 2b287ef8 the SETUP is healthy (boot, two
-- server Wishlists, selected Saved Build 2, chooser rows) but there is no
-- Guided setup button or coach, so each EXPECT fails there (reported, not
-- raised). GUARD: existing behaviour that must hold. Effects come from
-- captured production calls (counted adapter writers, host action log,
-- sends, Orb spends, Auto), never from the guide. No native claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local L=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('guided_setup_flow')
local H,A,writes,spends
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity',
 'UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist','ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}
local NAMES={'ProjectEbonholdEchoJournal','EchoJournalMicroButton','NexusEditorFrame','NexusWishlistNameInput',
 'NexusActiveWishlistSelector','NexusWishlistOnlyPicker','NexusLoadoutAssociationPanel','NexusGuidedSetup',
 'NexusQuickStart','NexusQuickStartEscape','NexusHelpWindow','NexusPanel'}
local LONG='Wunschliste \195\156ber-Gr\195\182\195\159e \226\128\148 \240\159\148\165 sehr lange Namen f\195\188r den F\195\188hrer und noch mehr Text'
local CONSENT='NEXUS_ASSIGN_WISHLIST_AUTO_ON'

local function Boot(o)
 o=o or {}
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 for _,n in ipairs(NAMES) do _G[n]=nil end
 H=dofile('tests/prototype/harness.lua');H.playerLevel=80;wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5)
 H.AddEcho(201174,'Echo Free',0,5);H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [3]={name='Empty three',verified=true,echoes={}},[106]={name='W-Six',verified=false,echoes=E6},
  [107]={name=o.free or 'W-Free',verified=false,echoes=EF}}
 H.perks.serverActiveSlot=2
 spends=0
 ProjectEbonhold.OrbService={IsStateKnown=function() return true end,GetCharges=function() return 0 end,
  IsOfferPending=function() return false end,RequestCharges=function() end,
  ConfirmSpend=function() spends=spends+1;return false end}
 H.Boot();A=Nexus.GameAdapter;H.Notify();A.Poll();H.Advance(1)
 writes={}
 for _,k in ipairs(WRITERS) do local real=A[k]
  if type(real)=='function' then writes[k]=0;A[k]=function(...) writes[k]=writes[k]+1;return real(...) end end end
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
 local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent);journal:Hide()
 CreateFrame('Button','EchoJournalMicroButton',UIParent):SetScript('OnClick',function() journal:Show() end)
end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Effects() return table.concat({Writes(),#H.actions,#H.sent,spends,tostring(Auto())},'/') end
local function Guide() return _G.NexusGuidedSetup end
local function Shown() local g=Guide();return g~=nil and g:IsShown() end
local function Find(exact,text)
 local g=Guide();if not g then return nil end
 for _,c in ipairs(g.children) do
  if c.kind=='Button' and c:IsShown() then
   local t=V.Plain(c:GetText() or '')
   if (exact and t==text) or (not exact and t:find(text,1,true)) then return c end
  end
 end
end
local function Btn(t) return Find(true,t) end
local function Opt(t) return Find(false,t) end
local function Press(b) if b then b:Click() end return b~=nil end
local function On(b) return b~=nil and b:IsEnabled() end
local function Text() local g=Guide();if not g then return '' end
 return V.Plain((g.step:GetText() or '')..' | '..(g.status:GetText() or '')..' | '..(g.extra:GetText() or '')) end
local function Step() local g=Nexus.GuidedSetup;return g and g.StepId() or nil end
local function Row(name)
 local p=_G.NexusWishlistOnlyPicker
 for _,row in ipairs(p and p.children or {}) do
  if row.nameButton and row:IsVisible() and V.Plain(tostring(row.nameButton.text:GetText() or '')):find(name,1,true) then return row end
 end
end
local function Open(tag)
 Nexus.QuickStart.ShowSetup()
 local w,b=_G.NexusQuickStart,nil
 for _,c in ipairs(w and w.children or {}) do
  if c.kind=='Button' and V.Plain(c:GetText() or '')=='Guided setup (step by step)' then b=c end
 end
 C.expect(b~=nil,tag..': Setup / Welcome offers Guided setup')
 if b then b:Click() end
 return C.expect(Shown(),tag..': the coach opens')
end

C.scenario('F1 first use: every navigation control moves the guide only',function()
 Boot()
 C.setup(Nexus.QuickStart and Nexus.JournalTab and not Shown(),'F1: fixture: healthy boot, coach closed')
 local before=Effects()
 if not Open('F1') then return end
 C.expect(Step()=='welcome' and Text():find('Step 1 of 7',1,true)~=nil,'F1: it starts at Welcome',Text())
 C.expect(Btn('Next')~=nil and not On(Btn('Next')),'F1: Next waits for a choice')
 Press(Btn('Skip'));C.expect(Step()=='wishlist','F1: Skip moves on')
 Press(Btn('Back'));C.expect(Step()=='welcome','F1: Back returns')
 Press(Opt('I am new'));C.expect(Step()=='wishlist','F1: New opens the Wishlist step')
 Press(Btn('Close'));C.expect(not Shown(),'F1: Close hides the coach')
 Nexus.GuidedSetupUI.Show();C.expect(Shown() and Step()=='wishlist','F1: reopening resumes the same step')
 local reg=0;for _,n in ipairs(UISpecialFrames) do if n=='NexusGuidedSetup' then reg=reg+1 end end
 C.expect(reg==1,'F1: Escape closes the coach (registered once)',reg)
 if Guide() then Guide():Hide() end
 Nexus.GuidedSetupUI.Show();C.expect(Step()=='wishlist','F1: after Escape it resumes')
 Press(Btn('Help'));C.expect(_G.NexusHelpWindow~=nil and NexusHelpWindow:IsShown(),'F1: Help opens')
 if _G.NexusHelpWindow then NexusHelpWindow:Hide() end
 Nexus.GuidedSetupUI.Replay();C.expect(Step()=='welcome','F1: replay starts again at Welcome')
 C.guard(Effects()==before,'F1: navigation wrote, acted, sent, spent and toggled nothing',Effects())
 C.guard(rawget(NexusDB,'hasSeenQuickStart')==nil,'F1: the informational Setup / Welcome records no acknowledgement')
end)

C.scenario('F2 existing path: choice, target, one explicit assignment, verified read back',function()
 Boot()
 C.setup(#(A.GetWishlistCandidates() or {})>=2 and A.SelectedSavedBuild()==2,'F2: fixture: two server Wishlists; Fire PvE selected')
 if not Open('F2') then return end
 Press(Opt('I already have'))
 C.expect(Step()=='wishlist' and Opt('W-Free')~=nil and Opt('W-Six')~=nil,'F2: the existing Wishlists are listed')
 Press(Opt('W-Free'))
 C.expect(Text():find('[done] Chosen',1,true)~=nil and On(Btn('Next')),'F2: the choice is shown and Next is offered',Text())
 Press(Btn('Next'))
 C.expect(Step()=='target' and Opt('Empty three')~=nil and not Opt('Empty three'):IsEnabled(),'F2: an empty Saved Build is shown with its reason and refused')
 Press(Opt('Fire PvE'));C.expect(On(Btn('Next')),'F2: Fire PvE is a ready target')
 local before=Effects()
 Press(Btn('Next'))
 C.expect(Step()=='assign' and Text():find('[to do]',1,true)~=nil,'F2: the step waits for the player action',Text())
 Press(Btn('Open the Wishlist chooser'))
 C.expect(not Shown() and _G.NexusWishlistOnlyPicker~=nil and NexusWishlistOnlyPicker:IsShown(),'F2: the coach steps aside for the real chooser')
 C.guard(Effects()==before,'F2: coach choices and opening the chooser changed nothing',Effects())
 local row=Row('W-Free');C.setup(row~=nil,'F2: fixture: the chooser lists W-Free')
 if not row then return end
 row.nameButton:Click()
 C.guard(writes.SetLoadoutWishlist==1 and Writes()==1,'F2: the explicit choice makes exactly one assignment write',Writes())
 C.expect(Shown() and Text():find('[verified]',1,true)~=nil,'F2: the coach returns verified after the read back',Text())
 before=Effects()
 C.expect(On(Btn('Next')) and Press(Btn('Next')) and Step()=='manual','F2: Continue moves on')
 C.guard(Effects()==before,'F2: Continue changes nothing')
end)

C.scenario('F3 replace an existing assignment: consequences, Cancel, Auto ON consent; Auto kept ON',function()
 Boot()
 C.setup(A.SetLoadoutWishlist(2,106)==true,'F3: fixture: Fire PvE follows W-Six');writes.SetLoadoutWishlist=0
 SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
 C.setup(Auto(),'F3: fixture: Auto is ON before the guide')
 local before=Effects()
 if not Open('F3') then return end
 Press(Opt('I already have'));Press(Opt('W-Free'));Press(Btn('Next'));Press(Opt('Fire PvE'))
 C.expect(Text():find('W-Six',1,true)~=nil and Text():find('replaces',1,true)~=nil,'F3: the consequence names the current Wishlist',Text())
 C.expect(not On(Btn('Next')),'F3: Next waits for the decision')
 Press(Btn('Cancel'))
 C.expect(Nexus.GuidedSetup.State().target==nil and Effects()==before,'F3: Cancel drops the choice and changes nothing')
 Press(Opt('Fire PvE'));Press(Btn('Replace and continue'))
 C.expect(On(Btn('Next')),'F3: an accepted replacement is ready')
 Press(Btn('Next'));Press(Btn('Open the Wishlist chooser'))
 local row=Row('W-Free');C.setup(row~=nil,'F3: fixture: the chooser lists W-Free')
 if not row then return end
 H.popup=nil;row.nameButton:Click()
 local p=H.popup
 C.guard(p~=nil and p.which==CONSENT and Writes()==0,'F3: with Auto ON the chooser asks first; nothing written')
 if H.popup==p then H.popup=nil end
 Nexus.GuidedSetupUI.Show()
 C.expect(Text():find('[waiting',1,true)~=nil and not On(Btn('Next')),'F3: a dismissed confirmation is pending, not complete',Text())
 Press(Btn('Open the Wishlist chooser'));row=Row('W-Free')
 if row then H.popup=nil;row.nameButton:Click() end
 p=H.popup
 if p then H.popup=nil;StaticPopupDialogs[p.which].OnAccept(p.frame,p.data) end
 C.guard(writes.SetLoadoutWishlist==1,'F3: the accepted confirmation writes once')
 C.expect(Text():find('[verified]',1,true)~=nil,'F3: verified after the read back',Text())
 Press(Btn('Next'));Press(Btn('Skip'))
 C.expect(Step()=='auto' and Text():find('Auto is ON',1,true)~=nil,'F3: Auto already ON is stated and kept',Text())
 Press(Btn('Next'));C.expect(Step()=='summary','F3: summary')
 Nexus.GuidedSetupUI.Replay()
 C.guard(Auto(),'F3: Auto stays ON through the guide and its replay')
end)

C.scenario('F4 SIMULATED lesson and optional lessons: no live action; honest summary',function()
 Boot()
 local before=Effects()
 if not Open('F4') then return end
 Press(Opt('Just explore'))
 C.expect(Step()=='manual' and Text():find('SIMULATED',1,true)~=nil,'F4: explore opens the clearly simulated lesson')
 Press(Opt('Sample Frost'))
 C.expect(Text():find('Not this one',1,true)~=nil and not On(Btn('I understand (simulated)')),'F4: a wrong pick is explained')
 Press(Opt('Sample Ember (Rare)'));Press(Btn('I understand (simulated)'))
 C.expect(On(Btn('Next')),'F4: the acknowledged lesson can continue')
 Press(Btn('Next'));Press(Btn('Next'))
 local t=Text()
 C.expect(Step()=='summary' and t:find('[lesson only',1,true)~=nil and t:find('[verified]',1,true)==nil
  and t:find('not complete',1,true)~=nil,'F4: the summary does not call setup complete',t)
 Press(Btn('Orb lesson (optional)'))
 C.expect(_G.NexusHelpWindow~=nil and NexusHelpWindow:IsShown(),'F4: the Orb lesson opens Help')
 C.guard(Effects()==before,'F4: simulation and lessons took no game action, send, spend or Auto change',Effects())
end)

C.scenario('F5 420 px, 125% text and a long UTF-8 name stay inside the coach with full text reachable',function()
 Boot({free=LONG})
 L.UseFont({name='125%',char=8.75,line=15,size=15})
 if not Open('F5') then return end
 Press(Opt('I already have'))
 local g=Guide()
 C.expect(g:GetWidth()==420,'F5: nominal 420 px width',g:GetWidth())
 local o=Opt('Wunschliste')
 C.expect(o~=nil and type(o.full)=='string' and o.full:find(LONG,1,true)~=nil,'F5: the complete long name is the option tooltip text')
 if o then Press(o) end
 local root=L.Rect(g,g)
 for _,fs in ipairs({g.step,g.purpose,g.status}) do
  local r=L.Rect(fs,g)
  local fits=fs:GetHeight()>=math.min(160,L.Rows(fs:GetText(),372,8.75)*15)
  C.expect(L.Inside(r,root) and fits,'F5: a text block is inside and tall enough (or capped with hover text)',L.Text(r))
 end
 local nxt=Btn('Next')
 for _,c in ipairs(g.children) do
  if c.kind=='Button' and c:IsShown() then
   local r=L.Rect(c,g)
   C.expect(L.Inside(r,root),'F5: control inside the coach: '..V.Plain(c:GetText() or ''),L.Text(r))
   if nxt and c~=nxt and c.points[1] and c.points[1][1]=='TOPLEFT' then
    C.expect(L.Apart(r,L.Rect(nxt,g)),'F5: no overlap with the navigation row')
   end
  end
 end
 C.expect(Text():find(LONG,1,true)~=nil,'F5: the chosen long name is shown in full in the wrapped status')
end)

C.finish('(guided coach: one step at a time; navigation changes nothing; verified only after read back)')
