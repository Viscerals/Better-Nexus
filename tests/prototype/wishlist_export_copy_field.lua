-- The export dialog shows the EBH1 code in the same pooled StaticPopup edit
-- box that the import-naming dialog configures for a 96-letter safe name, and
-- a dialog that declares no letter limit inherits both that limit and that
-- dialog's display handler. The code the player copies can therefore be cut,
-- or blanked when it is longer than the handler keeps, with no sign that
-- anything happened. The player who receives it reports that the code "does
-- not import", so the defect is reported on the other side of the transfer.
-- The field must also hold the exact code: the player copies what the field
-- holds, so a display projection that doubles a pipe changes the wishlist name
-- inside the code. This drives the real sequence: import a code, name the
-- imported wishlist, export it, and paste what was copied back in. The code is
-- SYNTHETIC, built with the product's own encoder at the supported maximum,
-- and is not any reporter's code.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)

-- 79 ordinary copies and 6 permanent copies: the supported maximum, with
-- seven-digit ids, so the code stays longer than the 1024 bytes the inherited
-- display handler keeps.
local entries,wanted={},{}
for i=1,6 do
 entries[#entries+1]={spellId=2100000+i,quality=(i%4),stacks=1,locked=true}
 wanted[2100000+i]={quality=(i%4),stacks=1,locked=true}
end
for i=1,79 do
 entries[#entries+1]={spellId=2000000+i,quality=(i%4),stacks=1,locked=false}
 wanted[2000000+i]={quality=(i%4),stacks=1,locked=false}
end
local code=assert(Nexus.Codec.EncodeEBH1(entries,'MAGE',string.rep('R',96)))
check(#code>1024,'the encoded code is longer than the handler keeps: '..#code..' bytes')

-- A pipe is legal in a wishlist name, and it is the character a display
-- projection changes.
local CHOSEN='Raid|ST Synthetic'

-- The pooled edit box already carries the client's own handler before any
-- Nexus dialog opens. Claiming the field must restore that handler, not clear
-- it: a cleared handler is a live-client regression that an empty harness box
-- cannot show by itself.
StaticPopup_Show('NEXUS_UPDATE_RELEASES','note')
local pooled=assert(H.popup and H.popup.editBox,'the pooled edit box exists before any EBH1 dialog')
local sentinel=function() end
pooled:SetScript('OnTextChanged',sentinel)
StaticPopup_Hide()

-- Import the code through the real dialogs and name it: exactly what a player
-- does before exporting the same plan for somebody else.
StaticPopup_Show('NEXUS_IMPORT_WISHLIST')
local box=assert(H.popup and H.popup.editBox,'the import dialog uses the pooled edit box')
check(box==pooled,'it is the same pooled box')
box:SetText(code)
H.AcceptPopup()
if H.popup and H.popup.which=='NEXUS_NAME_IMPORTED_WISHLIST' then
 H.popup.editBox:SetText(CHOSEN)
 H.AcceptPopup()
end
local draft=Nexus.WishlistEditor.DebugDraftState()
check(draft.pending==79 and draft.pendingLock==6,
 'the draft to be exported carries 79 ordinary and 6 permanent targets: '
 ..tostring(draft.pending)..'/'..tostring(draft.pendingLock))

StaticPopup_Show('NEXUS_EXPORT_WISHLIST')
local copyBox=assert(H.popup and H.popup.editBox,'the export dialog uses the pooled edit box')
check(copyBox:GetScript('OnTextChanged')==sentinel,
 'the copy field carries the handler it had before, not the naming handler')
local shown=copyBox:GetText()
check(#shown>1024,'the copy field is not cut to a name length: it shows '..#shown..' characters')
local parsed=Nexus.Codec.DecodeEBH1(shown,true)
check(type(parsed)=='table' and parsed.entries~=nil,'the copied text is still a decodable EBH1 code')
check(#parsed.entries==85,'the copied text carries every entry: '..#parsed.entries..' of 85')
-- The copied text is the code itself, not a projection of it: the name keeps
-- its single pipe, and every entry keeps its own id, quality, stacks and role.
check(parsed.name==CHOSEN,'the copied code keeps the exact wishlist name: '..tostring(parsed.name))
local seen,locked=0,0
for _,e in ipairs(parsed.entries)do
 local want=wanted[e.spellId]
 check(want~=nil,'entry '..tostring(e.spellId)..' is one of the exported targets')
 check(e.quality==want.quality and e.stacks==want.stacks,
  'entry '..tostring(e.spellId)..' keeps its quality and stacks: '..tostring(e.quality)..'/'..tostring(e.stacks))
 check((e.locked==true)==want.locked,'entry '..tostring(e.spellId)..' keeps its role')
 seen=seen+1
 if e.locked then locked=locked+1 end
end
check(seen==85 and locked==6,'every target is present once, with six permanent: '..seen..'/'..locked)
StaticPopup_Hide()

-- What was copied imports again, whole, on the other side of the transfer.
StaticPopup_Show('NEXUS_IMPORT_WISHLIST')
local back=assert(H.popup and H.popup.editBox,'the import dialog opens again')
back:SetText(shown)
check(back:GetText()==shown,'the copied code survives the paste: kept '..#back:GetText()..' of '..#shown)
H.AcceptPopup()
if H.popup and H.popup.which=='NEXUS_NAME_IMPORTED_WISHLIST' then
 H.popup.editBox:SetText('Round trip')
 H.AcceptPopup()
end
local again=Nexus.WishlistEditor.DebugDraftState()
check(again.pending==79 and again.pendingLock==6,
 'the round trip keeps 79 ordinary and 6 permanent targets: '
 ..tostring(again.pending)..'/'..tostring(again.pendingLock))
print('PASS wishlist_export_copy_field: the copied EBH1 code is exact, and it imports again checks='..checks)
