-- An Orb action whose one-Orb spend was already confirmed, interrupted by a
-- dungeon loading screen (RDF) and then a reload, settles from its exact
-- ownership result even when the total Orb balance moved afterwards for an
-- unrelated reason. Real Store, OrbRuntime, OrbAdapter and GameAdapter; only
-- the game services are synthetic. Receipt shape of the reported case
-- (BN-ORB-RDF-REPORT-001): spend confirmed, choice sent and observed within the
-- recorded offer, then the choice reply is lost at the loading screen, so the
-- game keeps its pick latch and the offer cannot be chosen until a reload.
--
-- The later balance never completes anything by itself: every scenario moves
-- the balance first and checks that the action stays unresolved until the
-- exact ownership result arrives. The negative controls keep every other
-- settlement requirement.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 return H,H.M,H.A,H.O
end
local function Receipt()return Nexus.Store.State().orbRefinement.pending end
local function Gate(M)local r=M.Status().recovery;return r and r.gate and r.gate.gate or (r and r.kind) or M.Status().state end
local function Loadouts(H,A,entries)
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
  [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 assert(A.SetLoadoutWishlistIdentity(1,'First',entries or {{spellId=410002,quality=2,stacks=2}}))
 return H.perks.serverBuildSlots
end
-- Ownership after the server applied the choice: the source stack removed and
-- the gained Echo added (a new table, as the client's granted push does).
local function Owned(H,source,gainId,gainQ)
 local out=H.Clone(H.granted);local removed=false
 for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
 assert(removed,'fake server removes one actual source stack')
 if gainId then local n=H.names[gainId];out[n]=out[n] or {};table.insert(out[n],{spellId=gainId,quality=gainQ}) end
 return out
end
-- The choice reply arrives: latch cleared, offer settled, board closed, and the
-- client's granted refresh delivers `granted`.
local function Deliver(H,A,O,granted,keep)
 keep=keep or {}
 if not keep.latch then H.perks.pendingSelectSpellId=nil end
 if not keep.offer then O.offer=false end
 H.perks.currentChoice=keep.board and H.Clone(keep.board) or (keep.offer and not keep.noBoard and H.perks.currentChoice or nil)
 H.granted=granted;H.Notify();A.Poll();H.Advance(.5)
end
local function Rechecks(H,M,n)for _=1,n or 1 do H.now=H.now+4;M.Recheck();H.Advance(.5)end end
-- Count every call that reaches the game after the reload, refused calls too.
local function CountCalls(H)
 local calls={select=0,spend=0,player=0}
 local rawSelect=H.service.SelectPerk
 H.service.SelectPerk=function(...)calls.select=calls.select+1;return rawSelect(...)end
 local orb=ProjectEbonhold.OrbService;local rawSpend=orb.ConfirmSpend
 orb.ConfirmSpend=function(...)calls.spend=calls.spend+1;return rawSpend(...)end
 calls.pick=function(id)calls.player=calls.player+1;return H.service.SelectPerk(id)end
 return calls
end
local function NothingSent(H,calls,where)
 check(calls.spend==0,where..': no Orb spend after the reload (calls='..calls.spend..')')
 check(calls.select==calls.player,where..': every SelectPerk after the reload is a player call ('..calls.select..'/'..calls.player..')')
 check(H.Count('orb-spend')==1,where..': exactly the one original Orb spend reached the game')
end
local function Reload(H)
 H.Fire('PLAYER_LOGOUT')
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 -- A reload also restarts the game client's Lua: its pick latch is gone and
 -- the pending Orb offer can be chosen again.
 H.perks.pendingSelectSpellId=nil
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 return Nexus.OrbRuntime
end
-- Normal run -> one spend -> exact one-Orb decrement with the offer ->
-- spend confirmed -> Nexus's choice sent and observed -> loading screen with
-- the reply lost -> reload. opts.offer: cards (default target first);
-- opts.plan: assigned entries; opts.inSession: run before the reload.
local function Stuck(opts)
 opts=opts or {}
 local H,M,A,O=Fresh()
 local slots=Loadouts(H,A,opts.plan)
 local charges0=O.charges
 assert(M.Start(3))
 check(H.Count('orb-spend')==1,'setup: one Orb spend submitted')
 local source=O.source
 H.Offer(opts.offer and opts.offer(source,H))
 H.Advance(.5)
 local r=Receipt()
 check(O.charges==charges0-1 and r.chargesBefore==charges0,'setup: exactly one Orb less, observed through the normal path')
 check(r.spendConfirmed==true and r.selectionAttempted==true and r.choiceMayHaveBeenSent==true and r.choiceObserved==true
  and r.selectionRefused==false and r.selectionAmbiguous==false,'setup: spend confirmed; the choice was sent and observed')
 check(type(r.offerKey)=='string' and r.offeredKeys[r.selectedKey]==true and r.originalSlot==1 and r.removed==tostring(source)..':'..H.db[source].quality
  and type(r.before)=='table' and r.lockedKey~=nil and r.loadoutChanged==nil,'setup: the receipt has the reported shape')
 check(H.Count('take')==1 and H.perks.pendingSelectSpellId~=nil,'setup: the choice is in flight')
 -- Loading screen (RDF). The choice reply is lost: the game keeps its latch.
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(.5);H.Fire('PLAYER_ENTERING_WORLD')
 if opts.inSession then opts.inSession(H,M,A,O,source) end
 H.Advance(2)
 check(M.Status().pending and not M.Status().running,'loading screen: the action stays unresolved and the run stops')
 check(H.service.SelectPerk(tonumber((r.selectedKey:match('^(%d+):'))))==false,'loading screen: the game refuses a pick while its latch is set')
 M=Reload(H)
 local calls=CountCalls(H)
 H.Advance(.5)
 check(M.Status().state=='RECOVERY' and Receipt()~=nil,'reload: the saved receipt starts passive recovery')
 return H,M,A,O,source,calls,slots
end
local function Held(H,M,calls,where,gate)
 local s=M.Status()
 check(s.pending and Receipt()~=nil and s.spent+s.reserved==1,where..': still unresolved, receipt and exposure kept ('..tostring(s.state)..'/'..tostring(Gate(M))..')')
 if gate then
  local ok=false;for g in gate:gmatch('[^|]+')do ok=ok or Gate(M)==g end
  check(ok,where..': held by '..gate..', got '..tostring(Gate(M))..': '..tostring(s.reason))
 end
 check(M.BlocksOrdinary()==true and not M.Resume() and not M.Prepare(),where..': ordinary rolling blocked; no Resume and no new run')
 NothingSent(H,calls,where)
end
local function Settled(H,M,calls,where)
 local s=M.Status()
 check(not s.pending and s.state=='STOPPED' and Receipt()==nil,
  where..': the exact result settles the action, got '..tostring(s.state)..'/'..tostring(Gate(M))..': '..tostring(s.reason))
 check(s.spent==1 and s.reserved==0,where..': usage is the one Orb, no refund')
 check(not M.BlocksOrdinary(),where..': ordinary rolling is no longer blocked')
 NothingSent(H,calls,where)
end

-- 1-3. The balance moves after the confirmed spend; then the exact result.
for _,case in ipairs({
 {name='gain after reload',drift=function(O)O.charges=O.charges+1 end},
 {name='later spend after reload',drift=function(O)O.charges=O.charges-1 end},
 {name='gain during the dungeon',inSession=function(H,M,A,O)O.charges=O.charges+1 end},
}) do
 local H,M,A,O,source,calls=Stuck({inSession=case.inSession})
 if case.drift then case.drift(O) end
 H.Advance(1);Rechecks(H,M,1)
 Held(H,M,calls,case.name..', balance moved only')
 check(calls.pick(410002)==true,case.name..': after the reload the player can choose the recorded Echo')
 H.Advance(.5)
 Held(H,M,calls,case.name..', player chose, no result yet')
 check(Receipt()~=nil,case.name..': the receipt is kept until the result is accepted')
 Deliver(H,A,O,Owned(H,source,410002,2))
 Settled(H,M,calls,case.name)
 -- Exactly once: later reads and refreshes change nothing.
 H.granted=H.Clone(H.granted);H.Notify();A.Poll();Rechecks(H,M,2)
 check(M.Status().state=='STOPPED' and M.Status().spent==1 and Receipt()==nil,case.name..': settled exactly once')
 NothingSent(H,calls,case.name..' after later reads')
end

-- Negative controls. Each moves the balance after the confirmed spend, then
-- breaks one other requirement; the action must stay unresolved.
-- A. The spend was never confirmed by the balance: the offer arrived while the
-- balance still showed the old amount, the player chose in the game, and the
-- balance after the result does not show one Orb less.
do
 local H,M,A,O=Fresh()
 Loadouts(H,A)
 assert(M.Start(3));local source=O.source
 O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});M.Pump()
 check(H.Count('take')==0 and Receipt().spendConfirmed==false,'A setup: no confirmed spend, so Nexus does not choose')
 check(H.service.SelectPerk(410002)==true,'A setup: the player chooses in the game');H.Advance(.5)
 check(Receipt().choiceObserved==true and Receipt().selectedKey=='410002:2' and Receipt().spendConfirmed==false,'A setup: choice observed, spend not confirmed')
 H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1)
 M=Reload(H);local calls=CountCalls(H);H.Advance(.5)
 O.charges=O.charges+1 -- still does not prove the one-Orb spend
 Deliver(H,A,O,Owned(H,source,410002,2));Rechecks(H,M,1)
 Held(H,M,calls,'A spend not confirmed','charges')
 check(H.Count('take')==1,'A: only the player choice reached the game')
end
-- B. A different Echo is gained than the recorded choice.
do
 local H,M,A,O,source,calls=Stuck()
 O.charges=O.charges+1
 Deliver(H,A,O,Owned(H,source,410004,3));Rechecks(H,M,1)
 Held(H,M,calls,'B wrong Echo')
 check(M.Status().reason:find('does not match',1,true)~=nil,'B: reported as an ownership mismatch')
end
-- C. Incomplete ownership delta: the source is gone, nothing gained yet.
do
 local H,M,A,O,source,calls=Stuck()
 O.charges=O.charges+1
 Deliver(H,A,O,Owned(H,source,nil));Rechecks(H,M,2)
 Held(H,M,calls,'C incomplete delta','ownership')
end
-- D. The original loadout changed.
do
 local H,M,A,O,source,calls=Stuck()
 H.perks.serverActiveSlot=2;H.Notify();A.Poll();H.Advance(.5)
 O.charges=O.charges+1
 Deliver(H,A,O,Owned(H,source,410002,2));Rechecks(H,M,1)
 Held(H,M,calls,'D loadout changed')
 check(Receipt().loadoutChanged==true,'D: the loadout change is kept in the receipt')
end
-- E. The original slot is not known yet after the reload: wait.
do
 local H,M,A,O,source,calls=Stuck()
 H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;H.Notify();A.Poll();H.Advance(.5)
 O.charges=O.charges+1
 Deliver(H,A,O,Owned(H,source,410002,2));Rechecks(H,M,2)
 Held(H,M,calls,'E slot unknown')
 check(M.Status().recovery.kind=='LOADOUT_UNKNOWN' and Receipt().loadoutChanged==nil,'E: waits for the slot data, records no change')
end
-- F. Locked Echoes changed.
do
 local H,M,A,O,source,calls=Stuck()
 O.charges=O.charges+1
 H.locked={Locked={{spellId=410007,quality=2}}}
 Deliver(H,A,O,Owned(H,source,410002,2));Rechecks(H,M,1)
 Held(H,M,calls,'F locked changed')
end
-- G. The game still reports the Orb offer as open, while no choice board is
-- shown (so the board requirement cannot be what holds it).
do
 local H,M,A,O,source,calls=Stuck()
 O.charges=O.charges+1
 Deliver(H,A,O,Owned(H,source,410002,2),{offer=true,noBoard=true});Rechecks(H,M,1)
 check(#(H.perks.currentChoice or {})==0 and O.offer==true,'G setup: offer flag set, no board')
 Held(H,M,calls,'G offer open','offer')
end
-- G2. The recorded offer is still shown: with a moved balance the recovery does
-- not tie it to the saved action, and nothing settles while it is open.
do
 local H,M,A,O,source,calls=Stuck()
 O.charges=O.charges+1
 Deliver(H,A,O,Owned(H,source,410002,2),{offer=true});Rechecks(H,M,1)
 Held(H,M,calls,'G2 offer shown','OFFER_UNMATCHED')
end
-- L. The same session, no loading screen: Orb income while the running run
-- waits for its result. The balance alone confirms nothing; the exact result
-- settles the operation once, and the run then continues within its limit.
do
 local H,M,A,O=Fresh()
 Loadouts(H,A)
 assert(M.Start(3));local source=O.source
 H.Offer();H.Advance(.5)
 check(Receipt().spendConfirmed==true and Receipt().choiceObserved==true and M.Status().running,'L setup: running, spend confirmed, choice sent')
 O.charges=O.charges+1;H.Advance(2)
 local log=M.RunLog()
 check(M.Status().pending and log.entries[1] and log.entries[1].state~='confirmed' and H.Count('orb-spend')==1,
  'L: Orb income alone confirms nothing and starts nothing')
 Deliver(H,A,O,Owned(H,source,410002,2));H.Advance(1)
 log=M.RunLog()
 check(log.entries[1].state=='confirmed' and log.entries[1].obtained=='410002:2','L: the exact result confirms operation 1: '..tostring(log.entries[1].state))
 local confirmed=0;for _,e in ipairs(log.entries)do if e.state=='confirmed' then confirmed=confirmed+1 end end
 check(confirmed==1 and H.Count('take')==1,'L: confirmed exactly once, one choice')
 check(H.Count('orb-spend')<=2 and M.Status().spent+M.Status().reserved<=3,'L: at most the next approved Orb follows, within the limit')
end
-- H. A game action is still in flight.
do
 local H,M,A,O,source,calls=Stuck()
 O.charges=O.charges+1
 check(calls.pick(410002)==true,'H setup: the player chooses');H.Advance(.5)
 Deliver(H,A,O,Owned(H,source,410002,2),{latch=true});Rechecks(H,M,1)
 Held(H,M,calls,'H host pending','host')
end
-- I. Another Echo choice is open.
do
 local H,M,A,O,source,calls=Stuck()
 O.charges=O.charges+1
 Deliver(H,A,O,Owned(H,source,410002,2),{board={{spellId=410005,quality=0},{spellId=410006,quality=3},{spellId=410008,quality=1}}})
 Rechecks(H,M,1)
 Held(H,M,calls,'I board open','board')
end
-- J. Same-ID, same-quality: the recorded choice is the removed Echo itself.
do
 local H,M,A,O,source,calls=Stuck({plan={{spellId=410004,quality=3,stacks=1}},
  offer=function(src,h)return {{spellId=src,quality=h.db[src].quality},{spellId=410008,quality=1},{spellId=410005,quality=0}} end})
 check(Receipt().selectedKey==Receipt().removed,'J setup: the recorded choice is the removed Echo')
 O.charges=O.charges+1
 local q=tonumber(Receipt().removed:match(':(%d+)$'))
 Deliver(H,A,O,Owned(H,source,source,q));Rechecks(H,M,2)
 Held(H,M,calls,'J same-ID')
 check(M.Status().reason:find('same-ID',1,true)~=nil,'J: reported as the same-ID ambiguity')
end
-- K. No fresh ownership response: the exact result was already visible at the
-- first read after the reload. It settles only after a fresh read-only
-- ownership response (Recheck), never from the balance.
do
 local H,M,A,O,source,calls=Stuck({inSession=function(H,M,A,O,src)
  O.charges=O.charges+1
  H.granted=Owned(H,src,410002,2);H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil
  -- the offer flag is still set in this session, so nothing settles before the reload
 end})
 O.offer=false;H.Advance(1)
 Held(H,M,calls,'K no fresh response','fresh')
 Rechecks(H,M,1)
 Settled(H,M,calls,'K after one fresh ownership response')
end
print('PASS Orb balance drift after a confirmed spend: the exact result settles once; balance alone never does; every other hold kept checks='..checks)
