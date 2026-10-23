-- Public-seam regression: an upload belongs to the editor that authorized it.
-- External fixture. Run from the immutable trusted source root with LuaJIT:
--   luajit <fixture> [no_switch|same_content|changed_content|native_only]
-- No argument runs all four with newly loaded synthetic host/module worlds.
-- No native client, private data, network, provider or resource action.
local CASES = {'no_switch','same_content','changed_content','native_only'}

local function quoted(value)
 return '"'..tostring(value):gsub('[%z\1-\31\\"]',function(c)
  if c=='"' then return '\\"' end
  if c=='\\' then return '\\\\' end
  return string.format('\\u%04x',string.byte(c))
 end)..'"'
end
local function json(value)
 local kind=type(value)
 if kind=='nil' then return 'null' end
 if kind=='string' then return quoted(value) end
 if kind=='number' or kind=='boolean' then return tostring(value) end
 assert(kind=='table','fixture JSON received '..kind)
 local n,count=0,0
 for k in pairs(value) do
  count=count+1
  if type(k)=='number' and k>=1 and k==math.floor(k) then n=math.max(n,k) else n=-math.huge end
 end
 local fields={}
 if count>0 and n==count then
  for i=1,n do fields[#fields+1]=json(value[i]) end
  return '['..table.concat(fields,',')..']'
 end
 local keys={};for k in pairs(value) do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
 for _,k in ipairs(keys)do fields[#fields+1]=quoted(k)..':'..json(value[k])end
 return '{'..table.concat(fields,',')..'}'
end
local function emit(kind,value) print(kind..'\t'..json(value)) end
local function same(a,b) return json(a)==json(b) end
local function copies(row,id)
 local count=0
 for _,e in ipairs(type(row)=='table' and row.echoes or {})do
  if e.spellId==id and e.locked~=true then count=count+(e.stacks or 1)end
 end
 return count
end
local function permanentCopies(row,id)
 local count=0
 for _,e in ipairs(type(row)=='table' and row.designRows or {})do
  if e.spellId==id then count=count+(e.stacks or 1)end
 end
 return count
end

local function run(which)
 local setupChecks,checks,failures=0,0,{}
 local function setup(v,label,observed)
  setupChecks=setupChecks+1
  emit('SETUP',{case=which,label=label,pass=v==true,observed=observed})
  assert(v==true,'SETUP_FAILURE '..which..': '..label)
 end
 local function expect(v,label,observed)
  checks=checks+1
  emit('EXPECT',{case=which,label=label,pass=v==true,observed=observed})
  if v~=true then failures[#failures+1]=label end
 end
 Nexus=nil;NexusDB={};WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 for _,id in ipairs({201172,201175,201174,201176,200767}) do
  H.AddEcho(id,'Synthetic Echo '..id,0,5)
 end
 local id,other,lock=201172,201175,200767
 local function ordinary(n)
  return {{spellId=id,quality=0,stacks=n,locked=false},
          {spellId=other,quality=0,stacks=1,locked=false}}
 end
 local originalA=ordinary(1)
 local bCount=which=='changed_content' and 3 or 2
 local originalB=ordinary(bCount)
 local design={[lock]=true}
 H.locked={{spellId=lock,stacks=1}}
 H.granted={{spellId=id,stacks=2},{spellId=other,stacks=1}}
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={
  [1]={name='Saved A',verified=true,echoes={{spellId=201174,stacks=1,locked=false}}},
  [2]={name='Saved B',verified=true,echoes={{spellId=201176,stacks=1,locked=false}}},
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
 -- Load real modules only; no Main, AutomationRuntime or Sync boot jobs.
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
  accountRoot=function()return account end,notify=function(t)messages[#messages+1]=t end})
 c.Initialize(A)
 local function opened(slot,name,echoes,loadout)
  local saved=backing.loadoutWishlists[loadout]
  return {slot=slot,name=name,key=saved.key,assignmentId=saved.assignmentId,
   echoes=H.Clone(echoes),lockEvidenceVersion=1,designTargets=H.Clone(design)}
 end
 local WA=opened(101,'Wishlist A',originalA,1)
 local WB=opened(102,'Wishlist B',originalB,2)
 setup(A.IsLoadoutPopulated(1)==true and A.IsLoadoutPopulated(2)==true,
  'both captured destinations are populated')
 setup(A.ServerWishlistSlotToken(101)==A.ServerWishlistTokenFor(WA.name,WA.echoes)
  and A.ServerWishlistSlotToken(102)==A.ServerWishlistTokenFor(WB.name,WB.echoes),
  'both typed server Wishlist mirrors match their selected tokens')
 setup(c.LockedProjection()~=nil and c.LockedProjection().bySpell[lock]==1,
  'real locked projection admits one permanent copy')
 setup(c.BeginWishlist(WB,2)==true,'public BeginWishlist admits B before upload')
 setup(c.PendingTotal()==bCount+1,'B typed draft loaded its ordinary rows',
  {count=c.PendingTotal(),expected=bCount+1,messages=H.Clone(messages)})
 local dB,modeB=c.PrepareApply(nil,c.INTENT.SAVE_CHANGES)
 setup(type(dB)=='table' and modeB=='update','B confirmation has admitted draft',
  {mode=modeB,messages=H.Clone(messages)})
 local bToken=dB.confirmation.draftToken
 local bView={ordinary=H.Clone(c.CanonicalEchoes()),draft=c.DebugDraftState(),
  permanent=H.Clone(c.FulfilledDraftTargets()),pendingLock=H.Clone(c.PendingLockRows())}
 c.CancelApply(dB)
 setup(c.BeginWishlist(WA,1)==true,'public BeginWishlist admits A')
 local rowKey
 for k,row in pairs(c.PendingRows())do if row.spellId==id then rowKey=k end end
 setup(rowKey~=nil,'ordinary A edit row exists')
 c.AdjustStacks(rowKey,1)
 local data,mode=c.PrepareApply(nil,c.INTENT.SAVE_CHANGES)
 setup(type(data)=='table' and mode=='update' and data.slot==101 and data.name=='Wishlist A',
  'A confirmation captures original upload identity')
 setup(copies({echoes=data.echoes},id)==2 and copies({echoes=data.echoes},other)==1,
  'A ordinary payload is edited before confirmation',data.echoes)
 setup(c.DebugDraftState().fulfilled==1,'A draft retains one fulfilled permanent target')
 local expectedEqual=which~='changed_content'
 setup((data.confirmation.draftToken==bToken)==expectedEqual,
  'A and replacement B serialized public confirmation tokens have intended relation',
  {equal=data.confirmation.draftToken==bToken,A=data.confirmation.draftToken,B=bToken})
 setup(Nexus.Sync==nil,'Sync runtime is not loaded')
 local before=H.Clone(backing)
 local beforeA,beforeB=H.Clone(backing.loadoutWishlists[1]),H.Clone(backing.loadoutWishlists[2])
 local writes={}
 local realWriter=A.UpdateWishlistAssociationAfterSave
 A.UpdateWishlistAssociationAfterSave=function(destination,slot,name,echoes,targets,binding)
  writes[#writes+1]={destination=destination,slot=slot,name=name,echoes=H.Clone(echoes),
   targets=H.Clone(targets),binding=H.Clone(binding)}
  return realWriter(destination,slot,name,echoes,targets,binding)
 end
 local callback={ran=false}
 local host=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function(...)
  local accepted=host(...)
  callback.ran=true
  if which=='same_content' or which=='changed_content' then
   callback.opened=c.BeginWishlist(WB,2)
   callback.context=c.EditingContext()
   callback.view={ordinary=H.Clone(c.CanonicalEchoes()),draft=c.DebugDraftState(),
    permanent=H.Clone(c.FulfilledDraftTargets()),pendingLock=H.Clone(c.PendingLockRows())}
   -- The same public draft projection seen when B's token was established.
   callback.projectionMatchesPrecheckedB=same(callback.view,bView)
  elseif which=='native_only' then
   H.perks.serverActiveSlot=2;H.Notify();A.Poll()
  end
  return accepted
 end
 local accepted,reason=c.AcceptApply(data)
 local after=H.Clone(backing)
 local afterA,afterB=H.Clone(backing.loadoutWishlists[1]),H.Clone(backing.loadoutWishlists[2])
 local uploads={}
 for _,action in ipairs(H.actions)do if action[1]=='upload' then uploads[#uploads+1]=H.Clone(action)end end
 local result=c.SaveResult()
 local observed={case=which,accepted=accepted==true,reason=reason,callback=callback,uploads=uploads,writes=writes,
  before={A=beforeA,B=beforeB,design=before.lockDesignTargetsBySlot},
  after={A=afterA,B=afterB,design=after.lockDesignTargetsBySlot},result=result,
  finalContext=c.EditingContext(),nativeActiveSlot=A.Slots().activeSlot,forbidden=forbidden,messages=messages}
 emit('OBSERVED',observed)
 -- A callback not reached/admitted is a setup failure, never product RED.
 setup(callback.ran==true,'host accepted exactly the intended callback boundary')
 if which=='same_content' or which=='changed_content' then
  setup(callback.opened==true and callback.context.loadoutSlot==2 and callback.context.slot==102,
   'replacement B is a valid admitted public context during host callback',callback.context)
  setup(callback.projectionMatchesPrecheckedB==true,'callback B projection equals its prechecked token input')
 end
 expect(#uploads==1 and uploads[1][2]==101 and uploads[1][3]=='Wishlist A'
  and copies({echoes=uploads[1][4]},id)==2 and copies({echoes=uploads[1][4]},other)==1,
  'exactly one original A-slot/name/ordinary-payload host upload',uploads)
 expect(same(beforeB,afterB),'A upload never mutates B assignment',{before=beforeB,after=afterB})
 local cross=0;for _,w in ipairs(writes)do if w.destination==2 then cross=cross+1 end end
 expect(cross==0,'A upload never invokes B assignment writer',writes)
 if which=='no_switch' or which=='native_only' then
  expect(accepted==true,'unchanged context save succeeds')
  expect(#writes==1 and writes[1].destination==1,'unchanged context writes captured A only',writes)
  expect(afterA.name=='Wishlist A' and afterA.slot==101 and copies(afterA,id)==2,
   'captured A gets the edited ordinary assignment',afterA)
  expect(permanentCopies(afterA,lock)==1 and writes[1].targets[lock]==true,
   'captured A retains its separate permanent target',
   {storedDesignRows=afterA.designRows,writerTargets=writes[1].targets})
  local expectedNative=which=='native_only' and 2 or 1
  expect(A.Slots().activeSlot==expectedNative,'native slot keeps its independent state',A.Slots().activeSlot)
 elseif which=='changed_content' then
  expect(accepted==false and #writes==0,'changed-content context swap is partial with no assignment writer',
   {accepted=accepted,reason=reason,writes=writes})
  expect(same(beforeA,afterA),'changed-content swap preserves A assignment')
  expect(same(before.lockDesignTargetsBySlot,after.lockDesignTargetsBySlot),
   'changed-content swap commits no permanent design')
 else
  -- No arbitrary reason contract: a future fix may refuse opening or stop the
  -- post-upload commit. The safety oracle is original destination isolation.
  expect(same(beforeA,afterA) or (afterA.name=='Wishlist A' and copies(afterA,id)==2),
   'same-content swap cannot replace A with an unrelated plan',afterA)
 end
 local zero=true;for _,n in pairs(forbidden)do if n~=0 then zero=false end end
 expect(zero,'zero spend Take activation native-Save Sync or other gameplay calls',forbidden)
 emit('CASE_RESULT',{case=which,setupChecks=setupChecks,checks=checks,failures=failures,
  status=#failures==0 and 'PASS' or 'BEHAVIOR_RED'})
 return #failures==0
end

local selected=arg and arg[1]
if selected then
 local known=false;for _,which in ipairs(CASES)do if selected==which then known=true end end
 assert(known,'unknown case '..tostring(selected))
 if not run(selected)then error('BEHAVIOR_RED '..selected,0)end
else
 local failed={}
 for _,which in ipairs(CASES)do if not run(which)then failed[#failed+1]=which end end
 if #failed>0 then error('BEHAVIOR_RED '..table.concat(failed,','),0)end
end
