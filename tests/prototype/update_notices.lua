-- Prerelease update notices, end to end: declared release identity -> the real
-- Sync request producer -> the real inbound decoder -> the update observer ->
-- chat notice, menu status, popup and /nexus update.
-- test.9027 compared against baseVersion 1.19.5, accepted only a bundled
-- availableVersion that no package had, excluded every prerelease, and stored a
-- peer version without showing anything. A test build never learned about a
-- newer test build. All versions here are synthetic. No network, no game client.
local T=dofile('tests/prototype/startup_support.lua')
local H,popup
-- identity: nil = repository source; else {label=,channel=,version=,available=}
local function Boot(identity,db)
 Nexus=nil;NexusDB=db;WishlistRealizerDB=nil;SlashCmdList=nil
 H=dofile('tests/prototype/harness.lua')
 NexusDB=NexusDB or T.Profile(3,0)
 T.Load()
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

-- 3. The real path: test.9027 receives the real test.9028 request. One unverified advisory.
Ready()
assert(Chat('newer Nexus')==0)
assert(Deliver(request28,'TesterB'),'the inbound decoder accepts the request')
status=Nexus.Updates.Status()
assert(status.state=='reported' and status.candidate.display=='1.20.0-beta.1 test.9028' and status.candidate.verified==false and status.candidate.authority=='peer-advisory','a newer test build of the same series is reported: '..status.detail)
local line=assert(LastChat('A newer Nexus test build was reported: 1.20.0-beta.1 test.9028. You have 1.20.0-beta.1 test.9027.'),'the chat notice states both builds')
assert(line:find('Check GitHub Releases before updating',1,true) and line:find('not verified',1,true) and not line:find('available',1,true),'a peer report is never worded as a confirmed publication: '..line)
assert(status.menu=='Newer build reported (unverified): 1.20.0-beta.1 test.9028')
local notice=Nexus.Updates.GetVisibleNotice();assert(notice and notice.verified==false)
-- Repeated peers, repeated traffic, the same target: one notice.
for i=1,12 do assert(Deliver(request28,'Crowd'..i))end
assert(Chat('A newer Nexus test build was reported')==1,'many agreeing peers neither repeat the notice nor add authority')
assert(Nexus.Updates.Status().candidate.verified==false and #Nexus.Updates.PeerObservations()>=13)
-- The stored state holds no peer name, text or link.
local root=NexusDB.updateAdvisory;local stored=root.testBuild
assert(root.authority=='peer-advisory' and root.stableRelease==nil and stored.version=='1.20.0-beta.1' and stored.test==9028)
for k in pairs(root)do assert(k=='authority' or k=='testBuild' or k=='stableRelease','no other stored field: '..k)end
for k,v in pairs(stored)do assert(k=='version' or k=='test' or k=='observedAt','no other stored field: '..k);assert(type(v)~='string' or not v:find('TesterB',1,true))end
assert(NexusDB.updateNotice==nil,'a peer report never becomes release authority')
Nexus.Panel.ShowUpdateStatus()
assert(popup.url=='https://github.com/Viscerals/Better-Nexus/releases' and popup.text:find('not verified',1,true) and popup.text:find('test.9028',1,true),'popup: both builds, provenance, local link')
assert(#H.actions==0,'opening the notice is read-only')
print('PASS same-series test.9027 -> test.9028 advisory through producer, decoder, observer, chat, menu and popup')

-- 4. Dismissal and reload. Seen in the popup: no repeat in a later session. A newer target is announced once.
local db=NexusDB
Boot(PUBLIC27,db);Ready()
assert(Nexus.Updates.Status().state=='reported' and Chat('A newer Nexus test build was reported')==0,'after reload the status persists and a seen target is not announced again')
assert(Deliver(request28,'TesterB') and Chat('A newer Nexus test build was reported')==0)
assert(Deliver(request28,'TesterC','1.20.0-beta.1+test.9030') and Chat('test.9030')==1,'a newer target is announced once')
db=NexusDB;Boot(PUBLIC27,db)
-- Local initialization is enough. The Community catalog is still preparing when the reminder appears.
T.Until(H,function()return Chat('test.9030')>0 or Nexus.StartupStatus().state=='ready' end)
assert(Chat('test.9030')==1 and Nexus.StartupStatus().state~='ready','not seen in the popup: one reminder in the new session, shown while shared data still prepares')
Ready();assert(Deliver(request28,'TesterC','1.20.0-beta.1+test.9030') and Chat('test.9030')==1,'and not more than one')
db=NexusDB;assert(db.updateAdvisory.testBuild.test==9030)
Boot({label='test.9030-0123abc',channel='public-test'},db)
assert(Nexus.Updates.Status().state=='unknown' and NexusDB.updateAdvisory.testBuild==nil,'after the manual update the advisory is gone: no self-update prompt')
print('PASS dismissal, reload, bounded repeats, no self-update prompt')

-- 5. Numeric order, same/older, commit suffix, other build metadata.
local function Reported(installed,version)
 Boot(installed);Ready()
 assert(Deliver(request28,'Numeric',version),'decoder accepts '..version)
 local s=Nexus.Updates.Status();return s.state=='reported' and s.candidate.display or nil,s
end
assert(Reported({label='test.9-abcdef0',channel='public-test'},'1.20.0-beta.1+test.10')=='1.20.0-beta.1 test.10','test.9 -> test.10 is numeric, not lexical')
assert(Reported({label='test.10-abcdef0',channel='public-test'},'1.20.0-beta.1+test.9')==nil,'test.10 is not told to go to test.9')
assert(Reported({label='test.9999-abcdef0',channel='public-test'},'1.20.0-beta.1+test.10000')=='1.20.0-beta.1 test.10000','test.9999 -> test.10000')
assert(Reported(PUBLIC27,'1.20.0-beta.1+test.9027')==nil,'same test: suppressed')
assert(Reported(PUBLIC27,'1.20.0-beta.1+test.9026')==nil,'older test: suppressed')
assert(Reported(PUBLIC27,'1.20.0-beta.1')==nil,'a peer without a test number (test.9027 itself, internal, source) reports nothing')
assert(Reported(PUBLIC27,'1.20.0-beta.1+ffffff0')==nil and Reported(PUBLIC27,'1.20.0-beta.1+test.9028.ffffff0')==nil and Reported(PUBLIC27,'1.20.0-beta.1+zzz.99999')==nil,'a commit or other build metadata never orders builds')
assert(Reported(PUBLIC27,'1.20.0-beta.1+test.09999')==nil,'a padded number is not a test number')
print('PASS numeric boundaries, same/older suppression, no commit-suffix precedence')

-- 6. Release series, stable successor, no downgrade, preferences.
assert(Reported(PUBLIC27,'1.20.0-beta.2+test.1')=='1.20.0-beta.2 test.1','a newer release series wins even with a lower test number')
assert(Reported(PUBLIC27,'1.20.0')=='1.20.0','the stable successor of the beta line is reported')
assert(Reported(PUBLIC27,'1.19.5')==nil and Reported(PUBLIC27,'1.19.9')==nil,'the old stable line is never an upgrade from a newer beta')
local _,s=Reported(PUBLIC27,'1.20.0');assert(LastChat('A newer Nexus release was reported: 1.20.0.'),'stable wording')
Boot(PUBLIC27);Ready();Nexus.Updates.SetPreference('stable')
assert(Deliver(request28,'P1') and Nexus.Updates.Status().state=='unknown' and Chat('reported')==0,'stable-only: no test build is suggested')
assert(Deliver(request28,'P2','1.20.0') and Nexus.Updates.Status().candidate.display=='1.20.0','stable-only still learns the stable successor')
Boot({version='1.19.5',channel='stable'});Ready()
assert(Nexus.Updates.Preference()=='stable' and Nexus.ReleaseIdentity().channel=='stable')
assert(Deliver(request28,'P3') and Nexus.Updates.Status().state=='unknown','a stable installation is not pushed into a beta by default')
Nexus.Updates.SetPreference('test')
assert(Nexus.Updates.Status().state=='reported' and Nexus.Updates.Status().candidate.display=='1.20.0-beta.1 test.9028','the explicit test-inclusive preference applies to the stored report')
Boot(PUBLIC27);Ready();Nexus.Updates.SetEnabled(false)
assert(Deliver(request28,'P4') and Chat('reported')==0 and Nexus.Updates.GetVisibleNotice()==nil,'notices disabled: no chat, no notice')
s=Nexus.Updates.Status();assert(s.state=='disabled' and s.url=='https://github.com/Viscerals/Better-Nexus/releases' and s.installed=='1.20.0-beta.1 test.9027','opt-out keeps the installed label and the manual link')
-- Review F2: older published lines state a higher SemVer prerelease in the same field. They are not upgrades.
for _,old in ipairs({'1.20.0-beta.3.community-off','1.20.0-beta.2.community-off','1.20.0-beta.2','1.21.0-beta.1','1.20.0-rc.1'})do
 assert(Reported(PUBLIC27,old)==nil,'a prerelease without a public test number is never reported: '..old)
end
-- Review F4: a development checkout or internal package with a raised version reports nothing.
for _,raised in ipairs({'1.20.0-beta.2+dev','1.21.0+dev','1.21.0+internal','2.0.0-beta.1+internal','1.21.0+test.5'})do
 assert(Reported(PUBLIC27,raised)==nil,'a marked development or internal version is never reported: '..raised)
end
assert(Reported(PUBLIC27,'1.20.0-rc.1+test.3')=='1.20.0-rc.1 test.3','a later fixed-form series with a public test number is reported')
print('PASS release series, stable successor, no downgrade, stable-only / test-inclusive / opt-out')

-- 7. Development source and internal packages: useful label, nothing claimed, nothing placed in a series.
local shown,st=Reported(nil,'1.20.0-beta.1+test.9028')
assert(shown==nil and st.state=='unknown' and st.channel=='development' and st.installed=='1.20.0-beta.1','a source checkout has no test number to compare; status unknown with a useful label')
shown,st=Reported({label='test.9027-3f1cd20',channel='internal'},'1.20.0-beta.1+test.9028')
assert(shown=='1.20.0-beta.1 test.9028' and st.channelLabel=='internal test package','an internal package still learns about a public test build')
print('PASS development and internal identities')

-- 8. Hostile and malformed input: refused by the decoder or ignored; never text, link or authority.
Boot(PUBLIC27);Ready()
local rejected=0
for _,bad in ipairs({'1.20.0-beta.1+test.9028 http://x.example','http://evil.example/Nexus.zip','1.20.0-beta.1+test.9028|cffff0000','1.20.0-beta.1+test.99999999999999999999','9'..string.rep('9',40),'1.20.0-beta.1+test.9028+x','1.20.0-beta.1+test..9028',''})do
 if not Deliver(request28,'Hostile',bad)then rejected=rejected+1 end
end
assert(Nexus.Updates.Status().state=='unknown' and Chat('reported')==0,'hostile or oversized versions produce no advisory ('..rejected..' refused by the decoder)')
-- Review F1: free-form prerelease text is valid SemVer and passes the decoder. It is never shown or stored.
for _,text in ipairs({'9.9.9-www.evil.example.zip','9.9.9-get-it-at.evil-nexus.com','9.9.9-beta.1.evil','9.9.9-BETA.1+test.5','9.9.9-beta.99999+test.5'})do
 assert(Deliver(request28,'Texter',text),'fixture: the decoder accepts '..text)
 assert(Nexus.Updates.Status().state=='unknown' and NexusDB.updateAdvisory==nil,'peer text never becomes an advisory: '..text)
end
for _,l in ipairs(H.chat)do assert(not l:find('evil',1,true),'no peer text in chat')end
assert(Deliver(request28,'Liar','999.0.0'))
s=Nexus.Updates.Status()
assert(s.state=='reported' and s.candidate.verified==false and s.menu:find('unverified',1,true) and NexusDB.updateNotice==nil,'an arbitrary high peer version is only an unverified report')
assert(s.url=='https://github.com/Viscerals/Better-Nexus/releases','the link is the local one')
Nexus.Release.releasesUrl='http://evil.example/x';assert(Nexus.Updates.ReleaseUrl()=='https://github.com/Viscerals/Better-Nexus/releases','a malformed local link falls back to the fixed page')
-- A false report from an earlier session does not hide what peers state in this session.
db=NexusDB;Boot(PUBLIC27,db);Ready()
assert(Nexus.Updates.Status().candidate.display:find('999.0.0',1,true))
assert(Deliver(request28,'Honest') and Nexus.Updates.Status().candidate.display=='1.20.0-beta.1 test.9028','this session\'s report replaces the kept one')
print('PASS hostile input, no peer link, no authority from a high number')

-- 9. Trusted bundled metadata keeps its own wording and wins over an equal or older report.
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.20.0-beta.1+test.9029'});Ready()
s=Nexus.Updates.Status()
assert(s.state=='available' and s.candidate.verified==true and s.menu=='Update available: 1.20.0-beta.1 test.9029','bundled metadata is compared against the installed build, prerelease included: '..s.detail)
assert(LastChat('New Nexus test build available: 1.20.0-beta.1 test.9029. You have 1.20.0-beta.1 test.9027.'))
assert(Deliver(request28,'T1') and Nexus.Updates.Status().candidate.verified==true,'an older report does not replace trusted evidence')
assert(Deliver(request28,'T2','1.20.0-beta.1+test.9031') and Nexus.Updates.Status().candidate.verified==false and Nexus.Updates.Status().candidate.display=='1.20.0-beta.1 test.9031','a strictly newer report is shown, still unverified')
Boot({label='test.9027-3f1cd20',channel='public-test',available='1.19.5'})
assert(Nexus.Updates.Status().state=='unknown','bundled old stable is not an upgrade')
-- A notice stored by an older client with peer authority stays quarantined.
Boot(PUBLIC27,(function()local d=T.Profile(3,0);d.updateNotice={version='9.9.9',authority='peer'};return d end)())
assert(Nexus.Updates.Status().state=='unknown' and NexusDB.updateNotice==nil and NexusDB.updateNoticeQuarantine.version=='9.9.9','a peer-authority notice kept by an older client is quarantined, not shown')
print('PASS trusted bundled path and legacy quarantine')

-- 10. The real HUD menu: the update entry is never disabled, states the provenance, opens the local link;
-- the channel entry switches the preference. The HUD button marks a visible notice.
Boot(PUBLIC27);Ready()
local items;EasyMenu=function(list)items=list end
local function Entry(pattern)for _,item in ipairs(items or {})do if type(item.text)=='string' and item.text:find(pattern,1,true)then return item end end end
local button=assert(NexusPanel and NexusPanel._menuBtn,'the real HUD menu button')
button:Click();local entry=assert(Entry('Update status unknown - open Releases page'),'menu entry without any report')
assert(not entry.disabled,'the manual link is available with no report');popup=nil;entry.func()
assert(popup and popup.url=='https://github.com/Viscerals/Better-Nexus/releases' and popup.text:find('Installed: 1.20.0-beta.1 test.9027',1,true))
assert(Deliver(request28,'MenuPeer'));H.Advance(1,.05)
button:Click();entry=assert(Entry('Newer build reported (unverified): 1.20.0-beta.1 test.9028'),'menu entry states an unverified report')
assert(button:GetText()=='!','the HUD button marks the visible notice')
local channel=assert(Entry('Update notices: stable + test builds'));channel.func()
assert(Nexus.Updates.Preference()=='stable');button:Click()
assert(Entry('Update status unknown') and Entry('Update notices: stable only'),'stable-only hides the test report in the menu');H.Advance(1,.05)
assert(button:GetText()~='!','and on the HUD button')
Entry('Update notices: stable only').func();button:Click()
assert(Entry('Newer build reported (unverified): 1.20.0-beta.1 test.9028'),'the kept report returns with the test-inclusive preference')
local toggle=assert(Entry('Disable Update Notices'));toggle.func();button:Click()
assert(Entry('Update notices off - open Releases page') and not Entry('Update notices off').disabled,'opt-out keeps the manual link in the menu')
print('PASS HUD menu entries, preference switch, opt-out, manual link')

-- 11. Review F3 / F11: a peer that raises its number in every request cannot fill the chat or the saved data;
-- an earlier dismissal survives a later one.
Boot(PUBLIC27);Ready()
for i=1,200 do assert(Deliver(request28,'Climber','1.20.0-beta.1+test.'..(9100+i)))end
assert(Chat('A newer Nexus test build was reported')==3,'at most three update chat lines per session: '..Chat('A newer Nexus test build was reported'))
assert(NexusDB.updateAdvisory.testBuild.test==9108,'at most eight stored advisory changes per session: '..tostring(NexusDB.updateAdvisory.testBuild.test))
Nexus.Panel.ShowUpdateStatus()
db=NexusDB;Boot(PUBLIC27,db);Ready()
assert(Deliver(request28,'Climber2','1.20.0-beta.1+test.9300'));Nexus.Panel.ShowUpdateStatus()
assert(#NexusDB.updateDismissed==2,'both seen targets are remembered')
db=NexusDB;db.updateAdvisory.testBuild.test=9108
Boot(PUBLIC27,db);T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
assert(Chat('test.9108')==0,'a target dismissed earlier is not announced again after a later dismissal')
Boot({label='test.007-abcdef0',channel='public-test'})
assert(Nexus.ReleaseIdentity().test==nil and Nexus.ReleaseIdentity().channel=='internal','a padded label states no test number, as in the tools')
print('PASS bounded notices and state changes, dismissal set, padded label')

-- 12. Old peers. The published test.9027 decoder rule is the same ValidVersion: prove it accepts the new announcement.
Boot(PUBLIC27);Ready()
assert(Nexus.SyncInternals and Deliver(request28,'OldPeerCheck'),'request with +test metadata is a valid request')
assert(Nexus.Sync.Stats().malformedRejected==0)
assert(#H.actions==0,'no gameplay action in any case')
print('PASS update notices')
