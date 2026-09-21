local function serialize(v)
 if type(v)=='string'then return string.format('%q',v)end
 if type(v)~='table'then return tostring(v)end
 local out={'{'};for k,x in pairs(v)do out[#out+1]='['..serialize(k)..']='..serialize(x)..','end
 return table.concat(out)..'}'
end
local H=dofile('tests/prototype/harness.lua')
H.perks.serverActiveSlot=1
H.perks.serverBuildSlots={[1]={name='Owned',verified=true,echoes={{spellId=200001,quality=1,stacks=1}}}}
H.Boot();local A=Nexus.GameAdapter
assert(A.SetLoadoutWishlistIdentity(1,'Plan one',{{spellId=200002,quality=2,stacks=2}}))
-- A second durable association makes guessing an active assignment impossible.
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
 s.loadoutWishlists[2]={name='Plan two',key='200003:1',echoes={{spellId=200003,quality=3,stacks=1}}}
end))
local saved=serialize(NexusDB)
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H2=dofile('tests/prototype/harness.lua');H2.perks.serverBuildSlots=nil;H2.perks.serverActiveSlot=nil
NexusDB=assert(loadstring('return '..saved))();H2.Boot();local A2=Nexus.GameAdapter
assert(A2.Wishlist()==nil,'unknown active identity cannot select a different saved assignment')
assert(A2.WishlistNote()=='Restoring assigned Wishlist...','known durable assignment must show restoration while server identity is loading')
Nexus.Panel.Refresh();Nexus.Panel.Show()
assert(Nexus.Panel._lastModel.assignment.state=='restoring','normal main model retains restoring state')
local displayed=false
for _,r in ipairs({NexusPanel:GetRegions()})do if r.GetText and r:GetText()=='Restoring assigned Wishlist...' then displayed=r:IsVisible()end end
assert(displayed,'normal main fontstring displays restoring, not Assign a Wishlist')
Nexus.OrbPanel.Show();assert(NexusOrbPanel.plan:GetText()=='Restoring assigned Wishlist...' and not NexusOrbPanel.start:IsEnabled())
assert(Nexus.Store.State().loadoutWishlists[1].name=='Plan one','restoration must preserve exact association')
H2.perks.serverActiveSlot=1
H2.perks.serverBuildSlots={[1]={name='Owned',verified=true,echoes={{spellId=200001,quality=1,stacks=1}}}}
H2.Notify();A2.Poll();H2.Advance(.5)
assert(A2.Wishlist() and A2.Wishlist().name=='Plan one','local saved assignment resolves after active identity arrives')
Nexus.OrbPanel.Refresh();Nexus.Panel.Refresh()
assert(NexusOrbPanel.snapshot.config.name=='Plan one' and Nexus.Panel._lastModel.progress.wishlistName=='Plan one','main and Orb target resolve from the same restored association')
assert(#H2.actions==0,'restoration does not activate, upload or spend')
print('PASS durable assignment survives fresh boot, delayed identity and exact restoration')
