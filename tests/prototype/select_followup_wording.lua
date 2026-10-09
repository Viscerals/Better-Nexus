-- Review F1, F10 and F7 (follow-up). F1: the unresolved own Select's wait
-- names read refreshes only while they could settle it (not once another
-- selection of the same Echo made it ambiguous), states the missing receipt
-- and that the wait can last the run, says what Auto off/on and a reload do,
-- and carries no spell ID or local ordinal. F10: the Auto tooltip shows an
-- Orb pause in the player's wording, not the raw gate code. F7: the
-- roll-record boundary of a recovered Select keeps whole fields within the
-- recorder's detail limit and marks the fields it leaves out. Real modules,
-- synthetic service.
local F=dofile('tests/prototype/select_followup_support.lua')
local R=F.R
local scenario,finish=R.Checks()
local function NoIds(text) return not text:find('200010',1,true) and not text:find('#',1,true) end

scenario('the wait names read refreshes only while they could settle it, and the run-long limit',function(check)
 local H,A=R.Boot();R.AutoSubmit(H)
 H.perks.pendingSelectSpellId=nil;H.Notify();H.Advance(1)
 local _,_,_,wait=A.SelectUnresolved()
 assert(wait=='grant','setup: the own Select waits for its grant: '..tostring(wait))
 local r=tostring(Nexus.AutomationEffectiveState().reason)
 check(r:find('re-reads the granted Echoes',1,true)~=nil,'a grant wait names the read refreshes: '..r)
 check(r:find('no receipt',1,true)~=nil and r:find('may never arrive',1,true)~=nil
  and r:find('until a new run',1,true)~=nil,'it states the missing receipt and that it can last the run: '..r)
 check(r:find('Auto off and on keeps it',1,true)~=nil and r:find('without learning or cancelling',1,true)~=nil,
  'it says what Auto off/on and a reload do: '..r)
 check(NoIds(r),'no spell ID or local ordinal: '..r)
 -- The player's Select of the same Echo: no later grant can settle it.
 H.service.SelectPerk(R.X);H.Advance(.5)
 _,_,_,wait=A.SelectUnresolved()
 assert(wait=='ambiguous','setup: an outside same-Echo Select makes it ambiguous: '..tostring(wait))
 r=tostring(Nexus.AutomationEffectiveState().reason)
 check(not r:find('re-read',1,true) and r:find('until a new run',1,true)~=nil,
  'an ambiguous wait names no refresh and keeps the run-long limit: '..r)
 check(NoIds(r),'no spell ID or local ordinal: '..r)
end)

scenario('the Auto tooltip shows an Orb pause in the player wording',function(check)
 local H,A=R.Boot();Nexus.Panel.Show();H.Offer();SlashCmdList.NEXUS('auto')
 ProjectEbonhold.OrbService={IsStateKnown=function() return false end,IsOfferPending=function() return false end}
 Nexus.RequestRecompute();H.Advance(1)
 local allowed,gate=H.runtime.AutoAllowed()
 assert(allowed==false and gate=='orb state not yet known','setup: the Orb gate pauses ordinary rolling: '..tostring(gate))
 assert(H.boardAttempts==0,'setup: nothing is sent')
 local worded=Nexus.UserText.Message(gate)
 local now=F.NowLine()
 check(now~=nil and now:find(worded,1,true)~=nil and not now:find(gate,1,true),
  'the tooltip uses the player wording ('..worded..'): '..tostring(now))
 ProjectEbonhold.OrbService=nil
end)

scenario('a roll-record boundary keeps whole fields within its limit and marks an omission',function(check)
 local H,A=R.Boot();H.Offer()
 local copies={}
 for i=1,10000 do copies[i]={spellId=R.X,quality=2} end
 H.granted=H.Clone(H.granted);H.granted['Echo 10']=copies;H.Notify();A.Poll()
 assert(A.GrantedCount(R.X)==10000,'setup: ten thousand earlier copies are visible')
 assert(A.Take(R.X)==true,'setup: one Select is sent')
 H.Advance(12) -- past its watchdog: its outcome is a recovered one
 R.Grant(H,R.X);H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(.5)
 assert(A.SelectOutcome(1)=='proven','setup: its exact grant proves it')
 local detail
 for _,row in ipairs(Nexus.DiagnosticLogs.Snapshot('rollTrace')) do
  if row.k=='B' and row.kind=='select_recovery' then detail=row.d end
 end
 detail=tostring(detail)
 check(#detail<=Nexus.RollRecorder.LIMITS.detailBytes,'within the detail limit: '..#detail..' bytes: '..detail)
 check(detail=='proven L#1 spell 200010 pre 10000 now 10001 ...',
  'whole fields; the fields that do not fit are left out and marked: '..detail)
end)
finish()
