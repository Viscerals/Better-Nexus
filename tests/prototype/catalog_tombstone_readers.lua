-- Removal-marker walks: a named reader owns its own walk slot, so the
-- retention sweep (the shared slot, synchronous) and the hash warm-up or the
-- Sync candidate scan (multi-frame named readers) never invalidate each
-- other's walk. The shared slot keeps its semantics, an unknown reader name
-- is the shared slot, and a catalog change still refuses a named walk once
-- as stale and then as invalid. Real boot and catalog; synthetic markers.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local fx=L.New({players={{name='Alpha',class='MAGE'}},removalMarkers=4,markerShape='v1'})
local H=F.Boot(fx:Install(F.Database({version=2})))
for _=1,200 do H.Advance(.05,.05) end
local C=Nexus.BuildCatalog
check(C.Status().tombstoneCount==4,'fixture: four removal markers: '..tostring(C.Status().tombstoneCount))
-- 1. The shared walk steps through the markers in a fixed order.
local m1=C.TombstoneNext(nil)
local m2=C.TombstoneNext(m1)
local m3=C.TombstoneNext(m2)
check(m1~=nil and m2~=nil and m3~=nil and m1~=m2 and m2~=m3,'the shared walk steps through the markers')
-- 2. A named reader keeps its position while a synchronous sweep restarts
-- and advances the shared slot past it.
local h1=C.TombstoneNext(nil,'build-hash-cache')
check(h1==m1,'a named walk starts at the first marker')
local s1=C.TombstoneNext(nil)
local s2=C.TombstoneNext(s1)
check(s1==m1 and s2==m2,'fixture: the sweep restarted the shared walk and moved past the named position')
local h2,why,done=C.TombstoneNext(h1,'build-hash-cache')
check(h2==m2 and not done,'the named walk continues from its own position: '..tostring(why))
local s3=C.TombstoneNext(s2)
check(s3==m3,'the shared walk is not disturbed by the named reader')
-- 3. Two named readers are independent of each other.
local x1=C.TombstoneNext(nil,'sync-candidate')
local h3=C.TombstoneNext(h2,'build-hash-cache')
local x2=C.TombstoneNext(x1,'sync-candidate')
check(x1==m1 and h3==m3 and x2==m2,'two named readers walk independently')
-- 4. An unknown reader name is the shared slot.
local u1=C.TombstoneNext(nil,'unknown-reader')
local s4,sWhy,sDone=C.TombstoneNext(s3)
check(u1==m1 and s4==nil and sDone==true and sWhy=='INVALID_CURSOR','an unknown reader name uses the shared slot: '..tostring(sWhy))
-- 5. A named walk ends with done after the last marker.
local h4=C.TombstoneNext(h3,'build-hash-cache')
local none,_,walkDone=C.TombstoneNext(h4,'build-hash-cache')
check(h4~=nil and none==nil and walkDone==true,'the named walk reaches the end of the four markers')
-- 6. A catalog change refuses a live named walk once as stale, then invalid.
local y1=C.TombstoneNext(nil,'sync-candidate')
local echoes={}
for j=1,79 do echoes[j]={spellId=200000+j,quality=j%4,stacks=1} end
local ok,putWhy,ticket=C.Put({id='change-1',title='Change',author='Other-Realm',class='MAGE',postedAt=2,lastModified=2,
 echoes=echoes,loadoutAvailable=true},{source='remote',sender='Other-Realm'})
if ok==nil and type(ticket)=='table' then
 for _=1,4000 do if ticket.state~='pending' then break end;H.Advance(.05,.05) end
 ok=ticket.committed==true
end
check(ok==true,'fixture: a catalog change: '..tostring(putWhy))
local _,stale,staleDone=C.TombstoneNext(y1,'sync-candidate')
local _,invalid,invalidDone=C.TombstoneNext(y1,'sync-candidate')
check(staleDone==true and stale=='STALE_CURSOR' and invalidDone==true and invalid=='INVALID_CURSOR',
 'after a change a named walk is stale once, then invalid: '..tostring(stale)..' / '..tostring(invalid))
print('PASS catalog_tombstone_readers checks='..checks)
