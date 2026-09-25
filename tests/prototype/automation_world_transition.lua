-- Ordinary Auto across a loading screen inside one UI session. The selection
-- stays ON; actions are held from PLAYER_LEAVING_WORLD until the entry that
-- closes it has settled with the adapter ready. An entry with no observed leave
-- (login, /reload, or anything this session cannot classify) and a logout turn
-- Auto OFF. Real runtime, adapter, policy and panel; synthetic game surface.
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
 function H.Offer()H.Board(WANT);H.Notify()end
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
-- transition: its own lifecycle keeps holding the board.
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

-- 9. Button labels fit the 72-pixel button: Auto: --, Auto: ON, Auto: OFF.
do
 local H=Boot();Nexus.Panel.Show();H.Advance(.5)
 assert(Label()=='Auto: OFF','OFF label: '..Label())
 NexusPanel._autoBtn:Click();H.Advance(.5)
 assert(H.Auto() and Label()=='Auto: ON','button click turns Auto ON: '..Label())
 NexusPanel._autoBtn:Click();H.Advance(.5)
 assert(not H.Auto() and Label()=='Auto: OFF','button click turns Auto OFF: '..Label())
 local src=io.open('ui/Panel.lua'):read('*a')
 assert(src:find('"Auto: --"',1,true),'unknown-state label is Auto: --')
 assert(not src:find('Automation: ',1,true),'the long label is gone')
end
print('PASS Auto selection kept across a same-session loading screen with actions held until settled; unclassified entry and logout revoke; compact Auto labels')
