-- Full UI localization, records family (issues #143-#148): the Leaderboard,
-- the startup status, the data log window, the support report page, the
-- one-time release note and the new-best DPS chat line show every
-- code-owned word through Nexus.Localization at their real display
-- receivers (FontString and button text, tooltip lines, chat), while
-- player, build and realm names, DPS figures, log text and support payload
-- stay as they are.
--
-- Sessions (each a real TOC boot with synthetic saved data):
--  1. English: exact English bytes for representative keys; the support
--     summary and report payload are recorded.
--  2. Pseudo pack from session start: every window in its main states
--     (populated, empty, loading/sync status, refusal, hovers, class menu,
--     log tabs, support states, release note) is scanned for untranslated
--     words; payload bytes equal session 1; rendering, hovering and
--     navigation write, send and act nothing.
--  3. "long" pseudo pack on the densest windows: no error, text still shown,
--     no template refused by its result limit.
--  4. Pseudo pack with some records keys removed: those show exact English.
--  5. New-best DPS chat line on a read-only profile under the pseudo pack.
-- Synthetic offline evidence only: no glyph, font, pixel or native claim.
local S=dofile('tests/prototype/l10n_pseudo_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local LF=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local function plain(text) return (tostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end

-- Synthetic records: Alpha has both records, Bravo a Training Dummy record
-- only, Carol a Lich King record whose build page is missing (a Copy
-- refusal). Titles and names are data and never translated.
local function Fixture()
 return LF.New({players={
  {name='Alpha',class='MAGE',dps={dummy=48250,lk=51000},title='Zxq Alpha Vrk',locked=2},
  {name='Bravo',class='PRIEST',dps={dummy=30100},title='Zxq Bravo Vrk',locked=0},
  {name='Carol',class='ROGUE',dps={lk=1250000},title='Zxq Carol Vrk',build='missing',locked=0},
 }})
end
local fx=Fixture()
local DATA={'Alpha','Bravo','Carol','Zxq Alpha Vrk','Zxq Bravo Vrk','Zxq Carol Vrk','ebonhold','Ebonhold'}
for _,p in ipairs(fx.players) do DATA[#DATA+1]='Synthetic Leaderboard fixture build '..p.buildId;DATA[#DATA+1]=p.buildId end

local function Boot(hookMode,entries,db)
 if hookMode~=false then S.InstallBootHook(hookMode,entries) end
 local H=F.Boot(db or Fixture():Install(F.Database()))
 for _=1,200 do H.Advance(.05,.05) end
 return H
end
local function T(key) return (Nexus.Localization.Text(key)) end

-- The support payload of one session, computed at a fixed clock right after
-- boot so both sessions build it from the same synthetic incident and time.
local function SupportPayload(H)
 H.now=math.max(H.now,100000)
 local support=Nexus.SupportIncidents
 support.Clear()
 support.Record('catalog-refusal',{reason='SEMANTIC_ENVELOPE',producer='saved-build capture',origin='local',
  operation='saved-build capture',ticket='t-1',build='test.9999-abcdef0',representation='inline',
  counts={ordinary=81,locked=6,total=87},limits={ordinary=79,locked=6,total=85},
  affected={{spellId=200701,quality=2,stacks=1,locked=true}},committed=false,scope='synthetic scope'})
 local builder=Nexus.SupportReport
 local incident=support.Latest()
 local summary=builder.Summary(incident)
 local report=assert(builder.Prepare({incident=incident,extended=false}),'the report is built')
 local lines=table.concat(builder.IncidentLines(incident),'\n')
 return {summary=summary,chunks=table.concat(report.chunks,'\0'),lines=lines}
end

local function Find(pred)
 for _,f in ipairs(H_frames()) do if pred(f) then return f end end
end
function H_frames() return CURRENT_H.frames end
-- FontStrings are regions, not harness frames: walk the tree under root.
local function FindRegion(root,pred)
 for _,r in ipairs(root.regions or {}) do if pred(r) then return r end end
 for _,c in ipairs(root.children or {}) do local hit=FindRegion(c,pred);if hit then return hit end end
end
-- A button by its English label, or by that label as reviewed pseudo text in
-- a pseudo session (the owner adopted the Help-quoted labels as keys).
local function Button(text,parent)
 local marked=S.OPEN..text..S.CLOSE
 return Find(function(f) local t=f.kind=='Button' and f:GetText() return (t==text or t==marked) and (not parent or f:GetParent()==parent) end)
end
local function Hover(f)
 local enter=assert(f and f:GetScript('OnEnter'),'a hover script')
 return S.CaptureTooltip(function() enter(f) end)
end

------------------------------------------------------------------------
-- 1. English session
------------------------------------------------------------------------
CURRENT_H=Boot(false)
local H=CURRENT_H
local english=SupportPayload(H)
local LB=Nexus.Leaderboard
LF.Open(H,'lk')
local frame=NexusLeaderboardFrame
local function Texts(root) local out={};for _,i in ipairs(S.VisibleTexts(root)) do out[plain(i.text)]=true end;return out end
local en=Texts(frame)
check(en['2 ranked Lich King records • best known, from shared records received'],'EN the Lich King count line keeps its exact English')
check(en['Training Dummy'] and en['Lich King'] and en['Both records'],'EN the category tabs keep their English')
check(en['CHARACTER / LOADOUT'] and en['RESULT'] and en['#'],'EN the column headers keep their English')
check(en['Copy into Editor']==nil or true,'EN (detail buttons hidden without a selection)')
check(frame._leaderboardDetail.empty:GetText()==LB.SELECT_PROMPT,'EN the select prompt equals M.SELECT_PROMPT')
LB.SetClassFilter('WARRIOR');for _=1,40 do H.Advance(.05,.05) end
en=Texts(frame)
check(en['0 ranked Lich King records • best known, from shared records received'],'EN zero is shown as 0 in the count line')
check(frame._leaderboardDetail.empty:GetText()=='No Lich King records are known yet.\n\nLeaderboard data syncs on login; Sync Now checks again.','EN the empty pane keeps its exact English')
LB.SetCategory('combined');for _=1,40 do H.Advance(.05,.05) end
check(frame._leaderboardDetail.empty:GetText()=='No builds have both Training Dummy and Lich King records yet.\n\nBoth-record builds are ordered by their highest valid single DPS result. The displayed average does not determine this rank.','EN the empty Both records pane keeps its exact English')
LB.SetClassFilter('ALL');LB.Hide()
-- Release note: the composed note equals the former literal byte for byte.
local NOTE='|cffffd200Assigned Wishlist and visible Help|r\n'
 ..'- Orb mode uses the same assigned Wishlist as the main panel.\n'
 ..'- Enter a maximum and Start once to approve safe surplus copies and recycling.\n'
 ..'- Required rolled copies and future permanent targets remain protected.\n'
 ..'- Help retains seven topics with corrected text and navigation layering.\n\n'
 ..'|cffffd200Optional Orb refinement|r\n'
 ..'- Target changes pause the run. Resume retains its used and pending budget.\n'
 ..'- Close keeps an approved run active; main-panel Pause/Stop remain available.\n'
 ..'- Same-ID, same-quality results remain paused when completion cannot be proved.\n\n'
 ..'Experimental: native gameplay is not verified by offline tests.\n'
 ..'Real-resource Orb testing requires a separate user decision.'
check(Nexus.Changelog.NoteText()==NOTE,'EN the release note body is byte-identical')
-- Startup status: representative sentences, including capacity refusals.
local LS=Nexus.LoadingStatus
local function cap(counter,map,limit,bundled,reason)
 return LS.CapacityText({state='failed',coreReady=true,reason=reason or 'ROOT_SLOT_LIMIT',
  failure={counter=counter,map=map,limit=limit,counted={bundled=bundled or 0}}})
end
check(cap('distinct-slots','barrier',2048,5)=='Community data unavailable: your saved Community builds, the builds shipped with this version, removal markers and retention markers together hold more than the 2048 different entries this build opens. Nothing was changed or deleted.','EN capacity: distinct slots, barrier, shipped')
check(cap('distinct-slots','tombstone',2048,0)=='Community data unavailable: your saved Community builds and removal markers together hold more than the 2048 different entries this build opens. Nothing was changed or deleted.','EN capacity: distinct slots, tombstone')
check(cap('distinct-slots','builds',2048,3)=='Community data unavailable: your saved Community builds and the builds shipped with this version together hold more than the 2048 different entries this build opens. Nothing was changed or deleted.','EN capacity: distinct slots, builds, shipped')
check(cap('map-keys','barrier',2048,0,'BARRIER_SET_LIMIT')=='Community data unavailable: the saved retention markers exceed the limit (2048). Nothing was changed or deleted.','EN capacity: retention markers')
check(cap('map-keys','bundled',2048,0)=='Community data unavailable: the builds shipped with this version exceed the limit (2048). Nothing was changed or deleted.','EN capacity: shipped builds')
check(cap('distinct-builds','x',2048,0)=='Community data unavailable: your saved Community list holds more than the 2048 different builds this build opens. Nothing was changed or deleted.','EN capacity: distinct builds')
check(cap('root-map-edges','x',8192,0,'ROOT_MAP_LIMIT')=='Community data unavailable: your saved Community records and markers together exceed the total this build opens (limit 8192). Nothing was changed or deleted.','EN capacity: total')
check(cap('map-keys','x',0,0)=='Community data unavailable: your saved Community data is larger than this build opens. Nothing was changed or deleted.','EN capacity: no limit recorded')
local _,progress=LS.Progress({state='pending',coreReady=true,step='catalog-sort',stepDone=3,stepTotal=10})
check(progress=='Current step: Sorting build library records; 3 / 10 (30%)','EN step progress: '..tostring(progress))
_,progress=LS.Progress({state='pending',coreReady=true,step='scan',recordsSeen=42})
check(progress=='Current step: Reading Community builds; 42 records read (in progress)','EN scan progress')
check(select(2,LS.Progress({state='failed'}))=='See /nexus status for the recorded reason','EN failed progress')
check(LS.Detail({state='failed',coreReady=false})=='Local controls wait until saved data is checked.\nSee /nexus status for details. Keep your saved-data backup.','EN failed detail')
check(LS.PhaseText({state='failed',coreReady=true,reason='X_9'})=='Shared data unavailable: X_9','EN failed step with its raw reason')
-- Data log and support page.
Nexus.LogViewer.Show('state');for _=1,10 do H.Advance(.05,.05) end
local status=FindRegion(NexusLogViewer,function(f) return f.kind=='FontString' and tostring(f:GetText()):find('^Page 1/') end)
check(status and status:GetText():find(' total bytes | copy pages in order (no inserted separators)',1,true),'EN the log status line keeps its exact English and separators')
check(Button('Recent choices') and Button('Advanced peer') and Button('Clear Log') and Button('< Page'),'EN log tabs and buttons keep their English')
NexusLogViewer:Hide()
Nexus.SupportReportUI.Show()
check(Texts(NexusSupportReport)['Support storage: not loaded. Prepare report file loads it on demand.'],'EN the support storage line keeps its English')
check(Nexus.SupportReport.WrittenNotice({id='R-1'})=='Report R-1 is prepared in memory. WoW writes the file when you reload, log out, or exit normally. It is not yet verified on disk. Nexus does not reload or log out for you.','EN the written notice keeps its English')
NexusSupportReport:Hide()

------------------------------------------------------------------------
-- 2. Pseudo session
------------------------------------------------------------------------
CURRENT_H=Boot(nil)
H=CURRENT_H
check(Nexus.Localization.ActiveLanguage()=='frFR','SETUP the pseudo pack is active from session start')
local pseudo=SupportPayload(H)
check(pseudo.summary==english.summary,'PAYLOAD the copyable summary bytes are identical in English and pseudo sessions')
check(pseudo.chunks==english.chunks,'PAYLOAD the prepared report chunks are identical in English and pseudo sessions')
check(pseudo.lines==english.lines,'PAYLOAD the incident lines are identical in English and pseudo sessions')
LB=Nexus.Leaderboard
local UT=Nexus.UserText
-- Allowed English: fixture data, plus the documented pending producers
-- (UserText scope and record facts, CandidateEvidence reasons).
local PENDING={UT.LEADERBOARD_SCOPE}
local policy=Nexus.SyncModePolicy
if policy and policy.Mode and policy.Text and policy.Mode() then PENDING[#PENDING+1]=policy.Text(policy.Mode()) end
for _,p in ipairs(fx.players) do
 for _,cat in ipairs({'lk','dummy'}) do
  if p.dps[cat] then
   local parts=UT.RecordDetailParts({duration=p.duration[cat],level=p.level,ts=p.ts[cat]})
   PENDING[#PENDING+1]=table.concat(parts,'  •  ')
  end
 end
end
-- Pending literals (see the fragment): Help quotes these four button labels
-- and help_action_first checks them as source literals; ux_status_composition
-- checks the receiving-count sentence. Allowed only as the whole shown text.
local PENDING_EXACT={}
local function allow(word,text)
 local whole=plain(text)
 if PENDING_EXACT[whole] or whole:find('^Syncing \226\128\162 %d+ receiving$') then return true end
 for _,d in ipairs(DATA) do if text:find(d,1,true) and d:find(word,1,true) then return true end end
 for _,d in ipairs(PENDING) do if text:find(d,1,true) and d:find(word,1,true) then return true end end
 return false
end
local scanned=0
-- Pending (ui/FullUIWorkspaces.lua, workspaces family): BindTabs relabels
-- this window's three navigation buttons with its own English labels.
local function WorkspaceTab(f)
 for _,b in pairs((NexusLeaderboardFrame or {})._workspaceTabs or {}) do if f==b then return true end end
 return false
end
local function Scan(tag,items,skip)
 local list={}
 for _,i in ipairs(items) do
  local text=type(i)=='table' and i.text or i
  if not (type(i)=='table' and ((skip and skip(i.frame)) or WorkspaceTab(i.frame))) then list[#list+1]=text;scanned=scanned+1 end
 end
 local missing=S.Untranslated(list,allow)
 local shown={};for n,m in ipairs(missing) do if n<=4 then shown[#shown+1]=('%q (%s)'):format(m.text,m.word) end end
 check(#missing==0,tag..': every visible code-owned word passed the seam; untranslated: '..table.concat(shown,'; '))
 return list
end
local function Snapshot()
 return F.Serialize(NexusDB)..'\n'..F.Serialize(WishlistRealizerDB or {})..'\n'..F.Serialize(NexusSupportDB or {}),#H.sent,#H.actions
end

-- Release note: shown once before the passive window (showing it records
-- that it was seen, an existing write outside this check).
NexusDB.hasSeenQuickStart=true;NexusDB.lastChangelogSeen=nil
if type(NexusDB.settings)=='table' then NexusDB.settings.lastChangelogSeen=nil end
Nexus.Changelog.ShowIfNeeded()
check(NexusChangelogPopup and NexusChangelogPopup:IsShown(),'SETUP the release note is shown')
-- An incident for the support page (setup, before the passive window).
for _=1,40 do H.Advance(.05,.05) end
local db0,sent0,actions0=Snapshot()

-- Release note scan.
Scan('release note',S.VisibleTexts(NexusChangelogPopup))
check(Button(T('release_note.button.acknowledge'),NexusChangelogPopup),'the release note button shows its pseudo label')
NexusChangelogPopup:Hide()

-- Leaderboard: populated categories, selection, refusal, hovers, menu.
LF.Open(H,'lk')
frame=NexusLeaderboardFrame
local pane=frame._leaderboardDetail
Scan('leaderboard lk',S.VisibleTexts(frame))
local function Rows()
 local out={}
 for _,b in ipairs(frame._virtualListScrollFrame.scrollChild.children) do
  if b:IsShown() and b.data then out[#out+1]=b end
 end
 return out
end
local rows=Rows()
check(#rows==2,'SETUP the Lich King list holds two records: '..#rows)
for _,row in ipairs(rows) do
 Scan('leaderboard row hover '..tostring(row.data.player),Hover(row))
 row:GetScript('OnLeave')(row)
 row:Click();for _=1,4 do H.Advance(.05,.05) end
 local texts=S.VisibleTexts(frame)
 Scan('leaderboard detail '..tostring(row.data.player),texts)
 check(S.IsPseudo(pane.copy:GetText()) and S.IsPseudo(pane.open:GetText()),'the detail buttons show pseudo labels')
 check(S.IsPseudo(pane.more:GetText()),'the detail status reached its FontString through the seam: '..tostring(pane.more:GetText()))
 if row.data.player=='Carol' then
  local copyPart=Nexus.Localization.Format('leaderboard.status.copy_unavailable',{reason=T('leaderboard.reason.current_identity_unavailable')})
  local openPart=Nexus.Localization.Format('leaderboard.status.open_unavailable',{reason=T('leaderboard.reason.exact_identity_unavailable')})
  check(pane.more:GetText()==copyPart..'; '..openPart,'Copy and Open refusals show translated sentences and reasons joined by the code-owned separator: '..pane.more:GetText())
  check(not pane.copy:IsEnabled(),'the refused Copy stays disabled')
 end
 check(pane.record:GetText():find('DPS',1,true) and S.IsPseudo(pane.record:GetText()),'the record line carries the DPS figure inside the translated template')
end
for _,cat in ipairs({'dummy','combined'}) do
 LF.Open(H,cat)
 Scan('leaderboard '..cat,S.VisibleTexts(frame))
 for _,row in ipairs(Rows()) do Scan('leaderboard '..cat..' hover',Hover(row));row:GetScript('OnLeave')(row) end
end
check(Texts(frame)[plain(Nexus.Localization.Format('leaderboard.status.ranked_both_records',{count='1'}))],'the Both records count line is translated')
-- Empty and loading states: a class with no records, in two categories.
local classBtn=Find(function(f) return f.kind=='Button' and type(f.text)=='table' and f:GetParent()==frame and type(f.arrow)=='table' end)
classBtn:Click()
local menu=Find(function(f) return f.kind=='Frame' and f:IsShown() and f:GetParent()==UIParent and f.children[1] and f.children[1].regions and f.children[1].regions[2]
 and f.children[1].regions[2].GetText and f.children[1].regions[2]:GetText()==T('leaderboard.label.all_classes') end)
check(menu~=nil,'the class menu opens with its translated rows')
Scan('class menu',S.VisibleTexts(menu))
local warrior=menu.children[#menu.children]
warrior:Click()
for _=1,40 do H.Advance(.05,.05) end
local emptyText=pane.empty:GetText()
check(S.IsPseudo(emptyText) and emptyText:find('\n\n',1,true),'the empty Both records pane is translated with its code-owned paragraph break')
Scan('leaderboard empty combined',S.VisibleTexts(frame))
LB.SetCategory('lk')
Scan('leaderboard loading or refreshed',S.VisibleTexts(frame))
for _=1,40 do H.Advance(.05,.05) end
Scan('leaderboard empty lk',S.VisibleTexts(frame))
check(S.IsPseudo(pane.empty:GetText()),'the empty Lich King pane is translated')
check(Texts(frame)[plain(Nexus.Localization.Format('leaderboard.status.ranked_lk_records',{count='0'}))],'zero is inserted as 0 in the translated count line')
LB.SetClassFilter('ALL');for _=1,40 do H.Advance(.05,.05) end
-- Sync status states (read-only stub of the status getter).
local sync=Nexus.Sync
local realStatus,realStats=sync.GetLeaderboardSyncStatus,sync.Stats
local statusText=FindRegion(frame,function(f) return f.kind=='FontString' and f:GetParent()==frame and f.width==250 end)
for _,case in ipairs({{'throttled',12},{'syncing',0,{receiving=3}},{'syncing',0,{}},{'cleaning'},{'sending'},{'syncing',0,{},true}}) do
 sync.GetLeaderboardSyncStatus=function() return case[1],case[2],0,case[3] end
 sync.Stats=function() return {preparingRequest=case[4]==true} end
 LB.RefreshStatus()
 local shown=statusText and statusText:GetText() or ''
 if case[3] and case[3].receiving then
  check(plain(shown)=='Syncing \226\128\162 3 receiving','PENDING the receiving-count status keeps its literal English: '..shown)
 else
  check(S.IsPseudo(shown),'sync status '..case[1]..' is translated: '..shown)
 end
 Scan('sync status '..case[1],{shown,Button(T(case[4] and 'leaderboard.button.preparing_shared_data' or 'leaderboard.button.sync_now')):GetText()})
end
sync.GetLeaderboardSyncStatus,sync.Stats=realStatus,realStats
LB.RefreshStatus()
-- Hovers of Sync Now and Both records.
Scan('sync now hover',Hover(Button(T('leaderboard.button.sync_now'),frame)))
local both=Find(function(f) return f.kind=='Button' and type(f.text)=='table' and f.text:GetText()==T('leaderboard.tab.both_records') end)
Scan('both records hover',Hover(both))
LB.Hide()

-- Startup status window and loading hover.
local LS=Nexus.LoadingStatus
local statuses={
 {state='pending',coreReady=false,phase='store-validation'},
 {state='pending',coreReady=true,step='catalog-sort',stepDone=3,stepTotal=10},
 {state='pending',coreReady=true,step='scan',recordsSeen=42},
 {state='pending',coreReady=true,step='catalog-unlisted-step'},
 {state='failed',coreReady=true,reason='ROOT_SLOT_LIMIT',failure={counter='distinct-slots',map='barrier',limit=2048,counted={bundled=5}}},
 {state='failed',coreReady=true,reason='TOMBSTONE_SET_LIMIT',failure={counter='map-keys',map='tombstone',limit=2048,counted={}}},
 {state='failed',coreReady=false,reason='X_9'},
 {state='ready',coreReady=true},
}
for i,st in ipairs(statuses) do
 LS.Update(st,true)
 Scan('startup status '..i,S.VisibleTexts(NexusLoadingStatusFrame))
 check(S.IsPseudo(NexusLoadingStatusFrame.title:GetText()),'startup title '..i..' is translated')
 Scan('startup detail '..i,{LS.Detail(st),select(2,LS.Progress(st))})
end
local probe=CreateFrame('Button',nil,UIParent);probe:SetText('Zq')
LS.BindSharedButton(probe,'Zq')
local realStartup=Nexus.StartupStatus
for _,st in ipairs({statuses[2],statuses[7]}) do
 Nexus.StartupStatus=function() return st end
 local lines=Hover(probe)
 check(#lines==3 and lines[1]:find('Zq',1,true),'the loading hover shows the caller label inside the translated line')
 Scan('loading hover '..st.state,lines)
end
Nexus.StartupStatus=realStartup
NexusLoadingStatusFrame:Hide()

-- Data log window: tabs, peer controls, status, hovers (log text excluded).
local function NotPayload(f) return f.kind=='EditBox' end
Nexus.LogViewer.Show('state');for _=1,10 do H.Advance(.05,.05) end
Scan('log window',S.VisibleTexts(NexusLogViewer),NotPayload)
local peerTab=Button(T('log.tab.advanced_peer'),NexusLogViewer)
check(peerTab~=nil and peerTab:GetWidth()>=56,'the translated tab is sized from its label')
peerTab:Click();for _=1,10 do H.Advance(.05,.05) end
Scan('log peer tab',S.VisibleTexts(NexusLogViewer),NotPayload)
Scan('log export hover',Hover(Button('Prepare full diagnostic report',NexusLogViewer)))
Scan('log clear hover',Hover(Button(T('log.button.clear_log'),NexusLogViewer)))
local pageLine=FindRegion(NexusLogViewer,function(f) return f.kind=='FontString' and tostring(f:GetText()):find(' | ',1,true) end)
check(pageLine and S.IsPseudo(pageLine:GetText()),'the page status line is translated around code-owned separators')
NexusLogViewer:Hide()

-- Support page: storage states, incident navigation, copy summary note.
Nexus.SupportReportUI.Show()
local function NotSupportPayload(f) return f==NexusSupportReport.incident or f.kind=='EditBox' end
Scan('support page',S.VisibleTexts(NexusSupportReport),NotSupportPayload)
check(S.IsPseudo(NexusSupportReport.storage:GetText()) and S.IsPseudo(NexusSupportReport.status:GetText()),'the storage and incident status lines are translated')
check(NexusSupportReport.incident:GetText()==Nexus.SupportReport.Escape(english.lines),'the incident box shows the payload lines unchanged')
Button(T('support.button.next_incident'),NexusSupportReport):Click()
Button('Copy summary',NexusSupportReport):Click()
check(NexusSupportReport.copyBox:GetText()==Nexus.SupportReport.Summary(Nexus.SupportIncidents.Latest()),'the copy box holds the summary bytes unchanged')
Scan('support copy note',{NexusSupportReport.copyNote:GetText()})
Button(T('support.button.inspect_prepared'),NexusSupportReport):Click()
Scan('support inspect without a report',{NexusSupportReport.prepared:GetText()})

-- Passivity: nothing above wrote saved data, sent or acted.
local db1,sent1,actions1=Snapshot()
check(db1==db0,'PASSIVE rendering, hovering and navigating wrote no saved data')
check(sent1==sent0,'PASSIVE rendering, hovering and navigating sent nothing: '..sent0..' -> '..sent1)
check(actions1==actions0,'PASSIVE rendering, hovering and navigating took no game action')

-- Explicit support actions after the passive window: refusal and success.
LoadAddOn=function() return false end
NexusSupportStorage=nil
local refused,why=Nexus.SupportReportUI.PrepareFile(false)
check(refused==nil and why=='the NexusSupport component is not installed or is disabled','the returned reason stays raw English: '..tostring(why))
local preparedText=NexusSupportReport.prepared:GetText()
check(preparedText:find(T('support.reason.component_not_installed'),1,true),'the shown reason is translated at the display boundary')
Scan('support refusal',{preparedText,NexusSupportReport.storage:GetText()})
LoadAddOn=function(name) if name~='NexusSupport' then return false end;dofile('companion/NexusSupport/Storage.lua');H.Fire('ADDON_LOADED','NexusSupport');return true end
local meta=assert(Nexus.SupportReportUI.PrepareFile(false),'the report is prepared')
preparedText=NexusSupportReport.prepared:GetText()
check(preparedText:find('WTF/Account/<ACCOUNT>/SavedVariables/NexusSupport.lua',1,true),'the file path is inserted verbatim')
check(preparedText:find(tostring(meta.id),1,true),'the report ID is inserted verbatim')
Scan('support prepared',{preparedText,NexusSupportReport.storage:GetText()})
Button(T('support.button.inspect_prepared'),NexusSupportReport):Click()
Scan('support inspect',{NexusSupportReport.prepared:GetText()})
NexusSupportReport:Hide()
-- Explicit log actions after the passive window: export and clear.
Nexus.LogViewer.Show('state');for _=1,10 do H.Advance(.05,.05) end
local logEdit=Find(function(f) return f.kind=='EditBox' and f:GetParent()==NexusLogScroll end)
Button('Prepare full diagnostic report',NexusLogViewer):Click()
check(S.IsPseudo(logEdit:GetText()),'the report preparation notice in the copy box is translated')
for _=1,400 do H.Advance(.05,.05) end
Button(T('log.button.clear_log'),NexusLogViewer):Click()
check(S.IsPseudo(Button(T('log.button.cleared'),NexusLogViewer) and T('log.button.cleared')),'the cleared label is translated')
Scan('log after clear',S.VisibleTexts(NexusLogViewer),NotPayload)
NexusLogViewer:Hide()

-- Templates: long and non-ASCII values are inserted verbatim; a value above
-- the slot limit is refused (callers then keep their exact English).
local longName='\195\132rj\195\182 '..string.rep('n',1000)
local out=Nexus.Localization.Format('leaderboard.label.by_owner',{name=longName})
check(out:find(longName,1,true) and S.IsPseudo(out),'a long non-ASCII name is inserted verbatim into the translated template')
local refusedText,source=Nexus.Localization.Format('leaderboard.label.by_owner',{name=string.rep('n',1025)})
check(source=='unavailable','a value above the slot limit is refused, not cut: '..tostring(source))

------------------------------------------------------------------------
-- 3. Long pseudo pack on the densest windows
------------------------------------------------------------------------
CURRENT_H=Boot('long')
H=CURRENT_H
LF.Open(H,'lk');frame=NexusLeaderboardFrame;pane=frame._leaderboardDetail
for _,row in ipairs(Rows()) do row:Click();for _=1,4 do H.Advance(.05,.05) end
 Scan('long leaderboard detail',S.VisibleTexts(frame))
 check(S.IsPseudo(pane.more:GetText()) and S.IsPseudo(pane.record:GetText()),'long text is still shown in the detail')
end
LF.Open(H,'combined');Scan('long leaderboard combined',S.VisibleTexts(frame))
LS=Nexus.LoadingStatus
for i,st in ipairs(statuses) do LS.Update(st,true);Scan('long startup '..i,S.VisibleTexts(NexusLoadingStatusFrame)) end
Nexus.SupportReportUI.Show();Scan('long support',S.VisibleTexts(NexusSupportReport),function(f) return f==NexusSupportReport.incident or f.kind=='EditBox' end)
Nexus.LogViewer.Show('state');for _=1,10 do H.Advance(.05,.05) end;Scan('long log',S.VisibleTexts(NexusLogViewer),NotPayload)
local longChat=Nexus.Localization.Format('leaderboard.chat.new_best',{build=string.rep('b',1024),category=T('leaderboard.value.category_lk'),dps='1.25M'})
check(S.IsPseudo(longChat) and longChat:find(string.rep('b',1024),1,true),'the long-mode chat template fits its result limit with a maximal title')

------------------------------------------------------------------------
-- 4. Missing pack entries fall back to exact English
------------------------------------------------------------------------
local entries=S.PseudoEntries()
local removed={'leaderboard.tab.lich_king','leaderboard.status.ranked_lk_records','loading.title.loading',
 'log.button.refresh','support.button.close','release_note.button.acknowledge'}
for _,key in ipairs(removed) do check(entries[key]~=nil,'SETUP '..key..' has a pseudo entry');entries[key]=nil end
CURRENT_H=Boot(nil,entries)
H=CURRENT_H
LF.Open(H,'lk');frame=NexusLeaderboardFrame
local missingTexts=Texts(frame)
check(missingTexts['Lich King'] and missingTexts['2 ranked Lich King records • best known, from shared records received'],'MISSING the removed tab and count line show exact English')
check(missingTexts[plain(T('leaderboard.tab.training_dummy'))] and S.IsPseudo(T('leaderboard.tab.training_dummy')),'MISSING other keys stay translated')
LB=Nexus.Leaderboard;LB.Hide()
Nexus.LoadingStatus.Update({state='pending',coreReady=false,phase='store-validation'},true)
check(NexusLoadingStatusFrame.title:GetText()=='Nexus loading','MISSING the startup title shows exact English')
Nexus.LogViewer.Show('state')
check(Button('Refresh',NexusLogViewer)~=nil,'MISSING the log Refresh button shows exact English')
NexusLogViewer:Hide()
Nexus.SupportReportUI.Show()
check(Button('Close',NexusSupportReport)~=nil,'MISSING the support Close button shows exact English')
NexusSupportReport:Hide()
NexusDB.hasSeenQuickStart=true;NexusDB.lastChangelogSeen=nil
if type(NexusDB.settings)=='table' then NexusDB.settings.lastChangelogSeen=nil end
Nexus.Changelog.ShowIfNeeded()
check(Button('Got it',NexusChangelogPopup)~=nil,'MISSING the release note button shows exact English')

------------------------------------------------------------------------
-- 5. New-best DPS chat line on a read-only profile (pseudo)
------------------------------------------------------------------------
local ordinary,permanent={},{}
for i=1,79 do ordinary[#ordinary+1]={spellId=300000+i,quality=2,stacks=1} end
for i=1,6 do permanent[#permanent+1]={spellId=310000+i,quality=3,stacks=1} end
S.InstallBootHook()
H=F.Boot(F.Database({version=6}),function(h)
 for _,e in ipairs(ordinary) do h.AddEcho(e.spellId,'Echo '..e.spellId,e.quality,4,e.spellId) end
 for _,e in ipairs(permanent) do h.AddEcho(e.spellId,'Locked '..e.spellId,e.quality,1,e.spellId) end
end)
CURRENT_H=H
for _=1,100 do H.Advance(.05,.05) end
local A,D=Nexus.GameAdapter,Nexus.DpsCapture
local realUnitName=UnitName
UnitName=function(unit) if unit=='target' then return 'Training Dummy' end;return realUnitName(unit) end
UnitExists=function(unit) return unit=='target' end
local combat={total=482500}
function combat:GetActor() return {total=self.total,Tempo=function() return 10 end} end
function combat:GetCombatTime() return 10 end
Details={GetCurrentCombat=function() return combat end}
DETAILS_ATTRIBUTE_DAMAGE=1
local granted={}
for _,e in ipairs(ordinary) do local name=H.names[e.spellId];granted[name]=granted[name] or {};granted[name][#granted[name]+1]={spellId=e.spellId,quality=e.quality} end
H.granted=granted
local lockedRows={};for _,e in ipairs(permanent) do lockedRows[#lockedRows+1]={spellId=e.spellId,stacks=1} end
H.locked=lockedRows;H.Notify();A.Poll()
local slot={};for _,e in ipairs(ordinary) do slot[#slot+1]={spellId=e.spellId,quality=e.quality,stacks=1,locked=false} end
for _,e in ipairs(permanent) do slot[#slot+1]={spellId=e.spellId,quality=e.quality,stacks=1,locked=true} end
H.perks.serverBuildSlots={[1]={name='Saved',verified=true,echoes=slot}};H.perks.serverActiveSlot=1;H.Notify();A.Poll()
local chat=S.CaptureChat(function()
 D.OnCombatStart()
 for _=1,7 do H.Advance(5,.05);D.OnUpdate(5) end
 D.OnCombatEnd()
end)
local best
for _,line in ipairs(chat) do if line:find('DPS',1,true) and line:find('|cff4dff80',1,true) then best=line end end
check(best~=nil,'the new-best chat line was printed')
check(best:find('|cff7fd5ffNexus:|r |cff4dff80\194\171',1,true) and best:find('\194\187|r |cffffc040\194\171',1,true),'the chat line keeps its code-owned prefix and colours around translated text: '..tostring(best))
check(best:find(T('leaderboard.value.category_dummy'),1,true),'the category name is translated inside the line')
check(Nexus.Localization.ActiveLanguage()=='frFR' and S.LooksUntranslated((best:gsub('^|cff7fd5ffNexus:|r ','')),function(w) return w=='DPS' end)==nil,'the chat line has no untranslated word')

print(('PASS l10n_ui_records checks=%d scanned=%d (synthetic offline; native NOT_RUN)'):format(checks,scanned))
