-- Group 7 (S4-02): transport throttle feedback delivered as UI_ERROR_MESSAGE.
-- Static FrameXML (patch-enUS-3 ChatFrame.lua 2674-2691, read as data, never
-- executed): ChatFrame_MessageEventHandler runs message-event filters only
-- inside its CHAT_MSG branch. core/SyncTransport.lua InstallFilters
-- registers its notice handler as a chat filter for CHAT_MSG_SYSTEM and for
-- UI_ERROR_MESSAGE; a UI error is an event delivered to registered frames,
-- never through that branch, so the UI_ERROR registration cannot fire.
-- EXPECT (fails at 8c): a supported throttle UI error (GlobalStrings
-- ERR_CHAT_THROTTLED) delivered as the UI_ERROR_MESSAGE event right after an
-- actual send attempt pauses the actual transport (leaderboard sync status
-- "throttled") and requeues the attempted packet once.
-- GUARD (holds at 8c): the CHAT_MSG_SYSTEM filter still pauses and requeues
-- once (positive control of this fixture); while paused nothing is sent;
-- repeated matching errors do not requeue twice; an unrelated UI error, a
-- channel THROTTLED notice and a matching UI error outside the four-second
-- attribution window pause nothing and requeue nothing.
-- Limits: the real server delivery type and packet loss are unknown; this
-- does not claim the offline-peer complaint was caused or fixed. The UI error
-- uses the 3.3.5 event form (arg1 = message; external-335a knowledge).
-- SETUP: one real runtime per scenario (startup_support), synthetic
-- channel; the FrameXML filter table is recorded at its global entry point.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_feedback_event_wiring')
local printable=B.printable
local THROTTLED='The number of messages that can be sent is limited, please wait to send another message.'
local UNRELATED="You can't do that yet"

local H,S,filters
local function Boot(label)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local T=dofile('tests/prototype/startup_support.lua')
 H=dofile('tests/prototype/harness.lua')
 filters={}
 ChatFrame_AddMessageEventFilter=function(event,fn)
  filters[event]=filters[event] or {}
  table.insert(filters[event],fn)
 end
 NexusDB=T.Profile(2,0)
 H.perks.serverBuildSlots={[102]={name='NEXUS-TEST-Feedback',verified=false,echoes={{spellId=200001,quality=1,stacks=3}}}}
 T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function()
  return Nexus.StartupStatus().state=='ready' and Nexus.BuildCatalog.ManualPreparationStatus().ready
 end)
 S=Nexus.Sync
 C.setup(filters.CHAT_MSG_SYSTEM~=nil,label..': the actual transport installed its CHAT_MSG_SYSTEM filter')
end
-- The static FrameXML rule: filters run only for CHAT_MSG events.
local function ChatEvent(event,text,...)
 if event:sub(1,8)~='CHAT_MSG' then return false end
 local suppressed=false
 for _,fn in ipairs(filters[event] or {}) do
  local ok,filtered=pcall(fn,{},event,text,...)
  if ok and filtered then suppressed=true end
 end
 return suppressed
end
-- A UI error reaches every frame registered for the event (3.3.5: arg1).
local function UIError(text) H.Fire('UI_ERROR_MESSAGE',text) end
local function Attempts() return tonumber(S.Stats().sendAttempts) or 0 end
local function Requeued() return tonumber(S.Stats().requeued) or 0 end
local function Throttled() return (S.GetLeaderboardSyncStatus())=='throttled' end
-- An actual send attempt; returns right after the step that made it.
local function Attempt(label)
 local before=Attempts()
 S.RequestSync()
 local got=B.Until(H,function() return Attempts()>before end,1200)
 C.setup(got~=nil,label..': the actual transport made a send attempt')
 C.setup(not Throttled(),label..': the transport was not already paused')
 return got~=nil
end

C.scenario('U throttle UI error right after an attempt',function()
 Boot('U')
 if not Attempt('U') then return end
 local requeued=Requeued()
 UIError(THROTTLED)
 local paused,once=Throttled(),Requeued()
 print('OBSERVED','U paused='..printable(paused),'requeued delta='..(once-requeued))
 C.expect(paused,'U: the supported throttle UI error pauses the actual transport')
 C.expect(once==requeued+1,'U: and requeues the attempted packet once',once-requeued)
 UIError(THROTTLED)
 C.guard(Requeued()<=requeued+1,'U: a repeated matching error does not requeue twice',Requeued()-requeued)
 local attempts=Attempts()
 H.Advance(6,.05)
 C.guard(not paused or Attempts()==attempts,'U: while paused nothing is sent',Attempts()-attempts)
end)

C.scenario('K CHAT_MSG_SYSTEM positive control',function()
 Boot('K')
 if not Attempt('K') then return end
 local requeued=Requeued()
 local suppressed=ChatEvent('CHAT_MSG_SYSTEM',THROTTLED)
 C.guard(Throttled() and Requeued()==requeued+1,'K: the filtered system notice pauses and requeues once',Requeued()-requeued)
 C.guard(suppressed==true,'K: the waiting notice is quieted by the filter')
end)

C.scenario('X unrelated, channel and unattributed notices',function()
 Boot('X')
 if not Attempt('X') then return end
 local requeued=Requeued()
 UIError(UNRELATED)
 C.guard(not Throttled() and Requeued()==requeued,'X: an unrelated UI error pauses and requeues nothing')
 ChatEvent('CHAT_MSG_CHANNEL_NOTICE_USER','THROTTLED','',nil,'1. synthetic',nil,nil,nil,nil,'synthetic')
 C.guard(not Throttled() and Requeued()==requeued,'X: a channel THROTTLED notice pauses and requeues nothing')
 -- A quiet period longer than the four-second attribution window.
 local last,count=H.now,Attempts()
 local quiet=B.Until(H,function()
  if Attempts()~=count then count=Attempts();last=H.now end
  return H.now-last>4.5
 end,1200)
 C.setup(quiet~=nil,'X: a quiet period beyond the attribution window was reached')
 requeued=Requeued()
 UIError(THROTTLED)
 C.guard(not Throttled() and Requeued()==requeued,
  'X: a matching UI error with no attempt in the last four seconds pauses and requeues nothing')
end)

C.guard(#H.actions==0,'no game action',#H.actions)
C.finish('(UI-error throttle feedback reaches the transport with attribution; unrelated notices ignored)')
