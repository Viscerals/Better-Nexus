-- Owner-confirmed current realm-local channel contract. Synthetic native
-- events exercise two-chunk assembly and durable admission, not a live server.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0
local function check(value,message) assert(value,message);checks=checks+1 end
local function Run(case)
 local realm=case.localOwner and 'Ebonhold' or 'TestRealm'
 local payload={id='synthetic-native-owner',t='Synthetic native owner',
  a='Origin-'..realm,o='Origin@'..realm,c='MAGE',m=1700000200,
  ownerVerified=case.payloadFlag and true or nil,e={{200001,1,3},{200002,2,1}}}
 P.Boot({'Receiver','Idle'},0,function(i,db)
  if i~=1 then return end
  local name=case.localOwner and 'Receiver' or case.mismatch and 'Other' or 'Origin'
  db.communityBuilds[payload.id]={id=payload.id,title=payload.t,
   author=name..'-'..realm,realm=realm,class='MAGE',lastModified=payload.m,
   postedAt=payload.m,ordinaryComplete=true,
   echoes={{spellId=200001,quality=1,stacks=3},{spellId=200002,quality=2,stacks=1}},
   ownerVerified=case.verified or case.localOwner or false,
   ownerKey=case.conflict and 'other@testrealm'
    or (case.verified or case.localOwner) and name:lower()..'@'..realm:lower() or nil,
   claimedOwnerKey=not (case.verified or case.localOwner) and name..'@'..realm or nil,
   relaySender=not (case.verified or case.localOwner) and 'Relay-TestRealm' or nil,
   isMine=case.localOwner or false}
 end,{realm=realm,roots=NEXUS_TEST_OWNER_ROOT and {NEXUS_TEST_OWNER_ROOT,NEXUS_TEST_OWNER_ROOT} or nil})
 local peer=P.A
 local N=peer.e.Nexus
 local old,source=N.BuildCatalog.Get(payload.id)
 check(old and source~='bundled',case.name..': retained fixture')
 if case.promotes then
  check(N.Identity.VerifiedOwnerKey(old)==nil
   and N.Identity.CanonicalOwnerKey(old.claimedOwnerKey)=='origin@testrealm',
   case.name..': matching unverified claim fixture')
 end
 if case.conflict then
  check(old.ownerKey=='other@testrealm' and old.claimedOwnerKey~=nil,'conflicting stored keys retained')
 end
 if case.localOwner then
  check(N.Identity.LocalOwnsBuild(old,'receiver@ebonhold'),'local owner fixture protected')
 end
 local b64=N.Codec.Base64Encode(N.Codec.JSONEncode(payload))
 local split=math.floor(#b64/2)
 local chunks={b64:sub(1,split),b64:sub(split+1)}
 local sender=case.sender or 'Origin'
 if case.noSender then sender=nil end
 local declared=case.declared or sender or 'Origin-TestRealm'
 local boundaries={}
 local debug=N.PeerDebug
 debug.Start()
 local record=debug.Record
 debug.Record=function(kind,fields)
  if kind=='owner_boundary' then boundaries[#boundaries+1]=fields end
  return record(kind,fields)
 end
 if case.route=='addon' then
  peer.H.Fire('CHAT_MSG_ADDON',N.SyncWire.PREFIX,'ACK1','WHISPER',sender)
 end
 local received=N.Sync.Stats().received
 for index,chunk in ipairs(chunks) do
  -- Change only the event's native realm lookup. Restore it before driving
  -- catalog work, so a different local identity cannot invalidate the oracle.
  peer.e.GetRealmName=function()
   return case.invalidRealm or case.changeRealm and index==2 and 'OtherRealm' or realm
  end
  peer.e.GetNormalizedRealmName=peer.e.GetRealmName
  if case.fallbackRealm then peer.e.GetNormalizedRealmName=nil end
  if case.missingRealm then
   peer.e.GetNormalizedRealmName=nil;peer.e.GetRealmName=nil
  end
  local wire=string.format('WLRB|%s|%s|%d|%d/2|%s',declared,payload.id,payload.m,index,chunk)
  if case.deferred and index==2 then
   local holder={id='synthetic-catalog-holder',t='Synthetic holder',
    a='Holder-TestRealm',o='Holder@TestRealm',c='MAGE',m=payload.m,
    e={{200001,1,1}}}
   local bytes=N.Codec.Base64Encode(N.Codec.JSONEncode(holder))
   local half=math.floor(#bytes/2)
   for part,value in ipairs({bytes:sub(1,half),bytes:sub(half+1)}) do
    P.Channel(peer,string.format('WLRB|Holder-TestRealm|%s|%d|%d/2|%s',
     holder.id,holder.m,part,value),'Holder-TestRealm')
   end
   check(not N.BuildCatalog.ManualPreparationStatus().ready,'real holder starts catalog work')
  end
  if case.route=='unknown' or case.route=='mixed' and index==2 then
   N.Sync.HandleIncoming(wire,sender)
  elseif case.route=='addon' then
   peer.H.Fire('CHAT_MSG_ADDON',N.SyncWire.PREFIX,'P7:'..wire,'WHISPER',sender)
  elseif case.route=='wrong' then
   peer.H.Fire('CHAT_MSG_CHANNEL',wire,sender,nil,'1. otherchannel',nil,nil,nil,nil,'otherchannel')
  else
   P.Channel(peer,wire,sender)
  end
  peer.e.GetRealmName=function() return realm end
  peer.e.GetNormalizedRealmName=peer.e.GetRealmName
  if case.deferred and index==2 then
   check(N.Sync.WorkState().deferredAdmissions>0,'native owner admission actually defers')
  end
  for _=1,index==1 and 20 or 300 do P.Step() end
  if index==1 then
   check(peer.T.Equal(N.BuildCatalog.Get(payload.id),old),case.name..': first chunk cannot write')
   check(#boundaries==0,case.name..': first chunk cannot reach owner admission')
  end
 end
 debug.Record=record
 local row=N.BuildCatalog.Get(payload.id)
 if case.promotes then
  check(N.Identity.VerifiedOwnerKey(row)=='origin@testrealm',case.name..': native bare sender must promote; assembled='
   ..tostring(#boundaries>0)..' directOwner='..tostring(boundaries[#boundaries] and boundaries[#boundaries].directOwner))
  check(row.claimedOwnerKey==nil and row.relaySender==nil,'promotion removes claim and relay')
  check(N.Sync.Stats().received==received+(case.deferred and 2 or 1),'one assembled record commits')
  check(peer.T.Equal(row.echoes,old.echoes),'promotion preserves ordinary contents')
 else
  check(peer.T.Equal(row,old),case.name..': entire protected row unchanged')
  check(N.Sync.Stats().received==received,case.name..': no receive commit')
 end
 check(row.lockedEchoes==nil and row.lockedAuthorityProven~=true,'unknown locked roles remain unknown')
 if #boundaries>0 then
  local boundary=boundaries[#boundaries]
  check(boundary.rawSenderQualified==(N.Identity.CanonicalOwnerFromTransport(sender)~=nil),
   case.name..': diagnostics retain raw event sender shape')
  if case.promotes then
   check(boundary.directOwner==true and boundary.claimMatches==true
    and boundary.existingVerified==false and boundary.storedOwnerConflict==false,
    'native authority reaches admission with the matching unverified claim')
  end
 end
 print('NATIVE_OWNER case='..case.name..' chunks=2 outcome='..(case.promotes and 'promoted' or 'unchanged'))
end
Run{name='bare native channel',promotes=true}
Run{name='bare envelope with native sender',declared='Origin-TestRealm',promotes=true}
Run{name='qualified sender preserved',sender='Origin-TestRealm',promotes=true}
Run{name='native owner after deferred storage',deferred=true,promotes=true}
Run{name='native realm API fallback',fallbackRealm=true,promotes=true}
Run{name='wrong channel',route='wrong'}
Run{name='unknown route',route='unknown'}
Run{name='bare addon unchanged',route='addon'}
Run{name='mismatched retained claim',mismatch=true}
Run{name='qualified different realm',sender='Origin-OtherRealm'}
Run{name='wrong bare sender',sender='Other'}
Run{name='bare relay sender',sender='Relay'}
Run{name='conflicting stored owners',conflict=true}
Run{name='protected local owner',localOwner=true}
Run{name='verified row relay',sender='Relay',verified=true}
Run{name='payload verification flag rejected',payloadFlag=true}
Run{name='mixed native and unknown chunks',route='mixed'}
Run{name='realm changes during assembly',changeRealm=true}
Run{name='missing realm',missingRealm=true}
Run{name='invalid realm',invalidRealm='bad@realm'}
Run{name='non-string realm',invalidRealm=7}
Run{name='unknown realm',invalidRealm='unknown'}
Run{name='missing native sender',noSender=true}
print('PASS sync_native_channel_owner checks='..checks)
