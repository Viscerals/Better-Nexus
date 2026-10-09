-- L1: final automatic Take whose exact grant fills all 79 rolled slots.
-- Real modules, synthetic service; no native client or private data.
local F=dofile('tests/prototype/select_followup_support.lua')
local R=F.R
local scenario,finish=R.Checks()
scenario('L1 full capacity: exact final grant releases tracked Take before the level80 save-path idle render',function(check)
 local H,A=R.Boot()
 local seed,left={},78
 for id=200030,200045 do
  local rows={}
  for _=1,math.min(5,left) do rows[#rows+1]={spellId=id,quality=H.db[id].quality} end
  seed['Echo '..(id-200000)]=rows;left=left-#rows
 end
 H.granted=seed;H.Notify();A.Poll();H.Advance(.5)
 assert(left==0 and A.Owned().synced and A.Owned().total==78,'setup: 78 synchronized rolled copies, no X')
 H.playerLevel=80;Nexus.Panel.Show();R.AutoSubmit(H)
 local spends=0
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,IsOfferPending=function()return false end,
  GetCharges=function()return 3 end,RequestCharges=function()return true end,
  ConfirmSpend=function()spends=spends+1;return true end}
 H.pendingRolls=0;H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil
 H.Notify();H.Advance(12)
 assert(A.SelectOutcome(1)=='unresolved' and A.Board()==nil,'setup: final choice gone without its grant')
 check(F.Lifecycle().state~='confirmed','control: no premature confirmation')
 check(Nexus.AutomationEffectiveState().state=='waiting' or Nexus.AutomationEffectiveState().state=='rechecking',
  'control: unresolved final selection still waits')
 R.Grant(H,R.X)
 assert(A.Owned().synced and A.Owned().total==79 and A.SelectOutcome(1)=='proven' and not A.InFlight(),
  'setup: exact final grant proven; synchronized full 79-copy save branch')
 H.Advance(6)
 check(Nexus.PendingIntentState()==nil,'full-capacity tracked Take released: '..tostring(Nexus.PendingIntentState()))
 local e=Nexus.AutomationEffectiveState()
 check(e.state=='ready','full-capacity effective wait ends: '..tostring(e.state)..'/'..tostring(e.reason))
 local model=Nexus.Panel._lastModel or {};local guide=model.orbGuidance or {}
 check(guide.state=='finished' and NexusPanel._orbsBtn:IsShown(),
  'full-capacity guidance no longer hides Open Orbs: '..tostring(guide.state))
 local l,counts=F.Lifecycle()
 check(l.state=='confirmed' and l.reason=='grant_observed','full-capacity observed result: '..tostring(l.state)..'/'..tostring(l.reason))
 check(counts.confirmed==1,'one full-capacity grant confirmation: '..tostring(counts.confirmed))
 H.Advance(6)
 local _,later=F.Lifecycle()
 check(later.confirmed==1,'later full-capacity steps do not duplicate confirmation')
 check(H.selectAttempts==1 and H.boardAttempts==1 and H.Count(R.X)==1 and spends==0,'no resend or Orb spend')
end)
finish()
