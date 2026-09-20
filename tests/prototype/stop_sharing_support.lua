-- Real community controls, catalog transactions, and Sync; synthetic data only.
local S=dofile('tests/prototype/share_test_support.lua');local D={T=S.T}
function D.Begin()
 local H,C=S.Boot();local first=S.Post('NEXUS-TEST-STOP-SHARING');local id=first.id
 S.T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)
 H.combat=true
 S.T.Until(H,function()return C.ManualPreparationStatus().ready end)
 Nexus.CommunityBuilds.ShowBuild(id)
 local button
 S.T.Until(H,function()
  for _,f in ipairs(H.frames)do
   if f:GetText()=='Stop Sharing' and f:IsVisible() and f:IsEnabled() and f:GetScript('OnClick')then button=f;return true end
  end
 end)
 S.T.Until(H,function()return C.ManualPreparationStatus().ready end)
 H.deleteCalls=0;H.tombstoneCalls=0;H.tombstoneTickets={};H.stopMessages={}
 local broadcast=Nexus.Sync.BroadcastDelete
 Nexus.Sync.BroadcastDelete=function(...)
  H.deleteCalls=H.deleteCalls+1;return broadcast(...)
 end
 local tombstone=C.SetTombstone
 C.SetTombstone=function(...)
  H.tombstoneCalls=H.tombstoneCalls+1
  local ok,why,ticket=tombstone(...)
  if ticket then H.tombstoneTickets[#H.tombstoneTickets+1]=ticket end
  return ok,why,ticket
 end
 local prior=print
 print=function(...)
  local parts={};for i=1,select('#',...)do parts[#parts+1]=tostring(select(i,...))end
  H.stopMessages[#H.stopMessages+1]=table.concat(parts,' ');return prior(...)
 end
 return H,C,id,button,function()print=prior end
end
function D.Confirm(H,id,button)
 button:Click()
 assert(H.popup and H.popup.which=='NEXUS_STOP_SHARING_BUILD' and H.popup.data.id==id,'actual exact-ID Stop Sharing confirmation')
 H.AcceptPopup()
 return H.stopMessages[#H.stopMessages] or ''
end
function D.Busy(H,C)
 local row=H.Clone((C.Get('synthetic-startup-1')));row.title='Unrelated incoming work';row.lastModified=3
 local ok,why,ticket=C.Put(row,{source='sync'})
 assert(ok==nil and why=='ROOT_MUTATION_PENDING' and ticket,'real unrelated pending catalog mutation')
 return ticket
end
function D.NoTable(messages)
 for _,message in ipairs(messages)do assert(not message:find('table: ',1,true),'structured Stop Sharing outcome must never print a table address')end
end
return D
