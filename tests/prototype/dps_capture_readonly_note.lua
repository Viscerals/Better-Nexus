-- A personal-best capture on a read-only saved profile (future format) is
-- kept for the session only. The player is told so in the chat line and in
-- the DPS note; nothing is written into the saved root. Real capture path
-- (fake Details!, a training dummy target), real Store read-only policy.
-- Synthetic data only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local ordinary,permanent={},{}
for i=1,79 do ordinary[#ordinary+1]={spellId=300000+i,quality=2,stacks=1} end
for i=1,6 do permanent[#permanent+1]={spellId=310000+i,quality=3,stacks=1} end
local db=F.Database({version=6})
local input=F.Serialize(db)
local H=F.Boot(db,function(h)
 for _,e in ipairs(ordinary) do h.AddEcho(e.spellId,'Echo '..e.spellId,e.quality,4,e.spellId) end
 for _,e in ipairs(permanent) do h.AddEcho(e.spellId,'Locked '..e.spellId,e.quality,1,e.spellId) end
end)
for _=1,100 do H.Advance(.05,.05) end
check(Nexus.MainInternals.SavedRootReadOnlyV1()~=nil,'SETUP: the saved profile is read-only')
check(Nexus.Store.StateWriteStatus().mode=='unavailable','SETUP: no durable write is possible')
local A,D=Nexus.GameAdapter,Nexus.DpsCapture
local realUnitName=UnitName
UnitName=function(unit) if unit=='target' then return 'Training Dummy' end;return realUnitName(unit) end
UnitExists=function(unit) return unit=='target' end
local combat={total=100000}
function combat:GetActor() return {total=self.total,Tempo=function() return 10 end} end
function combat:GetCombatTime() return 10 end
Details={GetCurrentCombat=function() return combat end}
DETAILS_ATTRIBUTE_DAMAGE=1
local function applyOwned(rows,locked)
 local granted={}
 for _,e in ipairs(rows) do
  local name=H.names[e.spellId]
  granted[name]=granted[name] or {}
  for _=1,(e.stacks or 1) do granted[name][#granted[name]+1]={spellId=e.spellId,quality=e.quality} end
 end
 H.granted=granted
 local lockedRows={}
 for _,e in ipairs(locked) do lockedRows[#lockedRows+1]={spellId=e.spellId,stacks=e.stacks or 1} end
 H.locked=lockedRows
 H.Notify();A.Poll()
end
local function applySlot(rows,lockedRows)
 local echoes={}
 for _,e in ipairs(rows) do echoes[#echoes+1]={spellId=e.spellId,quality=e.quality,stacks=e.stacks or 1,locked=false} end
 for _,e in ipairs(lockedRows) do echoes[#echoes+1]={spellId=e.spellId,quality=e.quality,stacks=e.stacks or 1,locked=true} end
 H.perks.serverBuildSlots={[1]={name='Saved',verified=true,echoes=echoes}}
 H.perks.serverActiveSlot=1
 H.Notify();A.Poll()
end
local function capture()
 D.OnCombatStart()
 for _=1,7 do H.Advance(5,.05);D.OnUpdate(5) end
 D.OnCombatEnd()
end
applyOwned(ordinary,permanent)
applySlot(ordinary,permanent)
check(D.GetCurrentEchoCount()==79,'fixture: the ordinary snapshot is 79 copies: '..tostring(D.GetCurrentEchoCount()))
-- The capture announces the best through the global print (the chat frame
-- in the client); capture that output for this one call.
local printed={}
local realPrint=print
print=function(...) local parts={} for i=1,select('#',...) do parts[i]=tostring((select(i,...))) end;printed[#printed+1]=table.concat(parts,' ');realPrint(...) end
capture()
print=realPrint
local note=tostring(Nexus.lastDpsNote)
check(note:find('deferred',1,true)==nil and note:find('ignored',1,true)==nil,'the capture is recorded for the session: '..note)
local best=D.GetCurrentPersonalBest('dummy')
check(best and (best.dps or 0)>0,'the session shows the new best: '..tostring(best and best.dps))
check(note:find('session only',1,true)~=nil,'the DPS note says the record is kept for this session only: '..note)
local announced
for _,line in ipairs(printed) do
 if line:find('New best',1,true) then announced=line end
end
check(announced~=nil,'the chat line announces the best')
check(announced and announced:find('session only',1,true)~=nil,'and says it is session only: '..tostring(announced))
check(F.Serialize(NexusDB)==input,'nothing was written into the saved root')
H.Fire('PLAYER_LOGOUT')
check(F.Serialize(NexusDB)==input,'the saved root is byte-identical after the session')
print('PASS dps_capture_readonly_note checks='..checks)
