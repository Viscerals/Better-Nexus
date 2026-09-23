-- The export dialog shows the EBH1 code in the same pooled StaticPopup edit
-- box that the import-naming dialog configures for a 96-letter safe name, and
-- a dialog that declares no letter limit inherits both that limit and that
-- dialog's display handler. The code the player copies can therefore be cut,
-- or blanked when it is longer than the handler keeps, with no sign that
-- anything happened. The player who receives it reports that the code "does
-- not import", so the defect is reported on the other side of the transfer.
-- This drives the real sequence: import a code, name the imported wishlist,
-- then export. The code is SYNTHETIC, built with the product's own encoder at
-- the supported maximum, and is not any reporter's code.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)

-- 79 ordinary copies and 6 permanent copies: the supported maximum, with
-- seven-digit ids, so the code is longer than the 1024 bytes the inherited
-- display handler keeps.
local entries={}
for i=1,6 do entries[#entries+1]={spellId=2100000+i,quality=(i%4),stacks=1,locked=true} end
for i=1,79 do
 entries[#entries+1]={spellId=2000000+i,quality=(i%4),stacks=1,locked=false}
end
local code=assert(Nexus.Codec.EncodeEBH1(entries,'MAGE',string.rep('R',96)))
check(#code>1024,'the encoded code is longer than the handler keeps: '..#code..' bytes')

-- Import it through the real dialogs and name it: exactly what a player does
-- before exporting the same plan for somebody else.
StaticPopup_Show('NEXUS_IMPORT_WISHLIST')
local box=assert(H.popup and H.popup.editBox,'the import dialog uses the pooled edit box')
box:SetText(code)
H.AcceptPopup()
if H.popup and H.popup.which=='NEXUS_NAME_IMPORTED_WISHLIST' then
 H.popup.editBox:SetText('Raid ST Synthetic')
 H.AcceptPopup()
end
local draft=Nexus.WishlistEditor.DebugDraftState()
check(draft.pending==79 and draft.pendingLock==6,
 'the draft to be exported carries 79 ordinary and 6 permanent targets: '
 ..tostring(draft.pending)..'/'..tostring(draft.pendingLock))

StaticPopup_Show('NEXUS_EXPORT_WISHLIST')
local copyBox=assert(H.popup and H.popup.editBox,'the export dialog uses the pooled edit box')
check(copyBox:GetScript('OnTextChanged')==nil,
 'the naming dialog handler no longer owns the copy field')
local shown=copyBox:GetText()
check(#shown>1024,'the copy field is not cut to a name length: it shows '..#shown..' characters')
local parsed=Nexus.Codec.DecodeEBH1(shown,true)
check(type(parsed)=='table' and parsed.entries~=nil,'the copied text is still a decodable EBH1 code')
check(#parsed.entries==85,'the copied text carries every entry: '..#parsed.entries..' of 85')
print('PASS wishlist_export_copy_field: the copied EBH1 code is neither cut nor blanked by an inherited name field checks='..checks)
