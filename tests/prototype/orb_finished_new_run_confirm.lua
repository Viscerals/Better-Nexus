-- Start/Stop rework (2026-11-19). The earlier risk was a primary control that
-- changed meaning under the player (Pause, Resume, then "Start new run" with a
-- maximum filled in), so one press after a finished run spent again. Start is
-- now one fixed control: it never changes its words, it is unavailable while
-- the run is ON, and after a run ends it is offered only when there is work.
-- (Replaces the two-press new-run confirmation pin.)
local H=dofile('tests/prototype/orbs_support.lua');local A,O=H.A,H.O
local M=Nexus.OrbAuto
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=1}})
SlashCmdList.NEXUS('orbs');local f=assert(NexusOrbPanel);Nexus.OrbPanel.Refresh()
check(f.start:GetText()=='Start' and f.start:IsEnabled(),'Start is offered with its fixed words')
f.start:Click();H.Advance(.5);Nexus.OrbPanel.Refresh()
check(M.Active() and H.Count('orb-spend')==1,'one press starts the run and spends one Orb')
check(f.start:GetText()=='Start' and not f.start:IsEnabled(),'while ON, Start keeps its words and is unavailable')
f.start:Click();H.Advance(.5)
check(H.Count('orb-spend')==1,'a press on the unavailable Start spends nothing')
O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});H.Advance(.5)
local out=H.Clone(H.granted)
for _,es in pairs(out) do for i=#es,1,-1 do if es[i].spellId==O.source then table.remove(es,i);break end end end
out['Desired A']={{spellId=410002,quality=2}}
H.granted=out;H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false;H.Notify();A.Poll();H.Advance(.5)
Nexus.OrbPanel.Refresh()
check(not M.Active() and M.Status().state=='DONE','the run finished: the Wishlist is complete')
check(f.start:GetText()=='Start' and not f.start:IsEnabled(),'a finished run with nothing to do offers no Start')
local spends=H.Count('orb-spend');f.start:Click();H.Advance(.5)
check(H.Count('orb-spend')==spends and not M.Active(),'a press after the finished run spends nothing')
print('PASS orb_finished_new_run_confirm: one fixed Start, unavailable while ON and after a finished run with nothing to do checks='..checks)
