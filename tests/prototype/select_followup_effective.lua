-- Review F2: an overdue own Select whose read refreshes have started, then a
-- pause that is not that Select's own wait -- client auto-accept, a rival
-- add-on, an unknown Orb state, the player acting on the board. While it
-- holds: the effective state is paused, its reason names that pause and keeps
-- the unresolved Select; the heading, the Auto tooltip and the support report
-- say paused, not rechecking; no read refresh is sent. Paced refreshes resume
-- once it clears. The display and report reads call no client service,
-- adapter gate or getter. Real modules, synthetic service.
local F=dofile('tests/prototype/select_followup_support.lua')
local R=F.R
local scenario,finish=R.Checks()

local function Pause(name,apply,hold,clear)
 scenario(name,function(check)
  _G.EchoOptimizer=nil -- no rival left over from an earlier scenario
  local H,A=R.Boot();Nexus.Panel.Show()
  local wait,worded=F.Rechecking(H,A)
  apply(H)
  Nexus.RequestRecompute();H.Advance(.5)
  local allowed,gate=H.runtime.AutoAllowed()
  assert(allowed==false and type(gate)=='string','setup: the ordinary gate reports the pause: '..tostring(gate))
  local calls,reads,ok,e,now,facts=F.Passive(A,function()
   local line=F.NowLine()
   return Nexus.AutomationEffectiveState(),line,A.SelectRecoveryFacts()
  end)
  check(ok and #calls==0 and reads==0,'the effective state, the Auto tooltip and the facts are memory-only reads: '
   ..table.concat(calls,',')..' reads='..reads..' '..tostring(ok or e))
  e=ok and e or {}
  local reason=tostring(e.reason)
  check(e.selected==true and e.state=='paused','selected, and the effective state is paused: '..tostring(e.state)..' / '..reason)
  check(reason~=wait and (reason:find(wait,1,true)~=nil or (worded~=nil and reason:find(worded,1,true)~=nil)),
   'the reason keeps the unresolved Select wait whole: '..reason)
  check(reason:find(gate,1,true)~=nil or reason:find(Nexus.UserText.Message(gate),1,true)~=nil,
   'the reason names the pause the gate reports ('..gate..'): '..reason)
  check(now~=nil and now:find('paused',1,true)~=nil and not now:find('rechecking',1,true),'the Auto tooltip says paused: '..tostring(now))
  local head=F.Head()
  check(head:find('paused',1,true)~=nil and not head:find('rechecking',1,true),'the heading says paused: '..head)
  check(ok and facts.unresolved~=nil and facts.unresolved.ordinal==1,'the own Select is still the unresolved one')
  local requests,attempts=H.grantedRequests,H.boardAttempts
  local report=Nexus.SupportReport.Prepare({})
  local text=report and table.concat(report.chunks) or ''
  check(H.grantedRequests==requests and H.boardAttempts==attempts,'preparing the report requests and sends nothing')
  check(text:find('Auto: selected=yes effective=paused',1,true)~=nil,'the report says selected and paused')
  local before=H.grantedRequests
  hold(H,30)
  check(H.grantedRequests==before,'no read refresh while the pause holds: '..(H.grantedRequests-before)..' in 30 s')
  check(H.Count()==1 and H.Auto() and A.SelectOutcome(1)=='unresolved','nothing is resent; Auto stays selected; still unresolved')
  clear(H);before=H.grantedRequests;H.Advance(6)
  local resumed=Nexus.AutomationEffectiveState()
  check(H.grantedRequests>before and resumed.state=='rechecking','paced read refreshes resume once it clears: '
   ..(H.grantedRequests-before)..' '..tostring(resumed.state))
 end)
end
local function Hold(H,seconds) H.Advance(seconds) end

Pause('client auto-accept re-enabled during an overdue rechecked Select',
 function() ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true) end,Hold,
 function() ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',false) end)
Pause('a rival Echo add-on loaded during an overdue rechecked Select',
 function() _G.EchoOptimizer={} end,Hold,function() _G.EchoOptimizer=nil end)
Pause('an unknown Orb state during an overdue rechecked Select',
 function() ProjectEbonhold.OrbService={IsStateKnown=function() return false end,IsOfferPending=function() return false end} end,
 Hold,function() ProjectEbonhold.OrbService=nil end)
-- The player's own board clicks through the hooked client service (answered
-- at once here: the fixture clears the client's latch).
local function Banish(H) H.service.BanishPerk(1);H.perks.pendingBanishIndex=nil end
Pause('the player acting on the board during an overdue rechecked Select',Banish,
 function(H,seconds) for _=1,seconds/2 do Banish(H);H.Advance(2) end end,function() end)
finish()
