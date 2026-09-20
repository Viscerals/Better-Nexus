-- Busy-receiver admission: a Catalog.Put refusal without a ticket is not an
-- accepted operation and is not a verdict on a valid inbound summary.
local A=dofile('tests/prototype/sync_admission_support.lua');local T=A.T
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

-- 5b. The deadline is fixed per item. Continuing catalog work does not extend it.
H,C=A.Boot(100);A.Hold(C)
local firstId,lateId='deferred-summary-6a','deferred-summary-6b'
A.Receive(firstId,'Peer',A.base+10,'Ahead in the queue')
A.Receive(lateId,'PeerTwo',A.base+10,'Expires while the catalog works')
assert(Deferred()==2,'fixture: two items wait behind long catalog work')
local enqueued,pumps=H.now,C.ManualPreparationStatus().totalPumps
T.Until(H,function()return H.now>=enqueued+299 end)
assert(Deferred()>=1 and Stats().admissionExpired==0,'no item expires before its own fixed deadline')
T.Until(H,function()return H.now>=enqueued+301 end)
local working=C.ManualPreparationStatus()
assert(not working.ready and working.totalPumps>pumps+1000,'fixture: the catalog kept working through the whole wait')
assert(C.Get(lateId)==nil and Stats().admissionExpired>=1 and Stats().storageRejected==Stats().admissionExpired,'an item whose turn did not come expires as a storage refusal while other catalog work continues')
assert(Deferred()==0,'no retained item outlives its deadline')
T.Until(H,function()return C.ManualPreparationStatus().ready end,40000);H.Advance(5,.05)
assert(C.Get(lateId)==nil and H.puts[lateId].accepted==0,'expired item is never submitted or stored later')
local firstRow=C.Get(firstId)
assert((firstRow~=nil)==(H.puts[firstId].accepted==1),'the earlier item is stored only if its one submission was accepted before its deadline')
print('PASS fixed per-item deadline expires during continuing catalog work (earlier item stored='..tostring(firstRow~=nil)..')')

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
