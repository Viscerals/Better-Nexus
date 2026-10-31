-- Public seams, synthetic services. No native execution or private fixtures.
local H=dofile('tests/prototype/orbs_support.lua')
local A=Nexus.GameAdapter
local function text()return table.concat(assert(Nexus.SupportReport.Prepare({})).chunks,'')end
assert(type(A.ChoicePresenceView)=='function','ordinary choice observations have a passive view')
local view=A.ChoicePresenceView()
-- The normal harness startup already reads the board; a fresh owner is checked below.
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
local runner=Nexus.OrbRuntime.RunnerView()
assert(runner.initialized==false and runner.pending==nil,'an uninitialized runner is not a measured no-receipt')
H.Board({{spellId=410001,quality=1},{spellId=410003,quality=0},{spellId=410004,quality=3}})
H.O.offer=false
local getter=ProjectEbonhold.PerkService.GetCurrentChoice
local reads=0
ProjectEbonhold.PerkService.GetCurrentChoice=function(...)reads=reads+1;return getter(...)end
local board=A.Board()
assert(board and #board.cards==3 and reads==1,'the ordinary board preserves one existing native read')
view=A.ChoicePresenceView()
assert(view.choicePresence=='present' and view.choiceCount==3,'ordinary choice is observed without an Orb plan')
local capability,status=A.Orbs.ServiceState()
assert(capability=='STATE_AWARE' and status=='IDLE','fixture: Orb offer is idle')
local service=A.Orbs.ServiceStateView()
assert(service.offer=='absent' and service.status=='IDLE','service sample is distinct from the ordinary board')
local report=text()
assert(report:find('Echo choice: presence=present',1,true)
 and report:find('Orb service: offer=absent',1,true)
 and report:find('Orb runner: initialized=no',1,true),'report keeps the three sources separate')
assert(report:find('Orb action: unknown',1,true)
 and not report:find('Orb action: none unresolved',1,true),'uninitialized state is not confirmed absence')
assert(Nexus.OrbRuntime.RunnerView().initialized==false and reads==1,'report collection initializes and reads nothing')
local svc=ProjectEbonhold.PerkService
local ordinaryGetter=svc.GetCurrentChoice
svc.GetCurrentChoice=function()error({{spellId=410001,quality=1}},0)end
assert(A.Board()==nil,'a table-valued API error must never become a gameplay board')
assert(A.ChoicePresenceView().choicePresence=='unknown','table-valued errors remain diagnostic unknown')
svc.GetCurrentChoice=ordinaryGetter
A.Board()
ProjectEbonhold.PerkService=setmetatable({},{__index=function()error('SYNTHETIC_MEMBER_ERROR')end})
local lookupOk=pcall(A.Board)
ProjectEbonhold.PerkService=svc
view=A.ChoicePresenceView()
assert(not lookupOk and view.choicePresence=='unknown' and view.lastChoicePresence=='present',
 'an interrupted service/member lookup invalidates currentness while retaining the preceding observation')
A.Board()
-- Failure class is historical evidence even after the sample stops being current.
-- Exercise the existing Board and full report seams; collection must not retry.
local failedCases={
 {'read_failed',function()error('SYNTHETIC_PRIVATE_CHOICE_FAILURE')end},
 {'nil_response',function()return nil end},
 {'malformed',function()return {unexpected={spellId=410001}}end},
 {'no_getter'}, {'no_service'},
}
local failures={}
local function expectFailureFact(ok,message)
 if not ok then failures[#failures+1]=message;print('FAIL '..message)end
end
for _,case in ipairs(failedCases)do
 local reason,calls=case[1],0
 ProjectEbonhold.PerkService=svc
 if reason=='no_service'then ProjectEbonhold.PerkService=nil
 elseif reason=='no_getter'then svc.GetCurrentChoice=nil
 else svc.GetCurrentChoice=function(...)calls=calls+1;return case[2](...)end end
 assert(A.Board()==nil,'failed fixture is not a gameplay board: '..reason)
 local sample=A.ChoicePresenceView()
 assert(sample.choicePresence=='unknown' and sample.choiceReason==reason,
  'the normal read classifies the fixture: '..reason)
 H.now=H.now+2
 local aged=A.ChoicePresenceView()
 expectFailureFact(aged.choicePresence=='unknown' and aged.choiceCount==nil
  and aged.choiceFreshness=='stale' and aged.choiceReason=='stale',
  reason..': aged failure does not assert current choice presence or absence')
 expectFailureFact(aged.lastChoiceReason==reason,
  reason..': stale view retains the original failure reason')
 local beforeCalls,beforeSerial,beforeAt=calls,aged.serial,aged.at
 local summary=Nexus.SupportReport.Summary()
 local prepared=text()
 for _,entry in ipairs({{'summary',summary},{'prepared',prepared}})do
  expectFailureFact(entry[2]:find('lastReason='..reason,1,true)~=nil,
   reason..': '..entry[1]..' retains the original failure reason')
  expectFailureFact(entry[2]:find('Echo choice: presence=unknown',1,true)~=nil
   and not entry[2]:find('SYNTHETIC_PRIVATE_CHOICE_FAILURE',1,true),
   reason..': '..entry[1]..' is unknown without the raw error')
 end
 local after=A.ChoicePresenceView()
 expectFailureFact(calls==beforeCalls and after.serial==beforeSerial and after.at==beforeAt
  and after.choicePresence=='unknown',
  reason..': summary and preparation do not resample the failure')
end
ProjectEbonhold.PerkService=svc;svc.GetCurrentChoice=ordinaryGetter
assert(#failures==0,'historical choice failures: '..table.concat(failures,'; '))
A.Board()

for _,case in ipairs({
 {'UNKNOWN',function()return false end,function()error('pending should not be read')end},
 {'INVALID',function()error('SYNTHETIC_SERVICE_ERROR')end,function()return false end},
 {'UNAVAILABLE',nil,function()return false end},
}) do
 ProjectEbonhold.OrbService.IsStateKnown=case[2];ProjectEbonhold.OrbService.IsOfferPending=case[3]
 local _,st=A.Orbs.ServiceState();service=A.Orbs.ServiceStateView()
 assert(st==case[1] and service.offer=='unknown','unavailable service state never becomes offer absence')
end
assert(H.Count('orb-spend')==0 and H.Count('take')==0,'diagnostics send no gameplay action')
-- Reload only the observer owner, with no startup calls, to check absence of
-- an observation independently of the harness's normal startup reads.
assert(loadfile('core/GameAdapter.lua'))('Nexus',{})
assert(Nexus.GameAdapter.ChoicePresenceView().observed==false,'no sample is invented on owner load')

-- D-ROLL-01: a Banish or Freeze names the client choice slot of the card Nexus
-- decided on. A.Board() projects only entries with a spellId, so a malformed
-- entry before a card in a dense choice array shifts that card's projected
-- position. These shapes are synthetic: whether the client ever returns such
-- an entry is not known (a native boundary), and nothing here claims it does.
-- Real TOC boots, adapter, planner and runtime; the harness's synthetic
-- services, which address P.currentChoice by the 0-based index they receive,
-- and its action log are the wire oracle. No native claim.
local slotFailures={}
local function slotFact(ok,message,detail)
 if not ok then
  local line=message..(detail~=nil and (' ['..tostring(detail)..']') or '')
  slotFailures[#slotFailures+1]=line;print('FAIL '..line)
 end
end
-- A fresh profile and owners, as a new session: the checks above leave a
-- reloaded, unstarted adapter behind.
local function FreshBoot(prepare)
 local stale={}
 for key in pairs(_G)do
  if type(key)=='string' and (key:find('^Nexus') or key:find('^ProjectEbonhold') or key:find('^SLASH_NEXUS'))then
   stale[#stale+1]=key
  end
 end
 for _,key in ipairs(stale)do _G[key]=nil end
 WishlistRealizerDB=nil;SlashCmdList=nil
 local fresh=dofile('tests/prototype/harness.lua')
 if prepare then prepare(fresh) end
 fresh.Boot()
 return fresh,Nexus.GameAdapter
end
-- The game actions the synthetic services accepted after `from`.
local function GameActions(h,from)
 local out={}
 for i=from+1,#h.actions do
  local kind=h.actions[i][1]
  if kind=='banish' or kind=='freeze' or kind=='take' or kind=='reroll' then out[#out+1]=h.actions[i] end
 end
 return out
end

do
 local h,adapter=FreshBoot()
 local nextId=200001
 local function Card(id) return {spellId=id,quality=1} end
 -- Dense arrays only: an ordinary three-card board, and four entries with a
 -- malformed (spellId-less) one leading or between cards. Every case has
 -- its own spell IDs, so no earlier board, freeze overlay or latch carries over.
 local function Shape(shape)
  local a,b,c=nextId,nextId+1,nextId+2
  nextId=nextId+3
  if shape=='ordinary' then return {Card(a),Card(b),Card(c)}
  elseif shape=='leading' then return {{quality=1},Card(a),Card(b),Card(c)}
  elseif shape=='interior' then return {Card(a),{quality=1},Card(b),Card(c)} end
  error('unknown dense shape '..tostring(shape))
 end
 -- No latch, a new run-data push (the charge ledger's own reset) and the
 -- adapter's poll releasing its own in-flight action.
 local function Settle()
  h.perks.pendingBanishIndex=nil;h.perks.pendingFreezeIndex=nil
  h.run=h.Clone(h.run)
  adapter.Poll()
  return not adapter.InFlight()
 end
 for _,shape in ipairs({'ordinary','leading','interior'})do
  for _,action in ipairs({'Banish','Freeze'})do
   for position=0,2 do
    local tag='D-ROLL-01 '..action..' '..shape..' projected card '..position
    slotFact(Settle(),tag..': SETUP nothing is in flight')
    local raw=Shape(shape)
    h.Board(raw)
    local board=adapter.Board()
    local rawCount=shape=='ordinary' and 3 or 4
    slotFact(board~=nil and #board.cards==3 and #raw==rawCount,
     tag..': SETUP '..rawCount..' raw entries project three cards',board and #board.cards)
    local chosen=board and board.cards[position+1]
    if chosen then
     local rawIndex0
     for i,c in ipairs(raw)do if c.spellId==chosen.spellId then rawIndex0=i-1 end end
     local from=#h.actions
     local ok,why=adapter[action](position)
     local sent=GameActions(h,from)
     local wire=sent[1] and sent[1][2]
     local target=type(wire)=='number' and raw[wire+1] or nil
     print('OBSERVED',tag..': rawCount='..#raw..' projectedCount='..#board.cards..' chosen='..tostring(chosen.spellId)
      ..' chosenRawIndex0='..tostring(rawIndex0)..' wireIndex0='..tostring(wire)..' wireSpellId='..tostring(target and target.spellId))
     slotFact(ok==true and #sent==1 and sent[1][1]==action:lower(),tag..': exactly one '..action..' reaches the synthetic service',why)
     slotFact(wire==rawIndex0 and target~=nil and target.spellId==chosen.spellId,
      tag..': the wire index names the client slot of the decided card, never a skipped or neighbouring entry',
      'wire='..tostring(wire)..' expected='..tostring(rawIndex0))
    end
   end
  end
 end
 -- The real planner still waits on an exactly-three-entry board with one
 -- malformed entry: only two cards project (unchanged three-card guard).
 h.Board({{quality=1},Card(200001),Card(200002)})
 local two=adapter.Board()
 local decision=Nexus.EchoWeaver.DecideNexus({plan={requestedCounts={[200001]=1}},
  owned={synced=true,bySpell={}},board=two,level=40,horizon=2})
 slotFact(two~=nil and #two.cards==2 and decision.type=='wait' and decision.reason=='waiting for three-card board',
  'D-ROLL-01: a three-entry board with a malformed entry waits at the planner three-card guard',decision.reason)
 -- The existing refusals still hold on a malformed board, with no service call:
 -- a client latch, a guaranteed decided card, a session pause and an Orb
 -- service whose state is unavailable. Pause stays set for the Orb case,
 -- whose gate is checked first.
 local function Refused(label,expected,arrange,restore)
  slotFact(Settle(),'D-ROLL-01 '..label..': SETUP nothing is in flight')
  local raw=Shape('leading')
  if arrange then arrange(raw) end
  h.Board(raw)
  for _,action in ipairs({'Banish','Freeze'})do
   local from=#h.actions
   local ok,why=adapter[action](0)
   slotFact(ok==false and why==expected and #GameActions(h,from)==0,
    'D-ROLL-01 '..label..': '..action..' is refused ('..expected..') and sends nothing',why)
  end
  if restore then restore() end
 end
 Refused('pending latch','in flight',function() h.perks.pendingBanishIndex=0 end,function() h.perks.pendingBanishIndex=nil end)
 Refused('guaranteed card','blocked card',function(raw) raw[2].isGuaranteed=true end)
 Refused('session pause','Nexus paused for this session',function() Nexus.SessionPause.Pause() end)
 Refused('unknown Orb state','orb state unavailable',function() ProjectEbonhold.OrbService={} end)
end

-- The ordinary automatic route (Auto ON, real planner, intent preauthorization
-- and adapter), as the characterization fixture drove it: two picks left, no
-- Reroll charges, so the planner Banishes three unwanted cards or Freezes one
-- of two wanted copies. A matched ordinary board is the positive control.
for _,kind in ipairs({'banish','freeze'})do
 for _,shape in ipairs({'ordinary','leading'})do
  local tag='D-ROLL-01 automatic '..kind..' '..shape
  local h,adapter=FreshBoot(function(fresh) fresh.pendingRolls=2;fresh.run.totalRerolls=0 end)
  local planned=adapter.SetFirstLoadoutWishlistIdentity('Synthetic client slot control',
   {{spellId=200001,quality=1,stacks=kind=='freeze' and 2 or 1}})
  slotFact(planned,tag..': SETUP the plan is set')
  local raw=kind=='freeze' and {{spellId=200001,quality=1},{spellId=200001,quality=1},{spellId=200021,quality=1}}
   or {{spellId=200020,quality=1},{spellId=200021,quality=1},{spellId=200022,quality=1}}
  local chosen=raw[1].spellId
  if shape=='leading' then table.insert(raw,1,{quality=1}) end
  h.Board(raw);h.Notify();h.Advance(.5)
  local board=adapter.Board()
  slotFact(board~=nil and #board.cards==3 and #raw==(shape=='leading' and 4 or 3),
   tag..': SETUP the raw board projects three cards',board and #board.cards)
  local from=#h.actions
  SlashCmdList.NEXUS('auto');h.Advance(1.2)
  local stats=Nexus.RecomputeStats()
  local sent=GameActions(h,from)
  local wire=sent[1] and sent[1][2]
  local target=type(wire)=='number' and raw[wire+1] or nil
  print('OBSERVED',tag..': rawCount='..#raw..' actions='..#sent..' kind='..tostring(sent[1] and sent[1][1])
   ..' wireIndex0='..tostring(wire)..' wireSpellId='..tostring(target and target.spellId)
   ..' preauthFailed='..tostring(stats.actionLifecycle and stats.actionLifecycle.preauthFailed))
  slotFact(#sent==1 and sent[1][1]==kind,tag..': the automatic route submits exactly one '..kind,#sent)
  slotFact(target~=nil and target.spellId==chosen,
   tag..': the submitted client slot holds the decided Echo, never the malformed entry',
   'wire='..tostring(wire)..' spell='..tostring(target and target.spellId))
 end
end
assert(#slotFailures==0,'D-ROLL-01 client slot: '..#slotFailures..' failed; first: '..tostring(slotFailures[1]))
print('PASS choice_presence_diagnostics')
