-- G-01 (core/SyncSession.lua SendStatusTo): the diagnostic probe whisper is
-- disabled. For every target, ASCII case, realm, saved mode and connection it
-- answers a bare false, fabricates no peer reason and submits nothing on any
-- route (native chat/addon sends, Transport batches, Wire packet attempts);
-- the slash command prints only an actual provided reason, so it is silent.
-- The existing offline whisper guard (SyncWire.IsWhisperTargetBlocked) keeps
-- its own case-folded, realm-preserving scope. The inert probe never calls it,
-- so that scope is read through the guard itself, not through a probe result.
local F=dofile('tests/prototype/offline_peer_dps_support.lua')
local checks,failed=0,{}
local function check(value,message)
 checks=checks+1;print((value and 'PASS ' or 'FAIL ')..message)
 if not value then failed[#failed+1]=message end
end
local function Cursor(f)
 return {sent=#f.H.sent,chat=#f.H.chat,batches=#f.batches,attempts=#f.attempts}
end
local function Quiet(f,c,label)
 local added={}
 for i=c.sent+1,#f.H.sent do
  local packet=f.H.sent[i]
  added[#added+1]=tostring(packet.route)..'/'..tostring(packet.kind)..' '..tostring(packet.text)
 end
 check(#added==0,label..': zero native sends on every route: '..table.concat(added,' ; '))
 check(#f.batches==c.batches and #f.attempts==c.attempts,label..': no Transport batch or Wire packet attempt')
end
-- open: the existing whisper guard does not block this target.
local function Guard(f,target,open,label)
 check(f.W.IsWhisperTargetBlocked(target)==not open,
  label..': existing peer guard scope is '..(open and 'open' or 'blocked'))
end
local function Direct(f,target,open,label)
 local c=Cursor(f)
 local result={f.S.SendStatusTo(target)}
 Quiet(f,c,label)
 check(result[1]==false and result[2]==nil and result[3]==nil,
  label..': inert false without a fabricated reason: '..tostring(result[2]))
 check(#f.H.chat==c.chat,label..': the direct call prints nothing')
 Guard(f,target,open,label)
end
local function Command(f,target,open,label)
 local c=Cursor(f)
 SlashCmdList.NEXUS('probe '..target)
 Quiet(f,c,label)
 local printed={}
 for i=c.chat+1,#f.H.chat do printed[#printed+1]=f.H.chat[i] end
 check(#printed==0,label..': the inert command is silent, no manufactured refusal: '..table.concat(printed,' | '))
 -- The slash parser lowercases the target it would have passed on.
 Guard(f,target:lower(),open,label)
end

for _,mode in ipairs({'automatic','manual'})do
 local f=F.Boot(false);f.Negotiate('Blocked-RealmA');f.Block('Blocked-RealmA')
 NexusDB.settingsVersion=5;NexusDB.settings.syncMode=mode
 f.W.Housekeep(true)
 Direct(f,'Blocked-RealmA',false,mode..' exact target')
 Direct(f,'blocked-realma',false,mode..' full-name ASCII case')
 Command(f,'Blocked-RealmA',false,mode..' mixed-case slash target')
 Direct(f,'Blocked-RealmB',true,mode..' different qualified realm')
 Direct(f,'Blocked',true,mode..' bare name is a separate scope')
 Command(f,'OtherPeer-RealmA',true,mode..' unrelated slash target')
 check(f.W.IsPeerBlocked('Blocked-RealmA'),mode..': probe cannot clear cooldown')
 f.H.now=f.H.now+60;f.W.Housekeep(true)
 Direct(f,'blocked-realma',false,mode..' deadline without new observation')
 local c=Cursor(f)
 for _=1,30 do f.Pump()end
 Quiet(f,c,mode..': no deferred status retry')
 check(#f.H.actions==0,mode..': no gameplay action')
end

-- Sync-channel membership is separate from the whisper guard: it stays open
-- for unrelated/previously online targets and blocks a known offline peer.
-- The disconnected probe is inert for all of them.
for _,mode in ipairs({'automatic','manual'})do
 local f=F.Boot(false);f.Negotiate('Blocked-RealmA');f.Block('Blocked-RealmA')
 f.Negotiate('Online-RealmA')
 NexusDB.settingsVersion=5;NexusDB.settings.syncMode=mode
 GetChannelList=function()return end
 GetChannelName=function()return 0 end
 f.W.Housekeep(true)
 assert(f.W.IsPeerBlocked('Unrelated'),'fixture: addon wire is disconnected')
 Direct(f,'Unrelated',true,mode..' disconnected unrelated target')
 Direct(f,'Online-RealmA',true,mode..' disconnected previously online target')
 Command(f,'OtherPeer-RealmA',true,mode..' disconnected unrelated slash target')
 Direct(f,'blocked-realma',false,mode..' disconnected known offline target')
 check(#f.H.actions==0,mode..' disconnected: no gameplay action')
end

do
 local f=F.Boot(false)
 NexusDB.settingsVersion=5;NexusDB.settings.syncMode='off'
 local c=Cursor(f)
 local accepted,why=f.S.SendStatusTo('OtherPeer')
 check(accepted==false and type(why)=='string' and why:find('Off',1,true),'Off: original mode refusal preserved')
 SlashCmdList.NEXUS('probe OtherPeer')
 Quiet(f,c,'Off: direct and command')
 local printed=table.concat(f.H.chat,'\n',c.chat+1)
 check(type(why)=='string' and printed:find(why,1,true)~=nil,'Off: the command prints the actual saved-mode reason: '..printed)
end

do
 local f=F.Boot(false)
 Direct(f,'StatusOnly',true,'inert status-only probe')
 local notice=string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,'StatusOnly')
 check(not f.W.NoteOfflineNotice(notice) and not f.W.IsPeerBlocked('StatusOnly'),'an offline notice after the inert probe adds no addon attribution')
end

assert(#failed==0,table.concat(failed,'; '))
print('PASS offline_peer_status_probe checks='..checks)
