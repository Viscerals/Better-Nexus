-- Wishlist overlay: planned locked design targets (W5). A Wishlist's planned locked Echoes are kept as
-- local design targets; the server mirror holds only the rolled copies. The overlay read the mirror only,
-- so a plan's locked targets never appeared in it, although the main panel, the Orb and the editor show
-- them. Required (display only): the overlay lists each planned locked target as a separate "(locked
-- target)" row after the ordinary rows, with desired against OWNED LOCKED copies; an ordinary copy of the
-- same Echo, an unsynced or missing locked read, or the plan itself never counts as owned; the rows follow
-- the assigned Wishlist when the active slot changes and follow the owned locked copies when they change;
-- an unreadable design is said so instead of being dropped silently; an unchanged tick does no work; the
-- overlay writes nothing and the lines never exceed the overlay's limit.
-- Real boot, real editor import and assignment, real adapter projections and the real overlay frame.
local H=dofile('tests/prototype/orbs_support.lua')
local A,W,O=H.A,Nexus.WishlistEditor,Nexus.WishlistOverlay
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.perks.serverBuildSlots={
 [1]={name='Owned one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
 [2]={name='Owned two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}},
 [3]={name='Owned three',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}},
 [4]={name='Owned four',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}},
 [5]={name='Owned five',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
-- 79 ordinary copies (spells 200001..200079), then the given locked targets {spellId,copies}.
local function plan(locks,extraOrdinary)
 local e={}
 for i=1,79 do e[#e+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
 if extraOrdinary then e[#e]={spellId=extraOrdinary,quality=extraOrdinary%4,stacks=1,locked=false} end
 for _,l in ipairs(locks) do e[#e+1]={spellId=l[1],quality=l[1]%4,stacks=l[2],locked=true}end
 return e
end
local function save(slot,name,locks,extraOrdinary)
 H.perks.serverActiveSlot=slot;H.Notify();A.Poll()
 local code=assert(Nexus.Codec.EncodeEBH1(plan(locks,extraOrdinary),'MAGE',name))
 W.ImportEBH1String(code,name)
 local d=W.DebugDraftState()
 check(d.pending==79,'the imported draft holds 79 rolled copies ('..name..')')
 local create
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()=='Create Wishlist'then create=f;break end end
 assert(create,'Create button');create:Click();H.AcceptPopup()
 check(not W.IsApplyPending(),'the synthetic save completes ('..name..')')
 H.now=H.now+3.1
 check(A.AssignedWishlist().name==name and A.AssignedWishlist().state=='ready','assigned: '..name)
end
local function activate(slot)
 H.perks.serverActiveSlot=slot;H.Notify();A.Poll();Nexus.RequestRecompute();H.Advance(1.5)
end
local function name(id) return A.Catalog().rows[id].name end
local overlayFrame
local function Lines()
 if not overlayFrame then
  for _,f in ipairs(H.frames)do if f.GetName and f:GetName()=='NexusOverlay' then overlayFrame=f end end
 end
 local out={}
 for _,r in ipairs(overlayFrame and overlayFrame.regions or {})do
  if r.shown and r.text and r.text~='' then out[#out+1]=(r.text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))end
 end
 return out
end
local function LockedRows()
 local rows={}
 for i,t in ipairs(Lines())do if t:find('(locked target)',1,true) then rows[#rows+1]={i=i,t=t} end end
 return rows
end
local function Find(rows,id) for _,r in ipairs(rows)do if r.t:find(name(id)..' (locked target)',1,true) then return r end end end

save(1,'Plan A',{{200080,1}})
save(2,'Plan B',{{200081,1}})
save(3,'Plan C',{{200082,2},{200083,1}})
save(4,'Plan D',{})
-- A plan whose ordinary list also holds a copy of its own locked target's Echo.
save(5,'Plan E',{{200080,1}},200080)
local assigned=Nexus.Store.State().loadoutWishlists
local storeBefore=NexusDB and NexusDB.loadoutWishlists
H.locked={};H.granted={}
activate(1)
O.Show();H.Advance(1.5)
local lines=Lines()
check(#lines==80,'Plan A: 79 ordinary rows and one planned locked target: '..#lines)
local rows=LockedRows()
check(#rows==1 and Find(rows,200080),'Plan A: exactly one locked target row, for '..name(200080)..': '..#rows)
check(rows[1].t:sub(1,3)=='[ ]' and rows[1].t:find('(0/1)',1,true),'Plan A: the planned target is shown as not owned (0/1): '..rows[1].t)
check(rows[1].i==#lines,'Plan A: the locked target row comes after every ordinary row')
for i=1,#lines-1 do check(not lines[i]:find('(locked target)',1,true),'Plan A: ordinary row '..i..' is not a locked target') end

-- Owned means owned locked copies. An ordinary copy, the plan and a missing read are not owned.
H.granted={['Echo 80']={{spellId=200080,quality=0}}};H.Notify();A.Poll();H.Advance(1.5)
rows=LockedRows()
check(#rows==1 and rows[1].t:sub(1,3)=='[ ]' and rows[1].t:find('(0/1)',1,true),'an ordinary copy of the Echo does not make the locked target owned: '..rows[1].t)
H.granted={};H.locked=nil;H.Notify();A.Poll();H.Advance(1.5)
rows=LockedRows()
check(#rows==1 and rows[1].t:sub(1,3)=='[ ]' and rows[1].t:find('(0/1)',1,true),'an unreadable locked list owns nothing: '..rows[1].t)
H.locked={{spellId=200080,stacks=1}};H.Notify();A.Poll();H.Advance(1.5)
rows=LockedRows()
check(#rows==1 and rows[1].t:sub(1,3)=='[X]' and rows[1].t:find('(1/1)',1,true),'one owned locked copy fulfils the target: '..rows[1].t)
H.locked={};H.Notify();A.Poll();H.Advance(1.5)
rows=LockedRows()
check(#rows==1 and rows[1].t:sub(1,3)=='[ ]','losing the copy shows the target as missing again')

-- Switching the active slot switches the planned targets; nothing of the other plan stays.
activate(2)
rows=LockedRows()
check(#rows==1 and Find(rows,200081) and not Find(rows,200080),'Plan B: its own target only: '..(rows[1] and rows[1].t or 'none'))
-- Desired against owned counts, duplicates and the stack limit.
activate(3)
rows=LockedRows()
check(#rows==2 and Find(rows,200082) and Find(rows,200083),'Plan C: two planned targets: '..#rows)
check(Find(rows,200082).t:find('(0/2)',1,true) and Find(rows,200083).t:find('(0/1)',1,true),'Plan C: desired counts 2 and 1')
H.locked={{spellId=200082,stacks=1}};H.Notify();A.Poll();H.Advance(1.5)
rows=LockedRows()
check(Find(rows,200082).t:sub(1,3)=='[~]' and Find(rows,200082).t:find('(1/2)',1,true),'Plan C: one of two copies is partial (1/2): '..Find(rows,200082).t)
check(Find(rows,200083).t:sub(1,3)=='[ ]','Plan C: the other target is still missing')
H.locked={{spellId=200082,stacks=5},{spellId=200083,stacks=1}};H.Notify();A.Poll();H.Advance(1.5)
rows=LockedRows()
check(Find(rows,200082).t:sub(1,3)=='[X]' and Find(rows,200082).t:find('(2/2)',1,true),'Plan C: owning more than desired shows (2/2), never above the target: '..Find(rows,200082).t)
check(Find(rows,200083).t:sub(1,3)=='[X]' and Find(rows,200083).t:find('(1/1)',1,true),'Plan C: the second target is fulfilled')
check(Find(rows,200082).i>=78 and Find(rows,200083).i>=78 and #Lines()==81,'Plan C: both locked targets are the last rows, after every ordinary row (rows '..Find(rows,200082).i..' and '..Find(rows,200083).i..' of '..#Lines()..')')
H.locked={}
-- A plan with no locked target shows no locked row.
activate(4)
check(#LockedRows()==0 and #Lines()==79,'Plan D: no planned locked target: 79 ordinary rows only ('..#Lines()..')')
-- The same Echo as an ordinary copy and as a locked target: two separate rows, counted apart.
activate(5)
local both=0
for _,t in ipairs(Lines())do if t:find(name(200080),1,true) then both=both+1 end end
check(both==2,'Plan E: the Echo has an ordinary row and a separate locked target row: '..both)
H.granted={['Echo 80']={{spellId=200080,quality=0}}};H.Notify();A.Poll();H.Advance(1.5)
rows=LockedRows()
check(#rows==1 and rows[1].t:sub(1,3)=='[ ]','Plan E: an owned ordinary copy fulfils the ordinary row only, not the locked target')
H.granted={}
-- No assigned Wishlist at all: the old single line, no rows.
H.perks.serverActiveSlot=0;H.Notify();A.Poll();Nexus.RequestRecompute();H.Advance(1.5)
lines=Lines()
check(#lines==1 and lines[1]:find('No wishlist set',1,true),'no assigned Wishlist: one "No wishlist set" line: '..#lines..' '..tostring(lines[1]))
-- Back to Plan A: the target returns.
activate(1)
rows=LockedRows()
check(#rows==1 and Find(rows,200080),'switching back to Plan A shows its target again')

-- An unchanged tick does no work (revision gate); a change is a single rebuild.
H.Advance(1.5)
local s1=O.Stats()
H.Advance(3)
local s2=O.Stats()
check(s2.wishlistReads==s1.wishlistReads and s2.rowUpdates==s1.rowUpdates and s2.projectionBuilds==s1.projectionBuilds,
 'unchanged ticks read nothing and update no row')
check(s2.revisionSkips>s1.revisionSkips,'the unchanged ticks were skipped by the revision gate')
H.locked={{spellId=200080,stacks=1}};H.Notify();A.Poll();H.Advance(1.5)
local s3=O.Stats()
check(s3.rowUpdates>s2.rowUpdates and s3.rowUpdates-s2.rowUpdates<=2 and s3.wishlistReads-s2.wishlistReads<=1,
 'one owned-copy change updates only the changed row: rows '..(s3.rowUpdates-s2.rowUpdates)..', reads '..(s3.wishlistReads-s2.wishlistReads))

-- An unreadable design is reported, not dropped silently, and the ordinary rows stay.
H.locked={}
local realAssigned=A.AssignedWishlist
A.AssignedWishlist=function()
 local r=realAssigned();r.state='unavailable';r.entries={};for i=1,79 do r.entries[i]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
 return r
end
Nexus.RequestRecompute();H.perks.serverActiveSlot=2;H.Notify();A.Poll();H.Advance(1.5)
lines=Lines()
local noted=false
for _,t in ipairs(lines)do if t:find('locked targets unavailable',1,true) then noted=true end end
check(noted and #LockedRows()==0 and #lines==80,'unreadable planned targets: a note line, no locked row, 79 ordinary rows: '..#lines)
A.AssignedWishlist=realAssigned
-- A projection that holds two locked rows of one Echo (a mirrored locked copy plus the plan's extra copy):
-- one row, with the group's counts.
A.AssignedWishlist=function()
 local r=realAssigned();r.state='ready';r.entries={}
 for i=1,79 do r.entries[i]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
 r.entries[80]={spellId=200080,quality=0,stacks=1,locked=true}
 r.entries[81]={spellId=200080,quality=0,stacks=1,locked=true}
 return r
end
H.locked={{spellId=200080,stacks=1}};Nexus.RequestRecompute();H.perks.serverActiveSlot=3;H.Notify();A.Poll();H.Advance(1.5)
rows=LockedRows()
check(#rows==1 and #Lines()==80 and rows[1].t:sub(1,3)=='[~]' and rows[1].t:find('(1/2)',1,true),'two locked rows of one Echo show one row with the group counts (1/2): '..#rows..' '..(rows[1] and rows[1].t or ''))
A.AssignedWishlist=realAssigned
H.locked={}
activate(1)
check(#LockedRows()==1,'after the design is readable again the target row returns')

-- Display only: nothing was written, uploaded, spent or unlocked by the overlay.
check(Nexus.Store.State().loadoutWishlists[1]~=nil and H.Count('orb-spend')==0,'no Orb spend')
for _,a in ipairs(H.actions)do check(a[1]~='unlock' and a[1]~='lock','no lock or unlock action: '..tostring(a[1])) end
check(#Lines()<=90,'the overlay never exceeds its 90 lines: '..#Lines())
print('PASS wishlist_overlay_locked_targets: planned locked targets listed apart from the ordinary rows with desired against owned locked copies; ordinary copy, plan and unreadable list never count as owned; switching, owned-copy refresh, unchanged ticks, unreadable design; display only checks='..checks)
