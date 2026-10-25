-- EXPECT semantic replacement from accepted base bc5f4959: WAIT_WORLD keeps approved session
-- ownership while all actions remain held; diagnostics still settle nothing.
-- Real addon, synthetic services. Local epochs and observed relations cannot
-- correlate a server action or establish no spend. Never executes saved Lua.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S
local H,M,A,O=S.Fresh();H.OrbPlan();H.Approve(2,false)
local p=R.Saved();local v=M.BoundaryDiagnostics()
check(H.Count('orb-spend')==1 and H.Count('take')==0,'one original spend; diagnostic calls add no actions')
check(v.mode=='durable' and #p.boundaryJournal==2 and p.boundaryJournal[1].event=='receipt' and p.boundaryJournal[2].event=='pre_call','first two provenance entries are stored before host call')
check(v.reason==nil and v.sessionRetained==0,'durable evidence is not mislabeled foreign or session-only')
check(v.receiptJournal[3].event=='host_call' and v.receiptJournal[4].event=='host_true' and v.receiptJournal[5].event=='spend_submitted'
 and v.unsaved and v.durableRetained==2,'actual host call/return is distinct from adapter disposition and not falsely called persisted')
M.Pump();v=M.BoundaryDiagnostics()
check(v.snapshot.chargesBefore==10 and v.snapshot.chargesNow==10 and v.snapshot.chargeRelation=='equal' and v.snapshot.ownedRelation=='before','exact initial comparison evidence')
local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1;local writes=0
owner.UpdateStateV1=function(...)writes=writes+1;return raw(...)end
local stable=R.Saved();local retained=v.retained
for i=1,30 do M.Status(false);M.Pump()end
check(writes==0 and M.BoundaryDiagnostics().retained==retained and R.Same(R.Saved(),stable),'stable reads do not write or append repeated evidence')
owner.UpdateStateV1=raw
H.Fire('PLAYER_LEAVING_WORLD');v=M.BoundaryDiagnostics()
check(v.phase=='l' and v.epoch==1 and M.Status().state=='WAIT_WORLD' and M.Status().running and M.Status().pending,'loading holds existing authorization; exposure retained')
check(v.unsaved==false and v.durableRetained==v.retained,'live lifecycle write includes diagnostic boundary')
H.Fire('PLAYER_ENTERING_WORLD');M.Pump()
-- Vary only observed balance after classified entry; no action repeats.
-- A differing balance then pauses; none of these diagnostics settle a spend.
O.charges=9;M.Pump();v=M.BoundaryDiagnostics()
check(v.snapshot.chargeRelation=='one_below' and v.snapshot.offerPresent==false and M.RecoveryView().spendObserved==false,'decrement without offer is evidence only')
O.charges=8;M.Pump();check(M.BoundaryDiagnostics().snapshot.chargeRelation=='lower','lower balance distinct')
O.charges=11;M.Pump();check(M.BoundaryDiagnostics().snapshot.chargeRelation=='higher','higher balance distinct')
local source=O.source;local out=H.Clone(H.granted)
for _,rows in pairs(out)do for i=#rows,1,-1 do if rows[i].spellId==source then table.remove(rows,i)end end end
H.granted=out;H.Notify();A.Poll();M.Pump()
check(M.BoundaryDiagnostics().snapshot.ownedRelation=='source_removed','source removal distinguished from unchanged ownership')
H.granted['Desired A']={{spellId=410002,quality=2}};H.Notify();A.Poll();M.Pump()
check(M.BoundaryDiagnostics().snapshot.ownedRelation=='neither','unlinked ownership change is neither, not settlement')
for i=1,12 do H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD');M.Pump()end
v=M.BoundaryDiagnostics()
check(v.retained==8 and v.dropped>0 and v.receiptJournal[1].event=='receipt' and v.receiptJournal[2].event=='pre_call','cap eight; first two provenance entries survive recent ring eviction')
for _,e in ipairs(v.receiptJournal)do
 local n=0;for k,x in pairs(e)do n=n+1;check(type(x)~='table' and type(x)~='function' and type(x)~='userdata','flat scalar entry')end
 check(n<=10 and e.guid==nil and e.payload==nil and e.name==nil,'bounded privacy schema')
end
local detached=M.BoundaryDiagnostics();detached.receiptJournal[1].event='bad';detached.snapshot.chargesNow=999
check(M.BoundaryDiagnostics().receiptJournal[1].event=='receipt' and M.BoundaryDiagnostics().snapshot.chargesNow~=999,'support view is detached')
M=S.Reload(H);local saved=H.Clone(R.Saved());S.Pass(H,M,A,1);v=M.BoundaryDiagnostics()
check(v.mode=='session_only' and v.reason=='restored_receipt' and v.durableRetained==8,'restored evidence survives; new observations are explicitly session only')
check(R.Same(R.Saved(),saved) and M.ContinueView().reason=='spend_unconfirmed','restored capture changes neither original receipt nor Continue gate')
check(H.Count('orb-spend')==1 and H.Count('take')==0 and M.Status().reserved==1,'no repeat, selection or invented refund')
-- A same-name foreign field, including false, remains untouched.
local H2,M2,A2,O2=R.Class({latch=false,edit=function(row,state)row.boundaryJournal=false;state.boundaryJournal=false end})
S.Pass(H2,M2,A2,1);local v2=M2.BoundaryDiagnostics()
check(R.Saved().boundaryJournal==false and v2.retained==0 and v2.mode=='session_only','foreign false retained without repair')
-- Save failure preserves the original no-send gate, and diagnostics report it.
local H3,M3=S.Fresh();H3.OrbPlan();local restore=R.BreakStore()
local ok=M3.Start(2)
check(not ok and H3.Count('orb-spend')==0 and H3.Count('take')==0,'failed persistence never permits a host call')
restore()
-- EXPECT semantic replacement from accepted base bc5f4959: validates retained history
-- before action admission. Unknown history is an authority refusal, not a
-- diagnostic-budget refusal; diagnostic reads must neither repair nor lift it.
for _,archive in ipairs({false,{{v=2,id='future',cd='future',receipt={}}}})do
 local HF,MF,AF,OF=S.Fresh();HF.OrbPlan()
 assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(r)r.orbRecoveryArchive=HF.Clone(archive) end))
 local approved,why=MF.Start(2);assert(not approved and why)
 local status=MF.Status(false);local diag=MF.BoundaryDiagnostics()
 check(HF.Count('orb-spend')==0 and HF.Count('take')==0 and R.Saved()==nil
  and status.state=='IDLE' and not status.running and status.reserved==0
  and status.startReason=='Retained Orb history cannot be verified. No new Orb action was sent.',
  'unknown history refuses before receipt or host admission')
 check(diag.mode=='unavailable' and diag.reason=='no_receipt' and not diag.observed,
  'history refusal does not claim diagnostic capture or budget exhaustion')
 local _,actual=R.Row();check(R.Same(actual.orbRecoveryArchive,archive),'unknown archive not repaired')
 local original=HF.Clone(actual);local state=HF.Clone(Nexus.Store.State())
 local authority=Nexus.MainInternals.StoreAuthorityOwner;local write=authority.UpdateStateV1;local read=AF.Orbs.Read
 local diagnosticWrites,diagnosticReads=0,0
 authority.UpdateStateV1=function(...)diagnosticWrites=diagnosticWrites+1;return write(...)end
 AF.Orbs.Read=function(...)diagnosticReads=diagnosticReads+1;return read(...)end
 for i=1,30 do check(R.Same(MF.BoundaryDiagnostics(),diag),'unknown-history diagnostic view is stable')end
 authority.UpdateStateV1=write;AF.Orbs.Read=read
 check(diagnosticWrites==0 and diagnosticReads==0 and R.Same(actual,original)
  and R.Same(Nexus.Store.State(),state),'GUARD unknown-history diagnostics make no Orb adapter read or Store write and preserve retained state')
 check(R.Same(MF.Status(false),status) and HF.Count('orb-spend')==0 and HF.Count('take')==0,
  'diagnostics preserve the existing authority refusal and send no action')
end
local HB,MB,AB,OB=S.Fresh();HB.OrbPlan()
local read=AB.Orbs.Read
AB.Orbs.Read=function(...)local s,e,why=read(...);if s then s.lockedKey=string.rep('x',4096)end;return s,e,why end
local approved=MB.Start(2)
check(not approved and HB.Count('orb-spend')==0 and not R.Saved(),'EXPECT oversized prospective receipt refuses before pending or host admission')
-- Fill the eight-entry archive capacity with distinct, valid receipts produced by the
-- actual checked Continue and atomic Store path, not invalid placeholder history.
local full,identities={},{}
for i=1,8 do
 local HH,MH,AH,OH=R.Class({latch=false,edit=function(row,state)row.logSerial=i;state.logSerial=i end})
 R.Server(HH);S.Pass(HH,MH,AH,1)
 local before=HH.Clone(R.Saved())
 check(MH.ContinueBegin()==true,'SETUP valid retained receipt admits a strict Continue check')
 for tick=1,80 do if MH.ContinueView().stage=='ready' then break end;HH.Advance(.25)end
 local cv=MH.ContinueView()
 check(cv.stage=='ready' and MH.ContinueConfirm(cv.token)==true,'SETUP real checked Continue archives the exact receipt')
 local entry=R.SavedRow('orbRecoveryArchive')[1]
 check(R.Same(entry.receipt,before),'GUARD real Continue preserves the entire original receipt')
 check(entry.kind=='ACK_UNCONFIRMED' and entry.resolution.confidence=='NONE'
  and not identities[entry.id] and HH.Count('orb-spend')==0 and HH.Count('take')==0,
  'SETUP distinct real unconfirmed archive, with no spend or result confirmation')
 identities[entry.id]=true;full[i]=HH.Clone(entry)
end
local HC,MC,AC,OC=S.Fresh();HC.OrbPlan()
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(r)r.orbRecoveryArchive=HC.Clone(full) end))
local approved=MC.Start(2,false,MC.Status().historyReview)
check(not approved and HC.Count('orb-spend')==0 and not R.Saved() and not MC.BlocksOrdinary(),'EXPECT valid full archive refuses a new unarchivable operation before ownership')
check(R.Same(R.SavedRow('orbRecoveryArchive'),full),'full archive is never evicted to fit diagnostics')
local HE,ME,AE,OE=S.Fresh();HE.OrbPlan();OE.mode='throw';HE.Approve(2,false)
local sawError=false;for _,e in ipairs(ME.BoundaryDiagnostics().receiptJournal)do if e.event=='host_error' then sawError=true end end
check(sawError and R.Saved().ambiguous and not ME.RecoveryView().spendObserved,'actual host error is not a spend/refusal conclusion')
check(HE.Count('orb-spend')==1 and not ME.Status().running and ME.Status().reserved==1,'ambiguous return preserves existing action/exposure semantics')
local HP,MP,AP,OP=S.Fresh();HP.OrbPlan()
AP.Orbs.BoundarySink(function()error('synthetic diagnostic sink failure')end)
HP.Approve(2,false)
check(HP.Count('orb-spend')==1 and MP.Status().state=='WAIT_OFFER','diagnostic callback errors do not reach or alter the host')
-- Genuine one-shot original persistence failure: do not retry-to-admit a host
-- action just because a bare second write would succeed.
local HG,MG,AG,OG=S.Fresh();HG.OrbPlan()
local gw=Nexus.MainInternals.StoreAuthorityOwner;local gr=gw.UpdateStateV1;local originalAttempts,metadataAttempts=0,0
gw.UpdateStateV1=function(fn,...)
 local probe={};fn(probe);local pr=probe.orbRefinement and probe.orbRefinement.pending
 if pr then
  if pr.boundaryJournal~=nil then metadataAttempts=metadataAttempts+1 else originalAttempts=originalAttempts+1 end
  if originalAttempts==1 then return nil end
 end
 return gr(fn,...)
end
HG.Approve(2,false);gw.UpdateStateV1=gr
check(HG.Count('orb-spend')==0 and originalAttempts==1 and metadataAttempts==0,'genuine first mandatory failure is never retried; optional attempt not made')
-- Refusing only our optional metadata leaves original host admission intact.
local HD,MD,AD,OD=S.Fresh();HD.OrbPlan();local dw=Nexus.MainInternals.StoreAuthorityOwner;local dr=dw.UpdateStateV1;local refusals=0
dw.UpdateStateV1=function(fn,...)
 local probe={};fn(probe);local pr=probe.orbRefinement and probe.orbRefinement.pending
 if pr and pr.boundaryJournal~=nil then refusals=refusals+1;return nil end
 return dr(fn,...)
end
HD.Approve(2,false);dw.UpdateStateV1=dr
local dv=MD.BoundaryDiagnostics()
check(HD.Count('orb-spend')==1 and refusals==1 and R.Saved().boundaryJournal==nil,'one metadata refusal does not refuse original verified receipt/spend')
check(dv.mode=='session_only' and dv.reason=='write_refused' and dv.durableRetained==0 and dv.captureFailures==1,'refused metadata is explicitly session-only, not durable')
-- Later refusal may omit ONLY this visit's diagnostic field. Picks and every
-- protected original receipt field remain. It is reported, not hidden.
local HL,ML,AL,OL=S.Fresh();HL.OrbPlan();HL.Approve(2,false);ML.Pause()
local initial=HL.Clone(R.Saved());local lw=Nexus.MainInternals.StoreAuthorityOwner;local lr=lw.UpdateStateV1
lw.UpdateStateV1=function(fn,...)
 local probe={};fn(probe);local pr=probe.orbRefinement and probe.orbRefinement.pending
 if pr and pr.boundaryJournal~=nil then return nil end;return lr(fn,...)
end
HL.Fire('PLAYER_LEAVING_WORLD');lw.UpdateStateV1=lr
local later=HL.Clone(R.Saved());local lv=ML.BoundaryDiagnostics();initial.boundaryJournal=nil
check(R.Same(later,initial) and lv.reason=='write_refused' and lv.priorWrittenOmitted==2,'prior visit-owned journal omission is explicit; protected receipt fields retained')
-- Optional exceptions and a malformed post-write result cannot be called a
-- verified diagnostic commit, even when the original receipt was saved first.
for _,fault in ipairs({'throw','malformed'})do
 local HM,MM,AM,OM=S.Fresh();HM.OrbPlan();local mw=Nexus.MainInternals.StoreAuthorityOwner;local mr=mw.UpdateStateV1
 mw.UpdateStateV1=function(fn,...)
  local probe={};fn(probe);local pr=probe.orbRefinement and probe.orbRefinement.pending
  if pr and pr.boundaryJournal~=nil then
   if fault=='throw' then error('synthetic optional metadata error')end
   local ok=mr(fn,...);local _,row=R.Row();row.orbRefinement.pending.boundaryJournal={{unexpected='kept-unknown'}};return ok
  end
  return mr(fn,...)
 end
 HM.Approve(2,false);mw.UpdateStateV1=mr;local mv=MM.BoundaryDiagnostics()
 check(HM.Count('orb-spend')==1 and R.Saved().spendConfirmed==false and R.Saved().removed~=nil,'optional fault preserves verified original action receipt: '..fault)
 check(mv.mode=='session_only' and mv.durableRetained==0 and not mv.persisted and mv.captureFailures==1,'optional fault does not fabricate durability: '..fault)
end
-- Maximal journal and all three maximal picks fit the unchanged archive limits
-- on the real 79-copy/67-distinct receipt fixture, and survive real Store writes.
local journal={};for i=1,8 do journal[i]={event='select_ambiguous',epoch=65535,phase='w',charge=1000000,
 relation='one_below',owned='source_removed',offer=false,pick=false,host=false}end
local picks={};for i=1,3 do picks[i]={id=2147483647-i,q=255,board=string.rep('1:',19)..'11',m='norec',acc=false,
 op=false,slot=65535,sk=false,rd='noctx',u=false,inb=false,ph='w',ep=65535,at=2000000000,c=999}end
local HA,MA,AA,OA=R.Class({latch=false,edit=function(row,state)
 for _,r in ipairs({row,state})do r.boundaryJournal=H.Clone(journal);r.picks=H.Clone(picks);r.pickSeen=999;r.pickDropped=999 end
end})
R.Server(HA);S.Pass(HA,MA,AA,1);local original=HA.Clone(R.Saved())
check(#original.boundaryJournal==8 and #original.picks==3,'all bounded evidence retained through reload sanitization')
check(MA.BoundaryDiagnostics().reason=='restored_receipt','retained valid journal is not called foreign')
assert(MA.ContinueBegin())
for i=1,80 do if MA.ContinueView().stage=='ready' then break end;HA.Advance(.25)end
check(MA.ContinueView().stage=='ready','maximum evidence remains eligible for original strict check')
local ready=MA.ContinueView().token
MA.BoundaryDiagnostics();MA.Pump();MA.Status(false)
check(MA.ContinueView().token==ready and R.Same(R.Saved(),original),'metadata reads do not invalidate token/content')
check(MA.ContinueConfirm(ready)==true,'maximum journal/picks archive through real Store')
local entry=R.SavedRow('orbRecoveryArchive')[1]
local function measure(v,depth)
 depth=depth or 1;local e,b,d=0,0,depth
 for k,x in pairs(v)do e=e+1;b=b+#tostring(k)
  if type(x)=='table'then local ee,bb,dd=measure(x,depth+1);e=e+ee;b=b+bb;d=math.max(d,dd)
  elseif type(x)=='string'then b=b+#x else b=b+8 end
 end
 return e,b,d
end
local edges,bytes,depth=measure(entry)
check(edges<=1200 and bytes<=6144 and depth<=4,'archive edge/byte/depth limits unchanged: '..edges..'/'..bytes..'/'..depth)
check(R.Same(entry.receipt,original),'exact receipt/journal retained unchanged in archive')
local done=MA.BoundaryDiagnostics()
check(not done.receiptPresent and done.durableRetained==0 and not done.persisted,'last observed facts are not a current saved pending receipt after archive')
print('ARCHIVE maximal-journal-and-picks edges='..edges..' bytes='..bytes..' depth='..depth)
print('PASS orb_boundary_diagnostics checks='..checks..'; bounded local evidence only, no server correlation or settlement change')
