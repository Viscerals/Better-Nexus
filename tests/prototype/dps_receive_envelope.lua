-- #22: a received DPS record is held to the same supported envelope as a
-- local capture (79 ordinary, 6 locked, 85 total Echo copies). A loadout
-- outside it is not a loadout the game can hold, so the record is refused
-- with the integrity reason, is not stored, and is not listed. The direct
-- owner path and the relay path share one admission, so both are checked.
--
-- Everything here is SYNTHETIC.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local fx=L.New({players={
 {name='PrototypeTester',class='MAGE',dps={lk=39000,dummy=38000},isLocal=true,variant=30,ordinary=60},
}})
local H=F.Boot(fx:Install(F.Database({version=2})),function(h) h.playerLevel=60 end)
local D=Nexus.DpsCapture
check(Nexus.LoadoutEvidence.SemanticLimits().ordinary==79,'fixture: the ordinary limit is 79')

-- Wire rows in the stored {spellId,count} shape. Ordinary copies come from
-- the fixture's ordinary pool; a second copy is added from the start of the
-- pool once all 84 distinct Echoes are used. Locked copies likewise.
local function Rows(first,size,copies)
 local counts={}
 for k=0,copies-1 do
  local id=first+(k%size)
  counts[id]=(counts[id] or 0)+1
 end
 local out={}
 for id,count in pairs(counts) do out[#out+1]={spellId=id,count=count} end
 table.sort(out,function(a,b)return a.spellId<b.spellId end)
 return out
end
local stamp=0
local function Wire(name,ordinaryCopies,lockedCopies,dps)
 stamp=stamp+1
 local wire={v=7,c='dummy',d=dps,u=180,t=time()-100+stamp,p=name,l=80,k='MAGE',
  o=name:lower()..'@'..fx.realmKey,r=fx.realm,
  e=Rows(L.ORDINARY_POOL_FIRST,L.ORDINARY_POOL_SIZE,ordinaryCopies)}
 if lockedCopies>0 then wire.lk=Rows(L.LOCKED_POOL_FIRST,L.LOCKED_POOL_SIZE,lockedCopies) end
 return wire
end
local function Listed(dps)
 for _,entry in ipairs(D.GetDpsBoard('dummy')) do
  if math.floor(tonumber(entry.dps) or 0)==dps then return true end
 end
 return false
end
local function Integrity() return D.RejectionStats().integrity or 0 end
local function Settle() for _=1,20 do H.Advance(.05,.05) end end

-- 1. The supported maximum, 79 + 6 = 85, is accepted and listed (the check
-- does not refuse the boundary).
local ok=D.ReceiveRecord(Wire('Edgeone',79,6,41000),'Edgeone-'..fx.realm)
Settle()
check(ok==true,'a 79 + 6 record is accepted: '..tostring(ok))
check(Listed(41000),'and listed')

-- 2. Records outside the envelope, from their own sender.
local cases={
 {name='Overord',ordinary=80,locked=0,dps=42000,why='80 ordinary copies'},
 {name='Overlock',ordinary=79,locked=7,dps=43000,why='7 locked copies'},
 {name='Overboth',ordinary=84,locked=6,dps=44000,why='84 + 6 copies'},
}
for _,c in ipairs(cases) do
 local before=Integrity()
 local accepted=D.ReceiveRecord(Wire(c.name,c.ordinary,c.locked,c.dps),c.name..'-'..fx.realm)
 Settle()
 check(accepted==false,'a record with '..c.why..' is refused: '..tostring(accepted))
 check(Integrity()==before+1,'with the integrity reason ('..c.why..'): '..before..' -> '..Integrity())
 check(not Listed(c.dps),'and it is not listed ('..c.why..')')
end

-- 2b. The envelope counts COPIES, not rows: 78 ordinary rows where one row
-- holds 3 copies (80 copies), and 6 locked rows where one holds 2 copies
-- (7 copies), are both outside it.
local function Stacked(name,dps,ordinaryRows,extraCount,lockedRows,lockedExtra)
 stamp=stamp+1
 local e=Rows(L.ORDINARY_POOL_FIRST,L.ORDINARY_POOL_SIZE,ordinaryRows-1)
 e[#e+1]={spellId=L.ORDINARY_POOL_FIRST+ordinaryRows-1,count=extraCount}
 local wire={v=7,c='dummy',d=dps,u=180,t=time()-100+stamp,p=name,l=80,k='MAGE',
  o=name:lower()..'@'..fx.realmKey,r=fx.realm,e=e}
 if lockedRows>0 then
  local lk=Rows(L.LOCKED_POOL_FIRST,L.LOCKED_POOL_SIZE,lockedRows-1)
  lk[#lk+1]={spellId=L.LOCKED_POOL_FIRST+lockedRows-1,count=lockedExtra}
  wire.lk=lk
 end
 return wire
end
for _,c in ipairs({
 {name='Stackord',wire=function() return Stacked('Stackord',47000,78,3,0,0) end,dps=47000,why='78 rows holding 80 ordinary copies'},
 {name='Stacklock',wire=function() return Stacked('Stacklock',48000,79,1,6,2) end,dps=48000,why='6 locked rows holding 7 copies'},
}) do
 local before=Integrity()
 local accepted=D.ReceiveRecord(c.wire(),c.name..'-'..fx.realm)
 Settle()
 check(accepted==false,'a record with '..c.why..' is refused: '..tostring(accepted))
 check(Integrity()==before+1,'with the integrity reason ('..c.why..')')
 check(not Listed(c.dps),'and it is not listed ('..c.why..')')
end

-- 3. The relay path has the same admission: a relayed record outside the
-- envelope is refused the same way, while a relayed 79 + 6 record is not
-- refused for its size.
local before=Integrity()
local relayedOver=D.ReceiveRelayedRecord(Wire('Relayover',80,0,45000),'Relayer-'..fx.realm)
Settle()
check(relayedOver==false,'a relayed 80-copy record is refused: '..tostring(relayedOver))
check(Integrity()==before+1,'with the integrity reason: '..before..' -> '..Integrity())
check(not Listed(45000),'and it is not listed')
before=Integrity()
local relayedEdge=D.ReceiveRelayedRecord(Wire('Relayedge',79,6,46000),'Relayer-'..fx.realm)
Settle()
check(Integrity()==before,'a relayed 79 + 6 record is not refused for integrity: '..tostring(relayedEdge))
check(relayedEdge==true,'and a relayed 79 + 6 record for an empty slot is accepted: '..tostring(relayedEdge))

print('PASS dps_receive_envelope '..checks..' checks')
