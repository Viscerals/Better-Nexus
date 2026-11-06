-- Desired policy: authenticated admission origin is local bookkeeping, never auth.
local S=dofile('tests/prototype/catalog_admission_policy_support.lua')
local F=S.F
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
-- Fixture preconditions are reported apart from the policy oracles: SETUP
-- names a scenario precondition, GUARD the synchronous comparison window of
-- one refused submission. Neither is counted as policy evidence.
local preconditions=0
local function setup(v,m)assert(v,'SETUP: '..m);preconditions=preconditions+1 end
local function guard(v,m)assert(v,'GUARD: '..m);preconditions=preconditions+1 end
-- Public mutation precondition (see S.Put): a durable baseline that
-- constrains one submission is taken only once public mutation readiness
-- holds (ManualPreparationStatus().ready: no open catalog candidate), so it
-- does not span the publication of earlier admitted catalog work. Public
-- readiness does not show that scheduled maintenance outside an open
-- candidate has finished, and nothing here claims it.
local function Ready()return S.C.ManualPreparationStatus().ready==true end
-- One bounded wait through the shared S.T.Until, never retried. Returns the
-- harness updates it advanced (0 when already ready). A wait that does not
-- reach readiness fails with this call's own SETUP context.
local function AwaitReadiness(context)
 if Ready() then return 0 end
 local reached,updates=pcall(S.T.Until,S.H,Ready)
 setup(reached,'public mutation readiness is reached within one bounded wait '..context..': '..tostring(updates))
 return updates
end
-- The helper's own precondition, established before its durable baseline.
-- With `pending` (a valid batch submitted as an open catalog candidate), the
-- profiler reads during the wait for that candidate and its outcome are
-- checked as SETUP before any baseline or policy expectation.
local function EstablishMutationReadiness(context,pending)
 local readsBefore=pending and pending.reads()
 local updates=AwaitReadiness(context)
 if pending then pending.observed(readsBefore,updates,context) end
end
local function InvalidOriginRefusal(label,pending)
 label=label or ''
 EstablishMutationReadiness((pending and 'for the pending valid batch, before the invalid-origin baseline' or 'before the invalid-origin baseline')..label,pending)
 local before=S.Saved()
 -- Comparison window, opened immediately after the baseline. S.Remote's
 -- S.Put waits for readiness itself only when the catalog is not ready at
 -- this instant. When it is ready (the helper's precondition held), harness
 -- time or a catalog preparation pump before the comparison could come only
 -- from the refused submission, which must be synchronous; otherwise the
 -- strict durable equality reports what that wait published. This fixture
 -- pumps no readiness inside the window.
 local window={now=S.H.now,pumps=S.C.PreparationPumpCount(),ready=Ready()}
 local ok,why=S.Remote(S.Record('invalid-origin'),'Bad@Peer')
 if window.ready then
  guard(S.H.now==window.now,'the refused submission advanced no harness time'..label)
  guard(S.C.PreparationPumpCount()==window.pumps,'the refused submission ran no catalog preparation pump'..label)
 end
 guard(Ready(),'the refused submission left no catalog candidate open'..label)
 check(ok==false and why=='REMOTE_ORIGIN_UNAVAILABLE','invalid actual sender cannot become a quota origin: '..tostring(ok)..' '..tostring(why)..label)
 check(S.Saved()==before,'invalid-origin refusal changes no durable row'..label)
 check(S.Raw('invalid-origin')==nil and S.C.Get('invalid-origin')==nil,
  'invalid actual sender creates no catalog record'..label)
end
local H,C=S.Boot()
check(S.Remote(S.Record('relayed',{syncAdmissionOriginV1='forged@foreign'}),'Relay-Ebonhold'),
 'legitimate synthetic relayed record is admitted')
check(S.Raw('relayed').syncAdmissionOriginV1=='relay@ebonhold',
 'new identity records actual transport origin, never foreign-supplied witness')
local row=C.Get('relayed')
check(row.ownerVerified==false and row.ownerKey==nil,
 'admission witness grants no content ownership')
check(S.Remote(S.Record('relayed',{lastModified=2,syncAdmissionOriginV1='owner@ebonhold'}),'Owner-Ebonhold'),
 'actual owner can perform existing authorized verification upgrade')
check(S.Raw('relayed').syncAdmissionOriginV1=='relay@ebonhold',
 'existing-ID owner upgrade preserves original actual admission origin')
check(C.Get('relayed').ownerVerified==true,'verification still comes from the actual owner')
local function unused()error('CompactEncode unexpectedly requested a validation callback')end
local protocol=Nexus.SyncInternals.Protocol.New({parseVersion=unused,
 ownerKeyMatchesAuthor=unused,isSafeTree=unused})
local payload=protocol.CompactEncode(S.Raw('relayed'))
check(payload.syncAdmissionOriginV1==nil and not Nexus.Codec.JSONEncode(payload):find('syncAdmissionOriginV1',1,true),
 'real full-record wire encoder excludes the local admission witness')
check(S.Put(S.Record('local-new',{author='PrototypeTester-Ebonhold',ownerKey='prototypetester@ebonhold',
 syncAdmissionOriginV1='forged@foreign'}),{source='local'}),'explicit local record is admitted')
check(S.Raw('local-new').syncAdmissionOriginV1==nil,'local payload cannot forge a new admission origin')
check(S.Remote(S.Record('bare-new'),'Bare'),'valid actual bare sender retains legacy unverified admission')
check(S.Raw('bare-new').syncAdmissionOriginV1=='transport-bare:bare'
 and S.C.Get('bare-new').ownerVerified==false,
 'bare quota namespace borrows no realm and grants no ownership')
-- Ordinary invocation: readiness is established before the helper, so this
-- call meets no open catalog work at entry and does not depend on the
-- helper's internal order, which the pending-batch invocation below
-- exercises deterministically.
EstablishMutationReadiness('before the ordinary invalid-origin refusal')
InvalidOriginRefusal()
check(S.Remote(S.Record('foreign-object',{syncAdmissionOriginV1={ownerVerified=true,
 origin='forged@foreign'}}),'Relay-Ebonhold'),'even object-shaped foreign metadata is ignored')
check(S.Raw('foreign-object').syncAdmissionOriginV1=='relay@ebonhold'
 and S.C.Get('foreign-object').ownerVerified==false,
 'foreign metadata shape cannot forge either origin or ownership')
local ownerBefore=S.Raw('relayed').ownerKey
local ok,why=S.Remote(S.Record('relayed',{author='Foreign-Ebonhold',ownerKey='foreign@ebonhold',lastModified=3,
 syncAdmissionOriginV1='relay@ebonhold'}),'Foreign-Ebonhold')
check(ok==false and why=='PROVENANCE_COLLISION','metadata cannot authorize owner collision')
check(S.Raw('relayed').ownerKey==ownerBefore,'ownership refusal preserves original record')
H=F.Reload();S.H=H;S.C=Nexus.BuildCatalog;C=S.C
check(S.Raw('relayed').syncAdmissionOriginV1=='relay@ebonhold','local witness survives literal reload')
check(C.Get('relayed').ownerVerified==true,'reload does not infer auth from origin witness')
S.Boot(1)
check(S.Raw('seed-1').syncAdmissionOriginV1==nil,'unattributed historical row starts without a guessed origin')
check(S.Remote(S.Record('seed-1',{lastModified=3}),'Owner-Ebonhold'),'safe historical update remains allowed')
check(S.Raw('seed-1').syncAdmissionOriginV1==nil,'historical update does not invent original admission sender')
S.Boot()
check(S.Remote(S.Record('native-spelling',{author='Native-RogueLite(Live)',
 ownerKey='native@roguelite(live)'}),'Native-Rogue-Lite(Live)'),
 'qualified actual native sender may admit content independently of the claimed owner spelling')
check(S.Raw('native-spelling').syncAdmissionOriginV1=='native@rogue-lite(live)',
 'quota origin keeps actual native realm context instead of a claimed normalized alias')
check(S.C.Get('native-spelling').ownerVerified==false,'origin witness cannot authenticate a different realm spelling')
-- Synthetic profiler-cost case. Test cost: one more real-TOC Boot, three
-- synthetic admissions and bounded readiness waits. After this final Boot
-- the client profiler is replaced, in this fixture only, by a deterministic
-- fake anchored to the real reading at installation, or to an explicit
-- 0 ms baseline in the supported no-clock mode (the harness then leaves no
-- profiler). A reading is that anchor plus the harness milliseconds since
-- installation plus 0.25 ms per read so far, so readings rise monotonically
-- without an epoch jump. Three things are kept apart: structurally, the
-- valid batch is an open catalog candidate when the helper is entered
-- (SETUP); observably, the fake is read during the helper's own bounded
-- readiness wait for it (SETUP: a read in that interval, nothing more);
-- which runtime code read it, how much catalog work each update ran and
-- any native frame-time effect are unknown here. The helper must wait for
-- that batch before its own durable baseline: a baseline taken first would
-- span the batch's publication and fail the strict durable equality. The
-- invalid sender, record, reason and full durable equality are those
-- checked above.
S.Boot()
local costH,realProfiler,profilerReads=S.H,debugprofilestop,0
local anchorMs,anchorNow=type(realProfiler)=='function' and realProfiler() or 0,costH.now
debugprofilestop=function()
 profilerReads=profilerReads+1
 return anchorMs+(costH.now-anchorNow)*1000+profilerReads*.25
end
setup(S.Remote(S.Record('cost-prior-1'),'Relay-Ebonhold'),
 'synthetic profiler cost: prior valid row is admitted')
EstablishMutationReadiness('before the synthetic profiler cost batch')
local batchOk,batchWhy,tickets=S.C.PutBatch({
 {record=S.Record('cost-prior-2'),options={source='remote',sender='Relay-Ebonhold'}},
 {record=S.Record('cost-prior-3'),options={source='remote',sender='Relay-Ebonhold'}}})
setup(batchOk==nil and type(tickets)=='table' and #tickets==2,
 'synthetic profiler cost: valid batch submitted: '..tostring(batchWhy))
setup(not Ready(),'synthetic profiler cost: submitted valid batch is pending catalog work')
local spanning=S.Saved()
InvalidOriginRefusal(' (synthetic profiler cost)',{
 reads=function()return profilerReads end,
 observed=function(readsBefore,updates,context)
  local reads=profilerReads-readsBefore
  setup(reads>0,'the synthetic profiler is read during the '..tostring(updates)
   ..' harness update(s) of the readiness wait '..context..' (observed '..reads
   ..'; a read in that interval, not attributed to catalog pacing)')
  for i,t in ipairs(tickets)do
   setup(t.state=='committed' and t.committed==true,
    'synthetic profiler cost: prior valid batch member '..i..' is admitted: '..tostring(t.reason))
  end
  setup(S.Raw('cost-prior-2')~=nil and S.Raw('cost-prior-3')~=nil and S.Saved()~=spanning,
   'a baseline taken before the readiness precondition would span prior valid publication')
 end})
debugprofilestop=realProfiler
print('PASS catalog_admission_origin checks='..checks..' setup='..preconditions)
