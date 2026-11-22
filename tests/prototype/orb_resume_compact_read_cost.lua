-- Compact Resume gates do not turn the 4Hz mini read into an adapter/pump path.
ORB_SUPPORT_ECHOES={}
for id=510001,511500 do ORB_SUPPORT_ECHOES[#ORB_SUPPORT_ECHOES+1]={id,2} end
local H=dofile('tests/prototype/orbs_support.lua');local A,M=H.A,H.M
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
M.CompactStatus() -- existing initialization is outside the measured hot path
-- Five populated native Saved Builds, 85 entries each, plus 1500 catalog rows.
-- This exercises the fresh slot projection rather than an empty-slot shortcut.
H.perks.serverBuildSlots={}
for slot=1,5 do local entries={}
 for i=1,85 do entries[i]={spellId=510000+i,quality=2,stacks=1} end
 H.perks.serverBuildSlots[slot]={name='Cost slot '..slot,verified=true,echoes=entries}
end
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
local cat=A.Catalog();local rawPairs=pairs;local catalogSize=0
for _ in rawPairs(cat.rows)do catalogSize=catalogSize+1 end
check(catalogSize>=1500,'fixture has a real large unused catalog')
local measuring=false;local counts={};local originals={}
local function wrap(t,k,label)
 local fn=t[k];check(type(fn)=='function','existing boundary '..label)
 originals[#originals+1]={t,k,fn}
 t[k]=function(...)if measuring then counts[label]=(counts[label]or 0)+1 end;return fn(...)end
end
for _,spec in ipairs({
 {A.Orbs,'Read','adapterRead'},{A,'Owned','owned'},{A,'InFlight','flight'},{A,'EchoActiveSlotGeneration','reconcile'},
 {A,'AutomationSignature','fallbackSignature'},{A,'RequestGranted','refresh'},{A,'Poll','poll'},
 {A.Orbs,'Acquire','acquire'},{A.Orbs,'Rebind','rebind'},
 {M,'Pump','pump'},{M,'Resume','resumeAction'},
 {A,'AssignedWishlist','assignment'},{A,'OwnershipTrustView','passiveContext'},
 {A,'Slots','slotProjection'},{A,'Catalog','catalogAcquisition'},{A,'Wishlist','wishlistProjection'},
 {Nexus,'PendingIntentState','runtimeFacade'},
 {Nexus.MainInternals.StoreAuthorityOwner,'UpdateStateV1','storeMutation'}})do wrap(unpack(spec))end
pairs=function(t)if measuring and t==cat.rows then counts.fullCatalogWalk=(counts.fullCatalogWalk or 0)+1 end;return rawPairs(t)end
local function Read(label)
 counts={};local saved=F.Serialize(NexusDB);local actions=#H.actions
 measuring=true;local s=M.CompactStatus();measuring=false
 for _,k in ipairs({'adapterRead','owned','flight','reconcile','fallbackSignature','refresh','poll',
 'acquire','rebind','pump','resumeAction','runtimeFacade','storeMutation','fullCatalogWalk'})do
  check((counts[k]or 0)==0,label..' performs no '..k)
 end
 check(F.Serialize(NexusDB)==saved and #H.actions==actions,label..' leaves durable state and submitted actions exact')
 print('COMPACT_COST',label,F.Serialize(counts))
 return s
end
check(Read('idle')==nil and not counts.assignment and not counts.passiveContext,'idle returns before new work')
check(A.SetLoadoutWishlistIdentity(1,'Cost original',{{spellId=410002,quality=2,stacks=3}}),'real assigned Saved Build')
check(M.Start(3),'real run begins')
check(Read('running').running and not counts.assignment and not counts.passiveContext,'running returns before paused-only work')
check(M.Pause(),'run explicitly paused')
check(Read('paused').canResume and counts.assignment==1 and counts.passiveContext==1,'paused uses one assignment projection and one pure context view')
local trust=A.OwnershipTrustView;A.OwnershipTrustView=nil
check(not Read('missing context').canResume,'missing required passive context fails closed')
A.OwnershipTrustView=trust
check(Read('context restored').canResume,'restored passive context does not change permission or pending work')
-- A real admitted automatic check is paused before its owed offer appears.
-- This is the paused hot path that must remain display-only at 4 Hz.
local R=dofile('tests/prototype/orb_recovery_support.lua')
local server=R.Server(H,{mode='hold'})
H.service.RequestChoice=function()SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME)end
check(M.Resume(),'SETUP resume existing approved run before automatic check')
for _=1,120 do if M.ContinueView().liveStage=='checking' then break end;H.Advance(.25)end
check(M.ContinueView().liveStage=='checking','SETUP real automatic check was admitted')
check(M.Pause(),'SETUP pause the admitted automatic owner')
H.Offer();H.Advance(.5)
check(M.ContinueView().liveStage=='held',
 'SETUP held automatic owner has a current owed offer without a full Status read')
check(Read('held automatic owed offer').canResume,'EXPECT held automatic compact Resume uses passive facts only')
-- Display eligibility cannot replace direct Resume's current action guards.
H.perks.pendingReroll=true
check(not Read('owed offer gains host latch').canResume,'EXPECT compact-only owed Resume drops immediately for a new host latch')
check(not M.Resume() and H.Count('take')==0,'GUARD fresh host-pending state refuses real Resume')
H.perks.pendingReroll=nil
for i=#originals,1,-1 do local o=originals[i];o[1][o[2]]=o[3]end
pairs=rawPairs
print('PASS orb_resume_compact_read_cost checks='..checks..' catalogRows='..catalogSize)
