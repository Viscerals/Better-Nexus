-- Follow-ups from the second reported RDF case (test.9051): an Orb choice
-- whose reply the game lost at a loading screen. Real Store, OrbRuntime,
-- OrbAdapter, GameAdapter and SupportReport; only the game services are
-- synthetic.
--
-- A. After a reload the player can choose before Nexus has read anything, so
--    the first ownership read already shows the chosen Echo and is not newer
--    than the recovery baseline. When that exact result is the only thing
--    missing, recovery asks the game ONCE, read-only (the Recheck request),
--    for a newer ownership response. It never asks for anything else, never
--    asks twice, and settlement stays exactly as strict.
-- B. While the game itself still holds the earlier choice after a loading
--    screen, the status says so and names the Echo to choose after /reload.
-- C. The support summary and the prepared report state the Orb action.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 return H,H.M,H.A,H.O
end
local function Receipt()return Nexus.Store.State().orbRefinement.pending end
local function Loadouts(H,A)
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
  [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 assert(A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410002,quality=2,stacks=2}}))
end
local function Owned(H,source,gainId,gainQ)
 local out=H.Clone(H.granted);local removed=false
 for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
 assert(removed,'fake server removes one actual source stack')
 if gainId then local n=H.names[gainId];out[n]=out[n] or {};table.insert(out[n],{spellId=gainId,quality=gainQ}) end
 return out
end
local function CountCalls(H)
 local calls={select=0,spend=0,player=0}
 local rawSelect=H.service.SelectPerk
 H.service.SelectPerk=function(...)calls.select=calls.select+1;return rawSelect(...)end
 local orb=ProjectEbonhold.OrbService;local rawSpend=orb.ConfirmSpend
 orb.ConfirmSpend=function(...)calls.spend=calls.spend+1;return rawSpend(...)end
 calls.pick=function(id)calls.player=calls.player+1;return H.service.SelectPerk(id)end
 return calls
end
local function NothingSent(H,calls,where)
 check(calls.spend==0 and calls.select==calls.player,where..': no Orb spend and no automatic choice (spend='..calls.spend..', select='..calls.select..'/'..calls.player..')')
 check(H.Count('orb-spend')==1,where..': exactly the one original Orb spend reached the game')
end
local function Reload(H)
 H.Fire('PLAYER_LOGOUT')
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 H.perks.pendingSelectSpellId=nil -- the game client's Lua restarts too
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 return Nexus.OrbRuntime
end
-- A normal run: one spend, the offer, Nexus's choice sent and observed; then a
-- loading screen during which the game's reply to that choice is lost.
local function LostReply()
 local H,M,A,O=Fresh()
 Loadouts(H,A)
 assert(M.Start(3));local source=O.source
 H.Offer();H.Advance(.5)
 local r=Receipt()
 check(r.spendConfirmed and r.choiceMayHaveBeenSent and r.choiceObserved and r.selectedKey=='410002:2','setup: confirmed spend, choice sent and observed')
 check(H.perks.pendingSelectSpellId==410002,'setup: the game holds the choice')
 H.Fire('PLAYER_LEAVING_WORLD');H.Advance(.5);H.Fire('PLAYER_ENTERING_WORLD')
 return H,M,A,O,source
end
local function Lines(text)local out={};for l in (text..'\n'):gmatch('(.-)\n')do out[#out+1]=l end;return out end
local function OrbLine(text)for _,l in ipairs(Lines(text))do if l:find('Orb action:',1,true)then return l end end end
local function Report()
 local report,err,job=Nexus.SupportReport.Prepare({extended=false})
 assert(report,err);return table.concat(job.lines,'\n')
end

-- A1. The player chose right after the reload; the exact result is already in
-- the first ownership read. One automatic read-only refresh settles it.
do
 local H,M,A,O,source=LostReply()
 H.Advance(2)
 M=Reload(H);local calls=CountCalls(H)
 local requests=O.requests
 -- Before Nexus reads anything: the player chooses and the game applies it.
 check(calls.pick(410002)==true,'A1: after the reload the game accepts the choice')
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.granted=Owned(H,source,410002,2);H.Notify();A.Poll()
 H.Advance(2)
 local s=M.Status()
 check(not s.pending and s.state=='STOPPED' and Receipt()==nil,
  'A1: settles from one automatic ownership refresh, without Recheck: '..tostring(s.state)..' / '..tostring(s.reason))
 check(O.requests-requests==1,'A1: exactly one read-only refresh was requested (requests='..(O.requests-requests)..')')
 check(s.spent==1 and s.reserved==0,'A1: usage is the one Orb')
 NothingSent(H,calls,'A1')
 H.Advance(30)
 check(O.requests-requests==1,'A1: no further automatic request after settlement')
 check(OrbLine(Nexus.SupportReport.Summary())=='Orb action: none unresolved','C: after settlement the summary says no Orb action is unresolved: '..tostring(OrbLine(Nexus.SupportReport.Summary())))
end
-- A2. The refresh gets no answer: exactly one request, a truthful wait, and
-- Recheck still works. The support summary and the report state the action.
do
 local H,M,A,O,source=LostReply()
 H.Advance(2)
 M=Reload(H);local calls=CountCalls(H)
 local requests=O.requests
 check(calls.pick(410002)==true,'A2: the player chooses')
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.granted=Owned(H,source,410002,2);H.holdGrantedResponse=true;H.Notify();A.Poll()
 H.Advance(30)
 local s=M.Status()
 check(s.pending and s.recovery.kind=='WAIT_RESULT' and s.recovery.gate and s.recovery.gate.gate=='fresh','A2: waits for a fresh response: '..tostring(s.reason))
 check(O.requests-requests==1,'A2: the automatic refresh is requested once, not repeated (requests='..(O.requests-requests)..')')
 check(s.reason:find('asked the game once',1,true)~=nil and s.reason:find('Recheck requests one more',1,true)~=nil
  and s.reason:find('No Orb and no choice',1,true)~=nil,'A2: the status says what was asked and what Recheck does: '..s.reason)
 check(M.BlocksOrdinary() and not M.Resume() and not M.Prepare(),'A2: ordinary rolling blocked; no Resume, no new run')
 local line=OrbLine(Nexus.SupportReport.Summary())
 check(line and line:find('unresolved after a reload',1,true) and line:find('recovery=WAIT_RESULT',1,true)
  and line:find('waiting for=fresh',1,true),'C: the summary states the unresolved Orb action and its requirement: '..tostring(line))
 local detail=Nexus.SupportReport.Summary():match('Orb action:[^\n]*\n([^\n]*)')
 check(detail and detail:find('spend confirmed=yes',1,true) and detail:find('choice=sent,observed',1,true)
  and detail:find('selected=410002:2',1,true) and detail:find('automatic refresh=requested',1,true)
  and detail:find('loadout change recorded=no',1,true),'C: the second line gives the evidence state: '..tostring(detail))
 check(not Nexus.SupportReport.Summary():find('PrototypeTester',1,true),'C: no character name in the summary')
 check(OrbLine(Report())==line,'C: the prepared report carries the same Orb line')
 NothingSent(H,calls,'A2')
 H.holdGrantedResponse=false;H.now=H.now+4;M.Recheck();H.Advance(1)
 check(not M.Status().pending and M.Status().state=='STOPPED','A2: Recheck then settles')
 NothingSent(H,calls,'A2 after Recheck')
end
-- A3. The first read shows a different Echo: not the exact result, so no
-- automatic request; Recheck then shows the mismatch, as before.
do
 local H,M,A,O,source=LostReply()
 H.Advance(2)
 M=Reload(H);local calls=CountCalls(H)
 local requests=O.requests
 check(calls.pick(410004)==true,'A3: the player chooses another Echo')
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.granted=Owned(H,source,410004,3);H.Notify();A.Poll()
 H.Advance(10)
 check(M.Status().pending and O.requests==requests,'A3: no automatic request when the ownership is not the recorded result')
 check(M.Status().reason:find('asked the game once',1,true)==nil,'A3: the status does not claim a request that was not made: '..M.Status().reason)
 H.now=H.now+4;M.Recheck();H.Advance(1)
 check(M.Status().pending and M.Status().reason:find('does not match',1,true)~=nil,'A3: Recheck shows the mismatch; the action stays unresolved')
 NothingSent(H,calls,'A3')
end
-- A4. The ownership response is newer than the baseline: settles without any
-- request (the automatic refresh is only for the stale first read).
do
 local H,M,A,O,source=LostReply()
 H.Advance(2)
 M=Reload(H);local calls=CountCalls(H)
 local requests=O.requests
 H.Advance(1)
 check(M.Status().recovery.gate and M.Status().recovery.gate.gate=='offer','A4: the offer is still open after the reload')
 local text=M.Status().reason
 check(text:find('Desired A',1,true)~=nil and text:find('different Echo',1,true)~=nil and text:find('will not choose or spend',1,true)~=nil,
  'A4: while the recorded offer is open after the reload, the status names the Echo to choose: '..text)
 check(calls.pick(410002)==true,'A4: the player chooses');H.Advance(.5)
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.granted=Owned(H,source,410002,2);H.Notify();A.Poll();H.Advance(1)
 check(not M.Status().pending and O.requests==requests,'A4: a newer ownership response settles it with no request')
 NothingSent(H,calls,'A4')
end

-- B1. In the same session: the game still holds the choice after the loading
-- screen. After a short wait the status names the Echo and the /reload route.
do
 local H,M,A,O,source=LostReply()
 H.Advance(2)
 local s=M.Status()
 check(s.state=='PAUSED' and s.reason:find('Session interrupted',1,true)~=nil,'B1: right after the loading screen: '..s.reason)
 H.Advance(6)
 s=M.Status()
 check(s.state=='PAUSED' and s.pending,'B1: still paused and unresolved')
 check(s.reason:find('still waiting for its reply',1,true)~=nil and s.reason:find('/reload',1,true)~=nil
  and s.reason:find('Desired A',1,true)~=nil and s.reason:find('different Echo',1,true)~=nil,
  'B1: the status names the waiting game choice, the Echo and /reload: '..s.reason)
 check(H.Count('orb-spend')==1 and H.Count('take')==1,'B1: nothing sent')
 local line=OrbLine(Nexus.SupportReport.Summary())
 local detail=Nexus.SupportReport.Summary():match('Orb action:[^\n]*\n([^\n]*)')
 check(line and line:find('unresolved in this session',1,true) and detail and detail:find('game pick in flight=yes',1,true),
  'C: the summary shows the in-session action and the game pick in flight: '..tostring(line)..' / '..tostring(detail))
 -- The reply arrives late after all: the operation settles as usual.
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.granted=Owned(H,source,410002,2);H.Notify();A.Poll();H.Advance(1)
 s=M.Status()
 check(M.RunLog().entries[1].state=='confirmed' and s.reason:find('still waiting for its reply',1,true)==nil,'B1: the late reply confirms it; the hint is gone: '..s.reason)
end
-- B4. The game's reply clears its latch, but the ownership response has not
-- arrived: the /reload advice is withdrawn at once.
do
 local H,M,A,O=LostReply()
 H.Advance(8)
 check(M.Status().reason:find('/reload',1,true)~=nil,'B4 setup: the held-choice text is shown')
 H.holdGrantedResponse=true
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false;H.Notify();A.Poll();H.Advance(1)
 local s=M.Status()
 check(s.pending and s.reason:find('/reload',1,true)==nil and s.reason:find('Session interrupted',1,true)~=nil,
  'B4: once the game no longer holds the choice, the /reload advice is gone: '..s.reason)
end
-- B5. Another pause reason is never replaced by the hint: the assigned
-- Wishlist changes during the loading screen.
do
 local H,M,A,O=LostReply()
 local ok=A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410004,quality=3,stacks=1}})
 H.Notify();A.Poll();H.Advance(8)
 local reason=M.Status().reason
 check(ok and reason:find('assigned Wishlist changed',1,true)~=nil,'B5 setup: the assignment change pauses the run: '..tostring(ok)..' / '..reason)
 check(reason:find('/reload',1,true)==nil,'B5: the held-choice text does not replace another pause reason: '..reason)
end
-- B6. The game still holds the choice, but no Orb offer is owed any more:
-- no /reload advice (it would not open an offer).
do
 local H,M,A,O=LostReply()
 O.offer=false;H.Advance(8)
 check(M.Status().reason:find('/reload',1,true)==nil,'B6: without an owed offer there is no /reload advice: '..M.Status().reason)
end
-- B2. The game holds a different choice: not this action's; no hint.
do
 local H,M,A,O=LostReply()
 H.perks.pendingSelectSpellId=410004
 H.Advance(8)
 check(M.Status().reason:find('/reload',1,true)==nil,'B2: another game choice in flight gives no /reload hint: '..M.Status().reason)
end
-- B3. No loading screen: a long wait for the reply keeps the existing timeout
-- behaviour and gives no /reload hint.
do
 local H,M,A,O=Fresh()
 Loadouts(H,A)
 assert(M.Start(3));H.Offer();H.Advance(40)
 local s=M.Status()
 check(s.pending and s.reason:find('/reload',1,true)==nil,'B3: without a loading screen there is no /reload hint: '..s.reason)
end
-- C2. The report line from a failing or hostile Orb owner: bounded, no
-- control bytes, and never the reason the summary is lost.
do
 local H,M,A,O=Fresh()
 local runtime=Nexus.OrbRuntime;local real=runtime.RecoveryView
 local POISON='SENTINEL'..string.char(1)..string.char(10)..string.char(7)..'|cffff0000|r'..string.rep('Z',300)
 runtime.RecoveryView=function()return {pending=true,restored=POISON,state=POISON,recovery=POISON,gate=POISON,
  spendConfirmed=POISON,choiceSent=POISON,choiceObserved=true,selectedKey=POISON,removed=POISON,
  loadoutChanged=POISON,pickInFlight=POISON,autoRefresh=POISON} end
 local summary=Nexus.SupportReport.Summary()
 local first=OrbLine(summary);local second=summary:match('Orb action:[^\n]*\n([^\n]*)')
 check(first and second,'C2: the poisoned view still gives the two Orb lines')
 for _,l in ipairs({first,second})do
  check(not l:find('[%z\1-\31]') and #l<400 and not l:find(string.rep('Z',30),1,true),'C2: bounded, no control bytes: '..#l)
 end
 check(second:find('spend confirmed=no',1,true) and second:find('game pick in flight=unknown',1,true)
  and second:find('automatic refresh=not requested',1,true) and first:find('in this session',1,true),
  'C2: a non-boolean flag is never reported as yes: '..first..' / '..second)
 runtime.RecoveryView=function()error('hostile owner')end
 check(OrbLine(Nexus.SupportReport.Summary())=='Orb action: not available (the Orb owner did not answer)','C2: a throwing owner gives the not-available line')
 runtime.RecoveryView=function()return setmetatable({},{__index=function()error('hostile index')end})end
 check(OrbLine(Nexus.SupportReport.Summary())=='Orb action: not available (the Orb owner did not answer)','C2: a hostile answer gives the not-available line')
 runtime.RecoveryView=real
end
print('PASS Orb RDF follow-ups: one automatic read-only refresh after reload, /reload hint for a held game choice, Orb action in the support report checks='..checks)
