-- No elapsed/GC threshold: bounded state and call/event stability are semantic.
local F=dofile('tests/prototype/tome_observation_support.lua')
local U=dofile('tests/prototype/format5_support.lua')
local checks=0
local function expect(v,m)checks=checks+1;assert(v,'EXPECT: '..m)end
Nexus={};NexusDB={privateSentinel='PRIVATE_TOME_SENTINEL'}
dofile('core/GameAdapter.lua');dofile('core/SupportReport.lua')
Nexus.AutomationEffectiveState=function()error('facade construction not allowed')end
local v=Nexus.GameAdapter.TomeObservationFacts()
expect(v.armObserved==false and v.retained==0,'never-entered starts explicitly unobserved')
local lines=table.concat(Nexus.SupportReport.TomeObservationLines(),'\n')
expect(lines:find('arm_observed=no',1,true) and lines:find('gate=unknown',1,true),'never-entered report is not an invented gate result')
expect(NexusDB.privateSentinel=='PRIVATE_TOME_SENTINEL' and next(NexusDB,'privateSentinel')==nil,'standalone passive section never constructs Store/facade')
local W=F.Boot('missing')
local plan={advisorOnly=false,leverPlan={keep={},disable={F.LEVER[1],F.LEVER[2]}}}
F.Pick(W,'A')
F.Arm(W,plan)
local first=F.Facts(W);local reads=W.O.reads;local calls=#W.O.calls
expect(first.arm.assignmentSequence==first.assignment.sequence and first.assignment.sequence>0,'completed arm is linked to existing successful association')
local db=U.Serialize(NexusDB)
for _=1,25 do F.Arm(W,plan)end
local later=F.Facts(W)
expect(later.revision==first.revision and later.retained==first.retained and later.dropped==first.dropped,'two-lever unchanged evaluation does not churn ring/revision')
-- Two disable candidates: StepArm's disable scan and Level-1 progress counts
-- each call LeverHasKnownMember once per lever (four discovery reads / arm).
expect(W.O.reads-reads==100 and #W.O.calls==calls,'four discovery probes per two-lever arm, no diagnostic sends')
expect(U.Serialize(NexusDB)==db,'normal no-op observer path writes no Store/SV fields')
local beforeRevision=later.revision
later.arm.gate='PRIVATE_TOME_SENTINEL';later.events[1].code='PRIVATE_TOME_SENTINEL';later.tracked.pending='PRIVATE_TOME_SENTINEL'
expect(F.Facts(W).arm.gate=='eligible' and F.Facts(W).revision==beforeRevision and F.Facts(W).tracked.pending==nil,'detached clone cannot mutate owner')
for i=1,40 do W.A.TomeObservationAssignment('loadout',1,100+i)end
W.A.TomeObservationAssignment('PRIVATE_TOME_SENTINEL','PRIVATE_TOME_SENTINEL','PRIVATE_TOME_SENTINEL')
local bounded=F.Facts(W)
expect(bounded.cap==16 and bounded.retained==16 and #bounded.events==16 and bounded.dropped>0,'fixed sixteen-event ring evicts with count')
for i=2,#bounded.events do expect(bounded.events[i].seq>bounded.events[i-1].seq,'ring events retain order')end
expect(bounded.assignment.kind=='unknown' and bounded.assignment.loadout==0 and bounded.assignment.wishlist==0,'private strings do not enter scalar identifiers')
expect(not U.Serialize(bounded):find('PRIVATE_TOME_SENTINEL',1,true),'snapshot contains no private input names')
db=U.Serialize(NexusDB);reads=W.O.reads;calls=#W.O.calls
local revision=bounded.revision
for _=1,10 do F.Report(W)end
expect(W.O.reads==reads and #W.O.calls==calls and F.Facts(W).revision==revision,'repeated report capture calls no host/observer refresh')
expect(U.Serialize(NexusDB)==db,'repeated report preparation writes no durable state')
local realFacts=W.A.TomeObservationFacts
local synthetic=realFacts()
synthetic.resolution={observed=true,lever=777701,want=false,outcome='catalog_missing',cur=false,rawKind='not_evaluated',age=0}
synthetic.events={{seq=1,kind='resolution',code='catalog_missing',lever=777701,want=false,rawKind='not_evaluated',cur=false,age=0}}
W.A.TomeObservationFacts=function()return synthetic end
lines=table.concat(Nexus.SupportReport.TomeObservationLines(),'\n')
expect(lines:find('outcome=catalog_missing; interpreted_disabled=unknown; mirror_kind=not_evaluated',1,true),'unevaluated resolution never becomes an observed false mirror')
expect(lines:find('raw_kind=not_evaluated; interpreted_disabled=unknown',1,true) and not lines:find('observed_disabled=',1,true),'resolution event uses interpreted/unknown vocabulary')
synthetic.resolution.rawKind='mixed';synthetic.events[1].rawKind='mixed'
lines=table.concat(Nexus.SupportReport.TomeObservationLines(),'\n')
expect(lines:find('interpreted_disabled=unknown; mirror_kind=mixed',1,true),'mixed raw mirror answers remain unknown')
W.A.TomeObservationFacts=realFacts
local saved={}
for key,value in pairs(W.A)do if type(value)=='function' and key~='TomeObservationFacts' then
 saved[key]=value;W.A[key]=function()error('unexpected adapter entry '..key)end
end end
Nexus.AutomationEffectiveState=function()error('unexpected facade entry')end
lines=table.concat(Nexus.SupportReport.TomeObservationLines(),'\n')
for key,value in pairs(saved)do W.A[key]=value end
expect(lines:find('Tome observations:',1,true),'new section only clones existing observation owner')
expect(lines:find('AutoAllowed aggregate',1,true) and lines:find('not proof of master Auto OFF',1,true),'aggregate action gate is not mislabeled as master Auto OFF')
expect(not lines:find('PRIVATE_TOME_SENTINEL',1,true),'new section contains no private names')
print('SUMMARY tome_observation_bounds checks='..checks..' failures=0')
print('PASS tome_observation_bounds: bounded/change-only memory, passive clone, no Store or host refresh')
