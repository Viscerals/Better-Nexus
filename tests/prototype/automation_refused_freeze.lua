-- A Freeze the client refuses synchronously must not block the board. The
-- loop breaker for a refused Freeze is frozeThisBoard (the next decision runs
-- with canFreeze=false and takes a needed offer); a refused Take keeps blocking
-- by design because re-deciding would pick the same card. Real runtime, real
-- adapter and its service hooks: the harness service answers false to
-- FreezePerk (installed before boot, so the adapter's hook still sees the
-- call as the client's hook would). Synthetic data only.
local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2
local refusals=0
H.service.FreezePerk=function() refusals=refusals+1;return false end
H.Boot()
local A=Nexus.GameAdapter;local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
check(A.SetFirstLoadoutWishlistIdentity('Refused freeze plan',{{spellId=200001,quality=1,stacks=2}}),'plan set')
H.Board({{spellId=200001,quality=1},{spellId=200001,quality=1},{spellId=200021,quality=1}})
H.Notify();H.Advance(.5)
check(A.Wishlist()~=nil,'the target resolves')
local function Actions(kind)local n=0;for _,a in ipairs(H.actions)do if a[1]==kind then n=n+1 end end;return n end
SlashCmdList.NEXUS('auto');H.Advance(1.2)
check(refusals==1,'fixture: the reference Freeze was attempted once and refused: '..refusals)
check(Actions('freeze')==0,'fixture: no Freeze reached the service')
local stats=Nexus.RecomputeStats()
check(stats.actionLifecycle and stats.actionLifecycle.rejected==1,
 'the refused Freeze is recorded as rejected: '..tostring(stats.actionLifecycle and stats.actionLifecycle.rejected))
-- The same board is decided again without Freeze: one Take of the needed
-- Echo within a few beats, and the Freeze is not retried.
H.Advance(3)
check(Actions('take')==1,'after a refused Freeze the same board gets its next decision (one Take sent, '..Actions('take')..')')
local take;for _,a in ipairs(H.actions)do if a[1]=='take' then take=a end end
check(take and take[2]==200001,'the Take is the needed Echo: '..tostring(take and take[2]))
check(refusals==1,'the refused Freeze is not retried on the same board: '..refusals)
life=Nexus.RecomputeStats().lastActionLifecycle
check(life and life.actionType=='take','the lifecycle now follows the Take: '..tostring(life and life.actionType))
-- The Take waits for its own confirmation as before (pending client latch).
local count=#H.actions;H.Advance(1)
check(#H.actions==count,'the pending Take is not duplicated')
print('PASS automation_refused_freeze checks='..checks)
