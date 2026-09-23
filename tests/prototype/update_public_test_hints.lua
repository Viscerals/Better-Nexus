-- What a public-test hint never does. The hint itself (a newer same-series
-- public test announced by a peer becoming an explicitly UNVERIFIED hint) is
-- covered end to end in update_notices; this file covers the four promises
-- around it: no discovery traffic, no saved-data write, no gameplay action and
-- no survival past the session. Real TOC boot, synthetic saved data and peers.
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,popup
local PUBLIC={label='test.9035-abcdef0',channel='public-test'}
local NEWER='1.20.0-beta.1+test.9037'
local function Boot(db,mode)
 Nexus=nil;NexusDB=db;WishlistRealizerDB=nil;SlashCmdList=nil
 H=dofile('tests/prototype/harness.lua')
 NexusDB=NexusDB or T.Profile(3,0)
 if mode then
  NexusDB.settings=type(NexusDB.settings)=='table' and NexusDB.settings or {}
  NexusDB.settings.syncMode=mode
 end
 T.Load()
 Nexus.Release.buildLabel=PUBLIC.label;Nexus.Release.channel=PUBLIC.channel
 Nexus.Release.availableVersion=nil
 popup=nil
 local show=StaticPopup_Show
 StaticPopup_Show=function(which,a,b,data)popup={which=which,text=a,url=b};return show(which,a,b,data)end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 return H
end
local function Keys()
 return table.concat({tostring(NexusDB.updateNotice),tostring(NexusDB.updateAdvisory),
  tostring(NexusDB.updateDismissed),tostring(NexusDB.updateNoticeQuarantine),
  tostring(NexusDB.updateAdvisoryQuarantine),tostring(NexusDB.updateHint),
  tostring(NexusDB.updateHintDismissed)},'|')
end

-- 1. Reading the hint initiates nothing. Every route a user can take is read
-- only: no packet is built or queued, no gameplay action is submitted, and no
-- saved key appears. Off is the strictest saved Sync mode there is.
for _,mode in ipairs({'off','manual','auto'}) do
 Boot(nil,mode)
 check(Nexus.Updates.PublicTestHint()==nil,mode..': no hint before anything is received')
 check(Nexus.Updates.Observe(NEWER,'TesterC-Realm'),mode..': the announcement is accepted as an observation')
 local hint=Nexus.Updates.PublicTestHint()
 check(hint and hint.display=='1.20.0-beta.1 test.9037',
  mode..': a received announcement is the only way a hint appears: '..tostring(hint and hint.display))
 check(hint.verified==false and hint.authority=='peer-report-unverified',
  mode..': and it is labelled unverified')
 local keys,sent,actions=Keys(),#H.sent,#H.actions
 local status=Nexus.Updates.Status()
 Nexus.Panel.ShowUpdateStatus()
 SlashCmdList.NEXUS('update')
 Nexus.Updates.DismissHint()
 Nexus.Updates.Status()
 check(#H.sent==sent,mode..': reading the status, the popup and /nexus update send nothing: '
  ..#H.sent..' vs '..sent)
 check(#H.actions==actions,mode..': and submit no gameplay action')
 check(Keys()==keys,mode..': and write no update key: '..Keys())
 check(status.state=='hint' and status.detail:find('not checked against GitHub',1,true),
  mode..': the status says what it is: '..status.detail)
 check(popup and popup.url=='https://github.com/Viscerals/Better-Nexus/releases',
  mode..': the only link is the configured Releases page')
 check(not popup.text:find('http',1,true) and not popup.text:lower():find('download',1,true)
  and not popup.text:lower():find('installing',1,true),
  mode..': the popup offers no link, download or installation instruction: '..popup.text)
end

-- 2. The hint is session state. A reload of the same saved data starts with no
-- hint at all, because nothing about it was ever written.
Boot(nil,'auto')
check(Nexus.Updates.Observe(NEWER,'TesterC-Realm'),'fixture: the announcement is received')
check(Nexus.Updates.PublicTestHint()~=nil,'fixture: the hint exists in this session')
Nexus.Updates.DismissHint()
local carried=NexusDB
Boot(carried,'auto')
check(Nexus.Updates.PublicTestHint()==nil,'a reload starts with no hint')
check(Nexus.Updates.Status().state=='unknown','and an honest unknown status')
check(Nexus.Updates.Status().detail:find('No newer public-test announcement was received',1,true)~=nil,
 'that states exactly what is missing: '..Nexus.Updates.Status().detail)
check(not Nexus.Updates.Status().detail:lower():find('up to date',1,true)
 and Nexus.Updates.Status().detail:find('not proof that this build is the latest',1,true),
 'and never calls this installation current')
check(Keys()=='nil|nil|nil|nil|nil|nil|nil','and no update key was written by any of it: '..Keys())

-- 3. A message whose metadata was stripped to fit the transport limit supplies
-- no test number. Nothing is inferred from the release series alone.
Boot(nil,'auto')
check(Nexus.Updates.Observe('1.20.0-beta.1','StrippedPeer-Realm'),'the plain version is still observed')
check(Nexus.Updates.PublicTestHint()==nil,'a stripped announcement supplies no test number')
check(Nexus.Updates.Observe('1.20.0-beta.1+test.9035','EqualPeer-Realm'),'an equal test is observed')
check(Nexus.Updates.PublicTestHint()==nil,'and an equal test number is not newer')
check(Nexus.Updates.Observe('1.20.0-beta.1+test.9034','OlderPeer-Realm'),'an older test is observed')
check(Nexus.Updates.PublicTestHint()==nil,'and an older one is not newer either')
check(Nexus.Updates.Observe('1.20.0-beta.1+test.0009037','PaddedPeer-Realm'),'a padded number is observed')
check(Nexus.Updates.PublicTestHint()==nil,'a padded test identifier states no test number')
check(Nexus.Updates.Observe('1.20.0-beta.1+test.2147483648','HugePeer-Realm'),'an out-of-range number is observed')
check(Nexus.Updates.PublicTestHint()==nil,'and an out-of-range one states none')
check(Nexus.Updates.Observe('1.20.0-beta.1+test.9037.ffffff0','SuffixPeer-Realm'),'a commit suffix is observed')
check(Nexus.Updates.PublicTestHint()==nil,'a commit suffix never orders builds')
check(Nexus.Updates.Observe('1.21.0-beta.1+test.9037','OtherSeriesPeer-Realm'),'another series is observed')
check(Nexus.Updates.PublicTestHint()==nil,'and a different release series is not this series')
check(Nexus.Updates.Observe(NEWER,'RealPeer-Realm'),'the qualifying announcement is accepted')
check(Nexus.Updates.PublicTestHint()~=nil,'control: the qualifying shape does produce the hint')

print('PASS update_public_test_hints: a hint is received, never fetched; session only; no write, no traffic, no action checks='..checks)
