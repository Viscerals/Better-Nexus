-- A busy receiver must retain a valid Share summary and its full record, then
-- commit the exact three-copy source once. Both directions, plus an owner
-- update of the same ID and a repeated ordinary request.
local P=dofile('tests/prototype/sync_pair_support.lua')
local A,B=P.Boot({'PairAlpha','PairBeta'})
local function Accepted(put)return put.ok==true or (put.ok==nil and put.ticket)end
for _,p in ipairs({A,B})do
 -- Observe only; every result passes through unchanged.
 p.puts={};local original=p.e.Nexus.BuildCatalog.Put
 p.e.Nexus.BuildCatalog.Put=function(row,options,...)
  local ok,why,ticket=original(row,options,...)
  p.puts[#p.puts+1]={id=row.id,stamp=row.lastModified,full=type(row.echoes)=='table' and #row.echoes>0,
   ok=ok,why=why,ticket=type(ticket)=='table'}
  return ok,why,ticket
 end
end
local contention=0
-- A valid unrelated third-party summary through the real receive callback
-- makes the receiver busy exactly when the summary and full record arrive.
P.before=function(p,q,code)
 if code~='WLBI' and code~='WLRB' then return end
 if not P.Ready(q) then return end
 contention=contention+1
 local data={id='pair-contention-'..contention,t='Synthetic contention',a='Other-Ebonhold',
  o=q.e.Nexus.Identity.OwnerKey('Other','Ebonhold'),c='MAGE',m=q.e.time(),h='a1',n=3}
 P.Channel(q,'WLBI|Other-Ebonhold|'..q.e.Nexus.Codec.Base64Encode(q.e.Nexus.Codec.JSONEncode(data)),'Other-Ebonhold')
 assert(not P.Ready(q),'contention owns the receiver catalog')
end
local function Writes(p,id,stamp)
 local refusedSummary,refusedFull,acceptedSummary,acceptedFull=0,0,0,0
 for _,put in ipairs(p.puts)do
  if put.id==id and (stamp==nil or put.stamp==stamp) then
   if not Accepted(put) then assert(put.why=='ROOT_MUTATION_PENDING','only the real busy refusal is expected') end
   if put.full then
    if Accepted(put) then acceptedFull=acceptedFull+1 else refusedFull=refusedFull+1 end
   else
    if Accepted(put) then acceptedSummary=acceptedSummary+1 else refusedSummary=refusedSummary+1 end
   end
  end
 end
 return refusedSummary,refusedFull,acceptedSummary,acceptedFull
end
local function Transfer(from,to,title)
 local id=P.Post(from,title)
 P.Until(function()return P.Full(to,id)end)
 local source,row=from.e.Nexus.BuildCatalog.Get(id),P.Full(to,id)
 assert(#row.echoes==1 and row.echoes[1].spellId==200001 and row.echoes[1].quality==1 and row.echoes[1].stacks==3,'receiver commits the exact three-copy source')
 assert(row.id==id and row.ownerKey==source.ownerKey and row.lastModified==source.lastModified and row.title==title and row.isMine~=true,'receiver owner, revision and title match the source')
 local refusedSummary,refusedFull,acceptedSummary,acceptedFull=Writes(to,id)
 assert(refusedSummary>=1 and refusedFull>=1,'fixture reached the real busy refusal for both the summary and the full record')
 assert(acceptedSummary==1 and acceptedFull==1,'each retained item was submitted exactly once')
 local stats=to.e.Nexus.Sync.Stats()
 assert(stats.storageRejected==0 and stats.malformedRejected==0 and stats.admissionExpired==0 and stats.admissionOverflow==0,'busy refusals were deferred, never reported as storage or schema failures')
 P.Until(function()return P.Ready(to) and to.e.Nexus.Sync.WorkState().deferredAdmissions==0 end)
 return id
end
local idA=Transfer(A,B,'NEXUS-TEST-PAIR-A-TO-B')
print('PASS busy receiver A to B: summary and full record deferred, each submitted once, exact commit')
local idB=Transfer(B,A,'NEXUS-TEST-PAIR-B-TO-A')
assert(idB~=idA,'reverse direction uses a separately identified record')
print('PASS busy receiver B to A: separately identified record, exact commit')

-- Owner update of the same ID through the real owner operation.
P.Until(function()return P.Ready(A)end)
local before=P.Full(B,idA).lastModified
local ok=A.e.Nexus.CommunityBuilds.EditBuild(idA,'NEXUS-TEST-PAIR-A-TO-B','Updated description through the owner path')
assert(ok,'owner edit accepted')
P.Until(function()local row=P.Full(B,idA);return row and row.description=='Updated description through the owner path' end)
local updated,source=P.Full(B,idA),A.e.Nexus.BuildCatalog.Get(idA)
assert(updated.lastModified==source.lastModified and updated.lastModified>before and updated.ownerKey==source.ownerKey,'receiver commits the exact newer owner revision')
assert(updated.echoes[1].stacks==3 and #updated.echoes==1,'update preserves the exact three-copy contents')
local _,_,_,fullWrites=Writes(B,idA,updated.lastModified)
assert(fullWrites==1,'the updated revision was written exactly once')
print('PASS busy receiver commits the owner update of the same ID once')

-- Ordinary repeated request: no duplicate row, no second write.
P.Until(function()return P.Ready(B) and B.e.Nexus.Sync.WorkState().deferredAdmissions==0 end)
local function AcceptedWrites(p,id)local n=0;for _,put in ipairs(p.puts)do if put.id==id and Accepted(put)then n=n+1 end end;return n end
local writesA,writesB=AcceptedWrites(B,idA),AcceptedWrites(A,idB)
B.H.Advance(10,.05);B.e.SlashCmdList.NEXUS('sync');P.Advance(60)
assert(AcceptedWrites(B,idA)==writesA and AcceptedWrites(A,idB)==writesB,'repeated ordinary request causes no second write of a committed revision')
B.e.Nexus.CommunityBuilds.Show()
local frame=assert(B.e.NexusCommunityBuildsFrame)
if frame._scopeBtn:IsEnabled()then frame._scopeBtn:Click()end
if frame._qualifiedBtn:GetText()~='All Shared'then frame._qualifiedBtn:Click()end
frame._searchBox:SetText('NEXUS-TEST-PAIR-A-TO-B')
frame._searchBox:GetScript('OnTextChanged')(frame._searchBox,true)
P.Until(function()
 local view=B.e.Nexus.CommunityBuilds.DiagnosticSnapshot()
 return view.projectionCurrent and view.resultCount==1 and view.displayedCount==1
end)
local rows=assert(B.e.Nexus.ViewProjections.Builds({scope='all',currentClassOnly=true,qualifiedOnly=false,search='NEXUS-TEST-PAIR-A-TO-B',sortMode='dps'}))
assert(#rows==1 and rows[1].id==idA,'receiver projection lists the exact ID once')
assert(P.Count('WLRD')==0 and #A.H.actions==0 and #B.H.actions==0,'no withdrawal wire and zero gameplay mutation')
print('PASS repeated ordinary request leaves one exact row and no duplicate write')
