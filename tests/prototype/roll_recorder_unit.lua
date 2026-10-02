-- The automatic local roll recorder (core/RollRecorder.lua) on its own, with the real
-- DiagnosticLogs ring owner and the real Model. Fixtures only; no game, no network.
-- Covers: defaults, privacy, hard bounds and oldest-first replacement, truncation and
-- incompleteness flags, failure isolation, decision/outcome linkage in place and when late,
-- reload and loading boundaries, Freeze survival, ownership change, no side effects,
-- and measured per-decision work.
Nexus=nil;NexusDB=nil
dofile('core/DiagnosticHistory.lua')
dofile('core/DiagnosticLogs.lua')
dofile('logic/Model.lua')
dofile('core/RollRecorder.lua')
local R,Logs=Nexus.RollRecorder,Nexus.DiagnosticLogs
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local clockNow=100
local function Fresh(config)
 NexusDB={};R.Reset();Logs.Init(NexusDB)
 local c={now=function()return clockNow end,epoch=function()return 1790000000 end}
 for k,v in pairs(config or {})do c[k]=v end
 R.Configure(c)
end
local function Records() return Logs.Snapshot('rollTrace') end
-- Names that must never reach a record.
local SECRETS={'SecretCharacter','SecretRealm','SecretWishlist','SecretEchoName','SecretChatLine'}
UnitName=function()return 'SecretCharacter' end
GetRealmName=function()return 'SecretRealm' end
UnitClass=function()return 'Mage','MAGE' end
local calls=0
Nexus.GameAdapter={CatalogStatus=function()calls=calls+1;return {publishedHash='0123abcd'} end}
Nexus.RuntimeBuildLabel=function()return 'test.0000-unit' end

local function Catalog(rows)
 local c={rows={},playerMask=1,levers={}}
 for id,row in pairs(rows or {})do c.rows[id]=row end
 return c
end
local function Row(o) o=o or {};return {classMask=o.class or 1,minLevel=o.level or 1,requiredSpell=o.lever or 0,maxStack=o.cap or 5} end
local function Ctx(o)
 o=o or {}
 local requested,rows={}, {}
 for i=1,(o.targets or 2)do requested[1000+i]=1+(i%2);rows[1000+i]=Row()end
 rows[2001]=Row();rows[2002]=Row()
 local cards=o.cards or {{spellId=1001,quality=1,name='SecretEchoName'},{spellId=2001,quality=0},{spellId=1002,quality=2}}
 return {
  state={allowBanish=true,allowReroll=true,allowFreeze=true},
  action=o.action or {type='take',index=1,spellId=1001,reasonCode='SELECT_OUTSTANDING_WISHLIST',
   policyId='adaptive-0-settle-live1',policyProfile='group-protected-neutral-1',policyRequested='adaptive'},
  board={cards=cards,signature='sig'..(o.sig or 1)},
  owned=o.owned or {synced=true,bySpell={[1001]=1}},locked=o.locked or {synced=true,bySpell={[1002]=1}},
  plan={requestedCounts=requested,lockedRequestedCounts={[1002]=1},explicitRoles=true,name='SecretWishlist'},
  catalog=o.catalog or Catalog(rows),level=o.level or 20,horizon=o.horizon or 12,
  charges=o.charges or {banish=3,reroll=2,freeze=1,trustworthy=true},disabledLevers={},activeSlot=2,catalogRevision=7}
end
local function Flat(record)
 local bytes=0
 for k,v in pairs(record)do
  check(type(k)=='string','record keys are strings')
  check(type(v)~='table' and type(v)~='function','records hold only scalars: '..k)
  if type(v)=='string' then bytes=bytes+#v end
 end
 return bytes
end

-- 1. Defaults: recording is on without any setting; an exact false setting turns it off.
Fresh()
local id=R.Decision(Ctx())
check(type(id)=='string' and #Records()==1,'recording is on by default')
Fresh({enabled=function()return nil end})
check(R.Decision(Ctx())~=nil,'a missing setting does not switch recording off')
Fresh({enabled=function()return false end})
check(R.Decision(Ctx())==nil and #Records()==0 and R.Status().enabled==false and R.Status().skipped==1,'only an exact false setting disables recording')
check(R.Boundary('auto','on')==nil and #Records()==0,'disabled: boundaries are not recorded either')

-- 2. Content and privacy.
Fresh()
local ctx=Ctx()
id=R.Decision(ctx)
local record=Records()[1]
check(record.k=='D' and record.v==1 and record.pol=='adaptive-0-settle-live1' and record.prof=='group-protected-neutral-1' and record.req=='adaptive','policy, profile and requested policy are linked')
check(record.b=='test.0000-unit' and record.cv=='0123abcd' and record.lvl==20 and record.hz==12 and record.cls=='MAGE' and record.slot==2,'build, catalog version, level, class, horizon, slot')
check(record.of=='1001.1.;2001.0.;1002.2.','offers: id, quality, flags')
check(record.ch=='3.2.1.1','charges and trust')
check(record.pr=='take:1:1001:SELECT_OUTSTANDING_WISHLIST','proposal')
check(record.tg=='1001,2,0,1,0,5,f,0;1002,1,1,0,1,5,f,0' and record.tn==2 and record.ex==1,'targets: requested, locked target, ordinary, locked, cap, eligibility, required spell: '..tostring(record.tg))
check(record.run and record.s and record.n==1 and id==record.s..'-'..record.n,'opaque run and decision ids')
Flat(record)
local dump=Nexus.RollRecorder.Export()..'|'..tostring(record.run)
for _,secret in ipairs(SECRETS)do
 check(not dump:find(secret,1,true),'no identifier leaks into the export: '..secret)
 for _,v in pairs(record)do check(not (type(v)=='string' and v:find(secret,1,true)),'no identifier in a record field: '..secret)end
end
-- Flags on offers, and eligibility digits.
Fresh()
R.Decision(Ctx({cards={{spellId=1001},{spellId=2001,quality=0},{spellId=1002,quality=2}}}))
check(Records()[1].of=='1001.-.;2001.0.;1002.2.','an unknown quality is recorded as unknown, not as 0: '..Records()[1].of)
Fresh()
local flagged=Ctx({cards={{spellId=1001,quality=1,isGuaranteed=true},{spellId=2001,quality=0,isFrozen=true,banishEligible=false},
 {spellId=1002,quality=2,isCarried=true,justFrozen=true,freezeEligible=false,selectable=false}}})
R.Decision(flagged)
check(Records()[1].of=='1001.1.G;2001.0.Fb;1002.2.CJfu','offer flags G F C J b f u: '..Records()[1].of)
Fresh()
local catalog=Catalog({[1001]=Row({class=2}),[1002]=Row({level=40}),[1003]=Row({lever=9}),[1004]=Row({cap=1})})
catalog.levers[9]=true
local elig=Ctx({catalog=catalog,owned={synced=true,bySpell={[1004]=1}}})
elig.plan.requestedCounts={[1001]=1,[1002]=1,[1003]=1,[1004]=1,[1005]=1}
elig.disabledLevers={[9]=true}
R.Decision(elig)
local parts={}
for entry in Records()[1].tg:gmatch('[^;]+')do local f={};for x in entry:gmatch('[^,]+')do f[#f+1]=x end;parts[f[1]]=f[7] end
check(parts['1001']=='e' and parts['1002']=='d' and parts['1003']=='b' and parts['1004']=='7' and parts['1005']=='x',
 'eligibility digits: class/level/lever/cap, x for an Echo with no catalog row: '..Records()[1].tg)
check(Records()[1].tg:find('1003,1,0,0,0,5,b,9',1,true),'the required spell is recorded')

-- 3. Hard bounds: count, record size, flat records, oldest replaced first.
Fresh()
local first
for i=1,700 do
 clockNow=clockNow+1
 local big=Ctx({targets=40,sig=i})
 R.Decision(big)
 if i==1 then first=Records()[1].n end
end
local kept=Records()
local stats=Logs.Stats('rollTrace')
check(#kept<=256 and #kept>=200,'at most 256 records are kept: '..#kept)
check(stats.cap==256 and stats.dropped>=700-375 and stats.appended==700,'older records were replaced, and the replacement is counted: dropped='..stats.dropped)
check(kept[1].n>first and kept[#kept].n==700,'the oldest are replaced first; the newest record is present')
local maximum=0
for i,r in ipairs(kept)do
 local bytes=Flat(r);if bytes>maximum then maximum=bytes end
 check(bytes<=2048,'a record stays within 2048 string bytes: '..bytes)
 if i>1 then check(r.n==kept[i-1].n+1,'retained decisions are consecutive: a gap would show a drop') end
end
check(R.Status().retained==#kept and R.Status().cap==256,'status reports retention and cap')

-- Worst case: the longest value in every field, then every later update. The record stays
-- within its byte bound, and the byte budget of the targets (not only their count) is enforced.
Fresh()
local worst=Ctx({targets=40,cards={{spellId=1234567,quality=3,isGuaranteed=true,isFrozen=true,isCarried=true,justFrozen=true,banishEligible=false,freezeEligible=false,selectable=false},
 {spellId=1234568,quality=3,isGuaranteed=true,isFrozen=true,isCarried=true,justFrozen=true,banishEligible=false,freezeEligible=false,selectable=false},
 {spellId=1234569,quality=3,isGuaranteed=true,isFrozen=true,isCarried=true,justFrozen=true,banishEligible=false,freezeEligible=false,selectable=false}}})
worst.plan.requestedCounts={};worst.owned={synced=true,bySpell={}}
for i=1,40 do worst.plan.requestedCounts[1230000+i]=85;worst.owned.bySpell[1230000+i]=85;worst.catalog.rows[1230000+i]=Row({cap=85,lever=1234567}) end
worst.action={type='freeze',index=3,spellId=1234569,reasonCode=string.rep('R',120),policyId='adaptive-0-settle-live1',policyProfile='group-protected-neutral-1',policyRequested='released',fallbackReason='SELECTOR_UNKNOWN'}
worst.charges={banish=100,reroll=100,freeze=100,trustworthy=true}
worst.state={pending=true,ordinaryBoardAllowed=false,allowBanish=false,allowReroll=false,allowFreeze=false,canFreeze=false,searchRefused={banish=true,reroll=true}}
id=R.Decision(worst)
R.Intent(id,'prepared','x',{type='banish',index=1,spellId=9999999,elapsed=0})
for i=1,40 do R.Intent(id,'uncertain',string.rep('x',90),{elapsed=99999.9,mutation=true}) end
local grown={synced=true,bySpell={}};for i=1,40 do grown.bySpell[1230000+i]=0 end
R.After({basis=string.rep('b',90),board=worst.board,owned=grown,charges=worst.charges})
record=Records()[1]
local worstBytes=Flat(record)
check(worstBytes<=2048,'the worst-case record, after every update, stays within 2048 string bytes: '..worstBytes)
check(record.tn==40 and record.inc and record.inc:find('io',1,true),'the worst case is flagged, not silent')
-- The byte budget bounds the targets text even under a smaller limit.
Fresh()
local saved=R.LIMITS.recordBytes;R.LIMITS.recordBytes=1100
R.Decision(Ctx({targets=32}))
record=Records()[1];R.LIMITS.recordBytes=saved
local entries=0;for _ in record.tg:gmatch('[^;]+')do entries=entries+1 end
check(#record.tg<=100 and entries<32 and record.inc and record.inc:find('tg',1,true),'the targets text obeys its byte budget: '..#record.tg..' bytes, '..entries..' of 32 entries')

-- 4. Truncation and incompleteness are marked, never silent.
Fresh()
R.Decision(Ctx({targets=60}))
record=Records()[1]
local count=0;for _ in record.tg:gmatch('[^;]+')do count=count+1 end
check(record.tn==60 and count<=32 and record.inc and record.inc:find('tg',1,true),'60 targets: kept '..count..' of 60 and flagged tg: '..tostring(record.inc))
check(R.Status().truncated==1,'truncation is counted')
Fresh()
R.Decision(Ctx({owned={synced=false,bySpell={}},charges={banish=1,trustworthy=false},catalog={rows={}}}))
record=Records()[1]
check(record.inc=='ow,el,ch' and record.ch=='1.-.-.0','unsynced ownership, unknown eligibility and untrusted charges are flagged: '..tostring(record.inc))
check(record.cp:find('S',1,true),'unsynced ownership appears in the capability text')
Fresh()
R.Decision(Ctx({}))
check(Records()[1].inc==nil,'a complete record carries no incompleteness flag')
-- Pending / refusal / capability text.
Fresh()
local capability=Ctx({});capability.state={pending=true,ordinaryBoardAllowed=false,allowBanish=false,allowReroll=false,allowFreeze=false,
 canFreeze=false,searchRefused={banish=true,reroll=true}}
capability.locked={synced=false,bySpell={}}
R.Decision(capability)
check(Records()[1].cp=='POLbrfzBR','pending, Orb-gate, locked-unsynced, disabled and refused states are recorded: '..tostring(Records()[1].cp))

-- 5. Failure isolation: nothing raises, nothing blocks, a gap is declared.
Fresh()
local append=Logs.Append
Logs.Append=function() error('disk full') end
local ok,result=pcall(R.Decision,Ctx())
check(ok and result==nil,'an append error is contained and answers nil')
check(R.Status().failed==1 and R.Status().dropped==1 and tostring(R.Status().lastError):find('disk full',1,true),'the failure is counted and diagnosable')
Logs.Append=function() return false,'refused' end
check(R.Decision(Ctx())==nil and R.Status().dropped==2,'a refused append is a counted drop')
Logs.Append=append
R.Decision(Ctx())
check(Records()[1].pd==2,'the next saved record says how many were dropped before it: '..tostring(Records()[1].pd))
for _,call in ipairs({function()return R.Decision(nil)end,function()return R.Decision({})end,function()return R.Decision({plan={}})end,
 function()return R.Intent(nil)end,function()return R.Intent('x','y')end,function()return R.After()end,function()return R.After({board=7})end,
 function()return R.Boundary()end,function()return R.Boundary(nil,{})end,function()return R.Status()end,function()return R.Export()end})do
 local good=pcall(call);check(good,'a malformed call never raises')
end

-- 6. Decision, outcome and after-observation are linked in one record while it is the newest.
Fresh()
id=R.Decision(Ctx())
R.Intent(id,'prepared','intent_beat',{elapsed=0})
R.Intent(id,'submitted','adapter_accepted',{elapsed=0.4,mutation=true})
R.Intent(id,'confirmed','board_transition',{elapsed=1.25,mutation=true})
local after=Ctx({sig=2,owned={synced=true,bySpell={[1001]=2,[1002]=0}},charges={banish=3,reroll=2,freeze=0,trustworthy=true},
 cards={{spellId=1001,quality=1},{spellId=2001,quality=0},{spellId=1002,quality=2}}})
R.After({basis='next_board',board=after.board,owned=after.owned,charges=after.charges})
local rows=Records()
check(#rows==1,'outcome and after-observation update the decision record in place: '..#rows)
record=rows[1]
check(record.io=='prepared:intent_beat@0.0,submitted:adapter_accepted@0.4!,confirmed:board_transition@1.2!' or record.io=='prepared:intent_beat@0.0,submitted:adapter_accepted@0.4!,confirmed:board_transition@1.3!','action lifecycle with timing and mutation mark: '..tostring(record.io))
check(record.cb=='next_board:board_transition' and record.af=='1001.1.;2001.0.;1002.2.' and record.ac=='3.2.0.1','confirmation basis, after offers and after charges')
check(record.ao=='1001:+1','ordinary ownership change of a target: '..tostring(record.ao))
-- Late outcome: another record was written first. The fact is kept with a link.
Fresh()
id=R.Decision(Ctx())
R.Boundary('auto','on')
R.Intent(id,'submitted','adapter_accepted',{elapsed=0.4,mutation=true})
rows=Records()
check(#rows==3 and rows[3].k=='O' and rows[3].ref==rows[1].n and rows[3].s==rows[1].s and rows[3].io:find('submitted',1,true),'a late outcome is written as its own record naming the decision')
check(R.Status().late==1,'late outcomes are counted')
-- Action identity per intent (control 011). Every prepared intent carries its own action tag
-- (t take, b banish, f freeze, r reroll; index.spell); the SUBMITTED action is stored as `sa` and is
-- the one the after-observation is judged against, never the board's first proposal.
local function Freeze(a) return Ctx({action={type='freeze',index=1,spellId=1001,reasonCode='PAIR_FREEZE_SECOND_NEEDED',policyId='adaptive-0-settle-live1'}}) end
local FROZEN_AFTER={cards={{spellId=1001,quality=1,isFrozen=true},{spellId=2002,quality=0},{spellId=2001,quality=0}}}
local PLAIN_AFTER={cards={{spellId=1001,quality=1},{spellId=2002,quality=0},{spellId=2001,quality=0}}}
-- Proposal A -> prepared B -> superseded -> prepared A -> submitted A, on one unchanged board.
Fresh()
id=R.Decision(Freeze())
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='take',index=2,spellId=2001})
R.Intent(id,'superseded','decision_changed',{elapsed=.1,type='take',index=2,spellId=2001})
R.Intent(id,'prepared','intent_beat',{elapsed=.2,type='freeze',index=1,spellId=1001})
R.Intent(id,'submitted','adapter_accepted',{elapsed=.6,mutation=true,type='freeze',index=1,spellId=1001})
record=Records()[1]
check(record.pa==nil,'there is no initial-proposal-only field any more')
check(record.sa=='f1.1001','the submitted action is A, not the earlier prepared B: '..tostring(record.sa))
check(record.io=='prepared:intent_beat@0.0=t2.2001,superseded:decision_changed@0.1,prepared:intent_beat@0.2=f1.1001,submitted:adapter_accepted@0.6!',
 'the lifecycle names the action of every prepared intent: '..tostring(record.io))
R.After({basis='next_board',board=FROZEN_AFTER})
check(Records()[1].fz=='set:kept' and Records()[1].inc==nil,'B->A: the Freeze outcome follows the submitted Freeze of 1001: '..tostring(Records()[1].fz))
-- Proposal A (Freeze 1001), but only a Take of 2001 was prepared and submitted.
Fresh()
id=R.Decision(Freeze())
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='take',index=3,spellId=2001})
R.Intent(id,'submitted','adapter_accepted',{elapsed=.5,mutation=true,type='take',index=3,spellId=2001})
R.After({basis='next_board',board=FROZEN_AFTER})
record=Records()[1]
check(record.sa=='t3.2001' and record.fz==nil,'a submitted Take is not judged as the proposed Freeze, even if 1001 happens to be held: '..tostring(record.sa)..' '..tostring(record.fz))
-- Proposal Take, submitted Freeze of another spell: the outcome follows that spell.
Fresh()
id=R.Decision(Ctx())
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='freeze',index=3,spellId=1002})
R.Intent(id,'submitted','adapter_accepted',{elapsed=.5,mutation=true,type='freeze',index=3,spellId=1002})
R.After({basis='next_board',board={cards={{spellId=1002,quality=2,isCarried=true},{spellId=2002,quality=0},{spellId=2001,quality=0}}}})
check(Records()[1].sa=='f3.1002' and Records()[1].fz=='set:kept','a submitted Freeze of a spell other than the proposal is judged on its own spell')
Fresh()
id=R.Decision(Ctx())
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='freeze',index=3,spellId=1002})
R.Intent(id,'submitted','adapter_accepted',{elapsed=.5,mutation=true,type='freeze',index=3,spellId=1002})
R.After({basis='next_board',board={cards={{spellId=1001,quality=1,isFrozen=true},{spellId=2002,quality=0},{spellId=2001,quality=0}}}})
check(Records()[1].fz=='set:gone','the proposal spell being held does not hide that the submitted Freeze did not survive')
-- Several superseded and refused intents; the refused one is not a submission.
Fresh()
id=R.Decision(Freeze())
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='take',index=2,spellId=2001})
R.Intent(id,'superseded','decision_changed',{elapsed=.1,type='take',index=2,spellId=2001})
R.Intent(id,'prepared','intent_beat',{elapsed=.2,type='banish',index=2,spellId=2001})
R.Intent(id,'rejected','adapter_refused',{elapsed=.5,mutation=true,type='banish',index=2,spellId=2001})
R.Intent(id,'prepared','intent_beat',{elapsed=.6,type='freeze',index=1,spellId=1001})
R.Intent(id,'submitted','adapter_accepted',{elapsed=1,mutation=true,type='freeze',index=1,spellId=1001})
record=Records()[1]
check(record.sa=='f1.1001' and record.inc==nil,'a refused intent is not a submission; the submitted action is the last accepted one: '..tostring(record.sa)..' '..tostring(record.inc))
check(record.io:find('prepared:intent_beat@0.2=b2.2001,rejected:adapter_refused@0.5!',1,true),'the refused Banish is named: '..record.io)
-- Nothing submitted: the proposal is not an outcome.
Fresh()
id=R.Decision(Freeze())
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='freeze',index=1,spellId=1001})
R.Intent(id,'superseded','board_changed_before_submit',{elapsed=.2,type='freeze',index=1,spellId=1001})
R.After({basis='next_board',board=FROZEN_AFTER})
check(Records()[1].sa==nil and Records()[1].fz==nil,'no submission: no Freeze outcome is claimed for the proposal')
-- Two accepted submissions on one board, or a submission without identity, are marked incomplete.
Fresh()
id=R.Decision(Freeze())
R.Intent(id,'submitted','adapter_accepted',{elapsed=.5,mutation=true,type='freeze',index=1,spellId=1001})
R.Intent(id,'submitted','adapter_accepted',{elapsed=.9,mutation=true,type='take',index=2,spellId=2001})
R.After({basis='next_board',board=FROZEN_AFTER})
record=Records()[1]
check(record.inc and record.inc:find('am',1,true) and record.fz==nil,'two submissions: the outcome is ambiguous, marked am and not annotated: '..tostring(record.inc)..' '..tostring(record.fz))
Fresh()
id=R.Decision(Freeze())
R.Intent(id,'submitted','adapter_accepted',{elapsed=.5,mutation=true})
R.After({basis='next_board',board=FROZEN_AFTER})
record=Records()[1]
check(record.sa==nil and record.inc and record.inc:find('am',1,true) and record.fz==nil,'a submission with no action identity is ambiguous: '..tostring(record.inc))
-- A late outcome (another record was written first) carries its own tag and sa.
Fresh()
id=R.Decision(Freeze())
R.Boundary('auto','on')
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='take',index=2,spellId=2001})
R.Intent(id,'submitted','adapter_accepted',{elapsed=.5,mutation=true,type='take',index=2,spellId=2001})
rows=Records()
check(rows[3].k=='O' and rows[3].io=='prepared:intent_beat@0.0=t2.2001' and rows[4].sa=='t2.2001' and rows[4].ref==rows[1].n,'late records carry the action tag and the submitted action: '..tostring(rows[3].io)..' '..tostring(rows[4] and rows[4].sa))
-- Reload: the submitted action is already in the saved record; a later outcome for it is linked, not guessed.
Fresh()
id=R.Decision(Freeze())
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='freeze',index=1,spellId=1001})
R.Intent(id,'submitted','adapter_accepted',{elapsed=.5,mutation=true,type='freeze',index=1,spellId=1001})
R.Reset();R.Configure({now=function()return 900 end,epoch=function()return 1790000999 end})
R.Boundary('session','')
R.Intent(id,'confirmed','board_transition',{elapsed=2,mutation=true,type='freeze',index=1,spellId=1001})
rows=Records()
check(rows[1].sa=='f1.1001' and rows[#rows].k=='O' and rows[#rows].ref==rows[1].n and rows[#rows].io:find('confirmed',1,true),'after a reload the saved decision keeps its submitted action and the late outcome names the decision')
-- Truncation: a very long sequence cuts the lifecycle text, flags it, and still keeps the submitted action.
Fresh()
id=R.Decision(Freeze())
for n=1,30 do
 R.Intent(id,'prepared','intent_beat',{elapsed=n/10,type='take',index=2,spellId=2001})
 R.Intent(id,'superseded','decision_changed',{elapsed=n/10,type='take',index=2,spellId=2001})
end
R.Intent(id,'prepared','intent_beat',{elapsed=9,type='freeze',index=1,spellId=1001})
R.Intent(id,'submitted','adapter_accepted',{elapsed=9.5,mutation=true,type='freeze',index=1,spellId=1001})
record=Records()[1]
check(#record.io<=400 and record.inc:find('io',1,true) and record.sa=='f1.1001','a truncated lifecycle is flagged and the submitted action is still recorded: '..#record.io)
R.After({basis='next_board',board=FROZEN_AFTER})
check(Records()[1].fz=='set:kept' and Flat(Records()[1])<=2048,'the outcome still follows the submitted action and the record stays bounded')
-- Eviction: a late record keeps its own identity when the decision was replaced.
Fresh()
id=R.Decision(Freeze())
for n=1,300 do clockNow=clockNow+1;R.Decision(Ctx({sig=n+10})) end
R.Intent(id,'submitted','adapter_accepted',{elapsed=.5,mutation=true,type='freeze',index=1,spellId=1001})
rows=Records()
check(#rows<=256 and rows[#rows].k=='O' and rows[#rows].sa=='f1.1001' and rows[#rows].ref==tonumber(id:match('%-(%d+)$')),'an outcome for an evicted decision is still a self-describing record')

-- An outcome too long for its field is cut and flagged.
Fresh()
id=R.Decision(Ctx())
for i=1,40 do R.Intent(id,'uncertain','reason_number_'..i,{elapsed=i}) end
record=Records()[1]
check(#record.io<=400 and record.inc and record.inc:find('io',1,true),'the lifecycle text is bounded and flagged: '..#record.io)

-- 7. Boundaries: loading and run resets end the open decision with a fate; reload shows a gap.
Fresh()
id=R.Decision(Ctx())
R.Boundary('world_leave','')
rows=Records()
check(rows[1].fate=='interrupted:world_leave' and rows[2].k=='B' and rows[2].kind=='world_leave','a loading screen ends the open decision as interrupted')
R.After({basis='next_board',board=Ctx().board})
check(#Records()==2 and Records()[1].af==nil,'an after-observation of a closed decision is not invented')
R.Decision(Ctx({sig=2}));R.Boundary('run','')
rows=Records()
check(rows[3].fate=='interrupted:run' and rows[4].run~=rows[3].run and rows[4].kind=='run','a run reset ends the open decision and starts a new run id')
R.Decision(Ctx({sig=3}))
check(Records()[5].run==rows[4].run,'later decisions carry the new run id')
local before=Records()[5]
R.Reset();R.Configure({now=function()return 500 end,epoch=function()return 1790009999 end})
R.Boundary('session','')
rows=Records()
check(rows[#rows].kind=='session' and rows[#rows].s~=before.s and before.cb==nil and before.fate==nil,'a reload starts a new session tag after a decision that has no outcome')
R.Boundary('policy','adaptive>released')
check(Records()[#Records()].kind=='policy' and Records()[#Records()].d=='adaptive>released','a policy switch is a timeline boundary')

-- 8. Freeze survival and held offers.
Fresh()
local freezeCtx=Ctx({action={type='freeze',index=1,spellId=1001,reasonCode='PAIR_FREEZE_SECOND_NEEDED',policyId='adaptive-0-settle-live1'}})
id=R.Decision(freezeCtx)
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='freeze',index=1,spellId=1001});R.Intent(id,'submitted','adapter_accepted',{elapsed=.4,mutation=true,type='freeze',index=1,spellId=1001})
R.After({basis='next_board',board={cards={{spellId=1001,quality=1,isFrozen=true},{spellId=2002,quality=0},{spellId=2001,quality=0}}}})
check(Records()[1].fz=='set:kept','a Freeze that survives is recorded')
Fresh()
id=R.Decision(freezeCtx)
R.Intent(id,'prepared','intent_beat',{elapsed=0,type='freeze',index=1,spellId=1001});R.Intent(id,'submitted','adapter_accepted',{elapsed=.4,mutation=true,type='freeze',index=1,spellId=1001})
R.After({basis='next_board',board={cards={{spellId=1001,quality=1},{spellId=2002,quality=0},{spellId=2001,quality=0}}}})
check(Records()[1].fz=='set:gone','a Freeze that did not survive is recorded as gone')
Fresh()
R.Decision(Ctx({cards={{spellId=1001,quality=1,isFrozen=true},{spellId=2001,quality=0},{spellId=1002,quality=2}}}))
R.After({basis='next_board',board={cards={{spellId=1001,quality=1,isCarried=true},{spellId=2002,quality=0},{spellId=2001,quality=0}}}})
check(Records()[1].fz=='held:kept','a held offer that survives a non-Freeze action is recorded')
Fresh()
R.Decision(Ctx({cards={{spellId=1001,quality=1,isFrozen=true},{spellId=2001,quality=0},{spellId=1002,quality=2}}}))
R.After({basis='board_cleared'})
check(Records()[1].cb=='board_cleared:no_intent' and Records()[1].af==nil,'no board after: no offers are invented; no intent is stated')

-- 9. No side effects: the inputs are untouched, no game call is made, no table is kept.
Fresh()
local function Snapshot(v,seen)
 if type(v)~='table' then return tostring(v) end
 seen=seen or {};if seen[v] then return '<cycle>' end;seen[v]=true
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={};for _,k in ipairs(keys)do out[#out+1]=tostring(k)..'='..Snapshot(v[k],seen)end
 return '{'..table.concat(out,',')..'}'
end
local pristine=Ctx();local reference=Snapshot(pristine)
calls=0
local guarded=setmetatable({},{__index=function(_,k) error('the recorder called Nexus.GameAdapter.'..tostring(k)) end})
Nexus.GameAdapter={CatalogStatus=function()calls=calls+1;return {publishedHash='0123abcd'} end}
id=R.Decision(pristine)
R.Intent(id,'prepared','x',{})
R.After({basis='next_board',board=pristine.board,owned=pristine.owned,charges=pristine.charges})
check(Snapshot(pristine)==reference,'decision inputs are not modified')
check(calls==1,'the catalog version is read once, then cached per revision: '..calls)
R.Decision(Ctx({sig=2}))
check(calls==1,'no further catalog read for an unchanged catalog revision')
Nexus.GameAdapter=nil
Fresh()
check(R.Decision(Ctx())~=nil and Records()[1].cv=='unknown','a missing adapter is recorded as an unknown catalog version, not a failure')
Nexus.GameAdapter={CatalogStatus=function()calls=calls+1;return {publishedHash='0123abcd'} end}

-- 10. Export: one line per record, one column count, escaped separators, honest header.
Fresh()
R.Decision(Ctx());R.Boundary('auto','on|off\nnow')
local text=R.Export()
local lines={};for line in text:gmatch('[^\n]+')do lines[#lines+1]=line end
check(lines[1]=='NEXUS_ROLL_TRACE_1' and lines[2]:find('retained=2',1,true),'export header')
check(text:find('NOT A DRAW MODEL',1,true) and text:find('Nothing is sent anywhere',1,true),'the export states what it is not and that nothing is sent')
local columns;for _,line in ipairs(lines)do if line:sub(1,2)=='k|' then columns=select(2,line:gsub('|','|')) end end
for i=7,#lines do check(select(2,lines[i]:gsub('|','|'))==columns,'every record line has the same column count: '..i) end
check(text:find('on%%7Coff now',1) ~= nil,'separators and newlines inside a value are escaped')

-- 10b. Reading is passive: an export and a status read create and write nothing.
NexusDB={};R.Reset();R.Configure({now=function()return clockNow end})
local passiveText=R.Export();local passiveStatus=R.Status()
check(rawget(NexusDB,'rollTraceLog')==nil and rawget(NexusDB,'diagnosticMeta')==nil,'export and status of a missing history create no key')
check(passiveText:find('retained=0',1,true) and passiveStatus.retained==0 and passiveStatus.unreadable==nil,'a missing history reads as empty')
check(Logs.Exists('rollTrace')==false and Logs.Exists('nonsense')==false,'Exists is false for a missing or unknown history')
R.Decision(Ctx());check(Logs.Exists('rollTrace')==true,'Exists is true once a record was written')
-- A history that exists but cannot be read without repair is reported, and a read writes nothing.
local function Dump(v) if type(v)~='table' then return tostring(v) end local k={};for key in pairs(v)do k[#k+1]=key end table.sort(k,function(x,y)return tostring(x)<tostring(y) end)
 local out={};for _,key in ipairs(k)do out[#out+1]=tostring(key)..'='..Dump(v[key])end return '{'..table.concat(out,',')..'}' end
for label,mutate in pairs({
 ['no bookkeeping']=function(db)db.rollTraceLog={{k='D',s='x',n=1}};db.diagnosticMeta=nil end,
 ['gapped array']=function(db)db.rollTraceLog={[1]={k='D',s='x',n=1},[3]={k='D',s='x',n=3}} end,
 ['future schema']=function(db)db.diagnosticMeta.histories.rollTrace.storageSchema=99 end,
})do
 NexusDB={};R.Reset();Logs.Init(NexusDB);R.Configure({now=function()return clockNow end});R.Decision(Ctx());R.Decision(Ctx({sig=2}))
 mutate(NexusDB)
 local before=Dump(NexusDB)
 local exported=R.Export();local st=R.Status()
 check(Dump(NexusDB)==before,'a read of '..label..' writes nothing')
 check(exported:find('record not read',1,true)~=nil,'a read of '..label..' says the record was not read: '..exported:sub(1,60))
 check(st.unreadable~=nil,'status of '..label..' names the reason')
end

-- 11. Measured work: bounded per decision, no growth with history length.
Fresh()
local contexts={};for i=1,50 do contexts[i]=Ctx({targets=32,sig=i}) end
collectgarbage();collectgarbage()
local startMemory,startClock=collectgarbage('count'),os.clock()
local N=2000
for i=1,N do
 local c=contexts[i%50+1]
 local d=R.Decision(c)
 R.Intent(d,'submitted','adapter_accepted',{elapsed=0.4,mutation=true})
 R.After({basis='next_board',board=c.board,owned=c.owned,charges=c.charges})
end
local cpu=(os.clock()-startClock)/N*1000
collectgarbage();collectgarbage()
local retainedMemory=collectgarbage('count')-startMemory
print(string.format('MEASURE roll recorder: %.4f ms CPU per decision cycle (record + outcome + after), retained %.1f KiB after %d cycles',cpu,retainedMemory,N))
check(cpu<2,'a full decision cycle costs under 2 ms of CPU: '..cpu)
check(retainedMemory<1500,'retained memory is bounded by the ring, not by the number of decisions: '..retainedMemory..' KiB')
check(#Records()<=256,'ring bound holds after the measured run')
print('PASS roll recorder unit checks='..checks)
