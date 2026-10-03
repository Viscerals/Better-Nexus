-- 035 part 2c: what happens AFTER Continue. The fresh state becomes the next baseline; the old
-- action is never re-attributed, never replayed and never given a replacement allowance.
--
-- A real harness run: a live run spends one Orb, its offer is seen and recorded, the run is
-- stopped, the game reloads and the offer is gone: the bounded class. Continue archives it. Then
-- the player farms an Orb, gets a reward and changes the slot; none of it changes the archive or
-- the old counts. A new run needs its own approval and every normal gate (resources, ownership,
-- locks, assignment, limit), starts from the fresh balance with its own counters, and the old
-- action's spent Orb is neither refunded nor counted again.
-- Synthetic game and server; native behavior is NOT TESTED.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local failures={}
local function section(name,fn)
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function Until(H,M,stage,seconds)
 local waited=0
 while waited<(seconds or 20) do
  if M.ContinueView().stage==stage then return true end
  H.Advance(.25);waited=waited+.25
 end
 return M.ContinueView().stage==stage
end
-- The real flow to the class: spend, offer recorded, no choice, stop, reload, offer gone.
local function ClassFromARun()
 local H,M,A,O=S.Fresh()
 local src,slots=S.SpendOfferNoChoice(H,M,A,O)
 local oldSpent,oldLimit=M.Status().spent,M.Status().limit
 M=S.Reload(H)
 H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
 local server=R.Server(H)
 S.Pass(H,M,A,2)
 return H,M,A,O,server,oldSpent,oldLimit
end

section('1 continue, then a new run from the fresh state',function()
 local H,M,A,O,server,oldSpent,oldLimit=ClassFromARun()
 check(oldSpent==1 and oldLimit==3,'the old run spent one Orb of three')
 check(M.ContinueView().eligible==true,'the class, from a real run')
 local original=H.Clone(R.Saved())
 assert(M.ContinueBegin());check(Until(H,M,'ready'),'ready')
 assert(M.ContinueConfirm(M.ContinueView().token))
 local archive=H.Clone(R.SavedRow('orbRecoveryArchive'))
 check(#archive==1 and archive[1].spent==1 and archive[1].limit==3 and R.Same(archive[1].receipt,original),'archived: spent 1, limit 3, the receipt unchanged')
 local balance=O.charges
 -- the player goes on: farms an Orb, gets a reward, changes the slot
 O.charges=balance+1
 H.perks.serverActiveSlot=2
 server.Push(1220,tostring(O.charges)..',1,0')
 H.Advance(6)
 local after=R.SavedRow('orbRecoveryArchive')[1]
 local stripped=H.Clone(after);stripped.late=nil;stripped.lateN=nil
 local base=H.Clone(archive[1])
 check(R.Same(stripped,base),'the archive is not touched by anything that happens afterwards')
 check(M.Status().state=='STOPPED' and M.Status().pending==false and M.BlocksOrdinary()==false,'the old run stays stopped and blocks nothing')
 -- a new run needs its own approval and every normal gate
 local calls=R.Calls(H)
 check(calls.spend==0,'nothing was spent by Continue or by what followed')
 H.perks.serverActiveSlot=1
 local ok,why=M.Start(1)
 check(ok==true,'a new run starts through the normal approval: '..tostring(why))
 local st=M.Status()
 check(st.limit==1 and st.spent+st.reserved==1 and st.running==true,'its own limit and its own counter (not the old spent Orb): '..st.spent..'/'..st.limit)
 check(calls.spend==1,'exactly one new spend, from the new approval')
 check(O.charges==balance+1,'the lost Orb was not refunded: the balance is the player\'s own farming and nothing else')
 local row=R.SavedRow('orbRecoveryArchive')
 check(#row==1 and row[1].spent==1 and row[1].limit==3,'the archive still shows the old counts')
end)

section('2 the normal gates still refuse',function()
 local H,M,A,O,server=ClassFromARun()
 assert(M.ContinueBegin());assert(Until(H,M,'ready'));assert(M.ContinueConfirm(M.ContinueView().token))
 -- no balance
 O.charges=0
 local ok,why=M.Start(1)
 check(ok==nil and why~=nil and not why:find('Continue',1,true),'no Orbs: the ordinary resource gate answers: '..tostring(why))
 -- an open offer
 O.charges=9;O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 local ok2,why2=M.Start(1)
 check(ok2==nil and why2~=nil,'an open offer: the ordinary gate answers: '..tostring(why2))
 check(H.Count('orb-spend')==1,'and nothing was spent (only the original spend)')
 -- the old run cannot be resumed
 check(select(2,M.Resume())~=nil and M.Status().running==false,'the old run is not resumed')
end)

if #failures>0 then error(#failures..' section(s) failed:\n'..table.concat(failures,'\n'),0) end
print('PASS Orb recovery after Continue: a new baseline, no retroactive attribution, normal gates, no replacement allowance checks='..checks)
