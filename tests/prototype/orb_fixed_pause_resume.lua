-- Start/Stop rework (2026-11-19, user-authorized): the player's Orb controls
-- are Start and Stop only. During a run the full Orb window shows Stop and a
-- Start that is unavailable, never Pause or Resume, in fixed places; a
-- repeated press of either changes nothing; Stop ends the run at once.
-- (Replaces the M6 fixed Pause/Resume pin.)
local H=dofile('tests/prototype/orbs_support.lua');local O=H.O
local M=Nexus.OrbAuto
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
local f=Nexus.OrbPanel.Show()
local sx,sy=select(4,f.start:GetPoint());local tx,ty=select(4,f.stop:GetPoint())
f.start:Click();f.start:Click();H.Advance(.5);Nexus.OrbPanel.Refresh()
check(M.Active() and H.Count('orb-spend')==1,'a repeated Start starts one run and spends one Orb')
check(not f.pause:IsShown() and not f.resume:IsShown(),'no Pause or Resume during the run')
check(f.start:IsShown() and not f.start:IsEnabled() and f.stop:IsShown() and f.stop:IsEnabled(),'Start unavailable, Stop offered')
local sx2,sy2=select(4,f.start:GetPoint());local tx2,ty2=select(4,f.stop:GetPoint())
check(sx==sx2 and sy==sy2 and tx==tx2 and ty==ty2,'Start and Stop keep their places')
f.stop:Click();f.stop:Click();Nexus.OrbPanel.Refresh()
check(not M.Active(),'Stop ends the run; a repeated Stop changes nothing')
O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});H.Advance(1)
check(H.Count('take')==0 and H.Count('orb-spend')==1,'nothing is sent after Stop')
check(not f.pause:IsShown() and not f.resume:IsShown(),'still no Pause or Resume after the run')
print('PASS orb_fixed_pause_resume: Start and Stop only, fixed places, no Pause or Resume checks='..checks)
