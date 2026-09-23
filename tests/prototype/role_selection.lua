-- Native-reported untagged 85-entry import, exercised through actual adapter,
-- editor, button callbacks, controller, Store and mock Ebonhold services.
-- Test inputs contain no player SavedVariables. No live game/network access.
local H=dofile('tests/prototype/harness.lua')
local raw=[==[EBH1:200050.2.1,200052.2.1,200063.2.1,200205.2.1,200227.2.1,200228.3.1,200230.3.1,200232.3.1,200236.3.1,200237.3.1,200240.3.1,200259.3.1,200270.3.1,200429.0.1,200494.2.1,200495.2.1,200496.2.1,200583.3.1,200585.3.1,200592.3.1,200597.3.1,200601.3.1,200606.3.1,200621.3.1,200627.3.1,200632.3.1,200635.3.1,200639.3.1,200678.2.1,200679.2.1,200690.2.1,200693.3.1,200695.3.1,200722.2.1,200726.2.1,200728.2.1,200730.2.1,200734.2.1,200738.2.1,200742.2.1,200756.3.1,200780.3.1,200798.3.1,200808.3.1,200838.3.1,200844.3.1,200852.2.1,200882.2.1,200886.2.1,200888.2.1,200894.2.1,200896.2.1,200898.2.1,200900.2.1,200950.2.1,200956.3.1,200960.3.1,200962.3.1,201250.2.1,201254.3.1,201256.3.1,201258.3.1,201262.3.1,201270.3.1,201276.3.1,201298.3.1,201304.3.1,201308.3.1,201312.3.1,201324.3.1,201332.3.1,201336.3.1,201340.3.1,201356.3.1,201360.3.1,201366.3.1,201370.3.1,201378.3.1,201382.3.1,201388.3.1,201398.3.1,201406.3.1,201410.3.1,201424.3.1,201428.3.1:MAGE:250 mio]==]
local lockIds={201262,201270,201250,200690,200756,200882}
local names={[200690]="Reaper's Reprieve",[200756]="Overtime Conversion",[200882]="Arcane Density",
 [201250]="Echoing Tides",[201262]="Accelerated Decay",[201270]="Armor Mastery"}
local entries={}
for id,q,copies in raw:match('^EBH1:([^:]+)'):gmatch('(%d+)%.(%d+)%.(%d+)')do
 id,q,copies=tonumber(id),tonumber(q),tonumber(copies)
 H.AddEcho(id,names[id] or ('Target '..id),q,10)
 entries[#entries+1]={spellId=id,quality=q,stacks=copies,locked=false}
end
H.AddEcho(299998,'Different current build',1,10)
H.perks.serverBuildSlots={
 [1]={name='Current loadout',verified=true,echoes={{spellId=299998,quality=1,stacks=1,locked=false}}},
 [101]={name='250 mio untagged',verified=false,echoes=H.Clone(entries)},
}
H.perks.serverActiveSlot=1
for _,id in ipairs(lockIds)do H.locked[#H.locked+1]={spellId=id,stacks=1}end
H.Boot()
Nexus.Store.Settings().useCurrentLocksForUntagged=false -- Explicit manual-choice control; automatic path has separate tests.
local A,Editor=Nexus.GameAdapter,Nexus.WishlistEditor
local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
local function equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local function plan(slot)
 for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==(slot or 101)then return c end end
end
local function clone(v)return H.Clone(v)end
local function namedButton(name)return assert(_G[name],name..' missing')end
local function roles(es)
 local ordinary,locked=0,0
 for _,e in ipairs(es or {})do if e.locked==true then locked=locked+e.stacks
 elseif e.locked==false then ordinary=ordinary+e.stacks else return -1,-1 end end
 return ordinary,locked
end
local function clickSave()
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible()
  and (f:GetText()=='Save Wishlist' or f:GetText()=='Create Wishlist')then
  local before=#H.actions;f:Click();H.AcceptPopup()
  return #H.actions==before+1 and H.actions[#H.actions][1]=='upload' and not Editor.IsApplyPending()
 end end
 error('actual editor Save button not found')
end
local p=assert(plan())
check(A.WishlistEvidenceState(p)=='evidence-pending','baseline remains unresolved without user confirmation')
check(not A.SetLoadoutWishlist(1,101,p),'unconfirmed plan still cannot be assigned')
local before=clone(Nexus.Store.State());local live=clone(H.perks.serverBuildSlots);local owned=clone(H.locked)
check(Editor.OpenForWishlist(p,1)==true,'EXPECTED RED: unresolved legacy build opens explicit locked-target choice')
local dialog=assert(_G.NexusWishlistRolePicker,'EXPECTED RED: real role picker exists')
check(dialog:IsShown(),'role picker visible instead of waiting forever')
check(not namedButton('NexusWishlistRoleConfirm'):IsEnabled(),'85 unresolved copies cannot be confirmed as ordinary')
check(equal(before,Nexus.Store.State()),'opening does not alter saved state')
local beforeActions=#H.actions
namedButton('NexusWishlistRoleCancel'):Click()
check(not dialog:IsShown() and equal(before,Nexus.Store.State()),'cancel is no-write')
check(Editor.OpenForWishlist(p,1),'reopen unresolved')
namedButton('NexusWishlistRoleUseOwned'):Click()
check(dialog.message:GetText():find('currently locked Echoes',1,true)
 and not dialog.message:GetText():find('owned locks',1,true),'T07/T12 actual role-picker explanation uses locked-target vocabulary')
check(dialog.count:GetText():find('Rolled copies 79/79',1,true) and dialog.count:GetText():find('Locked targets 6/6',1,true),'display-order-independent six matching suggestions')
check(equal(before,Nexus.Store.State()),'suggestions are not confirmation')
check(namedButton('NexusWishlistRoleConfirm'):IsEnabled(),'complete chosen split enables confirmation')
check(namedButton('NexusWishlistRoleConfirm'):Click()==true,'explicit role confirmation opens ordinary editor')
check(not dialog:IsShown(),'confirmation closes modal')
check(#H.actions==beforeActions,'role selection does not upload, spend, lock, unlock, or assign')
check(equal(live,H.perks.serverBuildSlots) and equal(owned,H.locked),'server mirrors and locked Echoes unchanged')
local saved=assert(plan())
check(saved.evidenceSource=='user-confirmed' and A.WishlistEvidenceState(saved)=='actionable','local plan roles resolve without equipped-build equality')
local o,l=roles(saved.echoes);check(o==79 and l==6,'complete original 79+6 retained')
check(Editor.DebugPendingCount()==79,'ordinary draft has all 79 entries')
local f=Editor._fulfilledDraftTargets;local cnt=0;for _ in pairs(f)do cnt=cnt+1 end
check(cnt==6,'all six owned design targets retained in draft')
check(clickSave()==true,'actual Save confirmation succeeds')
local action=H.actions[#H.actions]
check(action and action[1]=='upload' and action[2]==101 and #action[4]==79,'save uploads ordinary entries to correct existing wishlist')
check(A.GetLoadoutWishlist(1)~=nil,'save associates with explicitly selected loadout')
check(Editor.OpenForWishlist(plan(),1)==true and not dialog:IsShown(),'reopening untagged 85 mirror uses saved confirmation')
local o2,l2=roles(plan().echoes);check(o2==79 and l2==6,'reopen no lost locks')
-- Arrays reordered by the server do not invalidate content-based roles.
local reverse={};for i=#entries,1,-1 do reverse[#reverse+1]=clone(entries[i]) end
H.perks.serverBuildSlots[101].echoes=reverse
local reversed=plan();check(A.WishlistEvidenceState(reversed)=='actionable','server order irrelevant')
local ro,rl=roles(reversed.echoes);check(ro==79 and rl==6,'server reorder preserves role counts')
-- Role selections are character-local, quality/copy bound, not name/slot guesses.
H.perks.serverBuildSlots[102]={name='250 mio untagged',verified=false,echoes=clone(entries)}
H.perks.serverBuildSlots[102].echoes[1].spellId=299998
H.perks.serverBuildSlots[102].echoes[1].quality=1
check(A.WishlistEvidenceState(plan(102))=='evidence-pending','same name with different contents gets no cached roles')
local unknown=plan(102);local beforeStale=clone(Nexus.Store.State())
check(Editor.OpenForWishlist(unknown,1),'other untagged build can be opened')
namedButton('NexusWishlistRoleUseOwned'):Click()
H.perks.serverBuildSlots[102].echoes[2].spellId=299998;H.perks.serverBuildSlots[102].echoes[2].quality=1
check(namedButton('NexusWishlistRoleConfirm'):Click()==false,'source drift refuses stale role choice')
check(dialog:IsShown() and dialog.message:GetText():find('changed',1,true),'stale choice remains visible with reason')
check(equal(beforeStale,Nexus.Store.State()),'stale confirmation changes no local records')
namedButton('NexusWishlistRoleCancel'):Click()
-- Strict decoder stays strict; only the editor's explicit draft path permits it.
check(Nexus.Codec.DecodeEBH1(raw)==nil,'normal codec does not grant authority to untagged85')
local parsed=Nexus.Codec.DecodeEBH1(raw,true)
check(parsed and parsed.needsRoleSelection and #parsed.entries==85,'editor decode preserves full ambiguous import')
Editor.ImportEBH1String(raw,'Explicit import test')
check(dialog:IsShown(),'real raw import opens picker, not parse failure or silent truncation')
local importBefore=clone(Nexus.Store.State())
namedButton('NexusWishlistRoleUseOwned'):Click()
check(namedButton('NexusWishlistRoleConfirm'):Click()==true,'raw import choice becomes editable draft')
check(equal(importBefore,Nexus.Store.State()),'import confirmation itself is not a saved/server write')
check(Editor.DebugPendingCount()==79,'raw import ordinary79 ready for save')
H.now=H.now+3.1
check(clickSave()==true,'raw import Create persists same role split')
-- Explicitly marked imports continue to avoid the extra confirmation step.
local marked={};local lockSet={};for _,id in ipairs(lockIds)do lockSet[id]=true end
for _,e in ipairs(entries)do local v=clone(e);v.locked=lockSet[v.spellId] or false;marked[#marked+1]=v end
local markedText=Nexus.Codec.EncodeEBH1(marked,'MAGE','Marked control')
check(Nexus.Codec.DecodeEBH1(markedText)~=nil,'explicit-codec control')
Editor.ImportEBH1String(markedText,'Marked control')
check(not dialog:IsShown() and Editor.DebugPendingCount()==79,'marked import retains one-step editor path')
-- Invalid >85 and invalid flag marker still refuse in the permissive draft path.
check(Nexus.Codec.DecodeEBH1(raw:gsub(':MAGE:',',299998.1.1:MAGE:'),true)==nil,'86 copies rejected')
check(Nexus.Codec.DecodeEBH1('EBH1:200050.2.1.2:MAGE:bad',true)==nil,'unknown role marker rejected')
print('PASS role-choice legacy/import/UI/save/reopen checks='..checks)
