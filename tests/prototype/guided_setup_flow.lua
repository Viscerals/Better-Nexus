-- Guided setup coach (issue #131), laid out after the Claude Design guided
-- setup artifact: first-use and existing paths, every navigation control
-- (Continue, Back, Skip for now, checklist, X, Escape, inline Help, resume,
-- replay), replace consequences with Choose another, Auto already ON with its
-- consent, the SIMULATED preview, optional lessons, and 420 px / 125% / long
-- UTF-8 layout, through the real Setup / Welcome entry, coach window, Echo
-- Journal chooser and StaticPopup handlers (synthetic host services). Also
-- full Help in place of the coach with its asynchronous returns (F9, F10),
-- the design's footer treatments (F11) and its filled step actions (F12).
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
 'NexusGuidedSetupEscape','NexusQuickStart','NexusQuickStartEscape','NexusHelpWindow','NexusPanel'}
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
 -- First use is the guided setup coach now; these scenarios start with it
 -- closed by a plain hide, which records no first-use acknowledgement.
 if NexusGuidedSetup and NexusGuidedSetup:IsShown() then NexusGuidedSetup:Hide() end
 local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent);journal:Hide()
 CreateFrame('Button','EchoJournalMicroButton',UIParent):SetScript('OnClick',function() journal:Show() end)
end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Effects() return table.concat({Writes(),#H.actions,#H.sent,spends,tostring(Auto())},'/') end
-- Effects without sends, for flows that also run client frames (NextFrame).
local function Quiet() return table.concat({Writes(),#H.actions,spends,tostring(Auto())},'/') end
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
local function Text() return Guide() and V.Plain(Nexus.GuidedSetupUI.VisibleText() or '') or '' end
local function Step() local g=Nexus.GuidedSetup;return g and g.StepId() or nil end
local function Row(name)
 local p=_G.NexusWishlistOnlyPicker
 for _,row in ipairs(p and p.children or {}) do
  if row.nameButton and row:IsVisible() and V.Plain(tostring(row.nameButton.text:GetText() or '')):find(name,1,true) then return row end
 end
end
-- The client's next frame with every send attributed (F9, F10): one pass of
-- every visible OnUpdate, as one H.Advance(.05) step makes it. A send made in
-- the OnUpdate of a frame that existed before the flow began (Known) and
-- belongs to none of the flow's windows is background; any other send (the
-- coach's one-frame return, Help, the checklist, the editor, or a frame made
-- since the flow began) is the flow's own. A background send of a kind
-- (route and prefix or chat type) the session had not sent before the flow
-- is listed in tally.unknown, not silently excused. tally.returned is the
-- class of the frame whose OnUpdate brought the coach back.
local OWN={NexusGuidedSetup=true,NexusHelpWindow=true,NexusQuickStart=true,NexusSetupChecklist=true,NexusEditorFrame=true}
local function Known() local k={};for _,f in ipairs(H.frames) do k[f]=true end;return k end
local function Kind(m) return tostring(m.route)..':'..tostring(m.prefix or m.kind) end
local function Tally()
 local kinds={};for _,m in ipairs(H.sent) do kinds[Kind(m)]=true end
 return {flow=0,background=0,unknown={},kinds=kinds}
end
local function Background(f,known)
 if not known[f] then return false end
 local p=f
 while p do if p.name and OWN[p.name] then return false end;p=p.parent end
 return true
end
local function NextFrame(known,tally)
 H.now=H.now+.05
 local list={};for i,f in ipairs(H.frames) do list[i]=f end
 for _,f in ipairs(list) do
  if f:IsVisible() and f.scripts.OnUpdate then
   local s,was=#H.sent,Shown()
   f.scripts.OnUpdate(f,.05)
   local own=not Background(f,known)
   for i=s+1,#H.sent do
    if own then tally.flow=tally.flow+1
    else
     tally.background=tally.background+1
     if not tally.kinds[Kind(H.sent[i])] then tally.unknown[#tally.unknown+1]=Kind(H.sent[i]) end
    end
   end
   if not was and Shown() and tally.returned==nil then tally.returned=own and 'flow' or 'background' end
  end
 end
end
local function Tallied(tally,sent)
 return 'sent='..(#H.sent-sent)..' background='..tally.background..' flow='..tally.flow
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
-- Welcome records the path; Continue moves on.
local function Start(path) Press(Opt(path));return Press(Btn('Continue')) end

C.scenario('F1 first use: every navigation control moves the guide only',function()
 Boot()
 C.setup(Nexus.QuickStart and Nexus.JournalTab and not Shown(),'F1: fixture: healthy boot, coach closed')
 local before=Effects()
 if not Open('F1') then return end
 C.expect(Step()=='welcome' and Text():find('Step 1 of 7',1,true)~=nil and Text():find('Welcome to Nexus',1,true)~=nil,
  'F1: it starts at Welcome, step 1 of 7',Text())
 C.expect(Btn('Continue')~=nil and not On(Btn('Continue')),'F1: Continue waits for a choice')
 C.expect(Btn('Skip for now')==nil,'F1: Welcome cannot be skipped')
 C.expect(Text():find('never assigns, spends Orbs, sends data, or changes Auto',1,true)~=nil,'F1: the navigation safety line is shown')
 Press(Opt('New to Nexus'))
 C.expect(Step()=='welcome' and On(Btn('Continue')),'F1: a choice is recorded without moving on')
 Press(Btn('Continue'));C.expect(Step()=='wishlist','F1: Continue opens the Wishlist step')
 Press(Btn('Skip for now'))
 C.expect(Step()=='target' and Nexus.GuidedSetup.State().skipped.wishlist==true,'F1: Skip for now moves on and records skipped')
 Press(Btn('Back'));C.expect(Step()=='wishlist','F1: Back returns')
 Press(Btn('Checklist v'))
 C.expect(Opt('Read a recommendation')~=nil and Text():find('Skipped',1,true)~=nil,'F1: the checklist lists the steps with their status words',Text())
 Press(Opt('Read a recommendation'));C.expect(Step()=='manual','F1: a checklist row moves to its step')
 Press(Btn('Back'));Press(Btn('Back'));Press(Btn('Back'))
 C.expect(Step()=='wishlist','F1: Back walks the path')
 Press(Btn('X'));C.expect(not Shown(),'F1: X closes the coach')
 Nexus.GuidedSetupUI.Show();C.expect(Shown() and Step()=='wishlist','F1: reopening resumes the same step')
 local reg,raw=0,0
 for _,n in ipairs(UISpecialFrames) do if n=='NexusGuidedSetupEscape' then reg=reg+1 elseif n=='NexusGuidedSetup' then raw=raw+1 end end
 C.expect(reg==1 and raw==0,'F1: Escape closes the coach through its one listed Escape child (the coach itself is not listed)',reg..'/'..raw)
 Press(Btn('Help'))
 C.expect(Shown() and Text():find('About: Choose a Wishlist',1,true)~=nil and not (_G.NexusHelpWindow and NexusHelpWindow:IsShown()),
  'F1: Help opens the step help card inside the coach',Text())
 if _G.NexusGuidedSetupEscape then NexusGuidedSetupEscape:Hide() end
 C.expect(Shown() and Text():find('About:',1,true)==nil and NexusGuidedSetupEscape:IsShown(),
  'F1: Escape closes the help card first and keeps the coach')
 Press(Btn('Help'));Press(Btn('Open full Help'))
 C.expect(_G.NexusHelpWindow~=nil and NexusHelpWindow:IsShown(),'F1: the help card opens full Help')
 if _G.NexusHelpWindow then NexusHelpWindow:Hide() end
 Press(Btn('X'));Nexus.GuidedSetupUI.Show()
 if _G.NexusGuidedSetupEscape then NexusGuidedSetupEscape:Hide() end
 C.expect(not Shown(),'F1: Escape (the listed child hidden, as the client does) closes the coach')
 Nexus.GuidedSetupUI.Show();C.expect(Step()=='wishlist','F1: after Escape it resumes')
 Nexus.GuidedSetupUI.Replay()
 C.expect(Step()=='welcome' and Text():find('Welcome back',1,true)~=nil,'F1: replay starts again at Welcome',Text())
 C.guard(Effects()==before,'F1: navigation wrote, acted, sent, spent and toggled nothing',Effects())
 C.guard(rawget(NexusDB,'hasSeenQuickStart')==true,
  'F1: the later deliberate Close of the pending first-use coach records only its dismissal')
end)

C.scenario('F2 existing path: choice, target, one explicit assignment, verified read back',function()
 Boot()
 C.setup(#(A.GetWishlistCandidates() or {})>=2 and A.SelectedSavedBuild()==2,'F2: fixture: two server Wishlists; Fire PvE selected')
 if not Open('F2') then return end
 Start('I already have')
 C.expect(Step()=='wishlist' and Opt('W-Free')~=nil and Opt('W-Six')~=nil,'F2: the existing Wishlists are listed')
 C.expect(Text():find('Wishlist - what you want',1,true)~=nil and Text():find('Saved Build - what you play',1,true)~=nil,
  'F2: Wishlist and Saved Build are explained apart',Text())
 Press(Opt('W-Free'))
 C.expect(Text():find('Chosen: W-Free',1,true)~=nil and On(Btn('Continue')),'F2: the choice is shown and Continue is offered',Text())
 Press(Btn('Continue'))
 -- The original guided design offers an empty slot too. Choosing it changes
 -- nothing and says the game's own save comes first; Continue waits (F14).
 local GT=Nexus.UserText.Guide.target
 C.expect(Step()=='target' and Opt('Empty three')~=nil and Opt('Empty three'):IsEnabled()
  and Text():find(GT.emptyOffer,1,true)~=nil,'F2: an empty Saved Build is offered with what it needs first',Text())
 local empty=Effects()
 Press(Opt('Empty three'))
 C.expect(not On(Btn('Continue')) and Btn('Open My Builds')~=nil and Text():find(GT.cEmptySave,1,true)~=nil,
  'F2: an empty target waits for the player\'s own save in My Builds; Continue does not lead to a dead end',Text())
 C.guard(Effects()==empty,'F2: choosing the empty slot saved, wrote, acted, sent and toggled nothing',Effects())
 Press(Opt('Fire PvE'));C.expect(On(Btn('Continue')),'F2: Fire PvE is a ready target')
 C.expect(Text():find('If you assign W-Free here',1,true)~=nil,'F2: the consequence card names the Wishlist',Text())
 local before=Effects()
 Press(Btn('Continue'))
 C.expect(Step()=='assign' and Btn('Open the Wishlist chooser')~=nil and not On(Btn('Continue')),'F2: the step waits for the player action',Text())
 Press(Btn('Open the Wishlist chooser'))
 C.expect(not Shown() and _G.NexusWishlistOnlyPicker~=nil and NexusWishlistOnlyPicker:IsShown(),'F2: the coach steps aside for the real chooser')
 C.guard(Effects()==before,'F2: coach choices and opening the chooser changed nothing',Effects())
 local row=Row('W-Free');C.setup(row~=nil,'F2: fixture: the chooser lists W-Free')
 if not row then return end
 row.nameButton:Click()
 C.guard(writes.SetLoadoutWishlist==1 and Writes()==1,'F2: the explicit choice makes exactly one assignment write',Writes())
 C.expect(Shown() and Text():find('Nexus confirmed it',1,true)~=nil and Text():find('Read back',1,true)~=nil,
  'F2: the coach returns confirmed, with its read back evidence',Text())
 before=Effects()
 C.expect(On(Btn('Continue')) and Press(Btn('Continue')) and Step()=='manual','F2: Continue moves on')
 C.guard(Effects()==before,'F2: Continue changes nothing')
end)

C.scenario('F3 replace an existing assignment: consequences, Choose another, Auto ON consent; Auto kept ON',function()
 Boot()
 C.setup(A.SetLoadoutWishlist(2,106)==true,'F3: fixture: Fire PvE follows W-Six');writes.SetLoadoutWishlist=0
 SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
 C.setup(Auto(),'F3: fixture: Auto is ON before the guide')
 local before=Effects()
 if not Open('F3') then return end
 Start('I already have');Press(Opt('W-Free'));Press(Btn('Continue'));Press(Opt('Fire PvE'))
 C.expect(Text():find('W-Six',1,true)~=nil and Text():find('switches it to',1,true)~=nil and Text():find('Nothing is deleted',1,true)~=nil,
  'F3: the consequence names the current Wishlist and keeps it',Text())
 C.expect(Text():find('Auto is ON',1,true)~=nil,'F3: the consequence names the Auto ON effect')
 C.expect(not On(Btn('Continue')),'F3: Continue waits for the decision')
 Press(Btn('Choose another'))
 C.expect(Nexus.GuidedSetup.State().target==nil and Effects()==before,'F3: Choose another drops the choice and changes nothing')
 Press(Opt('Fire PvE'));Press(Btn('Replace and continue'))
 C.expect(On(Btn('Continue')),'F3: an accepted replacement is ready')
 Press(Btn('Continue'));Press(Btn('Open the Wishlist chooser'))
 local row=Row('W-Free');C.setup(row~=nil,'F3: fixture: the chooser lists W-Free')
 if not row then return end
 H.popup=nil;row.nameButton:Click()
 local p=H.popup
 C.guard(p~=nil and p.which==CONSENT and Writes()==0,'F3: with Auto ON the chooser asks first; nothing written')
 if H.popup==p then H.popup=nil end
 Nexus.GuidedSetupUI.Show()
 C.expect(Text():find('Waiting for you',1,true)~=nil and not On(Btn('Continue')),'F3: a dismissed confirmation is pending, not complete',Text())
 Press(Btn('Open the Wishlist chooser again'));row=Row('W-Free')
 if row then H.popup=nil;row.nameButton:Click() end
 p=H.popup
 if p then H.popup=nil;StaticPopupDialogs[p.which].OnAccept(p.frame,p.data) end
 C.guard(writes.SetLoadoutWishlist==1,'F3: the accepted confirmation writes once')
 C.expect(Text():find('Nexus confirmed it',1,true)~=nil,'F3: confirmed after the read back',Text())
 Press(Btn('Continue'));Press(Btn('Skip for now'))
 C.expect(Step()=='auto' and Text():find('Auto is ON right now',1,true)~=nil and not On(Btn('Continue')),
  'F3: Auto already ON is read and waits for the player',Text())
 Press(Btn('Keep Auto ON'));C.expect(Step()=='summary','F3: Keep Auto ON moves to the summary')
 C.expect(Text():find("You're set up",1,true)~=nil,'F3: a confirmed assignment is set up',Text())
 Nexus.GuidedSetupUI.Replay()
 C.guard(Auto(),'F3: Auto stays ON through the guide and its replay')
end)

C.scenario('F4 SIMULATED preview and optional lessons: no live action; honest summary',function()
 Boot()
 local before=Effects()
 if not Open('F4') then return end
 Start('Just look around')
 C.expect(Step()=='manual' and Text():find('SIMULATED PREVIEW',1,true)~=nil and Text():find('Step 2 of 4',1,true)~=nil,
  'F4: a look-around opens the clearly simulated preview as step 2 of 4',Text())
 C.expect(not On(Btn('Continue')),'F4: the preview waits for one pick or Skip')
 Press(Opt('Sample Frost'))
 C.expect(Text():find('your pick always wins',1,true)~=nil and On(Btn('Continue')),'F4: any pick is tried and explained',Text())
 Press(Btn('Continue'))
 C.expect(Step()=='auto' and Btn('Keep Auto OFF')~=nil,'F4: Auto is offered as optional')
 Press(Btn('Keep Auto OFF'))
 local t=Text()
 C.expect(Step()=='summary' and t:find("You've had a look around",1,true)~=nil and t:find('Nexus confirmed',1,true)==nil
  and t:find('Not part of a look-around',1,true)~=nil and t:find('sent nothing and used no Orbs',1,true)~=nil,
  'F4: the summary does not call setup complete',t)
 C.expect(Nexus.GuidedSetup.Summary().complete==false,'F4: core setup is not complete')
 Press(Opt('Orbs & Lost Memories'))
 C.expect(Text():find('spends nothing',1,true)~=nil,'F4: the Orb lesson reads without opening anything')
 Press(Opt('Sharing & Sync'));Press(Btn('Open Help: Sharing'))
 C.expect(_G.NexusHelpWindow~=nil and NexusHelpWindow:IsShown(),'F4: the sharing lesson opens Help')
 C.guard(Effects()==before,'F4: simulation and lessons took no game action, send, spend or Auto change',Effects())
end)

C.scenario('F5 420 px, 125% text and a long UTF-8 name stay inside the coach with full text reachable',function()
 Boot({free=LONG})
 L.UseFont({name='125%',char=8.75,line=15,size=15})
 if not Open('F5') then return end
 Start('I already have')
 local g=Guide()
 C.expect(g:GetWidth()==420,'F5: nominal 420 px width',g:GetWidth())
 local o=Opt('Wunschliste')
 C.expect(o~=nil and type(o.full)=='string' and o.full:find(LONG,1,true)~=nil,'F5: the complete long name is the option tooltip text')
 if o then Press(o) end
 local root=L.Rect(g,g)
 for _,fs in ipairs(Nexus.GuidedSetupUI.TextRegions()) do
  local r=L.Rect(fs,g)
  local fits=fs:GetHeight()>=math.min(220,L.Rows(fs:GetText(),fs:GetWidth(),8.75)*15)
  C.expect(L.Inside(r,root) and fits,'F5: a text block is inside and tall enough (or capped with hover text)',L.Text(r))
 end
 local nxt=Btn('Continue')
 for _,c in ipairs(g.children) do
  if c.kind=='Button' and c:IsShown() then
   local r=L.Rect(c,g)
   C.expect(L.Inside(r,root),'F5: control inside the coach: '..V.Plain(c:GetText() or ''),L.Text(r))
   if nxt and c~=nxt then
    C.expect(L.Apart(r,L.Rect(nxt,g)),'F5: no overlap with Continue: '..V.Plain(c:GetText() or ''))
   end
  end
 end
 C.expect(Text():find(LONG,1,true)~=nil,'F5: the chosen long name is shown in full in the wrapped status')
end)

C.scenario('F6 choice rows and preview cards stack without overlap at 420 px and 125% text',function()
 Boot()
 L.UseFont({name='125%',char=8.75,line=15,size=15})
 if not Open('F6') then return end
 local g=Guide()
 local function Rows(tag)
  local root,shown=L.Rect(g,g),{}
  for _,c in ipairs(g.children) do
   if c.kind=='Button' and c:IsShown() then shown[#shown+1]={c,L.Rect(c,g)} end
  end
  for i=1,#shown do
   C.expect(L.Inside(shown[i][2],root),tag..': inside the coach: '..V.Plain(shown[i][1]:GetText() or ''),L.Text(shown[i][2]))
   for j=i+1,#shown do
    C.expect(L.Apart(shown[i][2],shown[j][2]),tag..': no overlap: '..V.Plain(shown[i][1]:GetText() or '')
     ..' / '..V.Plain(shown[j][1]:GetText() or ''))
   end
  end
 end
 Rows('Welcome')
 Start('Just look around')
 C.setup(Step()=='manual','F6: fixture: the preview step')
 local cards=Nexus.UserText.Guide.sim.cards
 local original=cards[1].desc
 cards[1].desc=original..' - Wunschliste \195\156ber-Gr\195\182\195\159e \226\128\148 \240\159\148\165 mit sehr langem lokalisiertem Text'
 Nexus.GuidedSetupUI.Render()
 Rows('long localized preview')
 cards[1].desc=original
 Press(Btn('Checklist v'))
 Rows('open checklist')
end)

-- Every shown button of the coach: inside it and pairwise apart (F6's check).
local function Laid(tag,g)
 local root,shown=L.Rect(g,g),{}
 for _,c in ipairs(g.children) do
  if c.kind=='Button' and c:IsShown() then shown[#shown+1]={c,L.Rect(c,g)} end
 end
 for i=1,#shown do
  C.expect(L.Inside(shown[i][2],root),tag..': inside the coach: '..V.Plain(shown[i][1]:GetText() or ''),L.Text(shown[i][2]))
  for j=i+1,#shown do
   C.expect(L.Apart(shown[i][2],shown[j][2]),tag..': no overlap: '..V.Plain(shown[i][1]:GetText() or '')
    ..' / '..V.Plain(shown[j][1]:GetText() or ''))
  end
 end
 return shown
end

-- F7: the design's desktop window. The visible UI size is a harness value
-- (UIParent's size); native screen sizes, UI scale and the real-client
-- wide/compact comparison are NOT RUN.
C.scenario('F7 a wide screen shows the design desktop window: side checklist, step card beside it, Help as a side panel',function()
 Boot()
 local uiW,uiH=UIParent:GetWidth(),UIParent:GetHeight()
 UIParent:SetSize(1400,900)
 local before=Effects()
 if not Open('F7') then UIParent:SetSize(uiW,uiH);return end
 Start('I already have')
 local g=Guide()
 C.expect(g:GetWidth()==900,'F7: the desktop window is 900 px wide',g:GetWidth())
 C.expect(Btn('Checklist v')==nil and Btn('Checklist ^')==nil,'F7: no collapsible checklist: the checklist is always shown')
 local nav,content=0,0
 for _,c in ipairs(g.children) do
  if c.kind=='Button' and c:IsShown() then
   local r=L.Rect(c,g)
   local t=V.Plain(c:GetText() or '')
   if r[3]<=208 and (t:find('Choose a Wishlist',1,true) or t:find('Pick the Saved Build',1,true) or t:find('Finish',1,true)) then nav=nav+1 end
   if r[1]>=208 and t:find('W-Free',1,true) then content=content+1 end
  end
 end
 C.expect(nav>=3,'F7: the step list is the side navigation at the left',nav)
 C.expect(content==1,'F7: the step card (its Wishlist choices) sits beside it',content)
 C.expect(Text():find('CHECKLIST',1,true)~=nil and Text():find('Choose a Wishlist',1,true)~=nil,'F7: the navigation is titled and lists the steps',Text())
 local nb=Opt('Pick the Saved Build')
 if nb then Press(nb) end
 C.expect(Step()=='target','F7: a side navigation row moves to its step')
 Press(Btn('Back'))
 Laid('F7',g)
 Press(Btn('Help'))
 local about
 for _,fs in ipairs(Nexus.GuidedSetupUI.TextRegions()) do
  if V.Plain(fs:GetText() or ''):find('About:',1,true) then about=L.Rect(fs,g) end
 end
 C.expect(about~=nil and about[1]>=900-16-232,'F7: Help opens as the side panel at the right',about and L.Text(about))
 Laid('F7 help',g)
 if _G.NexusGuidedSetupEscape then NexusGuidedSetupEscape:Hide() end
 C.expect(Shown() and not Text():find('About:',1,true),'F7: Escape closes the Help side panel first')
 L.UseFont({name='125%',char=8.75,line=15,size=15})
 Nexus.GuidedSetupUI.Render()
 C.expect(g:GetWidth()==900,'F7: at 125% text a 1400 px UI keeps the desktop window')
 for _,fs in ipairs(Nexus.GuidedSetupUI.TextRegions()) do
  local r=L.Rect(fs,g)
  C.expect(L.Inside(r,L.Rect(g,g)) and fs:GetHeight()>=math.min(220,L.Rows(fs:GetText(),fs:GetWidth(),8.75)*15),
   'F7: a text block at 125% is inside and tall enough',L.Text(r))
 end
 Laid('F7 125%',g)
 UIParent:SetSize(1000,900)
 Nexus.GuidedSetupUI.Render()
 C.expect(g:GetWidth()==420,'F7: at 125% text a 1000 px UI uses the compact window (the design: 1100 px needed)',g:GetWidth())
 L.UseFont(L.MODELS.default)
 UIParent:SetSize(uiW,uiH)
 Nexus.GuidedSetupUI.Render()
 C.expect(g:GetWidth()==420,'F7: a small UI keeps the compact window')
 C.guard(Effects()==before,'F7: both presentations and every move wrote, acted, sent, spent and toggled nothing',Effects())
end)

C.scenario('F8 the compact window at 125% text with 35% longer localized labels: nothing cut, nothing overlaps',function()
 Boot()
 local T=Nexus.UserText.Guide
 local keep={title=T.title,labels=T.labels,buttons=T.buttons,kicker=T.kicker}
 local function Long(s) return s..' '..string.rep('x',math.ceil(#s*0.35)) end
 T.title='Nexus-Einrichtung mit Schritt-f\195\188r-Schritt-Anleitung'
 local labels,buttons={},{}
 for k,v in pairs(keep.labels) do labels[k]=Long(v) end
 for k,v in pairs(keep.buttons) do buttons[k]=v end
 for _,k in ipairs({'back','skip','next','help','checklistShow','checklistHide'}) do buttons[k]=Long(keep.buttons[k]) end
 T.labels,T.buttons=labels,buttons
 L.UseFont({name='125%',char=8.75,line=15,size=15})
 local ok,err=pcall(function()
  Nexus.GuidedSetupUI.Show()
  local g=Guide()
  if not C.setup(Shown(),'F8: fixture: the coach is shown') then return end
  Press(Opt('I already have'));Press(Btn(buttons.next))
  C.setup(Step()=='wishlist','F8: fixture: the Wishlist step')
  C.expect(g:GetWidth()==420,'F8: the compact 420 px window',g:GetWidth())
  local shown=Laid('F8',g)
  for _,pair in ipairs(shown) do
   local label=V.Plain(pair[1]:GetText() or '')
   C.expect(pair[1]:GetWidth()>=L.Length(label)*8.75,'F8: the whole label fits its button: '..label,pair[1]:GetWidth())
  end
  local title,char,line=L.Rect(g.title,g),L.Rect(g.char,g),L.Rect(g.headLine,g)
  C.expect(g.title:GetHeight()>=L.Rows(g.title:GetText(),g.title:GetWidth(),8.75)*15 and title[4]<=char[2]
   and char[4]<=line[2],'F8: the wrapped title and character line sit above the header line',L.Text(title)..' '..L.Text(char))
  local texts=Nexus.GuidedSetupUI.TextRegions()
  for i,fs in ipairs(texts) do
   local r=L.Rect(fs,g)
   C.expect(r[2]>=line[2] and fs:GetHeight()>=math.min(220,L.Rows(fs:GetText(),fs:GetWidth(),8.75)*15),
    'F8: a text block is below the header and tall enough',L.Text(r))
   for j=i+1,#texts do
    C.expect(L.Apart(r,L.Rect(texts[j],g)),'F8: no two text blocks overlap: '..V.Plain(fs:GetText() or ''):sub(1,24)
     ..' / '..V.Plain(texts[j]:GetText() or ''):sub(1,24))
   end
  end
  Press(Btn(buttons.skip))
  C.expect(Step()=='target','F8: the long Skip label still moves on')
  Laid('F8 target',g)
 end)
 T.title,T.labels,T.buttons=keep.title,keep.labels,keep.buttons
 L.UseFont(L.MODELS.default)
 C.setup(ok,'F8: fixture: the scenario ran',err)
end)

-- F9: full Help is the dense reference window. The coach steps aside for it
-- instead of sitting under it (the step in progress stays readable), and
-- returns at the same step one frame after Help closes; a route that Help
-- opens itself takes Help's place instead. One client frame (NextFrame)
-- stands in for the next frame. Only its sends by frames already running
-- before Help opened, outside the coach, Help, checklist and editor, of a
-- kind already sent before, are left to the background; a send by the
-- coach's return or any frame of the flow counts against the flow, and so
-- does every send of a click (clicks run outside any frame). Work the flow
-- might hand to a background frame is not separated by this. Native Escape
-- dispatch order is NOT RUN.
C.scenario('F9 full Help replaces the coach while open; closing it returns the same step; a Help route takes over',function()
 Boot()
 if not Open('F9') then return end
 Start('I already have')
 C.setup(Step()=='wishlist','F9: fixture: the Wishlist step',Step())
 local quiet,sent,seen=Quiet(),#H.sent,rawget(NexusDB,'hasSeenQuickStart')
 local known,tally=Known(),Tally()
 local function Frame() NextFrame(known,tally) end
 Press(Btn('Help'))
 -- The design's aside names full Help as what /nexus tutorial opens; that
 -- command opens Help again (core/MainCommands.lua), never the coach.
 C.expect(Text():find('in place of this guide',1,true)~=nil and Text():find('/nexus tutorial',1,true)~=nil,
  'F9: the help card says full Help replaces the guide and names /nexus tutorial, which opens that Help',Text())
 Press(Btn('Open full Help'))
 C.expect(_G.NexusHelpWindow~=nil and NexusHelpWindow:IsShown() and not Shown(),'F9: full Help opens in place of the coach, not over it')
 C.expect(not NexusGuidedSetupEscape:IsShown() and rawget(NexusDB,'hasSeenQuickStart')==seen,
  'F9: stepping aside takes no Escape and records no dismissal')
 NexusHelpWindow:Hide() -- Close or Escape
 C.expect(not Shown(),'F9: the coach does not return inside the same Escape pass')
 Frame()
 C.expect(Shown() and Step()=='wishlist' and Text():find('About:',1,true)==nil,
  'F9: on the next frame the coach is back at the same step, its help card closed',Text())
 C.guard(tally.returned=='flow','F9: the coach came back in a frame the attribution counts as the flow\'s own',tostring(tally.returned))
 Press(Btn('Help'));Press(Btn('Open full Help'))
 local checklist
 for _,c in ipairs(NexusHelpWindow.children) do
  if c.kind=='Button' and c:GetText()=='Setup checklist' then checklist=c end
 end
 if C.setup(checklist~=nil and not Shown(),'F9: fixture: full Help again, with its Setup checklist route') then checklist:Click() end
 Frame()
 C.expect(_G.NexusSetupChecklist~=nil and NexusSetupChecklist:IsShown() and not Shown(),
  'F9: a window opened from Help is not covered by the coach coming back')
 if _G.NexusSetupChecklist then NexusSetupChecklist:Hide() end
 Nexus.Help.Show('start')
 local setup
 for _,c in ipairs(NexusHelpWindow.children) do
  if c.kind=='Button' and c:GetText()=='Setup / Welcome' then setup=c end
 end
 if setup then setup:Click() end
 Frame()
 C.expect(Shown() and Step()=='wishlist' and not NexusHelpWindow:IsShown(),'F9: Help Setup / Welcome resumes the coach at its step')
 C.guard(Quiet()==quiet and tally.flow==0 and #H.sent-tally.background==sent and rawget(NexusDB,'hasSeenQuickStart')==seen,
  'F9: Help, its routes and the return wrote, acted, sent, spent, toggled and recorded nothing',Quiet()..' '..Tallied(tally,sent))
 C.guard(#tally.unknown==0,'F9: every send left to the background is of a kind the session sent before Help opened',
  table.concat(tally.unknown,','))
end)

-- F10: the two asynchronous ways a coach that stepped aside could come back,
-- each while full Help is open in its place: a save or assignment receipt
-- (U.OnChange) and the Wishlist Editor's close hook, which the coach's first
-- editor route installs and which outlasts that route (U.WatchEditor). Neither
-- brings the coach over Help; Help's own Close brings it back one frame
-- later with the result read afresh, and the editor's own return still works.
-- The assignment receipt comes from the real Echo Journal chooser (one
-- explicit player choice, the only write); the save receipt through the seam
-- the editor's save site calls (core/GuidedSetup.lua G.Note), with no write.
-- Native NOT RUN.
C.scenario('F10 a receipt or an editor closing while full Help is open does not bring the coach over Help',function()
 Boot()
 if not Open('F10') then return end
 Start('I already have')
 if not C.setup(Step()=='wishlist','F10: fixture: the Wishlist step',Step()) then return end
 local G=Nexus.GuidedSetup
 local quiet,sent,seen=Quiet(),#H.sent,rawget(NexusDB,'hasSeenQuickStart')
 local known,tally=Known(),Tally()
 local function Help() return _G.NexusHelpWindow~=nil and NexusHelpWindow:IsShown() end
 local function FullHelp(tag)
  Press(Btn('Help'));Press(Btn('Open full Help'))
  return C.setup(Help() and not Shown() and Guide().waitingKind=='help',tag..': fixture: full Help is open in place of the coach')
 end
 Press(Btn('Start an empty Wishlist'))
 if not C.setup(not Shown() and _G.NexusEditorFrame~=nil and NexusEditorFrame:IsShown(),
  'F10: fixture: the coach stepped aside for the real Wishlist Editor') then return end
 NexusEditorFrame:Hide() -- closed without a save
 C.guard(Shown() and Step()=='wishlist' and G.State().awaitSave==nil,
  'F10: closing the unsaved editor still returns the coach at its step, with no pending save')
 -- The editor stays open while Setup / Welcome resumes the coach; then Help.
 Press(Btn('Start an empty Wishlist'))
 Nexus.GuidedSetupUI.Show()
 if not C.setup(Shown() and NexusEditorFrame:IsShown(),'F10: fixture: the coach resumed beside the open editor') then return end
 if not FullHelp('F10 editor') then return end
 NexusEditorFrame:Hide() -- the player closes the editor while Help is open
 C.expect(not Shown() and Help(),'F10: closing the editor while full Help is open does not bring the coach over Help')
 NexusHelpWindow:Hide()
 NextFrame(known,tally)
 C.expect(Shown() and Step()=='wishlist','F10: closing Help then brings the coach back at its step',Step())
 C.guard(Quiet()==quiet and tally.flow==0 and #H.sent-tally.background==sent and rawget(NexusDB,'hasSeenQuickStart')==seen,
  'F10: the editor routes, Help and the return wrote, acted, sent, spent, toggled and recorded nothing',Quiet()..' '..Tallied(tally,sent))
 Press(Opt('W-Free'));Press(Btn('Continue'));Press(Opt('Fire PvE'));Press(Btn('Continue'))
 if not C.setup(Step()=='assign','F10: fixture: the Assign step',Step()) then return end
 Press(Btn('Open the Wishlist chooser'))
 if not C.setup(not Shown() and Row('W-Free')~=nil,'F10: fixture: the coach stepped aside for the real chooser, which lists W-Free') then return end
 Nexus.GuidedSetupUI.Show()
 if not C.setup(Shown() and G.AssignStatus().state=='pending' and Row('W-Free')~=nil,
  'F10: fixture: the coach resumed beside the open chooser; its request waits',G.AssignStatus().state) then return end
 if not FullHelp('F10 receipt') then return end
 local row=Row('W-Free')
 if not C.setup(row~=nil,'F10: fixture: the chooser still lists W-Free under Help') then return end
 row.nameButton:Click()
 C.guard(writes.SetLoadoutWishlist==1 and Writes()==1,'F10: the explicit chooser choice makes exactly one assignment write',Writes())
 C.expect(not Shown() and Help(),'F10: its assignment receipt does not bring the coach over Help')
 G.Note('save',{kind='kept',name='W-Free'})
 C.expect(not Shown() and Help(),'F10: nor does a save receipt')
 NexusHelpWindow:Hide()
 NextFrame(known,tally)
 C.expect(Shown() and Step()=='assign' and Text():find('Nexus confirmed it',1,true)~=nil and On(Btn('Continue')),
  'F10: closing Help brings the coach back with the assignment read back afresh',Text())
 C.guard(Writes()==1 and spends==0 and not Auto() and tally.flow==0 and rawget(NexusDB,'hasSeenQuickStart')==seen,
  'F10: besides that one choice nothing was written, spent, toggled or recorded, and no frame of the flow sent',Quiet()..' '..Tallied(tally,sent))
end)

-- F11: the design's footer (ui/GuidedSetup.lua file header): Continue the one
-- filled action with a thickened label, Skip for now underlined text with no
-- fill or edge, Back the themed secondary button; in the compact 420 px
-- window at 125% text, also with 35% longer labels. Colours are read from the
-- paint calls of the two drawn buttons; the values are the design's oklch
-- colours as converted in ui/GuidedSetup.lua FOOT. Native pixels, the faux
-- bold and the underline against real glyphs are NOT RUN.
local DESIGN={amber={0.8,0.45,0.16},gold={0.91,0.63,0.3},ink={0.06,0.04,0.03},
 waitFill={0.06,0.04,0.03},waitEdge={0.21,0.17,0.15},waitInk={0.47,0.44,0.42},link={0.77,0.74,0.71}}
C.scenario('F11 the footer: Continue filled, Skip for now underlined text, Back secondary; 420 px, 125%, long labels',function()
 Boot()
 local T=Nexus.UserText.Guide
 local keep=T.buttons
 L.UseFont({name='125%',char=8.75,line=15,size=15})
 local ok,err=pcall(function()
  if not Open('F11') then return end
  Start('I already have')
  local g=Guide()
  if not C.setup(Step()=='wishlist' and g:GetWidth()==420,'F11: fixture: the Wishlist step in the compact window',g:GetWidth()) then return end
  local before=Effects()
  local nxt,skip,back=g.next,g.skip,g.back
  local function Spy(r) local f=function(self,...) self.drawn={...} end;r.SetVertexColor=f;r.SetTextColor=f end
  Spy(nxt.label);Spy(skip.label)
  if nxt.fill then Spy(nxt.fill) end
  for _,e in ipairs(nxt.edges or {}) do Spy(e) end
  nxt.label.SetShadowOffset=function(self,x,y) self.shadow={x,y} end
  Nexus.GuidedSetupUI.Render()
  local function Is(r,c)
   local d=r and r.drawn
   return d~=nil and math.abs(d[1]-c[1])<1e-6 and math.abs(d[2]-c[2])<1e-6 and math.abs(d[3]-c[3])<1e-6
  end
  local function Edges(c)
   for _,e in ipairs(nxt.edges or {}) do if not Is(e,c) then return false end end
   return #(nxt.edges or {})==4
  end
  C.expect(nxt.look=='primary' and nxt._nexusThemeExempt==true and not nxt._nexusDarkStyled,
   'F11: Continue is drawn by the coach, outside the Theme')
  C.expect(not On(nxt) and nxt.painted=='waiting' and Is(nxt.fill,DESIGN.waitFill) and Edges(DESIGN.waitEdge)
   and Is(nxt.label,DESIGN.waitInk),'F11: a waiting Continue has the design\'s dark fill, grey edge and grey label',nxt.painted)
  C.expect(skip:IsShown() and skip.look=='link' and skip.fill==nil and skip.edges==nil and skip._nexusThemeExempt==true
   and not skip._nexusDarkStyled and skip.underline and skip.underline:IsShown() and Is(skip.label,DESIGN.link),
   'F11: Skip for now is underlined text with no fill or edge')
  -- This harness's buttons have no font string, so the Theme styles none of
  -- them here (ui_theme_* tests cover its painting); what the coach decides
  -- is which buttons it leaves to the Theme.
  C.expect(back:IsShown() and back.look==nil and not back._nexusThemeExempt and g.help.look==nil and not g.help._nexusThemeExempt,
   'F11: Back is left to the Theme as the secondary button, like Help')
  local rowW=420-32
  local function Footer(tag)
   Laid(tag,g)
   for _,b in ipairs({nxt,skip,back}) do
    if b:IsShown() then
     local label=V.Plain(b:GetText() or '')
     C.expect(b:GetWidth()>=math.min(rowW,L.Length(label)*8.75+24),tag..': the whole label fits: '..label,b:GetWidth())
    end
   end
   if nxt:IsShown() then
    C.expect(nxt:GetWidth()>=math.min(rowW,L.Length(V.Plain(nxt:GetText() or ''))*8.75+34),
     tag..': Continue keeps its wider side padding',nxt:GetWidth())
   end
   if skip:IsShown() then
    local u,r=L.Rect(skip.underline,g),L.Rect(skip,g)
    local text=L.Length(V.Plain(skip:GetText() or ''))*8.75
    C.expect(L.Inside(u,r) and u[3]-u[1]>=math.min(text,skip:GetWidth()-8) and u[4]-u[2]==1,
     tag..': the underline spans the Skip text inside its button',L.Text(u)..' in '..L.Text(r))
   end
  end
  Footer('F11')
  Press(Opt('W-Free'))
  C.expect(On(nxt) and nxt.painted=='primary' and Is(nxt.fill,DESIGN.amber) and Edges(DESIGN.gold) and Is(nxt.label,DESIGN.ink)
   and nxt.label.shadow~=nil and nxt.label.shadow[1]==1 and nxt.label.shadow[2]==0,
   'F11: a usable Continue is the filled amber action with a dark, thickened label',nxt.painted)
  Footer('F11 ready')
  Press(Btn('Continue'))
  if not C.setup(Step()=='target' and skip:IsShown(),'F11: fixture: the Saved Build step offers Skip for now',Step()) then return end
  local function Long(s) return s..' '..string.rep('x',math.ceil(#s*0.35)) end
  local buttons={}
  for k,v in pairs(keep) do buttons[k]=v end
  for _,k in ipairs({'back','skip','next'}) do buttons[k]=Long(keep[k]) end
  T.buttons=buttons
  Nexus.GuidedSetupUI.Render()
  Footer('F11 long')
  Press(Opt('Fire PvE'))
  C.expect(On(nxt) and nxt.painted=='primary','F11: with a long label a usable Continue is still the filled action',nxt.painted)
  Footer('F11 long ready')
  C.guard(Effects()==before,'F11: the footer looks and every move wrote, acted, sent, spent and toggled nothing',Effects())
 end)
 T.buttons=keep
 L.UseFont(L.MODELS.default)
 C.setup(ok,'F11: fixture: the scenario ran',err)
end)

-- F12: a step card's one main action is the design's filled action (the
-- same fill, edge and thickened dark label as a usable Continue, drawn
-- outside the Theme); its other actions stay the themed secondary button.
-- Through the replace card, the Assign card ready, pending (a request armed,
-- nothing chosen), confirmed, with no answer and after a later change, and
-- the Auto card; in the compact 420 px window at 125% text with 35% longer
-- labels. While a step action is filled, Continue waits. Colours are read
-- from the paint calls (as F11). An unreadable target before any assignment
-- is the prerequisite card; the same failing read back after the assignment
-- is the design's No answer card, whose one action (as on the stale card) is
-- Check again: no chooser, no new request, and a later fresh read back
-- confirms it. The effect guards are unchanged: only the one explicit
-- chooser choice writes. Native pixels are NOT RUN.
C.scenario('F12 step actions: the main one filled like Continue, the others secondary; pending, no answer, stale; 420 px, 125%, long labels',function()
 Boot()
 C.setup(A.SetLoadoutWishlist(2,106)==true,'F12: fixture: Fire PvE follows W-Six');writes.SetLoadoutWishlist=0
 local T=Nexus.UserText.Guide
 local keep=T.buttons
 local function Long(s) return s..' '..string.rep('x',math.ceil(#s*0.35)) end
 local buttons={}
 for k,v in pairs(keep) do buttons[k]=v end
 for _,k in ipairs({'retry','replace','cancel','open','openAgain','check','keep','review'}) do buttons[k]=Long(keep[k]) end
 L.UseFont({name='125%',char=8.75,line=15,size=15})
 local ok,err=pcall(function()
  local before=Effects()
  if not Open('F12') then return end
  T.buttons=buttons
  Start('I already have')
  local g,G=Guide(),Nexus.GuidedSetup
  if not C.setup(Step()=='wishlist' and g:GetWidth()==420,'F12: fixture: the Wishlist step in the compact window',g:GetWidth()) then return end
  local nxt=g.next
  local OWN={[g.next]=true,[g.skip]=true,[g.back]=true,[g.help]=true,[g.close]=true,[g.checklist]=true}
  -- The shown step actions: not the header, footer or a choice row.
  local function Actions()
   local list={}
   for _,c in ipairs(g.children) do
    if c.kind=='Button' and c:IsShown() and not OWN[c] and c.desc==nil then list[#list+1]=c end
   end
   return list
  end
  local function Spy(r) local f=function(self,...) self.drawn={...} end;r.SetVertexColor=f;r.SetTextColor=f end
  local function Is(r,c)
   local d=r and r.drawn
   return d~=nil and math.abs(d[1]-c[1])<1e-6 and math.abs(d[2]-c[2])<1e-6 and math.abs(d[3]-c[3])<1e-6
  end
  local function Edges(b,c)
   for _,e in ipairs(b.edges or {}) do if not Is(e,c) then return false end end
   return #(b.edges or {})==4
  end
  -- Spies on every drawn step action made so far, then a render to read.
  local function Paint()
   for _,c in ipairs(g.children) do
    if c.kind=='Button' and c.look=='primary' and not OWN[c] and not c.spied then
     c.spied=true;Spy(c.label);Spy(c.fill);for _,e in ipairs(c.edges) do Spy(e) end
     c.label.SetShadowOffset=function(self,x,y) self.shadow={x,y} end
    end
   end
   Nexus.GuidedSetupUI.Render()
  end
  local function Card(tag,main,other)
   Paint()
   local p,s,filled=Btn(main),other and Btn(other),0
   C.expect(p~=nil and p.look=='primary' and p._nexusThemeExempt==true and not p._nexusDarkStyled and On(p) and p.painted=='primary'
    and Is(p.fill,DESIGN.amber) and Edges(p,DESIGN.gold) and Is(p.label,DESIGN.ink)
    and p.label.shadow~=nil and p.label.shadow[1]==1 and p.label.shadow[2]==0,
    tag..': '..main..' is the filled amber action with a dark, thickened label',p and p.painted)
   if other then
    C.expect(s~=nil and s.look==nil and not s._nexusThemeExempt and On(s),tag..': '..other..' is left to the Theme as the secondary button')
   end
   for _,c in ipairs(Actions()) do
    local label=V.Plain(c:GetText() or '')
    if c.look=='primary' then filled=filled+1 end
    C.expect(c:GetWidth()>=math.min(420-32-16,L.Length(label)*8.75+24) and c.full==c:GetText(),
     tag..': the label fits its button or is whole on hover: '..label,c:GetWidth())
   end
   C.expect(filled==1,tag..': the card has one filled action',filled)
   C.expect(not On(nxt) and nxt.painted=='waiting',tag..': while a step action is filled, Continue waits',nxt.painted)
   Laid(tag,g)
  end
  -- Every text block of the card inside the coach and tall enough (F5's check).
  local function TextsFit(tag)
   local root=L.Rect(g,g)
   for _,fs in ipairs(Nexus.GuidedSetupUI.TextRegions()) do
    local r=L.Rect(fs,g)
    C.expect(L.Inside(r,root) and fs:GetHeight()>=math.min(220,L.Rows(fs:GetText(),fs:GetWidth(),8.75)*15),
     tag..': a text block is inside and tall enough',L.Text(r))
   end
  end
  local UA,real=T.assign,A.GetLoadoutWishlistState
  local function Unreadable() A.GetLoadoutWishlistState=function() error('synthetic readback failure') end end
  Press(Opt('W-Free'));Press(Btn('Continue'));Press(Opt('Fire PvE'))
  if not C.setup(Step()=='target' and G.TargetFacts() and G.TargetFacts().replaces,'F12: fixture: the replace card for Fire PvE') then return end
  Card('F12 replace',buttons.replace,buttons.cancel)
  Press(Btn(buttons.replace))
  C.expect(On(nxt) and nxt.painted=='primary' and #Actions()==0,'F12: an accepted replacement leaves Continue the one filled action')
  Press(Btn('Continue'))
  if not C.setup(Step()=='assign' and G.AssignStatus().state=='ready','F12: fixture: the Assign step is ready',G.AssignStatus().state) then return end
  Card('F12 ready',buttons.open)
  -- Before any assignment an unreadable target is not ready: the
  -- prerequisite card, never a No answer result, and no chooser.
  Unreadable()
  Nexus.GuidedSetupUI.Render()
  C.expect(G.AssignStatus().state=='ready' and not G.TargetFacts().ready and Text():find(UA.missing,1,true)~=nil
   and Text():find(UA.unavailable,1,true)==nil and Btn(buttons.open)==nil and Btn(buttons.check)==nil
   and Btn(keep.goTarget)~=nil and not On(nxt),
   'F12: before any assignment an unreadable target is the prerequisite card, not a No answer result',Text())
  Laid('F12 unreadable target',g)
  A.GetLoadoutWishlistState=real
  Nexus.GuidedSetupUI.Render()
  if not C.setup(G.AssignStatus().state=='ready' and Btn(buttons.open)~=nil,'F12: fixture: read back again, the Assign step is ready',
   G.AssignStatus().state) then return end
  Press(Btn(buttons.open))
  if not C.setup(not Shown() and Row('W-Free')~=nil,'F12: fixture: the coach stepped aside for the real chooser') then return end
  Nexus.GuidedSetupUI.Show()
  if not C.setup(Shown() and G.AssignStatus().state=='pending','F12: fixture: the request is pending',G.AssignStatus().state) then return end
  Card('F12 pending',buttons.openAgain,buttons.check)
  C.guard(Effects()==before,'F12: the step actions, replace and opening the chooser wrote, acted, sent, spent and toggled nothing',Effects())
  local row=Row('W-Free')
  if not C.setup(row~=nil,'F12: fixture: the chooser still lists W-Free') then return end
  row.nameButton:Click()
  C.guard(writes.SetLoadoutWishlist==1 and Writes()==1,'F12: the explicit chooser choice makes exactly one assignment write',Writes())
  Nexus.GuidedSetupUI.Render()
  C.expect(G.AssignStatus().state=='verified' and #Actions()==0 and On(nxt) and nxt.painted=='primary',
   'F12: confirmed, the card has no action and Continue is the filled one',G.AssignStatus().state)
  Unreadable()
  Nexus.GuidedSetupUI.Render()
  if C.setup(G.AssignStatus().state=='unknown','F12: fixture: a failing read back is no answer',G.AssignStatus().state) then
   Card('F12 no answer',buttons.check)
   C.expect(Text():find(UA.unavailable,1,true)~=nil and Text():find(UA.unavailableBody,1,true)~=nil
    and Text():find(UA.missing,1,true)==nil and Text():find(T.target.cUnknown,1,true)~=nil,
    'F12: the unknown result of the assignment is the design\'s No answer card, not the prerequisite card',Text())
   C.expect(#Actions()==1 and Btn(buttons.openAgain)==nil and Btn(buttons.open)==nil and Btn(keep.goTarget)==nil,
    'F12: No answer offers only Check again: no chooser and no link back',#Actions())
   C.expect(g.skip:IsShown() and Text():find(T.gate.assignUnknown,1,true)~=nil,
    'F12: Skip for now and the No answer gate hint stay offered',Text())
   TextsFit('F12 no answer')
   local req=G.State().request
   local armed,why=G.ArmAssign()
   C.guard(armed==false and why=='notReady' and G.State().request==req,
    'F12: while the result is unknown the target takes no new request',tostring(why))
   Press(Btn(buttons.check))
   C.expect(G.AssignStatus().state=='unknown' and G.State().request==req and not On(nxt) and Btn(buttons.check)~=nil,
    'F12: Check again reads again; still no answer, nothing is assumed or armed',G.AssignStatus().state)
  end
  A.GetLoadoutWishlistState=real
  Nexus.GuidedSetupUI.Render()
  C.expect(G.AssignStatus().state=='verified' and On(nxt),'F12: a later fresh read back confirms the same assignment',
   G.AssignStatus().state)
  C.guard(writes.SetLoadoutWishlist==1 and Writes()==1,'F12: no answer and Check again wrote nothing more',Writes())
  C.setup(A.ClearLoadoutWishlist(2)==true,'F12: fixture: another route unassigns Fire PvE')
  before=Effects()
  Nexus.GuidedSetupUI.Render()
  local st=G.AssignStatus().state
  if C.setup(st=='stale' or st=='changed','F12: fixture: the earlier check no longer counts',st) then
   Card('F12 stale',buttons.check)
   C.expect(Text():find(UA.stale,1,true)~=nil and #Actions()==1 and Btn(buttons.openAgain)==nil and Btn(buttons.open)==nil,
    'F12: the stale card\'s one action is the filled Check again, with no chooser',Text())
   TextsFit('F12 stale')
  end
  Press(Btn('Checklist v'));Press(Opt('Auto (optional)'))
  if not C.setup(Step()=='auto' and not Auto(),'F12: fixture: the Auto step with Auto OFF',Step()) then return end
  local kept=buttons.keep:format('OFF')
  Card('F12 auto',kept,buttons.review)
  Press(Btn(kept))
  C.expect(Step()=='summary' and G.State().autoKept=='off','F12: the filled Keep Auto OFF still keeps it and moves on',Step())
  C.guard(Effects()==before and not Auto(),'F12: after the fixture change the step actions wrote, acted, sent, spent and toggled nothing',Effects())
 end)
 T.buttons=keep
 L.UseFont(L.MODELS.default)
 C.setup(ok,'F12: fixture: the scenario ran',err)
end)

-- F13: the original guided design's Wishlist step (its paste field, Check
-- code and inline accepted / rejected / unfinished outcome) over the editor's
-- real read-only check (WishlistEditor.CheckImportCode); the HTML's Sample
-- buttons are demo controls and are not offered. Every outcome, the
-- separate Open it as a draft, Continue's gate, Skip, Back, close, reopen,
-- a listed choice and replay, in the compact 420 px window at 125% text
-- with a long UTF-8 code name. guided_first_entry E10-E13 follow the draft
-- action into the editor's naming dialog and draft. Effects as everywhere:
-- no adapter write, game action, send, spend or Auto change, and no guide
-- receipt from a check. Native text entry and pixels are NOT RUN.
C.scenario('F13 the Wishlist step checks a pasted code in place; outcomes inline, the draft a separate action; 420 px, 125%',function()
 Boot()
 local T=Nexus.UserText.Guide
 L.UseFont({name='125%',char=8.75,line=15,size=15})
 local ok,err=pcall(function()
  if not Open('F13') then return end
  Start('New to Nexus')
  local g,G=Guide(),Nexus.GuidedSetup
  if not C.setup(Step()=='wishlist' and g:GetWidth()==420,'F13: fixture: the Wishlist step in the compact window',g:GetWidth()) then return end
  local before,receipts=Effects(),#G.Receipts()
  local box=g.importBox
  C.expect(box~=nil and not box:IsShown(),'F13: the paste field stays closed until its choice is made')
  H.popup=nil
  Press(Btn(T.wishlist.importTitle))
  C.expect(Shown() and box:IsShown() and Btn('Check code')~=nil and Btn('Open it as a draft')==nil and H.popup==nil,
   'F13: choosing Paste a Wishlist code opens the field and Check code in the step, with no popup')
  C.expect(Text():find(T.wishlist.importLabel,1,true)~=nil and box.maxLetters==Nexus.WishlistEditor.IMPORT_MAX_LETTERS,
   'F13: the field is labelled as the design does and holds the import dialog\'s own limit',tostring(box.maxLetters))
  C.expect(not On(Btn('Continue')) and Text():find(T.gate.wishlistImport,1,true)~=nil and Btn('Skip for now')~=nil,
   'F13: Continue waits on the code; Skip for now stays offered',Text())
  -- Every text block, the field and every button at 125%: inside, tall
  -- enough (or capped with hover text), and apart from one another. The
  -- coach grows to hold an outcome, so its bounds are read for each render
  -- (as Laid does), never kept from an earlier one.
  local function Fits(tag)
   local root=L.Rect(g,g)
   for _,fs in ipairs(Nexus.GuidedSetupUI.TextRegions()) do
    local r=L.Rect(fs,g)
    C.expect(L.Inside(r,root) and fs:GetHeight()>=math.min(220,L.Rows(fs:GetText(),fs:GetWidth(),8.75)*15),
     tag..': a text block is inside and tall enough',L.Text(r))
   end
   local shown=Laid(tag,g)
   local field=L.Rect(box,g)
   C.expect(L.Inside(field,root),tag..': the paste field is inside the coach',L.Text(field))
   for _,pair in ipairs(shown) do
    C.expect(L.Apart(field,pair[2]),tag..': the field overlaps no button: '..V.Plain(pair[1]:GetText() or ''))
   end
  end
  Fits('F13 open')
  Press(Btn('Check code'))
  C.expect(Text():find(T.wishlist.importEmpty,1,true)~=nil and Btn('Open it as a draft')==nil,
   'F13: an empty field is not checked, never accepted or rejected',Text())
  local codec=Nexus.Codec.DecodeEBH1
  box:SetText('EBH1:201175.0.1:MAGE:Reader')
  Nexus.Codec.DecodeEBH1=nil
  Press(Btn('Check code'))
  Nexus.Codec.DecodeEBH1=codec
  C.expect(Text():find(T.wishlist.importUnavailable,1,true)~=nil and Btn('Open it as a draft')==nil,
   'F13: without the code reader the outcome is unknown, never accepted',Text())
  box:SetText('EBH1:201175.0.1')
  Press(Btn('Check code'))
  C.expect(Text():find(T.wishlist.importBad,1,true)~=nil and Text():find(T.wishlist.importBadBody,1,true)~=nil
   and Btn('Open it as a draft')==nil and not On(Btn('Continue')),'F13: a cut-off code is refused inline and offers no draft',Text())
  Fits('F13 rejected')
  local code=Nexus.Codec.EncodeEBH1({{spellId=201175,quality=0,stacks=1,locked=false},
   {spellId=201172,quality=0,stacks=2,locked=false}},'MAGE',LONG)
  box:SetText(code)
  C.expect(Text():find(T.wishlist.importBad,1,true)==nil,'F13: a changed code drops the earlier outcome')
  Press(Btn('Check code'))
  local open=Btn('Open it as a draft')
  C.expect(Text():find('Code read: Wunschliste',1,true)~=nil and Text():find('2 Echo entries (3 rolled copies, 0 locked targets)',1,true)~=nil
   and Text():find(T.wishlist.importOkBody,1,true)~=nil,'F13: a valid code reads inline with its name and counts, and says nothing is imported yet',Text())
  C.expect(open~=nil and On(open) and open.look=='primary' and Btn('Check code').look==nil,
   'F13: Open it as a draft is now the filled action; Check code becomes secondary')
  C.expect(not On(Btn('Continue')) and Text():find(T.gate.wishlistChecked,1,true)~=nil,
   'F13: a checked code is not a Wishlist: Continue still waits and says what counts',Text())
  Fits('F13 accepted')
  C.guard(Effects()==before and #G.Receipts()==receipts and G.State().awaitSave==nil and G.State().draft==nil
   and G.State().wishlist==nil and H.popup==nil and not (_G.NexusEditorFrame and NexusEditorFrame:IsShown()),
   'F13: every check read only: no write, action, send, spend, Auto change, receipt, armed save, draft, popup or editor',Effects())
  Press(Btn('Skip for now'))
  C.expect(Step()=='target' and G.State().skipped.wishlist==true and G.State().wishlist==nil,
   'F13: Skip for now moves on as skipped; the checked code is not imported')
  Press(Btn('Back'))
  C.expect(Step()=='wishlist' and box:IsShown() and box:GetText()==code and Btn('Open it as a draft')~=nil,
   'F13: Back returns to the field with the same code and its check')
  Press(Btn('X'))
  Nexus.GuidedSetupUI.Show()
  C.expect(Shown() and Step()=='wishlist' and box:IsShown() and box:GetText()==code,'F13: close and reopen keep the field and its code')
  Press(Opt('W-Free'))
  C.expect(not box:IsShown() and On(Btn('Continue')) and Text():find('Chosen: W-Free',1,true)~=nil,
   'F13: a listed Wishlist closes the paste field and is the one choice',Text())
  Press(Btn(T.wishlist.importTitle))
  C.expect(box:IsShown() and not On(Btn('Continue')) and Text():find('Chosen: W-Free',1,true)==nil,
   'F13: back on the paste field the listed choice is set aside; Continue waits on the code again',Text())
  Nexus.GuidedSetupUI.Replay()
  Start('New to Nexus')
  C.expect(Step()=='wishlist' and not box:IsShown() and Btn('Check code')==nil,'F13: replay starts the step with the field closed')
  Press(Btn(T.wishlist.importTitle))
  C.expect(box:GetText()=='' and Btn('Open it as a draft')==nil,'F13: and with no earlier code or check')
  C.guard(Effects()==before and #G.Receipts()==receipts,'F13: the whole flow wrote, acted, sent, spent, toggled and reported nothing',Effects())
 end)
 L.UseFont(L.MODELS.default)
 C.setup(ok,'F13: fixture: the scenario ran',err)
end)

-- F14: every target the original design offers has a real route, and
-- Continue never leads to an Assign step that can only refuse. The Echo
-- Journal chooser assigns to the active Saved Build only (core TargetOptions
-- journal); a populated Saved Build that is not active, and an empty slot,
-- wait on the player's own step in the game's My Builds page (opened through
-- JournalTab.OpenBuilds(false), the panel's My Builds route, spied here; F15
-- runs the real controller). The spy answers through onSettled as the real
-- one does: seen, or (answer 'unseen') not seen after the last settle. The
-- player's in-game choice and the game's confirmed save are modelled as host
-- slot changes read by the real adapter; Ebonhold's own save popup and its
-- server write are NOT RUN. Also: the first-run target while a Saved Build is
-- active, an already linked Saved Build that is not active, a refused or
-- unconfirmed My Builds route, unreadable slots and a changed character. The
-- guide arms, saves, loads, activates and assigns nothing.
C.scenario('F14 target routes: not active, empty, first-run, already linked, refused, unknown, changed context',function()
 Boot()
 local T,G=Nexus.UserText.Guide,Nexus.GuidedSetup
 local journal=Nexus.JournalTab
 local realOpen,calls,answer=journal.OpenBuilds,{},true
 journal.OpenBuilds=function(chooser,close,settled,...)
  calls[#calls+1]={chooser=chooser,close=close,settled=settled,extra=select('#',...)}
  if answer and type(settled)=='function' then settled(answer==true) end
  return answer~=false
 end
 local function Poll() H.Notify();A.Poll();H.Advance(1) end
 local ok,err=pcall(function()
  if not Open('F14') then return end
  Start('I already have');Press(Opt('W-Free'));Press(Btn('Continue'))
  if not C.setup(Step()=='target' and A.SelectedSavedBuild()==2,'F14: fixture: the target step; Fire PvE is active') then return end
  local quiet=Quiet()
  -- 1. A populated Saved Build that is not active.
  Press(Opt('Slot 1 - One'))
  local f=G.TargetFacts()
  C.expect(f and f.route=='select' and f.ready and not f.canContinue and not G.CanNext() and not On(Btn('Continue')),
   'F14 select: a Saved Build that is not active is chosen but Continue waits',f and tostring(f.route))
  C.expect(Text():find(Nexus.UserText.Guide.target.cSelectHow,1,true)~=nil and Text():find(T.gate.targetSelect,1,true)~=nil
   and Btn('Open My Builds')~=nil and Btn('Open My Builds').look=='primary','F14 select: it says the player makes it active in My Builds, with that one action',Text())
  local armed,why=G.ArmAssign()
  C.guard(armed==false and why=='route' and G.State().request==nil,'F14 select: no request can be armed for it (defence kept)',tostring(why))
  Press(Btn('Open My Builds'))
  C.expect(#calls==1 and calls[1].chooser==false and calls[1].close==nil and type(calls[1].settled)=='function'
   and calls[1].extra==0 and not Shown() and Guide().waitingKind=='builds',
   'F14 select: Open My Builds opens the game page (not the chooser) and the coach steps aside once it is seen',#calls)
  C.guard(Quiet()==quiet and G.State().request==nil,'F14 select: opening My Builds wrote, acted, spent, armed and toggled nothing',Quiet())
  -- The player chooses Saved Build 1 in the game.
  H.perks.serverActiveSlot=1;Poll()
  C.setup(A.SelectedSavedBuild()==1,'F14: fixture: the player made Saved Build 1 active in the game')
  Nexus.GuidedSetupUI.Show()
  f=G.TargetFacts()
  C.expect(Shown() and Step()=='target' and f and f.route=='journal' and f.canContinue and On(Btn('Continue')),
   'F14 select: reopened, the slot is read again and is now the chooser\'s: Continue is offered',Text())
  Press(Btn('Continue'))
  C.expect(Step()=='assign' and Btn('Open the Wishlist chooser')~=nil,'F14 select: the Assign step can do its job')
  Press(Btn('Back'))
  -- 2. An empty slot: the game's own confirmed save comes first.
  Press(Opt('Slot 3 - Empty three'))
  f=G.TargetFacts()
  C.expect(f and f.empty and f.route=='save' and not f.ready and not On(Btn('Continue'))
   and Text():find(T.target.cEmptySave,1,true)~=nil and Text():find(T.gate.targetSave,1,true)~=nil and Btn('Open My Builds')~=nil,
   'F14 empty: an empty slot says to save Echoes into it in My Builds (the game asks first); Continue waits',Text())
  armed,why=G.ArmAssign()
  C.guard(armed==false and why=='empty' and G.State().request==nil,'F14 empty: nothing can be armed for an empty slot',tostring(why))
  Press(Btn('Open My Builds'))
  C.guard(#calls==2 and calls[2].chooser==false and Quiet()==quiet,'F14 empty: the same game page; nothing saved or written by the guide',Quiet())
  -- The player saves current Echoes into slot 3 (the game confirmed it) but
  -- slot 1 stays active: read again, it is a Saved Build that is not active.
  H.perks.serverBuildSlots[3].echoes={{spellId=201172,quality=0,stacks=1}};Poll()
  Nexus.GuidedSetupUI.Show()
  f=G.TargetFacts()
  C.expect(f and not f.empty and f.route=='select' and not On(Btn('Continue')),'F14 empty: after the save, read again, it still waits until it is active',f and tostring(f.route))
  H.perks.serverActiveSlot=3;Poll()
  Nexus.GuidedSetupUI.Render()
  f=G.TargetFacts()
  C.expect(f and f.route=='journal' and f.canContinue and On(Btn('Continue')),'F14 empty: saved and active, it is a ready target',f and tostring(f.route))
  -- 3. The first-run target while a Saved Build is active.
  Press(Opt(T.target.first))
  f=G.TargetFacts()
  C.expect(f and f.route=='first' and not On(Btn('Continue')) and Text():find(T.target.cFirst,1,true)~=nil
   and Btn('Open My Builds')==nil,'F14 first: the first-run target says the chooser does not assign to it now; no game page is offered',Text())
  -- 4. A refused My Builds route.
  Press(Opt('Slot 2 - Fire PvE'))
  C.setup(G.TargetFacts() and G.TargetFacts().route=='select','F14: fixture: Fire PvE is not active now')
  answer=false
  Press(Btn('Open My Builds'))
  C.expect(Shown() and Text():find(T.notes.buildsUnavailable,1,true)~=nil and not Guide().waiting and not On(Btn('Continue')),
   'F14 refused: a page that does not open says so; the coach stays and nothing changes',Text())
  C.guard(Quiet()==quiet,'F14 refused: nothing written, acted, spent or toggled',Quiet())
  -- The game's button was used, but My Builds was not seen after it.
  answer='unseen'
  Press(Btn('Open My Builds'))
  C.expect(#calls==4 and Shown() and Text():find(T.notes.buildsUnconfirmed,1,true)~=nil and not Guide().waiting
   and Text():find(T.notes.buildsUnavailable,1,true)==nil and not On(Btn('Continue')),
   'F14 unconfirmed: a page not seen after the button says so; the coach stays and claims nothing',Text())
  answer=true
  C.guard(Quiet()==quiet,'F14 unconfirmed: nothing written, acted, spent or toggled',Quiet())
  -- 5. Unreadable Saved Builds.
  local slots=A.Slots
  A.Slots=function() error('synthetic slot read failure') end
  Nexus.GuidedSetupUI.Render()
  C.expect(G.TargetOptions()==nil and not On(Btn('Continue')) and Text():find(T.target.unavailable,1,true)~=nil
   and Btn('Open My Builds')==nil,'F14 unknown: unreadable slots offer no route and no Continue',Text())
  A.Slots=slots
  Nexus.GuidedSetupUI.Render()
  -- 6. An already linked Saved Build that is not active: nothing to assign.
  C.setup(A.SetLoadoutWishlist(1,107)==true,'F14: fixture: Saved Build 1 follows W-Free');writes.SetLoadoutWishlist=0
  quiet=Quiet()
  Press(Opt('Slot 1 - One'))
  f=G.TargetFacts()
  C.expect(f and f.already and f.route=='select' and f.canContinue and On(Btn('Continue')),
   'F14 linked: a Saved Build that already follows the Wishlist continues; the Assign step only reads it',f and tostring(f.route))
  Press(Btn('Continue'))
  C.expect(Step()=='assign' and G.AssignStatus().state=='observed','F14 linked: observed, not assigned by the guide',G.AssignStatus().state)
  Press(Btn('Back'))
  -- 7. A changed character clears the choice (never restored).
  local store=Nexus.Store
  local owner=store.CurrentOwnerKey
  store.CurrentOwnerKey=function() return 'synthetic-other@ebonhold' end
  Nexus.GuidedSetupUI.Render()
  C.expect(G.State().target==nil and G.State().notice=='owner' and not On(Btn('Continue')),
   'F14 context: a changed character drops the chosen target',tostring(G.State().notice))
  store.CurrentOwnerKey=owner
  C.guard(Quiet()==quiet and #calls==4,'F14: every route wrote, acted, spent and toggled nothing; My Builds opened only when asked',Quiet()..' calls='..#calls)
 end)
 journal.OpenBuilds=realOpen
 C.setup(ok,'F14: fixture: the scenario ran',err)
end)

-- F15: the real JournalTab.OpenBuilds(false) behind the coach's Open My
-- Builds, against a synthetic Echoes page whose menu-bar button toggles it
-- (a second click closes an open page) and which has two pages: Loadouts
-- (with its stock section title, the page My Builds is read from) and
-- another, selected by the page's own Loadouts tab. Closed, already open, on
-- the other page, not opened by the click, and opened only after the first
-- asynchronous settle (a synthetic C_Timer). The coach steps aside only when
-- My Builds is seen; otherwise it stays and says so. The Wishlist chooser
-- route keeps an open page too. The real client's page, hub navigation and
-- timing are NOT RUN: native visual validation remains necessary.
C.scenario('F15 the real My Builds route never clicks an open page closed; the coach steps aside only once My Builds is seen',function()
 Boot()
 local T=Nexus.UserText.Guide
 local journal,button=_G.ProjectEbonholdEchoJournal,_G.EchoJournalMicroButton
 local loadouts=CreateFrame('Frame',nil,journal)
 loadouts:CreateFontString():SetText('Your loadouts')
 local other=CreateFrame('Frame',nil,journal)
 other:CreateFontString():SetText('Echo collection')
 other:Hide()
 local tab,tabClicks=CreateFrame('Button',nil,journal),0
 tab:SetText('Loadouts')
 tab:SetScript('OnClick',function() tabClicks=tabClicks+1;other:Hide();loadouts:Show() end)
 local clicks,opens=0,'now'
 button:SetScript('OnClick',function()
  clicks=clicks+1
  if journal:IsShown() then journal:Hide() elseif opens=='now' then journal:Show() end
 end)
 local keepTimer,queue=C_Timer,{}
 local ok,err=pcall(function()
  if not Open('F15') then return end
  Start('I already have');Press(Opt('W-Free'));Press(Btn('Continue'));Press(Opt('Slot 1 - One'))
  if not C.setup(Btn('Open My Builds')~=nil and not journal:IsShown(),'F15: fixture: a Saved Build that is not active; the page is closed') then return end
  local quiet=Quiet()
  local function Aside() return not Shown() and Guide().waiting==true and Guide().waitingKind=='builds' end
  -- 1. Closed: the game's button opens it once; My Builds is seen.
  Press(Btn('Open My Builds'))
  C.expect(clicks==1 and journal:IsVisible() and loadouts:IsVisible() and Aside(),
   'F15 closed: one click opens the page; the coach steps aside once My Builds is seen',clicks)
  -- 2. Already open: no click, so the page is not toggled closed.
  Nexus.GuidedSetupUI.Show()
  Press(Btn('Open My Builds'))
  C.expect(clicks==1 and journal:IsVisible() and loadouts:IsVisible() and Aside(),
   'F15 open: an open My Builds is not clicked; it stays open and the coach steps aside',clicks)
  -- 3. Open on another page: its own Loadouts tab, not the toggle.
  other:Show();loadouts:Hide()
  Nexus.GuidedSetupUI.Show()
  Press(Btn('Open My Builds'))
  C.expect(clicks==1 and tabClicks==1 and journal:IsVisible() and loadouts:IsVisible() and Aside(),
   'F15 other page: the Loadouts tab is chosen, the window is not toggled, and the coach steps aside',clicks..'/'..tabClicks)
  -- 4. The click does not bring the page: the coach stays and claims nothing.
  journal:Hide();opens='never'
  Nexus.GuidedSetupUI.Show()
  Press(Btn('Open My Builds'))
  C.expect(clicks==2 and not journal:IsShown() and Shown() and not Guide().waiting
   and Text():find(T.notes.buildsUnconfirmed,1,true)~=nil and Btn('Open My Builds')~=nil,
   'F15 not seen: the coach stays with the unconfirmed note and its route still offered',Text())
  -- 5. The page arrives after the click, before the first settle.
  C_Timer={After=function(delay,fn) queue[#queue+1]={delay,fn} end}
  opens='later'
  Press(Btn('Open My Builds'))
  C_Timer=keepTimer
  -- The Journal's two settles, by their delays (anything else queued runs after).
  local first,last,rest
  for _,q in ipairs(queue) do
   if q[1]==0.10 and not first then first=q[2] elseif q[1]==0.35 and not last then last=q[2] else rest=rest or {};rest[#rest+1]=q[2] end
  end
  if not C.setup(first~=nil and last~=nil,'F15: fixture: the Journal queued its two settles',#queue) then return end
  C.expect(clicks==3 and Shown() and not Guide().waiting,'F15 settle: the coach does not step aside before the page is seen',clicks)
  journal:Show()
  first()
  C.expect(Aside(),'F15 settle: seen at the first settle, the coach steps aside')
  last()
  for _,fn in ipairs(rest or {}) do fn() end
  C.expect(Aside() and clicks==3,'F15 settle: the last settle changes nothing more',clicks)
  -- 6. The Wishlist chooser keeps an open page and still opens.
  C.expect(Nexus.JournalTab.OpenBuilds(true)==true and clicks==3 and journal:IsVisible()
   and _G.NexusWishlistOnlyPicker~=nil and NexusWishlistOnlyPicker:IsShown(),
   'F15 chooser: an open page is not clicked; the Wishlist chooser opens there',clicks)
  NexusWishlistOnlyPicker:Hide()
  C.guard(Quiet()==quiet,'F15: every route wrote, assigned, acted, spent and toggled nothing',Quiet())
 end)
 C_Timer=keepTimer
 C.setup(ok,'F15: fixture: the scenario ran',err)
end)

-- F16: the close/reopen race on the same real route as F15 (the real
-- JournalTab.OpenBuilds(false), its two queued settles at 0.10 and 0.35 s
-- under a synthetic C_Timer). Open My Builds is pending (the page arrives
-- late), the player closes the coach deliberately, reopens it (Show, first
-- use, replay) or leaves it closed, and only then is My Builds seen: that old
-- route's onSettled(true) is stale and must not hide the coach, mark a step,
-- arm a request, keep Auto, assign, save, load, send or spend. The Journal's
-- onSettled is passed through a counting wrapper only, so each EXPECT runs
-- after a stale answer of seen was really delivered. An older route of the
-- same session stays stale too; the latest one still steps aside once My
-- Builds is seen. Real client timing and pages are NOT RUN.
C.scenario('F16 a My Builds answer from before Close and reopen is stale: the reopened coach stays and nothing changes',function()
 Boot()
 local T,G=Nexus.UserText.Guide,Nexus.GuidedSetup
 local journal,button=_G.ProjectEbonholdEchoJournal,_G.EchoJournalMicroButton
 local loadouts=CreateFrame('Frame',nil,journal)
 loadouts:CreateFontString():SetText('Your loadouts')
 local other=CreateFrame('Frame',nil,journal)
 other:CreateFontString():SetText('Echo collection')
 other:Hide()
 local tab=CreateFrame('Button',nil,journal)
 tab:SetText('Loadouts')
 tab:SetScript('OnClick',function() other:Hide();loadouts:Show() end)
 -- The game's button opens nothing by itself: the page arrives later (shown
 -- by the scenario), as after the first asynchronous settle.
 local clicks=0
 button:SetScript('OnClick',function() clicks=clicks+1;if journal:IsShown() then journal:Hide() end end)
 local realOpen,delivered=Nexus.JournalTab.OpenBuilds,{}
 Nexus.JournalTab.OpenBuilds=function(chooser,close,settled,...)
  if type(settled)=='function' then
   local own=settled
   settled=function(seen,...) delivered[#delivered+1]=seen==true;return own(seen,...) end
  end
  return realOpen(chooser,close,settled,...)
 end
 local keepTimer,closes=C_Timer,0
 local ok,err=pcall(function()
  if not Open('F16') then return end
  local before=Effects()
  local function Aside() return not Shown() and Guide().waiting==true and Guide().waitingKind=='builds' end
  -- The guide's own record: step, Continue, request, Keep Auto, skipped
  -- target, chosen target, receipts and the game's active Saved Build.
  local function Mark()
   local s=G.State()
   return table.concat({tostring(Step()),tostring(G.CanNext()),tostring(s.request),tostring(s.autoKept),
    tostring(s.skipped.target),tostring(s.target and s.target.destination),tostring(#G.Receipts()),
    tostring(A.SelectedSavedBuild())},'/')
  end
  -- The Saved Build step with Slot 1 (not active) chosen and the page closed.
  local function Ready(tag)
   if not Shown() then Nexus.GuidedSetupUI.Show() end
   journal:Hide();loadouts:Show();other:Hide()
   if Step()=='welcome' then Start('I already have');Press(Opt('W-Free'));Press(Btn('Continue')) end
   if not (G.State().target and G.State().target.destination==1) then Press(Opt('Slot 1 - One')) end
   return C.setup(Shown() and Step()=='target' and Btn('Open My Builds')~=nil and not journal:IsShown(),
    tag..': fixture: Slot 1 chosen at the Saved Build step; the page is closed',Step())
  end
  -- One Open My Builds press; the Journal's two settles, by their delays.
  local function Route()
   local queue,r={},{}
   C_Timer={After=function(delay,fn) queue[#queue+1]={delay,fn} end}
   r.pressed=Press(Btn('Open My Builds'))
   C_Timer=keepTimer
   for _,q in ipairs(queue) do
    if q[1]==0.10 and not r.first then r.first=q[2] elseif q[1]==0.35 and not r.last then r.last=q[2]
    else r.rest=r.rest or {};r.rest[#r.rest+1]=q[2] end
   end
   return r
  end
  local function Settle(r)
   if r.first then r.first() end
   if r.last then r.last() end
   for _,fn in ipairs(r.rest or {}) do fn() end
  end

  -- 1. Two presses in one session: the older answer is stale; the latest
  -- steps aside only once My Builds is seen.
  if not Ready('F16 older') then return end
  local n=#delivered
  local a=Route()
  local b=Route()
  if not C.setup(a.pressed and b.pressed and a.first and a.last and b.first and b.last and Shown()
   and not Guide().waiting and #delivered==n,'F16 older: fixture: Open My Builds pressed twice; both routes pending',#delivered-n) then return end
  local mark=Mark()
  journal:Show()
  Settle(a)
  if not C.setup(delivered[n+1]==true,'F16 older: fixture: the older route answered seen',tostring(delivered[n+1])) then return end
  C.expect(Shown() and not Guide().waiting and Mark()==mark and Text():find(T.notes.buildsUnconfirmed,1,true)==nil,
   'F16 older: the older route\'s answer is stale: the coach stays, unchanged, with no note',(#delivered-n)..' '..Mark())
  b.first()
  C.expect(Aside() and Mark()==mark,'F16 current: the latest route steps aside once My Builds is seen',Mark())
  if b.last then b.last() end
  for _,fn in ipairs(b.rest or {}) do fn() end
  C.expect(Aside(),'F16 current: its last settle changes nothing more')
  C.guard(Effects()==before,'F16 older: both routes wrote, acted, sent, spent and toggled nothing',Effects())

  -- 2. Pending, Close, then: left closed, reopened, first use, replay.
  local REOPEN={
   {'closed',nil},
   {'reopen',function() return Nexus.GuidedSetupUI.Show()==true end},
   {'first use',function() return Nexus.GuidedSetupUI.ShowFirstUse(function() closes=closes+1 end)==true end},
   {'replay',function() return Nexus.GuidedSetupUI.Replay()==true end},
  }
  for _,v in ipairs(REOPEN) do
   local tag='F16 '..v[1]
   -- First use is told closed only by its own deliberate Close below; no
   -- case's Close, reopen or stale answer may add to the count.
   local closed=closes
   if not Ready(tag) then return end
   n=#delivered
   local r=Route()
   if not C.setup(r.pressed and r.first~=nil and r.last~=nil and Shown() and not Guide().waiting and #delivered==n,
    tag..': fixture: Open My Builds is pending; the Journal has not answered',#delivered-n) then return end
   Press(Btn('X'))
   if not C.setup(not Shown() and not Guide().waiting,tag..': fixture: the player closed the coach') then return end
   if v[2] and not C.setup(v[2]() and Shown(),tag..': fixture: the coach was reopened') then return end
   mark=Mark()
   journal:Show() -- My Builds is seen only now
   Settle(r)
   if not C.setup(delivered[n+1]==true,tag..': fixture: the old route answered seen',tostring(delivered[n+1])) then return end
   if v[2] then
    C.expect(Shown() and not Guide().waiting and Guide().waitingKind==nil and Mark()==mark
     and Text():find(T.notes.buildsUnconfirmed,1,true)==nil,
     tag..': the stale answer neither hides the reopened coach nor changes its guide',Mark())
   else
    C.expect(not Shown() and not Guide().waiting and Guide().waitingKind==nil and Mark()==mark,
     tag..': the stale answer leaves the closed coach closed, waiting on nothing',Mark())
   end
   C.guard(Effects()==before and closes==closed,tag..': nothing written, assigned, acted, sent, spent, toggled or reported closed',
    Effects()..' closes='..closes..' was '..closed)
   if v[1]=='reopen' then
    -- The reopened session's own route still works: My Builds is open now.
    local fresh=Route()
    Settle(fresh)
    C.expect(Aside(),tag..': Open My Builds in the reopened session still steps aside once My Builds is seen')
   elseif v[1]=='first use' then
    Press(Btn('X'))
    C.expect(not Shown() and closes==1,'F16 first use: the deliberate Close still tells first use once',closes)
   end
  end
  C.guard(Effects()==before and A.SelectedSavedBuild()==2,'F16: every route and reopen assigned, saved, loaded, sent, spent and toggled nothing',Effects())
 end)
 C_Timer=keepTimer
 Nexus.JournalTab.OpenBuilds=realOpen
 C.setup(ok,'F16: fixture: the scenario ran',err)
end)

C.finish('(guided coach: one step at a time; navigation changes nothing; confirmed only after read back)')
