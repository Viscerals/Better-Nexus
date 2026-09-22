-- The saved update keys (updateNotice, updateAdvisory, updateDismissed) are
-- maintained only while saved data can really be written. A read-only session
-- keeps them exactly as found, including through /nexus update and through a
-- dismissal, and an older single-entry dismissed list is never replaced by a
-- partial copy of itself. Real TOC boot; synthetic saved data only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local AVAILABLE='1.99.0'
local function Boot(db)
 F.fileHooks={[ [[data\Release.lua]] ]=function()Nexus.Release.availableVersion=AVAILABLE end}
 local H=F.Boot(db);F.fileHooks=nil
 return H
end
local function Keys()
 return F.Serialize({notice=NexusDB.updateNotice,advisory=NexusDB.updateAdvisory,
  dismissed=NexusDB.updateDismissed,noticeQuarantine=NexusDB.updateNoticeQuarantine,
  advisoryQuarantine=NexusDB.updateAdvisoryQuarantine})
end
local function Saved(db)
 db.updateNotice={version='9.9.9',test=1,authority='peer-observation',source='Peer-Realm'}
 db.updateAdvisory={testBuild={version='9.9.9',test=2,observedAt=1}}
 db.updateDismissed='1.96.6#0'
 return db
end

-- 1. A malformed saved format marker keeps the whole profile read-only.
local readOnly=Saved(F.Database({mutate=function(db)db.settingsVersion={version=5} end}))
local before=F.Serialize({notice=readOnly.updateNotice,advisory=readOnly.updateAdvisory,
 dismissed=readOnly.updateDismissed,noticeQuarantine=nil,advisoryQuarantine=nil})
local H=Boot(readOnly)
local w=Nexus.Store.StateWriteStatus()
check(w.mode=='unavailable' and w.format=='malformed','read-only: the saved-data owner refuses writes: '..tostring(w.mode))
check(Keys()==before,'read-only: start-up rewrites, quarantines or removes no update key')
local chat=#H.chat;SlashCmdList.NEXUS('update')
check(#H.chat>chat,'read-only: /nexus update still answers')
check(Keys()==before,'read-only: /nexus update writes nothing')
local status=Nexus.Updates.Status()
check(type(status)=='table' and type(status.state)=='string','read-only: the update status is still available: '..tostring(status.state))
check(Nexus.Updates.Dismiss()==true,'read-only: a dismissal is accepted for this session')
check(Keys()==before,'read-only: the dismissal writes nothing and keeps the saved list')
-- The dismissal that cannot be saved still holds for this session: the same
-- target is not announced again after it. Notices are switched off first so
-- that the session state comes from the dismissal, not from an earlier notice.
local notices=0
Nexus.Updates.SetEnabled(false)
Nexus.Updates.Init({notify=function()notices=notices+1 end})
check(notices==0,'read-only: with notices off nothing is announced')
check(Nexus.Updates.Dismiss()==true,'read-only: the dismissal is accepted')
Nexus.Updates.SetEnabled(true)
check(notices==0,'read-only: the dismissed target stays quiet for the rest of the session')
check(Keys()==before,'read-only: it still writes no update key')
-- Positive control: without the dismissal the same target is announced once.
Nexus.Updates.SetEnabled(false)
Nexus.Updates.Init({notify=function()notices=notices+1 end})
Nexus.Updates.SetEnabled(true)
check(notices==1,'control: the target is announced when it was not dismissed: '..notices)

-- 2. Positive control: a durable session maintains the same keys as before.
local durable=Saved(F.Database())
Boot(durable)
check(Nexus.Store.StateWriteStatus().mode=='durable','durable: the saved-data owner is writable')
check(NexusDB.updateNotice==nil or NexusDB.updateNotice.authority=='bundled-release',
 'durable: a stored peer-authority notice is not kept as a notice')
check(type(NexusDB.updateNoticeQuarantine)=='table','durable: it is quarantined instead')
check(NexusDB.updateAdvisory==nil and type(NexusDB.updateAdvisoryQuarantine)=='table',
 'durable: the stored peer advisory is quarantined once')
check(Nexus.Updates.Dismiss()==true,'durable: the dismissal is accepted')
local list=NexusDB.updateDismissed
check(type(list)=='table' and list[1]=='1.96.6#0' and type(list[2])=='string' and #list==2,
 'durable: the older single dismissal is kept and the new one is added: '..F.Serialize(list))
check(Nexus.Updates.Dismiss()==true and #NexusDB.updateDismissed==2,'durable: dismissing the same target twice adds nothing')
print('PASS update_keys_read_only: update keys untouched in a read-only session; normal maintenance and dismissal kept checks='..checks)
