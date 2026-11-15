-- Positive controls for the saved Sync mode. Only an accepted format 3-5
-- carries an Off/Manual choice; format 5 with "automatic" or no mode, and a
-- format-2 or unversioned profile that happens to store syncMode "off", keep
-- today's automatic behavior. Under Manual the disabled diagnostic probe
-- (G-01) submits nothing on any route, while an explicit Sync Now still sends.
-- Two real runtimes; the saved values are never rewritten.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Run(label,configure,expectMode)
 local A,B=P.Boot({'ControlPeer','OtherPeer'},{5,5},function(i,db)if i==1 then configure(db)end end)
 local before=A.e.NexusDB.settings.syncMode
 check(A.e.Nexus.SyncModePolicy.Mode()==expectMode,label..': effective mode '..expectMode)
 P.Advance(40)
 local requested=false
 for _,t in ipairs(P.trace)do if t.from==A.name and t.code=='WLRQ' then requested=true end end
 check(requested,label..': the automatic login Sync is sent')
 local sent=#A.H.sent
 B.e.Nexus.Sync.RequestSync()
 P.Until(function()return #A.H.sent>sent end,4000)
 check(#A.H.sent>sent,label..': the other peer is answered')
 check(A.e.NexusDB.settings.syncMode==before,label..': the saved mode value is unchanged')
 return A,B
end
Run('format 5, automatic',function(db)db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode='automatic' end,'automatic')
Run('format 5, no mode',function(db)db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode=nil end,'automatic')
local A=Run('format 2 storing off',function(db)db.settingsVersion=2;db.settings.syncMode='off' end,'automatic')
check(A.e.NexusDB.settingsVersion==2,'format 2: marker unchanged')
A=Run('unversioned storing manual',function(db)db.settingsVersion=nil;db.settings.syncMode='manual' end,'automatic')
check(A.e.NexusDB.settingsVersion==2,'unversioned: stamped 2 as before')

-- Manual, G-01: the diagnostic probe whisper is disabled. No peer can answer
-- it and its token carried local Wishlist facts, so the explicit /nexus probe
-- submits zero captured bytes on any route and queues nothing under Manual
-- too. Counted directly around the command, before any bridge step, so no
-- other traffic is attributed to it. Manual's own user-granted Sync Now is not
-- disabled (sync_saved_mode_manual and sync_saved_mode_share_retry cover
-- Sync Now, Share and their follow-ups).
local M,O=P.Boot({'ProbePeer','OtherPeer'},{5,5},function(i,db)
 if i==1 then db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode='manual' end
end)
check(M.e.Nexus.SyncModePolicy.Mode()=='manual','Manual: the accepted format-5 Manual choice is honored')
check(#M.H.sent==0,'Manual: idle before the probe')
local start,queued=#M.H.sent,M.e.Nexus.Sync.Stats().admittedPackets or 0
M.e.SlashCmdList.NEXUS('probe OtherPeer-Ebonhold')
local added={}
for i=start+1,#M.H.sent do
 local packet=M.H.sent[i]
 added[#added+1]=tostring(packet.route)..'/'..tostring(packet.kind)..' '..tostring(packet.text)
end
check(#added==0,'Manual: the explicit probe submits zero bytes on any route: '..table.concat(added,' ; '))
check((M.e.Nexus.Sync.Stats().admittedPackets or 0)==queued,'Manual: the probe queues nothing for later submission')
local okProbe,whyProbe=M.e.Nexus.Sync.SendStatusTo('OtherPeer-Ebonhold')
check(okProbe==false and whyProbe==nil and #M.H.sent==start,'Manual: the probe facade is inert (false, no refusal reason) and sends nothing')
-- Positive control: the same counter sees this peer's own traffic, and an
-- explicit Sync Now still holds a manual grant and sends under Manual.
M.e.SlashCmdList.NEXUS('sync')
check(M.e.Nexus.SyncModePolicy.ActiveManualGrant()~=nil,'Manual: an explicit Sync Now still holds a manual grant')
P.Until(function()return #M.H.sent>start end,4000)
check(#M.H.sent>start,'Manual: the explicit Sync Now still sends')
check(M.e.NexusDB.settings.syncMode=='manual' and M.e.NexusDB.settingsVersion==5 and M.e.Nexus.SyncModePolicy.Mode()=='manual','Manual: the saved mode, marker and effective mode are unchanged')
print('PASS sync_saved_mode_controls: automatic/absent format 5, format 2 and unversioned unchanged; probe inert and Sync Now granted under Manual checks='..checks)
