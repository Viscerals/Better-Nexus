-- Review F4: Select admission reads the client's Select flag. A player's
-- Select flag that outlived the watchdog is still a set flag: the adapter
-- refuses before calling a client that would accept a Select while flagged
-- (the harness client refuses; the fixture swaps in one that accepts). A
-- Perks table that cannot be read is not admission; a readable table with no
-- flag admits exactly one Select. The client's fields are never written.
-- Review F11: a genuine outside Select, Banish, Freeze or Reroll while the own
-- Select is retained past its watchdog is logged and gets the existing
-- user-acting pause; the own Select keeps its tracking, a different-spell
-- Select is not counted as competing, and the adapter's own calls are never
-- logged as the player's. Real modules, synthetic service.
local F=dofile('tests/prototype/select_followup_support.lua')
local R=F.R
local scenario,finish=R.Checks()

local function PlayerFlagPastWatchdog()
 local H,A=R.Boot();H.Offer()
 assert(H.service.SelectPerk(R.X)==true,'setup: the player Select of X is accepted')
 H.Advance(12)
 assert(H.perks.pendingSelectSpellId==R.X and A.SelectUnresolved()==nil,'setup: its flag is still set past the watchdog; no own Select')
 return H,A
end

for _,target in ipairs({R.X,R.Z}) do
 scenario('a player Select flag past its watchdog refuses an own Select of '..(target==R.X and 'the same' or 'another')..' Echo before the client call',function(check)
  local H,A=PlayerFlagPastWatchdog()
  local calls=F.AcceptingSelect(H)
  local ok=A.Take(target)
  check(ok~=true and calls()==0,'refused before the client is called: ok='..tostring(ok)..' calls='..calls())
  check(A.SelectUnresolved()==nil and A.SelectRecoveryFacts().submitted==0,'no own Select is recorded')
  check(H.perks.pendingSelectSpellId==R.X,"the client flag is still the player's: "..tostring(H.perks.pendingSelectSpellId))
 end)
end

scenario('an unreadable Perks table is not Select admission',function(check)
 local H,A=R.Boot();H.Offer()
 local calls=F.AcceptingSelect(H)
 local perks=ProjectEbonhold.Perks;ProjectEbonhold.Perks=nil
 local ok,err=pcall(A.Take,R.X)
 ProjectEbonhold.Perks=perks
 check(ok and calls()==0,'no Select is sent while the client flag cannot be read: calls='..calls()..' '..tostring(ok or err))
 check(A.SelectUnresolved()==nil,'no own Select is recorded')
end)

scenario('control: a readable table with no Select flag admits exactly one Select',function(check)
 local H,A=R.Boot();H.Offer()
 local calls=F.AcceptingSelect(H)
 check(A.Take(R.X)==true and calls()==1 and A.SelectUnresolved()==1,'admitted and tracked once: calls='..calls())
 check(A.Take(R.Z)~=true and calls()==1,'no second Select while it is unresolved')
end)

scenario('Auto sends no Select to a client that would accept while a player flag is set',function(check)
 local H,A=R.Boot();H.Offer()
 assert(H.service.SelectPerk(R.X)==true,'setup: the player Select of X is accepted')
 local calls=F.AcceptingSelect(H)
 SlashCmdList.NEXUS('auto');H.Advance(15)
 assert(H.Auto(),'setup: Auto stays selected')
 check(calls()==0,'no automatic Select reaches the client while the player flag is set, past its watchdog: '..calls())
 check(A.SelectUnresolved()==nil and H.perks.pendingSelectSpellId==R.X,"no own Select; the flag is the player's")
 local e=Nexus.AutomationEffectiveState()
 check(e.state=='waiting','the effective state is a wait: '..tostring(e.state)..' / '..tostring(e.reason))
end)

scenario('outside board actions during a retained own Select are logged and pause automation',function(check)
 local H,A=R.Boot();R.AutoSubmit(H);H.Advance(12)
 local ordinal,phase,_,_,_,overdue=A.SelectUnresolved()
 assert(ordinal==1 and phase=='latch' and overdue and H.perks.pendingSelectSpellId==R.X,
  'setup: the own Select is retained past its watchdog with its flag set')
 check(#F.UserActions()==0 and H.runtime.AutoAllowed()==true,'the own automatic Take is not a player action and starts no pause')
 local acts={
  {'SelectPerk',function() return H.service.SelectPerk(R.Z) end},
  {'BanishPerk',function() return H.service.BanishPerk(1) end,'pendingBanishIndex'},
  {'FreezePerk',function() return H.service.FreezePerk(2) end,'pendingFreezeIndex'},
  {'RequestReroll',function() return H.service.RequestReroll() end,'pendingReroll'},
 }
 for i,act in ipairs(acts) do
  act[2]()
  if act[3] then H.perks[act[3]]=nil end -- the client answers at once (fixture)
  H.Advance(.5)
  local logged=F.UserActions()
  check(#logged==i and tostring(logged[i]):find(act[1],1,true)==1,'the outside '..act[1]..' is logged: '..table.concat(logged,','))
  local allowed,why=H.runtime.AutoAllowed()
  check(allowed==false and tostring(why):find('user acting',1,true)~=nil,'the outside '..act[1]..' gets the user-acting pause: '..tostring(why))
  local own=A.SelectRecoveryFacts().unresolved
  check(own~=nil and own.ordinal==1 and own.competing==0 and A.InFlight(),
   'the own Select keeps its tracking and is not competing: '..tostring(own and own.competing))
  H.Advance(3.5)
 end
 check(H.Count()==1 and H.perks.pendingSelectSpellId==R.X,'nothing was resent; the client flag is untouched')
 R.Grant(H,R.X);H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(3)
 check(A.SelectOutcome(1)=='proven' and H.Count(R.Y)==1,'its exact grant still settles it, then one fresh Take')
 local selfLogged=false
 for _,u in ipairs(F.UserActions()) do if u==('SelectPerk:'..R.Y) then selfLogged=true end end
 check(not selfLogged,'the automatic Take is not logged as a player action')
end)
finish()
