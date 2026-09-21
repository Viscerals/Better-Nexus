-- Actual incoming protocol, Share popup, lifecycle, and library filter controls.
local S=dofile('tests/prototype/share_test_support.lua');local T=S.T
local H,C=S.Boot()
local data={id='incoming-wire-share-test',t='Synthetic incoming summary',
 a='Other-Ebonhold',o=Nexus.Identity.OwnerKey('Other','Ebonhold'),
 c='MAGE',m=time(),h='a1',n=3}
local wire='WLBI|Other-Ebonhold|'..Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(data))
Nexus.Sync.HandleIncoming(wire,'Other-Ebonhold')
local busy=C.ManualPreparationStatus()
assert(busy.relevant and not busy.ready,'actual incoming protocol retains catalog work')
local first=S.Post('NEXUS-TEST-THREE-COPIES');local id=first.id
assert(first.localPending and not first.localSaved and not first.queueAdmitted,'Share waits behind actual incoming work')
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)
local incoming=assert(C.Get(data.id))
assert(incoming.title==data.t and incoming.ownerKey==data.o,'original incoming summary commits normally')
local record=assert(C.Get(id))
assert(record.echoes[1].stacks==3 and record.ordinaryComplete==true,'three supplied copies are complete ordinary evidence')
assert(H.putCalls[id]==1 and #H.shareCalls==1 and H.shareCalls[1].id==id,'one local commit queues the same approved ID once')
assert(Nexus.CommunityBuilds.ShareStatus(id).queueAdmitted,'normal Sync transport accepts the saved partial-size build')

Nexus.CommunityBuilds.Show()
local frame=assert(NexusCommunityBuildsFrame)
local function Click(button)
 assert(button:IsVisible() and button:IsEnabled(),'normal visible enabled library control')
 button:Click()
end
if frame._myBuildsBtn:IsEnabled() then Click(frame._myBuildsBtn) end
assert(not frame._myBuildsBtn:IsEnabled() and frame._scopeBtn:IsEnabled(),'disabled scope button marks selected My Builds')
if frame._qualifiedBtn:GetText()~='All Shared' then Click(frame._qualifiedBtn) end
frame._searchBox:SetText('NEXUS-TEST-THREE-COPIES')
frame._searchBox:GetScript('OnTextChanged')(frame._searchBox,true)
local function Published(count)
 T.Until(H,function()
  local view=Nexus.CommunityBuilds.DiagnosticSnapshot()
  return view.projectionCurrent and view.resultCount==count and view.displayedCount==count
 end)
end
Published(1)
local rows=assert(Nexus.ViewProjections.Builds({scope='mine',currentClassOnly=true,
 qualifiedOnly=false,search='NEXUS-TEST-THREE-COPIES',sortMode='dps'}))
assert(#rows==1 and rows[1].id==id,'actual My Builds projection contains the approved exact ID')
assert(not rows[1]._nexusQualified,'no synthetic DPS records were invented')
Click(frame._qualifiedBtn);assert(frame._qualifiedBtn:GetText()=='Both DPS records')
Published(0)
Click(frame._qualifiedBtn);Published(1)
Click(frame._scopeBtn);Published(1)
assert(not frame._scopeBtn:IsEnabled() and frame._myBuildsBtn:IsEnabled(),'disabled scope button now marks All Shared')
assert(H.putCalls[id]==1 and #H.shareCalls==1,'listing/filter reads do not resubmit or broadcast')
assert(#H.actions==0,'Share and listing do not mutate game resources or server Wishlists')
print('PASS actual incoming Sync contention, one three-copy Share, My Builds/All Shared listing, truthful DPS qualification')
