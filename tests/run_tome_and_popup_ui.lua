local H=dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/WishlistOverlay.lua"); dofile("core/WishlistModel.lua"); dofile("core/WishlistController.lua"); dofile("ui/WishlistRenderer.lua"); dofile("ui/WishlistEditor.lua")
local A=Nexus.GameAdapter
H.discovered={[200100]=true}
H.FireEvent("SPELLS_CHANGED"); H.FireEvent("PLAYER_ENTERING_WORLD"); H.Advance(1)
local missing=A.UnknownTomesForEchoes({{spellId=200100},{spellId=200104},{spellId=200700}})
assert(#missing==2,"unknown tome detector should exclude learned tomes and report two unknown gates")
NexusDB=NexusDB or {}
Nexus.WishlistEditor.Init(A,Nexus.Model)
Nexus.WishlistEditor.Show()
-- Native 3.3.5 reproduced DIALOG/50 editor covering StaticPopup1 at
-- DIALOG/1, including its Save Changes button. The editor must stay below
-- the client's confirmation layer; increasing a global popup is not ours.
local strataOrder = {BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,
    FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
local editor = assert(_G.NexusEditorFrame)
local popupStrata, popupLevel = "DIALOG", 1
assert(strataOrder[editor:GetFrameStrata()] < strataOrder[popupStrata]
    or (editor:GetFrameStrata() == popupStrata
        and editor:GetFrameLevel() < popupLevel),
    "Wishlist editor covers native Save Changes confirmation")
Nexus.WishlistEditor.ToggleDisplayPopup()
local popup=_G.NexusDisplayPopup
assert(popup and popup:IsShown(),"display settings popup did not open")
assert(popup:GetFrameStrata()=="TOOLTIP","display settings must render above the editor")
assert((popup:GetFrameLevel() or 0)>50,"display settings frame level is not above the editor")
print("unknown tome tracking and editor popup z-order -- OK")

-- Real facade/button/controller regression from independent native review.
do
local H=dofile('tests/harness.lua')
dofile('data/DefaultProfile.lua')
dofile('logic/Model.lua')
dofile('core/Store.lua')
dofile('core/GameAdapter.lua')
dofile('core/WishlistModel.lua')
dofile('core/WishlistController.lua')
dofile('ui/WishlistRenderer.lua')
NexusDB={settingsVersion=2,settings={},chars={},dpsCapture={}}
H.BootstrapStoreReady()
local A=Nexus.GameAdapter
A.Catalog=function() return {rows={[810001]={spellId=810001,groupId=810001,name='Echo',quality=2,maxStack=1,classMask=1}},playerMask=1} end
A.Owned=function() return {bySpell={}} end
A.LockedOwned=function() return {bySpell={}} end
A.Wishlist=function() return nil end
A.GetWishlistCandidates=function() return {} end
A.Slots=function() return {activeSlot=0,maxSlots=5,bySlot={}} end
A.GetLoadoutWishlist=function() return nil end
local upload,association,uploadCount
uploadCount=0
A.UploadWishlist=function(slot,name,echoes) uploadCount=uploadCount+1;upload={slot=slot,name=name,echoes=echoes};return true end
A.UpdateWishlistAssociationAfterSave=function(loadout,slot,name,echoes) association={loadout=loadout,slot=slot,name=name};return true end
Nexus.Panel={AttachMenuFrame=function() end,CloseOtherWindows=function() end}
Nexus.Theme={StyleWindow=function() end,StyleTree=function() end}
local created={}
local create=CreateFrame
CreateFrame=function(kind,name,parent,template) local f=create(kind,name,parent,template);f.kind=kind;f.parent=parent;created[#created+1]=f;return f end
local hidden=0
StaticPopup_Hide=function(which) hidden=hidden+1; if H.lastStaticPopup and H.lastStaticPopup.which==which then H.lastStaticPopup=nil end end
dofile('ui/WishlistEditor.lua')
local E=Nexus.WishlistEditor
E.Init(A,Nexus.Model)
assert(E.OpenForWishlist({slot=1,name='Original',key='original',echoes={{spellId=810001,quality=2,stacks=1}},lockEvidenceVersion=1},1))
local main=H.frames.NexusEditorFrame
local save
for _,f in ipairs(created) do if f.kind=='Button' and f.parent==main and f.text=='Save Wishlist' then save=f end end
assert(save,'save button unavailable')
save:GetScript('OnClick')(save)
assert(H.lastStaticPopup and H.lastStaticPopup.data.slot==1,'save dialog not opened')
local oldData=H.lastStaticPopup.data
local oldAccept=StaticPopupDialogs[H.lastStaticPopup.which].OnAccept
main:Hide()
main:GetScript('OnHide')(main)
assert(E.OpenForWishlist({slot=2,name='Reopened',key='reopened',echoes={{spellId=810001,quality=2,stacks=1}},lockEvidenceVersion=1},2))
assert(H.lastStaticPopup==nil, 'closed editor retained a stale save confirmation')
oldAccept({},oldData)
assert(upload==nil and association==nil,'stale confirmation changed an unrelated association')
save:GetScript('OnClick')(save)
assert(H.lastStaticPopup and H.lastStaticPopup.data.slot==2)
local accepted=H.lastStaticPopup.data
assert(H.AcceptLastStaticPopup())
assert(upload.slot==2 and association.loadout==2 and association.slot==2,
    'current confirmation lost its intended association')
oldAccept({},accepted)
assert(uploadCount==1,'save confirmation committed twice')
save:GetScript('OnClick')(save)
local cancelled=H.lastStaticPopup
assert(type(StaticPopupDialogs[cancelled.which].OnCancel)=='function',
    'Cancel does not invalidate the pending confirmation')
StaticPopupDialogs[cancelled.which].OnCancel({},cancelled.data)
oldAccept({},cancelled.data)
assert(uploadCount==1,'cancelled confirmation committed')
A.UploadWishlist=function() uploadCount=uploadCount+1;return false,'spacing' end
save:GetScript('OnClick')(save)
assert(H.AcceptLastStaticPopup() and E.IsApplyPending(),'retry fixture not pending')
main:Hide()
main:GetScript('OnHide')(main)
E._PumpApplyRetry()
assert(not E.IsApplyPending() and uploadCount==2,'closed editor retried a cancelled save')
print('Wishlist confirmation close/reopen, context, cancel, duplicate and retry ownership -- OK')
end
