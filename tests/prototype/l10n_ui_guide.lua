-- Full UI localization, guide family (help., setup., guide., consent.,
-- settings., workspace. keys): the Reference manual (every page, the FAQ, the
-- topic cards, tabs and routes), the Welcome and its information-only replay,
-- the Setup checklist, the guided setup coach (every step of the new and
-- explore paths, its Reference view, checklist, expanders, preview, summary
-- lessons and close chat), the Saved Build overwrite warning (first-launch
-- and Auto kinds), every Settings category and page with its row and category
-- hovers, and the Plan / Explore workspace tabs show their code-owned words
-- through Nexus.Localization at the real display receivers (FontString and
-- button text, tooltip lines, chat).
-- Phases, each a fresh real TOC boot:
--  P1 pseudo pack from session start: no visible code-owned English is left
--     outside the pseudo marks (data and other families' pending words are
--     named narrowly below); templates keep unknown as "?", zero as "0" and
--     insert long UTF-8 names verbatim; rendering, hovering, navigating and
--     closing change no saved data (beyond the coach's own documented place
--     record), send nothing, act on nothing and leave Auto OFF.
--  P2 the overwrite warning (both kinds), the information-only Welcome and
--     the checklist under the pseudo pack, answered No / cancelled only.
--  P3 "long" pseudo mode (every ASCII word doubled): no error, text shown.
--  P4 a pseudo pack without some guide-family keys: those show exact English.
--  P5 English (no pack): every page's blocks join to its exact English text,
--     every T("key", "English") literal of the family's files is that key's
--     English base, and representative windows show their exact English.
-- Synthetic offline evidence only: no glyph, font, layout or native claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local checks,failed=0,{}
local function check(v,m) checks=checks+1;if not v then failed[#failed+1]=m;print('FAIL '..m) end end
local OPEN,CLOSE=S.OPEN,S.CLOSE
local LONG='Wunschliste \195\156ber-Gr\195\182\195\159e \226\128\148 \240\159\148\165 sehr lange Namen f\195\188r den F\195\188hrer'
local FILES={'ui/Help.lua','ui/QuickStart.lua','ui/GuidedSetup.lua','ui/OverwriteWarning.lua','ui/SettingsWindow.lua','ui/FullUIWorkspaces.lua'}

local function Boot(mode,entries,mutate,keepWarnings)
 if mode~='english' then S.InstallBootHook(mode,entries) end
 local H=F.Boot(F.Database{mutate=function(db)
  db.hasSeenQuickStart=true
  if mutate then mutate(db) end
 end},function(h) F.OrbService(h);h.keepOverwriteWarningPrompts=keepWarnings end)
 Nexus.DisableOrdinaryAutomation()
 return H
end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
-- Saved data without two documented records that are not this family's
-- display: the coach's own place (core/GuidedSetup.lua: the guide saves only
-- its place for this character) and the runtime's scheduled compaction note
-- (dataCompaction.last, written by core/DataCompaction.lua maintenance as
-- simulated time runs).
local function Strip(t)
 if type(t)~='table' then return end
 t.guidedSetupPlaceV1=nil
 if type(t.dataCompaction)=='table' then t.dataCompaction.last=nil end
 for _,v in pairs(t) do Strip(v) end
end
local function Saved()
 local copy=loadstring('return '..F.Serialize(NexusDB))()
 Strip(copy)
 return F.Serialize(copy)..'|'..F.Serialize(WishlistRealizerDB or {})
end
-- The coach's first place write creates the owner's durable row (documented
-- coach behaviour); it is made once before a passivity snapshot.
local function PrimeCoachPlace()
 Nexus.GuidedSetupUI.Show();Nexus.GuidedSetup.SetPath('new');Nexus.GuidedSetup.GoTo('wishlist')
 Nexus.GuidedSetupUI.Hide();Nexus.GuidedSetup.GoTo('welcome')
end
local function Effects(H)
 return table.concat({Saved(),'actions='..#H.actions,'sent='..#H.sent,'auto='..tostring(Auto())},' ')
end
-- Where two effect snapshots first differ (failure detail only).
local function Diff(a,b)
 if a==b then return '' end
 local i=1;while i<=#a and a:sub(i,i)==b:sub(i,i) do i=i+1 end
 return ' first difference: before ...'..a:sub(math.max(1,i-80),i+80)..' | after ...'..b:sub(math.max(1,i-80),i+80)
end

-- Data that is never translated: the fixture's character, realm, Saved
-- Build, Wishlist and Echo names, numbers. Pending words of other families
-- are allowed per receiver below, never by word.
local DATA={PrototypeTester=true,Ebonhold=true,Gen=true,plan=true}
local function allowData(word,text) return DATA[word]==true end
local function scan(label,texts,allow)
 local miss=S.Untranslated(texts,function(w,t) return allowData(w,t) or (allow and allow(w,t)) end)
 for _,m in ipairs(miss) do print('UNTRANSLATED '..label..': ['..m.word..'] '..tostring(m.text):sub(1,160)) end
 check(#miss==0,label..': every visible code-owned word passed the seam ('..#miss..' left)')
 return #texts
end
local function anyPseudo(texts)
 for _,t in ipairs(texts) do if S.IsPseudo(t.text or t) then return true end end
 return false
end
local function shownButtons(root)
 local out={}
 for _,c in ipairs(root and root.children or {}) do
  if c.kind=='Button' and c:IsShown() then out[#out+1]=c end
 end
 return out
end
local function P(english) return OPEN..english..CLOSE end
local function buttonWith(root,text)
 for _,b in ipairs(shownButtons(root)) do
  local t=tostring(b:GetText() or '')
  if t:find(text,1,true) then return b end
 end
end
local function hover(frame)
 local fn=frame and frame:GetScript('OnEnter')
 if not fn then return {} end
 local lines=S.CaptureTooltip(fn,frame)
 local leave=frame:GetScript('OnLeave');if leave then leave(frame) end
 return lines
end

------------------------------------------------------------------------
-- P1: Reference, coach, Settings and workspaces under the pseudo pack.
------------------------------------------------------------------------
do
 local H=Boot(nil)
 PrimeCoachPlace()
 local before=Effects(H)
 local L=Nexus.Localization
 check(L.ActiveLanguage()=='frFR','P1 SETUP the pseudo pack is the session language')
 check(L.Diagnostics().base.undeclared==0 and L.Diagnostics().base.missingDeclared==0,'P1 SETUP the composed catalog declares every English entry')

 -- Reference: every page, its tabs, topic card, window buttons and page label.
 local Help=Nexus.Help
 for i,p in ipairs(Help.Pages) do
  Help.Show(p.id)
  local w=_G.NexusHelpWindow
  local texts=S.VisibleTexts(w)
  -- The Auto page appends the panel's live permission lines (Panel family).
  local panelLines={}
  if p.id=='rolling' and Nexus.Panel and Nexus.Panel.AutoDetailLines then
   for _,l in ipairs(Nexus.Panel.AutoDetailLines() or {}) do panelLines[l]=true end
  end
  local filtered={}
  for _,t in ipairs(texts) do
   local text=t.text
   if t.frame==w.body and next(panelLines) then
    local keep={}
    for line in (text..'\n'):gmatch('(.-)\n') do if not panelLines[line] then keep[#keep+1]=line end end
    text=table.concat(keep,'\n')
   end
   filtered[#filtered+1]={text=text,frame=t.frame}
  end
  scan('P1 Reference page '..p.id,filtered)
  check(S.IsPseudo(w.body:GetText()) and S.IsPseudo(w.title:GetText()) and S.IsPseudo(w.page:GetText()),
   'P1 Reference page '..p.id..': body, title and page label reach their FontStrings translated')
  check(w.page:GetText()==P('Page '..i..' / '..#Help.Pages),'P1 Reference page '..p.id..': page position template with its counts')
 end
 -- FAQ: the question lines keep the code-owned gold around translated text.
 Help.Show('faq')
 local faqBody=_G.NexusHelpWindow.body:GetText()
 check(faqBody:find('|cffffd100'..P('What do I do next?')..'|r\n',1,true)==1,'P1 FAQ: a translated question stays its own gold line')
 -- A route refusal reaches the note line and chat translated.
 local chat=S.CaptureChat(function() Help.OpenTopic('no-such-topic') end)
 check(#chat==1 and S.IsPseudo(chat[1]) and chat[1]:find('|cffffd200Nexus:|r ',1,true)==1,'P1 Reference: a refusal reaches chat translated after the code-owned prefix')
 check(S.IsPseudo(_G.NexusHelpWindow.note:GetText()),'P1 Reference: the same refusal is shown on the note line')
 Help.Hide()

 -- Guided setup coach: every step of the new path, then the explore path.
 local U,G=Nexus.GuidedSetupUI,Nexus.GuidedSetup
 local shown=U.Show()
 check(shown==true and _G.NexusGuidedSetup and _G.NexusGuidedSetup:IsShown(),'P1 SETUP the coach opens')
 local f=_G.NexusGuidedSetup
 local function coachScan(label)
  U.Render()
  local texts=S.VisibleTexts(f)
  check(anyPseudo(texts),'P1 coach '..label..': translated words reach the window')
  return scan('P1 coach '..label,texts)
 end
 coachScan('welcome')
 G.SetPath('new')
 for _,id in ipairs(G.STEPS) do
  G.GoTo(id);coachScan('step '..id)
 end
 -- Choices with their read-back words: a listed Wishlist, then each Saved
 -- Build target with its consequence lines, then the Assign step for it.
 G.GoTo('wishlist')
 local wishes=G.WishlistOptions() or {}
 check(#wishes>=1,'P1 SETUP the fixture lists a Wishlist')
 if wishes[1] then G.ChooseWishlist(wishes[1]);coachScan('wishlist chosen') end
 G.GoTo('target');U.Render()
 local targets=G.TargetOptions() or {}
 check(#targets>=1,'P1 SETUP the fixture lists Saved Build targets')
 for i,o in ipairs(targets) do
  if o.destination~=nil then G.ChooseTarget(o.destination);coachScan('target '..tostring(o.destination)) end
  if i>=4 then break end
 end
 G.GoTo('assign');coachScan('assign for the chosen target')
 G.GoTo('auto');coachScan('auto with a choice made')
 G.GoTo('summary');coachScan('summary with choices')
 -- The kicker template: "Step N of M" with both counts.
 G.GoTo('wishlist');U.Render()
 check(U.VisibleText():find(P('Step 2 of 7'),1,true)~=nil,'P1 coach: the step line template shows its counts')
 -- Wishlist paste check with nothing pasted: its refusal line.
 if U.CheckImport then U.CheckImport();coachScan('wishlist import refusal') end
 -- The step list toggle, the Auto expander and the simulated preview.
 local toggle=buttonWith(f,P('All steps v'))
 check(toggle~=nil,'P1 coach: the All steps toggle shows translated')
 if toggle then toggle:Click();coachScan('all steps open');local again=buttonWith(f,P('All steps ^'));if again then again:Click() end end
 G.GoTo('auto');U.Render()
 local more=buttonWith(f,P('> What does Auto do?'))
 if more then more:Click();coachScan('auto explained') end
 G.GoTo('manual');G.SimPick(1);coachScan('preview picked as recommended');G.SimPick(2);coachScan('preview picked another')
 G.GoTo('summary');U.Render()
 local lessons=0
 for _,b in ipairs(shownButtons(f)) do
  local t=tostring(b:GetText())
  if t:sub(-#P('Read'))==P('Read') then lessons=lessons+1;b:Click();coachScan('summary lesson '..lessons);break end
 end
 check(lessons>=1,'P1 coach: a summary lesson opens with translated text')
 -- The header Reference view: its topic list and each short article.
 G.GoTo('target');U.Render()
 local ref=f.help
 check(ref and S.IsPseudo(ref:GetText()),'P1 coach: the header Reference button is translated')
 if ref then
  ref:Click();coachScan('Reference topics')
  for _,topic in ipairs(Nexus.UserText.Guide.reference.topics) do
   local b=buttonWith(f,P(topic.title))
   check(b~=nil,'P1 coach Reference: topic '..topic.page..' is listed translated')
   if b then b:Click();coachScan('Reference topic '..topic.page);local back=buttonWith(f,P('< All topics'));if back then back:Click() end end
  end
  ref:Click()
 end
 -- The close button's hover and the close chat lines.
 local tip=hover(f.close)
 -- Its first line is the raw close glyph "X" (a symbol); the hint follows.
 check(#tip==2 and tip[1]=='X' and S.IsPseudo(tip[2]),'P1 coach: the close hover hint is translated')
 local closeChat=S.CaptureChat(function() U.Close() end)
 check(#closeChat>=2,'P1 coach: closing says where it paused and how to reopen')
 for i,line in ipairs(closeChat) do check(S.IsPseudo(line) and not S.LooksUntranslated(line,allowData),'P1 coach close chat line '..i..' is translated') end
 -- The explore path and the summary close.
 U.Show();G.SetPath('explore')
 for _,id in ipairs(G.EXPLORE) do G.GoTo(id);coachScan('explore '..id) end
 local finishChat=S.CaptureChat(function() U.Close('finish') end)
 check(#finishChat>=1 and S.IsPseudo(finishChat[1]),'P1 coach: the look-around close line is translated')

 -- Settings: every category, every page, every row and category hover.
 local SW=Nexus.SettingsWindow
 SW.Show('automation')
 local win=_G.NexusSettingsWindow
 local OTHER={automation=true,appearance=true,language=true,display=true,notices=true}
 for _,cat in ipairs(SW.Categories()) do
  SW.Select(cat)
  -- Rows of other owners (Panel, Theme) keep their owners' words (pending).
  local foreign={}
  local policy=Nexus.SyncModePolicy
  if policy and policy.Text and policy.Mode then foreign[policy.Text(policy.Mode())]=true end
  for _,row in ipairs(SW.Rows(cat)) do
   if OTHER[cat] then foreign[row.text]=true;foreign['[x] '..row.text]=true;foreign[row.detail or '']=true end
  end
  -- The window title stays English (pending: terminology lint coupling).
  foreign['Nexus Settings']=true
  local function allowForeign(w,t) return foreign[t]==true end
  local pages=0
  repeat
   pages=pages+1
   local texts=S.VisibleTexts(win)
   scan('P1 Settings '..cat..' page '..pages,texts,allowForeign)
   for _,b in ipairs(shownButtons(win)) do
    if b._nexusFullLabel then
     local lines=hover(b._nexusInfoHover and b._nexusInfoHover:IsShown() and b._nexusInfoHover or b)
     local items={};for _,l in ipairs(lines) do items[#items+1]={text=l} end
     scan('P1 Settings '..cat..' row hover',items,allowForeign)
    end
   end
   local nextBtn=buttonWith(win,P('Next'))
   local more=nextBtn and nextBtn:IsEnabled()
   if more then nextBtn:Click() end
  until not more or pages>10
 end
 local catHovers=0
 for _,b in ipairs(shownButtons(win)) do
  local lines=hover(b)
  if #lines==2 then
   catHovers=catHovers+1
   check(S.IsPseudo(lines[1]) and S.IsPseudo(lines[2]),'P1 Settings: category hover '..catHovers..' is translated')
  end
 end
 check(catHovers==#SW.Categories(),'P1 Settings: every category button has its translated hover ('..catHovers..')')
 SW.Select('sync')
 check(SW.Rows('sync')[1].text==P('Current Sync: '..P('Manual')),'P1 Settings: Current Sync nests the translated mode name in its template')
 SW.Hide()

 -- Plan / Explore workspace tabs and their hovers; reason display.
 local WS=Nexus.FullUIWorkspaces
 local ok=WS.ShowPlan()
 local ed=_G.NexusEditorFrame
 check(ok==true and ed and ed._workspaceTabs,'P1 SETUP the Plan workspace opens with its tabs')
 if ed and ed._workspaceTabs then
  for _,key in ipairs({'plan','builds','records'}) do
   local b=ed._workspaceTabs[key]
   -- While shared data loads, LoadingStatus repaints a shared tab with the
   -- label ui/WishlistRenderer.lua gave it and owns its hover (pending:
   -- another family). The bound labels are checked on fresh tabs below.
   if not b._nexusDataLoading then
    check(S.IsPseudo(b:GetText()),'P1 workspace tab '..key..' text is translated')
    local lines=hover(b)
    check(#lines==2 and S.IsPseudo(lines[1]) and S.IsPseudo(lines[2]),'P1 workspace tab '..key..' hover is translated')
   end
  end
 end
 -- The real BindTabs on fresh buttons: every label and hover, active in gold.
 local host=CreateFrame('Frame',nil,UIParent)
 local tabs={plan=CreateFrame('Button',nil,host),builds=CreateFrame('Button',nil,host),records=CreateFrame('Button',nil,host)}
 check(WS.BindTabs(host,'records',tabs)==true,'P1 SETUP BindTabs binds fresh tabs')
 check(tabs.records:GetText()=='|cffffd200'..P('Records')..'|r' and tabs.plan:GetText()==P('Plan') and tabs.builds:GetText()==P('Explore'),
  'P1 workspace: bound tab labels are translated, the active one in its code-owned gold')
 for key,b in pairs(tabs) do
  local lines=hover(b)
  check(#lines==2 and S.IsPseudo(lines[1]) and S.IsPseudo(lines[2]),'P1 workspace tab '..key..' hover is translated')
 end
 host:Hide()
 check(WS.ReasonText('wishlist editor unavailable')==P('wishlist editor unavailable'),'P1 workspace: its own reason shows translated')
 check(WS.ReasonText('another owner reason')=='another owner reason','P1 workspace: another owner\'s reason is shown as given')
 if ed then ed:Hide() end

 -- Template slots: unknown is "?", zero is "0", names are verbatim.
 check(L.Format('help.label.page_position',{page=L.Count(nil),total=L.Count(0)})==P('Page ? / 0'),'P1 template: unknown count is ?, zero is 0')
 check(L.Format('guide.body.wishlist_selected',{wishlist=LONG})==P('Selected: '..LONG),'P1 template: a long UTF-8 name is inserted verbatim')
 check(L.Format('setup.status.steps_done_open',{done=L.Count(0),total=L.Count(5)})==P('Setup steps done now: 0 of 5. Nothing here completes a step for you.'),'P1 template: zero done keeps 0')

 local after=Effects(H)
 check(after==before,'P1 PASSIVE: rendering, hovering, navigating and closing changed no saved data, action, send or Auto'..Diff(before,after))
 check(not Auto(),'P1 PASSIVE: Auto stays OFF')
 local d=L.Diagnostics()
 check((d.byReason.unknown_key or 0)==0 and (d.byReason.invalid_key or 0)==0,'P1: no unknown or invalid key was looked up')
end

------------------------------------------------------------------------
-- P2: the overwrite warning, the information-only Welcome and the checklist.
------------------------------------------------------------------------
do
 local H=Boot(nil,nil,function(db) db.overwriteWarnings=nil end,true)
 local before=Effects(H)
 -- The first-launch warning's real entry (QuickStart.ShowIfFirstTime asks it).
 check(Nexus.OverwriteWarning.EnsureOnboarding()=='pending','P2 SETUP the first-launch warning asks')
 local w=_G.NexusOverwriteWarning
 check(w and w:IsShown(),'P2 SETUP the first-launch warning is open')
 local texts=S.VisibleTexts(w)
 scan('P2 first-launch warning while reading',texts,function(word,t) return t=='X' end)
 check(w.countdown:GetText()==P('Read the warning: 5 seconds'),'P2 countdown template shows its count')
 check(w.yes:GetText()==P('Continue \226\128\148 Auto stays OFF') and w.no:GetText()==P('Close'),'P2 first-launch answers are translated')
 local body=w.body:GetText()
 check(body==P('Auto can overwrite your active game Saved Build. It may replace Echoes you value, including Echoes obtained with Orbs. Nexus cannot undo that save or recover spent Orbs.')
  ..'\n\n'..P('After a finished run at level 80, changing the assignment or saving edits to its assigned Wishlist can cause replacement without a new run.')
  ..'\n\n'..P('Continue may open the guided setup if this is your first use. Close opens information-only setup. Neither turns Auto on.'),
  'P2 the complete consequence and the first-launch choices, in order')
 -- The reading delay passes on the warning's own clock read; only the
 -- warning's countdown runs (no other scheduler turn is simulated).
 H.now=H.now+5.2
 w:GetScript('OnUpdate')(w,0)
 check(w.countdown:GetText()==P('Do you understand?') and w.yes:IsEnabled(),'P2 after the reading delay: translated question, answers enabled')
 -- No (Close): declines and opens the information-only Welcome.
 w.no:Click()
 local q=_G.NexusQuickStart
 check(not w:IsShown() and q and q:IsShown(),'P2 Close opens the information-only Welcome')
 scan('P2 information-only Welcome',S.VisibleTexts(q))
 check(q.title:GetText()==P('Nexus setup (information only)'),'P2 Welcome replay title is translated')
 -- The checklist: its status lines are UserText's (pending, another family).
 local c=Nexus.QuickStart.ShowChecklist()
 local statusFS={};for _,fs in ipairs(c.status or {}) do statusFS[fs]=true end
 local items={}
 for _,t in ipairs(S.VisibleTexts(c)) do if not statusFS[t.frame] then items[#items+1]=t end end
 scan('P2 Setup checklist',items)
 check(S.IsPseudo(c.summary:GetText()),'P2 checklist summary template reaches its FontString')
 c:Hide()
 -- The Auto kind: requested, read and cancelled; never accepted.
 local accepted=0
 local owner={}
 Nexus.OverwriteWarning.RequestAuto(owner,function() accepted=accepted+1;return true end)
 check(w:IsShown(),'P2 SETUP the Auto warning is open')
 local readout=Nexus.Readout
 local pendingLines={}
 if readout and readout.AutomationScopeLines then
  -- The same read the warning makes (ui/OverwriteWarning.lua BodyText).
  local okS,settings=pcall(Nexus.Store.Settings)
  local internals=Nexus.MainInternals
  local okR,readOnly=false,nil
  if internals and internals.SavedRootReadOnlyV1 then okR,readOnly=pcall(internals.SavedRootReadOnlyV1) end
  for _,l in ipairs(readout.AutomationScopeLines({selected=false,settings=okS and settings or nil,
   readOnly=okR and readOnly~=nil and readOnly~=false}) or {}) do pendingLines[l]=true end
  if type(readout.TOME_PARAGRAPH)=='string' then pendingLines[readout.TOME_PARAGRAPH]=true end
 end
 local abody={}
 for line in (w.body:GetText()..'\n'):gmatch('(.-)\n') do if not pendingLines[line] then abody[#abody+1]=line end end
 scan('P2 Auto warning (Readout lines are another family\'s)',{{text=table.concat(abody,'\n')}})
 check(w.body:GetText():find(P('Choose No to keep Auto OFF. Opening this warning does not enable Auto.'),1,true)~=nil,'P2 Auto warning keeps its closing consent line')
 check(w.yes:GetText()==P('Yes') and w.no:GetText()==P('No'),'P2 Auto warning answers are translated')
 Nexus.OverwriteWarning.CancelAuto(owner)
 check(accepted==0 and not w:IsShown(),'P2 cancelled: nothing accepted')
 local after=Effects(H)
 check(after==before and not Auto(),Diff(before,after)..'P2 PASSIVE: reading, answering No and cancelling changed no saved data, action, send or Auto')
end

------------------------------------------------------------------------
-- P3: long pseudo mode on the densest windows.
------------------------------------------------------------------------
do
 local H=Boot('long')
 PrimeCoachPlace()
 local before=Effects(H)
 for _,p in ipairs(Nexus.Help.Pages) do
  local ok,err=pcall(Nexus.Help.Show,p.id)
  local body=_G.NexusHelpWindow and _G.NexusHelpWindow.body:GetText() or ''
  check(ok and #body>0 and S.IsPseudo(body),'P3 long: Reference page '..p.id..' renders its text ('..tostring(err)..')')
 end
 Nexus.Help.Hide()
 local U,G=Nexus.GuidedSetupUI,Nexus.GuidedSetup
 U.Show();G.SetPath('new')
 for _,id in ipairs(G.STEPS) do
  G.GoTo(id)
  local ok,err=pcall(U.Render)
  check(ok and S.IsPseudo(U.VisibleText()),'P3 long: coach step '..id..' renders ('..tostring(err)..')')
 end
 U.Hide()
 Nexus.SettingsWindow.Show('support')
 check(S.IsPseudo(Nexus.SettingsWindow.Rows('support')[1].text),'P3 long: Settings rows render')
 Nexus.SettingsWindow.Hide()
 local after=Effects(H)
 check(after==before,'P3 PASSIVE: nothing changed'..Diff(before,after))
end

------------------------------------------------------------------------
-- P4: a pack without some guide-family keys shows their exact English.
------------------------------------------------------------------------
do
 local entries=S.PseudoEntries()
 local removed={'help.button.previous','help.body.start_first_task','help.tab.faq','guide.button.next',
  'settings.button.next','setup.button.reference','workspace.tab.plan','guide.label.kicker'}
 for _,k in ipairs(removed) do check(entries[k]~=nil,'P4 SETUP '..k..' is a catalog key');entries[k]=nil end
 local H=Boot(nil,entries)
 Nexus.Help.Show('start')
 local w=_G.NexusHelpWindow
 local body=w.body:GetText()
 local first=Nexus.Localization.Resolve('help.body.start_first_task')
 check(body:sub(1,#first+2)==first..'\n\n','P4 a missing page block shows its exact English in place')
 check(body:find(OPEN,1,true)~=nil,'P4 the other blocks of the page stay translated')
 check(buttonWith(w,'Previous') and buttonWith(w,'Previous'):GetText()=='Previous','P4 a missing button key shows exact English')
 check(w.tabs[8]:GetText()=='FAQ' and S.IsPseudo(w.tabs[1]:GetText()),'P4 a missing tab shows English beside translated tabs')
 Nexus.Help.Hide()
 local U,G=Nexus.GuidedSetupUI,Nexus.GuidedSetup
 U.Show();G.SetPath('new');G.GoTo('wishlist');U.Render()
 check(U.VisibleText():find('Step 2 of 7',1,true)~=nil and not U.VisibleText():find(P('Step 2 of 7'),1,true),'P4 a missing coach template shows the exact English sentence')
 check(buttonWith(_G.NexusGuidedSetup,'Continue') and buttonWith(_G.NexusGuidedSetup,'Continue'):GetText()=='Continue','P4 a missing coach word shows exact English')
 U.Hide()
 Nexus.SettingsWindow.Show('support')
 check(buttonWith(_G.NexusSettingsWindow,'Next'):GetText()=='Next','P4 Settings: a missing key shows exact English')
 Nexus.SettingsWindow.Hide()
 Nexus.FullUIWorkspaces.ShowPlan()
 local ed=_G.NexusEditorFrame
  check(ed and ed._workspaceTabs and ed._workspaceTabs.plan:GetText()=='|cffffd200Plan|r',
  'P4 workspace: the missing active tab label shows exact English in its code-owned colour')
 if ed then ed:Hide() end
end

------------------------------------------------------------------------
-- P5: English.
------------------------------------------------------------------------
do
 local H=Boot('english')
 local L=Nexus.Localization
 check(L.ActiveLanguage()=='enUS','P5 SETUP English is the session language')
 local Help=Nexus.Help
 for _,p in ipairs(Help.Pages) do
  check(Help.PageText(p)==p.text,'P5 page '..p.id..': its catalog blocks join to the exact English page text')
  Help.Show(p.id)
  if p.id~='faq' and p.id~='rolling' then check(_G.NexusHelpWindow.body:GetText()==p.text,'P5 page '..p.id..' is shown exactly') end
 end
 Help.Show('start')
 check(_G.NexusHelpWindow.title:GetText()=='Nexus Reference - Getting started' and _G.NexusHelpWindow.page:GetText()=='Page 1 / 8',
  'P5 Reference title and page label are exact English')
 Help.Hide()
 -- Every T("key", "English") literal in the family's files is that key's English.
 local literals=0
 for _,file in ipairs(FILES) do
  local src=S.readFile(file)
  for key,lit in src:gmatch('T%(%s*"([%l%d_%.]+)"%s*,%s*("[^"\n]*")%s*%)') do
   literals=literals+1
   local english=assert(loadstring('return '..lit))()
   check(L.Resolve(key)==english,'P5 '..file..': '..key..' is its English base')
  end
 end
 check(literals>=80,'P5 SETUP the family literals were read ('..literals..')')
 -- Every coach word with a catalog key is still that key's English: the
 -- coach view shows UserText's own words in an English session.
 local U,G=Nexus.GuidedSetupUI,Nexus.GuidedSetup
 U.Show();G.SetPath('new');G.GoTo('target');U.Render()
 local guide=Nexus.UserText.Guide
 check(U.VisibleText():find(guide.target.title,1,true)~=nil and U.VisibleText():find('Step 3 of 7',1,true)~=nil,'P5 coach shows UserText\'s exact English')
 -- R5 copy correction (paired raw leaf and catalog): the Saved Build uses the
 -- Wishlist; choosing the target is only a choice.
 local why='A Saved Build is the build slot the game loads. Choose which Saved Build should use your Wishlist.'
 check(guide.why.target==why and L.Text('guide.body.why_target')==why,'R5 why_target: the raw leaf and the catalog say the same corrected English')
 check(U.VisibleText():find(why,1,true)~=nil and not U.VisibleText():find('will follow',1,true),'R5 why_target: the target step shows the corrected English: '..U.VisibleText():sub(1,300))
 U.Hide()
 check(L.Format('guide.label.kicker',{step=L.Count(3),total=L.Count(7)})=='Step 3 of 7','P5 template English')
 check(L.Diagnostics().misses==0,'P5 English boot and display resolved without any fallback')
end

-- R5 (FULLUI-GUIDE-SPEC-P2-01): a valid static translation of one leaf
-- (guide.button.next = "Step %d of %d", literal percent signs) must not make
-- an unrelated printf leaf of the same English contents (the step kicker)
-- skip its own counts, key and fallback. Real startup -> Show -> Wishlist
-- step -> Render -> VisibleText, one fresh boot per case.
do
 local function Coach(entries)
  local H=Boot('wrap',entries)
  local U,G=Nexus.GuidedSetupUI,Nexus.GuidedSetup
  local before=Effects(H)
  U.Show();G.SetPath('new');G.GoTo('wishlist');U.Render()
  return U.VisibleText(),U,H,before
 end
 -- 1. Colliding label, missing kicker entry: the kicker's exact English counts.
 local e=S.PseudoEntries();e['guide.button.next']='Step %d of %d';e['guide.label.kicker']=nil
 local text,U=Coach(e)
 check(text:find('Step 2 of 7',1,true)~=nil,'R5 guide: a missing kicker falls back to exact English with its counts despite the colliding label: '..text:sub(1,200))
 check(buttonWith(_G.NexusGuidedSetup,'Step %d of %d')~=nil,'R5 guide: the colliding static label is shown literally on its button')
 -- 2. Colliding label, independent translated kicker: its own template and counts.
 e=S.PseudoEntries();e['guide.button.next']='Step %d of %d';e['guide.label.kicker']='Schritt {step}/{total}'
 text=Coach(e)
 check(text:find('Schritt 2/7',1,true)~=nil and not text:find('Schritt {step}',1,true),'R5 guide: the kicker keeps its own translation and counts: '..text:sub(1,200))
 -- 3. Non-colliding literal percent: shown literally; the kicker is unaffected.
 e=S.PseudoEntries();e['guide.button.next']='Weiter (100%)'
 local text3=Coach(e)
 check(buttonWith(_G.NexusGuidedSetup,'Weiter (100%)')~=nil,'R5 guide: a literal percent in a static label stays literal')
 check(text3:find(P('Step 2 of 7'),1,true)~=nil,'R5 guide: the translated kicker keeps its counts beside a literal-percent label')
end

if #failed>0 then error('l10n_ui_guide: '..#failed..' of '..checks..' checks failed; first: '..failed[1]) end
print('PASS l10n_ui_guide checks='..checks..' (pseudo, long, missing-entry and English phases; synthetic offline, native NOT_RUN)')
