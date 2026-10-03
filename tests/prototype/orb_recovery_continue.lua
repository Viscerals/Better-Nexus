-- 035 part 2c: PHASE-ONE player-confirmed Continue for the bounded class: a confirmed spend,
-- an unresolved old receipt, no usable recorded outcome, and the original offer gone.
--
-- What Continue is: the player chooses to go on with an UNCONFIRMED outcome. Nexus keeps the
-- spend counted and the original receipt unchanged in a separate saved archive, releases the
-- old blocker only after a strict, state-bound check, and sends nothing. It never says a
-- verified Echo result exists, never refunds, repeats or chooses, never raises or removes the
-- configured limit, and never continues on its own (phase two is NOT built).
--
-- The check: two replies of the charge opcode, each observed after Nexus asked for a refresh,
-- each qualifying (see orb_transport_observer), each with an explicit third field equal to 0,
-- the same balance, internally consistent with the game's own cache, plus a fresh ownership
-- push, an empty board, no pending offer, no pick or host action, no Nexus intent. The
-- consent token binds to those values and to the loading epoch. Two uncorrelated arrivals
-- detect a change; they do NOT prove that no older server answer is still on its way, and the
-- texts say so. A loading transition only voids the attempt: it is never proof of readiness.
-- Synthetic server and game model; native behavior is NOT TESTED.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local F=S.Shape()
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
-- Build the class, start the synthetic server and let the recovery settle.
local function World(opts)
 local H,M,A,O=R.Class(opts)
 local server=R.Server(H,opts and opts.server)
 S.Pass(H,M,A,2)
 return H,M,A,O,server
end
local function Ready(H,M)
 assert(M.ContinueBegin())
 check(Until(H,M,'ready'),'the check reached ready: '..tostring(M.ContinueView().stage)..'/'..tostring(M.ContinueView().refusal))
 return M.ContinueView()
end

-- 1. Eligibility of the bounded class; everything else is refused with its reason.
section('1 eligibility',function()
 local H,M,A,O=World()
 local v=M.ContinueView()
 check(v.eligible==true and v.reason==nil and v.stage=='idle','the reported class is eligible: '..tostring(v.reason))
 check(v.archive and v.archive.count==0 and v.archive.capacity==8,'the archive is empty and holds eight')
 -- the same class with the loadout still the original one
 local H2,M2=World({latch=false})
 check(M2.ContinueView().eligible==true,'the class does not depend on the loadout hold')
 local function Reason(opts)
  local H3,M3=World(opts);return M3.ContinueView().reason,M3,H3
 end
 check(Reason({edit=function(row,state)row.spendConfirmed=nil;state.spendConfirmed=nil end})=='spend_unconfirmed','no confirmed spend')
 check(Reason({edit=function(row,state)
  for _,r in ipairs({row,state}) do r.selectedKey=F.receipt.offerKey:match('(%d+:%d+):true');r.selectionAttempted=true;r.choiceObserved=true;r.kind='TARGET' end
 end})=='choice_recorded','a recorded choice is not the class')
 local H4,M4,A4,O4=R.Class({latch=false})
 H4.Board({{spellId=500037,quality=1},{spellId=500001,quality=1},{spellId=500038,quality=1}});O4.offer=true
 S.Pass(H4,M4,A4,1)
 check(M4.ContinueView().eligible==false and M4.ContinueView().reason=='offer_open','an open offer is not the class')
 local H5,M5,A5,O5=S.Fresh()
 check(M5.ContinueView().eligible==false and M5.ContinueView().reason=='no_receipt','no receipt')
 local H6,M6,A6,O6=S.Fresh();local src=S.SpendOfferNoChoice(H6,M6,A6,O6)
 check(M6.ContinueView().eligible==false and M6.ContinueView().reason=='not_restored','a live receipt of this session is not the class')
 check(Reason({edit=function(row,state)row.guid='0xFFFF';state.guid='0xFFFF' end})=='other_character','another character')
end)

-- 2. The strict check, then the explicit confirmation. Everything that was saved stays.
section('2 continue',function()
 local H,M,A,O,server=World()
 local original=H.Clone(R.Saved())
 local calls=R.Calls(H)
 local sentBefore=#H.sent
 local spentBefore,limitBefore=M.Status().spent,M.Status().limit
 local maxBefore=M.Status().config.maxOrbs
 local v=Ready(H,M)
 check(server.requests==2,'two read-only requests, one at a time: '..server.requests)
 check(v.token~=nil and v.facts and v.facts.replies==2,'a state-bound token and two observed replies')
 check(R.Saved()~=nil and M.Status().pending==true and M.BlocksOrdinary()==true,'nothing is released before the confirmation')
 check(type(v.text)=='string' and v.text:find('unconfirmed',1,true) and v.text:find('not prove',1,true),
  'the text says the outcome is unconfirmed and that the arrivals do not prove quiescence')
 check(not v.text:lower():find('verified echo') and not v.text:lower():find('settled'),'it claims no result')
 local ok,how=M.ContinueConfirm(v.token)
 check(ok==true and how=='archived','confirmed: '..tostring(how))
 -- the saved state
 check(R.Saved()==nil,'the blocker is released: no pending receipt is saved')
 local archive=R.SavedRow('orbRecoveryArchive')
 check(type(archive)=='table' and #archive==1,'one archive entry')
 local e=archive[1]
 check(e.v==1 and e.kind=='ACK_UNCONFIRMED' and type(e.id)=='string' and #e.id<=40 and type(e.cd)=='string','a versioned entry with its identifier and content digest')
 check(R.Same(e.receipt,original),'the original receipt is retained unchanged')
 check(e.spent==original.spent and e.limit==original.limit and e.spent==170 and e.limit==219,'the known spent count and the run limit are kept exactly')
 check(e.resolution and e.resolution.outcome=='UNCONFIRMED' and e.resolution.confidence=='NONE','the outcome is unconfirmed, with no confidence claimed')
 check(e.consent and e.consent.v==1 and e.consent.policy=='TWO_OBSERVED' and e.consent.serial==v.token.serial,'the consent version, policy and serial are recorded')
 local pre=e.pre
 check(pre and pre.r1 and pre.r2 and pre.r1.ord<pre.r2.ord and pre.r1.pending==0 and pre.r2.pending==0 and pre.r1.nf==3 and pre.r2.nf==3,
  'both replies: ordinal, explicit third field present, zero')
 check(pre.req1<pre.r1.ord and pre.req2<pre.r2.ord and pre.req2>=pre.r1.ord,'each reply was observed after its own request began')
 check(pre.balance==49 and pre.rel=='one_below' and pre.slot==101 and pre.origSlot==101 and type(pre.lo)=='string','balance, its relation to the record, current and original slot')
 check(pre.fpC and pre.fpL and #pre.fpC<=16 and #pre.fpL<=16,'ownership and lock fingerprints are short digests')
 check(pre.offer==false and pre.board==0 and pre.host==false and pre.flight==false and pre.intent==false,'offer, board, host action, flight and intent were all quiet')
 check(e.post and e.post.balance==49 and e.post.fpC==pre.fpC,'the post-state is the fresh baseline')
 check(R.Plain(e,200),'the entry is plain data')
 -- the run
 local st=M.Status()
 check(st.pending==false and st.state=='STOPPED' and st.running==false,'the old run is stopped, not re-enabled')
 check(st.spent==spentBefore and st.limit==limitBefore and st.config.maxOrbs==maxBefore,'spent, limit and the configured maximum are unchanged')
 check(M.BlocksOrdinary()==false,'ordinary rolling is no longer blocked by it')
 check(select(2,M.Resume())~=nil and M.Status().running==false,'the old run cannot be resumed')
 -- nothing was sent
 check(calls.spend==0 and calls.nexusSelects()==0 and H.Count('orb-spend')==0 and H.Count('take')==0,'no spend and no choice')
 check(#H.sent==sentBefore,'no addon message was sent by Nexus')
 -- repeating the confirmation is idempotent
 local writes=S.CountOrbWrites()
 local again,why=M.ContinueConfirm(v.token)
 check(again==true and why=='already' and #R.SavedRow('orbRecoveryArchive')==1 and writes()==0,'a repeated confirmation writes nothing and adds nothing')
 -- and survives a reload
 M=R.Reload(H)
 S.Pass(H,M,A)
 check(R.Saved()==nil and #R.SavedRow('orbRecoveryArchive')==1 and M.Status().pending==false and M.Status().state~='RECOVERY','after a reload: archived, no receipt, no recovery')
 check(R.Same(R.SavedRow('orbRecoveryArchive')[1].receipt,original),'the archive is still the original receipt')
end)

-- 3. No automatic continuation: a quiet world, a ready check and a long wait change nothing.
section('3 never automatic',function()
 local H,M,A,O,server=World()
 H.Advance(120);S.Rechecks(H,M,3)
 check(M.ContinueView().stage=='idle' and server.requests<=3,'nothing starts a check on its own (only Recheck asked)')
 local v=Ready(H,M)
 H.Advance(120)
 check(M.ContinueView().stage=='ready' and R.Saved()~=nil,'a ready check waits for the player, however long')
 check(M.Status().pending==true and M.BlocksOrdinary()==true,'the blocker stays until the confirmation')
end)

-- 4. Cancel, stale tokens and a second check.
section('4 cancel and stale tokens',function()
 local H,M,A,O,server=World()
 local v1=Ready(H,M)
 check(M.ContinueCancel()==true and M.ContinueView().stage=='idle' and M.ContinueView().token==nil,'cancel returns to idle')
 local log=M.ContinueLog()
 check(#log>=2 and log[#log].outcome=='cancelled' and log[#log-1].outcome=='ready','the log keeps the ready check and its cancellation')
 local ok,why=M.ContinueConfirm(v1.token)
 check(ok==nil and why=='stale_token' and R.Saved()~=nil,'a cancelled token is dead')
 check(M.ContinueCancel()==true,'cancel is idempotent')
 local v2=Ready(H,M)
 check(v2.token~=v1.token and v2.token.serial>v1.token.serial,'a new check gives a new token')
 check(select(2,M.ContinueConfirm(v1.token))=='stale_token','the old token is still dead')
 for _,bad in ipairs({false,'x',42,{},{serial=v2.token.serial}}) do
  check(select(2,M.ContinueConfirm(bad))=='stale_token','a forged or malformed token is refused: '..type(bad))
 end
 check(M.ContinueView().stage=='ready' and R.Saved()~=nil,'refused confirmations change nothing')
 check(M.ContinueConfirm(v2.token)==true,'the live token works')
 check(select(2,M.ContinueConfirm(v1.token))=='stale_token' and #R.SavedRow('orbRecoveryArchive')==1,'afterwards the old token is still dead and nothing is added')
 check(select(2,M.ContinueBegin())=='no_receipt','no second check without a receipt')
end)

-- 5. Beginning twice is one attempt; the run keeps its state while it is checked.
section('5 repeated begin',function()
 local H,M,A,O,server=World()
 local ok,how=M.ContinueBegin()
 check(ok==true and how=='checking','begin starts the check')
 local ok2,how2=M.ContinueBegin()
 check(ok2==true and how2=='checking' and server.requests==1,'a second begin is the same attempt and sends no second request')
 check(Until(H,M,'ready'),'it reaches ready')
 local t=M.ContinueView().token
 local ok3,how3=M.ContinueBegin()
 check(ok3==true and how3=='ready' and M.ContinueView().token==t,'begin on a ready check keeps its token')
 check(server.requests==2,'and sent nothing more')
end)

-- 6. Without a loadout hold the same class behaves the same.
section('6 no hold',function()
 local H,M,A,O,server=World({latch=false})
 local original=H.Clone(R.Saved())
 local v=Ready(H,M)
 check(M.ContinueConfirm(v.token)==true and R.Saved()==nil,'continued')
 check(R.Same(R.SavedRow('orbRecoveryArchive')[1].receipt,original) and R.SavedRow('orbRecoveryArchive')[1].pre.lo=='SAME','the entry records the loadout check as SAME')
end)

-- 7. The roll trace setting changes nothing.
section('7 trace on and off',function()
 local function Scenario(trace)
  local H,M,A,O,server=World()
  Nexus.Store.Settings().rollTrace=trace
  local v=Ready(H,M);assert(M.ContinueConfirm(v.token))
  local e=H.Clone(R.SavedRow('orbRecoveryArchive')[1])
  e.at=nil;e.pre.r1.ord=nil;e.pre.r2.ord=nil;e.pre.req1=nil;e.pre.req2=nil;e.post.ord=nil
  return e
 end
 check(R.Same(Scenario(true),Scenario(false)),'the same archive entry with the roll record on and off')
end)

-- 8. The status text names Continue where it applies, and says nothing that is not true.
section('8 block texts',function()
 local H,M,A,O,server=World()
 local why=M.BlockReason('Ordinary rolling')
 check(why:find('Continue',1,true) and not why:find('not built',1,true) and not why:find('only a proposal',1,true),'the block text names the exit: '..why)
 local r=M.Status().reason
 check(not r:find('settlement path is only a proposal',1,true),'the recovery text no longer claims there is no exit: '..r)
end)

-- 9. The words: the check asks for the Orb count AND the Echoes, and no text says "nothing was sent".
section('9 what the texts say',function()
 local H,M,A,O,server=World()
 local v=M.ContinueView()
 check(v.text:find('Orb count',1,true) and v.text:find('Echoes',1,true) and v.text:find('No spend and no choice',1,true),'the intro names both read-only requests and what is not sent: '..v.text)
 assert(M.ContinueBegin());H.Advance(.01)
 check(M.ContinueView().text:find('read-only',1,true) and M.ContinueView().text:find('Echoes',1,true),'the checking text too')
 for _,code in ipairs({'pending_positive','no_reply','no_ownership','choice_recorded'}) do
  local text=M.ContinueReason(code)
  check(not text:find('Nothing was sent',1,true) and not text:find('Press Continue',1,true),code..': '..text)
 end
 check(M.ContinueReason('no_reply'):find('Check in the Continue window',1,true),'the retry text names the control that exists')
 check(M.ContinueReason('stale_token'):find('no longer current',1,true) and M.ContinueReason('nonsense')=='Nothing was changed.','codes map to words')
end)

-- 10. Only the pending receipt is cleared: every other saved field of orbRefinement stays, also an unknown one.
section('10 settings stay',function()
 local H,M,A,O,server=World()
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 assert(owner.UpdateStateV1(function(r) r.orbRefinement.futureField={a=1,b='x'};r.orbRefinement.keepMe=7 end))
 assert(M.ContinueBegin());assert(Until(H,M,'ready'));assert(M.ContinueConfirm(M.ContinueView().token))
 local _,row=R.Row()
 check(row.orbRefinement.pending==nil and row.orbRefinement.keepMe==7 and row.orbRefinement.futureField and row.orbRefinement.futureField.b=='x',
  'no other saved Orb setting was rebuilt or dropped')
end)

if #failures>0 then error(#failures..' section(s) failed:\n'..table.concat(failures,'\n'),0) end
print('PASS Orb recovery continue: strict state-bound check, explicit confirmation, archive, nothing sent, never automatic checks='..checks)
