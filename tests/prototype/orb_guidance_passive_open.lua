-- Opening the Orb window is passive, also while an Orb run is active or an
-- earlier Orb action is being recovered: the same steps with and without
-- opening it produce the same game actions, the same saved receipt and the
-- same Orb state. And the window's start refusal names the causes that are
-- actually present. Real OrbRuntime/OrbAdapter with the synthetic Orb
-- service of orbs_support.lua; SYNTHETIC ids.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Ser(v,seen)
 seen=seen or {}
 if type(v)~='table' then return tostring(v) end
 if seen[v] then return '<cycle>' end;seen[v]=true
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local o={};for _,k in ipairs(keys) do o[#o+1]=tostring(k)..'='..Ser(v[k],seen) end
 return '{'..table.concat(o,',')..'}'
end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 if NexusOrbPanel then NexusOrbPanel:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 return H,H.M,H.A,H.O
end
local function Reload(H)
 H.Fire('PLAYER_LOGOUT')
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 return Nexus.OrbRuntime
end
local function Snapshot(H,M)
 local s=M.Status()
 local st=Nexus.Store.State()
 return table.concat({
  'spend='..H.Count('orb-spend'),'take='..H.Count('take'),'actions='..#H.actions,
  -- Requests sent to the server (a refresh is outgoing traffic too).
  'orbRequests='..tostring(H.orbs and H.orbs.requests),'slotRequests='..tostring(H.slotRequests),
  'recovery='..Ser(M.Status().recovery),
  'state='..tostring(s.state),'spent='..tostring(s.spent),'reserved='..tostring(s.reserved),
  'limit='..tostring(s.limit),'pending='..tostring(s.pending),
  'receipt='..Ser(st.orbRefinement and st.orbRefinement.pending),
  'config='..Ser(st.orbRefinement and {maxOrbs=st.orbRefinement.maxOrbs,sources=st.orbRefinement.sources,
   excluded=st.orbRefinement.excluded,recycle=st.orbRefinement.recycle}),
  'auto='..tostring(Nexus.RecomputeStats and Nexus.RecomputeStats().autoEnabled),
 },' | ')
end

-- 1. Start refusal: each present cause is named. While an action has no
-- confirmed result, a shown choice or offer is only reported: no "choose"
-- or "finish" instruction that could repeat an action already sent.
local function NoImperative(why)
 local l=why:lower()
 return not l:find('choose',1,true) and not l:find('finish',1,true)
  and not l:find('retry',1,true) and not l:find('start a new',1,true)
end
local function Leads(why,first,second)
 local a,b=why:find(first,1,true),why:find(second,1,true)
 return a~=nil and b~=nil and a<b
end
do
 local H,M,A,O=Fresh()
 H.OrbPlan()
 H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 H.Notify();A.Poll()
 local why=tostring(M.Status().startReason)
 check(why:find('Choose the open Echo choice in the game window first',1,true)~=nil,
  'a genuinely unanswered choice keeps its instruction: '..why)
 check(not why:find('Resolve the current Echo action',1,true),'the old combined sentence is gone')
 -- The same board while a choice latch has no result.
 H.perks.pendingSelectSpellId=410002;H.Notify();A.Poll()
 why=tostring(M.Status().startReason)
 check(why:find('has no confirmed result',1,true)~=nil,'the unconfirmed action is named: '..why)
 check(why:find('An Echo choice is shown',1,true)~=nil,'the board is reported as an observation: '..why)
 check(Leads(why,'has no confirmed result','An Echo choice is shown'),'and the waiting status leads: '..why)
 check(NoImperative(why),'with no instruction to choose, finish, retry or start again: '..why)
 check(M.Status().canStart==false,'Start stays refused (the condition is unchanged)')
 -- The watchdog releases the stuck latch: still no confirmed result.
 for _=1,24 do H.Advance(.5) end
 check(not A.InFlight(),'fixture: the watchdog released the latch')
 why=tostring(M.Status().startReason)
 check(why:find('has no confirmed result',1,true)~=nil and NoImperative(why),
  'an expired watchdog is not a result: no instruction either: '..why)
 H.perks.pendingSelectSpellId=nil;H.Board(nil);O.offer=true;H.Notify();A.Poll()
 why=tostring(M.Status().startReason)
 check(why:find('Finish the open Orb offer in the game window first',1,true)~=nil,'an open Orb offer keeps its instruction: '..why)
 H.perks.pendingSelectSpellId=410002;H.Notify();A.Poll()
 why=tostring(M.Status().startReason)
 check(why:find('An Orb offer is shown',1,true)~=nil and NoImperative(why),
  'with an unconfirmed action the offer is only reported: '..why)
end
-- An automatic Take whose latch cleared on the same board: the automation
-- runtime records the action as uncertain, and the adapter keeps that Select
-- unresolved (in flight, not owned) because a same-board clear is not a
-- proven refusal. No latch remains, but the action still has no confirmed
-- result, so the board is only reported (the HUD says "Waiting..." for the
-- same record).
do
 local H,M,A,O=Fresh()
 H.OrbPlan()
 SlashCmdList.NEXUS('auto')
 H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 H.Notify();A.Poll()
 for _=1,8 do Nexus.RequestRecompute();H.Advance(.25) end
 check(H.Count('take')==1 and H.perks.pendingSelectSpellId==410002,'fixture: Auto took the wanted card: '..H.Count('take'))
 H.perks.pendingSelectSpellId=nil;H.Notify();A.Poll()
 for _=1,4 do Nexus.RequestRecompute();H.Advance(.25) end
 check(Nexus.PendingIntentState()=='uncertain','fixture: the automation runtime records it as uncertain: '..tostring(Nexus.PendingIntentState()))
 check(not A.UnconfirmedLatch() and A.InFlight(),'fixture: no latch remains; the Select itself stays unresolved')
 local why=tostring(M.Status().startReason)
 check(Leads(why,'has no confirmed result','An Echo choice is shown') and NoImperative(why),
  'an uncertain automatic action: the board is only reported: '..why)
 check(M.Status().canStart==false,'Start stays refused')
end

-- 2. An active approved run waiting for its result: with and without
-- opening the Orb window, identical steps give identical outcomes.
local function ActiveRun(open)
 local H,M,A,O=Fresh()
 H.OrbPlan();H.Approve(2);H.Offer()
 if open then Nexus.OrbPanel.Show() end
 for _=1,12 do H.Advance(.25) end
 H.Result(410002,2)
 for _=1,12 do H.Advance(.25) end
 local snap=Snapshot(H,M)
 if open then check(NexusOrbPanel:IsShown(),'fixture: the window was open') end
 return snap
end
do
 local control=ActiveRun(false)
 local opened=ActiveRun(true)
 check(control:find('spend=1',1,true)~=nil,'fixture: the approved run spent once: '..control)
 check(opened==control,'opening the window changes nothing in an active run:\n'..opened..'\nvs\n'..control)
end

-- 3. Recovery of an earlier Orb action after a reload (read-only observing):
-- with and without opening the window, identical outcomes.
local function Recovery(open)
 local H,M,A,O=Fresh()
 H.OrbPlan();H.Approve(2);H.Offer()
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 M=Reload(H)
 H.Notify();A.Poll()
 if open then Nexus.OrbPanel.Show() end
 for _=1,8 do H.Advance(.25) end
 -- An event while the window is (or is not) open: the game reports a
 -- change and the adapter polls.
 H.Notify();A.Poll()
 for _=1,12 do H.Advance(.25) end
 -- The HUD names the unresolved earlier Orb action and suggests no start.
 Nexus.RequestRecompute();H.Advance(.5)
 local g=(Nexus.Panel._lastModel or {}).orbGuidance or {}
 check(g.state=='orb-run','the HUD shows the unresolved Orb action: '..tostring(g.state))
 check(not tostring(g.text):find('Review Orbs',1,true) and not tostring(g.text):find('Start',1,true),
  'with its recovery reason, not a start suggestion: '..tostring(g.text))
 return Snapshot(H,M)
end
do
 local control=Recovery(false)
 local opened=Recovery(true)
 check(control:find('pending=true',1,true)~=nil,'fixture: the restored receipt is being recovered: '..control)
 check(opened==control,'opening the window changes nothing in a recovery:\n'..opened..'\nvs\n'..control)
end

print('PASS orb_guidance_passive_open checks='..checks)
