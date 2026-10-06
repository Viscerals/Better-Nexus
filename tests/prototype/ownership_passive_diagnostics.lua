-- Passive ownership diagnostics in the support report, also when no Orb window
-- was ever opened. Normal rolling reads GameAdapter.LockedOwned() as the Orb read
-- does, and EchoWeaver waits while locked.synced=false. So the full prepared
-- report must say what the last normal Owned() and LockedOwned() evaluations
-- sampled: each with its own observed flag and age, the sampled generation apart
-- from the current one, the distinct count, the fixed rejection and the raw type
-- class. At aac790c the adapter keeps none of this and the report has no such
-- block (source reading).
-- Contract: TEST_CONTRACT.md of the tests-first review, sections 3a, 5a and 10.
-- Only a normal Owned()/LockedOwned() call updates its own sample. Collection
-- reads only Nexus.GameAdapter.OwnershipTrustView and
-- Nexus.OrbRuntime.ReadinessView, looked up when the report is collected, and
-- changes nothing.
-- Real TOC boot, adapter, report builder, EchoWeaver and Wishlist view model; the
-- fake services of orbs_support.lua. A pristine adapter instance, loaded in a
-- sandbox with its own Nexus table, stands for "before any normal read".
-- Artificial IDs and names. No run is started and nothing is spent. The
-- level-cap scenario reproduces the existing conservative wait and repairs
-- nothing. Every expectation is evaluated and reported; the test fails at the
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

-- Whole seconds from here on, so that every age is exact.
H.now=math.floor(H.now)+100
local BASE_GRANTED=H.Clone(H.granted)
local WAIT_LOCKED='waiting for locked Echo state'
-- Three recognized locks; then the same three and one malformed sibling.
local function locks() return {{spellId=410007,quality=2},{spellId=200001,quality=1},{spellId=200002,quality=2}} end
local function locksWithSibling() local t=locks();t[#t+1]={spellId='ZQ_bad'};return t end
local function copies(l)
 local n=0
 for _,c in pairs(type(l)=='table' and type(l.bySpell)=='table' and l.bySpell or {}) do n=n+c end
 return n
end

-- Documented codes and keys (TEST_CONTRACT.md, sections 3a, 5, 5a and 6).
local function set(list) local s={};for _,v in ipairs(list) do s[v]=true end;return s end
local REJECTIONS=set({'none','absent','not_table','unreadable','invalid_value','conflicting_alias','cycle','depth','over_cap','scalar_leaf'})
local RAW_TYPES=set({'nil','boolean','number','string','table','function','userdata','thread','unknown'})
local YESNO=set({'yes','no'})
local NULL=set({'unknown','unavailable','?'})
local UNSEEN=set({'not_observed','unknown','unavailable','?'})
local READINESS_UNSEEN=set({'none','not_observed','unknown','unavailable','?'})
local function oneOf(values) return function(v) return values[v]==true or UNSEEN[v]==true end end
local function count(v) return (v:match('^%d+$')~=nil and #v<=7) or UNSEEN[v]==true end
local function age(v) return (v:match('^%d+s?$')~=nil and #v<=8) or UNSEEN[v]==true end
local OWN_VALID={
 ['ordinary.observed']=oneOf(YESNO),['ordinary.age']=age,['ordinary.synced']=oneOf(YESNO),
 ['ordinary.generation']=count,['ordinary.confirmed']=oneOf(YESNO),['ordinary.fresh']=oneOf(YESNO),
 ['ordinary.ghost']=oneOf(YESNO),['ordinary.distinct']=count,['ordinary.total']=count,
 ['locked.observed']=oneOf(YESNO),['locked.age']=age,['locked.synced']=oneOf(YESNO),['locked.copies']=count,
 ['locked.rejection']=oneOf(REJECTIONS),['locked.raw']=oneOf(RAW_TYPES),
 ['current.generation']=count,['current.confirmed']=oneOf(YESNO),['current.armed']=oneOf(YESNO),
 ['current.retries']=count,
}
local ORDINARY_KEYS={'ordinary.age','ordinary.synced','ordinary.generation','ordinary.confirmed','ordinary.fresh',
 'ordinary.ghost','ordinary.distinct','ordinary.total'}
local LOCKED_KEYS={'locked.age','locked.synced','locked.copies','locked.rejection','locked.raw'}
local READINESS_REQUIRED={'observed','age','stage','assignment.state','assignment.roles','progress',
 'owned.synced','owned.generation','owned.confirmed','owned.armed','owned.fresh','owned.ghost','owned.total',
 'locked.synced','locked.copies','locked.rejection'}
local READINESS_FACTS={'age','stage','assignment.state','assignment.roles','progress','owned.synced',
 'owned.generation','owned.confirmed','owned.armed','owned.fresh','owned.ghost','owned.total','locked.synced',
 'locked.copies','locked.rejection','balance','charges','offer.pending','host.pending','progress.rolled',
 'progress.permanent'}
local OWNED_SAMPLE={'ownedAt','ownedAge','ownedSampledGeneration','ownedSampledConfirmed','ownedDistinct',
 'ownedSynced','ownedFresh','ownedGhost','ownedTotal'}
local LOCKED_SAMPLE={'lockedAt','lockedAge','lockedSynced','lockedCopies','lockedRejection','lockedRawType'}
local CURRENT={'ownedGeneration','ownedConfirmed','ownedArmed','ownedRetries'}
-- Privacy (blocks and views): no name, no Echo ID, no reference, no control character.
local NAMES={'Disposable A','Disposable B','Desired A','Desired B','Protected low','Excess high',
 'Unsafe fallback','Synthetic Echo','Orb test','ZQ plan','ZQ build','PrototypeTester','Ebonhold'}
local IDS={}
for id=410001,410008 do IDS[#IDS+1]=id end
for id=200001,200090 do IDS[#IDS+1]=id end
IDS[#IDS+1]=499999
local function leaks(list,markers,maxLines,maxBytes)
 local text=table.concat(list,'\n')
 local found={}
 for _,n in ipairs(NAMES) do if text:find(n,1,true) then found[#found+1]='name '..n end end
 for _,id in ipairs(IDS) do if text:find('%f[%d]'..id..'%f[%D]') then found[#found+1]='id '..id end end
 for _,r in ipairs({'table: ','function: ','userdata: ','thread: ','builtin'}) do
  if text:find(r,1,true) then found[#found+1]='reference' end
 end
 for _,m in ipairs(markers or {}) do if text:find(m,1,true) then found[#found+1]='text '..m:sub(1,40) end end
 for _,line in ipairs(list) do if line:find('%c') then found[#found+1]='control character' end end
 if #list>maxLines then found[#found+1]=#list..' lines' end
 if #text>maxBytes then found[#found+1]=#text..' bytes' end
 return found
end
local function lines(text,prefix)
 local out={}
 for line in (tostring(text or '')..'\n'):gmatch('([^\n]*)\n') do
  if line:match('^%s*'..prefix) then out[#out+1]=line end
 end
 return out
end
local function tokens(list)
 local t,conflicts={},{}
 for _,line in ipairs(list) do
  for k,v in line:gmatch('([%a][%w_%.]*)=([%w_%.%-%?]*)') do
   if t[k]~=nil and t[k]~=v then conflicts[#conflicts+1]=k end
   t[k]=v
  end
 end
 return t,conflicts
end
local function ageValue(v)
 local n=type(v)=='string' and v:match('^(%d+)s?$')
 return n and tonumber(n) or nil
end
local function facts(t,keys)
 if type(t)~='table' then return printable(t) end
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=k..'='..printable(t[k]) end
 return table.concat(out,' ')
end
local function isCount(x) return type(x)=='number' and x>=0 and x==math.floor(x) and x<=1000000 end
local function finite(x) return type(x)=='number' and x==x and x>-math.huge and x<math.huge end
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

-- Spies: counted inside a collection window, and in total since boot for the
-- Orb paths; behaviour is unchanged.
local SPY={on=false,calls={},total={}}
local function wrap(owner,name,label)
 if type(owner)~='table' or type(owner[name])~='function' then return end
 local fn=owner[name]
 owner[name]=function(...)
  SPY.total[label]=(SPY.total[label] or 0)+1
  if SPY.on then SPY.calls[label]=(SPY.calls[label] or 0)+1 end
  return fn(...)
 end
end
local function wrapAll(owner,prefix)
 if type(owner)~='table' then return end
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
wrap(Nexus.OrbPanel,'Show','OrbPanel.Show')
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

local function call(fn)
 if type(fn)~='function' then return nil,'not available' end
 local ok,v=pcall(fn)
 if not ok then return nil,printable(v) end
 if type(v)~='table' then return nil,'not a table' end
 return v
end
local function trustView() return call(A.OwnershipTrustView) end
local function readinessView() return call(Nexus.OrbRuntime.ReadinessView) end
-- The accessor (section 3a): scalars only, bounded, one independent sample each.
local function validTrust(tag,t)
 local n=0
 for k,x in pairs(t) do
  n=n+1
  local kind=type(x)
  expect(type(k)=='string' and (kind=='string' or kind=='number' or kind=='boolean'),tag..': '..printable(k)..' is a scalar',kind)
  if kind=='string' then
   local found=leaks({x},{'ZQ_'},1,32)
   expect(#found==0,tag..': '..printable(k)..' is a short code with no name, Echo ID, reference or injected text',table.concat(found,','))
  end
  if kind=='number' then expect(finite(x),tag..': '..printable(k)..' is finite',x) end
 end
 expect(n<=40,tag..': the view is bounded',n)
 expect(type(t.ownedObserved)=='boolean' and type(t.lockedObserved)=='boolean',tag..': each sample says whether it was observed',
  facts(t,{'ownedObserved','lockedObserved'}))
 expect(isCount(t.ownedGeneration) and type(t.ownedConfirmed)=='boolean' and type(t.ownedArmed)=='boolean' and isCount(t.ownedRetries),
  tag..': the current generation facts are present',facts(t,CURRENT))
 if t.ownedObserved==true then
  expect(finite(t.ownedAt) and isCount(t.ownedAge) and isCount(t.ownedSampledGeneration) and type(t.ownedSampledConfirmed)=='boolean'
   and type(t.ownedSynced)=='boolean' and type(t.ownedGhost)=='boolean' and (t.ownedFresh==nil or type(t.ownedFresh)=='boolean')
   and isCount(t.ownedDistinct) and isCount(t.ownedTotal) and t.ownedDistinct<=t.ownedTotal,
   tag..': the ordinary sample is complete',facts(t,OWNED_SAMPLE))
 else
  local invented={}
  for _,k in ipairs(OWNED_SAMPLE) do if t[k]~=nil then invented[#invented+1]=k end end
  expect(#invented==0,tag..': no ordinary sample fact is invented',table.concat(invented,','))
 end
 if t.lockedObserved==true then
  expect(finite(t.lockedAt) and isCount(t.lockedAge) and type(t.lockedSynced)=='boolean' and isCount(t.lockedCopies)
   and REJECTIONS[t.lockedRejection]==true and RAW_TYPES[t.lockedRawType]==true and t.lockedSynced==(t.lockedRejection=='none'),
   tag..': the locked sample is complete, and trusted exactly when nothing was rejected',facts(t,LOCKED_SAMPLE))
 else
  local invented={}
  for _,k in ipairs(LOCKED_SAMPLE) do if t[k]~=nil then invented[#invented+1]=k end end
  expect(#invented==0,tag..': no locked sample fact is invented',table.concat(invented,','))
 end
end
-- The report block (section 5a): bounded, private, documented values only.
local OWNERSHIP='Ownership sample'
local function ownershipBlock(tag,text,markers)
 expect(text:find('Orb action:',1,true)~=nil,tag..': the existing Orb action line is kept')
 local list=lines(text,OWNERSHIP)
 if not expect(#list>0,tag..': the prepared report carries an ownership sample block (lines beginning "Ownership sample")') then return nil end
 local t,conflicts=tokens(list)
 expect(#conflicts==0,tag..': each ownership key has one value',table.concat(conflicts,','))
 local found=leaks(list,markers,8,1000)
 expect(#found==0,tag..': the block is bounded and carries no name, Echo ID, reference, raw value or injected text',table.concat(found,','))
 local claims={}
 local lower=table.concat(list,'\n'):lower()
 for _,w in ipairs({'removed','revoked','deleted','lost','orb action:'}) do if lower:find(w,1,true) then claims[#claims+1]=w end end
 for k in pairs(t) do if k:lower():find('cause',1,true) then claims[#claims+1]=k end end
 table.sort(claims)
 expect(#claims==0,tag..': the block labels evidence and rejection only (no removal claim, no cause, no Orb action line)',table.concat(claims,','))
 for key,valid in pairs(OWN_VALID) do
  if t[key]~=nil then expect(valid(t[key]),tag..': '..key..' has a documented value',t[key]) end
 end
 return t
end
local function shown(tag,t,component,keys)
 local missing={}
 for _,k in ipairs(keys) do if t[k]==nil then missing[#missing+1]=k end end
 expect(t[component..'.observed']=='yes' and #missing==0,tag..': the '..component..' sample is shown with all its facts',
  printable(t[component..'.observed'])..' missing '..table.concat(missing,','))
end
local function unseen(tag,t,component,keys)
 local invented={}
 for _,k in ipairs(keys) do if t[k]~=nil and UNSEEN[t[k]]~=true then invented[#invented+1]=k..'='..t[k] end end
 expect(t[component..'.observed']=='no' and #invented==0,tag..': the '..component..' sample is shown as not observed and nothing is invented',
  printable(t[component..'.observed'])..' '..table.concat(invented,','))
end
local function prepared()
 local report,why=Nexus.SupportReport.Prepare({})
 if type(report)~='table' or type(report.chunks)~='table' then error('the real builder did not prepare a report: '..printable(why)) end
 return table.concat(report.chunks,'')
end
local function trusted()
 H.holdGrantedResponse=nil;O.known=true;H.locked={};H.playerLevel=40
 H.granted=H.Clone(BASE_GRANTED);A.Owned();A.LockedOwned()
end

-- S0. Before either normal read. A pristine adapter instance, loaded in a sandbox
-- with its own Nexus table, has evaluated neither Owned() nor LockedOwned(). Its
-- accessor answers "not observed" for each, and the full prepared report that
-- collects it says so and invents no sample. The live adapter is not touched.
local pristine,pristineError
do
 local own=setmetatable({},{__index=function(t,k) local v={};rawset(t,k,v);return v end})
 local chunk,err=loadfile('core/GameAdapter.lua')
 if chunk then
  setfenv(chunk,setmetatable({Nexus=own},{__index=_G}))
  local ok,e=pcall(chunk,'Nexus',{})
  if ok then pristine=rawget(own,'GameAdapter') else pristineError=e end
 else
  pristineError=err
 end
end
scenario('S0 before either normal read',function()
 if not expect(type(pristine)=='table','S0: fixture: a pristine adapter instance loads in its own sandbox',pristineError) then return end
 expect(type(pristine.OwnershipTrustView)=='function','S0: GameAdapter.OwnershipTrustView() exists')
 local real=A.OwnershipTrustView
 local t,why,text
 local ok,err,calls=window(function()
  t,why=call(pristine.OwnershipTrustView)
  A.OwnershipTrustView=pristine.OwnershipTrustView
  local okP,p=pcall(prepared)
  A.OwnershipTrustView=real
  if not okP then error(p,0) end
  text=p
 end)
 expect(ok,'S0: the collection window completed',err)
 expect(next(calls)==nil,'S0: the accessor and the report called no getter, read, request, status, spend, lock or write',callList(calls))
 if expect(t~=nil,'S0: the pristine OwnershipTrustView answers',why) then
  validTrust('S0',t)
  expect(t.ownedObserved==false and t.lockedObserved==false,'S0: neither ordinary nor locked ownership is observed yet',
   facts(t,{'ownedObserved','lockedObserved'}))
  expect(t.ownedGeneration==0 and t.ownedConfirmed==false,'S0: the current generation is the initial, unconfirmed one',facts(t,CURRENT))
 end
 local o=ownershipBlock('S0',text or '',{})
 if o then
  unseen('S0',o,'ordinary',ORDINARY_KEYS)
  unseen('S0',o,'locked',LOCKED_KEYS)
  expect(o['current.generation']=='0' and o['current.confirmed']=='no','S0: the current generation is shown apart from any sample',
   facts(o,{'current.generation','current.confirmed'}))
 end
end)

-- S1. A normal locked read of three recognized locks, then a strict refusal while
-- they remain, with no Orb window, Orb read or Orb status: the full no-run report
-- shows the recognized copies apart from the false trust, the fixed rejection and
-- the raw type class, and its Orb readiness block still says nothing was observed.
scenario('S1 locked sample without any Orb observation',function()
 H.holdGrantedResponse=nil;O.known=true;H.playerLevel=40
 H.granted=H.Clone(BASE_GRANTED);A.Owned()
 H.locked=locks()
 local l1=A.LockedOwned()
 expect(l1.synced==true and copies(l1)==3,'S1 valid: fixture: three recognized locks are trusted',tostring(l1.synced)..'/'..copies(l1))
 local o1=ownershipBlock('S1 valid',prepared(),{})
 if o1 then
  shown('S1 valid',o1,'locked',LOCKED_KEYS)
  expect(o1['locked.synced']=='yes' and o1['locked.copies']=='3' and o1['locked.rejection']=='none' and o1['locked.raw']=='table',
   'S1 valid: trusted, three copies, no rejection, raw type table',facts(o1,LOCKED_KEYS))
 end
 H.now=H.now+30
 H.locked=locksWithSibling()
 local l2=A.LockedOwned()
 expect(l2.synced==false and copies(l2)==3,'S1 refused: fixture: the strict reader keeps the three recognized copies and refuses trust',
  tostring(l2.synced)..'/'..copies(l2))
 local t,why=trustView()
 if expect(t~=nil,'S1 refused: OwnershipTrustView answers',why) then
  validTrust('S1 refused',t)
  expect(t.lockedObserved==true and t.lockedSynced==false and t.lockedCopies==3 and t.lockedRejection=='invalid_value'
   and t.lockedRawType=='table' and t.lockedAt==H.now and t.lockedAge==0,
   'S1 refused: the recognized copies are kept apart from the false trust, with the fixed rejection and the time of the read',
   facts(t,LOCKED_SAMPLE))
 end
 local text=prepared()
 expect(text:find('Orb action: none unresolved',1,true)~=nil and text:find('no run in this session',1,true)~=nil,
  'S1 refused: the full no-run report keeps its existing Orb lines')
 local o2=ownershipBlock('S1 refused',text,{'ZQ_'})
 if o2 then
  shown('S1 refused',o2,'locked',LOCKED_KEYS)
  expect(o2['locked.synced']=='no' and o2['locked.copies']=='3' and o2['locked.rejection']=='invalid_value'
   and o2['locked.raw']=='table' and ageValue(o2['locked.age'])==0,
   'S1 refused: the report shows three recognized copies, no trust, the fixed rejection and the age of the read',facts(o2,LOCKED_KEYS))
 end
 local r=lines(text,'Orb readiness')
 if expect(#r>0,'S1 refused: the Orb readiness block is still present') then
  local rt=tokens(r)
  local invented={}
  for _,k in ipairs(READINESS_FACTS) do
   if rt[k]~=nil and READINESS_UNSEEN[rt[k]]~=true then invented[#invented+1]=k..'='..rt[k] end
  end
  expect(rt.observed=='no' and #invented==0,'S1 refused: the Orb readiness block still says nothing was observed and invents nothing',
   printable(rt.observed)..' '..table.concat(invented,','))
 end
 local orb=(SPY.total['OrbRuntime.Status'] or 0)+(SPY.total['Orbs.Read'] or 0)+(SPY.total['OrbPanel.Show'] or 0)
 expect(orb==0,'S1: fixture: no Orb window, Orb read or Orb status ran in this test so far',orb)
end)

-- S2. Independent ages. Each sample keeps the time of its own last normal read: a
-- later locked read does not refresh the ordinary sample, and the reverse. The
-- answer is a copy.
scenario('S2 independent ages',function()
 trusted()
 local T0=H.now
 local t0,why=trustView()
 if expect(t0~=nil,'S2: OwnershipTrustView answers',why) then
  validTrust('S2 both read',t0)
  expect(t0.ownedObserved==true and t0.ownedAt==T0 and t0.ownedAge==0 and t0.lockedObserved==true and t0.lockedAt==T0 and t0.lockedAge==0,
   'S2 both read: each sample has the time of its own read',facts(t0,{'ownedObserved','ownedAt','ownedAge','lockedObserved','lockedAt','lockedAge'}))
  t0.ownedAt=-1;t0.lockedObserved=false;t0.lockedRawType='ZQ_MUTATED';t0.ownedSampledGeneration=-99
  local again=trustView()
  expect(again~=nil and not rawequal(again,t0) and again.ownedAt==T0 and again.lockedObserved==true and again.lockedRawType=='table'
   and again.ownedSampledGeneration~=-99,'S2 copy: each call returns a new table and the samples are unchanged',
   facts(again,{'ownedAt','lockedObserved','lockedRawType','ownedSampledGeneration'}))
 end
 H.now=H.now+40
 H.locked={{spellId=410007,stacks=7}}
 A.LockedOwned()
 local t1=trustView()
 if t1 then
  expect(t1.lockedAt==T0+40 and t1.lockedAge==0 and t1.lockedRejection=='over_cap' and t1.lockedCopies==7,
   'S2 locked read: the locked sample is new',facts(t1,{'lockedAt','lockedAge','lockedRejection','lockedCopies'}))
  expect(t1.ownedAt==T0 and t1.ownedAge==40 and t1.ownedSynced==true,'S2 locked read: the ordinary sample keeps its own time and facts',
   facts(t1,{'ownedAt','ownedAge','ownedSynced'}))
 end
 local o1=ownershipBlock('S2 locked read',prepared(),{})
 if o1 then
  expect(ageValue(o1['locked.age'])==0 and ageValue(o1['ordinary.age'])==40 and o1['locked.rejection']=='over_cap'
   and o1['ordinary.synced']=='yes','S2 locked read: the report shows each sample with its own age and facts',
   facts(o1,{'locked.age','ordinary.age','locked.rejection','ordinary.synced'}))
 end
 H.now=H.now+15
 A.Owned()
 local t2=trustView()
 if t2 then
  expect(t2.ownedAt==T0+55 and t2.ownedAge==0,'S2 ordinary read: the ordinary sample is new',facts(t2,{'ownedAt','ownedAge'}))
  expect(t2.lockedAt==T0+40 and t2.lockedAge==15 and t2.lockedRejection=='over_cap',
   'S2 ordinary read: the locked sample keeps its own time and facts',facts(t2,{'lockedAt','lockedAge','lockedRejection'}))
 end
 local o2=ownershipBlock('S2 ordinary read',prepared(),{})
 if o2 then
  expect(ageValue(o2['ordinary.age'])==0 and ageValue(o2['locked.age'])==15,'S2 ordinary read: the report shows each sample with its own age',
   facts(o2,{'ordinary.age','locked.age'}))
 end
 H.now=H.now+7
 local t3=trustView()
 if t3 then
  expect(t3.ownedAt==T0+55 and t3.ownedAge==7 and t3.lockedAt==T0+40 and t3.lockedAge==22,
   'S2 no read: both ages grow and neither time moves',facts(t3,{'ownedAt','ownedAge','lockedAt','lockedAge'}))
 end
 trusted()
end)

-- S3. Sampled against current. A run boundary moves the current generation but not
-- the sample: an old trusted sample stays labelled with its own generation and
-- age, apart from the current, unconfirmed generation. A read just now is not a
-- fresh or trusted response. S4: collection with a reply pending changes nothing.
scenario('S3 sampled and current generation; S4 passive collection',function()
 trusted()
 H.granted={['Disposable A']={{spellId=410001,quality=1},{spellId=410001,quality=1}},['Disposable B']={{spellId=410003,quality=0}}}
 local base=A.Owned()
 expect(base.synced==true and base.distinct==2 and base.total==3,'S3: fixture: two distinct rolled Echoes in three copies, trusted',
  tostring(base.synced)..'/'..tostring(base.distinct)..'/'..tostring(base.total))
 local gen,T0=base.generation,H.now
 local t0,why=trustView()
 if expect(t0~=nil,'S3: OwnershipTrustView answers',why) then
  validTrust('S3 trusted',t0)
  expect(t0.ownedSampledGeneration==gen and t0.ownedSampledConfirmed==true and t0.ownedSynced==true and t0.ownedDistinct==2
   and t0.ownedTotal==3,'S3 trusted: the sample carries its generation, confirmation, distinct count and total',facts(t0,OWNED_SAMPLE))
  expect(t0.ownedGeneration==gen and t0.ownedConfirmed==true,'S3 trusted: the current generation is the sampled one',facts(t0,CURRENT))
 end
 H.now=H.now+20
 H.holdGrantedResponse=true;A.RunBoundaryReset()
 local t1=trustView()
 if t1 then
  expect(t1.ownedGeneration==gen+1 and t1.ownedConfirmed==false,'S3 boundary: the current generation moved and is not confirmed',facts(t1,CURRENT))
  expect(t1.ownedSampledGeneration==gen and t1.ownedSampledConfirmed==true and t1.ownedSynced==true and t1.ownedAt==T0
   and t1.ownedAge==20,'S3 boundary: the old sample is kept as it was, with its own generation and age',facts(t1,OWNED_SAMPLE))
 end
 local o1=ownershipBlock('S3 boundary',prepared(),{})
 if o1 then
  expect(o1['ordinary.generation']==tostring(gen) and o1['current.generation']==tostring(gen+1) and o1['current.confirmed']=='no',
   'S3 boundary: the report keeps the old sample apart from the current, unconfirmed generation',
   facts(o1,{'ordinary.generation','current.generation','current.confirmed'}))
  expect(o1['ordinary.synced']=='yes' and o1['ordinary.confirmed']=='yes' and ageValue(o1['ordinary.age'])==20
   and o1['ordinary.distinct']=='2' and o1['ordinary.total']=='3','S3 boundary: the old sample is shown with its age, distinct count and total',
   facts(o1,{'ordinary.synced','ordinary.confirmed','ordinary.age','ordinary.distinct','ordinary.total'}))
 end
 local g=A.Owned()
 expect(g.synced==false and g.generation==gen+1,'S3 new generation: fixture: the same mirror is not confirmed',
  tostring(g.synced)..'/'..tostring(g.generation))
 local t2=trustView()
 if t2 then
  expect(t2.ownedSampledGeneration==gen+1 and t2.ownedSampledConfirmed==false and t2.ownedSynced==false and t2.ownedFresh==false
   and t2.ownedAge==0,'S3 new generation: a read just now is not a fresh or trusted response',facts(t2,OWNED_SAMPLE))
 end
 local o2=ownershipBlock('S3 new generation',prepared(),{})
 if o2 then
  expect(ageValue(o2['ordinary.age'])==0 and o2['ordinary.synced']=='no' and o2['ordinary.fresh']=='no' and o2['ordinary.confirmed']=='no',
   'S3 new generation: age 0, with no fresh, confirmed or trusted response',
   facts(o2,{'ordinary.age','ordinary.synced','ordinary.fresh','ordinary.confirmed'}))
 end
 -- S4. A reply arrives that the next Owned() would confirm, and time passes.
 H.granted=H.Clone(H.granted)
 H.now=H.now+25
 A.ConsumeDirty()
 local c0,db0=counters(),serialize(NexusDB)
 local req0=serialize({H.grantedRequests or 0,H.slotRequests or 0,O.requests or 0,#H.actions})
 local tv0=trustView()
 local tv1,text
 local ok,err,calls=window(function()
  tv1=trustView();text=prepared()
  Nexus.SupportReport.Summary();Nexus.SupportReport.OrbLines()
 end)
 expect(ok,'S4: the collection window completed',err)
 expect(next(calls)==nil,'S4: collection called no getter, read, request, catalog, status, spend, lock or write',callList(calls))
 sameCounters('S4',c0,counters())
 expect(serialize(NexusDB)==db0,'S4: saved data is unchanged')
 local req1=serialize({H.grantedRequests or 0,H.slotRequests or 0,O.requests or 0,#H.actions})
 expect(req1==req0,'S4: no service request or action was sent',req0..' -> '..req1)
 local dirtyBoard,dirtySlots,dirtyData=A.ConsumeDirty()
 expect(not dirtyBoard and not dirtySlots and not dirtyData,'S4: collection marked nothing dirty',
  tostring(dirtyBoard)..'/'..tostring(dirtySlots)..'/'..tostring(dirtyData))
 if tv0 then
  local after=trustView()
  expect(serialize(tv1)==serialize(tv0) and serialize(after)==serialize(tv0),'S4: collection neither changes nor refreshes a sample',
   serialize(tv0)..' -> '..serialize(after))
 end
 local o=ownershipBlock('S4',text or '',{})
 if o then
  expect(o['current.confirmed']=='no' and o['ordinary.confirmed']=='no' and ageValue(o['ordinary.age'])==25,
   'S4: the pending reply stays unconfirmed and the sample keeps the age of the last read',
   facts(o,{'current.confirmed','ordinary.confirmed','ordinary.age'}))
 end
 -- Liveness: the reply really was pending; the next normal Owned() confirms it.
 local r=A.Owned()
 local c2=counters()
 expect(r.synced==true and c2.rev4==(c0.rev4 or 0)+1,'S4: liveness: the next normal Owned() confirms the reply that collection left alone',
  tostring(r.synced)..' rev '..tostring(c0.rev4)..' -> '..tostring(c2.rev4))
 local t3=trustView()
 if t3 then
  expect(t3.ownedConfirmed==true and t3.ownedSampledConfirmed==true and t3.ownedFresh==true and t3.ownedAge==0,
   'S4: and the sample shows that evaluation',facts(t3,OWNED_SAMPLE))
 end
 H.holdGrantedResponse=nil
 trusted()
end)

-- S5. Each locked shape of TEST_CONTRACT.md section 6: the getter keeps its answer;
-- the locked sample adds the raw type class (a Lua type name, never the value);
-- the report shows synced, copies, rejection and type class without the value.
scenario('S5 locked shapes',function()
 trusted()
 local t0,why=trustView()
 expect(t0~=nil,'S5: OwnershipTrustView answers',why)
 local cases={
  {'valid empty',function() return {} end,true,0,set({'none'}),set({'table'})},
  {'nil',function() return nil end,false,0,set({'absent'}),set({'nil'})},
  {'number',function() return 5 end,false,0,set({'not_table'}),set({'number'})},
  {'string',function() return 'ZQ_RAW_MARKER Disposable A 410007' end,false,0,set({'not_table'}),set({'string'})},
  {'thread',function() return coroutine.create(function() end) end,false,0,set({'not_table'}),set({'thread'})},
  {'invalid sibling',locksWithSibling,false,3,set({'invalid_value'}),set({'table'})},
  {'conflicting count names',function() return {{spellId=410007,stack=1,count=2}} end,false,0,set({'conflicting_alias'}),set({'table'})},
  {'over the limit',function() return {{spellId=410007,stacks=7}} end,false,7,set({'over_cap'}),set({'table'})},
  {'cycle',function() local t={{spellId=410007}};t[2]=t;return t end,false,1,set({'cycle'}),set({'table'})},
  {'depth',function() local d={spellId=410007};for _=1,9 do d={d} end;return d end,false,0,set({'depth'}),set({'table'})},
  {'scalar leaf',function() return {{spellId=410007},{note='ZQ_LEAF_MARKER'}} end,false,1,set({'scalar_leaf'}),set({'table'})},
  {'getter raises',false,false,0,set({'absent','unreadable'}),set({'nil','unknown'})},
 }
 for _,c in ipairs(cases) do
  local tag='S5 '..c[1]
  local svc=ProjectEbonhold.PerkService
  local real=svc.GetLockedPerks
  if c[2] then H.locked=c[2]() else svc.GetLockedPerks=function() error('ZQ_GETTER_MARKER Disposable A 410007') end end
  local ok,l=pcall(A.LockedOwned)
  svc.GetLockedPerks=real
  expect(ok and type(l)=='table' and l.synced==c[3] and copies(l)==c[4],
   tag..': fixture: the getter keeps its answer (synced '..tostring(c[3])..', '..c[4]..' copies)',
   ok and (tostring(type(l)=='table' and l.synced)..'/'..copies(l)) or l)
  local t=trustView()
  if t then
   validTrust(tag,t)
   expect(t.lockedObserved==true and t.lockedAge==0 and t.lockedSynced==c[3] and t.lockedCopies==c[4]
    and c[5][t.lockedRejection]==true and c[6][t.lockedRawType]==true,
    tag..': the sample has the fixed rejection and the raw type class of that read',facts(t,LOCKED_SAMPLE))
  end
  local o=ownershipBlock(tag,prepared(),{'ZQ_'})
  if o then
   expect(o['locked.synced']==(c[3] and 'yes' or 'no') and o['locked.copies']==tostring(c[4]) and c[5][o['locked.rejection']]==true
    and c[6][o['locked.raw']]==true,tag..': the report shows them without the raw value',facts(o,LOCKED_KEYS))
  end
 end
 trusted()
end)

-- S6. A failing or corrupt accessor: the report is still prepared, the other block
-- and the existing Orb lines are still there, and nothing is guessed.
scenario('S6 failing or corrupt accessors',function()
 trusted()
 local realTrust,realView=A.OwnershipTrustView,Nexus.OrbRuntime.ReadinessView
 local evil=setmetatable({},{__tostring=function() error('ZQ_TOSTRING_MARKER') end})
 local corrupt={ownedObserved=true,ownedAt=0/0,ownedAge=-7,ownedSampledGeneration=2.5,ownedSampledConfirmed=1,
  ownedSynced='yes',ownedFresh={},ownedGhost=print,ownedDistinct=1e300,ownedTotal=-3,ownedGeneration=1/0,
  ownedConfirmed='true',ownedArmed=evil,ownedRetries=0/0,lockedObserved='true',lockedAt=evil,lockedAge=12345678,
  lockedSynced=evil,lockedCopies=-1,lockedRejection='ZQ_REJECTION_MARKER Disposable A 410001',
  lockedRawType='ZQ_RAW_TYPE_MARKER 410007'}
 for i=1,200 do corrupt['ZQjunk'..i]='ZQ_JUNK_MARKER Disposable A 410001' end
 local variants={
  {'missing',false,nil},
  {'throws',false,function() error('ZQ_TRUST_THROW_MARKER Disposable A 410001') end},
  {'not a table',false,function() return 'ZQ_TRUST_STRING_MARKER Disposable A 410001' end},
  {'raising index',false,function() return setmetatable({},{__index=function() error('ZQ_TRUST_INDEX_MARKER') end}) end},
  {'corrupt values',true,function() return corrupt end},
 }
 for _,v in ipairs(variants) do
  local tag='S6 trust '..v[1]
  A.OwnershipTrustView=v[3]
  local ok,text=pcall(prepared)
  A.OwnershipTrustView=realTrust
  if expect(ok,tag..': the report is still prepared',text) then
   expect(#lines(text,'Orb readiness')>0,tag..': the Orb readiness block is still present')
   local o=ownershipBlock(tag,text,{'ZQ_'})
   if o then
    local guessed={}
    for k,x in pairs(o) do
     if OWN_VALID[k] and not k:match('%.observed$') and NULL[x]~=true then guessed[#guessed+1]=k..'='..x end
    end
    table.sort(guessed)
    expect(#guessed==0,tag..': every fact is shown as unknown',table.concat(guessed,','))
    local ordinary=o['ordinary.observed']
    expect((NULL[ordinary]==true or (v[2] and ordinary=='yes')) and NULL[o['locked.observed']]==true,
     tag..': observed is shown only from a boolean answer, otherwise as unavailable',facts(o,{'ordinary.observed','locked.observed'}))
   end
  end
 end
 for _,v in ipairs({{'missing',nil},{'throws',function() error('ZQ_VIEW_THROW_MARKER Disposable A 410001') end}}) do
  local tag='S6 readiness '..v[1]
  Nexus.OrbRuntime.ReadinessView=v[2]
  local ok,text=pcall(prepared)
  Nexus.OrbRuntime.ReadinessView=realView
  if expect(ok,tag..': the report is still prepared',text) then
   local o=ownershipBlock(tag,text,{'ZQ_'})
   if o then
    expect(o['ordinary.observed']=='yes' and o['locked.observed']=='yes' and o['locked.synced']=='yes' and o['locked.rejection']=='none',
     tag..': the ownership block still shows both samples',facts(o,{'ordinary.observed','locked.observed','locked.synced','locked.rejection'}))
   end
  end
 end
 A.OwnershipTrustView=function() error('ZQ_TRUST_THROW_MARKER') end
 Nexus.OrbRuntime.ReadinessView=function() error('ZQ_VIEW_THROW_MARKER') end
 local ok,text=pcall(prepared)
 A.OwnershipTrustView,Nexus.OrbRuntime.ReadinessView=realTrust,realView
 if expect(ok,'S6 both fail: the report is still prepared',text) then
  local r=tokens(lines(text,'Orb readiness'))
  expect(r.observed=='unavailable' or r.observed=='unknown','S6 both fail: the Orb readiness block says readiness is unavailable',r.observed)
  local o=ownershipBlock('S6 both fail',text,{'ZQ_'})
  if o then
   expect(NULL[o['ordinary.observed']]==true and NULL[o['locked.observed']]==true,'S6 both fail: the ownership block says the samples are unavailable',
    facts(o,{'ordinary.observed','locked.observed'}))
  end
 end
end)

-- S7. One normal Orb window read, then later normal ownership reads: the Orb
-- observation keeps its own time and facts, and the report keeps the Orb
-- readiness block's keys apart from the newer ownership samples.
scenario('S7 the Orb observation keeps its own time',function()
 trusted()
 local okShow,errShow=pcall(function() Nexus.OrbPanel.Show();NexusOrbPanel:Hide() end)
 expect(okShow,'S7: fixture: one normal Orb window read',errShow)
 local T0=H.now
 local v0=readinessView()
 local r0=tokens(lines(prepared(),'Orb readiness'))
 H.now=H.now+50
 H.locked=locksWithSibling();A.LockedOwned()
 H.now=H.now+5
 A.Owned()
 local v1,why=readinessView()
 if expect(v0~=nil and v1~=nil,'S7: ReadinessView answers',why) then
  expect(v0.observed==true and v0.at==T0 and v1.at==T0 and v1.age==55,'S7: later ownership reads do not move the Orb observation time',
   facts(v1,{'observed','at','age'}))
  local moved={}
  for _,k in ipairs({'stage','assignment','progress','ownedSynced','ownedConfirmed','ownedGeneration','ownedTotal','lockedSynced',
   'lockedCopies','lockedRejection'}) do
   if v1[k]~=v0[k] then moved[#moved+1]=k end
  end
  expect(#moved==0,'S7: nor its observation-time facts',table.concat(moved,','))
 end
 local t,whyT=trustView()
 if expect(t~=nil,'S7: OwnershipTrustView answers',whyT) then
  expect(t.lockedAt==T0+50 and t.lockedAge==5 and t.lockedRejection=='invalid_value' and t.ownedAt==T0+55 and t.ownedAge==0,
   'S7: the ownership samples have the times and facts of the later reads',
   facts(t,{'lockedAt','lockedAge','lockedRejection','ownedAt','ownedAge'}))
 end
 local text=prepared()
 local r=lines(text,'Orb readiness')
 if expect(#r>0,'S7: the Orb readiness block is present') then
  local rt=tokens(r)
  local missing,moved={},{}
  for _,k in ipairs(READINESS_REQUIRED) do if rt[k]==nil then missing[#missing+1]=k end end
  for k,x in pairs(r0) do if k~='age' and rt[k]~=x then moved[#moved+1]=k end end
  table.sort(moved)
  expect(rt.observed=='yes' and #missing==0,'S7: the Orb readiness block keeps all its keys',
   printable(rt.observed)..' missing '..table.concat(missing,','))
  expect(ageValue(rt.age)==55 and #moved==0,'S7: with the age and facts of the Orb observation, not of the later reads',
   printable(rt.age)..' '..table.concat(moved,','))
 end
 local o=ownershipBlock('S7',text,{'ZQ_'})
 if o then
  expect(ageValue(o['locked.age'])==5 and ageValue(o['ordinary.age'])==0 and o['locked.rejection']=='invalid_value',
   'S7: the ownership block has the later samples',facts(o,{'locked.age','ordinary.age','locked.rejection'}))
 end
end)

-- S8. Level cap, non-repair reproduction. A valid lock projection becomes refused
-- while its recognized copies remain: EchoWeaver keeps its existing locked wait,
-- the HUD Wishlist progress lists every requested locked target as still to lock,
-- target intent and saved data stay unchanged and trust is not widened. The
-- diagnostics show the refusal beside the recognized count.
scenario('S8 level cap: a valid lock projection becomes refused',function()
 trusted()
 H.playerLevel=80
 local owned=A.Owned()
 expect(owned.synced==true,'S8: fixture: rolled ownership is trusted at the level cap',owned.synced)
 local cat=A.Catalog()
 local plan={requestedCounts={[410002]=1,[410007]=1,[200001]=1},lockedRequestedCounts={[410007]=1,[200001]=1},
  explicitRoles=true,wishedFamilies={},targets={}}
 local design={[410007]=true,[200001]=true}
 local intent,db0=serialize({plan=plan,design=design}),serialize(NexusDB)
 local VM=Nexus.MainInternals.ViewModel.New({ratchet=Nexus.Ratchet,model=Nexus.Model,wishlistModel=Nexus.WishlistModel.New()})
 local function decide(locked)
  return Nexus.EchoWeaver.DecideNexus({plan=plan,owned=owned,locked=locked,level=80,horizon=40,ordinaryBoardAllowed=true,
   board={cards={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}}},
   charges={banish=5,reroll=5,freeze=5,trustworthy=true},catalog=cat})
 end
 local function toLock(locked)
  local _,_,_,list=VM.WishlistProgress(plan,owned,cat,nil,locked,design,nil)
  return type(list)=='table' and list or {}
 end
 H.locked=locks()
 local valid=A.LockedOwned()
 expect(valid.synced==true and copies(valid)==3,'S8 valid: fixture: three recognized locks are trusted',tostring(valid.synced)..'/'..copies(valid))
 local okD1,d1=pcall(decide,valid)
 expect(okD1 and type(d1)=='table' and d1.reason~=WAIT_LOCKED,'S8 valid: EchoWeaver passes its locked gate',
  okD1 and type(d1)=='table' and (tostring(d1.type)..'/'..tostring(d1.reason)) or d1)
 local okL1,list1=pcall(toLock,valid)
 expect(okL1 and #list1==0,'S8 valid: the HUD Wishlist progress lists no requested locked target as still to lock',
  okL1 and table.concat(list1,',') or list1)
 H.locked=locksWithSibling()
 local refused=A.LockedOwned()
 expect(refused.synced==false and copies(refused)==3 and refused.bySpell[410007]==1 and refused.bySpell[200001]==1,
  'S8 refused: fixture: the strict reader keeps the recognized copies and does not widen trust',
  tostring(refused.synced)..'/'..copies(refused))
 local okD2,d2=pcall(decide,refused)
 expect(okD2 and type(d2)=='table' and d2.type=='wait' and d2.reason==WAIT_LOCKED,'S8 refused: EchoWeaver keeps its existing locked wait',
  okD2 and type(d2)=='table' and (tostring(d2.type)..'/'..tostring(d2.reason)) or d2)
 local okL2,list2=pcall(toLock,refused)
 expect(okL2 and #list2==2,'S8 refused: the HUD Wishlist progress conservatively lists every requested locked target as still to lock',
  okL2 and #list2 or list2)
 expect(serialize({plan=plan,design=design})==intent,'S8: the target intent is unchanged')
 expect(serialize(NexusDB)==db0,'S8: saved data, every Wishlist and design included, is unchanged')
 local t,why=trustView()
 if expect(t~=nil,'S8: OwnershipTrustView answers',why) then
  expect(t.lockedSynced==false and t.lockedCopies==3 and t.lockedRejection=='invalid_value' and t.ownedSynced==true,
   'S8: the samples show the refusal with its recognized copies, beside trusted rolled ownership',
   facts(t,{'lockedSynced','lockedCopies','lockedRejection','ownedSynced'}))
 end
 local o=ownershipBlock('S8',prepared(),{'ZQ_'})
 if o then
  expect(o['locked.synced']=='no' and o['locked.copies']=='3' and o['locked.rejection']=='invalid_value' and o['ordinary.synced']=='yes',
   'S8: the report shows the refused lock evidence apart from its recognized count',
   facts(o,{'locked.synced','locked.copies','locked.rejection','ordinary.synced'}))
 end
end)

if #failures>0 then
 error('ownership_passive_diagnostics: '..#failures..' of '..checks..' expectation(s) failed; first: '..failures[1],0)
end
print('PASS ownership_passive_diagnostics checks='..checks)
