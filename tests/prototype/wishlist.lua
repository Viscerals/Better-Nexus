local H=dofile('tests/prototype/harness.lua');H.Boot()
local A=Nexus.GameAdapter
local backing={};local settings={}
local store={State=function() return backing end,Settings=function() return settings end}
-- The real controller uses a deliberately injected local state store, while
-- upload spacing, key production, catalog and game service use the real adapter.
local messages={}
local adapter={};for k,v in pairs(A) do adapter[k]=v end
A.Init({},store)
local function controller()
 local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=store,accountRoot=function()return {}end,notify=function(t)messages[#messages+1]=t end})
 c.Initialize(adapter);return c
end
local function fixture()
 local t={}
 for i=1,79 do t[#t+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
 for i=80,85 do t[#t+1]={spellId=200000+i,quality=i%4,stacks=1,locked=true} end
 return t
end
local function count(t) local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local checks=0
local function check(v,msg) assert(v,msg);checks=checks+1 end
local c=controller();c.BeginNewWishlist()
check(c.LoadPendingEchoes(fixture()),'load 79+6')
check(c.PendingTotal()==79 and count(c.PendingLockRows())==6,'exact separate role budgets')
local d=assert(c.PrepareApply('Prototype exact targets'))
check(c.AcceptApply(d)==true,'first upload')
local key=A.WishlistKey(d.echoes)
check(count(backing.lockDesignTargetsBySlot[key])==6,'six committed targets')
check(backing.firstRunWishlist.key==key,'association uses uploaded key')
check(c.BeginWishlist({slot=101,name=d.name,key=key,echoes=d.echoes,lockEvidenceVersion=1}),'reopen')
check(count(c.PendingLockRows())==6,'six targets restored')
local same=assert(c.PrepareApply('ignored'))
local ok,why=c.AcceptApply(same)
check(ok==false and why=='spacing' and c.IsApplyPending(),'real spacing retry')
H.now=H.now+3.1
check(c.PumpApplyRetry()==true,'unchanged retry succeeds')
check(count(backing.lockDesignTargetsBySlot[key])==6,'unchanged retry retains all targets')
-- Make another pending upload and then change its confirmed draft.
local retry=assert(c.PrepareApply('ignored'));local uploads=#H.actions
ok,why=c.AcceptApply(retry)
check(ok==false and why=='spacing','second spacing retry')
local pending=c.PendingRows();local rowKey=next(pending)
c.RemovePending(rowKey);check(c.PendingTotal()==78,'edit draft')
H.now=H.now+3.1
ok,why=c.PumpApplyRetry()
check(ok==false and why=='stale_confirmation','changed draft cancels')
check(#H.actions==uploads,'no old draft uploaded after change')
check(count(backing.lockDesignTargetsBySlot[key])==6,'old six targets preserved after cancelled retry')
-- Dialog confirmation also binds the exact draft.
c=controller();c.BeginNewWishlist();c.LoadPendingEchoes(fixture());d=assert(c.PrepareApply('Dialog'))
c.RemovePending(next(c.PendingRows()))
check(c.AcceptApply(d)==false,'changed dialog rejects')
-- Same-family distinct quality IDs must reach the real upload without collapse.
H.AddEcho(290001,'Tiered Echo',1,5,900);H.AddEcho(290002,'Tiered Echo',3,5,900)
H.now=H.now+3.1
check(A.UploadWishlist(0,'Tiers',{{spellId=290001,quality=1,stacks=2},{spellId=290002,quality=3,stacks=1}}),'tiered upload')
local sent=H.actions[#H.actions][4]
check(#sent==2 and sent[1].spellId==290001 and sent[1].stacks==2 and sent[2].spellId==290002,'exact variants retained')
H.now=H.now+3.1
local before=#H.actions
check(not A.UploadWishlist(0,'Overflow',{{spellId=200001,quality=1,stacks=80}}),'invalid copies reject')
check(not A.UploadWishlist(0,'NaN',{{spellId=0/0,stacks=1}}),'NaN reject')
check(#H.actions==before,'refused input has no writes')
-- A known invalid numbered slot is not silently treated as first-run.
check(not A.SetLoadoutWishlist(9,101),'invalid numbered slot rejected')
print('PASS Wishlist real-controller/adapter checks='..checks)
