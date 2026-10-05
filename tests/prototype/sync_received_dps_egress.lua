-- Receiver-side egress after an inbound remote DPS record. Two isolated
-- production runtimes (sync_pair_support): Receiver stores records that
-- Origin (a third player, not a peer) posted over the native channel; Idle
-- only listens. A received record must not make the receiver broadcast a
-- build it does not own: no summary (WLBI) of the auto page it creates for
-- the remote owner, no full-build relay (WLRB) of a held remote build the
-- record names, and no re-submission of the remote record itself (WLD2).
-- The record and its page are still admitted exactly as before, and a late
-- peer still obtains both builds through its own Sync request (the
-- established request/response path), which is the designed recovery route.
local P=dofile('tests/prototype/sync_pair_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local HELD='origin-held'
-- Small loadouts: a DPS record travels in bounded wire chunks.
local heldRows=L.OrdinaryRows(11,6)
local newRows=L.OrdinaryRows(12,6)
local function Fixture(i,db)
 if i~=1 then return end
 -- A remote build the Receiver already holds inline (received earlier from a
 -- verified owner): the one case in which the old relay could resend a
 -- complete build after a DPS record named it.
 db.communityBuilds[HELD]={id=HELD,title='Origin held loadout',author='Origin-TestRealm',
  ownerKey='origin@testrealm',ownerVerified=true,realm='TestRealm',class='MAGE',
  postedAt=1,lastModified=1,ordinaryComplete=true,loadoutAvailable=true,
  echoes=L.Copy(heldRows),fingerprint=L.Fingerprint(heldRows),lockedEchoes={},lockedComplete=true}
end
local A,B=P.Boot({'Receiver','Idle'},0,Fixture,{realm='TestRealm'})
local N,NB=A.e.Nexus,B.e.Nexus
local D,C=N.DpsCapture,N.BuildCatalog
check(C.Get(HELD)~=nil and #C.Get(HELD).echoes>0,'fixture: the Receiver holds the remote build inline')
check(N.Identity.VerifiedOwnerKey(C.Get(HELD))=='origin@testrealm','fixture: its owner is verified')
-- While the records arrive, nothing from Idle reaches the Receiver: every
-- Receiver packet in the measured windows is unsolicited, never an answer.
P.hold=function(p) return p==B end
-- The receiver's own public egress entries, by build: a summary, a full
-- build, a DPS record. Responses to a peer's request use none of them.
local calls={}
for _,name in ipairs({'BroadcastBuildSummary','BroadcastBuild','BroadcastDpsRecord'}) do
 local real=N.Sync[name]
 N.Sync[name]=function(record,...)
  local id=type(record)=='table' and (record.id or record.buildId or record.b) or nil
  calls[#calls+1]=name..':'..tostring(id)
  return real(record,...)
 end
end
local function Calls() local out=table.concat(calls,' ');calls={};return out=='' and '(none)' or out end

local function Payload(rows,score,buildId)
 local echoes=L.DpsRows(rows)
 return {v=7,p='Origin',o='origin@testrealm',r='TestRealm',k='MAGE',l=80,c='dummy',d=score,u=180,
  t=A.e.time()-100,e=echoes,f=D.GetEchoKey(echoes),h=D.GetEchoHash(echoes),b=buildId}
end
local function Deliver(payload)
 local encoded=N.Codec.Base64Encode(N.Codec.JSONEncode(payload))
 local chunks={}
 for first=1,#encoded,160 do chunks[#chunks+1]=encoded:sub(first,first+159) end
 for index,chunk in ipairs(chunks) do
  P.Channel(A,string.format('WLD2|Origin|Origin:%d:%d|%d/%d|%s',payload.t,payload.d,index,#chunks,chunk),'Origin')
 end
end
-- Receiver packets since a cursor, by wire code (the pair support's own
-- classification: first field, addon-route tag removed).
local function Egress(cursor)
 local counts={}
 for i=cursor+1,#A.H.sent do
  local code=((A.H.sent[i].text:gsub('||','|')):match('^([^|]+)') or '?'):gsub('^P%d+:','')
  counts[code]=(counts[code] or 0)+1
 end
 return counts
end
local function Line(counts)
 local parts={}
 for code,n in pairs(counts) do parts[#parts+1]=code..'='..n end
 table.sort(parts);return table.concat(parts,' ')
end

-- 1. A record for a loadout no peer has a page for: the Receiver creates the
-- remote owner's record page locally and stays silent about it.
local cursor=#A.H.sent
Deliver(Payload(newRows,47000))
P.Advance(20)
local best=D.GetCharacterBest('dummy','Origin')
check(best and best.dps==47000 and D.VerifiedOwnerKey(best)=='origin@testrealm','the remote record is stored with its verified owner')
local autoId=best and best.buildId
check(autoId~=nil and C.Get(autoId)~=nil and C.Get(autoId).autoDps==true,'the record page exists locally: '..tostring(autoId))
check(N.Identity.VerifiedOwnerKey(C.Get(autoId))=='origin@testrealm','the page carries the remote owner, not this client')
local egress=Egress(cursor)
local made=Calls()
check(not made:find('BroadcastBuildSummary',1,true),'the receiver does not broadcast a summary of the remote owner\'s page: '..made)
check(not made:find('BroadcastBuild:',1,true) and not made:find('BroadcastDpsRecord',1,true),'no full build and no record re-submission from the receiver: '..made)
check((egress.WLBI or 0)==0,'no unsolicited summary on the wire: '..Line(egress))
check((egress.WLRB or 0)==0,'no unsolicited full build on the wire: '..Line(egress))
check((egress.WLD2 or 0)==0,'no re-submitted record on the wire: '..Line(egress))
check(NB.BuildCatalog.Get(autoId)==nil,'the idle peer received no page it did not ask for')

-- 2. A record that names a held remote build: linked, not relayed.
cursor=#A.H.sent
Deliver(Payload(heldRows,46000,HELD))
P.Advance(20)
local held=D.GetCharacterBest('dummy','Origin','origin@testrealm')
check(held and held.dps==47000,'the lower result keeps the best: '..tostring(held and held.dps))
egress=Egress(cursor);made=Calls()
check(not made:find('BroadcastBuild:',1,true),'the held remote build is not relayed after a record named it: '..made)
check(not made:find('BroadcastBuildSummary',1,true) and not made:find('BroadcastDpsRecord',1,true),'no summary or record re-submission either: '..made)
check((egress.WLRB or 0)==0 and (egress.WLBI or 0)==0 and (egress.WLD2 or 0)==0,'nothing unsolicited on the wire: '..Line(egress))

-- 3. The designed recovery route still works: the idle peer asks, the
-- Receiver answers, and both remote-owned builds arrive through the request.
P.hold=nil
check(NB.Sync.RequestSync()==true,'the idle peer can request a Sync')
P.Until(function() return NB.BuildCatalog.Get(autoId)~=nil and NB.BuildCatalog.Get(HELD)~=nil end)
-- A relay names the owner as a claim; verified authority comes only from the
-- owner's own transport, never from the relaying peer (unchanged rule).
local relayed=NB.BuildCatalog.Get(autoId)
check((relayed.claimedOwnerKey or relayed.ownerKey)=='origin@testrealm' and NB.Identity.VerifiedOwnerKey(relayed)==nil,
 'the requested page names the remote owner as a claim and is not verified by the relay: '
 ..tostring(relayed.claimedOwnerKey)..'/'..tostring(relayed.ownerKey)..'/'..tostring(relayed.ownerVerified))
print('PASS sync_received_dps_egress checks='..checks)
