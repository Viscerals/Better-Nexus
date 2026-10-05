-- D2: a change of the assigned Wishlist must reach the HUD's static plan
-- whatever order the five-second fallback sees it in.
--
-- The runtime keeps the assigned Wishlist and its plan in a cached static
-- context. It is rebuilt when a notification marks the slots dirty, or when
-- the fallback signature finds a mismatch in a STATIC component. Three links
-- let a real change be missed indefinitely:
--   * a notification consumed by a non-dirty reader (the Orb read context's
--     GameAdapter.EchoActiveSlotGeneration) lost its dirty marking;
--   * every full step advanced the fallback baseline of the slots and
--     active-slot generations, also when that step did not rebuild the static
--     context, so a later fallback no longer saw them;
--   * the fallback classified only the FIRST mismatched field, so a dynamic
--     field listed earlier (granted, locked) hid a static one listed later
--     (association), and the new baseline absorbed it.
-- Loadout 2 is assigned W (40/79 with the rolled copies), loadout 5 is
-- assigned W2 (35/79 with the same rolled copies).
local S=dofile('tests/prototype/progress_refresh_support.lua')
local C=S.Checker('fallback_static_invalidation')
local check=C.check
local A

local W=S.Rows(S.Ordinary(1,79))
local W2spec={}
for i=6,40 do W2spec[#W2spec+1]={200000+i,1,false} end
for i=41,79 do W2spec[#W2spec+1]={200000+i,i<=45 and 2 or 1,false} end
local W2=S.Rows(W2spec)
local function Boot()
 local H=S.Boot({granted=S.GA,active=2,locked={},
  slots={[2]={name='Build Two',verified=true,echoes=S.SlotRows(S.GA)},
   [5]={name='Build Five',verified=true,echoes=S.SlotRows(S.GA)},
   [101]={name='Synthetic W',verified=false,echoes=S.Copy(W)},
   [102]={name='Synthetic W2',verified=false,echoes=S.Copy(W2)}},
  associations={[2]=S.Association(101,'Synthetic W',W),[5]=S.Association(102,'Synthetic W2',W2)}})
 A=Nexus.GameAdapter
 local h=S.Hud()
 check(h.name=='Synthetic W' and h.owned==40 and h.total==79,'fixture: loadout 2 shows W 40/79: '..S.Text(h))
 return H
end
local function OnW2() local h=S.Hud() return h.name=='Synthetic W2' and h.owned==35 and h.total==79 end
-- An ordinary step that does not rebuild the static plan: a board notification.
local function UnrelatedStep(H)
 H.Board({{spellId=200081,quality=S.Q(200081)},{spellId=200082,quality=S.Q(200082)},{spellId=200083,quality=S.Q(200083)}})
 H.Advance(.5)
end
local function OrbRead() return A.EchoActiveSlotGeneration() end

-- 1. Controls.
do
 local H=Boot();H.perks.serverActiveSlot=5;H.Notify()
 check(S.Within(H,1,OnW2)~=nil,'notified switch: W2 35/79 within 1 s: '..S.Text(S.Hud()))
end
do
 local H=Boot();H.perks.serverActiveSlot=5
 check(S.Within(H,5.5,OnW2)~=nil,'silent switch: W2 35/79 within the fallback period: '..S.Text(S.Hud()))
end

-- 2. A notification consumed by the Orb-style read keeps its dirty marking:
-- the switch is handled by the next poll, as an unconsumed one is.
do
 local H=Boot();H.perks.serverActiveSlot=5;H.Notify();OrbRead()
 check(S.Within(H,0.5,OnW2)~=nil,'consumed notification: W2 within 0.5 s (one poll): '..S.Text(S.Hud()))
end

-- 3. Ordering A: the active-slot change is first seen by an Orb-style read
-- (no notification), an unrelated step runs, then a dynamic change (granted)
-- makes the fallback's first mismatch "granted" while "association" follows.
do
 local H=Boot();H.perks.serverActiveSlot=5;OrbRead()
 UnrelatedStep(H)
 local g=S.Copy(S.GA);g[200090]=2;H.granted=S.Granted(g)
 check(S.Within(H,6,OnW2)~=nil,'ordering granted->association: W2 35/79 within 6 s: '..S.Text(S.Hud()))
 H.Advance(30)
 check(OnW2(),'and it stays W2: '..S.Text(S.Hud()))
end

-- 4. Ordering B: the same with a dynamic LOCKED change.
do
 local H=Boot();H.perks.serverActiveSlot=5;OrbRead()
 UnrelatedStep(H)
 H.locked={{spellId=200089,stacks=1}}
 check(S.Within(H,6,OnW2)~=nil,'ordering locked->association: W2 35/79 within 6 s: '..S.Text(S.Hud()))
end

-- 5. Ordering C (static only, no dynamic change): the assigned Wishlist's own
-- server row changes a role (same contents, Echo 79 becomes a LOCKED target),
-- first seen by an Orb-style read, then an unrelated step.
do
 local H=Boot()
 local row=H.perks.serverBuildSlots[101]
 for _,e in ipairs(row.echoes) do if e.spellId==200079 then e.locked=true end end
 OrbRead()
 UnrelatedStep(H)
 local function Roles() local h=S.Hud() return h.total==78 and S.Has(h.toLock,'Echo 79') and h.lockedTotal==1 end
 check(S.Within(H,6,Roles)~=nil,'ordering slots-only: the new role reaches the HUD (40/78, Echo 79 TO LOCK) within 6 s: '
  ..S.Text(S.Hud())..' toLock='..#S.Hud().toLock)
 local w0=S.Work();H.Advance(30);local w1=S.Work()
 check(w1.repairs==w0.repairs and w1.static==w0.static,'and no further repair or rebuild follows: repairs +'
  ..(w1.repairs-w0.repairs)..' static +'..(w1.static-w0.static))
end

-- 6. Ordering D (association only, no slot change): another writer replaces
-- loadout 2's assignment in the character row without the adapter's dirty
-- mark, and a dynamic change arrives in the same fallback period.
do
 local H=Boot()
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 check(owner.UpdateStateV1(function(state)
  state.loadoutWishlists[2]=S.Association(102,'Synthetic W2',W2)
 end),'fixture: the assignment of loadout 2 is replaced through the store owner')
 local g=S.Copy(S.GA);g[200090]=2;H.granted=S.Granted(g)
 check(S.Within(H,6,OnW2)~=nil,'ordering granted->association (same slot): W2 within 6 s: '..S.Text(S.Hud()))
end

-- 7. Steady state: no change, no repeated work.
do
 local H=Boot()
 H.Advance(6)
 local w0=S.Work();H.Advance(60);local w1=S.Work()
 check(w1.repairs==w0.repairs and w1.static==w0.static and w1.steps==w0.steps,
  'steady state for 60 s: no repair, rebuild or step: repairs +'..(w1.repairs-w0.repairs)
  ..' static +'..(w1.static-w0.static)..' steps +'..(w1.steps-w0.steps))
end

C.finish('consumed, silent and notified switches; granted, locked, slots-only and association-only orderings; no repeated work')
