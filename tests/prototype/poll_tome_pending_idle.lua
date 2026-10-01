-- Tome toggle reconciliation in the poll (HUD and lifecycle cost, 2026-10-01,
-- test.9053). GameAdapter.Poll runs about five times a second. Its tome step
-- returned early only when the row had no pending map, but every shaped row
-- has one (empty), so each poll entered the Store mutation entry, which
-- compares the whole character row with the read snapshot. Measured on the
-- reporter's saved data: about half of Nexus's allocation and a third of its
-- lifecycle time while idle.
--
-- Required: with nothing pending, polls do not enter the Store mutation entry
-- for this step; a pending toggle is still reconciled on every poll, stays
-- pending until the server confirms it, and is cleared when confirmed; an
-- entry loaded from saved data for an unknown lever is still cleared.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function upvalue(fn,name)
 for i=1,255 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==name then return v end end
end

NexusDB=nil;WishlistRealizerDB=nil
local H=dofile('tests/prototype/harness.lua')
H.names[777001]='Tome of Gated Echo'
H.AddEcho(300001,'Gated Echo',1,1,0);H.db[300001].requiredSpell=777001
H.discovered[300001]=true;H.perks.discoveredEchoes=H.discovered
H.playerLevel=1
H.Boot()
local A=Nexus.GameAdapter
local reconcile=upvalue(A.Poll,'ReconcileTomePending')
check(type(reconcile)=='function','the poll tome step is found')

-- Store mutation entries made directly by the tome step. GameAdapter's
-- UpdateStoreState tail-calls the entry, so the step is the calling frame.
local owner=Nexus.MainInternals.StoreAuthorityOwner
local rawUpdate=owner.UpdateStateV1
local fromStep=0
owner.UpdateStateV1=function(...)
 local caller=debug.getinfo(2,'f')
 if caller and caller.func==reconcile then fromStep=fromStep+1 end
 return rawUpdate(...)
end
local polls=0
local rawPoll=A.Poll
A.Poll=function(...) polls=polls+1;return rawPoll(...) end
local function Pending() return Nexus.Store.State().tomeTogglePending end
local function Count(kind) local n=0;for _,a in ipairs(H.actions) do if a[1]==kind then n=n+1 end end;return n end

-- 1. Nothing pending.
check(type(Pending())=='table' and next(Pending())==nil,'fixture: the shaped row has an empty pending map')
polls,fromStep=0,0
H.Advance(3)
check(polls>=10,'the poll runs: '..polls)
check(fromStep==0,'nothing pending: no Store mutation entry from the tome step (test.9053: one per poll): '..fromStep..' in '..polls..' polls')

-- 2. A toggle is sent and waits for the server.
local ok,why=A.ToggleLever(777001,true)
check(ok==true and Count('toggle')==1,'fixture: the toggle is sent: '..tostring(why))
check(type(Pending()[777001])=='table' and Pending()[777001].want==true,'the toggle is pending')
check(A.DisabledLevers()[777001]=='pending','the lever shows pending')
polls,fromStep=0,0
H.Advance(3)
check(polls>=10 and fromStep==polls,'pending: the tome step reconciles on every poll: '..fromStep..' of '..polls)
check(type(Pending()[777001])=='table','not confirmed: still pending')

-- 3. The server confirms it: cleared, then idle again.
H.disabled[300001]=true
H.Advance(.5)
check(Pending()[777001]==nil and next(Pending())==nil,'confirmed: the pending entry is cleared')
check(A.DisabledLevers()[777001]=='confirmed','the lever shows confirmed')
polls,fromStep=0,0
H.Advance(3)
check(polls>=10 and fromStep==0,'after the confirmation: no entry again: '..fromStep)

-- 4. Saved data with a pending entry for a lever this catalog does not know.
local F=dofile('tests/prototype/format5_support.lua')
local db=F.Database()
check(db.chars[F.NAME].tomeTogglePending[7]~=nil,'fixture: saved row carries a pending entry')
F.Boot(db)
H=nil
for _=1,10 do Nexus.GameAdapter.Poll() end
check(next(Nexus.Store.State().tomeTogglePending)==nil,'a saved entry for an unknown lever is still cleared')
local live=NexusDB.chars and NexusDB.chars[F.OWNER]
check(type(live)=='table' and type(live.tomeTogglePending)=='table' and live.tomeTogglePending[7]==nil,
 'the durable row is cleared too')

print('PASS idle polls skip the tome step write; pending toggles still reconcile; '..checks..' checks')
