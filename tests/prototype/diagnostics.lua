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

-- Bound parsing to one view owner; new fault groups are independent of reason.
local function OwnerLine(text,owner,prefix)
 local within=false
 for line in (text..'\n'):gmatch('([^\n]*)\n')do
  if line:find(owner..' catalog=',1,true)==1 then within=true
  elseif within and line:match('^%S')then break
  elseif within and line:find(prefix,1,true)==1 then return line end
 end
end
local function FaultBits(text,importError,statusError)
 local line=OwnerLine(text,'community','  faults ')
 if line then
  return line:find(' saved_import=error:'..tostring(importError)..' share_status=error:'..tostring(statusError),1,true)~=nil
 end
 -- Matched RED keeps the preceding two-bit report representation. The new
 -- view tests separately require the new owner groups; no source is fabricated.
 line=OwnerLine(text,'community','  projection=')
 return line and line:find(' error:'..tostring(importError)..' status_error:'..tostring(statusError),1,true)~=nil
end
local ViewChecks=dofile('tests/prototype/view_regression_support.lua').Checker('diagnostic view fault')

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
local publicText=Nexus.GetDiagnosticPageText('state')
local line=CommunityLine(publicText)
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
C.expect(line:find('import=pending:false phase:idle ',1,true) and FaultBits(publicText,true,false),
 'direct pre-job diagnostic preserves import fault separately from pending and status')
C.expect(renderedLine:find('import=pending:false phase:idle ',1,true) and FaultBits(rendered,true,false),
 'registered hidden viewer retains import fault independently of hidden reason')
C.guard(not rendered:find('Synthetic personal import diagnostic fault',1,true),
 'consumer never includes raw import exception payload')
C.guard(FindCommunityLine('community catalog=0\n  filters scope=mine\nleaderboard catalog=1\n  projection=wrong')==nil,
 'community parser cannot borrow the leaderboard projection line')
for _,values in ipairs({{true,true},{'truthy import',{private='status payload'}},{1,'true'},{false,false}})do
 CB.DiagnosticSnapshot=function()
  local d=originalSnapshot();d.savedImportError=values[1];d.shareStatusError=values[2];return d
 end
 local sanitizedText=Nexus.GetDiagnosticPageText('state')
 local sanitized=CommunityLine(sanitizedText)
 C.expect(FaultBits(sanitizedText,values[1]==true,values[2]==true),
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
C.expect(FaultBits(Nexus.GetDiagnosticPageText('state'),true,false),
 'All report retains independent import fault despite another reason')
local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
local projectionMessage='Synthetic diagnostic projection setter fault'
label.SetText=function()error(projectionMessage,0)end
local refreshed,refreshError=pcall(CB.Refresh)
label.SetText=setter
local masked=CB.DiagnosticSnapshot()
C.setup(not refreshed and refreshError==projectionMessage and masked.blockedReason=='projection-error'
 and masked.savedImportError,'real renderer projection fault masks a simultaneously retained import fault')
local maskedText=Nexus.GetDiagnosticPageText('state')
local maskedLine=CommunityLine(maskedText)
C.expect(FaultBits(maskedText,true,false) and maskedLine:match(' blocked=projection%-error$'),
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
C.expect(FaultBits(Nexus.GetDiagnosticPageText('state'),false,false),
 'healthy recovered report has explicit false fault bits')
-- Real status setter failure, through the public popup and refresh routes.
CB.ShowPostBuild()
local statusLabel=NexusPostPopup._shareStatus;local statusSetter=statusLabel.SetText
statusLabel.SetText=function()error('Synthetic diagnostic status setter fault',0)end
CB.Refresh()
C.setup(CB.DiagnosticSnapshot().shareStatusError==true and CB.DiagnosticSnapshot().savedImportError==false,
 'actual Share setter fault has an independent status ledger')
C.expect(FaultBits(Nexus.GetDiagnosticPageText('state'),false,true),
 'direct report preserves actual status failure separately from import')
ViewChecks.scenario('explicit diagnostic Clear retains current status fault',function()
 local beforeDiag,beforeStats=CB.DiagnosticSnapshot(),CB.VirtualStats();local now=H.now
 SlashCmdList.NEXUS('logclear')
 local afterDiag,afterStats=CB.DiagnosticSnapshot(),CB.VirtualStats()
 ViewChecks.guard(afterDiag.savedImportError==beforeDiag.savedImportError
  and afterDiag.shareStatusError==beforeDiag.shareStatusError
  and afterDiag.projectionError==beforeDiag.projectionError
  and afterStats.lastStatusError==beforeStats.lastStatusError
  and afterStats.statusFailures==beforeStats.statusFailures and H.now==now,
  'explicit Clear changes history, not producer fault observations, counters or time')
end)
SlashCmdList.NEXUS('log');H.Advance(.15,.01)
local hiddenStatusText=ViewerText()
local hiddenStatus=CommunityLine(hiddenStatusText)
print('REGISTERED_STATUS_VIEWER '..hiddenStatus)
C.setup(CB.DiagnosticSnapshot().blockedReason=='hidden' and CB.DiagnosticSnapshot().shareStatusError,
 'normal viewer hides Library without recovering failed Share setter')
C.expect(FaultBits(hiddenStatusText,false,true) and hiddenStatus:match(' blocked=hidden$'),
 'hidden report preserves active status fault even when visibility masks reason')
statusLabel.SetText=statusSetter;CB.Refresh()
C.setup(CB.DiagnosticSnapshot().shareStatusError==false,'successful actual status write proves recovery')
C.expect(FaultBits(Nexus.GetDiagnosticPageText('state'),false,false),
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
local pendingText=Nexus.GetDiagnosticPageText('state')
local pendingLine=CommunityLine(pendingText)
C.expect(pendingLine:find('import=pending:true ',1,true) and FaultBits(pendingText,true,false),
 'actual pending-job failure prints pending true and error true together')
SlashCmdList.NEXUS('log');H.Advance(.15,.01)
local hiddenPendingText=ViewerText()
local hiddenPending=CommunityLine(hiddenPendingText)
print('REGISTERED_PENDING_VIEWER '..hiddenPending)
C.expect(hiddenPending:find('import=pending:true ',1,true) and FaultBits(hiddenPendingText,true,false)
 and hiddenPending:match(' blocked=hidden$'),'registered hidden pending job retains truthful job and fault evidence')
Nexus.BuildCatalog.BeginSavedMirrorCursor=factory;CB.Show()
C.guard(Settle()~=nil,'restored factory completes the original real pending import')
C.expect(FaultBits(Nexus.GetDiagnosticPageText('state'),false,false),
 'completed pending import clears current diagnostic fault bit')
C.guard(#H.actions==0 and #H.sent==0,'pending fault and recovery send no gameplay/network action')
C.finish('(synthetic diagnostic consumer only)')
checks=checks+C.n.expect+C.n.guard+C.n.setup
print('PASS controls: measured Library work unchanged; sanitized fault booleans; registered viewer; actions='..#H.actions..' sends='..#H.sent)
print('PASS public saved-import-error diagnostic compatibility')
end

-- Current owner fault state is not inferred from dirty, pending, or visibility.
do
local C=ViewChecks
local F=dofile('tests/prototype/format5_support.lua')
local function Boot()
 local db=F.Database();db.buildFilters={scope='all'}
 return F.Boot(db,function(h)h.perks.serverBuildSlots={}end)
end
local function Settled(H,owner)
 for i=1,2000 do
  H.Advance(.01,.01)
  local d=owner.DiagnosticSnapshot()
  if d.projectionCurrent and not d.savedImportPending then return i end
 end
end
local function ViewError(text,owner)
 local line=OwnerLine(text,owner,'  faults ')
 return line and line:match(' view=error:(%S+)')
end
local function SnapshotBlock(text)
 return text:match('PERSISTED VIEW DIAGNOSTICS[^\n]*\n(.-)\n\n') or ''
end
local function Viewer(H)
 if not C.setup(NexusLogViewer and NexusLogViewer:IsShown(),
  'registered slash viewer is shown before reading its fresh pages')then return end
 local belongs=false
 for _,frame in ipairs(H.frames)do if frame==NexusLogScroll then belongs=true end end
 if not C.setup(belongs,'registered viewer belongs to the current boot')then return end
 local pages={}
 for i=1,Nexus.LogViewer.PageInfo().pages do
  if not C.setup(Nexus.LogViewer.SetPage(i),'actual viewer page is selectable')then return end
  pages[#pages+1]=NexusLogScroll.scrollChild:GetText():gsub('||','|')
 end
 return table.concat(pages)
end
C.scenario('real Library view failure survives hidden viewer and recovers',function()
 local H=Boot();local CB=Nexus.CommunityBuilds;CB.Show()
 if not C.setup(Settled(H,CB)~=nil,'actual Library publication settles before fault')then return end
 CB.Hide();CB.MarkDataDirty()
 local dirty=CB.DiagnosticSnapshot()
 if not C.setup(dirty.projectionDirty and not dirty.projectionCurrent and dirty.blockedReason=='hidden',
  'ordinary hidden invalidation is dirty without any prior producer failure')then return end
 C.expect(dirty.projectionError==false and ViewError(Nexus.GetDiagnosticPageText('state'),'community')=='false',
  'healthy dirty Library is explicitly not an owned view fault')
 CB.Show()
 if not C.setup(Settled(H,CB)~=nil,'dirty Library publishes successfully before injected host failure')then return end
 local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
 local message='Synthetic retained Library diagnostic view fault'
 label.SetText=function()error(message,0)end
 local before=CB.VirtualStats();local ok,err=pcall(CB.Refresh)
 if not C.setup(not ok and err==message and CB.VirtualStats().lastDataError==message
  and CB.VirtualStats().dataFailures==before.dataFailures+1
  and CB.DiagnosticSnapshot().blockedReason=='projection-error',
  'real explicit Refresh retains actual host exception in its view ledger')then label.SetText=setter;return end
 C.expect(CB.DiagnosticSnapshot().projectionError==true,'actual Library retained view flag is exported by producer')
 local direct=Nexus.GetDiagnosticPageText('state')
 C.expect(ViewError(direct,'community')=='true','direct report exposes the actual retained Library view fault')
 C.expect(OwnerLine(direct,'community','  projection='):match('phase:%S+ receiving='),
  'existing projection-line phase/receiving adjacency remains intact')
 SlashCmdList.NEXUS('log');H.Advance(.15,.01)
 local hidden=Viewer(H)
 if not C.setup(hidden and CB.DiagnosticSnapshot().blockedReason=='hidden'
  and CB.VirtualStats().lastDataError==message,'registered viewer hides Library while actual view fault remains retained')then label.SetText=setter;return end
 C.expect(ViewError(hidden,'community')=='true','registered hidden Library viewer exposes retained view fault independently of hidden')
 C.guard(not SnapshotBlock(direct):find(message,1,true) and not SnapshotBlock(hidden):find(message,1,true),
  'sanitized snapshot blocks contain no raw retained view error payload')
 local fault=CB.DiagnosticSnapshot();local stats=CB.VirtualStats();local now=H.now
 SlashCmdList.NEXUS('logclear')
 local after=CB.DiagnosticSnapshot()
 C.guard(after.projectionError==fault.projectionError and after.savedImportError==fault.savedImportError
  and after.shareStatusError==fault.shareStatusError and CB.VirtualStats().lastDataError==stats.lastDataError
  and CB.VirtualStats().dataFailures==stats.dataFailures and H.now==now,
  'explicit public Clear does not recover current Library fault or advance time')
 label.SetText=setter;CB.Show()
 if not C.setup(Settled(H,CB)~=nil and CB.VirtualStats().lastDataError==nil,
  'restored host dependency produces a successful real publication')then return end
 C.expect(CB.DiagnosticSnapshot().projectionError==false and ViewError(Nexus.GetDiagnosticPageText('state'),'community')=='false',
  'successful Library publication clears current exported view fault')
 local faults=OwnerLine(Nexus.GetDiagnosticPageText('state'),'community','  faults ')
 C.expect(faults and faults:match('^  faults view=error:%S+ saved_import=error:false share_status=error:false$'),
  'Community fault groups keep independent owners with explicit labels')
 C.guard(#H.actions==0 and #H.sent==0,'view fault, Clear and recovery send no gameplay or transport action')
end)
C.scenario('Leaderboard owns its own current view flag',function()
 local H=Boot();local LB=Nexus.Leaderboard;LB.Show('lk')
 if not C.setup(Settled(H,LB)~=nil,'actual Leaderboard publication settles')then return end
 LB.Hide();LB.MarkDataDirty()
 local dirty=LB.DiagnosticSnapshot()
 if not C.setup(dirty.projectionDirty and dirty.blockedReason=='hidden','ordinary hidden Leaderboard invalidation is dirty')then return end
 C.expect(dirty.projectionError==false and ViewError(Nexus.GetDiagnosticPageText('state'),'leaderboard')=='false',
  'healthy dirty Leaderboard is explicitly not an owned view fault')
 LB.Show('lk')
 if not C.setup(Settled(H,LB)~=nil,'Leaderboard republishes before real dependency refusal')then return end
 local request=Nexus.ViewProjections.RequestLeaderboard;local calls=0
 local message='Synthetic Leaderboard projection dependency failure'
 Nexus.ViewProjections.RequestLeaderboard=function(...)
  local caller=debug.getinfo(2,'S')
  if caller and caller.source=='@ui/Leaderboard.lua' then calls=calls+1;return nil,nil,message end
  return request(...)
 end
 LB.MarkDataDirty()
 local before=LB.VirtualStats().dataFailures;local ok=pcall(LB.Refresh)
 if not C.setup(ok and calls==1 and LB.VirtualStats().dataFailures==before+1
  and LB.VirtualStats().lastDataError==message,'actual Leaderboard Refresh handles one public projection dependency failure')then
  Nexus.ViewProjections.RequestLeaderboard=request;return end
 C.expect(LB.DiagnosticSnapshot().projectionError==true,'Leaderboard producer exports its actual current view fault')
 C.expect(ViewError(Nexus.GetDiagnosticPageText('state'),'leaderboard')=='true','direct Leaderboard report retains its own current view fault')
 SlashCmdList.NEXUS('log');H.Advance(.15,.01)
 local hidden=Viewer(H)
 if not C.setup(hidden and LB.DiagnosticSnapshot().blockedReason=='hidden'
  and LB.VirtualStats().lastDataError==message,'viewer hides Leaderboard while its actual failure is current')then
  Nexus.ViewProjections.RequestLeaderboard=request;return end
 C.expect(ViewError(hidden,'leaderboard')=='true','registered hidden Leaderboard viewer exposes its current owned view fault')
 local faults=OwnerLine(hidden,'leaderboard','  faults ')
 C.expect(faults and faults:match('^  faults view=error:true$'),
  'Leaderboard fault group never claims ownership of import or Share ledgers')
 C.guard(not SnapshotBlock(hidden):find(message,1,true),'Leaderboard snapshot block exports no raw dependency message')
 Nexus.ViewProjections.RequestLeaderboard=request;LB.Show('lk')
 if not C.setup(Settled(H,LB)~=nil and LB.VirtualStats().lastDataError==nil,'restored Leaderboard dependency publishes successfully')then return end
 C.expect(LB.DiagnosticSnapshot().projectionError==false and ViewError(Nexus.GetDiagnosticPageText('state'),'leaderboard')=='false',
  'successful Leaderboard recovery exports no current view fault')
 C.guard(#H.actions==0 and #H.sent==0,'Leaderboard observation sends no gameplay or transport action')
end)
C.scenario('strict view sanitizer and unavailable snapshot reads',function()
 local H=Boot()
 for _,entry in ipairs({{'community',Nexus.CommunityBuilds},{'leaderboard',Nexus.Leaderboard}})do
  local name,owner=entry[1],entry[2];local snapshot=owner.DiagnosticSnapshot
  for _,value in ipairs({true,false,'truthy view payload',1,{private='payload'}})do
   owner.DiagnosticSnapshot=function()
    local d=snapshot();d.projectionError=value;return d
   end
   local ok,text=pcall(Nexus.GetDiagnosticPageText,'state');owner.DiagnosticSnapshot=snapshot
   if not C.setup(ok,'public report survives strict view-bit input')then return end
   local expected=type(value)=='boolean' and tostring(value) or 'unknown'
   C.expect(ViewError(text,name)==expected,'only a genuine boolean gives a known view fault observation')
   C.guard(not SnapshotBlock(text):find('truthy view payload',1,true),'nonboolean view input never becomes snapshot payload')
  end
  for _,mode in ipairs({'missing','throwing','non-table'})do
   if mode=='missing'then owner.DiagnosticSnapshot=nil
   else owner.DiagnosticSnapshot=function()
    if mode=='throwing'then error('Synthetic unreadable view provider',0)end
    return 'Synthetic non-table view provider'
   end end
   local ok,text=pcall(Nexus.GetDiagnosticPageText,'state');owner.DiagnosticSnapshot=snapshot
   if not C.setup(ok,'public report contains an unavailable snapshot without raising')then return end
   local projection=OwnerLine(text,name,'  projection=')
   C.expect(projection and projection:match(' blocked=unavailable$') and ViewError(text,name)=='unknown',
    'missing, throwing and non-table sources are unknown, never verified healthy')
   if name=='community'then
    local faults=OwnerLine(text,name,'  faults ')
    C.expect(faults and faults:find('saved_import=error:unknown share_status=error:unknown',1,true),
     'unavailable Community snapshot does not fabricate healthy import or Share observations')
   end
  end
 end
 C.guard(#H.actions==0 and #H.sent==0,'sanitization controls send no gameplay or transport action')
end)
C.finish('(current owned diagnostic flags; synthetic host only)')
checks=checks+C.n.expect+C.n.guard+C.n.setup
end

print('PASS diagnostic snapshot/paging/export checks='..checks..'; export turns='..turns..'; bytes='..#result)
