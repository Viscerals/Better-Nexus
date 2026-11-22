-- Start/Stop rework (2026-11-19, user-authorized): no Resume target review
-- exists, so no review click can act on another target. A fresh run reads the
-- active loadout's Wishlist at every pass: a Wishlist changed during the run is
-- the target set of the next pass, with no review or approval.
-- (Replaces the M7 review-identity pin.)
local H=dofile('tests/prototype/orbs_support.lua');local A,O=H.A,H.O
local M=Nexus.OrbAuto
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=1}})
local f=Nexus.OrbPanel.Show()
f.start:Click();H.Advance(.5)
check(M.Active() and H.Count('orb-spend')==1,'setup: a run spent one Orb')
-- the Wishlist changes to another target while the offer is awaited
H.OrbPlan({{spellId=410004,quality=3,stacks=1}})
O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});H.Advance(.5)
check(H.Count('take')==1 and H.actions[#H.actions][2]==410004,'the next pass chooses for the changed Wishlist, without a review')
check(not f.review:IsShown(),'no review control')
M.Stop()
print('PASS orb_review_identity: no review; each pass reads the current Wishlist checks='..checks)
