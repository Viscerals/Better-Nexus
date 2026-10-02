-- W4: empty locked-target buckets must not accumulate (control BN-CONTROL-W4-BOUNDS-20261002-013).
--
-- Mechanism (source-confirmed): WishlistController.LockDesignTargets created
-- character.lockDesignTargetsBySlot[<content key>] = {} on every LOOKUP, and
-- CommitLockDesignTargets stored an empty fresh design under the saved content key. Every
-- distinct ordinary-only Wishlist content that was opened or saved therefore left a durable
-- empty bucket, with no removal path. The count of buckets is the oracle. No limit is claimed:
-- the migration reader's 4096 bound counts character rows, not these buckets.
-- Real controller, real model, real adapter; synthetic ids only. Part 1 uses the injected
-- local store of tests/prototype/wishlist.lua, part 2 the real Store with saved data and a
-- module reload, part 3 a read-only saved root.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function count(t) local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function EmptyCount(map) local n=0;for _,v in pairs(map or {})do if next(v)==nil then n=n+1 end end;return n end

-- Distinct ordinary-only content per i.
local function Ordinary(i)
 local t={}
 for k=1,5 do t[#t+1]={spellId=200000+((i*7+k*13)%85)+1,quality=(i+k)%4,stacks=1+(i+k)%3,locked=false} end
 t[#t+1]={spellId=200001+(i%85),quality=math.floor(i/85)%4,stacks=1+math.floor(i/340)%5,locked=false}
 t[#t+1]={spellId=200001+((i*3)%85),quality=i%4,stacks=1+(i%7),locked=false}
 return t
end
local function Keys(n,adapter)
 local keys,distinct={}, 0
 for i=1,n do local k=adapter.WishlistKey(Ordinary(i));if not keys[k] then keys[k]=true;distinct=distinct+1 end end
 return distinct
end

-- ---------------------------------------------------------------- 1. injected store
do
 local H=dofile('tests/prototype/harness.lua');H.Boot()
 local A=Nexus.GameAdapter
 local backing={};local settings={}
 local store={State=function() return backing end,Settings=function() return settings end}
 local account={}
 local adapter={};for k,v in pairs(A) do adapter[k]=v end
 A.Init({},store)
 local function controller()
  local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=store,accountRoot=function()return account end,notify=function()end})
  c.Initialize(adapter);return c
 end
 local c=controller()
 local distinct=Keys(60,A)
 check(distinct>=40,'the fixture produces many distinct content keys: '..distinct)
 -- 1a. repeated opens of distinct ordinary-only content
 for i=1,60 do check(c.LoadPendingEchoes(Ordinary(i),false,nil),'open '..i) end
 check(count(backing.lockDesignTargetsBySlot)==0,'60 ordinary-only opens leave no bucket: '..count(backing.lockDesignTargetsBySlot))
 -- 1b. reopening the same content changes nothing
 for i=1,60 do c.LoadPendingEchoes(Ordinary(i),false,nil) end
 check(count(backing.lockDesignTargetsBySlot)==0,'reopening known contents adds nothing')
 -- 1c. repeated edit-and-save cycles of ordinary-only content
 local saved=0
 for i=100,119 do
  c.BeginNewWishlist()
  check(c.LoadPendingEchoes(Ordinary(i),false,nil),'load '..i)
  local d=c.PrepareApply('W4 '..i)
  if d and c.AcceptApply(d)==true then saved=saved+1 end
  H.Advance(4,.5) -- the server spaces build operations by 3 s
 end
 check(saved>=10,'the saves are accepted: '..saved)
 check(count(backing.lockDesignTargetsBySlot)==0,'20 ordinary-only saves leave no bucket: '..count(backing.lockDesignTargetsBySlot))
 check(backing.firstRunWishlist~=nil and backing.firstRunWishlist.key~=nil,'the saves still record their assignment')
 -- 1d. a genuine locked target creates and retains its bucket
 local function Fixture()
  local t={}
  for i=1,79 do t[#t+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
  for i=80,85 do t[#t+1]={spellId=200000+i,quality=i%4,stacks=1,locked=true} end
  return t
 end
 local c2=controller();c2.BeginNewWishlist()
 check(c2.LoadPendingEchoes(Fixture()),'load 79+6')
 local d=assert(c2.PrepareApply('W4 locked'))
 check(c2.AcceptApply(d)==true,'save 79+6')
 local key=A.WishlistKey(d.echoes)
 check(count(backing.lockDesignTargetsBySlot)==1 and count(backing.lockDesignTargetsBySlot[key])==6,'the locked design creates exactly one bucket with six targets')
 local kept=backing.lockDesignTargetsBySlot[key]
 -- ordinary opens afterwards neither remove nor replace it
 for i=1,30 do c.LoadPendingEchoes(Ordinary(i),false,nil) end
 check(count(backing.lockDesignTargetsBySlot)==1 and backing.lockDesignTargetsBySlot[key]==kept,'later ordinary opens keep the existing bucket as it is')
 -- reopening that content (ordinary part only) still applies its committed targets
 local ordinaryPart={};for _,e in ipairs(Fixture()) do if not e.locked then ordinaryPart[#ordinaryPart+1]=e end end
 local c3=controller();c3.LoadPendingEchoes(ordinaryPart,false,nil)
 check(count(c3.PendingLockRows())==6,'the committed targets are still found for their content')
 -- 1e. pre-existing buckets (empty and non-empty) are never pruned or rewritten
 backing.lockDesignTargetsBySlot['legacy-empty']={}
 backing.lockDesignTargetsBySlot['legacy-full']={[200010]=true}
 local legacyEmpty,legacyFull=backing.lockDesignTargetsBySlot['legacy-empty'],backing.lockDesignTargetsBySlot['legacy-full']
 for i=1,30 do c.LoadPendingEchoes(Ordinary(i),false,nil);c.BeginNewWishlist();c.LoadPendingEchoes(Ordinary(i+500),false,nil) end
 check(backing.lockDesignTargetsBySlot['legacy-empty']==legacyEmpty and backing.lockDesignTargetsBySlot['legacy-full']==legacyFull and count(backing.lockDesignTargetsBySlot)==3,'existing empty and non-empty buckets are left exactly as they were')
 -- 1f. the retired flat account table still moves under the current key, once
 local backing2={}
 local store2={State=function() return backing2 end,Settings=function() return settings end}
 local account2={lockDesignTargets={[200020]=true}}
 A.Init({},store2)
 local c4=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=store2,accountRoot=function()return account2 end,notify=function()end})
 c4.Initialize(adapter)
 c4.LoadPendingEchoes(Ordinary(7),false,nil)
 local moved=backing2.lockDesignTargetsBySlot and backing2.lockDesignTargetsBySlot[A.WishlistKey(Ordinary(7))]
 check(type(moved)=='table' and moved[200020]==true and account2.lockDesignTargets==nil,'the legacy flat table moves under its key and is retired')
 check(count(backing2.lockDesignTargetsBySlot)==1,'and creates exactly that one bucket')
 c4.LoadPendingEchoes(Ordinary(8),false,nil)
 check(count(backing2.lockDesignTargetsBySlot)==1,'a second content does not move or create anything')
 A.Init({},store)
end

-- ---------------------------------------------------------------- 2. real Store, saved data, reload
do
 local db=F.Database()
 local H=F.Boot(db,function(h)h.pendingRolls=2 end)
 local A=Nexus.GameAdapter
 local function Row(d) return d.chars[F.NAME] end
 local original=Row(db).lockDesignTargetsBySlot
 local originalKey,originalBucket
 for k,v in pairs(original)do originalKey,originalBucket=k,v end
 check(count(original)==1 and originalBucket[F.PERMANENT]==true,'fixture: one saved non-empty bucket')
 local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=Nexus.Store,accountRoot=function()return {}end,notify=function()end})
 c.Initialize(A)
 for i=1,80 do c.LoadPendingEchoes(Ordinary(i),false,nil) end
 check(count(Row(db).lockDesignTargetsBySlot)==1,'80 ordinary-only opens against the real Store add no bucket: '..count(Row(db).lockDesignTargetsBySlot))
 check(Row(db).lockDesignTargetsBySlot[originalKey]==originalBucket,'the saved bucket is the same table')
 -- opening its own content applies the saved target
 local own={};for i,e in ipairs(F.PLAN)do own[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks,locked=false} end
 c.LoadPendingEchoes(own,false,nil)
 check(count(c.PendingLockRows())>=1,'opening the saved content still applies its committed target')
 -- reload: round-tripped literal data
 local H2,saved=F.Reload(function(h)h.pendingRolls=2 end)
 local db2=NexusDB
 check(count(Row(db2).lockDesignTargetsBySlot)==1 and Row(db2).lockDesignTargetsBySlot[originalKey][F.PERMANENT]==true,'after a reload the saved bucket is unchanged and nothing else exists')
 local c2=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=Nexus.Store,accountRoot=function()return {}end,notify=function()end})
 c2.Initialize(Nexus.GameAdapter)
 for i=1,40 do c2.LoadPendingEchoes(Ordinary(i),false,nil) end
 check(count(Row(NexusDB).lockDesignTargetsBySlot)==1,'and the reloaded profile does not grow either')
 check(#F.Serialize(NexusDB)<=#saved+64,'the serialized profile does not grow with opens: '..#F.Serialize(NexusDB)..' vs '..#saved)
end

-- ---------------------------------------------------------------- 3. read-only saved root
do
 local db=F.Database({version=6})
 local H=F.Boot(db,function(h)h.pendingRolls=2 end)
 check(Nexus.MainInternals.SavedFormatClassV1()=='future','the saved root is read-only (future format)')
 local before=F.Serialize(db)
 local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=Nexus.Store,accountRoot=function()return {}end,notify=function()end})
 c.Initialize(Nexus.GameAdapter)
 for i=1,40 do c.LoadPendingEchoes(Ordinary(i),false,nil) end
 check(F.Serialize(db)==before,'opening Wishlists in a read-only root writes nothing')
end
print('PASS lock bucket growth checks='..checks)
