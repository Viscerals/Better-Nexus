-- Issue #132 public-seam regression: an accepted Wishlist upload belongs to
-- the editor/Create context and the draft that authorized it. When a
-- synchronous host callback replaces that draft, the save reports partial
-- completion, assigns and commits nothing for the replacement, and uploads
-- nothing more. When the host then raises, the real GameAdapter reports
-- host_error and the save binds nothing to the replacement either.
-- Run from the trusted source root with LuaJIT:
--   luajit tests/prototype/wishlist_upload_context.lua [case]
-- No argument runs every case, each in a newly loaded synthetic host and
-- module world. A case that fails setup or raises is reported and the other
-- cases still run. Synthetic data only: no native client, private data,
-- network, provider or resource action. A pass does not show that the native
-- client reaches these callback sequences, nor that they caused the report.
--
-- Categories are pinned to the fixed public base bc5f495 (accepted main),
-- whose bc5f495:core/WishlistController.lua compares only the confirmed draft
-- token after an accepted upload. EXPECT and GUARD follow the bc5f495
-- comparison model defined below:
--   SETUP  the fixture reached the state it names (host window reached,
--          replacement admitted, token relation as intended, the deliberate
--          host raise happened). A failed SETUP stops that case and is not
--          behavior evidence.
--   EXPECT required behavior predicted to fail in the bc5f495 comparison
--          model.
--   GUARD  behavior predicted to hold in the bc5f495 comparison model; it
--          must keep holding.
-- Every EXPECT and GUARD event carries `predicted`, one column per name. For
-- the fixed base bc5f495 and the historical comparison identities a43cf27
-- (the branch point of this fix, also token-only), 791cdcc (which added the
-- editor/Create context check) and 9c60456 (which added the draft identity,
-- before this revision's partial-notice wording), the column is the outcome
-- predicted for that name's comparison model: the Controller at that exact
-- commit (<name>:core/WishlistController.lua), considered together with the
-- supporting modules and harness this current fixture loads (GameAdapter,
-- WishlistModel, CandidateEvidence and the others). A comparison model is
-- not a checkout: it claims nothing about the other files of any of those
-- commits, nor that they equal the current ones. The `successor` column is
-- `hold` throughout: the required outcome, not a claim that any run produced
-- it. Predictions are not executions. Only an actual run is evidence, and
-- only for the tree it ran on, whose identity the host must record; the
-- output of one tree is never evidence for another.
-- With NEXUS_UPLOAD_CONTEXT_BASELINE set to one of those names (or
-- `successor`), each event also says whether the observed outcome of this run
-- agrees with that name's column, and one ADJUDICATION line gives the name's
-- role and lists the disagreements. The name only selects a prediction
-- column; it neither identifies nor relabels the tree that ran. For a
-- recognized name, case statuses, the SUMMARY line and the exit are the same
-- as without it, so an agreement never stands in for a failure; any other
-- non-empty value fails the baseline assert before a case runs.
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
--   contextless_host_error as contextless_replaced, then the real host wrapper
--                        raises after the accepted upload and the callback
local T=dofile('tests/prototype/startup_support.lua')

local CASES={'no_switch','same_content','changed_content','native_only',
 'create_no_switch','create_replaced','first_run_no_switch','contextless_replaced',
 'contextless_host_error'}
-- kind: what is saved. active: native active slot of the world. replace: what
-- the host callback begins. native: the callback changes only the native
-- active slot. raise: the host raises after the accepted upload and the
-- callback.
local SPEC={
 no_switch={kind='opened',active=1},
 same_content={kind='opened',active=1,replace='opened'},
 changed_content={kind='opened',active=1,replace='opened'},
 native_only={kind='opened',active=1,native=true},
 create_no_switch={kind='create',active=1},
 create_replaced={kind='create',active=1,replace='copy'},
 first_run_no_switch={kind='create',active=0},
 contextless_replaced={kind='create',active=0,replace='copy'},
 contextless_host_error={kind='create',active=0,replace='copy',raise=true},
}

-- The baselines the predictions name, each standing for its comparison model
-- (see the header), not a checkout. BASE is the fixed public base bc5f495
-- (accepted main). BRANCH a43cf27 (the branch point of this fix), MID 791cdcc
-- (the intermediate context check) and PRIOR 9c60456 (the frozen
-- draft-identity source) are historical comparison identities only.
local BASE,BRANCH,MID,PRIOR='bc5f495','a43cf27','791cdcc','9c60456'
local BASELINES={BASE,BRANCH,MID,PRIOR}
-- The meaning of each adjudication name, reported on the ADJUDICATION line.
local ROLE={[BASE]='fixed public base',[BRANCH]='historical branch point',
 [MID]='historical intermediate',[PRIOR]='historical intermediate',successor='successor'}
local HOLDS={}
-- FAILS_BASE: both token-only Controllers (bc5f495 and a43cf27).
-- FAILS_BASE_MID: those and 791cdcc. FAILS_BEFORE_SUCCESSOR: every baseline.
local FAILS_BASE={[BASE]=true,[BRANCH]=true}
local FAILS_BASE_MID={[BASE]=true,[BRANCH]=true,[MID]=true}
local FAILS_BEFORE_SUCCESSOR={[BASE]=true,[BRANCH]=true,[MID]=true,[PRIOR]=true}
-- Checks predicted to fail at some baseline; every other check is predicted
-- to hold at every baseline. Each prediction is for that baseline's
-- comparison model: its own core/WishlistController.lua, cited per commit
-- below, considered together with the supporting modules this current
-- fixture loads. No other module at any baseline commit was compared, and no
-- equality of those modules with the current ones is claimed.
--  * bc5f495 and a43cf27 compare only the confirmed draft token after the
--    upload (bc5f495:core/WishlistController.lua and
--    a43cf27:core/WishlistController.lua, each read at its own commit). An
--    equal-content replacement passes it, so the original save commits its
--    design bucket (and, for a Copy, role choices), clears a Copy's evidence
--    and runs the writer the replacement's context selects: same_content
--    rewrites Saved Build 2 (UpdateWishlistAssociationAfterSave) and rebinds
--    B's editor; create_replaced runs no writer (its Create context is gone)
--    and reports a saved-unassigned success; contextless_replaced runs the
--    first-run writer. changed_content fails the token test and is partial.
--  * 791cdcc:core/WishlistController.lua adds the editor/Create context
--    identity test; it catches every replacement except contextless_replaced,
--    where both contexts stay nil.
--  * Created-draft and result bookkeeping (SentDraft, Create admission,
--    SaveResult) compare contexts and tokens in the bc5f495, a43cf27 and
--    791cdcc Controller files cited above, so a context change already
--    retires them there; an equal-content contextless replacement, also
--    after a host error, does not.
--  * 9c60456:core/WishlistController.lua adds the draft identity; only the
--    wording of the partial notice in this revision is still predicted to
--    fail there.
local PREDICT={
 same_content={partial=FAILS_BASE,writers=FAILS_BASE,store=FAILS_BASE,savedBuild2=FAILS_BASE,
  notices=FAILS_BASE,named=FAILS_BASE_MID,wording=FAILS_BEFORE_SUCCESSOR,view=FAILS_BASE},
 changed_content={named=FAILS_BASE_MID,wording=FAILS_BEFORE_SUCCESSOR},
 create_replaced={partial=FAILS_BASE,store=FAILS_BASE,notices=FAILS_BASE,named=FAILS_BASE_MID,
  wording=FAILS_BEFORE_SUCCESSOR,view=FAILS_BASE},
 contextless_replaced={partial=FAILS_BASE_MID,writers=FAILS_BASE_MID,store=FAILS_BASE_MID,
  notices=FAILS_BASE_MID,named=FAILS_BASE_MID,wording=FAILS_BEFORE_SUCCESSOR,view=FAILS_BASE_MID,
  result=FAILS_BASE_MID,sent=FAILS_BASE_MID,admit=FAILS_BASE_MID},
 contextless_host_error={result=FAILS_BASE_MID,sent=FAILS_BASE_MID,admit=FAILS_BASE_MID},
}
local ADJUDICATE=os.getenv('NEXUS_UPLOAD_CONTEXT_BASELINE')
if ADJUDICATE=='' then ADJUDICATE=nil end
if ADJUDICATE~=nil then
 local known=ADJUDICATE=='successor'
 for _,name in ipairs(BASELINES)do if ADJUDICATE==name then known=true end end
 assert(known,'NEXUS_UPLOAD_CONTEXT_BASELINE must be bc5f495, a43cf27, 791cdcc, 9c60456 or successor')
end
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}
local PARTIAL='but the editor changed'
local HOST_FAILURE='synthetic host failure after the accepted upload'
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
-- Every key of a table, labelled with its Lua type and sorted, so a string
-- key "1", a number key 1 and a stray index 0 or 3 are all told apart.
local function KeySet(t)
 local out={}
 if type(t)~='table' then return out end
 for k in pairs(t)do out[#out+1]=type(k)..':'..tostring(k) end
 table.sort(out)
 return out
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
 local predict=PREDICT[which] or {}
 local function setup(v,label,observed)
  report.setup=report.setup+1
  emit('SETUP',{case=which,label=label,pass=v==true,observed=observed})
  if v~=true then error({setupFailure=label},0) end
 end
 -- One EXPECT or GUARD check. `fails` names the baselines whose comparison
 -- model this check is predicted to fail in (PREDICT); the category follows
 -- the fixed public base: EXPECT when predicted to fail there, else GUARD.
 local function check(v,label,observed,fails)
  fails=fails or HOLDS
  local category=fails[BASE] and 'expect' or 'guard'
  local predicted={successor='hold'}
  for _,name in ipairs(BASELINES)do predicted[name]=fails[name] and 'fail' or 'hold' end
  local pass=v==true
  local event={case=which,label=label,pass=pass,predicted=predicted,observed=observed}
  if ADJUDICATE then
   event.agrees=(predicted[ADJUDICATE]=='hold')==pass
   if not event.agrees then report.disagreements[#report.disagreements+1]=label end
  end
  report[category]=report[category]+1
  emit(category:upper(),event)
  if not pass then
   local list=report[category..'Failures'];list[#list+1]=label
   report.firstFailure=report.firstFailure or label
  end
 end

 Nexus=nil;NexusDB={};WishlistRealizerDB=nil
 -- The NexusDB root the real GameAdapter binds its assignment-action epoch
 -- to; the injected Store facade below is the only writable owner, so a save
 -- may neither replace nor write this table.
 local dbRoot=NexusDB
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
 setup(Nexus.MainInternals==nil,
  'no real Store owner seam is loaded: every write goes through the injected Store facade')
 local backing,settings,account={},{},{}
 local store={State=function()return backing end,Settings=function()return settings end}
 local A=Nexus.GameAdapter
 A.Init({},store)
 local okA,whyA=A.SetLoadoutWishlistIdentity(1,'Wishlist A',H.Clone(originalA),H.Clone(design))
 local okB,whyB=A.SetLoadoutWishlistIdentity(2,'Wishlist B',H.Clone(originalB),H.Clone(design))
 setup(okA==true and okB==true,'two real adapter assignment writes admitted',{A=whyA or 'accepted',B=whyB or 'accepted'})
 -- The injected Store row (`backing`, what Store.State() returns and what the
 -- real writers mutate through the facade fallback) holds exactly the two
 -- fixture assignments, so a stray key a save writes is visible below.
 setup(T.Equal(KeySet(backing),{'string:loadoutWishlists','string:wishlistAssignmentSerial'})
  and T.Equal(KeySet(backing.loadoutWishlists),{'number:1','number:2'})
  and backing.wishlistAssignmentSerial==2,
  'the injected Store row holds exactly Saved Builds 1 and 2 and their stamp before any save',
  {row=KeySet(backing),links=KeySet(backing.loadoutWishlists)})
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

 -- The serialized-token input of the draft shown (contents only).
 local function DraftView()
  local d=c.DebugDraftState()
  return {ordinary=H.Clone(c.CanonicalEchoes()),pending=d.pending,pendingLock=d.pendingLock,
   fulfilled=d.fulfilled,permanent=H.Clone(c.FulfilledDraftTargets()),lockRows=H.Clone(c.PendingLockRows())}
 end
 -- The replacement as the public controller seam shows it: its token input,
 -- every draft row (ordinary, locked-slot, permanent target), the draft debug
 -- state (browse offsets, Copy context, block reason), and its Copy evidence,
 -- editor and Create contexts. Deep clones, captured inside the host callback
 -- right after the replacement is admitted and again after the save returns.
 local function ReplacementView()
  return {draft=DraftView(),pendingRows=H.Clone(c.PendingRows()),pendingLockRows=H.Clone(c.PendingLockRows()),
   permanent=H.Clone(c.FulfilledDraftTargets()),debug=H.Clone(c.DebugDraftState()),
   blocked=c.ApplyBlockReason(),candidate=H.Clone(c.CandidateContext()),
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
  -- The authorizing Create draft carries no Copy evidence: a replacement
  -- that does (checked inside the callback) is another whole draft even when
  -- its contents and serialized token are equal.
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
 -- The real GameAdapter upload entry the controller calls (its Adapter is
 -- this same table): a pass-through recorder of what the adapter returned,
 -- so the host_error translation is observed at the adapter boundary itself.
 local adapterReturns={}
 local adapterUpload=A.UploadWishlist
 setup(type(adapterUpload)=='function','adapter upload API present: UploadWishlist')
 A.UploadWishlist=function(...)
  local r1,r2=adapterUpload(...)
  adapterReturns[#adapterReturns+1]={ok=r1,reason=r2}
  return r1,r2
 end
 local callback={ran=false}
 local host=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function(...)
  local accepted=host(...)
  callback.ran,callback.hostAccepted=true,accepted==true
  if callbackAction then
   -- Notice marks around the callback, so a line it wrote would be shown
   -- apart from the save's own lines instead of being filtered away.
   callback.noticesBefore=#messages
   local okCall,callError=pcall(callbackAction,callback)
   if not okCall then callback.error=tostring(callError) end
   callback.noticesAfter=#messages
  end
  if spec.raise then
   -- The deliberate host failure after the accepted upload and the callback,
   -- outside the callback's own protection: only the real GameAdapter pcall
   -- around UploadServerBuildSlot can turn it into host_error.
   callback.raised=true
   error(HOST_FAILURE,0)
  end
  return accepted
 end
 -- Snapshots right before the save, for the owner oracles below: deep clones
 -- of the injected Store row, of the controller account root and of the
 -- injected settings, and the identity of the row's assignment map table.
 local before=H.Clone(backing)
 local accountBefore,settingsBefore=H.Clone(account),H.Clone(settings)
 local linksRef=backing.loadoutWishlists
 local mark=#messages
 local accepted,reason=c.AcceptApply(data)
 local after=H.Clone(backing)
 local uploads={}
 for _,action in ipairs(H.actions)do if action[1]=='upload' then uploads[#uploads+1]=H.Clone(action) end end
 -- Every line written since the save began, callback window included; none
 -- is reset or filtered out after the callback.
 local saveNotices,partial={},{}
 for i=mark+1,#messages do
  saveNotices[#saveNotices+1]=messages[i]
  if messages[i]:find(PARTIAL,1,true) then partial[#partial+1]=messages[i] end
 end
 local callbackNotices={}
 for i=(callback.noticesBefore or 0)+1,(callback.noticesAfter or 0) do
  callbackNotices[#callbackNotices+1]=messages[i]
 end
 local result=c.SaveResult()
 local afterView=ReplacementView()
 emit('OBSERVED',{case=which,accepted=accepted==true,reason=reason,callback=callback,uploads=uploads,
  adapterReturns=adapterReturns,writes=writes,before=before,after=after,result=result,afterView=afterView,
  nativeActiveSlot=A.Slots().activeSlot,forbidden=forbidden,notices=saveNotices,
  callbackNotices=callbackNotices,account=account,settings=settings})

 -- A callback that was not reached or not admitted is a setup failure.
 setup(callback.ran==true and callback.hostAccepted==true,'the host accepted the upload and its callback boundary was reached')
 setup(callback.error==nil,'the host callback ran without error',callback.error)
 if callbackAction then
  setup(#callbackNotices==0,
   "nothing inside the host callback wrote a notice (source-verified for this data): every line since the save began is the save's own",
   callbackNotices)
 end
 if spec.raise then
  setup(callback.raised==true,
   'the host raised after the accepted upload and the callback: a deliberate, witnessed host failure')
 end
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

 check(#uploads==1 and uploads[1][2]==uploadSlot and uploads[1][3]==uploadName
  and T.Equal(uploads[1][4],expectedPayload),
  'exactly one host upload: original slot and name, exact ordinary rows, no extra or permanent rows',uploads)
 local adapterOutcome=adapterReturns[1] or {}
 if spec.raise then
  check(#adapterReturns==1 and adapterOutcome.ok==false and adapterOutcome.reason=='host_error',
   'the real GameAdapter turns the raised host call into host_error, once',adapterReturns)
 else
  check(#adapterReturns==1 and adapterOutcome.ok==true and adapterOutcome.reason==nil,
   'the real GameAdapter reports exactly one accepted upload call',adapterReturns)
 end
 check(T.Equal((before.loadoutWishlists or {})[2],(after.loadoutWishlists or {})[2]),
  'the upload never changes the Saved Build 2 assignment',
  {before=(before.loadoutWishlists or {})[2],after=(after.loadoutWishlists or {})[2]},predict.savedBuild2)
 local zero=true;for _,n in pairs(forbidden)do if n~=0 then zero=false end end
 check(zero,'zero spend, Take, activation, native Save, Sync or other gameplay calls',forbidden)
 check(A.Slots().activeSlot==(spec.native and 2 or spec.active),
  'the native active slot keeps its independent state',A.Slots().activeSlot)
 check(c.IsApplyPending()==false,'no save retry remains')
 -- Owners outside the injected row: the global NexusDB root (identity and
 -- deep content), the table the controller's accountRoot returns and the
 -- injected Store.Settings() table (deep T.Equal against the clones taken
 -- right before the save), and the identity of the row's assignment map
 -- (no writer swapped it for another table).
 check(rawequal(NexusDB,dbRoot) and T.Equal(NexusDB,{}) and WishlistRealizerDB==nil,
  'the save neither replaces nor writes the NexusDB root',{root=NexusDB,legacy=WishlistRealizerDB})
 check(T.Equal(account,accountBefore) and T.Equal(settings,settingsBefore),
  'the save writes neither the controller account root nor the injected settings',
  {account=account,settings=settings})
 check(rawequal(backing.loadoutWishlists,linksRef),
  'no writer replaces the assignment map table of the injected Store row')

 -- The explicit replacement Create through the real PrepareApply: its
 -- confirmation payload names the copy name the controller offers (the
 -- uploaded name stays taken) and the name the player typed. Cancelled; it
 -- never reaches the host.
 local function ReplacementCreate()
  H.now=H.now+3.1
  local d2,m2=c.PrepareApply('Plan C')
  local admitted=type(d2)=='table'
  check(admitted and m2=='create',
   'the explicit replacement Create is admitted, not refused as already created',{mode=m2},predict.admit)
  check(admitted and d2.name=='Plan C (Copy 1)' and d2.requestedName=='Plan C',
   'the replacement Create is offered as Plan C (Copy 1) for requested Plan C: the uploaded name stays taken',
   {mode=m2,name=admitted and d2.name or nil,requestedName=admitted and d2.requestedName or nil},predict.admit)
  if admitted then c.CancelApply(d2) end
  local n=0;for _,action in ipairs(H.actions)do if action[1]=='upload' then n=n+1 end end
  check(n==1,'admitting the replacement uploads nothing',n)
 end

 if spec.raise then
  check(accepted==false and reason=='host_error','the original save returns host_error',
   {accepted=accepted,reason=reason})
  check(#writes==0,'no call to any of the eight assignment writer APIs',writes,predict.writers)
  check(T.Equal(before,after),'the whole store is unchanged: every Saved Build, first-run and design bucket',
   {changed=ChangedKeys(before,after)},predict.store)
  local line=saveNotices[1] or ''
  check(#saveNotices==1 and #partial==0 and line:find("'Plan C'",1,true)~=nil
   and line:find('may or may not have reached the server',1,true)~=nil
   and line:find('nothing was assigned',1,true)~=nil,
   'exactly one notice in total during the save: the host error, said as may or may not have reached the server',
   saveNotices,predict.notices)
  check(T.Equal(callback.full,afterView),
   'the original save leaves the replacement draft, its permanent targets, Copy evidence and contexts as admitted',
   {callback=callback.full,after=afterView},predict.view)
  check(result==nil,'no result of the original save is shown on the replacement editor',result,predict.result)
  local sent,sentUncertain=c.SentDraft()
  check(sent==nil,'the replacement draft is not marked as already sent',
   {name=sent,uncertain=sentUncertain},predict.sent)
  ReplacementCreate()
 elseif spec.replace then
  check(accepted==false and reason=='uploaded_draft_changed',
   'the replaced draft is reported as partial (uploaded_draft_changed)',{accepted=accepted,reason=reason},predict.partial)
  check(#writes==0,'no call to any of the eight assignment writer APIs',writes,predict.writers)
  check(T.Equal(before,after),'the whole store is unchanged: every Saved Build, first-run and design bucket',
   {changed=ChangedKeys(before,after)},predict.store)
  check(#partial==1,'exactly one partial notice',saveNotices,predict.notices)
  check(#saveNotices==1 and #partial==1,
   'exactly one notice in total during the save, the partial one: no success, uncertain or second line',
   saveNotices,predict.notices)
  check(#partial==1 and partial[1]:find("'"..uploadName.."' was uploaded",1,true)~=nil,
   'the partial notice names the uploaded Wishlist',saveNotices,predict.named)
  local line=saveNotices[1] or ''
  check(#saveNotices==1 and line:find('changed no assignment',1,true)~=nil
   and line:find('any assignment it already had is kept',1,true)~=nil
   and line:find('nothing is uploaded again',1,true)~=nil
   and line:find('Echo Journal',1,true)~=nil
   and not line:find('save again',1,true) and not line:find('not assigned',1,true),
   'the partial notice says no assignment or locked target changed, an earlier assignment is kept, nothing uploads again, and points to the Echo Journal',
   saveNotices,predict.wording)
  check(T.Equal(callback.full,afterView),
   'the original save leaves the replacement draft, its permanent targets, Copy evidence and contexts as admitted',
   {callback=callback.full,after=afterView},predict.view)
  check(result==nil,'no result of the original save is shown on the replacement editor',result,predict.result)
  if spec.kind=='create' then
   local sent,sentUncertain=c.SentDraft()
   check(sent==nil,'the replacement draft is not marked as already sent',
    {name=sent,uncertain=sentUncertain},predict.sent)
   ReplacementCreate()
  end
 else
  check(accepted==true and reason==nil,'the unchanged-context save succeeds',{accepted=accepted,reason=reason})
  check(#partial==0,'no partial notice',saveNotices)
  -- Every line since the save began, in order, against the notices the
  -- success path of the Controller source writes for this world.
  local wanted
  if spec.kind=='opened' then
   wanted={'Wishlist saved (3/79 rolled copies planned'}
  elseif spec.active==1 then
   wanted={"assigned 'Plan C' to Saved A.",'Wishlist saved (4/79 rolled copies planned'}
  else
   wanted={"'Plan C' is the first-run Wishlist target",'Wishlist saved (4/79 rolled copies planned'}
  end
  local inOrder=#saveNotices==#wanted
  for i,fragment in ipairs(wanted)do
   if not (saveNotices[i] and saveNotices[i]:find(fragment,1,true)) then inOrder=false end
  end
  check(inOrder,'the save writes exactly its own success notices, in order, and no other line',
   {notices=saveNotices,wanted=wanted})
  local writer,destination
  if spec.kind=='opened' then writer,destination='UpdateWishlistAssociationAfterSave',1
  elseif spec.active==1 then writer,destination='SetLoadoutWishlistIdentity',1
  else writer='SetFirstLoadoutWishlistIdentity' end
  check(#writes==1 and writes[1].fn==writer and writes[1].ok==true
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
  check(T.Equal(changed,expectedKeys),'exactly the expected store keys change',changed)
  check(after.wishlistAssignmentSerial==3,'one new assignment stamp',after.wishlistAssignmentSerial)
  local beforeLinks,afterLinks=before.loadoutWishlists or {},after.loadoutWishlists or {}
  if spec.kind=='opened' then
   check(T.Equal(afterLinks[1],EXPECTED_OPENED),
    'Saved Build 1 holds exactly edited Wishlist A: original slot and name, exact ordinary rows, separate permanent design',afterLinks[1])
   -- The whole assignment map of the injected row, both directions (T.Equal):
   -- index 1 is the edited record, index 2 the record from before the save,
   -- and no other index (0, 3, a string key) exists.
   check(T.Equal(afterLinks,{[1]=EXPECTED_OPENED,[2]=beforeLinks[2]}),
    'the whole Saved Build map is exactly 1 = edited Wishlist A and 2 = Wishlist B as before, no other index',
    KeySet(afterLinks))
   check(type(writes[1])=='table' and type(writes[1].args[5])=='table' and writes[1].args[5][LOCK]==true,
    'the writer receives the separate permanent design')
   check(after.firstRunWishlist==nil,'no first-run target appears')
   check(T.Equal(after.lockDesignTargetsBySlot,{[EXPECTED_OPENED.key]={[LOCK]=true}}),
    'one design bucket for the saved contents, holding only the permanent target',after.lockDesignTargetsBySlot)
  else
   local record
   if spec.active==1 then
    record=afterLinks[1]
    check(after.firstRunWishlist==nil,'no first-run target appears')
    -- The whole assignment map of the injected row, both directions.
    check(T.Equal(afterLinks,{[1]=EXPECTED_CREATE,[2]=beforeLinks[2]}),
     'the whole Saved Build map is exactly 1 = Plan C and 2 = Wishlist B as before, no other index',
     KeySet(afterLinks))
   else
    record=after.firstRunWishlist
    -- The whole map against the one from before the save, whose exact key
    -- set {1,2} the setup above proved.
    check(T.Equal(beforeLinks,afterLinks),'every Saved Build assignment is unchanged (no slot-1 handoff over an assignment)',
     KeySet(afterLinks))
   end
   check(T.Equal(record,EXPECTED_CREATE),
    'the destination holds exactly Plan C: exact ordinary rows, separate permanent design',record)
   check(DesignBucketOK(after.lockDesignTargetsBySlot,EXPECTED_CREATE.key),
    'one design bucket for Plan C holding only the permanent target',after.lockDesignTargetsBySlot)
   check(RoleChoiceOK(after.wishlistRoleChoices),
    'one role choice: Plan C ordinary rows and its one permanent target',after.wishlistRoleChoices)
  end
  local kind=(spec.kind=='create' and spec.active==0) and 'firstRun' or 'assigned'
  check(type(result)=='table' and result.kind==kind,'the save result names the assignment that was written',result)
  if spec.kind=='create' then
   local sent=c.SentDraft()
   check(sent=='Plan C','the created draft is marked as sent',sent)
   H.now=H.now+3.1
   local d2,m2=c.PrepareApply('Plan C')
   check(d2==nil and m2=='already_created','pressing Create again for the created draft is refused',{mode=m2})
   local n=0;for _,action in ipairs(H.actions)do if action[1]=='upload' then n=n+1 end end
   check(n==1,'the repeated Create uploads nothing',n)
  end
 end
end

local ADJUDICATED={checks=0,disagreements={},incomplete={}}
local function runCase(which)
 local report={setup=0,expect=0,guard=0,expectFailures={},guardFailures={},disagreements={}}
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
 if ADJUDICATE then
  ADJUDICATED.checks=ADJUDICATED.checks+report.expect+report.guard
  for _,label in ipairs(report.disagreements)do
   ADJUDICATED.disagreements[#ADJUDICATED.disagreements+1]=which..': '..label
  end
  if status=='SETUP_FAILED' or status=='RAISED' then ADJUDICATED.incomplete[#ADJUDICATED.incomplete+1]=which end
 end
 emit('CASE_RESULT',{case=which,status=status,setupChecks=report.setup,expectChecks=report.expect,
  guardChecks=report.guard,expectFailures=report.expectFailures,guardFailures=report.guardFailures,
  firstFailure=report.firstFailure,disagreements=ADJUDICATE and report.disagreements or nil,
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
if ADJUDICATE then
 -- Observed outcomes of this run against the selected prediction column; the
 -- name does not say which tree ran, and the host must record that identity.
 emit('ADJUDICATION',{fixture='wishlist_upload_context',baseline=ADJUDICATE,role=ROLE[ADJUDICATE],
  basis='observed in this run vs the selected prediction column: for a base or historical commit name, the outcome predicted for its comparison model (the core/WishlistController.lua of that commit with the current supporting modules and harness this fixture was written against, not a whole checkout and not the modules of the tree that ran); for successor, the required outcome. Neither is an execution, and the column does not identify the tree that ran; the execution host (not the synthetic game host) must record the identity of that tree',checks=ADJUDICATED.checks,
  disagreements=ADJUDICATED.disagreements,incomplete=ADJUDICATED.incomplete})
end
-- With no baseline name or a recognized one, the exit follows the case
-- statuses alone; the adjudication never changes it. An unrecognized value
-- fails the baseline assert near the top instead.
if failed then
 error('wishlist_upload_context: '..table.concat(parts,' ')
  ..' (SETUP_FAILED and RAISED are not behavior evidence)',0)
end
