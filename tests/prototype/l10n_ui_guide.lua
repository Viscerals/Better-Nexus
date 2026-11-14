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
--  P6 the Assign step's result bodies (changed, other, partial, stale and the
--     two-field mismatch) in each of the six real language packs chosen by
--     the saved interface language, and in English as the name-role control.
-- Synthetic offline evidence only: no glyph, font, layout or native claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
-- The Reference document as shown (all of Help's parts, test-only V.HelpDocument).
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
-- The loader before any pseudo boot hook (S.InstallBootHook replaces it until
-- its one use); P6 boots only with this one.
local PRISTINE_LOADFILE=loadfile
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
-- The actual Help route to Guided setup while a warning waits (no stub:
-- GuidedSetupUI.Show itself refuses for any open warning kind). Returns
-- whether it ran, its result and refusal, and what chat heard.
local function OpenGuideHeard()
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...)) end
 local ok,shown,why=pcall(function() return Nexus.Help.OpenGuide() end)
 print=realPrint
 return ok,shown,why,table.concat(heard,' / ')
end
-- The blocked-guide refusal is accurate for every warning kind: Guided setup
-- did not open, answer the open warning, then open Guided setup again. It
-- names no answer button (first-launch shows Continue / Close, Auto Yes / No).
local function AccurateGuideRefusal(text)
 text=tostring(text or '')
 return text:find('Guided setup did not open.',1,true)~=nil
  and text:find('Answer the open warning',1,true)~=nil
  and text:find('then open Guided setup again.',1,true)~=nil
  and text:find('(Yes or No)',1,true)==nil
  and text:find('%f[%a]Yes%f[%A]')==nil and text:find('%f[%a]No%f[%A]')==nil
end
local function CoachOpen() return _G.NexusGuidedSetup~=nil and NexusGuidedSetup:IsShown() end

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
  -- R5 (Source86): the window title is keyed (settings.title.window); it is
  -- no longer allowed raw.
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
 -- Help's Guided setup route while the first-launch warning still waits: the
 -- real refusal, which must not name Yes / No (this warning shows Continue /
 -- Close). Nothing is answered to reach it; nothing opens or changes.
 do
  local pre=Effects(H)
  local ok,shown,why,said=OpenGuideHeard()
  check(ok and shown==false and type(why)=='string' and why~='' and S.IsPseudo(why) and AccurateGuideRefusal(why),
   'P2 first-launch warning open: Help.OpenGuide refuses, says to answer the open warning and retry, and names no Yes / No '..tostring(why))
  check(type(why)=='string' and why~='' and said:find(why,1,true)~=nil,'P2 first-launch warning open: chat says the same refusal '..said)
  check(not CoachOpen() and w:IsShown() and Nexus.OverwriteWarning.IsOpen()
   and w.yes:GetText()==P('Continue \226\128\148 Auto stays OFF') and w.no:GetText()==P('Close') and w.yes:IsEnabled(),
   'P2 first-launch warning open: no coach; the warning, its answers and their labels stay')
  local post=Effects(H)
  check(post==pre and not Auto(),Diff(pre,post)..'P2 first-launch warning open: the refused Guide route changed no saved data, action, send or Auto')
 end
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
 -- Help's Guided setup route while the Auto warning still waits: the same
 -- accurate refusal; the warning is neither answered nor accepted.
 do
  local pre=Effects(H)
  local ok,shown,why,said=OpenGuideHeard()
  check(ok and shown==false and type(why)=='string' and why~='' and S.IsPseudo(why) and AccurateGuideRefusal(why),
   'P2 Auto warning open: Help.OpenGuide refuses, says to answer the open warning and retry '..tostring(why))
  check(type(why)=='string' and why~='' and said:find(why,1,true)~=nil,'P2 Auto warning open: chat says the same refusal '..said)
  check(accepted==0 and not CoachOpen() and w:IsShown() and Nexus.OverwriteWarning.IsOpen()
   and w.yes:GetText()==P('Yes') and w.no:GetText()==P('No'),
   'P2 Auto warning open: nothing accepted, no coach; the warning and its Yes / No labels stay')
  local post=Effects(H)
  check(post==pre and not Auto(),Diff(pre,post)..'P2 Auto warning open: the refused Guide route changed no saved data, action, send or Auto')
 end
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
 local body=V.HelpDocument(w)
 local first=Nexus.Localization.Resolve('help.body.start_first_task')
 -- Accepted v23 form: the page's own (translated) title as the gold heading
 -- and a blank line come first; the missing first block follows at once.
 local head='|cffffd100'..Nexus.Localization.Text('help.title.page_start')..'|r\n\n'
 check(body:sub(1,#head+#first+2)==head..first..'\n\n','P4 a missing page block shows its exact English in place, under its title')
 check(body:find(OPEN,1,true)~=nil,'P4 the other blocks of the page stay translated (whole shown document)')
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
  -- Accepted v23 form, restated independently (V.HelpReferenceExpected),
  -- compared with the whole shown document.
  if p.id~='faq' and p.id~='rolling' then
   check(V.HelpDocument(_G.NexusHelpWindow)==V.HelpReferenceExpected((L.Text(p.titleKey)),p.text),'P5 page '..p.id..' is shown exactly, under its title')
  end
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
 -- R5 P526: the consequence line for the Saved Build the Echo Journal
 -- targets: the traced trigger, no latency promise (raw leaf = catalog).
 local active='The Echo Journal targets this slot now, so the next recommendation Nexus makes uses the new Wishlist.'
 check(guide.target.cActive==active and L.Text('guide.body.target_c_active')==active,'R5 target_c_active: the raw leaf and the catalog say the traced English')
 -- (The real replace card that shows it: guided_setup_flow F12.)
 check(not U.VisibleText():find('right away',1,true),'R5 target_c_active: no latency promise is shown')
 -- R5 P525: the Options window title, keyed at creation and Refresh.
 local SWin=Nexus.SettingsWindow
 SWin.Show()
 local titled=false
 for _,t in ipairs(S.VisibleTexts(_G.NexusSettingsWindow)) do if t.text=='Nexus Options' then titled=true end end
 check(titled and L.Text('settings.title.window')=='Nexus Options','R5 settings title: the window says Nexus Options')
 SWin.Refresh()
 titled=false
 for _,t in ipairs(S.VisibleTexts(_G.NexusSettingsWindow)) do if t.text=='Nexus Options' then titled=true end end
 check(titled,'R5 settings title: Refresh keeps the keyed title')
 _G.NexusSettingsWindow:Hide()
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

------------------------------------------------------------------------
-- P6: the Assign step's unconfirmed result bodies in the six real language
-- packs, and in English as the name-role control. Each session is a real TOC
-- boot whose language is the saved interface language (settings.uiLanguage);
-- no pseudo pack. The scenario is the reproduced one: public Wishlist and
-- Saved Build choices, replacement consent where the slot follows another
-- Wishlist, ArmAssign / BeginAssign / Note receipts, the real core
-- AssignStatus and the real U.Render. The only synthetic inputs are bounded
-- seams for Saved Build 2: its assignment read back and its action token.
-- No status, localization, FormatCopy, Fmt or render function is replaced.
-- A one-field sentence gets only its own field: changed, partial and stale
-- the Saved Build, other the other Wishlist the receipt names (never the
-- Saved Build or the read back); the two-field mismatch keeps the Saved Build
-- and the Wishlist read back. Each whole body is checked at its FontString.
-- Rendering is passive (no adapter assignment write, action, send, saved
-- change or Auto) and Continue keeps waiting on every unconfirmed result.
------------------------------------------------------------------------
do
 -- Every earlier boot hook removed itself on its one use; any leftover one
 -- is removed here, so no pseudo pack reaches these boots.
 if loadfile~=PRISTINE_LOADFILE then loadfile=PRISTINE_LOADFILE end
 check(loadfile==PRISTINE_LOADFILE,'P6 SETUP no pseudo boot hook is installed')
 -- Distinct player-owned names (UTF-8): the chosen Wishlist, the other
 -- Wishlist a receipt names, the Wishlist read back and the Saved Build.
 local CHOSEN='Chosen Wishlist player-name \195\156'
 local OTHER='Other Wishlist player-name \206\169'
 local READBACK='Read-back Wishlist player-name \195\159'
 local BUILD='Saved Build QA Dest'
 local KEYS={changed='guide.body.assign_stale_body_changed',other='guide.body.assign_stale_body_other',
  partial='guide.body.assign_stale_body_partial',stale='guide.body.assign_stale_body_stale',
  mismatch='guide.body.assign_stale_body_mismatch'}
 local STATES={'changed','other','partial','stale','mismatch'}
 local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','ClearLoadoutWishlist','ClearFirstRunWishlist',
  'ConfirmWishlistRoles','SetLoadoutWishlistIdentity'}
 local function clone(t) local r={};for k,v in pairs(t) do r[k]=v end;return r end
 -- Either client boolean convention (harness.lua).
 local function enabled(b) local v=b and b:IsEnabled();return v==true or v==1 end
 -- A coach FontString drawn this render (shown, or one scroll away: the
 -- bounded window marks it _nexusOut) whose whole text is exactly `text`.
 local function shownExactly(root,text)
  for _,r in ipairs(root.regions or {}) do
   if r.kind=='FontString' and r:GetText()==text and (r:IsShown() or r._nexusOut) then return true end
  end
  return false
 end
 -- A coach button drawn this render whose complete label (Arm: b.full, also
 -- when the shown text is fitted) is exactly `text`.
 local function buttonExactly(root,text)
  for _,b in ipairs(root.children or {}) do
   if b.kind=='Button' and (b:IsShown() or b._nexusOut) and (b.full==text or b:GetText()==text) then return b end
  end
 end
 local function Session(language)
  local H=F.Boot(F.Database{mutate=function(db)
   db.hasSeenQuickStart=true
   if language~='enUS' then db.settings.uiLanguage=language end
   db.chars[F.NAME].loadoutWishlists={}
  end},function(h)
   h.playerLevel=80
   h.AddEcho(201172,'Echo One',0,5);h.AddEcho(201173,'Echo Six',0,5)
   h.AddEcho(201174,'Echo Free',0,5);h.AddEcho(201175,'Echo Fire',0,5)
   h.service.GetServerMaxSlots=function() return 6 end
   h.perks.serverBuildSlots={
    [1]={name='Saved Build One',verified=true,echoes={{spellId=201172,quality=0,stacks=1}}},
    [2]={name=BUILD,verified=true,echoes={{spellId=201175,quality=0,stacks=1}}},
    [106]={name='Other pool',verified=false,echoes={{spellId=201173,quality=0,stacks=1}}},
    [107]={name=CHOSEN,verified=false,echoes={{spellId=201174,quality=0,stacks=1}}}}
   h.perks.serverActiveSlot=2
   F.OrbService(h)
  end)
  H.Notify();Nexus.GameAdapter.Poll();H.Advance(1)
  Nexus.DisableOrdinaryAutomation()
  return H
 end

 for _,language in ipairs({'deDE','esES','frFR','plPL','ptBR','ruRU','enUS'}) do
  local H=Session(language)
  local A,L,G,U=Nexus.GameAdapter,Nexus.Localization,Nexus.GuidedSetup,Nexus.GuidedSetupUI
  local english=language=='enUS'
  local tag='P6 '..language
  check(L.ActiveLanguage()==language,tag..' SETUP the saved interface language is the session language')
  if not english then
   check(type(Nexus.LocalizationPacks)=='table' and type(Nexus.LocalizationPacks[language])=='table',tag..' SETUP its real pack is loaded')
  end
  local SafeName=Nexus.UserText.SafeName
  check(SafeName(CHOSEN)==CHOSEN and SafeName(OTHER)==OTHER and SafeName(READBACK)==READBACK,
   tag..' SETUP the UTF-8 Wishlist names are safe player text as they are')
  local guide=Nexus.UserText.Guide
  -- The result head and the chooser's again label: static copy leaves.
  local headKey,againKey='guide.body.assign_stale','guide.button.open_again'
  check(L.Resolve(headKey)==guide.assign.stale and L.Resolve(againKey)==guide.buttons.openAgain,
   tag..' SETUP the result head and chooser-again keys are those copy leaves')
  local head,again=L.Text(headKey),L.Text(againKey)
  -- Counted pass-throughs: an assignment write would be seen, never made here.
  local writes=0
  for _,name in ipairs(WRITERS) do
   local real=A[name]
   if type(real)=='function' then A[name]=function(...) writes=writes+1;return real(...) end end
  end
  local candidate
  for _,v in ipairs(A.GetWishlistCandidates() or {}) do if tonumber(v.slot)==107 then candidate=v end end
  check(candidate~=nil and candidate.name==CHOSEN,tag..' SETUP the chosen Wishlist is listed under its own name')
  local originalRead,originalToken=G.ReadAssignment,A.AssignmentActionToken

  local function Run(state)
   local st=tag..' '..state
   G.ReadAssignment,A.AssignmentActionToken=originalRead,originalToken
   G.Replay();G.SetPath('existing')
   check(U.Show()==true,st..' SETUP the coach opens')
   local chose,targeted=G.ChooseWishlist(candidate),G.ChooseTarget(2)
   local w=G.State().wishlist
   check(chose==true and targeted==true and w~=nil,st..' SETUP public Wishlist and Saved Build choices')
   if not w then return end
   -- other and mismatch: Saved Build 2 follows another Wishlist (read back).
   local replaced=state=='other' or state=='mismatch'
   local read=replaced and {state='assigned',key='readback-wishlist-key',name=READBACK,action='base-action'}
    or {state='none',action='base-action'}
   local token='base-action'
   G.ReadAssignment=function(destination)
    if destination~=2 then return originalRead(destination) end
    return clone(read)
   end
   A.AssignmentActionToken=function(destination,...)
    if destination~=2 then return originalToken(destination,...) end
    return token
   end
   local consent=not replaced or G.ConfirmReplace()
   local armed=G.ArmAssign()
   check(consent==true and armed==true,st..' SETUP public replacement consent and bound assignment request')
   if not (consent and armed) then return end
   if state=='changed' then
    read.action='later-action'
   else
    local key=state=='other' and 'other-wishlist-key' or w.key
    local origin=G.BeginAssign(2,key)
    check(origin~=nil,st..' SETUP public operation origin')
    if not origin then return end
    if not replaced then token='own-action' end
    G.Note('assign',{destination=2,ok=true,key=key,name=state=='other' and OTHER or w.name,
     guide=origin,origin='bounded-synthetic-readback-regression'})
    if state=='partial' then read={state='roles',key=w.key,name=w.name,action='own-action'}
    elseif state=='stale' then read={state='assigned',key=w.key,name=w.name,action='later-action'} end
   end
   check(G.GoTo('assign')==true,st..' SETUP the Assign step')
   local status=G.AssignStatus()
   check(status.state==state,st..' SETUP the real core status ('..tostring(status.state)..')')
   if status.state~=state then return end
   local facts=G.TargetFacts()
   check(facts~=nil and facts.ready==true,st..' SETUP the result view is reached')
   if not facts then return end
   check(not G.CanNext(),st..': an unconfirmed result never allows Continue')
   if state=='other' then check(status.name==OTHER and status.readName==READBACK,st..' SETUP the receipt and the read back name different Wishlists') end
   if state=='mismatch' then check(status.readName==READBACK,st..' SETUP the read back names its Wishlist') end
   -- The Saved Build as the view labels it (guide.body.target_slot).
   local dest=L.Format('guide.body.target_slot',{slot=L.Count(2),name=SafeName(facts.name)})
   check(dest:find(BUILD,1,true)~=nil,st..' SETUP the Saved Build label holds its name')
   local fields
   if state=='other' then fields={other=SafeName(status.name)}
   elseif state=='mismatch' then fields={build=dest,other=SafeName(status.readName)}
   else fields={build=dest} end
   local expected,source=L.Format(KEYS[state],fields)
   check(type(expected)=='string' and source~='unavailable',st..' SETUP the pack template formats with its own fields')
   if type(expected)~='string' then return end
   local raw=guide.assign.staleBody[state]
   local englishForm
   if state=='other' then englishForm=string.format(raw,SafeName(OTHER))
   elseif state=='mismatch' then englishForm=string.format(raw,dest,SafeName(READBACK))
   else englishForm=string.format(raw,dest) end
   if english then check(expected==englishForm,st..': English keeps its exact sentence')
   else check(expected~=englishForm,st..' SETUP the pack translates this sentence') end
   -- Whose name the sentence carries.
   if state=='other' then
    check(expected:find(OTHER,1,true) and not expected:find(BUILD,1,true) and not expected:find(READBACK,1,true)
     and not expected:find(CHOSEN,1,true),st..': names the other Wishlist only')
   elseif state=='mismatch' then
    check(expected:find(dest,1,true) and expected:find(READBACK,1,true),st..': names the Saved Build and the Wishlist read back')
   else
    check(expected:find(dest,1,true) and not expected:find(OTHER,1,true) and not expected:find(READBACK,1,true),st..': names the Saved Build only')
   end
   -- What the old two-argument call showed: the strict template refused it
   -- and the English printf put the Saved Build where 'other' means a Wishlist.
   local legacy=string.format(raw,dest,SafeName(state=='other' and status.name or status.readName) or '?')
   local before,beforeWrites=Effects(H),writes
   U.Render()
   local after=Effects(H)
   check(after==before and writes==beforeWrites,st..' PASSIVE: rendering changed no saved data, action, send, write or Auto'..Diff(before,after))
   local f=_G.NexusGuidedSetup
   local shown=U.VisibleText()
   check(shownExactly(f,expected),st..': the whole body is shown at its FontString: '..shown:sub(1,400))
   if legacy~=expected then check(shown:find(legacy,1,true)==nil,st..': the old English fallback is not shown') end
   if state=='other' then
    local wrong=L.Format(KEYS.other,{other=dest})
    check(shown:find(wrong,1,true)==nil,st..': the Saved Build is never shown as the other Wishlist')
   end
   check(shownExactly(f,head),st..': the static result head is shown in the session language')
   check(f.next and f.next:IsShown() and not enabled(f.next),st..': Continue is shown waiting')
   -- Routing kept: stale and changed offer Check again only; the others
   -- also reopen the chooser.
   local recheck=state=='stale' or state=='changed'
   check((buttonExactly(f,again)~=nil)==(not recheck),st..': the chooser-again action is offered '..(recheck and 'never' or 'beside Check again'))
  end

  for _,state in ipairs(candidate and STATES or {}) do Run(state) end
  G.ReadAssignment,A.AssignmentActionToken=originalRead,originalToken
  U.Hide()
  check(writes==0,tag..' PASSIVE: no adapter assignment write was made')
  check(not Auto(),tag..' PASSIVE: Auto stays OFF')
 end
end

if #failed>0 then error('l10n_ui_guide: '..#failed..' of '..checks..' checks failed; first: '..failed[1]) end
print('PASS l10n_ui_guide checks='..checks..' (pseudo, long, missing-entry and English phases; synthetic offline, native NOT_RUN)')
