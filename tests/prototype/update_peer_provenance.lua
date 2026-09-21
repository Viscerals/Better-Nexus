-- Release provenance of update notices, module level. The eight scenarios of the
-- supplied reproduction (review archive "Nexus-test9029-update-notice-review",
-- probe_update_advisory.lua, run against the exact test.9029 modules) with the
-- CORRECTED expectations. On test.9029 a peer stating "1.96.6" produced "A newer
-- Nexus release was reported: 1.96.6", the saved report returned at the next
-- initialization, "999.0.0" did the same, and a peer report replaced bundled
-- release evidence. Real data/Release.lua, logic/Version.lua and core/Updates.lua;
-- synthetic saved data, time and callbacks. No harness, no network.
local notices
local function Load(persisted)
 Nexus=nil;NexusDB=persisted or {}
 time=function()return 1790016000 end
 GetTime=function()return 0 end
 dofile('data/Release.lua');dofile('logic/Version.lua');dofile('core/Updates.lua')
 -- A fixed installed identity, the same on the source tree and on a packaged copy.
 Nexus.ReleaseIdentity=function()
  return {version='1.20.0-beta.1',label='test.9029-2d576cf',test=9029,channel='internal',
   announce='1.20.0-beta.1+internal',display='1.20.0-beta.1 test.9029'}
 end
 Nexus.Release.availableVersion=nil
 notices={}
 Nexus.Updates.Init({notify=function(version,url,message)notices[#notices+1]=message end})
end
local function Unknown(name)
 local s=Nexus.Updates.Status()
 assert(s.state=='unknown' and Nexus.Updates.GetCandidate()==nil and Nexus.Updates.GetVisibleNotice()==nil,name..': unknown, no candidate: '..s.detail)
 assert(#notices==0,name..': no notification ('..#notices..')')
 assert(NexusDB.updateAdvisory==nil,name..': no saved advisory')
 assert(s.url=='https://github.com/Viscerals/Better-Nexus/releases' and s.menu=='Update status unknown - open Releases page',name..': the configured Releases page')
 assert(not s.detail:lower():find('up to date',1,true) and s.detail:find('not proof that this build is the latest',1,true),name..': neither available nor latest')
end

Load();Unknown('fresh, no report')
Load()
assert(Nexus.Updates.Observe('1.96.6','SyntheticPeer-Realm'))
assert(Nexus.Version.Compare('1.96.6','1.20.0-beta.1')==1,'the version order itself is unchanged')
Unknown('peer states 1.96.6')
local seen=Nexus.Updates.PeerObservations()
assert(#seen==1 and seen[1].version=='1.96.6' and seen[1].reported=='stable' and seen[1].authority=='peer-observation','kept as a diagnostic observation')
-- The saved data of a client that ran test.9029 (peer advisory stored), then a new initialization with no peer.
Load({updateAdvisory={authority='peer-advisory',stableRelease={version='1.96.6',observedAt=1790016000}},
 updateDismissed={'1.19.9#0'},settings={updateNotifications=true,updateChannel='test',other=7}})
Unknown('saved 1.96.6 at initialization')
assert(NexusDB.updateAdvisoryQuarantine.stableRelease.version=='1.96.6','moved to a bounded diagnostic record')
assert(NexusDB.updateDismissed[1]=='1.19.9#0' and NexusDB.settings.updateChannel=='test' and NexusDB.settings.other==7,'dismissals and settings are unchanged')
Load();assert(Nexus.Updates.Observe('1.19.5','SyntheticPeer-Realm'));Unknown('older release')
Load();assert(Nexus.Updates.Observe('1.20.0-beta.1+test.9028','SyntheticPeer-Realm'));Unknown('older same-series test build')
Load();assert(Nexus.Updates.Observe('999.0.0','SyntheticPeer-Realm'));Unknown('arbitrary 999.0.0')
Load();for i=1,20 do assert(Nexus.Updates.Observe('1.20.0-beta.1+test.'..(9100+i),'Peer'..i..'-Realm'))end;Unknown('many peers, rising test numbers')
-- Trusted bundled evidence (synthetic availableVersion) keeps its notice and is not replaced.
Load()
Nexus.Release.availableVersion='1.21.0'
Nexus.Updates.Reevaluate()
local c=assert(Nexus.Updates.GetCandidate())
assert(c.verified==true and c.authority=='bundled-release' and c.display=='1.21.0' and #notices==1,'bundled evidence: one notice')
assert(notices[1]=='New Nexus release available: 1.21.0. You have 1.20.0-beta.1 test.9029. Installation is manual: /nexus update shows the Releases page.',notices[1])
assert(Nexus.Updates.Observe('1.96.6','SyntheticPeer-Realm'))
c=Nexus.Updates.GetCandidate()
assert(c.display=='1.21.0' and c.verified==true and #notices==1,'a peer 1.96.6 neither replaces nor hides bundled evidence, and adds no notice')
assert(Nexus.Updates.Status().state=='available','status stays available from bundled evidence')
print('PASS update_peer_provenance: 8 reproduction scenarios with corrected expectations')
