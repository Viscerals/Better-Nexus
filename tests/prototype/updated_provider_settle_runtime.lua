-- Ordinary rolling on the updated provider, through the real runtime: the
-- later-frame settle rule (GameAdapter ChoiceActionable) delays an action; it
-- never ends one. Standards review of 2f79a852 (N-1):
--   a. the optional leveling pick (Random Roll) on a choice that is still
--      settling waits, then picks once on a later frame;
--   b. a Wishlist Take whose cards the game republishes (same cards, a new
--      choice table) between the decision and the send is refused with the
--      settle reason; the runtime supersedes that intent and decides again,
--      so the board ends with exactly one Take and no rejected intent.
-- The real guards stay: a pending native Select still sends nothing.
-- Real TOC boot (harness), real Wishlist/runtime/policy/adapter path;
-- synthetic services and SYNTHETIC ids only (native NOT_RUN).
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local X,Y,A1,A2=200001,200002,200041,200042
local function Card(id,q) return {spellId=id,quality=q or id%4} end
local function Boot(level,before)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=level or 20
 H.service.GetServerActiveDesign=function() return 0 end
 if before then before(H) end
 H.Boot();return H
end
local function Takes(H,id)
 local n=0
 for _,a in ipairs(H.actions) do if a[1]=='take' and (id==nil or a[2]==id) then n=n+1 end end
 return n
end
local function Lifecycle() return Nexus.RecomputeStats().lastActionLifecycle or {} end

-- a. Random Roll on the updated provider: settling, then one leveling Take.
do
 local H=Boot(2)
 SlashCmdList.NEXUS('leveling on')
 -- Every adapter Take the runtime enters, refused or not.
 local take,entered=Nexus.GameAdapter.Take,0
 Nexus.GameAdapter.Take=function(...) entered=entered+1;return take(...) end
 H.Board({Card(200011,1),Card(200014,4),Card(200012,2)});H.Notify()
 SlashCmdList.NEXUS('auto')
 H.Advance(.3)
 check(Takes(H)==0 and entered==0,'a: the leveling pick waits while the choice is settling (no Take attempted): '
  ..Takes(H)..' '..entered)
 H.Advance(3)
 check(Takes(H)==1 and Takes(H,200014)==1,'a: one leveling Take of the highest rarity once actionable: '..Takes(H))
 check(Lifecycle().state=='submitted','a: the Take is submitted, not rejected: '..tostring(Lifecycle().state)
  ..' '..tostring(Lifecycle().reason))
 H.Advance(3);check(Takes(H)==1,'a: and not resent')
 check(entered==1,'a: exactly one Take was attempted, none refused while settling: '..entered)
 Nexus.GameAdapter.Take=take
end

-- b. A Wishlist Take whose cards are republished as a new table just before
-- the adapter Take: superseded and decided again, never stuck as rejected.
local function WishlistBoot()
 local H=Boot(20)
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Synthetic Settle',
  {{spellId=X,quality=X%4,stacks=1},{spellId=Y,quality=Y%4,stacks=1}},{})==true,'fixture: the plan is set')
 return H
end
do
 local H=WishlistBoot()
 local cards={Card(X),Card(A1),Card(A2)}
 local take=Nexus.GameAdapter.Take
 local republished,results=0,{}
 Nexus.GameAdapter.Take=function(...)
  if republished==0 then republished=1;H.Board(cards) end -- same cards, new table
  local res={take(...)}
  results[#results+1]=res
  return unpack(res)
 end
 H.Board(cards);H.Notify();H.Advance(.5)
 SlashCmdList.NEXUS('auto')
 H.Advance(6)
 check(republished==1 and results[1] and results[1][1]==false,
  'b: fixture: the first Take met a republished choice and was refused: '..tostring(results[1] and results[1][2]))
 check(Takes(H,X)==1 and Takes(H)==1,'b: the board ends with exactly one Take of the needed Echo: '..Takes(H))
 check(Lifecycle().state=='submitted','b: no rejected intent holds the board: '..tostring(Lifecycle().state)
  ..' '..tostring(Lifecycle().reason))
 Nexus.GameAdapter.Take=take
end

-- Pacing (measured offline, not native): with Auto already on, a newly
-- published ordinary draw is acted on soon after its settle period. It took
-- 1.5 s with a 1.0 s settle and 0.88 s when a settling choice is re-checked
-- only at the 0.2 s poll pace (both measured on this harness); 0.72 s now.
do
 local H=WishlistBoot()
 SlashCmdList.NEXUS('auto');H.Advance(1,1/60) -- Auto on, no choice shown yet
 check(Takes(H)==0,'pacing setup: nothing sent before the draw')
 local t0=H.now
 H.Board({Card(A2),Card(X),Card(A1)});H.Notify()
 while Takes(H)==0 and H.now<t0+3 do H.Advance(1/60,1/60) end
 local delay=H.now-t0
 print(string.format('MEASURE updated-provider Wishlist Take delay at 60 fps: %.3f s',delay))
 check(Takes(H,X)==1 and delay<0.8,'pacing: the needed Echo is taken within 0.8 s of the draw: '..string.format('%.3f',delay))
end
-- Control: a pending native Select still sends nothing on an actionable board.
do
 local H=WishlistBoot()
 H.Board({Card(X),Card(A1),Card(A2)});H.Notify();H.Advance(.5)
 H.perks.pendingSelectSpellId=A2
 SlashCmdList.NEXUS('auto')
 H.Advance(5)
 check(Takes(H)==0,'control: a pending native Select: no Take: '..Takes(H))
end
print('PASS updated-provider settle through the runtime: leveling and Wishlist Takes wait and then act once; a pending native pick sends nothing ('..checks..' checks)')
