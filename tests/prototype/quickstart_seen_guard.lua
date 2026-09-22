-- QuickStart is a one-time window whose acknowledgement is saved data.
-- Deciding whether to show it, showing it and closing it never create,
-- replace or repair the saved table, and hasSeenQuickStart is written only
-- when the saved-data owner reports a durable write and local start-up
-- completed. A session that may not record it still closes the window for
-- that session. Real TOC boot, real window and real buttons; synthetic data.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Window() return NexusQuickStart end
local function Shown() local w=Window();return w~=nil and w:IsShown() end
local function Button(text)
 local w=Window();if not w then return nil end
 for _,c in ipairs(w.children or {})do
  if c.kind=='Button' and c:GetText()==text then return c end
 end
end
local function Flag() return type(NexusDB)=='table' and rawget(NexusDB,'hasSeenQuickStart') or nil end
local function Record(id)
 return {id=id,title='Synthetic '..id,author='Other-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1}}}
end
local function Overlay(n)local m={};for i=1,n do m['syn-'..i]=Record('syn-'..i) end;return m end

-- 1. Absent saved table: the window still decides, shows and closes, and the
-- saved table is not created by any of those steps.
F.Boot(F.Database())
local keep=NexusDB
NexusDB=nil
Nexus.QuickStart.ShowIfFirstTime()
check(NexusDB==nil,'absent data: deciding whether to show creates no saved table')
check(Shown(),'absent data: the window is shown')
check(Nexus.QuickStart.CanRecordSeen()==false,'absent data: the acknowledgement is withheld')
Button('Later'):Click()
check(NexusDB==nil,'absent data: closing the window creates no saved table')
check(not Shown(),'absent data: the window closes')
Nexus.QuickStart.ShowIfFirstTime()
check(not Shown(),'absent data: it is not shown again in this session')
NexusDB=keep

-- 2. Invalid saved table: it is neither replaced nor repaired.
F.Boot(F.Database())
keep=NexusDB
NexusDB='not a saved table'
Nexus.QuickStart.ShowIfFirstTime()
check(NexusDB=='not a saved table','invalid data: the saved value is unchanged by the decision')
check(Shown(),'invalid data: the window is shown')
Button('Later'):Click()
check(NexusDB=='not a saved table','invalid data: closing writes nothing and repairs nothing')
NexusDB=keep

-- 3. Normal ready start-up: the user action saves the acknowledgement, and
-- nothing else in the saved data changes. It survives a reload.
local H=F.Boot(F.Database())
local s=Nexus.StartupStatus()
check(s.coreReady and s.state~='failed','ready: local start-up completed: '..tostring(s.reason))
check(Nexus.Store.StateWriteStatus().mode=='durable','ready: the saved-data owner is writable')
check(Flag()==nil,'ready: the acknowledgement is not set before the user acts')
Nexus.QuickStart.ShowIfFirstTime()
check(Shown(),'ready: the window is shown once')
local before=F.Serialize(NexusDB)
Button('Later'):Click()
check(Flag()==true,'ready: the user action records the acknowledgement')
NexusDB.hasSeenQuickStart=nil
check(F.Serialize(NexusDB)==before,'ready: the acknowledgement is the only change')
NexusDB.hasSeenQuickStart=true
check(not Shown(),'ready: the window closes')
H=F.Reload();H.Advance(1,.05)
check(Flag()==true,'ready: the acknowledgement survives a reload')
Nexus.QuickStart.ShowIfFirstTime()
check(not Shown(),'ready: the window is not offered again')

-- 4. Entry buttons still open their own views and keep their own checks.
F.Boot(F.Database())
Nexus.QuickStart.ShowIfFirstTime()
Button('Import / Create Wishlist'):Click()
check(Flag()==true,'ready: an entry button also records the acknowledgement')
check(NexusEditorFrame and NexusEditorFrame:IsShown(),'ready: the Wishlist editor opens')

-- 5. Failed start-up (a non-capacity catalog refusal): local tools wait, the
-- window is usable, and nothing is written.
local bad={settingsVersion=2,settings={autoPick=false},chars={},communityBuilds={ok=Record('ok')},
 buildCatalog={schemaVersion=1,catalogVersion='x',sourceVersion='x',unexpected='field'}}
F.Boot(bad)
local b=Nexus.StartupStatus()
check(b.state=='failed' and not b.coreReady,'failed: local start-up is withheld: '..tostring(b.reason))
local failedBefore=F.Serialize(NexusDB)
Nexus.QuickStart.ShowIfFirstTime()
check(Shown(),'failed: the window is still shown')
check(Nexus.QuickStart.CanRecordSeen()==false,'failed: the acknowledgement is withheld')
Button('Later'):Click()
check(not Shown(),'failed: the window closes')
check(Flag()==nil,'failed: no acknowledgement is written')
check(F.Serialize(NexusDB)==failedBefore,'failed: the saved data is unchanged')
Nexus.QuickStart.ShowIfFirstTime()
check(not Shown(),'failed: the session dismissal prevents a second prompt')
Nexus.QuickStart.Show()
check(Shown(),'failed: the user can still open it deliberately')

-- 6. Malformed saved format marker: the session is read-only.
local readOnly=F.Database({mutate=function(db)db.settingsVersion={version=5} end})
F.Boot(readOnly)
local w=Nexus.Store.StateWriteStatus()
check(w.mode=='unavailable' and w.format=='malformed','read-only: the owner refuses writes: '..tostring(w.mode))
local roBefore=F.Serialize(NexusDB)
Nexus.QuickStart.ShowIfFirstTime()
check(Shown(),'read-only: the window is still shown')
Button('Later'):Click()
check(Flag()==nil,'read-only: no acknowledgement is written')
check(F.Serialize(NexusDB)==roBefore,'read-only: the saved data and the marker are unchanged')

-- 7. Capacity-refused shared catalog: local tools work, local Wishlist saves
-- approved by decision C still persist, and the acknowledgement is withheld.
local refused={settingsVersion=2,settings={autoPick=false},chars={},communityBuilds=Overlay(2049)}
local H7=F.Boot(refused,function(H)
 H.perks.serverBuildSlots={[1]={name='Local plan',verified=true,echoes={{spellId=200001,quality=1,stacks=2}}}}
 H.perks.serverActiveSlot=1
end)
local c=Nexus.StartupStatus()
check(c.state=='failed' and c.reason=='ROOT_SLOT_LIMIT' and c.coreReady==true,
 'capacity: the shared catalog is refused and local tools start: '..tostring(c.reason))
local capacityBefore=F.Serialize(NexusDB)
Nexus.QuickStart.ShowIfFirstTime()
check(Shown(),'capacity: the window is shown')
Button('Later'):Click()
check(Flag()==nil,'capacity: no acknowledgement is written')
check(F.Serialize(NexusDB)==capacityBefore,'capacity: the saved data is unchanged by the window')
-- Decision C persistence is untouched: a local Wishlist assignment is saved.
local A=Nexus.GameAdapter
check(A.SetFirstLoadoutWishlistIdentity('Local plan',{{spellId=200001,quality=1,stacks=2}}),
 'capacity: a local Wishlist assignment is accepted')
H7.Notify();A.Poll();H7.Advance(1,.05)
check(A.AssignedWishlist().state=='ready','capacity: the local assignment resolves')
check(F.Serialize(NexusDB)~=capacityBefore,'capacity: the local assignment reached saved data')
check(Flag()==nil,'capacity: the local save did not record the acknowledgement')
local savedRows=0
for _,row in pairs(NexusDB.chars or {})do
 if type(row)=='table' and type(row.loadoutWishlists)=='table' and next(row.loadoutWishlists)~=nil then
  savedRows=savedRows+1
 end
end
check(savedRows==1,'capacity: exactly one saved character row holds the local Wishlist: '..savedRows)
print('PASS quickstart_seen_guard: no database is created or repaired; the acknowledgement is saved only by a durable session; local saves are unaffected checks='..checks)
