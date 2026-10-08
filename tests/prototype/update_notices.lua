-- Prerelease update notices, end to end: declared release identity -> the real
-- Sync request producer -> the real inbound decoder -> the update observer ->
-- chat notice, menu status, popup and /nexus update. Since 2026-09-21 only
-- release evidence bundled in the package produces a notice; a peer version is
-- a bounded diagnostic observation (sections 3-10).
-- test.9027 compared against baseVersion 1.19.5, accepted only a bundled
-- availableVersion that no package had, excluded every prerelease, and stored a
-- peer version without showing anything. A test build never learned about a
-- newer test build. All versions here are synthetic. No network, no game client.
local T=dofile('tests/prototype/startup_support.lua')
local H,popup
-- identity: nil = repository source (set explicitly below, so the test means the same
-- thing when it runs on a packaged copy whose data/Release.lua carries a package label);
-- else {label=,channel=,version=,available=}
local function Boot(identity,db)
 Nexus=nil;NexusDB=db;WishlistRealizerDB=nil;SlashCmdList=nil
 H=dofile('tests/prototype/harness.lua')
 NexusDB=NexusDB or T.Profile(3,0)
 T.Load()
 identity=identity or {label='source',channel='development'}
 if identity then
  Nexus.Release.buildLabel=identity.label or Nexus.Release.buildLabel
  Nexus.Release.channel=identity.channel or Nexus.Release.channel
  if identity.version then Nexus.Release.version=identity.version;Nexus.VERSION=identity.version end
  Nexus.Release.availableVersion=identity.available
 end
 popup=nil
 local show=StaticPopup_Show
 StaticPopup_Show=function(which,a,b,data)popup={which=which,text=a,url=b};return show(which,a,b,data)end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
end
local function Ready()T.Until(H,function()return Nexus.StartupStatus().state=='ready' end);T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,40000)end
local PUBLIC27={label='test.9027-3f1cd20',channel='public-test'}
local function Chat(pattern)local n=0;for _,l in ipairs(H.chat)do if l:find(pattern,1,true)then n=n+1 end end;return n end
local function LastChat(pattern)for i=#H.chat,1,-1 do if H.chat[i]:find(pattern,1,true)then return H.chat[i] end end end

-- The real producer: the ordinary Sync request of a client with the given identity.
local function Produce(identity)
 Boot(identity);Ready()
 SlashCmdList.NEXUS('sync')
 local text
 T.Until(H,function()for _,p in ipairs(H.sent)do local s=p.text:gsub('||','|'):gsub('^P%d+:','');if s:find('^WLRQ|')then text=s end end;return text~=nil end,4000)
 return text
end
local function Field(text,index)local n=0;for part in (text..'|'):gmatch('([^|]*)|')do n=n+1;if n==index then return part end end end
-- Deliver one request through the real channel event and inbound decoder.
local serial=0
local function Deliver(text,peer,version)
 serial=serial+1
 peer=peer or ('Peer'..serial)
 text=text:gsub('^WLRQ|[^|]+|','WLRQ|'..peer..'|'):gsub('c1%-[%w%-]+','c1-'..(7000+serial)..'-1001')
 if version then local head=text:match('^(.*)|[^|]*$');text=head..'|'..version end
 local before=Nexus.Sync.Stats().malformedRejected or 0
 H.Fire('CHAT_MSG_CHANNEL',text,peer..'-Ebonhold',nil,'1. '..Nexus.Sync.ChannelName(),nil,nil,nil,nil,Nexus.Sync.ChannelName())
 return (Nexus.Sync.Stats().malformedRejected or 0)==before
end

-- 1. Producer. Only a public test package states its test number; the packet gains no field.
local source=Produce(nil)
assert(Field(source,6)=='1.20.0-beta.1+dev' and Field(source,7)==nil,'repository source marks its announcement as development: '..source)
local internal=Produce({label='test.9028-abcdef0',channel='internal'})
assert(Field(internal,6)=='1.20.0-beta.1+internal','an internal or review package never announces a public test number: '..internal)
local request28=Produce({label='test.9028-abcdef0',channel='public-test'})
assert(Field(request28,6)=='1.20.0-beta.1+test.9028' and Field(request28,7)==nil,'public test.9028 announces its number in the existing version field: '..request28)
assert(#Field(request28,6)<=32 and Nexus.Version.Compare(Field(request28,6),'1.20.0-beta.1')==0,'build metadata leaves standard SemVer precedence unchanged')
assert(Nexus.Version.Compare('1.20.0-beta.1+test.9','1.20.0-beta.1+test.10')==0 and Nexus.Version.Compare('1.20.0-beta.2','1.20.0-beta.10')==-1,'the version library keeps its rules for every other user')
local id=Nexus.ReleaseIdentity()
assert(id.test==9028 and id.channel=='public-test' and id.display=='1.20.0-beta.1 test.9028' and id.label=='test.9028-abcdef0')
print('PASS producer: '..Field(request28,6))

-- 2. Installed test.9027, no evidence: status is unknown, never "up to date"; the link still works.
Boot(PUBLIC27)
local status=Nexus.Updates.Status()
assert(status.state=='unknown' and status.installed=='1.20.0-beta.1 test.9027' and status.channel=='public-test' and status.preference=='test','installed identity and unknown state before anything else is ready: '..status.detail)
assert(status.detail:find('not proof that this build is the latest',1,true) and not status.detail:lower():find('up to date',1,true),'absence of evidence is not a verified latest build')
assert(Nexus.StartupStatus().state~='ready','fixture: shared data is still preparing')
SlashCmdList.NEXUS('update')
assert(popup and popup.which=='NEXUS_UPDATE_RELEASES' and popup.url=='https://github.com/Viscerals/Better-Nexus/releases' and popup.text:find('Installed: 1.20.0-beta.1 test.9027',1,true),'/nexus update works while the Community catalog is pending')
assert(Chat('Releases page: https://github.com/Viscerals/Better-Nexus/releases')==1)
print('PASS unknown status and manual link before catalog completion')

-- 3. The real path: test.9027 receives the real test.9028 request. Since 2026-09-23
-- a qualifying same-series public test is shown as an explicitly UNVERIFIED hint:
-- never a candidate, never saved, never a GitHub check and never a peer link.
-- Anything that is not that exact shape stays completely silent (native report:
-- a peer stating 1.96.6 was announced as a newer release; still refused below).
Ready()
local function NoNotice(why)
 local s=Nexus.Updates.Status()
 assert(s.state=='unknown' and s.candidate==nil,why..': status stays unknown: '..s.detail)
 assert(Nexus.Updates.GetVisibleNotice()==nil and Nexus.Updates.GetCandidate()==nil,why..': no visible notice, no candidate')
 assert(Chat('newer Nexus')==0 and Chat('was reported')==0 and Chat('available:')==0,why..': no update chat line')
 assert(NexusDB.updateAdvisory==nil and NexusDB.updateNotice==nil,why..': nothing is saved as an advisory or a notice')
 assert(Nexus.Updates.PublicTestHint()==nil,why..': and no public-test hint either')
 return s
end
-- A hint, and none of the things a hint must never become.
local function HintOnly(display,why)
 local s=Nexus.Updates.Status()
 local hint=Nexus.Updates.PublicTestHint()
 assert(hint,why..': a qualifying announcement is shown as a hint: '..s.detail)
 assert(hint.display==display and hint.verified==false and hint.authority=='peer-report-unverified',
  why..': the hint states exactly what it is: '..tostring(hint.display)..' / '..tostring(hint.authority))
 assert(Nexus.Updates.GetCandidate()==nil and Nexus.Updates.GetVisibleNotice()==nil,
  why..': a hint is never a candidate and never a trusted notice')
 assert(NexusDB.updateAdvisory==nil and NexusDB.updateNotice==nil and NexusDB.updateDismissed==nil,
  why..': and nothing about it is written to saved data')
 assert(s.detail:find('not checked against GitHub',1,true) and not s.detail:lower():find('up to date',1,true),
  why..': the status says it was not checked: '..s.detail)
 assert(s.url=='https://github.com/Viscerals/Better-Nexus/releases',why..': the configured Releases page only')
 return s,hint
end
local function Observed(source)
 for _,row in ipairs(Nexus.Updates.PeerObservations())do if row.source==source or row.source:sub(1,#source+1)==source..'-' then return row end end
end
assert(Deliver(request28,'TesterB'),'the inbound decoder accepts the request')
local hint
status,hint=HintOnly('1.20.0-beta.1 test.9028','same-series test.9028 from one peer')
assert(status.state=='hint' and status.candidate==nil,'the state is the hint, never "available": '..status.detail)
assert(status.menu=='Newer public test reported: 1.20.0-beta.1 test.9028 (unverified)','the menu says it is unverified: '..status.menu)
local row=assert(Observed('TesterB'),'the peer version is kept as a bounded diagnostic observation')
assert(row.version=='1.20.0-beta.1+test.9028' and row.authority=='peer-observation' and row.reported=='test','the observation states what the peer said and its shape, not release evidence')
assert(Chat('UNVERIFIED')==1 and Chat('available:')==0,'one unverified hint line, and no trusted-release wording')
assert(LastChat('UNVERIFIED'):find('1.20.0-beta.1 test.9028',1,true) and not LastChat('UNVERIFIED'):lower():find('http',1,true),
 'the line names the reported build and carries no link: '..tostring(LastChat('UNVERIFIED')))
for i=1,12 do assert(Deliver(request28,'Crowd'..i))end
HintOnly('1.20.0-beta.1 test.9028','many agreeing peers')
assert(Chat('UNVERIFIED')==1,'twelve peers repeating it add no further chat line')
assert(#Nexus.Updates.PeerObservations()>=13,'every peer is still observed')
assert(NexusPanel._menuBtn:GetText()~='!','an unverified hint never raises the trusted HUD badge')
Nexus.Panel.ShowUpdateStatus()
assert(popup.url=='https://github.com/Viscerals/Better-Nexus/releases'
 and popup.text:find('Newer public test reported: 1.20.0-beta.1 test.9028',1,true)
 and popup.text:find('Reported by another client; not checked against GitHub',1,true)
 and popup.text:find('Check the Better Nexus Releases page before updating',1,true),
 'the popup: installed build, the unverified hint, the local link: '..popup.text)
assert(not popup.text:find('http',1,true),'and no link inside the popup text at all: '..popup.text)
assert(#H.actions==0,'opening the status is read-only')
-- Seeing it is a session dismissal: it stops the line and writes nothing.
assert(NexusDB.updateDismissed==nil,'the hint dismissal saved no dismissal list')
for i=1,3 do assert(Deliver(request28,'Again'..i))end
assert(Chat('UNVERIFIED')==1,'a dismissed hint is not announced again by a repeat')
assert(Nexus.Updates.PublicTestHint().dismissed==true,'and it stays in the status, marked as seen')
print('PASS a qualifying same-series public test is an unverified hint and nothing more')

-- 4. Fresh peer reports that must never create authority: the reported 1.96.6, an arbitrary
-- high number, a forged public test number, another release line.
local FORGED='1.20.0-beta.1+test.99999'
for _,version in ipairs({'1.96.6','999.0.0',FORGED,'2.0.0-beta.1+test.1','1.20.0','1.21.0'})do
 Boot(PUBLIC27);Ready()
 assert(Deliver(request28,'Reporter',version),'fixture: the decoder accepts '..version)
 local hinted=version==FORGED
 if hinted then
  -- Valid syntax, a public-test marker and a plausible number authenticate
  -- nothing. A deliberately false announcement of the right shape becomes a
  -- hint that says it is unverified, and never anything stronger.
  local hs,hh=HintOnly('1.20.0-beta.1 test.99999','forged but valid-looking '..version)
  assert(hs.state=='hint' and hh.verified==false and hh.authority=='peer-report-unverified',
   'a forged announcement stays unverified: '..hs.detail)
 else
  NoNotice('peer '..version)
 end
 assert(Observed('Reporter').version==version,'observed as stated: '..version)
 local items;EasyMenu=function(list)items=list end
 NexusPanel._menuBtn:Click();H.Advance(1,.05)
 local found=false
 for _,item in ipairs(items or {})do
  if type(item.text)=='string' then
   if not hinted then
    assert(not item.text:find(version:match('^[%d%.]+'),1,true) or item.text:find('Installed',1,true),'no menu entry names the peer version '..version..': '..item.text)
   end
   if item.text=='Update status unknown - open Releases page' then found=not item.disabled end
   if hinted and item.text=='Newer public test reported: 1.20.0-beta.1 test.99999 (unverified)' then found=not item.disabled end
  end
 end
 assert(found,'the menu keeps an enabled entry to the manual Releases page')
 assert(NexusPanel._menuBtn:GetText()~='!','no HUD badge for a peer version '..version)
end
print('PASS 1.96.6, 999.0.0, another lineage and peer stable claims stay silent; a forged same-series test is an unverified hint only')

-- 5. A peer advisory saved by an earlier build (as test.9028 stored "1.96.6") does not return at
-- login or reload. It is moved once into a bounded diagnostic record; nothing else changes.
local d=T.Profile(3,0)
d.updateAdvisory={authority='peer-advisory',stableRelease={version='1.96.6',observedAt=1790016000},testBuild={version='1.20.0-beta.1',test=9030,observedAt=1790016000}}
d.updateDismissed={'1.20.0-beta.1#9020'}
d.settings.updateNotifications=true
local before={builds=T.Count(d.communityBuilds),dismissed=d.updateDismissed[1],autoPick=d.settings.autoPick}
Boot(PUBLIC27,d)
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
NoNotice('saved 1.96.6 advisory at login')
assert(NexusDB.updateAdvisoryQuarantine and NexusDB.updateAdvisoryQuarantine.stableRelease.version=='1.96.6'
 and NexusDB.updateAdvisoryQuarantine.testBuild.test==9030 and NexusDB.updateAdvisoryQuarantine.reason=='peer report is not release evidence','kept as a bounded diagnostic record')
assert(T.Count(NexusDB.communityBuilds)==before.builds and NexusDB.updateDismissed[1]==before.dismissed
 and NexusDB.settings.autoPick==before.autoPick and NexusDB.settings.updateNotifications==true,'settings, dismissals and builds are unchanged')
db=NexusDB;Boot(PUBLIC27,db);Ready()
NoNotice('reload after the quarantine')
assert(NexusDB.updateAdvisoryQuarantine.stableRelease.version=='1.96.6','idempotent: the diagnostic record stays once')
-- A malformed saved advisory is handled the same way.
d=T.Profile(3,0);d.updateAdvisory='9.9.9'
Boot(PUBLIC27,d);NoNotice('malformed saved advisory')
print('PASS saved peer advisory: no notice at login or reload, quarantined once, nothing else touched')

-- 6. Trusted bundled evidence keeps its notice, its wording and its place; a higher peer
-- version cannot replace or hide it.
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.20.0-beta.1+test.9029'});Ready()
s=Nexus.Updates.Status()
assert(s.state=='available' and s.candidate.verified==true and s.candidate.authority=='bundled-release' and s.menu=='Update available: 1.20.0-beta.1 test.9029','bundled evidence is compared with the installed build: '..s.detail)
assert(Chat('New Nexus test build available: 1.20.0-beta.1 test.9029. You have 1.20.0-beta.1 test.9027.')==1,'one trusted chat notice')
for _,version in ipairs({'1.96.6','1.20.0-beta.1+test.9031','999.0.0'})do
 assert(Deliver(request28,'Masker',version))
 s=Nexus.Updates.Status()
 assert(s.candidate.display=='1.20.0-beta.1 test.9029' and s.candidate.verified==true,'a peer '..version..' does not replace or hide trusted evidence')
end
assert(Chat('available:')==1,'exactly one trusted chat line')
-- The 1.20.0-beta.1+test.9031 report above is newer than this installation, so
-- it is a hint. It is added beside the trusted candidate, never over it.
local beside=assert(Nexus.Updates.PublicTestHint(),'the reported 9031 is a hint')
assert(beside.display=='1.20.0-beta.1 test.9031' and beside.verified==false,'unverified: '..beside.display)
s=Nexus.Updates.Status()
assert(s.state=='available' and s.candidate.display=='1.20.0-beta.1 test.9029' and s.candidate.verified==true,
 'the trusted candidate still owns the state: '..s.detail)
assert(s.detail:find('New Nexus test build available: 1.20.0-beta.1 test.9029',1,true)
 and s.detail:find('Another client also reports 1.20.0-beta.1 test.9031 (unverified',1,true),
 'the trusted line comes first and the hint is marked: '..s.detail)
assert(Nexus.Updates.GetCandidate().display=='1.20.0-beta.1 test.9029','and the candidate is unchanged')
local items;EasyMenu=function(list)items=list end
NexusPanel._menuBtn:Click();H.Advance(1,.05)
local entry
for _,item in ipairs(items or {})do if item.text=='Update available: 1.20.0-beta.1 test.9029' then entry=item end end
assert(entry and not entry.disabled and NexusPanel._menuBtn:GetText()=='!','menu entry and HUD badge for trusted evidence')
popup=nil;entry.func()
assert(popup and popup.url=='https://github.com/Viscerals/Better-Nexus/releases' and popup.text:find('New Nexus test build available: 1.20.0-beta.1 test.9029',1,true))
print('PASS trusted bundled notice kept; peer versions cannot replace or hide it')

-- 7. Bundled same, older and newer builds; stable successor; channels.
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.20.0-beta.1+test.9027'})
assert(Nexus.Updates.Status().state=='unknown','bundled same build: unknown, never available')
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.20.0-beta.1+test.9026'})
assert(Nexus.Updates.Status().state=='unknown','bundled older test build: unknown')
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.19.5'})
assert(Nexus.Updates.Status().state=='unknown','bundled old stable is not an upgrade')
Boot({label='test.9-abcdef0',channel='public-test',available='1.20.0-beta.1+test.10'})
assert(Nexus.Updates.Status().candidate.display=='1.20.0-beta.1 test.10','test.9 -> test.10 is numeric, not lexical')
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.20.0'});Ready()
s=Nexus.Updates.Status()
assert(s.state=='available' and s.candidate.kind=='stable' and LastChat('New Nexus release available: 1.20.0.'),'stable wording for a stable successor')
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.20.0-beta.1+test.9028.ffffff0'})
assert(Nexus.Updates.Status().state=='unknown','a commit suffix never orders builds')
-- Internal and development installations are not placed in a public series by a peer.
local shown,st=nil,nil
Boot({label='test.9029-2d576cf',channel='internal'});Ready()
assert(Deliver(request28,'ToInternal','1.20.0-beta.1+test.9030'))
st=Nexus.Updates.Status();assert(st.state=='unknown' and st.channelLabel=='internal test package' and st.installed=='1.20.0-beta.1 test.9029','an internal package gets no peer-derived notice: '..st.detail)
Boot(nil);Ready()
assert(Deliver(request28,'ToSource','1.20.0-beta.1+test.9030'))
st=Nexus.Updates.Status();assert(st.state=='unknown' and st.channel=='development','a source checkout gets no peer-derived notice')
-- An internal or development package stated by a peer is not a published update either.
Boot(PUBLIC27);Ready()
for _,raised in ipairs({'1.21.0+internal','1.20.0-beta.2+dev','2.0.0-beta.1+internal'})do
 assert(Deliver(request28,'Raised',raised));NoNotice('peer '..raised)
 assert(Observed('Raised').reported==nil,'an internal or development version is not even a release shape: '..raised)
end
print('PASS bundled same/older/newer, stable successor, commit suffix, internal and development identities')

-- 8. Preferences, opt-out, dismissal and reload with trusted evidence.
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.20.0-beta.1+test.9029'});Ready()
Nexus.Updates.SetPreference('stable')
assert(Nexus.Updates.Status().state=='unknown' and Nexus.Updates.Preference()=='stable','stable-only hides a bundled test build')
assert(Nexus.Updates.Status().detail:find('A newer test build (1.20.0-beta.1 test.9029) is not announced because notices are set to stable releases only.',1,true),'the hidden trusted build is named truthfully: '..Nexus.Updates.Status().detail)
assert(Deliver(request28,'ToStableOnly','1.20.0-beta.1+test.9031'))
assert(Nexus.Updates.PublicTestHint()==nil and Nexus.Updates.Status().state=='unknown',
 'stable-only: a public-test announcement produces no hint')
assert(Chat('UNVERIFIED')==0,'stable-only: and no hint chat line')
Nexus.Updates.SetPreference('test')
assert(Nexus.Updates.Status().state=='available','the test-inclusive preference shows it again')
assert(Nexus.Updates.PublicTestHint()~=nil,
 'and the announcement withheld by the preference is available again without any new traffic')
Nexus.Updates.SetEnabled(false)
assert(Nexus.Updates.PublicTestHint()==nil,'notices off: no hint either')
Nexus.Updates.SetEnabled(true)
Nexus.Updates.SetEnabled(false)
s=Nexus.Updates.Status()
assert(s.state=='disabled' and Nexus.Updates.GetVisibleNotice()==nil and s.url=='https://github.com/Viscerals/Better-Nexus/releases','opt-out: no notice, manual link kept')
Nexus.Updates.SetEnabled(true)
Nexus.Panel.ShowUpdateStatus()
db=NexusDB;local chatBefore=Chat('available:')
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.20.0-beta.1+test.9029'},db);Ready()
assert(Nexus.Updates.Status().state=='available' and Chat('available:')==0,'a dismissed trusted target is not announced again after reload; the status stays')
db=NexusDB;Boot({label='test.9027-3f1cd20',channel='public-test',available='1.20.0-beta.1+test.9030'},db);Ready()
assert(Chat('New Nexus test build available: 1.20.0-beta.1 test.9030.')==1,'a newer trusted target is announced once')
Boot({version='1.19.5',channel='stable',available='1.20.0-beta.1+test.9029'})
assert(Nexus.Updates.Preference()=='stable' and Nexus.Updates.Status().state=='unknown','a stable installation is not pushed into a beta by default')
print('PASS preferences, opt-out, dismissal and reload with trusted evidence')

-- 9. Hostile input and the local link. A notice stored by an older client with peer authority stays quarantined.
Boot(PUBLIC27);Ready()
local rejected=0
for _,bad in ipairs({'1.20.0-beta.1+test.9028 http://x.example','http://evil.example/Nexus.zip','1.20.0-beta.1+test.9028|cffff0000','1.20.0-beta.1+test.99999999999999999999','9'..string.rep('9',40),'1.20.0-beta.1+test.9028+x','1.20.0-beta.1+test..9028',''})do
 if not Deliver(request28,'Hostile',bad)then rejected=rejected+1 end
end
for _,text in ipairs({'9.9.9-www.evil.example.zip','9.9.9-get-it-at.evil-nexus.com','9.9.9-beta.1.evil'})do
 assert(Deliver(request28,'Texter',text),'fixture: the decoder accepts '..text)
end
NoNotice('hostile and free-form versions ('..rejected..' refused by the decoder)')
for _,l in ipairs(H.chat)do assert(not l:find('evil',1,true),'no peer text in chat')end
Nexus.Release.releasesUrl='http://evil.example/x';assert(Nexus.Updates.ReleaseUrl()=='https://github.com/Viscerals/Better-Nexus/releases','a malformed local link falls back to the fixed page')
Boot(PUBLIC27,(function()local x=T.Profile(3,0);x.updateNotice={version='9.9.9',authority='peer'};return x end)())
assert(Nexus.Updates.Status().state=='unknown' and NexusDB.updateNotice==nil and NexusDB.updateNoticeQuarantine.version=='9.9.9','a peer-authority notice kept by an older client is quarantined, not shown')
print('PASS hostile input, local link only, legacy notice quarantine')

-- 10. Sync peer handling is unchanged: the request is accepted, the peer is observed, nothing is refused.
Boot(PUBLIC27);Ready()
local rejectedBefore=Nexus.Sync.Stats().malformedRejected or 0
assert(Deliver(request28,'SyncPeer','1.96.6') and (Nexus.Sync.Stats().malformedRejected or 0)==rejectedBefore,'a peer with any valid version is still accepted for Sync')
assert(Observed('SyncPeer') and Observed('SyncPeer').reported=='stable','and observed for diagnostics')
for i=1,40 do assert(Deliver(request28,'Many'..i,'1.20.0-beta.1+test.'..(9100+i)))end
assert(#Nexus.Updates.PeerObservations()<=32,'the diagnostic list stays bounded')
-- Forty different rising numbers are ONE hint - the highest - and at most the
-- bounded number of chat lines. A flood never becomes a stream of popups.
local flood=assert(Nexus.Updates.PublicTestHint(),'the highest reported test is the one hint')
assert(flood.display=='1.20.0-beta.1 test.9140','the highest by number, not by order or text: '..flood.display)
assert(Chat('UNVERIFIED')<=2,'the session hint bound holds: '..Chat('UNVERIFIED'))
assert(Nexus.Updates.GetCandidate()==nil and NexusDB.updateNotice==nil and NexusDB.updateAdvisory==nil,
 'and forty peers still create no candidate and no saved state')
print('PASS Sync peer acceptance, bounded diagnostics and one bounded hint')

-- 11. Review of the earlier padded-label rule stays.
Boot({label='test.007-abcdef0',channel='public-test'})
assert(Nexus.ReleaseIdentity().test==nil and Nexus.ReleaseIdentity().channel=='internal','a padded label states no test number, as in the tools')
print('PASS padded label')

-- 12. Old peers. The published test.9027 decoder rule is the same ValidVersion: prove it accepts the new announcement.
Boot(PUBLIC27);Ready()
assert(Nexus.SyncInternals and Deliver(request28,'OldPeerCheck'),'request with +test metadata is a valid request')
assert(Nexus.Sync.Stats().malformedRejected==0)
assert(#H.actions==0,'no gameplay action in any case')
print('PASS update notices')
