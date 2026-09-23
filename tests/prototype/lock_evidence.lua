-- Regression: valid 79+6 designed mirrors must resolve exact active lock roles
-- before editor opening and assignment, not only after an association exists.
-- Synthetic data only; no game or network access.
local H=dofile('tests/prototype/harness.lua')
local locks={200690,200756,200882,201250,201262,201270}
local qualities={2,3,2,3,3,3}
local total={}
for i=1,79 do
 local id=210000+i;H.AddEcho(id,'Ordinary '..i,2,5)
 total[#total+1]={spellId=id,quality=2,stacks=1,locked=false}
end
for i,id in ipairs(locks) do
 H.AddEcho(id,'Locked '..i,qualities[i],5)
 total[#total+1]={spellId=id,quality=qualities[i],stacks=1,locked=false}
 H.locked[#H.locked+1]={spellId=id,stacks=1}
end
H.perks.serverBuildSlots={
 [1]={name='Synthetic active',verified=true,echoes=H.Clone(total)},
 [101]={name='Synthetic plan',verified=false,echoes=H.Clone(total)},
}
H.perks.serverActiveSlot=1
H.Boot()
local A=Nexus.GameAdapter
local state,settings={},{}
local store={State=function()return state end,Settings=function()return settings end}
A.Init({},store)
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local function roleCounts(echoes)
 local ordinary,locked=0,0
 for _,row in ipairs(echoes or {}) do
  if row.locked==true then locked=locked+row.stacks
  elseif row.locked==false then ordinary=ordinary+row.stacks
  else return -1,-1 end
 end
 return ordinary,locked
end
local function candidates() return A.GetWishlistCandidates() end
local c=candidates()[1]
check(c~=nil and c.slot==101,'candidate must remain visible')
check(A.WishlistEvidenceState(c)=='actionable','EXPECTED RED: exact active 79+6 candidate must be actionable before association')
local n,l=roleCounts(c.echoes)
check(n==79 and l==6,'exact count subtraction 79+6')
local messages={}
local ctl=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=store,notify=function(s)messages[#messages+1]=s end})
ctl.Initialize(A)
check(ctl.BeginWishlist(c)==true,'editor opens verified candidate before assignment')
check(ctl.PendingTotal()==79,'editor ordinary total')
local count=0;for _ in pairs(ctl.FulfilledDraftTargets())do count=count+1 end
check(count==6,'editor retains the six already-owned targets as fulfilled')
local exported=ctl.ExportEntries();local en,el=0,0
for _,e in ipairs(exported) do if e.locked then el=el+e.stacks else en=en+e.stacks end end
check(en==79 and el==6,'editor export retains all 79+6 exact target copies')
local ok,why=A.SetLoadoutWishlist(1,101,c)
check(ok==true,'assignment succeeds: '..tostring(why))
local linked,kind=A.GetLoadoutWishlistState(1)
check(kind=='actionable' and linked~=nil,'associated read is actionable')
local wish=A.Wishlist()
check(wish and #wish.entries==85,'policy target resolves after association')
check(ctl.BeginShow()==true,'real editor open entry works')
check(#H.actions==0,'read/association performs no gameplay writes')
print('PASS lock evidence real-adapter/editor/association checks='..checks)

local function equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)=='number' and a~=a and b~=b then return true end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local function reset()
 state={}
 H.perks.serverBuildSlots={
  [1]={name='Synthetic active',verified=true,echoes=H.Clone(total)},
  [101]={name='Synthetic plan',verified=false,echoes=H.Clone(total)},
 }
 H.perks.serverActiveSlot=1
 H.locked={}
 for _,id in ipairs(locks)do H.locked[#H.locked+1]={spellId=id,stacks=1}end
end
local function findPlan()
 for _,row in ipairs(A.GetWishlistCandidates())do if row.slot==101 then return row end end
end
local function pendingRefusal(label, mutate)
 reset();mutate()
 local source=H.Clone(H.perks.serverBuildSlots)
 local owned=H.Clone(H.locked)
 local before=H.Clone(state)
 local row=findPlan()
 check(row~=nil,label..': preserves visible identity')
 check(A.WishlistEvidenceState(row)=='evidence-pending',label..': does not manufacture authority')
 local yes,reason=A.SetLoadoutWishlist(1,101,row)
 check(yes==false and type(reason)=='string' and not reason:find('invalid wishlist',1,true),label..': specific refusal')
 check(equal(state,before),label..': no association mutation')
 check(equal(H.perks.serverBuildSlots,source) and equal(H.locked,owned),label..': source evidence immutable')
end
pendingRefusal('mismatched active identity',function()
 H.perks.serverBuildSlots[1].echoes[1].spellId=210002
end)
pendingRefusal('unverified active',function()H.perks.serverBuildSlots[1].verified=false end)
pendingRefusal('missing verified flag',function()H.perks.serverBuildSlots[1].verified=nil end)
pendingRefusal('locked data absent',function()H.locked=nil end)
pendingRefusal('too many locked copies',function()H.locked[#H.locked+1]={spellId=210001,stacks=1}end)
pendingRefusal('missing locked identity',function()H.locked[1]={spellId=299999,stacks=1}end)
pendingRefusal('zero locked copies',function()H.locked[1].stacks=0 end)
pendingRefusal('malformed locked metadata',function()H.locked[1].stacks=0/0 end)
pendingRefusal('active input sparse/malformed',function()H.perks.serverBuildSlots[1].echoes[86]='bad' end)
pendingRefusal('ambiguous verified flags',function()H.perks.serverBuildSlots[101].verified=true end)

reset()
for _,e in ipairs(H.perks.serverBuildSlots[101].echoes)do e.locked=nil end
local noFlags=findPlan();check(noFlags and A.WishlistEvidenceState(noFlags)=='actionable','omitted flags derive with exact independent evidence')
local n2,l2=roleCounts(noFlags.echoes);check(n2==79 and l2==6,'omitted flags preserve exact counts')

-- A passive candidate already held by the real editor must be resolved on open,
-- rather than require refreshing or creating its association first.
reset();H.locked=nil
local held=findPlan();check(held.lockEvidenceStatus=='unavailable','capture pending editor candidate')
H.locked={};for _,id in ipairs(locks)do H.locked[#H.locked+1]={spellId=id,stacks=1}end
check(ctl.BeginWishlist(held)==true,'pending editor candidate becomes usable after legitimate evidence arrives')
check(A.SetLoadoutWishlist(1,101,held)==true,'pending captured candidate passes exact fresh selection')

-- Preserve the marker that a fallback stored record depends on active evidence.
local saved=H.Clone(state.loadoutWishlists[1])
check(saved.evidenceSource=='verified-active','derived saved association keeps provenance')
H.perks.serverBuildSlots[101]=nil
check(A.GetLoadoutWishlist(1)~=nil,'missing live mirror may use reverified saved identity')
H.locked=nil
local before=H.Clone(state)
check(A.GetLoadoutWishlist(1)==nil,'stored derived roles do not outlive unavailable authoritative locks')
check(A.Wishlist()==nil and tostring(A.WishlistNote()):find('synchronized',1,true),'policy reports specific pending state')
check(equal(state,before),'failed recheck preserves stored association')
H.locked={};for _,id in ipairs(locks)do H.locked[#H.locked+1]={spellId=id,stacks=1}end
check(A.GetLoadoutWishlist(1)~=nil,'legitimate evidence restores saved identity')
H.perks.serverBuildSlots[2]=H.Clone(H.perks.serverBuildSlots[1])
state.loadoutWishlists[2]=H.Clone(saved)
check(A.GetLoadoutWishlist(2)==nil,'inactive associated snapshot receives no active-only authority')
local _,inactive=A.GetLoadoutWishlistState(2)
check(inactive=='evidence-pending','inactive state remains explicit')

-- Stale click cannot retain authority after the verified source changes.
reset();local click=findPlan();H.perks.serverBuildSlots[1].verified=false
local yes,reason=A.SetLoadoutWishlist(1,101,click)
check(yes==false and reason:find('verified',1,true),'stale click revalidates live evidence')
check(state.loadoutWishlists==nil,'stale click does not write')

-- Authoritative designed flags and ordinary-only Wishlists still work without
-- requiring the selected target to equal the player's current build.
reset()
for i,e in ipairs(H.perks.serverBuildSlots[101].echoes)do e.locked=i>79 end
H.perks.serverBuildSlots[1].echoes[1].spellId=210002
local explicit=findPlan()
check(A.WishlistEvidenceState(explicit)=='actionable' and explicit.evidenceSource==nil,'real explicit roles retain independent authority')
check(A.SetLoadoutWishlist(1,101,explicit)==true,'valid explicitly designed targets still assign')
reset();H.locked=nil
for i=85,80,-1 do H.perks.serverBuildSlots[101].echoes[i]=nil end
check(A.SetLoadoutWishlist(1,101,findPlan())==true,'ordinary-only target does not require locked-Echo data')
reset();H.perks.serverActiveSlot=0
local first=findPlan()
local okFirst,whyFirst=A.SetFirstRunWishlist(101,first)
check(okFirst==false and whyFirst:find('active',1,true),'first-run ambiguous 85 is not guessed from six locks')
check(state.firstRunWishlist==nil,'first-run failure keeps saved state')

-- Count subtraction, not row classification: the same spell can have an
-- ordinary copy and two separately permanent copies.
reset()
H.perks.serverBuildSlots[1].echoes[1]={spellId=locks[1],quality=qualities[1],stacks=1,locked=false}
H.perks.serverBuildSlots[1].echoes[80].stacks=2
H.perks.serverBuildSlots[1].echoes[85]=nil
H.perks.serverBuildSlots[101].echoes=H.Clone(H.perks.serverBuildSlots[1].echoes)
H.locked[1].stacks=2;H.locked[6]=nil
local counted=findPlan();local on,ln=roleCounts(counted.echoes)
check(on==79 and ln==6,'shared ordinary/locked spell is split by counts')
local a,b=0,0
for _,e in ipairs(counted.echoes)do if e.spellId==locks[1] then
 if e.locked then b=b+e.stacks else a=a+e.stacks end
end end
check(a==1 and b==2,'two locked copies do not consume the ordinary copy')

-- Read-only discovery and editor opening never rewrite raw mirrors or history.
reset();local raw=H.Clone(H.perks.serverBuildSlots);local lockcopy=H.Clone(H.locked)
local row=findPlan();A.ResolveWishlistEvidence(row)
check(next(state)==nil,'read-time evidence bridge does not mutate saved character data')
state.lockDesignTargetsBySlot={[row.key]={}};local preparedState=H.Clone(state)
ctl.BeginWishlist(row)
check(equal(H.perks.serverBuildSlots,raw) and equal(H.locked,lockcopy),'all read paths preserve live input tables')
check(equal(state,preparedState),'editor retains existing prepared character data')
check(#H.actions==0,'no rolling, resource, lock, upload or activation call in recovery')

-- A legitimate lock-only semantic notification promotes an untouched awaiting
-- editor without waiting for a designed-slot mutation or requiring a reload.
reset();H.locked=nil
state.loadoutWishlists={[1]={slot=101,name='Synthetic plan',key=A.WishlistKey(total),echoes=H.Clone(total)}}
H.now=H.now+1;H.Notify();A.Poll()
local waiting=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=store,notify=function()end})
waiting.Initialize(A)
local opened,mode=waiting.SelectLoadout(1)
check(opened==true and mode=='new' and waiting.DebugDraftState().awaitingWishlist~=nil,'pending association is observed')
H.locked={};for _,id in ipairs(locks)do H.locked[#H.locked+1]={spellId=id,stacks=1}end
H.now=H.now+1;H.Notify();A.Poll()
local promoted=waiting.RefreshWishlistEvidence('')
check(promoted==true and waiting.PendingTotal()==79,'lock response promotes untouched editor without reload')
local final=waiting.ExportEntries();local finalN,finalL=0,0
for _,e in ipairs(final)do if e.locked then finalL=finalL+e.stacks else finalN=finalN+e.stacks end end
check(finalN==79 and finalL==6,'promotion retains exact targets')
print('PASS complete lock-evidence boundary checks='..checks)

-- Saving the resolved editor remains an ordinary 79-copy upload plus a local
-- six-copy design association; the server's later ordinary mirror reopens it.
local save=assert(waiting.PrepareApply('Synthetic saved plan'))
check(#save.echoes==79,'resolved editor uploads ordinary pool only')
H.now=H.now+4
check(waiting.AcceptApply(save)==true,'resolved editor save succeeds')
local sent=H.actions[#H.actions]
check(sent and sent[1]=='upload' and #sent[4]==79,'real upload retains the ordinary envelope')
H.perks.serverBuildSlots[101].echoes=H.Clone(sent[4])
local reopened=findPlan()
check(waiting.BeginWishlist(reopened)==true,'server ordinary mirror reopens after save')
local copies=waiting.ExportEntries();local sn,sl=0,0
for _,e in ipairs(copies)do if e.locked then sl=sl+e.stacks else sn=sn+e.stacks end end
check(sn==79 and sl==6,'save/reopen retains 79 ordinary and all six fulfilled targets')
print('PASS final lock evidence checks='..checks)
