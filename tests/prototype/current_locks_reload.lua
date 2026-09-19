-- Defaulted roles persist as local PLAN evidence, never reconstructed by
-- silently changing permanent locks or requiring the equipped ordinary build.
local function serialize(v)
 local kind=type(v)
 if kind=='string' then return string.format('%q',v)end
 if kind=='number' or kind=='boolean' then return tostring(v)end
 assert(kind=='table');local a={'{'}
 for k,c in pairs(v)do a[#a+1]='['..serialize(k)..']='..serialize(c)..','end
 a[#a+1]='}';return table.concat(a)
end
local H=dofile('tests/prototype/harness.lua')
local entries={}
for i=1,85 do entries[i]={spellId=200000+i,quality=i%4,stacks=1}end
H.perks.serverActiveSlot=1
H.perks.serverBuildSlots={[1]={name='Current',verified=true,echoes={{spellId=200090,quality=2,stacks=1}}},
 [101]={name='Original',verified=false,echoes=H.Clone(entries)}}
for i=80,85 do H.locked[#H.locked+1]={spellId=200000+i,stacks=1}end
H.Boot()
local candidate
for _,c in ipairs(Nexus.GameAdapter.GetWishlistCandidates())do if c.slot==101 then candidate=c end end
assert(Nexus.WishlistEditor.ResolveAndAssignWishlist(candidate,1))
assert(Nexus.Store.State().wishlistRoleChoices[1].source=='current-locks')
assert(Nexus.GameAdapter.Wishlist())
local saved=serialize(NexusDB)
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H2=dofile('tests/prototype/harness.lua')
H2.perks.serverActiveSlot=1
local reverse={};for i=#entries,1,-1 do reverse[#reverse+1]=H2.Clone(entries[i])end
H2.perks.serverBuildSlots={[1]={name='Current',verified=true,echoes={{spellId=200089,quality=1,stacks=1}}},
 [101]={name='Server renamed',verified=false,echoes=reverse}}
-- Reading a previously chosen plan does not require today's owned evidence.
H2.locked={}
NexusDB=assert(loadstring('return '..saved))()
H2.Boot()
local a=Nexus.GameAdapter
local c
for _,v in ipairs(a.GetWishlistCandidates())do if v.slot==101 and v.name=='Server renamed' then c=v end end
assert(c and c.evidenceSource=='current-locks' and a.WishlistEvidenceState(c)=='actionable')
local ordinary,locked=0,0
for _,v in ipairs(c.echoes)do if v.locked then locked=locked+v.stacks else ordinary=ordinary+v.stacks end end
assert(ordinary==79 and locked==6)
assert(a.GetLoadoutWishlist(1) and a.Wishlist())
assert(Nexus.WishlistEditor.OpenForWishlist(c,1))
assert(not NexusWishlistRolePicker or not NexusWishlistRolePicker:IsShown())
assert(#H2.actions==0 and #H2.locked==0,'reload does not upload, grant, lock, or spend')
local draft=Nexus.WishlistEditor.DebugDraftState()
assert(draft.pending==79 and draft.pendingLock==6,'planned targets retained when not currently owned')
-- A missing current lock response must not default a different unresolved plan.
H2.locked=nil
local different=H2.Clone(entries);different[1]={spellId=200086,quality=2,stacks=1}
H2.perks.serverBuildSlots[102]={name='Another',verified=false,echoes=different}
for _,v in ipairs(a.GetWishlistCandidates())do if v.slot==102 then c=v end end
assert(Nexus.WishlistEditor.OpenForWishlist(c,1))
assert(NexusWishlistRolePicker:IsShown() and not NexusWishlistRoleConfirm:IsEnabled())
assert(NexusWishlistRolePicker.message:GetText():find("Waiting for the server's current permanent Echo list",1,true))
NexusWishlistRoleCancel:Click()
print('PASS default current-lock role save/fresh reload, reorder/rename, missing evidence and no ownership fabrication')
