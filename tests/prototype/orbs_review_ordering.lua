local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
local permutations={{1,2,3},{1,3,2},{2,1,3},{2,3,1},{3,1,2},{3,2,1}}
local initial=H.Clone(H.granted)
O.charges=100 -- Twelve isolated approved operations; the fixture starts with ten.
local function prepare()
 M.Stop();H.granted=H.Clone(initial);H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
 H.Notify();A.Poll();H.OrbPlan();H.Approve(1,false)
end
local function ownership()
 local out=H.Clone(H.granted)
 for _,es in pairs(out)do for i=#es,1,-1 do if es[i].spellId==O.source then table.remove(es,i);break end end end
 out['Desired A']={{spellId=410002,quality=2}};H.granted=out;H.Notify();A.Poll()
end
for _,order in ipairs(permutations)do
 prepare();local spends,takes=H.Count('orb-spend'),H.Count('take')
 local steps={
  function()O.charges=O.charges-1 end,
  function()O.offer=true;H.Board({{spellId=410002,quality=2},{spellId=410008,quality=1},{spellId=410004,quality=3}})end,
  function()H.granted=H.Clone(H.granted);H.Notify();A.Poll()end}
 for _,i in ipairs(order)do steps[i]();M.Pump();assert(M.Status().pending and H.Count('orb-spend')==spends)end
 assert(H.Count('take')==takes+1,'one choice across reordered offer, charge and unchanged ownership')
 H.Result(410002,2);assert(not M.Status().pending,'confirmed target settles')
end
for _,order in ipairs(permutations)do
 prepare();H.Offer();local spends=H.Count('orb-spend');M.Pause()
 local steps={ownership,function()O.offer=false end,function()H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil end}
 for n,i in ipairs(order)do steps[i]();M.Pump()
  assert(M.Status().pending==(n<3),'result waits for ownership and complete offer/selection closure in every order')
  assert(H.Count('orb-spend')==spends,'no spend during passive settlement')
 end
end
print('PASS 12 real-adapter runtime notification permutations; no duplicate selection/spend')
