-- An item retained in an earlier catalog scope is not a prior claim in the new
-- one. A fresh valid receipt of the same ID and revision that arrives after a
-- scope change, and before any housekeeping turn, must be admitted there.
-- The paired part runs first: each peer copies the process globals at boot, so
-- they must not yet hold a single-runtime harness.
-- Full record, through two real runtimes.
local P=dofile('tests/prototype/sync_pair_support.lua')
local A,B=P.Boot({'ScopeAlpha','ScopeBeta'},0)
local C=B.e.Nexus.BuildCatalog
local full={calls=0,accepted=0};local held,chunks=0,{}
local put=C.Put
C.Put=function(row,options,...)
 local ok,why,ticket=put(row,options,...)
 if type(row.echoes)=='table' and #row.echoes>0 then
  full.calls=full.calls+1
  if ok==true or (ok==nil and type(ticket)=='table')then full.accepted=full.accepted+1 end
 end
 return ok,why,ticket
end
P.before=function(p,q,code)
 if q~=B or code~='WLRB' then return end
 chunks[#chunks+1]=p.H.sent[p.cursor].text
 if not P.Ready(B) then return end
 held=held+1
 local data={id='scope-full-holder-'..held,t='Synthetic holder',a='Other-Ebonhold',o=B.e.Nexus.Identity.OwnerKey('Other','Ebonhold'),c='MAGE',m=B.e.time(),h='a1',n=3}
 P.Channel(B,'WLBI|Other-Ebonhold|'..B.e.Nexus.Codec.Base64Encode(B.e.Nexus.Codec.JSONEncode(data)),'Other-Ebonhold')
end
local id=P.Post(A,'NEXUS-TEST-FULL-NEW-SCOPE')
P.Until(function()return #chunks>0 and full.calls>0 and B.e.Nexus.Sync.WorkState().deferredAdmissions==1 end)
assert(full.accepted==0 and P.Full(B,id)==nil,'fixture: the real full record was refused without a ticket and retained')
C.BeginRootAdmission(B.e.NexusDB,B.e.Nexus.BundledBuilds)
-- The same full record arrives again before any housekeeping turn, on the
-- channel route as a second responder would send it. In this window the
-- established ShouldStore session cache already holds this revision and the
-- catalog root is not serving reads, so the record is skipped as a duplicate
-- before admission. That is unchanged baseline behavior. What must hold here:
-- nothing from the old scope is written, its cancellation is truthful, and
-- the record commits exactly once through a normal later exchange.
for _,text in ipairs(chunks)do P.Channel(B,(text:gsub('^P%d+:','')),A.name)end
assert(full.accepted==0,'no full-record write happens from the re-receipt during the scope change')
B.e.Nexus.Sync.Housekeep()
local stats=B.e.Nexus.Sync.Stats()
assert(stats.admissionCancelled==1 and B.e.Nexus.Sync.WorkState().deferredAdmissions==0,'the old-scope full record is cancelled as a storage refusal')
P.before=nil
B.T.Until(B.H,function()return P.Ready(B)end)
assert(full.accepted==0 and P.Full(B,id)==nil,'the cancelled item was never submitted into the new scope')
B.H.Advance(10,.05);B.e.SlashCmdList.NEXUS('sync')
P.Until(function()return P.Full(B,id)~=nil end)
local row,source=P.Full(B,id),A.e.Nexus.BuildCatalog.Get(id)
assert(#row.echoes==1 and row.echoes[1].spellId==200001 and row.echoes[1].quality==1 and row.echoes[1].stacks==3,'a normal later exchange commits the exact three-copy record in the new scope')
assert(row.ownerKey==source.ownerKey and row.lastModified==source.lastModified,'owner and revision match the source')
assert(full.accepted==1,'exactly one accepted full-record write, in the new scope only')
assert(#A.H.actions==0 and #B.H.actions==0,'zero gameplay mutation')
print('PASS old-scope full record is cancelled, never written across the binding change, and commits once later')

-- Summary, single runtime.
local S=dofile('tests/prototype/sync_admission_support.lua');local T=S.T
for _,mode in ipairs({'database','binding'})do
 local H,C=S.Boot();S.Hold(C)
 local id,stamp='scope-arrival-'..mode,S.base+10
 local sent=S.Receive(id,'Peer',stamp,'Exact new scope receipt')
 assert(Nexus.Sync.WorkState().deferredAdmissions==1,'fixture: summary retained in the first scope')
 if mode=='database' then NexusDB=H.Clone(NexusDB)end
 C.BeginRootAdmission(NexusDB,Nexus.BundledBuilds)
 -- No Housekeep or OnUpdate turn runs before the fresh receipt.
 S.Receive(id,'Peer',stamp,'Exact new scope receipt')
 local stats=Nexus.Sync.Stats()
 assert(stats.admissionCancelled==1,'the old-scope item was cancelled before comparison, as a storage refusal')
 assert(Nexus.Sync.WorkState().deferredAdmissions==1 and stats.admissionDeferred==2,'the fresh receipt is retained in the new scope, not called a duplicate')
 T.Until(H,function()return C.Get(id)~=nil end)
 local row=C.Get(id)
 assert(row.ownerKey==sent.o and row.lastModified==stamp and row.title=='Exact new scope receipt','the new scope commits the exact receipt')
 assert(H.puts[id].accepted==1,'exactly one submission, in the new scope only')
 T.Until(H,function()return C.ManualPreparationStatus().ready and Nexus.Sync.WorkState().deferredAdmissions==0 end)
 H.Advance(10,.05)
 assert(H.puts[id].accepted==1 and #H.actions==0,'no second write and no gameplay action')
 print('PASS fresh summary after '..mode..' change is admitted in the new scope; old item cancelled')
end
