-- The one-time release note records lastChangelogSeen only when the saved-data
-- owner reports a durable write and local start-up completed. A failed or
-- read-only start-up shows and closes the note without consuming it, so the
-- acknowledgement is not lost together with the session that could not save
-- it. Real TOC boot; synthetic saved data only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local KEY='prototype-P1.6-assigned-orbs'
local function Seen()
 local top=NexusDB.lastChangelogSeen
 local settings=type(NexusDB.settings)=='table' and NexusDB.settings.lastChangelogSeen or nil
 return top,settings
end
local function Popup() return NexusChangelogPopup end
local function CloseButton()
 local popup=Popup();if not popup then return nil end
 for _,child in ipairs(popup.children or {}) do
  if child.kind=='Button' and child:GetText()=='Got it' then return child end
 end
end
local function Record(id)
 return {id=id,title='Synthetic '..id,author='Other-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1}}}
end
local function Overlay(n)local m={};for i=1,n do m['syn-'..i]=Record('syn-'..i) end;return m end

-- 1. Positive control: an ordinary start-up records the acknowledgement once.
local ok=F.Database({mutate=function(db)db.hasSeenQuickStart=true end})
local H=F.Boot(ok)
H.Advance(3,.05)
local s=Nexus.StartupStatus()
check(s.coreReady and s.state~='failed','control: local start-up completed: '..tostring(s.reason))
check(Nexus.Store.StateWriteStatus().mode=='durable','control: the saved-data owner is writable')
check(Nexus.Changelog.CanRecordSeen()==true,'control: the acknowledgement may be recorded')
check(Popup() and Popup():IsShown(),'control: the release note is shown')
local top,settings=Seen()
check(top==KEY and settings==KEY,'control: the acknowledgement is recorded in both places')
local button=CloseButton()
check(button~=nil,'control: the note has its close button')
button:Click()
check(not Popup():IsShown(),'control: the note closes')
H=F.Reload();H.Advance(3,.05)
check(not (Popup() and Popup():IsShown()),'control: the recorded note is not offered again')

-- 2. A refused shared catalog: local tools start, saved data stays as found.
-- The note is shown and closes, and the acknowledgement is not consumed.
local refused={settingsVersion=2,settings={autoPick=false},chars={},hasSeenQuickStart=true,
 communityBuilds=Overlay(2049)}
local H2=F.Boot(refused)
H2.Advance(3,.05)
local r=Nexus.StartupStatus()
check(r.state=='failed' and r.reason=='ROOT_SLOT_LIMIT' and r.coreReady==true,
 'capacity: the shared catalog is refused and local tools start: '..tostring(r.reason))
check(Nexus.Changelog.CanRecordSeen()==false,'capacity: the acknowledgement is withheld in a failed start-up')
check(Popup() and Popup():IsShown(),'capacity: the release note is still shown')
local top2,settings2=Seen()
check(top2==nil and settings2==nil,'capacity: nothing was written: '..tostring(top2)..'/'..tostring(settings2))
CloseButton():Click()
check(not Popup():IsShown(),'capacity: the note closes normally')
top2,settings2=Seen()
check(top2==nil and settings2==nil,'capacity: closing the note writes nothing either')
H2=F.Reload();H2.Advance(3,.05)
check(Popup():IsShown(),'capacity: the note is offered again in the next session')
local top3,settings3=Seen()
check(top3==nil and settings3==nil,'capacity: the reload records nothing')

-- 3. The same profile once the shared catalog fits: the note is recorded.
NexusDB.communityBuilds['syn-2049']=nil
H2=F.Reload();H2.Advance(3,.05)
local back=Nexus.StartupStatus()
check(back.coreReady and back.state~='failed','recovered: start-up completes: '..tostring(back.reason))
local top4,settings4=Seen()
check(top4==KEY and settings4==KEY,'recovered: the acknowledgement is recorded normally')

-- 4. A malformed saved format marker: the session runs read-only. The note is
-- viewable and closes, and the acknowledgement is never written.
local readOnly=F.Database({mutate=function(db)db.settingsVersion={version=5};db.hasSeenQuickStart=true end})
local H3=F.Boot(readOnly)
H3.Advance(3,.05)
local w=Nexus.Store.StateWriteStatus()
check(w.mode=='unavailable' and w.format=='malformed','read-only: the saved-data owner is not writable: '..tostring(w.mode))
check(Nexus.Changelog.CanRecordSeen()==false,'read-only: the acknowledgement is withheld')
check(Popup() and Popup():IsShown(),'read-only: the release note is still viewable')
CloseButton():Click()
check(not Popup():IsShown(),'read-only: the note closes normally')
Nexus.Changelog.ShowIfNeeded()
local top5,settings5=Seen()
check(top5==nil and settings5==nil,'read-only: no acknowledgement is written: '..tostring(top5)..'/'..tostring(settings5))
check(type(rawget(NexusDB,'settingsVersion'))=='table','read-only: the malformed marker is unchanged')
print('PASS changelog_seen_guard: recorded on a durable start-up; withheld, viewable and re-offered on a refused or read-only one checks='..checks)
