-- Busy-receiver admission: a Catalog.Put refusal without a ticket is not an
-- accepted operation and is not a verdict on a valid inbound summary.
local A=dofile('tests/prototype/sync_admission_support.lua');local T=A.T
T.SingleSlicePacing()
local function Stats()return Nexus.Sync.Stats()end
local function Deferred()return Nexus.Sync.WorkState().deferredAdmissions end

-- 1. Exact retained identity, one submission, truthful terminal commit.
local H,C=A.Boot();A.Hold(C)
local id='deferred-summary-1'
local sent=A.Receive(id,'Peer',A.base+10,'Deferred exact summary')
assert(H.puts[id].calls==1 and H.puts[id].refused==1 and H.puts[id].accepted==0
 and H.puts[id].lastRefusal=='ROOT_MUTATION_PENDING','fixture reaches the real ticketless busy refusal')
assert(Stats().storageRejected==0 and Stats().admissionDeferred==1 and Deferred()==1,'busy refusal retains one bounded deferred item instead of a storage failure')
assert(C.Get(id)==nil and Stats().received==0,'a deferred item is neither a committed row nor a counted receipt')
local status,_,total=Nexus.Sync.GetLeaderboardSyncStatus()
assert(status~='idle' and total>0,'deferred inbound work cannot be reported as idle')
A.Receive(id,'Peer',A.base+10,'Deferred exact summary')
A.Receive(id,'Peer',A.base+5,'Older replay')
assert(Deferred()==1 and Stats().admissionDeferred==1 and Stats().admissionSuperseded==0,'exact duplicate and older replay keep the one retained item')
assert(C.Get(id)==nil and H.puts[id].accepted==0,'replays while busy own no ticket')
T.Until(H,function()return C.Get(id)~=nil end)
local row=C.Get(id)
assert(row.title=='Deferred exact summary' and row.ownerKey==sent.o and row.lastModified==A.base+10
 and row.author=='Peer-Ebonhold' and row.isMine~=true,'committed row has the exact retained sender, owner, revision and title')
assert(C.Get('admission-holder')~=nil,'the earlier transaction committed normally')
A.Settled(H,C)
assert(H.puts[id].accepted==1 and Stats().admissionResolved==1 and Deferred()==0,'exactly one accepted submission settled the retained item')
assert(Stats().storageRejected==0 and Stats().admissionExpired==0 and Stats().received>=2,'receipt is counted only from the committed ticket')
local calls=H.puts[id].calls;H.Advance(10,.05)
assert(H.puts[id].calls==calls and #H.actions==0,'no resubmission after the terminal commit and no gameplay action')
print('PASS busy inbound summary is retained once, submitted once, and committed exactly')

-- 2. A newer revision from the same verified owner replaces the retained item.
H,C=A.Boot();A.Hold(C);id='deferred-summary-2'
A.Receive(id,'Peer',A.base+10,'First revision','a1')
A.Receive(id,'Peer',A.base+20,'Second revision','b2')
assert(Deferred()==1 and Stats().admissionSuperseded==1,'newer same-owner revision supersedes in place')
A.Receive(id,'Peer',A.base+20,'Second revision conflicting','c3')
assert(Deferred()==1 and Stats().admissionSuperseded==1,'equal revision with different content cannot replace the retained item')
T.Until(H,function()return C.Get(id)~=nil end);A.Settled(H,C)
row=C.Get(id)
assert(row.lastModified==A.base+20 and row.title=='Second revision' and row.fingerprintHash=='b2','only the newest retained revision commits')
assert(H.puts[id].accepted==1,'superseded revision was never submitted')
print('PASS update while deferred keeps one item and commits only the newest revision')

-- 3. A different owner cannot take over a retained ID.
H,C=A.Boot();A.Hold(C);id='deferred-summary-3'
local owner=A.Receive(id,'Peer',A.base+10,'Rightful first claim')
A.Receive(id,'Mallory',A.base+99,'Takeover attempt')
assert(Deferred()==1,'foreign owner claim is refused, not queued')
T.Until(H,function()return C.Get(id)~=nil end);A.Settled(H,C)
row=C.Get(id)
assert(row.ownerKey==owner.o and row.title=='Rightful first claim' and row.lastModified==A.base+10,'retained owner and revision are unchanged by the foreign claim')
print('PASS wrong-owner claim cannot displace a deferred item')

-- 4. Submission revalidates against the then-current catalog.
H,C=A.Boot();id='deferred-summary-4'
local first=A.Hold(C,id,'Holder',A.base+10)
A.Receive(id,'Peer',A.base+50,'Different owner, same ID')
assert(Deferred()==1 and C.Get(id)==nil,'fixture: same-ID item from another owner waits behind the first transaction')
T.Until(H,function()return C.Get(id)~=nil end);A.Settled(H,C)
row=C.Get(id)
assert(row.ownerKey==first.o and row.lastModified==A.base+10,'owner recheck at submission refuses the later foreign revision')
assert(H.puts[id].accepted==1 and Stats().admissionResolved==1 and Deferred()==0,'refused revalidation is terminal and submits nothing')
H,C=A.Boot();id='deferred-summary-5'
A.Hold(C,id,'Peer',A.base+50)
A.Receive(id,'Peer',A.base+10,'Reordered older revision')
assert(Deferred()==1,'fixture: reordered older revision waits behind the newer transaction')
T.Until(H,function()return C.Get(id)~=nil end);A.Settled(H,C)
assert(C.Get(id).lastModified==A.base+50 and H.puts[id].accepted==1,'stale recheck at submission keeps the newer committed revision')
print('PASS submission rechecks owner and revision; stale and foreign items settle without a write')

-- 5. Expiry is a truthful storage failure, never a receipt.
H,C=A.Boot(60);A.Hold(C);id='deferred-summary-6'
A.Receive(id,'Peer',A.base+10,'Will expire')
assert(Deferred()==1 and not C.ManualPreparationStatus().ready,'fixture: item deferred behind long catalog work')
H.now=H.now+301;Nexus.Sync.Housekeep()
assert(Deferred()==0 and Stats().admissionExpired==1 and Stats().storageRejected==1,'expired wait settles once as a storage refusal')
A.Settled(H,C)
assert(C.Get(id)==nil and H.puts[id].accepted==0 and H.puts[id].calls==1,'expired item is never submitted or stored')
print('PASS expired deferred item is a terminal storage failure')

-- 5b. The deadline is fixed per item and is never extended by continuing
-- catalog work. Since waiting items are now committed as one batch when the
-- catalog frees, two items behind one transaction are both served; the
-- starvation case of one-at-a-time submission no longer occurs at this size.
-- What must stay exact is the lifetime itself: 300 seconds from each item's
-- own arrival, unchanged while the catalog works, and 5a keeps the terminal
-- expiry case.
H,C=A.Boot(100);A.Hold(C)
local firstId,lateId='deferred-summary-6a','deferred-summary-6b'
A.Receive(firstId,'Peer',A.base+10,'Ahead in the queue')
H.Advance(7,.05)
A.Receive(lateId,'PeerTwo',A.base+10,'Arrives seven seconds later')
assert(Deferred()==2,'fixture: two items wait behind real catalog work')
local pumps=C.ManualPreparationStatus().totalPumps
local function Retained()
 local rows={}
 for _,row in ipairs(Nexus.Sync.AdmissionSnapshot().entries)do rows[tostring(row.id)]=row end
 return rows
end
local before=Retained()
assert(before[firstId] and before[lateId],'fixture: both items are retained')
assert(before[firstId].expiresAt-before[firstId].enqueuedAt==300
 and before[lateId].expiresAt-before[lateId].enqueuedAt==300,'each lifetime is the fixed 300 seconds from its own arrival')
assert(before[lateId].enqueuedAt>=before[firstId].enqueuedAt,'the later item did not arrive before the earlier one')
T.Until(H,function()return H.now>=before[firstId].enqueuedAt+60 end)
local during=Retained()
local working=C.ManualPreparationStatus()
assert(working.totalPumps>pumps+1000,'fixture: the catalog kept working through the wait')
for _,id in ipairs({firstId,lateId})do
 if during[id] then
  assert(during[id].expiresAt==before[id].expiresAt and during[id].enqueuedAt==before[id].enqueuedAt,
   id..': its deadline was not extended or restarted by the continuing work')
 else
  assert(C.Get(id)~=nil,id..': it left the queue only by being committed')
 end
end
assert(Stats().admissionExpired==0,'no item expired before its own deadline')
T.Until(H,function()return C.Get(firstId)~=nil and C.Get(lateId)~=nil end,40000)
-- An expired item is removed and never submitted, so a commit is itself the
-- proof that each item was served inside its own unchanged lifetime.
assert(Stats().admissionExpired==0,'neither item expired: both were served inside their own lifetimes')
assert(Deferred()==0,'no retained item outlives its deadline')
T.Until(H,function()return C.ManualPreparationStatus().ready end,40000);H.Advance(5,.05)
for _,id in ipairs({firstId,lateId})do
 assert(C.Get(id)~=nil,id..': it was stored')
 assert(H.puts[id].accepted==1,id..': exactly one accepted submission, on either route')
end
assert(Stats().storageRejected==0 and Stats().admissionExpired==0,'nothing was refused or expired')
print('PASS fixed per-item deadline: two retained items keep their own unchanged lifetimes and are served inside them')

-- 6. Explicit reset cancels retained items.
H,C=A.Boot();A.Hold(C);id='deferred-summary-7'
A.Receive(id,'Peer',A.base+10,'Will be reset')
assert(Deferred()==1)
Nexus.Sync.Init(Nexus.Codec,Nexus.GameAdapter)
assert(Deferred()==0,'explicit reset owns no retained inbound item')
T.Until(H,function()return C.ManualPreparationStatus().ready end);H.Advance(10,.05)
assert(C.Get(id)==nil and H.puts[id].accepted==0,'reset item is never submitted')
print('PASS explicit reset cancels deferred admission')

-- 6b. A retained item never crosses into another player, database or binding.
for _,change in ipairs({'database','binding','owner'})do
 H,C=A.Boot();A.Hold(C);id='deferred-summary-scope-'..change
 A.Receive(id,'Peer',A.base+10,'Scoped before '..change..' change')
 assert(Deferred()==1,'fixture: item retained before the scope change')
 if change=='database' then NexusDB=H.Clone(NexusDB);C.BeginRootAdmission(NexusDB,Nexus.BundledBuilds)
 elseif change=='binding' then C.BeginRootAdmission(NexusDB,Nexus.BundledBuilds)
 else UnitName=function()return 'DifferentPlayer','Ebonhold' end end
 -- A rebind also fails the earlier holder's own ticket; count only this item.
 local refusedBefore=Stats().storageRejected
 Nexus.Sync.Housekeep()
 assert(Deferred()==0 and Stats().admissionCancelled==1 and Stats().storageRejected==refusedBefore+1,'scope change cancels the item at once as a storage refusal: '..change)
 if change~='owner' then
  T.Until(H,function()return C.ManualPreparationStatus().ready end)
  H.Advance(20,.05);T.Until(H,function()return C.ManualPreparationStatus().ready end)
 else H.Advance(20,.05) end
 assert(C.Get(id)==nil and H.puts[id].accepted==0 and H.puts[id].calls==1,'cancelled item is never submitted into the new scope: '..change)
 print('PASS deferred item cancelled on '..change..' change; no cross-scope write')
end

-- 7. Bounds: per-sender and total caps fail as ordinary storage refusals.
H,C=A.Boot();A.Hold(C)
for i=1,17 do A.Receive('bounded-'..i,'Peer',A.base+i) end
assert(Deferred()==16 and Stats().admissionOverflow==1 and Stats().storageRejected==1,'seventeenth item from one sender is refused, not queued')
print('PASS deferred admission is bounded per sender')
