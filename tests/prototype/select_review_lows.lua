-- Fresh independent review of the Select recovery follow-up, findings L1-L4.
-- L1: at level 80, Auto's final Take whose choice went away is a real wait
-- while its Select is unresolved; its exact grant with the client flag clear
-- ends that wait -- the tracked intent, the effective wait, the stale Orb
-- guidance that hid Open Orbs -- and is recorded once as
-- confirmed:grant_observed. Controls: an unrelated grant, the exact grant
-- while the flag is still set and a run boundary's void confirm nothing; a new
-- board stays held until the grant. L2: the prepared support report keeps the
-- whole unresolved-Select wait, also behind a pause prefix; a longer reason
-- (synthetic accessor) is cut on a UTF-8 character boundary, bounded and
-- marked. L3a: the watchdog line for an outside Select flag agrees with
-- A.Take, which sends no Select while it is set (control: a Freeze flag keeps
-- its per-action release). L3b: the world hold names its read refreshes with
-- their conditions; after an outside same-Echo Select it no longer promises
-- the exact grant and names what still ends it. L4 (coverage): a Take a board
-- change left uncertain is confirmed once by its later exact grant through
-- the runtime's link; voided by a run boundary it never is. Nothing is resent
-- and no client field is written. Real modules, synthetic service.
local F=dofile('tests/prototype/select_followup_support.lua')
local R=F.R
local scenario,finish=R.Checks()
local EURO='\226\130\172'

local function Occurrences(text,needle)
 local n,at=0,1
 while true do
  local a,b=text:find(needle,at,true)
  if not a then return n end
  n,at=n+1,b+1
 end
end
-- Read refreshes, board-action attempts and saved actions, as one value.
local function Effects(H) return (H.grantedRequests or 0)..'/'..H.boardAttempts..'/'..#H.actions end
-- Counts every write to the client's Perks table through the add-on's view
-- of it (the fake client and the fixture write the real table, H.perks).
-- Returns a function that restores the table and answers the count.
local function CountPerksWrites()
 local pe,real,writes=ProjectEbonhold,ProjectEbonhold.Perks,0
 pe.Perks=setmetatable({},{__index=real,__newindex=function(_,k,v) writes=writes+1;real[k]=v end})
 return function() pe.Perks=real;return writes end
end

------------------------------------------------------------------------
-- L1. Level 80: Auto's final Take, then its choice goes away.
------------------------------------------------------------------------
local function FinalTake(H) H.playerLevel=80;Nexus.Panel.Show();R.AutoSubmit(H) end
-- No board; the client flag clears with the choice unless it is kept.
local function ChoiceGone(H,keepFlag)
 if not keepFlag then H.perks.pendingSelectSpellId=nil end
 H.perks.currentChoice=nil;H.Notify();H.Advance(12)
end
-- A state-aware Orb service that is idle (synthetic, the shape used by
-- orb_guidance_navigation). Spending is counted.
local function IdleOrbs(H)
 H.orbSpends=0
 ProjectEbonhold.OrbService={IsStateKnown=function() return true end,IsOfferPending=function() return false end,
  GetCharges=function() return 3 end,RequestCharges=function() return true end,
  ConfirmSpend=function() H.orbSpends=H.orbSpends+1;return true end}
end
-- The HUD's Orb guidance state, whether Open Orbs is shown, and its text.
local function Guide()
 local m=Nexus.Panel._lastModel or {}
 local g=type(m.orbGuidance)=='table' and m.orbGuidance or {}
 local button=NexusPanel and NexusPanel._orbsBtn
 return g.state,button~=nil and button:IsShown()==true,g.text
end

scenario('L1 level 80, no board: the final automatic Take waits while unresolved; its exact grant with the flag clear ends the wait, recorded once',function(check)
 local H,A=R.Boot();FinalTake(H);IdleOrbs(H)
 local written=CountPerksWrites()
 H.pendingRolls=0 -- the final choice used the last normal roll
 ChoiceGone(H)
 local ordinal,phase,_,wait,_,overdue=A.SelectUnresolved()
 assert(ordinal==1 and phase=='grant' and wait=='grant' and overdue and A.Board()==nil,
  'setup: level 80, no board, the own Select overdue without a grant: '..tostring(phase)..'/'..tostring(wait))
 local _,before=F.Lifecycle()
 local e=Nexus.AutomationEffectiveState()
 check((e.state=='waiting' or e.state=='rechecking') and tostring(e.reason):find('Echo selection already sent',1,true)~=nil,
  'control: unresolved, it is a real wait for that selection: '..tostring(e.state)..' / '..tostring(e.reason))
 local state,shown,text=Guide()
 check(state=='waiting' and not shown,'control: the HUD waits and offers no Open Orbs: '..tostring(state))
 check(before.confirmed==0 and not F.TraceIo():find('confirmed:',1,true),'control: nothing is confirmed while it is unresolved')
 R.Grant(H,R.X)
 assert(A.SelectOutcome(1)=='proven' and not A.InFlight(),'setup: the adapter proved its exact grant with the flag clear')
 for _=1,20 do H.Advance(.25);if Nexus.PendingIntentState()==nil then break end end
 H.Advance(.5)
 check(Nexus.PendingIntentState()==nil,'the tracked Take is released: '..tostring(Nexus.PendingIntentState()))
 e=Nexus.AutomationEffectiveState()
 check(e.state=='ready','the effective wait ends: '..tostring(e.state)..' / '..tostring(e.reason))
 local now=F.NowLine()
 check(now~=nil and not now:find('result of the automatic take',1,true),'the Auto tooltip no longer waits for that Take: '..tostring(now))
 state,shown,text=Guide()
 check(state=='finished' and shown,'the stale Orb wait ends and Open Orbs is offered: '..tostring(state)..' / '..tostring(text))
 local l,counts=F.Lifecycle()
 check(l.actionType=='take' and l.state=='confirmed' and l.reason=='grant_observed',
  'the observed grant is its result: '..tostring(l.state)..'/'..tostring(l.reason))
 H.Advance(10)
 l,counts=F.Lifecycle()
 check(counts.confirmed==before.confirmed+1 and Occurrences(F.TraceIo(),'confirmed:grant_observed')==1,
  'recorded once; later steps add nothing: confirmed='..tostring(counts.confirmed)..' '..F.TraceIo())
 check(H.selectAttempts==1 and H.boardAttempts==1 and (A.Owned().bySpell[R.X] or 0)==1 and H.orbSpends==0,
  'nothing resent or spent; the copy is counted once')
 check(written()==0,'no client field is written')
end)

scenario('L1 control: at level 80 an unrelated grant, or the exact grant while the flag is still set, confirms nothing',function(check)
 local H,A=R.Boot();FinalTake(H)
 local written=CountPerksWrites()
 ChoiceGone(H,true)
 local ordinal,phase=A.SelectUnresolved()
 assert(ordinal==1 and phase=='latch' and A.Board()==nil and H.perks.pendingSelectSpellId==R.X,
  'setup: level 80, no board, the client Select flag still set: '..tostring(phase))
 R.Grant(H,R.Z);H.Advance(2)
 check(A.SelectOutcome(1)=='unresolved' and F.Lifecycle().state~='confirmed','an unrelated grant settles nothing')
 R.Grant(H,R.X);H.Advance(5)
 local _,_,_,wait=A.SelectUnresolved()
 check(A.SelectOutcome(1)=='unresolved' and wait=='latch_after_grant' and A.InFlight(),
  'the exact grant with the flag still set settles nothing: '..tostring(wait))
 local l,counts=F.Lifecycle()
 check(l.state~='confirmed' and counts.confirmed==0 and not F.TraceIo():find('confirmed:',1,true),
  'no confirmation is recorded: '..tostring(l.state)..'/'..tostring(l.reason))
 local e=Nexus.AutomationEffectiveState()
 check(e.state=='waiting' and tostring(e.reason):find('still shows a selection pending',1,true)~=nil,
  'it is still a real wait: '..tostring(e.state)..' / '..tostring(e.reason))
 local state=Guide()
 check(state=='waiting','the HUD still waits: '..tostring(state))
 check(H.selectAttempts==1 and H.boardAttempts==1 and H.perks.pendingSelectSpellId==R.X and written()==0,
  'nothing resent; the client flag is untouched and no client field is written')
end)

scenario('L1 control: at level 80 a run boundary voids the unresolved final Take; nothing confirms it, also a later rise',function(check)
 local H,A=R.Boot();FinalTake(H);ChoiceGone(H)
 assert(A.SelectOutcome(1)=='unresolved' and A.Board()==nil,'setup: level 80, no board, unresolved')
 H.playerLevel=66;H.Advance(2) -- seen at level 80, then a lower level: a new run
 assert(A.SelectOutcome(1)=='voided','setup: the run boundary voided the own Select')
 local l,counts=F.Lifecycle()
 check(l.state~='confirmed' and counts.confirmed==0,'the void records no confirmation: '..tostring(l.state)..'/'..tostring(l.reason))
 R.Grant(H,R.X);H.Advance(3)
 l,counts=F.Lifecycle()
 check(A.SelectOutcome(1)=='voided' and A.SelectUnresolved()==nil,'a later exact rise does not revive the voided Select')
 check(l.state~='confirmed' and counts.confirmed==0 and not F.TraceIo():find('confirmed:',1,true),'and confirms nothing: '..F.TraceIo())
 check(H.selectAttempts==1 and H.boardAttempts==1,'nothing resent')
end)

scenario('L1 control: after the no-board wait, a new level-80 board stays held until the exact grant, then one fresh Take',function(check)
 local H,A=R.Boot();FinalTake(H)
 local written=CountPerksWrites()
 ChoiceGone(H)
 assert(A.SelectOutcome(1)=='unresolved' and A.Board()==nil,'setup: level 80, no board, unresolved')
 H.Offer(R.next);H.Advance(6)
 check(H.boardAttempts==1 and A.InFlight() and A.SelectOutcome(1)=='unresolved',
  'no Echo action of any kind on the new board while it is unresolved: boardAttempts='..H.boardAttempts)
 local _,before=F.Lifecycle()
 R.Grant(H,R.X)
 for _=1,25 do H.Advance(.2);if H.Count(R.Y)>0 then break end end
 check(H.Count(R.Y)==1 and H.Count(R.X)==1 and H.selectAttempts==2,'its exact grant resumes one fresh Take on that board; X is not replayed')
 local _,counts=F.Lifecycle()
 check(counts.confirmed==before.confirmed+1 and Occurrences(F.TraceIo(),'confirmed:grant_observed')==1,
  'its result is recorded once: '..F.TraceIo())
 check(written()==0,'no client field is written')
end)

------------------------------------------------------------------------
-- L2. The prepared support report's Auto reason line.
------------------------------------------------------------------------
local LIMITS={'no receipt','may never arrive','until a new run','Auto off and on keeps it','/reload','without learning or cancelling'}
local function HasLimits(text)
 for _,phrase in ipairs(LIMITS) do if not text:find(phrase,1,true) then return false end end
 return true
end
local function ReasonLine(text)
 for line in tostring(text):gmatch('[^\n]+') do
  if line:sub(1,13)=='Auto reason: ' then return line end
 end
end
local function Prepared()
 local report=Nexus.SupportReport.Prepare({})
 return report and table.concat(report.chunks) or ''
end

scenario('L2 the prepared report keeps the whole unresolved-Select wait, also behind a pause prefix',function(check)
 local H,A=R.Boot()
 local reason=F.Rechecking(H,A)
 local calls,reads,ok,e=F.Passive(A,Nexus.AutomationEffectiveState)
 check(ok and #calls==0 and reads==0 and e.state=='rechecking','control: the effective-state getter reads memory only: '
  ..table.concat(calls,',')..' reads='..reads)
 local function Reported(label,want,state)
  local effects=Effects(H)
  local text=Prepared()
  local line=ReasonLine(text) or ''
  check(Effects(H)==effects and text:find('Auto: selected=yes effective='..state,1,true)~=nil,
   'control: '..label..': the report names the state, and preparing it requests and sends nothing')
  check(line:find(want,1,true)~=nil,label..': the Auto reason line keeps the whole '..#want..'-byte reason: '..line)
  check(HasLimits(line),label..': the missing receipt, the run-long wait, Auto off/on and /reload reach the report: '..line)
 end
 Reported('rechecking',reason,'rechecking')
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true)
 Nexus.RequestRecompute();H.Advance(.5)
 local paused=Nexus.AutomationEffectiveState()
 assert(paused.state=='paused' and paused.reason~=reason and tostring(paused.reason):find(reason,1,true)~=nil,
  'setup: a pause prefix in front of the same wait: '..tostring(paused.reason))
 Reported('paused',paused.reason,'paused')
end)

scenario('L2 a long reason is cut on a UTF-8 character boundary, bounded and marked (synthetic accessor)',function(check)
 local H=R.Boot()
 local real,effects=Nexus.AutomationEffectiveState,Effects(H)
 local function Hex(s) return (s:gsub('.',function(c) return string.format('%02X',c:byte()) end)) end
 -- Three-byte characters after 10, 11 and 12 ASCII bytes: whatever the cap,
 -- a cut by bytes splits a character in at least two of the three.
 for pad=0,2 do
  local head=string.rep('a',10+pad)
  local reasons,lines={},{}
  for i,copies in ipairs({1000,4000}) do
   reasons[i]=head..string.rep(EURO,copies)..' tail'
   Nexus.AutomationEffectiveState=function()
    return {selected=true,state='waiting',reason=reasons[i],hold=true,rechecks=0}
   end
   local ok,text=pcall(Prepared)
   Nexus.AutomationEffectiveState=real
   lines[i]=ok and ReasonLine(text) or ''
  end
  local line=lines[1]
  local body=line:sub(14)
  local kept=body:match('^(.-)%s*%.%.%.$') or body:match('^(.-)%s*\226\128\166$') or body
  check(line:find('Auto reason: '..head,1,true)==1 and Nexus.Identity.ValidUtf8(line),
   'pad '..pad..': the reason reaches the report as valid UTF-8, no character split: ..'..Hex(line:sub(-8)))
  check(kept~=body and #kept>0 and #kept<#reasons[1] and reasons[1]:sub(1,#kept)==kept,
   'pad '..pad..': a prefix of the reason and a marked omission: ..'..Hex(line:sub(-8)))
  check(lines[2]==line,'pad '..pad..': bounded: a four times longer reason gives the same line ('..#line..'/'..#lines[2]..' bytes)')
 end
 check(Effects(H)==effects,'preparing the reports requests and sends nothing')
end)

------------------------------------------------------------------------
-- L3a. The watchdog line for an outside client flag.
------------------------------------------------------------------------
local function Watchdog(H,kind)
 local out={}
 for _,line in ipairs(H.chat) do
  local l=line:lower()
  if l:find('after 10s',1,true) and l:find(kind,1,true) then out[#out+1]=line end
 end
 return out
end
-- Select non-admission in words ("sends no Select", "does not send a Select").
local function SaysNoSelect(text)
 local l=text:lower()
 return l:find('no select',1,true)~=nil or l:find('not send',1,true)~=nil
end

scenario('L3a the watchdog line for an outside Select flag agrees with A.Take: no Select is sent while it is set',function(check)
 local H,A=R.Boot();H.Offer()
 assert(H.service.SelectPerk(R.X)==true,'setup: the player Select of X is accepted')
 local attempts=H.boardAttempts
 SlashCmdList.NEXUS('auto');H.Advance(13)
 assert(H.perks.pendingSelectSpellId==R.X and A.SelectUnresolved()==nil and not A.InFlight(),
  'setup: the player flag outlived its watchdog; no own Select; it holds no other action')
 local said=Watchdog(H,'select')
 local text=tostring(said[1])
 check(#said==1,'control: one watchdog line, not repeated: '..#said)
 check(not text:find('no longer waited on',1,true),'it does not say the flag is no longer waited on: '..text)
 check(SaysNoSelect(text),'it says Nexus sends no Select while the flag is set: '..text)
 local l=F.Lifecycle()
 check(l.actionType=='take' and l.state=='rejected' and tostring(l.reason):find('selection is pending',1,true)~=nil
  and H.boardAttempts==attempts,'control: A.Take refuses before any client call: '..tostring(l.state)..'/'..tostring(l.reason))
 local e=Nexus.AutomationEffectiveState()
 check(H.Auto() and tostring(e.reason):find('did not send',1,true)~=nil,'control: the HUD wait says the same: '..tostring(e.reason))
end)

scenario('L3a control: an outside Freeze flag past its watchdog keeps the per-action release and its wording',function(check)
 local H,A=R.Boot();H.Offer()
 assert(H.service.FreezePerk(1)==true,'setup: the player Freeze is accepted')
 local attempts=H.boardAttempts
 SlashCmdList.NEXUS('auto');H.Advance(12)
 for _=1,20 do if H.Count(R.X)>0 then break end;H.Advance(.2) end
 local said=Watchdog(H,'freeze')
 check(#said==1 and said[1]:find('no longer waited on',1,true)~=nil,'its watchdog line is unchanged: '..tostring(said[1]))
 check(H.Count(R.X)==1 and H.boardAttempts==attempts+1,'it no longer holds the loop: one automatic Take follows: '..(H.boardAttempts-attempts))
 check(H.perks.pendingFreezeIndex==1,'the client Freeze flag is untouched')
end)

------------------------------------------------------------------------
-- L3b. The world hold of the own Select after a loading screen.
------------------------------------------------------------------------
local HELD='no confirmed result for take sent before the loading screen'
local function Rereads(text) return text:lower():find('re-read',1,true)~=nil end
-- Read refreshes run only while Auto is ON and nothing else pauses them
-- (SelectPoll): a text that names them says so (SelectWait's qualifier).
local function Conditional(text)
 local l=text:lower()
 return l:find('while auto is on',1,true)~=nil and l:find('paus',1,true)~=nil
end
local function NoGrantSettles(text)
 local l=text:lower()
 for _,phrase in ipairs({'can no longer settle','cannot settle','no later grant can settle','no grant can settle'}) do
  if l:find(phrase,1,true) then return true end
 end
 return false
end
local function Held(H)
 local allowed,why=H.runtime.AutoAllowed()
 return allowed,tostring(why)
end

scenario('L3b the world hold of an own grant wait names its read refreshes with their conditions, also during another pause',function(check)
 local H,A=R.Boot();R.AutoSubmit(H);R.Travel(H)
 H.perks.pendingSelectSpellId=nil;H.Notify();H.Advance(1)
 local _,_,_,wait=A.SelectUnresolved()
 local allowed,why=Held(H)
 assert(allowed==false and wait=='grant' and why:find(HELD,1,true),
  'setup: the world hold of the own Select, which waits for its grant: '..tostring(wait)..' / '..why)
 check(H.runtime.StatusLine():find(why,1,true)~=nil and why:find('exact grant',1,true)~=nil,
  'control: the status line shows the hold, which can still end with the exact grant: '..H.runtime.StatusLine())
 check(Rereads(why) and Conditional(why),'its read refreshes are named with their conditions: '..why)
 local before=H.grantedRequests;H.Advance(10)
 check(H.grantedRequests>before,'control: with nothing pausing them, read refreshes are sent: '..(H.grantedRequests-before))
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true) -- client auto-accept pauses them
 Nexus.RequestRecompute();H.Advance(.5)
 local _,paused=Held(H)
 check(paused:find(HELD,1,true)~=nil and (not Rereads(paused) or Conditional(paused)),
  'paused: the hold does not promise read refreshes regardless of the pause: '..paused)
 before=H.grantedRequests;H.Advance(30)
 check(H.grantedRequests==before,'control: no read refresh while the pause holds: '..(H.grantedRequests-before))
 local e=Nexus.AutomationEffectiveState()
 check(e.state=='paused' and tostring(e.reason):find('auto-accept',1,true)~=nil
  and tostring(e.reason):find('nothing else pauses it',1,true)~=nil,
  'control: the effective state names the pause and keeps the conditional wait: '..tostring(e.reason))
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',false)
 before=H.grantedRequests;H.Advance(3)
 check(H.grantedRequests>before and H.selectAttempts==1,'control: refreshes resume once it clears; nothing was resent')
end)

scenario('L3b after an outside same-Echo Select the world hold no longer promises the exact grant and names what ends it',function(check)
 local H,A=R.Boot();R.AutoSubmit(H);R.Travel(H)
 local accepted=H.service.SelectPerk(R.X) -- the player's click on the same Echo, through the hooked client
 local attempts=H.boardAttempts
 H.Advance(.5);H.perks.pendingSelectSpellId=nil;H.Notify();H.Advance(1)
 local _,_,_,wait=A.SelectUnresolved()
 local allowed,why=Held(H)
 assert(accepted==false and wait=='ambiguous' and allowed==false and why:find(HELD,1,true),
  'setup: the outside same-Echo Select made the held own Select ambiguous: '..tostring(wait)..' / '..why)
 check(not why:find('ends with the exact grant',1,true),'the hold no longer says the exact grant ends it: '..why)
 check(NoGrantSettles(why),'it says that no grant can settle it now: '..why)
 check(why:lower():find('auto off and on',1,true)~=nil,'it names what still ends this hold (Auto off and on): '..why)
 check(not Rereads(why),'control: it names no read refresh: '..why)
 local before=H.grantedRequests;H.Advance(12)
 check(H.grantedRequests==before and H.boardAttempts==attempts,'control: no read refresh and nothing sent: '..(H.grantedRequests-before))
 SlashCmdList.NEXUS('auto');SlashCmdList.NEXUS('auto');H.Advance(4)
 local _,after=Held(H)
 local _,_,_,still=A.SelectUnresolved()
 local l,counts=F.Lifecycle()
 check(not after:find(HELD,1,true) and still=='ambiguous' and A.InFlight(),
  'control: Auto off and on ends only this hold; the own Select stays ambiguous and held: '..after)
 check(l.state=='uncertain' and l.reason=='player_resumed' and counts.confirmed==0,
  'control: the crossed Take stays unconfirmed: '..tostring(l.state)..'/'..tostring(l.reason))
 R.Grant(H,R.X);H.Advance(5)
 check(A.SelectOutcome(1)=='unresolved' and H.boardAttempts==attempts,'control: its exact grant cannot settle it; nothing is sent')
end)

------------------------------------------------------------------------
-- L4. The late-linked grant, no loading screen.
------------------------------------------------------------------------
-- Auto's Take; Auto OFF, so no newer decision replaces the lifecycle read;
-- the client flag clears and the board moves on without a grant; the
-- runtime's own step releases the Take as uncertain. Returns the lifecycle
-- counts from before that release.
local function LinkedUncertain(H,A)
 R.AutoSubmit(H);SlashCmdList.NEXUS('auto')
 local l,before=F.Lifecycle()
 assert(not H.Auto() and l.actionType=='take' and l.state=='submitted','setup: one automatic Take submitted, then Auto OFF')
 H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(1)
 l=F.Lifecycle()
 assert(l.actionType=='take' and l.state=='uncertain' and l.reason=='board_transition' and A.SelectOutcome(1)=='unresolved',
  'setup: the step released the Take as uncertain:board_transition, no grant yet: '..tostring(l.state)..'/'..tostring(l.reason))
 return before
end

scenario('L4 coverage: a Take left uncertain by a board change is confirmed once by its later exact grant, through the link',function(check)
 local H,A=R.Boot()
 local written=CountPerksWrites()
 local before=LinkedUncertain(H,A)
 R.Grant(H,R.X)
 assert(A.SelectOutcome(1)=='proven','setup: its exact grant with the flag clear proves the Select')
 H.Advance(1)
 local l,counts=F.Lifecycle()
 check(l.actionType=='take' and l.state=='confirmed' and l.reason=='grant_observed',
  'the late exact grant is its result: '..tostring(l.state)..'/'..tostring(l.reason))
 check(counts.uncertain==before.uncertain+1 and counts.confirmed==before.confirmed+1,
  'uncertain once, then confirmed once: '..(counts.uncertain-before.uncertain)..'/'..(counts.confirmed-before.confirmed))
 local io=F.TraceIo()
 check(Occurrences(io,'uncertain:board_transition')==1 and Occurrences(io,'confirmed:grant_observed')==1,'the roll record has each once: '..io)
 local decision,late
 for _,row in ipairs(Nexus.DiagnosticLogs.Snapshot('rollTrace')) do
  if row.k=='D' and tostring(row.sa):find('%.'..R.X..'$') then decision=row end
  if tostring(row.io):find('confirmed:grant_observed',1,true) then late=row end
 end
 check(decision~=nil and late~=nil and late.k=='O' and late.ref==decision.n,'it is a late row naming the Take decision: '
  ..tostring(late and late.k)..' ref='..tostring(late and late.ref)..' n='..tostring(decision and decision.n))
 R.Grant(H,R.X);H.Advance(3) -- a second exact rise
 l,counts=F.Lifecycle()
 check(counts.confirmed==before.confirmed+1 and Occurrences(F.TraceIo(),'confirmed:grant_observed')==1,
  'the link is used once: a later rise records nothing')
 check(H.selectAttempts==1 and H.boardAttempts==1 and H.Count(R.X)==1 and written()==0,'nothing resent; no client field is written')
 SlashCmdList.NEXUS('auto')
 for _=1,25 do H.Advance(.2);if H.Count(R.Y)>0 then break end end
 l,counts=F.Lifecycle()
 check(H.Count(R.Y)==1 and H.Count(R.X)==1 and counts.confirmed==before.confirmed+1,
  'control: Auto ON decides afresh on the current board; X is never resent')
end)

scenario('L4 control: the same linked Take voided by a run boundary is never confirmed, also after a later rise',function(check)
 local H,A=R.Boot()
 local written=CountPerksWrites()
 local before=LinkedUncertain(H,A)
 H.playerLevel=80;H.Advance(1);H.playerLevel=66;H.Advance(2) -- a recognised run boundary
 assert(A.SelectOutcome(1)=='voided','setup: the run boundary voided the own Select')
 local l,counts=F.Lifecycle()
 check(l.state~='confirmed' and counts.confirmed==before.confirmed and not F.TraceIo():find('confirmed:',1,true),
  'the void records no confirmation: '..tostring(l.state)..'/'..tostring(l.reason))
 R.Grant(H,R.X);H.Advance(3)
 l,counts=F.Lifecycle()
 check(A.SelectOutcome(1)=='voided' and A.SelectUnresolved()==nil and l.state~='confirmed'
  and counts.confirmed==before.confirmed and not F.TraceIo():find('confirmed:',1,true),
  'a later exact rise does not revive it: '..F.TraceIo())
 check(counts.uncertain==before.uncertain+1 and Occurrences(F.TraceIo(),'uncertain:board_transition')==1,'its uncertainty is recorded once')
 check(H.selectAttempts==1 and H.boardAttempts==1 and written()==0,'nothing resent; no client field is written')
end)
finish()
