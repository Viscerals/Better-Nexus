-- Catalog verdict reuse, differential (BN-CATALOG-VERDICT-REUSE-006): the
-- same deterministic operations run twice, once with verdict reuse and once
-- with every row walked (Catalog.DebugSetVerdictReuse(false), the full
-- rebuild). After every step the published root (verdicts, index, counts,
-- vectors, slots), the durable bundle, every public read and every refusal
-- must be identical. Steps cover one-row and eight-row batches, a single
-- Put, duplicate, stale and hostile members, a removal marker and an overlay
-- removal, in-place source edits before the capture and during the walk, an
-- in-place evidence-pool edit, an evidence append, an owner change, a failed
-- publication and an exhausted generation counter. Edits are injected at a
-- mutation phase, not at a frame, so both routes are edited at the same
-- logical point; single-slice pacing (no profile clock) makes the slice
-- boundaries, and so the injection points, deterministic.
-- Real TOC boot, real catalog; synthetic records only.
dofile('tests/prototype/startup_support.lua').SingleSlicePacing()
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local clock=1790000000
local function Clock() time=function() return clock end end
local function Record(id,extra)
 local r={id=id,title='Synthetic '..tostring(id),author='Peer-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
 for k,v in pairs(extra or {})do r[k]=v end
 return r
end

-- Canonical text of a value: sorted keys, recursive, no table identities.
local function Ser(value,depth)
 depth=depth or 0
 local kind=type(value)
 if kind=='string' then return string.format('%q',value) end
 if kind=='number' then
  if value~=value then return 'nan' end
  return string.format('%.17g',value)
 end
 if kind~='table' then return tostring(kind=='boolean' and value or kind) end
 if depth>40 then return '<deep>' end
 local parts={}
 for k,v in pairs(value) do parts[#parts+1]=Ser(k,depth+1)..'='..Ser(v,depth+1) end
 table.sort(parts)
 local mt=getmetatable(value)
 return '{'..table.concat(parts,',')..(mt and ',<mt>' or '')..'}'
end

local SLOT_FIELDS={'key','id','kind','overlay','bundled','tombstone','barrier'}
local PHASES={'batch-prepare','put-prepare','maintenance-prepare','mutation-bundle','mutation-session-tombstones',
 'mutation-session-barriers','mutation-session-writes','mutation-capture','capture','collect','sort','rows',
 'finalize-scan','finalize-prune','index','bundle','witness-capture','witness-verify','publish'}
local RANK={};for i,p in ipairs(PHASES) do RANK[p]=i end

local function Run(reuse,size,plan)
 local db={settingsVersion=5,accountCharacters={},settings={},chars={},communityBuilds={}}
 for i=1,size do db.communityBuilds['b-'..i]=Record('b-'..i,{lastModified=i}) end
 db.communityBuilds['bad-1']={id='bad-1',title=5}
 db.communityBuilds['own-1']=Record('own-1',{author='Peer-Realm',ownerKey='Peer@Realm'})
 local shipped={['ship-1']=Record('ship-1'),['b-2']=Record('b-2',{lastModified=0,title='Shipped b-2'})}
 F.fileHooks={[ [[data\BundledBuilds.lua]] ]=function() Nexus.BundledBuilds.builds=shipped end}
 local H=F.Boot(db,Clock);F.fileHooks=nil
 local C=Nexus.BuildCatalog
 C.DebugSetVerdictReuse(reuse)
 local ST
 for i=1,255 do local n,v=debug.getupvalue(C.DebugStats,i);if not n then break end;if n=='ST' then ST=v end end
 assert(ST,'catalog state')
 local inject
 -- While set, the catalog's own pumps (only) see another player name.
 local ownerWindow=false
 local pump=C.PumpRootAdmission
 C.PumpRootAdmission=function(...)
  local h=ST.candidate
  local around
  if inject and inject.done and inject.restorePhase and not inject.restored and h
   and RANK[h.phase] and RANK[h.phase]>=RANK[inject.restorePhase] then
   inject.restored=true;inject.restore()
  end
  if inject and not inject.done and h and h.mode=='mutation' and RANK[h.phase] and RANK[h.phase]>=RANK[inject.phase] then
   inject.done=true;inject.handle=h;inject.fn(ST,h)
   around=inject.after
  end
  local realUnitName=UnitName
  if ownerWindow then UnitName=function() return 'Otherplayer' end end
  local results={pump(...)}
  UnitName=realUnitName
  if around then around() end
  if inject and inject.done and inject.untilHandleEnds and not inject.restored and ST.candidate~=inject.handle then
   inject.restored=true;inject.untilHandleEnds()
  end
  return unpack(results)
 end
 for _=1,200 do H.Advance(.05,.05) end
 local env={H=H,C=C,ST=ST,Record=Record,serial=0}
 function env.OwnerWindow(open) ownerWindow=open end
 local function Settle(tickets)
  for _=1,20000 do
   local open=false
   for _,t in ipairs(tickets or {}) do if t.state=='pending' then open=true end end
   if not open and C.ManualPreparationStatus().ready then break end
   H.Advance(.05,.05)
  end
 end
 function env.Inject(phase,fn,after,restorePhase,restore,untilHandleEnds)
  inject={phase=phase,fn=fn,after=after,restorePhase=restorePhase,restore=restore,
   untilHandleEnds=untilHandleEnds};env.injection=inject
 end
 function env.Batch(records)
  local requests={}
  for i,r in ipairs(records) do requests[i]={record=r,options={}} end
  local ok,why,tickets=C.PutBatch(requests)
  Settle(tickets)
  local outcome={ok=ok,why=why}
  for i,t in ipairs(tickets or {}) do outcome[i]={state=t.state,committed=t.committed,reason=t.reason,storedAs=t.storedAs} end
  return outcome
 end
 function env.New(n)
  local list={}
  for i=1,n do env.serial=env.serial+1;list[i]=Record('new-'..env.serial,{lastModified=100+env.serial}) end
  return list
 end
 function env.Settle() Settle({}) end
 function env.Readmit()
  C.BeginRootAdmission(NexusDB,Nexus.BundledBuilds)
  for _=1,20000 do
   if ST.rootState=='ROOT_ADMITTED' and C.ManualPreparationStatus().ready then break end
   H.Advance(.05,.05)
  end
  return {state=ST.rootState,count=C.Count()}
 end
 local function Signature(outcome)
  local root=ST.currentServingRoot and ST.currentServingRoot.catalogRoot
  local parts={'outcome='..Ser(outcome)}
  if type(root)=='table' and type(root.rows)=='table' then
   local slots={}
   for key,slot in pairs(root.slots or {}) do
    local copy={};for _,f in ipairs(SLOT_FIELDS) do copy[f]=slot[f] end;slots[key]=copy
   end
   parts[#parts+1]='rows='..Ser(root.rows)
   parts[#parts+1]='index='..Ser(root.index)
   parts[#parts+1]='counts='..Ser(root.counts)
   parts[#parts+1]='vectors='..Ser({root.overlayKeys,root.tombstoneKeys,root.barrierKeys,root.slotCount,root.generation})
   parts[#parts+1]='slots='..Ser(slots)
   parts[#parts+1]='reuse='..Ser({root.reuseBasis,root.reusableKeys and next(root.reusableKeys)~=nil,root.reuseOwnerKey})
  else
   parts[#parts+1]='root=<invalid> '..Ser({ST.rootState,ST.rootReason})
  end
  parts[#parts+1]='bundle='..Ser(NexusDB.authorityBundle)
  parts[#parts+1]='state='..Ser({C.RootState(),C.Count(),C.Status(),C.All(),C.SaturationSummary(),C.LastLimitSummary()})
  local ids={}
  for i=1,size+4 do ids[#ids+1]='b-'..i end
  for i=1,env.serial do ids[#ids+1]='new-'..i end
  for _,id in ipairs({'bad-1','ship-1','hostile-1','hostile-2','dup-1'}) do ids[#ids+1]=id end
  local reads={}
  for _,id in ipairs(ids) do reads[#reads+1]={id,C.Get(id),C.GetSummary(id),C.AuthorityState(id)} end
  parts[#parts+1]='reads='..Ser(reads)
  return table.concat(parts,'\n')
 end
 local out={labels={},sigs={},injected={},steps={}}
 out.labels[1]='boot';out.sigs[1]=Signature({})
 for _,step in ipairs(plan) do
  env.injection=nil;inject=nil
  local outcome=step.run(env)
  out.labels[#out.labels+1]=step.label
  out.sigs[#out.sigs+1]=Signature(outcome)
  out.injected[step.label]=env.injection and env.injection.done or nil
  local d=C.DebugStats()
  local before=out.last or {reuses=0,mism=0}
  out.steps[step.label]={outcome=outcome,reuses=(d.verdictReuses or 0)-before.reuses,
   mism=(d.reuseCompareMismatches or 0)-before.mism,admitted=ST.rootState=='ROOT_ADMITTED'}
  out.last={reuses=d.verdictReuses or 0,mism=d.reuseCompareMismatches or 0}
 end
 out.stats=C.DebugStats()
 return out
end

local function Compare(tag,size,plan)
 local on=Run(true,size,plan)
 local off=Run(false,size,plan)
 for i,label in ipairs(on.labels) do
  local a,b=on.sigs[i],off.sigs[i]
  if a~=b then
   local la,lb={},{}
   for line in a:gmatch('[^\n]+') do la[#la+1]=line end
   for line in b:gmatch('[^\n]+') do lb[#lb+1]=line end
   local detail=''
   for j=1,math.max(#la,#lb) do
    if la[j]~=lb[j] then
     local x,y=la[j] or '',lb[j] or ''
     local k=1;while k<=#x and x:sub(k,k)==y:sub(k,k) do k=k+1 end
     detail=(x:sub(1,(x:find('=') or 1)))..' ... reuse: '..x:sub(math.max(1,k-80),k+120)..' || full: '..y:sub(math.max(1,k-80),k+120)
     break
    end
   end
   error(tag..' step '..label..': reuse and full rebuild differ: '..detail)
  end
  checks=checks+1
 end
 for label,done in pairs(on.injected) do check(done==true and off.injected[label]==true,tag..' '..label..': the edit was injected in both routes') end
 check((off.stats.verdictReuses or 0)==0,tag..': the full rebuild reuses nothing')
 return on,off
end

local function Batch(label,count) return {label=label,run=function(e) return e.Batch(e.New(count)) end} end

-- 1. The main sequence.
local plan={
 Batch('one-row first after admission',1),
 Batch('one-row',1),
 Batch('eight-row',8),
 {label='duplicate, stale, hostile and valid members',run=function(e)
  local hostile2=Record('hostile-2');hostile2.echoes=setmetatable({{spellId=200001,quality=1,stacks=1}},{})
  return e.Batch({e.Record('dup-1',{lastModified=300}),e.Record('dup-1',{lastModified=301}),
   e.Record('b-5',{lastModified=0,title='Stale b-5'}),{id='hostile-1',title=5},hostile2,
   e.Record('b-6',{lastModified=400,title='Updated b-6'})})
 end},
 {label='single Put',run=function(e)
  local ok,why,ticket=e.C.Put(e.Record('b-7',{lastModified=900,title='Single put'}),{})
  e.Settle();return {ok=ok,why=why}
 end},
 Batch('one-row after single Put',1),
 {label='removal marker',run=function(e)
  local ok,why=e.C.SetTombstone('own-1',{stamp=5,author='Peer-Realm'},{source='remote',sender='Peer-Realm'})
  e.Settle();return {ok=ok,why=why}
 end},
 Batch('one-row after removal marker',1),
 Batch('one-row again',1),
 {label='overlay removal',run=function(e)
  local ok,why=e.C.RemoveOverlay('b-10');e.Settle();return {ok=ok,why=why}
 end},
 Batch('one-row after overlay removal',1),
 Batch('one-row reuse again',1),
 {label='in-place edit before the capture',run=function(e)
  e.Inject('mutation-capture',function() NexusDB.authorityBundle.communityBuilds['b-12'].title='Edited before capture' end)
  return e.Batch(e.New(1))
 end},
 {label='in-place key addition before the capture',run=function(e)
  e.Inject('mutation-capture',function() NexusDB.authorityBundle.communityBuilds['b-15'].probeExtra='added' end)
  return e.Batch(e.New(1))
 end},
 Batch('one-row after key addition',1),
 {label='in-place edit during the walk',run=function(e)
  e.Inject('rows',function() NexusDB.authorityBundle.communityBuilds['b-13'].title='Edited during walk' end)
  local outcome=e.Batch(e.New(1));e.Settle();return outcome
 end},
 {label='re-admission after drift',run=function(e) return e.Readmit() end},
 Batch('one-row after drift',1),
 Batch('one-row reuse after drift',1),
 {label='in-place evidence-pool edit',run=function(e)
  local store=Nexus.LoadoutEvidence.DurableStore()
  local key=NexusDB.authorityBundle.communityBuilds['b-14'].evidenceKey
  local entry=store and store.entries and key and store.entries[key]
  assert(type(entry)=='table','pool entry for b-14')
  local row=entry[1] or select(2,next(entry))
  row.stacks=(row.stacks or 1)+1
  return e.Batch(e.New(1))
 end},
 Batch('one-row after pool edit',1),
 {label='evidence append (revision change)',run=function(e)
  local key=Nexus.LoadoutEvidence.Intern({{spellId=200003,quality=1,stacks=1}})
  local outcome=e.Batch(e.New(1));e.Settle()
  outcome.interned=key~=nil
  return outcome
 end},
 {label='re-admission after evidence append',run=function(e) return e.Readmit() end},
 Batch('one-row after evidence append',1),
 Batch('one-row reuse after evidence append',1),
 {label='owner change during the walk',run=function(e)
  -- The catalog's pumps see another owner from the capture until the
  -- index phase (the whole row walk); nothing else does.
  e.Inject('mutation-capture',function() e.OwnerWindow(true) end,
   nil,'index',function() e.OwnerWindow(false) end)
  local outcome=e.Batch(e.New(1))
  e.OwnerWindow(false)
  return outcome
 end},
 Batch('one-row after owner change',1),
 Batch('one-row reuse after owner change',1),
 {label='failed publication',run=function(e)
  local evidence=Nexus.LoadoutEvidence
  local real=evidence.AuthorityTokenV1
  -- Only the protected publication captures a token with candidate
  -- evidence (CaptureToken from PublishRoot); every other call is real.
  e.Inject('witness-verify',function() evidence.AuthorityTokenV1=function(includeCandidate)
   if includeCandidate==true then error('injected publication failure') end
   return real(includeCandidate) end end,
   nil,nil,nil,function() evidence.AuthorityTokenV1=real end)
  local outcome=e.Batch(e.New(1))
  evidence.AuthorityTokenV1=real
  e.Settle();return outcome
 end},
 {label='re-admission after failed publication',run=function(e) return e.Readmit() end},
 Batch('one-row after failed publication',1),
 Batch('one-row reuse after failed publication',1),
 {label='exhausted generation counter',run=function(e)
  e.ST.servingGeneration=9007199254740991
  local outcome=e.Batch(e.New(1));e.Settle();return outcome
 end},
}
local on=Compare('size 40',40,plan)
-- Every step did what it claims (the reuse route; the full route is equal).
local S=on.steps
local function Committed(label)
 local o=S[label].outcome
 return o and (o.ok==true or (o[1] and o[1].committed==true))
end
for _,label in ipairs({'one-row first after admission','one-row','eight-row','one-row after single Put',
 'one-row after removal marker','one-row again','one-row after overlay removal','one-row reuse again',
 'in-place edit before the capture','in-place key addition before the capture','one-row after key addition','one-row after drift','one-row reuse after drift','in-place evidence-pool edit',
 'one-row after pool edit','one-row after evidence append','one-row reuse after evidence append',
 'owner change during the walk','one-row after owner change','one-row reuse after owner change',
 'one-row after failed publication','one-row reuse after failed publication'}) do
 check(Committed(label),label..': committed')
end
for _,label in ipairs({'one-row','eight-row','one-row again','one-row reuse again','one-row reuse after drift',
 'one-row reuse after evidence append','one-row reuse after owner change','one-row reuse after failed publication'}) do
 check(S[label].reuses>0,label..': verdicts were reused ('..S[label].reuses..')')
end
for _,label in ipairs({'one-row first after admission','one-row after overlay removal','one-row after drift',
 'one-row after evidence append','owner change during the walk','one-row after owner change'}) do
 check(S[label].reuses==0,label..': no verdict was reused (no reuse source or another owner): '..S[label].reuses)
end
check(S['in-place edit before the capture'].mism>0,'the row edited before the capture was walked, not reused')
check(S['in-place key addition before the capture'].mism>0,'the row given a new key before the capture was walked, not reused')
check(S['in-place evidence-pool edit'].mism>0,'rows whose pool entry was edited were walked, not reused')
local mixed=S['duplicate, stale, hostile and valid members'].outcome
check(mixed[2] and mixed[2].committed==false and mixed[2].reason=='DUPLICATE_BATCH_MEMBER','the duplicate member is refused')
check(mixed[6] and mixed[6].committed==true,'the valid member of the mixed batch commits')
check(S['removal marker'].outcome.ok==true or S['removal marker'].outcome.why=='ROOT_MUTATION_PENDING','the removal marker is accepted: '..tostring(S['removal marker'].outcome.why))
local drift=S['in-place edit during the walk'].outcome
check(drift[1] and drift[1].committed==false and drift[1].reason=='SOURCE_DRIFT','an edit during the walk refuses the mutation: '..tostring(drift[1] and drift[1].reason))
check(S['re-admission after drift'].admitted and S['re-admission after evidence append'].admitted
 and S['re-admission after failed publication'].admitted,'re-admission succeeds')
local failed=S['failed publication'].outcome
check(failed[1] and failed[1].committed==false and failed[1].reason=='ROOT_PUBLICATION_FAILED','the failed publication refuses: '..tostring(failed[1] and failed[1].reason))
local exhausted=S['exhausted generation counter'].outcome
check(exhausted.ok==false or (exhausted[1] and exhausted[1].committed==false),'the exhausted counter refuses: '..tostring(exhausted.why)..' '..tostring(exhausted[1] and exhausted[1].reason))
-- 2. Other catalog sizes, shorter sequence.
for _,size in ipairs({1,120}) do
 local short={Batch('one-row first',1),Batch('one-row',1),Batch('eight-row',8),Batch('one-row again',1)}
 local r=Compare('size '..size,size,short)
 check((r.stats.verdictReuses or 0)>0,'size '..size..': verdicts were reused: '..tostring(r.stats.verdictReuses))
end
print('PASS catalog verdict reuse differential checks='..checks)
