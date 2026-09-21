-- User-chosen planned locks do not depend on currently owning those Echoes.
local H=dofile('tests/prototype/harness.lua')
local E={};for i=1,85 do E[i]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
H.perks.serverBuildSlots={[1]={name='Active',verified=true,echoes={{spellId=200090,quality=2,stacks=1}}},
 [101]={name='Unowned desired plan',verified=false,echoes=H.Clone(E)}}
H.perks.serverActiveSlot=1;H.locked={};H.Boot()
Nexus.Store.Settings().useCurrentLocksForUntagged=false -- Explicit manual-choice control; automatic path has separate tests.
local A,W=Nexus.GameAdapter,Nexus.WishlistEditor
local n=0;local function check(v,m)assert(v,m);n=n+1 end
local function candidate(slot)for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==(slot or 101)then return c end end end
local function counts(c)local o,l=0,0;for _,e in ipairs(c.echoes)do if e.locked then l=l+e.stacks else o=o+e.stacks end end;return o,l end
local function chooseFirstSix()
 for i=1,6 do _G['NexusWishlistRolePlus'..i]:Click()end
end
check(W.OpenForWishlist(candidate(),1),'unowned plan editable')
NexusWishlistRoleUseOwned:Click()
check(not NexusWishlistRoleConfirm:IsEnabled(),'empty owned set makes no guessed roles')
chooseFirstSix()
check(NexusWishlistRoleConfirm:IsEnabled(),'manual six choice works without owning any')
check(NexusWishlistRoleConfirm:Click()==true,'unowned plan confirmation succeeds')
local o,l=counts(candidate());check(o==79 and l==6,'exact role totals')
local draft=W.DebugDraftState();check(draft.pending==79 and draft.pendingLock==6 and draft.fulfilled==0,'unowned targets stay desired, not owned')
check(#H.actions==0,'no owned/locked operations occurred')
check(A.SetLoadoutWishlist(1,101,candidate()),'independent desired plan can be assigned')
check(A.Wishlist()~=nil,'target resolves without active-build equality')
-- Copies, not rows, count toward the six-lock limit.
local copies=H.Clone(E);copies[1].stacks=3;table.remove(copies,85);table.remove(copies,84)
H.perks.serverBuildSlots[102]={name='Copies',verified=false,echoes=copies}
check(W.OpenForWishlist(candidate(102),1),'multi-copy source opens')
NexusWishlistRolePlus1:Click();NexusWishlistRolePlus1:Click()
for i=2,5 do _G['NexusWishlistRolePlus'..i]:Click()end
check(not NexusWishlistRolePlus6:IsEnabled(),'six-copy cap includes both copies from the first row')
check(NexusWishlistRoleConfirm:Click()==true,'split a single ID between ordinary and locked')
local split=candidate(102);local a,b=0,0
for _,e in ipairs(split.echoes)do if e.spellId==200001 then if e.locked then b=b+e.stacks else a=a+e.stacks end end end
check(a==1 and b==2,'one ordinary and two locked copies of same ID preserved')
-- An assignment click is bound to the target selected when its picker opens.
H.perks.serverBuildSlots[103]={name='Other',verified=false,echoes=H.Clone(E)}
H.perks.serverBuildSlots[103].echoes[85].spellId=200090;H.perks.serverBuildSlots[103].echoes[85].quality=2
check(W.ResolveAndAssignWishlist(candidate(103),1),'pending assignment opens the same role picker')
chooseFirstSix();H.perks.serverActiveSlot=0
local savedCount=#Nexus.Store.State().wishlistRoleChoices
check(NexusWishlistRoleConfirm:Click()==false,'active-selection drift blocks assignment')
check(#Nexus.Store.State().wishlistRoleChoices==savedCount,'drift does not store the choice')
NexusWishlistRoleCancel:Click();H.perks.serverActiveSlot=0
check(W.ResolveAndAssignWishlist(candidate(103),0),'new-character assignment uses role picker')
chooseFirstSix();check(NexusWishlistRoleConfirm:Click()==true,'explicit first-run choice assigns')
check(A.GetFirstRunWishlist()~=nil,'first-run target resolves with no equipped build')
-- Direct role proof must preserve ID, quality and counts and reject invalid envelopes.
local source=candidate(103);local before=#Nexus.Store.State().wishlistRoleChoices
local malformed=H.Clone(source.echoes);malformed[1].spellId=999999
check(A.ConfirmWishlistRoles(source,malformed)==nil,'changed ID rejected')
malformed=H.Clone(source.echoes);malformed[1].quality=255
check(A.ConfirmWishlistRoles(source,malformed)==nil,'changed quality rejected')
malformed=H.Clone(source.echoes);malformed[1].stacks=2
check(A.ConfirmWishlistRoles(source,malformed)==nil,'changed copies rejected')
malformed=H.Clone(source.echoes);for _,e in ipairs(malformed)do e.locked=false end
check(A.ConfirmWishlistRoles(source,malformed)==nil,'85 ordinary rejected')
check(#Nexus.Store.State().wishlistRoleChoices==before,'refusals preserve saved choices')
-- A real explicit server-role update cannot be overwritten by an older dialog.
local race=H.Clone(E);race[85].spellId=200089;race[85].quality=1
H.perks.serverBuildSlots[104]={name='Role update race',verified=false,echoes=race}
check(W.OpenForWishlist(candidate(104),nil),'source-role race chooser opens')
chooseFirstSix()
for i,e in ipairs(H.perks.serverBuildSlots[104].echoes)do e.locked=i>79 end
local oldCount=#Nexus.Store.State().wishlistRoleChoices
check(NexusWishlistRoleConfirm:Click()==false,'new explicit server roles cannot be silently overridden')
check(#Nexus.Store.State().wishlistRoleChoices==oldCount,'server-role conflict preserves saved choices')
NexusWishlistRoleCancel:Click()
-- A shorter ambiguous build needs only the number of locks required by its split.
local eighty=H.Clone(E);for i=85,81,-1 do table.remove(eighty,i)end
H.perks.serverBuildSlots[105]={name='80 copies',verified=false,echoes=eighty}
check(W.OpenForWishlist(candidate(105),nil),'80-copy unknown source opens')
check(not NexusWishlistRoleConfirm:IsEnabled(),'80 ordinary cannot be confirmed')
NexusWishlistRolePlus1:Click()
check(NexusWishlistRoleConfirm:Click()==true,'79 ordinary plus one locked may be confirmed')
local ao,al=counts(candidate(105));check(ao==79 and al==1,'partial locked design does not require six')
-- Invalid storage never triggers clearing or replacing unrelated player data.
local owner=Nexus.MainInternals.StoreAuthorityOwner
local valid=Nexus.Store.State().wishlistRoleChoices
assert(owner.UpdateStateV1(function(st)st.wishlistRoleChoices='unrecognized old data'end))
local ok=A.RememberWishlistRoles(source.echoes)
check(ok==false and Nexus.Store.State().wishlistRoleChoices=='unrecognized old data','unknown saved field is not reset')
assert(owner.UpdateStateV1(function(st)st.wishlistRoleChoices=H.Clone(valid)end))
print('PASS role-choice unowned/copies/first-run/stale/refusal controls='..n)
