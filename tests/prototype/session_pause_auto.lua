-- Issue #171: whole-addon session pause and ordinary Auto. Real TOC, runtime,
-- adapter, policy and slash commands over the synthetic game surface. Every
-- "no action" below is checked against an unpaused control on the same rig.
local WANT={{spellId=200001,quality=1},{spellId=200001,quality=1},{spellId=200020,quality=0}}
local function Boot(before)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={[1]={name='Active saved build',verified=true,
  echoes={{spellId=200001,quality=1,stacks=2}}}}
 -- Every board-action attempt, accepted or refused, and every read request.
 H.attempts=0
 for _,name in ipairs({'SelectPerk','BanishPerk','FreezePerk','RequestReroll'})do
  local call=H.service[name];H.service[name]=function(...)H.attempts=H.attempts+1;return call(...)end
 end
 if before then before(H) end
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#') then
   local chunk,err=loadfile((line:gsub('\\','/')));assert(chunk,err);chunk('Nexus',{})
  end
 end
 -- The real runtime instance as Main creates it (no product seam added).
 local factory=Nexus.MainInternals.AutomationRuntime;local new=factory.New
 factory.New=function(...)H.runtime=new(...);return H.runtime end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(20,.05)
 H.AcknowledgeOverwriteWarnings()
 assert(H.runtime,'runtime instance captured')
 assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Assigned plan',{{spellId=200001,quality=1,stacks=2}}),'assign the plan')
 local BOARD={take=true,freeze=true,banish=true,reroll=true}
 function H.Takes()local n=0;for _,a in ipairs(H.actions)do if BOARD[a[1]] then n=n+1 end end;return n end
 function H.Auto()return Nexus.RecomputeStats().autoEnabled end
 function H.Offer(cards)H.Board(cards or WANT);H.Notify()end
 function H.Chat(from)return table.concat(H.chat,'\n',from or 1)end
 return H
end

-- 1. Control: this rig acts on the board when Auto is ON and nothing holds it.
do
 local H=Boot();H.Offer();H.Advance(.5)
 assert(H.Takes()==0 and not H.Auto(),'starts OFF: no action')
 SlashCmdList.NEXUS('auto');H.Advance(1.2)
 assert(H.Auto() and H.Takes()==1,'control: Auto ON acts on the board, actions='..H.Takes())
end

-- 2. /nexus pause holds the selected Auto: the selection stays ON, actual
-- ticks pass with a valid offer, and no board action is attempted.
do
 local H=Boot();SlashCmdList.NEXUS('auto');H.Advance(.5)
 assert(H.Auto() and H.Takes()==0,'Auto ON with no board yet')
 local mark=#H.chat+1
 SlashCmdList.NEXUS('pause')
 assert(Nexus.SessionPause and Nexus.SessionPause.IsPaused()==true,'the pause command sets the session pause')
 assert(H.Chat(mark):find('Nexus paused',1,true),'the command answers: '..H.Chat(mark))
 H.Offer();H.Advance(5)
 assert(H.Auto(),'pause keeps the Auto selection ON')
 assert(H.Takes()==0 and H.attempts==0,'no board action while paused, attempts='..H.attempts)
 local ok,why=H.runtime.AutoAllowed()
 assert(not ok and tostring(why):find('paused',1,true),'the authority gate names the pause: '..tostring(why))
 -- The explicit step and the panel refresh route reach the same gate.
 assert(H.runtime.RunFullStep('explicit','test')~=nil)
 Nexus.RefreshPanel();H.Advance(1)
 assert(H.Takes()==0 and H.attempts==0,'explicit step and refresh act on nothing while paused')
 -- Resume removes only the global hold; the prior selection acts on a later
 -- normal turn, exactly once.
 mark=#H.chat+1
 SlashCmdList.NEXUS('resume')
 assert(Nexus.SessionPause.IsPaused()==false,'resume clears the session pause')
 assert(H.Chat(mark):find('resumed',1,true),'the command answers: '..H.Chat(mark))
 assert(H.Takes()==0,'Resume itself sends nothing')
 H.Advance(1.5)
 assert(H.Auto() and H.Takes()==1,'after Resume the prior selection acts again, actions='..H.Takes())
 H.Advance(3);assert(H.attempts==1,'and only once, attempts='..H.attempts)
end

-- 3. Auto that was OFF stays OFF across pause and resume, and cannot be turned
-- ON while paused (no new authority is granted during the pause).
do
 local H=Boot();H.Offer();H.Advance(.5)
 SlashCmdList.NEXUS('pause');SlashCmdList.NEXUS('auto');H.Advance(2)
 assert(not H.Auto() and H.Takes()==0,'Auto cannot be turned ON while paused')
 SlashCmdList.NEXUS('resume');H.Advance(3)
 assert(not H.Auto() and H.Takes()==0,'Auto OFF stays OFF after Resume')
end


-- 4. An intent prepared before the pause is superseded, never submitted.
do
 local H=Boot();H.Offer();H.Advance(.5);SlashCmdList.NEXUS('auto');H.Advance(.25)
 local life=Nexus.RecomputeStats().lastActionLifecycle
 assert(H.Takes()==0 and life.state=='prepared','an action is prepared, not yet sent: '..tostring(life.state))
 SlashCmdList.NEXUS('pause');H.Advance(2)
 life=Nexus.RecomputeStats().lastActionLifecycle
 assert(life.state=='superseded' and life.reason=='session_pause' and not life.mutationAttempted,
  'the prepared action is superseded by the pause: '..tostring(life.state)..'/'..tostring(life.reason))
 assert(H.attempts==0,'nothing sent while paused')
end

-- 5. A Pause and Resume between two turns still supersede the prepared
-- intent: the next action is a fresh decision at the normal beat, sent once.
do
 local H=Boot();H.Offer();H.Advance(.5);SlashCmdList.NEXUS('auto');H.Advance(.25)
 assert(Nexus.RecomputeStats().lastActionLifecycle.state=='prepared','prepared before the quick pause')
 local before=Nexus.RecomputeStats().actionLifecycle.superseded
 SlashCmdList.NEXUS('pause');SlashCmdList.NEXUS('resume')
 local status=Nexus.SessionPause.Status()
 assert(status.paused==false and status.epoch==2,'two real transitions: epoch='..tostring(status.epoch))
 H.Advance(.45)
 assert(Nexus.RecomputeStats().actionLifecycle.superseded==before+1,'the pre-pause intent was superseded')
 assert(H.attempts==0,'the pre-pause intent is not submitted')
 H.Advance(1.5)
 assert(H.Takes()==1 and H.attempts==1,'one fresh action after the quick pause, attempts='..H.attempts)
end

-- 6. Direct adapter entries refuse while paused, before any native call or
-- bookkeeping; the same call goes through unpaused (control).
do
 local H=Boot();H.Offer();H.Advance(.5)
 local calls={}
 for _,name in ipairs({'LockPerk','UnlockPerk','SaveServerBuildSlot','ActivateServerBuildSlot',
  'UploadServerBuildSlot','RequestServerBuildSlots','RequestGrantedPerks','ToggleTomeEcho'}) do
  local call=H.service[name];H.service[name]=function(...)calls[#calls+1]=name;return call(...)end
 end
 local A=Nexus.GameAdapter
 SlashCmdList.NEXUS('pause')
 H.now=H.now+10
 local ok,why=A.Take(200001)
 assert(not ok and tostring(why):find('paused',1,true),'Take refuses while paused: '..tostring(why))
 assert(not A.Banish(0) and not A.Freeze(0) and not A.Reroll(),'Banish, Freeze and Reroll refuse')
 assert(not A.LockPerk(200001) and not A.UnlockPerk(200001),'Lock and Unlock refuse')
 assert(not A.Save(1,'x') and not A.Activate(1),'Save and Activate refuse')
 assert(not A.UploadWishlist(0,'x',{{spellId=200001,quality=1}}),'Upload refuses')
 assert(not A.RequestSlots() and not A.RequestGranted() and not A.RecheckSelect(),'read requests refuse')
 assert(not A.SetSoloPicker(),'the client option is not changed while paused')
 assert(H.attempts==0 and #calls==0,'no native call: attempts='..H.attempts..' calls='..table.concat(calls,','))
 SlashCmdList.NEXUS('resume')
 assert(A.Take(200001)==true and H.attempts==1,'control: the same Take goes through unpaused')
 assert(A.RequestSlots()==true and calls[#calls]=='RequestServerBuildSlots','control: a read request goes through unpaused')
end

-- 7. A warning approval that arrives while paused cannot turn Auto ON, and a
-- later approval of the same stale request after Resume does not either.
do
 local H=Boot();H.Offer();H.Advance(.5)
 local warning=Nexus.OverwriteWarning;local request=warning.RequestAuto;local captured
 warning.RequestAuto=function(_,accept)captured=accept;return false end
 SlashCmdList.NEXUS('auto')
 warning.RequestAuto=request
 assert(type(captured)=='function' and not H.Auto(),'the approval is waiting')
 SlashCmdList.NEXUS('pause')
 assert(captured()==false and not H.Auto(),'a late approval while paused does not turn Auto ON')
 H.Advance(2);assert(H.attempts==0,'no action')
 SlashCmdList.NEXUS('resume');H.Advance(2)
 assert(not H.Auto() and H.attempts==0,'Resume grants no Auto authority')
end


-- 8-9. An action sent before the pause stays honest. Its exact late result
-- settles it once while paused; without one it stays unresolved through the
-- pause, a loading screen, its timeout and Resume. Nothing is resent, and the
-- paused poll sends no read-only recheck where the unpaused one does.
local OTHER={{spellId=200001,quality=1},{spellId=200030,quality=0},{spellId=200031,quality=1}}
local NOCHARGES={remainingBanishes=0,totalRerolls=0,usedRerolls=0,totalFreezes=0,usedFreezes=0}
local function Grant(H,id)
 local g=H.Clone(H.granted) or {};local k='Echo '..(id-200000);g[k]=g[k] or {}
 table.insert(g[k],{spellId=id});H.granted=g;H.Notify()
end
local function SentTakeAcrossWorld(pause)
 local H=Boot();H.run=NOCHARGES;H.Offer();SlashCmdList.NEXUS('auto');H.Advance(1.2)
 local l=Nexus.RecomputeStats().lastActionLifecycle
 assert(H.attempts==1 and l.actionType=='take' and l.state=='submitted','one Take sent: '..tostring(l.state))
 if pause then SlashCmdList.NEXUS('pause') end
 local reads=H.grantedRequests or 0
 H.Fire('PLAYER_LEAVING_WORLD')
 H.perks.pendingSelectSpellId=nil;H.Offer(OTHER);H.Advance(1) -- answered; its grant lags
 H.Advance(1);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(14)
 return H,(H.grantedRequests or 0)-reads
end
do
 local _,controlReads=SentTakeAcrossWorld(false)
 assert(controlReads>0,'control: unpaused, the unresolved Select is rechecked read-only, reads='..controlReads)
 local H,reads=SentTakeAcrossWorld(true)
 assert(reads==0,'paused: no read-only recheck is sent, reads='..reads)
 assert(H.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.state=='uncertain','still unresolved, not resent')
 Grant(H,200001);H.Advance(1.5)
 local stats=Nexus.RecomputeStats()
 assert(stats.actionLifecycle.confirmed==1,'the exact late grant settles the sent Take while paused')
 assert(H.attempts==1 and H.Auto(),'no new action while paused; the selection stays ON')
 H.Advance(5);assert(Nexus.RecomputeStats().actionLifecycle.confirmed==1,'settled once')
 SlashCmdList.NEXUS('resume');H.Advance(2)
 assert(H.attempts==2,'after Resume the next decision acts once, attempts='..H.attempts)
end
do
 local H=SentTakeAcrossWorld(true);H.Advance(30)
 local ok,why=H.runtime.AutoAllowed()
 assert(not ok and H.attempts==1,'held while paused past the confirmation timeout')
 assert(Nexus.RecomputeStats().actionLifecycle.confirmed==0,'time and the moved board are not its result')
 SlashCmdList.NEXUS('resume');H.Advance(5)
 ok,why=H.runtime.AutoAllowed()
 assert(not ok and tostring(why):find('take sent before the loading screen',1,true),
  'Resume keeps the world hold of the unresolved Take: '..tostring(why))
 assert(H.attempts==1 and H.Auto(),'nothing resent after Resume')
end

print('PASS session pause holds ordinary Auto without changing its selection')
