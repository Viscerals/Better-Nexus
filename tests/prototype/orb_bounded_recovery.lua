-- Synthetic services; real Orb owner, adapter, Store and policy. No live spending.
local R=dofile('tests/prototype/orb_recovery_support.lua')
local checks=0
-- SETUP establishes inputs, EXPECT checks behavior, and GUARD preserves safety.
-- Executed source-bound results are recorded separately from these predicates.
local function check(v,m)
 assert(v,m);checks=checks+1
end
local function fresh(limit)
 local H,M,A,O=R.S.Fresh()
 R.S.Loadouts(H,A)
 H.perks.currentChoice={}
 assert(M.Start(limit or 6))
 return H,M,A,O
end
local function bareRequest() SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME) end
local function quietServer(H,mode)
 local server=R.Server(H,{mode=mode})
 H.service.RequestChoice=function() bareRequest();server.queue[#server.queue+1]={op=16,body=''} end
 return server
end
local function waitFor(H,predicate,seconds)
 for _=1,(seconds or 30)*4 do if predicate() then return true end;H.Advance(.25) end
 return predicate()
end
local function lostResult(H,O)
 H.Offer();H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
end
-- Capacity branch fixtures are actual validated immutable archive entries.
-- Distinct retained receipt serials are archived by real Check/Confirm; no
-- placeholder digest, invalid receipt or scratch-only Store callback is used.
local validArchiveEntries={};local archiveIdentities={}
for i=1,8 do
 local H,M,A,O=R.Class({latch=false,edit=function(row,state)row.logSerial=900+i;state.logSerial=900+i end})
 R.Server(H);R.S.Pass(H,M,A,1);local original=H.Clone(R.Saved())
 assert(M.ContinueBegin());assert(waitFor(H,function()return M.ContinueView().stage=='ready'end))
 assert(M.ContinueConfirm(M.ContinueView().token))
 local e=R.SavedRow('orbRecoveryArchive')[1]
 assert(R.Same(e.receipt,original) and e.resolution.confidence=='NONE' and not archiveIdentities[e.id],'SETUP valid distinct capacity entry from actual atomic Continue')
 archiveIdentities[e.id]=true;validArchiveEntries[i]=H.Clone(e)
end
local function entryBytes(t)
 local bytes=0;for k,v in pairs(t)do bytes=bytes+#tostring(k)
  if type(v)=='table'then bytes=bytes+entryBytes(v)elseif type(v)=='string'then bytes=bytes+#v else bytes=bytes+8 end
 end;return bytes
end
do
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={};M.Status();Nexus.OrbPanel.Show()
 check(NexusOrbPanel.approval:GetText():find('2 uncertain recoveries',1,true)~=nil,'Start disclosure explains bounded uncertainty before approval')
end
-- A loading transition preserves only the existing session authorization. A
-- current offer is reconciled once; the runner's idle label cannot answer it.
do
 local H,M,A,O=fresh()
 H.Fire('PLAYER_LEAVING_WORLD')
 O.known=false
 H.Advance(2)
 check(H.Count('orb-spend')==1 and H.Count('take')==0,'loading sends no action')
 H.Fire('PLAYER_ENTERING_WORLD');O.known=true
 H.Offer();H.Advance(3.5)
 check(H.Count('orb-spend')==1 and H.Count('take')==1,'current offer selected once after loading')
 H.Advance(4)
 check(H.Count('take')==1 and H.Count('orb-spend')==1,'held native choice is never repeated')
 H.Result(410002,2);H.Advance(1)
 check(H.Count('orb-spend')==2,'actual partial result continues approved build attempt')
end
-- A missed result is never manufactured. Fresh explicit empty-choice replies
-- and two quiet charge replies permit a bounded risk continuation using the
-- current build, with the original receipt retained as unconfirmed.
do
 local H,M,A,O=fresh()
 local server=R.Server(H)
 H.service.RequestChoice=function()
  bareRequest()
  server.queue[#server.queue+1]={op=16,body=''}
 end
 H.Offer()
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.Advance(.5)
 local original=H.Clone(R.Saved())
 for _=1,80 do if H.Count('orb-spend')>=2 then break end;H.Advance(.25) end
 check(H.Count('orb-spend')==2,'quiet empty reply permits the next approved attempt')
 local archive=R.SavedRow('orbRecoveryArchive')
 check(archive and #archive==1 and R.Same(archive[1].receipt,original),'unconfirmed receipt retained exactly')
 check(archive[1].resolution.outcome=='UNCONFIRMED' and archive[1].resolution.confidence=='NONE','no completion fabricated')
 check(M.Status().progress.rolledMissing==2,'actual build remains incomplete')
 check(M.Status().recoveries==1 and M.Status().unconfirmedResults==1,'recovery use and unconfirmed result are separate facts')
end
-- No reply, an earlier unsolicited empty reply, malformed/segmented replies,
-- or an outgoing naked-opcode echo cannot establish a current empty choice.
for _,mode in ipairs({'missing','old','malformed','segmented','late_bad','echo'}) do
 local H,M,A,O=fresh();local server=R.Server(H)
 assert(A.Orbs.TransportStart())
 if mode=='old' then server.Push(16,'') end
 H.service.RequestChoice=function()
  bareRequest()
  if mode=='malformed' then server.queue[#server.queue+1]={op=16,body='garbage'}
  elseif mode=='segmented' then server.queue[#server.queue+1]={op=16,body='@1234\t001/001\t'}
  elseif mode=='late_bad' then
   server.queue[#server.queue+1]={op=16,body=''}
   server.queue[#server.queue+1]={op=16,body='garbage'}
  elseif mode=='echo' then H.Fire('CHAT_MSG_ADDON',R.PREFIX,'16','WHISPER',R.ME) end
 end
 lostResult(H,O);H.Advance(45)
 check(H.Count('orb-spend')==1 and H.Count('take')==1,mode..': no retry or duplicate selection')
 check(M.Status().pending and M.Status().state=='PAUSED',mode..': receipt and truthful unresolved pause kept')
 check(not R.SavedRow('orbRecoveryArchive'),mode..': no unconfirmed archive without explicit fresh empty reply')
end
-- A native selection latch and a visible choice are independent blockers.
for _,mode in ipairs({'latch','choice','nil_unknown','invalid','balance_unknown'}) do
 local H,M,A,O=fresh();local server=quietServer(H)
 H.Offer()
 if mode~='latch' then H.perks.pendingSelectSpellId=nil end
 O.offer=false
 if mode=='choice' then H.Board({{spellId=410004,quality=3},{spellId=410003,quality=0},{spellId=410001,quality=1}})
 elseif mode=='invalid' then H.perks.currentChoice={[2]={spellId=410002,quality=2}}
 else H.perks.currentChoice=nil end
 if mode=='nil_unknown' then H.service.RequestChoice=nil end
 if mode=='balance_unknown' then O.known=false end
 H.Advance(40)
 check(H.Count('orb-spend')==1 and H.Count('take')==1,mode..': active or unreadable game state sends no duplicate')
 check(M.Status().pending and not R.SavedRow('orbRecoveryArchive'),mode..': current record stays unresolved')
end
-- Stop during loading and during the check never gains authorization later.
for _,where in ipairs({'loading','checking'}) do
 local H,M,A,O=fresh();local server=quietServer(H,'hold')
 if where=='loading' then H.Fire('PLAYER_LEAVING_WORLD');assert(M.Stop());H.Fire('PLAYER_ENTERING_WORLD');H.Offer()
 else
  lostResult(H,O)
  check(waitFor(H,function()return M.Status().recoveries==1 end),'check started before Stop')
  assert(M.Stop());server.Release()
 end
 H.Advance(40)
 check(H.Count('orb-spend')==1 and H.Count('take')==(where=='loading' and 0 or 1),'Stop during '..where..' sends nothing later')
 check(M.Status().state=='STOPPED' and M.Status().pending,'Stop during '..where..' remains stopped and unresolved')
 check(not R.SavedRow('orbRecoveryArchive'),'Stop cancels automatic archive authority')
end
do
 local H,M,A,O=fresh();quietServer(H)
 lostResult(H,O)
 H.service.RequestChoice=function()bareRequest();M.Stop()end
 H.Advance(35)
 check(M.Status().state=='STOPPED' and H.Count('orb-spend')==1,'Stop inside a refresh callback cancels later authority')
 O.known=false;M.Pump();O.known=true;M.Pump()
 check(M.Status().state=='STOPPED' and not M.Resume(),'a failed later read cannot turn Stop into a resumable pause')
end
-- Unconfirmed outcomes consume a fixed two-per-run allowance. A successful
-- replacement and an explicit Pause/Resume do not renew that allowance.
do
 local H,M,A,O=fresh(8);quietServer(H)
 lostResult(H,O)
 check(waitFor(H,function()return H.Count('orb-spend')==2 end),'first recovery continues')
 H.Offer({{spellId=410004,quality=3},{spellId=410003,quality=0},{spellId=410008,quality=1}});H.Result(410004,3)
 check(M.RunLog().entries[2].state=='confirmed','GUARD a different source/choice pair still confirms normally')
 check(waitFor(H,function()return H.Count('orb-spend')==3 end),'actual distinct replacement continues')
 assert(M.Pause());assert(M.Resume())
 lostResult(H,O)
 check(waitFor(H,function()return H.Count('orb-spend')==4 end),'second recovery continues')
 lostResult(H,O);H.Advance(35)
 local s=M.Status()
 check(s.state=='PAUSED' and s.pending and s.recoveries==2 and s.unconfirmedResults==2,'third missed outcome stops at the fixed bound')
 check(H.Count('orb-spend')==4 and #R.SavedRow('orbRecoveryArchive')==2,'bounded attempts and two retained receipts')
 H.Advance(80)
 check(H.Count('orb-spend')==4,'time never renews recovery allowance')
end
-- A check must survive every ordinary safety gate; a later transition, changed
-- assignment/locks, automatic acceptance, or refused archive cancels it.
for _,mode in ipairs({'transition','assignment','slot','locks','guid','level','service','auto_accept','store'}) do
 local H,M,A,O=fresh();local server=quietServer(H,'hold')
 lostResult(H,O)
 check(waitFor(H,function()return M.Status().recoveries==1 end),mode..': recovery started')
 if mode=='transition' then H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD')
 elseif mode=='assignment' then assert(A.SetLoadoutWishlistIdentity(1,'Changed',{{spellId=410004,quality=3,stacks=1}}))
 elseif mode=='slot' then H.perks.serverActiveSlot=2;H.Notify();A.Poll()
 elseif mode=='locks' then H.locked={['Locked']={{spellId=410007,quality=2}}};H.Notify();A.Poll()
 elseif mode=='guid' then UnitGUID=function()return '0x0000000000000099' end
 elseif mode=='level' then H.playerLevel=H.playerLevel+1
 elseif mode=='service' then H.service=H.Clone(H.service);ProjectEbonhold.PerkService=H.service
 elseif mode=='auto_accept' then ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true)
 elseif mode=='store' then Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1=function()return false end end
 server.Release();server.mode='auto';H.Advance(30)
 check(H.Count('orb-spend')==1 and H.Count('take')==1,mode..': no next command')
 check(M.Status().pending and not R.SavedRow('orbRecoveryArchive'),mode..': original exposure retained')
 if mode=='transition' or mode=='auto_accept' or mode=='store' then
  local text=M.Status().reason
  check(text:find('Stop',1,true) and not text:find('Check again',1,true) and not text:find('Try again',1,true),
   'EXPECT '..mode..' live refusal offers a real exit without fictional retry controls')
 end
end
-- Even unobserved spend attempts consume exposure; none are called spent or
-- granted. A small approved limit ends without creating another attempt.
do
 local H,M,A,O=fresh(2);quietServer(H)
 check(waitFor(H,function()return M.Status().state=='FINISHED' end,45),'uncertain exposure reaches the approved maximum')
 local s=M.Status()
 check(H.Count('orb-spend')==2 and s.spent==0 and s.uncertain==2 and s.reserved==0,'two unknown attempts stay separate from observed spend')
 check(s.progress.rolledMissing==2 and s.state~='COMPLETE','exhausted exposure does not fabricate build completion')
 check(s.reason:find('unconfirmed',1,true)~=nil,'budget stop discloses unknown outcomes')
 Nexus.OrbPanel.Show()
 check(NexusOrbPanel.usage:GetText():find('unknown spend exposure: 2',1,true)~=nil,'EXPECT semantic label correction: run page shows unknown spend exposure separately from outcome count')
 check(Nexus.OrbRuntime.RunnerView().uncertain==2 and Nexus.SupportReport.Summary():find('uncertainSpendExposure=2',1,true)~=nil,'passive owner/support facts expose uncertainty')
end
-- Explicit manual source counts authorize a finite number of source attempts.
-- An unknown attempt consumes that quota; recovery never refunds it merely
-- because current ownership still shows that source. Automatic Start instead
-- recomputes safe surplus from the actual build at each bounded continuation.
do
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
 assert(M.UseAssignedWishlist());H.Approve(6,false);quietServer(H)
 lostResult(H,O)
 check(waitFor(H,function()return H.Count('orb-spend')==2 end),'manual pool permits its other approved source attempt')
 lostResult(H,O);H.Advance(30)
 check(H.Count('orb-spend')==2 and M.Status().state=='NO_SOURCES','manual quotas are not silently refunded for an unknown outcome')
 check(M.Status().progress.rolledMissing==2 and M.Status().unconfirmedResults==2,'manual exhaustion makes no completed-build claim')
end
-- A late result and ownership push are current observations. They cannot turn
-- the archived uncertain operation or the next unoffered attempt into a
-- confirmed replacement.
do
 local H,M,A,O=fresh();local server=quietServer(H)
 lostResult(H,O)
 check(waitFor(H,function()return H.Count('orb-spend')==2 end),'new attempt follows the unconfirmed archive')
 local archived=H.Clone(R.SavedRow('orbRecoveryArchive')[1])
 server.Push(1000,'1');H.Result(410002,2);H.Advance(1)
 check(M.Status().pending and M.Status().progress.rolledMissing==1,'late ownership is real progress but does not settle the next unoffered attempt')
 check(R.Same(R.SavedRow('orbRecoveryArchive')[1],archived) and M.RunLog().entries[1].state=='unknown','late result never rewrites or confirms the archived receipt')
 check(M.RunLog().entries[2].state~='confirmed','late result not attributed to the next attempt')
end
-- A real complete build ends the approved run after an unconfirmed outcome.
do
 local H,M,A,O=fresh();quietServer(H)
 lostResult(H,O)
 check(waitFor(H,function()return H.Count('orb-spend')==2 end),'retry for actual completion starts')
 H.Offer();H.Result(410002,2)
 check(waitFor(H,function()return H.Count('orb-spend')==3 end),'still missing one target copy')
 H.Offer();H.Result(410002,2);H.Advance(10)
 local s=M.Status()
 check(s.state=='COMPLETE' and s.progress.rolledMissing==0 and not s.pending,'completion requires the actual two owned target copies')
 check(H.Count('orb-spend')==3 and H.Count('take')==3 and s.recoveries==2,'completion sends no further command and retains both uncertain outcomes')
end
-- Ordinary receipt shape stays unchanged, while positive archived unknown
-- exposure must survive reload without restoring permission to spend.
do
 local H,M,A,O=fresh();quietServer(H)
 lostResult(H,O)
 check(waitFor(H,function()return H.Count('orb-spend')==2 end),'SETUP old unknown attempt archived before matching new offer')
 H.Offer()
 local old=R.SavedRow('orbRecoveryArchive')[1].receipt;local current=R.Saved()
 check(old.removed==current.removed and old.selectedKey==current.selectedKey,'SETUP two attempts use the same source and choice')
 check(current.attributionAmbiguous==true,'EXPECT ambiguity saved before the potentially matching choice is submitted')
 H.Result(410002,2) -- may be the archived attempt's late result; no operation ID
 check(M.RunLog().entries[2].state~='confirmed','EXPECT a matching late gain cannot confirm the next operation')
 check(M.Status().progress.rolledMissing==1,'GUARD actual observed ownership still advances build progress')
 check(R.Saved().attributionAmbiguous==true,'EXPECT ambiguity is retained on the current receipt')
 M=R.Reload(H);H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(2)
 check(M.Status().pending and not M.Status().running and R.Saved().attributionAmbiguous==true,'GUARD reload stays passive and cannot confirm an attribution-ambiguous receipt from one gain')
end
do
 local H,M,A,O=fresh();local server=R.Server(H)
 H.service.RequestChoice=function()
  SendAddonMessage(R.PREFIX,'16\t','WHISPER',R.ME)
  server.queue[#server.queue+1]={op=16,body=''} -- only the own framed request echoed
 end
 lostResult(H,O);H.Advance(40)
 check(H.Count('orb-spend')==1 and not R.SavedRow('orbRecoveryArchive'),'GUARD own framed-empty request echo is not an empty-choice reply')
 check(M.Status().reason:find('own choice request',1,true),'EXPECT own framed request refusal names the compatibility limit')
end
do
 local H,M,A,O=fresh();local server=R.Server(H);local choiceQueries=0
 H.service.RequestChoice=function()
  bareRequest()
  choiceQueries=choiceQueries+1
  if choiceQueries==1 then server.queue[#server.queue+1]={op=16,body=''} end
  -- A second question's nonempty answer would arrive late; do not issue it.
 end
 lostResult(H,O)
 check(waitFor(H,function()return H.Count('orb-spend')==2 end),'EXPECT quiet recovery continues after its observed choice answer')
 check(choiceQueries==1 and server.requests==2,'EXPECT one choice query accompanies the two serialized balance queries')
end
do
 local H,M,A,O=fresh();local server=quietServer(H,'hold')
 lostResult(H,O)
 check(waitFor(H,function()return M.Status().recoveries==1 end),'EXPECT live recovery begins before Continue UI control')
 Nexus.OrbPanel.Show();local popup=Nexus.OrbPanel.ShowContinue();if popup then popup:Hide() end
 M.ContinueCancel();H.Advance(.5)
 check(M.Status().recoveries==1,'EXPECT viewing or closing restored Continue cannot consume a live recovery allowance')
 check(M.ContinueView().stage~='checking' and M.ContinueView().token==nil,'GUARD restored Continue exposes no live check or token')
 server.mode='auto';server.Release()
 check(waitFor(H,function()return H.Count('orb-spend')==2 end),'EXPECT live recovery continues after harmless Continue UI access')
 check(M.Status().recoveries==1,'EXPECT UI access never renews the live allowance')
end
do
 local H,M,A,O=fresh(2);quietServer(H)
 check(R.Saved().uncertain==nil,'ordinary new receipt does not gain a zero-valued uncertainty field')
 check(waitFor(H,function()return H.Count('orb-spend')==2 end),'one unobserved attempt continues within the approved maximum')
 check(R.Saved().uncertain==1,'positive previous uncertainty is retained on the next pending receipt')
 M=R.Reload(H);H.Advance(1)
 local s=M.Status()
 check(not s.running and s.pending and s.uncertain==1 and s.reserved==1 and s.limit==2,'reload retains both exposures and maximum but no spending authorization')
 check(H.Count('orb-spend')==2 and H.Count('take')==0,'reload sends no new command')
end
-- Display permission must agree with the action owner after a failed check.
do
 local H,M,A,O=fresh();R.Server(H)
 H.service.RequestChoice=bareRequest
 H.Advance(40)
 local before=H.Clone(R.Saved())
 check(M.Status().state=='PAUSED' and not M.Status().canResume and not M.Resume(),'failed unknown-spend recovery is not offered as resumable')
 check(O.requests==2,'failed explicit check sent exactly two serialized base refreshes')
 check(R.Same(R.Saved(),before) and H.Count('orb-spend')==1 and H.Count('take')==0,'refused Resume and display keep receipt and exposure unchanged')
end
do
 local H,M,A,O=fresh();H.service.RequestChoice=nil;H.Advance(25)
 check(O.requests==1 and M.Status().recoveries==0 and M.Status().canResume,'GUARD missing choice capability retains one legacy refresh without consuming recovery allowance')
 check(M.Status().pending and H.Count('orb-spend')==1,'GUARD missing choice capability never infers absence or refunds exposure')
end
-- Refusing an oversized native choice must inspect only three valid keys plus
-- an overflow key per traversal. Count visits at the returned-input seam;
-- each existing diagnostic traversal is counted independently as well.
do
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A)
 local malformed={};for i=1,100 do malformed[i]={spellId=410002,quality=2} end
 H.perks.currentChoice=malformed
 local rawPairs=pairs;local maximum=0
 pairs=function(t)
  local iterator,state,key=rawPairs(t)
  if t~=malformed then return iterator,state,key end
  local visits=0
  return function(s,k)
   local nextKey,value=iterator(s,k)
   if nextKey~=nil then
    visits=visits+1;maximum=math.max(maximum,visits)
    if visits>4 then error('oversized choice traversal exceeded the public input bound') end
   end
   return nextKey,value
  end,state,key
 end
 local ok,snapshot,reason,stage=pcall(A.Orbs.Read)
 pairs=rawPairs
 check(ok and snapshot==nil and stage=='choice' and maximum==4,'EXPECT oversized choice reaches the actual choice stage and stops exactly at its fourth input visit')
 check(H.Count('orb-spend')==0 and H.Count('take')==0,'oversized choice refusal sends nothing')
end

-- Automatic recovery preserves two of the existing archive slots AND two
-- worst-case entry byte budgets for explicit restored-receipt Continue.
local function seedArchive(n,padding)
 local function clone(v)if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=clone(x)end;return out end
 local list={}
 for i=1,n do
  list[i]=clone(validArchiveEntries[i])
  if padding then list[i].unknown=string.rep('x',math.max(0,padding-entryBytes(list[i])-#'unknown'))end
  assert(entryBytes(list[i])<=6144,'SETUP every capacity record remains inside the real entry cap')
 end
 assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)row.orbRecoveryArchive=list end))
 return R.SavedRow('orbRecoveryArchive')
end
for _,n in ipairs({6,7}) do
 local H,M,A,O=fresh();quietServer(H);local archive=H.Clone(seedArchive(n));lostResult(H,O);H.Advance(35)
 check(M.Status().recoveries==0 and H.Count('orb-spend')==1,'EXPECT automatic entry reserve refuses before using allowance at '..n)
 check(R.Same(R.SavedRow('orbRecoveryArchive'),archive) and M.Status().pending,'GUARD existing records retained at entry reserve')
 check(M.Status().reason:find('reserved',1,true)~=nil,'EXPECT finite explicit recovery reserve explained')
end
do
 local H,M,A,O=fresh();quietServer(H);seedArchive(3,5500);lostResult(H,O);H.Advance(35)
 check(M.Status().recoveries==0 and #R.SavedRow('orbRecoveryArchive')==3,'EXPECT byte reserve refuses even with entry slots available')
end
-- Loading time does not consume the missing-offer wait or trigger recovery
-- before a delayed current offer has its ordinary post-entry opportunity.
do
 local H,M,A,O=fresh();quietServer(H)
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(25);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1)
 check(M.Status().recoveries==0 and O.requests==0,'EXPECT long loading does not immediately expire pending wait')
 H.Offer();H.Advance(1)
 check(H.Count('take')==0,'EXPECT explicit post-entry settling window precedes mutations')
 H.Advance(2)
 check(H.Count('take')==1 and M.Status().recoveries==0,'GUARD delayed present choice reconciles exactly once without recovery')
end
-- A direct passive pump cannot advance the live recovery refresh state machine.
do
 local H,M,A,O=fresh();local server=quietServer(H,'hold');lostResult(H,O)
 check(waitFor(H,function()return M.Status().recoveries==1 end),'SETUP pending quiet check')
 server.Release();local requests=server.requests;M.Pump(true)
 check(server.requests==requests and not R.SavedRow('orbRecoveryArchive'),'EXPECT passive observation sends no next recovery query or archive')
 check(waitFor(H,function()server.Release();return H.Count('orb-spend')==2 end),'GUARD normal pump retains approved continuation')
end
-- Unknown exposure is per archived operation, never its cumulative run total.
do
 local H,M,A,O=fresh(2);quietServer(H);H.Advance(35)
 local archive=R.SavedRow('orbRecoveryArchive')
 check(#archive==2 and archive[1].uncertain==1 and archive[2].uncertain==1,'EXPECT each archive entry counts only its own unknown exposure')
 local report=Nexus.OrbHistory.Report(M.RunLog())
 check(report:find('unconfirmed outcomes: 2',1,true) and report:find('unknown spend exposure: 2',1,true),'EXPECT copy report discloses uncertainty totals')
 check(not report:find('confirmed usage:',1,true),'EXPECT observed decrement is not called confirmed usage')
end


-- The protected capacity remains usable through the explicit restored path,
-- whose existing caps are finite and unchanged.
for _,setup in ipairs({{n=6,pad=0},{n=7,pad=0},{n=3,pad=5500}}) do
 local H,M,A,O=R.Class({latch=false});local server=R.Server(H);seedArchive(setup.n,setup.pad)
 local before=H.Clone(R.SavedRow('orbRecoveryArchive'));H.Advance(1)
 assert(M.ContinueBegin())
 check(waitFor(H,function()return M.ContinueView().stage=='ready' end),'GUARD explicit Continue can check with automatic reserve occupied')
 assert(M.ContinueConfirm(M.ContinueView().token))
 local archive=R.SavedRow('orbRecoveryArchive')
 check(#archive==setup.n+1 and not M.Status().pending,'EXPECT explicit Continue can use reserved capacity')
 for i,e in ipairs(before) do check(R.Same(archive[i],e),'GUARD old archive entry and unknown fields kept') end
end
-- Capacity is revalidated at the archive, after the quiet check started.
do
 local H,M,A,O=fresh();local server=quietServer(H,'hold');lostResult(H,O)
 check(waitFor(H,function()return M.Status().recoveries==1 end),'SETUP recovery started with space')
 local old=H.Clone(seedArchive(6));server.mode='auto';server.Release();H.Advance(3)
 check(M.Status().pending and H.Count('orb-spend')==1 and R.Same(R.SavedRow('orbRecoveryArchive'),old),'EXPECT final archive check protects newly occupied reserve')
 check(M.Status().reason:find('reserved',1,true)~=nil,'EXPECT final capacity refusal explains reserve')
end
-- Pause freezes, and reload discards, any live recovery authorization.
for _,mode in ipairs({'pause','reload'}) do
 local H,M,A,O=fresh();local server=quietServer(H,'hold');lostResult(H,O)
 assert(waitFor(H,function()return M.Status().recoveries==1 end))
 if mode=='pause' then assert(M.Pause());check(M.RunLog().state=='PAUSED','EXPECT history names explicit Pause during a live check') else M=R.Reload(H) end
 server.mode='auto';server.Release();H.Advance(35)
 check(not M.Status().running and M.Status().pending and H.Count('orb-spend')==1,'GUARD '..mode..' during check cannot continue or archive automatically')
 check(M.ContinueView().stage~='checking','EXPECT '..mode..' has no stale live checking display')
end
-- Unavailable or replaced secure outgoing observation fails closed.
for _,mode in ipairs({'missing_hook','changed_send'}) do
 local H,M,A,O=fresh();local server=quietServer(H,'hold');lostResult(H,O)
 if mode=='missing_hook' then hooksecurefunc=nil else
  assert(waitFor(H,function()return M.Status().recoveries==1 end))
  SendAddonMessage=function()end;server.mode='auto';server.Release()
 end
 H.Advance(40)
 check(H.Count('orb-spend')==1 and not R.SavedRow('orbRecoveryArchive'),'GUARD '..mode..' cannot establish safe empty reply')
end
-- Loading guidance belongs to the action that crossed loading, survives its
-- timeout pause, and also explains a previously paused held native choice.
for _,paused in ipairs({false,true}) do
 local H,M,A,O=fresh();H.Offer();if paused then assert(M.Pause()) end
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(20);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(32)
 check(M.Status().reason:find('/reload',1,true)~=nil,'EXPECT held-choice remedy survives long wait; paused='..tostring(paused))
 check(H.Count('take')==1 and H.Count('orb-spend')==1,'GUARD held choice never repeated')
end
do
 local H,M,A,O=fresh();H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD');H.Offer();H.Advance(6)
 check(M.Status().reason:find('/reload',1,true),'SETUP actual held-choice hint is visible before first settlement')
 H.Result(410002,2);H.Advance(1)
 check(M.RunLog().entries[1].state=='confirmed' and H.Count('orb-spend')==2,'SETUP matching first result confirms and second spend actually starts')
 H.Offer();H.Advance(30)
 check(H.Count('take')==2 and M.Status().state=='PAUSED','SETUP actual second choice reaches legacy timeout')
 check(not M.Status().reason:find('/reload',1,true),'EXPECT later ordinary choice does not inherit prior loading remedy')
end
-- Actual completion does not require inventing the ambiguous action's result.
do
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A)
 assert(A.SetLoadoutWishlistIdentity(1,'One target',{{spellId=410002,quality=2,stacks=1}}))
 H.perks.currentChoice={};assert(M.Start(5));quietServer(H);lostResult(H,O)
 assert(waitFor(H,function()return H.Count('orb-spend')==2 end));H.Offer();H.Result(410002,2);H.Advance(2)
 check(M.Status().state=='COMPLETE' and M.Status().progress.rolledMissing==0 and M.Status().pending,'EXPECT observed complete build stops with ambiguous receipt retained')
 check(R.Saved().attributionAmbiguous==true and M.RunLog().entries[2].state~='confirmed' and H.Count('orb-spend')==2,'GUARD actual completion fabricates no action attribution or further spend')
 check(M.ContinueView().eligible,'EXPECT actual build completion retains an explicit attribution exit')
 assert(M.ContinueBegin());assert(waitFor(H,function()return M.ContinueView().stage=='ready' end))
 check(M.ContinueConfirm(M.ContinueView().token) and not M.BlocksOrdinary(),'EXPECT completed build releases old operation only through durable explicit consent')
end
-- Actual fixed approval box: an independent conservative 7px glyph / 17px
-- line wrap model at its real width. Native font rendering remains untested.
do
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);Nexus.OrbPanel.Show()
 local fs=NexusOrbPanel.approval;local lines,explicit,maxChars=0,0,0;local width=fs:GetWidth()
 for para in (fs:GetText()..'\n'):gmatch('(.-)\n') do
  explicit=explicit+1;maxChars=math.max(maxChars,#para);lines=lines+1;local used=0
  for word in para:gmatch('%S+') do
   local n=#word*7;local gap=used>0 and 7 or 0
   if used>0 and used+gap+n>width then lines=lines+1;used=n else used=used+gap+n end
  end
 end
 check(explicit==2 and maxChars*7<=width and lines==2 and lines*17<=fs:GetHeight(),'EXPECT both explicit consent lines fit the actual approval box conservatively')
 check(fs:GetText():find('within this maximum',1,true) and fs:GetText():find('owned Echoes',1,true),'GUARD approval names both exposure bound and actual completion')
end


-- A partial refresh failure must not send later queries, including RequestChoice
-- whose native nonempty answer can trigger the game's own automatic acceptance.
for _,failed in ipairs({'charges','ownership'}) do
 local H,M,A,O=R.S.Fresh();local charges,owned,choices=0,0,0
 H.service.RequestChoice=function()choices=choices+1;bareRequest()end
 ProjectEbonhold.OrbService.RequestCharges=function()charges=charges+1;if failed=='charges' then error('synthetic refresh failure') end end
 H.service.RequestGrantedPerks=function()owned=owned+1;if failed=='ownership' then error('synthetic refresh failure') end end
 assert(A.Orbs.StartChoiceObserver())
 check(not A.Orbs.RequestRefresh(true),'GUARD partial refresh failure is not a successful request')
 check(charges==1 and owned==(failed=='charges' and 0 or 1) and choices==0,'EXPECT query ordering stops at failed '..failed..' refresh')
 check(H.Count('orb-spend')==0 and H.Count('take')==0,'GUARD refresh failure sends no mutation')
end
do
 local H,M,A,O=fresh(2);quietServer(H)
 assert(waitFor(H,function()return H.Count('orb-spend')==2 end));local mini=Nexus.OrbPanel.ShowMini()
 local p=mini.pending;local text=p._nexusFullText or p:GetText()
 check(text:find('Unknown spend: 1',1,true) and text:find('current exposure: 1',1,true),'EXPECT mini retains archived unknown and current reserved exposure together')
end


-- Recovery permission must survive the gap from archive to the actual next
-- submission. New unknown-choice evidence invalidates the earlier empty fact.
local function archiveGap()
 local H,M,A,O=fresh();local server=quietServer(H);lostResult(H,O)
 assert(waitFor(H,function()local a=R.SavedRow('orbRecoveryArchive');return a and #a==1 end))
 assert(H.Count('orb-spend')==1,'SETUP exact archive-to-next-command gap')
 return H,M,A,O,server
end
do
 local H,M,A,O,server=archiveGap();assert(M.Pause())
 local reason=M.CompactStatus().reason;local raw=A.Orbs.Read;local reads=0
 A.Orbs.Read=function(...)reads=reads+1;return raw(...)end
 for _=1,8 do M.Pump()end;H.Advance(11)
 A.Orbs.Read=raw
 check(reads==0 and M.CompactStatus().reason==reason,
  'BOUND paused post-archive permit performs no full reads and preserves the explicit Pause reason: '..reads)
 local takes=H.Count('take');server.Push(16,'garbage');server.Push(16,'')
 check(M.Resume() and H.Count('orb-spend')==2 and H.Count('take')==takes,
  'GUARD explicit Resume classifies the complete transport backlog and spends at most once')
end
for _,kind in ipairs({'malformed','nonempty','segmented','rejected'}) do
 local H,M,A,O,server=archiveGap()
 if kind=='malformed' then server.Push(16,'garbage')
 elseif kind=='nonempty' then server.Push(16,'1,410002,2')
 elseif kind=='segmented' then server.Push(16,'@1234\t001/001\t')
 else server.Push(16,'',{sender='OtherSender'}) end
 H.perks.currentChoice=nil;H.Advance(.25)
 check(H.Count('orb-spend')==1 and not M.Status().pending,'EXPECT '..kind..' after archive invalidates next-command permission')
 check(#R.SavedRow('orbRecoveryArchive')==1 and M.Status().recoveries==1,'GUARD post-archive hold never repeats archive or allowance')
end
do
 local H,M,A,O,server=archiveGap();local requests=server.requests
 server.Push(16,'garbage');H.perks.currentChoice=nil;H.Advance(.25)
 check(H.Count('orb-spend')==1,'EXPECT newer unknown choice holds continuation')
 server.Push(16,'');H.Advance(.25)
 check(H.Count('orb-spend')==2 and M.Status().recoveries==1,'GUARD newer admitted empty response restores a still-quiet continuation')
 check(server.requests==requests,'GUARD post-archive permission sends no added refresh query')
end
for _,where in ipairs({'save','adapter','getter'}) do
 local H,M,A,O,server=archiveGap();local injected=false
 local function inject()if not injected then injected=true;server.Push(16,'garbage');H.perks.currentChoice=nil end end
 if where=='save' then
  local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1
  owner.UpdateStateV1=function(fn,...)
   local ok=raw(fn,...);if R.Saved() then inject() end;return ok
  end
 elseif where=='adapter' then
  local raw=A.Orbs.Spend;A.Orbs.Spend=function(...)inject();return raw(...)end
 else
  local raw=H.service.GetCurrentChoice;H.service.GetCurrentChoice=function()local v=raw();inject();return v end
 end
 H.Advance(.25)
 check(injected and H.Count('orb-spend')==1,'EXPECT '..where..' gap cannot use stale recovery permission at submission')
 check(#R.SavedRow('orbRecoveryArchive')==1 and M.Status().recoveries==1,'GUARD '..where..' gap retains original unconfirmed receipt and allowance')
end
for _,kind in ipairs({'latch','choice','epoch','own_bare','own_framed','status'}) do
 local H,M,A,O,server=archiveGap()
 if kind=='latch' then H.perks.pendingSelectSpellId=410002
 elseif kind=='choice' then H.Board({{spellId=410004,quality=3},{spellId=410003,quality=0},{spellId=410001,quality=1}})
 elseif kind=='epoch' then H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD')
 elseif kind=='own_bare' then bareRequest()
 elseif kind=='own_framed' then SendAddonMessage(R.PREFIX,'16\t','WHISPER',R.ME)
 else A.Orbs.TransportStatus=function()error('synthetic status failure')end end
 H.Advance(4)
 check(H.Count('orb-spend')==1,'GUARD '..kind..' invalidates post-recovery permission')
end
do
 local H,M,A,O,server=archiveGap();H.Advance(.25)
 check(H.Count('orb-spend')==2 and M.Status().recoveries==1,'GUARD unchanged quiet permission still continues exactly once')
end


do
 local H,M,A,O,server=archiveGap();local raw=A.Orbs.TransportStatus
 A.Orbs.TransportStatus=function()error('synthetic status failure')end
 M.Pump();check(H.Count('orb-spend')==1,'GUARD unreadable status does not permit a command')
 A.Orbs.TransportStatus=raw;server.Push(16,'');M.Pump()
 check(H.Count('orb-spend')==2,'EXPECT status recovery followed by newer admitted empty reply restores quiet permission')
end


-- Ownership may still advance between archive and the next command. The
-- permit is about the unresolved choice, not a demand for unchanged ownership.
do
 local H,M,A,O,server=archiveGap();H.Result(410002,2);H.Advance(.25)
 check(M.Status().progress.rolledMissing==1 and H.Count('orb-spend')==2,'GUARD actual partial ownership advances while unchanged choice permission continues')
 check(M.RunLog().entries[1].state=='unknown','GUARD current ownership never confirms the archived operation')
end

-- S1 semantic addition: a fresh exact owned gain is progress, never attribution.
-- Only the player's checked consent may release its retained blocker.
for _,reload in ipairs({false,true}) do
 local H,M,A,O=fresh();local server=quietServer(H)
 lostResult(H,O)
 check(waitFor(H,function()return H.Count('orb-spend')==2 end),'SETUP ambiguous successor starts')
 H.Offer();H.Result(410002,2);assert(M.Stop())
 if reload then M=R.Reload(H);H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(2) end
 check(M.ContinueView().eligible,'EXPECT observed attribution-only receipt has explicit checked exit, reload='..tostring(reload))
 local before=H.Clone(R.Saved());local spend,take=H.Count('orb-spend'),H.Count('take')
 assert(M.ContinueBegin())
 check(waitFor(H,function()return M.ContinueView().stage=='ready' end),'EXPECT attribution exit checks become ready')
 check(M.BlocksOrdinary() and R.Saved(),'GUARD consent alone does not release receipt')
 local token=M.ContinueView().token
 local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1
 owner.UpdateStateV1=function()return false end
 check(not M.ContinueConfirm(token) and M.BlocksOrdinary() and R.Saved(),'GUARD failed attribution archive retains receipt and gate')
 owner.UpdateStateV1=raw
 check(M.ContinueConfirm(token),'EXPECT explicit durable attribution archive succeeds')
 local archive=R.SavedRow('orbRecoveryArchive');local e=archive[#archive]
 check(R.Same(e.receipt,before) and e.resolution.outcome=='UNCONFIRMED' and e.resolution.confidence=='NONE','GUARD exact original ambiguous receipt retained without confirmation')
 check(not M.BlocksOrdinary() and not M.Status().running and M.Status().state=='STOPPED','EXPECT durable explicit exit releases ordinary gate and ends old run')
 check(H.Count('orb-spend')==spend and H.Count('take')==take and not M.Resume(),'GUARD attribution exit neither spends nor selects nor resumes')
end

do
 local H,M,A,O=fresh();local server=quietServer(H,'hold')
 assert(A.Orbs.TransportStart())
 local raw=H.service.RequestGrantedPerks
 H.service.RequestGrantedPerks=function()error('synthetic partial ownership failure')end
 local ok,why,mark=A.Orbs.RequestRefresh()
 check(not ok and type(mark)=='table' and mark.n==1 and A.Orbs.TransportStatus().requests==1,'EXPECT sent partial refresh retains its transport mark and request count')
 -- Use the owner interface too: a later recovery must wait for this request.
 assert(not M.Recheck());local requests=server.requests
 H.service.RequestGrantedPerks=raw;H.Advance(4)
 check(M.Recheck() and server.requests==requests,'GUARD explicit Recheck requests ownership alone without overlapping the unanswered charge refresh')
 H.Advance(5)
 check(server.requests==requests,'GUARD unanswered partial refresh serializes later recovery queries')
 server.Release();H.Advance(2)
 check(server.requests>requests,'EXPECT observed reply releases outstanding refresh serialization')
end

for _,mode in ipairs({'store','observer','transport','unobservable_query','near_bytes'}) do
 local H,M,A,O=fresh();local server=quietServer(H)
 if mode=='store' then R.BreakStore()
 elseif mode=='observer' then A.Orbs.StartChoiceObserver=function()return false end
 elseif mode=='transport' then A.Orbs.TransportStart=function()return false end
 elseif mode=='unobservable_query' then H.service.RequestChoice=function()end
 else seedArchive(2,5500) end
 H.Advance(35)
 check(M.Status().recoveries==0,'EXPECT '..mode..' optional/precheck failure consumes no allowance')
 check(server.requests==1,'EXPECT '..mode..' preserves one legacy refresh without duplicate query')
 check(M.Status().pending and M.Status().state=='PAUSED' and H.Count('orb-spend')==1 and H.Count('take')==0,'GUARD '..mode..' fallback pauses without replay or receipt loss')
 check(M.Status().canResume,'EXPECT '..mode..' fallback does not install a permanent automatic gate')
end

for _,stop in ipairs({false,true}) do
 local H,M,A,O=fresh();local server=R.Server(H,{mode='hold'});local queried=false
 H.service.RequestChoice=function()bareRequest();queried=true;server.queue[#server.queue+1]={op=16,body='410002,2'}end
 check(waitFor(H,function()return queried end),'SETUP owned choice query issued for an overdue offer')
 O.charges=O.charges-1;O.offer=true
 H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 server.Push(16,'410002,2');M.Pump();H.Advance(.5)
 check(M.Status().state=='PAUSED' and H.Count('take')==0,'SETUP owed offer cancels check before any own selection')
 if stop then
  assert(M.Stop());check(not M.Resume() and not M.Status().canResume,'GUARD Stop never reopens owed-offer Resume')
 else
  check(M.Status().canResume and M.CompactStatus().canResume,'EXPECT owed unchosen offer has matching Resume affordances')
  check(M.Resume(),'EXPECT explicit Resume can finish the already owed offer')
  H.Advance(1)
  check(H.Count('orb-spend')==1 and H.Count('take')==1,'GUARD owed Resume selects once without a new spend')
  check(not M.Resume() and H.Count('take')==1,'GUARD owed choice cannot be repeated')
 end
end

do
 local H,M,A,O=fresh(3);quietServer(H)
 lostResult(H,O);assert(waitFor(H,function()return H.Count('orb-spend')==2 end))
 local mini=Nexus.OrbPanel.ShowMini();local text=mini.pending._nexusFullText or mini.pending:GetText()
 check(text:find('outcomes: 1',1,true) and text:find('current exposure: 1',1,true),'EXPECT mini shows observed-spend unknown outcome and new reservation together')
 M=R.Reload(H);H.Advance(1)
 local view=M.RunnerView()
 check(view.historyKnown==false and view.recoveries==nil and view.unconfirmedResults==nil and view.reserved==1,'EXPECT reload reports retained exposure with unavailable session history totals')
end
do
 local H,M,A,O=fresh();local server=quietServer(H,'hold');lostResult(H,O)
 assert(waitFor(H,function()return M.Status().recoveries==1 end))
 local v=M.ContinueView()
 check(v.liveRecovery and v.liveStage=='checking' and v.stage=='idle' and not v.token,'EXPECT diagnostic live stage is visible without granting manual Continue authority')
end

-- The attribution flag is set before submission: it is insufficient without
-- a fresh exact distinct owned gain, or while native/current guards disagree.
for _,mode in ipairs({'flag_only','host','latch','locks','binding','owner','service'}) do
 local H,M,A,O=fresh();quietServer(H);lostResult(H,O)
 assert(waitFor(H,function()return H.Count('orb-spend')==2 end));H.Offer()
 if mode~='flag_only' then H.Result(410002,2) else H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false end
 assert(M.Stop())
 if mode=='host' then H.perks.pendingReroll=true
 elseif mode=='latch' then H.perks.pendingSelectSpellId=410002
 elseif mode=='locks' then H.locked={['Locked']={{spellId=410007,quality=2}}};H.Notify();A.Poll()
 elseif mode=='binding' then assert(A.SetLoadoutWishlistIdentity(1,'Changed',{{spellId=410004,quality=3,stacks=1}}))
 elseif mode=='owner' then UnitGUID=function()return 'different' end
 elseif mode=='service' then H.service=H.Clone(H.service);ProjectEbonhold.PerkService=H.service end
 local spends,takes=H.Count('orb-spend'),H.Count('take')
 M.ContinueBegin();H.Advance(1)
 check(M.ContinueView().stage~='ready' and M.Status().pending and M.BlocksOrdinary(),'GUARD '..mode..' cannot gain an explicit attribution token')
 check(H.Count('orb-spend')==spends and H.Count('take')==takes,'GUARD '..mode..' explicit refusal sends no gameplay command')
end
do
 local H,M,A,O=fresh();quietServer(H);lostResult(H,O)
 assert(waitFor(H,function()return H.Count('orb-spend')==2 end));H.Offer();H.Result(410002,2);assert(M.Stop())
 M=R.Reload(H,function(saved,state)
  for _,p in ipairs({saved,state}) do p.spendConfirmed=nil;p.spent=1 end
 end)
 M.Pump();O.charges=R.Saved().chargesBefore;H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(1)
 local original=H.Clone(R.Saved());assert(M.ContinueBegin())
 assert(waitFor(H,function()return M.ContinueView().stage=='ready' end));assert(M.ContinueConfirm(M.ContinueView().token))
 local s=M.Status();local a=R.SavedRow('orbRecoveryArchive');local e=a[#a]
 check(s.spent==1 and s.uncertain==1 and s.reserved==0 and e.uncertain==1,'EXPECT unobserved current charge is retained as exposure without double charge or refund')
 check(R.Same(e.receipt,original) and not M.BlocksOrdinary(),'GUARD unknown charge archive keeps the original receipt unchanged')
end
do
 local H,M,A,O=fresh();quietServer(H);lostResult(H,O)
 assert(waitFor(H,function()return H.Count('orb-spend')==2 end));H.Offer();H.Result(410002,2);assert(M.Stop())
 assert(M.ContinueBegin());assert(waitFor(H,function()return M.ContinueView().stage=='ready' end))
 local token=M.ContinueView().token;local before=H.Clone(R.Saved());local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1
 owner.UpdateStateV1=function(fn,...)
  assert(A.SetLoadoutWishlistIdentity(1,'Changed at save',{{spellId=410004,quality=3,stacks=1}}))
  return raw(fn,...)
 end
 check(not M.ContinueConfirm(token) and M.BlocksOrdinary() and R.Same(R.Saved(),before),'GUARD actual atomic write rechecks attribution binding before clearing anything')
end
for _,where in ipairs({'before','during'}) do
 local H,M,A,O=fresh();local server=quietServer(H,'hold')
 if where=='before' then H.Advance(9) else assert(waitFor(H,function()return M.Status().recoveries==1 end)) end
 SendAddonMessage(R.PREFIX,'16\t','WHISPER',R.ME)
 server.Push(16,'');server.mode='auto';server.Release();H.Advance(35)
 check(M.Status().pending and H.Count('orb-spend')==1 and not R.SavedRow('orbRecoveryArchive'),'GUARD framed own send/echo '..where..' check cannot prove empty choice')
 check(M.Status().recoveries==(where=='before' and 0 or 1),'EXPECT only a previously admitted check consumes allowance')
end
do
 local H,M,A,O=fresh();H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD');O.known=false
 H.Advance(11)
 check(M.Status().running and H.Count('orb-spend')==1,'GUARD unreadable post-entry data retains a bounded read opportunity')
 H.Advance(1.5)
 check(not M.Status().running and M.Status().state=='PAUSED' and H.Count('orb-spend')==1 and H.Count('take')==0,'EXPECT twelve-second unreadable bound pauses without gameplay replay')
end

do
 local H,M,A,O=fresh(8);quietServer(H);lostResult(H,O)
 assert(waitFor(H,function()return H.Count('orb-spend')==2 end));lostResult(H,O)
 assert(waitFor(H,function()return H.Count('orb-spend')==3 end));H.Offer()
 H.Result(410002,2);H.Advance(14)
 check(M.Status().state=='PAUSED' and M.Status().recoveries==2 and M.Status().pending and M.ContinueView().eligible,'EXPECT exhausted two-check session retains explicit exit after actual owned progress')
 assert(M.ContinueBegin());assert(waitFor(H,function()return M.ContinueView().stage=='ready' end))
 local used=M.Status().recoveries;assert(M.ContinueConfirm(M.ContinueView().token))
 check(M.Status().recoveries==used and not M.BlocksOrdinary() and H.Count('orb-spend')==3,'GUARD explicit exit never renews exhausted live allowance or spends')
end
do
 local H,M,A,O=fresh();quietServer(H);H.Offer()
 -- The native latch refuses these player calls, but all raw pick evidence is
 -- still retained. Repeated transitions fill the bounded provenance journal.
 R.Pick(H,410003);R.Pick(H,410004);R.Pick(H,410002)
 for _=1,3 do H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD') end
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 local original=H.Clone(R.Saved())
 check(original.selectionAttempted and #original.picks==3 and #original.boundaryJournal==8,'SETUP maximal recorded choice, three picks and eight provenance entries; picks='..tostring(original.picks and #original.picks)..' journal='..tostring(original.boundaryJournal and #original.boundaryJournal))
 check(waitFor(H,function()return R.SavedRow('orbRecoveryArchive') or M.Status().state=='PAUSED' end,40),'SETUP maximal automatic entry reaches archive decision')
 local a=R.SavedRow('orbRecoveryArchive')
 check(a~=nil,'EXPECT maximal ordinary receipt deterministically archives within its finite caps')
 do
  local function measure(v,l)
   local edges,bytes,depth=0,0,l or 1
   for k,x in pairs(v) do
    edges=edges+1;bytes=bytes+#tostring(k)
    if type(x)=='table' then local e,b,d=measure(x,(l or 1)+1);edges=edges+e;bytes=bytes+b;depth=math.max(depth,d)
    elseif type(x)=='string' then bytes=bytes+#x else bytes=bytes+8 end
   end
   return edges,bytes,depth
  end
  local e,b,d=measure(a[1])
  check(a[1].receipt.selectionAttempted and #a[1].receipt.picks==3 and #a[1].receipt.boundaryJournal==8,'GUARD archive keeps the full recorded choice, pick and journal evidence rather than trimming to fit')
  check(a[1].kind=='AUTO_UNCONFIRMED' and e<=1200 and b<=6144 and d<=4,'GUARD maximal automatic entry stays inside original edge/byte/depth limits')
  print('SETUP maximal AUTO_UNCONFIRMED measured edges='..e..' bytes='..b..' depth='..d)
 end
end

for _,kind in ipairs({'full','future','malformed','oversized','changed_choice'}) do
 local H,M,A,O=fresh();quietServer(H);lostResult(H,O)
 assert(waitFor(H,function()return H.Count('orb-spend')==2 end));H.Offer();H.Result(410002,2);assert(M.Stop())
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 assert(owner.UpdateStateV1(function(row)
  if kind=='full' then
   row.orbRecoveryArchive={};for i=1,8 do row.orbRecoveryArchive[i]={v=1,id='kept'..i,cd='kept'..i,receipt={}} end
  elseif kind=='future' then row.orbRecoveryArchive={{v=2,id='newer',cd='newer',receipt={}}}
  elseif kind=='malformed' then row.orbRecoveryArchive='retained'
  elseif kind=='oversized' then row.orbRefinement.pending.futureEvidence=string.rep('x',6200)
  else row.orbRefinement.pending.selectedKey='410004:3' end
 end))
 local original=H.Clone(R.Saved());local archive=H.Clone(R.SavedRow('orbRecoveryArchive'));local spends,takes=H.Count('orb-spend'),H.Count('take')
 local begun=M.ContinueBegin()
 if begun then
  assert(waitFor(H,function()return M.ContinueView().stage=='ready' end))
  check(not M.ContinueConfirm(M.ContinueView().token),'GUARD oversized attribution entry cannot archive')
 end
 check(R.Same(R.Saved(),original) and R.Same(R.SavedRow('orbRecoveryArchive'),archive) and M.BlocksOrdinary(),'GUARD '..kind..' attribution archive refuses without evicting or clearing')
 check(H.Count('orb-spend')==spends and H.Count('take')==takes,'GUARD '..kind..' attribution refusal sends no gameplay command')
end

for _,kind in ipairs({'service','binding','level'}) do
 local H,M,A,O=fresh();quietServer(H);lostResult(H,O)
 assert(waitFor(H,function()return H.Count('orb-spend')==2 end));H.Offer();H.Result(410002,2);assert(M.Stop())
 M=R.Reload(H);M.Pump();H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(1)
 assert(M.ContinueBegin());assert(waitFor(H,function()return M.ContinueView().stage=='ready' end))
 local token=M.ContinueView().token;local original=H.Clone(R.Saved())
 if kind=='service' then H.service=H.Clone(H.service);ProjectEbonhold.PerkService=H.service
 elseif kind=='level' then H.playerLevel=H.playerLevel+1
 else assert(A.SetLoadoutWishlistIdentity(1,'Changed restored binding',{{spellId=410004,quality=3,stacks=1}})) end
 check(not M.ContinueConfirm(token) and R.Same(R.Saved(),original) and M.BlocksOrdinary(),'GUARD restored '..kind..' change invalidates the explicit token before save')
end

-- public-owner regressions. Each case starts from real receipt/archive writes;
-- no historical receipt, adapter or source policy implementation is replaced.
local r1fail={}
local function r1case(name,fn)
 local ok,why=pcall(fn)
 print(''..name..' '..(ok and 'PASS' or 'FAIL '..tostring(why)))
 if not ok then r1fail[#r1fail+1]=name..': '..tostring(why) end
end
local function r1archive(chosen)
 local H,M,A,O=fresh(1);quietServer(H)
 if chosen then lostResult(H,O) end
 assert(waitFor(H,function()return M.Status().state=='FINISHED' end,45))
 assert(not R.Saved() and #R.SavedRow('orbRecoveryArchive')==1)
 return H,M,A,O
end
-- EXPECT semantic replacement: a NEW represented approval accepts a current-
-- state baseline; historical UNKNOWN/NONE stays unchanged, never server-confirmed.
r1case('new acknowledged run observes same pair without lifetime veto',function()
 local H,M,A,O=r1archive(true);local old=H.Clone(R.SavedRow('orbRecoveryArchive'))
 assert(M.Start(3,false,M.Status().historyReview));H.Offer();assert(M.Stop())
 check(not R.Saved().attributionAmbiguous,'EXPECT acknowledged prior pair does not veto new observed replacement')
 H.Result(410002,2)
 check(not R.Saved() and M.RunLog().entries[1].reason:find('no server action correlation',1,true),'EXPECT current replacement observation states its attribution limit')
 check(R.Same(R.SavedRow('orbRecoveryArchive'),old),'GUARD old unconfirmed record remains exact')
end)
r1case('source-only ambiguity before choice and after reload',function()
 local H,M,A,O=r1archive(false);assert(M.Start(3,false,M.Status().historyReview))
 check(not R.Saved().attributionAmbiguous and not R.Saved().selectedKey and R.Saved().attributionFormat==1,'EXPECT new acknowledged source starts only under a versioned current-state baseline')
 assert(M.Stop());M=R.Reload(H);M.Pump();H.Offer();R.Pick(H,410002)
 check(R.Saved().choiceObserved and R.Saved().attributionAmbiguous,'EXPECT restored manual choice preserves source uncertainty')
 H.Result(410002,2);H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(1)
 check(R.Saved() and M.BlocksOrdinary(),'EXPECT restored source ambiguity cannot confirm')
end)
for _,reload in ipairs({false,true}) do
 r1case('manual choice reload='..tostring(reload),function()
  local H,M,A,O=r1archive(true);assert(M.Start(3,false,M.Status().historyReview));assert(M.Stop())
  if reload then M=R.Reload(H);M.Pump() end
  H.Offer();R.Pick(H,410002)
  check(R.Saved().choiceObserved and (R.Saved().attributionAmbiguous==true)==reload,'EXPECT live acknowledgment remains observation-only; reload restores conservative pair ambiguity')
  M=R.Reload(H);M.Pump();H.Result(410002,2);H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(1)
  check(R.Saved() and M.BlocksOrdinary(),'EXPECT manually chosen late gain stays unconfirmed after reload')
 end)
end
for _,mode in ipairs({'late_only','compound','compound_reload'}) do
 r1case('different archived pair '..mode,function()
  local compound=mode~='late_only'
  local H,M,A,O=r1archive(true)
  -- A new approved source pool uses A, while the retained unknown operation used B.
  assert(A.SetLoadoutWishlistIdentity(1,'Both targets',{{spellId=410002,quality=2,stacks=2},{spellId=410004,quality=3,stacks=1}}))
  assert(M.UseAssignedWishlist());assert(M.SetSource('410001:1',1));assert(M.SetLimit(3));assert(M.SetRecycle(true))
  local plan=assert(M.Prepare('auto'));assert(M.Confirm(plan.token,plan.historyAcknowledgment))
  assert(O.source==410001)
  H.Offer({{spellId=410004,quality=3},{spellId=410003,quality=0},{spellId=410008,quality=1}})
  assert(R.Saved().selectedKey=='410004:3' and R.Saved().choiceMayHaveBeenSent,'SETUP current different source/choice is actually in WAIT_RESULT')
  assert(M.Stop());M=R.Reload(H);M.Pump() -- reload deliberately discards session-only baseline
  local successor=O.source;O.source=410003;H.Result(410002,2);O.source=successor;H.Advance(.5)
  check(R.Saved() and R.Saved().attributionAmbiguous,'EXPECT late different archived pair is attribution-only')
   check(M.Status().state~='PAUSED' and R.Saved() and R.Saved().selectedKey=='410004:3',
    'EXPECT restored matched late delta retains the current chosen receipt without an unrelated-mismatch pause')
  if compound then H.Result(410004,3);H.Advance(.5) end
  assert(M.Stop())
  if mode=='compound_reload' then
   M=R.Reload(H);M.Pump();H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(1)
  end
  check(M.ContinueView().eligible==compound,'EXPECT explicit exit requires actual current chosen gain, including compound snapshot')
 end)
end
r1case('late owned completion is separate',function()
 local H,M,A,O=r1archive(true)
 assert(A.SetLoadoutWishlistIdentity(1,'One actual copy',{{spellId=410002,quality=2,stacks=1}}))
 assert(M.Start(3,false,M.Status().historyReview));H.Offer({{spellId=410004,quality=3},{spellId=410003,quality=0},{spellId=410008,quality=1}})
 H.Result(410002,2)
 check(M.Status().state=='COMPLETE' and M.Status().pending and M.Status().progress.rolledMissing==0,'EXPECT actual completion retains unresolved differently selected action')
 check(M.RunLog().entries[1].state~='confirmed' and H.Count('orb-spend')==2,'EXPECT completion invents no action and spends no more')
end)
r1case('different normal pair still settles after reload',function()
 local H,M,A,O=r1archive(true);assert(M.Start(3,false,M.Status().historyReview))
 H.Offer({{spellId=410004,quality=3},{spellId=410003,quality=0},{spellId=410008,quality=1}})
 assert(R.Saved().selectedKey=='410004:3' and not R.Saved().attributionAmbiguous,'SETUP different exact source/choice pair')
 M=R.Reload(H);M.Pump();H.Result(410004,3);H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(1)
 check(not R.Saved() and not M.BlocksOrdinary(),'GUARD versioned receipt identity preserves genuine distinct result settlement')
end)
r1case('archive memory isolates character owner',function()
 local H,M,A,O=r1archive(true);local archive=H.Clone(R.SavedRow('orbRecoveryArchive'))
 UnitGUID=function()return 'synthetic-other-owner' end
  assert(M.Start(3,false,M.Status().historyReview));assert(M.Stop());M=R.Reload(H);M.Pump()
  H.Offer();R.Pick(H,410002);H.Result(410002,2);H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(1)
  check(not R.Saved(),'GUARD another character never inherits archived source/pair ambiguity after reload discards the baseline')
 check(R.Same(R.SavedRow('orbRecoveryArchive'),archive),'GUARD foreign owner archive is retained unchanged')
end)
r1case('unrelated mismatch stays blocked',function()
 local H,M,A,O=r1archive(true);assert(M.Start(3,false,M.Status().historyReview));H.Offer()
 H.Result(410008,1)
 check(M.Status().pending and M.Status().state=='PAUSED' and not M.ContinueView().eligible,'GUARD unrelated gain is never an attributable late result')
end)
r1case('unexplained owned completion keeps mismatch blocker',function()
 local H,M,A,O=r1archive(true)
 assert(A.SetLoadoutWishlistIdentity(1,'Actual target',{{spellId=410002,quality=2,stacks=1}}))
 assert(M.Start(3,false,M.Status().historyReview));H.Offer({{spellId=410004,quality=3},{spellId=410003,quality=0},{spellId=410008,quality=1}})
 H.granted[H.names[410002]]={{spellId=410002,quality=2},{spellId=410002,quality=2}}
 H.Result(410008,1);H.Advance(1)
 check(M.Status().state=='COMPLETE' and M.Status().pending and M.BlocksOrdinary(),'EXPECT actual owned completion is independent of an unexplained operation delta')
 check(not M.ContinueView().eligible and M.RunLog().entries[1].state~='confirmed','GUARD completion never makes unrelated mismatch attributable or abandonable')
end)
for _,kind in ipairs({'future','malformed','unknown_receipt','unknown_late'}) do
 r1case('history '..kind..' fails closed',function()
  local H,M,A,O=r1archive(true)
  local owner=Nexus.MainInternals.StoreAuthorityOwner
  assert(owner.UpdateStateV1(function(row)
   if kind=='future' then row.orbRecoveryArchive[1].v=2
   elseif kind=='malformed' then row.orbRecoveryArchive='kept'
   elseif kind=='unknown_receipt' then row.orbRecoveryArchive[1].receipt.removed=nil
   else row.orbRecoveryArchive[1].late={{k='future_kind'}} end
  end))
  local archive=H.Clone(R.SavedRow('orbRecoveryArchive'));local spend=H.Count('orb-spend')
  local ok,why=M.Start(3);H.Advance(1)
  check(not ok and why:find('cannot be verified',1,true) and H.Count('orb-spend')==spend
   and R.Same(R.SavedRow('orbRecoveryArchive'),archive),
   'EXPECT unknown archive fails verification before acknowledgment and cannot spend or repair history')
 end)
end
if #r1fail>0 then error(table.concat(r1fail,'\n'),0) end
-- Lifecycle and authority behavioral regressions. These invoke the actual public owners
-- and UI handlers; SETUP establishes the boundary, EXPECT is the repaired
-- behavior, and GUARD preserves independent safety facts.
local r2fail={}
local function r2case(name,fn)
 local ok,why=pcall(fn);print(''..name..' '..(ok and 'PASS' or 'FAIL '..tostring(why)))
 if not ok then r2fail[#r2fail+1]=name..': '..tostring(why) end
end
for _,locked in ipairs({false,true}) do
 r2case('A completed lifecycle locked='..tostring(locked),function()
  local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
  local entries={{spellId=410002,quality=2,stacks=1}}
  if locked then entries[#entries+1]={spellId=410007,quality=2,stacks=1,locked=true} end
  assert(A.SetLoadoutWishlistIdentity(1,'Completion lifecycle',entries));assert(M.Start(3));quietServer(H);lostResult(H,O)
  assert(waitFor(H,function()return H.Count('orb-spend')==2 end),'SETUP unacknowledged new history remains relevant inside the same approval')
  H.Offer();H.Result(410002,2)
  local state=locked and 'ROLLED_COMPLETE' or 'COMPLETE';local before=M.Status()
  assert(before.state==state and before.pending,'SETUP real completed attribution hold')
  local spend,take=H.Count('orb-spend'),H.Count('take')
  for _,event in ipairs({'PLAYER_LEAVING_WORLD','PLAYER_ENTERING_WORLD'}) do
   H.Fire(event)
   check(M.Status().state==state,'EXPECT completion preserved immediately after '..event)
  end
  H.Advance(5);M.Pause()
  check(M.Status().state==state and not M.PrepareLimitIncrease(9),'EXPECT completed receipt cannot reopen paused limit increase')
  check(M.Status().spent==before.spent and M.Status().uncertain==before.uncertain and R.Saved() and not M.Resume(),'GUARD lifecycle retains receipt/exposure without Resume')
  check(H.Count('orb-spend')==spend and H.Count('take')==take,'GUARD completed lifecycle sends nothing')
 end)
end
local function r2held(gain)
 local H,M,A,O=fresh();local server=quietServer(H)
 lostResult(H,O);assert(waitFor(H,function()return H.Count('orb-spend')==2 end),'SETUP first archive')
 server.mode='hold';lostResult(H,O)
 assert(waitFor(H,function()return M.Status().recoveries==2 end),'SETUP successor admitted automatic check')
 assert(M.Pause());if gain then H.Result(410002,2) end
 return H,M,A,O,server
end
r2case('A held Continue real Check Cancel Confirm',function()
 local H,M,A,O,server=r2held(true);local view=M.ContinueView()
 assert(view.eligible and view.stage=='held','SETUP eligible held automatic attribution receipt')
 local f=assert(Nexus.OrbPanel.ShowContinue())
 check(f.check:IsEnabled(),'EXPECT held eligible UI enables Check')
 f.check:Click();check(M.ContinueView().stage=='checking','EXPECT real Check handler starts explicit check')
 f.cancel:Click();check(M.ContinueView().stage=='idle' and R.Saved(),'GUARD Cancel retains receipt without live ownership')
 server.Release();server.mode='auto';H.Advance(1);f.check:Click()
 assert(waitFor(H,function()return M.ContinueView().stage=='ready' end),'EXPECT fresh explicit check becomes ready')
 H.Advance(.5);local spend,take=H.Count('orb-spend'),H.Count('take');f.go:Click()
 check(not R.Saved() and not M.BlocksOrdinary() and not M.Status().running,'EXPECT real Confirm handler archives and stops')
 check(H.Count('orb-spend')==spend and H.Count('take')==take,'GUARD UI exit sends no mutation')
end)
r2case('A ineligible Continue preserves automatic owner',function()
 local H,M,A,O=fresh();quietServer(H,'hold')
 assert(waitFor(H,function()return M.Status().recoveries==1 end));assert(M.Pause())
 assert(M.ContinueView().liveRecovery and M.ContinueView().liveStage=='held','SETUP held automatic owner')
 check(not M.ContinueBegin() and M.ContinueView().liveRecovery and M.ContinueView().liveStage=='held','EXPECT ineligible manual entry cannot replace held automatic owner')
end)
for _,order in ipairs({'choice','charges','cache','pause','preadmission','loading'}) do
 r2case('B owed offer '..order,function()
  local H,M,A,O=fresh();local server=R.Server(H,{mode='hold'});local queried=false
  H.service.RequestChoice=function()bareRequest();queried=true;server.queue[#server.queue+1]={op=16,body='410002,2'}end
  if order=='preadmission' then
   H.Advance(9);assert(M.Recheck());H.Advance(30)
   assert(M.Status().state=='PAUSED' and M.Status().recoveries==0,'SETUP outstanding timeout before admission')
  else assert(waitFor(H,function()return queried end),'SETUP current choice query sent') end
  if order=='pause' then assert(M.Pause()) end
   if order=='loading' then H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD') end
  O.charges=O.charges-1;O.offer=true
  H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
  if order=='choice' then server.Push(16,'410002,2')
  elseif order=='charges' then server.Push(1220,tostring(O.charges)..',0,1') end
   M.Pump();H.Advance(order=='loading' and 3.5 or .5)
   check(M.CompactStatus().canResume and M.Status().canResume,'EXPECT equivalent strict owed offer offers Resume for '..order)
  local spend=H.Count('orb-spend');check(M.Resume(),'EXPECT owed direct Resume agrees for '..order)
  H.Advance(.5)
  check(H.Count('orb-spend')==spend and H.Count('take')==1 and not M.Resume(),'GUARD owed Resume selects once without another spend')
 end)
end
for _,event in ipairs({'rejected','nonquiet'}) do
 r2case('C unreadable retains '..event,function()
  local H,M,A,O,server=archiveGap();local raw=A.Orbs.Read
  A.Orbs.Read=function()return nil,'synthetic unreadable' end
  if event=='rejected' then server.Push(18,'x',{sender='OtherSender'})
  else server.Push(1220,tostring(O.charges)..',1,0') end
  M.Pump();A.Orbs.Read=raw;server.Push(16,'');M.Pump()
  local ok,why=M.Resume()
  check(not ok and type(why)=='string' and why:find('Stop',1,true),'EXPECT unclassified invalidation survives unknown read and fresh empty reply')
  check(not M.Status().canResume and not M.CompactStatus().canResume and H.Count('orb-spend')==1,'GUARD revoked authority is absent in action and both views')
 end)
end
for _,kind in ipairs({'epoch','own_query','observer','context'}) do
 r2case('C sticky revocation '..kind,function()
  local H,M,A,O,server=archiveGap()
  if kind=='epoch' then H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD')
  elseif kind=='own_query' then bareRequest()
  elseif kind=='observer' then SendAddonMessage=function()end
  else H.playerLevel=H.playerLevel+1 end
  H.Advance(4);server.Push(16,'');M.Pump()
  local spend=H.Count('orb-spend');local ok,why=M.Resume()
  check(not ok and type(why)=='string' and not M.Status().canResume and not M.CompactStatus().canResume,'EXPECT revoked '..kind..' permit cannot claim Resume succeeded')
  check(H.Count('orb-spend')==spend and #R.SavedRow('orbRecoveryArchive')==1,'GUARD sticky revocation neither resends nor rearchives')
 end)
end
for _,kind in ipairs({'limit','empty_balance'}) do
 r2case('C terminal precedes permit '..kind,function()
  local H,M,A,O=fresh(kind=='limit' and 1 or 6);local server=quietServer(H);lostResult(H,O)
  assert(waitFor(H,function()return R.SavedRow('orbRecoveryArchive')~=nil end),'SETUP archive before next decision')
  if kind=='limit' then server.Push(16,'garbage');H.perks.currentChoice=nil else O.charges=0 end
  M.Pump()
  check(M.Status().state==(kind=='limit' and 'FINISHED' or 'OUT_OF_ORBS'),'EXPECT real '..kind..' terminal is not masked by a permit hold')
  check(H.Count('orb-spend')==1 and not R.Saved(),'GUARD terminal sends no next action')
 end)
end
r2case('C actual host false consumes recovery permit',function()
 local H,M,A,O,server=archiveGap();O.mode='refuse';M.Pump()
 assert(H.Count('orb-spend')==2 and not R.Saved() and M.Status().state=='PAUSED','SETUP actual host false crossed and receipt cleared')
 O.mode='accept';local ok,why=M.Resume()
 check(not ok and type(why)=='string' and not M.Status().canResume,'EXPECT consumed recovery permit is not reused after host false')
 check(H.Count('orb-spend')==2,'GUARD host false cannot cause a third host call')
end)
r2case('C pre-host rejection keeps unused permit',function()
 local H,M,A,O,server=archiveGap();local raw=A.Orbs.Spend
 A.Orbs.Spend=function()return nil,'REJECTED','synthetic pre-host refusal' end;M.Pump();A.Orbs.Spend=raw
 assert(H.Count('orb-spend')==1 and not R.Saved(),'SETUP no host boundary crossed')
 check(M.Resume() and H.Count('orb-spend')==2,'GUARD pre-host refusal does not consume the unused permit')
end)
for _,kind in ipairs({'missing_query','missing_hook','throwing_hook','replaced_send'}) do
 r2case('D capability '..kind,function()
  local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
  local rawHook=hooksecurefunc;local attempts,queries=0,0
  hooksecurefunc=function(first,...)
   if first=='SendAddonMessage' then attempts=attempts+1;if kind=='throwing_hook' then error('synthetic outgoing hook failure') end end
   return rawHook(first,...)
  end
  if kind=='missing_hook' then hooksecurefunc=nil end
  if kind=='missing_query' then H.service.RequestChoice=nil
  else H.service.RequestChoice=function()queries=queries+1;bareRequest()end end
  local server=R.Server(H);assert(M.Start(6))
  if kind=='replaced_send' then SendAddonMessage=function()end end
  H.Advance(35);M.Recheck();H.Advance(1)
  check(attempts<=(kind=='missing_hook' and 0 or 1),'EXPECT outgoing hook failure is attempted at most once per adapter')
  local reason=M.Status().reason
  check(reason:find(kind=='missing_query' and 'cannot request' or 'cannot be observed',1,true)~=nil,'EXPECT actual fallback names absent '..kind)
  check(M.Status().recoveries==0 and queries==0 and R.Saved() and H.Count('orb-spend')==1,'GUARD absent capability consumes no recovery admission or query')
  local report=Nexus.SupportReport.Summary()
  check(report:find('choiceQuery=',1,true) and report:find('outgoingObserver=',1,true) and report:find('ownBare=',1,true) and report:find('ownFramed=',1,true),'EXPECT support copy exposes bounded capability and outgoing framing facts')
 end)
end
for _,cancel in ipairs({'Pause','Stop'}) do
 r2case('F finite pre-admission query '..cancel,function()
  local H,M,A,O=fresh();local server=R.Server(H);local queries=0
  H.service.RequestChoice=function()queries=queries+1;bareRequest();M[cancel]();server.queue[#server.queue+1]={op=16,body=''}end
  H.Advance(40)
  check(queries==1 and M.Status().recoveries==0 and not R.SavedRow('orbRecoveryArchive'),'GUARD synchronous '..cancel..' sends one query, zero admissions and zero archives')
  check(H.Count('orb-spend')==1 and R.Saved(),'GUARD query cancellation never automatically spends again')
  print('OBSERVED '..cancel..' queries='..queries..' admissions='..M.Status().recoveries..' hostCalls='..H.Count('orb-spend'))
 end)
end
for _,kind in ipairs({'offer','host','auto_accept','rival'}) do
 r2case('C transient guard requires fresh classified choice '..kind,function()
  local H,M,A,O,server=archiveGap();local raw=A.RivalDetected
  if kind=='offer' then O.offer=true elseif kind=='host' then H.perks.pendingReroll=true
  elseif kind=='auto_accept' then ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true)
  else A.RivalDetected=function()return true end end
  M.Pump();if M.Status().running then assert(M.Pause()) end
  assert(M.Status().state=='PAUSED','SETUP current guard held without submission')
  check(not M.Resume() and not M.Status().canResume,'EXPECT live '..kind..' guard truthfully refuses Resume')
  O.offer=false;H.perks.pendingReroll=nil;ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',false);A.RivalDetected=raw
  M.Pump();check(not M.Resume(),'GUARD clearing a local guard supplies no fresh choice fact')
  server.Push(16,'');M.Pump()
  check(M.Status().canResume and M.Resume() and H.Count('orb-spend')==2,'EXPECT actual empty reply restores choice under unchanged remaining guards')
 end)
end
r2case('E full usage and compact strip hover',function()
 local H,M,A,O=archiveGap();H.Advance(.25);assert(R.Saved(),'SETUP retained successor receipt')
 M=R.Reload(H);H.Advance(1);Nexus.OrbPanel.Show()
 local f=NexusOrbPanel;local parent=CreateFrame('Frame',nil,UIParent);parent:SetSize(300,100)
 local strip=Nexus.OrbPanel.AttachMainPanel(parent)
 assert(#f.usage:GetText()*7>f.usage:GetWidth(),'SETUP retained facts exceed conservative run usage width')
 check(f.usageHit~=nil and strip.summaryHit~=nil,'EXPECT full text helpers exist on actual usage and compact strip')
 local before=H.Count('orb-spend');local tooltip=GameTooltip;local captured
 GameTooltip={SetOwner=function()end,AddLine=function(_,value)captured=value end,Show=function()end,Hide=function()end}
 for _,pair in ipairs({{f.usage,f.usageHit},{strip.summary,strip.summaryHit}}) do
  local fs,hit=pair[1],pair[2]
  check(hit~=nil and hit._nexusText==fs,'EXPECT full text helper covers actual usage and compact strip')
  fs.GetStringHeight=function()return 120 end -- independent overflow model only
  hit:GetScript('OnEnter')(hit)
  check(captured==fs:GetText(),'EXPECT hover reveals exact complete retained facts')
 end
 GameTooltip=tooltip;check(H.Count('orb-spend')==before,'GUARD hovering sends no action')
end)
r2case('E held instruction and archive copy semantics',function()
 local H,M,A,O=r2held(true)
 check(M.BlockReason('Ordinary rolling'):find('checked Continue',1,true)~=nil,'EXPECT eligible held receipt gives its actual in-session checked exit')
 local report=Nexus.SupportReport.Summary()
 check(report:find('kind=AUTO_UNCONFIRMED',1,true) and report:find('confidence=NONE',1,true) and report:find('consent v1 SESSION_BOUNDED_TWO',1,true),'EXPECT support names actual archive kind, confidence and consent policy')
end)
for _,kind in ipairs({'full','future','malformed','oversized','changed_choice'}) do
 r2case('E deterministic archive refusal '..kind,function()
  local H,M,A,O=fresh();quietServer(H);lostResult(H,O)
  assert(waitFor(H,function()return H.Count('orb-spend')==2 end));H.Offer();H.Result(410002,2);assert(M.Stop())
  assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(row)
   if kind=='full' then row.orbRecoveryArchive=H.Clone(validArchiveEntries)
   elseif kind=='future' then row.orbRecoveryArchive={{v=2,id='kept',cd='kept',receipt={}}}
   elseif kind=='malformed' then row.orbRecoveryArchive='kept'
   elseif kind=='oversized' then row.orbRefinement.pending.futureEvidence=string.rep('x',6200)
   else row.orbRefinement.pending.selectedKey='410004:3' end
  end))
  local original=H.Clone(R.Saved());local archive=H.Clone(R.SavedRow('orbRecoveryArchive'))
  local ok,why=M.ContinueBegin()
  if kind=='oversized' or kind=='changed_choice' then
   assert(ok and waitFor(H,function()return M.ContinueView().stage=='ready' end),'SETUP eligible current proof reaches atomic archive')
   ok,why=M.ContinueConfirm(M.ContinueView().token)
  end
  local expected=kind=='oversized' and 'entry_too_large' or kind=='changed_choice' and 'receipt_changed' or 'archive_'..kind
  check(not ok and why==expected,'EXPECT '..kind..' refuses deterministically: '..tostring(why))
  check(R.Same(R.Saved(),original) and R.Same(R.SavedRow('orbRecoveryArchive'),archive) and M.BlocksOrdinary(),'GUARD exact original receipt/archive/gate retained on '..kind)
   if kind=='full' or kind=='future' or kind=='malformed' then
    check(M.BlockReason('Ordinary rolling'):find('Continue is unavailable',1,true),
     'EXPECT '..kind..' attribution guidance names the refused exit instead of promising Continue')
    if kind=='full' then
     M=R.Reload(H);M.Pump(true);H.granted=H.Clone(H.granted);H.Notify();A.Poll();H.Advance(1)
     check(M.Status(false).reason:find('Continue is unavailable',1,true),
      'EXPECT restored attribution gate also names the full-archive refusal')
    end
   end
 end)
end
r2case('E actual versioned maximal automatic receipt',function()
 local H,M,A,O=archiveGap();M.Pump();H.Offer()
 R.Pick(H,410003);R.Pick(H,410004);R.Pick(H,410002)
 for _=1,3 do H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD') end
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 local original=H.Clone(R.Saved())
 assert(original.attributionFormat==1 and original.attributionAmbiguous and #original.picks==3 and #original.boundaryJournal==8,'SETUP maximal versioned ambiguous receipt')
 assert(waitFor(H,function()local a=R.SavedRow('orbRecoveryArchive');return #a==2 end,40),'EXPECT maximal representation deterministically archives')
 local e=R.SavedRow('orbRecoveryArchive')[2]
 local function size(v,level)
  local edges,bytes,depth=0,0,level or 1
  for k,x in pairs(v) do edges=edges+1;bytes=bytes+#tostring(k)
   if type(x)=='table' then local n,b,d=size(x,(level or 1)+1);edges=edges+n;bytes=bytes+b;depth=math.max(depth,d)
   elseif type(x)=='string' then bytes=bytes+#x else bytes=bytes+8 end
  end
  return edges,bytes,depth
 end
 local edges,bytes,depth=size(e)
 check(R.Same(e.receipt,original) and e.kind=='AUTO_UNCONFIRMED','GUARD complete maximal encoded receipt retained without trimming')
 print('OBSERVED maximal same-approval entry edges='..edges..' bytes='..bytes..' depth='..depth)
 check(edges+32<=1200 and bytes+512<=6144 and depth==4,
  'GUARD maximal versioned representation keeps its complete late reserve within unchanged entry caps')
 check(edges<=1200 and bytes<=6144 and depth<=4,'GUARD actual post-representation remains within unchanged caps')
 print('OBSERVED maximal versioned entry edges='..edges..' bytes='..bytes..' depth='..depth)
end)
-- Current owner cancellation and owed-offer orders use real callback/event paths.
for _,cancel in ipairs({'Pause','Stop'})do for _,fault in ipairs({'missing_send','throw'})do
 r2case('pre-admission '..cancel..' then '..fault,function()
  local H,M,A,O=fresh();local server=R.Server(H);local queries=0
  H.service.RequestChoice=function()
   queries=queries+1;assert(M[cancel]())
   if fault=='throw'then error('synthetic request failure after cancellation')end
  end
  H.Advance(20)
  local expected=cancel=='Stop' and 'STOPPED' or 'PAUSED';local status=M.Status()
  assert(queries==1 and status.recoveries==0 and R.Saved(),'SETUP one pre-admission request failed after explicit cancellation')
  check(status.state==expected and not status.running,'EXPECT failed callback preserves explicit '..cancel..' state')
  H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD')
  check(M.Status().state==expected and not M.Status().running,'GUARD lifecycle cannot reopen cancelled owner')
  check(H.Count('orb-spend')==1 and H.Count('take')==0 and not R.SavedRow('orbRecoveryArchive'),'GUARD cancelled failed query adds no gameplay action/archive')
  if cancel=='Pause'then check(M.Status().canResume and M.Resume(),'EXPECT explicit Pause before admission retains guarded Resume')
  else check(not M.Resume(),'GUARD stopped query owner never offers Resume')end
 end)
end end
for _,event in ipairs({'PLAYER_ENTERING_WORLD','PLAYER_LOGOUT'})do
 r2case('unclassified event holds admitted check '..event,function()
  local H,M,A,O=fresh();quietServer(H,'hold')
  assert(waitFor(H,function()return M.Status().recoveries==1 end),'SETUP automatic check admitted')
  H.Fire(event)
  check(M.Status().state=='PAUSED' and not M.Status().running and M.ContinueView().liveStage=='held',
   'EXPECT unclassified lifecycle event truthfully holds the admitted owner')
  check(H.Count('orb-spend')==1 and H.Count('take')==0 and M.Status().recoveries==1,'GUARD event neither replays nor refunds admitted check')
 end)
end
r2case('pre-admission refusal keeps explicit Resume route',function()
 local H,M,A,O=fresh();local server=quietServer(H,'hold')
 H.Advance(9);assert(M.Recheck());H.Advance(30)
 assert(M.Status().state=='PAUSED' and M.Status().recoveries==0 and R.Saved(),'SETUP outstanding request refused before admission')
 server.Release();server.mode='auto';H.Advance(.5)
 check(M.Status().canResume and M.CompactStatus().canResume,'EXPECT zero-admission refusal does not install an automatic owner gate')
 check(M.Resume() and H.Count('orb-spend')==1 and H.Count('take')==0,'GUARD explicit Resume retains original receipt and action checks')
end)
for _,order in ipairs({'balance_cache','balance_reply','rejected_reply'})do
 r2case('owed offer after '..order,function()
  local H,M,A,O=fresh();local server=quietServer(H,'hold')
  assert(waitFor(H,function()return M.Status().recoveries==1 end),'SETUP automatic check admitted before balance')
  O.charges=O.charges-1
  if order=='balance_reply'then server.Push(1220,tostring(O.charges)..',-1,0')
  elseif order=='rejected_reply'then server.Push(1220,tostring(O.charges)..',-1,0',{sender='OtherSender'})end
  M.Pump();assert(M.Status().state=='PAUSED','SETUP first pump sees only balance/refusal')
  O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}});M.Pump()
  if order=='rejected_reply'then
   check(not M.Status().canResume and not M.Resume(),'GUARD rejected transport is excluded from owed Resume')
  else
   check(M.Status().canResume and M.CompactStatus().canResume,'EXPECT later strict owed offer is independent of balance-first refusal order')
   check(M.Resume() and H.Count('orb-spend')==1 and H.Count('take')==1,'GUARD owed Resume selects once without repeating spend')
  end
 end)
end
r2case('host-false boundary survives display wording',function()
 local H,M,A,O,server=archiveGap();local raw=A.Orbs.Spend
 A.Orbs.Spend=function(...)
  local ok,kind,reason,boundary=raw(...)
  if kind=='REJECTED'then reason='A different display refusal.'end
  return ok,kind,reason,boundary
 end
 O.mode='refuse';M.Pump();A.Orbs.Spend=raw;O.mode='accept'
 assert(H.Count('orb-spend')==2 and not R.Saved(),'SETUP actual host false crossed once and retained no submitted receipt')
 check(not M.Resume() and H.Count('orb-spend')==2,'EXPECT actual host crossing consumes one-use permit independently of display prose')
end)
r2case('real pre-host rejection cannot masquerade as host false',function()
 local H,M,A,O,server=archiveGap();local raw=A.Orbs.Spend
 A.Orbs.Spend=function(token,key,expected,guard)
  local stale=H.Clone(expected);stale.charges=stale.charges+1
  local ok,kind,reason,boundary=raw(token,key,stale,guard)
  assert(not ok and kind=='REJECTED','SETUP real Adapter expected-balance guard refuses before host')
  return ok,kind,'The game refused the Orb spend.',boundary
 end
 M.Pump();A.Orbs.Spend=raw
 assert(H.Count('orb-spend')==1 and not R.Saved(),'SETUP actual host was not crossed')
 check(M.Resume() and H.Count('orb-spend')==2,'EXPECT pre-host refusal keeps unused permit regardless of display wording')
end)
for _,where in ipairs({'post_check','pre_host'})do
 r2case('invalid choice shape at '..where,function()
  local H,M,A,O,server=archiveGap();local raw=A.Orbs.Spend
  if where=='pre_host'then
   A.Orbs.Spend=function(...)
    H.perks.currentChoice={[2]={spellId=410002,quality=2}}
    return raw(...)
   end
  else H.perks.currentChoice={[2]={spellId=410002,quality=2}}end
  M.Pump();A.Orbs.Spend=raw
  check(H.Count('orb-spend')==1 and not R.Saved(),'EXPECT malformed choice getter refuses before another host call')
  if M.Status().running then assert(M.Pause())end
  H.perks.currentChoice=nil
  check(not M.Resume(),'GUARD clearing malformed cache supplies no fresh classified choice')
  server.Push(16,'');M.Pump()
  check(M.Resume() and H.Count('orb-spend')==2,'EXPECT a genuinely fresh empty reply restores only unused current choice authority')
 end)
end
r2case('automatic archive rechecks context inside actual Store callback',function()
 local H,M,A,O=fresh();quietServer(H);local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1
 local injected,calls=false,0
 owner.UpdateStateV1=function(fn,...)
  if not injected and M.ContinueView().liveStage=='ready'then
   injected=true
   return raw(function(row)
    calls=calls+1;local prior=H.playerLevel;H.playerLevel=prior+1
    local result={fn(row)};H.playerLevel=prior;return unpack(result)
   end,...)
  end
  return raw(fn,...)
 end
 lostResult(H,O);assert(waitFor(H,function()return injected end),'SETUP real automatic archive reached the Store boundary')
 owner.UpdateStateV1=raw
 assert(calls==1,'SETUP production Store invoked the actual mutator once, without scratch replay')
 check(R.Saved() and not R.SavedRow('orbRecoveryArchive'),'EXPECT fresh context change inside atomic archive preserves original pending and gate')
 check(H.Count('orb-spend')==1 and H.Count('take')==1 and M.Status().recoveries==1,'GUARD atomic refusal does not refund/replay admitted usage')
end)
r2case('running attribution guidance requires Stop first',function()
 local H,M,A,O=archiveGap();M.Pump();H.Offer();H.Result(410002,2)
 assert(M.Status().running and R.Saved().attributionAmbiguous,'SETUP actual running partial-build attribution hold')
 local original=H.Clone(R.Saved());local why=M.BlockReason('Ordinary rolling')
 check(why:find('Stop',1,true) and why:find('Continue',1,true),'EXPECT active attribution guidance names Stop before explicit Continue')
 check(R.Same(R.Saved(),original) and H.Count('orb-spend')==2,'GUARD guidance changes no receipt or action')
end)
r2case('unobservable choice query is retired for the entire approval',function()
 local H,M,A,O=fresh();local server=R.Server(H);local queries=0
 H.service.RequestChoice=function()queries=queries+1 end -- sends cannot be observed
 H.Advance(40)
 assert(queries==1 and M.Status().state=='PAUSED' and M.Status().recoveries==0,'SETUP one retired unobservable query')
 H.Offer();assert(M.Resume());H.Result(410002,2);H.Advance(.5)
 assert(H.Count('orb-spend')==2,'SETUP a genuine exact result admits the next approved receipt')
 H.Advance(40)
 check(queries==1 and M.Status().state=='PAUSED' and M.Status().recoveries==0,
  'EXPECT later receipts do not repeat a choice capability already shown unobservable')
end)
r2case('automatic check phases stop with the approved run',function()
 local H,M,A,O=fresh();quietServer(H,'hold')
 assert(waitFor(H,function()return M.ContinueView().liveStage=='checking' end),'SETUP admitted automatic check')
 local before=M.CompactStatus();Nexus.OrbPanel.ShowMini()
 check(NexusOrbMini.state:GetText():find('Recovery: Checking',1,true),'GUARD automatic phase identifies recovery checking')
 assert(M.Stop());Nexus.OrbPanel.ShowMini()
 check(M.CompactStatus().state=='STOPPED' and not M.CompactStatus().recoveryPhase
  and NexusOrbMini.state:GetText()=='Stopped','EXPECT stopped automatic check is not presented as held or resumable')
 check(H.Count('orb-spend')==1 and H.Count('take')==0,'GUARD phase rendering changes no actions')
end)
r2case('manual Continue phases identify the explicit check',function()
 local H,M,A,O=R.Class({latch=false});R.Server(H,{mode='hold'});assert(M.ContinueBegin())
 Nexus.OrbPanel.ShowMini()
 check(M.CompactStatus().recoveryKind=='manual' and NexusOrbMini.state:GetText():find('Continue: Checking',1,true),
  'EXPECT manual Continue checking is distinct from automatic recovery')
 H.Advance(16);Nexus.OrbPanel.ShowMini()
 check(NexusOrbMini.state:GetText():find('Continue refused',1,true),
  'EXPECT a refused explicit check remains labelled Continue')
 check(H.Count('orb-spend')==0 and H.Count('take')==0,'GUARD manual phase rendering submits no spend or choice')
end)
r2case('new Confirm carries the remaining classified loading window',function()
 local H,M,A,O=R.S.Fresh();R.S.Loadouts(H,A);H.perks.currentChoice={}
 assert(A.SetLoadoutWishlistIdentity(1,'One observed copy',{{spellId=410002,quality=2,stacks=1}}))
 assert(M.Start(2));H.Offer();H.Result(410002,2)
 assert(not R.Saved() and not M.Status(false).running,'SETUP previous approved run completed and released its receipt')
 assert(A.SetLoadoutWishlistIdentity(1,'Two observed copies',{{spellId=410002,quality=2,stacks=2}}))
 H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD')
 local spends,takes=H.Count('orb-spend'),H.Count('take');assert(M.Start(3))
 check(H.Count('orb-spend')==spends and not R.Saved(),
  'EXPECT new approval cannot discard the still-active three-second loading window')
 H.Advance(2.5)
 check(H.Count('orb-spend')==spends and H.Count('take')==takes,'GUARD remaining loading time submits nothing')
 H.Advance(.75)
 check(H.Count('orb-spend')==spends+1 and R.Saved() and H.Count('take')==takes,
  'EXPECT the original window expiry permits one freshly guarded new spend')
end)
if #r2fail>0 then error(table.concat(r2fail,'\n'),0) end
print('PASS bounded Orb transition and missed-result recovery checks='..checks)
