-- The import code is pasted into a StaticPopup edit box, and that box is
-- pooled and reused by every dialog. A dialog that declares no letter limit
-- inherits whatever the previous dialog left on the box, so an import that
-- follows the import-naming dialog can silently receive a cut string.
-- Earlier acceptance called the importer with the full text directly, which
-- cannot see the field at all, so this exercises the real paste path: the
-- pooled box, its limit, its handlers, and what the accept handler reads.
-- The code here is SYNTHETIC, built with the product's own encoder at a
-- realistic size. It is not any reporter's code and proves nothing about one.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0)
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
local W=Nexus.WishlistEditor

-- A realistic wishlist: 73 distinct entries carrying 85 copies in total, six
-- of them permanent, exactly the shape a long raid import has.
-- 6 permanent entries of one copy each (the permanent maximum) and 67
-- ordinary entries carrying 79 copies: 73 entries, 85 copies, exactly the
-- supported 79 ordinary / 6 permanent / 85 total envelope.
local entries={}
for i=1,6 do entries[#entries+1]={spellId=310000+i,quality=(i%4),stacks=1,locked=true} end
for i=1,67 do
 entries[#entries+1]={spellId=300000+i,quality=(i%4),stacks=(i<=12) and 2 or 1,locked=false}
end
local copies,locked=0,0
for _,e in ipairs(entries)do
 copies=copies+e.stacks
 if e.locked then locked=locked+e.stacks end
end
check(#entries==73 and copies==85 and locked==6,
 'the synthetic plan carries 73 entries, 85 copies and 6 permanent: '..#entries..'/'..copies..'/'..locked)
local code=assert(Nexus.Codec.EncodeEBH1(entries,'MAGE','Raid ST Synthetic'))
check(#code>500,'the encoded code is a realistic length: '..#code..' bytes')

-- What the accept handler actually hands to the importer.
local received
local importer=W.ImportEBH1String
W.ImportEBH1String=function(text,name)
 received=text
 return importer(text,name)
end

-- The import-naming dialog runs first, exactly as it does after any earlier
-- import, and configures the pooled edit box for a short safe name.
StaticPopup_Show('NEXUS_NAME_IMPORTED_WISHLIST','Earlier import',nil,{name='Earlier import'})
local named=assert(H.popup and H.popup.editBox,'the naming dialog uses the pooled edit box')
check((named:GetMaxLetters() or 0)>0,'the naming dialog limits that box: '..tostring(named:GetMaxLetters()))
StaticPopup_Hide()

-- Now the import dialog, on the same pooled box, and a real paste into it.
StaticPopup_Show('NEXUS_IMPORT_WISHLIST')
local box=assert(H.popup and H.popup.editBox,'the import dialog uses the pooled edit box')
box:SetText(code)
check(box:GetText()==code,
 'the pasted code survives the field: kept '..#box:GetText()..' of '..#code..' bytes')
H.AcceptPopup()
check(received==code,
 'the accept handler reads the whole pasted code: '..tostring(received and #received)..' of '..#code)
local state=W.Draft and W.Draft() or nil
if state and state.entries then
 check(#state.entries==73,'the imported draft keeps every entry: '..#state.entries)
end
W.ImportEBH1String=importer
print('PASS wishlist_import_paste_path: a long import code survives the pooled popup field and reaches the importer whole checks='..checks)
