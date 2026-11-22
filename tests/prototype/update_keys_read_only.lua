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
-- 3. A public-test hint gains no exception. In the same read-only session it
-- is shown, reaches the status and is dismissed, all from session state: a
-- start-up that may not write is not made to write by an unverified hint.
local hintDb=Saved(F.Database({mutate=function(db)db.settingsVersion={version=5} end}))
local hintBefore=F.Serialize({notice=hintDb.updateNotice,advisory=hintDb.updateAdvisory,
 dismissed=hintDb.updateDismissed,noticeQuarantine=nil,advisoryQuarantine=nil})
F.fileHooks={[ [[data\Release.lua]] ]=function()
 Nexus.Release.availableVersion=nil
 Nexus.Release.buildLabel='test.9035-abcdef0';Nexus.Release.channel='public-test'
end}
F.Boot(hintDb);F.fileHooks=nil
check(Nexus.Store.StateWriteStatus().mode=='unavailable','read-only hint: the owner still refuses writes')
check(Nexus.ReleaseIdentity().channel=='public-test','fixture: a public test installation')
check(Nexus.Updates.Observe('1.20.0-beta.1+test.9037','ReadOnlyPeer-Realm'),'read-only hint: the announcement is accepted')
local hint=Nexus.Updates.PublicTestHint()
check(hint and hint.display=='1.20.0-beta.1 test.9037','read-only hint: it is shown from session state')
check(Nexus.Updates.Status().state=='hint','read-only hint: and reaches the status')
check(Nexus.Updates.DismissHint()==true,'read-only hint: the dismissal is accepted')
check(Keys()==hintBefore,'read-only hint: and none of it wrote an update key')

-- 4. A read-only root stays read-only while the character identity is not
-- known (the client placeholder name, or no realm yet). The saved-format
-- verdict comes first, so the owner refuses rather than answering "loading",
-- and no update path rewrites, quarantines or removes a saved key.
local identityCases={
 {'Unknown name',function(real)return function(unit)if unit=='player' then return 'Unknown' end return real(unit)end end,nil},
 {'empty realm',nil,function()return '' end},
}
for _,format in ipairs({
 {'future',function(db)db.settingsVersion=6 end},
 {'unverified',function(db)db.settingsVersion=5;db.settings.syncMode='sometimes' end},
 {'malformed',function(db)db.settingsVersion={version=5} end}}) do
 for _,case in ipairs(identityCases) do
  local label=format[1]..' / '..case[1]
  local db=Saved(F.Database({mutate=format[2]}))
  local keysBefore=F.Serialize({notice=db.updateNotice,advisory=db.updateAdvisory,
   dismissed=db.updateDismissed,noticeQuarantine=nil,advisoryQuarantine=nil})
  Boot(db)
  check(Nexus.Store.StateWriteStatus().mode=='unavailable','fixture '..label..': read-only with identity known')
  check(Keys()==keysBefore,'fixture '..label..': start-up wrote no update key')
  local rootBefore=F.Serialize(NexusDB)
  local realName,realNorm,realRealm=UnitName,GetNormalizedRealmName,GetRealmName
  if case[2] then UnitName=case[2](realName) end
  if case[3] then GetNormalizedRealmName=case[3];GetRealmName=case[3] end
  check(Nexus.Store.CurrentOwnerKey()==nil,'fixture '..label..': the identity is unknown')
  local w=Nexus.Store.StateWriteStatus()
  check(w.mode=='unavailable' and w.reason=='saved-format' and w.format==format[1],
   label..': the saved-format verdict precedes the identity check: '..tostring(w.mode)..'/'..tostring(w.reason)..'/'..tostring(w.format))
  Nexus.Updates.Init({notify=function()end})
  Nexus.Updates.Reevaluate()
  SlashCmdList.NEXUS('update')
  Nexus.Updates.Dismiss()
  Nexus.Updates.SetEnabled(true)
  Nexus.Updates.SetPreference('stable')
  UnitName,GetNormalizedRealmName,GetRealmName=realName,realNorm,realRealm
  check(Keys()==keysBefore,label..': no update key is rewritten, quarantined or removed: '..Keys())
  check(NexusDB.updateNoticeQuarantine==nil and NexusDB.updateAdvisoryQuarantine==nil,label..': no quarantine key is created')
  check(F.Serialize(NexusDB)==rootBefore,label..': the saved root is byte-identical')
 end
end

-- 5. Before the saved-data owner has given a writable verdict (the start-up
-- coordinator has not reached STORE_READY), /nexus update and a dismissal on
-- a writable root still answer but write nothing; the same maintenance then
-- happens once the owner is ready.
local early=Saved(F.Database())
local earlyKeys=F.Serialize({notice=early.updateNotice,advisory=early.updateAdvisory,
 dismissed=early.updateDismissed,noticeQuarantine=nil,advisoryQuarantine=nil})
local earlyMode,earlyChat,earlyAfterUpdate,earlyAfterDismiss
F.fileHooks={[ [[data\Release.lua]] ]=function()Nexus.Release.availableVersion=AVAILABLE end}
F.Boot(early,nil,function(h)
 earlyMode=Nexus.Store.StateWriteStatus().mode
 earlyChat=#h.chat
 SlashCmdList.NEXUS('update')
 earlyChat=#h.chat>earlyChat
 earlyAfterUpdate=Keys()
 Nexus.Updates.Dismiss()
 earlyAfterDismiss=Keys()
end)
F.fileHooks=nil
check(earlyMode~='durable','pre-ready: the owner has not given a writable verdict yet: '..tostring(earlyMode))
check(earlyChat,'pre-ready: /nexus update still answers')
check(earlyAfterUpdate==earlyKeys,'pre-ready: /nexus update writes no update key: '..tostring(earlyAfterUpdate))
check(earlyAfterDismiss==earlyKeys,'pre-ready: a dismissal writes no update key: '..tostring(earlyAfterDismiss))
check(Nexus.StartupStatus().coreReady==true and Nexus.Store.StateWriteStatus().mode=='durable','pre-ready: start-up then completes writable')
check(NexusDB.updateAdvisory==nil and type(NexusDB.updateAdvisoryQuarantine)=='table'
 and type(NexusDB.updateNoticeQuarantine)=='table','pre-ready: the ordinary maintenance happens once the owner is ready')
print('PASS update_keys_read_only: update keys untouched in a read-only session; normal maintenance and dismissal kept checks='..checks)
