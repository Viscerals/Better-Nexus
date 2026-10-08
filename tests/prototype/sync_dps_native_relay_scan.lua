-- Real inbound WLD2 -> durable authority -> bounded production responder scan.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Run(verified)
 P.Boot({'Receiver','Idle'},0,nil,{realm='TestRealm'})
 local peer=P.A;local N=peer.e.Nexus;local D=N.DpsCapture
 local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
 local payload={v=7,p='Origin',o='origin@testrealm',r='TestRealm',k='MAGE',l=80,
  c='dummy',d=47000,u=180,t=peer.e.time()-100,e=echoes,
  f=D.GetEchoKey(echoes),h=D.GetEchoHash(echoes),lk={{spellId=200085,count=1}}}
 local encoded=N.Codec.Base64Encode(N.Codec.JSONEncode(payload));local half=math.floor(#encoded/2)
 for index,chunk in ipairs({encoded:sub(1,half),encoded:sub(half+1)})do
  local wire=string.format('WLD2|Origin|Origin:%d:47000|%d/2|%s',payload.t,index,chunk)
  if verified then P.Channel(peer,wire,'Origin') else N.Sync.HandleIncoming(wire,'Origin')end
 end
 for _=1,300 do peer.H.Advance(.05,.05)end
 local row=D.GetCharacterBest('dummy','Origin')
 check(row and (D.VerifiedOwnerKey(row)~=nil)==verified,'fixture authority established by actual ingress')
 local before=D.OutboundStats();local cursor=#peer.H.sent;local progress={};local offered,done=0,false
 local bucket=D.SyncBucket('dummy','Origin')
 local context={requester='Requester-TestRealm',requestId='c1-native-dps-proof',bucket=bucket}
 P.Channel(peer,'WLRQ|Requester-TestRealm|0|0|c1-native-dps-proof|7','Requester-TestRealm')
 for _=1,100 do
  local count,complete=D.BroadcastAllBuildBests('0',bucket,progress,1,context)
  offered=offered+count;done=complete;if done then break end
 end
 check(done,'responder scan completes within bounded work')
 for _=1,300 do peer.H.Advance(.05,.05)end
 local chunks,total={},nil
 for index=cursor+1,#peer.H.sent do
  local text=peer.H.sent[index].text:gsub('||','|'):gsub('^P7:','')
  local sender,transfer,i,n,data,requester,requestId,part=text:match('^WLD2|([^|]+)|([^|]+)|(%d+)/(%d+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$')
  if data then
   check(requester==context.requester and requestId==context.requestId
    and tonumber(part)==bucket,'captured wire retains exact response window and bucket')
   check(sender=='Receiver','wire author remains relay transport identity')
   chunks[tonumber(i)]=data;total=tonumber(n)
  end
 end
 if verified then
  check(offered==1 and total~=nil and #chunks==total,
   'verified production scan emits one complete record offered='..offered
   ..' total='..tostring(total)..' sent='..(#peer.H.sent-cursor)
   ..' outbound='..N.Codec.JSONEncode(D.OutboundStats()))
  local received=N.Codec.JSONDecode(N.Codec.Base64Decode(table.concat(chunks)))
  check(received and received.o=='origin@testrealm' and received.p=='Origin'
   and received.d==47000 and received.t==payload.t and received.f==payload.f,
   'captured relay preserves exact recorded owner/content/score/time')
  check(received.x and received.x.n==context.requester and received.x.i==context.requestId
   and received.x.b==bucket,'captured relay has production-generated authorization context')
 else
  local after=D.OutboundStats()
  check(offered==0 and total==nil,'unverified production scan emits no DPS')
  check((after.relay_authorization or 0)>(before.relay_authorization or 0),
   'unverified skip is specifically authority refusal')
 end
 check(#peer.H.actions==0,'production response scan performs no gameplay action')
 print('PASS production scan verified='..tostring(verified)..' offered='..offered)
end
Run(false);Run(true)
print('PASS dps production relay scan checks='..checks)
