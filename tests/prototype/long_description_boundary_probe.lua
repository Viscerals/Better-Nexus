-- Root's minimal anonymous boundary probe. No witness encoding is asserted.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('long_description_boundary_probe')
local PLAN=string.rep('A',990)..' plan'
local OWNER='Artificial owner title'
local function E(id,n)return {spellId=id,quality=(id-200000)%4,stacks=n}end
local H=F.Boot(F.Database({mutate=function(db)db.chars[F.NAME].loadoutWishlists[1].name=PLAN end}),function(h)
 h.perks.serverBuildSlots={[1]={name='Artificial Saved Build',verified=true,echoes={E(200001,2),E(200002,1)}}}
 h.perks.serverActiveSlot=1
end)
local A,CB=Nexus.GameAdapter,Nexus.CommunityBuilds
local function Mirror()
 for _,b in pairs(CB.Builds() or {})do if b.importedSavedBuild==true and tonumber(b.serverSlot)==1 then return b end end
end
local function Until(fn)
 for i=1,2000 do if fn()then return true end;H.Advance(.05,.05)end
 return false
end
C.setup(Nexus.StartupStatus().coreReady==true,'startup ready')
C.setup((A.GetLoadoutWishlist(1) or {}).name==PLAN,'the actual assignment resolves the 995-byte plan name')
CB.Show()
C.setup(Until(function()local b=Mirror();return b and b.destinationProgress==3 end),'initial mirror imported at3/6')
local before=Mirror() or {}
C.setup(before.id~=nil and before.destinationWishlistName==PLAN and #tostring(before.description)<2000,'valid served generated description and assigned name')
CB.ShowBuild(before.id)
C.setup(Until(function()local p=NexusCommunityBuildsFrame and NexusCommunityBuildsFrame._detailPanel;return p and p._nexusShownId==before.id end),'real detail opens')
local panel=NexusCommunityBuildsFrame._detailPanel
panel.editBtn:Click()
local popup=NexusEditPopup
C.setup(popup and popup:IsShown() and popup._editingId==before.id,'real Edit dialog opens')
popup._editTitleBox:SetFocus();popup._editTitleBox:SetText('');popup._editTitleBox:Insert(OWNER)
C.setup(popup._editDescBox:_NexusRawText()==before.description,'description remains untouched')
popup._saveBtn:Click()
C.setup(Until(function()return (Mirror() or {}).title==OWNER end),'title-only edit committed')
H.perks.serverBuildSlots[1].echoes=H.Clone(F.PLAN);H.Notify();A.Poll();CB.Hide();CB.Show()
C.setup(Until(function()return (Mirror() or {}).destinationProgress==6 end),'signature-changing reimport reaches6/6')
local after=Mirror() or {}
print('OBSERVED','description bytes='..#tostring(after.description),'progress='..tostring(after.destinationProgress)..'/'..tostring(after.destinationTotal))
C.expect(type(after.description)=='string' and after.description:find(PLAN,1,true) and after.description:find('6/6',1,true) and not after.description:find('3/6',1,true),'untouched generated description follows current assigned progress for an admitted plan name')
C.guard(after.title==OWNER,'owner title preserved')
C.guard(after.id==before.id and after.serverSlot==before.serverSlot,'mirror identity and slot preserved')
C.guard(after.destinationWishlistName==PLAN and (A.GetLoadoutWishlist(1) or {}).name==PLAN,'assignment preserved')
C.guard(after.ownerKey==before.ownerKey and after.ownerVerified==true and after.isMine==true,'owner authority preserved')
C.guard(after.recordBuildId==before.recordBuildId and after.publishedBuildId==before.publishedBuildId,'bindings preserved')
C.guard(#H.actions==0,'no native action')
C.finish('anonymous valid-name boundary; offline only')
