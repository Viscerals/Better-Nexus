local H=dofile('tests/prototype/harness.lua');H.Boot()
local L,V=Nexus.DiagnosticLogs,Nexus.LogViewer
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
assert(L.Clear('decision'))
for i=1,20 do assert(L.Append('decision',{id=i,message=string.rep('detail',100),nested={value=i}})) end
local snapshot,yields
local co=coroutine.create(function()snapshot=L.SnapshotCooperative('decision',function(message)coroutine.yield(message)end)end)
yields=0
while coroutine.status(co)~='dead' do
 local ok,why=coroutine.resume(co);check(ok,'snapshot coroutine '..tostring(why))
 if coroutine.status(co)~='dead'then
  yields=yields+1
  if yields==1 then
   assert(L.UpdateLast('decision',function(r)r.nested.value=999 end))
   assert(L.Append('decision',{id=21,nested={value=21}}))
  end
 end
end
check(yields==10,'defensive copying yields every two records')
check(#snapshot==20 and snapshot[20].nested.value==20,'snapshot stable across concurrent replacement/append')
snapshot[1].nested.value=-1
check(L.Snapshot('decision')[1].nested.value==1,'export copy cannot mutate history')
local raw=string.rep('a',15998)..'é🙂'..string.rep('line|x\n',16000)..'END'
V.Init(function()return raw end);V.Show('state');H.Advance(.15)
local edit=NexusLogScroll.scrollChild
check(edit~=nil,'real viewer edit box')
local info=V.PageInfo();check(info.bytes==#raw and info.pages>1,'full export retained, visible pages')
local chunks={}
for i=1,info.pages do
 check(V.SetPage(i),'page select')
 local text=edit:GetText();check(#text<=32000,'bounded escaped rendering')
 -- DisplaySafeText only escapes pipes; there are no other control bytes here.
 chunks[#chunks+1]=text:gsub('||','|')
end
check(table.concat(chunks)==raw,'all original bytes recovered including UTF-8 page boundary')
check(not V.SetPage(0) and not V.SetPage(info.pages+1),'invalid pages blocked')
-- Actual export begins by yielding before history/page materialization.
local export=Nexus.NewAIExportCoroutine();check(type(export)=='thread','real export factory')
local ok,phase=coroutine.resume(export);check(ok and coroutine.status(export)=='suspended','first export slice yields')
local turns=0;local result
while coroutine.status(export)~='dead' and turns<5000 do
 ok,result=coroutine.resume(export);assert(ok,result);turns=turns+1
end
check(coroutine.status(export)=='dead' and type(result)=='string' and #result>0,'full export completes without truncation')
check(turns>1,'real export is cooperative')
do
-- Real public report consumer retains known import reasons and sanitizes unknown text.
local F=dofile('tests/prototype/format5_support.lua')
local db=F.Database()
db.buildFilters={scope='mine'}
local priorLogScroll=NexusLogScroll
local H=F.Boot(db,function(h)
 h.perks.serverBuildSlots={[1]={name='Synthetic diagnostic slot',verified=true,
  echoes={{spellId=200001,quality=1,stacks=1,locked=false}}}}
 h.perks.serverActiveSlot=1
end)
check(Nexus.StartupStatus().state=='ready','setup: real TOC startup ready')
check(type(SlashCmdList.NEXUS)=='function' and type(Nexus.GetDiagnosticPageText)=='function',
 'setup: registered slash handler and public diagnostic page route exist')
local CB=Nexus.CommunityBuilds
local slots=Nexus.GameAdapter.Slots
local attempts=0
Nexus.GameAdapter.Slots=function(...)
 local caller=debug.getinfo(2,'S')
 if caller and caller.source=='@core/CommunityController.lua' then
  attempts=attempts+1;error('Synthetic personal import diagnostic fault',0)
 end
 return slots(...)
end
local shown,why=pcall(CB.Show)
Nexus.GameAdapter.Slots=slots
check(shown,'setup: actual Show contains the personal import exception: '..tostring(why))
local snapshot=CB.DiagnosticSnapshot()
check(attempts==1 and snapshot.filterScope=='mine' and snapshot.savedImportError==true
 and snapshot.blockedReason=='saved-import-error',
 'setup: actual Mine import fault owns the new renderer reason: '..tostring(snapshot.blockedReason))
local function FindCommunityLine(text)
 local header=false
 for line in (text..'\n'):gmatch('([^\n]*)\n')do
  if line:match('^community catalog=')then header=true
  elseif header and line:match('^%S')then break
  elseif header and line:match('^  projection=')then return line,header end
 end
 return nil,header
end
local function CommunityLine(text)
 local line,header=FindCommunityLine(text)
 check(header,'community diagnostic block missing')
 check(line,'community projection line missing');return line
end
local C=dofile('tests/prototype/view_regression_support.lua').Checker('diagnostic fault bits')
local function WorkFingerprint()
 local d=CB.DiagnosticSnapshot();local s=CB.VirtualStats();local w=Nexus.ViewProjections.WorkStats()
 return table.concat({tostring(d.blockedReason),tostring(d.savedImportPending),
  tostring(d.savedImportError),s.importFailures,s.dataFailures,w.communityPumps,
  w.publications,#H.actions,#H.sent,Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)},'|')
end
local before=WorkFingerprint()
local line=CommunityLine(Nexus.GetDiagnosticPageText('state'))
check(WorkFingerprint()==before,'guard: report read leaves measured Library work, publication, revision and retained fault unchanged')
local exported=line:match(' blocked=(%S+)')
print('OBSERVED actual_import_attempts='..attempts..' renderer_reason='..snapshot.blockedReason
 ..' exported_reason='..tostring(exported))
print('PUBLIC_PROVIDER '..line)
-- Negative controls keep the fixed allowlist: no arbitrary reason/error payload.
local originalSnapshot=CB.DiagnosticSnapshot
for _,token in ipairs({'unknown-synthetic-token','synthetic\ncontrol|payload'})do
 CB.DiagnosticSnapshot=function()
  local d=originalSnapshot();d.blockedReason=token;return d
 end
 local text=Nexus.GetDiagnosticPageText('state')
 check(CommunityLine(text):match(' blocked=unavailable$'), 'guard: unknown token remains unavailable')
 check(not text:find(token,1,true),'guard: arbitrary reason text does not escape sanitizer')
end
CB.DiagnosticSnapshot=originalSnapshot
-- The registered command is /nexus log.
-- Opening the normal viewer closes Library; its state must truthfully be hidden.
SlashCmdList.NEXUS('log')
H.Advance(.15,.01)
check(NexusLogScroll and NexusLogScroll.scrollChild,'real diagnostic viewer edit box exists')
local fresh=false
for _,frame in ipairs(H.frames)do if frame==NexusLogScroll then fresh=true end end
check(fresh and NexusLogScroll~=priorLogScroll,'guard: slash viewer frame belongs to current harness, not stale globals')
local function ViewerText()
 local belongs=false
 for _,frame in ipairs(H.frames)do if frame==NexusLogScroll then belongs=true end end
 check(belongs,'guard: rendered viewer belongs to the current harness')
 local pages={}
 for page=1,Nexus.LogViewer.PageInfo().pages do
  check(Nexus.LogViewer.SetPage(page),'guard: actual viewer page is selectable')
  pages[#pages+1]=NexusLogScroll.scrollChild:GetText():gsub('||','|')
 end
 return table.concat(pages)
end
local rendered=ViewerText()
local renderedLine=CommunityLine(rendered)
check(renderedLine:match(' blocked=hidden$') and CB.DiagnosticSnapshot().blockedReason=='hidden',
 'guard: normal viewer closes Library and retains truthful hidden reason')
print('REGISTERED_SLASH_VIEWER '..renderedLine)
check(#H.actions==0 and #H.sent==0,'guard: synthetic observation sends no gameplay/network action')
check(exported==snapshot.blockedReason,
 'EXPECT public diagnostics preserves recognized saved-import-error; actual='..tostring(exported))

-- Orthogonal fault evidence survives reason precedence without exposing payloads.
C.setup(snapshot.savedImportPending==false,'Begin failure occurs before any actual import job')
C.expect(line:find('import=pending:false phase:idle error:true status_error:false',1,true),
 'direct pre-job diagnostic preserves import fault separately from pending and status')
C.expect(renderedLine:find('import=pending:false phase:idle error:true status_error:false',1,true),
 'registered hidden viewer retains import fault independently of hidden reason')
C.guard(not rendered:find('Synthetic personal import diagnostic fault',1,true),
 'consumer never includes raw import exception payload')
C.guard(FindCommunityLine('community catalog=0\n  filters scope=mine\nleaderboard catalog=1\n  projection=wrong')==nil,
 'community parser cannot borrow the leaderboard projection line')
for _,values in ipairs({{true,true},{'truthy import',{private='status payload'}},{1,'true'},{false,false}})do
 CB.DiagnosticSnapshot=function()
  local d=originalSnapshot();d.savedImportError=values[1];d.shareStatusError=values[2];return d
 end
 local sanitized=CommunityLine(Nexus.GetDiagnosticPageText('state'))
 C.expect(sanitized:find(' error:'..tostring(values[1]==true)..' status_error:'..tostring(values[2]==true),1,true),
  'only literal true survives both fault-bit sanitizers')
 C.guard(not sanitized:find('truthy import',1,true) and not sanitized:find('status payload',1,true),
  'nonboolean fault inputs never become diagnostic payload')
end
CB.DiagnosticSnapshot=originalSnapshot
-- An actual All view masks import reason while preserving the retained error.
NexusDB.buildFilters.scope='all';CB.Show();CB.Refresh()
local all=CB.DiagnosticSnapshot()
C.setup(all.filterScope=='all' and all.savedImportError and not all.savedImportPending
 and all.blockedReason~='saved-import-error','real All state masks a held pre-job import fault')
C.expect(CommunityLine(Nexus.GetDiagnosticPageText('state')):find(' error:true status_error:false',1,true),
 'All report retains independent import fault despite another reason')
local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
local projectionMessage='Synthetic diagnostic projection setter fault'
label.SetText=function()error(projectionMessage,0)end
local refreshed,refreshError=pcall(CB.Refresh)
label.SetText=setter
local masked=CB.DiagnosticSnapshot()
C.setup(not refreshed and refreshError==projectionMessage and masked.blockedReason=='projection-error'
 and masked.savedImportError,'real renderer projection fault masks a simultaneously retained import fault')
local maskedLine=CommunityLine(Nexus.GetDiagnosticPageText('state'))
C.expect(maskedLine:find(' error:true status_error:false',1,true) and maskedLine:match(' blocked=projection%-error$'),
 'projection-error report still carries independent import fault')
local function Settle()
 for i=1,2000 do
  H.Advance(.01,.01)
  local d=CB.DiagnosticSnapshot()
  if d.projectionCurrent and not d.savedImportPending and not d.savedImportError then return i end
 end
end
C.guard(Settle()~=nil,'restored real dependencies complete import and publish healthy view')
local recovered=CB.DiagnosticSnapshot()
C.setup(recovered.savedImportError==false and recovered.shareStatusError==false,
 'actual producer clears both current fault observations after recovery')
C.expect(CommunityLine(Nexus.GetDiagnosticPageText('state')):find(' error:false status_error:false',1,true),
 'healthy recovered report has explicit false fault bits')
-- Real status setter failure, through the public popup and refresh routes.
CB.ShowPostBuild()
local statusLabel=NexusPostPopup._shareStatus;local statusSetter=statusLabel.SetText
statusLabel.SetText=function()error('Synthetic diagnostic status setter fault',0)end
CB.Refresh()
C.setup(CB.DiagnosticSnapshot().shareStatusError==true and CB.DiagnosticSnapshot().savedImportError==false,
 'actual Share setter fault has an independent status ledger')
C.expect(CommunityLine(Nexus.GetDiagnosticPageText('state')):find(' error:false status_error:true',1,true),
 'direct report preserves actual status failure separately from import')
SlashCmdList.NEXUS('log');H.Advance(.15,.01)
local hiddenStatus=CommunityLine(ViewerText())
print('REGISTERED_STATUS_VIEWER '..hiddenStatus)
C.setup(CB.DiagnosticSnapshot().blockedReason=='hidden' and CB.DiagnosticSnapshot().shareStatusError,
 'normal viewer hides Library without recovering failed Share setter')
C.expect(hiddenStatus:find(' error:false status_error:true',1,true) and hiddenStatus:match(' blocked=hidden$'),
 'hidden report preserves active status fault even when visibility masks reason')
statusLabel.SetText=statusSetter;CB.Refresh()
C.setup(CB.DiagnosticSnapshot().shareStatusError==false,'successful actual status write proves recovery')
C.expect(CommunityLine(Nexus.GetDiagnosticPageText('state')):find(' error:false status_error:false',1,true),
 'successful status recovery clears printed status bit')
C.guard(#H.actions==0 and #H.sent==0,'extended diagnostic observation sends no gameplay/network action')
-- Genuine pending-job fault: Begin succeeds, receive defers it, then cleanup fails.
local pendingDB=F.Database();pendingDB.buildFilters={scope='mine'}
H=F.Boot(pendingDB,function(h)h.perks.serverBuildSlots={}end)
CB=Nexus.CommunityBuilds
local receiving=true;Nexus.Sync.IsReceiving=function()return receiving end
local factory=Nexus.BuildCatalog.BeginSavedMirrorCursor;local faultCalls=0
Nexus.BuildCatalog.BeginSavedMirrorCursor=function()
 faultCalls=faultCalls+1;error('Synthetic pending import cleanup fault',0)
end
CB.Show()
C.setup(CB.DiagnosticSnapshot().savedImportPending==true and faultCalls==0,
 'real Begin creates a genuine receive-deferred job before factory execution')
receiving=false
for i=1,200 do if faultCalls>0 then break end;H.Advance(.01,.01)end
local pendingDiag=CB.DiagnosticSnapshot()
C.setup(faultCalls==1 and pendingDiag.savedImportPending and pendingDiag.savedImportError,
 'real import pump fault retains its existing unfinished job')
local pendingLine=CommunityLine(Nexus.GetDiagnosticPageText('state'))
C.expect(pendingLine:find('import=pending:true ',1,true) and pendingLine:find(' error:true status_error:false',1,true),
 'actual pending-job failure prints pending true and error true together')
SlashCmdList.NEXUS('log');H.Advance(.15,.01)
local hiddenPending=CommunityLine(ViewerText())
print('REGISTERED_PENDING_VIEWER '..hiddenPending)
C.expect(hiddenPending:find('import=pending:true ',1,true) and hiddenPending:find(' error:true status_error:false',1,true)
 and hiddenPending:match(' blocked=hidden$'),'registered hidden pending job retains truthful job and fault evidence')
Nexus.BuildCatalog.BeginSavedMirrorCursor=factory;CB.Show()
C.guard(Settle()~=nil,'restored factory completes the original real pending import')
C.expect(CommunityLine(Nexus.GetDiagnosticPageText('state')):find(' error:false status_error:false',1,true),
 'completed pending import clears current diagnostic fault bit')
C.guard(#H.actions==0 and #H.sent==0,'pending fault and recovery send no gameplay/network action')
C.finish('(synthetic diagnostic consumer only)')
checks=checks+C.n.expect+C.n.guard+C.n.setup
print('PASS controls: measured Library work unchanged; sanitized fault booleans; registered viewer; actions='..#H.actions..' sends='..#H.sent)
print('PASS public saved-import-error diagnostic compatibility')
end
print('PASS diagnostic snapshot/paging/export checks='..checks..'; export turns='..turns..'; bytes='..#result)
