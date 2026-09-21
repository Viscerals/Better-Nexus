-- Reuse the independent reproduction verbatim before testing its downstream
-- consumers. Only capture its returned synthetic harness; no product seam is replaced.
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/orbs_support.lua' then H=result end
 return result
end
dofile('tests/prototype/assignment_distinct_designs.lua')
dofile=originalDofile
assert(H)
local A,W=Nexus.GameAdapter,Nexus.WishlistEditor
local function export(id,wrong)
 local box=CreateFrame('EditBox',nil,UIParent)
 StaticPopupDialogs.NEXUS_EXPORT_WISHLIST.OnShow({editBox=box})
 local parsed=assert(Nexus.Codec.DecodeEBH1(box._nexusExplicitExportText))
 local found=false
 for _,e in ipairs(parsed.entries)do
  if e.locked then
   assert(e.spellId~=wrong,'editor must not load the other assignment permanent design')
   if e.spellId==id then assert(e.quality==id%4 and e.stacks==1);found=true end
  end
 end
 assert(found,'normal editor export includes the exact assigned permanent target')
end
local function inspect(h,slot,id,wrong,name)
 local a,w=Nexus.GameAdapter,Nexus.WishlistEditor
 h.perks.serverActiveSlot=slot;h.Notify();a.Poll();Nexus.RequestRecompute();h.Advance(.5)
 local linked=assert(a.GetLoadoutWishlist(slot))
 assert(linked.name==name and linked.designTargets[id] and not linked.designTargets[wrong])
 assert(w.OpenForWishlist(linked,slot));export(id,wrong)
 Nexus.Panel.Refresh();Nexus.OrbPanel.Show()
 local progress=Nexus.Panel._lastModel.progress
 assert(progress.wishlistName==name and NexusOrbPanel.snapshot.config.name==name,'normal main and Orb views agree')
 local labels={};for _,label in ipairs(progress.toLock or {})do labels[label]=true end
 assert(labels[h.names[id]],'normal main permanent-target consumer uses the assignment design')
 assert(not labels[h.names[wrong]],'main does not inherit the other design')
 assert(NexusPanel.toLockText:GetText():find(h.names[id],1,true),'normal permanent-target fontstring renders the same design')
end
inspect(H,1,200080,200081,'Plan A');inspect(H,2,200081,200080,'Plan B')
local candidates={}
for _,candidate in ipairs(A.GetWishlistCandidates())do candidates[candidate.name]=candidate end
assert(candidates['Plan A'].designTargets[200080] and candidates['Plan B'].designTargets[200081],'assignment picker retains both local full designs')
assert(W.ResolveAndAssignWishlist(candidates['Plan A'],2),'actual assignment handler can copy an exact local full plan')
assert(A.AssignedWishlist().name=='Plan A' and A.AssignedWishlist().wishlist.designTargets[200080])
assert(W.ResolveAndAssignWishlist(candidates['Plan B'],2))
local function serialize(value)
 if type(value)=='string'then return string.format('%q',value)end
 if type(value)~='table'then return tostring(value)end
 local out={'{'};for key,item in pairs(value)do out[#out+1]='['..serialize(key)..']='..serialize(item)..','end
 return table.concat(out)..'}'
end
local saved=serialize(NexusDB)
local server=H.Clone(H.perks.serverBuildSlots)
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
NexusDB=assert(loadstring('return '..saved))()
local H2=dofile('tests/prototype/orbs_support.lua')
assert(Nexus.StartupStatus().state=='ready','complete assignments obey unchanged saved-graph bounds')
H2.perks.serverBuildSlots=server
inspect(H2,1,200080,200081,'Plan A');inspect(H2,2,200081,200080,'Plan B')
H2.perks.serverActiveSlot=1;H2.granted={['Echo 80']={{spellId=200080,quality=0}}}
H2.Notify();Nexus.GameAdapter.Poll()
assert(not Nexus.OrbRuntime.Start(1) and H2.Count('orb-spend')==0,'restored exact permanent design still protects its only acquired copy')
-- Two equal-name/equal-content mirrors cannot identify which row to overwrite.
local rolled=Nexus.GameAdapter.GetLoadoutWishlist(1).echoes
H2.perks.serverBuildSlots[101]={name='Plan A',verified=false,echoes=H2.Clone(rolled)}
H2.perks.serverBuildSlots[102]={name='Plan A',verified=false,echoes=H2.Clone(rolled)}
H2.Notify();Nexus.GameAdapter.Poll()
local localPlan=Nexus.GameAdapter.GetLoadoutWishlist(1)
assert(localPlan.slot==nil and localPlan.designTargets[200080],'ambiguous mirrored slot retains exact local plan')
assert(Nexus.WishlistEditor.OpenForWishlist(localPlan,1));export(200080,200081)
for _,button in ipairs(H2.frames)do
 if button.kind=='Button' and button:IsVisible() and button:GetText()=='Save Wishlist'then button:Click()end
end
assert(#H2.actions==0,'inspection, export, restore and protection make no game mutation')
print('PASS distinct full designs through assignment picker, main model, real editor export, fresh boot and actual spending guard')
