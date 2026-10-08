-- Positive controls for the saved Sync mode. Only an accepted format 3-5
-- carries an Off/Manual choice; format 5 with "automatic" or no mode, and a
-- format-2 or unversioned profile that happens to store syncMode "off", keep
-- today's automatic behavior. The explicit probe whisper works under Manual.
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

-- Manual: the explicit /nexus probe whisper is permitted (the user asked for it).
local M,O=P.Boot({'ProbePeer','OtherPeer'},{5,5},function(i,db)
 if i==1 then db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode='manual' end
end)
check(#M.H.sent==0,'Manual: idle before the probe')
M.e.SlashCmdList.NEXUS('probe OtherPeer-Ebonhold')
local last=M.H.sent[#M.H.sent]
check(#M.H.sent==1 and last.kind=='WHISPER' and tostring(last.target):lower()=='otherpeer-ebonhold','Manual: the explicit probe whisper is sent once')
print('PASS sync_saved_mode_controls: automatic/absent format 5, format 2 and unversioned unchanged; probe allowed under Manual checks='..checks)
