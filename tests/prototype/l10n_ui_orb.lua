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
do
 local failures=S.BookFidelity(BOOK,'english')
 check(#failures==0,'English: every Orb book entry shows the producer bytes:\n'..table.concat(failures,'\n'))
 local exactN=0
 for _ in pairs(BOOK.exact) do exactN=exactN+1 end
 check(exactN>340 and #BOOK.formats==26,'Orb book admitted whole: '..exactN..' exact, '..#BOOK.formats..' formats')
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
 local failures=S.BookFidelity(UI.PhraseBook(),'pseudo')
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

print('l10n_ui_orb: '..checks..' checks')
