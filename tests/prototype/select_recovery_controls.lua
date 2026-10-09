-- Compact controls for the bounded ordinary Select recovery, through the real
-- adapter, runtime, panel, roll record and support report with the synthetic
-- service (no game or private data). Each scenario pins one rule:
--  1 before the watchdog, a visible grant waits for the client's flag, and the
--    watchdog text reports the grant it saw, never its absence;
--  2 an outside same-spell Select keeps any number of rises ambiguous;
--  3 a later Select flag of another spell blocks settlement past its watchdog;
--  4 a run boundary voids the Select (not proven) and keeps Select admission
--    closed while its flag is still set;
--  5 an unreadable Perks table is not a cleared flag;
--  6 a short loading screen answered before the watchdog resumes once;
--  7 repeated world events coalesce: one record, paced rechecks, no resend;
--  8 an outside Select flag or a refused automatic Take reads as a wait;
--  9 passive display and report reads call nothing and change no authority;
--    the heading names the wait, the button the selection, and the roll
--    record and report keep the evidence.
local R=dofile('tests/prototype/select_recovery_support.lua')
local scenario,finish=R.Checks()
local function Plain(text) return ((text or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end

scenario('a grant visible before the watchdog waits for the client flag',function(check)
 local H,A=R.Boot();H.Offer();assert(A.Take(R.X))
 H.Advance(2);R.Grant(H,R.X);H.Advance(9)
 local said
 for _,line in ipairs(H.chat) do if line:find('Select still unresolved after 10s',1,true) then said=line end end
 check(said~=nil and said:find('a matching grant is visible',1,true)~=nil and not said:find('not visible',1,true),
  'the watchdog text reports the visible grant, never its absence: '..tostring(said))
 check(A.InFlight()==true and H.perks.pendingSelectSpellId==R.X,'with the flag still set it stays unresolved; no native write')
 local before=H.selectAttempts;A.Take(R.Y)
 check(H.selectAttempts==before,'no Select reaches the client while the flag is set')
 H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(.2)
 check(A.InFlight()==false and (A.Owned().bySpell[R.X] or 0)==1,'once the flag clears the exact grant settles it, counted once')
end)

scenario('an outside same-spell Select stays ambiguous after two exact rises',function(check)
 local H,A=R.Boot();H.Offer();assert(A.Take(R.X))
 H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(.2)
 H.Offer(R.initial);H.service.SelectPerk(R.X) -- an outside Select of the same spell
 check(H.perks.pendingSelectSpellId==R.X,'fixture: the client accepted the outside Select')
 R.Grant(H,R.X);H.perks.pendingSelectSpellId=nil;H.Advance(.2);R.Grant(H,R.X);H.Advance(.2)
 check(A.GrantedCount(R.X)==2,'fixture: two exact rises are visible')
 check(A.InFlight()==true,'no number of rises settles a Select an outside same-spell Select made ambiguous')
 local before=H.selectAttempts;A.Take(R.Y)
 check(H.selectAttempts==before,'and nothing new reaches the client')
end)

scenario('a later Select flag of another spell blocks settlement past its watchdog',function(check)
 local H,A=R.Boot();H.Offer();assert(A.Take(R.X))
 H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(.2)
 H.service.SelectPerk(R.Y) -- another spell's Select, accepted
 check(H.perks.pendingSelectSpellId==R.Y,'fixture: the other Select holds the client flag')
 H.Advance(12);R.Grant(H,R.X);H.Advance(.2)
 check(A.InFlight()==true,'its exact grant does not settle while another Select flag is set, even past its watchdog')
 local before=H.selectAttempts;A.Take(R.Z)
 check(H.selectAttempts==before,'no Select reaches the client meanwhile')
 H.perks.pendingSelectSpellId=nil;H.Advance(.2)
 check(A.InFlight()==false,'the flag clears: the exact grant settles the own Select')
end)

scenario('a run boundary voids the Select and keeps admission closed while its flag is set',function(check)
 local H,A=R.Boot();H.Offer();assert(A.Take(R.X));H.Advance(12)
 A.RunBoundaryReset()
 local facts=A.SelectRecoveryFacts()
 local last=facts.outcomes[#facts.outcomes]
 check(facts.unresolved==nil and last and last.outcome=='voided','the run boundary voids it; it is not proven')
 check((A.Owned().bySpell[R.X] or 0)==0,'and nothing of it is owned')
 local before=H.selectAttempts;A.Take(R.X)
 check(A.InFlight()==true and H.selectAttempts==before,'its still-set flag keeps Select admission closed')
 H.perks.pendingSelectSpellId=nil;H.Advance(.2)
 check(A.InFlight()==false and A.Take(R.X)==true and H.selectAttempts==before+1,'once the flag clears a new Select is admitted')
end)

scenario('an unreadable Perks table is not a cleared Select flag',function(check)
 local H,A=R.Boot();H.Offer();assert(A.Take(R.X))
 H.granted=H.Clone(H.granted);H.granted['Echo 10']={{spellId=R.X,quality=2}} -- the grant is visible
 local perks=ProjectEbonhold.Perks;ProjectEbonhold.Perks=nil
 pcall(A.Poll)
 ProjectEbonhold.Perks=perks
 local ordinal,phase,_,wait=A.SelectUnresolved()
 check(ordinal~=nil and phase=='latch' and A.SelectOutcome(ordinal)=='unresolved',
  'a visible grant does not settle it while no Perks table can be read: '..tostring(phase)..'/'..tostring(wait))
 A.Poll()
 check(A.InFlight()==true and A.SelectOutcome(ordinal)=='unresolved','restored with its flag still set: still unresolved')
 H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(.2)
 check(A.InFlight()==false and A.SelectOutcome(ordinal)=='proven','a readable table with no flag lets the exact grant settle it')
end)

scenario('a short loading screen answered before the watchdog resumes once',function(check)
 local H,A=R.Boot();R.AutoSubmit(H)
 H.Advance(.1);H.Fire('PLAYER_LEAVING_WORLD');H.Advance(1);H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1)
 R.Grant(H,R.X);H.perks.pendingSelectSpellId=nil;H.Offer(R.next)
 check(H.Count()==1,'nothing is sent inside the settle')
 H.Advance(4)
 check(H.Auto() and H.Count(R.Y)==1 and H.Count(R.X)==1 and H.selectAttempts==2,
  'its exact grant resumes one fresh decision after the settle; the old choice is not replayed')
end)

scenario('repeated world events coalesce on one unresolved Select',function(check)
 local H,A=R.Boot();R.AutoSubmit(H)
 for _=1,3 do H.Advance(.2);H.Fire('PLAYER_LEAVING_WORLD');H.Advance(.5);H.Fire('PLAYER_ENTERING_WORLD') end
 local before=H.grantedRequests;H.Advance(60)
 local own=A.SelectRecoveryFacts().unresolved
 check(own~=nil and own.ordinal==1 and own.entries==3,'every entry is counted on the one unresolved Select: '..tostring(own and own.entries))
 local sent=H.grantedRequests-before
 check(sent>=2 and sent<=8,'settled rechecks run, paced and coalesced: '..sent..' in 60 s')
 check(H.selectAttempts==1 and H.Count()==1 and H.Auto(),'nothing is resent and Auto stays selected')
end)

scenario('an outside Select flag and a refused automatic Take read as waits',function(check)
 local H,A=R.Boot();H.Offer();H.perks.pendingSelectSpellId=R.Z -- the player's own Select, unanswered
 SlashCmdList.NEXUS('auto');H.Advance(1)
 local e=Nexus.AutomationEffectiveState()
 check(H.Count()==0 and e.selected==true and e.state=='waiting',
  'an outside Select flag: selected, nothing sent, waiting: '..tostring(e.state)..' / '..tostring(e.reason))
 H.perks.pendingSelectSpellId=nil
 local real=H.service.SelectPerk;H.service.SelectPerk=function() return false end -- the client refuses
 H.Notify();H.Advance(1.5)
 H.service.SelectPerk=real
 e=Nexus.AutomationEffectiveState()
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='rejected' and e.state=='waiting',
  'a refused automatic Take still holds this choice and reads as a wait: '..tostring(e.state)..' / '..tostring(e.reason))
end)

scenario('passive reads call nothing; the heading names the wait; the evidence is kept',function(check)
 local H,A=R.Boot();Nexus.Panel.Show();R.AutoSubmit(H)
 local function Head() return Plain(NexusPanel._rollStatus:GetText()) end
 local function Button() return Plain(NexusPanel._autoBtn:GetText()) end
 H.Advance(.1);H.Fire('PLAYER_LEAVING_WORLD');Nexus.RequestRecompute();H.Advance(1)
 check(Head()=='Auto ON — paused' and Button()=='Auto ON','loading: the paused heading; the button shows the selection: '..Head()..' / '..Button())
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1)
 -- Inside the settle, the Select unresolved: every client service, adapter
 -- gate and getter is counted, and so is every Perks field read.
 local calls,reads,service,adapter=0,0,{},{}
 for name,fn in pairs(H.service) do
  if type(fn)=='function' then service[name]=fn;H.service[name]=function(...)calls=calls+1;return fn(...)end end
 end
 for _,k in ipairs({'InFlight','PendingActions','UnconfirmedLatch','GrantedCount','Owned','RequestGranted','RecheckSelect',
  'Take','Ready','RivalDetected','AutoAcceptOn','OrdinaryBoardAllowed','Board','Poll'}) do
  local fn=A[k];if type(fn)=='function' then adapter[k]=fn;A[k]=function(...)calls=calls+1;return fn(...)end end
 end
 local perks=ProjectEbonhold.Perks
 ProjectEbonhold.Perks=setmetatable({},{__index=function(_,k)reads=reads+1;return perks[k] end})
 local lines={}
 rawset(GameTooltip,'AddLine',function(_,text)lines[#lines+1]=tostring(text)end)
 local ok,facts,effective=pcall(function()
  NexusPanel._autoBtn.scripts.OnEnter(NexusPanel._autoBtn)
  return A.SelectRecoveryFacts(),Nexus.AutomationEffectiveState()
 end)
 rawset(GameTooltip,'AddLine',nil)
 ProjectEbonhold.Perks=perks
 for k,fn in pairs(adapter) do A[k]=fn end
 for k,fn in pairs(service) do H.service[k]=fn end
 check(ok and calls==0 and reads==0,'passive reads call no client service, gate or getter and read no Perks field: calls='
  ..calls..' reads='..reads..' '..tostring(ok or facts))
 local own=ok and facts.unresolved
 check(own and own.ordinal==1 and own.spellId==R.X and own.baseline==0 and own.entries==1,'the facts are the one unresolved Select with its provenance')
 check(ok and effective.selected==true and effective.state=='paused' and tostring(effective.reason):find('settling',1,true)~=nil,
  'selected, and the effective state is the settle pause: '..tostring(ok and effective.state))
 local now
 for _,line in ipairs(lines) do if line:find('^Now: ') then now=line end end
 check(now~=nil and not now:find('200010',1,true) and not now:find('#',1,true),'the tooltip names the effective state in plain words: '..tostring(now))
 check(Nexus.AutomationEffectiveState().state=='paused','the passive reads did not end the settle')
 H.Advance(3)
 check(Head()=='Auto waiting' and Button()=='Auto ON','after the settle the heading names the wait: '..Head())
 H.Advance(6)
 check(Head()=='Auto rechecking' and Nexus.AutomationEffectiveState().rechecks>=1,'with read refreshes sent it names the rechecks: '..Head())
 R.Grant(H,R.X);H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(3)
 check(H.Count(R.Y)==1 and H.Count(R.X)==1 and H.selectAttempts==2,'proof resumes one fresh decision; the old choice is not replayed')
 local trace=Nexus.RollRecorder.Export()
 check(trace:find('select_recovery',1,true)~=nil and trace:find('proven L#1 spell 200010 pre 0 now 1 e1',1,true)~=nil,
  'the roll record notes the recovered Select: local ordinal, exact spell, counts and entries')
 local before=H.grantedRequests
 local report=Nexus.SupportReport.Prepare({})
 local text=report and table.concat(report.chunks) or ''
 check(H.grantedRequests==before and H.selectAttempts==2,'preparing the report requests nothing')
 check(text:find('-- ordinary Select recovery (memory only',1,true)~=nil and text:find('local #1 spell=200010',1,true)~=nil
  and text:find('outcome=proven',1,true)~=nil and text:find('not a server token',1,true)~=nil,
  'the report keeps the resolved facts, labelled as local provenance')
end)
finish()
