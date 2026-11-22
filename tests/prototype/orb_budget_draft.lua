-- Start/Stop rework (2026-11-19, user-authorized): the Orb maximum is removed
-- as a player option. It is not optional and has no zero-limit stand-in. The
-- Orb window shows no maximum box, Max button, usage-against-maximum line or
-- approval text, and Start never asks for or uses an amount: a saved maximum
-- from an earlier version is neither shown nor applied, and the run is not
-- bounded by it. The run ends normally (complete, no Orbs, no source) or on Stop.
-- (Replaces the maximum-draft pin of BN-ORB-DEFAULT-OWNER-ANSWER-001/-002.)
local H=dofile('tests/prototype/orbs_support.lua');local A,O=H.A,H.O
local M=Nexus.OrbAuto
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
-- A maximum saved by an earlier version: kept in saved data, never applied.
assert(Nexus.OrbRuntime.SetLimit(1))
check(Nexus.Store.State().orbRefinement.maxOrbs==1,'fixture: an earlier saved maximum of 1')
local f=Nexus.OrbPanel.Show()
for _,k in ipairs({'limit','max','usage','approval'}) do check(not f[k]:IsShown(),'no '..k..' on the Orb window') end
check(f.start:GetText()=='Start' and f.start:IsEnabled(),'Start asks for no amount')
local OFFER={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}}
local function Taken()
 local out=H.Clone(H.granted)
 for _,es in pairs(out) do for i=#es,1,-1 do if es[i].spellId==O.source then table.remove(es,i);break end end end
 out['Desired A']=out['Desired A'] or {};table.insert(out['Desired A'],{spellId=410002,quality=2})
 H.granted=out;H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false;H.Notify();A.Poll()
end
H.granted['Disposable A']={{spellId=410001,quality=1},{spellId=410001,quality=1},{spellId=410001,quality=1}}
H.Notify();A.Poll();Nexus.OrbPanel.Refresh()
f.start:Click();H.Advance(.5)
for i=1,3 do
 check(H.Count('orb-spend')==i,'Orb '..i..' is spent: the saved maximum of 1 does not stop the run')
 O.offer=true;H.Board(OFFER);H.Advance(.5);Taken();H.Advance(.5)
end
check(not M.Active() and M.Status().state=='DONE' and H.Count('orb-spend')==3,'the run ends when the Wishlist is complete, after 3 Orbs')
check(Nexus.Store.State().orbRefinement.maxOrbs==1,'the earlier saved maximum is kept untouched (old saves)')
print('PASS orb_budget_draft: no maximum option; a saved earlier maximum is neither shown nor applied checks='..checks)
