-- W16 repair: the role picker keeps the selected Wishlist's identity across its delay.
-- A role confirmation compared the content of the live row with the selected one but not its
-- name, and built the opened record from the live row. A slot reused under the same content but
-- another name was then opened and overwritten. The selected name is now part of the selection,
-- and the editor that opens afterwards still refuses a slot that changes later.
-- Counted host uploads are the oracle. Synthetic mirrors only.
local H=dofile('tests/prototype/harness.lua')
local E={};for i=1,85 do E[i]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
local NAME='Unowned desired plan'
H.perks.serverBuildSlots={[1]={name='Active',verified=true,echoes={{spellId=200090,quality=2,stacks=1}}},
 [101]={name=NAME,verified=false,echoes=H.Clone(E)}}
H.perks.serverActiveSlot=1;H.locked={};H.Boot()
Nexus.Store.Settings().useCurrentLocksForUntagged=false
local A,W=Nexus.GameAdapter,Nexus.WishlistEditor
local n=0;local function check(v,m)assert(v,m);n=n+1 end
local function candidate(slot)for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==(slot or 101)then return c end end end
local function chooseFirstSix() for i=1,6 do _G['NexusWishlistRolePlus'..i]:Click()end end
local function uploads() local c=0 for _,a in ipairs(H.actions)do if a[1]=='upload' then c=c+1 end end return c end
local function frameButton(text)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end end
 error('visible button absent: '..text)
end
local function choices() return #(Nexus.Store.State().wishlistRoleChoices or {}) end

-- 1. Control: nothing changes during the picker; the editor opens and saves once.
do
 check(W.OpenForWishlist(candidate(),1),'the legacy plan opens the role picker')
 chooseFirstSix()
 check(NexusWishlistRoleConfirm:Click()==true,'the confirmation succeeds')
 frameButton('Save Wishlist'):Click()
 if H.popup then H.AcceptPopup();H.Advance(4) end
 check(uploads()==1,'an unchanged slot receives the one upload: '..uploads())
end

-- A legacy plan whose roles are not chosen yet (a plan whose content was confirmed before is
-- remembered and opens without the picker): 85 copies, content distinct per i.
local function legacy(i)
 local rows=H.Clone(E);rows[1].stacks=1+i
 for _=1,i do table.remove(rows) end
 return rows
end

-- 2. The slot is reused under the same content but another name while the picker is open.
do
 local rows=legacy(1)
 H.perks.serverBuildSlots[102]={name='Second plan',verified=false,echoes=H.Clone(rows)}
 H.Advance(4)
 local before,roles=uploads(),choices()
 check(W.OpenForWishlist(candidate(102),1),'the picker opens for the second plan')
 check(NexusWishlistRoleConfirm:IsVisible(),'the role picker is shown (the plan is not remembered)')
 chooseFirstSix()
 check(NexusWishlistRoleConfirm:IsEnabled(),'six locked targets are chosen')
 H.perks.serverBuildSlots[102].name='Renamed By Someone Else'
 check(NexusWishlistRoleConfirm:Click()==false,'a changed name is a changed Wishlist: the confirmation is refused')
 check(choices()==roles,'no role choice is stored for the other Wishlist')
 check(uploads()==before,'nothing is uploaded')
 NexusWishlistRoleCancel:Click()
end

-- 3. The slot is reused after the confirmation, before the editor saves.
do
 local rows=legacy(2)
 H.perks.serverBuildSlots[103]={name='Third plan',verified=false,echoes=H.Clone(rows)}
 H.Advance(4)
 check(W.OpenForWishlist(candidate(103),1),'the picker opens for the third plan')
 check(NexusWishlistRoleConfirm:IsVisible(),'the role picker is shown')
 chooseFirstSix()
 check(NexusWishlistRoleConfirm:Click()==true,'the confirmation succeeds with the slot unchanged')
 local before=uploads()
 H.perks.serverBuildSlots[103]={name='Someone Elses Plan',verified=false,echoes={{spellId=200001,quality=1,stacks=1}}}
 frameButton('Save Wishlist'):Click()
 if H.popup then H.AcceptPopup();H.Advance(4) end
 check(uploads()==before,'a slot reused after the confirmation is not uploaded to')
end

print('PASS stale_server_slot_roles checks='..n)
