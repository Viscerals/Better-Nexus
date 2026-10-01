-- Live (no reload) Orb action whose one-Orb spend is already confirmed, then
-- the total balance leaves {before, before-1} for an unrelated reason (two Orbs
-- gained, or another Orb spent). BN-ORB-LIVE-SETTLEMENT-004.
-- be19854/bb271a9: every live pump paused and returned at the balance check
-- before finishResult, so the exact ownership result could never settle the
-- action in the same session (only a reload reached recovery). Required: the
-- drift pauses continuation and submits nothing; the balance alone settles
-- nothing; the exact result then settles the action exactly once at the later
-- balance (one Orb used, no exposure, receipt cleared); no next Orb is spent
-- automatically; Recheck, Stop, more events and a reload change nothing.
-- Negative controls keep every other settlement requirement. Real Store,
-- OrbRuntime, OrbAdapter and GameAdapter; only the game services are synthetic.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 return H,H.M,H.A,H.O
end
local function Receipt()return Nexus.Store.State().orbRefinement.pending end
local function Loadouts(H,A,entries)
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
  [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 assert(A.SetLoadoutWishlistIdentity(1,'First',entries or {{spellId=410002,quality=2,stacks=2}}))
end
local function Owned(H,source,gainId,gainQ)
 local out=H.Clone(H.granted);local removed=false
 for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
 assert(removed,'fake server removes one actual source stack')
 if gainId then local n=H.names[gainId];out[n]=out[n] or {};table.insert(out[n],{spellId=gainId,quality=gainQ}) end
 return out
end
local function Deliver(H,A,O,granted,keep)
 keep=keep or {}
 if not keep.latch then H.perks.pendingSelectSpellId=nil end
 if not keep.offer then O.offer=false end
 H.perks.currentChoice=keep.board and H.Clone(keep.board) or (keep.offer and not keep.noBoard and H.perks.currentChoice or nil)
 H.granted=granted;H.Notify();A.Poll();H.Advance(1)
end
local function Confirmed(M)
 local n=0;for _,e in ipairs(M.RunLog().entries or {})do if e.state=='confirmed' then n=n+1 end end;return n
end
-- Live run -> one spend -> exact one-Orb decrement with the offer -> spend
-- confirmed -> Nexus's choice in flight -> the balance drifts.
local function Live(drift,opts)
 opts=opts or {}
 local H,M,A,O=Fresh()
 Loadouts(H,A,opts.plan)
 local before=O.charges
 assert(M.Start(3))
 local source=O.source
 H.Offer(opts.offer and opts.offer(source,H));H.Advance(.5)
 local r=Receipt()
 check(r and r.spendConfirmed==true and r.chargesBefore==before and O.charges==before-1,'setup: one Orb less observed with the offer; spend confirmed')
 check(r.selectionAttempted==true and r.choiceMayHaveBeenSent==true and r.offeredKeys[r.selectedKey]==true,'setup: Nexus chose an offered Echo')
 check(H.Count('orb-spend')==1 and H.Count('take')==1,'setup: one spend, one choice')
 O.charges=before-1+drift
 H.Advance(2)
 local s=M.Status()
 check(s.pending and Receipt()~=nil and s.spent+s.reserved==1,'drift '..drift..': still unresolved, receipt and exposure kept')
 check(not s.running and s.state=='PAUSED','drift '..drift..': continuation paused: '..tostring(s.state))
 check(H.Count('orb-spend')==1 and H.Count('take')==1,'drift '..drift..': nothing more submitted')
 check(Confirmed(M)==0,'drift '..drift..': the balance alone confirms nothing')
 return H,M,A,O,source,before
end
local function Held(H,M,where)
 local s=M.Status()
 check(s.pending and Receipt()~=nil and s.spent+s.reserved==1,where..': held, receipt and exposure kept ('..tostring(s.state)..': '..tostring(s.reason)..')')
 check(Confirmed(M)==0,where..': not confirmed')
 check(M.BlocksOrdinary()==true and not M.Resume(),where..': ordinary rolling blocked; no Resume')
 check(H.Count('orb-spend')==1,where..': exactly the one Orb spend reached the game')
end

-- 1-2. Two Orbs gained (11 after 10 -> 9) and another Orb spent (8).
for _,drift in ipairs({2,-1}) do
 local H,M,A,O,source,before=Live(drift)
 Deliver(H,A,O,Owned(H,source,410002,2))
 local s=M.Status()
 check(not s.pending and Receipt()==nil,'drift '..drift..': the exact result settles the action ('..tostring(s.state)..': '..tostring(s.reason)..')')
 check(s.spent==1 and s.reserved==0 and Confirmed(M)==1,'drift '..drift..': one Orb used, no exposure, confirmed once')
 check(M.RunLog().entries[1].obtained=='410002:2','drift '..drift..': the recorded Echo is the result')
 check(not s.running and s.state~='READY','drift '..drift..': no automatic continuation: '..tostring(s.state))
 check(O.charges==before-1+drift,'drift '..drift..': settled at the later balance')
 -- Idempotent: more events, Recheck, time; then Stop and a reload.
 H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.now=H.now+4;M.Recheck();H.Advance(3)
 s=M.Status()
 check(s.spent==1 and Confirmed(M)==1 and Receipt()==nil and H.Count('orb-spend')==1 and H.Count('take')==1,
  'drift '..drift..': later events change nothing; no new spend')
 M.Stop();H.Advance(1)
 s=M.Status()
 check(s.state=='STOPPED' and s.spent==1 and not M.BlocksOrdinary(),'drift '..drift..': Stop ends the run without refund; ordinary rolling free')
 H.Fire('PLAYER_LOGOUT')
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{});assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 H.Advance(2)
 check(Receipt()==nil and not Nexus.OrbRuntime.Status().pending and H.Count('orb-spend')==1,'drift '..drift..': after a reload nothing is pending or replayed')
end

-- Negative controls: drift after the confirmed spend, then one requirement fails.
-- A. Ownership result missing (unchanged ownership).
do local H,M,A,O=Live(2);H.Notify();A.Poll();H.Advance(2);Held(H,M,'A no result') end
-- B. A different Echo is gained than the recorded choice.
do
 local H,M,A,O,source=Live(2);Deliver(H,A,O,Owned(H,source,410004,3))
 Held(H,M,'B wrong Echo');check(M.Status().reason:find('does not match',1,true)~=nil,'B: reported as a mismatch')
end
-- C. Incomplete delta: source gone, nothing gained.
do local H,M,A,O,source=Live(-1);Deliver(H,A,O,Owned(H,source,nil));Held(H,M,'C incomplete delta') end
-- D. The original loadout changed.
do
 local H,M,A,O,source=Live(2);H.perks.serverActiveSlot=2;H.Notify();A.Poll();H.Advance(.5)
 Deliver(H,A,O,Owned(H,source,410002,2));Held(H,M,'D loadout changed')
 check(Receipt().loadoutChanged==true,'D: the loadout change is kept in the receipt')
end
-- E. Locked Echoes changed.
do
 local H,M,A,O,source=Live(2);H.locked={Locked={{spellId=410007,quality=2}}}
 Deliver(H,A,O,Owned(H,source,410002,2));Held(H,M,'E locked changed')
end
-- F. The game still reports the Orb offer as open, with no board shown (so
-- the board requirement cannot be what holds it); F2 with the offer shown.
do
 local H,M,A,O,source=Live(2);Deliver(H,A,O,Owned(H,source,410002,2),{offer=true,noBoard=true})
 check(#(H.perks.currentChoice or {})==0 and O.offer==true,'F setup: offer flag set, no board')
 Held(H,M,'F offer open')
end
do local H,M,A,O,source=Live(2);Deliver(H,A,O,Owned(H,source,410002,2),{offer=true});Held(H,M,'F2 offer shown') end
-- G. The game's choice latch is still set.
do local H,M,A,O,source=Live(-1);Deliver(H,A,O,Owned(H,source,410002,2),{latch=true});Held(H,M,'G host pending') end
-- H. Another Echo choice board is open.
do
 local H,M,A,O,source=Live(2)
 Deliver(H,A,O,Owned(H,source,410002,2),{board={{spellId=410005,quality=0},{spellId=410006,quality=3},{spellId=410008,quality=1}}})
 Held(H,M,'H board open')
end
-- I. Same-ID, same-quality: the recorded choice is the removed Echo itself.
do
 local H,M,A,O,source=Live(2,{plan={{spellId=410004,quality=3,stacks=1}},
  offer=function(src,h)return {{spellId=src,quality=h.db[src].quality},{spellId=410008,quality=1},{spellId=410005,quality=0}} end})
 check(Receipt().selectedKey==Receipt().removed,'I setup: the recorded choice is the removed Echo')
 Deliver(H,A,O,Owned(H,source,source,tonumber(Receipt().removed:match(':(%d+)$'))))
 Held(H,M,'I same-ID');check(M.Status().reason:find('same-ID',1,true)~=nil,'I: reported as the same-ID ambiguity')
end
-- J. The spend was never confirmed: the offer arrived without the one-Orb
-- decrement; the player chose; the balance then moved and the result arrived.
do
 local H,M,A,O=Fresh();Loadouts(H,A)
 assert(M.Start(3));local source=O.source
 O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});M.Pump()
 check(Receipt().spendConfirmed==false and H.Count('take')==0,'J setup: no confirmed spend, Nexus does not choose')
 check(H.service.SelectPerk(410002)==true,'J setup: the player chooses');H.Advance(.5)
 O.charges=O.charges+2;H.Advance(1)
 Deliver(H,A,O,Owned(H,source,410002,2));H.Advance(1)
 Held(H,M,'J spend not confirmed')
end
print('PASS live Orb balance drift after a confirmed spend: exact result settles once, continuation paused, every other hold kept checks='..checks)
