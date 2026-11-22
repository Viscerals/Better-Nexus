-- Start/Stop rework (2026-11-19): the Orb window's real Start starts the run
-- with no maximum; closing the window leaves the run going; Stop ends it.
-- (Replaces the earlier maximum-approval and Pause/Resume strip pin.)
local H=dofile('tests/prototype/orbs_support.lua');local M,O=Nexus.OrbAuto,H.O
H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
local OFFER={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}}
local function Taken(id,q)
 local out=H.Clone(H.granted)
 for _,es in pairs(out) do for i=#es,1,-1 do if es[i].spellId==O.source then table.remove(es,i);break end end end
 out[H.names[id]]=out[H.names[id]] or {};table.insert(out[H.names[id]],{spellId=id,quality=q})
 H.granted=out;H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false;H.Notify();H.A.Poll()
end
local f=Nexus.OrbPanel.Show()
assert(not f.limit:IsShown() and not f.max:IsShown(),'no maximum control')
f.start:Click();H.Advance(.5)
assert(M.Active() and H.Count('orb-spend')==1,'actual Start starts the run and spends one Orb')
local close
for _,b in ipairs(H.frames)do if b:GetParent()==f and b:GetText()=='Close'then close=b end end
assert(close);close:Click();assert(not f:IsShown() and M.Active(),'closing the window leaves the run going')
O.offer=true;H.Board(OFFER);H.Advance(.5)
assert(H.Count('take')==1,'closed window: the offer is answered')
Taken(410002,2);H.Advance(.5)
assert(H.Count('orb-spend')==2,'closed window: the run continues with the next Orb')
Nexus.OrbPanel.Show();assert(f.stop:IsEnabled(),'Stop is offered while the run is ON')
f.stop:Click();assert(not M.Active(),'Stop ends the run')
O.offer=true;H.Board(OFFER);H.Advance(1)
assert(H.Count('take')==1 and H.Count('orb-spend')==2,'nothing is sent after Stop')
assert(Nexus.RecomputeStats().autoEnabled==false,'ordinary rolling stays OFF')
print('PASS actual Start/Close/Stop with a continuing run and no maximum')
