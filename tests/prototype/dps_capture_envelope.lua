-- The reported failure: "Catalog saved-build capture failed: SEMANTIC_ENVELOPE
-- (inline record: 81 ordinary, 6 permanent, 87 total Echo copies)". The record
-- is built by the DPS capture path, whose ordinary snapshot merges two sources
-- that describe DIFFERENT moments: Adapter.Owned (this run) and the active
-- SAVED slot. The slot marks its own permanent rows, and merging those into the
-- ordinary pool left them there whenever the current permanent map no longer
-- carried that exact id, so an ordinary pool of 79 copies reached the catalog
-- as 81 and the whole capture was refused.
--
-- Everything here is SYNTHETIC. It is not the reporter's record, which was not
-- retained anywhere, and no count below is reconstructed from their logs.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
-- Every Echo this test uses is in the client catalog before the addon loads,
-- the way a real client presents them.
local ordinary,permanent={},{}
for i=1,79 do ordinary[#ordinary+1]={spellId=300000+i,quality=2,stacks=1} end
for i=1,6 do permanent[#permanent+1]={spellId=310000+i,quality=3,stacks=1} end
for _,e in ipairs(ordinary) do H.AddEcho(e.spellId,'Echo '..e.spellId,e.quality,4,e.spellId) end
for _,e in ipairs(permanent) do H.AddEcho(e.spellId,'Locked '..e.spellId,e.quality,1,e.spellId) end
for i=1,2 do H.AddEcho(319000+i,'Replaced locked '..i,3,1,319000+i) end
for i=1,6 do H.AddEcho(320000+i,'Stale ordinary '..i,2,4,320000+i) end
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local A,D=Nexus.GameAdapter,Nexus.DpsCapture
local support=assert(Nexus.SupportIncidents,'the incident owner is loaded')
local Evidence=Nexus.LoadoutEvidence
local limits=Evidence.SemanticLimits()
check(limits.ordinary==79 and limits.locked==6 and limits.total==85,
 'the supported envelope is 79 ordinary, 6 locked, 85 total: '
 ..limits.ordinary..'/'..limits.locked..'/'..limits.total)

-- A training dummy as the target, so the real capture path classifies the
-- session the way it does in the client.
local realUnitName=UnitName
UnitName=function(unit)
 if unit=='target' then return 'Training Dummy' end
 return realUnitName(unit)
end
UnitExists=function(unit) return unit=='target' end

-- A fake Details! so the real capture path can run: one combat, one actor.
local combat={total=100000}
function combat:GetActor(_,_) return {total=self.total,Tempo=function() return 10 end} end
function combat:GetCombatTime() return 10 end
Details={GetCurrentCombat=function() return combat end}
DETAILS_ATTRIBUTE_DAMAGE=1

-- A coherent loadout: 79 ordinary copies and 6 permanent copies, the exact
-- supported maximum. The player owns them this run, and the active saved slot
-- lists the same thing, including its six permanent rows.
local function applyOwned(rows,locked)
 local granted={}
 for _,e in ipairs(rows) do
  local name=H.names[e.spellId]
  granted[name]=granted[name] or {}
  for _=1,(e.stacks or 1) do granted[name][#granted[name]+1]={spellId=e.spellId,quality=e.quality} end
 end
 H.granted=granted
 -- nil = GetLockedPerks has not answered yet (LockedOwned().synced is false).
 -- {} = it answered, and this character holds no permanent Echo at all.
 if locked==nil then
  H.locked=nil
 else
  local lockedRows={}
  for _,e in ipairs(locked) do
   lockedRows[#lockedRows+1]={spellId=e.spellId,stacks=e.stacks or 1}
  end
  H.locked=lockedRows
 end
 H.Notify();A.Poll()
end
-- The active saved slot carries BOTH roles, with the permanent rows marked as
-- the client marks them.
local function applySlot(rows,lockedRows)
 local echoes={}
 for _,e in ipairs(rows) do
  echoes[#echoes+1]={spellId=e.spellId,quality=e.quality,stacks=e.stacks or 1,locked=false}
 end
 for _,e in ipairs(lockedRows or {}) do
  echoes[#echoes+1]={spellId=e.spellId,quality=e.quality,stacks=e.stacks or 1,locked=true}
 end
 H.perks.serverBuildSlots={[1]={name='Saved',verified=true,echoes=echoes}}
 H.perks.serverActiveSlot=1
 H.Notify();A.Poll()
end

local function capture()
 D.OnCombatStart()
 -- A real capture needs a real session length; the harness clock supplies it.
 for _=1,7 do H.Advance(5,.05);D.OnUpdate(5) end
 D.OnCombatEnd()
end

-- 1. The exact reported shape: the saved slot's permanent rows are NOT the
-- permanent copies the character holds now (two were replaced), which is the
-- only difference between a clean capture and the refused one.
applyOwned(ordinary,permanent)
local stalePermanent={}
for i=1,4 do stalePermanent[#stalePermanent+1]=permanent[i] end
stalePermanent[#stalePermanent+1]={spellId=319001,quality=3,stacks=1}
stalePermanent[#stalePermanent+1]={spellId=319002,quality=3,stacks=1}
applySlot(ordinary,stalePermanent)
local snapshot=D.GetCurrentEchoCount()
check(snapshot==79,
 'the ordinary snapshot stays at the 79 copies the character actually holds: '..snapshot)
-- The same inputs through the maximum merge WITHOUT the role rule give the
-- reported 81: the two stale permanent rows land in the ordinary pool.
local inflated=0
for _,e in ipairs(ordinary) do inflated=inflated+e.stacks end
check(inflated+2==81,'the reported inflation is exactly the two stale locked rows: '..(inflated+2))

-- 1b. A copy the player really holds is never lost. The permanent map is
-- subtracted from the OWNED projection, which is the only pool that carries
-- permanent copies; subtracting it from the slot's ordinary evidence as well
-- would drop an ordinary copy of an Echo the player also holds permanently.
local shared=ordinary[1].spellId
applyOwned(ordinary,permanent)
-- This run granted only part of what the saved slot lists, which is the
-- ordinary gap the merge exists for, and the shared id is also permanent.
local thinGrant={}
for i=2,79 do thinGrant[#thinGrant+1]=ordinary[i] end
applyOwned(thinGrant,{{spellId=shared,quality=3,stacks=1}})
local slotRows={}
for _,e in ipairs(ordinary) do slotRows[#slotRows+1]=e end
applySlot(slotRows,{{spellId=shared,quality=3,stacks=1}})
local kept=D.GetCurrentEchoCount()
check(kept==79,'an Echo held both ordinarily and in a locked slot keeps its ordinary copy: '..kept)

-- 1c. A correct 79 + 6 loadout stays recordable while the permanent map is
-- still arriving: the saved slot's own permanent marks are used instead of
-- guessing, and that source is reported.
-- The client grants permanent copies too, so they are inside the owned
-- projection; only the permanent map says which ones they are.
local grantedWithPermanent={}
for _,e in ipairs(ordinary) do grantedWithPermanent[#grantedWithPermanent+1]=e end
for _,e in ipairs(permanent) do grantedWithPermanent[#grantedWithPermanent+1]=e end
applyOwned(grantedWithPermanent,nil)
applySlot(ordinary,permanent)
local lateSnapshot=D.GetCurrentEchoCount()
check(lateSnapshot==79,
 'a late locked map does not inflate the ordinary pool: '..lateSnapshot)
-- A pool derived from the saved loadout's own role marks is not RECORDED:
-- those marks may be from an earlier loadout, and a record built on them
-- would be filed under a fingerprint that may be missing a copy. The
-- capture waits, and says what it is waiting for.
support.Clear()
combat.total=200000
capture()
check((Nexus.lastDpsNote or ''):find('PERMANENT_ROLES_UNVERIFIED',1,true)~=nil
 or (Nexus.lastDpsNote or ''):find('has not arrived yet',1,true)~=nil,
 'an unconfirmed locked list defers instead of recording a key it cannot trust: '
 ..tostring(Nexus.lastDpsNote))
check(support.Latest() and support.Latest().reason=='PERMANENT_ROLES_UNVERIFIED',
 'and the incident names that reason: '..tostring(support.Latest() and support.Latest().reason))
check((Nexus.lastDpsNote or ''):find('kept until it does',1,true)~=nil,
 'and says it clears itself: '..tostring(Nexus.lastDpsNote))
-- As soon as the permanent list arrives, the same loadout records.
applyOwned(ordinary,permanent)
applySlot(ordinary,permanent)
combat.total=250000
capture()
check((Nexus.lastDpsNote or ''):find('deferred',1,true)==nil,
 'a correct 79 + 6 loadout records once the locked list is there: '
 ..tostring(Nexus.lastDpsNote))
-- 1e. A character who holds NO permanent Echo at all. GetLockedPerks answers
-- with an empty list, which is an answer: that emptiness must not be read as
-- "the list has not arrived", because nothing further is ever going to arrive
-- and every session such a character runs would be discarded forever.
support.Clear()
applyOwned(ordinary,{})
applySlot(ordinary,{})
check(A.LockedOwned().synced==true and next(A.LockedOwned().bySpell)==nil,
 'fixture: the locked list is synchronized and empty')
local noneSnapshot=D.GetCurrentEchoCount()
check(noneSnapshot==79,'the ordinary pool is the 79 copies held: '..noneSnapshot)
local bestBeforeNone=D.GetCurrentPersonalBest('dummy')
combat.total=300000
capture()
check((Nexus.lastDpsNote or ''):find('deferred',1,true)==nil,
 'a character with zero locked Echoes records normally: '..tostring(Nexus.lastDpsNote))
check(support.Latest()==nil or support.Latest().reason~='PERMANENT_ROLES_UNVERIFIED',
 'and is never told to wait for a list that already arrived: '
 ..tostring(support.Latest() and support.Latest().reason))
local afterNone=D.GetCurrentPersonalBest('dummy')
check(afterNone and (afterNone.dps or 0)>(bestBeforeNone and bestBeforeNone.dps or 0),
 'the record is written: '..tostring(afterNone and afterNone.dps))
check(#(afterNone.lockedEchoes or {})==0,'with no locked copies in it')

-- 1d. When the current permanent list is KNOWN and the saved loadout marks a
-- copy permanent that the list does not carry, the two sources contradict each
-- other about that copy. Guessing either way is wrong in the other direction -
-- an inflated pool that the catalog refuses, or a silently dropped copy filed
-- under a key nothing can match - so the capture is deferred with that exact
-- reason and the player is told how to make the sources agree.
support.Clear()
applyOwned(ordinary,permanent)
applySlot(ordinary,stalePermanent)
local bestBeforeContest=D.GetCurrentPersonalBest('dummy')
combat.total=400000
capture()
check((Nexus.lastDpsNote or ''):find('deferred',1,true)~=nil,
 'a contested locked role defers the capture: '..tostring(Nexus.lastDpsNote))
check((Nexus.lastDpsNote or ''):find('save the loadout again',1,true)~=nil,
 'and says how to resolve it: '..tostring(Nexus.lastDpsNote))
local contestIncident=support.Latest()
check(contestIncident and contestIncident.reason=='CONTESTED_PERMANENT_ROLE',
 'the incident names the contradiction: '..tostring(contestIncident and contestIncident.reason))
check(contestIncident.readiness and contestIncident.readiness.contestedPermanent==2,
 'with the number of contested copies: '..tostring(contestIncident.readiness and contestIncident.readiness.contestedPermanent))
local afterContest=D.GetCurrentPersonalBest('dummy')
check((afterContest and afterContest.dps or 0)==(bestBeforeContest and bestBeforeContest.dps or 0),
 'and no record was replaced while the sources disagree')

-- 2. With the saved loadout and the current permanent list in agreement, the
-- capture writes a record, and the record is inside the envelope.
support.Clear()
applySlot(ordinary,permanent)
combat.total=500000
capture()
check((Nexus.lastDpsNote or ''):find('deferred',1,true)==nil,
 'agreeing sources record normally: '..tostring(Nexus.lastDpsNote))
local best=D.GetCurrentPersonalBest('dummy')
check(best~=nil,'a coherent capture is recorded: '..tostring(Nexus.lastDpsNote))
local recordedOrdinary,recordedPermanent=0,0
for _,e in ipairs(best.echoes or {}) do recordedOrdinary=recordedOrdinary+(e.count or e.stacks or 1) end
for _,e in ipairs(best.lockedEchoes or {}) do recordedPermanent=recordedPermanent+(e.count or e.stacks or 1) end
check(recordedOrdinary==79,'the recorded ordinary pool is 79: '..recordedOrdinary)
check(recordedPermanent==6,'the recorded locked pool is 6: '..recordedPermanent)
check(recordedOrdinary+recordedPermanent==85,
 'the whole record is the supported 85 copies, not 87: '..(recordedOrdinary+recordedPermanent))
local verdict=Evidence.SemanticCounts and Evidence.SemanticCounts(best.echoes,best.lockedEchoes) or nil
if verdict then
 check(verdict.ordinary<=limits.ordinary and verdict.total<=limits.total,
  'and the evidence owner agrees it fits: '..tostring(verdict.ordinary)..'/'..tostring(verdict.total))
end

-- 3. A snapshot that cannot be a current loadout is deferred, not written.
-- Here the saved slot holds ordinary copies the character no longer owns, so
-- the union of two moments exceeds the ordinary envelope on its own.
support.Clear()
local before=D.GetCurrentPersonalBest('dummy')
local beforeKey=before and before.fingerprint
local stale={}
for i=1,79 do stale[#stale+1]=ordinary[i] end
for i=1,6 do stale[#stale+1]={spellId=320000+i,quality=2,stacks=1} end
applySlot(stale,permanent)
combat.total=900000
capture()
local after=D.GetCurrentPersonalBest('dummy')
check((Nexus.lastDpsNote or ''):find('deferred',1,true)~=nil,
 'an impossible ordinary pool defers the capture: '..tostring(Nexus.lastDpsNote))
check((Nexus.lastDpsNote or ''):find('previous record is unchanged',1,true)~=nil,
 'and says the previous record stands: '..tostring(Nexus.lastDpsNote))
check(after==nil or after.fingerprint==beforeKey,
 'the earlier valid record was not replaced by the derived one')
check(after==nil or (after.dps==before.dps),
 'and its result is unchanged: '..tostring(after and after.dps))

-- 4. The deferral is retained as a support incident with the failure-time
-- facts, because a refusal is not a Lua exception and Errors never sees it.
local incidents=support.History()
check(#incidents==1,'one incident is retained: '..#incidents)
local incident=incidents[1]
check(incident.kind=='capture-deferred' and incident.reason=='SEMANTIC_ENVELOPE',
 'it records the refusal that happened: '..incident.kind..'/'..incident.reason)
check(incident.producer=='DPS record capture','with its actual producer: '..tostring(incident.producer))
check(incident.origin=='local','and the origin it came from: '..tostring(incident.origin))
check(incident.counts and incident.counts.ordinary==85,
 'the failure-time ordinary count is retained: '..tostring(incident.counts and incident.counts.ordinary))
check(incident.counts.locked==6 and incident.counts.total==91,
 'with the locked and total counts: '..incident.counts.locked..'/'..incident.counts.total)
check(incident.limits.ordinary==79 and incident.limits.total==85,
 'and the limits that were enforced: '..incident.limits.ordinary..'/'..incident.limits.total)
check(incident.committed==false,'it states that nothing committed')
check(incident.scope and incident.scope:find('no personal, public or catalog write',1,true),
 'and the scope of that outcome: '..tostring(incident.scope))
check(incident.representation=='inline','the representation is recorded: '..tostring(incident.representation))
check(type(incident.affected)=='table' and #incident.affected>0,
 'the affected tuples available at the boundary are retained: '..tostring(#incident.affected))
check(#incident.affected<=support.MAX_TUPLES,
 'within the per-incident limit: '..#incident.affected..' of '..support.MAX_TUPLES)
check(incident.affectedOmitted~=nil,'and an omission count when the list was longer')
check(type(Nexus.Errors.History())=='table' and #Nexus.Errors.History()==0,
 'the Errors page stays empty, which is why refusals need their own retention')

-- 5. The same condition repeating is one incident with a count.
capture();capture()
check(support.Count()==1,'a repeat of the same refusal does not add a record: '..support.Count())
check(support.History()[1].occurrences>=2,
 'it counts the occurrences instead: '..support.History()[1].occurrences)

-- 6. A capture whose sources are coherent again records normally.
applySlot(ordinary,permanent)
combat.total=1200000
capture()
check((Nexus.lastDpsNote or ''):find('deferred',1,true)==nil,
 'a coherent capture is not deferred: '..tostring(Nexus.lastDpsNote))
local recovered=D.GetCurrentPersonalBest('dummy')
check(recovered and recovered.dps>(before and before.dps or 0),
 'and the better result is recorded: '..tostring(recovered and recovered.dps))
print('PASS dps_capture_envelope: the saved slot\'s locked rows stay locked, and an impossible snapshot defers instead of being refused checks='..checks)
