-- Remote withdrawal stays unsupported while protocol 7 proves no edit/delete
-- order. These checks hold the refusal consistently: no new inbound WLRD, at
-- any stamp, hides a stored row, and no local path emits a WLRD.
local P=dofile('tests/prototype/sync_pair_support.lua')
local A,B=P.Boot({'GuardAlpha','GuardBeta'},0)
local C=B.e.Nexus.BuildCatalog
local id=P.Post(A,'NEXUS-TEST-WITHDRAWAL-GUARDS')
P.Until(function()return P.Full(B,id)end)
P.Until(function()return P.Ready(B)end)
local source=A.e.Nexus.BuildCatalog.Get(id)
local committed=B.H.Clone(P.Full(B,id));local revision=committed.lastModified
local function Delete(sender,stamp)
 P.Channel(B,table.concat({'WLRD',sender,id,tostring(stamp),sender},'|'),sender)
 P.Advance(10);P.Until(function()return P.Ready(B)end)
end
local function Intact(why)
 local row=C.Get(id)
 assert(row and row.lastModified==revision and row.description==source.description and row.echoes[1].stacks==3,why)
 assert(C.TombstoneState(id).state=='NONE',why..' (no reservation)')
end
local malformed,storage=B.e.Nexus.Sync.Stats().malformedRejected,B.e.Nexus.Sync.Stats().storageRejected
Delete(A.name,revision-1);Intact('stale same-owner withdrawal must not hide the newer committed row')
Delete(A.name,revision-1);Intact('replayed stale withdrawal changes nothing')
Delete(A.name,1);Intact('reordered much older withdrawal changes nothing')
Delete(A.name,revision);Intact('equal-stamp direct-owner withdrawal proves no order and must not hide the row')
Delete(A.name,revision+1);Intact('later-stamp direct-owner withdrawal proves no order and must not hide the row')
Delete(A.name,revision+100000);Intact('far-later direct-owner withdrawal proves no order and must not hide the row')
assert(B.e.Nexus.Sync.Stats().malformedRejected==malformed and B.e.Nexus.Sync.Stats().storageRejected==storage,'an order-unproved withdrawal is refused as such, not as a malformed or storage failure')
assert(B.e.Nexus.Sync.Stats().withdrawalOrderRefused==6,'each of the six direct-owner withdrawals was refused for unproved order')
print('PASS direct-owner withdrawals at older, equal and later stamps leave the stored row visible')
Delete('WrongOwner-Ebonhold',revision+100);Intact('wrong-owner withdrawal cannot hide the row at any stamp')
print('PASS wrong-owner withdrawal is refused')

-- Originating Stop Sharing through the actual controls.
P.Until(function()return P.Ready(A)end)
A.e.Nexus.CommunityBuilds.ShowBuild(id)
local button
A.T.Until(A.H,function()
 for _,f in ipairs(A.H.frames)do
  if f:GetText()=='Stop Sharing' and f:IsVisible() and f:IsEnabled() and f:GetScript('OnClick')then button=f;return true end
 end
end)
A.T.Until(A.H,function()return P.Ready(A)end)
button:Click();assert(A.H.popup.data.id==id);A.H.AcceptPopup();P.Advance(20)
local status=assert(A.e.Nexus.Sync.GetDeleteStatus(id))
assert(status.terminal and status.reason=='REMOTE_TOMBSTONE_ORDER_UNPROVEN','origin reports the exact remote ordering refusal')
assert(A.e.Nexus.BuildCatalog.TombstoneState(id).state=='CURRENT_DENY' and A.e.Nexus.BuildCatalog.Get(id)==nil,'local owner removal commits and is retained')
-- An ordinary peer request must not obtain the withdrawal the origin refused.
B.e.SlashCmdList.NEXUS('sync');P.Advance(60)
A.H.Advance(10,.05);A.e.SlashCmdList.NEXUS('sync');P.Advance(60)
assert(P.Count('WLRQ')>=1,'fixture: an ordinary reconciliation request was sent')
assert(P.Count('WLRD')==0,'no path emits a withdrawal while its order is unproved')
assert((A.e.Nexus.Sync.ResponseStats().tombstoneWireRefused or 0)>=1,'responder reached the local tombstone and refused it, instead of never looking')
Intact('receiver keeps the exact row: remote withdrawal is not claimed')
assert(A.e.Nexus.BuildCatalog.TombstoneState(id).state=='CURRENT_DENY','the local tombstone is unchanged by the refused wire')
print('PASS Stop Sharing is zero-wire on the originating and the responder path; remote row remains')

-- A reservation that already exists is preserved exactly. It is seeded through
-- the catalog owner, as an earlier client version stored it; no wire path
-- creates one any more.
local owner=C.Get(id).ownerKey
local seeded={stamp=revision,author=A.name,ownerKey=owner,ownerVerified=true}
local stored,why,ticket=C.SetTombstone(id,seeded,{source='remote',sender=A.name})
assert(stored==true or (stored==nil and type(ticket)=='table'),'fixture: existing remote reservation seeded: '..tostring(why))
P.Until(function()return P.Ready(B) and C.TombstoneState(id).state=='OPAQUE_BLOCK_ALL' end)
assert(C.Get(id)==nil and B.e.NexusDB.authorityBundle.communityBuilds[id]~=nil,'the existing reservation hides the row and retains its raw contents')
local refused=B.e.Nexus.Sync.Stats().withdrawalOrderRefused
Delete(A.name,revision)
assert(C.TombstoneState(id).state=='OPAQUE_BLOCK_ALL' and B.e.Nexus.Sync.Stats().withdrawalOrderRefused==refused,'an exact replay of an existing reservation stays an idempotent no-op')
Delete(A.name,revision+5)
assert(C.TombstoneState(id).state=='OPAQUE_BLOCK_ALL' and C.TombstoneState(id).stamp==revision,'an unequal replay changes nothing')
A.H.Advance(10,.05);A.e.SlashCmdList.NEXUS('sync');B.H.Advance(10,.05);B.e.SlashCmdList.NEXUS('sync');P.Advance(60)
assert(C.Get(id)==nil and C.TombstoneState(id).state=='OPAQUE_BLOCK_ALL','the existing reservation still denies inbound rows for its ID')
assert(#A.H.actions==0 and #B.H.actions==0,'zero gameplay mutation')
print('PASS an existing reservation is preserved: replay is a no-op, conflict changes nothing, inbound rows stay denied')
