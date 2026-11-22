-- Start/Stop rework (2026-11-19, user-authorized): there is no paused run to
-- resume, so there is no Resume target and no target review. A run always
-- acts for the active loadout's Wishlist at each pass; a loadout (slot) switch
-- ends the run. The Orb window never shows Review target or Cancel review.
-- (Replaces the M6 Resume-target review pin.)
local H=dofile('tests/prototype/orbs_support.lua');local A,O=H.A,H.O
local M=Nexus.OrbAuto
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
local f=Nexus.OrbPanel.Show()
check(not f.review:IsShown(),'no review control before a run')
f.start:Click();H.Advance(.5);Nexus.OrbPanel.Refresh()
check(M.Active() and not f.review:IsShown(),'no review control during a run')
H.perks.serverActiveSlot=2;H.Notify();A.Poll();H.Advance(.5);Nexus.OrbPanel.Refresh()
check(not M.Active() and M.Status().reason:find('active loadout changed',1,true),'a slot switch ends the run and says so')
check(not f.review:IsShown() and not f.resume:IsShown(),'no review or Resume after it')
O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});H.Advance(1)
check(H.Count('take')==0 and H.Count('orb-spend')==1,'nothing is sent for the other loadout')
print('PASS orb_target_review: no Resume target or review; a slot switch ends the run checks='..checks)
