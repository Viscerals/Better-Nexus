-- Focused follow-on controls for ownership of an existing first-run handoff.
-- The exact independent actual-UI reproduction is a separate unchanged script.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
H.playerLevel=1;wipe(H.db)
H.AddEcho(201172,'Arcane Bombardment',0,5)
H.AddEcho(200767,'Arcane Bond',0,5)
H.perks.serverActiveSlot=0
local first={{spellId=201172,quality=0,stacks=1,locked=false}}
local second={{spellId=200767,quality=0,stacks=2,locked=false}}
H.perks.serverBuildSlots={[102]={name='First plan',verified=false,echoes=H.Clone(first)},
 [103]={name='Second plan',verified=false,echoes=H.Clone(second)}}
ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
 GetCharges=function()return 0 end,IsOfferPending=function()return false end,
 RequestCharges=function()end,ConfirmSpend=function()error('handoff tests cannot spend')end}
H.Boot()
local A=Nexus.GameAdapter
assert(A.SetFirstLoadoutWishlistIdentity('First plan',first))
local original=H.Clone(Nexus.Store.State().firstRunWishlist)
local function matching()
 local s=Nexus.Store.State()
 assert(type(s.firstRunWishlist)=='table' and T.Equal(s.firstRunWishlist,s.loadoutWishlists[1]),
  'proven current handoff mirrors the complete replacement record and assignment identity')
 return s
end
local function journal()
 if not ProjectEbonholdEchoJournal then CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)end
 ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
end
local function select(name)
 journal();NexusActiveWishlistSelector:Click()
 for _,r in ipairs(NexusWishlistOnlyPicker.children)do
  if r.nameButton and r.nameButton:IsVisible() and r.nameButton.text:GetText():find(name,1,true)then
   r.nameButton:Click();return
  end
 end
 error('actual selection row missing: '..name)
end
local identity=original.assignmentId
for _,name in ipairs({'Second plan','First plan','First plan','Second plan'})do
 select(name)
 local s=matching()
 assert(s.firstRunWishlist.name==name and s.firstRunWishlist.assignmentId~=identity,'explicit picker replacement stamps and mirrors only its new target')
 identity=s.firstRunWishlist.assignmentId
end
journal();NexusActiveWishlistSelector:Click();NexusWishlistOnlyPicker.clearRow:Click()
assert(Nexus.Store.State().loadoutWishlists[1]==nil and A.AssignedWishlist().state=='unassigned','different and repeated selection still fully unassigns its own handoff')
assert(#H.actions==0,'picker and Unassign submit no service actions')

for _,method in ipairs({'selected-source','identity'})do
 for _,mode in ipairs({'matching','false','nil','different-id','legacy','no-handoff'})do
  assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
   s.firstRunWishlist=H.Clone(original);s.loadoutWishlists={[1]=H.Clone(original)}
   if mode=='false' then s.firstRunWishlist=false
   elseif mode=='nil' then s.firstRunWishlist=nil
   elseif mode=='different-id' then s.loadoutWishlists[1].assignmentId='assigned:unrelated'
   elseif mode=='legacy' then s.firstRunWishlist.assignmentId=nil;s.loadoutWishlists[1].assignmentId=nil
   elseif mode=='no-handoff' then s.loadoutWishlists[1]=nil end
   s.loadoutWishlists[2]=H.Clone(original);s.loadoutWishlists[2].assignmentId='assigned:other-slot'
  end))
  local before=H.Clone(Nexus.Store.State())
  if method=='identity' then assert(A.SetFirstRunWishlistIdentity('Second plan',second))
  else
   local candidate
   for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==103 then candidate=c end end
   assert(candidate and A.SetFirstRunWishlist(103,candidate))
  end
  local after=Nexus.Store.State()
  assert(after.firstRunWishlist.name=='Second plan' and after.firstRunWishlist.echoes[1].spellId==200767
   and after.firstRunWishlist.echoes[1].stacks==2,'explicit assignment installs exact replacement content')
  if mode=='matching' then matching()
  else assert(T.Equal(before.loadoutWishlists[1],after.loadoutWishlists[1]),'replacement neither creates nor changes an unproven handoff: '..method..'/'..mode)end
  assert(T.Equal(before.loadoutWishlists[2],after.loadoutWishlists[2]),'unrelated numbered slot remains exact')
  local saved=H.Clone(after)
  assert(not A.SetFirstRunWishlist(999),'invalid source remains refused')
  assert(T.Equal(saved,Nexus.Store.State()),'refused source cannot alter the existing handoff')
 end
end
assert(#H.actions==0,'all companion cases remain local with no gameplay or upload')
print('PASS actual repeated/different picker changes; complete matching handoff; selected-source and identity setters; unrelated/legacy/nil/false/no-handoff guards')
