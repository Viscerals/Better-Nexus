-- Diagnostic evidence through real public report/viewer/export boundaries.
-- Synthetic offline hosts only; native clipboard/UI behavior remains NOT_RUN.
-- Staged source origins, not a claim this file was run against every pin:
-- C: pre-consumer 5d396f22a532c2622c82796a78abdd9332c86474 (no error bits).
-- ViewChecks: 88478ffb1dbac3d02197d7de28e59eae70c0eec1 (intermediate two-bit line).
-- R: 82d1a0a9def265667587f8e1394a633497e9ff0a (owner fault groups, pre-retention fix).
-- Block-1 C owns the import/Share bit predicates (including the intermediate fallback).
-- ViewChecks owns the later exact owner grammar and view independence predicates.
-- Counts include overlapping controls, not independent evidence items.
-- Matched RED/GREEN and output-mutation results belong in the PR evidence;
-- no historical execution outcome is inferred from these source comments.
-- FaultBits retains the anchored intermediate two-bit grammar for that stage;
-- it does not pretend that layout existed in the public integration/contributor.
-- Earlier projection-line error/status_error predicates are strengthened to
-- explicit owner bits. The projection-only negative guard also measures the
-- nonempty actual snapshot block. All four original sanitizer tuples remain;
-- the added string-Share tuple makes the negative payload markers meaningful.
-- The former phase/receiving substring assertion is strengthened to the whole
-- public-base projection grammar, rejecting extra unpublished error tokens.
-- Owner grammar: Community view/saved_import/share_status; Leaderboard view only.
-- A false view bit means no retained owned view-ledger fault, not universal
-- projection-job health. Unowned Leaderboard pump failures are outside this scope.
-- Existing import/Share nonboolean-to-false compatibility is retained; view
-- nonbooleans are unknown. Missing/unreadable snapshots do not prove health.
-- State content is carried opaquely by NEXUS_DIAGNOSTIC_LOG_5 D/L dictionary
-- framing/escaping. Its inverse preserves whole CR-normalized lines and trailing
-- newline, without interpreting token meanings or claiming an external parser API.
-- Public integration 1e8215c81a0e0b999606902401e65fb375cafd0e and contributor
-- 1f993d7beda05a3c77cad45ac3e3bb39855e5ec6 have no unpublished error/status_error
-- tokens. Owner fault groups are additive to those public State-page layouts.
-- This fixture owns its strict token expectations; it claims no external-parser
-- compatibility or universal passivity of inherited State-page getters.

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
local function SnapshotBlock(text)
 return text:match('PERSISTED VIEW DIAGNOSTICS[^\n]*\n(.-)\n\n') or ''
end
local function ParseFaultLine(line,owner)
 if type(line)~='string'then return end
 local view,import,status
 if owner=='community'then
  view,import,status=line:match('^  faults view=error:(%a+) saved_import=error:(%a+) share_status=error:(%a+)$')
 else view=line:match('^  faults view=error:(%a+)$')end
 local known={['true']=true,['false']=true,unknown=true}
 if not known[view] or (owner=='community' and (not known[import] or not known[status]))then return end
 return view,import,status
end
local function FaultBits(text,importError,statusError)
 local line=OwnerLine(text,'community','  faults ')
 if line then
  local view,import,status=ParseFaultLine(line,'community')
  return view~=nil and import==tostring(importError) and status==tostring(statusError)
 end
 -- Only the intermediate 88478ffb two-bit projection layout is accepted here.
 -- Public bases have no such tokens; current-view checks require owner groups.
 line=OwnerLine(text,'community','  projection=')
 return line and line:match('^  projection=current:%S+ pending:%S+ dirty:%S+ import=pending:%S+ phase:%S+ error:'
  ..tostring(importError)..' status_error:'..tostring(statusError)
  ..' receiving=%S+ publication_age=%S+ blocked=%S+$')~=nil
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
 'GUARD public diagnostic route preserves recognized saved-import-error; actual='..tostring(exported))

-- Orthogonal fault evidence survives reason precedence without exposing payloads.
local importReady=C.setup(snapshot.savedImportPending==false,'Begin failure occurs before any actual import job')
local importViewReady=ViewChecks.setup(CB.VirtualStats().lastDataError==nil and CB.VirtualStats().dataFailures==0,
 'actual import-only producer has no retained owned view fault')
if importReady then
C.expect(line:find('import=pending:false phase:idle ',1,true) and FaultBits(publicText,true,false),
 'direct pre-job diagnostic preserves import fault separately from pending and status')
if importViewReady then
 ViewChecks.expect(OwnerLine(publicText,'community','  faults ')
  =='  faults view=error:false saved_import=error:true share_status=error:false',
  'actual import-only report does not OR import failure into the view ledger')
end
C.expect(renderedLine:find('import=pending:false phase:idle ',1,true) and FaultBits(rendered,true,false),
 'registered hidden viewer retains import fault independently of hidden reason')
end
C.guard(not rendered:find('Synthetic personal import diagnostic fault',1,true),
 'consumer never includes raw import exception payload')
C.setup(FindCommunityLine('community catalog=0\n  filters scope=mine\nleaderboard catalog=1\n  projection=wrong')==nil,
 'community parser cannot borrow the leaderboard projection line')
for _,values in ipairs({{true,true},{'truthy import',{private='status payload'}},{1,'true'},{false,false},{'truthy import marker','status payload'}})do
 CB.DiagnosticSnapshot=function()
  local d=originalSnapshot();d.savedImportError=values[1];d.shareStatusError=values[2];return d
 end
 local sanitizedText=Nexus.GetDiagnosticPageText('state')
 local sanitized=CommunityLine(sanitizedText)
 local measured=SnapshotBlock(sanitizedText)
 if C.setup(#measured>0 and measured:find('community catalog=',1,true),
  'sanitizer control measures a nonempty actual Community snapshot block')then
 C.expect(FaultBits(sanitizedText,values[1]==true,values[2]==true),
  'only literal true survives both fault-bit sanitizers')
 C.guard(not sanitized:find('truthy import',1,true) and not sanitized:find('status payload',1,true)
  and not measured:find('truthy import',1,true) and not measured:find('status payload',1,true),
  'nonboolean fault inputs never become diagnostic payload in the measured owner block')
 end
end
CB.DiagnosticSnapshot=originalSnapshot
-- An actual All view masks import reason while preserving the retained error.
NexusDB.buildFilters.scope='all';CB.Show();CB.Refresh()
local all=CB.DiagnosticSnapshot()
if C.setup(all.filterScope=='all' and all.savedImportError and not all.savedImportPending
 and all.blockedReason~='saved-import-error','real All state masks a held pre-job import fault')then
C.expect(FaultBits(Nexus.GetDiagnosticPageText('state'),true,false),
 'All report retains independent import fault despite another reason')
end
local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
local projectionMessage='Synthetic diagnostic projection setter fault'
label.SetText=function()error(projectionMessage,0)end
local refreshed,refreshError=pcall(CB.Refresh)
label.SetText=setter
local masked=CB.DiagnosticSnapshot()
if C.setup(not refreshed and refreshError==projectionMessage and masked.blockedReason=='projection-error'
 and masked.savedImportError,'real renderer projection fault masks a simultaneously retained import fault')then
local maskedText=Nexus.GetDiagnosticPageText('state')
if ViewChecks.setup(Nexus.Leaderboard.VirtualStats().lastDataError==nil
 and Nexus.Leaderboard.VirtualStats().dataFailures==0,
 'other actual producer has no retained owned view fault during Community failure')then
 ViewChecks.expect(OwnerLine(maskedText,'leaderboard','  faults ')=='  faults view=error:false',
  'actual Community fault does not OR into the other owner view ledger')
end
local maskedLine=CommunityLine(maskedText)
C.expect(FaultBits(maskedText,true,false) and maskedLine:match(' blocked=projection%-error$'),
 'projection-error report still carries independent import fault')
ViewChecks.expect(OwnerLine(maskedText,'community','  faults ')
 =='  faults view=error:true saved_import=error:true share_status=error:false',
 'one actual projection-error report preserves coexistent view/import faults and no retained Share status error')
-- Export the captured actual fault state through the unchanged opaque D/L format.
do
 local provider=Nexus.GetDiagnosticPageText
 local captured=maskedText..'\nSynthetic export sentinel %7C|%25\r\n'
 local stateCalls,otherCalls=0,0
 Nexus.GetDiagnosticPageText=function(page,...)
  if page=='state'then stateCalls=stateCalls+1;return captured end
  otherCalls=otherCalls+1;return provider(page,...)
 end
 local exportOK,exportText=pcall(function()
  local co=Nexus.NewAIExportCoroutine()
  for i=1,2000 do
   local ok,value=coroutine.resume(co)
   if not ok then error(value,0)end
   if coroutine.status(co)=='dead'then return value end
  end
  error('Synthetic export did not finish within the bounded resume count',0)
 end)
 Nexus.GetDiagnosticPageText=provider
 local restoredState=Nexus.GetDiagnosticPageText('state')
 local providerRestored=C.setup(Nexus.GetDiagnosticPageText==provider and type(restoredState)=='string'
  and not restoredState:find('Synthetic export sentinel',1,true),
  'restored actual State provider identity and call no longer return the frozen export-only sentinel')
 assert(providerRestored,'fixture State provider restoration failed; later provider reads are gated')
 if C.setup(exportOK and type(exportText)=='string'
  and exportText:match('^NEXUS_DIAGNOSTIC_LOG_5\n') and exportText:match('\nEND|[^\n]*$'),
  'actual bounded export completes with version5 header and terminator',(not exportOK) and exportText or nil)then
  local dictionary={[0]=''};local refs={};local valid=true;local definitions=0
  for row in (exportText..'\n'):gmatch('([^\n]*)\n')do
   local id,encoded=row:match('^D|(%d+)|(.*)$')
   if id then
    id=tonumber(id)
    if dictionary[id]~=nil then valid=false end
    -- One pass: an encoded literal "%7C" becomes "%7C", never another pipe.
    dictionary[id]=encoded:gsub('%%(%x%x)',function(hex)return string.char(tonumber(hex,16))end)
    definitions=definitions+1
   else
    local page,line,text=row:match('^L|(%d+)|(%d+)|(%d+)$')
    if page then refs[#refs+1]={tonumber(page),tonumber(line),tonumber(text)}end
   end
  end
  local state={}
  for _,ref in ipairs(refs)do
   if dictionary[ref[1]]=='state'then
    if ref[2]~=#state+1 or dictionary[ref[3]]==nil then valid=false
    else state[#state+1]=dictionary[ref[3]]end
   end
  end
  if C.setup(valid and definitions>0 and #state>0 and stateCalls==1 and otherCalls>0,
   'actual dictionary references reconstruct ordered State rows and delegate other real pages')then
  local reconstructed=table.concat(state,'\n')
  C.guard(reconstructed==(captured:gsub('\r','')),
   'opaque State D/L inverse preserves the complete CR-normalized page and its trailing newline')
  ViewChecks.expect(OwnerLine(reconstructed,'community','  faults ')
   =='  faults view=error:true saved_import=error:true share_status=error:false',
   'real coexistent owner fault line survives the unchanged opaque export inverse')
  C.guard(reconstructed:find('Synthetic export sentinel %7C|%25\n',1,true),
   'single-pass dictionary decoding preserves literal percent escapes and a pipe')
  print('OPAQUE_STATE_INVERSE lines='..#state..' state_calls='..stateCalls..' other_page_calls='..otherCalls)
  end
 end
 C.guard(#H.actions==0 and #H.sent==0,'opaque inverse sends no gameplay or transport action')
end
end

local function Settle()
 for i=1,2000 do
  H.Advance(.01,.01)
  local d=CB.DiagnosticSnapshot()
  if d.projectionCurrent and not d.savedImportPending and not d.savedImportError then return i end
 end
end
if C.guard(Settle()~=nil,'restored real dependencies complete import and publish without a retained view error')then
local recovered=CB.DiagnosticSnapshot()
if C.setup(recovered.savedImportError==false and recovered.shareStatusError==false,
 'actual producer clears both current fault observations after recovery')then
C.expect(FaultBits(Nexus.GetDiagnosticPageText('state'),false,false),
 'recovered report has explicit no-retained-import-or-Share fault bits')
end
-- Real status setter failure, through the public popup and refresh routes.
CB.ShowPostBuild()
local statusLabel=NexusPostPopup._shareStatus;local statusSetter=statusLabel.SetText
statusLabel.SetText=function()error('Synthetic diagnostic status setter fault',0)end
CB.Refresh()
local shareReady=C.setup(CB.DiagnosticSnapshot().shareStatusError==true
 and CB.DiagnosticSnapshot().savedImportError==false,
 'actual Share setter fault has an independent status ledger')
local shareViewReady=ViewChecks.setup(CB.VirtualStats().lastDataError==nil,
 'Share-only producer has no retained owned view fault')
if shareReady then
local shareText=Nexus.GetDiagnosticPageText('state')
C.expect(FaultBits(shareText,false,true),
 'direct report preserves actual status failure separately from import')
if shareViewReady then
 ViewChecks.expect(OwnerLine(shareText,'community','  faults ')
  =='  faults view=error:false saved_import=error:false share_status=error:true',
  'actual Share-only report does not OR Share failure into the view ledger')
end
end
if shareReady then
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
end
SlashCmdList.NEXUS('log');H.Advance(.15,.01)
local hiddenStatusText=ViewerText()
local hiddenStatus=CommunityLine(hiddenStatusText)
print('REGISTERED_STATUS_VIEWER '..hiddenStatus)
if shareReady and C.setup(CB.DiagnosticSnapshot().blockedReason=='hidden' and CB.DiagnosticSnapshot().shareStatusError,
 'normal viewer hides Library without recovering failed Share setter')then
C.expect(FaultBits(hiddenStatusText,false,true) and hiddenStatus:match(' blocked=hidden$'),
 'hidden report preserves active status fault even when visibility masks reason')
end
statusLabel.SetText=statusSetter;CB.Refresh()
if shareReady and C.setup(CB.DiagnosticSnapshot().shareStatusError==false,'successful actual status write proves recovery')then
C.expect(FaultBits(Nexus.GetDiagnosticPageText('state'),false,false),
 'successful status recovery clears printed status bit')
end
C.guard(#H.actions==0 and #H.sent==0,'extended diagnostic observation sends no gameplay/network action')
end
-- Genuine pending-job fault: Begin succeeds, receive defers it, then cleanup fails.
local pendingDB=F.Database();pendingDB.buildFilters={scope='mine'}
H=F.Boot(pendingDB,function(h)h.perks.serverBuildSlots={}end)
CB=Nexus.CommunityBuilds
local receiving=true;local previousReceiving=Nexus.Sync.IsReceiving
Nexus.Sync.IsReceiving=function()return receiving end
local factory=Nexus.BuildCatalog.BeginSavedMirrorCursor;local faultCalls=0
Nexus.BuildCatalog.BeginSavedMirrorCursor=function()
 faultCalls=faultCalls+1;error('Synthetic pending import cleanup fault',0)
end
CB.Show()
local pendingReady=C.setup(CB.DiagnosticSnapshot().savedImportPending==true and faultCalls==0,
 'real Begin creates a genuine receive-deferred job before factory execution')
local pendingFaultReady=false
if pendingReady then
receiving=false
for i=1,200 do if faultCalls>0 then break end;H.Advance(.01,.01)end
local pendingDiag=CB.DiagnosticSnapshot()
pendingFaultReady=C.setup(faultCalls==1 and pendingDiag.savedImportPending and pendingDiag.savedImportError,
 'real import pump fault retains its existing unfinished job')
if pendingFaultReady then
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
end
end
Nexus.BuildCatalog.BeginSavedMirrorCursor=factory
Nexus.Sync.IsReceiving=previousReceiving;CB.Show()
local pendingSettled=C.guard(Settle()~=nil,'restored factory completes the original real pending import')
if pendingReady and pendingFaultReady and pendingSettled then
C.expect(FaultBits(Nexus.GetDiagnosticPageText('state'),false,false),
 'completed pending import clears current diagnostic fault bit')
end
C.guard(#H.actions==0 and #H.sent==0,'pending fault and recovery send no gameplay/network action')
C.finish('(synthetic diagnostic consumer only)')
checks=checks+C.n.expect+C.n.guard+C.n.setup
print('PASS controls: measured Library work unchanged; sanitized fault booleans; registered viewer; actions='..#H.actions..' sends='..#H.sent)
print('PASS public route saved-import-error diagnostic compatibility')
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
 return (ParseFaultLine(line,owner))
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
  'dirty Library without retained error is explicitly not an owned view fault')
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
 local projection=OwnerLine(direct,'community','  projection=')
 C.expect(projection and projection:match('^  projection=current:%S+ pending:%S+ dirty:%S+ import=pending:%S+ phase:%S+ receiving=%S+ publication_age=%S+ blocked=%S+$')
  and not projection:find(' error:',1,true) and not projection:find('status_error:',1,true),
  'projection line keeps the public-base layout: phase/receiving adjacent and no import/Share error tokens')
 SlashCmdList.NEXUS('log');H.Advance(.15,.01)
 local hidden=Viewer(H)
 if not C.setup(hidden and CB.DiagnosticSnapshot().blockedReason=='hidden'
  and CB.VirtualStats().lastDataError==message,'registered viewer hides Library while actual view fault remains retained')then label.SetText=setter;return end
 C.expect(ViewError(hidden,'community')=='true','registered hidden Library viewer exposes retained view fault independently of hidden')
 if C.setup(SnapshotBlock(direct):find('community catalog=',1,true)
  and SnapshotBlock(hidden):find('community catalog=',1,true),
  'nonempty direct and hidden sanitized blocks contain the real Community owner')then
 C.guard(not SnapshotBlock(direct):find(message,1,true) and not SnapshotBlock(hidden):find(message,1,true),
  'sanitized snapshot blocks contain no raw retained view error payload')
 end
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
  'dirty Leaderboard without retained error is explicitly not an owned view fault')
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
 local direct=Nexus.GetDiagnosticPageText('state')
 C.expect(ViewError(direct,'leaderboard')=='true','direct Leaderboard report retains its own current view fault')
 if C.setup(Nexus.CommunityBuilds.VirtualStats().lastDataError==nil
  and Nexus.CommunityBuilds.VirtualStats().lastImportError==nil
  and Nexus.CommunityBuilds.VirtualStats().lastStatusError==nil,
  'other actual Community producer has no retained view, import or Share error during Leaderboard failure')then
  C.expect(OwnerLine(direct,'community','  faults ')
   =='  faults view=error:false saved_import=error:false share_status=error:false',
   'actual Leaderboard fault does not OR into the other Community owner ledger')
 end
 local projection=OwnerLine(direct,'leaderboard','  projection=')
 C.expect(projection and projection:match('^  projection=current:%S+ pending:%S+ dirty:%S+ import=pending:%S+ phase:%S+ receiving=%S+ publication_age=%S+ blocked=%S+$')
  and not projection:find(' error:',1,true) and not projection:find('status_error:',1,true),
  'Leaderboard projection keeps the public-base layout with phase/receiving adjacent and no import/Share error tokens')
 SlashCmdList.NEXUS('log');H.Advance(.15,.01)
 local hidden=Viewer(H)
 if not C.setup(hidden and LB.DiagnosticSnapshot().blockedReason=='hidden'
  and LB.VirtualStats().lastDataError==message,'viewer hides Leaderboard while its actual failure is current')then
  Nexus.ViewProjections.RequestLeaderboard=request;return end
 C.expect(ViewError(hidden,'leaderboard')=='true','registered hidden Leaderboard viewer exposes its current owned view fault')
 local faults=OwnerLine(hidden,'leaderboard','  faults ')
 C.expect(faults and faults:match('^  faults view=error:true$'),
  'Leaderboard fault group never claims ownership of import or Share ledgers')
 if C.setup(SnapshotBlock(hidden):find('leaderboard catalog=',1,true),
  'nonempty hidden sanitized block contains the real Leaderboard owner')then
 C.guard(not SnapshotBlock(hidden):find(message,1,true),'Leaderboard snapshot block exports no raw dependency message')
 end
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
   if C.setup(SnapshotBlock(text):find(name..' catalog=',1,true),
    'strict sanitizer payload control inspects a nonempty block with its actual owner')then
   C.guard(not SnapshotBlock(text):find('truthy view payload',1,true),'nonboolean view input never becomes snapshot payload')
 end
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

-- Retained fault observations stay independent of dirty and pending state.
do
 local R=dofile('tests/prototype/view_regression_support.lua').Checker('retained view diagnostic')
 local function Retained(owner,message)
  return owner.VirtualStats().lastDataError==message
 end
 local function ReportFault(owner)
  return ViewError(Nexus.GetDiagnosticPageText('state'),owner)
 end
 R.scenario('Leaderboard retains fault across dirty, receive revision and pending retry',function()
  local H=Boot();local LB=Nexus.Leaderboard;local P=Nexus.ViewProjections
  LB.Show('lk')
  if not R.setup(Settled(H,LB)~=nil,'real Leaderboard publication without retained error settles before fault')then return end
  R.guard(LB.VirtualStats().lastDataError==nil and LB.DiagnosticSnapshot().projectionError==false
   and ReportFault('leaderboard')=='false','publication has no retained view fault')
  LB.Hide();LB.MarkDataDirty()
  R.guard(LB.VirtualStats().lastDataError==nil and LB.DiagnosticSnapshot().projectionError==false
   and ReportFault('leaderboard')=='false','hidden dirty mark without retained error does not fabricate a fault')
  LB.Show('lk')
  if not R.setup(Settled(H,LB)~=nil,'dirty Leaderboard without retained error republishes before fault')then return end
  local request=P.RequestLeaderboard;local calls=0
  local message='Synthetic retained Leaderboard diagnostic failure'
  P.RequestLeaderboard=function(...)
   local caller=debug.getinfo(2,'S')
   if caller and caller.source=='@ui/Leaderboard.lua' then calls=calls+1;return nil,nil,message end
   return request(...)
  end
  LB.MarkDataDirty()
  local failures=LB.VirtualStats().dataFailures;local ok=pcall(LB.Refresh)
  P.RequestLeaderboard=request
  if not R.setup(ok and calls==1 and Retained(LB,message)
   and LB.VirtualStats().dataFailures==failures+1,'real Leaderboard Refresh retains one dependency failure')then return end
  local publication=LB.VirtualStats().dataRefreshes
  R.guard(LB.DiagnosticSnapshot().projectionError==true and ReportFault('leaderboard')=='true',
   'actual initial failure is independently observable before invalidation')
  LB.Hide();LB.MarkDataDirty()
  local dirty=LB.DiagnosticSnapshot()
  if not R.setup(Retained(LB,message) and LB.VirtualStats().dataRefreshes==publication
   and dirty.projectionDirty and not dirty.projectionCurrent and dirty.blockedReason=='hidden',
   'hidden dirty mark retains actual error without a successful publication')then return end
  R.expect(dirty.projectionError==true,'dirty invalidation cannot erase the retained Leaderboard fault')
  R.expect(ReportFault('leaderboard')=='true','public hidden dirty report retains the actual fault')
  local receiving=true
  local oldReceiving,oldRemaining=Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft
  Nexus.Sync.IsReceiving=function()return receiving end
  Nexus.Sync.ReceiveTimeLeft=function()return receiving and 1 or 0 end
  -- Request alone schedules within 0.5 s; only the executed receive callback
  -- can defer beyond 0.6 s. deferredSince/MAX_RECEIVE_DEFER can shorten
  -- that window, causing SETUP failure, never a false proof of this branch.
  local preReceive=Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())
  if not R.setup(not preReceive or preReceive.due-H.now<=.5,
   'receive discriminator starts without an older far-future scheduled callback')then
   Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft=oldReceiving,oldRemaining;return
  end
  local revision=Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED)
  Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED)
  local receivePending
  for i=1,70 do
   H.Advance(.01,.01)
   receivePending=Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())
   if receivePending and receivePending.due-H.now>.6 then break end
  end
  local deferred=LB.DiagnosticSnapshot()
  if not R.setup(Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED)==revision+1
   and receivePending and receivePending.due-H.now>.6
   and Retained(LB,message) and LB.VirtualStats().dataRefreshes==publication
   and deferred.projectionDirty and deferred.syncReceiving,
   'executed receive callback after DPS revision observation defers without recovering the fault')then
   Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft=oldReceiving,oldRemaining;return
  end
  print(string.format('RECEIVE_DEFERRED leaderboard due_in=%.3f',receivePending.due-H.now))
  R.expect(deferred.projectionError==true,'receive-window dirty notification retains Leaderboard fault')
  R.expect(ReportFault('leaderboard')=='true','public receive-deferred report retains the fault')
  local pumped=P.WorkStats().leaderboardPumps
  LB.Show('lk')
  local pending=LB.DiagnosticSnapshot()
  if not R.setup(pending.projectionPending and Retained(LB,message)
   and LB.VirtualStats().dataRefreshes==publication and P.WorkStats().leaderboardPumps==pumped,
   'restored actual request creates pending work before any pump or publication')then
   Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft=oldReceiving,oldRemaining;return
  end
  R.expect(pending.projectionError==true,'real pending retry is not successful fault recovery')
  R.expect(ReportFault('leaderboard')=='true','public pending report retains fault independently of pending reason')
  local refreshed,why=LB.RefreshData()
  R.guard(refreshed==false and why=='pending' and LB.DiagnosticSnapshot().projectionPending
   and Retained(LB,message),'repeated real request stays pending and retains its error ledger')
  R.expect(LB.DiagnosticSnapshot().projectionError==true,'repeated pending request cannot hide the retained fault')
  receiving=false
  local settled=Settled(H,LB)
  Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft=oldReceiving,oldRemaining
  if not R.setup(settled~=nil and LB.VirtualStats().lastDataError==nil
   and LB.VirtualStats().dataRefreshes>publication and P.WorkStats().leaderboardPumps>pumped,
   'ordinary real projection pumps publish and clear the retained error')then return end
  R.guard(LB.DiagnosticSnapshot().projectionError==false and ReportFault('leaderboard')=='false',
   'successful actual publication clears the exported retained fault')
  R.guard(LB.VirtualStats().dataFailures==failures+1,'dirty and pending progression create no extra failure')
  R.guard(#H.actions==0 and #H.sent==0,'retention and recovery send no gameplay or transport action')
 end)
 R.scenario('Community keeps its independent retained fault through the same notifications',function()
  local H=Boot();local CB=Nexus.CommunityBuilds;CB.Show()
  if not R.setup(Settled(H,CB)~=nil,'real Community publication and import settle')then return end
  local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
  local message='Synthetic Community retained diagnostic control'
  label.SetText=function()error(message,0)end
  local failures=CB.VirtualStats().dataFailures;local ok,err=pcall(CB.Refresh)
  if not R.setup(not ok and err==message and Retained(CB,message)
   and CB.VirtualStats().dataFailures==failures+1,'actual host setter exception is retained by Community owner')then
   label.SetText=setter;return
  end
  local publication=CB.VirtualStats().dataRefreshes
  CB.Hide();CB.MarkDataDirty()
  R.guard(CB.DiagnosticSnapshot().projectionError==true and Retained(CB,message)
   and ReportFault('community')=='true','Community hidden dirty mark keeps independent fault visible')
  local receiving=true;local oldReceiving,oldRemaining=Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft
  Nexus.Sync.IsReceiving=function()return receiving end
  Nexus.Sync.ReceiveTimeLeft=function()return receiving and 1 or 0 end
  -- Request alone schedules within 0.5 s; only the executed receive callback
  -- can defer beyond 0.6 s. deferredSince/MAX_RECEIVE_DEFER can shorten
  -- that window, causing SETUP failure, never a false proof of this branch.
  local preReceive=Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())
  if not R.setup(not preReceive or preReceive.due-H.now<=.5,
   'receive discriminator starts without an older far-future scheduled callback')then
   label.SetText=setter;Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft=oldReceiving,oldRemaining;return
  end
  local revision=Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)
  Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED)
  local receivePending
  for i=1,70 do
   H.Advance(.01,.01)
   receivePending=Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())
   if receivePending and receivePending.due-H.now>.6 then break end
  end
  if not R.setup(Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)==revision+1
   and receivePending and receivePending.due-H.now>.6
   and Retained(CB,message) and CB.VirtualStats().dataRefreshes==publication,
   'executed receive callback after Library revision observation defers without publication or error clearing')then
   label.SetText=setter;Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft=oldReceiving,oldRemaining;return
  end
  print(string.format('RECEIVE_DEFERRED community due_in=%.3f',receivePending.due-H.now))
  local deferred=CB.DiagnosticSnapshot()
  R.guard(deferred.projectionError==true and ReportFault('community')=='true'
   and deferred.savedImportError==false and deferred.shareStatusError==false
   and OwnerLine(Nexus.GetDiagnosticPageText('state'),'community','  faults ')
    =='  faults view=error:true saved_import=error:false share_status=error:false',
   'Community view error coexists with no retained import or Share error')
  label.SetText=setter;receiving=false;CB.Show()
  local pending=CB.DiagnosticSnapshot()
  if not R.setup(pending.projectionPending and Retained(CB,message),
   'real Community request is pending before retained-fault publication recovery')then
   Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft=oldReceiving,oldRemaining;return
  end
  R.guard(pending.projectionError==true and ReportFault('community')=='true',
   'Community pending work coexists with its retained view fault in public text')
  local settled=Settled(H,CB)
  Nexus.Sync.IsReceiving,Nexus.Sync.ReceiveTimeLeft=oldReceiving,oldRemaining
  if not R.setup(settled~=nil and CB.VirtualStats().lastDataError==nil
   and CB.VirtualStats().dataRefreshes>publication,'restored actual Community binding publishes successfully')then return end
  R.guard(CB.DiagnosticSnapshot().projectionError==false and ReportFault('community')=='false',
   'actual Community publication recovery clears its own retained fault')
  R.guard(CB.VirtualStats().dataFailures==failures+1 and #H.actions==0 and #H.sent==0,
   'Community notification/control paths add no new failure or gameplay/network action')
 end)
 R.finish('(actual retained errors across dirty and pending; synthetic host only)')
 checks=checks+R.n.expect+R.n.guard+R.n.setup
end

end

print('PASS diagnostic snapshot/paging/export checks='..checks..'; export turns='..turns..'; bytes='..#result)
