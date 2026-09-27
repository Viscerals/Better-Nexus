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
  'state='..tostring(s.state),'spent='..tostring(s.spent),'reserved='..tostring(s.reserved),
  'limit='..tostring(s.limit),'pending='..tostring(s.pending),
  'receipt='..Ser(st.orbRefinement and st.orbRefinement.pending),
  'config='..Ser(st.orbRefinement and {maxOrbs=st.orbRefinement.maxOrbs,sources=st.orbRefinement.sources,
   excluded=st.orbRefinement.excluded,recycle=st.orbRefinement.recycle}),
  'auto='..tostring(Nexus.RecomputeStats and Nexus.RecomputeStats().autoEnabled),
 },' | ')
end

-- 1. Start refusal: each present cause is named; nothing combined or vague.
do
 local H,M,A,O=Fresh()
 H.OrbPlan()
 H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
 H.Notify();A.Poll()
 local why=tostring(M.Status().startReason)
 check(why:find('Echo choice is open in the game window',1,true)~=nil,'an open Echo choice is named: '..why)
 check(not why:find('Resolve the current Echo action',1,true),'the old combined sentence is gone')
 H.perks.pendingSelectSpellId=410002;H.Notify();A.Poll()
 why=tostring(M.Status().startReason)
 check(why:find('waiting for the game to confirm',1,true)~=nil,'an unconfirmed action is named too: '..why)
 check(why:find('Echo choice is open',1,true)~=nil,'and both stay listed: '..why)
 check(M.Status().canStart==false,'Start stays refused (the condition is unchanged)')
 H.perks.pendingSelectSpellId=nil;H.Board(nil);O.offer=true;H.Notify();A.Poll()
 why=tostring(M.Status().startReason)
 check(why:find('An Orb offer is open',1,true)~=nil,'an open Orb offer is named: '..why)
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
 for _=1,20 do H.Advance(.25) end
 return Snapshot(H,M)
end
do
 local control=Recovery(false)
 local opened=Recovery(true)
 check(control:find('pending=true',1,true)~=nil,'fixture: the restored receipt is being recovered: '..control)
 check(opened==control,'opening the window changes nothing in a recovery:\n'..opened..'\nvs\n'..control)
end

print('PASS orb_guidance_passive_open checks='..checks)
