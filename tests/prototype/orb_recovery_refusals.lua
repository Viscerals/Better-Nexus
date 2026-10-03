-- 035 part 2c negative controls: everything that must NOT let Continue release the blocker.
--
-- The receipt, its spent count and limit, the archive and the block stay exactly as they were
-- whenever a precondition fails; a refusal names its reason; and nothing that is stale, a
-- default, optimistic, omitted, malformed, rejected, late, reordered, duplicated or changed
-- during the check can pass for the explicit zero of a fresh qualifying reply. A fixed number
-- of seconds is never proof of quiescence: a wait that ends can only refuse.
-- The synthetic server is not the real one; native behavior is NOT TESTED. An older server
-- answer that arrives after a new request began cannot be told from the new one, and one test
-- below states that limit as it is.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local F=S.Shape()
local failures={}
local function section(name,fn)
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function World(opts)
 local H,M,A,O=R.Class(opts)
 local server=R.Server(H,opts and opts.server)
 S.Pass(H,M,A,2)
 return H,M,A,O,server
end
local function Run(H,M,seconds,stage)
 local waited=0
 while waited<seconds do
  if stage and M.ContinueView().stage==stage then return true end
  H.Advance(.25);waited=waited+.25
 end
 return stage==nil or M.ContinueView().stage==stage
end
-- The attempt has been refused with this reason; the blocker, the receipt, the spent count
-- and the archive are untouched.
local function Refused(H,M,original,reason,why)
 local v=M.ContinueView()
 local expected=type(reason)=='table' and reason or {[reason]=true}
 check(v.stage=='refused' and expected[v.refusal],why..': refused as '..(type(reason)=='table' and 'one of the expected reasons' or reason)..', got '..tostring(v.stage)..'/'..tostring(v.refusal))
 check(type(v.text)=='string' and #v.text>0 and v.token==nil and v.step==nil,why..': it names the reason, offers no token and no spinner')
 check(R.Saved()~=nil and R.Same(R.Saved(),original) and R.SavedRow('orbRecoveryArchive')==nil,why..': the receipt is unchanged and nothing is archived')
 check(M.Status().pending==true and M.BlocksOrdinary()==true and M.Status().spent==original.spent,why..': the block and the spent count stay')
end
local function Begin(M) local ok,why=M.ContinueBegin();check(ok,'begin: '..tostring(why)) end

-- 1. Stale, default, omitted and optimistic values are not an explicit zero.
section('1 omitted and default',function()
 local H,M,A,O,server=World({server={body=function() return '49,0' end}})
 local original=H.Clone(R.Saved())
 check(H.orbs.offer==false and select(2,Nexus.GameAdapter.Orbs.ServiceState()),'the local flag says no pending offer (it proves nothing)')
 Begin(M);Run(H,M,5,'refused')
 Refused(H,M,original,'reply_unqualified','a reply without the third field')
 local st=Nexus.GameAdapter.Orbs.TransportStatus()
 check(st.rejects.third_absent>=1 and st.bad[1220]~=nil,'the omission is counted and the opcode tainted')
 -- an empty third field is not explicit either (the game reads it as zero)
 local H2,M2,A2,O2,s2=World({server={body=function() return '49,0,' end}})
 local o2=H2.Clone(R.Saved());Begin(M2);Run(H2,M2,5,'refused')
 Refused(H2,M2,o2,'reply_unqualified','an empty third field')
 -- no reply at all: the game's own flags are quiet and Nexus has nothing observed
 local H3,M3,A3,O3,s3=World({server={mode='drop'}})
 local o3=H3.Clone(R.Saved());Begin(M3)
 check(Run(H3,M3,M3.CONTINUE_WAIT+3,'refused'),'a wait that ends refuses')
 Refused(H3,M3,o3,'no_reply','no reply')
 check(H3.orbs.known==true and H3.orbs.offer==false and O3.offer==false,'while IsStateKnown and IsOfferPending were both quiet: they are not proof')
 local again=M3.ContinueBegin()
 check(again==true and M3.ContinueView().stage=='checking','the player may check again, and a new check starts at once')
end)

-- 2. Known positive pending routes to the existing offer flow: no spend, the block stays.
section('2 known positive',function()
 local H,M,A,O,server=World({server={body=function(n) return n==1 and '49,0,1' or '49,0,0' end}})
 local original=H.Clone(R.Saved());local calls=R.Calls(H)
 Begin(M);Run(H,M,5,'refused')
 Refused(H,M,original,'pending_positive','a first reply with one pending offer')
 check(M.ContinueView().text:find('offer',1,true) and M.ContinueView().text:find('game',1,true),'the text sends the player to the game')
 check(calls.spend==0 and calls.nexusSelects()==0,'nothing was spent or chosen')
 local H2,M2,A2,O2,s2=World({server={body=function(n) return n==1 and '49,0,0' or '49,0,2' end}})
 local o2=H2.Clone(R.Saved());Begin(M2);Run(H2,M2,5,'refused')
 Refused(H2,M2,o2,'pending_positive','a second reply with pending offers')
 -- the two replies disagree on the balance
 local H3,M3,A3,O3,s3=World({server={body=function(n) return n==1 and '49,0,0' or '48,0,0' end}})
 local o3=H3.Clone(R.Saved());Begin(M3);Run(H3,M3,5,'refused')
 Refused(H3,M3,o3,{reply_changed=true,state_changed=true},'two different balances')
end)

-- 3. The game's own cache must agree with what was observed.
section('3 cache disagreement',function()
 -- the packets arrive and qualify, but the game's handler did not apply them to its cache
 -- (another build): the replies say 51, the cache says 49
 local H,M,A,O,server=World({server={noCache=true,body=function() return '51,0,0' end}})
 local original=H.Clone(R.Saved())
 Begin(M);Run(H,M,6,'refused')
 Refused(H,M,original,'balance_mismatch','replies and cache disagree')
end)

-- 4. The transport admission, end to end.
section('4 rejected and unqualified packets',function()
 local cases={
  {'wrong sender',function(server) server.Push(1220,'49,0,0',{sender='Other'}) end,'rejected_packet'},
  {'nil sender',function(server) server.Push(1220,'49,0,0',{sender=false}) end,'rejected_packet'},
  {'wrong channel',function(server) server.Push(1220,'49,0,0',{dist='PARTY'}) end,'rejected_packet'},
  {'cross-realm alias',function(server) server.Push(1220,'49,0,0',{sender=R.ME..'-Ebonhold'}) end,'rejected_packet'},
  {'segmented tiny reply',function(server) server.Push(1220,'@ABCD\t001/001\t49,0,0',{noCache=true}) end,'reply_unqualified'},
  {'malformed field',function(server) server.Push(1220,'49,0,x',{noCache=true}) end,'reply_unqualified'},
  {'negative balance',function(server) server.Push(1220,'-1,0,0',{noCache=true}) end,'reply_unqualified'},
  {'forged choice push',function(server) server.Push(16,'forged',{sender='Other'}) end,'rejected_packet'},
  {'forged ownership push',function(server) server.Push(18,'forged',{sender='Other'}) end,'rejected_packet'},
  {'forged slot push',function(server) server.Push(542,'9',{sender='Other'}) end,'rejected_packet'},
  {'a late offer',function(server) server.Push(16,'offer') end,'late_choice'},
  {'a late pick result',function(server) server.Push(1000,'1') end,'late_result'},
 }
 for _,c in ipairs(cases) do
  local H,M,A,O,server=World({server={mode='hold'}})
  local original=H.Clone(R.Saved())
  Begin(M)
  c[2](server)
  H.Advance(.5)
  Refused(H,M,original,c[3],c[1])
 end
 -- an empty body is the game's no-op: it changes nothing and the check goes on
 local H,M,A,O,server=World()
 Begin(M);server.Push(1220,'',{sender='Other'});server.Push(1220,'')
 check(Run(H,M,8,'ready'),'an echo of the request is not an answer and not a refusal')
end)

-- 5. Cache poisoning that cannot be refreshed keeps Continue unavailable.
section('5 poisoned cache',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 server.Push(16,'forged',{sender='Other'})  -- the game's dispatcher would accept this; the observer does not
 local ok,why=M.ContinueBegin()
 check(ok==nil and why=='observer_tainted' and server.requests==0,'begin refuses at once and asks the game for nothing: '..tostring(why))
 check(M.ContinueView().eligible==true and M.ContinueView().refusal=='observer_tainted','the view says why')
 server.Push(16,'')                           -- a later admitted push replaces what the game cached
 Begin(M)
 check(Run(H,M,8,'ready'),'after an admitted choice push the check can run')
 -- a poisoned ownership push BEFORE the check is refreshed by the check's own request
 local H2,M2,A2,O2,s2=World()
 s2.Push(18,'forged',{sender='Other'})
 Begin(M2)
 check(Run(H2,M2,8,'ready'),'a forged ownership push is replaced by the admitted push the check asked for')
 -- and one that arrives while the check runs voids it
 local H3,M3,A3,O3,s3=World({server={mode='hold'}})
 local o3=H3.Clone(R.Saved());Begin(M3);s3.Push(18,'forged',{sender='Other'});H3.Advance(.5)
 Refused(H3,M3,o3,'rejected_packet','a forged ownership push during the check')
end)

-- 6. Loading transitions void the attempt; they are never readiness.
section('6 loading transitions',function()
 local function Case(name,at)
  local H,M,A,O,server=World({server={mode='hold'}})
  local original=H.Clone(R.Saved())
  Begin(M)
  if at=='ready' then server.mode='auto';server.Release();H.Advance(.1);Run(H,M,8,'ready') end
  R.Leaving(H);R.Entering(H);H.Advance(.5)
  Refused(H,M,original,'loading_transition',name)
  return H,M,A,O,server,original
 end
 Case('a loading screen during the first wait','wait')
 local H,M,A,O,server,original=Case('a loading screen with a ready check','ready')
 check(M.ContinueView().token==nil,'the token is gone')
 -- the reply that was held across the loading screen arrives in the new epoch and does not resurrect it
 local H2,M2,A2,O2,s2=World({server={mode='hold'}})
 local o2=H2.Clone(R.Saved());Begin(M2);R.Leaving(H2);R.Entering(H2);s2.mode='auto';s2.Release();H2.Advance(1)
 Refused(H2,M2,o2,'loading_transition','an old reply arriving after the transition')
 -- a new check afterwards counts only what arrived after its own start
 local oldOrd=Nexus.GameAdapter.Orbs.TransportStatus().ord
 Begin(M2)
 check(Run(H2,M2,8,'ready'),'a fresh check in the new epoch completes')
 local v=M2.ContinueView();assert(M2.ContinueConfirm(v.token))
 local e=R.SavedRow('orbRecoveryArchive')[1]
 check(e.pre.r1.ord>oldOrd and e.pre.r2.ord>e.pre.r1.ord,'the replies are ones that arrived after the new check began')
 check(e.pre.ep==Nexus.GameAdapter.Orbs.TransportStatus().epoch,'in the current epoch')
end)

-- 7. The documented limit: an older server answer that arrives after a new request began is
-- indistinguishable. The check takes the first answer after its own request; it does not and
-- cannot say that no older answer was still on its way.
section('7 uncorrelated arrivals',function()
 local H,M,A,O,server=World({server={mode='hold'}})
 Begin(M)
 server.Push(1220,'49,0,0')   -- "an old reply", delivered after the request began
 server.mode='auto';server.Release();
 check(Run(H,M,8,'ready'),'accepted: arrival order is all the check has')
 local v=M.ContinueView()
 check(v.text:find('not prove',1,true) and v.text:lower():find('older'),'and the text says so')
 local e=nil
 assert(M.ContinueConfirm(v.token))
 e=R.SavedRow('orbRecoveryArchive')[1]
 check(e.pre.obs and e.pre.obs.note=='uncorrelated','the entry records that arrival order was not a correlation')
end)

-- 8. State that changes while the check runs, or while it waits for the player.
section('8 state changes',function()
 local function Case(name,reason,change,when)
  local H,M,A,O,server=World({server={mode='hold'}})
  local original=H.Clone(R.Saved())
  Begin(M)
  if when=='ready' then server.mode='auto';server.Release();H.Advance(.1);assert(Run(H,M,8,'ready')) end
  local token=M.ContinueView().token
  change(H,M,A,O,server)
  H.Advance(.5);server.mode='auto';server.Release();H.Advance(.5)
  if when=='ready' then
   local ok,why=M.ContinueConfirm(token)
   check(ok==nil and why~=nil,name..': confirmation refused: '..tostring(why))
   check(R.Saved()~=nil and R.SavedRow('orbRecoveryArchive')==nil,name..': nothing archived')
  end
  local v=M.ContinueView()
  local expected=type(reason)=='table' and reason or {[reason]=true}
  check(v.stage=='refused' and expected[v.refusal],name..' ('..(when or 'wait')..'): '..tostring(v.stage)..'/'..tostring(v.refusal))
  check(R.Same(R.Saved(),original) and M.BlocksOrdinary()==true,name..': receipt and block unchanged')
 end
 local changes={
  {'an Orb gained',{state_changed=true,reply_changed=true},function(H,M,A,O,server) server.Push(1220,'50,1,0') end},
  {'an Orb spent',{state_changed=true,reply_changed=true},function(H,M,A,O,server) server.Push(1220,'48,0,0') end},
  {'a reward Echo','state_changed',function(H,M,A,O) H.granted=S.OwnedMap(F,H,'500002:1');H.Notify();A.Poll() end},
  {'an Echo lost','state_changed',function(H,M,A,O) local g=H.Clone(H.granted);for k in pairs(g) do g[k]=nil;break end;H.granted=g;H.Notify();A.Poll() end},
  {'a slot change','state_changed',function(H) H.perks.serverActiveSlot=102 end},
  {'an Orb offer opens','offer_or_action',function(H,M,A,O) O.offer=true;H.Board({{spellId=500037,quality=1},{spellId=500001,quality=1},{spellId=500038,quality=1}}) end},
  {'an Echo choice opens','offer_or_action',function(H) H.Board({{spellId=500037,quality=1},{spellId=500001,quality=1},{spellId=500038,quality=1}}) end},
  {'a game action in flight','offer_or_action',function(H) H.perks.pendingSelectSpellId=500001 end},
  {'a reroll in flight','offer_or_action',function(H) H.perks.pendingReroll=true end},
  {'a Nexus action in flight','offer_or_action',function() Nexus.GameAdapter.InFlight=function() return true end end},
  {'a Nexus intent','offer_or_action',function() Nexus.PendingIntentState=function() return {kind='synthetic'} end end},
 }
 local inFlight,intent=Nexus and Nexus.GameAdapter and Nexus.GameAdapter.InFlight,nil
 for _,c in ipairs(changes) do
  for _,when in ipairs({'wait','ready'}) do
   Case(c[1],c[2],c[3],when)
  end
 end
end)

-- 9. Duplicate and reordered answers.
section('9 duplicates and reordering',function()
 -- identical answers, duplicated, are consistent
 local H,M,A,O,server=World({server={mode='hold'}})
 Begin(M);server.Push(1220,'49,0,0');server.Push(18,'x');server.Push(18,'x');server.Push(1220,'49,0,0')
 server.mode='auto';server.Release()
 check(Run(H,M,8,'ready'),'duplicated identical answers are consistent')
 local v=M.ContinueView();assert(M.ContinueConfirm(v.token))
 local e=R.SavedRow('orbRecoveryArchive')[1]
 check(e.pre.extra>=2,'the extra answers are counted: '..tostring(e.pre.extra))
 -- a different answer arriving later (reordered) voids a ready check
 local H2,M2,A2,O2,s2=World()
 Begin(M2);assert(Run(H2,M2,8,'ready'))
 local t=M2.ContinueView().token
 s2.Push(1220,'48,0,0');H2.Advance(.5)
 check(M2.ContinueView().stage=='refused' and select(2,M2.ContinueConfirm(t))~=nil,'a different balance after ready voids it')
 -- an answer with a pending offer after ready voids it too
 local H3,M3,A3,O3,s3=World()
 Begin(M3);assert(Run(H3,M3,8,'ready'));local t3=M3.ContinueView().token
 s3.Push(1220,'49,0,1');H3.Advance(.5)
 check(M3.ContinueView().stage=='refused' and M3.ContinueView().refusal=='pending_positive','a late pending offer voids it')
 check(select(2,M3.ContinueConfirm(t3))~=nil and R.Saved()~=nil,'and the receipt stays')
end)

-- 10. A refresh that never completes ends at useful controls.
section('10 refresh never completes',function()
 local H,M,A,O,server=World({server={mode='drop'}})
 local original=H.Clone(R.Saved())
 Begin(M)
 check(M.ContinueView().stage=='checking' and M.ContinueView().step~=nil,'it waits while it can')
 check(Run(H,M,M.CONTINUE_WAIT+2,'refused'),'and stops after the bound')
 Refused(H,M,original,'no_reply','no answer at all')
 check(M.ContinueView().text:lower():find('check again') or M.ContinueView().text:lower():find('press'),'the text says what the player can do')
 -- the first answer arrives, the second never does
 local H2,M2,A2,O2,s2=World({server={body=function(n) return '49,0,0' end}})
 local rawQ=ProjectEbonhold.OrbService.RequestCharges
 local count=0
 ProjectEbonhold.OrbService.RequestCharges=function(...) count=count+1;if count>=2 then s2.mode='drop' end;return rawQ(...) end
 local o2=H2.Clone(R.Saved());Begin(M2)
 check(Run(H2,M2,M2.CONTINUE_WAIT+4,'refused'),'a missing second answer also ends')
 Refused(H2,M2,o2,'no_reply','a missing second answer')
 check(s2.requests==2,'two requests only: no retry loop')
 -- no ownership push
 local H3,M3,A3,O3,s3=World()
 local rawG=H3.service.RequestGrantedPerks
 H3.service.RequestGrantedPerks=function() H3.holdGrantedResponse=true;return nil end
 local o3=H3.Clone(R.Saved());Begin(M3)
 check(Run(H3,M3,M3.CONTINUE_WAIT+4,'refused'),'no ownership push ends')
 Refused(H3,M3,o3,'no_ownership','no fresh ownership')
end)

-- 11. Reads that throw.
section('11 read throws',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 local owned=A.Owned
 A.Owned=function() error('synthetic adapter failure',0) end
 local ok,why=M.ContinueBegin()
 A.Owned=owned
 check(ok==nil and why=='unreadable' and M.ContinueView().stage~='checking','a throwing read refuses the begin')
 check(R.Same(R.Saved(),original) and server.requests==0,'and sends nothing')
 Begin(M);assert(Run(H,M,8,'ready'));local t=M.ContinueView().token
 A.Owned=function() error('synthetic adapter failure',0) end
 local ok2,why2=M.ContinueConfirm(t)
 A.Owned=owned
 check(ok2==nil and why2=='unreadable' and R.Saved()~=nil and R.SavedRow('orbRecoveryArchive')==nil,'a throwing read refuses the confirmation')
end)

-- 12. A failed save keeps the attempt; a retry after recovery archives once.
section('12 write failure',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 Begin(M);assert(Run(H,M,8,'ready'));local t=M.ContinueView().token
 local restore=R.BreakStore()
 local ok,why=M.ContinueConfirm(t)
 check(ok==nil and why=='write_failed','the save is refused: '..tostring(why))
 restore()
 check(R.Same(R.Saved(),original) and R.SavedRow('orbRecoveryArchive')==nil and M.Status().pending==true,'nothing changed')
 check(M.ContinueView().stage=='ready' and M.ContinueView().token==t,'the check is still ready and the token still the player\'s')
 check(M.ContinueConfirm(t)==true and #R.SavedRow('orbRecoveryArchive')==1 and R.Saved()==nil,'the retry archives exactly once')
 -- the Store accepts the call but the row does not show the data (a transient row)
 local H2,M2,A2,O2,s2=World()
 local o2=H2.Clone(R.Saved())
 Begin(M2);assert(Run(H2,M2,8,'ready'));local t2=M2.ContinueView().token
 local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1
 owner.UpdateStateV1=function() return true end
 local ok2,why2=M2.ContinueConfirm(t2)
 owner.UpdateStateV1=raw
 check(ok2==nil and why2=='write_failed' and R.Same(R.Saved(),o2) and R.SavedRow('orbRecoveryArchive')==nil,'a write that is not in the row is refused')
 -- a mutator that throws midway leaves the row as it was
 local H3,M3,A3,O3,s3=World()
 local o3=H3.Clone(R.Saved())
 Begin(M3);assert(Run(H3,M3,8,'ready'));local t3=M3.ContinueView().token
 local owner3=Nexus.MainInternals.StoreAuthorityOwner;local raw3=owner3.UpdateStateV1
 owner3.UpdateStateV1=function() error('store exploded',0) end
 local ok3,why3=M3.ContinueConfirm(t3)
 owner3.UpdateStateV1=raw3
 check(ok3==nil and R.Same(R.Saved(),o3) and R.SavedRow('orbRecoveryArchive')==nil and M3.Status().pending==true,'a throwing Store leaves everything as it was: '..tostring(why3))
end)

-- 13. Capacity and format: refuse, never evict, never repair.
section('13 archive capacity and format',function()
 local function Entry(i)
  return {v=1,id='seed'..i,cd='cd'..i,kind='ACK_UNCONFIRMED',receipt={chargesBefore=i},spent=i,limit=i}
 end
 local function Case(name,seed,reason)
  local H,M,A,O,server=World()
  local original=H.Clone(R.Saved())
  local _,row=R.Row()
  assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(r) r.orbRecoveryArchive=seed end))
  local before=H.Clone(row.orbRecoveryArchive)
  local ok,why=M.ContinueBegin()
  check(ok==nil and why==reason and server.requests==0,name..': begin refuses before asking the game: '..tostring(why))
  check(M.ContinueView().archive.state==reason:gsub('^archive_',''),name..': the view says why')
  check(R.Same(R.Saved(),original) and R.Same(row.orbRecoveryArchive,before),name..': the receipt and the archive are untouched')
 end
 local full={};for i=1,8 do full[i]=Entry(i) end
 Case('eight entries',full,'archive_full')
 local nine={};for i=1,9 do nine[i]=Entry(i) end
 Case('nine entries',nine,'archive_full')
 Case('a string',  'x','archive_malformed')
 Case('a number',  7,'archive_malformed')
 Case('a hash',    {a=Entry(1)},'archive_malformed')
 Case('a hole',    {Entry(1),nil,Entry(3)},'archive_malformed')
 Case('a non-table entry',{Entry(1),'x'},'archive_malformed')
 Case('no id',     {{v=1,cd='x',receipt={}}},'archive_malformed')
 Case('no receipt',{{v=1,id='a',cd='x'}},'archive_malformed')
 Case('a future version',{{v=2,id='a',cd='x',receipt={}}},'archive_future')
 -- an entry that is too large is refused at the confirmation, before anything is written
 local H,M,A,O,server=World()
 Begin(M);assert(Run(H,M,8,'ready'));local t=M.ContinueView().token
 local _,row=R.Row()
 -- a field that is not part of the receipt's identity, so only the size can refuse it
 for i=1,3000 do row.orbRefinement.pending.offeredKeys['999'..i..':1']=true end
 local huge=H.Clone(row.orbRefinement.pending)
 local ok,why=M.ContinueConfirm(t)
 check(ok==nil and why=='entry_too_large','a huge receipt is refused for its size: '..tostring(why))
 check(R.Same(row.orbRefinement.pending,huge) and row.orbRecoveryArchive==nil,'and nothing is written or dropped')
 -- another receipt in the row (the identity differs): it is not the one that was checked
 local H3,M3,A3,O3,s3=World()
 Begin(M3);assert(Run(H3,M3,8,'ready'));local t3=M3.ContinueView().token
 local _,row3=R.Row()
 row3.orbRefinement.pending.removed='999999:1'
 local other=H3.Clone(row3.orbRefinement.pending)
 local ok3,why3=M3.ContinueConfirm(t3)
 check(ok3==nil and why3=='receipt_changed','a different saved receipt is refused: '..tostring(why3))
 check(R.Same(row3.orbRefinement.pending,other) and row3.orbRecoveryArchive==nil,'and left alone')
 -- the archive is checked again at the confirmation
 local H2,M2,A2,O2,s2=World()
 Begin(M2);assert(Run(H2,M2,8,'ready'));local t2=M2.ContinueView().token
 local _,row2=R.Row()
 assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(r) r.orbRecoveryArchive=H2.Clone(full) end))
 local o2=H2.Clone(R.Saved())
 local ok2,why2=M2.ContinueConfirm(t2)
 check(ok2==nil and why2=='archive_full' and R.Same(R.Saved(),o2) and #row2.orbRecoveryArchive==8,'a full archive at the confirmation refuses it: '..tostring(why2))
end)

-- 14. Reload before and after each transition of the receipt.
section('14 reload at each transition',function()
 -- (a) in the middle of a check
 local H,M,A,O,server=World({server={mode='hold'}})
 local original=H.Clone(R.Saved())
 Begin(M)
 M=R.Reload(H);S.Pass(H,M,A,1)
 check(M.ContinueView().stage=='idle' and M.ContinueView().eligible==true,'(a) a reload ends the attempt; the class is still eligible')
 check(R.Same(R.Saved(),original) and R.SavedRow('orbRecoveryArchive')==nil,'(a) the receipt is intact')
 -- (b) with a ready check
 local H2,M2,A2,O2,s2=World()
 local o2=H2.Clone(R.Saved())
 Begin(M2);assert(Run(H2,M2,8,'ready'));local t=M2.ContinueView().token
 M2=R.Reload(H2);S.Pass(H2,M2,A2,1)
 check(select(2,M2.ContinueConfirm(t))=='stale_token' and R.Same(R.Saved(),o2),'(b) the token does not survive a reload')
 -- (c) after the archive
 local H3,M3,A3,O3,s3=World()
 local o3=H3.Clone(R.Saved())
 Begin(M3);assert(Run(H3,M3,8,'ready'));assert(M3.ContinueConfirm(M3.ContinueView().token))
 M3=R.Reload(H3);S.Pass(H3,M3,A3,1);S.Rechecks(H3,M3,3)
 check(R.Saved()==nil and #R.SavedRow('orbRecoveryArchive')==1 and M3.Status().pending==false and M3.BlocksOrdinary()==false,'(c) archived and stays released across a reload')
 check(R.Same(R.SavedRow('orbRecoveryArchive')[1].receipt,o3),'(c) the original receipt is intact')
 check(select(2,M3.ContinueBegin())=='no_receipt','(c) nothing to continue again')
 -- (d) after a refused save and a reload
 local H4,M4,A4,O4,s4=World()
 local o4=H4.Clone(R.Saved())
 Begin(M4);assert(Run(H4,M4,8,'ready'));local t4=M4.ContinueView().token
 local restore=R.BreakStore();M4.ContinueConfirm(t4);restore()
 M4=R.Reload(H4);S.Pass(H4,M4,A4,1)
 check(R.Same(R.Saved(),o4) and R.SavedRow('orbRecoveryArchive')==nil and M4.ContinueView().eligible==true,'(d) a refused save and a reload change nothing')
 Begin(M4);check(Run(H4,M4,8,'ready'),'(d) and the player can try again')
end)

-- 15. Late events after the archive: recorded, bounded, never linked, never acted on.
section('15 late events',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 Begin(M);assert(Run(H,M,8,'ready'));assert(M.ContinueConfirm(M.ContinueView().token))
 local calls=R.Calls(H)
 local stateBefore=M.Status().state
 server.Push(1220,'49,0,2');H.Advance(6)
 server.Push(16,'late offer');H.Advance(6)
 server.Push(1000,'1');H.Advance(6)
 server.Push(1220,'49,0,0',{sender='Other'});H.Advance(6)
 local e=R.SavedRow('orbRecoveryArchive')[1]
 check(type(e.late)=='table' and #e.late>=3 and #e.late<=4,'the late events are kept, bounded: '..tostring(e.late and #e.late))
 local kinds={}
 for _,l in ipairs(e.late) do kinds[l.k]=true;check(R.Plain(l,16),'plain data') end
 check(kinds.pending_positive and kinds.choice_push and kinds.pick_result,'each kind is named')
 for i=1,40 do server.Push(1220,'49,0,'..(1+i%3));H.Advance(.3) end
 H.Advance(6)
 e=R.SavedRow('orbRecoveryArchive')[1]
 check(#e.late<=4 and e.lateN<=99 and e.lateN>=3,'bounded counters: '..tostring(e.lateN))
 check(R.Same(e.receipt,original) and e.spent==original.spent,'the archived receipt is never touched')
 check(M.Status().state==stateBefore and M.Status().pending==false,'no state change and no link to the old receipt')
 check(calls.spend==0 and calls.nexusSelects()==0,'nothing was sent')
 M=R.Reload(H);S.Pass(H,M,A,1)
 check(#R.SavedRow('orbRecoveryArchive')[1].late<=4 and R.SavedRow('orbRecoveryArchive')[1].lateN>=3,'the late events survive a reload')
end)

-- 16. No observer: no fallback to the relaxed local flag.
section('16 no observer',function()
 local H,M,A,O=R.Class()
 local B=Nexus.GameAdapter.Orbs
 B.TransportStart=function() return false,'no frames' end
 local server=R.Server(H)
 S.Pass(H,M,A,2)
 local original=H.Clone(R.Saved())
 local v=M.ContinueView()
 check(v.eligible==false and v.reason=='no_observer','eligibility says why: '..tostring(v.reason))
 check(select(2,M.ContinueBegin())=='no_observer' and server.requests==0,'begin refuses')
 check(H.orbs.known==true and H.orbs.offer==false and H.perks.currentChoice==nil,'although every local flag is quiet')
 H.Advance(30)
 check(R.Same(R.Saved(),original) and R.SavedRow('orbRecoveryArchive')==nil,'and the block stays')
end)

-- 17. The support report names the strict path and the last attempt, with no identity.
section('17 support lines',function()
 local H,M,A,O,server=World({server={body=function() return '49,0' end}})
 Begin(M);Run(H,M,5,'refused')
 server.Push(1220,'49,0,0',{sender='Somebody-Else'})
 local text=table.concat(Nexus.SupportReport.OrbLines(),'\n')
 check(text:find('continue',1,true) and text:find('reply_unqualified',1,true),'the last attempt and its reason')
 check(text:find('third_absent=',1,true) and text:find('sender=',1,true),'the strict-path counters name each reason')
 check(not text:find('Somebody',1,true) and not text:find(R.ME,1,true),'no player or sender name')
 for _,l in ipairs(Nexus.SupportReport.OrbLines()) do check(#l<500 and not l:find('[%z\1-\31]'),'bounded line') end
end)

-- 18. Requests are serialized with earlier Nexus requests.
section('18 serialized requests',function()
 local H,M,A,O,server=World({server={mode='hold'}})
 M.Recheck() -- an earlier Nexus request; its reply is held
 check(server.requests==1,'one request so far')
 Begin(M);H.Advance(1)
 check(server.requests==1 and M.ContinueView().step=='req1','the check does not send its request while an earlier one has no observed reply')
 server.mode='auto';server.Release();H.Advance(.5)
 check(Run(H,M,10,'ready'),'then it goes on and completes')
 check(server.requests==3,'its own two requests followed: '..server.requests)
 -- an earlier request that is never answered ends the check
 local H2,M2,A2,O2,s2=World({server={mode='drop'}})
 local o2=H2.Clone(R.Saved())
 M2.Recheck()
 Begin(M2)
 check(Run(H2,M2,M2.CONTINUE_WAIT+3,'refused'),'it gives up')
 Refused(H2,M2,o2,'no_reply','an earlier request without a reply')
 check(s2.requests==1,'and sent nothing of its own')
end)

-- 19. The same receipt comes back (a backup, an older build): one entry per content, never a duplicate.
section('19 an existing entry',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 Begin(M);assert(Run(H,M,8,'ready'));assert(M.ContinueConfirm(M.ContinueView().token))
 local first=H.Clone(R.SavedRow('orbRecoveryArchive')[1])
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 assert(owner.UpdateStateV1(function(r) r.orbRefinement.pending=H.Clone(original) end))
 M=R.Reload(H);S.Pass(H,M,A,2)
 check(M.ContinueView().eligible==true,'the restored receipt is the class again')
 Begin(M);assert(Run(H,M,8,'ready'));assert(M.ContinueConfirm(M.ContinueView().token))
 local archive=R.SavedRow('orbRecoveryArchive')
 check(#archive==1 and R.Saved()==nil,'the same receipt is not archived twice: the identifier and the content digest match')
 check(R.Same(archive[1],first),'and the entry that was kept is untouched')
 -- the same spend with more evidence: same identifier, other content: both are kept
 local variant=H.Clone(original);variant.picks={{id=500001,q=1,m='offer',c=1}};variant.pickSeen=1
 assert(owner.UpdateStateV1(function(r) r.orbRefinement.pending=H.Clone(variant) end))
 M=R.Reload(H);S.Pass(H,M,A,2)
 Begin(M);assert(Run(H,M,8,'ready'));assert(M.ContinueConfirm(M.ContinueView().token))
 archive=R.SavedRow('orbRecoveryArchive')
 check(#archive==2 and archive[2].id==archive[1].id and archive[2].cd~=archive[1].cd,'other content under the same identifier is kept too')
 check(R.Same(archive[1],first) and archive[2].receipt.picks~=nil and #archive[2].receipt.picks==1,'neither loses anything')
end)

-- 21. The write is verified and a failed one is rolled back.
section('21 verification and rollback',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 Begin(M);assert(Run(H,M,8,'ready'));local t=M.ContinueView().token
 local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1
 -- a store that writes the archive and puts the pending receipt back
 owner.UpdateStateV1=function(fn,...)
  local a,b=raw(fn,...)
  local _,row=R.Row()
  if row and row.orbRefinement then row.orbRefinement.pending=H.Clone(original) end
  return a,b
 end
 local ok,why=M.ContinueConfirm(t)
 owner.UpdateStateV1=raw
 check(ok==nil and why=='write_failed','an unverified write is refused: '..tostring(why))
 check(R.SavedRow('orbRecoveryArchive')==nil and R.Same(R.Saved(),original),'and rolled back: no entry is left and the receipt is as it was')
 check(M.ContinueView().stage=='ready' and M.Status().pending==true,'the check is still ready')
 check(M.ContinueConfirm(t)==true and #R.SavedRow('orbRecoveryArchive')==1,'the retry works')
end)

-- 22. Evidence that is not saved yet is never archived away.
section('22 unsaved evidence',function()
 local H,M,A,O=S.World(F,{slot=101,latch=true,charges=F.receipt.chargesBefore-1,open=true})
 local server=R.Server(H)
 S.Pass(H,M,A,2)
 local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1
 -- the store refuses to write a pending receipt, but accepts the archive move (which clears it)
 owner.UpdateStateV1=function(fn,...)
  local scratch={}
  if pcall(fn,scratch) and type(scratch.orbRefinement)=='table' and scratch.orbRefinement.pending~=nil then return nil end
  return raw(fn,...)
 end
 R.Pick(H,S.IdQ(S.Offer(F)[2]))
 check(Nexus.OrbRuntime.RecoveryView().rawPickUnsaved==true and R.Saved().picks==nil,'the pick evidence is not saved')
 H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;H.orbs.offer=false;S.Pass(H,M,A,1)
 Begin(M);assert(Run(H,M,8,'ready'));local t=M.ContinueView().token
 local ok,why=M.ContinueConfirm(t)
 check(ok==nil and why=='write_failed','the archive refuses to drop it: '..tostring(why))
 check(R.Saved()~=nil and R.SavedRow('orbRecoveryArchive')==nil,'nothing moved')
 owner.UpdateStateV1=raw
 H.Advance(.5)
 check(R.Saved().picks~=nil and #R.Saved().picks==1,'once the store works the next pass saves it')
 check(M.ContinueConfirm(t)==true,'and then the same token confirms')
 local e=R.SavedRow('orbRecoveryArchive')[1]
 check(e.receipt.picks~=nil and #e.receipt.picks==1 and e.observed.picks==1,'the evidence is in the archive')
end)

-- 23. A pass that cannot read the game voids the check.
section('23 unreadable pass',function()
 local H,M,A,O,server=World({server={mode='hold'}})
 local original=H.Clone(R.Saved())
 Begin(M)
 local restore=R.BreakOwned(H);H.Advance(.6)
 Refused(H,M,original,'unreadable','a read that fails during the check')
 restore()
 local H2,M2,A2,O2,s2=World()
 Begin(M2);assert(Run(H2,M2,8,'ready'))
 local o2=H2.Clone(R.Saved())
 local restore2=R.BreakOwned(H2);H2.Advance(.6)
 Refused(H2,M2,o2,'unreadable','a read that fails while it waits for the player')
 restore2()
end)

-- 24. A request that was not sent does not look like one that is awaiting a reply.
section('24 request failure',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 local orb=ProjectEbonhold.OrbService
 local rawRequest=orb.RequestCharges
 orb.RequestCharges=function() error('synthetic send failure',0) end
 local ok,why=M.ContinueBegin()
 check(ok==true or why==nil,'the check starts')
 H.Advance(.5)
 Refused(H,M,original,'request_failed','a send that failed')
 orb.RequestCharges=rawRequest
 Begin(M)
 check(Run(H,M,10,'ready'),'the next check is not blocked by the request that never left: '..tostring(M.ContinueView().refusal))
end)

if #failures>0 then error(#failures..' section(s) failed:\n'..table.concat(failures,'\n'),0) end
print('PASS Orb recovery refusals: stale, omitted, rejected, late, changed and failed inputs never release the blocker checks='..checks)
