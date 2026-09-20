-- Actual runtime wiring: the active saved row's verification reaches neither
-- the planner choice, nor a predicted queue, nor the Journal estimate.
-- Real adapter, runtime, policy and Journal provider; synthetic game surface.
local function Run(verified)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={[1]={name='Active saved build',verified=verified,
  echoes={{spellId=200001,quality=1,stacks=2}}}}
 H.Boot();local A=Nexus.GameAdapter
 assert(A.SetLoadoutWishlistIdentity(1,'Assigned plan',{{spellId=200001,quality=1,stacks=2}}),'assign the exact plan to the active slot')
 -- Old persisted guarantee flags at their old truthy values.
 for key in pairs(Nexus.DefaultProfile.defaultFlags or {})do Nexus.DefaultProfile.defaultFlags[key]=true end
 Nexus.DefaultProfile.defaultFlags.DISABLE_SUPPRESSES_GUARANTEE=true
 Nexus.DefaultProfile.defaultFlags.REROLL_HOLDS_GUARANTEED=true
 -- Observe only. Both calls pass through unchanged.
 local seen={states={},predicted=0,historical=0}
 local decide=Nexus.Policy.Decide
 Nexus.Policy.Decide=function(state,...)
  seen.states[#seen.states+1]={hasFlag=state.snapshotVerified~=nil,queue=#((state.queue or {}).entries or {}),
   requested=state.plan and state.plan.requestedCounts and state.plan.requestedCounts[200001]}
  local action=decide(state,...);seen.states[#seen.states].action=action;return action
 end
 local historical=Nexus.Ratchet.HistoricalGuaranteeQueue
 Nexus.Ratchet.HistoricalGuaranteeQueue=function(...)seen.historical=seen.historical+1;return historical(...)end
 local predict=Nexus.Ratchet.PredictQueue
 Nexus.Ratchet.PredictQueue=function(...)
  local queue=predict(...);seen.predicted=seen.predicted+#queue.entries;return queue
 end
 H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.Notify();H.Advance(.5)
 local wishlist=assert(A.Wishlist(),'assigned Wishlist resolves for the active slot')
 SlashCmdList.NEXUS('auto');H.Advance(1.2)
 local submitted=#H.actions;H.Advance(.6)
 assert(#H.actions==submitted,'pending action is not duplicated')
 -- The lifecycle hands the real Journal provider to JournalTab on world
 -- entry. Capture that same function on an ordinary second world entry.
 local provider;local install=Nexus.JournalTab.TryInstall
 Nexus.JournalTab.TryInstall=function(dataProvider,...)provider=dataProvider;return install(dataProvider,...)end
 H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1,.05)
 Nexus.JournalTab.TryInstall=install
 local journal=assert(provider,'lifecycle supplied the real Journal provider')()
 local notes
 for _,section in ipairs(journal.sections)do if section.title=='Notes' then notes=table.concat(section.lines,'\n')end end
 return {H=H,seen=seen,actions=H.Clone(H.actions),notes=assert(notes,'Journal Notes section'),
  recommendation=Nexus.Panel and Nexus.Panel._lastModel and Nexus.Panel._lastModel.recommendation}
end
local function Actions(run)
 local out={};for i,a in ipairs(run.actions)do out[i]=tostring(a[1])..':'..tostring(a[2])end;return table.concat(out,',')
end
local verified,unverified=Run(true),Run(false)
for label,run in pairs({verified=verified,unverified=unverified})do
 assert(#run.seen.states>0,'runtime reached the real policy: '..label)
 for _,state in ipairs(run.seen.states)do
  assert(not state.hasFlag,'runtime passes no saved-verification flag to the policy: '..label)
  assert(state.queue==0,'runtime passes no inferred queue: '..label)
  assert(state.requested==2,'real compiled requestedCounts reach the policy: '..label)
  assert(state.action.planner=='pilot103','the one ordinary planner decides: '..label)
 end
 assert(run.seen.predicted==0 and run.seen.historical==0,'no future offer is inferred and the historical model is never called: '..label)
 assert(not run.notes:lower():find('guaranteed queue',1,true) and run.notes:find('none is assumed',1,true),'Journal estimate assumes no future offer: '..label)
end
assert(#verified.actions>=1 and Actions(verified)==Actions(unverified),'submitted actions are identical when only saved verification differs: '..Actions(verified)..' vs '..Actions(unverified))
assert(verified.notes==unverified.notes,'Journal notes are identical when only saved verification differs')
local first,second=verified.seen.states[1].action,unverified.seen.states[1].action
assert(first.type==second.type and first.spellId==second.spellId and first.reason==second.reason and first.type~='wait','first decision is identical and makes useful progress')
print('PASS runtime decisions, submitted actions ('..Actions(verified)..') and Journal estimate do not depend on saved verification')
