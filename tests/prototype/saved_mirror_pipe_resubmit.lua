-- Root actual UI reproduction of SPEC-R3-1; anonymous fake server, no native Lua.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('section_spec_r3_pipe')
local PLAN='Fire|Frost plan';local LINK='https://discord.com/channels/7/8/9';local OWNER='Artificial owner title'
local function E(id,n)return {spellId=id,quality=(id-200000)%4,stacks=n}end
local H=F.Boot(F.Database({mutate=function(db)db.chars[F.NAME].loadoutWishlists[1].name=PLAN end}),function(h)
 h.perks.serverBuildSlots={[1]={name='Artificial Saved Build',verified=true,echoes={E(200001,2),E(200002,1)}}}
 h.perks.serverActiveSlot=1
end)
local A,CB=Nexus.GameAdapter,Nexus.CommunityBuilds
local function Mirror()for _,b in pairs(CB.Builds() or {})do if b.importedSavedBuild==true and tonumber(b.serverSlot)==1 then return b end end end
local function Until(fn)for i=1,2000 do if fn()then return true end;H.Advance(.05,.05)end;return false end
local function Type(box,text)box:SetFocus();box:SetText('');box:Insert(text)end
C.setup(Nexus.StartupStatus().coreReady==true,'startup ready')
C.setup((A.GetLoadoutWishlist(1) or {}).name==PLAN,'real assignment retains existing pipe name')
CB.Show();C.setup(Until(function()local b=Mirror();return b and b.destinationProgress==3 end),'mirror imported at3/6')
local before=Mirror() or {};CB.ShowBuild(before.id)
C.setup(Until(function()local p=NexusCommunityBuildsFrame and NexusCommunityBuildsFrame._detailPanel;return p and p._nexusShownId==before.id end),'real detail opens')
local panel=NexusCommunityBuildsFrame._detailPanel
C.setup(panel.linkSaveBtn:IsShown() and panel.linkSaveBtn:IsEnabled(),'Save Link offered')
Type(panel.linkBox,LINK);panel.linkSaveBtn:Click()
Until(function()return (Mirror() or {}).link==LINK end)
local linked=Mirror() or {};print('OBSERVED generated',before.description,'link',tostring(linked.link))
C.expect(linked.link==LINK,'real Save Link accepts unchanged generated description')
panel.editBtn:Click();local popup=NexusEditPopup
C.setup(popup and popup:IsShown() and popup._editingId==before.id,'real Edit dialog opens')
C.setup(popup._editDescBox:_NexusRawText()==before.description,'description remains exact served text')
Type(popup._editTitleBox,OWNER);popup._saveBtn:Click()
Until(function()return (Mirror() or {}).title==OWNER end)
local edited=Mirror() or {};print('OBSERVED titleOnly title',edited.title,'popupShown',tostring(popup:IsShown()))
C.expect(edited.title==OWNER,'real title-only Edit saves changed title with unchanged generated description')
C.guard(edited.description==before.description,'unmodified generated description preserved through save')
C.guard(edited.id==before.id and edited.serverSlot==before.serverSlot,'mirror identity and slot preserved')
C.guard(edited.ownerKey==before.ownerKey and edited.ownerVerified==true and edited.isMine==true,'owner authority preserved')
C.guard(edited.recordBuildId==before.recordBuildId and edited.publishedBuildId==before.publishedBuildId,'bindings preserved')
C.guard((A.GetLoadoutWishlist(1) or {}).name==PLAN,'assignment retained')
C.guard(#H.actions==0 and #H.sent==0,'no game or network action')
C.finish('actual UI interaction; synthetic only')
