-- "Update from Wishlist" reads Echo roles like Share (docs/P1_7_LOCKED_ROLE_WIRE.md).
-- Before, it copied every Wishlist entry into the ordinary list and kept the
-- previous revision's lockedEchoes, so a role change was lost and stale
-- locked rows would travel with the new revision. Real TOC, adapter,
-- controller and catalog; synthetic data.
local S=dofile('tests/prototype/share_test_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Key(rows)
 local t={}
 for _,r in ipairs(rows or {}) do t[#t+1]=string.format('%d:%d:%d',r.spellId or r.id,r.quality or 0,r.stacks or r.count or 1) end
 table.sort(t);return table.concat(t,',')
end
local H,C=S.Boot()
-- The shared build: ordinary 200001x3 + 200002x1, locked 200086 (server slot).
H.perks.serverBuildSlots={[102]={name='NEXUS-TEST-UPDATE',verified=false,echoes={
 {spellId=200001,quality=1,stacks=3},{spellId=200002,quality=2,stacks=1},{spellId=200086,quality=2,stacks=1,locked=true}}}}
H.Notify()
for _=1,20 do H.Advance(.1,.1) end
local id=S.Post('NEXUS-TEST-UPDATE').id
S.T.Until(H,function() return C.Get(id)~=nil end)
check(Key(C.Get(id).lockedEchoes)=='200086:2:1','fixture: the shared build has locked target 200086')
-- The active Wishlist now states a different locked target (its saved design).
assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Role update',
 {{spellId=200001,quality=1,stacks=3},{spellId=200002,quality=2,stacks=1}},
 {[200085]={version=1,copies=1,rows={{spellId=200085,quality=1,stacks=1,locked=true,sourceRole='locked'}}}}))
for _=1,40 do H.Advance(.1,.1) end
local stamp=C.Get(id).lastModified
local ok,why=Nexus.CommunityBuilds.UpdateFromWishlist(id)
check(ok,'the update is accepted: '..tostring(why))
S.T.Until(H,function() local r=C.Get(id);return r and r.lastModified>stamp end)
local row=C.Get(id)
check(Key(row.echoes)=='200001:1:3,200002:2:1','the ordinary targets stay ordinary: '..Key(row.echoes))
check(Key(row.lockedEchoes)=='200085:1:1','the locked set is the Wishlist\'s (200085), not the stale 200086: '..Key(row.lockedEchoes))
print('PASS community_update_roles checks='..checks)
