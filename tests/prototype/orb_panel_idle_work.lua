-- Orb window idle work. test.9032 (tester report: severe choppiness while the
-- Orbs / Lost Memories window is open and idle). Baseline review probe
-- probe_orb_refresh_work.lua on the same modules: 4 refreshes in one second did
-- 8 adapter reads, 8 complete catalog traversals (8,000 row visits with a
-- 1,000-row catalog) and 16 assignment lookups. Cause: OrbRuntime.Status read
-- twice (inspect, then preflight -> inspect), OrbAdapter.Read rebuilt every
-- catalog row on each read, and Status copied the whole catalog.
-- Same setup as that probe: real Store, Identity, OrbPolicy, OrbAdapter,
-- OrbRuntime and OrbPanel; synthetic catalog, services and assignment. Work
-- counts only; not native frame time.
local H=dofile('tests/prototype/harness.lua')
Nexus={};NexusDB={settingsVersion=2,settings={},chars={}}
dofile('core/Identity.lua');dofile('core/Store.lua')
local S=Nexus.Store
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)s.syntheticControl=true end))
local ROWS=1000
local cat={rows={},playerMask=128}
local rawStore={}
for id=1001,1000+ROWS do
 cat.rows[id]={spellId=id,name='Synthetic '..id,quality=1,groupId=id,requiredSpell=0,maxStack=4,classMask=0}
 rawStore[id]={groupId=id,requiredSpell=0,classMask=0}
end
local stats={reads=0,scans=0,rowsBuilt=0,mutations=0,assignments=0,disabled=0,writes=0}
-- Every availability row reads its live PerkDatabase entry once: count row builds there.
local raw=setmetatable({},{__index=function(_,id)stats.rowsBuilt=stats.rowsBuilt+1;return rawStore[id]end,
 __newindex=function(_,id,v)rawStore[id]=v end})
local granted={{spellId=1001,quality=1,stacks=3}};local locked={}
local entries={{spellId=1002,quality=1,stacks=1}}
local charges=3
local A={}
Nexus.GameAdapter=A
A.Catalog=function()return cat end
A.Owned=function()return {synced=true,generation=1}end
A.LockedOwned=function()return {synced=true}end
A.AutomationSignature=function()return {activeSlot=1}end
A.Level=function()return 80 end
A.InFlight=function()return false end
A.RivalDetected=function()return false end
A.AssignedWishlist=function()
 stats.assignments=stats.assignments+1
 return {state='ready',entries=entries,name='Synthetic',owner=S.CurrentOwnerKey(),activeSlot=1,identity='synthetic'}
end
local function mutation()stats.mutations=stats.mutations+1;return true end
ProjectEbonhold={PerkDatabase=raw,Perks={serverActiveSlot=1,discoveredEchoes={}},
 OrbService={IsStateKnown=function()return true end,GetCharges=function()return charges end,
 IsOfferPending=function()return false end,ConfirmSpend=mutation,RequestCharges=function()stats.mutations=stats.mutations+1;return true end},
 PerkService={GetGrantedPerks=function()return granted end,GetLockedPerks=function()return locked end,
 GetCurrentChoice=function()return {}end,SelectPerk=mutation,RequestGrantedPerks=function()stats.mutations=stats.mutations+1;return true end,
 GetDiscoveredEchoes=function()return {}end,IsTomeEchoDisabled=function()stats.disabled=stats.disabled+1;return false end}}
ProjectEbonholdOptionsService={GetSetting=function()return false end}
Nexus.StartupStatus=function()return {coreReady=true}end
Nexus.Help={Show=function()end}
dofile('logic/OrbPolicy.lua');dofile('core/OrbAdapter.lua')
local originalRead=A.Orbs.Read
A.Orbs.Read=function(...)stats.reads=stats.reads+1;return originalRead(...)end
local originalPairs=pairs
pairs=function(t)if t==cat.rows then stats.scans=stats.scans+1 end;return originalPairs(t)end
local realWrite=Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1
Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1=function(...)stats.writes=stats.writes+1;return realWrite(...)end
dofile('core/OrbRuntime.lua');dofile('ui/OrbPanel.lua')
local f=Nexus.OrbPanel.Show()
assert(f.snapshot and f.snapshot.canStart==true,'fixture: Start is available: '..tostring(f.snapshot and f.snapshot.startReason))
local function reset()for k in originalPairs(stats)do if k~='mutations' then stats[k]=0 end end end
local function Tick(n)for i=1,n do f:GetScript('OnUpdate')(f,.25)end end

-- 1. Visible, idle, Advanced closed: one read per refresh, no catalog traversal, few rows.
reset();Tick(4)
print(string.format('VISIBLE_ONE_SECOND: ui_refreshes=4 adapter_reads=%d full_catalog_scans=%d rows_built=%d assignment_resolutions=%d disabled_checks=%d writes=%d mutations=%d',
 stats.reads,stats.scans,stats.rowsBuilt,stats.assignments,stats.disabled,stats.writes,stats.mutations))
assert(stats.reads==4,'one adapter read per refresh (baseline 8): '..stats.reads)
assert(stats.scans==0,'no complete catalog traversal (baseline 8): '..stats.scans)
assert(stats.rowsBuilt<=4*3,'only the rows the view needs are built (baseline 8000 row visits): '..stats.rowsBuilt)
assert(stats.assignments<=4,'one assignment lookup per refresh (baseline 16): '..stats.assignments)
assert(stats.writes==0 and stats.mutations==0,'reading the view writes nothing and sends nothing')
assert(f.snapshot.sources==nil and f.snapshot.sourceCount==1,'Advanced closed: no source list copied, count kept')

-- 2. Advanced open: the source list is prepared; still no catalog traversal.
local toggle;for _,c in ipairs(f.children)do if c.GetText and c:GetText()=='Advanced' then toggle=c end end
assert(toggle,'fixture: the real Advanced button');toggle:Click()
reset();Tick(4)
assert(type(f.snapshot.sources)=='table' and #f.snapshot.sources==1 and f.sourceRows[1].label:GetText():find('Synthetic 1001',1,true),'Advanced lists the eligible source')
assert(stats.scans==0 and stats.reads==4 and stats.writes==0,'Advanced: still one read per refresh and no traversal')
toggle:Click()

-- 3. Hidden: nothing is read.
f:Hide();reset();Tick(4)
assert(stats.reads==0 and stats.scans==0 and stats.rowsBuilt==0,'hidden window reads nothing')
f:Show()

-- 4. Every relevant change still reaches the display, also when a table changes in place.
local function Refresh()Nexus.OrbPanel.Refresh();return f.snapshot end
local s
local before=Refresh().progress.rolledMissing
assert(before==1,'fixture: one target copy missing')
entries[1].stacks=3                                    -- assignment contents changed in place
assert(Refresh().progress.rolledMissing==3,'in-place target change is shown')
entries[1].stacks=1
granted[2]={spellId=1002,quality=1,stacks=1}          -- ownership changed in place: the target is now owned
s=Refresh()
assert(s.progress.rolledMissing==0 and s.canStart==false and s.startReason=='All rolled targets are already complete. No Orbs are needed.','ownership change is shown: '..tostring(s.startReason))
granted[2]=nil
charges=0
assert(Refresh().charges==0 and f.snapshot.canStart==false and f.snapshot.startReason=='No confirmed Orbs are available.','resource change: Start disabled with the reason')
charges=3
rawStore[1002]=nil                                     -- live catalog metadata for the target disappears
s=Refresh()
assert(s.canStart==false and tostring(s.startReason):find('currently unavailable',1,true),'missing live metadata for a target blocks Start: '..tostring(s.startReason))
rawStore[1002]={groupId=1002,requiredSpell=0,classMask=0}
rawStore[1001]=nil                                     -- the source's live metadata disappears
s=Refresh()
assert(s.canStart==false and s.sourceCount==0,'missing live metadata never makes a copy an eligible source: '..tostring(s.startReason))
rawStore[1001]={groupId=1001,requiredSpell=0,classMask=0}
cat.rows[1001].groupId=1002;rawStore[1001].groupId=1002 -- catalog grouping changed in place
s=Refresh()
assert(s.catalog[1001].group=='g:1002','in-place catalog metadata change is read fresh')
cat.rows[1001].groupId=1001;rawStore[1001].groupId=1001
assert(Refresh().canStart==true,'restored state is shown again')

-- 5. A stale display never authorizes: the click reads fresh.
local shown=Refresh();assert(shown.canStart==true)
charges=0                                              -- changes after the last refresh, before the click
f.limit:SetText('2');stats.mutations=0
f.start:Click()
assert(stats.mutations==0 and f.notice:GetText()=='No confirmed Orbs are available.','Start re-validates at click time: '..tostring(f.notice:GetText()))
charges=3
print('PASS orb_panel_idle_work: 4 reads, 0 traversals, '..'<=12 row builds, <=4 assignment reads per idle second; changes shown; fresh action checks')
