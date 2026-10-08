-- Synthetic local storage survives a fresh module boot and untagged/reordered
-- server mirrors. Includes real Journal picker and editor save-button paths.
local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
local function serialize(v,parents)
 if type(v)=='string'then return string.format('%q',v)end
 if type(v)=='number'or type(v)=='boolean'then return tostring(v)end
 assert(type(v)=='table','only serializable synthetic data')
 parents=parents or {};assert(not parents[v],'cycle cannot be saved');parents[v]=true
 local keys={};for k in pairs(v)do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b)end)
 local out={'{'};for _,k in ipairs(keys)do out[#out+1]='['..serialize(k,parents)..']='..serialize(v[k],parents)..','end
 out[#out+1]='}';parents[v]=nil;return table.concat(out)
end
local H=dofile('tests/prototype/harness.lua')
local E={};for i=1,85 do E[i]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
H.perks.serverActiveSlot=1
H.perks.serverBuildSlots={[1]={name='Current',verified=true,echoes={{spellId=200090,quality=2,stacks=1}}},
 [101]={name='Desired target',verified=false,echoes=H.Clone(E)}}
H.locked={}
H.Boot()
Nexus.Store.Settings().useCurrentLocksForUntagged=false -- Explicit manual-choice control; automatic path has separate tests.
local A,W=Nexus.GameAdapter,Nexus.WishlistEditor
-- The actual Editing dropdown is also an entry point; no caller must keep
-- using the obsolete indefinite-awaiting behavior.
W.NewWishlist()
local switch
for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and type(f:GetText())=='string' and f:GetText()=='New Wishlist  -  choose another'then switch=f;break end end
check(switch~=nil,'actual Editing dropdown button is visible')
switch:Click()
local menu=assert(_G.NexusWishlistEditorSwitchMenu)
local editRow
for _,row in ipairs(menu.rows)do if row._label and row._label:GetText():find('Desired target',1,true)then editRow=row;break end end
check(editRow~=nil and editRow:IsEnabled(),'unresolved existing target remains clickable')
editRow:Click()
check(NexusWishlistRolePicker:IsShown(),'Editing dropdown opens explicit role selection')
NexusWishlistRoleCancel:Click()
check(#H.actions==0 and Nexus.Store.State().wishlistRoleChoices==nil,'cancelled Editing dropdown choice makes no writes')
NexusEditorFrame:Hide()
local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
journal:Show();Nexus.JournalTab.RefreshAssociations()
local selector=assert(_G.NexusActiveWishlistSelector,'actual Journal selector created')
selector:Click()
local picker=assert(_G.NexusWishlistOnlyPicker,'actual Journal dropdown created')
local target
for _,row in ipairs(picker.children)do
 if row.nameButton and row.nameButton.text:GetText():find('Desired target',1,true)then target=row end
end
check(target~=nil,'real Journal menu includes untagged 85-copy target')
check(target.nameButton.text:GetText():find('choose locked targets',1,true)~=nil,'actionable menu label replaces endless waiting')
target.nameButton:Click()
check(NexusWishlistRolePicker:IsShown(),'real Journal assignment routes to role picker')
for i=1,6 do _G['NexusWishlistRolePlus'..i]:Click()end
check(NexusWishlistRoleConfirm:Click()==true,'real Journal role-confirm-and-assign action succeeds')
local linked=assert(A.GetLoadoutWishlist(1))
check(linked.name=='Desired target','correct existing Wishlist associated')
check(W.DebugDraftState().pendingLock==6,'six unowned desired targets editable')
local save
for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible()and f:GetText()=='Save Wishlist'then save=f;break end end
check(save~=nil,'real existing-Wishlist Save button available')
save:Click();H.AcceptPopup()
check(#H.actions==1 and H.actions[1][1]=='upload' and #H.actions[1][4]==79,'actual save uploads only ordinary79 without owning desired locks')
local linkedAfter=A.GetLoadoutWishlist(1)
check(linkedAfter and W.OpenForWishlist(linkedAfter,1),'saved plan reopens while actual loadout differs')
local d=W.DebugDraftState();check(d.pending==79 and d.pendingLock==6 and d.fulfilled==0,'explicit typed roles not duplicated by sidecar at reopen')
local beforeChoice=serialize(Nexus.Store.State().wishlistRoleChoices)
local beforeActions=#H.actions
local saved=serialize(NexusDB)
check(#saved>0 and beforeActions==1,'serializable account state captured without game operations')
-- A literal save followed by entirely fresh module globals approximates an
-- offline reload. It is not a claim of a native client or backup-recovery test.
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonholdEchoJournal=nil
local H2=dofile('tests/prototype/harness.lua')
H2.perks.serverActiveSlot=1
local reversed={};for i=#E,1,-1 do reversed[#reversed+1]=H2.Clone(E[i])end
H2.perks.serverBuildSlots={[1]={name='Current',verified=true,echoes={{spellId=200091,quality=3,stacks=1}}},
 [101]={name='Server renamed target',verified=false,echoes=reversed}}
H2.locked={}
NexusDB=assert(loadstring('return '..saved))()
H2.Boot()
check(Nexus.StartupStatus().state=='ready','fresh Store and shared startup accepts role-choice saved shape')
local A2,W2=Nexus.GameAdapter,Nexus.WishlistEditor
local live
for _,c in ipairs(A2.GetWishlistCandidates())do if c.slot==101 and c.name=='Server renamed target' then live=c;break end end
check(live and live.evidenceSource=='user-confirmed' and A2.WishlistEvidenceState(live)=='actionable','same exact content resolves after rename, reorder and fresh load')
local o,l=0,0;for _,e in ipairs(live.echoes)do if e.locked then l=l+e.stacks else o=o+e.stacks end end
check(o==79 and l==6,'fresh runtime retains exact 79+6')
check(serialize(Nexus.Store.State().wishlistRoleChoices)==beforeChoice,'resolution did not rewrite or mutate saved choice')
local restored=A2.GetLoadoutWishlist(1)
check(restored~=nil and A2.Wishlist()~=nil,'assigned target survives offline save/reload')
check(W2.OpenForWishlist(restored,1)==true,'real editor reopens restored association')
local d2=W2.DebugDraftState();check(d2.pending==79 and d2.pendingLock==6 and d2.fulfilled==0,'targets remain planned rather than falsely owned')
check(not (NexusWishlistRolePicker and NexusWishlistRolePicker:IsShown()),'no repeated role prompt for unchanged confirmed content')
check(#H2.actions==0,'fresh reads do not upload, lock, unlock, or spend')
-- A different character gets no implicit role proof from the first character.
local snapshot=serialize(NexusDB)
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonholdEchoJournal=nil
local H3=dofile('tests/prototype/harness.lua')
function UnitGUID()return '0x0000000000000002'end
function UnitName()return 'OtherSyntheticCharacter','Ebonhold'end
H3.perks.serverActiveSlot=1
H3.perks.serverBuildSlots={[1]={name='Current',verified=true,echoes={{spellId=200090,quality=2,stacks=1}}},
 [101]={name='Desired target',verified=false,echoes=H3.Clone(E)}}
NexusDB=assert(loadstring('return '..snapshot))()
H3.Boot()
local other
for _,c in ipairs(Nexus.GameAdapter.GetWishlistCandidates())do if c.slot==101 then other=c;break end end
check(Nexus.GameAdapter.WishlistEvidenceState(other)=='evidence-pending','another character does not inherit role confirmation')
check(Nexus.Store.State().wishlistRoleChoices==nil,'another character has no role-choice record')
print('PASS role-choice Journal/save/fresh-load/character-isolation checks='..checks)
