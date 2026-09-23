-- The import code is pasted into a StaticPopup edit box, and that box is
-- pooled and reused by every dialog. A dialog that declares no letter limit
-- inherits whatever the previous dialog left on the box, so an import that
-- follows the import-naming dialog can silently receive a cut string, and the
-- handler that dialog installed can blank a long value instead of cutting it.
-- Earlier acceptance called the importer with the full text directly, which
-- cannot see the field at all, so this exercises the real paste path: the
-- pooled box, its limit, its handlers, and what the accept handler reads.
-- The code here is SYNTHETIC, built with the product's own encoder at the
-- supported maximum. It is not any reporter's code and proves nothing about
-- one. It is deliberately longer than 1024 bytes, because the inherited
-- handler blanks a value above that length instead of shortening it, and a
-- shorter code cannot tell the two halves of the correction apart.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local W=Nexus.WishlistEditor

-- The supported maximum: 79 ordinary copies and 6 permanent copies, 85 entries
-- and 85 copies, with the seven-digit Echo ids and the 96-character name a
-- real plan can carry.
local entries={}
for i=1,6 do entries[#entries+1]={spellId=2100000+i,quality=(i%4),stacks=1,locked=true} end
for i=1,79 do
 entries[#entries+1]={spellId=2000000+i,quality=(i%4),stacks=1,locked=false}
end
local copies,locked=0,0
for _,e in ipairs(entries)do
 copies=copies+e.stacks
 if e.locked then locked=locked+e.stacks end
end
check(#entries==85 and copies==85 and locked==6,
 'the synthetic plan carries 85 entries, 85 copies and 6 permanent: '..#entries..'/'..copies..'/'..locked)
local name=string.rep('R',96)
local code=assert(Nexus.Codec.EncodeEBH1(entries,'MAGE',name))
check(#code>1024,'the encoded code is longer than the handler keeps: '..#code..' bytes')

-- What the accept handler actually hands to the importer.
local received
local importer=W.ImportEBH1String
W.ImportEBH1String=function(text,chosen)
 received=text
 return importer(text,chosen)
end

-- The import-naming dialog runs first, exactly as it does after any earlier
-- import, and configures the pooled edit box for a short safe name.
StaticPopup_Show('NEXUS_NAME_IMPORTED_WISHLIST','Earlier import',nil,{name='Earlier import'})
local named=assert(H.popup and H.popup.editBox,'the naming dialog uses the pooled edit box')
check((named:GetMaxLetters() or 0)==96,'the naming dialog limits that box: '..tostring(named:GetMaxLetters()))
check(named:GetScript('OnTextChanged')~=nil,'and installs its own display handler on it')
StaticPopup_Hide()

-- Now the import dialog, on the same pooled box, and a real paste into it.
StaticPopup_Show('NEXUS_IMPORT_WISHLIST')
local box=assert(H.popup and H.popup.editBox,'the import dialog uses the pooled edit box')
check(box==named,'it is the same pooled box the naming dialog configured')
-- Both halves of the correction are asserted separately: the field must be
-- large enough, and the naming dialog's handler must be gone. Either one alone
-- still loses the code.
check((box:GetMaxLetters() or 0)>=#code,
 'the field can hold a whole code: limit '..tostring(box:GetMaxLetters())..' for '..#code..' bytes')
check(box:GetScript('OnTextChanged')==nil,'the naming dialog handler no longer owns the field')
box:SetText(code)
check(box:GetText()==code,
 'the pasted code survives the field: kept '..#box:GetText()..' of '..#code..' bytes')
H.AcceptPopup()
check(received==code,
 'the accept handler reads the whole pasted code: '..tostring(received and #received)..' of '..#code)

-- The code really became a draft: the parse and the roles are unchanged by
-- this correction, so every entry arrives with its own role.
if H.popup and H.popup.which=='NEXUS_NAME_IMPORTED_WISHLIST' then
 H.popup.editBox:SetText('Raid ST Synthetic')
 H.AcceptPopup()
end
local draft=W.DebugDraftState()
check(draft.pending==79 and draft.pendingLock==6,
 'the imported draft keeps 79 ordinary and 6 permanent targets: '
 ..tostring(draft.pending)..'/'..tostring(draft.pendingLock))
W.ImportEBH1String=importer
print('PASS wishlist_import_paste_path: a maximum import code survives the pooled popup field and reaches the importer whole checks='..checks)
