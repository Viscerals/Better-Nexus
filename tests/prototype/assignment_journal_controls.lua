-- Reuse the exact real Journal reproduction, then follow its adjacent actual controls.
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/orbs_support.lua' then H=result end
 return result
end
dofile('tests/prototype/assignment_journal_picker.lua')
dofile=originalDofile
assert(H)
local function checkExport()
 local box=CreateFrame('EditBox',nil,UIParent)
 StaticPopupDialogs.NEXUS_EXPORT_WISHLIST.OnShow({editBox=box})
 local parsed=assert(Nexus.Codec.DecodeEBH1(box._nexusExplicitExportText))
 local a,b=false,false
 for _,row in ipairs(parsed.entries)do if row.locked then
  a=a or row.spellId==200080;b=b or row.spellId==200081
 end end
 assert(b and not a,'actual Journal edit control opens the selected complete design')
end
Nexus.JournalTab.RefreshAssociations()
assert(NexusAssociatedWishlistDesignButton:IsEnabled());NexusAssociatedWishlistDesignButton:Click();checkExport()
NexusEditorFrame:Hide();ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
NexusActiveWishlistSelector:Click()
local gear
for _,row in ipairs(NexusWishlistOnlyPicker.children)do if row.nameButton then
 local label=row.nameButton.text:GetText()
 if label:find('Plan A',1,true)then assert(not label:find('[Selected]',1,true),'equal rolled contents cannot mark Plan A as selected')end
 if label:find('Plan B',1,true)then assert(label:find('[Selected]',1,true),'exact assignment has selected marker');gear=row.gear end
end end
assert(gear);gear:Click();checkExport()
H.granted={['Echo 81']={{spellId=200081,quality=1}}};H.Notify();H.A.Poll()
assert(not Nexus.OrbRuntime.Start(1),'required copy after visible Journal assignment must remain reserved')
assert(H.Count('orb-spend')==0 and H.Count('take')==0,'visible controls never bypass source protection')
print('PASS Journal associated Edit, row gear, exact Selected marker, export and required-copy guard')
