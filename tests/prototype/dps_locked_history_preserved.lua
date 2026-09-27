-- A DPS record keeps the locked (permanent) Echo set it was captured with.
-- The set the character holds NOW is a different moment: reading the board or
-- the sync digest must never write the current locks into a stored record, and
-- must never publish a record that was rewritten that way (#39: "Never fill
-- historical locks from the current loadout").
--
-- Everything here is SYNTHETIC; the harness is the one dps_capture_envelope
-- uses, so the record is written by the real capture path.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
local ordinary,permanent,replaced={},{},{}
for i=1,79 do ordinary[#ordinary+1]={spellId=300000+i,quality=2,stacks=1} end
for i=1,6 do permanent[#permanent+1]={spellId=310000+i,quality=3,stacks=1} end
for _,e in ipairs(ordinary) do H.AddEcho(e.spellId,'Echo '..e.spellId,e.quality,4,e.spellId) end
for _,e in ipairs(permanent) do H.AddEcho(e.spellId,'Locked '..e.spellId,e.quality,1,e.spellId) end
for i=1,2 do H.AddEcho(319000+i,'Replaced locked '..i,3,1,319000+i) end
-- A later locked set: four of the captured six plus two others.
for i=1,4 do replaced[#replaced+1]=permanent[i] end
replaced[#replaced+1]={spellId=319001,quality=3,stacks=1}
replaced[#replaced+1]={spellId=319002,quality=3,stacks=1}
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local A,D=Nexus.GameAdapter,Nexus.DpsCapture

local realUnitName=UnitName
UnitName=function(unit)
 if unit=='target' then return 'Training Dummy' end
 return realUnitName(unit)
end
UnitExists=function(unit) return unit=='target' end
local combat={total=100000}
function combat:GetActor(_,_) return {total=self.total,Tempo=function() return 10 end} end
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
 for _,e in ipairs(rows) do
  echoes[#echoes+1]={spellId=e.spellId,quality=e.quality,stacks=e.stacks or 1,locked=false}
 end
 for _,e in ipairs(lockedRows) do
  echoes[#echoes+1]={spellId=e.spellId,quality=e.quality,stacks=e.stacks or 1,locked=true}
 end
 H.perks.serverBuildSlots={[1]={name='Saved',verified=true,echoes=echoes}}
 H.perks.serverActiveSlot=1
 H.Notify();A.Poll()
end
local function holds(lockedRows)
 applyOwned(ordinary,lockedRows);applySlot(ordinary,lockedRows)
end
local function capture(total)
 combat.total=total
 D.OnCombatStart()
 for _=1,7 do H.Advance(5,.05);D.OnUpdate(5) end
 D.OnCombatEnd()
end

-- Every publication of a DPS record after this point is counted.
local sync=assert(Nexus.Sync,'Sync is loaded')
local realBroadcast=assert(sync.BroadcastDpsRecord,'the DPS broadcast is reachable')
local broadcasts={}
sync.BroadcastDpsRecord=function(record,...)
 broadcasts[#broadcasts+1]=record
 return realBroadcast(record,...)
end

local me=realUnitName('player')
local function localEntry()
 for _,entry in ipairs(D.GetDpsBoard('dummy')) do
  if entry.player==me or entry.name==me then return entry end
 end
end
local function lockedCount(entry)
 local n=0
 for _,e in ipairs(entry and entry.lockedEchoes or {}) do n=n+(tonumber(e.count or e.stacks) or 1) end
 return n
end
local function lockedSpells(entry)
 local ids={}
 for _,e in ipairs(entry and entry.lockedEchoes or {}) do ids[#ids+1]=tonumber(e.spellId) end
 table.sort(ids)
 return table.concat(ids,',')
end
-- Every read that used to rewrite the stored record: the board, the cached
-- sync digest (with its lifecycle pumps) and the uncached digest.
local function readEverything()
 broadcasts={}
 D.GetDpsBoard('dummy');D.GetDpsBoard('lk')
 D.GetSyncHash();D.GetSyncHashUncached()
 for _=1,200 do H.Advance(.05,.05);D.GetSyncHash() end
 D.GetDpsBoard('dummy')
end

-- 1. A record captured while the character held six locked Echoes.
holds(permanent)
capture(100000)
check((Nexus.lastDpsNote or ''):find('deferred',1,true)==nil,'fixture: the capture records: '..tostring(Nexus.lastDpsNote))
local entry=localEntry()
check(entry~=nil,'fixture: the local record is on the board')
local capturedSpells=lockedSpells(entry)
local capturedFingerprint=entry.lockedFingerprint
check(lockedCount(entry)==6,'fixture: the record carries the six captured locked copies: '..lockedCount(entry))

-- 2. The character now holds a different locked set. Reads leave the record
-- exactly as captured and publish nothing.
holds(replaced)
readEverything()
entry=localEntry()
check(lockedSpells(entry)==capturedSpells,
 'the stored locked set is still the captured one: '..lockedSpells(entry)..' vs '..capturedSpells)
check(entry.lockedFingerprint==capturedFingerprint,
 'and its locked fingerprint is unchanged: '..tostring(entry.lockedFingerprint))
check(#broadcasts==0,'no record was published by a read: '..#broadcasts)

-- 3. A record captured while the character held NO locked Echo. Gaining
-- locked Echoes later does not add them to that record.
holds({})
capture(200000)
check((Nexus.lastDpsNote or ''):find('deferred',1,true)==nil,'fixture: the zero-locked capture records: '..tostring(Nexus.lastDpsNote))
entry=localEntry()
check(entry and lockedCount(entry)==0,'fixture: the new best carries no locked copy: '..lockedCount(entry))
holds(permanent)
readEverything()
entry=localEntry()
check(lockedCount(entry)==0,'the zero-locked record is not filled from the current locks: '..lockedCount(entry))
check(#broadcasts==0,'and nothing was published by a read: '..#broadcasts)

-- 4. A repeated read with unchanged current locks publishes nothing either.
holds(permanent)
readEverything()
check(#broadcasts==0,'a repeated read with unchanged locks publishes nothing: '..#broadcasts)

sync.BroadcastDpsRecord=realBroadcast
print('PASS dps_locked_history_preserved '..checks..' checks')
