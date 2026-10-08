-- R1 scope for the automatic non-board paths (user scope reconciliation, 2026-09-21).
-- NEW test, not a rerun of any review probe. Every automatic caller of a
-- GameAdapter mutator passes AutoAllowed(), which asks the ordinary-board gate.
-- This test drives two of them through the real runtime -- the tome-lever step
-- (StepArm -> ToggleLever) and the finished-run save (StepSave -> Save) -- with
-- the same fixture twice: Orb state known (control: the action is sent once) and
-- Orb state unknown (the action is not sent). Manual user controls are not
-- gated by R1 and are not part of this test. Offline only.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function count(H,kind)local n=0;for _,a in ipairs(H.actions)do if a[1]==kind then n=n+1 end end;return n end
local function autoOn(H)
 local m=Nexus.Panel and Nexus.Panel._lastModel
 if not(m and m.auto==true)then SlashCmdList.NEXUS('auto');H.Advance(.2,.1)end
 m=Nexus.Panel and Nexus.Panel._lastModel
 check(m and m.auto==true,'fixture: ordinary automation is ON')
end

-- Tome lever (level 1, StepArm). Each run starts from fresh saved data; the
-- blocked case runs BEFORE its control, so nothing the control sent or saved
-- can keep the blocked case at zero.
local function Lever(known)
 NexusDB=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 ProjectEbonhold.OrbService={IsStateKnown=function()return known end,IsOfferPending=function()return false end}
 H.names[777001]='Tome of Gated Echo'
 H.AddEcho(300001,'Gated Echo',1,1,0);H.db[300001].requiredSpell=777001
 H.discovered[300001]=true;H.perks.discoveredEchoes=H.discovered
 H.playerLevel=1
 H.Boot()
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('plan',{ {spellId=200001,quality=1,stacks=2} }),'plan set')
 H.Notify();H.Advance(1)
 autoOn(H)
 H.Advance(5,.1)
 return count(H,'toggle'),H
end
local blockedSent=Lever(false)
check(blockedSent==0,'unknown Orb state: the automatic lever step sends nothing ('..blockedSent..')')
local sent=Lever(true)
check(sent>=1,'control: with Orb state known the automatic lever step sends ('..sent..')')

-- Finished-run save (level 80, StepSave).
local function Save(known)
 NexusDB=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 local state=true
 ProjectEbonhold.OrbService={IsStateKnown=function()return state end,IsOfferPending=function()return false end}
 H.Boot()
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('plan',{ {spellId=200001,quality=1,stacks=2} }),'plan set')
 -- One offering of this run is observed while the state is known (StepSave requires it).
 H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}});H.Notify();H.Advance(1)
 H.perks.currentChoice=nil
 local g={};for i=1,79 do g['Echo '..i]={{spellId=200000+i,quality=i%4}} end
 H.granted=g;H.playerLevel=80;H.Notify();H.Advance(1)
 state=known
 autoOn(H)
 H.Advance(8,.1)
 return count(H,'save'),H
end
blockedSent=Save(false)
check(blockedSent==0,'unknown Orb state: the finished run is not saved automatically ('..blockedSent..')')
sent=Save(true)
check(sent==1,'control: with Orb state known the finished run is saved once ('..sent..')')

-- An existing OrbService without IsStateKnown blocks the same automatic path.
do
 NexusDB=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 ProjectEbonhold.OrbService={IsOfferPending=function()return false end}
 H.names[777001]='Tome of Gated Echo'
 H.AddEcho(300001,'Gated Echo',1,1,0);H.db[300001].requiredSpell=777001
 H.discovered[300001]=true;H.perks.discoveredEchoes=H.discovered
 H.playerLevel=1
 H.Boot()
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('plan',{ {spellId=200001,quality=1,stacks=2} }),'plan set')
 H.Notify();H.Advance(1);autoOn(H);H.Advance(5,.1)
 check(count(H,'toggle')==0,'service without IsStateKnown: the automatic lever step sends nothing')
end
print('PASS automatic non-board paths send nothing while Orb state is unknown checks='..checks)
