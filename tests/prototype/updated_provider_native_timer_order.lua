-- The game's own auto-accept timer against Nexus's later-frame settle rule
-- (GameAdapter ChoiceActionable), adversarial frame order, offline.
--
-- Model of the captured client (perks_service.lua, static reading; nothing
-- of it is copied or executed): at the choice parse the client shows a timer
-- frame holding the card it chose; that frame's OnUpdate adds each frame's
-- elapsed time and, on the first frame its sum reaches 0.18 s, calls
-- SelectPerk with that card. It never re-checks its option. The replica below
-- behaves the same way. Assumed, as in CONTRACTS.md: GetTime() is constant
-- within a frame, a shown frame's OnUpdate runs on every frame, and its
-- elapsed time tracks GetTime() (the harness models all three).
--
-- Adversarial order: a driver frame that asks Nexus for an action EVERY frame
-- runs BEFORE the timer within each frame. The property: no Nexus Reroll,
-- Banish, Freeze or Take is admitted before the native timer has fired, for
-- 60, 20 and 10 fps, one long frame right after the parse, a first
-- observation in the parse instant and after it, and the option switched off
-- after arming. Then, with the
-- native Select pending, Nexus sends nothing (pending latch). Positive
-- control: with no armed timer, Nexus acts on the first admitted frame, and
-- that frame is measured.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local A1,A2,A3=200051,200052,200053
local function Card(id) return {spellId=id,quality=id%4} end
local function Boot()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=20
 H.service.GetServerActiveDesign=function() return 0 end
 H.Boot();return H
end
-- One race. `armed`: a native timer is armed at the parse. `firstSeenDelay`:
-- seconds after the parse before Nexus first reads the board. `frames`: the
-- frame steps after the parse, in order.
local function Race(label,o)
 local H=Boot()
 H.Board({Card(A1),Card(A2),Card(A3)}) -- the parse
 local parsedAt=H.now
 -- Worst case unless delayed: Nexus reads the new table in the same instant
 -- as the parse (the earliest a first observation can be).
 if not o.firstSeenDelay then Nexus.GameAdapter.Board() end
 local fired,firedAt=false,nil
 local nexusAt,nexusKind=nil,nil
 local driver=CreateFrame('Frame')
 local seen=false
 driver:SetScript('OnUpdate',function()
  if nexusAt then return end
  if H.now-parsedAt<(o.firstSeenDelay or 0) then return end
  Nexus.GameAdapter.Board();seen=true
  local ok=Nexus.GameAdapter[o.action or 'Reroll'](o.arg)
  if ok then nexusAt=H.now;nexusKind=o.action or 'Reroll' end
 end);driver:Show()
 if o.armed then
  local timer=CreateFrame('Frame');timer.t=0
  timer:SetScript('OnUpdate',function(self,elapsed)
   self.t=self.t+elapsed
   if self.t<0.18 then return end
   self:Hide();fired=true;firedAt=H.now
   H.service.SelectPerk(A2) -- the card it chose at the parse; never re-checked
  end);timer:Show()
 end
 if o.optionOff then o.optionOff(H) end
 for _,step in ipairs(o.frames) do H.Advance(step,step) end
 return {H=H,fired=fired,firedAt=firedAt,nexusAt=nexusAt,nexusKind=nexusKind,parsedAt=parsedAt,seen=seen}
end
local function Frames(step,seconds) local t={};for i=1,math.floor(seconds/step+.5) do t[i]=step end;return t end
local function Sent(H,kind) local n=0;for _,a in ipairs(H.actions) do if a[1]==kind then n=n+1 end end;return n end

for _,case in ipairs({
 {'60 fps',{armed=true,frames=Frames(1/60,1.5)}},
 {'20 fps',{armed=true,frames=Frames(0.05,1.5)}},
 {'10 fps (settle edge on a timer frame)',{armed=true,frames=Frames(0.1,1.5)}},
 {'a Banish, 10 fps',{armed=true,action='Banish',arg=0,frames=Frames(0.1,1.5)}},
 {'one long frame after the parse',{armed=true,frames={0.6,1/60,1/60,1/60}}},
 {'first read 0.1 s after the parse',{armed=true,firstSeenDelay=0.1,frames=Frames(1/60,1.5)}},
 {'option switched off after arming',{armed=true,frames=Frames(0.05,1.5),
   optionOff=function() local o=_G.ProjectEbonholdOptionsService;if o and o.SetSetting then pcall(o.SetSetting,o,'autoAcceptLoadoutEchoes',false) end end}},
 {'a Take, 20 fps',{armed=true,action='Take',arg=A1,frames=Frames(0.05,1.5)}},
}) do
 local r=Race(case[1],case[2])
 check(r.fired==true,case[1]..': fixture: the native timer fired')
 check(r.nexusAt==nil or r.nexusAt>r.firedAt,case[1]..': no Nexus action before the native pick: nexus='
  ..tostring(r.nexusAt and r.nexusAt-r.parsedAt)..' native='..tostring(r.firedAt-r.parsedAt))
 check(Sent(r.H,'reroll')==0 and Sent(r.H,'take')==1,case[1]..': with the native Select pending, Nexus sends nothing: reroll='
  ..Sent(r.H,'reroll')..' take='..Sent(r.H,'take'))
end
-- Positive control and measurement: no armed timer, 60 fps.
do
 local r=Race('no timer',{frames=Frames(1/60,1.5)})
 check(r.nexusAt~=nil and Sent(r.H,'reroll')==1,'no timer: Nexus rerolls once')
 local delay=r.nexusAt-r.parsedAt
 print(string.format('MEASURE no-timer admit delay at 60 fps: %.3f s (settle 0.2 s + later frame)',delay))
 check(delay<0.3,'no timer: the reroll is admitted within 0.3 s of the parse: '..string.format('%.3f',delay))
end
print('PASS updated-provider native timer order: no Nexus action before an armed native pick in any frame order tested ('..checks..' checks)')
