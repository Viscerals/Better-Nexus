-- Readiness collection is passive. OrbRuntime.ReadinessView() and
-- GameAdapter.OwnershipTrustView() return copies of facts that the normal reads
-- already recorded, and preparing a support report reads only those. At aac790c
-- the existing reads have effects (source diagnosis): Owned() can confirm a
-- generation and mark data dirty, OrbAdapter.Read reconciles Echo state and
-- advances its observation serial, OrbRuntime.Status can initialize recovery and
-- rewrite in-memory targets. None of them may run for collection.
-- Contract: TEST_CONTRACT.md of the tests-first review, sections 3-8. Inside a collection window
-- this test counts calls of every PerkService and OrbService member, the listed
-- adapter, Orb adapter, Orb runtime and Store write entries, and GetSpellInfo.
-- It also compares the adapter's own read-only counters and revisions, its dirty
-- flags, the observation serial, a confirmation left pending on purpose, saved
-- data, the recovery view and the run history. Corrupt or failing inputs must
-- give safe unknown values: no text, name, ID or reference.
-- Real TOC boot, adapter, Orb runtime/policy, Orb window and report builder; the
-- fake services of orbs_support.lua. Artificial IDs and names. The one Orb spend
-- in the last scenario is a counted fake call that creates a real receipt to
-- preserve. Every expectation is evaluated and reported; the test fails at the
-- end if any did not hold.
local H=dofile('tests/prototype/orbs_support.lua')
local A,M,O=H.A,H.M,H.O
local failures,checks={},0
local function printable(v)
 local ok,s=pcall(tostring,v)
 return ok and type(s)=='string' and s or '<unprintable '..type(v)..'>'
end
local function expect(ok,label,detail)
 checks=checks+1
 if not ok then
  local line=label..(detail~=nil and (' ['..printable(detail)..']') or '')
  failures[#failures+1]=line;print('FAIL '..line)
 end
 return ok and true or false
end
local function scenario(name,fn)
 local ok,err=pcall(fn)
 if not ok then
  local line=name..': raised '..printable(err)
  failures[#failures+1]=line;print('FAIL '..line)
 end
end

local TRUST='Waiting for current rolled and locked Echo data from the server.'
local PLAN='ZQ plan alpha'
local BASE_GRANTED=H.Clone(H.granted)

-- Documented codes (TEST_CONTRACT.md, section 6).
local function set(list) local s={};for _,v in ipairs(list) do s[v]=true end;return s end
local STAGES=set({'ok','assignment','targets','capability','state','balance_loading','balance_invalid','catalog',
 'trust_owned','trust_locked','trust_both','call','granted_unavailable','granted_shape','granted_verify',
 'locked_unavailable','locked_shape','locked_verify','limits','choice','auto_accept','host','unknown'})
local REJECTIONS=set({'none','absent','not_table','unreadable','invalid_value','conflicting_alias','cycle','depth','over_cap','scalar_leaf'})
local ASSIGNMENTS=set({'ready','unassigned','restoring','loading','unavailable','unknown'})
local ROLES=set({'explicit','untyped','none','unknown'})
local NULL=set({'unknown','unavailable','?'})
local YESNO=set({'yes','no'})
local function oneOf(values) return function(v) return values[v]==true or NULL[v]==true end end
local function count(v) return (v:match('^%d+$')~=nil and #v<=7) or NULL[v]==true end
local VALID={
 observed=oneOf(YESNO),
 age=function(v) return (v:match('^%d+s?$')~=nil and #v<=8) or NULL[v]==true end,
 stage=oneOf(STAGES),
 ['assignment.state']=oneOf(ASSIGNMENTS),['assignment.roles']=oneOf(ROLES),
 progress=oneOf(set({'available','unavailable'})),
 ['owned.synced']=oneOf(YESNO),['owned.confirmed']=oneOf(YESNO),['owned.armed']=oneOf(YESNO),
 ['owned.fresh']=oneOf(YESNO),['owned.ghost']=oneOf(YESNO),
 ['owned.generation']=count,['owned.total']=count,
 ['locked.synced']=oneOf(YESNO),['locked.copies']=count,['locked.rejection']=oneOf(REJECTIONS),
 balance=oneOf(set({'confirmed','loading','unknown','unsupported'})),charges=count,
 ['offer.pending']=oneOf(YESNO),['host.pending']=oneOf(YESNO),
 ['progress.rolled']=count,['progress.permanent']=count,
}
local VIEW_OBSERVATION={'at','age','stage','assignment','roles','progress','rolledMissing','permanentMissing',
 'ownedSynced','ownedConfirmed','ownedArmed','ownedFresh','ownedGhost','ownedGeneration','ownedTotal',
 'lockedSynced','lockedCopies','lockedRejection'}
-- Privacy (block and views): no name, no Echo ID, no reference, no control character.
local NAMES={'Disposable A','Disposable B','Desired A','Desired B','Protected low','Excess high',
 'Unsafe fallback','Synthetic Echo','Orb test','ZQ plan','ZQ build','PrototypeTester','Ebonhold'}
local IDS={}
for id=410001,410008 do IDS[#IDS+1]=id end
for id=200001,200090 do IDS[#IDS+1]=id end
IDS[#IDS+1]=499999
local function readinessLines(text)
 local out={}
 for line in (tostring(text or '')..'\n'):gmatch('([^\n]*)\n') do
  if line:match('^%s*Orb readiness') then out[#out+1]=line end
 end
 return out
end
local function tokens(lines)
 local t,conflicts={},{}
 for _,line in ipairs(lines) do
  for k,v in line:gmatch('([%a][%w_%.]*)=([%w_%.%-%?]*)') do
   if t[k]~=nil and t[k]~=v then conflicts[#conflicts+1]=k end
   t[k]=v
  end
 end
 return t,conflicts
end
local function leaks(lines,markers)
 local text=table.concat(lines,'\n')
 local found={}
 for _,n in ipairs(NAMES) do if text:find(n,1,true) then found[#found+1]='name '..n end end
 for _,id in ipairs(IDS) do if text:find('%f[%d]'..id..'%f[%D]') then found[#found+1]='id '..id end end
 for _,r in ipairs({'table: ','function: ','userdata: ','thread: ','builtin'}) do
  if text:find(r,1,true) then found[#found+1]='reference' end
 end
 for _,m in ipairs(markers or {}) do if text:find(m,1,true) then found[#found+1]='text '..m:sub(1,40) end end
 for _,line in ipairs(lines) do if line:find('%c') then found[#found+1]='control character' end end
 if #lines>12 then found[#found+1]=#lines..' lines' end
 if #text>1200 then found[#found+1]=#text..' bytes' end
 return found
end
local function ageOf(t)
 local n=t.age and t.age:match('^(%d+)s?$')
 return n and tonumber(n) or nil
end
local function isCount(x) return type(x)=='number' and x>=0 and x==math.floor(x) and x<=1000000 end
local function serialize(v,seen)
 local kind=type(v)
 if kind=='string' then return string.format('%q',v) end
 if kind=='number' or kind=='boolean' or kind=='nil' then return tostring(v) end
 if kind~='table' then return '<'..kind..'>' end
 seen=seen or {}
 if seen[v] then return '<cycle>' end
 seen[v]=true
 local keys={}
 for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b)
  local ta,tb=type(a),type(b)
  if ta~=tb then return ta<tb end
  if ta=='number' or ta=='string' then return a<b end
  return tostring(a)<tostring(b)
 end)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=serialize(k,seen)..'='..serialize(v[k],seen) end
 seen[v]=nil
 return '{'..table.concat(out,',')..'}'
end

-- Spies: counted only inside a collection window; behaviour is unchanged.
local SPY={on=false,calls={}}
local function wrap(owner,name,label)
 if type(owner)~='table' or type(owner[name])~='function' then return end
 local fn=owner[name]
 owner[name]=function(...)
  if SPY.on then SPY.calls[label]=(SPY.calls[label] or 0)+1 end
  return fn(...)
 end
end
local function wrapAll(owner,prefix)
 local names={}
 for k,v in pairs(owner) do if type(v)=='function' then names[#names+1]=k end end
 for _,k in ipairs(names) do wrap(owner,k,prefix..k) end
end
wrapAll(ProjectEbonhold.PerkService,'PerkService.')
wrapAll(ProjectEbonhold.OrbService,'OrbService.')
wrap(ProjectEbonhold.PlayerRunService,'GetCurrentData','PlayerRunService.GetCurrentData')
wrap(ProjectEbonholdOptionsService,'GetSetting','Options.GetSetting')
wrap(ProjectEbonholdOptionsService,'SetSetting','Options.SetSetting')
for _,k in ipairs({'Owned','LockedOwned','Catalog','CheckCatalogSource','AssignedWishlist','Wishlist','Slots',
 'EchoActiveSlotGeneration','AutomationSignature','Board','Charges','GrantedCount','DisabledLevers','DiscoverySynced',
 'GetWishlistCandidates','GetLoadoutCandidates','GetFirstRunWishlist','ConsumeDirty','Poll','RequestGranted',
 'RunBoundaryReset','RequestSlots','LockPerk','UnlockPerk','Take','Banish','Reroll','Freeze','Activate','Save',
 'UploadWishlist','ToggleLever','SetSoloPicker','RestoreAutoAccept','ConsumeUserAction','ExternalActionSeen',
 'DumpLockedPerksRaw','OrdinaryBoardAllowed','InFlight','PendingActions','UnconfirmedLatch'}) do
 wrap(A,k,'GameAdapter.'..k)
end
for _,k in ipairs({'Read','Balance','ServiceState','RequestRefresh','CaptureStart','TransportStart','Watch',
 'Unwatch','Acquire','Rebind','Spend','Select','Release'}) do
 wrap(A.Orbs,k,'Orbs.'..k)
end
for _,k in ipairs({'Status','Recheck','Pump','Start','Prepare','Confirm','Resume','Pause','Stop','SetLimit',
 'SetRecycle','SetSource','Exclude','ClearExclusions','SuggestSources','UseAssignedWishlist','TrackBalance',
 'NewRunDraft','EditLimitText','CancelLimitEdit','LimitDraft','PrepareLimitIncrease','ConfirmLimit',
 'ContinueBegin','ContinueCancel','ContinueConfirm','BlocksOrdinary','BlockReason','CompactStatus',
 'SelectWishlist','MoveTarget'}) do
 wrap(M,k,'OrbRuntime.'..k)
end
wrap(Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner,'UpdateStateV1','Store.UpdateStateV1')
do
 local real=GetSpellInfo
 GetSpellInfo=function(...)
  if SPY.on then SPY.calls.GetSpellInfo=(SPY.calls.GetSpellInfo or 0)+1 end
  return real(...)
 end
end
local function window(fn)
 SPY.calls={};SPY.on=true
 local ok,err=pcall(fn)
 SPY.on=false
 return ok,err,SPY.calls
end
local function callList(calls)
 local out={}
 for k,n in pairs(calls) do out[#out+1]=k..' x'..n end
 table.sort(out)
 return table.concat(out,', ')
end
-- The adapter's own read-only counters and revisions.
local COUNTER_NAMES={'reconciliations','scans','cacheHits','failures','lastReason','ownedCalls','lockedCalls',
 'wishlistCalls','slotsCalls','boardCalls','catalogChecks','catalogFastHits','catalogRebuilds','catalogFailures',
 'syncRetries','syncRequestedAt','rev1','rev2','rev3','rev4','rev5','rev6','rev7','rev8','rev9','rev10','rev11'}
local function counters()
 local st=A.EchoReconcileStats();local cs=A.CatalogStatus();local sync=A.OwnedSyncInfo()
 local p=st.projections or {}
 local function calls(name) return p[name] and p[name].calls end
 local c={reconciliations=st.reconciliations,scans=st.scans,cacheHits=st.cacheHits,failures=st.failures,
  lastReason=st.lastReason,ownedCalls=calls('owned'),lockedCalls=calls('locked'),wishlistCalls=calls('wishlist'),
  slotsCalls=calls('slots'),boardCalls=calls('board'),catalogChecks=cs.checks,catalogFastHits=cs.fastHits,
  catalogRebuilds=cs.rebuilds,catalogFailures=cs.failures,syncRetries=sync.retries,syncRequestedAt=sync.requestedAt}
 local rev={A.PresentationRevisions()}
 for i=1,11 do c['rev'..i]=rev[i] end
 return c
end
local function sameCounters(tag,a,b)
 for _,k in ipairs(COUNTER_NAMES) do
  expect(a[k]==b[k],tag..': '..k..' is unchanged by collection',tostring(a[k])..' -> '..tostring(b[k]))
 end
end

local function view()
 local fn=Nexus.OrbRuntime.ReadinessView
 if type(fn)~='function' then return nil,'OrbRuntime.ReadinessView is not available' end
 local ok,v=pcall(fn)
 if not ok then return nil,tostring(v) end
 if type(v)~='table' then return nil,'not a table' end
 return v
end
local function trustView()
 local fn=A.OwnershipTrustView
 if type(fn)~='function' then return nil,'GameAdapter.OwnershipTrustView is not available' end
 local ok,v=pcall(fn)
 if not ok then return nil,tostring(v) end
 if type(v)~='table' then return nil,'not a table' end
 return v
end
local function scalars(tag,v)
 local n=0
 for k,x in pairs(v) do
  n=n+1
  local kind=type(x)
  expect(type(k)=='string' and (kind=='string' or kind=='number' or kind=='boolean'),
   tag..': '..tostring(k)..' is a scalar',kind)
  if kind=='string' then
   expect(#x<=32,tag..': '..tostring(k)..' is a short code',#x)
   local found=leaks({x},{'ZQ_'})
   expect(#found==0,tag..': '..tostring(k)..' carries no name, Echo ID, reference or injected text',table.concat(found,','))
  end
  if kind=='number' then expect(x==x and x>-math.huge and x<math.huge,tag..': '..tostring(k)..' is finite',x) end
 end
 expect(n<=40,tag..': the view is bounded',n)
end
local function validView(tag,v)
 scalars(tag,v)
 expect(type(v.observed)=='boolean',tag..': observed is a boolean',v.observed)
 for _,k in ipairs({'ownedSynced','ownedConfirmed','ownedArmed','ownedFresh','ownedGhost','lockedSynced'}) do
  expect(v[k]==nil or type(v[k])=='boolean',tag..': '..k..' is a boolean or absent',v[k])
 end
 for _,k in ipairs({'age','ownedGeneration','ownedTotal','lockedCopies','rolledMissing','permanentMissing'}) do
  expect(v[k]==nil or isCount(v[k]),tag..': '..k..' is a whole number or absent',v[k])
 end
 expect(v.stage==nil or STAGES[v.stage]==true,tag..': stage is a documented code',v.stage)
 expect(v.lockedRejection==nil or REJECTIONS[v.lockedRejection]==true,tag..': lockedRejection is a documented code',v.lockedRejection)
 expect(v.assignment==nil or ASSIGNMENTS[v.assignment]==true,tag..': assignment is a documented state',v.assignment)
 expect(v.roles==nil or ROLES[v.roles]==true,tag..': roles is a documented mode',v.roles)
 expect(v.progress==nil or v.progress=='available' or v.progress=='unavailable',tag..': progress is documented',v.progress)
end
local function validTrust(tag,t)
 scalars(tag,t)
 for _,k in ipairs({'ownedConfirmed','ownedArmed'}) do expect(type(t[k])=='boolean',tag..': '..k..' is a boolean',t[k]) end
 for _,k in ipairs({'ownedGeneration','ownedRetries'}) do expect(isCount(t[k]),tag..': '..k..' is a whole number',t[k]) end
 for _,k in ipairs({'ownedSynced','ownedFresh','ownedGhost','lockedSynced'}) do
  expect(t[k]==nil or type(t[k])=='boolean',tag..': '..k..' is a boolean or absent',t[k])
 end
 for _,k in ipairs({'ownedTotal','lockedCopies'}) do expect(t[k]==nil or isCount(t[k]),tag..': '..k..' is a whole number or absent',t[k]) end
 expect(t.lockedRejection==nil or REJECTIONS[t.lockedRejection]==true,tag..': lockedRejection is a documented code',t.lockedRejection)
end
-- One normal Orb window read: open, refresh, close.
local function observe()
 Nexus.OrbPanel.Show();local s=NexusOrbPanel.snapshot;NexusOrbPanel:Hide();return s
end
local function observeShown()
 Nexus.OrbPanel.Show()
 local f=NexusOrbPanel;local s=f.snapshot
 local out={plan=f.plan:GetText(),targets=f.targets:GetText(),status=f.status:GetText(),start=f.start:IsEnabled(),
  canStart=s.canStart,startReason=s.startReason,error=s.error}
 NexusOrbPanel:Hide()
 return out
end
local function prepared()
 local report,why=Nexus.SupportReport.Prepare({})
 if type(report)~='table' or type(report.chunks)~='table' then error('the real builder did not prepare a report: '..tostring(why)) end
 return table.concat(report.chunks,'')
end
local function checkBlock(tag,text,markers)
 expect(text:find('Orb action: none unresolved',1,true)~=nil,tag..': the existing Orb action line is kept')
 local lines=readinessLines(text)
 if not expect(#lines>0,tag..': the prepared report carries an Orb readiness block (lines beginning "Orb readiness")') then return nil end
 local t,conflicts=tokens(lines)
 expect(#conflicts==0,tag..': each readiness key has one value',table.concat(conflicts,','))
 local found=leaks(lines,markers)
 expect(#found==0,tag..': the block is bounded and carries no name, Echo ID, reference, raw text or injected payload',table.concat(found,','))
 for key,valid in pairs(VALID) do
  if t[key]~=nil then expect(valid(t[key]),tag..': '..key..' has a documented value',t[key]) end
 end
 return t
end
local function trusted()
 H.holdGrantedResponse=nil;O.known=true;H.locked={};H.playerLevel=40
 H.granted=H.Clone(BASE_GRANTED);A.Owned();A.LockedOwned()
end

-- The reproduced setting: an active populated Saved Build whose Wishlist
-- resolves through its association.
H.perks.serverBuildSlots={[1]={name='ZQ build one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}}}
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
assert(A.SetLoadoutWishlistIdentity(1,PLAN,{{spellId=410002,quality=2,stacks=1}}))

-- P1. Before any Orb window read: both accessors exist and read nothing; the
-- view says "not observed" and invents nothing.
scenario('P1 before the first observation',function()
 expect(type(Nexus.OrbRuntime.ReadinessView)=='function','P1: OrbRuntime.ReadinessView() exists')
 expect(type(A.OwnershipTrustView)=='function','P1: GameAdapter.OwnershipTrustView() exists')
 trusted()
 local db0,c0=serialize(NexusDB),counters()
 local v,t,text
 local ok,err,calls=window(function() v=view();t=trustView();text=prepared() end)
 expect(ok,'P1: the collection window completed',err)
 expect(next(calls)==nil,'P1: collection called no getter, read, request, status, spend, select, lock or write',callList(calls))
 sameCounters('P1',c0,counters())
 expect(serialize(NexusDB)==db0,'P1: saved data is unchanged')
 if expect(v~=nil,'P1: ReadinessView answers before any observation') then
  validView('P1',v)
  expect(v.observed==false,'P1: nothing is observed yet',tostring(v.observed))
  local invented={}
  for _,k in ipairs(VIEW_OBSERVATION) do if v[k]~=nil then invented[#invented+1]=k end end
  expect(#invented==0,'P1: no observation fact is invented',table.concat(invented,','))
 end
 if expect(t~=nil,'P1: OwnershipTrustView answers') then validTrust('P1',t) end
 local tk=checkBlock('P1',text or '',{})
 if tk then expect(tk.observed=='no','P1: the report says nothing was observed',tk.observed) end
end)

-- P8. The normal window read records its observation in memory only.
scenario('P8 the window read records in memory only',function()
 trusted()
 local db0=serialize(NexusDB)
 local ok,err,calls=window(function() observe();observe() end)
 expect(ok,'P8: the window reads completed',err)
 expect((calls['Store.UpdateStateV1'] or 0)==0,'P8: the window reads wrote nothing through the Store owner',callList(calls))
 expect(serialize(NexusDB)==db0,'P8: saved data is unchanged by the window reads')
 local v=view()
 if expect(v~=nil,'P8: ReadinessView answers after a window read') then
  validView('P8',v)
  expect(v.observed==true and v.stage=='ok' and v.progress=='available','P8: the successful read is recorded',
   tostring(v.stage)..'/'..tostring(v.progress))
  expect(v.assignment=='ready' and v.roles=='untyped','P8: with its assignment state and role mode',
   tostring(v.assignment)..'/'..tostring(v.roles))
  expect(type(v.at)=='number' and v.age==0,'P8: a new observation has age 0',v.age)
  expect(v.ownedSynced==true and v.lockedSynced==true and v.lockedRejection=='none','P8: with the trust facts of that read')
 end
end)

-- P7. Each view is a new table; changing it changes nothing recorded.
scenario('P7 views are copies',function()
 local v=view()
 if expect(v~=nil,'P7: ReadinessView answers') then
  v.stage='ZQ_MUTATED';v.observed=false;v.ownedSynced='ZQ_MUTATED'
  local w=view()
  expect(w~=nil and not rawequal(v,w),'P7: each call returns a new table')
  if w then expect(w.stage~='ZQ_MUTATED' and w.observed==true and w.ownedSynced~='ZQ_MUTATED','P7: the recorded observation is unchanged') end
 end
 local t=trustView()
 if expect(t~=nil,'P7: OwnershipTrustView answers') then
  t.ownedGeneration=-99;t.lockedRejection='ZQ_MUTATED'
  local u=trustView()
  expect(u~=nil and u.ownedGeneration~=-99 and u.lockedRejection~='ZQ_MUTATED','P7: the adapter facts are unchanged')
 end
end)

-- P2a. No observation serial moves during collection: a read after the window
-- advances it exactly once (a read during the window would make it twice).
scenario('P2a observation serial',function()
 trusted()
 observe()
 local s1,e1=A.Orbs.Read()
 if not expect(type(s1)=='table' and type(s1.grantStamp)=='number','P2a: fixture: a direct read succeeds',e1) then return end
 H.granted=H.Clone(H.granted)
 local ok,err,calls=window(function() view();trustView();prepared();Nexus.SupportReport.Summary() end)
 expect(ok,'P2a: the collection window completed',err)
 expect(next(calls)==nil,'P2a: collection read nothing',callList(calls))
 H.granted=H.Clone(H.granted)
 local s2=A.Orbs.Read()
 expect(type(s2)=='table' and s2.grantStamp==s1.grantStamp+1,'P2a: exactly one serial step, by the read after collection',
  tostring(s1.grantStamp)..' -> '..tostring(s2 and s2.grantStamp))
end)

-- P2b. A reply that the next Owned() would confirm, an old observation and the
-- whole report: collection confirms nothing, marks nothing dirty, moves no
-- revision or counter, writes nothing and does not refresh the observation.
scenario('P2b pending confirmation and an old observation',function()
 trusted()
 local gen=A.Owned().generation
 H.holdGrantedResponse=true;A.RunBoundaryReset()
 local g=A.Owned()
 expect(g.synced==false and g.generation==gen+1,'P2b: fixture: the same mirror after a run boundary is not confirmed')
 local s=observe()
 expect(s.error==TRUST and s.progress==nil,'P2b: fixture: the window read waits at the trust gate',s.error)
 H.granted=H.Clone(H.granted)   -- a reply arrived: the next Owned() would confirm it
 H.now=H.now+120                -- time passes; nothing runs
 local v0,t0=view(),trustView()
 A.ConsumeDirty()
 local c0,db0=counters(),serialize(NexusDB)
 local v1,t1,text
 local ok,err,calls=window(function()
  v1=view();t1=trustView();text=prepared()
  Nexus.SupportReport.Summary();Nexus.SupportReport.OrbLines()
 end)
 expect(ok,'P2b: the collection window completed',err)
 expect(next(calls)==nil,'P2b: collection called no getter, read, request, catalog, assignment, status, spend, select, lock or write',callList(calls))
 sameCounters('P2b',c0,counters())
 expect(serialize(NexusDB)==db0,'P2b: saved data is unchanged')
 local dirtyBoard,dirtySlots,dirtyData=A.ConsumeDirty()
 expect(not dirtyBoard and not dirtySlots and not dirtyData,'P2b: collection marked nothing dirty',
  tostring(dirtyBoard)..'/'..tostring(dirtySlots)..'/'..tostring(dirtyData))
 if expect(v0~=nil and v1~=nil,'P2b: ReadinessView answers') then
  validView('P2b',v1)
  expect(v1.at==v0.at and v1.stage=='trust_owned','P2b: the observation is neither replaced nor refreshed',v1.stage)
  expect(isCount(v1.age) and v1.age>=120,'P2b: its age shows that it is old',v1.age)
  expect(v1.ownedConfirmed==false and v1.ownedSynced==false,'P2b: observation-time trust facts are kept')
 end
 if expect(t0~=nil and t1~=nil,'P2b: OwnershipTrustView answers') then
  expect(t0.ownedConfirmed==false and t1.ownedConfirmed==false,'P2b: the pending reply is not confirmed by collection')
 end
 local tk=checkBlock('P2b',text or '',{TRUST})
 if tk then
  expect(tk.stage=='trust_owned' and tk['owned.confirmed']=='no','P2b: the report shows the observation as it was',tostring(tk.stage))
  local age=ageOf(tk);expect(age~=nil and age>=120,'P2b: with its age',tk.age)
 end
 -- Liveness: the reply really was pending; the next normal Owned() confirms it.
 A.Owned()
 local c2=counters()
 expect(c2.rev4==(c0.rev4 or 0)+1,'P2b: liveness: the next normal Owned() confirms the reply that collection left alone',
  tostring(c0.rev4)..' -> '..tostring(c2.rev4))
 local t2=trustView()
 if t2 then expect(t2.ownedConfirmed==true,'P2b: and the trust view shows that evaluation') end
 trusted()
end)

-- P4. Locked rejection codes, one defect each. The getter keeps its answer; the
-- trust view reports the last evaluation and reads nothing itself.
scenario('P4 locked rejection codes',function()
 trusted()
 local cases={
  {'valid',function() return {{spellId=410007,quality=2}} end,true,1,'none'},
  {'empty',function() return {} end,true,0,'none'},
  {'nil',function() return nil end,false,0,'absent'},
  {'not a table',function() return 5 end,false,0,'not_table'},
  {'invalid sibling',function() return {{spellId=410007},{spellId='bad'}} end,false,1,'invalid_value'},
  {'conflicting count names',function() return {{spellId=410007,stack=1,count=2}} end,false,0,'conflicting_alias'},
  {'cycle',function() local t={{spellId=410007}};t[2]=t;return t end,false,1,'cycle'},
  {'depth',function() local d={spellId=410007};for i=1,9 do d={d} end;return d end,false,0,'depth'},
  -- One record above the 120-copy row ceiling (records, not copies, meet the
  -- live capacity).
  {'over the limit',function() return {{spellId=410007,stacks=121}} end,false,121,'over_cap'},
  {'scalar leaf',function() return {{spellId=410007},{note='x'}} end,false,1,'scalar_leaf'},
 }
 for _,c in ipairs(cases) do
  local tag='P4 '..c[1]
  H.locked=c[2]()
  local l=A.LockedOwned()
  local copies=0
  for _,n in pairs(l.bySpell) do copies=copies+n end
  expect(l.synced==c[3] and copies==c[4],tag..': the getter keeps its answer (synced '..tostring(c[3])..', parsed copies '..c[4]..')',
   tostring(l.synced)..'/'..copies)
  local t
  local ok,err,calls=window(function() t=trustView() end)
  expect(ok and next(calls)==nil,tag..': the trust view reads nothing',callList(calls))
  if expect(t~=nil,tag..': OwnershipTrustView answers') then
   validTrust(tag,t)
   expect(t.lockedSynced==c[3] and t.lockedCopies==c[4] and t.lockedRejection==c[5],tag..': synced/copies/rejection',
    tostring(t.lockedSynced)..'/'..tostring(t.lockedCopies)..'/'..tostring(t.lockedRejection))
  end
 end
 -- A changed raw table is not re-read: the view keeps the last evaluation.
 H.locked={{spellId=410007,stacks=121}}
 local before=trustView()
 if before then expect(before.lockedRejection=='scalar_leaf','P4: until LockedOwned() runs again the view keeps the last evaluation',before.lockedRejection) end
 A.LockedOwned()
 local after=trustView()
 if after then
  expect(after.lockedRejection=='over_cap' and after.lockedSynced==false and after.lockedCopies==121,'P4: the next normal evaluation updates it',
   tostring(after.lockedRejection))
 end
 trusted()
end)

-- P5. Rolled ownership facts: generation, arming, confirmation, freshness,
-- trust, ghost and total, as the last Owned() evaluation saw them.
scenario('P5 rolled ownership facts',function()
 trusted()
 local base=A.Owned()
 local t=trustView()
 if expect(t~=nil,'P5: OwnershipTrustView answers') then
  validTrust('P5 trusted',t)
  expect(t.ownedGeneration==base.generation and t.ownedConfirmed==true and t.ownedArmed==true and t.ownedSynced==true
   and t.ownedGhost==false and t.ownedTotal==base.total,'P5 trusted: the facts of the last evaluation')
 end
 H.holdGrantedResponse=true;A.RunBoundaryReset()
 local g1=A.Owned()
 expect(g1.synced==false and g1.generation==base.generation+1,'P5 boundary: fixture: the same mirror is not confirmed')
 t=trustView()
 if t then
  expect(t.ownedGeneration==base.generation+1 and t.ownedConfirmed==false and t.ownedArmed==true and t.ownedFresh==false
   and t.ownedSynced==false and t.ownedGhost==false and t.ownedTotal==g1.total,
   'P5 boundary: armed, not confirmed, not fresh, untrusted; the mirror total is still reported')
  expect(isCount(t.ownedRetries) and t.ownedRetries>=1,'P5 boundary: the request count is reported',t.ownedRetries)
 end
 H.granted=H.Clone(H.granted)   -- a reply; nothing evaluates it yet
 t=trustView()
 if t then expect(t.ownedConfirmed==false and t.ownedSynced==false,'P5 reply: the view does not evaluate the reply itself') end
 local r=A.Owned()
 expect(r.synced==true,'P5 reply: fixture: the next normal Owned() confirms it')
 t=trustView()
 if t then expect(t.ownedConfirmed==true and t.ownedFresh==true and t.ownedSynced==true,'P5 reply: confirmed and fresh after that evaluation') end
 A.RunBoundaryReset();A.Owned()
 H.granted={}
 local e=A.Owned()
 expect(e.synced==true and e.total==0,'P5 empty: fixture: a new empty table confirms an empty mirror')
 t=trustView()
 if t then
  expect(t.ownedSynced==true and t.ownedTotal==0 and t.ownedConfirmed==true and t.ownedFresh==true,
   'P5 empty: confirmed empty ownership is trusted, distinct from unavailable')
 end
 H.holdGrantedResponse=nil
 local ghost={}
 for i=1,25 do local id=200000+i;ghost[H.names[id]]={{spellId=id,quality=i%4}} end
 H.granted=ghost;H.playerLevel=1
 local gh=A.Owned()
 H.playerLevel=40
 expect(gh.ghostSuspect==true and gh.synced==false,'P5 ghost: fixture: a level-1 mirror of 25 Echoes is a suspected ghost')
 t=trustView()
 if t then expect(t.ownedGhost==true and t.ownedSynced==false and t.ownedTotal==25,'P5 ghost: reported as a ghost and untrusted') end
 trusted()
end)

-- P6. Corrupt or failing inputs give safe unknowns; the window is unaffected.
scenario('P6 corrupt or failing inputs',function()
 trusted()
 -- (a) The Orb read hands back an injected reason and malformed stage values.
 local realRead=A.Orbs.Read
 for i,third in ipairs({'ZQ_STAGE_MARKER 410002',{evil='ZQ_TABLE_MARKER'}}) do
  local tag='P6 read '..i
  A.Orbs.Read=function() return nil,'ZQ_READ_MARKER_8812 Disposable A 410001',third end
  local ok,err=pcall(observe)
  A.Orbs.Read=realRead
  expect(ok,tag..': the window read survives',err)
  local v=view()
  if expect(v~=nil,tag..': ReadinessView answers') then
   validView(tag,v)
   expect(v.stage~=nil and STAGES[v.stage]==true,tag..': the recorded stage is a documented code',v.stage)
   expect(v.progress=='unavailable',tag..': progress is unavailable',v.progress)
  end
  checkBlock(tag,prepared(),{'ZQ_'})
 end
 -- (b) The trust view hands back corrupt values during a normal read.
 local realTrust=A.OwnershipTrustView
 local evil=setmetatable({},{__tostring=function() error('ZQ_TOSTRING_MARKER') end})
 A.OwnershipTrustView=function()
  return {ownedSynced='yes',ownedConfirmed=1,ownedArmed=evil,ownedFresh={},ownedGhost=print,ownedGeneration=2.5,
   ownedTotal=-3,ownedRetries=0/0,lockedSynced='true',lockedCopies=1/0,
   lockedRejection='ZQ_REJECTION_MARKER Disposable A 410001'}
 end
 H.locked=nil
 local ok,err=pcall(observe)
 A.OwnershipTrustView=realTrust
 expect(ok,'P6 trust: the window read survives corrupt trust facts',err)
 local v=view()
 if expect(v~=nil,'P6 trust: ReadinessView answers') then validView('P6 trust',v) end
 checkBlock('P6 trust',prepared(),{'ZQ_'})
 -- (c) A failing trust view changes nothing the window shows or allows.
 local okShown,shown0=pcall(observeShown)
 A.OwnershipTrustView=function() error('ZQ_TRUST_THROW_MARKER') end
 local okThrow,shown1=pcall(observeShown)
 A.OwnershipTrustView=realTrust
 expect(okShown and okThrow,'P6 trust throws: the window read survives',tostring(shown0)..' / '..tostring(shown1))
 if okShown and okThrow then
  for _,k in ipairs({'plan','targets','status','start','canStart','startReason','error'}) do
   expect(shown0[k]==shown1[k],'P6 trust throws: '..k..' is unchanged',tostring(shown0[k])..' vs '..tostring(shown1[k]))
  end
 end
 H.locked={}
 -- (d) The report accessor fails or answers garbage.
 local realView=Nexus.OrbRuntime.ReadinessView
 local corrupt={observed=true,at=0/0,age=-7,stage='ZQ_STAGE_MARKER Disposable A 410001',assignment=PLAN,roles=410002,
  progress='available 410002',rolledMissing=1/0,permanentMissing=-1,ownedSynced='yes',ownedConfirmed=1,ownedArmed=evil,
  ownedFresh={},ownedGhost=print,ownedGeneration=2.5,ownedTotal=-3,lockedSynced='true',lockedCopies=1e300,
  lockedRejection=string.rep('ZQ_REJECTION_MARKER',300),balance=PLAN,charges=-1}
 for i=1,200 do corrupt['ZQjunk'..i]='ZQ_JUNK_MARKER Disposable A 410001' end
 local variants={
  {'throws',function() error('ZQ_VIEW_THROW_MARKER Disposable A 410001') end,true},
  {'not a table',function() return 'ZQ_VIEW_STRING_MARKER Disposable A 410001' end,true},
  {'raising index',function() return setmetatable({},{__index=function() error('ZQ_VIEW_INDEX_MARKER') end}) end,true},
  {'corrupt values',function() return corrupt end,false},
 }
 for _,variant in ipairs(variants) do
  local tag='P6 view '..variant[1]
  Nexus.OrbRuntime.ReadinessView=variant[2]
  local okP,text=pcall(prepared)
  Nexus.OrbRuntime.ReadinessView=realView
  if expect(okP,tag..': the report is still prepared',text) then
   local t=checkBlock(tag,text,{'ZQ_'})
   if t then
    for key in pairs(VALID) do
     if key~='observed' and t[key]~=nil then expect(NULL[t[key]]==true,tag..': '..key..' is shown as unknown',t[key]) end
    end
    if variant[3] then
     expect(t.observed=='unavailable' or t.observed=='unknown','P6 view '..variant[1]..': the block says readiness is unavailable',t.observed)
    else
     expect(t.observed=='yes' or NULL[t.observed]==true,tag..': observed is yes or unknown',t.observed)
    end
   end
  end
 end
end)

-- P9. An existing receipt is preserved by collection; on a fresh runtime the
-- view does not initialize anything (a saved receipt stays unloaded).
scenario('P9 receipt preserved and no initialization',function()
 trusted()
 local key=Nexus.Store.CurrentOwnerKey()
 H.Approve(1,false)
 local row=NexusDB.chars[key]
 expect(H.Count('orb-spend')==1 and type(row)=='table' and type(row.orbRefinement)=='table'
  and type(row.orbRefinement.pending)=='table','P9: fixture: one counted fake spend left a real pending receipt',H.Count('orb-spend'))
 local R=Nexus.OrbRuntime
 local row0,rv0,log0=serialize(NexusDB.chars[key]),serialize(R.RecoveryView()),serialize(R.RunLog('current'))
 local spends,actions=H.Count('orb-spend'),#H.actions
 local text
 local ok,err,calls=window(function() view();trustView();text=prepared() end)
 expect(ok,'P9: the collection window completed',err)
 expect(next(calls)==nil,'P9: collection with a receipt called no getter, read, request, status, spend, select, lock or write',callList(calls))
 expect(serialize(NexusDB.chars[key])==row0,'P9: the saved receipt and preferences are unchanged')
 expect(serialize(R.RecoveryView())==rv0,'P9: the recovery view is unchanged')
 expect(serialize(R.RunLog('current'))==log0,'P9: the run history is unchanged')
 expect(H.Count('orb-spend')==spends and #H.actions==actions,'P9: nothing more was sent')
 expect(type(text)=='string' and text:find('Orb action: unresolved in this session',1,true)~=nil,'P9: the report keeps the unresolved receipt lines')
 local lines=readinessLines(text)
 if #lines>0 then
  local found=leaks(lines,{})
  expect(#found==0,'P9: a readiness block shown with a receipt follows the same rules',table.concat(found,','))
 end
 -- A fresh runtime: the saved receipt is not loaded yet.
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 R=Nexus.OrbRuntime
 local frames,db0=#H.frames,serialize(NexusDB)
 local v
 local okR,errR,callsR=window(function() v=view() end)
 expect(okR,'P9 fresh: the view call completed',errR)
 expect(v~=nil,'P9 fresh: ReadinessView answers on a fresh runtime')
 if v then validView('P9 fresh',v) end
 expect(next(callsR)==nil,'P9 fresh: the view does not initialize the runtime (no capture or observer start, no read)',callList(callsR))
 expect(#H.frames==frames,'P9 fresh: no recovery frame was created',#H.frames-frames)
 expect(serialize(NexusDB)==db0,'P9 fresh: saved data is unchanged')
 -- Liveness: the existing passive reader does load the receipt and start recovery.
 local rv
 local okL,errL,callsL=window(function() rv=R.RecoveryView() end)
 expect(okL and type(rv)=='table' and rv.pending==true and rv.restored==true,
  'P9 fresh: liveness: the existing recovery reader restores the saved receipt',errL)
 expect((callsL['Orbs.CaptureStart'] or 0)+(callsL['Orbs.TransportStart'] or 0)>=1,
  'P9 fresh: liveness: initializing starts passive recovery, so the check above could fail',callList(callsL))
 local after=prepared()
 expect(after:find('Orb action: unresolved after a reload',1,true)~=nil,'P9 fresh: the report keeps the restored receipt lines')
 expect(serialize(NexusDB)==db0,'P9 fresh: the receipt is still saved unchanged')
end)

if #failures>0 then
 error('orb_readiness_collection_pure: '..#failures..' of '..checks..' expectation(s) failed; first: '..failures[1],0)
end
print('PASS orb_readiness_collection_pure checks='..checks)
