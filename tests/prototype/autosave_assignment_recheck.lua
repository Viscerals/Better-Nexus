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
-- Exactly one: more updates, longer than the adapter's save spacing, and a
-- second round of assignment changes add no further save.
for _=1,3 do H.Notify();H.Advance(4,.1) end
assign('Plan A',200001);H.Advance(4,.1)
assign('Plan B',200080);H.Advance(8,.1)
s=saves()
check(#s==1,'later updates and assignment changes add no second save ('..#s..')')

-- W1: the updated game client no longer exports PerkService.SaveServerBuildSlot.
-- The scenario above is the old-provider success control (the harness supplies
-- that function). Below, the same finished run on fresh boots of the real TOC
-- with the provider function REMOVED from the fixture service: automatic
-- saving is reported unavailable exactly once, no further attempt reads the
-- provider, nothing is saved and nothing else changes. An ordinary refused
-- call (the function exists and returns false) keeps being retried and then
-- saves. Synthetic harness; no native client behaviour is established here.
local UNAVAILABLE='Automatic saving is not available with this game client'
local printed={}
local rawPrint=print
print=function(...)
 local parts={}
 for i=1,select('#',...) do parts[#parts+1]=tostring((select(i,...))) end
 printed[#printed+1]=table.concat(parts,' ')
end
local function count(list,fragment)
 local n=0
 for _,line in ipairs(list) do if tostring(line):find(fragment,1,true) then n=n+1 end end
 return n
end
-- A notice reaches the player by chat or by print; either route counts once.
local function said(h,fragment) return math.max(count(h.chat,fragment),count(printed,fragment)) end
local function savesOf(h) local n=0;for _,a in ipairs(h.actions)do if a[1]=='save' then n=n+1 end end;return n end
local function same(a,b)
 if type(a)~='table' or type(b)~='table' then return a==b end
 for k,v in pairs(a) do if not same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function boot(prepare)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 printed={}
 local h=dofile('tests/prototype/harness.lua')
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,IsOfferPending=function()return false end}
 if prepare then prepare(h) end
 h.Boot()
 return h
end
local function assignedSlot(h)
 h.perks.serverBuildSlots[1]={name='Main',verified=true,echoes=H.Clone(saved)}
 h.perks.serverActiveSlot=1
end
-- Removes the provider's save function from the real fixture service and
-- counts every later read of that absent name (each adapter save attempt
-- reads it once). __index runs only for absent keys, so nothing else changes.
local function removeSave(h,probe)
 h.service.SaveServerBuildSlot=nil
 setmetatable(h.service,{__index=function(_,k)
  if k=='SaveServerBuildSlot' then probe.n=probe.n+1 end
  return nil
 end})
end
-- The finished run of the scenario above: one board seen, then level 80 with
-- 79 owned Echoes and no board, Auto still OFF.
local function finishRun(h)
 h.Notify();h.Advance(1)
 h.Board({{spellId=200002,quality=2},{spellId=200020,quality=0},{spellId=200021,quality=1}});h.Notify();h.Advance(1)
 h.perks.currentChoice=nil
 h.granted=H.Clone(g);h.playerLevel=80;h.Notify();h.Advance(1)
 check(Nexus.RecomputeStats().autoEnabled==false,'W1 fixture: Auto starts OFF')
end
local function autoOn(h)
 SlashCmdList.NEXUS('auto');h.Advance(.2,.1)
 check(Nexus.RecomputeStats().autoEnabled==true,'W1 fixture: Auto ON')
end

-- W1-a. Assigned Saved Build, provider save function absent.
do
 local probe={n=0}
 local h=boot(function(h) assignedSlot(h);removeSave(h,probe) end)
 local a=Nexus.GameAdapter
 check(rawget(ProjectEbonhold.PerkService,'SaveServerBuildSlot')==nil,'W1-a fixture: the provider exports no save function')
 check(a.SetLoadoutWishlistIdentity(1,'Plan B',{ {spellId=200080,quality=200080%4,stacks=1} }),'W1-a fixture: assign Plan B')
 finishRun(h)
 local slotsBefore=h.Clone(h.perks.serverBuildSlots)
 check(said(h,UNAVAILABLE)==0,'W1-a: nothing is reported while Auto is OFF')
 autoOn(h)
 h.Notify();h.Advance(8,.1)
 check(savesOf(h)==0,'W1-a: no save is sent')
 check(said(h,UNAVAILABLE)==1,'W1-a: automatic saving is reported unavailable once ('..said(h,UNAVAILABLE)..')')
 check(said(h,'Save sent')==0,'W1-a: no save is reported as sent')
 local probes=probe.n
 check(probes>=1,'W1-a: the real runtime reached the adapter save')
 -- Unchanged context, well past the adapter's save spacing, plus a second
 -- round of assignment changes: no further attempt and no second notice.
 for _=1,3 do h.Notify();h.Advance(4,.1) end
 check(a.SetLoadoutWishlistIdentity(1,'Plan A',{ {spellId=200001,quality=200001%4,stacks=1} }),'W1-a: reassign Plan A');h.Advance(4,.1)
 check(a.SetLoadoutWishlistIdentity(1,'Plan B',{ {spellId=200080,quality=200080%4,stacks=1} }),'W1-a: reassign Plan B');h.Advance(8,.1)
 check(probe.n==probes,'W1-a: no repeated save attempt reads the provider ('..probes..' -> '..probe.n..')')
 check(said(h,UNAVAILABLE)==1,'W1-a: still exactly one notice ('..said(h,UNAVAILABLE)..')')
 check(savesOf(h)==0 and said(h,'Save sent')==0,'W1-a: still nothing saved or reported as sent')
 -- State is preserved: the Saved Build and its name, the assignment, the
 -- autoSave setting and the Auto master switch.
 check(same(slotsBefore,h.perks.serverBuildSlots),'W1-a: Saved Build contents and name unchanged')
 check(a.AssignedWishlist().name=='Plan B','W1-a: the assignment is kept')
 check(Nexus.Store.Settings().autoSave==true,'W1-a: the autoSave setting is unchanged')
 check(Nexus.RecomputeStats().autoEnabled==true,'W1-a: Auto stays ON')
end

-- W1-b. Positive control: the provider function exists and refuses (returns
-- false). That ordinary refusal is not "unavailable": it is retried without
-- the notice, and the save goes through once the provider accepts.
-- The runtime steps only on a trigger (forced, dirty data, a deadline or an
-- authorization change: AutomationRuntime RunUpdate), and a refused save
-- schedules none, so an idle Notify alone causes no further step. The retry is
-- therefore driven by the trigger the scenario at the top establishes: an
-- assignment change re-runs the save gate at once. Plan A blocks the gate,
-- Plan B approves it again, so each round is one more eligible save step.
local function reassignRound(h,a,label)
 check(a.SetLoadoutWishlistIdentity(1,'Plan A',{ {spellId=200001,quality=200001%4,stacks=1} }),label..': reassign Plan A');h.Advance(4,.1)
 check(a.SetLoadoutWishlistIdentity(1,'Plan B',{ {spellId=200080,quality=200080%4,stacks=1} }),label..': reassign Plan B');h.Advance(8,.1)
end
do
 local calls,accept=0,false
 local h=boot(function(h)
  assignedSlot(h)
  h.service.SaveServerBuildSlot=function(id,name)
   calls=calls+1
   if not accept then return false end
   h.actions[#h.actions+1]={'save',id,name};return true
  end
 end)
 local a=Nexus.GameAdapter
 check(a.SetLoadoutWishlistIdentity(1,'Plan B',{ {spellId=200080,quality=200080%4,stacks=1} }),'W1-b fixture: assign Plan B')
 finishRun(h)
 autoOn(h)
 h.Notify();h.Advance(8,.1)
 local firstCalls=calls
 check(firstCalls>=1,'W1-b: turning Auto ON reaches the provider save ('..firstCalls..')')
 reassignRound(h,a,'W1-b round 1')
 local secondCalls=calls
 check(secondCalls>firstCalls,'W1-b: an ordinary refused save is retried on the next eligible step ('..firstCalls..' -> '..secondCalls..')')
 reassignRound(h,a,'W1-b round 2')
 check(calls>secondCalls,'W1-b: and again on the one after ('..secondCalls..' -> '..calls..')')
 check(savesOf(h)==0,'W1-b: nothing is saved while the provider refuses')
 check(said(h,UNAVAILABLE)==0,'W1-b: a refused call is not reported as an unavailable capability')
 accept=true
 reassignRound(h,a,'W1-b round 3')
 check(savesOf(h)==1,'W1-b: the retry saves once the provider accepts ('..savesOf(h)..')')
 check(said(h,UNAVAILABLE)==0,'W1-b: and still no unavailable notice')
end

-- W1-c. First-run path (no Saved Build anywhere, first-run plan), old provider:
-- the seeding save is sent. This is the control for W1-d.
local function firstRun(h)
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('First plan',{ {spellId=200080,quality=200080%4,stacks=1} }),'W1 fixture: set the first-run plan')
 finishRun(h)
 autoOn(h)
 for _=1,3 do h.Notify();h.Advance(4,.1) end
end
do
 local h=boot()
 firstRun(h)
 local first
 for _,act in ipairs(h.actions)do if act[1]=='save' then first=first or act end end
 check(savesOf(h)==1 and first[2]==1 and first[3]=='Nexus','W1-c: old provider: the first run is seeded into Saved Build 1 ('..savesOf(h)..')')
 check(said(h,UNAVAILABLE)==0,'W1-c: no unavailable notice with the old provider')
end

-- W1-d. First-run path, provider save function absent: the same single
-- notice, no save, no claim of a sent save, and no instruction to use a
-- manual save whose presence in this game client is not established here.
do
 local probe={n=0}
 local h=boot(function(h) removeSave(h,probe) end)
 firstRun(h)
 check(savesOf(h)==0,'W1-d: no save is sent')
 check(said(h,UNAVAILABLE)==1,'W1-d: automatic saving is reported unavailable once ('..said(h,UNAVAILABLE)..')')
 check(said(h,'first-run save sent')==0 and said(h,'attempting to store')==0,'W1-d: no first-run save is reported as sent')
 check(said(h,"couldn't create the first Saved Build")==0,'W1-d: no manual-save instruction is given for the absent capability')
 local probes=probe.n
 check(probes>=1,'W1-d: the real runtime reached the adapter save')
 -- Further eligible steps: Auto OFF then ON is an authorization change, which
 -- the runtime answers with one decision step each time (ToggleAuto).
 for round=1,2 do
  SlashCmdList.NEXUS('auto');h.Advance(.2,.1)
  check(Nexus.RecomputeStats().autoEnabled==false,'W1-d round '..round..': Auto OFF')
  autoOn(h);h.Notify();h.Advance(4,.1)
 end
 check(probe.n==probes,'W1-d: no repeated save attempt reads the provider ('..probes..' -> '..probe.n..')')
 check(said(h,UNAVAILABLE)==1 and savesOf(h)==0,'W1-d: still one notice and nothing saved')
 check(next(h.perks.serverBuildSlots)==nil,'W1-d: no Saved Build was created')
 check(Nexus.GameAdapter.Wishlist()~=nil,'W1-d: the first-run plan is kept')
 check(Nexus.Store.Settings().autoSave==true and Nexus.RecomputeStats().autoEnabled==true,'W1-d: autoSave and Auto are unchanged')
end
print=rawPrint
print('PASS assignment writes no build itself; Auto OFF saves nothing; Auto ON at level 80 re-checks at once after an assignment change='..checks)
