-- Review F6 controls. Real board-action attempts (every SelectPerk, BanishPerk,
-- FreezePerk and RequestReroll call that reaches the client, accepted or not)
-- pin "no dependent action" for an own Select with no response, one made
-- ambiguous by the player's same-Echo click, and one held while Auto is OFF.
-- A genuine sibling tier (same family, another spellId) granted after the
-- Select settles nothing and is never the selected tier. And the Orb start
-- refusal still treats an uncertain automatic action as unconfirmed when it is
-- the only unresolved fact: a Freeze whose latch cleared on the same board,
-- with the adapter holding nothing. Real modules, synthetic services.
local F=dofile('tests/prototype/select_followup_support.lua')
local R=F.R
local scenario,finish=R.Checks()

scenario('no response: one Select reaches the client and nothing dependent follows',function(check)
 local H,A=R.Boot();R.AutoSubmit(H);R.Travel(H);H.Advance(60)
 check(H.boardAttempts==1 and H.selectAttempts==1 and H.Count()==1,'one board action in all: boardAttempts='..H.boardAttempts)
 check(H.Auto() and A.SelectOutcome(1)=='unresolved','Auto stays selected; the Select stays unresolved')
end)

scenario("ambiguous: one exact rise after the player's same-Echo click starts nothing dependent",function(check)
 local H,A=R.Boot();R.AutoSubmit(H)
 local accepted=H.service.SelectPerk(R.X) -- the player's click on the same Echo while its flag is set
 assert(accepted==false and H.boardAttempts==2,'setup: the outside Select reached the client and was refused')
 R.Grant(H,R.X);H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(60)
 check(A.GrantedCount(R.X)==1 and A.SelectOutcome(1)=='unresolved' and A.InFlight(),'the one exact rise settles nothing ambiguous')
 check(H.boardAttempts==2 and H.Count(R.Y)==0,'no dependent action on the next board: boardAttempts='..H.boardAttempts)
end)

scenario('Auto OFF: an unresolved Select starts nothing dependent',function(check)
 local H,A=R.Boot();R.AutoSubmit(H);R.Travel(H)
 SlashCmdList.NEXUS('auto');assert(not H.Auto(),'setup: Auto OFF')
 H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(40)
 check(H.boardAttempts==1 and H.Count()==1,'Auto OFF: nothing dependent is sent: boardAttempts='..H.boardAttempts)
 check(A.SelectOutcome(1)=='unresolved','and the Select stays unresolved')
end)

scenario("a genuine sibling-tier grant is not the own Select's grant",function(check)
 local H,A=F.BootWith(function(h) h.db[R.X].groupId=7100;h.AddEcho(F.SIBLING,'Echo 10',3,5,7100) end)
 local cat=A.Catalog()
 local family=cat and cat.familyOf[R.X]
 assert(family~=nil and family==cat.familyOf[F.SIBLING] and cat.rows[F.SIBLING].quality~=cat.rows[R.X].quality,
  'setup: X and its sibling are two tiers of one family')
 R.AutoSubmit(H)
 H.perks.pendingSelectSpellId=nil;H.Offer(R.next);H.Advance(.2)
 R.Grant(H,F.SIBLING);H.Advance(30)
 local owned=A.Owned()
 check(A.SelectOutcome(1)=='unresolved' and A.InFlight(),'the sibling grant settles nothing')
 check((owned.bySpell[R.X] or 0)==0 and (owned.bySpell[F.SIBLING] or 0)==1 and (owned.byFamily[family] or 0)==1,
  'the sibling copy is owned as itself, never as the selected tier')
 check(H.boardAttempts==1 and H.Count()==1,'no resend and no dependent action: boardAttempts='..H.boardAttempts)
end)

-- Last: the Orb fixture replaces the harness and add-on of the scenarios above.
local function Leads(why,first,second)
 local a,b=why:find(first,1,true),why:find(second,1,true)
 return a~=nil and b~=nil and a<b
end
local function NoImperative(why)
 local l=why:lower()
 return not l:find('choose',1,true) and not l:find('finish',1,true)
  and not l:find('retry',1,true) and not l:find('start a new',1,true)
end
scenario('Orb start refusal: an uncertain automatic Freeze alone is still unconfirmed',function(check)
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 if NexusOrbPanel then NexusOrbPanel:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua');local M,A=H.M,H.A
 H.OrbPlan({{spellId=410002,quality=2,stacks=1},{spellId=410004,quality=3,stacks=1}})
 SlashCmdList.NEXUS('auto')
 H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 H.Notify();A.Poll()
 for _=1,8 do Nexus.RequestRecompute();H.Advance(.25) end
 assert(H.Count('freeze')==1 and H.Count('take')==0 and H.perks.pendingFreezeIndex==0,'setup: Auto froze one of two needed offers')
 H.perks.pendingFreezeIndex=nil;H.Notify();A.Poll()
 for _=1,4 do Nexus.RequestRecompute();H.Advance(.25) end
 assert(Nexus.PendingIntentState()=='uncertain','setup: the runtime records the Freeze as uncertain: '..tostring(Nexus.PendingIntentState()))
 check(not A.UnconfirmedLatch() and not A.InFlight() and A.SelectUnresolved()==nil,
  'no latch and nothing in flight: the uncertain intent is the only unresolved fact')
 local why=tostring(M.Status().startReason)
 check(Leads(why,'has no confirmed result','An Echo choice is shown') and NoImperative(why),
  'the board is only reported, after the unconfirmed action: '..why)
 check(M.Status().canStart==false,'Start stays refused')
 check(H.Count('freeze')==1 and H.Count('take')==0 and H.Count('banish')==0 and H.Count('reroll')==0,'nothing else was sent')
end)
finish()
