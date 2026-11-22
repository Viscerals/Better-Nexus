-- Start/Stop rework (2026-11-19). The earlier maximum EditBox is gone from
-- the player's controls: during a run nothing can be typed or approved, Start
-- is locked while the run is ON, Stop is offered, and a hidden box submits
-- nothing even when its Enter handler is called directly.
-- (Replaces the strict legacy maximum EditBox lock pin.)
local H=dofile('tests/prototype/orbs_support.lua');local A,O=H.A,H.O
local M=Nexus.OrbAuto
dofile('tests/prototype/legacy_editbox_support.lua')(H)
H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
local f=Nexus.OrbPanel.Show()
assert(not f.limit:IsShown() and not f.max:IsShown(),'idle: no maximum box or Max button')
assert(M.Start(),'Start');H.Advance(.5);Nexus.OrbPanel.Refresh()
assert(H.Count('orb-spend')==1,'one Orb opens a draw')
local function locked(reason)
 assert(not f.limit:IsShown() and not f.max:IsShown(),reason..': a maximum control is shown')
 assert(not f.start:IsEnabled() and f.stop:IsEnabled(),reason..': Start must be locked and Stop offered')
 local actions=#H.actions
 f.limit:SetText('999');f.limit:GetScript('OnEnterPressed')(f.limit);Nexus.OrbPanel.Refresh()
 assert(#H.actions==actions and M.Active(),reason..': a direct Enter on the hidden box changed the run or sent something')
end
locked('waiting for the offer')
O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});H.Advance(.5);Nexus.OrbPanel.Refresh()
assert(H.Count('take')==1);locked('choice submitted')
f.stop:Click();assert(not M.Active(),'Stop ends the run')
Nexus.OrbPanel.Refresh()
-- (2026-11-19 decision) Stop does not erase the sent choice: Start is offered
-- and rejoins it; the rejoined run sends nothing before its answer.
assert(f.start:IsEnabled(),'while the choice is still in flight, Start is offered to rejoin it')
local sent=#H.actions
f.start:Click();H.Advance(1);Nexus.OrbPanel.Refresh()
assert(M.Active() and #H.actions==sent,'the rejoined run sends nothing before the choice is answered')
f.stop:Click();assert(not M.Active(),'Stop ends the rejoined run')
H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false;H.Notify();A.Poll()
Nexus.OrbPanel.Refresh()
assert(f.start:IsEnabled() and not f.stop:IsEnabled(),'after Stop, Start is offered again and Stop is not')
assert(H.Count('orb-spend')==1 and H.Count('take')==1,'only the run itself sent anything')
print('PASS no maximum EditBox: run locks Start, offers Stop, hidden box submits nothing')
