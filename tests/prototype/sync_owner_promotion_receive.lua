-- Synthetic Task 036 fixture. Real channel receive, assembly, admission and
-- Store. No native transport contract is inferred from this offline harness.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
local payload={id='synthetic-owner-promotion',t='Synthetic owner promotion',
 a='Origin-TestRealm',o='Origin@TestRealm',c='MAGE',m=1700000200,
 e={{200001,1,3},{200002,2,1}}}
local encoded
local function Run(actual,expected,route,verifiedSeed)
 P.Boot({'Receiver','Idle'},0)
 local peer=P.A
 local N=peer.e.Nexus
 local I,C=N.Identity,N.BuildCatalog
 local b64=N.Codec.Base64Encode(N.Codec.JSONEncode(payload))
 check(encoded==nil or encoded==b64,'all cases use identical full-build bytes')
 encoded=b64
 local split=math.floor(#b64/2)
 local chunks={b64:sub(1,split),b64:sub(split+1)}
 local function Send(sender,declared,index)
  local wire=string.format('WLRB|%s|%s|%d|%d/2|%s',
   declared,payload.id,payload.m,index,chunks[index])
  if route=='addon' then
   peer.H.Fire('CHAT_MSG_ADDON',N.SyncWire.PREFIX,'P7:'..wire,'WHISPER',sender)
  else P.Channel(peer,wire,sender) end
 end
 -- Seed the retained claim through the same receive path, from a relay.
 local seed=verifiedSeed and 'Origin-TestRealm' or 'Relay-TestRealm'
 if route=='addon' then
  peer.H.Fire('CHAT_MSG_ADDON',N.SyncWire.PREFIX,'ACK1','WHISPER',seed)
  peer.H.Fire('CHAT_MSG_ADDON',N.SyncWire.PREFIX,'ACK1','WHISPER',actual)
 end
 Send(seed,seed,1)
 Send(seed,seed,2)
 for _=1,300 do P.Step() end
 local old,source=C.Get(payload.id)
 check(old and (old.ownerVerified==true)==(verifiedSeed==true),'fixture: stored verification state')
 check((old.claimedOwnerKey or old.ownerKey)==I.CanonicalOwnerKey(payload.o),'fixture: canonical retained owner')
 check(old.lockedEchoes==nil and old.lockedAuthorityProven~=true,'fixture: unknown locked roles')
 check(source=='overlay','fixture: retained remote row in saved overlay')
 local snapshot=peer.T.Equal
 local retained={};for k,v in pairs(old) do retained[k]=v end
 local claim=I.CanonicalOwnerKey(old.claimedOwnerKey)
 local stored=I.CanonicalOwnerKey(old.ownerKey)
 local conflict=claim~=nil and stored~=nil and claim~=stored
 local verified=I.VerifiedOwnerKey(old)~=nil
 local match=(claim or stored)==I.CanonicalOwnerKey(payload.o)
 local D=N.PeerDebug
 check(D.Start(),'opt-in boundary trace starts')
 local record=D.Record
 local boundaries={}
 D.Record=function(kind,fields)
  if kind=='owner_boundary' then boundaries[#boundaries+1]=fields end
  return record(kind,fields)
 end
 -- Observe the production identity call without changing its answer.
 local owns=I.TransportOwns
 local observations={}
 I.TransportOwns=function(owner,sender)
  local answer=owns(owner,sender)
  -- Native channel authority may now qualify the bare event sender with the
  -- harness realm Ebonhold. That still cannot prove this TestRealm owner.
  if owner==I.CanonicalOwnerKey(payload.o) and (sender==actual
   or route=='channel' and actual=='Origin' and sender=='Origin-ebonhold') then
   observations[#observations+1]=answer
  end
  return answer
 end
 local received=N.Sync.Stats().received
 local declared=actual=='Origin' and 'Origin-TestRealm' or actual
 Send(actual,declared,1)
 for _=1,20 do P.Step() end
 check(#observations==0,'first chunk does not reach owner admission')
 check(#boundaries==0,'first chunk emits no commit boundary')
 check(snapshot(C.Get(payload.id),retained),'first chunk cannot change the store')
 Send(actual,declared,2)
 for _=1,300 do P.Step() end
 I.TransportOwns=owns
 D.Record=record
 check(#boundaries>0,'completed assembly emits boundary evidence')
 local boundary=boundaries[#boundaries]
 check(boundary.rawSenderQualified==(I.CanonicalOwnerFromTransport(actual)~=nil)
  and boundary.localRealmAvailable==true and boundary.directOwner==expected and boundary.claimMatches==match
  and boundary.storedOwnerConflict==conflict and boundary.existingVerified==verified
  and boundary.sourceKind==source,'diagnostic matches observed identity and stored evidence')
 local fields=0;for _ in pairs(boundary) do fields=fields+1 end
 check(fields==7,'boundary contains only six booleans and one enum')
 check(D.Report():find('owner_boundary',1,true)~=nil,'boundary survives trace sanitization and report')
 check(D.Report():find('rawSenderQualified='..tostring(boundary.rawSenderQualified),1,true)~=nil,'report preserves raw sender qualification')
 check(#observations>0,'assembled build reaches production owner identity')
 for _,answer in ipairs(observations) do check(answer==expected,'actual transport authority') end
 local row,finalSource=C.Get(payload.id)
 check(row and finalSource=='overlay','final store remains in saved overlay')
 check(row.lockedEchoes==nil and row.lockedAuthorityProven~=true,'unknown roles stay unknown')
 if expected then
  check(row.ownerVerified==true and I.VerifiedOwnerKey(row)=='origin@testrealm','qualified sender promotes')
  check(row.claimedOwnerKey==nil and row.relaySender==nil,'promotion removes retained claim and relay')
  check(N.Sync.Stats().received==received+1,'one assembled build commits')
  check(snapshot(row.echoes,retained.echoes),'promotion preserves exact ordinary rows')
 else
  check(snapshot(row,retained),'unauthoritative sender preserves entire retained row')
  check(N.Sync.Stats().received==received,'rejected build never commits')
 end
 print(string.format('OWNER_PROMOTION route=%s senderKind=%s chunks=2 assembled=true directOwner=%s claimMatches=%s storedOwnerConflict=%s existingVerified=%s sourceKind=%s outcome=%s',
  route,actual:find('-',1,true) and 'qualified' or 'bare',tostring(observations[#observations]),
  tostring(match),tostring(conflict),tostring(verified),source,expected and 'promoted' or 'unchanged'))
end
for _,route in ipairs({'channel','addon'}) do
 Run('Origin-TestRealm',true,route)
 Run('Origin',false,route)
 Run('Other-TestRealm',false,route)
 Run('Relay-TestRealm',false,route,true)
 Run('Origin',false,route,true)
end
-- A local owner's existing row remains protected from remote full builds.
do
 P.Boot({'Receiver','Idle'},0,function(i,db)
  if i==1 then db.communityBuilds[payload.id]={id=payload.id,
   title='Synthetic local owner',author='Receiver-Ebonhold',realm='Ebonhold',
   ownerKey='receiver@ebonhold',ownerVerified=true,isMine=true,class='MAGE',
   lastModified=payload.m,postedAt=payload.m,ordinaryComplete=true,
   echoes={{spellId=200003,quality=1,stacks=1}}} end
 end)
 local N=P.A.e.Nexus
 local old=N.BuildCatalog.Get(payload.id)
 check(old and old.isMine==true and N.Identity.LocalOwnsBuild(old,'receiver@ebonhold'),'fixture: trusted local owner')
 local b64=N.Codec.Base64Encode(N.Codec.JSONEncode(payload))
 local split=math.floor(#b64/2)
 for i,chunk in ipairs({b64:sub(1,split),b64:sub(split+1)}) do
  P.Channel(P.A,string.format('WLRB|Origin-TestRealm|%s|%d|%d/2|%s',payload.id,payload.m,i,chunk),'Origin-TestRealm')
 end
 for _=1,300 do P.Step() end
 check(P.A.T.Equal(N.BuildCatalog.Get(payload.id),old),'remote receive preserves local owner row')
 -- New fields refuse text in boolean slots and unknown source enums.
 local D=N.PeerDebug
 D.Start()
 D.Record('owner_boundary',{rawSenderQualified='synthetic-private-marker',sourceKind='synthetic-private-marker',
  peer='synthetic-private-marker',id='synthetic-private-marker',reason='synthetic-private-marker'})
 check(not D.Report():find('synthetic-private-marker',1,true),'boundary sanitizer excludes unexpected diagnostic text')
end
print('PASS sync_owner_promotion_receive checks='..checks)
