-- Actual existing-record Edit Build / Save Details setup. Synthetic data only.
local S=dofile('tests/prototype/share_test_support.lua');local E={T=S.T}
function E.Begin()
 local H,C=S.Boot();S.Incoming(H,C);local first=S.Post('NEXUS-TEST-EDIT-SAME-ID');local id=first.id
 S.T.Until(H,function()local v=Nexus.Sync.GetShareStatus(id);return v and v.sendCompleted end)
 H.combat=true
 S.T.Until(H,function()return C.ManualPreparationStatus().ready end)
 Nexus.CommunityBuilds.ShowBuild(id)
 local edit
 S.T.Until(H,function()
  for _,f in ipairs(H.frames)do
   if f:GetText()=='Edit Build' and f:IsVisible() and f:IsEnabled() and f:GetScript('OnClick') then edit=f;return true end
  end
 end)
 edit:Click();local p=assert(NexusEditPopup)
 assert(p:IsVisible() and p._editingId==id,'actual Edit Build opens selected exact ID')
 p._editTitleBox:_NexusSetRawText('NEXUS-TEST-EDIT-SAME-ID v2')
 p._editDescBox:_NexusSetRawText('Approved updated description')
 S.T.Until(H,function()return C.ManualPreparationStatus().ready end)
 return H,C,id,p,H.Clone((C.Get(id)))
end
function E.Submit(H,C,id,p,old)
 local before={puts=H.putCalls[id],broadcasts=#H.shareCalls,sent=#H.sent,chat=#H.chat}
 p._saveBtn:Click()
 assert(not p:IsShown() and H.putCalls[id]==before.puts+1,'actual Save Details submits one accepted local ticket')
 assert(C.Get(id).lastModified==old.lastModified and #H.shareCalls==before.broadcasts,'no committed revision or broadcast before ticket completes')
 local text=H.chat[#H.chat] or ''
 -- print() is captured by the runtime, while product notify() uses H.chat.
 -- The actual UI callback remains visible via the shared synthetic print tap.
 assert(H.editPrint and H.editPrint:find('Waiting to save locally; nothing has been sent',1,true),'actual Edit UI must disclose pending local save before commit')
 return before
end
function E.CapturePrint(H)
 local prior=print
 print=function(...)
  local parts={};for i=1,select('#',...)do parts[#parts+1]=tostring(select(i,...))end
  H.editPrint=table.concat(parts,' ');return prior(...)
 end
 return function()print=prior end
end
function E.AwaitCommit(H,C,id,old)
 S.T.Until(H,function()
  local row=C.Get(id);return row and row.lastModified>old.lastModified
 end)
 return assert(C.Get(id))
end
function E.LaterWork(H,C,kind)
 if kind=='put' then
  local row=H.Clone((C.Get('synthetic-startup-2')));row.title='Later incoming edit contention';row.lastModified=3
  local ok,why,ticket=C.Put(row,{source='sync'});assert(ok==nil and why=='ROOT_MUTATION_PENDING' and ticket);return ticket
 end
 local handle
 S.T.Until(H,function()handle=C.BeginCatalogMaintenance({database=NexusDB,operation='retention'});return handle~=nil end,1000)
 assert(C.MaintenanceEvictOverlay(handle,'synthetic-startup-2'))
 local ok,why,ticket=C.CommitMaintenance(handle);assert(ok==nil and why=='ROOT_MUTATION_PENDING' and ticket);return ticket
end
function E.Sends(H,id,revision)
 local rows={}
 for _,packet in ipairs(H.sent)do
  local body=packet.text:gsub('||','|'):match('^WLBI|[^|]+|(.+)$')
  if body then
   local row=Nexus.Codec.JSONDecode(Nexus.Codec.Base64Decode(body))
   if row and row.id==id and row.m==revision then rows[#rows+1]=row end
  end
 end
 return rows
end
return E
