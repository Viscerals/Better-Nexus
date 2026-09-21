-- Review finding F4 on range eadff8a..578c77e. NEW test written from the
-- independent review's reproduction. Real OrbRuntime/OrbAdapter; mocked game
-- services; no native evidence.
--
-- More than 60 s after the reload the recovery pump reads every 5 s. The owed
-- offer opens just after a slow read and the player answers it before the next
-- one. The observation of the offer and of the choice is event-driven (the
-- read-only SelectPerk observer), so it does not depend on the slow read. The
-- WAIT_OFFER text must match that.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false)
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery')
local reads=0;local realRead=A.Orbs.Read;A.Orbs.Read=function(...)reads=reads+1;return realRead(...)end
H.Advance(70,.05)
local waiting=M.Status();reads=0
check(waiting.recovery.kind=='WAIT_OFFER' and waiting.recovery.observing==true,'no offer yet; the observer is installed')
H.Advance(100,.05)
check(reads>=15 and reads<=25,'slow cadence: about one read per 5 s ('..reads..' in 100 s)')
-- Align to the moment just after a slow read.
reads=0;local guard=0;while reads==0 do H.Advance(.05,.05);guard=guard+1;assert(guard<400,'a slow read happens')end
O.charges=O.charges-1;O.offer=true
H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});H.Notify();A.Poll()
reads=0;H.Advance(2,.05)
check(reads==0,'no timed recovery read while the offer was open before the choice')
local actions=#H.actions
check(H.service.SelectPerk(410002)==true,'manual native choice 2 s after the offer opened')
check(#H.actions==actions+1,'the observation sent nothing: only the manual choice reached the game')
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and receipt.offerKey and receipt.offerSeenAfterReload and receipt.choiceObserved and receipt.selectedKey=='410002:2',
 'offer and choice are recorded at the moment of the choice')
check(M.Status().spent+M.Status().reserved==1,'exposure neither refunded nor doubled')
-- The result arrives and the offer closes before any timed read.
local out=H.Clone(H.granted);local removed=false
for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
assert(removed);out['Desired A']={{spellId=410002,quality=2}};H.granted=out
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll()
H.Advance(1,.05)
local s=M.Status()
check(not s.pending and s.state=='STOPPED' and s.spent==1 and s.reserved==0,'settled from the exact result within the fast window that the choice reopened')
check(H.Count('orb-spend')==1 and H.Count('take')==1,'no recovery mutation')
check(waiting.reason:find('at the moment you make it',1,true)~=nil,'text: the choice is recorded when it is made, not at a timed read')
print('PASS F4 event-driven offer and choice observation during the slow cadence checks='..checks)
