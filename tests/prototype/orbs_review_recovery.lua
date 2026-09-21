local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
H.OrbPlan({{spellId=410004,quality=3,stacks=1}});H.Approve(2,true)
local id=O.source;local q=H.db[id].quality
H.Offer({{spellId=id,quality=q},{spellId=410008,quality=1},{spellId=410001,quality=1}})
H.Fire('PLAYER_LOGOUT');NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide()
assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
M=Nexus.OrbRuntime;assert(M.Status().pending);M.Pump()
H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
H.granted=H.Clone(H.granted);H.Notify();A.Poll();M.Pump()
assert(M.Status().pending and M.Status().reason:find('same-ID',1,true),'recovered ambiguity retains specific reason')
H.now=H.now+4;M.Recheck()
assert(M.Status().pending and M.Status().spent+M.Status().reserved==1,'recovery refresh retains exposure')
assert(not M.Prepare() and not M.Resume() and H.Count('orb-spend')==1,'no retry or next spend after reload')
print('PASS same-ID recovery retains reason, pending ownership and original exposure')
