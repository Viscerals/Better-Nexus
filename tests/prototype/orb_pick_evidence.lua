-- 035 part 1: a manual Echo pick is never lost from the record.
--
-- The 034 probes showed two ways a real pick on the recorded offer leaves no trace:
--  * the choice callback needs a successful O.Read() and an equal context at that
--    instant, and drops the pick silently when the read fails for a moment;
--  * a live receipt records the pick at its next 0.2 s pass, so a reload or logout
--    before that pass loses it.
--
-- Contract pinned here (synthetic data only; real Store, OrbRuntime, OrbAdapter):
--  1. At the SelectPerk hook boundary the raw observation is captured at once, with
--     plain reads of the game's own tables and without O.Read(), and written to the
--     supported saved row in time for a normal reload or logout. It is bounded,
--     deidentified and NON-AUTHORITATIVE: no selected field is fabricated, no
--     settlement gate is relaxed, and a held, unmatched, context-poor or unreadable
--     observation never settles anything.
--  2. A pick whose context checks pass is recorded in the receipt at once (the same
--     fields and gates as before), also for a live receipt.
--  3. The game's own callback is unchanged: return values, invocation count and
--     errors; a failure inside Nexus never reaches the caller; the roll trace
--     setting changes nothing.
--  4. Nothing is sent: no spend and no choice by Nexus, the receipt, its spent count
--     and its limit stay, the loading screen and the reload keep the evidence.
-- The disk write itself is the game's own save at reload or logout; a crash before it
-- is not covered and is not claimed.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local F=S.Shape();local OFFER=S.Offer(F)
local failures={}
local function section(name,fn)
 local ok,err=pcall(fn)
 if not ok then failures[#failures+1]=name..': '..tostring(err) end
end
local function World(opts)
 local H,M,A,O=S.World(F,{slot=101,latch=opts and opts.latch,charges=F.receipt.chargesBefore-1,open=true})
 return H,M,A,O
end
local FIELDS={id=1,q=1,board=1,m=1,acc=1,op=1,slot=1,sk=1,rd=1,u=1,ph=1,ep=1,at=1,c=1,inb=1}
local function Entry(n) local p=R.Saved();return p and type(p.picks)=='table' and p.picks[n] or nil end
local function Exact(H,pickId) -- the exact result of the pick: the receipt's own offered card arrives
 H.granted=S.OwnedMap(F,H,pickId);H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil
 H.orbs.offer=false
end

-- 1. Normal flow: a restored receipt, the offer open, the player picks. The record is
-- made at once (as before) and the raw observation sits next to it.
section('1 normal flow',function()
 local H,M,A,O=World({latch=false})
 S.Pass(H,M,A,2)
 local calls=R.Calls(H)
 local id=S.IdQ(OFFER[2])
 check(R.Pick(H,id)==true,'the game accepted the pick')
 local p=R.Saved()
 check(p.selectedKey==OFFER[2] and p.choiceObserved==true,'the choice is recorded at once, as before')
 check(type(p.picks)=='table' and #p.picks==1,'one raw observation is stored with the receipt')
 local e=p.picks[1]
 check(e.id==id and e.q==1 and e.m=='offer' and e.acc==true and e.rd=='ok' and e.u==true and e.c==1,
  'matching offer, accepted, observer ok, used by the receipt')
 check(e.ph=='w' and e.slot==101 and e.sk==true and e.op==true,'lifecycle phase, slot and offer flag are plain facts')
 check(calls.nexusSelects()==0 and calls.spend==0,'Nexus sent nothing')
end)

-- 2. The read fails at the instant of the pick (the 034 probe P2). The raw observation
-- is stored; nothing is fabricated; the later exact result does not settle it.
section('2 read failure at the instant',function()
 local H,M,A,O=World({latch=false})
 S.Pass(H,M,A,2)
 local before=R.Saved()
 local spent,limit=before.spent,before.limit
 local calls=R.Calls(H)
 local id=S.IdQ(OFFER[2])
 local restore=R.BreakOwned(H)
 check(R.Pick(H,id)==true,'the game accepted the pick')
 local p=R.Saved()
 check(p.selectedKey==nil and p.choiceObserved==nil and p.selectionAttempted==nil and p.choiceMayHaveBeenSent==nil,
  'no selected field is fabricated from the raw observation')
 check(type(p.picks)=='table' and #p.picks==1,'the raw observation is saved at once, with no time passing')
 local e=p.picks[1]
 check(e.id==id and e.m=='offer' and e.acc==true and e.rd=='fail' and e.u==false,'raw: matches the offer, observer read failed, not used')
 restore();H.Advance(.5)
 Exact(H,OFFER[2]);S.Pass(H,M,A);S.Rechecks(H,M,3)
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.pending==true and v.selectedKey==nil and v.recovery=='UNOBSERVABLE','an exact result still ends UNOBSERVABLE: nothing was inferred')
 local q=R.Saved()
 check(q.spent==spent and q.limit==limit and q.spendConfirmed==true,'spent and limit are kept')
 check(#q.picks==1 and q.picks[1].id==id,'the raw observation is kept')
 check(calls.nexusSelects()==0 and calls.spend==0,'no spend and no choice was replayed')
 check(select(2,Nexus.OrbRuntime.Resume())~=nil,'Resume stays refused')
end)

-- 3. A live receipt and an immediate reload (the 034 probe P3b).
section('3 live receipt, immediate reload',function()
 local H,M,A,O=S.Fresh()
 local src,slots=S.SpendOfferNoChoice(H,M,A,O)
 local calls=R.Calls(H)
 check(R.Pick(H,410002)==true,'the game accepted the pick, no time passes')
 local p=R.Saved()
 check(p.selectedKey=='410002:2' and p.choiceObserved==true,'the matching pick is recorded at once for a live receipt')
 check(type(p.picks)=='table' and #p.picks==1 and p.picks[1].u==true,'raw observation stored, marked used')
 M=R.Reload(H)
 S.Pass(H,M,A);S.Rechecks(H,M,2)
 local q=R.Saved()
 check(q.selectedKey=='410002:2' and q.choiceObserved==true,'the record survives the reload')
 check(calls.nexusSelects()==0 and calls.spend==0,'Nexus sent nothing')
end)

-- 4. A held receipt (the loadout hold is set): the pick is kept as evidence only.
section('4 held receipt',function()
 local H,M,A,O=World({latch=true})
 S.Pass(H,M,A,2)
 local id=S.IdQ(OFFER[2])
 local calls=R.Calls(H)
 check(R.Pick(H,id)==true,'the game accepted the pick')
 local p=R.Saved()
 check(p.selectedKey==nil and p.choiceObserved==nil and p.loadoutChanged==true,'a held receipt records no choice')
 check(type(p.picks)=='table' and #p.picks==1 and p.picks[1].rd=='noctx' and p.picks[1].m=='offer' and p.picks[1].u==false,
  'but the raw observation is kept: no observer context, matching offer, not used')
 Exact(H,OFFER[2]);S.Pass(H,M,A);S.Rechecks(H,M,3)
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.state=='PAUSED' and v.gate=='loadout' and v.selectedKey==nil,'the hold and its gate are unchanged')
 check(calls.nexusSelects()==0 and calls.spend==0,'Nexus sent nothing')
end)

-- 5. An offer that is not the recorded one, and an Echo that is not on the board.
section('5 unmatched offer',function()
 local H,M,A,O=World({latch=false})
 S.Pass(H,M,A,2)
 H.perks.pendingSelectSpellId=nil
 H.Board({{spellId=500050,quality=3},{spellId=500051,quality=3},{spellId=500052,quality=2}})
 S.Pass(H,M,A,1)
 check(R.Pick(H,500051)==true,'the game accepted a pick on another board')
 local p=R.Saved()
 check(p.selectedKey==nil and p.choiceObserved==nil,'a pick on an unmatched board is not recorded for the receipt')
 check(#p.picks==1 and p.picks[1].m=='other' and p.picks[1].u==false and p.picks[1].inb~=false,'raw: other board, not used')
 check(R.Pick(H,424242)==false,'the game refused an Echo that is not on the board')
 local q=R.Saved()
 check(#q.picks==2 and q.picks[2].inb==false and q.picks[2].acc==false,'raw: not on the board, not accepted')
end)

-- 6. Duplicate callbacks and bounds.
section('6 duplicates and bounds',function()
 local H,M,A,O=World({latch=true})
 S.Pass(H,M,A,2)
 local id=S.IdQ(OFFER[1])
 check(R.Pick(H,id)==true)
 for _=1,4 do R.Pick(H,id) end
 local p=R.Saved()
 check(#p.picks==1 and p.picks[1].c==5,'five identical callbacks are one entry with a count')
 for i=1,12 do R.Pick(H,900000+i) end
 p=R.Saved()
 check(#p.picks==3,'at most three entries are kept')
 check(p.picks[1].id==id and p.picks[1].c==5,'the earliest evidence is never evicted')
 check(type(p.pickSeen)=='number' and p.pickSeen==17 and p.pickDropped==10,'callbacks seen and entries not stored are counted')
 for i=1,2000 do R.Pick(H,900100+i) end
 p=R.Saved()
 check(p.pickSeen<=999 and p.pickDropped<=999,'the counters are bounded')
 for _,e in ipairs(p.picks) do
  for k in pairs(e) do check(FIELDS[k],'only plain fields: '..tostring(k)) end
 end
 check(R.Plain(p.picks),'values are numbers, booleans or short text')
 check(R.Same(R.Saved().picks,Nexus.Store.State().orbRefinement.pending.picks),'the Store read shows the same entries')
end)

-- 7. Failed persistence: kept in memory, never fatal, retried, flushed at logout.
section('7 failed persistence',function()
 local H,M,A,O=World({latch=true})
 S.Pass(H,M,A,2)
 local id=S.IdQ(OFFER[2])
 local state=Nexus.OrbRuntime.Status().state
 local restore=R.BreakStore()
 check(R.Pick(H,id)==true)
 check(R.Saved().picks==nil,'nothing was written while the store refused')
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.rawPicks==1 and v.rawPickUnsaved==true,'the view says the observation is not saved yet')
 check(Nexus.OrbRuntime.Status().state==state,'a failed save of evidence changes no run state')
 restore();H.Advance(.5)
 check(type(R.Saved().picks)=='table' and #R.Saved().picks==1,'the next pass saves it')
 check(Nexus.OrbRuntime.RecoveryView().rawPickUnsaved==false)
 -- and the flush at logout
 local H2,M2,A2=World({latch=true})
 S.Pass(H2,M2,A2,2)
 local restore2=R.BreakStore()
 R.Pick(H2,id)
 restore2();H2.Fire('PLAYER_LOGOUT')
 check(type(R.Saved().picks)=='table' and #R.Saved().picks==1,'the logout flush saves it')
end)

-- 8. Loading screen and reentry (a live paused receipt).
section('8 loading screen',function()
 local H,M,A,O=S.Fresh()
 local src,slots=S.SpendOfferNoChoice(H,M,A,O)
 local before=R.Saved()
 local spent,limit,logSerial=before.spent,before.limit,before.logSerial
 local calls=R.Calls(H)
 R.Leaving(H)
 check(Nexus.OrbRuntime.Status().state=='PAUSED','the loading screen paused the run')
 R.Pick(H,410003)
 local e1=Entry(1)
 check(e1 and e1.ph=='l' and e1.id==410003,'a callback during the transition is kept, phase l')
 R.Entering(H)
 local restore=R.BreakOwned(H)
 R.Pick(H,410004)
 local e2=Entry(2) or Entry(1)
 local seen=false
 for _,e in ipairs(R.Saved().picks) do if e.id==410004 and e.ph=='r' and e.rd=='fail' then seen=true end end
 check(seen,'a callback just after reentry, with the read failing, is kept, phase r')
 restore();S.Pass(H,M,A,1)
 local p=R.Saved()
 check(p.spent==spent and p.limit==limit and p.logSerial==logSerial and p.spendConfirmed==true,'the receipt, spent and limit are unchanged')
 check(Nexus.OrbRuntime.Status().state=='PAUSED' and select(2,Nexus.OrbRuntime.Resume())~=nil,'still paused; Resume refused')
 check(calls.spend==0 and calls.nexusSelects()==0,'nothing was replayed')
 -- immediately after the reload the evidence is still there
 M=R.Reload(H)
 S.Pass(H,M,A);S.Rechecks(H,M,2)
 check(#R.Saved().picks>=2,'the evidence survived the reload')
end)

-- 9. The host callback is unchanged: return values, invocation count, errors.
section('9 host callback equivalence',function()
 local H,M,A,O=World({latch=false})
 local host={calls=0}
 local function spy(id)
  host.calls=host.calls+1
  if id==666 then error('host boom',0) end
  return id%2==0
 end
 H.service.SelectPerk=spy -- the hook below wraps this function
 S.Pass(H,M,A,2)
 local ref={}
 local function run(f)
  local out={}
  for _,id in ipairs({410002,410003,666,500051}) do
   local ok,a=pcall(f,id);out[#out+1]=tostring(ok)..':'..tostring(a)
  end
  return table.concat(out,'|')
 end
 local direct=run(function(id)
  host.calls=host.calls+1
  if id==666 then error('host boom',0) end
  return id%2==0
 end)
 host.calls=0
 local hooked=run(H.service.SelectPerk)
 check(hooked==direct,'return values and errors are identical: '..hooked)
 check(host.calls==4,'the host was invoked once per call: '..host.calls)
 -- a failure inside Nexus never reaches the caller
 local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1
 owner.UpdateStateV1=function() error('store boom',0) end
 local ok,v=pcall(H.service.SelectPerk,410002)
 owner.UpdateStateV1=raw
 check(ok and v==true,'a failing save inside Nexus does not reach the game caller')
end)

-- 10. The roll trace setting changes nothing.
section('10 trace on and off',function()
 local function Scenario(trace)
  local H,M,A,O=World({latch=false})
  Nexus.Store.Settings().rollTrace=trace
  S.Pass(H,M,A,2)
  local id=S.IdQ(OFFER[2])
  local restore=R.BreakOwned(H)
  R.Pick(H,id);restore();H.Advance(.5)
  local p=R.Saved()
  local copy=H.Clone(p.picks);for _,e in ipairs(copy) do e.at=nil end
  return copy,p.selectedKey,p.spent
 end
 local a,sa,pa=Scenario(true);local b,sb,pb=Scenario(false)
 check(R.Same(a,b) and sa==sb and pa==pb,'the same evidence with the roll record on and off')
end)

-- 11. No pending receipt: nothing is captured and no row is written.
section('11 no receipt',function()
 local H,M,A,O=S.Fresh()
 local writes=S.CountOrbWrites()
 H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 R.Pick(H,410002);H.Advance(.5)
 local _,row=R.Row()
 check(writes()==0 and (row==nil or row.orbRefinement==nil or row.orbRefinement.pending==nil),'no Orb write and no receipt')
end)

-- 12. The evidence is not authority: even a perfect-looking observation settles
-- nothing and fills no gate by itself.
section('12 non-authoritative',function()
 local H,M,A,O=World({latch=true})
 S.Pass(H,M,A,2)
 R.Pick(H,S.IdQ(OFFER[2]))
 local view=Nexus.OrbRuntime.RecoveryView()
 check(view.selectedKey==nil and view.choiceSent==false and view.choiceObserved==false,'the recovery view shows no choice')
 local unmet=table.concat(view.unmet,',')
 check(unmet:find('choice',1,true)~=nil,'the choice requirement is still unmet in the record')
 local line
 for _,l in ipairs(Nexus.SupportReport.OrbLines()) do if l:find('raw picks',1,true) then line=l end end
 check(line~=nil,'the support report counts the raw picks')
 check(not line:find('%d%d%d%d%d%d') and not line:find(':%d'),'and names no Echo id or board: '..tostring(line))
end)

-- 13. The contextual read THROWS at the instant (not a refusal: an error inside a game
-- adapter call). The caller sees the host's own result, and the observation is kept.
section('13 callback read throws',function()
 local H,M,A,O=World({latch=false})
 S.Pass(H,M,A,2)
 local id=S.IdQ(OFFER[2])
 local owned=A.Owned
 A.Owned=function() error('synthetic adapter failure',0) end
 local ok,v=pcall(R.Pick,H,id)
 A.Owned=owned
 check(ok and v==true,'the game caller gets the host result and no error')
 local p=R.Saved()
 check(p.selectedKey==nil and #p.picks==1 and p.picks[1].rd=='err' and p.picks[1].m=='offer' and p.picks[1].u==false,
  'the observation is kept with the failure named; nothing is fabricated')
end)

-- 14. A callback that arrives while the observation is being saved (re-entrant) is
-- bounded and loses nothing that was already kept.
section('14 re-entrant callback',function()
 local H,M,A,O=World({latch=true})
 S.Pass(H,M,A,2)
 local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1
 local depth=0
 owner.UpdateStateV1=function(fn,...)
  local scratch={}
  if depth==0 and pcall(fn,scratch) and scratch.orbRefinement~=nil then
   depth=1;R.Pick(H,900001);depth=0 -- the nested callback during our own write
  end
  return raw(fn,...)
 end
 R.Pick(H,S.IdQ(OFFER[1]))
 owner.UpdateStateV1=raw
 local p=R.Saved()
 check(type(p.picks)=='table' and #p.picks>=1 and #p.picks<=3,'bounded')
 local first=false
 for _,e in ipairs(p.picks) do if e.id==S.IdQ(OFFER[1]) or e.id==900001 then first=true end end
 check(first and p.pickSeen>=1 and p.pickSeen<=3,'the callbacks are counted and kept: '..tostring(p.pickSeen))
 check(p.selectedKey==nil,'and nothing is fabricated')
end)

-- 15. Nexus's own pick is not captured as an observation: it is saved before the call.
section('15 own pick',function()
 local H,M,A,O=S.Fresh()
 H.OrbPlan({{spellId=410002,quality=2,stacks=1}})
 H.Approve(3,false)
 H.Offer({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 H.Advance(1)
 check(H.Count('take')==1,'the run chose the target itself')
 local p=Nexus.Store.State().orbRefinement.pending
 check(p~=nil and p.selectedKey=='410002:2' and p.picks==nil and p.pickSeen==nil,'its own pick is the receipt\'s choice, not a raw observation')
end)

-- 16. Saved evidence is data, not truth: a damaged file is rebuilt from known plain fields.
section('16 saved evidence is sanitized',function()
 local junk={
  {id=500001,q=1,board='500037:1,500001:1,500038:1',m='offer',acc=true,evil='x',c=5,slot=101,at=1700000000,ph='w'},
  'text',42,{id='abc'},{id=-5},
  {id=500006},{id=500007},
 }
 local H,M,A,O=S.World(F,{slot=101,latch=true,charges=F.receipt.chargesBefore-1,open=true})
 M=S.Reload(H,function(row,state)
  for _,r in ipairs({row,state}) do r.picks=H.Clone(junk);r.pickSeen=1000000000;r.pickDropped=-3 end
 end)
 S.Pass(H,M,A,2)
 R.Pick(H,S.IdQ(OFFER[1]))
 local p=R.Saved()
 check(type(p.picks)=='table' and #p.picks==2,'the damaged entries were dropped: '..tostring(p.picks and #p.picks))
 for _,e in ipairs(p.picks) do
  for k in pairs(e) do check(FIELDS[k],'only known fields: '..tostring(k)) end
 end
 local e=p.picks[1]
 check(e.id==500001 and e.q==1 and e.m=='offer' and e.c==5 and e.evil==nil and e.at==1700000000,'the valid first entry is kept, an unknown field is not')
 check(p.pickSeen==1 and p.pickDropped==nil,'out-of-range counters are rebuilt, not trusted: '..tostring(p.pickSeen))
end)

-- 17. A pick after the load but before the first timed pass is still captured: the hook is
-- installed when the receipt is restored, not at the first successful read.
section('17 pick before the first pass',function()
 local H,M,A,O=World({latch=true})
 M.BlocksOrdinary() -- the first owner call after the load restores the receipt
 check(R.Pick(H,S.IdQ(OFFER[2]))==true,'the game accepted the pick')
 local p=R.Saved()
 check(type(p.picks)=='table' and #p.picks==1 and p.picks[1].m=='offer','captured with no pass and no read in between')
 check(p.picks[1].ph=='r','still in the reentry phase: no read has succeeded yet')
end)

if #failures>0 then error(#failures..' section(s) failed:\n'..table.concat(failures,'\n'),0) end
print('PASS Orb pick evidence: raw observation kept at the hook boundary, non-authoritative, callback unchanged checks='..checks)
