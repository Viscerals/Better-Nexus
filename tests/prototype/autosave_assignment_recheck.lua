-- Pins the behaviour the automatic-save warning describes (Help, Quick Start,
-- Journal tooltips, README): assigning a Wishlist writes no Saved Build by
-- itself, Auto OFF leaves the Saved Build untouched, and with Auto ON at level
-- 80 after a finished run a changed assignment makes the save gate check again
-- at once, so a replacement can follow without a new run. Synthetic harness;
-- native timing is not established here.
NexusDB=nil;WishlistRealizerDB=nil
local H=dofile('tests/prototype/harness.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function saves()local out={};for _,a in ipairs(H.actions)do if a[1]=='save' then out[#out+1]=a end end;return out end
ProjectEbonhold.OrbService={IsStateKnown=function()return true end,IsOfferPending=function()return false end}
-- Saved Build 1 holds 200001..200079; the finished run holds 200002..200080.
local saved={}
for i=1,79 do saved[#saved+1]={spellId=200000+i,quality=i%4,stacks=1} end
H.perks.serverBuildSlots[1]={name='Main',verified=true,echoes=saved}
H.perks.serverActiveSlot=1
H.Boot()
local A=Nexus.GameAdapter
-- Plan A wants 200001 (only in the Saved Build); Plan B wants 200080 (only in the run).
local function assign(name,id)
 check(A.SetLoadoutWishlistIdentity(1,name,{ {spellId=id,quality=id%4,stacks=1} }),'assign '..name)
end
assign('Plan A',200001)
H.Notify();H.Advance(1)
H.Board({{spellId=200002,quality=2},{spellId=200020,quality=0},{spellId=200021,quality=1}});H.Notify();H.Advance(1)
H.perks.currentChoice=nil
local g={};for i=2,80 do g['Echo '..i]={{spellId=200000+i,quality=i%4}} end
H.granted=g;H.playerLevel=80;H.Notify();H.Advance(1)
check(Nexus.RecomputeStats().autoEnabled==false,'Auto starts OFF')

-- Auto OFF: neither the finished run nor an assignment change writes a build.
H.Advance(8,.1)
check(#saves()==0,'Auto OFF: the finished run is not saved')
assign('Plan B',200080);H.Advance(8,.1)
check(#saves()==0,'Auto OFF: an assignment the gate would approve still saves nothing')

-- Auto ON with Plan A: the run is a regression for Plan A, so it is blocked.
assign('Plan A',200001);H.Advance(1)
SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
check(Nexus.RecomputeStats().autoEnabled==true,'Auto ON')
H.Advance(8,.1)
check(#saves()==0,'Auto ON: a run that is worse for the assigned Wishlist is not saved')

-- Changing the assignment, with no other input and no new run, re-runs the
-- gate at once: the same finished run is now +1 for Plan B and replaces the
-- active Saved Build under the Wishlist's name.
assign('Plan B',200080);H.Advance(8,.1)
local s=saves()
check(#s==1,'Auto ON at level 80: an assignment change is followed by one save ('..#s..')')
check(s[1] and s[1][2]==1 and s[1][3]=='Plan B','the save targets the active Saved Build and uses the Wishlist name')
print('PASS assignment writes no build itself; Auto OFF saves nothing; Auto ON at level 80 re-checks at once after an assignment change='..checks)
