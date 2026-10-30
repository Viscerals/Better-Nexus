-- Full-UI localization, Orb family (ui/OrbPanel.lua, ui/OrbHistory.lua).
-- The real Orb window (run controls and Run history pages, copy view,
-- Advanced section), the Continue window, the main-panel Orb strip and line
-- and the mini panel are driven through their real entry points with the
-- real runtime and the fake game services of orbs_support.lua. Sections:
--  1. English: exact bytes of representative texts; the window's English
--     fallback table equals the seam's English base for every orb.* key.
--  2. Pseudo pack: every visible code-owned word of the family passes the
--     seam in the loading, idle, refused, running, paused, finished/confirm,
--     history, Advanced, Continue, strip and mini states, and in hovers.
--     Raw runtime texts (pending in the fragment) are listed explicitly.
--  3. Templates: unknown count "?", zero "0", a non-ASCII Wishlist name and
--     recorded Echo names inserted verbatim.
--  4. Passivity: rendering, hovering, page navigation, copy view and Cancel
--     change no saved table, send nothing and act on nothing.
--  5. Long pseudo mode on the densest views: no error, text still shown.
--  6. Missing pack entries show their exact English.
-- Synthetic offline evidence only: no native font, layout or client claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local WISHLIST='Zażółć Wünschliste'

local H,M,UI
local function Boot(mode,entries)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;UISpecialFrames=nil
 NexusOrbPanel=nil;NexusOrbMini=nil;NexusOrbContinue=nil;NexusOrbRunLog=nil;NexusOrbHistoryCopy=nil
 if mode then S.InstallBootHook(mode~='wrap' and mode or nil,entries) end
 H=dofile('tests/prototype/orbs_support.lua');M=H.M;UI=Nexus.OrbPanel
 UIParent:SetSize(1920,1080)
 return H
end
local function Plan(stacks)
 assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity(WISHLIST,{{spellId=410002,quality=2,stacks=stacks or 3}}))
 assert(M.UseAssignedWishlist())
end
local function Hover(widget)
 local enter=widget and widget:GetScript('OnEnter')
 if not enter then return {} end
 return S.CaptureTooltip(enter,widget)
end
-- Every text shown by `root`, plus the tooltip lines of every hover area in
-- it (each frame with an OnEnter script), depth first.
local function Collect(root,out)
 out=S.VisibleTexts(root,out or {})
 local function walk(f)
  if f.IsShown and not f:IsShown() then return end
  if f.GetScript and f:GetScript('OnEnter') then
   for _,line in ipairs(Hover(f)) do if type(line)=='string' and line~='' then out[#out+1]={text=line,frame=f} end end
  end
  for _,c in ipairs(f.children or {}) do walk(c) end
 end
 walk(root)
 return out
end
local function Find(label,parent)
 for _,b in ipairs(H.frames) do
  if b.kind=='Button' and b:GetText()==label and (not parent or b:GetParent()==parent) then return b end
 end
 error('button not found: '..tostring(label))
end
local function Strip()
 for _,f in ipairs(H.frames) do if f._orbControls then return f._orbControls end end
end

------------------------------------------------------------------------------
-- 1. English
------------------------------------------------------------------------------
Boot(nil)
local L=Nexus.Localization
check(L.ActiveLanguage()=='enUS','English session')
local d=L.Diagnostics()
check(d.base.undeclared==0 and d.base.missingDeclared==0,'composed English catalog admitted whole: '..d.base.undeclared..'/'..d.base.missingDeclared)
local english=S.English()
-- The window's fallback table (shown only while the seam is absent or a key
-- is unavailable) is the same English as the reviewed catalog, key by key.
do
 local src=S.readFile('ui/OrbPanel.lua')
 local block=assert(src:match('%-%- ORB%-ENGLISH BEGIN.-\nlocal ENGLISH=(%b{})'),'fallback table present')
 local fallback=assert(loadstring('return '..block))()
 local n=0
 for key,text in pairs(fallback) do
  n=n+1
  check(english[key]==text,'fallback English equals the catalog for '..key)
 end
 -- The v3 remainder keys are shown only through the display phrasebook,
 -- which without the seam shows the producer's raw English itself: they
 -- need no fallback, and the window never asks T/TF for them by name.
 local remainder=assert(src:match('%-%- ORB%-REMAINDER BEGIN.-\nlocal ORB_REMAINDER=(%b{})'),'remainder book present')
 remainder=assert(loadstring('return '..remainder))()
 local bookKeys,bookN={},0
 for _,key in pairs(remainder.exact) do if not bookKeys[key] then bookKeys[key]=true;bookN=bookN+1 end end
 for _,entry in ipairs(remainder.formats) do
  bookKeys[entry.key]=true;bookN=bookN+1
  for _,map in pairs(entry.nested or {}) do
   if type(map)=='table' then for _,key in pairs(map) do if not bookKeys[key] then bookKeys[key]=true;bookN=bookN+1 end end end
  end
 end
 for key in pairs(bookKeys) do check(english[key]~=nil,'a book key is a catalog key: '..key) end
 -- Keys the Orb guidance (logic/OrbGuidance.lua) shows itself.
 local guidanceKeys={}
 for _,key in pairs(Nexus.OrbGuidance.SHOWN_KEYS) do guidanceKeys[key]=true end
 guidanceKeys['orb.guidance.state_open_orbs']=true
 local catalog,remainderN=0,0
 for key in pairs(english) do
  if key:sub(1,4)=='orb.' then
   if (bookKeys[key] or guidanceKeys[key]) and not fallback[key] then
    remainderN=remainderN+1
    check(not src:find('T%("'..key:gsub('%p','%%%0')..'"')  and not src:find('TF%("'..key:gsub('%p','%%%0')..'"'),'remainder key is never asked by name: '..key)
   else
    catalog=catalog+1;check(fallback[key]~=nil,'fallback holds '..key)
   end
  end
 end
 check(n==catalog and n>300,'every other orb.* key has exactly one fallback: '..n..'/'..catalog)
 check(remainderN>290 and bookN>290,'remainder book keys: '..remainderN..' remainder-only of '..bookN..' book keys')
 -- The display-boundary map of raw runtime texts: each raw text is a literal
 -- of the Orb core (the producer keeps it), and its key's English is that
 -- same text, so the English window shows exactly what it showed before.
 local core={}
 for _,path in ipairs({'core/OrbRuntime.lua','core/OrbAdapter.lua'}) do core[#core+1]=S.readFile(path) end
 core=table.concat(core,'\n')
 local runtime=assert(src:match('%-%- ORB%-RUNTIME BEGIN.-\nlocal RUNTIME_TEXT=(%b{})'),'runtime map present')
 runtime=assert(loadstring('return '..runtime))()
 local mapped=0
 for raw,key in pairs(runtime) do
  mapped=mapped+1
  check(core:find('"'..raw..'"',1,true)~=nil,'runtime text is a producer literal: '..raw)
  check(english[key]==raw,'runtime key English is the raw text: '..key)
 end
 check(mapped>80,'runtime texts mapped: '..mapped)
end
-- The Orb display phrasebook (v3 remainder): every exact entry and every
-- producer format, rebuilt as the producer writes it, shows exactly the
-- producer's bytes in English; texts made of several of its sentences too.
local BOOK=assert(UI.PhraseBook(),'the Orb book is built')
-- R5 (Source86): the saved-format marker line puts two producer slots side
-- by side ("(%s%s)"), so which bytes are the type and which the text cannot
-- be told from the English. Localization.Phrase keeps such a line raw
-- (unique-parse rule) instead of guessing; every other format is checked.
local MARKER='orb.runtime.format_marker_invalid'
local function WithoutMarker(book)
 local copy={}
 for k,v in pairs(book) do copy[k]=v end
 copy.formats={}
 for _,entry in ipairs(book.formats) do if entry.key~=MARKER then copy.formats[#copy.formats+1]=entry end end
 return copy
end
do
 local marker
 for _,entry in ipairs(BOOK.formats) do if entry.key==MARKER then marker=entry end end
 local line=string.format(marker.format,'string',' 7x','7')
 local shown,known=L.Phrase(line,BOOK)
 check(known==false and shown==line,'R5: the adjacent-slot marker line stays raw (ambiguous split): '..tostring(shown))
end
do
 local failures=S.BookFidelity(WithoutMarker(BOOK),'english')
 check(#failures==0,'English: every Orb book entry shows the producer bytes:\n'..table.concat(failures,'\n'))
 local exactN=0
 for _ in pairs(BOOK.exact) do exactN=exactN+1 end
 -- Source16: the offer-open paragraph left the book; the window says it as
 -- three keyed paragraphs (section 7b), so 25 formats remain.
 check(exactN>340 and #BOOK.formats==25,'Orb book admitted whole: '..exactN..' exact, '..#BOOK.formats..' formats')
end
-- Raw text of a key in the book (the producer's bytes).
local function RawOf(key)
 for raw,k in pairs(BOOK.exact) do if k==key then return raw end end
 error('no raw text for '..key)
end
local INTRO=RawOf('orb.continue.attribution_owned_gain')..RawOf('orb.continue.exit_consequences')..RawOf('orb.continue.check_explanation')
local COMPOSED={
 INTRO..RawOf('orb.continue.confirm_question'),
 INTRO..RawOf('orb.continue.choose_check_confirm'),
 RawOf('orb.recovery.unobservable')..RawOf('orb.runtime.receipt_exit_unreserved'),
}
for _,entry in ipairs(BOOK.formats) do
 if entry.key=='orb.continue.confirm' then COMPOSED[#COMPOSED+1]=string.format(entry.format,2,5) end
 if entry.key=='orb.runtime.cannot_start_yet' then
  COMPOSED[#COMPOSED+1]=string.format(entry.format,RawOf('orb.runtime.no_assigned_wishlist')..' '..RawOf('orb.runtime.limit_reached'))
 end
 if entry.key=='orb.runtime.blocked_unattributable_next' then
  COMPOSED[#COMPOSED+1]=string.format(entry.format,'A new Orb run','Stop this Orb run first, then open')
 end
end
check(#COMPOSED==6,'composed producer texts built: '..#COMPOSED)
for _,raw in ipairs(COMPOSED) do
 local shown,known=L.Phrase(raw,BOOK)
 check(known==true and shown==raw,'English: a composed producer text shows its exact bytes: '..raw:sub(1,60))
end
-- The assignment note of the unassigned window: the adapter's exact bytes.
do
 local f=UI.Show();UI.Refresh()
 local note=Nexus.GameAdapter.WishlistNote()
 check(note=='Choose or create a wishlist to begin your first run.','English: the adapter note is raw English: '..tostring(note))
 check(f.targets:GetText()==note,'English: the targets line shows its exact bytes: '..tostring(f.targets:GetText()))
 f:Hide()
end
Plan(3)
local f=UI.Show()
check(f.title:GetText()=='Orbs / Lost Memories','title English')
check(f.start:GetText()=='Start' and f.max:GetText()=='Max','buttons English')
check(Hover(f.max)[1]=='Follow your confirmed Orb balance, up to 1000, until you enter another amount or start the run. This does not spend Orbs.','Max hover English')
check(f.approval:GetText()=='Start approves this maximum: eligible surplus copies/recycling. Ordinary Auto OFF.\nUp to 2 recovery checks within this maximum; owned Echoes decide completion.','consent English (two lines)')
check(f.plan:GetText()=='Assigned Wishlist: '..WISHLIST,'assigned Wishlist with a non-ASCII name verbatim')
check(f.balance:GetText():match('^[^\n]*')=='Confirmed Orb balance: 10','balance English: '..f.balance:GetText())
f.limit:SetText('');f.limit:ClearFocus();f.start:Click()
check(f.notice:GetText()=='The maximum follows the confirmed Orb balance, which is not available. Nothing was started.' and H.Count('orb-spend')==0,'refusal English, nothing spent: '..tostring(f.notice:GetText())..' spends='..H.Count('orb-spend'))
f.limit:SetText('3');f.limit:ClearFocus();f.start:Click()
UI.Refresh()
check(H.Count('orb-spend')==1,'Start spends through the real path')
check(f.usage:GetText()=='Orbs used: 0 / 3 approved; pending: 1 Orb requested, not confirmed yet','usage English: '..f.usage:GetText())
local shown,full=UI.PanelRunLine()
check(shown:find('^Orb run: Running %- Waiting for the Orb offer; Used 0 of 3 approved; ') ~=nil,'panel line English: '..shown)
check(full:find('Orbs used: 0 of 3 approved. ',1,true)~=nil,'panel line hover keeps the full usage: '..full)
local mini=UI.ShowMini()
check(mini.title:GetText()=='Orb run status' and mini.usage:GetText()=='Orbs used: 0 of 3 approved','mini English')
-- R5 copy correction: the usage hover names the run's current approved maximum.
do
 local lines=S.CaptureTooltip(mini.usageHit:GetScript('OnEnter'),mini.usageHit)
 local want='Orbs this run has used, against its current approved maximum. Unavailable means it could not be read; it is not 0.'
 local found=false
 for _,l in ipairs(lines) do if l==want then found=true end end
 check(found,'R5 mini_usage: the usage hover says the corrected English: '..table.concat(lines,' | '))
end
check(mini.pending:GetText()=='Pending: 1 Orb requested, not confirmed yet','mini pending English: '..mini.pending:GetText())
local strip=assert(Strip(),'the main-panel Orb strip is attached by the real panel')
strip.refresh()
check(strip.summary:GetText():find('Orbs used: 0 / 3 approved\n1 Orb pending, not confirmed yet\n',1,true)==1,'strip English: '..strip.summary:GetText())
mini.pause:Click()
check(mini.notice:GetText()=='Paused.','mini outcome English')
strip.refresh()
check(strip.summary:GetText():find("^Orbs used: 0 / 3 approved\n1 Orb pending; 'Za.- %(same%)\nPaused %- 1 Orb pending$")~=nil,
 'strip: a paused run with a pending Orb says so once on its state line: '..strip.summary:GetText())
UI.Refresh()
check(f.pause:GetText()=='Pause' and f.resume:GetText()=='Resume','fixed Pause/Resume English')
local log=UI.ShowLog()
check(log.page:GetText()=='Operations 1-1 of 1','history page label English: '..log.page:GetText())
check(log.note:GetText()=='History clears on reload or logout.','history note English')
check(log.header:GetText():find('^Run %d+ %- '..WISHLIST..'\nPaused\nOrbs used: 0 / 3 approved')~=nil,'history header English: '..log.header:GetText())
check(log.rows[1].result:GetText()=='> Request\nprepared','history result English, split on two lines as before: '..log.rows[1].result:GetText())
-- The copied report is a support payload: English, whatever the language.
local englishReport=Nexus.OrbHistory.Report(M.RunLog('current'),nil,false)
check(englishReport:find('^Nexus Orb history %(current run%)%. History clears on reload or logout%.')~=nil,'report English')

------------------------------------------------------------------------------
-- 2. Pseudo pack: every visible code-owned word passes the seam
------------------------------------------------------------------------------
-- Data that is never translated: fixture Echo names, the Wishlist name and
-- digits. Raw runtime texts below are the fragment's pending entries (the
-- runtime keeps its English; it is compared and recorded elsewhere), and
-- Readout's status words come from ui/Readout.lua (another family).
local DATA={WISHLIST,'Disposable A','Desired A','Disposable B','Desired B','Protected low','Excess high','Locked','Unsafe fallback'}
-- v3: the GameAdapter assignment notes pass the seam (Orb book) and the
-- Readout status words are said by ui/Readout.lua through their keys, so
-- nothing raw is allowed any more.
local PENDING_RUNTIME={}
local READOUT_WORDS={}
local function allow(word,text)
 local rest=S.Unmarked(text)
 -- Data may be shortened in its cell ("'Za..."): a word of a data value.
 for _,v in ipairs(DATA) do if v:find(word,1,true) and rest:find(word,1,true) then return true end end
 for _,v in ipairs(PENDING_RUNTIME) do if v:find(word,1,true) and rest:find(v,1,true) then return true end end
 for _,v in ipairs(READOUT_WORDS) do if v:find(word,1,true) and rest:find(v,1,true) then return true end end
 return false
end
local scanned,failures=0,{}
local function Scan(label,texts)
 local missing=S.Untranslated(texts,allow)
 for _,m in ipairs(missing) do failures[#failures+1]=label..': '..m.word..' in "'..m.text..'"' end
 scanned=scanned+#texts
 checks=checks+1
end
local function Serialize(value,seen)
 local kind=type(value)
 if kind~='table' then return kind..':'..tostring(value) end
 seen=seen or {}
 if seen[value] then return '<cycle>' end
 seen[value]=true
 local keys={}
 for k in pairs(value) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=Serialize(k,seen)..'='..Serialize(value[k],seen) end
 seen[value]=nil
 return '{'..table.concat(out,',')..'}'
end
local function Snapshot()
 return {db=Serialize(NexusDB),legacy=Serialize(WishlistRealizerDB),sent=#H.sent,actions=#H.actions,
  spends=H.Count('orb-spend'),state=tostring(M.Status().state),running=tostring(M.Status().running)}
end
local function Passive(label,fn)
 local before=Snapshot()
 fn()
 local after=Snapshot()
 for k,v in pairs(before) do check(after[k]==v,label..' is passive: '..k) end
end

Boot('wrap')
check(Nexus.Localization.ActiveLanguage()=='frFR','pseudo pack active from session start')
do
 local failures=S.BookFidelity(WithoutMarker(UI.PhraseBook()),'pseudo')
 check(#failures==0,'pseudo: every Orb book entry is said through the seam:\n'..table.concat(failures,'\n'))
 for _,raw in ipairs(COMPOSED) do
  local shown,known=Nexus.Localization.Phrase(raw,UI.PhraseBook())
  check(known==true and S.LooksUntranslated(shown)==nil,'pseudo: a composed producer text is said whole: '..tostring(shown):sub(1,80))
 end
 -- The Orb block sentence other windows show (UserText): its subject too.
 local block='A new Orb run is blocked: the observed gain cannot be attributed to this action. Open /nexus orbs for its explicit checked Continue exit. The record is kept until that check passes and you confirm; no spending restarts.'
 local shown=Nexus.UserText.Message(block)
 check(S.LooksUntranslated(shown)==nil and shown:find(S.OPEN..'A new Orb run'..S.CLOSE,1,true)~=nil
  and shown:find(S.OPEN..'Open'..S.CLOSE,1,true)~=nil,'pseudo: an Orb block sentence in another window is said with its subject and step: '..shown)
end
-- Loading: local saved data is not restored yet (the display read only).
do
 local real=Nexus.StartupStatus
 Nexus.StartupStatus=function() return {coreReady=false,state='loading'} end
 local f=UI.Show()
 Scan('loading',Collect(f))
 check(S.IsPseudo(f.status:GetText()) and S.IsPseudo(f.balance:GetText()),'loading lines pass the seam')
 local m=UI.ShowMini()
 Scan('mini loading',Collect(m))
 check(UI.PanelRunLine()==nil,'no panel line while loading')
 UI.HideMini();f:Hide()
 Nexus.StartupStatus=real
end
-- Idle without an assigned Wishlist: the adapter's note through the book.
local f=UI.Show()
Passive('idle render and hovers',function() UI.Refresh();Scan('idle unassigned',Collect(f)) end)
check(f.targets:GetText()==S.OPEN..'Choose or create a wishlist to begin your first run.'..S.CLOSE,
 'the assignment note is said through the seam: '..tostring(f.targets:GetText()))
-- Idle with a plan; Max hover; Advanced; refusals.
Plan(3)
UI.Refresh()
Passive('assigned render',function() Scan('idle assigned',Collect(f)) end)
check(f.plan:GetText()==S.OPEN..'Assigned Wishlist: '..WISHLIST..S.CLOSE,'non-ASCII Wishlist name verbatim inside the template')
f.advancedToggle:Click()
Passive('Advanced render',function() Scan('advanced',Collect(f)) end)
check(f.sourcePage:GetText()==S.OPEN..'Eligible sources 1 / 1'..S.CLOSE,'source pager template: '..f.sourcePage:GetText())
f.advancedToggle:Click()
f.limit:SetText('');f.limit:ClearFocus();f.start:Click()
check(S.IsPseudo(f.notice:GetText()) and H.Count('orb-spend')==0,'Start refusal passes the seam and spends nothing')
Scan('refused',Collect(f))
f.resume:GetScript('OnClick')(f.resume)
check(S.IsPseudo(f.notice:GetText()),'Resume refusal passes the seam: '..f.notice:GetText())
-- Running.
f.limit:SetText('3');f.limit:ClearFocus();f.start:Click();UI.Refresh()
check(H.Count('orb-spend')==1 and M.Status().running,'the run starts through the real Start')
Passive('running render, hovers and page switches',function()
 Scan('running',Collect(f))
 local log=UI.ShowLog();Scan('history running',Collect(log))
 f.runTab:Click();UI.Refresh()
 local m=UI.ShowMini();Scan('mini running',Collect(m))
 local strip=assert(Strip());strip.refresh();Scan('strip running',Collect(strip))
 local shown,full=UI.PanelRunLine()
 Scan('panel line running',{{text=shown},{text=full}})
end)
-- The HUD's Orb hub line (ui/Panel.lua) names the run state through its
-- key (OrbHistory.RUN_STATE_KEYS), not the English label table.
do
 local state=M.Status().state
 local label=Nexus.OrbHistory.RUN_STATES[state]
 local hub=Nexus.Panel.OrbHubLine()
 check(label~=nil and hub:find(S.OPEN..label..S.CLOSE,1,true)~=nil,'the hub line says the run state through its key: '..tostring(hub))
end
-- Template slots: unknown "?" and zero "0" on the mini pending counts.
do
 local real=M.CompactStatus
 M.CompactStatus=function()
  local s=real();s.uncertain=nil;s.unconfirmedResults=0;s.historyKnown=true;s.reserved=0;s.pending=false;return s
 end
 UI.ShowMini()
 local text=NexusOrbMini.pending:GetText()
 check(text==S.OPEN..'Unknown spend: ?; Reserved: 0; Outcomes: 0'..S.CLOSE,'unknown count is "?", zero is "0": '..text)
 local _,whole=UI.PanelRunLine()
 check(whole:find('Unknown spend: '..S.OPEN..'unavailable'..S.CLOSE,1,true)~=nil,'unavailable stays a distinct word, never 0: '..whole)
 M.CompactStatus=real
end
-- Paused (mini Pause), its strip and mini, and the paused page.
NexusOrbMini.pause:Click()
check(not M.Status().running and S.IsPseudo(NexusOrbMini.notice:GetText()),'mini Pause outcome passes the seam')
-- The runtime keeps its raw English reason; only the display says it.
check(M.Status().reason=='Paused. A submitted spend may still finish; the native offer remains available.','runtime reason stays raw English')
UI.Refresh()
check(f.status:GetText():find(S.OPEN..'Paused. A submitted spend may still finish; the native offer remains available.'..S.CLOSE,1,true)~=nil,
 'a mapped runtime reason is said through the seam at display: '..f.status:GetText())
UI.Refresh()
Passive('paused render',function()
 Scan('paused',Collect(f))
 Scan('mini paused',Collect(NexusOrbMini))
 local strip=Strip();strip.refresh();Scan('strip paused',Collect(strip))
end)
-- Changed Resume target and recovery layers: the real window rendering
-- synthetic Status/ContinueView reads (display only).
do
 local status,view=M.Status,M.ContinueView
 local function With(extra,cv)
  M.Status=function(...) local s=status(...);for k,v in pairs(extra) do s[k]=v end;return s end
  if cv then M.ContinueView=function() local v=view();for k,x in pairs(cv) do v[k]=x end;return v end end
  UI.Refresh()
  local texts=Collect(f)
  M.Status,M.ContinueView=status,view
  return texts
 end
 for _,t in ipairs({{kind='changed',key='k1',name='Neu',original=WISHLIST},{kind='changed',key='k2',name=WISHLIST,returned=true},
  {kind='original',name=WISHLIST},{kind='same'},{kind='settle'},{kind='unavailable',assignmentState='loading'},{kind='blocked',reason='authorization'}}) do
  local texts=With({state='PAUSED',running=false,resumeTarget=t,targetChanged=t.kind=='changed',operationName=WISHLIST})
  table.insert(DATA,'Neu')
  Scan('paused target '..t.kind,texts)
 end
 f.review:GetScript('OnClick')(f.review)
 Scan('review notice',{{text=f.notice:GetText()}})
 for _,cv in ipairs({{explanation=true,stage='idle'},{eligible=true,stage='idle'},{stage='checking'},{stage='refused'},{stage='done'}}) do
  Scan('recovery '..cv.stage,With({state='RECOVERY',recoveryKind='automatic',recoveryPhase='checking'},cv))
 end
 Scan('history baseline consent',With({historyCount=2,historyRisk='unconfirmed; Start accepts current Echoes baseline; late results may arrive.',
  state='IDLE',running=false,pending=false}))
end
-- Continue window: chrome, and the runtime's body text said through the
-- Orb book at the display (the runtime keeps its English).
do
 local view=M.ContinueView
 local c=assert(UI.ShowContinue(),'the Continue window opens')
 local real=view().text
 check(type(real)=='string' and real~='' and c.body:GetText()~=real and S.IsPseudo(c.body:GetText()),
  'the real Continue body passes the seam: '..tostring(c.body:GetText()))
 Scan('continue window',S.VisibleTexts(c))
 for _,text in ipairs(COMPOSED) do
  M.ContinueView=function() local v=view();v.text=text;return v end
  UI.ShowContinue()
  Scan('continue body '..text:sub(1,30),{{text=c.body:GetText(),frame=c.body}})
  check(S.IsPseudo(c.body:GetText()),'a composed Continue body passes the seam: '..c.body:GetText():sub(1,80))
 end
 M.ContinueView=view
 UI.ShowContinue()
 Passive('Continue cancel',function() c.cancel:GetScript('OnClick')(c.cancel) end)
 c:Hide()
end
-- Stop, then the history page with its rows, details, hovers and copy view.
UI.Refresh();f.stop:Click();UI.Refresh()
Scan('stopped',Collect(f))
local log=UI.ShowLog()
Passive('history page, selection, hovers and copy view',function()
 Scan('history',Collect(log))
 if log.rows[1]:IsShown() then
  log.rows[1]:Click();Scan('history details',Collect(log))
  log.rows[1]:Click()
 end
 local copy=Find(S.OPEN..'Copy report'..S.CLOSE,log);copy:Click()
 local view=NexusOrbHistoryCopy
 local texts={}
 for _,t in ipairs(S.VisibleTexts(view)) do if t.frame~=view.editBox then texts[#texts+1]=t end end
 Scan('copy view',texts)
 check(view.editBox:GetText():find('^Nexus Orb history %(current run%)')~=nil,'the copied report stays English (support payload)')
 Find(S.OPEN..'Close'..S.CLOSE,view):Click()
 log.previous:Click();Scan('history previous',Collect(log));log.current:Click()
 f.runTab:Click();UI.Refresh()
end)
-- Mini refusals and the no-run states.
do
 Passive('mini refusals',function()
  NexusOrbMini.resume:GetScript('OnClick')(NexusOrbMini.resume)
  Scan('mini refusal',{{text=NexusOrbMini.notice:GetText()}})
 end)
end
check(#failures==0,'untranslated visible text:\n'..table.concat(failures,'\n'))
check(scanned>150,'the scan reached the family: '..scanned)
print('scanned texts: '..scanned)

------------------------------------------------------------------------------
-- 5. Long pseudo mode on the densest views
------------------------------------------------------------------------------
Boot('long')
Plan(3)
f=UI.Show();f.limit:SetText('3');f.limit:ClearFocus();f.start:Click();UI.Refresh()
for _,t in ipairs(Collect(f)) do check(t.text~='' ,'long: text shown') end
check(S.IsPseudo(f.usage:GetText()) and S.IsPseudo(f.status:GetText():match('^[^\n]*')),'long: usage and status shown')
local logLong=UI.ShowLog();check(S.IsPseudo(logLong.page:GetText()),'long: history shown')
local m=UI.ShowMini();check(S.IsPseudo(m.usage:GetText()),'long: mini shown')
check(S.IsPseudo((UI.PanelRunLine())),'long: panel line shown')

------------------------------------------------------------------------------
-- 6. Missing pack entries show their exact English
------------------------------------------------------------------------------
local entries=S.PseudoEntries()
for _,key in ipairs({'orb.title.window','orb.button.max','orb.status.usage_head','orb.value.limit_approved',
 'orb.status.usage_pending_one','orb.tooltip.max_follow_balance'}) do entries[key]=nil end
Boot('wrap',entries)
Plan(3)
f=UI.Show()
check(f.title:GetText()=='Orbs / Lost Memories' and f.max:GetText()=='Max','missing entries: exact English')
check(Hover(f.max)[1]=='Follow your confirmed Orb balance, up to 1000, until you enter another amount or start the run. This does not spend Orbs.','missing tooltip entry: exact English')
check(S.IsPseudo(f.start:GetText()),'present entries still translated')
f.limit:SetText('3');f.limit:ClearFocus();f.start:Click();UI.Refresh()
check(f.usage:GetText():find('^Orbs used: 0 / 3 approved; '..S.OPEN..'pending:')==nil
 and f.usage:GetText():find('^Orbs used: 0 / 3 approved; pending: 1 Orb requested, not confirmed yet')~=nil,
 'missing template entries: exact English composition: '..f.usage:GetText())


------------------------------------------------------------------------------
-- 7. Source16 (global v6) at the real Orb receivers. Expected texts are
-- written out here, not derived from the code under test. A section-local
-- collector lists every miss, then one assertion reports them all.
------------------------------------------------------------------------------
local O,C=S.OPEN,S.CLOSE
local S16={}
local function soft(ok,label,detail) checks=checks+1;if not ok then S16[#S16+1]=label..(detail and (' :: '..tostring(detail)) or '') end end
local function Texts(root) local out={} for _,t in ipairs(S.VisibleTexts(root)) do out[#out+1]=t.text end return out end
local function HasText(list,want) for _,t in ipairs(list) do if t==want then return true end end return false end
local function Status(extra,cv)
 local status,view=M.Status,M.ContinueView
 M.Status=function(...) local s=status(...);for k,v in pairs(extra) do s[k]=v end;return s end
 if cv then M.ContinueView=function() local v=view();for k,x in pairs(cv) do v[k]=x end;return v end end
 UI.Refresh()
 local shown=UI.Show().status:GetText()
 M.Status,M.ContinueView=status,view
 return shown
end
local OUTER_EN='Local character data is not ready: %s No Orb action will be sent.'
local MARKER_EN='The saved data format marker is not a valid format number (%s). This build writes format %s. The data is kept unchanged and read-only.'
local function StartWhy(f)
 f.limit:SetText('3');f.limit:ClearFocus();f.start:Click();UI.Refresh()
 return f.startWhy:GetText(),M.Status().startReason
end
local function StubWrite(status)
 local real=Nexus.Store.StateWriteStatus
 Nexus.Store.StateWriteStatus=function() local s={} for k,v in pairs(status) do s[k]=v end return s end
 return function() Nexus.Store.StateWriteStatus=real end
end
-- 7a. P206: the malformed saved-format marker, through the real Store.
do
 Boot('wrap');Plan(3)
 local f=UI.Show()
 NexusDB.settingsVersion='7x }'
 local shown,raw=StartWhy(f)
 local inner=MARKER_EN:format('string "7x ?"','2')
 soft(raw==OUTER_EN:format(inner),'S16 P206 real Store: the runtime keeps its exact English refusal',raw)
 local want=O..'Start:'..C..' '..O..'Local character data is not ready: '..O..inner..C..' No Orb action will be sent.'..C
 soft(shown==want,'S16 P206 real Store: the Start line says the marker sentence through its key with the producer\'s own fields',shown)
 local before=Snapshot();UI.Refresh();UI.Refresh()
 local after=Snapshot();for k,v in pairs(before) do soft(after[k]==v,'S16 P206 real Store: showing is passive: '..k) end
 NexusDB.settingsVersion={}
 shown,raw=StartWhy(f)
 inner=MARKER_EN:format('table','2')
 soft(raw==OUTER_EN:format(inner),'S16 P206 empty text: the runtime keeps its exact English refusal',raw)
 soft(shown==O..'Start:'..C..' '..O..'Local character data is not ready: '..O..inner..C..' No Orb action will be sent.'..C,'S16 P206 empty text: no marker text and no separator',shown)
 NexusDB.settingsVersion=nil
 -- Producer-level statuses: unknown type, and delimiter-like marker data.
 local restore=StubWrite({mode='unavailable',reason='saved-format',format='malformed',supportedFormat=5})
 shown,raw=StartWhy(f);restore()
 inner=MARKER_EN:format('unknown type','5')
 soft(raw==OUTER_EN:format(inner),'S16 P206 unknown type: raw English kept',raw)
 soft(shown==O..'Start:'..C..' '..O..'Local character data is not ready: '..O..'The saved data format marker is not a valid format number ('..O..'unknown type'..C..'). This build writes format 5. The data is kept unchanged and read-only.'..C..' No Orb action will be sent.'..C,
  'S16 P206 unknown type: the type is said through its own key',shown)
 restore=StubWrite({mode='unavailable',reason='saved-format',format='unverified',savedFormat=4,supportedFormat=2,field='rows'})
 shown,raw=StartWhy(f);restore()
 soft(raw:find('did not pass this build',1,true) and S.IsPseudo(shown) and S.LooksUntranslated(shown)==nil,'S16 P206 neighbour: an unverified format stays translated',shown)
 restore=StubWrite({mode='unavailable',reason='saved-format',format='future',savedFormat=9,supportedFormat=2,knownFirst=3,knownLast=5})
 shown,raw=StartWhy(f);restore()
 soft(raw:find('is not supported',1,true) and S.IsPseudo(shown) and S.LooksUntranslated(shown)==nil,'S16 P206 neighbour: an unsupported format stays translated',shown)
 f:Hide()
end
do
 local entries=S.PseudoEntries()
 entries['orb.runtime.format_marker_invalid']='[{supported}]{marker_text} <- {marker_type} ILLISIBLE'
 entries['orb.runtime.character_data_not_ready']='PAS PRET: {reason} RIEN'
 entries['orb.label.start_reason']='Debut:'
 Boot('wrap',entries);Plan(3)
 local f=UI.Show()
 local restore=StubWrite({mode='unavailable',reason='saved-format',format='malformed',markerType='string',markerText='{a}%s; 7x)(',supportedFormat=5})
 local shown,raw=StartWhy(f);restore()
 soft(raw==OUTER_EN:format(MARKER_EN:format('string {a}%s; 7x)(','5')),'S16 P206 reordered: raw English kept with the marker bytes',raw)
 soft(shown=='Debut: PAS PRET: [5] {a}%s; 7x)( <- string ILLISIBLE RIEN','S16 P206 reordered: a valid reordered candidate places each field; braces, percent and separators stay data',shown)
 f:Hide()
end
do
 local entries=S.PseudoEntries();entries['orb.runtime.format_marker_invalid']=nil
 Boot('wrap',entries);Plan(3)
 local f=UI.Show()
 NexusDB.settingsVersion='7x }'
 local shown=StartWhy(f)
 NexusDB.settingsVersion=nil
 soft(shown==O..'Start:'..C..' '..O..'Local character data is not ready: '..MARKER_EN:format('string "7x ?"','2')..' No Orb action will be sent.'..C,'S16 P206 missing: a missing marker candidate keeps the complete English sentence',shown)
 entries=S.PseudoEntries();entries['orb.runtime.character_data_not_ready']='{reason} {nope}'
 Boot('wrap',entries);Plan(3)
 f=UI.Show()
 NexusDB.settingsVersion='7x }'
 shown=StartWhy(f)
 NexusDB.settingsVersion=nil
 soft(shown==O..'Start:'..C..' '..OUTER_EN:format(MARKER_EN:format('string "7x ?"','2')),'S16 P206 invalid: an invalid outer candidate shows the whole refusal in exact English',shown)
end
-- 7b. The offer-open paragraph: one runtime meaning, three ordered keyed
-- paragraphs joined by one space at the receiver.
local SEG1="The earlier Orb offer is still open. Before the reload Nexus proposed %s for it, and that call was refused before it reached the game. Nexus can confirm this action only if you choose that same Echo in the game's offer window. If you choose a different Echo, Nexus cannot confirm the action. The record and its spending exposure are kept."
local SEG2="For the original no-choice class, Continue is available only after a reload for a client-observed spend with no usable recorded choice and no open offer, after a read-only check. Separately, a stopped attribution-ambiguous action needs its fresh distinct chosen gain actually owned. Both exits require a quiet read-only check and your confirmation."
local SEG3="Open /nexus orbs for this record's eligibility and explanation. Nexus never continues by itself. Nexus will not choose or spend."
-- The producer's own composition (core/OrbRuntime.lua RECOVERY_TEXT):
-- its literal head, then the shared KEPT and NO_EXIT constants, then the tail.
local ORB_SRC=S.readFile('core/OrbRuntime.lua')
local OFFER_FMT=assert(ORB_SRC:match('OFFER_OPEN_PROPOSED="(.-)"%.%.KEPT%.%.NO_EXIT%.%." Nexus will not choose or spend%.",'),'the producer head')
 ..assert(ORB_SRC:match('\nlocal KEPT="(.-)"[\r\n]'),'KEPT')..assert(ORB_SRC:match('\nlocal NO_EXIT="(.-)"[\r\n]'),'NO_EXIT')
 .." Nexus will not choose or spend."
local ECHO='Ashen {Tithe} 100%; x'
do
 soft(OFFER_FMT==SEG1..' '..SEG2..' '..SEG3,'S16 offer: the producer format is exactly the three paragraphs joined by one space')
 local raw=OFFER_FMT:format(ECHO)
 Boot('wrap');Plan(3);UI.Show()
 local shown=Status({state='PAUSED',recovery={},running=false,pending=true,reason=raw},{eligible=true})
 local want=O..'Details:'..C..' '..O..SEG1:format(ECHO)..C..' '..O..SEG2..C..' '..O..SEG3..C
 soft(shown:find(want,1,true)~=nil,'S16 offer: the Details line says the three paragraphs in order, one space between, the Echo name verbatim',shown)
 soft(shown:find('^'..O..'Paused')~=nil,'S16 offer: close control, the paused headline stays translated',shown)
 local ut=Nexus.UserText.Message(raw)
 soft(ut==O..SEG1:format(ECHO)..C..' '..O..SEG2..C..' '..O..SEG3..C,'S16 offer: another window (UserText) says the same paragraphs',ut)
end
do
 local entries=S.PseudoEntries()
 entries['orb.recovery.offer_open_proposed']='{echo} :UN'
 entries['orb.recovery.offer_open_proposed_exits']='DEUX'
 entries['orb.recovery.offer_open_proposed_route']='TROIS'
 Boot('wrap',entries);Plan(3);UI.Show()
 local shown=Status({state='PAUSED',recovery={},running=false,pending=true,reason=OFFER_FMT:format(ECHO)},{eligible=true})
 soft(shown:find(O..'Details:'..C..' Ashen {Tithe} 100%; x :UN DEUX TROIS',1,true)~=nil,'S16 offer reordered: each paragraph in its place, the Echo name verbatim',shown)
 entries['orb.recovery.offer_open_proposed_route']=nil
 Boot('wrap',entries);Plan(3);UI.Show()
 shown=Status({state='PAUSED',recovery={},running=false,pending=true,reason=OFFER_FMT:format(ECHO)},{eligible=true})
 soft(shown:find(O..'Details:'..C..' '..OFFER_FMT:format(ECHO),1,true)~=nil,'S16 offer missing: one missing paragraph shows the whole paragraph in exact English',shown)
end
do
 local long=S.PseudoEntries('long')
 for _,k in ipairs({'orb.recovery.offer_open_proposed','orb.recovery.offer_open_proposed_exits','orb.recovery.offer_open_proposed_route'}) do
  soft(long[k] and #long[k]<=1024,'S16 offer long: the long candidate fits raw 1024: '..k,long[k] and #long[k])
 end
 Boot('long');Plan(3);UI.Show()
 local shown=Status({state='PAUSED',recovery={},running=false,pending=true,reason=OFFER_FMT:format(ECHO)},{eligible=true})
 soft(#shown>1645 and shown:find(ECHO,1,true)~=nil and select(2,shown:gsub(O,''))>=4,'S16 offer long: the whole long paragraph is shown with the Echo name',#shown)
end
-- 7c. The paused headline (RU source-fit 19): a complete >256-byte
-- candidate is shown; selection and its neighbours unchanged.
do
 local entries=S.PseudoEntries()
 local full=O..'Paused - a result restored after a reload is unresolved: no new Orb run or ordinary roll until it settles or you continue past it.'..string.rep(' complete',20)..C
 entries['orb.status.headline_paused_continue']=full
 Boot('wrap',entries);Plan(3);UI.Show()
 local shown=Status({state='PAUSED',recovery={},running=false,pending=true,reason='Waiting.'},{eligible=true})
 soft(#full>256 and shown:sub(1,#full)==full,'S16 headline: a complete candidate above 256 bytes is the paused-Continue headline',shown:sub(1,80))
 shown=Status({state='PAUSED',recovery={},running=false,pending=true,reason='Waiting.'},{eligible=false})
 soft(shown:find('^'..O..'Paused')~=nil and shown:sub(1,#full)~=full,'S16 headline: close control, paused without Continue keeps its own headline',shown:sub(1,80))
 shown=Status({state='RECOVERY',running=false,pending=true,reason='Waiting.'},{eligible=true})
 soft(shown:sub(1,#full)~=full and S.IsPseudo(shown),'S16 headline: close control, the recovery headline is not the paused one',shown:sub(1,80))
 entries['orb.status.headline_paused_continue']=string.rep('x',1100)
 Boot('wrap',entries);Plan(3);UI.Show()
 shown=Status({state='PAUSED',recovery={},running=false,pending=true,reason='Waiting.'},{eligible=true})
 soft(shown:find('^Paused %- a result restored after a reload is unresolved: no new Orb run or ordinary roll until it settles or you continue past it%.\n')~=nil,'S16 headline: an invalid candidate shows the exact English headline',shown:sub(1,80))
end
-- 7d. Recovery needs a fresh reply (RU-V4-P2-15): a complete block.
do
 local entries=S.PseudoEntries()
 local raw='Recovery needs a fresh empty-choice reply after newer activity. Resolve any open offer in the game, or Stop and approve a new run. No new Orb is sent.'
 local full=O..raw..string.rep(' complete',20)..C
 entries['orb.runtime.recovery_needs_fresh_reply']=full
 Boot('wrap',entries)
 soft(#full>256 and (UI.Phrase(raw))==full,'S16 RU-15: a complete candidate above 256 bytes is shown',(UI.Phrase(raw)))
end
-- 7e. The archived diagnostic pair (orb.continue.attribution_owned_gain).
do
 local key='orb.continue.attribution_owned_gain'
 local function PairKept(v) return type(v)=='string' and v:find('%f[%w]UNCONFIRMED%f[%W]')~=nil and v:find('%f[%w]NONE%f[%W]')~=nil end
 local src=S.readFile('core/OrbRuntime.lua')
 soft(src:find('resolution={outcome="UNCONFIRMED",confidence="NONE"}',1,true)~=nil,'S16 pair: the archive producer stores the literal pair')
 soft(src:find('e.resolution.outcome~="UNCONFIRMED" or e.resolution.confidence~="NONE"',1,true)~=nil,'S16 pair: the archive validator requires the literal pair')
 soft(src:find('confidence=childFact(e.resolution,"confidence","NONE")',1,true)~=nil and src:find('outcome=childFact(e.resolution,"outcome","UNCONFIRMED")',1,true)~=nil,'S16 pair: the support export repeats the literal pair')
 local english=RawOf(key)
 soft(src:find('"'..english..'"',1,true)~=nil and PairKept(english),'S16 pair: the paragraph is the producer literal and names both identifiers')
 local ctx=S.readFile('docs/localization/KEY_CONTEXT.json')
 local row=ctx:match('"key": "'..key:gsub('%.','%%.')..'".-"meaning": "(.-)"')
 soft(row and row:find('UNCONFIRMED',1,true) and row:find('NONE',1,true) and row:find('literal',1,true),'S16 pair: the key context names both archived identifiers as literal',row)
 local good='PREUVE FRAICHE: cette action reste UNCONFIRMED; archivee sans changement avec la confiance NONE. '
 local bad='PREUVE FRAICHE: cette action reste NON CONFIRMEE; archivee sans changement avec la confiance AUCUNE. '
 soft(PairKept(good) and not PairKept(bad),'S16 pair: the acceptance rule keeps a candidate with both literals and refuses one that translates them')
 local entries=S.PseudoEntries();entries[key]=good
 Boot('wrap',entries);Plan(3)
 local view=M.ContinueView
 local c=assert(UI.ShowContinue(),'the Continue window opens')
 M.ContinueView=function() local v=view();v.text=INTRO..RawOf('orb.continue.choose_check_confirm');return v end
 local before=Snapshot()
 UI.ShowContinue()
 local body=c.body:GetText()
 M.ContinueView=view
 soft(body:sub(1,#good)==good and PairKept(body) and body:find('PREUVE FRAICHE',1,true)==1,'S16 pair: the real Continue body shows distinct prose with both literal identifiers',body:sub(1,120))
 local after=Snapshot();for k,v in pairs(before) do soft(after[k]==v,'S16 pair: showing is passive: '..k) end
 c:Hide()
end
-- 7f. The composed identity-found note (core/GameAdapter.lua), from the
-- real adapter after a real association, at the Orb window's targets line
-- (whole note) and at /nexus wishlist (UserText: without its prefix).
local ID_SUFFIX=' Open the Wishlist Editor to choose and confirm its locked targets.'
local function IdentityWorld(entries)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;UISpecialFrames=nil
 NexusOrbPanel=nil;NexusOrbMini=nil;NexusOrbContinue=nil;NexusOrbRunLog=nil;NexusOrbHistoryCopy=nil
 if entries~=false then S.InstallBootHook(nil,entries) end
 local h=dofile('tests/prototype/harness.lua')
 local locks={200690,200756,200882,201250,201262,201270};local q={2,3,2,3,3,3};local total={}
 for i=1,79 do local id=210000+i;h.AddEcho(id,'Ordinary '..i,2,5);total[#total+1]={spellId=id,quality=2,stacks=1,locked=false} end
 for i,id in ipairs(locks) do h.AddEcho(id,'Locked '..i,q[i],5);total[#total+1]={spellId=id,quality=q[i],stacks=1,locked=false};h.locked[#h.locked+1]={spellId=id,stacks=1} end
 h.perks.serverBuildSlots={[1]={name='Synthetic active',verified=true,echoes=h.Clone(total)},[101]={name='Synthetic plan',verified=false,echoes=h.Clone(total)}}
 h.perks.serverActiveSlot=1
 h.Boot()
 local A=Nexus.GameAdapter
 local c;for _,row in ipairs(A.GetWishlistCandidates()) do if row.slot==101 then c=row end end
 assert(c and A.SetLoadoutWishlist(1,101,c),'SETUP S16 identity: a real association')
 h.perks.serverBuildSlots[101]=nil
 return h,A
end
local function IdRead(h,A)
 local before={F=Serialize(NexusDB),L=Serialize(WishlistRealizerDB),sent=#h.sent,actions=#h.actions}
 local wish=A.Wishlist()
 local note=A.WishlistNote()
 local f=Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh()
 local orb=f.targets:GetText();f:Hide()
 h.chat={};SlashCmdList.NEXUS('wishlist')
 local chat=h.chat[#h.chat]
 local after={F=Serialize(NexusDB),L=Serialize(WishlistRealizerDB),sent=#h.sent,actions=#h.actions}
 local passive=true;for k,v in pairs(before) do if after[k]~=v then passive=false end end
 return wish,note,orb,chat,passive
end
local TAG='|cff7fd5ffNexus:|r '
do
 local h,A=IdentityWorld(nil)
 h.perks.serverBuildSlots[1].verified=false
 local wish,note,orb,chat,passive=IdRead(h,A)
 local reason='active loadout is not verified; locked-Echo evidence is pending'
 soft(wish==nil and note=='Wishlist identity found; '..reason..'.'..ID_SUFFIX,'S16 identity: the adapter keeps its raw note',note)
 soft(orb==O..'Wishlist identity found; '..O..reason..C..'.'..ID_SUFFIX..C,'S16 identity: the Orb window says the whole note, the reason through its key',orb)
 soft(chat==TAG..O..O..reason..C..'.'..ID_SUFFIX..C,'S16 identity: /nexus wishlist says the note without its prefix, the reason through its key',chat)
 soft(passive,'S16 identity: reading and showing write nothing, send nothing, act on nothing')
 h.perks.serverBuildSlots[1].verified=true;h.locked=nil
 wish,note,orb,chat,passive=IdRead(h,A)
 reason='waiting for synchronized permanent locked-Echo evidence'
 soft(note=='Wishlist identity found; '..reason..'.'..ID_SUFFIX,'S16 identity sync: the adapter keeps its raw note',note)
 soft(orb==O..'Wishlist identity found; '..O..reason..C..'.'..ID_SUFFIX..C,'S16 identity sync: the Orb window says the whole note',orb)
 soft(chat==TAG..O.."Waiting for the server's current locked Echo list. Details: "..note..C,'S16 identity sync: close control, UserText keeps its keyed wait sentence with the raw note as details',chat)
 soft(passive,'S16 identity sync: passive')
 -- Unknown reason and the note without the editor instruction (the
 -- adapter's other branch), as the adapter records them.
 local unknown='an external; reason {x} 100%'
 A._wishlistNote='Wishlist identity found; '..unknown..'.';A._wishlistNoteFacts={text=A._wishlistNote,reason=unknown,pending=false}
 local ut=(Nexus.UserText.Message(A._wishlistNote))
 soft(ut==O..unknown..'.'..C,'S16 identity unknown: UserText keeps an unknown reason verbatim inside the key',ut)
 ut=(Nexus.OrbPanel.Phrase(A._wishlistNote))
 soft(ut==O..'Wishlist identity found; '..unknown..'.'..C,'S16 identity unknown: the Orb window keeps an unknown reason verbatim inside the key',ut)
 A._wishlistNote='Wishlist identity found; wishlist identity or structure is invalid.';A._wishlistNoteFacts={text=A._wishlistNote,reason='wishlist identity or structure is invalid',pending=false}
 ut=(Nexus.UserText.Message(A._wishlistNote))
 soft(ut==O..O..'Wishlist identity or structure is invalid'..C..'.'..C,'S16 identity no instruction: the note without the editor instruction',ut)
 ut=(Nexus.UserText.Message('Wishlist identity found; wishlist identity or structure is invalid. Open it'))
 soft(ut=='wishlist identity or structure is invalid. Open it','S16 identity: a text the adapter did not produce keeps the existing English rewrite',ut)
end
do
 local entries=S.PseudoEntries()
 entries['orb.assignment.identity_found_open_editor']=nil
 entries['orb.assignment.identity_found_reason_open_editor']=nil
 local h,A=IdentityWorld(entries)
 h.perks.serverBuildSlots[1].verified=false
 local _,note,orb,chat=IdRead(h,A)
 soft(orb==note,'S16 identity missing: a missing Orb candidate shows the whole note in exact English',orb)
 soft(chat==TAG..'active loadout is not verified; locked-Echo evidence is pending.'..ID_SUFFIX,'S16 identity missing: a missing UserText candidate shows the existing English',chat)
end
do
 local h,A=IdentityWorld(false)
 h.perks.serverBuildSlots[1].verified=false
 local _,note,orb,chat,passive=IdRead(h,A)
 soft(orb==note and note=='Wishlist identity found; active loadout is not verified; locked-Echo evidence is pending.'..ID_SUFFIX,'S16 identity English: the Orb window shows the exact note',orb)
 soft(chat==TAG..'active loadout is not verified; locked-Echo evidence is pending.'..ID_SUFFIX,'S16 identity English: /nexus wishlist shows the exact current English',chat)
 soft(passive,'S16 identity English: passive')
end
-- 7g. SOURCE18-9DE4-FINAL-SPEC-P2-01: an opaque identity reason stays
-- literal at both receivers, with a valid, missing or invalid candidate,
-- even when it reads like a refusal or contains a rewritten word. The real
-- adapter composes the note; only the read-only evidence leaf's reason is
-- controlled (defensive boundary; native production of these reasons is
-- not claimed). Expected outputs are written out here.
local function Leaf(A)
 local function Up(fn,want)
  for i=1,120 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==want then return i,v end end
  error('SETUP S16 opaque: missing upvalue '..want)
 end
 local _,resolve=Up(A.Wishlist,'ResolveWishlistEvidence')
 local index,original=Up(resolve,'ExactActiveWishlistRoles')
 return function(reason) debug.setupvalue(resolve,index,function() return nil,reason end) end,
  function() debug.setupvalue(resolve,index,original) end
end
local OPAQUE={
 {name='plain',reason='an external; reason {x} 100%'},
 {name='refusal-like',reason='an external no net gain; reason {x} 100%'},
 {name='coverage-like',reason='coverage lost: 7 {x} 100%'},
 {name='rewrite-like',reason='opaque TARGET: A {x} 100% UNARMED'},
}
for _,mode in ipairs({'candidate','missing','invalid'}) do
 local entries=S.PseudoEntries()
 if mode=='missing' then
  entries['orb.assignment.identity_found_open_editor']=nil
  entries['orb.assignment.identity_found_reason_open_editor']=nil
 elseif mode=='invalid' then
  entries['orb.assignment.identity_found_open_editor']='{reason} {nope}'
  entries['orb.assignment.identity_found_reason_open_editor']='{reason} {nope}'
 end
 local h,A=IdentityWorld(entries)
 local set,restore=Leaf(A)
 for _,case in ipairs(OPAQUE) do
  set(case.reason)
  local wish,note,orb,chat,passive=IdRead(h,A)
  local raw='Wishlist identity found; '..case.reason..'.'..ID_SUFFIX
  local wantOrb,wantChat
  if mode=='candidate' then
   wantOrb=O..raw..C
   wantChat=TAG..O..case.reason..'.'..ID_SUFFIX..C
  else
   wantOrb=raw
   wantChat=TAG..case.reason..'.'..ID_SUFFIX
  end
  local tag='S16 opaque '..mode..' '..case.name
  soft(wish==nil and note==raw,tag..': the adapter composes its raw note with the exact reason and instruction',note)
  soft(orb==wantOrb,tag..': the Orb window shows the whole note with the exact reason',orb)
  soft(chat==wantChat,tag..': /nexus wishlist shows the note with the exact reason, no legacy rewrite',chat)
  soft(passive,tag..': passive read')
 end
 restore()
end
do
 -- Close controls: a known reason keeps its keyed choose sentence; ordinary
 -- non-identity legacy texts behave as before; an unknown text resembling
 -- an identity note (not the adapter's note) keeps the legacy route.
 local h,A=IdentityWorld(nil)
 local set,restore=Leaf(A)
 set('wishlist does not exactly match the verified active loadout; locked roles remain unknown')
 local _,note,_,chat=IdRead(h,A)
 restore()
 soft(chat==TAG..O.."Choose this Wishlist's locked Echo targets in the editor. Your planned build does not have to match the equipped build. Details: "..note..C,
  'S16 opaque control: a known reason keeps its keyed choose sentence with the whole note as details',chat)
 soft((Nexus.UserText.Message('save refused: no net gain over the saved build'))==O..'Not saved: no additional matching Wishlist copies were confirmed.'..C,
  'S16 opaque control: a non-identity refusal keeps its legacy meaning')
 soft((Nexus.UserText.Message('opaque TARGET: A'))=='opaque WISHLIST: A','S16 opaque control: a non-identity text keeps the legacy rewrite')
 soft((Nexus.UserText.Message('Wishlist identity found; an external no net gain; reason.'))==O..'Not saved: no additional matching Wishlist copies were confirmed.'..C,
  'S16 opaque control: a text that only resembles an identity note keeps the legacy route')
end
-- 7h. UserText.EnglishMessage stays English for the adapter's trusted
-- identity note while another language is active (the scoped English-only
-- override reaches the typed identity route). The real session pack and the
-- real adapter note are used; only the read-only evidence leaf's reason is
-- controlled for the opaque case. Expected texts are written out here.
do
 local UT=function() return Nexus.UserText end
 local KNOWN='active loadout is not verified; locked-Echo evidence is pending'
 local OPAQUE='an external no net gain; opaque TARGET: A {x} 100%'
 local function Snap(h) return Serialize(NexusDB)..'|'..Serialize(WishlistRealizerDB)..'|'..#h.sent..'|'..#h.actions end
 for _,mode in ipairs({'candidate','missing','invalid','english'}) do
  local entries
  if mode=='english' then entries=false else
   entries=S.PseudoEntries()
   if mode=='missing' then entries['orb.assignment.identity_found_reason_open_editor']=nil
   elseif mode=='invalid' then entries['orb.assignment.identity_found_reason_open_editor']='{reason} {nope}' end
  end
  local h,A=IdentityWorld(entries)
  h.perks.serverBuildSlots[1].verified=false
  local set,restore=Leaf(A)
  for _,case in ipairs({{name='known',reason=nil},{name='opaque',reason=OPAQUE}}) do
   if case.reason then set(case.reason) else restore() end
   A.Wishlist()
   local note=A.WishlistNote()
   local reason=case.reason or KNOWN
   local tag='S16 English '..mode..' '..case.name
   soft(note=='Wishlist identity found; '..reason..'.'..ID_SUFFIX,tag..': the adapter keeps its raw note',note)
   local english=reason..'.'..ID_SUFFIX
   local shown
   if mode=='candidate' then
    shown=case.reason and (O..reason..'.'..ID_SUFFIX..C) or (O..O..reason..C..'.'..ID_SUFFIX..C)
   else shown=english end
   local before=Snap(h)
   local d1=UT().Message(note)
   local e1=UT().EnglishMessage(note)
   local d2=UT().Message(note)
   soft(d1==shown,tag..': the display says the note in the active language',d1)
   soft(e1==english,tag..': EnglishMessage is the exact English, reason and pending instruction whole, no lead',e1)
   soft(d2==shown,tag..': the active language is restored after English conversion',d2)
   soft(Snap(h)==before and A.WishlistNote()==note,tag..': conversion is passive and the raw note unchanged')
  end
  restore()
  if mode=='candidate' then
   -- An error inside the English conversion still restores the active language.
   A.Wishlist()
   local note=A.WishlistNote()
   local real=A.WishlistNoteFacts
   A.WishlistNoteFacts=function() error('probe: facts unavailable') end
   local ok=pcall(UT().EnglishMessage,note)
   A.WishlistNoteFacts=real
   soft(not ok,'S16 English error: the conversion error reaches the caller')
   soft(UT().Message(note)==O..O..KNOWN..C..'.'..ID_SUFFIX..C,'S16 English error: the active language is restored after a failed English conversion',UT().Message(note))
   -- Close controls: a keyed wait sentence, an unrelated refusal and the
   -- wrapped advisor line keep their historical English presentation.
   set(nil) restore()
   h.perks.serverBuildSlots[1].verified=true;h.locked=nil
   A.Wishlist()
   local sync=A.WishlistNote()
   soft(UT().EnglishMessage(sync)=="Waiting for the server's current locked Echo list. Details: "..sync,'S16 English control: the keyed wait sentence stays its English',UT().EnglishMessage(sync))
   soft(UT().EnglishMessage('save refused: no net gain over the saved build')=='Not saved: no additional matching Wishlist copies were confirmed.','S16 English control: an unrelated refusal keeps its English rewrite')
   h.perks.serverBuildSlots[1].verified=false;h.locked={}
   for _,id in ipairs({200690,200756,200882,201250,201262,201270}) do h.locked[#h.locked+1]={spellId=id,stacks=1} end
   A.Wishlist()
   local line='TARGET: none -- advisor only  ('..A.WishlistNote()..')'
   soft(UT().EnglishMessage(line)=='WISHLIST: none -- advisor only  ('..KNOWN..'.'..ID_SUFFIX..')','S16 English control: the wrapped advisor line keeps its historical English',UT().EnglishMessage(line))
  end
 end
end
check(#S16==0,'Source16 Orb receivers:\n'..table.concat(S16,'\n'))

print('l10n_ui_orb: '..checks..' checks')
