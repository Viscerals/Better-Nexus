-- Ordinary Auto across a loading screen inside one UI session. The selection
-- stays ON; actions are held from PLAYER_LEAVING_WORLD until the entry that
-- closes it has settled with the adapter ready. An entry with no observed leave
-- (login, /reload, or anything this session cannot classify) and a logout turn
-- Auto OFF. An action sent before the leave and unresolved at it stays
-- unresolved and holds automation until player input (scenarios 10-12).
-- Real runtime, adapter, policy and panel; synthetic game surface.
local WANT={{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}}
local function Boot()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={[1]={name='Active saved build',verified=true,
  echoes={{spellId=200001,quality=1,stacks=2}}}}
 -- Every board-action attempt, accepted or refused, so a resend cannot hide
 -- behind the fake service refusing a second call while one is pending.
 H.attempts=0
 for _,name in ipairs({'SelectPerk','BanishPerk','FreezePerk','RequestReroll'})do
  local call=H.service[name];H.service[name]=function(...)H.attempts=H.attempts+1;return call(...)end
 end
 -- H.Boot's own sequence, with the real runtime instance captured as Main
 -- creates it (no product seam is added for the test).
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#') then
   local chunk,err=loadfile((line:gsub('\\','/')));assert(chunk,err);chunk('Nexus',{})
  end
 end
 local factory=Nexus.MainInternals.AutomationRuntime;local new=factory.New
 factory.New=function(...)H.runtime=new(...);return H.runtime end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(20,.05)
 assert(H.runtime,'runtime instance captured')
 assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Assigned plan',{{spellId=200001,quality=1,stacks=2}}),'assign the plan')
 -- Board actions the service accepted (the policy picks which one).
 local BOARD={take=true,freeze=true,banish=true,reroll=true}
 function H.Takes()local n=0;for _,a in ipairs(H.actions)do if BOARD[a[1]] then n=n+1 end end;return n end
 function H.Auto()return Nexus.RecomputeStats().autoEnabled end
 function H.Allowed()return H.runtime.AutoAllowed()end
 function H.Offer(cards)H.Board(cards or WANT);H.Notify()end
 return H
end
local function Label()
 local text=NexusPanel._autoBtn:GetText() or ''
 return (text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))
end

-- 1. Control: this rig does act on the board when Auto is ON and nothing
-- holds it, so every "no action" below is a real hold, not a dead rig.
do
 local H=Boot();H.Offer();H.Advance(.5)
 assert(H.Takes()==0 and not H.Auto(),'starts OFF: no action')
 SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.Auto() and H.Takes()==1,'control: Auto ON acts on the board, actions='..H.Takes())
end

-- 2. A loading screen keeps the selection and holds actions until the entry
-- has settled; the first action comes only after the settle, exactly once.
do
 local H=Boot();SlashCmdList.NEXUS('auto');H.Advance(1)
 assert(H.Auto() and H.Takes()==0,'Auto ON with no board: nothing to act on')
 H.Fire('PLAYER_LEAVING_WORLD')
 local ok,why=H.Allowed()
 assert(H.Auto(),'leaving world keeps the Auto selection')
 assert(not ok and tostring(why):find('loading screen',1,true),'leaving world holds actions: '..tostring(why))
 H.Offer();H.Advance(5)
 assert(H.Takes()==0,'no action while the loading screen is open, however long')
 H.Fire('PLAYER_ENTERING_WORLD')
 ok,why=H.Allowed()
 assert(H.Auto() and not ok and tostring(why):find('settling',1,true),'the closing entry settles first: '..tostring(why))
 H.Advance(2.5)
 assert(H.Takes()==0,'no action inside the settle window')
 -- The settle end schedules its own step: the action follows within one
 -- intent beat (0.4 s) and poll, not at a later fallback recompute.
 H.Advance(1.2)
 assert(H.Auto() and H.Allowed(),'after the settle the selection acts again')
 assert(H.Takes()==1,'one action after the settle, actions='..H.Takes())
 H.Advance(3);assert(H.Takes()==1 and H.attempts==1,'and only once')
end

-- 3. A prepared (unsubmitted) action is dropped at the leave, recorded as such,
-- and not sent during the loading screen or the settle.
do
 local H=Boot();H.Offer();H.Advance(.5);SlashCmdList.NEXUS('auto');H.Advance(.25)
 local life=Nexus.RecomputeStats().lastActionLifecycle
 assert(H.Takes()==0 and life.state=='prepared','an action is prepared, not yet sent: '..tostring(life.state))
 H.Fire('PLAYER_LEAVING_WORLD')
 life=Nexus.RecomputeStats().lastActionLifecycle
 assert(life.state=='superseded' and life.reason=='world_transition','prepared action dropped at the leave: '..tostring(life.state)..'/'..tostring(life.reason))
 H.Advance(3);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(2.5)
 assert(H.Takes()==0 and H.attempts==0,'the dropped action is not sent before the settle ends')
end

-- 4. A submitted action whose result has not arrived is not resent after the
-- transition: it stays unresolved and holds the board (scenario 10).
do
 local H=Boot();H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.Takes()==1 and H.attempts==1,'one board action submitted')
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD')
 -- Well past the settle, the confirmation timeout and several fallback
 -- recomputes: the unanswered action keeps holding the same board.
 for _=1,6 do
  H.Advance(5)
  assert(H.Auto() and H.attempts==1,'no resend or new action on the unresolved board, attempts='..H.attempts..' at '..H.now)
 end
end

-- 5. An entry with no observed leave cannot be classified and turns Auto OFF;
-- so does a logout. Neither is later restored.
do
 local H=Boot();Nexus.Panel.Show();SlashCmdList.NEXUS('auto');H.Advance(.5)
 assert(Label()=='Auto: ON','button shows ON: '..Label())
 H.Fire('PLAYER_ENTERING_WORLD')
 assert(not H.Auto(),'entry without an observed leave revokes Auto')
 assert(Label()=='Auto: OFF','button shows OFF after the revoke: '..Label())
 H.Offer();H.Advance(5);assert(H.Takes()==0,'revoked: no action')
 SlashCmdList.NEXUS('auto');H.Advance(.2);H.Fire('PLAYER_LEAVING_WORLD');H.Fire('PLAYER_ENTERING_WORLD')
 H.Fire('PLAYER_ENTERING_WORLD')
 assert(not H.Auto(),'a second entry after the closing one is unclassified and revokes')
 SlashCmdList.NEXUS('auto');H.Fire('PLAYER_LOGOUT')
 assert(not H.Auto(),'logout revokes Auto')
end

-- 6. The settle also waits for the adapter's readiness evidence (a real player
-- name after entry); unknown readiness stays held however long it lasts.
do
 local H=Boot();SlashCmdList.NEXUS('auto');H.Advance(.5)
 H.Fire('PLAYER_LEAVING_WORLD');H.Offer()
 local name=UnitName;UnitName=function()return 'Unknown' end
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(10)
 local ok,why=H.Allowed()
 assert(H.Auto() and not ok and tostring(why):find('settling',1,true),'unknown player identity keeps the hold: '..tostring(why))
 assert(H.Takes()==0,'no action while readiness is unknown')
 UnitName=name;H.Advance(6)
 assert(H.Takes()==1,'readiness restored: acts, actions='..H.Takes())
end

-- 7. Turning Auto ON during a loading screen still waits for the closing entry
-- and its settle; turning it OFF there is honoured on entry.
do
 local H=Boot();H.Fire('PLAYER_LEAVING_WORLD');SlashCmdList.NEXUS('auto');H.Offer();H.Advance(3)
 assert(H.Auto() and H.Takes()==0,'ON during the loading screen: held')
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(2);assert(H.Takes()==0,'held inside the settle')
 H.Advance(2);assert(H.Takes()==1,'acts after the settle')
 local J=Boot();SlashCmdList.NEXUS('auto');J.Fire('PLAYER_LEAVING_WORLD');SlashCmdList.NEXUS('auto')
 J.Fire('PLAYER_ENTERING_WORLD');J.Offer();J.Advance(5)
 assert(not J.Auto() and J.Takes()==0,'OFF chosen during the loading screen stays OFF')
end

-- 8. While actions are held with no board, the button shows the selection
-- (ON), and the hold reason is in the status line; one click turns it OFF.
do
 local H=Boot();Nexus.Panel.Show();SlashCmdList.NEXUS('auto');H.Advance(.5)
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(1)
 assert(H.Auto() and Label()=='Auto: ON','held during the loading screen, button ON: '..Label())
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1)
 assert(not H.Allowed() and Label()=='Auto: ON','settling, button still ON: '..Label())
 NexusPanel._autoBtn:Click();H.Advance(.5)
 assert(not H.Auto() and Label()=='Auto: OFF','one click during a hold turns the selection OFF: '..Label())
end

-- 9. Shorter labels for the 72-pixel button: Auto: --, Auto: ON, Auto: OFF.
-- Size and colours are unchanged. This checks strings and the offline frame
-- model only; the rendered text width is not measured (native check).
do
 local H=Boot();Nexus.Panel.Show();H.Advance(.5)
 assert(Label()=='Auto: OFF','OFF label: '..Label())
 local btn=NexusPanel._autoBtn
 assert(btn:GetWidth()==72 and btn:GetHeight()==22,'button size unchanged: '..tostring(btn:GetWidth())..'x'..tostring(btn:GetHeight()))
 assert((btn:GetText() or ''):find('|cffe63c3c',1,true),'OFF colour unchanged')
 NexusPanel._autoBtn:Click();H.Advance(.5)
 assert(H.Auto() and Label()=='Auto: ON','button click turns Auto ON: '..Label())
 assert((btn:GetText() or ''):find('|cff2ee62e',1,true),'ON colour unchanged')
 NexusPanel._autoBtn:Click();H.Advance(.5)
 assert(not H.Auto() and Label()=='Auto: OFF','button click turns Auto OFF: '..Label())
 local src=io.open('ui/Panel.lua'):read('*a')
 assert(src:find('"Auto: --"',1,true),'unknown-state label is Auto: --')
 assert(not src:find('Automation: ',1,true),'the long label is gone')
end

-- 10. Whatever still waited for the server at the leave stays unresolved
-- after the loading screen. A missing, returning or different board, the
-- confirmation timeout and the adapter's dead-latch watchdog are not its
-- result, so nothing dependent is sent. Every variant runs past the watchdog
-- with a board present and the adapter no longer in flight: only this hold is
-- left to stop a dependent action. Auto stays ON and the reason is shown.
-- On the pilot head 443453b every variant but "no update frame" sent a
-- dependent action; that one was already held by the same-board rule and
-- checks only the hold and its reason here. The last two variants have no
-- runtime intent at the leave: one poll before it, the older rule took the
-- board read as the Freeze's result, and only the adapter's latch is live.
local OTHER={{spellId=200001,quality=1},{spellId=200030,quality=0},{spellId=200031,quality=1}}
local function Leave(H)H.Fire('PLAYER_LEAVING_WORLD');H.Board({});H.Notify()end
local VARIANTS={
 {'board cleared in the loading screen',function(H)Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer()end},
 {'no update frame between leave and entry',function(H)Leave(H);H.Fire('PLAYER_ENTERING_WORLD');H.Offer()end},
 {'board cleared after the settle',function(H)H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD')
   H.Advance(5);H.Board({});H.Notify();H.Advance(3);H.Offer()end},
 {'board returns late',function(H)Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(20);H.Offer()end},
 {'loading longer than the watchdog',function(H)Leave(H);H.Advance(15);H.Fire('PLAYER_ENTERING_WORLD');H.Offer()end},
 {'a different board after entry',function(H)Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer(OTHER)end},
 {'already expired at the leave',function(H)H.Advance(12)
   assert(Nexus.RecomputeStats().lastActionLifecycle.state=='expired','precondition: expired, still holding the same board')
   Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer()end},
 {'latch cleared on the same board before the leave',function(H)H.perks.pendingFreezeIndex=nil;H.Advance(1)
   assert(Nexus.RecomputeStats().lastActionLifecycle.state=='uncertain','precondition: uncertain on the same board')
   Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer()end},
 {'board cleared one poll before the leave',function(H)H.Board({});H.Notify();H.Advance(.5)
   assert(Nexus.RecomputeStats().actionLifecycle.confirmed==1 and H.perks.pendingFreezeIndex~=nil,'precondition: the clear was taken as the result; the latch is live')
   H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer()end,true},
 {'a different board one poll before the leave',function(H)H.Offer(OTHER);H.Advance(.5)
   assert(Nexus.RecomputeStats().actionLifecycle.confirmed==1 and H.perks.pendingFreezeIndex~=nil,'precondition: the new board was taken as the result; the latch is live')
   H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer(OTHER)end,true},
}
for _,v in ipairs(VARIANTS) do
 local H=Boot();H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 local l=Nexus.RecomputeStats().lastActionLifecycle
 assert(H.attempts==1 and l.actionType=='freeze' and l.state=='submitted',v[1]..': one Freeze sent, no reply: '..tostring(l.actionType)..'/'..tostring(l.state))
 local sentAt=H.now
 v[2](H)
 local stop=math.max(H.now+10,sentAt+14)
 while H.now<stop do
  H.Advance(2)
  assert(H.attempts==1,v[1]..': nothing dependent is sent, attempts='..H.attempts..' at +'..(H.now-sentAt))
 end
 local ok,why=H.Allowed()
 l=Nexus.RecomputeStats().lastActionLifecycle
 assert(Nexus.GameAdapter.Board() and not Nexus.GameAdapter.InFlight(),v[1]..': reached: a board is present and the adapter holds nothing')
 assert(H.Auto() and not ok and tostring(why):find('no confirmed result for freeze sent before the loading screen',1,true),v[1]..': held, reason shown: '..tostring(why))
 if not v[3] then
  assert(l.state=='uncertain' and l.reason=='world_transition',v[1]..': still unresolved: '..tostring(l.state)..'/'..tostring(l.reason))
  assert(Nexus.RecomputeStats().actionLifecycle.confirmed==0,v[1]..': no confirmation recorded')
 end
end

-- 11. Only new player input ends that hold: Auto off and on again. The earlier
-- action is recorded as uncertain (player_resumed), never as confirmed, and
-- automation continues within one beat and poll.
do
 local H=Boot();H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer();H.Advance(14)
 assert(H.attempts==1 and not H.Allowed() and not Nexus.GameAdapter.InFlight(),'held after the watchdog, before the player acts')
 SlashCmdList.NEXUS('auto');SlashCmdList.NEXUS('auto')
 local l=Nexus.RecomputeStats().lastActionLifecycle
 assert(H.Auto() and l.state=='uncertain' and l.reason=='player_resumed','the player ends the hold; the result stays unknown: '..tostring(l.state)..'/'..tostring(l.reason))
 assert(Nexus.RecomputeStats().actionLifecycle.confirmed==0,'nothing was confirmed')
 H.Advance(1.2)
 assert(H.attempts==2,'automation continues after the player input, attempts='..H.attempts)
end

-- 12. Control: an action whose result arrived before the leave holds nothing.
-- After the settle the next action follows without a click.
do
 local H=Boot();H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.attempts==1,'one Freeze sent')
 local frozen=H.Clone(WANT);frozen[1].isFrozen=true
 H.perks.pendingFreezeIndex=nil;H.Offer(frozen);H.Advance(.3)
 assert(Nexus.RecomputeStats().actionLifecycle.confirmed==1,'the answered Freeze is confirmed by its board change')
 Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer(frozen)
 H.Advance(2.5);assert(H.attempts==1,'held inside the settle')
 -- Bounded: the settle ends at +3 s; the next action is prepared there and
 -- sent after its 0.4 s beat and a poll (measured +3.8 s).
 H.Advance(1.5);assert(H.attempts==2 and H.Allowed(),'resumes without a click within 1 s of the settle end, attempts='..H.attempts)
end
-- 13. A latch the player started (no runtime action) that still waits at the
-- leave holds automation the same way after the loading screen.
do
 local H=Boot();H.Offer();H.Advance(.5)
 H.perks.pendingFreezeIndex=1 -- the player's own Freeze, not answered
 SlashCmdList.NEXUS('auto');H.Advance(1)
 assert(H.attempts==0 and Nexus.GameAdapter.InFlight(),'precondition: the player latch holds the board; automation sent nothing')
 Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer();H.Advance(14)
 local ok,why=H.Allowed()
 assert(Nexus.GameAdapter.Board() and not Nexus.GameAdapter.InFlight(),'reached: the watchdog released the player latch')
 assert(H.attempts==0 and not ok and tostring(why):find('freeze sent before the loading screen',1,true),'held, reason shown: '..tostring(why)..', attempts='..H.attempts)
end

-- 13b. Only a Take's own grant ends its hold. An automatic Freeze that was
-- expired at the leave stays unresolved when a Select the player sent at the
-- same time is granted.
do
 local H=Boot();H.Offer();SlashCmdList.NEXUS('auto');H.Advance(12)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.state=='expired' and not Nexus.GameAdapter.InFlight(),
  'precondition: the Freeze is expired and its latch is dead')
 H.perks.pendingSelectSpellId=200020 -- the player's own Select, still waiting
 Leave(H)
 H.perks.pendingSelectSpellId=nil;H.granted={['Echo 20']={{spellId=200020}}};H.Notify()
 H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer();H.Advance(14)
 local ok,why=H.Allowed()
 assert(H.attempts==1 and not ok and tostring(why):find('no confirmed result for freeze and take',1,true),'the Freeze still holds: '..tostring(why)..', attempts='..H.attempts)
end

-- 13c. Every item still pending at the leave is recorded. The automatic
-- Take waits for its grant while the player's own Freeze latch is live: the
-- Take's grant alone does not end the hold, and the watchdog release of the
-- player's latch is not a result either.
do
 local H=Boot();H.run={remainingBanishes=0,totalRerolls=0,usedRerolls=0,totalFreezes=0,usedFreezes=0}
 H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.actionType=='take','one Take sent')
 H.perks.pendingSelectSpellId=nil;H.Offer(OTHER);H.Advance(.3) -- answered; the grant lags
 H.perks.pendingFreezeIndex=1 -- the player's own Freeze on the new board, never answered
 Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer(OTHER)
 local g=H.Clone(H.granted) or {};g['Echo 1']=g['Echo 1'] or {};table.insert(g['Echo 1'],{spellId=200001});H.granted=g;H.Notify()
 H.Advance(14)
 local ok,why=H.Allowed()
 assert(H.attempts==1 and not ok and tostring(why):find('no confirmed result for freeze and take',1,true),'held for the player latch: '..tostring(why)..', attempts='..H.attempts)
 assert(not Nexus.GameAdapter.InFlight(),'reached: the Take is granted and the player latch is dead')
end

-- 13d. A grant of another spell does not confirm a crossed Take. The
-- automatic Take failed on the same board; the player's own Select of another
-- spell is granted in the loading screen. The Take stays unresolved.
do
 local H=Boot();H.run={remainingBanishes=0,totalRerolls=0,usedRerolls=0,totalFreezes=0,usedFreezes=0}
 H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.actionType=='take','one Take sent')
 H.perks.pendingSelectSpellId=nil;H.Advance(1) -- refused: the latch clears on the same board
 assert(Nexus.RecomputeStats().lastActionLifecycle.state=='uncertain','precondition: the Take is uncertain on the same board')
 H.perks.pendingSelectSpellId=200020 -- the player's own Select of another spell
 Leave(H);H.perks.pendingSelectSpellId=nil;H.granted={['Echo 20']={{spellId=200020}}};H.Notify()
 H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer();H.Advance(14)
 local ok,why=H.Allowed()
 assert(H.attempts==1 and not ok and tostring(why):find('no confirmed result for 2 take requests',1,true),'the Take still holds: '..tostring(why))
 assert(Nexus.RecomputeStats().actionLifecycle.confirmed==0,'the other grant confirms nothing')
end

-- 14. A Take that crosses the loading screen is resolved by its grant, the
-- one supported result (the adapter's ConfirmAwaitingGrant rule). Before the
-- grant it holds; after it, automation continues without a click.
local NOCHARGES={remainingBanishes=0,totalRerolls=0,usedRerolls=0,totalFreezes=0,usedFreezes=0}
do
 local H=Boot();H.run=NOCHARGES;H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 local l=Nexus.RecomputeStats().lastActionLifecycle
 assert(H.attempts==1 and l.actionType=='take' and l.state=='submitted','one Take sent: '..tostring(l.actionType)..'/'..tostring(l.state))
 H.Fire('PLAYER_LEAVING_WORLD')
 H.perks.pendingSelectSpellId=nil;H.Offer(OTHER);H.Advance(1) -- answered in the loading screen; the board moved on
 H.Advance(1);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(14)
 local ok,why=H.Allowed()
 assert(H.attempts==1 and not ok and tostring(why):find('take sent before the loading screen',1,true),'no grant yet: held: '..tostring(why))
 local g=H.Clone(H.granted) or {};g['Echo 1']=g['Echo 1'] or {};table.insert(g['Echo 1'],{spellId=200001});H.granted=g;H.Notify()
 H.Advance(1.5)
 assert(Nexus.RecomputeStats().actionLifecycle.confirmed==1,'the grant confirms the Take')
 assert(H.attempts==2 and H.Allowed(),'continues without a click within 1.5 s of the grant, attempts='..H.attempts)
end

-- 14b. Bounded: when the grant arrives in the loading screen, the Take is
-- resolved by then and the next action follows the settle like scenario 12.
do
 local H=Boot();H.run=NOCHARGES;H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.actionType=='take','one Take sent')
 H.Fire('PLAYER_LEAVING_WORLD')
 H.perks.pendingSelectSpellId=nil;H.Offer(OTHER);H.Advance(1)
 local g=H.Clone(H.granted) or {};g['Echo 1']=g['Echo 1'] or {};table.insert(g['Echo 1'],{spellId=200001});H.granted=g;H.Notify()
 H.Advance(1);H.Fire('PLAYER_ENTERING_WORLD')
 H.Advance(2.5);assert(H.attempts==1,'held inside the settle')
 H.Advance(1.5);assert(H.attempts==2,'continues within 1 s of the settle end, attempts='..H.attempts)
end

-- 15. The level-80 save gate is held too, and the status line says why; after
-- player input it runs. A final Take whose grant arrives in the loading
-- screen lets the save gate run after the settle without a click.
local function Granted(n,withTarget)
 local g,c={},0
 for i=2,90 do if c>=n then break end;g['Echo '..i]={{spellId=200000+i}};c=c+1 end
 if withTarget then g['Echo 1']={{spellId=200001}} end
 return g
end
do
 local H=Boot();H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(14)
 assert(not Nexus.GameAdapter.Board() and H.runtime.StatusLine():find('auto paused: no confirmed result for freeze sent before the loading screen',1,true),
  'no board: the hold says why: '..H.runtime.StatusLine())
 H.playerLevel=80;H.granted=Granted(79,false);Nexus.GameAdapter.RequestGranted();H.Notify();H.Advance(6)
 local o=Nexus.GameAdapter.Owned()
 assert(o.synced and o.total==79,'reached: level 80, run complete, no board: '..tostring(o.total))
 local status=H.runtime.StatusLine()
 assert(status:find('auto paused: no confirmed result for freeze sent before the loading screen',1,true),'the save gate is held and says why: '..status)
 SlashCmdList.NEXUS('auto');SlashCmdList.NEXUS('auto');H.Advance(.5)
 status=H.runtime.StatusLine()
 assert(status:find('run complete',1,true),'after player input the save gate runs: '..status)
end
do
 local H=Boot();H.run=NOCHARGES
 H.playerLevel=80;H.granted=Granted(78,false);Nexus.GameAdapter.RequestGranted();H.Advance(1)
 H.Offer({{spellId=200001,quality=1},{spellId=200089,quality=0},{spellId=200090,quality=1}})
 SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.actionType=='take','the final Take is sent')
 H.Fire('PLAYER_LEAVING_WORLD')
 H.perks.pendingSelectSpellId=nil;H.Board({});H.Notify();H.granted=Granted(78,true);H.Notify()
 H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(4.5)
 local status=H.runtime.StatusLine()
 assert(H.Allowed() and status:find('run complete',1,true),'the granted final Take lets the save gate run without a click: '..status)
 assert(Nexus.RecomputeStats().actionLifecycle.confirmed==1,'the Take is confirmed by its grant on the save path too')
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(4.5)
 assert(H.Allowed() and H.runtime.StatusLine():find('run complete',1,true),'a second zone holds nothing: '..H.runtime.StatusLine())
end
do
 local H=Boot();H.playerLevel=80;H.granted=Granted(78,false);Nexus.GameAdapter.RequestGranted();H.Advance(1)
 H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 local l=Nexus.RecomputeStats().lastActionLifecycle
 assert(H.attempts==1 and l.state=='submitted' and l.actionType~='take','one non-Take action sent at level 80: '..tostring(l.actionType))
 Leave(H);H.granted=Granted(79,false);H.Notify() -- the run completes by another grant
 H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(14)
 local o=Nexus.GameAdapter.Owned()
 local status=H.runtime.StatusLine()
 assert(o.synced and o.total==79,'reached: the save path at level 80: '..tostring(o.total))
 assert(status:find('auto paused: no confirmed result for '..l.actionType..' sent before the loading screen',1,true),'the save path says why: '..status)
end
-- 16. At level 80 no StepRun resolves a Take, so a Take granted with no
-- loading screen is still "submitted" at a later leave. Its visible grant is
-- its result there: the zone holds nothing.
do
 local H=Boot();H.run=NOCHARGES
 H.playerLevel=80;H.granted=Granted(78,false);Nexus.GameAdapter.RequestGranted();H.Advance(1)
 H.Offer({{spellId=200001,quality=1},{spellId=200089,quality=0},{spellId=200090,quality=1}})
 SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.actionType=='take','the final Take is sent')
 H.perks.pendingSelectSpellId=nil;H.Board({});H.Notify();H.granted=Granted(78,true);H.Notify();H.Advance(34)
 assert(Nexus.RecomputeStats().lastActionLifecycle.state=='submitted','precondition: nothing resolved the granted Take before the zone')
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(4.5)
 local l=Nexus.RecomputeStats().lastActionLifecycle
 assert(l.state=='confirmed' and l.reason=='grant_observed','the leave records the visible grant: '..tostring(l.state)..'/'..tostring(l.reason))
 assert(H.Allowed() and H.runtime.StatusLine():find('run complete',1,true),'the zone holds nothing: '..H.runtime.StatusLine())
end

-- 17. A later leave adds its pending items to an open hold. At the first
-- leave only the automatic Take waited (its grant could end the hold). The
-- player's own Freeze, sent during that hold, is pending at the second
-- leave, so the Take's grant no longer ends the hold.
do
 local H=Boot();H.run=NOCHARGES;H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.actionType=='take','one Take sent')
 H.perks.pendingSelectSpellId=nil;H.Offer(OTHER);H.Advance(.3) -- answered; the grant lags
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer(OTHER);H.Advance(5)
 assert(not H.Allowed(),'held after the first zone')
 H.perks.pendingFreezeIndex=1 -- the player's own Freeze during the hold, never answered
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer(OTHER)
 local g=H.Clone(H.granted) or {};g['Echo 1']=g['Echo 1'] or {};table.insert(g['Echo 1'],{spellId=200001});H.granted=g;H.Notify()
 H.Advance(14)
 local ok,why=H.Allowed()
 assert(H.attempts==1 and not ok and tostring(why):find('no confirmed result for freeze and take',1,true),'held for the player latch: '..tostring(why)..', attempts='..H.attempts)
 assert(not Nexus.GameAdapter.InFlight(),'reached: the Take is granted and the player latch is dead')
end
-- 18. Two Select requests pending at the leave are two requests, also for
-- the same spell: the automatic Take waits for its grant and the player
-- clicks another copy of that spell (a live latch). One grant does not end
-- the hold, the watchdog release of the player's latch does not erase it,
-- and a second zone keeps it. Player input ends it without recording a
-- confirmation. Control: the automatic Take alone is one request (its local
-- tracking and its latch are not counted twice) and its grant resumes.
local function Grant(H,id)
 local g=H.Clone(H.granted) or {};local k='Echo '..(id-200000);g[k]=g[k] or {}
 table.insert(g[k],{spellId=id});H.granted=g;H.Notify()
end
for _,v in ipairs({{'same spell',200001},{'different spell',200030},{'single automatic Take',nil}}) do
 local H=Boot();H.run=NOCHARGES;H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.actionType=='take',v[1]..': one automatic Take')
 H.perks.pendingSelectSpellId=nil;H.Offer(OTHER);H.Advance(.3) -- answered; its grant lags
 if v[2] then
  local attempts=H.attempts -- the player's click goes through the same client service
  assert(H.service.SelectPerk(v[2]),v[1]..': the player Select is accepted');H.attempts=attempts
 end
 local pending=Nexus.GameAdapter.PendingActions()
 assert(#pending==(v[2] and 2 or 1),v[1]..': requests pending at the leave: '..#pending)
 if v[2]==200001 then
  assert(pending[1].spellId==200001 and pending[2].spellId==200001 and pending[1].source~=pending[2].source,
   'same spell: two requests are listed, not one')
 end
 Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer(OTHER);H.Advance(4)
 Grant(H,200001);H.Advance(1.5)
 if not v[2] then
  assert(H.attempts==2 and H.Allowed(),'single: its grant resumes without a click, attempts='..H.attempts)
 else
  H.Advance(12)
  local ok,why=H.Allowed()
  assert(H.attempts==1 and not ok and tostring(why):find('no confirmed result for 2 take requests',1,true),
   v[1]..': one grant does not end the hold: '..tostring(why)..', attempts='..H.attempts)
  assert(not Nexus.GameAdapter.InFlight(),v[1]..': reached: granted once, and the player latch is dead')
  H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(5)
  ok,why=H.Allowed()
  assert(H.attempts==1 and not ok and tostring(why):find('no confirmed result for 2 take requests',1,true),
   v[1]..': a second zone keeps it: '..tostring(why))
  local confirmed=Nexus.RecomputeStats().actionLifecycle.confirmed
  SlashCmdList.NEXUS('auto');SlashCmdList.NEXUS('auto')
  local l=Nexus.RecomputeStats().lastActionLifecycle
  -- Here the hold came from the adapter's two requests alone (the older
  -- board-change rule had already dropped the automatic intent before the
  -- leave), so no intent is resolved; nothing may be recorded as confirmed.
  assert(l.state~='confirmed' and Nexus.RecomputeStats().actionLifecycle.confirmed==confirmed,
   v[1]..': the acknowledgement records no confirmation: '..tostring(l.state)..'/'..tostring(l.reason))
  H.Advance(1.5);assert(H.attempts==2,v[1]..': automation continues after the acknowledgement, attempts='..H.attempts)
 end
end

-- 18b. A grant cannot be matched when another request for the same spell is
-- pending. (i) The automatic Take was refused on the same board, then the
-- player selects that spell: the player's grant does not end the hold and
-- confirms nothing. (ii) Level 80, where no StepRun resolves the Take: its
-- grant is visible at the leave while the player's own Select of the same
-- spell is live; the Take is not recorded as confirmed.
do
 local H=Boot();H.run=NOCHARGES;H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 H.perks.pendingSelectSpellId=nil;H.Advance(1) -- refused: the latch clears on the same board
 assert(Nexus.RecomputeStats().lastActionLifecycle.state=='uncertain','(i) precondition: the Take is uncertain on the same board')
 local attempts=H.attempts;assert(H.service.SelectPerk(200001),'(i) the player Select is accepted');H.attempts=attempts
 Leave(H);H.perks.pendingSelectSpellId=nil;Grant(H,200001);H.Advance(2)
 H.Fire('PLAYER_ENTERING_WORLD');H.Offer();H.Advance(14)
 local ok,why=H.Allowed()
 assert(H.attempts==1 and not ok and tostring(why):find('no confirmed result for 2 take requests',1,true),'(i) held: '..tostring(why))
 assert(Nexus.RecomputeStats().actionLifecycle.confirmed==0,'(i) the player grant confirms nothing')
end
do
 local H=Boot();H.run=NOCHARGES
 H.playerLevel=80;H.granted=Granted(77,false);Nexus.GameAdapter.RequestGranted();H.Advance(1)
 H.Offer({{spellId=200001,quality=1},{spellId=200089,quality=0},{spellId=200090,quality=1}})
 SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.actionType=='take','(ii) one automatic Take')
 H.perks.pendingSelectSpellId=nil;H.Board({});H.Notify();H.Advance(1) -- answered; no board, no StepRun
 Grant(H,200001)
 H.Offer({{spellId=200001,quality=1},{spellId=200085,quality=0},{spellId=200086,quality=1}})
 local attempts=H.attempts;assert(H.service.SelectPerk(200001),'(ii) the player Select is accepted');H.attempts=attempts
 assert(Nexus.RecomputeStats().lastActionLifecycle.state=='submitted' and Nexus.GameAdapter.GrantedCount(200001)==1,
  '(ii) precondition: the grant is visible and the Take is still submitted')
 H.Fire('PLAYER_LEAVING_WORLD')
 local l=Nexus.RecomputeStats().lastActionLifecycle
 assert(l.state=='uncertain' and l.reason=='world_transition' and Nexus.RecomputeStats().actionLifecycle.confirmed==0,
  '(ii) not matched to the grant: '..tostring(l.state)..'/'..tostring(l.reason))
end

-- 19. A hold that cannot end by a grant keeps its earlier items at a later
-- leave. First leave: only the player's Freeze latch is pending (no grant
-- path). Second leave: only a player Select is pending. Its grant does not
-- end the hold.
do
 local H=Boot();H.run=NOCHARGES;H.Offer();H.Advance(.5)
 H.perks.pendingFreezeIndex=1 -- the player's own Freeze, never answered
 SlashCmdList.NEXUS('auto');H.Advance(1)
 assert(H.attempts==0,'precondition: nothing automatic is sent while the player latch is live')
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer();H.Advance(12)
 assert(not Nexus.GameAdapter.InFlight(),'reached: the player Freeze latch is dead')
 assert(H.service.SelectPerk(200020),'the player Select is accepted');H.attempts=0
 H.Fire('PLAYER_LEAVING_WORLD');H.perks.pendingSelectSpellId=nil;H.Offer(OTHER);H.Advance(2)
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(4)
 Grant(H,200020);H.Advance(3)
 local ok,why=H.Allowed()
 assert(H.attempts==0 and not ok and tostring(why):find('no confirmed result for freeze and take',1,true),
  'the earlier Freeze still holds after the Select grant: '..tostring(why)..', attempts='..H.attempts)
end

-- 20. A run boundary ends the hold: the dead run's action is superseded
-- (run_boundary), not confirmed, and the hold reason is gone.
do
 local H=Boot();H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 Leave(H);H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Offer();H.Advance(14)
 assert(not H.Allowed(),'precondition: held after the zone')
 H.playerLevel=80;H.Advance(1);H.playerLevel=1;H.Advance(2)
 local l=Nexus.RecomputeStats().lastActionLifecycle
 local _,why=H.Allowed()
 assert(l.state=='superseded' and l.reason=='run_boundary','the run boundary supersedes it: '..tostring(l.state)..'/'..tostring(l.reason))
 assert(not tostring(why):find('no confirmed result',1,true),'the hold is gone: '..tostring(why))
 assert(Nexus.RecomputeStats().actionLifecycle.confirmed==0,'nothing is recorded as confirmed')
end
-- 21. A Take that the client refused is never recorded as confirmed by a
-- grant from the player's own Select of the same spell (level 80).
do
 local H=Boot();H.run=NOCHARGES
 H.playerLevel=80;H.granted=Granted(77,false);Nexus.GameAdapter.RequestGranted();H.Advance(1)
 H.Offer({{spellId=200001,quality=1},{spellId=200089,quality=0},{spellId=200090,quality=1}});H.Advance(.5)
 assert(H.service.SelectPerk(200001),'the player Select is accepted');H.attempts=0
 SlashCmdList.NEXUS('auto');H.Advance(12)
 local l=Nexus.RecomputeStats().lastActionLifecycle
 assert(H.attempts==1 and l.actionType=='take' and l.state=='rejected','precondition: the automatic Take was refused: '..tostring(l.state))
 H.perks.pendingSelectSpellId=nil;H.Board({});H.Notify();Grant(H,200001);H.Advance(3)
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(2);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(4.5)
 l=Nexus.RecomputeStats().lastActionLifecycle
 assert(l.state=='rejected' and Nexus.RecomputeStats().actionLifecycle.confirmed==0,'the refused Take stays refused: '..tostring(l.state)..'/'..tostring(l.reason))
end
print('PASS Auto selection kept across a same-session loading screen with actions held until settled; whatever still waited at the leave (runtime action or adapter latch) holds automation until player input, a run boundary or a Take grant, with the reason shown; unclassified entry and logout revoke; compact Auto labels')
