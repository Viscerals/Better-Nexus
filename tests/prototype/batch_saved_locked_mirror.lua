-- Group 9 (S5-C1): a Saved Build row with an explicit locked flag.
-- Native (static data, never executed): SS540 entries are
-- "<spellId>.<stacks>.<locked 0|1>" and the decoder sets locked as a boolean
-- (perks_service.lua 1030-1109); the native Upload serializes the flag. The
-- adapter keeps it. CommunityController.FinalizeSavedSlot passes the mixed
-- list to the ordinary identity check, which refuses locked-role data, so the
-- slot is never marked seen and the prior Saved mirror is retired.
-- EXPECT (fails at 8c): after a normal reopen,
--   L1 a slot of 200001 (ordinary) + 200002 (locked) keeps the same mirror,
--      with 200001 as its only ordinary copy and 200002 explicitly locked
--      (never an ordinary copy);
--   L2 a slot holding only a locked row keeps the prior mirror (same ID)
--      instead of retiring it (no ordinary identity can be formed).
-- GUARD (holds at 8c): the native source table and the adapter's locked
-- boolean are unchanged; an ordinary-only change updates the mirror with no
-- stale locked rows; a really removed slot still retires its mirror; a
-- malformed row (0 stacks) never enters a served mirror; the mirror stays the
-- character's own verified build; no game or network action.
-- SETUP: real TOC boot (format-5 profile), actual adapter, Saved import and
-- catalog through the Build Library facade; each server change is imported by
-- a normal Hide/Show reopen (a pure Refresh starts no import).
-- No server emission of locked=1 in Saved Builds is claimed.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_saved_locked_mirror')
local printable=B.printable
local F=dofile('tests/prototype/format5_support.lua')
local function E(id,stacks,locked) return {spellId=id,quality=(id-200000)%4,stacks=stacks or 1,locked=locked==true} end
local H=F.Boot(F.Database(),function(h)
 h.perks.serverBuildSlots={[1]={name='Synthetic slot',verified=true,echoes={E(200001),E(200002)}}}
 h.perks.serverActiveSlot=1
end)
local A,CB,CAT=Nexus.GameAdapter,Nexus.CommunityBuilds,Nexus.BuildCatalog
C.setup(Nexus.StartupStatus().coreReady==true,'start-up reached core-ready')
local function Stats()
 local s=CB.VirtualStats()
 return type(s)=='table' and type(s.savedImport)=='table' and s.savedImport or {}
end
local function Mirror(slot)
 for _,b in pairs(CB.Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==(slot or 1) then return b end
 end
end
-- Ordinary and locked copies of a served mirror's catalog record, whatever
-- representation it uses (lockedEchoes, or rows of echoes flagged locked).
local function Roles(mirror)
 local m=type(mirror)=='table' and mirror.id~=nil and CAT.Get(mirror.id) or nil
 local ordinary,locked,bad={},{},0
 for _,e in ipairs(type(m)=='table' and type(m.echoes)=='table' and m.echoes or {}) do
  local id,n=tonumber(e.spellId),tonumber(e.stacks or e.count) or 1
  if n<1 then bad=bad+1 end
  if e.locked then locked[id]=(locked[id] or 0)+n else ordinary[id]=(ordinary[id] or 0)+n end
 end
 for _,e in ipairs(type(m)=='table' and type(m.lockedEchoes)=='table' and m.lockedEchoes or {}) do
  local id,n=tonumber(e.spellId),tonumber(e.stacks or e.count) or 1
  if n<1 then bad=bad+1 end
  locked[id]=(locked[id] or 0)+n
 end
 return ordinary,locked,bad
end
local function Reimport(label,change)
 H.Advance(1.1,.05) -- past the one-second Saved import start spacing
 local before=Stats().completions or 0
 change(H.perks.serverBuildSlots)
 local raw=F.Serialize(H.perks.serverBuildSlots)
 H.Notify();A.Poll();CB.Hide();CB.Show()
 C.setup(B.Until(H,function() return (Stats().completions or 0)>before and Stats().pending~=true end,2000)~=nil,
  label..': a full later import completed')
 C.guard(F.Serialize(H.perks.serverBuildSlots)==raw,label..': the native source table is unchanged')
 local m=Mirror()
 local ordinary,locked=Roles(m)
 local function list(t) local o={};for id,n in pairs(t) do o[#o+1]=id..'x'..n end;table.sort(o);return table.concat(o,',') end
 print('OBSERVED',label,'mirror='..printable(m and m.id),'ordinary='..list(ordinary),'locked='..list(locked),
  'served='..printable(m and CAT.Get(m.id)~=nil))
 return m
end

CB.Show()
C.setup(B.Until(H,function() return Mirror()~=nil and Stats().pending~=true end,2000)~=nil,
 'the ordinary Saved Build is mirrored')
local id=(Mirror() or {}).id
C.setup(id~=nil and CAT.Get(id)~=nil,'the actual catalog serves the ordinary mirror')

C.scenario('L1 one ordinary and one locked row',function()
 local m=Reimport('L1',function(slots) slots[1].echoes={E(200001),E(200002,1,true)} end)
 local live=(A.Slots() or {}).bySlot
 C.guard(live and live[1] and live[1].echoes[2] and live[1].echoes[2].locked==true,
  'L1: the actual adapter keeps the locked boolean')
 C.expect(m~=nil and m.id==id and CAT.Get(id)~=nil,'L1: the prior mirror is kept (same ID), not retired',m and m.id)
 local ordinary,locked=Roles(m)
 C.expect(ordinary[200001]==1 and ordinary[200002]==nil and locked[200002]==1,
  'L1: 200001 is the only ordinary copy and 200002 is explicitly locked, never ordinary')
 if m then
  C.guard(CB.IsOwnBuild(m.id)==true and m.ownerVerified==true,'L1: the mirror stays the own verified build')
 end
end)

C.scenario('G1 an ordinary-only change',function()
 local m=Reimport('G1',function(slots) slots[1].echoes={E(200001,2)} end)
 local ordinary,locked=Roles(m)
 C.guard(m~=nil and ordinary[200001]==2 and next(locked)==nil,
  'G1: the mirror holds the new ordinary copies and no stale locked row')
 id=m and m.id or id
end)

C.scenario('L2 a slot holding only a locked row',function()
 local m=Reimport('L2',function(slots) slots[1].echoes={E(200001,1,true)} end)
 C.expect(m~=nil and m.id==id and CAT.Get(id)~=nil,
  'L2: the prior mirror is kept (same ID) when no ordinary identity can be formed',m and m.id)
 local _,_,bad=Roles(m)
 C.guard(bad==0,'L2: every served row is well formed')
end)

-- Implementation control (root review): an explicit locked row is taken only
-- from a slot row the adapter read in full and as the locked-evidence owner
-- admits it. A malformed locked row (a negative quality, an infinite spell ID:
-- A.Slots flags the row roleSourceValid=false and still projects it) refuses
-- the whole slot, mixed or locked-only, so the mirror retires as for any
-- malformed source; a structurally valid locked-only slot (L2) keeps it.
C.scenario('M malformed explicit locked rows refuse the slot',function()
 local function Ordinary(label)
  Reimport(label,function(slots) slots[1].echoes={E(200001)} end)
  local prior=Mirror()
  C.setup(prior~=nil and CAT.Get(prior.id)~=nil,label..': an ordinary mirror is served before the malformed change')
  return prior or {}
 end
 local prior=Ordinary('M1 setup')
 Reimport('M1',function(slots) slots[1].echoes={E(200001),{spellId=200002,quality=-1,stacks=1,locked=true}} end)
 C.guard(Mirror()==nil and prior.id~=nil and CAT.Get(prior.id)==nil,
  'M1: a mixed slot with a malformed locked row (negative quality) is refused and its mirror retires')
 prior=Ordinary('M2 setup')
 Reimport('M2',function(slots) slots[1].echoes={{spellId=math.huge,quality=1,stacks=1,locked=true}} end)
 C.guard(Mirror()==nil and prior.id~=nil and CAT.Get(prior.id)==nil,
  'M2: a locked-only slot with an unreadable locked row (infinite ID) is refused, not preserved')
 prior=Ordinary('M3 setup')
 Reimport('M3',function(slots) slots[1].echoes={E(200001),E(200002,121,true)} end)
 C.guard(Mirror()==nil and prior.id~=nil and CAT.Get(prior.id)==nil,
  'M3: a locked row above the 120-copy row ceiling is refused and its mirror retires')
 Ordinary('M4 restore')
end)

C.scenario('G2 a really removed slot',function()
 Reimport('G2',function(slots) slots[1]=nil end)
 C.guard(Mirror()==nil and CAT.Get(id)==nil,'G2: a removed Saved Build still retires its mirror')
end)

C.scenario('G3 a malformed row',function()
 H.perks.serverActiveSlot=2
 Reimport('G3',function(slots) slots[2]={name='Synthetic malformed slot',verified=true,echoes={{spellId=200003,quality=3,stacks=0,locked=false}}} end)
 local m=Mirror(2)
 local _,_,bad=Roles(m)
 C.guard(bad==0,'G3: a malformed row never enters a served mirror',m and m.id)
end)

C.guard(#H.actions==0 and #H.sent==0,'no game or network action',#H.actions..'/'..#H.sent)
C.finish('(explicit locked rows are represented or preserved, never retired as ordinary refusals)')
