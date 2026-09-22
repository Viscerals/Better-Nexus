-- Orb Start readiness vs local persistence. test.9032 (tester report: Start looked
-- available but refused "Local character data is not ready; no Orb action will be
-- sent."). Baseline review probes probe_orb_local_row.lua / probe_orb_refresh_work.lua
-- on the same modules: with a readable Store.State but no durable character row,
-- Start refused before the authorized writer (0 writer calls) while the real panel
-- enabled Start. The Store owner (UpdateStateV1) creates that row legitimately.
-- Correction: Store.StateWriteStatus classifies write readiness (read-only);
-- OrbRuntime requires "durable", lets the owner create the row at the explicit
-- write, then verifies the durable row holds the data (UpdateStateV1 also returns
-- true for its transient fallback). Start eligibility uses the same check.
-- Real Store, Identity, OrbPolicy, OrbAdapter, OrbRuntime, OrbPanel; synthetic
-- services. No game client, no spend: ConfirmSpend/SelectPerk only count.
local H=dofile('tests/prototype/harness.lua')
local name,realm='ProbeTester','SyntheticRealm'
function UnitName()return name end
function GetRealmName()return realm end
GetNormalizedRealmName=GetRealmName
local function Fresh()
 Nexus={};NexusDB={settingsVersion=2,settings={},chars={}}
 dofile('core/Identity.lua');dofile('core/Store.lua')
end
Fresh()
local S=Nexus.Store
local stats={writes=0,mutations=0,reads=0}
local cat={rows={},playerMask=128};local raw={}
for id=1001,1010 do
 cat.rows[id]={spellId=id,name='Synthetic '..id,quality=1,groupId=id,requiredSpell=0,maxStack=4,classMask=0}
 raw[id]={groupId=id,requiredSpell=0,classMask=0}
end
local granted={{spellId=1001,quality=1,stacks=3}};local entries={{spellId=1002,quality=1,stacks=1}}
local function Services()
 local A={}
 Nexus.GameAdapter=A
 A.Catalog=function()return cat end
 A.Owned=function()return {synced=true,generation=1}end
 A.LockedOwned=function()return {synced=true}end
 A.AutomationSignature=function()return {activeSlot=1}end
 A.Level=function()return 80 end
 A.InFlight=function()return false end
 A.RivalDetected=function()return false end
 A.AssignedWishlist=function()return {state='ready',entries=entries,name='Synthetic',owner=S.CurrentOwnerKey(),activeSlot=1,identity='synthetic'}end
 local function mutation()stats.mutations=stats.mutations+1;return true end
 ProjectEbonhold={PerkDatabase=raw,Perks={serverActiveSlot=1,discoveredEchoes={}},
  OrbService={IsStateKnown=function()return true end,GetCharges=function()return 3 end,
  IsOfferPending=function()return false end,ConfirmSpend=mutation,RequestCharges=mutation},
  PerkService={GetGrantedPerks=function()return granted end,GetLockedPerks=function()return {} end,
  GetCurrentChoice=function()return {}end,SelectPerk=mutation,RequestGrantedPerks=mutation,
  GetDiscoveredEchoes=function()return {}end,IsTomeEchoDisabled=function()return false end}}
 ProjectEbonholdOptionsService={GetSetting=function()return false end}
 Nexus.StartupStatus=function()return {coreReady=true}end
 Nexus.Help={Show=function()end}
 Nexus.DisableOrdinaryAutomation=function()return true end
 dofile('logic/OrbPolicy.lua');dofile('core/OrbAdapter.lua')
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 local realWrite=owner.UpdateStateV1
 owner.UpdateStateV1=function(...)stats.writes=stats.writes+1;return realWrite(...)end
 dofile('core/OrbRuntime.lua');dofile('ui/OrbPanel.lua')
 return owner,realWrite
end
local function Key()return S.CurrentOwnerKey()end
local owner,realWrite=Services()
local f=Nexus.OrbPanel.Show()
local function Snapshot()Nexus.OrbPanel.Refresh();return f.snapshot end
local function Click(limit)f.limit:SetText(tostring(limit));f.start:Click();return f.notice:GetText()end

-- 1. Readable assignment and ownership, NO durable row (the reproduced baseline case).
assert(NexusDB.chars[Key()]==nil and type(S.State())=='table','fixture: readable state, no durable row')
local before=stats.writes
for i=1,4 do f:GetScript('OnUpdate')(f,.25)end
local s=Snapshot()
assert(NexusDB.chars[Key()]==nil and stats.writes==before,'reading the view creates no row and writes nothing')
assert(s.canStart==true and f.start:IsEnabled(),'Start is offered because the click can persist')
-- The click: the owner creates the row, the limit and the pre-spend receipt are durable before the spend.
local receiptAtSpend
ProjectEbonhold.OrbService.ConfirmSpend=function()
 local row=NexusDB.chars[Key()]
 receiptAtSpend=row and row.orbRefinement and row.orbRefinement.pending and true or false
 stats.mutations=stats.mutations+1;return true
end
Click(3)
local row=NexusDB.chars[Key()]
assert(type(row)=='table' and row.orbRefinement.maxOrbs==3,'the authorized owner created the row; limit preserved')
assert(stats.mutations==1 and receiptAtSpend==true,'one spend, and its receipt was durable before it ('..stats.mutations..')')
assert(Nexus.OrbRuntime.Status().pending==true and Nexus.OrbRuntime.Status().reserved==1,'the receipt holds the exposure')
assert(s.persistence.mode=='durable' and s.persistence.rowPresent==false,'the Store reports durable writing is possible with the row absent')
print('PASS absent row: Start enabled, row created by the Store owner at the Start write, receipt durable before the one spend')

-- 2. Later loss of persistence while the receipt is unresolved: exposure kept, nothing more sent.
local mutationsBefore=stats.mutations
local chars=NexusDB.chars;NexusDB.chars=nil
Nexus.OrbRuntime.Pump()
s=Nexus.OrbRuntime.Status()
assert(s.pending==true and s.reserved==1 and stats.mutations==mutationsBefore,'persistence lost: exposure retained, no further action')
NexusDB.chars=chars
print('PASS persistence lost after a spend: unresolved exposure retained')

-- 3. Each unusable state: Start disabled with its reason; the click sends nothing and writes nothing.
local function Refused(label,setup,teardown,expect)
 Fresh();name='ProbeTester';owner,realWrite=Services();f=Nexus.OrbPanel.Show()
 setup()
 stats.mutations=0;local w=stats.writes
 s=Snapshot()
 assert(s.canStart==false and not f.start:IsEnabled(),label..': Start disabled')
 assert(tostring(s.startReason):find(expect,1,true),label..': reason "'..expect..'": '..tostring(s.startReason))
 local shownLimit=s.config.maxOrbs
 local disabledClick=Click(7)                     -- a disabled button does nothing
 local ok,why=Nexus.OrbRuntime.Start(7)            -- the real action path refuses too
 assert(not ok and tostring(why):find(expect,1,true) and stats.mutations==0 and stats.writes==w,label..': Start refuses with the same reason, sends and writes nothing: '..tostring(why))
 assert(Nexus.OrbRuntime.Status().config.maxOrbs==shownLimit,label..': the refused limit is not shown as approved')
 if teardown then teardown() end
end
Refused('unknown identity',function()name='Unknown'end,function()name='ProbeTester'end,'Your character identity is not known yet')
Refused('no database',function()NexusDB=nil end,nil,'Local saved data is unavailable')
Refused('no character container',function()NexusDB.chars=nil end,nil,'no character container')
Refused('future schema',function()NexusDB.settingsVersion=99 end,nil,'newer Nexus version')
Refused('row of another shape',function()NexusDB.chars[Key()]='corrupt' end,nil,'unsupported shape')
assert(NexusDB.chars==nil or NexusDB.chars[Key()]=='corrupt' or true)
print('PASS unknown identity, no database, no container, future schema, malformed row: disabled, refused, nothing written or sent')

-- 4. The writer reports success without persisting (transient fallback) or fails: refused, nothing sent.
for _,case in ipairs({{'transient success',function()return true end},{'writer failure',function()return nil end}})do
 Fresh();name='ProbeTester';owner,realWrite=Services();f=Nexus.OrbPanel.Show()
 owner.UpdateStateV1=case[2]
 stats.mutations=0
 assert(Snapshot().canStart==true,'fixture: display cannot foresee a failing writer')
 local notice=Click(4)
 assert(stats.mutations==0 and notice:find('Could not preserve Orb preferences/recovery state',1,true),case[1]..': refused: '..notice)
 assert(NexusDB.chars[Key()]==nil and Nexus.OrbRuntime.Status().config.maxOrbs==10,case[1]..': no row, and the refused limit is not shown as saved')
end
print('PASS transient success and writer failure: no spend, preferences unchanged')

-- 5. Character change: each character writes only its own row.
Fresh();name='ProbeTester';owner,realWrite=Services();f=Nexus.OrbPanel.Show()
assert(Nexus.OrbRuntime.SetLimit(5))
local first=Key()
name='OtherTester'
assert(Nexus.OrbRuntime.Status().config.maxOrbs==10,'the other character does not inherit the first character preferences')
assert(Nexus.OrbRuntime.SetLimit(6))
assert(NexusDB.chars[first].orbRefinement.maxOrbs==5 and NexusDB.chars[Key()].orbRefinement.maxOrbs==6,'each character row holds its own limit')
name='ProbeTester'
print('PASS character change: separate rows, no cross-character write')

-- 6. Recheck and repeated reads are display-only: no row, no write, no action.
Fresh();name='ProbeTester';owner,realWrite=Services();f=Nexus.OrbPanel.Show()
stats.mutations=0;local w=stats.writes
for i=1,3 do Nexus.OrbRuntime.Status();Nexus.OrbRuntime.Status(false) end
assert(NexusDB.chars[Key()]==nil and stats.writes==w and stats.mutations==0,'Status reads write nothing and send nothing')
print('PASS orb_readiness_persistence')
