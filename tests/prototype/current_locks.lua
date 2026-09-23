-- P1.4 actual import/edit/assign/save path, synthetic untagged85 and current
-- permanent locks. No native game or player data. Defaults differ from P1.3.
local H=dofile('tests/prototype/harness.lua')
local T=dofile('tests/prototype/startup_support.lua')
local entries,lockedIds={},{}
for i=1,85 do
 local id=200000+i
 entries[i]={spellId=id,quality=i%4,stacks=1}
 if i>79 then lockedIds[#lockedIds+1]=id end
end
-- Deliberately different current loadout; physical lock ordering reversed.
H.perks.serverBuildSlots={[1]={name='Current',verified=true,echoes={{spellId=200090,quality=2,stacks=1}}},
 [101]={name='Legacy85',verified=false,echoes=H.Clone(entries)}}
H.perks.serverActiveSlot=1
for i=#lockedIds,1,-1 do H.locked[#H.locked+1]={spellId=lockedIds[i],stacks=1} end
H.Boot()
local A,E=Nexus.GameAdapter,Nexus.WishlistEditor
local checks=0
local function check(v,msg)assert(v,msg);checks=checks+1 end
local function candidate(slot)
 for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==(slot or 101)then return c end end
end
local function split(echoes)
 local o,l=0,0
 for _,e in ipairs(echoes)do if e.locked==true then l=l+e.stacks else o=o+e.stacks end end
 return o,l
end
local function button(text)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end end
 error('button not found: '..text)
end
local original=H.Clone(H.locked);local mirrors=H.Clone(H.perks.serverBuildSlots)
local actions=#H.actions
local c=candidate()
check(A.WishlistEvidenceState(c)=='evidence-pending','source remains untagged before explicit user action')
check(E.OpenForWishlist(c,1),'opening exact source succeeds')
check(not NexusWishlistRolePicker or not NexusWishlistRolePicker:IsShown(),'EXPECTED RED: matching current locks avoid the modal entirely')
check(E.DebugPendingCount()==79,'all ordinary79 draft entries retained')
check(#H.actions==actions,'opening makes no game action, upload, or resource call')
check(T.Equal(original,H.locked) and T.Equal(mirrors,H.perks.serverBuildSlots),'live locks and mirrors unchanged')
c=candidate()
local o,l=split(c.echoes);check(o==79 and l==6,'valid complete 79+6 split')
check(c.evidenceSource=='current-locks','automatic choice has honest local-plan provenance')
check(A.WishlistEvidenceState(c)=='actionable','local plan usable without equipped-build equality')
SlashCmdList.NEXUS('status')
check(table.concat(H.chat,'\n'):find('auto OFF',1,true),'fallback does not enable master automation')
local remembered=H.Clone(Nexus.Store.State().wishlistRoleChoices)
check(#remembered==1 and remembered[1].source=='current-locks','source of role choice retained')
-- Subsequent different owned locks do not rewrite an already chosen plan.
H.locked={{spellId=200001,stacks=1}};H.Notify()
check(E.OpenForWishlist(candidate(),1),'reopen uses exact previously stored plan')
local after=candidate();local ao,al=split(after.echoes)
check(ao==79 and al==6 and T.Equal(remembered,Nexus.Store.State().wishlistRoleChoices),'owned changes do not alter prior desired roles')
H.locked=H.Clone(original);H.Notify()
check(E.ResolveAndAssignWishlist(candidate(),1),'actual local assignment works')
check(A.GetLoadoutWishlist(1)~=nil,'association resolvable')
button('Save Wishlist'):Click();H.AcceptPopup()
check(not E.IsApplyPending(),'save has completed')
local action=H.actions[#H.actions];check(action and action[1]=='upload' and #action[4]==79,'only ordinary79 uploaded')
check(E.OpenForWishlist(candidate(),1),'saved server mirror reopens')
local so,sl=split(candidate().echoes);check(so==79 and sl==6,'reopen preserves six locked targets')
local textParts={};for _,e in ipairs(entries)do textParts[#textParts+1]=e.spellId..'.'..e.quality..'.'..e.stacks end
local raw='EBH1:'..table.concat(textParts,',')..':MAGE:Untyped'
E.ImportEBH1String(raw,'Imported using locks')
check(not NexusWishlistRolePicker or not NexusWishlistRolePicker:IsShown(),'actual raw import avoids dialog')
check(E.DebugPendingCount()==79,'raw import retains ordinary79')
-- Genuine incomplete match keeps all records and exposes a working fallback.
local mismatch=H.Clone(entries);mismatch[85]={spellId=200086,quality=2,stacks=1}
H.perks.serverBuildSlots[102]={name='Different contents',verified=false,echoes=mismatch}
check(E.OpenForWishlist(candidate(102),1),'mismatched build opens fallback')
local dialog=assert(NexusWishlistRolePicker)
check(dialog:IsShown() and not NexusWishlistRoleConfirm:IsEnabled(),'five matching locks do not silently validate ordinary80')
check(dialog:GetWidth()==610 and dialog:GetHeight()==510,'fallback owns only its panel, not full screen')
check(dialog:GetFrameStrata()=='FULLSCREEN_DIALOG','explicit high modal strata')
check(NexusWishlistRoleCancel:GetFrameLevel()>dialog:GetFrameLevel(),'cancel above input panel')
check(NexusWishlistRolePlus1:GetFrameLevel()>dialog:GetFrameLevel(),'rows above input panel')
check(dialog.opaqueBackground~=nil,'solid readable background installed')
check(not NexusEditorFrame:IsShown(),'old editor is not an input competitor')
NexusWishlistRoleCancel:Click()
check(not dialog:IsShown() and NexusEditorFrame:IsShown(),'cancel returns the existing editor without resetting draft')
-- Manual option is preserved through the real settings command, not test bypass.
SlashCmdList.NEXUS('currentlocks off')
check(Nexus.Store.Settings().useCurrentLocksForUntagged==false,'manual preference available')
check(E.OpenForWishlist(candidate(102),1),'manual fallback opens')
check(dialog.count:GetText():find('Locked targets 0/6',1,true),'manual choice does not silently suggest roles')
NexusWishlistRolePlus1:Click()
check(dialog.count:GetText():find('Locked targets 1/6',1,true),'real row button changes the draft')
NexusWishlistRoleNext:Click()
check(dialog.pageLabel:GetText()=='Page 2 / 9','paging remains operable')
NexusWishlistRoleCancel:Click()
SlashCmdList.NEXUS('currentlocks on')
check(Nexus.Store.Settings().useCurrentLocksForUntagged==true,'default policy can be restored')
check(T.Equal(H.locked,original),'no lock changes in complete workflow')
print('PASS current-lock default, import/save/reopen/assignment, fallback layering, and opt-out checks='..checks)
