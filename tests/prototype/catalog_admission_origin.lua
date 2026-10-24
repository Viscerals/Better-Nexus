-- Desired policy: authenticated admission origin is local bookkeeping, never auth.
local S=dofile('tests/prototype/catalog_admission_policy_support.lua')
local F=S.F
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
-- Public mutation precondition (see S.Put): a durable baseline that
-- constrains one submission is taken only once earlier admitted catalog
-- work has settled, so it never spans unrelated valid maintenance. Nothing
-- advances between that baseline and the submission: S.Put re-checks the
-- same readiness and, already ready, submits at once.
local function Ready()return S.C.ManualPreparationStatus().ready==true end
local function EstablishMutationReadiness(label)
 if not Ready() then S.T.Until(S.H,Ready) end
 check(Ready(),'public mutation readiness precedes the durable baseline'..(label or ''))
end
local function InvalidOriginRefusal(label)
 label=label or ''
 EstablishMutationReadiness(label)
 local before=S.Saved()
 local ok,why=S.Remote(S.Record('invalid-origin'),'Bad@Peer')
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
-- synthetic admissions and bounded readiness waits. After a normal Boot the
-- client profiler is replaced, in this fixture only, by a deterministic fake
-- whose every read reports 0.25 ms more than the previous one at the same
-- harness time, so less catalog work fits into each update. Prior valid
-- admissions are still pending when the precondition is established; a
-- baseline taken earlier would span their publication. The invalid sender,
-- record, reason and full durable equality are those checked above.
S.Boot()
local costH,realProfiler,profilerReads=S.H,debugprofilestop,0
debugprofilestop=function()
 profilerReads=profilerReads+1
 return costH.now*1000+profilerReads*.25
end
check(S.Remote(S.Record('cost-prior-1'),'Relay-Ebonhold'),
 'synthetic profiler cost: prior valid row is admitted')
EstablishMutationReadiness(' (synthetic profiler cost, before batch)')
local batchOk,batchWhy,tickets=S.C.PutBatch({
 {record=S.Record('cost-prior-2'),options={source='remote',sender='Relay-Ebonhold'}},
 {record=S.Record('cost-prior-3'),options={source='remote',sender='Relay-Ebonhold'}}})
check(batchOk==nil and type(tickets)=='table','synthetic profiler cost: valid batch submitted: '..tostring(batchWhy))
check(not Ready(),'synthetic profiler cost: submitted valid batch is pending catalog work')
local spanning=S.Saved()
EstablishMutationReadiness(' (synthetic profiler cost)')
for i,t in ipairs(tickets)do
 check(t.state=='committed' and t.committed==true,
  'synthetic profiler cost: prior valid batch member '..i..' is admitted: '..tostring(t.reason))
end
check(S.Raw('cost-prior-2')~=nil and S.Raw('cost-prior-3')~=nil and S.Saved()~=spanning,
 'a baseline taken before the readiness precondition would span prior valid publication')
InvalidOriginRefusal(' (synthetic profiler cost)')
check(profilerReads>0,'synthetic profiler surcharge was read by catalog pacing')
debugprofilestop=realProfiler
print('PASS catalog_admission_origin checks='..checks)
