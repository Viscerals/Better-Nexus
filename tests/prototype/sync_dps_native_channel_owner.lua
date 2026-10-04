-- Real WLD2 ingress retains only authenticated native channel authority.
-- Synthetic identities/packets; no live client, account data or network.
local P=dofile('tests/prototype/sync_pair_support.lua')
local failures,checks={},0
local function check(v,m)
 checks=checks+1;print((v and 'PASS ' or 'FAIL ')..m)
 if not v then failures[#failures+1]=m end
end
local function Boot()
 P.Boot({'Receiver','Idle'},0,nil,{realm='TestRealm'})
 return P.A.e.Nexus,P.A
end
local function Payload(N,category,score)
 local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
 return {v=7,p='Origin',o='origin@testrealm',r='TestRealm',k='MAGE',l=80,
  c=category or 'dummy',d=score or 47000,u=180,t=P.A.e.time()-100,
  e=echoes,f=N.DpsCapture.GetEchoKey(echoes),h=N.DpsCapture.GetEchoHash(echoes),
  lk={{spellId=200085,count=1}}}
end
local function Settle(peer)
 for _=1,300 do peer.H.Advance(.05,.05) end
end
local function Deliver(N,peer,payload,route,actual,declared,beforeChunk)
 local encoded=N.Codec.Base64Encode(N.Codec.JSONEncode(payload))
 local half=math.floor(#encoded/2)
 if route=='addon' then
  peer.H.Fire('CHAT_MSG_ADDON',N.SyncWire.PREFIX,'ACK1','WHISPER',actual)
 end
 for index,chunk in ipairs({encoded:sub(1,half),encoded:sub(half+1)}) do
  if beforeChunk then route=beforeChunk(index,peer) or route end
  local wire=string.format('WLD2|%s|Origin:%d:%d|%d/2|%s',
   declared or 'Origin',payload.t,payload.d,index,chunk)
  if route=='native' then P.Channel(peer,wire,actual)
  elseif route=='addon' then
   peer.H.Fire('CHAT_MSG_ADDON',N.SyncWire.PREFIX,'P7:'..wire,'WHISPER',actual)
  else N.Sync.HandleIncoming(wire,actual) end
 end
 Settle(peer)
 return N.DpsCapture.GetCharacterBest(payload.c,'Origin')
end
for _,case in ipairs({
 {name='native bare actual and bare header',route='native',actual='Origin'},
 {name='native qualified actual and bare header',route='native',actual='Origin-TestRealm'},
 {name='addon qualified actual and bare header',route='addon',actual='Origin-TestRealm'},
 {name='qualified actual and qualified header control',route='native',actual='Origin-TestRealm',declared='Origin-TestRealm'},
}) do
 local N,peer=Boot()
 local payload=Payload(N)
 local row=Deliver(N,peer,payload,case.route,case.actual,case.declared)
 check(row and row.dps==47000,case.name..': exact score stored')
 check(row and N.DpsCapture.VerifiedOwnerKey(row)=='origin@testrealm',
  case.name..': authenticated owner retained')
 if row then
  print('OBSERVED '..case.name..' ownerVerified='..tostring(row.ownerVerified)
   ..' ownerKey='..tostring(row.ownerKey)..' relaySender='..tostring(row.relaySender))
 end
 local other=Payload(N,'lk',46000)
 Deliver(N,peer,other,case.route,case.actual,case.declared)
 local dummy=N.DpsCapture.GetDpsBoard('dummy')
 local lk=N.DpsCapture.GetDpsBoard('lk')
 local pairs=N.CandidateEvidence.RealDpsPairs(dummy,lk)
 check(#pairs==1,case.name..': matching verified records form Both pair')
 check(#peer.H.actions==0,case.name..': zero gameplay actions')
end
for _,case in ipairs({
 {name='mismatched actual sender',route='native',actual='Impostor-TestRealm',empty=true},
 {name='unknown bare route cannot borrow realm',route='unknown',actual='Origin',unverified=true},
 {name='bare addon cannot borrow realm',route='addon',actual='Origin',unverified=true},
}) do
 local N,peer=Boot()
 local row=Deliver(N,peer,Payload(N),case.route,case.actual)
 if case.empty then check(row==nil,case.name..': no record stored')
 else check(row and N.DpsCapture.VerifiedOwnerKey(row)==nil,case.name..': no verified authority') end
end
-- Native authority is scoped to the whole transfer, not its last chunk.
for _,case in ipairs({
 {name='mixed native and unknown chunks',before=function(i)
  return i==2 and 'unknown' or 'native' end},
 {name='native realm changes between chunks',before=function(i,peer)
  peer.e.GetNormalizedRealmName=function()return i==2 and 'OtherRealm' or 'TestRealm' end
 end},
 {name='native realm is missing',before=function(_,peer)
  peer.e.GetNormalizedRealmName=nil;peer.e.GetRealmName=nil
 end},
 {name='native realm is invalid',before=function(_,peer)
  peer.e.GetNormalizedRealmName=function()return 'bad@realm' end
 end},
}) do
 local N,peer=Boot()
 local row=Deliver(N,peer,Payload(N),'native','Origin',nil,case.before)
 check(row==nil,case.name..': nothing stored')
end

-- Contradictory claims and payload verification flags never grant authority.
for _,case in ipairs({
 {name='payload owner has a different realm',alter=function(p)p.o='origin@otherrealm';p.r='OtherRealm' end},
 {name='payload owner has a different player',alter=function(p)p.o='impostor@testrealm' end},
 {name='payload verification flag',alter=function(p)p.ownerVerified=true end},
 {name='qualified sender has a different realm',actual='Origin-OtherRealm'},
}) do
 local N,peer=Boot();local payload=Payload(N)
 if case.alter then case.alter(payload) end
 local row=Deliver(N,peer,payload,'native',case.actual or 'Origin')
 check(not row or N.DpsCapture.VerifiedOwnerKey(row)==nil,
  case.name..': no verified owner')
end

-- An exact direct-owner replay can promote a matching old unverified row.
-- Neither startup nor a Sync request is allowed to invent that proof.
do
 local N,peer=Boot();local payload=Payload(N)
 local old=Deliver(N,peer,payload,'unknown','Origin')
 check(old and N.DpsCapture.VerifiedOwnerKey(old)==nil,'legacy row starts unverified')
 Settle(peer)
 check(N.DpsCapture.VerifiedOwnerKey(old)==nil,'idle work does not promote legacy row')
 local row=Deliver(N,peer,payload,'native','Origin')
 check(row and N.DpsCapture.VerifiedOwnerKey(row)=='origin@testrealm','same-score owner replay promotes exact row')
 check(row and row.dps==47000 and row.ts==payload.t,'promotion preserves score and timestamp')
 local duplicate=Deliver(N,peer,payload,'native','Origin')
 check(duplicate and duplicate.dps==47000,'duplicate retains score')
 local stale=Payload(N,nil,99000);stale.t=payload.t-1
 Deliver(N,peer,stale,'native','Impostor','Impostor')
 row=N.DpsCapture.GetCharacterBest('dummy','Origin','origin@testrealm')
 check(row and row.dps==47000,'unauthorized relay cannot replace verified row')
 local lower=Payload(N,nil,46000);lower.t=payload.t+1
 Deliver(N,peer,lower,'native','Origin')
 row=N.DpsCapture.GetCharacterBest('dummy','Origin','origin@testrealm')
 check(row and row.dps==47000,'newer lower result cannot replace verified best')
 local higher=Payload(N,nil,48000);higher.t=payload.t+2
 row=Deliver(N,peer,higher,'native','Origin')
 check(row and row.dps==48000,'same authenticated owner higher result replaces best')
 local F=peer.e.dofile('tests/prototype/format5_support.lua')
 local serialized=F.Serialize(peer.e.NexusDB)
 peer.e.NexusDB=assert(loadstring('return '..serialized))()
 peer=P.Rejoin(1);N=peer.e.Nexus;Settle(peer)
 row=N.DpsCapture.GetCharacterBest('dummy','Origin','origin@testrealm')
 check(row and row.dps==48000 and row.ts==higher.t
  and N.DpsCapture.VerifiedOwnerKey(row)=='origin@testrealm',
  'serialized reload preserves exact score and verified transport provenance')
 -- Durable authority is sufficient for a bounded response relay, but not
 -- for an unsolicited broadcast pretending this peer is the record owner.
 local record=N.DpsCapture.MaterializeRecord(row)
 record.category='dummy'
 local unsolicited,unsolicitedWhy=N.Sync.BroadcastDpsRecord(record)
 check(unsolicited==false and unsolicitedWhy=='owner_sender',
  'foreign verified row cannot unsolicited-broadcast')
 record._originVerified=true
 local emitted,why=N.Sync.BroadcastDpsRecord(record,nil,true,
  {requester='Requester-TestRealm',requestId='native-dps-proof',
   bucket=N.DpsCapture.SyncBucket('dummy','Origin')})
 check(emitted==true,'verified received evidence is relay-eligible in response context: '..tostring(why))
end

-- Older supported wire representations retain their existing direct-owner
-- admission. Unsupported versions and bare unknown routes do not gain proof.
for _,version in ipairs({2,5,6,7,8}) do
 local N,peer=Boot();local payload=Payload(N);payload.v=version
 local row=Deliver(N,peer,payload,'native','Origin')
 if version<=7 then check(row and N.DpsCapture.VerifiedOwnerKey(row)=='origin@testrealm',
  'supported protocol '..version..' retains native direct authority')
 else check(row==nil,'unsupported protocol is refused') end
end
print('RESULT '..(#failures==0 and 'PASS' or 'FAIL')..' checks='..checks..' failures='..#failures)
assert(#failures==0,table.concat(failures,'; '))
