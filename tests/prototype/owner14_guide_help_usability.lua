-- Owner-approved usability follow-up 2026-10-30, guide/Help/shared-copy
-- lane: displayed items 5 (shorter plain setup wording), 6 (assigned now
-- versus captured, UserText.DestinationFields), 11 (Help page tabs apart
-- from buttons that open another window) and 13 (one checklist marker
-- language beside status words). Displayed item 10 (Auto OFF -> Auto: Off)
-- is EXCLUDED: a negative guard keeps every Auto OFF wording exact.
-- Real routes only: the coach window (U.Show, its buttons, All steps, the
-- summary), the Help window (its page tabs, window buttons and deep links)
-- and the pure destination formatter. EXPECT: the approved change (each
-- fails at f8cce3f4, reported, not raised). GUARD: behaviour that must
-- hold. Effects come from counted adapter writers, the host action log,
-- sends, Orb spends and Auto; reading, moving and closing change none of
-- them. Offline text models only: native fit, hit order, focus, contrast
-- and glyph pixels are NOT RUN.
local V=dofile('tests/prototype/view_regression_support.lua')
local L=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('owner14_guide_help_usability')
local H,A,writes,spends
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity',
 'UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist','ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}
local NAMES={'ProjectEbonholdEchoJournal','EchoJournalMicroButton','NexusEditorFrame','NexusWishlistNameInput',
 'NexusActiveWishlistSelector','NexusWishlistOnlyPicker','NexusLoadoutAssociationPanel','NexusGuidedSetup',
 'NexusGuidedSetupEscape','NexusQuickStart','NexusQuickStartEscape','NexusHelpWindow','NexusHelpScroll','NexusPanel',
 'NexusSetupChecklist'}
local LONG='Wunschliste \195\156ber-Gr\195\182\195\159e \226\128\148 \240\159\148\165 sehr lange Namen f\195\188r den F\195\188hrer und noch mehr Text'

local function Boot()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 for _,n in ipairs(NAMES) do _G[n]=nil end
 H=dofile('tests/prototype/harness.lua');H.playerLevel=80;wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5)
 H.AddEcho(201174,'Echo Free',0,5);H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [3]={name='Empty three',verified=true,echoes={}},[106]={name='W-Six',verified=false,echoes=E6},
  [107]={name='W-Free',verified=false,echoes=EF}}
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
 if NexusGuidedSetup and NexusGuidedSetup:IsShown() then NexusGuidedSetup:Hide() end
 local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent);journal:Hide()
 CreateFrame('Button','EchoJournalMicroButton',UIParent):SetScript('OnClick',function() journal:Show() end)
 return C.setup(Nexus.GuidedSetupUI~=nil and Nexus.Help~=nil and Nexus.UserText~=nil,'fixture: healthy boot')
end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Effects() return table.concat({Writes(),#H.actions,#H.sent,spends,tostring(Auto())},'/') end
local function Guide() return _G.NexusGuidedSetup end
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
local function Text() return Guide() and V.Plain(Nexus.GuidedSetupUI.VisibleText() or '') or '' end
local function Step() return Nexus.GuidedSetup.StepId() end
local function Copy() return Nexus.UserText.Guide end
local function Count(text,needle)
 local n,at=0,1
 while true do
  local s,e=text:find(needle,at,true)
  if not s then return n end
  n,at=n+1,e+1
 end
end

------------------------------------------------------------------------
-- Item 10 negative guard (shared copy): no Auto OFF/ON rename anywhere in
-- the shared player text this lane owns, and the guide's Auto step keeps
-- the exact Auto OFF words.
------------------------------------------------------------------------
local RENAMED={'Auto: Off','Auto: On','Auto: OFF','Auto: ON','Auto:Off','Auto:OFF'}
local function Strings(t,out,seen)
 out,seen=out or {},seen or {}
 if type(t)=='string' then out[#out+1]=t;return out end
 if type(t)~='table' or seen[t] then return out end
 seen[t]=true
 for _,v in pairs(t) do Strings(v,out,seen) end
 return out
end
C.scenario('X10 Auto OFF stays exact: shared copy, Help pages and the guide never rename it',function()
 if not Boot() then return end
 local all=Strings(Nexus.UserText)
 for _,p in ipairs(Nexus.Help.Pages or {}) do all[#all+1]=p.text end
 for _,t in pairs(Nexus.Help.Topics or {}) do for _,l in ipairs(t.lines or {}) do all[#all+1]=l end end
 local bad={}
 for _,s in ipairs(all) do for _,r in ipairs(RENAMED) do if s:find(r,1,true) then bad[#bad+1]=r..' in '..s:sub(1,80) end end end
 C.guard(#bad==0,'X10: no shared player text renames Auto OFF/ON with a colon',table.concat(bad,' / '))
 local a=Copy().auto or {}
 C.guard(a.modeOff=='Auto is OFF right now' and a.keptOff=='Left OFF. Nothing changed.'
  and (Copy().words or {}).leftOff=='Left OFF','X10: the guide keeps its exact Auto OFF words',tostring(a.modeOff))
 -- The panel's own Auto control (owned by the Panel lane) is only read.
 local panel=_G.NexusPanel
 local auto
 for _,c in ipairs(panel and panel.children or {}) do
  if c.kind=='Button' then
   local t=V.Plain(c:GetText() or '')
   if t=='Auto OFF' or t=='Auto ON' or t:find('^Auto:') then auto=t end
  end
 end
 C.guard(auto==nil or auto=='Auto OFF','X10: the panel Auto control, when present, still reads Auto OFF',tostring(auto))
end)

------------------------------------------------------------------------
-- Item 5: shorter, plain setup wording. One navigation safety line per
-- screen, no duplicated reason, plain outcome words; consent, consequence,
-- refusal and saved-versus-session words stay.
------------------------------------------------------------------------
C.scenario('G5 Welcome says each thing once; the outcome slot uses plain words; nothing acts',function()
 if not Boot() then return end
 local before=Effects()
 Nexus.GuidedSetupUI.Show()
 if not C.setup(Guide() and Guide():IsShown() and Step()=='welcome','G5: fixture: the coach opens at Welcome',Step()) then return end
 local t=Text()
 C.guard(t:find('never assigns, spends Orbs, sends data, or changes Auto',1,true)~=nil,'G5: the navigation safety words are shown',t)
 C.expect(Count(t,'never assigns, spends Orbs, sends data, or changes Auto')==1
  and Count(t:lower(),'never change anything')==0,'G5: the navigation safety words appear once on Welcome, not as two lines',t)
 local why=(Copy().why or {}).welcome or ''
 local lead=why:match('^(.-%.)') or why
 C.expect(lead~='' and Count(t,lead)==1 and Count(t,'Nexus recommends Echoes from a Wishlist you choose')==0,
  'G5: Welcome does not say what Nexus does twice',t)
 C.guard(t:find('Step 1 of 7',1,true)~=nil and Btn('Continue')~=nil and not Btn('Continue'):IsEnabled(),
  'G5: Welcome is step 1 of 7 and Continue waits for a choice')
 Press(Opt('New to Nexus'))
 t=Text()
 C.expect(not t:find('OBSERVED',1,true) and t:find((Copy().outcome or {}).observedLabel or '?',1,true)~=nil
  and ((Copy().outcome or {}).observedLabel or ''):find('HAPPENED',1,true)~=nil,
  'G5: a result reads WHAT HAPPENED in plain words, not OBSERVED',t)
 C.guard(t:find((Copy().words or {}).chosen or '?',1,true)~=nil and not t:find('Done - confirmed',1,true),
  'G5: a chosen path says Chosen, never Done - confirmed',t)
 -- The simulated lesson keeps its whole meaning; the repeated reason goes.
 Press(Btn('Continue'));Press(Btn('Skip for now'));Press(Btn('Skip for now'));Press(Btn('Skip for now'))
 if not C.setup(Step()=='manual','G5: fixture: skipped to the recommendation step',Step()) then return end
 t=Text()
 C.guard(t:find('SIMULATED PREVIEW - NOTHING IS CHOSEN IN GAME',1,true)~=nil,'G5: Step 5 keeps its simulated banner',t)
 C.expect(Count(t:lower(),'nothing is chosen in game')==1,'G5: Step 5 says nothing is chosen in game once (the banner)',t)
 Press(Opt('Sample Frost'))
 t=Text()
 C.guard(t:find('Preview only: you picked Sample Frost. Nothing was chosen in game.',1,true)~=nil,
  'G5: a pick still says it was a preview and chose nothing',t)
 Press(Btn('Continue'))
 if not C.setup(Step()=='auto','G5: fixture: the Auto step',Step()) then return end
 t=Text()
 C.guard(t:find('Auto is OFF right now',1,true)~=nil and t:find('Auto is ON right now',1,true)==nil,'G5: the Auto step reads Auto OFF exactly',t)
 C.expect(Count(t:lower(),'unless you change it')+Count(t:lower(),'unless you do')<=1,
  'G5: the Auto step says it stays as it is once',t)
 C.guard(t:find((Copy().auto or {}).reviewNote or '?',1,true)~=nil or (Copy().buttons or {}).review and Opt('Review on the Nexus panel')~=nil,
  'G5: the Auto step still names how Auto is changed',t)
 Press(Btn('Skip for now'))
 if not C.setup(Step()=='summary','G5: fixture: the summary',Step()) then return end
 t=Text()
 C.guard(t:find('Skipped',1,true)~=nil and not t:find('Done - confirmed',1,true) and t:find("You can close now",1,true)~=nil,
  'G5: skipped steps stay skipped; nothing is confirmed',t)
 C.expect(Count(t,'Only steps Nexus confirmed are marked done')<=1,'G5: the summary states the done rule once',t)
 Press(Btn('X'))
 C.guard(Effects()==before,'G5: opening, choosing, skipping and closing acted, wrote, sent, spent and toggled nothing',
  before..' -> '..Effects())
end)

------------------------------------------------------------------------
-- Item 13: one marker language. Every checklist row leads with its status
-- glyph (never a step number), beside its status word; each status has its
-- own printable ASCII glyph and word, so no meaning rests on colour.
------------------------------------------------------------------------
local function ChecklistRows()
 local c=Copy();local out={}
 for _,step in ipairs(Nexus.GuidedSetup.Order()) do
  local label=(c.labels or {})[step] or step
  local g=Guide()
  for _,b in ipairs(g and g.children or {}) do
   if b.kind=='Button' and b:IsShown() then
    local t=V.Plain(b:GetText() or '')
    if #t>#label and t:sub(-#label)==label and t:sub(-#label-2,-#label-1)=='  ' then
     out[#out+1]={step=step,marker=t:sub(1,#t-#label-2),word=b.desc and V.Plain(b.desc:GetText() or '') or ''}
     break
    end
   end
  end
 end
 return out
end
local function MarkerFor(word)
 for kind,s in pairs(Copy().status or {}) do if s.word==word then return s.glyph,kind end end
end
C.scenario('M13 the checklist uses one glyph-and-word marker per status in both presentations',function()
 if not Boot() then return end
 local st=Copy().status or {}
 local glyphs,words,bad={},{},{}
 for kind,s in pairs(st) do
  if type(s.glyph)~='string' or s.glyph=='' or s.glyph:find('[^\32-\126]') or s.glyph:find('|',1,true) or s.glyph:find('%d') then bad[#bad+1]=kind end
  if glyphs[s.glyph] or words[s.word] then bad[#bad+1]=kind..' repeats' end
  glyphs[s.glyph],words[s.word]=true,true
 end
 C.guard(#bad==0,'M13: each status has its own printable ASCII glyph (no digit, no pipe) and its own word',table.concat(bad,', '))
 C.guard(st.verified and st.verified.word:find('confirmed',1,true) and st.rejected.word~=st.skipped.word
  and st.stale.word~=st.unavailable.word and st['not'].word~=st.waiting.word,
  'M13: confirmed, declined, skipped, unknown, unavailable, not started and needs-you stay distinct')
 local before=Effects()
 Nexus.GuidedSetupUI.Show()
 Press(Opt('New to Nexus'));Press(Btn('Continue'));Press(Btn('Skip for now'))
 if not C.setup(Step()=='target','G13: fixture: Wishlist skipped, at the Saved Build step',Step()) then return end
 Press(Btn('All steps v'))
 local function Check(tag)
  local rows=ChecklistRows()
  C.setup(#rows==#Nexus.GuidedSetup.Order(),tag..': fixture: a checklist row for each step',#rows)
  local mixed={}
  for _,r in ipairs(rows) do
   local glyph=MarkerFor(r.word)
   if r.marker:find('^%d+$') then mixed[#mixed+1]=r.step..' shows the number '..r.marker
   elseif glyph and glyph~=r.marker then mixed[#mixed+1]=r.step..' '..r.marker..' beside '..r.word end
   if r.word=='' then mixed[#mixed+1]=r.step..' has no status word' end
  end
  C.expect(#rows>0 and #mixed==0,tag..': every row, the last one too, leads with its status glyph beside its word, never a step number',
   table.concat(mixed,'; '))
  local by={};for _,r in ipairs(rows) do by[r.step]=r end
  C.guard(by.welcome and by.welcome.marker==st.verified.glyph and by.wishlist and by.wishlist.word==st.skipped.word
   and by.wishlist.marker==st.skipped.glyph,tag..': Welcome is chosen (+), the Wishlist row reads Skipped (-)',
   by.wishlist and (by.wishlist.marker..' '..by.wishlist.word) or 'none')
  C.guard(not (by.assign and by.assign.word==st.verified.word),tag..': an unconfirmed assignment never reads Done - confirmed')
 end
 Check('M13 compact')
 -- The desktop presentation (side navigation) on a visible UI wide enough.
 local w,h=UIParent:GetWidth(),UIParent:GetHeight()
 UIParent:SetWidth(1600);UIParent:SetHeight(1000)
 Nexus.GuidedSetupUI.Render()
 C.setup(Btn('All steps v')==nil and Btn('All steps ^')==nil,'M13 wide: fixture: the side navigation replaces All steps')
 Check('M13 wide')
 UIParent:SetWidth(w);UIParent:SetHeight(h)
 Nexus.GuidedSetupUI.Render()
 Press(Btn('X'))
 C.guard(Effects()==before,'M13: opening the list and moving acted, wrote, sent, spent and toggled nothing',before..' -> '..Effects())
end)

------------------------------------------------------------------------
-- Item 11: Help's page tabs read as tabs of this window (a strip with the
-- selected page marked) and the buttons that open another window stand
-- apart under their own heading. Labels, routes, deep links and the
-- selected page staying disabled are unchanged.
------------------------------------------------------------------------
local WINDOW_BUTTONS={'Setup / Welcome','Assign Wishlist...','Wishlist Editor','Setup checklist'}
local function HelpButton(f,label)
 for _,c in ipairs(f.children or {}) do
  if c.kind=='Button' and V.Plain(c:GetText() or '')==label then return c end
 end
end
local function HelpRegion(f,text)
 for _,r in ipairs(L.Shown(f)) do
  if r.GetText and V.Plain(r:GetText() or '')==text then return r end
 end
end
local function Selected(b) return b._nexusSelected==true and b._nexusSelectedBar~=nil and b._nexusSelectedBar:IsShown() end
local function HelpChecks(tag,f)
 local root=L.Rect(f,f)
 local tabs=f.tabs or {}
 local tabBottom,tabTop=-math.huge,math.huge
 for _,t in ipairs(tabs) do local r=L.Rect(t,f);tabBottom=math.max(tabBottom,r[4]);tabTop=math.min(tabTop,r[2]) end
 local heading=f.windowsLabel and f.windowsLabel:IsShown() and f.windowsLabel or nil
 C.expect(heading~=nil and V.Plain(heading:GetText() or '')~='' and V.Plain(heading:GetText()):lower():find('another window',1,true)~=nil,
  tag..': the window buttons sit under their own heading that says they open another window',heading and heading:GetText())
 local rects={}
 for _,label in ipairs(WINDOW_BUTTONS) do
  local b=HelpButton(f,label)
  C.guard(b~=nil and b:IsShown() and b:IsEnabled() and b:GetScript('OnClick')~=nil,tag..': '..label..' is still offered with its route')
  if b then
   rects[#rects+1]=L.Rect(b,f)
   C.guard(not b._nexusSelected,tag..': '..label..' never shows the selected-page mark')
  end
 end
 if heading then
  local hr=L.Rect(heading,f)
  local hh=math.max(hr[4]-hr[2],L.Rows(heading:GetText(),hr[3]-hr[1],L.model and L.model.char or 5.5)*(L.model and L.model.line or 12))
  local ok=hr[2]>=tabBottom and L.Inside(hr,root)
  for _,r in ipairs(rects) do ok=ok and hr[2]+hh<=r[2] end
  C.expect(ok,tag..': the heading sits below the tab strip and above the window buttons, whole',L.Text(hr))
 end
 local gap=math.huge
 for _,r in ipairs(rects) do gap=math.min(gap,r[2]-tabBottom) end
 C.expect(gap>=18,tag..': the window buttons are set apart from the tabs (at least 18 px below them)',gap)
 local rule=f.tabRule
 C.expect(rule~=nil and rule:IsShown() and (function() local r=L.Rect(rule,f);return r[2]>=tabBottom-1 and r[3]-r[1]>=500 end)(),
  tag..': a strip line runs under the page tabs',rule and L.Text(L.Rect(rule,f)))
 -- Note, topic card and reference below, apart from every control.
 local note=L.Rect(f.note,f)
 local card=L.Rect(f.topicTitle,f)
 local ok=true
 for _,r in ipairs(rects) do ok=ok and r[4]<=note[2] end
 C.guard(ok and note[4]<=card[2]+1 and L.Inside(L.Rect(f.scroll,f),root) and (function() local s=L.Rect(f.scroll,f);return s[4]-s[2]>=120 and s[4]<=540-55 end)(),
  tag..': the route note, the topic card and the scrolling reference keep their order and room',L.Text(L.Rect(f.scroll,f)))
end
C.scenario('H11 Help tabs are a strip with the current page marked; window buttons stand apart; routes unchanged',function()
 if not Boot() then return end
 local before=Effects()
 SlashCmdList.NEXUS('reference')
 local f=_G.NexusHelpWindow
 if not C.setup(f and f:IsShown() and f.tabs and #f.tabs==#Nexus.Help.Pages,'H11: fixture: the Reference window and its tabs') then return end
 for i,p in ipairs(Nexus.Help.Pages) do
  Nexus.Help.Show(p.id)
  local marked,others=f.tabs[i],true
  for j,t in ipairs(f.tabs) do if j~=i and (Selected(t) or not t:IsEnabled()) then others=false end end
  C.expect(Selected(marked) and others,'H11: the tab of page '..p.id..' alone shows the selected mark',i)
  C.guard(not marked:IsEnabled(),'H11: the current page tab stays the disabled one ('..p.id..')')
 end
 -- A tab click moves the mark; the deep link selects its page.
 f.tabs[2]:Click()
 C.expect(Selected(f.tabs[2]) and not Selected(f.tabs[#f.tabs]),'H11: clicking a tab moves the selected mark to it')
 C.guard(f.page:GetText()=='Page 2 / '..#Nexus.Help.Pages and f.scroll:GetVerticalScroll()==0,'H11: a tab still opens its page at the top')
 Nexus.Help.Show('faq')
 C.guard(f.title:GetText():find('Questions',1,true)~=nil,'H11: the FAQ deep link still opens its page',f.title:GetText())
 C.guard(f.body:GetText():find('|cffffd100',1,true)~=nil,'H11: FAQ questions keep their gold heading colour')
 HelpChecks('H11 default',f)
 L.UseFont({name='125%',char=8.75,line=15,size=15})
 Nexus.Help.Show('start')
 HelpChecks('H11 125%',f)
 Nexus.Help.Show('faq')
 HelpChecks('H11 125% faq',f)
 L.UseFont(L.MODELS.default)
 -- The bottom navigation keeps its callbacks.
 Nexus.Help.Show('start')
 HelpButton(f,'Next'):Click()
 C.guard(f.page:GetText()=='Page 2 / '..#Nexus.Help.Pages and not f.tabs[2]:IsEnabled(),'H11: Next still moves the page')
 C.expect(Selected(f.tabs[2]) and not Selected(f.tabs[1]),'H11: Next moves the selected mark with the page')
 HelpButton(f,'Start page'):Click()
 C.guard(f.page:GetText()=='Page 1 / '..#Nexus.Help.Pages and not f.tabs[1]:IsEnabled(),'H11: Start page still returns to page 1')
 C.expect(Selected(f.tabs[1]) and not Selected(f.tabs[2]),'H11: Start page marks page 1')
 -- A window button still takes Help's place through its real route.
 HelpButton(f,'Setup checklist'):Click()
 C.guard(not f:IsShown() and _G.NexusSetupChecklist and NexusSetupChecklist:IsShown(),'H11: Setup checklist still opens its window in Help\'s place')
 if _G.NexusSetupChecklist then NexusSetupChecklist:Hide() end
 Nexus.Help.Show('start');HelpButton(f,'Close'):Click()
 C.guard(not f:IsShown(),'H11: Close still closes')
 -- Reopen/refresh cycles add no texture or hook (the selected bar is made once).
 local T=Nexus.Theme
 if T and T.Stats then
  Nexus.Help.Show('start')
  local s0,n0=T.Stats(),#H.frames
  for i=1,20 do Nexus.Help.Show(Nexus.Help.Pages[(i%#Nexus.Help.Pages)+1].id);Nexus.Help.Hide() end
  local s1=T.Stats()
  C.guard(s1.textures==s0.textures and s1.hooks==s0.hooks and #H.frames==n0,'H11: reopening and paging add no frame, texture or hook')
 end
 C.guard(Effects()==before,'H11: reading, paging and closing Help acted, wrote, sent, spent and toggled nothing',before..' -> '..Effects())
end)

------------------------------------------------------------------------
-- Item 6: the shared destination formatter explains assigned now (the
-- current link the caller states) apart from captured (the destination
-- held when an edit or view started). Shape, codes, flags, names and the
-- atomic minimums are unchanged; the formatter reads no backend state.
------------------------------------------------------------------------
local function Cells(d)
 local f,tip=Nexus.UserText.DestinationFields(d)
 local by={}
 for i,r in ipairs(f) do by[r.key]=r;by[i]=r end
 return by,tip,f
end
C.scenario('D6 assigned now and captured read apart; shape, codes and minimums unchanged; pure',function()
 if not Boot() then return end
 local UT=Nexus.UserText
 local before=Effects()
 -- Purity: no adapter or controller is reachable while it formats.
 local adapter,ctrl,dps=Nexus.GameAdapter,Nexus.WishlistController,Nexus.DestinationPresentation
 Nexus.GameAdapter,Nexus.WishlistController=nil,nil
 local ok,err=pcall(function()
  -- Shape (every case): four records in the fixed order with key/label/value/compact.
  local function Shape(tag,f)
   local keys={}
   for i,r in ipairs(f) do keys[i]=r.key
    if type(r.value)~='string' or r.value=='' or type(r.compact)~='string' or r.compact=='' or type(r.label)~='string' then keys[i]='bad:'..tostring(r.key) end
   end
   C.guard(#f==4 and table.concat(keys,',')=='character,savedBuild,wishlist,state'
    and type(f[3].minimum)=='string' and type(f[4].minimum)=='string',tag..': four cells in the order character, savedBuild, wishlist, state',table.concat(keys,','))
  end
  -- Assigned now: the current link the caller states.
  local a,tipA,fa=Cells({kind='savedBuild',slot=2,name='Fire PvE',active=true,character='Tester',wishlist='W-Free',wishlistState='assigned'})
  Shape('D6 assigned',fa)
  C.guard(a.wishlist.value=='W-Free (assigned)' and a.wishlist.compact=='W-Free' and a.wishlist.minimum=='W-Free'
   and a.state.value=='Active in the game' and a.state.minimum=='On','D6: an assigned Wishlist keeps its words, name and minimum',a.wishlist.value)
  local capA=false;for _,l in ipairs(tipA) do if l:find('^Captured') then capA=true end end
  C.guard(not capA,'D6: an uncaptured view carries no captured note',table.concat(tipA,' / '))
  C.guard(table.concat(UT.DestinationLines({kind='savedBuild',slot=2,name='Fire PvE',active=true,wishlist='W-Free',wishlistState='assigned'}),' / ')
   =="Destination: Saved Build 'Fire PvE' (slot 2) - active in the game / Wishlist: W-Free (assigned)",'D6: DestinationLines is unchanged')
  -- Captured, assignment unknown: held when the edit opened; not called assigned.
  local c,tipC,fc=Cells({kind='savedBuild',slot=6,name='Six',captured=true,character='Tester',wishlist='W-Six'})
  Shape('D6 captured',fc)
  C.guard(not c.wishlist.value:find('(assigned)',1,true) and c.wishlist.value:find('W-Six',1,true)==1
   and c.wishlist.compact=='?: W-Six' and c.wishlist.minimum=='?' and c.state.minimum=='C:?'
   and c.state.value:find('^Captured; ') and c.state.compact:find('^Captured: '),
   'D6: a captured Wishlist is never called assigned; its codes stay ?, C:?',c.wishlist.value..' | '..c.state.value)
  C.expect(c.wishlist.value:find('not checked as assigned now',1,true)~=nil and c.state.value:find('not checked as assigned now',1,true)~=nil,
   'D6: the captured Wishlist and state say plainly that it is not checked as assigned now',c.wishlist.value..' | '..c.state.value)
  local note
  for _,l in ipairs(tipC) do if l:find('^Captured:') then note=l end end
  C.guard(note~=nil and note:find('shown as captured earlier',1,true)~=nil,'D6: the captured note is kept',note)
  C.expect(note~=nil and note:find('held',1,true)~=nil and (note:find('opened',1,true) or note:find('started',1,true))
   and note:find('assigned now',1,true)~=nil and note:find('current link',1,true)~=nil and not note:lower():find('in use',1,true),
   'D6: the hover explains captured (held when it opened) apart from assigned now (the current link), never "in use"',note)
  C.guard(#tipC==5,'D6: one note line is added for a captured view, as before',#tipC)
  -- Captured with a stated assignment: no "not checked" claim.
  local cs=Cells({kind='savedBuild',slot=2,name='Fire PvE',captured=true,wishlist='W-Free',wishlistState='assigned'})
  C.guard(cs.wishlist.value=='W-Free (assigned)' and not cs.state.value:find('not checked',1,true) and cs.state.minimum=='C:?',
   'D6: a stated assignment is worded as stated, without the not-checked words',cs.state.value)
  -- First-run captured, unavailable and an empty Saved Build keep their codes.
  local fr=Cells({kind='firstRun',captured=true,wishlist='W-Free'})
  C.guard(fr.state.compact=='Captured: first-run target' and fr.state.minimum=='C:1' and fr.savedBuild.compact=='None',
   'D6: a captured first-run target keeps its whole label and C:1',fr.state.compact)
  local un=Cells({kind='savedBuild',slot=2,name='Fire PvE',unavailable=true,wishlist='W-Free',wishlistState='unavailable'})
  C.guard(un.wishlist.compact=='N/A: W-Free' and un.wishlist.minimum=='x' and un.state.minimum=='N/A' and not un.wishlist.value:find('(assigned)',1,true),
   'D6: unavailable stays N/A and x, never assigned',un.wishlist.value)
  local em=Cells({kind='savedBuild',slot=3,name='Empty three',empty=true,captured=true,wishlist='W-Free',wishlistState='assigned'})
  C.guard(em.wishlist.minimum=='!' and em.wishlist.compact=='Refused: W-Free' and em.state.minimum=='C:0',
   'D6: an empty Saved Build is refused whatever state is passed',em.wishlist.compact)
  local nk=Cells({})
  C.guard(nk.wishlist.value=='Not known' and nk.wishlist.minimum=='?' and nk.character.value=='Not known' and nk.state.value=='None captured',
   'D6: nothing known is Not known and None captured, never unassigned',nk.state.value)
  -- Display-safe names: an escaped pipe and a long UTF-8 name stay whole.
  local p=Cells({kind='savedBuild',slot=2,name='A|B',captured=true,wishlist=LONG})
  C.guard(p.savedBuild.value:find('A||B',1,true)~=nil and p.wishlist.value:find(LONG,1,true)==1,
   'D6: a pipe stays escaped and a long UTF-8 name stays whole',p.savedBuild.value)
  -- Preview keeps its designation and minimum.
  local pv=Cells({kind='savedBuild',slot=2,name='Fire PvE',captured=true,preview=true})
  C.guard(pv.state.value:find('^Preview; Captured; ') and pv.state.minimum=='PC?','D6: a captured preview keeps Preview first and PC?',pv.state.value)
 end)
 Nexus.GameAdapter,Nexus.WishlistController=adapter,ctrl
 C.guard(ok,'D6: the formatter ran with no adapter or controller reachable (pure)',err)
 C.guard(Effects()==before,'D6: formatting acted, wrote, sent, spent and toggled nothing',before..' -> '..Effects())
end)

C.finish('(owner-approved items 5, 6, 11, 13 through real coach, Help and formatter routes; Auto OFF exact; native fit, focus, contrast and glyphs NOT RUN)')
