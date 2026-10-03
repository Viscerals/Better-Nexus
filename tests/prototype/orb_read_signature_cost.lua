-- Orb reads and the five-second fallback signature (Echo-roll lag report,
-- 2026-09-30, test.9051). Measured on the reporter's saved data: while the Orb
-- window is open or a run is active, OrbAdapter.Read ran about 9 times a
-- second and built its context with GameAdapter.AutomationSignature, the
-- fallback check meant for every five seconds. Each call compared the whole
-- character row through the Store mutation entry and scanned every bag slot
-- for a Tome; the read kept one field of the result (the active-slot
-- generation). About 30% of the Orb window's CPU and 20% of its allocation.
--
-- Required: an Orb read calls neither the signature, the bag scan nor the
-- Store mutation entry; it still runs the same Echo reconciliation, so its
-- context carries the same active-slot generation (also after a slot change
-- between two reads, and none when the reconciliation fails); the approved run
-- takes the same actions and ends in the same state.
local H=dofile('tests/prototype/orbs_support.lua')
local A,M=H.A,H.M
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local inRead,reads=0,0
local seen={signature=0,bags=0,store=0}
local rawRead=A.Orbs.Read
A.Orbs.Read=function(...)
 inRead=inRead+1;reads=reads+1
 local r={pcall(rawRead,...)}
 inRead=inRead-1
 if not r[1] then error(r[2],0) end
 return unpack(r,2)
end
local rawSignature=A.AutomationSignature
A.AutomationSignature=function(...)
 if inRead>0 then seen.signature=seen.signature+1 end
 return rawSignature(...)
end
local rawSlots=GetContainerNumSlots
GetContainerNumSlots=function(...)
 if inRead>0 then seen.bags=seen.bags+1 end
 return rawSlots(...)
end
local owner=Nexus.MainInternals.StoreAuthorityOwner
local rawUpdate=owner.UpdateStateV1
owner.UpdateStateV1=function(...)
 if inRead>0 then seen.store=seen.store+1 end
 return rawUpdate(...)
end
local function activeGeneration() return select(2,A.PresentationRevisions()) end
-- A read in a later frame, with no poller running in between.
local function lateRead() H.now=H.now+.01;return A.Orbs.Read() end

-- 1. The read keeps the reconciliation: a slot change between two reads is
-- seen by the second read, and its context carries the new generation.
local s0=lateRead()
check(s0 and s0.context.active==activeGeneration(),'the context carries the active-slot generation: '..tostring(s0 and s0.context.active))
local before=activeGeneration()
local slot=H.perks.serverActiveSlot
H.perks.serverActiveSlot=slot+1
local s1=lateRead()
check(activeGeneration()==before+1,'the read itself reconciles the Echo state: generation '..tostring(activeGeneration())..' after '..tostring(before))
check(s1 and s1.context.active==before+1,'the context carries the reconciled generation: '..tostring(s1 and s1.context.active))
H.perks.serverActiveSlot=slot
check(lateRead() and activeGeneration()==before+2,'the change back is seen by the next read')
-- A failed reconciliation leaves the generation out, as before.
local rawActive=H.service.GetServerActiveSlot
H.service.GetServerActiveSlot=function() error('synthetic slot read failure') end
local sf=lateRead()
check(sf and sf.context.active==nil,'a failed reconciliation carries no generation: '..tostring(sf and sf.context.active))
H.service.GetServerActiveSlot=rawActive
lateRead()

-- 2. The approved run with the Orb window open (orbs_assigned.lua), with frames
-- in between so the window refresh and the Orb pump read as in the game.
local target={{spellId=410002,quality=2,stacks=2},{spellId=410007,quality=2,stacks=1,locked=true}}
assert(A.SetFirstLoadoutWishlistIdentity('Assigned plan',target))
Nexus.OrbPanel.Show();H.Advance(2)
assert(M.SetLimit(3));assert(M.Start());H.Advance(.5)
check(H.Count('orb-spend')==1,'one explicit Start approves one safe source')
H.Offer();H.Advance(1);H.Result(410002,2);H.Advance(1)
check(H.Count('orb-spend')==2,'a confirmed result continues from one Start')
H.Offer();H.Advance(1);H.Result(410002,2);H.Advance(2)
local st=M.Status()
check(st.state=='ROLLED_COMPLETE' and H.Count('orb-spend')==2 and H.Count('take')==2,
 'the same actions and the same end state: '..tostring(st.state)..' spends '..H.Count('orb-spend')..' takes '..H.Count('take'))
check(st.spent==2 and st.reserved==0,'confirmed usage retained')

-- 3. No read did the fallback work (the run above read many times).
check(reads>=20,'the run read the Orb state repeatedly: '..reads)
check(seen.signature==0,'no Orb read calls the five-second signature: '..seen.signature..' of '..reads..' reads')
check(seen.bags==0,'no Orb read scans the bags: '..seen.bags)
check(seen.store==0,'no Orb read enters the Store mutation path: '..seen.store)
print('PASS Orb reads without the fallback signature ('..reads..' reads), reconciliation kept, same run; '..checks..' checks')
