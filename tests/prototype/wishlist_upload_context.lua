-- Issue #132 public-seam regression: an accepted Wishlist upload belongs to
-- the editor/Create context and the draft that authorized it. When a
-- synchronous host callback replaces that draft, the save reports partial
-- completion, assigns and commits nothing for the replacement, and uploads
-- nothing more.
-- Run from the trusted source root with LuaJIT:
--   luajit tests/prototype/wishlist_upload_context.lua [case]
-- No argument runs every case, each in a newly loaded synthetic host and
-- module world. A case that fails setup or raises is reported and the other
-- cases still run. Synthetic data only: no native client, private data,
-- network, provider or resource action. A pass does not show that the native
-- client reaches these callback sequences, nor that they caused the report.
--
-- Categories:
--   SETUP  the fixture reached the state it names (host window reached,
--          replacement admitted, token relation as intended). A failed SETUP
--          stops that case and is not behavior evidence.
--   EXPECT required behavior known to fail at 791cdcc by design: the
--          context-less equal-content replacement, and the partial notice
--          that names the uploaded Wishlist.
--   GUARD  behavior that already holds at 791cdcc and must keep holding.
-- Cases (every save goes through the real controller and GameAdapter):
--   no_switch            opened Wishlist A saved; nothing changes meanwhile
--   same_content         the callback opens Wishlist B, whose token equals A's
--   changed_content      the callback opens Wishlist B, whose token differs
--   native_only          the callback changes only the native active slot
--   create_no_switch     new plan, Create & assign to captured Saved Build 1
--   create_replaced      the callback begins an equal-content Copy: no editor
--                        context, Create context changed (Saved Build 1 to none)
--   first_run_no_switch  context-less Create & assign to the first-run target
--   contextless_replaced the callback begins an equal-content Copy: both
--                        contexts stay nil and the token is equal; only the
--                        draft identity differs
local T=dofile('tests/prototype/startup_support.lua')

local CASES={'no_switch','same_content','changed_content','native_only',
 'create_no_switch','create_replaced','first_run_no_switch','contextless_replaced'}
-- kind: what is saved. active: native active slot of the world. replace: what
-- the host callback begins. baseCaught: the replacement changes an editor or
-- Create context identity, which 791cdcc already reports.
local SPEC={
 no_switch={kind='opened',active=1},
 same_content={kind='opened',active=1,replace='opened',baseCaught=true},
 changed_content={kind='opened',active=1,replace='opened',baseCaught=true},
 native_only={kind='opened',active=1,native=true},
 create_no_switch={kind='create',active=1},
 create_replaced={kind='create',active=1,replace='copy',baseCaught=true},
 first_run_no_switch={kind='create',active=0},
 contextless_replaced={kind='create',active=0,replace='copy',baseCaught=false},
}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}
local PARTIAL='but the editor changed'
local ID,OTHER,THIRD,LOCK=201172,201175,201176,200767
-- What a successful save stores, traced from the real writers
-- (StoredWishlistRecord), stamped after the two fixture assignments.
local EXPECTED_OPENED={slot=101,name='Wishlist A',key='201172:2,201175:1',assignmentId='assigned:3',
 lockEvidenceVersion=1,designRows={{spellId=LOCK,stacks=1}},
 echoes={{spellId=ID,quality=0,stacks=2,locked=false},{spellId=OTHER,quality=0,stacks=1,locked=false}}}
local EXPECTED_CREATE={name='Plan C',key='201172:3,201176:1',assignmentId='assigned:3',
 lockEvidenceVersion=1,designRows={{spellId=LOCK,quality=0,stacks=1}},
 echoes={{spellId=ID,quality=0,stacks=3,locked=false},{spellId=THIRD,quality=0,stacks=1,locked=false}}}

local function quoted(value)
 return '"'..tostring(value):gsub('[%z\1-\31\\"]',function(c)
  if c=='"' then return '\\"' end
  if c=='\\' then return '\\\\' end
  return string.format('\\u%04x',string.byte(c))
 end)..'"'
end
-- Report emission only; every safety oracle uses T.Equal. Sparse or mixed
-- tables are emitted as objects with typed key labels, so no field is lost.
local function json(value,seen)
 local kind=type(value)
 if kind=='nil' then return 'null' end
 if kind=='string' then return quoted(value) end
 if kind=='boolean' then return tostring(value) end
 if kind=='number' then
  if value~=value or value==math.huge or value==-math.huge then return quoted(tostring(value)) end
  return tostring(value)
 end
 if kind~='table' then return quoted('<'..kind..'>') end
 seen=seen or {}
 if seen[value] then return quoted('<cycle>') end
 seen[value]=true
 local count,array=0,true
 for k in pairs(value)do
  count=count+1
  if type(k)~='number' or k<1 or k~=math.floor(k) then array=false end
 end
 if array then for i=1,count do if value[i]==nil then array=false;break end end end
 local fields={}
 if array and count>0 then
  for i=1,count do fields[i]=json(value[i],seen) end
  seen[value]=nil
  return '['..table.concat(fields,',')..']'
 end
 local keys={};for k in pairs(value)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)
  if type(a)~=type(b) then return type(a)<type(b) end
  if type(a)=='number' or type(a)=='string' then return a<b end
  return tostring(a)<tostring(b)
 end)
 for _,k in ipairs(keys)do
  local label=type(k)=='string' and k or ('['..type(k)..':'..tostring(k)..']')
  fields[#fields+1]=quoted(label)..':'..json(value[k],seen)
 end
 seen[value]=nil
 return '{'..table.concat(fields,',')..'}'
end
local function emit(kind,value) print(kind..'\t'..json(value)) end

local function ChangedKeys(before,after)
 local all,changed={},{}
 for k in pairs(before)do all[k]=true end
 for k in pairs(after)do all[k]=true end
 for k in pairs(all)do if not T.Equal(before[k],after[k]) then changed[#changed+1]=tostring(k) end end
 table.sort(changed)
 return changed
end
local function BySpell(rows)
 local out={}
 for i,row in ipairs(type(rows)=='table' and rows or {})do out[i]=row end
 table.sort(out,function(a,b) return (tonumber(a.spellId) or 0)<(tonumber(b.spellId) or 0) end)
 return out
end
-- One design bucket, for this content key, holding only the permanent target.
local function DesignBucketOK(buckets,key)
 if type(buckets)~='table' then return false end
 local n=0;for k in pairs(buckets)do n=n+1;if k~=key then return false end end
 local bucket=buckets[key]
 if n~=1 or type(bucket)~='table' then return false end
 local spells=0;for k in pairs(bucket)do spells=spells+1;if k~=LOCK then return false end end
 local v=bucket[LOCK]
 return spells==1 and type(v)=='table' and v.version==1 and v.copies==1 and type(v.rows)=='table'
  and #v.rows==1 and v.rows[1].spellId==LOCK and v.rows[1].stacks==1 and v.rows[1].quality==0
end
-- One role choice: Plan C's ordinary rows plus its one permanent target.
local function RoleChoiceOK(choices)
 if type(choices)~='table' or #choices~=1 then return false end
 local r=choices[1]
 return type(r)=='table' and r.version==1 and r.source=='user-confirmed'
  and r.signature=='200767:0:1,201172:0:3,201176:0:1'
  and T.Equal(BySpell(r.echoes),{{spellId=LOCK,quality=0,stacks=1,locked=true},
   {spellId=ID,quality=0,stacks=3,locked=false},{spellId=THIRD,quality=0,stacks=1,locked=false}})
end

local function run(which,report)
 local spec=SPEC[which]
 local function setup(v,label,observed)
  report.setup=report.setup+1
  emit('SETUP',{case=which,label=label,pass=v==true,observed=observed})
  if v~=true then error({setupFailure=label},0) end
 end
 local function check(category,v,label,observed)
  report[category]=report[category]+1
  emit(category:upper(),{case=which,label=label,pass=v==true,observed=observed})
  if v~=true then local list=report[category..'Failures'];list[#list+1]=label end
 end
 local function expect(v,label,observed) check('expect',v,label,observed) end
 local function guard(v,label,observed) check('guard',v,label,observed) end
 -- Holds at 791cdcc only where its context guard already sees the replacement.
 local function caught(v,label,observed) check(spec.baseCaught and 'guard' or 'expect',v,label,observed) end

 Nexus=nil;NexusDB={};WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 for _,spell in ipairs({ID,201174,OTHER,THIRD,LOCK})do H.AddEcho(spell,'Synthetic Echo '..spell,0,5)end
 local function ordinary(n)
  return {{spellId=ID,quality=0,stacks=n,locked=false},{spellId=OTHER,quality=0,stacks=1,locked=false}}
 end
 local bCount=which=='changed_content' and 3 or 2
 local originalA,originalB=ordinary(1),ordinary(bCount)
 local design={[LOCK]=true}
 -- One permanent locked record of the design's spell. Granted Echoes keep the
 -- harness default (an empty mirror); no case reads them.
 H.locked={{spellId=LOCK,stacks=1}}
 H.perks.serverActiveSlot=spec.active
 H.perks.serverBuildSlots={
  [1]={name='Saved A',verified=true,echoes={{spellId=201174,stacks=1,locked=false}}},
  [2]={name='Saved B',verified=true,echoes={{spellId=THIRD,stacks=1,locked=false}}},
  [101]={name='Wishlist A',verified=false,echoes=H.Clone(originalA)},
  [102]={name='Wishlist B',verified=false,echoes=H.Clone(originalB)},
 }
 local forbidden={spend=0,take=0,activate=0,save=0,sync=0,other=0}
 local function forbid(key)
  return function() forbidden[key]=forbidden[key]+1;error('FORBIDDEN_HOST_ACTION '..key) end
 end
 H.service.SelectPerk=forbid('take')
 H.service.ActivateServerBuildSlot=forbid('activate')
 H.service.SaveServerBuildSlot=forbid('save')
 for _,k in ipairs({'BanishPerk','FreezePerk','RequestReroll','LockPerk','UnlockPerk','ToggleTomeEcho'})do
  H.service[k]=forbid('other')
 end
 SendAddonMessage=forbid('sync');SendChatMessage=forbid('sync')
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
  GetCharges=function()return 0 end,IsOfferPending=function()return false end,
  RequestCharges=function()end,ConfirmSpend=forbid('spend')}
 -- Real modules only; no Main, AutomationRuntime or Sync boot jobs.
 Nexus={}
 for _,path in ipairs({'core/EchoCatalogSource.lua','logic/Model.lua','core/CandidateEvidence.lua',
  'core/WishlistModel.lua','core/GameAdapter.lua','core/WishlistController.lua'})do dofile(path) end
 local backing,settings,account={},{},{}
 local store={State=function()return backing end,Settings=function()return settings end}
 local A=Nexus.GameAdapter
 A.Init({},store)
 local okA,whyA=A.SetLoadoutWishlistIdentity(1,'Wishlist A',H.Clone(originalA),H.Clone(design))
 local okB,whyB=A.SetLoadoutWishlistIdentity(2,'Wishlist B',H.Clone(originalB),H.Clone(design))
 setup(okA==true and okB==true,'two real adapter assignment writes admitted',{A=whyA or 'accepted',B=whyB or 'accepted'})
 local messages={}
 local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=store,
  accountRoot=function()return account end,notify=function(t)messages[#messages+1]=tostring(t)end})
 c.Initialize(A)
 local function opened(slot,name,echoes,loadout)
  local saved=backing.loadoutWishlists[loadout]
  return {slot=slot,name=name,key=saved.key,assignmentId=saved.assignmentId,
   echoes=H.Clone(echoes),lockEvidenceVersion=1,designTargets=H.Clone(design)}
 end
 local WA=opened(101,'Wishlist A',originalA,1)
 local WB=opened(102,'Wishlist B',originalB,2)
 setup(A.IsLoadoutPopulated(1)==true and A.IsLoadoutPopulated(2)==true,'both captured destinations are populated')
 setup(A.ServerWishlistSlotToken(101)==A.ServerWishlistTokenFor(WA.name,WA.echoes)
  and A.ServerWishlistSlotToken(102)==A.ServerWishlistTokenFor(WB.name,WB.echoes),
  'both typed server Wishlist mirrors match their selected tokens')
 setup(c.LockedProjection()~=nil and c.LockedProjection().bySpell[LOCK]==1,
  'real locked projection admits one permanent copy')
 setup(A.Slots().activeSlot==spec.active,'the world starts on its native active slot',A.Slots().activeSlot)
 setup(Nexus.Sync==nil,'Sync runtime is not loaded')

 local function DraftView()
  local d=c.DebugDraftState()
  return {ordinary=H.Clone(c.CanonicalEchoes()),pending=d.pending,pendingLock=d.pendingLock,
   fulfilled=d.fulfilled,permanent=H.Clone(c.FulfilledDraftTargets()),lockRows=H.Clone(c.PendingLockRows())}
 end
 local function ReplacementView()
  return {draft=DraftView(),candidate=H.Clone(c.CandidateContext()),
   editing=H.Clone(c.EditingContext()),create=H.Clone(c.CreateTargetContext())}
 end

 local data,mode,uploadName,uploadSlot,expectedPayload,callbackAction,bView,copyView
 if spec.kind=='opened' then
  setup(c.BeginWishlist(WB,2)==true,'public BeginWishlist admits B before upload')
  setup(c.PendingTotal()==bCount+1,'B typed draft loaded its ordinary rows',
   {count=c.PendingTotal(),expected=bCount+1,messages=H.Clone(messages)})
  local dB,modeB=c.PrepareApply(nil,c.INTENT.SAVE_CHANGES)
  setup(type(dB)=='table' and modeB=='update','B confirmation has admitted draft',
   {mode=modeB,messages=H.Clone(messages)})
  local bToken=dB.confirmation.draftToken
  bView=DraftView()
  c.CancelApply(dB)
  setup(c.BeginWishlist(WA,1)==true,'public BeginWishlist admits A')
  local rowKey
  for k,row in pairs(c.PendingRows())do if row.spellId==ID then rowKey=k end end
  setup(rowKey~=nil,'ordinary A edit row exists')
  c.AdjustStacks(rowKey,1)
  data,mode=c.PrepareApply(nil,c.INTENT.SAVE_CHANGES)
  setup(type(data)=='table' and mode=='update' and data.slot==101 and data.name=='Wishlist A',
   'A confirmation captures original upload identity')
  expectedPayload={{spellId=ID,quality=0,stacks=2},{spellId=OTHER,quality=0,stacks=1}}
  setup(T.Equal(data.echoes,expectedPayload),'A ordinary payload is edited before confirmation',data.echoes)
  setup(c.DebugDraftState().fulfilled==1,'A draft retains one fulfilled permanent target')
  local equal=which~='changed_content'
  setup((data.confirmation.draftToken==bToken)==equal,
   'A and replacement B serialized public confirmation tokens have intended relation',
   {equal=data.confirmation.draftToken==bToken,A=data.confirmation.draftToken,B=bToken})
  uploadName,uploadSlot='Wishlist A',101
  if spec.replace=='opened' then
   callbackAction=function(callback)
    callback.opened=c.BeginWishlist(WB,2)
    callback.full=ReplacementView()
   end
  elseif spec.native then
   callbackAction=function() H.perks.serverActiveSlot=2;H.Notify();A.Poll() end
  end
 else
  local planRows={{spellId=ID,quality=0,stacks=3,locked=false},
   {spellId=THIRD,quality=0,stacks=1,locked=false},{spellId=LOCK,quality=0,stacks=1,locked=true}}
  local function Copy()
   return Nexus.CandidateEvidence.Build({sourceIdentity='synthetic-copy-132',
    sourceRevision='synthetic-rev-1',title='Plan C',
    ordinaryEchoes={{spellId=ID,quality=0,stacks=3},{spellId=THIRD,quality=0,stacks=1}},
    lockedEchoes={{spellId=LOCK,quality=0,stacks=1}}})
  end
  local copyToken
  if spec.replace=='copy' then
   local candidate,why=Copy()
   setup(type(candidate)=='table','synthetic Copy evidence builds',why)
   local title=c.BeginCandidate(candidate)
   setup(title=='Plan C','public Copy (BeginCandidate) admits the replacement draft before upload',title)
   local dCopy,modeCopy=c.PrepareApply(title)
   setup(type(dCopy)=='table' and modeCopy=='create','Copy confirmation has an admitted draft',
    {mode=modeCopy,messages=H.Clone(messages)})
   copyToken,copyView=dCopy.confirmation.draftToken,DraftView()
   c.CancelApply(dCopy)
  end
  local okImport,importName,importCount,importWhy=c.LoadImported(
   {entries=H.Clone(planRows),name='Plan C',class='MAGE'},'Plan C')
  setup(okImport==true and importName=='Plan C' and importCount==3,
   'public Import (LoadImported) admits the Create draft',{why=importWhy})
  setup(c.EditingContext()==nil and c.CandidateContext()==nil,'the Create draft has no editor or Copy context')
  local target=c.CreateTargetContext()
  if spec.active==1 then
   setup(type(target)=='table' and target.loadoutSlot==1,'the Create draft captured populated Saved Build 1',target)
  else
   setup(target==nil,'the Create draft captured no Saved Build (context-less first run)',target)
  end
  data,mode=c.PrepareApply('Plan C',c.INTENT.SAVE_AND_ASSIGN)
  setup(type(data)=='table' and mode=='create' and data.slot==0 and data.name=='Plan C',
   'Create & assign confirmation captures the create sentinel and name',{mode=mode,messages=H.Clone(messages)})
  expectedPayload={{spellId=ID,quality=0,stacks=3},{spellId=THIRD,quality=0,stacks=1}}
  setup(T.Equal(data.echoes,expectedPayload),'the Create ordinary payload is the imported plan',data.echoes)
  local d=c.DebugDraftState()
  setup(d.fulfilled==1 and d.pendingLock==0,'the permanent target is a fulfilled design outside the payload',d)
  local destination=data.destination or {}
  if spec.active==1 then
   setup(destination.kind=='savedBuild' and destination.slot==1,'the confirmation names Saved Build 1',destination)
  else
   setup(destination.kind=='firstRun','the confirmation names the first-run target',destination)
  end
  if spec.replace=='copy' then
   setup(data.confirmation.draftToken==copyToken and T.Equal(DraftView(),copyView),
    'the original Create and the replacement Copy have equal draft contents and serialized tokens',
    {create=data.confirmation.draftToken,copy=copyToken})
   callbackAction=function(callback)
    callback.title=c.BeginCandidate(Copy())
    callback.full=ReplacementView()
   end
  end
  uploadName,uploadSlot='Plan C',0
 end

 -- Every call of the eight assignment writer APIs during the save, the host
 -- callback included, counted at the top level (fixture writes came before).
 local writes={}
 for _,fn in ipairs(WRITERS)do
  local real=A[fn]
  setup(type(real)=='function','writer API present: '..fn)
  A[fn]=function(...)
   local call={fn=fn,args=H.Clone({...})}
   writes[#writes+1]=call
   local r1,r2,r3,r4,r5=real(...)
   call.ok,call.reason=r1,r2
   return r1,r2,r3,r4,r5
  end
 end
 local callback={ran=false}
 local host=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function(...)
  local accepted=host(...)
  callback.ran,callback.hostAccepted=true,accepted==true
  if callbackAction then
   local okCall,callError=pcall(callbackAction,callback)
   if not okCall then callback.error=tostring(callError) end
  end
  return accepted
 end
 local before=H.Clone(backing)
 local mark=#messages
 local accepted,reason=c.AcceptApply(data)
 local after=H.Clone(backing)
 local uploads={}
 for _,action in ipairs(H.actions)do if action[1]=='upload' then uploads[#uploads+1]=H.Clone(action) end end
 local saveNotices,partial={},{}
 for i=mark+1,#messages do
  saveNotices[#saveNotices+1]=messages[i]
  if messages[i]:find(PARTIAL,1,true) then partial[#partial+1]=messages[i] end
 end
 local result=c.SaveResult()
 local afterView=ReplacementView()
 emit('OBSERVED',{case=which,accepted=accepted==true,reason=reason,callback=callback,uploads=uploads,
  writes=writes,before=before,after=after,result=result,afterView=afterView,
  nativeActiveSlot=A.Slots().activeSlot,forbidden=forbidden,notices=saveNotices})

 -- A callback that was not reached or not admitted is a setup failure.
 setup(callback.ran==true and callback.hostAccepted==true,'the host accepted the upload and its callback boundary was reached')
 setup(callback.error==nil,'the host callback ran without error',callback.error)
 if spec.replace=='opened' then
  local editing=callback.full and callback.full.editing
  setup(callback.opened==true and type(editing)=='table' and editing.loadoutSlot==2 and editing.slot==102,
   'replacement B is an admitted public editor context during the host callback',editing)
  setup(T.Equal(callback.full.draft,bView),'the callback B projection equals its prechecked token input')
 elseif spec.replace=='copy' then
  local full=callback.full or {}
  setup(callback.title=='Plan C' and full.editing==nil and full.create==nil
   and type(full.candidate)=='table' and full.candidate.sourceIdentity=='synthetic-copy-132',
   'the replacement Copy is admitted during the host callback with no editor or Create context',full)
  setup(T.Equal(full.draft,copyView),'the callback Copy projection equals its prechecked token input')
 end

 guard(#uploads==1 and uploads[1][2]==uploadSlot and uploads[1][3]==uploadName
  and T.Equal(uploads[1][4],expectedPayload),
  'exactly one host upload: original slot and name, exact ordinary rows, no extra or permanent rows',uploads)
 guard(T.Equal((before.loadoutWishlists or {})[2],(after.loadoutWishlists or {})[2]),
  'the upload never changes the Saved Build 2 assignment')
 local zero=true;for _,n in pairs(forbidden)do if n~=0 then zero=false end end
 guard(zero,'zero spend, Take, activation, native Save, Sync or other gameplay calls',forbidden)
 guard(A.Slots().activeSlot==(spec.native and 2 or spec.active),
  'the native active slot keeps its independent state',A.Slots().activeSlot)
 guard(c.IsApplyPending()==false,'no save retry remains')

 if spec.replace then
  caught(accepted==false and reason=='uploaded_draft_changed',
   'the replaced draft is reported as partial (uploaded_draft_changed)',{accepted=accepted,reason=reason})
  caught(#writes==0,'no call to any of the eight assignment writer APIs',writes)
  caught(T.Equal(before,after),'the whole store is unchanged: every Saved Build, first-run and design bucket')
  caught(#partial==1,'exactly one partial notice',saveNotices)
  expect(#partial==1 and partial[1]:find("'"..uploadName.."' was uploaded",1,true)~=nil,
   'the partial notice names the uploaded Wishlist',saveNotices)
  caught(T.Equal(callback.full,afterView),
   'the original save leaves the replacement draft, its permanent targets, Copy evidence and contexts as admitted',
   {callback=callback.full,after=afterView})
  caught(result==nil,'no result of the original save is shown on the replacement editor',result)
  if spec.kind=='create' then
   local sent=c.SentDraft()
   caught(sent==nil,'the replacement draft is not marked as already sent',sent)
   H.now=H.now+3.1
   local d2,m2=c.PrepareApply('Plan C')
   caught(type(d2)=='table' and m2=='create',
    'the explicit replacement Create is admitted, not refused as already created',{mode=m2})
   if type(d2)=='table' then c.CancelApply(d2) end
   local n=0;for _,action in ipairs(H.actions)do if action[1]=='upload' then n=n+1 end end
   guard(n==1,'admitting the replacement uploads nothing',n)
  end
 else
  guard(accepted==true and reason==nil,'the unchanged-context save succeeds',{accepted=accepted,reason=reason})
  guard(#partial==0,'no partial notice',saveNotices)
  local writer,destination
  if spec.kind=='opened' then writer,destination='UpdateWishlistAssociationAfterSave',1
  elseif spec.active==1 then writer,destination='SetLoadoutWishlistIdentity',1
  else writer='SetFirstLoadoutWishlistIdentity' end
  guard(#writes==1 and writes[1].fn==writer and writes[1].ok==true
   and (destination==nil or writes[1].args[1]==destination),
   'exactly one writer call in total: '..writer..(destination and ' for Saved Build 1' or ' (first run)'),writes)
  local expectedKeys
  if spec.kind=='opened' then
   expectedKeys={'loadoutWishlists','lockDesignTargetsBySlot','wishlistAssignmentSerial'}
  elseif spec.active==1 then
   expectedKeys={'loadoutWishlists','lockDesignTargetsBySlot','wishlistAssignmentSerial','wishlistRoleChoices'}
  else
   expectedKeys={'firstRunWishlist','lockDesignTargetsBySlot','wishlistAssignmentSerial','wishlistRoleChoices'}
  end
  table.sort(expectedKeys)
  local changed=ChangedKeys(before,after)
  guard(T.Equal(changed,expectedKeys),'exactly the expected store keys change',changed)
  guard(after.wishlistAssignmentSerial==3,'one new assignment stamp',after.wishlistAssignmentSerial)
  local beforeLinks,afterLinks=before.loadoutWishlists or {},after.loadoutWishlists or {}
  if spec.kind=='opened' then
   guard(T.Equal(afterLinks[1],EXPECTED_OPENED),
    'Saved Build 1 holds exactly edited Wishlist A: original slot and name, exact ordinary rows, separate permanent design',afterLinks[1])
   guard(type(writes[1])=='table' and type(writes[1].args[5])=='table' and writes[1].args[5][LOCK]==true,
    'the writer receives the separate permanent design')
   guard(after.firstRunWishlist==nil,'no first-run target appears')
   guard(T.Equal(after.lockDesignTargetsBySlot,{[EXPECTED_OPENED.key]={[LOCK]=true}}),
    'one design bucket for the saved contents, holding only the permanent target',after.lockDesignTargetsBySlot)
  else
   local record
   if spec.active==1 then
    record=afterLinks[1]
    guard(after.firstRunWishlist==nil,'no first-run target appears')
   else
    record=after.firstRunWishlist
    guard(T.Equal(beforeLinks,afterLinks),'every Saved Build assignment is unchanged (no slot-1 handoff over an assignment)')
   end
   guard(T.Equal(record,EXPECTED_CREATE),
    'the destination holds exactly Plan C: exact ordinary rows, separate permanent design',record)
   guard(DesignBucketOK(after.lockDesignTargetsBySlot,EXPECTED_CREATE.key),
    'one design bucket for Plan C holding only the permanent target',after.lockDesignTargetsBySlot)
   guard(RoleChoiceOK(after.wishlistRoleChoices),
    'one role choice: Plan C ordinary rows and its one permanent target',after.wishlistRoleChoices)
  end
  local kind=(spec.kind=='create' and spec.active==0) and 'firstRun' or 'assigned'
  guard(type(result)=='table' and result.kind==kind,'the save result names the assignment that was written',result)
  if spec.kind=='create' then
   local sent=c.SentDraft()
   guard(sent=='Plan C','the created draft is marked as sent',sent)
   H.now=H.now+3.1
   local d2,m2=c.PrepareApply('Plan C')
   guard(d2==nil and m2=='already_created','pressing Create again for the created draft is refused',{mode=m2})
   local n=0;for _,action in ipairs(H.actions)do if action[1]=='upload' then n=n+1 end end
   guard(n==1,'the repeated Create uploads nothing',n)
  end
 end
end

local function runCase(which)
 local report={setup=0,expect=0,guard=0,expectFailures={},guardFailures={}}
 local ok,err=xpcall(function() run(which,report) end,function(e)
  if type(e)=='table' and e.setupFailure then return e end
  return debug.traceback(tostring(e),2)
 end)
 local status
 if not ok and type(err)=='table' then status='SETUP_FAILED'
 elseif not ok then status='RAISED'
 elseif #report.guardFailures>0 then status='GUARD_FAILED'
 elseif #report.expectFailures>0 then status='EXPECT_RED'
 else status='PASS' end
 emit('CASE_RESULT',{case=which,status=status,setupChecks=report.setup,expectChecks=report.expect,
  guardChecks=report.guard,expectFailures=report.expectFailures,guardFailures=report.guardFailures,
  setupFailure=type(err)=='table' and err.setupFailure or nil,
  error=(not ok and type(err)~='table') and err or nil})
 return status
end

local selected=arg and arg[1]
local cases=CASES
if selected then
 assert(SPEC[selected],'unknown case '..tostring(selected))
 cases={selected}
end
local byStatus,order={},{'PASS','EXPECT_RED','GUARD_FAILED','SETUP_FAILED','RAISED'}
for _,which in ipairs(cases)do
 local status=runCase(which)
 byStatus[status]=byStatus[status] or {}
 local list=byStatus[status];list[#list+1]=which
end
local parts,failed={},false
for _,status in ipairs(order)do
 if byStatus[status] then
  parts[#parts+1]=status..'='..table.concat(byStatus[status],',')
  if status~='PASS' then failed=true end
 end
end
print('SUMMARY wishlist_upload_context '..table.concat(parts,' '))
if failed then
 error('wishlist_upload_context: '..table.concat(parts,' ')
  ..' (SETUP_FAILED and RAISED are not behavior evidence)',0)
end
