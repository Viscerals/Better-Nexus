-- Optional TSM normalized-realm shim must not decide native DPS authority.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0
local function check(v,m)checks=checks+1;assert(v,m);print('PASS '..m)end
local function Boot(normalized,game)
 P.Boot({'Receiver','Idle'},0,nil,{realm=game or 'Rogue-Lite (Live)',realmApis={{game=game or 'Rogue-Lite (Live)',normalized=normalized}}})
 local peer=P.A
 return peer.e.Nexus,peer
end
local function Payload(N,realm)
 local e={{spellId=200001,count=3},{spellId=200002,count=1}}
 return {v=7,p='Origin',o='origin@'..realm,r=realm,k='MAGE',l=80,c='dummy',d=27880520,u=51.082,t=P.A.e.time()-100,e=e,f=N.DpsCapture.GetEchoKey(e),h=N.DpsCapture.GetEchoHash(e),lk={{spellId=200085,count=1}}}
end
local function Settle(peer)for _=1,200 do peer.H.Advance(.05,.05)end end
local function Deliver(N,peer,r,actual)
 local b=N.Codec.Base64Encode(N.Codec.JSONEncode(r));local total=math.ceil(#b/100)
 for i=1,total do P.Channel(peer,string.format('WLD2|Origin|Origin:%d:%d|%d/%d|%s',r.t,r.d,i,total,b:sub((i-1)*100+1,i*100)),actual or 'Origin')end
 Settle(peer)
 return N.DpsCapture.GetCharacterBest('dummy','Origin',r.o)
end
for _,case in ipairs({{nil,'roguelite(live)'},{'RogueLite(Live)','rogue-lite(live)'},{'OtherShim','roguelite(live)'}})do
 local N,peer=Boot(case[1]);local r=Payload(N,case[2]);local row=Deliver(N,peer,r)
 if not row then
  for key,value in pairs(peer.e.NexusDB.authorityBundle.dpsCapture.characterBest.dummy)do print('OBSERVED '..key..' owner='..tostring(value.ownerKey)..' verified='..tostring(value.ownerVerified))end
  print(N.DpsCapture.GetDebugLog())
 end
 check(row and N.DpsCapture.VerifiedOwnerKey(row)==r.o,'native exact Ebonhold owner retained independent of optional API '..tostring(case[1])..' / '..case[2])
 check(row.dps==r.d and row.ts==r.t and row.duration==r.u and row.fingerprint==r.f,'exact score/time/duration/ordinary identity unchanged')
 check(N.Identity.CanonicalOwnerKey('origin@rogue-lite(live)')~='origin@roguelite(live)','wire canonical realms remain distinct globally')
 local material=N.DpsCapture.MaterializeRecord(row)
 check(material.lockedEchoes[1].spellId==200085 and material.lockedEchoes[1].count==1,'locked role and copies preserved')
 local catalog=N.BuildCatalog.Get(row.buildId)
 check(catalog and N.Identity.VerifiedOwnerKey(catalog)==r.o,'generated record page agrees with authenticated DPS owner')
end
-- Reproduce the exact earlier stored mismatch through the strict unknown route,
-- then recover only after a new authenticated native copy of that same record.
do
 local N,peer=Boot(nil);local r=Payload(N,'roguelite(live)')
 check(N.DpsCapture.ReceiveRecord(r,'Origin-rogue-lite(live)')==true,'seed observed earlier unverified mismatch')
 Settle(peer)
 local bucket=peer.e.NexusDB.authorityBundle.dpsCapture.characterBest.dummy
 local old=bucket['origin@rogue-lite(live)'];check(old and old.ownerVerified==false,'earlier row remains unverified before new proof')
 local score,time,fp=old.dps,old.ts,old.fingerprint
 local row=Deliver(N,peer,r)
 check(row and N.DpsCapture.VerifiedOwnerKey(row)==r.o,'matching unverified native-alias record recovered by authenticated transfer')
 check(bucket['origin@rogue-lite(live)']==nil,'only matching old unverified alias slot retired')
 check(row.dps==score and row.ts==time and row.fingerprint==fp,'recovery preserves exact historical score/time/fingerprint')
 local F=peer.e.dofile('tests/prototype/format5_support.lua')
 peer.e.NexusDB=assert(loadstring('return '..F.Serialize(peer.e.NexusDB)))()
 peer=P.Rejoin(1);N=peer.e.Nexus;Settle(peer)
 row=N.DpsCapture.GetCharacterBest('dummy','Origin',r.o)
 check(row and row.dps==score and row.ts==time and N.DpsCapture.VerifiedOwnerKey(row)==r.o,'serialized fresh-runtime reload preserves recovered authority')
end
for _,case in ipairs({{realm='otherrealm'},{realm='roguelite(live)',game='AnotherRealm'},{realm='roguelite(live)',actual='Impostor'},{realm='roguelite(live)',actual='Origin-OtherRealm'}})do
 local N,peer=Boot(nil,case.game);local r=Payload(N,case.realm);local row=Deliver(N,peer,r,case.actual)
 check(not row or N.DpsCapture.VerifiedOwnerKey(row)==nil,'wrong realm/player/qualified transport never borrows local alias authority')
 check(#peer.H.actions==0,'negative authority check takes no gameplay action')
end
for _,case in ipairs({
 {name='score',edit=function(old)old.dps=old.dps+1 end},
 {name='timestamp',edit=function(old)old.ts=old.ts-1 end},
 {name='duration',edit=function(old)old.duration=old.duration+1 end},
 {name='ordinary fingerprint',edit=function(old)old.fingerprint='different' end},
 {name='ordinary copies',edit=function(old)old.evidenceKey=nil;old.echoes={{spellId=200001,count=2},{spellId=200002,count=1}}end},
 {name='ordinary quality',edit=function(old)old.evidenceKey=nil;old.echoes={{spellId=200001,count=3,quality=2},{spellId=200002,count=1}}end},
 {name='locked identity',edit=function(old)old.lockedEvidenceKey=nil;old.lockedEchoes={{spellId=200086,count=1}}end},
 {name='locked copy count',edit=function(old)old.lockedEvidenceKey=nil;old.lockedEchoes={{spellId=200085,count=2}}end},
 {name='locked quality',edit=function(old)old.lockedEvidenceKey=nil;old.lockedEchoes={{spellId=200085,count=1,quality=2}}end},
 {name='ordinary reference conflict',edit=function(old)old.echoes={{spellId=200001,count=3},{spellId=200002,count=1}};old.evidenceKey='v1|200099:0:1:0'end},
 {name='locked reference conflict',edit=function(old)old.lockedEchoes={{spellId=200085,count=1}};old.lockedEvidenceKey='v1|200099:0:1:1'end},
 {name='existing owner',edit=function(old)old.ownerKey='other@rogue-lite(live)'end},
 {name='verified prior',edit=function(old)old.ownerKey='origin@rogue-lite(live)';old.ownerVerified=true end},
})do
 local N,peer=Boot(nil);local r=Payload(N,'roguelite(live)')
 check(N.DpsCapture.ReceiveRecord(r,'Origin-rogue-lite(live)')==true,'seed negative bridge '..case.name)
 Settle(peer);local bucket=peer.e.NexusDB.authorityBundle.dpsCapture.characterBest.dummy
 local prior=bucket['origin@rogue-lite(live)'];case.edit(prior)
 local F=peer.e.dofile('tests/prototype/format5_support.lua');local oldId=prior.buildId
 local oldPage=F.Serialize(peer.e.NexusDB.authorityBundle.communityBuilds[oldId])
 local before=prior.ownerVerified
 local row=Deliver(N,peer,r)
 check(bucket['origin@rogue-lite(live)']==prior and prior.ownerVerified==before,'conflicting '..case.name..' prior is never promoted or retired')
 check(row and N.DpsCapture.VerifiedOwnerKey(row)==r.o,'fresh authenticated record is independently admitted despite conflicting prior '..case.name)
 check(F.Serialize(peer.e.NexusDB.authorityBundle.communityBuilds[oldId])==oldPage,'old catalog page preserved for conflicting '..case.name)
end
for _,kind in ipairs({'missing','non-auto','verified'})do
 local N,peer=Boot(nil);local r=Payload(N,'roguelite(live)')
 check(N.DpsCapture.ReceiveRecord(r,'Origin-rogue-lite(live)')==true,'seed catalog bridge negative '..kind)
 Settle(peer);local bucket=peer.e.NexusDB.authorityBundle.dpsCapture.characterBest.dummy
 local prior=bucket['origin@rogue-lite(live)'];local oldId=prior.buildId
 local F=peer.e.dofile('tests/prototype/format5_support.lua')
 local oldPage=F.Serialize(peer.e.NexusDB.authorityBundle.communityBuilds[oldId])
 local get=N.BuildCatalog.Get
 N.BuildCatalog.Get=function(id)
  local value=get(id)
  if id==oldId then
   if kind=='missing' then return nil end
   local copy={};for k,v in pairs(value)do copy[k]=v end;value=copy
   if kind=='non-auto' then value.autoDps=false end
   if kind=='verified' then
    value.ownerKey='origin@rogue-lite(live)';value.ownerVerified=true;value.realm='rogue-lite(live)';value.author='Origin';value.player='Origin'
    value.relaySender=nil;value.claimedOwnerKey=nil;value.a=nil;value.o=nil;value.p=nil;value.r=nil
   end
  end
  return value
 end
 if kind=='verified' then check(N.Identity.VerifiedOwnerKey(N.BuildCatalog.Get(oldId))~=nil,'verified page refusal fixture carries coherent authority')end
 Deliver(N,peer,r)
 check(bucket['origin@rogue-lite(live)']==prior and prior.ownerVerified==false,'prior slot preserved when prior page '..kind)
 check(F.Serialize(peer.e.NexusDB.authorityBundle.communityBuilds[oldId])==oldPage,'prior page bytes preserved when prior page '..kind)
end
do
 P.Boot({'Origin','Receiver'},0,nil,{realm='Rogue-Lite (Live)',realmApis={
  {game='Rogue-Lite (Live)',normalized='RogueLite(Live)'},
  {game='Rogue-Lite (Live)'},
 }})
 local sender,recipient=P.A,P.B;local N=sender.e.Nexus
 local r=Payload(N,'roguelite(live)')
 check(N.DpsCapture.ReceiveRecord(r,'Origin-roguelite(live)')==true,'sender owns eligible verified record under real shim identity')
 Settle(sender)
 local row=N.DpsCapture.GetCharacterBest('dummy','Origin',r.o)
 local outgoing=N.DpsCapture.MaterializeRecord(row);outgoing.category='dummy'
 local cursor=#sender.H.sent
 check(N.Sync.BroadcastDpsRecord(outgoing)==true,'production sender export admits exact owned record')
 Settle(sender)
 local chunks,total={},nil
 for i=cursor+1,#sender.H.sent do
  local packet=sender.H.sent[i];local text=packet.text:gsub('||','|')
  local index,count,data=text:match('^WLD2|[^|]+|[^|]+|(%d+)/(%d+)|([^|]+)$')
  if data then
   check(packet.route=='chat' and packet.kind=='CHANNEL','owner broadcast uses authenticated native channel')
   chunks[tonumber(index)]=data;total=tonumber(count);P.Channel(recipient,packet.text,'Origin')
  end
 end
 check(total and #chunks==total,'production export transmits every exact DPS chunk')
 local decoded=N.Codec.JSONDecode(N.Codec.Base64Decode(table.concat(chunks)))
 check(decoded.o==r.o and decoded.r==r.r and decoded.d==r.d and decoded.t==r.t and decoded.f==r.f,'wire retains claimed owner; loss was admission discard, not omitted serialization')
 Settle(recipient)
 local received=recipient.e.Nexus.DpsCapture.GetCharacterBest('dummy','Origin',r.o)
 check(received and recipient.e.Nexus.DpsCapture.VerifiedOwnerKey(received)==r.o,'minimal recipient without shim admits production sender payload with authority')
 check(#sender.H.actions==0 and #recipient.H.actions==0,'paired export/admission takes no gameplay action')
end
print('PASS '..checks..' checks')
