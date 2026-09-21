-- Review finding F3 on range eadff8a..578c77e. NEW test written from the
-- independent review's reproduction (early-ownership order after a reload). Real
-- OrbRuntime/OrbAdapter; mocked game services; no native evidence.
--
-- The player chooses on the matched offer. The exact result ownership arrives
-- before the next recovery read, while the game still flags the offer as
-- pending. The observed choice must not be discarded. Settlement stays as
-- strict as before: it still needs the closed offer and the exact fresh result.
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan();H.Approve(2,false);check(M.Stop(),'stop before the offer');H.Offer()
local source=O.source
H.Fire('PLAYER_LOGOUT')
if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
-- Review 2 finding G1: count every CALL to the mocked entry points after the
-- reload, refused calls included. H.Count('take') sees accepted calls only, and
-- the mock refuses a second SelectPerk while the player's select is pending.
local calls={select=0,spend=0,player=0}
do
 local rawSelect=H.service.SelectPerk
 H.service.SelectPerk=function(...)calls.select=calls.select+1;return rawSelect(...)end
 local orb=ProjectEbonhold.OrbService;local rawSpend=orb.ConfirmSpend
 orb.ConfirmSpend=function(...)calls.spend=calls.spend+1;return rawSpend(...)end
end
local function playerSelect(id)calls.player=calls.player+1;return H.service.SelectPerk(id)end
local function checkCalls(where)
 check(calls.select==calls.player,where..': every SelectPerk call after the reload is a scripted player call (calls='..calls.select..', player='..calls.player..')')
 check(calls.spend==0,where..': no ConfirmSpend call after the reload (calls='..calls.spend..')')
end
M=Nexus.OrbRuntime;check(M.Status().state=='RECOVERY','passive recovery');H.Advance(.5)
check(M.Status().recovery.kind=='OFFER_OPEN' and M.Status().recovery.observing,'matched offer under observation')
local function result(id,q,name)
 local out=H.Clone(H.granted);local removed=false
 for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
 assert(removed);out[name]=out[name] or {};table.insert(out[name],{spellId=id,quality=q});return out
end
-- Between two recovery reads: the choice, then early exact ownership. The offer
-- flag and the board are still up.
-- The event-driven pump is suppressed here (as when it cannot run), so the next
-- timed read alone meets: recorded observer choice + early ownership + open flag.
local realPump=M.Pump;M.Pump=function()end
check(playerSelect(410002)==true,'manual native choice')
M.Pump=realPump
H.granted=result(410002,2,'Desired A');H.Notify();A.Poll()
H.Advance(.5)
local receipt=Nexus.Store.State().orbRefinement.pending
check(receipt and receipt.choiceObserved and receipt.selectedKey=='410002:2','the observed choice is kept although ownership changed early')
local s=M.Status()
check(s.pending and s.recovery.kind=='WAIT_RESULT','offer still flagged: waiting, not settled and not discarded (kind='..tostring(s.recovery.kind)..')')
check(s.spent+s.reserved==1,'exposure unchanged')
-- The offer closes. Only now can the exact result settle the action.
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false;H.Notify();A.Poll();H.Advance(.5)
s=M.Status()
check(not s.pending and s.state=='STOPPED' and s.spent==1 and s.reserved==0,'closed offer plus exact result settles')
check(H.Count('orb-spend')==1 and H.Count('take')==1,'no recovery mutation')
checkCalls('end')
print('PASS F3 early exact ownership keeps the observed choice; settlement unchanged checks='..checks)
