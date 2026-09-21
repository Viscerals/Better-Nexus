-- R1 (review of main eadff8a): unknown Orb state and the ordinary-action gate.
-- This is a NEW test written from the review report's stated scenario F4. It is
-- not a rerun of the review's original probe; that probe is not available here.
-- It drives the real GameAdapter.OrdinaryBoardAllowed gate and the real ordinary
-- mutators (Take, Banish, Reroll, Freeze) through the normal harness boot. Only
-- the game services are mocked. It proves no native client behaviour.
local H=dofile('tests/prototype/harness.lua');H.pendingRolls=6;H.Boot()
local A=Nexus.GameAdapter;local T=Nexus.UserText
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
check(A.SetFirstLoadoutWishlistIdentity('R1 plan',{ {spellId=200001,quality=1,stacks=2} }),'plan set')
local CARDS={{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}}
H.Board(CARDS);H.Notify();H.Advance(.5)
check(A.Wishlist()~=nil and A.Board()~=nil,'fixture has a real target and a real three-card board')
local P=H.perks
local function settle()
 P.pendingSelectSpellId=nil;P.pendingBanishIndex=nil;P.pendingFreezeIndex=nil;P.pendingReroll=nil
 H.Advance(.6)
end
local MUTATORS={
 {'Take',function()return A.Take(200001)end,'take'},
 {'Banish',function()return A.Banish(1)end,'banish'},
 {'Reroll',function()return A.Reroll()end,'reroll'},
 {'Freeze',function()return A.Freeze(2)end,'freeze'},
}
local queried
local function service(known,pending)
 return {IsStateKnown=function()queried=(queried or 0)+1;if type(known)=='function'then return known()end;return known end,
  IsOfferPending=function()if type(pending)=='function'then return pending()end;return pending end}
end
local function blocked(label,orb,expectReason)
 ProjectEbonhold.OrbService=orb
 local before=#H.actions
 local allowed,reason=A.OrdinaryBoardAllowed()
 -- The real mutators come first so that a weak gate fails at the mutation seam.
 for _,m in ipairs(MUTATORS)do
  local ok,why=m[2]()
  check(ok==false,label..': '..m[1]..' refused by the real mutator')
  check(why==reason,label..': '..m[1]..' reports the gate reason')
 end
 check(#H.actions==before,label..': no game mutation was submitted')
 check(allowed==false,label..': gate blocks')
 check(type(reason)=='string' and reason~='',label..': gate gives a reason')
 if expectReason then check(reason==expectReason,label..': reason is '..expectReason..' (got '..tostring(reason)..')')end
 local shown=T.Message(reason)
 check(type(shown)=='string' and shown~='',label..': a visible reason exists')
 if reason~='Orb offer active -- manual action required' then
  check(not shown:lower():find('offer is active',1,true),label..': visible text does not claim an active offer')
 end
end

-- F4: the OrbService exists, reports NOT known, and reports no pending offer.
queried=nil
blocked('unknown+not pending',service(false,false),'orb state not yet known')
check((queried or 0)>0,'the gate queried IsStateKnown')
check(T.Message('orb state not yet known'):find('not confirmed',1,true)~=nil,'unknown state has a truthful visible reason')
-- Unknown wins over any pending answer: an unknown service cannot vouch for it.
blocked('unknown+pending',service(false,true),'orb state not yet known')
-- Known and pending: the existing active-offer block remains.
blocked('known+pending',service(true,true),'Orb offer active -- manual action required')
-- Malformed known-state answers.
blocked('IsStateKnown returns nil',service(nil,false),'orb state unknown')
blocked('IsStateKnown returns a number',service(1,false),'orb state unknown')
blocked('IsStateKnown returns a string',service('true',false),'orb state unknown')
blocked('IsStateKnown throws',service(function()error('synthetic known failure')end,false),'orb state unknown')
blocked('IsStateKnown is not a function',{IsStateKnown=true,IsOfferPending=function()return false end},'orb state unavailable')
-- Malformed pending answers while the state is known.
blocked('IsOfferPending returns nil',service(true,nil),'orb state unknown')
blocked('IsOfferPending returns a number',service(true,0),'orb state unknown')
blocked('IsOfferPending throws',service(true,function()error('synthetic pending failure')end),'orb state unknown')
-- Missing capability.
blocked('empty OrbService',{},'orb state unavailable')
blocked('IsStateKnown only',{IsStateKnown=function()return true end},'orb state unavailable')
blocked('IsOfferPending is not a function',{IsStateKnown=function()return true end,IsOfferPending=false},'orb state unavailable')
-- A present OrbService field that is not a table is malformed, not absent.
blocked('OrbService is a boolean',true,'orb state unavailable')
blocked('OrbService is a function',function()return {}end,'orb state unavailable')

-- Automatic rolling uses the same gate: no action while unknown.
ProjectEbonhold.OrbService=service(false,false)
local before=#H.actions
SlashCmdList.NEXUS('auto');H.Advance(2)
check(#H.actions==before,'automatic rolling submits nothing while Orb state is unknown')
SlashCmdList.NEXUS('auto');H.Advance(.2)

-- Positive controls. Known + not pending permits every ordinary mutator.
local function permits(label,orb)
 ProjectEbonhold.OrbService=orb
 local allowed,reason=A.OrdinaryBoardAllowed()
 check(allowed==true and reason==nil,label..': gate allows ('..tostring(reason)..')')
end
permits('known+not pending',service(true,false))
for _,name in ipairs({'Freeze','Banish','Reroll','Take'})do
 for _,m in ipairs(MUTATORS)do if m[1]==name then
  H.Board(CARDS);H.Notify();H.Advance(.3)
  local n=#H.actions;local ok,why=m[2]()
  check(ok==true,'known+not pending: '..name..' accepted ('..tostring(why)..')')
  check(#H.actions==n+1 and H.actions[#H.actions][1]==m[3],'known+not pending: '..name..' reached the game service once')
  settle()
 end end
end
-- Explicit legacy capability: the client has no OrbService at all.
ProjectEbonhold.OrbService=nil
check(A.OrbCapability()=='NO_ORB_SERVICE','absent OrbService is reported as the explicit legacy capability')
permits('no OrbService',nil)
H.Board(CARDS);H.Notify();H.Advance(.3)
local n=#H.actions;local ok,why=A.Reroll()
check(ok==true and #H.actions==n+1,'no OrbService: ordinary Reroll still works ('..tostring(why)..')');settle()
-- Explicit legacy capability: an older pending-only OrbService without any
-- IsStateKnown member (retained contract from tests/prototype/automation.lua).
ProjectEbonhold.OrbService={IsOfferPending=function()return false end}
check(A.OrbCapability()=='PENDING_ONLY','pending-only OrbService is reported as its own explicit capability')
permits('pending-only service, not pending',ProjectEbonhold.OrbService)
blocked('pending-only service, pending',{IsOfferPending=function()return true end},'Orb offer active -- manual action required')
ProjectEbonhold.OrbService=service(true,false)
check(A.OrbCapability()=='STATE_AWARE','full OrbService is reported as state-aware')
print('PASS rolling review R1 unknown Orb state checks='..checks)
