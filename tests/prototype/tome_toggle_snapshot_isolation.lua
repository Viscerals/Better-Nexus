-- A successful Tome lever toggle writes its pending entry through the Store
-- owner and never installs a table taken from the Store.State() read
-- snapshot into the durable character row (BN-FULL-REVIEW-PRIVATE-BUILD-003,
-- audit F2). Required: the snapshot and the durable row hold distinct pending
-- tables; the new entry and an earlier pending entry are both in the durable
-- row and in a fresh read; a write into a retained read does not reach the
-- durable row; a refused toggle writes nothing.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
NexusDB=nil;WishlistRealizerDB=nil
local H=dofile('tests/prototype/harness.lua')
H.names[777001]='Tome of Gated Echo';H.names[777002]='Tome of Second Echo'
H.AddEcho(300001,'Gated Echo',1,1,0);H.db[300001].requiredSpell=777001
H.AddEcho(300002,'Second Echo',1,1,0);H.db[300002].requiredSpell=777002
H.discovered[300001]=true;H.discovered[300002]=true;H.perks.discoveredEchoes=H.discovered
H.playerLevel=1
H.Boot()
local A,Store=Nexus.GameAdapter,Nexus.Store
local function Row()
 for _,row in pairs(NexusDB.chars or {}) do if type(row)=='table' and type(row.tomeTogglePending)=='table' then return row end end
end
check(Row()~=nil,'fixture: the durable character row has a pending map')

-- 1. First toggle with a warm read snapshot.
local warm=Store.State();check(type(warm.tomeTogglePending)=='table','fixture: warm snapshot')
local ok,why=A.ToggleLever(777001,true)
check(ok==true,'first toggle sent: '..tostring(why))
local durable=Row().tomeTogglePending
check(type(durable[777001])=='table' and durable[777001].want==true,'durable row holds the new entry')
local read=Store.State()
check(type(read.tomeTogglePending[777001])=='table','a fresh read shows the new entry')
check(read.tomeTogglePending~=durable,'the read snapshot and the durable row hold distinct pending tables')
check(warm.tomeTogglePending~=durable,'the earlier warm snapshot table was not installed into the durable row')

-- 2. Second toggle keeps the first pending entry.
read=Store.State()
ok,why=A.ToggleLever(777002,true)
check(ok==true,'second toggle sent: '..tostring(why))
durable=Row().tomeTogglePending
check(type(durable[777001])=='table' and type(durable[777002])=='table','durable row keeps both pending entries')
local fresh=Store.State()
check(type(fresh.tomeTogglePending[777001])=='table' and type(fresh.tomeTogglePending[777002])=='table','a fresh read shows both entries')
check(fresh.tomeTogglePending~=durable,'still distinct tables after the second toggle')

-- 3. A write into a retained read does not reach the durable row.
fresh.tomeTogglePending[999999]={t=0,want=true}
check(Row().tomeTogglePending[999999]==nil,'a retained read cannot change the durable pending map')
check(read.tomeTogglePending~=Row().tomeTogglePending,'the read taken before the second toggle is not the durable table')

-- 4. A refused toggle (already pending) writes nothing.
local before=Row().tomeTogglePending
ok,why=A.ToggleLever(777001,true)
check(ok==false and why=='pending','already pending: refused')
check(Row().tomeTogglePending==before and before[777001]~=nil,'refusal leaves the durable map unchanged')
print('PASS tome toggle writes through the owner; read snapshots stay detached; '..checks..' checks')
