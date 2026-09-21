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
print('PASS diagnostic snapshot/paging/export checks='..checks..'; export turns='..turns..'; bytes='..#result)
