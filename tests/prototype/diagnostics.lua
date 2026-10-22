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
db.buildFilters={scope='mine',sort='dps',class='ALL'}
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
Nexus.GameAdapter.Slots=function()
 attempts=attempts+1;error('Synthetic personal import diagnostic fault',0)
end
local shown,why=pcall(CB.Show)
Nexus.GameAdapter.Slots=slots
check(shown,'setup: actual Show contains the personal import exception: '..tostring(why))
local snapshot=CB.DiagnosticSnapshot()
check(attempts>0 and snapshot.filterScope=='mine' and snapshot.savedImportError==true
 and snapshot.blockedReason=='saved-import-error',
 'setup: actual Mine import fault owns the new renderer reason: '..tostring(snapshot.blockedReason))
local function CommunityLine(text)
 local tail=text:match('community catalog=[^\n]*\n(.*)');check(tail, 'community diagnostic block missing')
 local line=tail:match('(  projection=[^\n]*)');check(line,'community projection line missing');return line
end
local function State()
 local d=CB.DiagnosticSnapshot();local s=CB.VirtualStats();local w=Nexus.ViewProjections.WorkStats()
 return table.concat({tostring(d.blockedReason),tostring(d.savedImportPending),
  tostring(d.savedImportError),s.importFailures,s.dataFailures,w.communityPumps,
  w.publications,#H.actions,#H.sent,Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)},'|')
end
local before=State()
local line=CommunityLine(Nexus.GetDiagnosticPageText('state'))
check(State()==before,'guard: real public report read does not advance work or change retained fault')
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
-- The actual slash command is /nexus log (not an undocumented diagnostics alias).
-- Opening the normal viewer closes Library; its state must truthfully be hidden.
SlashCmdList.NEXUS('log')
H.Advance(.15,.01)
check(NexusLogScroll and NexusLogScroll.scrollChild,'real diagnostic viewer edit box exists')
local rendered=NexusLogScroll.scrollChild:GetText():gsub('||','|')
local renderedLine=CommunityLine(rendered)
check(renderedLine:match(' blocked=hidden$') and CB.DiagnosticSnapshot().blockedReason=='hidden',
 'guard: normal viewer closes Library and retains truthful hidden reason')
print('REGISTERED_SLASH_VIEWER '..renderedLine)
print('PASS controls: passive public report; arbitrary tokens sanitized; actual slash viewer rendered; actions='..#H.actions..' sends='..#H.sent)
check(#H.actions==0 and #H.sent==0,'guard: synthetic observation sends no gameplay/network action')
check(exported==snapshot.blockedReason,
 'EXPECT public diagnostics preserves recognized saved-import-error; actual='..tostring(exported))
print('PASS public saved-import-error diagnostic compatibility')
end
print('PASS diagnostic snapshot/paging/export checks='..checks..'; export turns='..turns..'; bytes='..#result)
