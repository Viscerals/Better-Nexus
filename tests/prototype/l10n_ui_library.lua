-- Full UI localization, library family (Build Library, its Share/Edit forms,
-- confirmations, the shared-data startup window and the Sync mode dialog).
-- A pseudo pack (tests/prototype/l10n_pseudo_support.lua) is active from
-- session start; the real TOC boot, catalog, projections and windows run with
-- synthetic builds. Every visible code-owned word must reach its real display
-- receiver (FontString/Button text, tooltip lines, popup text, chat) marked as
-- translated; data (titles, names, descriptions, Echo names, numbers) is
-- allowed by an explicit list built from the fixture. Also: exact English for
-- representative keys in a plain-English child process, "long" pseudo mode,
-- a missing-entry fallback, template slots (unknown "?", zero "0", long and
-- non-ASCII names verbatim), and passivity (saved bytes, sends, actions)
-- across re-rendering, hovering, selection-free navigation and opening the
-- Sync mode dialog, measured after one intentional first open (opening
-- currently normalizes saved filter defaults: a known owner-lane issue).
-- Synthetic offline evidence only; native NOT_RUN.
local MODE=arg and arg[1]
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end

-- ---------------------------------------------------------------- English
-- Child process: plain English session (no pack). Exact bytes of
-- representative keys at their real receivers.
if MODE=='english' then
 local F=dofile('tests/prototype/format5_support.lua')
 local H=F.Boot(F.Database())
 for _=1,200 do H.Advance(.05,.05) end
 local L=Nexus.Localization
 check(L.ActiveLanguage()=='enUS','english session')
 local d=L.Diagnostics()
 check(d.base.undeclared==0 and d.base.missingDeclared==0,'catalog complete: undeclared='..d.base.undeclared..' missing='..d.base.missingDeclared)
 Nexus.CommunityBuilds.Show()
 for _=1,200 do H.Advance(.05,.05) end
 local f=assert(NexusCommunityBuildsFrame)
 check(f._titleText:GetText()=='Explore / Build Library','English title')
 check(f._syncBtn:GetText()=='Sync Now' and f._modeBtn:GetText()=='Sync mode...' and f._postBtn:GetText()=='Share Build','English action buttons')
 check(f._scopeBtn:GetText()=='All Shared' and f._myBuildsBtn:GetText()=='Mine','English scope buttons')
 check(f._sortToggle:GetText()=='Sort: Highest DPS','English sort label: '..tostring(f._sortToggle:GetText()))
 check(f._emptyState:GetText()=='No builds yet.\n\nPost a build from your active Echo Wishlist, or press Sync Now to find builds from other players.','English empty state')
 local st=f._detailPanel._nexusStatus
 check(st==nil or not st:IsShown() or st.title:GetText()=='No build selected','English detail status')
 check(L.Text('library.heading.detail_loading')=='Loading build details...','required key detail_loading')
 check(L.Text('library.body.detail_not_in_library')=='This build is not in your build library. It may have been removed, not received yet, or not accepted.','required key not_in_library')
 check(L.Text('library.heading.detail_unavailable')=='Build not available' and L.Text('library.heading.detail_incomplete')=='Build not available yet','required headings')
 check(L.Text('library.body.no_selection')=='Select a build on the left to see its Echoes, DPS records and owner. Selecting a build only reads it; nothing is sent, saved or assigned.','required no_selection body')
 f._modeBtn:Click()
 local dlg=assert(NexusSyncModeDialog)
 check(dlg.title:GetText()=='Sync mode' and dlg.apply:GetText()=='Apply' and dlg.cancel:GetText()=='Cancel','English Sync dialog')
 local labels={}
 for _,o in ipairs(dlg.options) do labels[#labels+1]=o.label:GetText() end
 check(table.concat(labels,',')=='Automatic,Manual,Off','English mode labels')
 check(dlg.current:GetText():find('^Current: Manual')~=nil,'English current line: '..tostring(dlg.current:GetText()))
 check(Nexus.SyncModePolicy.DisplayText('off')==Nexus.SyncModePolicy.Text('off') and Nexus.SyncModePolicy.DisplayText('manual')==Nexus.SyncModePolicy.Text('manual'),
  'DisplayText equals the raw English reason under English')
 dlg:Hide()
 check(L.Format('library.status.showing_range',{first=L.Count(1),last=L.Count(0),total=L.Count(nil)})=='Showing 1-0 of ?','template: zero is 0, unknown is ?')
 print('PASS l10n_ui_library english checks='..checks)
 return
end

-- ---------------------------------------------------------------- fixture
local F=dofile('tests/prototype/format5_support.lua')
local LB=dofile('tests/prototype/leaderboard_fixture_support.lua')
local ACCENT='Valentin\195\169'
local LONG=string.rep('W',40)..'caf\195\169'..string.rep('M',35)
local function Fixture()
 local fx=LB.New({players={
  {name='PrototypeTester',class='MAGE',isLocal=true,variant=1,ordinary=20,locked=2,dps={dummy=61000,lk=62000},title='Tester shared build'},
  {name=ACCENT,class='PRIEST',variant=2,ordinary=12,locked=0,dps={dummy=50000},title=LONG},
  {name='Shortname',class='WARRIOR',variant=3,ordinary=4,locked=0,title='Short build'},
 }})
 local db=F.Database({version=2})
 fx:Install(db)
 return fx,db
end
local function BootWith(db)
 return F.Boot(db,function(h)
  h.playerLevel=80
  h.perks.serverBuildSlots={[1]={name='Server slot alpha',verified=true,echoes={{spellId=200001,quality=0,stacks=1}}}}
 end)
end

-- ---------------------------------------------------------------- data allowlist
local DATA={Nexus=true}
local function AddWords(text)
 for w in tostring(text or ''):gmatch("[A-Za-z][A-Za-z']+") do DATA[w]=true end
end
local function CollectData(H)
 for _,b in pairs(NexusDB.communityBuilds or {}) do AddWords(b.title);AddWords(b.author);AddWords(b.description);AddWords(b.realm) end
 for _,n in pairs(H.names or {}) do AddWords(n) end
 for _,s in pairs(H.perks and H.perks.serverBuildSlots or {}) do AddWords(s.name) end
 AddWords(UnitName and UnitName('player'))
 local catalog=Nexus.BuildCatalog
 if Nexus.CommunityBuilds and Nexus.CommunityBuilds.Builds then
  local map=Nexus.CommunityBuilds.Builds()
  for _,b in pairs(map or {}) do AddWords(b.title);AddWords(b.author);AddWords(b.description) end
 end
end
-- Echo-name fallback "Echo <spellId>" is game data (CommunityController
-- EchoDisplayName); a plain word "Echo" elsewhere is not allowed.
local function Allow(word,text)
 if DATA[word] then return true end
 if word=='Echo' and S.Unmarked(text):find('Echo %d+') then return true end
 return false
end

-- Other families' widgets shown on this window (FullUIWorkspaces tab labels)
-- and the two labels kept as source literals (pending, help_action_first lint).
local function Skip(item,frame)
 local tabs=frame and frame._workspaceTabs or {}
 for _,b in pairs(tabs) do
  if item.frame==b or (b.GetFontString and item.frame==b:GetFontString()) then return true end
 end
 local plain=S.Unmarked(item.text)
 return plain=='Updating results...' or plain=='Stop Sharing'
end
local function Scan(root,label,frame)
 local texts=S.VisibleTexts(root)
 local keep={}
 for _,t in ipairs(texts) do if not Skip(t,frame) then keep[#keep+1]=t end end
 local missing=S.Untranslated(keep,Allow)
 local lines={}
 for _,m in ipairs(missing) do lines[#lines+1]=m.word..' in ['..m.text..']' end
 check(#missing==0,label..': untranslated visible text: '..table.concat(lines,' | '))
 return keep
end
local function TooltipOf(widget,label)
 local fn=widget and widget:GetScript('OnEnter')
 if not fn then return {} end
 local lines=S.CaptureTooltip(fn,widget)
 local missing=S.Untranslated(lines,Allow)
 local shown={}
 for _,m in ipairs(missing) do shown[#shown+1]=m.word..' in ['..m.text..']' end
 check(#missing==0,label..' tooltip: '..table.concat(shown,' | '))
 return lines
end
local function AnyPseudo(lines) for _,l in ipairs(lines) do if S.IsPseudo(l) then return true end end return false end

-- ---------------------------------------------------------------- long mode
if MODE=='long' then
 S.InstallBootHook('long')
 local fx,db=Fixture()
 local H=BootWith(db)
 for _=1,300 do H.Advance(.05,.05) end
 CollectData(H)
 Nexus.CommunityBuilds.Show()
 for _=1,300 do H.Advance(.05,.05) end
 local f=assert(NexusCommunityBuildsFrame)
 check(f:IsShown(),'long: the window shows')
 Nexus.CommunityBuilds.ShowBuild(fx.players[1].buildId)
 for _=1,300 do H.Advance(.05,.05) end
 local texts=Scan(f,'long main',f)
 check(#texts>20,'long: texts are shown: '..#texts)
 check(f._detailPanel:IsShown() and S.IsPseudo(f._detailPanel.recordsTitle:GetText()),'long: detail shows translated text')
 f._modeBtn:Click()
 Scan(NexusSyncModeDialog,'long Sync mode dialog')
 print('PASS l10n_ui_library long checks='..checks)
 return
end

-- ---------------------------------------------------------------- missing-entry fallback
if MODE=='fallback' then
 local entries=S.PseudoEntries()
 local REMOVED={'library.button.share_build','library.status.sync_listening','library.heading.browse_builds','sync.title.mode_dialog','library.status.sync_counts_idle','sync.label.mode_off'}
 for _,k in ipairs(REMOVED) do assert(entries[k],'pseudo entry '..k);entries[k]=nil end
 S.InstallBootHook(nil,entries)
 local H=BootWith(select(2,Fixture()))
 for _=1,300 do H.Advance(.05,.05) end
 Nexus.CommunityBuilds.Show()
 for _=1,300 do H.Advance(.05,.05) end
 local f=assert(NexusCommunityBuildsFrame)
 check(f._postBtn:GetText()=='Share Build','fallback: removed button key shows exact English')
 check(f._browseLabel:GetText()=='BROWSE BUILDS','fallback: removed heading shows exact English')
 check(S.IsPseudo(f._modeBtn:GetText()),'fallback: a present key still shows the pack')
 local status=f._syncStatusText:GetText()
 check(status:find(' bundled + ',1,true) and not S.IsPseudo(status:match('^[^\n]*')),
  'fallback: removed template renders its English template: '..status)
 f._modeBtn:Click()
 local d=NexusSyncModeDialog
 check(d.title:GetText()=='Sync mode','fallback: dialog title English')
 local off
 for _,o in ipairs(d.options) do if o.mode=='off' then off=o end end
 check(off.label:GetText()=='Off' and S.IsPseudo(off.help:GetText()),'fallback: removed mode label English, its help translated')
 print('PASS l10n_ui_library fallback checks='..checks)
 return
end

-- ---------------------------------------------------------------- pseudo scan (main)
S.InstallBootHook()
local fx,db=Fixture()
local H=BootWith(db)
for _=1,300 do H.Advance(.05,.05) end
CollectData(H)
local L=Nexus.Localization
check(L.ActiveLanguage()=='frFR','pseudo pack active')
local diag=L.Diagnostics()
check(diag.base.undeclared==0 and diag.base.missingDeclared==0,'catalog complete under the pseudo pack')
local CB=Nexus.CommunityBuilds

-- Intentional first open (normalizes saved filter defaults: owner-lane PD1),
-- then a settled baseline.
CB.Show()
for _=1,300 do H.Advance(.05,.05) end
local f=assert(NexusCommunityBuildsFrame)
check(f:IsShown(),'the Build Library is shown')
CollectData(H)

local function Snapshot()
 return {db=F.Serialize(NexusDB),wl=F.Serialize(WishlistRealizerDB or {}),sent=#H.sent,actions=#H.actions}
end
local function Same(a,b) return a.db==b.db and a.wl==b.wl and a.sent==b.sent and a.actions==b.actions end

-- Populated list, no selection.
local base=Snapshot()
local texts=Scan(f,'populated list',f)
check(#texts>20,'the populated list shows texts: '..#texts)
check(S.IsPseudo(f._titleText:GetText()) and S.IsPseudo(f._syncBtn:GetText()) and S.IsPseudo(f._resultText:GetText()),'toolbar receivers show pseudo text')
check(f._syncStatusText:GetText():find(S.OPEN,1,true)~=nil,'status line shows pseudo text')
local status=f._detailPanel._nexusStatus
check(status and status:IsShown() and status.kind=='none' and S.IsPseudo(status.title:GetText()) and S.IsPseudo(status.text:GetText()),
 'no-selection detail status is translated (kind none)')
-- Card rows: title (data) + translated byline, badges and DPS lines.
local cards=0
for _,t in ipairs(texts) do if t.text=='Tester shared build' then cards=cards+1 end end
check(cards>=1,'the row shows the fixture title verbatim (default filter: current class only): '..cards)

-- Hovers of every toolbar control and a row button (passive).
for name,w in pairs({scope=f._scopeBtn,mine=f._myBuildsBtn,class=f._classDropBtn,qualified=f._qualifiedBox,
  sort=f._sortToggle,sync=f._syncBtn,mode=f._modeBtn,post=f._postBtn}) do
 local lines=TooltipOf(w,name)
 check(#lines>0 and AnyPseudo(lines),name..': tooltip lines reach GameTooltip translated')
end
local hit=f._syncStatusHit
if hit and hit:GetScript('OnEnter') then TooltipOf(hit,'status line') end

-- Re-render and hover are passive.
for _=1,3 do CB.Refresh();H.Advance(.05,.05) end
check(Same(base,Snapshot()),'rendering and hovering the populated list changed no saved byte, send or action')

-- Sync mode dialog: opening is a draft only.
f._modeBtn:Click()
local dlg=assert(NexusSyncModeDialog)
check(dlg:IsShown(),'Sync mode dialog opens')
Scan(dlg,'Sync mode dialog')
for _,o in ipairs(dlg.options) do check(S.IsPseudo(o.label:GetText()) and S.IsPseudo(o.help:GetText()),'mode option '..o.mode..' translated') end
check(S.IsPseudo(dlg.current:GetText()),'current-mode line translated: '..dlg.current:GetText())
dlg.cancel:Click()
check(not dlg:IsShown() and Same(base,Snapshot()),'opening and cancelling the Sync mode dialog wrote and sent nothing')

-- Selection (a read) then detail: own build.
local own=fx.players[1].buildId
CB.ShowBuild(own)
for _=1,300 do H.Advance(.05,.05) end
local p=f._detailPanel
check(p:IsShown() and p._nexusShownId==own,'own build detail shown')
local selectedBase=Snapshot()
Scan(f,'own build detail',f)
check(S.IsPseudo(p.recordsTitle:GetText()) and S.IsPseudo(p.dummyRecord:GetText()) and S.IsPseudo(p.author:GetText()),'detail receivers translated')
check(p.title:GetText()=='Tester shared build','build title stays data')
for name,w in pairs({copy=p.lockBtn,share=p.shareBtn,retry=p.retryShareBtn,link=p.linkSaveBtn}) do
 if w:IsShown() then local lines=TooltipOf(w,'detail '..name);check(AnyPseudo(lines),'detail '..name..' tooltip translated') end
end
for _=1,3 do CB.Refresh();H.Advance(.05,.05) end
check(Same(selectedBase,Snapshot()),'re-rendering and hovering the selected detail changed nothing')

-- Remote build with an accented owner and a long title: inserted verbatim.
local remote=fx.players[2].buildId
CB.ShowBuild(remote)
for _=1,300 do H.Advance(.05,.05) end
check(p._nexusShownId==remote,'remote detail shown')
Scan(f,'remote build detail',f)
check(p.author:GetText():find(ACCENT,1,true)~=nil and S.IsPseudo(p.author:GetText()),'non-ASCII owner name inserted verbatim into the translated byline: '..p.author:GetText())
check(p.title:GetText()==LONG,'long title shown verbatim')

-- Detail status states through the real projection: unavailable.
CB.ShowBuild('lbfx-not-in-library')
for _=1,100 do H.Advance(.05,.05) end
status=p._nexusStatus
check(status:IsShown() and status.kind=='unavailable' and status.title:GetText()==L.Text('library.heading.detail_unavailable')
 and status.text:GetText()==L.Text('library.body.detail_not_in_library') and S.IsPseudo(status.text:GetText()),'not-in-library status translated (kind unavailable)')

-- Mine scope (an explicit filter click; outside the passivity window).
f._myBuildsBtn:Click()
for _=1,300 do H.Advance(.05,.05) end
Scan(f,'Mine scope',f)
f._scopeBtn:Click()
for _=1,200 do H.Advance(.05,.05) end

-- Share form, its source and class menus.
CB.ShowPostBuild()
for _=1,20 do H.Advance(.05,.05) end
local post=assert(NexusPostPopup)
check(post:IsShown(),'Share form shown')
Scan(post,'Share form')
post._postWishlistBtn:Click()
Scan(post,'Share form source menu')
post._postClassBtn:Click()
Scan(post,'Share form class menu')
post:Hide()

-- Edit dialog of the own build.
CB.ShowBuild(own);for _=1,100 do H.Advance(.05,.05) end
p.editBtn:Click()
local edit=assert(NexusEditPopup)
check(edit:IsShown(),'Edit dialog shown')
Scan(edit,'Edit dialog')
edit:Hide()

-- Stop Sharing confirmation: real popup text and buttons.
p.deleteBtn:Click()
local dialog=StaticPopupDialogs.NEXUS_STOP_SHARING_BUILD
check(H.popup and H.popup.which=='NEXUS_STOP_SHARING_BUILD' and S.IsPseudo(dialog.text) and S.IsPseudo(dialog.button1) and S.IsPseudo(dialog.button2),
 'Stop Sharing confirmation translated')
local shown=string.format(dialog.text,tostring(H.popup.arg1),tostring(H.popup.arg2))
check(shown:find('Tester shared build',1,true) and S.LooksUntranslated(shown,Allow)==nil,'confirmation shows the title verbatim inside translated text: '..shown)
StaticPopup_Hide('NEXUS_STOP_SHARING_BUILD')

-- Chat: a Copy refusal for a build still syncing is a real print path.
local lines=S.CaptureChat(function()
 print('|cff7fd5ffNexus:|r '..L.Text('library.chat.build_still_syncing'))
end)
check(#lines==1 and S.IsPseudo(lines[1]),'chat receiver shows pseudo text')
local applied=S.CaptureChat(function()
 f._modeBtn:Click();NexusSyncModeDialog.apply:Click()
end)
check(#applied>=1 and S.IsPseudo(applied[#applied]) and S.LooksUntranslated(applied[#applied],Allow)==nil,'Sync mode Apply chat line translated: '..tostring(applied[#applied]))
check(S.IsPseudo(NexusSyncModeDialog.result:GetText()),'Apply result line translated')
NexusSyncModeDialog:Hide()

-- Templates: long/non-ASCII names verbatim, unknown "?" and zero "0".
local row=L.Format('library.status.showing_range',{first=L.Count(0),last=L.Count(nil),total=L.Count(3)})
check(S.IsPseudo(row) and row:find('0-?',1,true),'template: zero 0 and unknown ? under the pack: '..row)
local named=L.Format('library.chat.share_preparing',{name=LONG})
check(named:find(LONG,1,true) and S.IsPseudo(named),'template inserts a long non-ASCII name verbatim')
check(Nexus.SyncModePolicy.Text('off')~=Nexus.SyncModePolicy.DisplayText('off') and Nexus.SyncModePolicy.IsModeReason(Nexus.SyncModePolicy.Text('off')),
 'raw mode reason stays English and compared; display form is translated')
check(Nexus.SyncModePolicy.DisplayReason(Nexus.SyncModePolicy.Text('manual'))==L.Text('sync.status.mode_manual'),'DisplayReason maps the raw manual reason')
check(Nexus.CommunityInternals.ShownReason('not your build')==L.Text('library.error.not_your_build')
 and Nexus.CommunityInternals.ShownReason('an unknown raw reason')=='an unknown raw reason','controller reasons: known mapped, unknown shown as given')

-- Child processes: English, long and missing-entry fallback.
local exe=arg and arg[-1] or 'luajit'
for _,mode in ipairs({'english','long','fallback'}) do
 local cmd='"'..exe..'" tests/prototype/l10n_ui_library.lua '..mode..' 2>&1'
 local h=assert(io.popen(cmd));local out=h:read('*a');local ok=h:close()
 check(out:find('PASS l10n_ui_library '..mode,1,true)~=nil,mode..' child process passed: '..out:sub(-600))
end
print('PASS l10n_ui_library checks='..checks..' (synthetic; native NOT_RUN)')
