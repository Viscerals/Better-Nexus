-- Remote withdrawal stays unsupported while protocol 7 proves no edit/delete
-- order. These checks hold the refusal consistently: a stale or foreign WLRD
-- hides nothing, and no local path emits a WLRD.
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
assert(B.e.Nexus.Sync.Stats().malformedRejected==malformed and B.e.Nexus.Sync.Stats().storageRejected==storage,'a stale withdrawal is a benign skip, not a malformed or storage failure')
print('PASS stale, replayed and reordered same-owner withdrawals leave the newer row visible')
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

-- Retained handling, stated as a limit and not as proof of order: an older
-- peer's direct-owner WLRD at or after the stored revision still reserves the
-- ID. The raw row is retained and hidden; nothing is deleted.
Delete(A.name,revision)
assert(C.Get(id)==nil and C.TombstoneState(id).state=='OPAQUE_BLOCK_ALL','established direct-owner handling is unchanged for an equal stamp')
assert(B.e.NexusDB.authorityBundle.communityBuilds[id]~=nil,'the opaque reservation hides the row and retains its raw contents')
assert(#A.H.actions==0 and #B.H.actions==0,'zero gameplay mutation')
print('PASS legacy direct-owner withdrawal handling is retained unchanged at an equal stamp')
