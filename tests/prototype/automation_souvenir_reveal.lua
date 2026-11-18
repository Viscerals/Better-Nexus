-- Souvenir reveal on the updated provider: an unneeded souvenir is given up
-- once, and the revealed Echoes are chosen from.
--
-- User requirement (2026-11-17): when the souvenir is not needed, open the
-- three hidden Echoes and choose from there; a needed souvenir is still taken.
--
-- Client reference: a STATIC READING of one captured client, offline only; no
-- native result, no server behavior proven (CONTRACTS.md, souvenir stage):
--   perks.lua         SHA-256 43e28daef02a1f95d344eaca880bde2ce1794a0e821113837c5bfc5d5b98b8a2
--     RequestMemoryDraw / PlayMemoryGiveUp send
--     ProjectEbonhold.sendToServer(CS.REQUEST_PERK_MEMORY_DRAW, ""), and "the
--     reply repaints the row with the random cards".
--   projectebonhold.lua: CS.REQUEST_PERK_MEMORY_DRAW = 349; no server opcode
--     is named for its reply, so the reply is read as the next published
--     choice (SEND_PLAYER_PERK_CHOICE, perks_service.lua SHA-256
--     3303632eedb997f121b6ac5fa155bd6041b3f17190d71fb7c8b71dd670bd7c51),
--     which also arms the game's own auto-accept timer (autoAcceptLoadoutEchoes
--     with a WantsMoreOfEcho card); the existing Auto gate holds Nexus while
--     that option is on.
-- Nothing of the client is executed or copied here.
--
-- Expected, per case below: exactly one reveal request for one souvenir draw,
-- never a retry; a Take only on the revealed board bound to that request; no
-- reveal when the souvenir is needed, wanted by the game's own build, or the
-- state is ambiguous; every existing hold still applies.
-- Real TOC boot (harness), real Wishlist/runtime/EchoWeaver/adapter path;
-- synthetic services and SYNTHETIC ids only.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local X,Y,Z=200001,200002,200030
local A1,A2,A3=200041,200042,200043
local HANDOFF='souvenir: take it or draw three random Echoes; the choice is left to the player'

local function Souvenir(id) return {spellId=id,quality=id%4,isGuaranteed=true,memoryRemaining=1} end
local function Card(id,extra) local c={spellId=id,quality=id%4};for k,v in pairs(extra or {}) do c[k]=v end;return c end

local function Boot(spec)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=5
 H.granted={}
 for id,n in pairs(spec.owned or {}) do
  H.granted[H.names[id]]={}
  for _=1,n do table.insert(H.granted[H.names[id]],{spellId=id,quality=id%4}) end
 end
 H.locked={}
 local ctx={H=H,reveals={},other={},selects=0,wants=spec.wants or {}}
 if spec.updated~=false then
  H.service.GetServerActiveDesign=function() return 0 end
  H.service.WantsMoreOfEcho=function(id) if ctx.onWants then ctx.onWants(id) end;return ctx.wants[id]==true end
 end
 local select=H.service.SelectPerk
 H.service.SelectPerk=function(...) ctx.selects=ctx.selects+1;return select(...) end
 if spec.setup then spec.setup(H,ctx) end
 H.Boot()
 -- Every entry into the reveal, and its result.
 local reveal=Nexus.GameAdapter.RevealMemory
 Nexus.GameAdapter.RevealMemory=function(...)
  ctx.inReveal=true;ctx.entered=(ctx.entered or 0)+1
  local res={reveal(...)}
  ctx.inReveal=false;ctx.result=res
  ctx.results=ctx.results or {};ctx.results[#ctx.results+1]=res
  return unpack(res)
 end
 ProjectEbonhold.CS=ProjectEbonhold.CS or {}
 if spec.cs~=false then ProjectEbonhold.CS.REQUEST_PERK_MEMORY_DRAW=spec.cs or 349 end
 ProjectEbonhold.sendToServer=function(op,payload)
  if ctx.sendError then error('synthetic send failure') end
  if op==349 then ctx.reveals[#ctx.reveals+1]=payload else ctx.other[#ctx.other+1]=op end
 end
 if spec.plan~=false then
  check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Synthetic Reveal',spec.echoes
   or {{spellId=X,quality=X%4,stacks=1},{spellId=Y,quality=Y%4,stacks=1}},{})==true,'fixture: the plan is set')
 end
 H.perks.pendingRollsCount=4
 H.Board(spec.board or {Souvenir(Z)})
 if spec.afterBoard then spec.afterBoard(H,ctx) end
 H.Notify();H.Advance(.5)
 if spec.auto~=false then SlashCmdList.NEXUS('auto') end
 H.Advance(1.5)
 return ctx
end
local function Shown()
 local m=Nexus.Panel and Nexus.Panel._lastModel or {}
 return tostring(m.recommendation or '')
end
local function Reason()
 local log=Nexus.DiagnosticLogs.Snapshot('decision')
 local last=log[#log] or {}
 return tostring((last.proposal or {}).reason or '')
end
local function Takes(ctx,id)
 local n=0
 for _,a in ipairs(ctx.H.actions) do if a[1]=='take' and (id==nil or a[2]==id) then n=n+1 end end
 return n
end
-- The server's reply to the reveal: the next published choice.
local function Reply(ctx,cards) ctx.H.Board(cards);ctx.H.Notify() end

-- 1. An unneeded souvenir, alone, with Wishlist targets still missing: one
-- reveal request with an empty body; no Select; nothing else sent.
local ctx=Boot({})
check(#ctx.reveals==1 and ctx.reveals[1]=='','one reveal request with an empty body: '..#ctx.reveals)
check(ctx.selects==0 and #ctx.other==0,'nothing else is sent')
-- Repeated ticks with no reply: never a second request, never a Select.
ctx.H.Advance(30)
check(#ctx.reveals==1 and ctx.selects==0,'no retry while the reply is missing: '..#ctx.reveals)
-- A reply after the bound window is not bound to the request. Since the
-- ordinary-rolling restoration (2026-11-17) it is an ordinary three-card draw
-- like any other: the needed Echo is taken once it is actionable, and the
-- reveal is never sent again. (Before: not chosen from at all.)
Reply(ctx,{Card(X),Card(A1),Card(A2)});ctx.H.Advance(3)
check(ctx.selects==1 and #ctx.reveals==1,'a late reply is an ordinary draw: one Select, no second reveal: '
 ..ctx.selects..' '..#ctx.reveals)

-- 2. The reply in time: three revealed Echoes; the needed one is taken once.
ctx=Boot({})
Reply(ctx,{Card(A1),Card(X),Card(A2)});ctx.H.Advance(3)
check(Takes(ctx,X)==1 and ctx.selects==1,'the needed revealed Echo is taken: '..Takes(ctx)..' / '..Reason())
check(#ctx.reveals==1,'still one reveal request')
-- The binding ends with that board: the next ordinary-looking board (after
-- the grant) is not chosen from on the updated provider.
ctx.H.perks.pendingSelectSpellId=nil
ctx.H.granted[ctx.H.names[X]]={{spellId=X,quality=X%4}}
ctx.H.Notify();ctx.H.Advance(2)
-- A foreign Select latch holds it for 2 s, so the decision comes after the
-- board has settled.
ctx.H.perks.pendingSelectSpellId=A3
Reply(ctx,{Card(Y),Card(A1),Card(A3)})
-- Read while held, so the board is settled and actionable when released:
-- only the binding (tied to its own board) then keeps it unchosen.
Nexus.GameAdapter.Board();ctx.H.Advance(1.2);Nexus.GameAdapter.Board();ctx.H.Advance(.8)
ctx.H.perks.pendingSelectSpellId=nil;ctx.H.Advance(5)
check(ctx.selects==2 and Takes(ctx,Y)==1 and #ctx.reveals==1,'a later unbound board is an ordinary draw: its needed Echo is taken once: '..ctx.selects)

-- 3. A revealed board without a needed Echo: a plain Take, never a Banish,
-- Reroll or Freeze (the reveal grants no search).
ctx=Boot({})
Reply(ctx,{Card(A1),Card(A2),Card(A3)});ctx.H.Advance(3)
local kinds={}
for _,a in ipairs(ctx.H.actions) do kinds[a[1]]=(kinds[a[1]] or 0)+1 end
check((kinds.take or 0)==1 and not kinds.banish and not kinds.reroll and not kinds.freeze,
 'a revealed board is chosen from, not searched: take='..tostring(kinds.take)..' banish='..tostring(kinds.banish)
 ..' reroll='..tostring(kinds.reroll)..' freeze='..tostring(kinds.freeze))

-- 4. Replies that are not a clean three-card reveal of that draw: not chosen
-- from, and never a second reveal.
for _,bad in ipairs({
 {'another souvenir board',{Souvenir(Z)}},
 {'two cards',{Card(X),Card(A1)}},
 {'a flagged card among three',{Card(X),Card(A1),Souvenir(A2)}},
}) do
 ctx=Boot({})
 Reply(ctx,bad[2]);ctx.H.Advance(5)
 check(#ctx.reveals==1 and ctx.selects==0,bad[1]..': no Select and no second reveal: '..#ctx.reveals..' '..ctx.selects)
 if bad[1]=='another souvenir board' then
  check(Shown()=='souvenir given up; waiting for the three revealed Echoes',
   'the same draw is shown as given up, never revealed again: '..Shown())
 end
end
-- A grant between the request and the reply: not the reply to it.
ctx=Boot({})
ctx.H.granted[ctx.H.names[A3]]={{spellId=A3,quality=A3%4}}
Reply(ctx,{Card(X),Card(A1),Card(A2)});ctx.H.Advance(3)
check(Nexus.GameAdapter.Board() and Takes(ctx,X)==1 and ctx.selects==1 and #ctx.reveals==1,
 'a reply after a new grant is not bound to the reveal; it is chosen from as an ordinary draw (restoration 2026-11-17)')
-- A changed pending-draw count: not the reply to it.
ctx=Boot({})
ctx.H.perks.pendingRollsCount=3
Reply(ctx,{Card(X),Card(A1),Card(A2)});ctx.H.Advance(3)
check(Takes(ctx,X)==1 and ctx.selects==1 and #ctx.reveals==1,
 'a reply with another pending-draw count is not bound to the reveal; it is chosen from as an ordinary draw (restoration 2026-11-17)')

-- 5. A needed souvenir is taken, never revealed.
ctx=Boot({board={Souvenir(X)}})
check(Takes(ctx,X)==1 and #ctx.reveals==0,'a needed souvenir is taken, not given up')

-- 6. No reveal, and the hand-off is stated, when:
for _,case in ipairs({
 {'the game\'s own build asks for the souvenir',{wants={[Z]=true}}},
 {'every Wishlist target is already owned',{owned={[X]=1,[Y]=1}}},
 {'a carried card stands beside the souvenir',{board={Card(A1,{isCarried=true}),Souvenir(Z)}}},
 {'two flagged cards',{board={Souvenir(Z),Souvenir(A1)}}},
 {'the souvenir is another spell in the family of a missing target',
  {setup=function(H) H.db[X].groupId=5001;H.AddEcho(200091,'Echo 1 Variant',(X%4+2)%4,5,5001) end,
   board={Souvenir(200091)}}},
 {'the reveal request code is not the captured one',{cs=350}},
 {'the reveal request code is absent',{cs=false}},
}) do
 ctx=Boot(case[2])
 ctx.H.Advance(5)
 check(#ctx.reveals==0 and ctx.selects==0,case[1]..': nothing is sent: '..#ctx.reveals..' '..ctx.selects)
 check(Reason()==HANDOFF,case[1]..': the hand-off is stated: '..Reason())
end
-- No reveal without a Wishlist, with Auto off, on the older provider.
ctx=Boot({plan=false});ctx.H.Advance(5)
check(#ctx.reveals==0 and ctx.selects==0,'no Wishlist: nothing is sent')
ctx=Boot({auto=false});ctx.H.Advance(5)
check(#ctx.reveals==0 and ctx.selects==0,'Auto off: nothing is sent')
ctx=Boot({updated=false});ctx.H.Advance(5)
check(#ctx.reveals==0 and ctx.selects==0,'older provider: nothing is sent')

-- 7. Existing holds still apply.
ctx=Boot({afterBoard=function(H) H.perks.pendingSelectSpellId=A1 end});ctx.H.Advance(5)
check(#ctx.reveals==0,'a pending native Select holds the reveal')
ctx=Boot({setup=function() ProjectEbonhold.OrbService={IsStateKnown=function() return false end,
 GetCharges=function() return 0 end,IsOfferPending=function() return false end,RequestCharges=function() end} end})
ctx.H.Advance(5)
check(#ctx.reveals==0 and Reason()=='Orb state active or unknown','an unknown Orb state holds the reveal: '..Reason())

-- 8. Changes inside the reveal's own reads (after it is decided, before the
-- request): the request is not sent.
-- The Wishlist now asks for the souvenir: no reveal; the souvenir is taken.
ctx=Boot({auto=false})
ctx.onWants=function(id)
 if id==Z and ctx.inReveal and not ctx.changed then
  ctx.changed=true
  Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Synthetic Reveal',
   {{spellId=Z,quality=Z%4,stacks=1},{spellId=Y,quality=Y%4,stacks=1}},{})
 end
end
SlashCmdList.NEXUS('auto');ctx.H.Advance(5)
check(ctx.changed==true,'fixture: the Wishlist changed inside the reveal')
check(#ctx.reveals==0 and ctx.entered>=1,'a Wishlist that changed inside the reveal stops it: '..#ctx.reveals)
check(Takes(ctx,Z)==1,'and the souvenir, now needed, is taken: '..Takes(ctx,Z))
-- The souvenir board is replaced (by a needed souvenir) inside the reveal's
-- reads: that reveal is refused, and the new souvenir is taken instead.
ctx=Boot({auto=false})
ctx.onWants=function(id)
 if id==Z and ctx.inReveal and not ctx.changed then ctx.changed=true;ctx.H.perks.currentChoice={Souvenir(X)} end
end
SlashCmdList.NEXUS('auto');ctx.H.Advance(1.5)
check(ctx.changed==true and #ctx.reveals==0 and ctx.results and ctx.results[1][1]==false,
 'a souvenir board replaced inside the reveal stops it: '..tostring(ctx.results and ctx.results[1][2]))
check(Takes(ctx,X)==1,'and the needed replacement is taken: '..Takes(ctx,X))
-- A native Select that starts inside the reveal's reads: no request.
ctx=Boot({auto=false})
ctx.onWants=function(id)
 if id==Z and ctx.inReveal and not ctx.changed then ctx.changed=true;ctx.H.perks.pendingSelectSpellId=Z end
end
SlashCmdList.NEXUS('auto');ctx.H.Advance(1.5)
check(ctx.changed==true and #ctx.reveals==0 and ctx.results and ctx.results[1][1]==false,
 'a native Select started inside the reveal stops it: '..tostring(ctx.results and ctx.results[1][2]))

-- A native Select that starts after the fresh re-decision read the board
-- (Adapter.Horizon reads GetPendingRollsCount after it): the memory-only
-- final check refuses.
ctx=Boot({auto=false})
do
 local rolls=ctx.H.service.GetPendingRollsCount
 ctx.H.service.GetPendingRollsCount=function(...)
  if ctx.inReveal and not ctx.changed then ctx.changed=true;ctx.H.perks.pendingSelectSpellId=Z end
  return rolls(...)
 end
end
SlashCmdList.NEXUS('auto');ctx.H.Advance(1.5)
check(ctx.changed==true and #ctx.reveals==0 and ctx.results and ctx.results[1][1]==false,
 'a native Select after the fresh re-decision stops the reveal: '..tostring(ctx.results and ctx.results[1][2]))

-- The souvenir re-published (a new table, the same card) after the fresh
-- re-decision read the board: the memory-only final snapshot refuses.
ctx=Boot({auto=false})
do
 local rolls=ctx.H.service.GetPendingRollsCount
 ctx.H.service.GetPendingRollsCount=function(...)
  if ctx.inReveal and not ctx.changed then ctx.changed=true;ctx.H.perks.currentChoice={Souvenir(Z)} end
  return rolls(...)
 end
end
SlashCmdList.NEXUS('auto');ctx.H.Advance(1.5)
check(ctx.changed==true and ctx.results and ctx.results[1][1]==false,
 'a souvenir re-published after the fresh re-decision stops that reveal: '..tostring(ctx.results and ctx.results[1][2]))
check(#ctx.reveals==0,'no request in that window: '..#ctx.reveals)

-- 9. A failing send is never retried.
ctx=Boot({auto=false});ctx.sendError=true
SlashCmdList.NEXUS('auto');ctx.H.Advance(30)
ctx.sendError=false;ctx.H.Advance(30)
check(#ctx.reveals==0 and ctx.selects==0,'a failed reveal send is not retried: '..#ctx.reveals)

-- 10. The game's own auto-accept (perks_service: its parse arms a timer for
-- a WantsMoreOfEcho card when autoAcceptLoadoutEchoes is on). The existing
-- Auto gate holds every automatic action while it is on, the reveal included;
-- the existing solo-picker lease turns it off when Auto starts.
local function Options(settable)
 return function(_,c)
  c.option=true
  _G.ProjectEbonholdOptionsService={GetSetting=function(_,key)
   if key=='autoAcceptLoadoutEchoes' then return c.option end end,
   SetSetting=settable and function(_,key,v) if key=='autoAcceptLoadoutEchoes' then c.option=v end end or nil}
 end
end
ctx=Boot({setup=Options(false),wants={[X]=true}});ctx.H.Advance(5)
check(#ctx.reveals==0 and ctx.selects==0,'auto-accept on and not switched off: no reveal, no Select')
ctx=Boot({setup=Options(true),wants={[X]=true}})
check(ctx.option==false and #ctx.reveals==1,'auto-accept switched off by the lease: the reveal is sent')
Reply(ctx,{Card(A1),Card(X),Card(A2)});ctx.H.Advance(3)
check(Takes(ctx,X)==1,'and the needed revealed Echo is taken by Nexus')
_G.ProjectEbonholdOptionsService=nil

-- 12. The game's own auto-accept timer, modelled on perks_service.lua: armed
-- at a choice parse with the card it chose, it fires on the first frame after
-- 0.18 s and calls Perks.SelectPerk, which refuses only when a pick is pending
-- or the card is not on the current choice. It re-checks neither its option
-- nor the Wishlist, so switching the option off does not cancel it.
local function NativeArm(ctx,spellId)
 local f=ctx.timer or CreateFrame('Frame');ctx.timer=f
 f.t=0;f.choice=spellId
 f:SetScript('OnUpdate',function(self,elapsed)
  self.t=self.t+elapsed
  if self.t<0.18 then return end
  self:Hide()
  local id=self.choice;self.choice=nil
  local P=ctx.H.perks
  local on=false
  for _,c in ipairs(P.currentChoice or {}) do if c.spellId==id then on=true end end
  if P.pendingSelectSpellId or not on then ctx.nativeRefused=(ctx.nativeRefused or 0)+1;return end
  P.pendingSelectSpellId=id;ctx.nativeSelects=(ctx.nativeSelects or 0)+1
 end)
 f:Show()
end
-- The current recommendation as the panel shows it (the prepared intent's
-- reason during its beat).
local function Prepared()
 local m=Nexus.Panel and Nexus.Panel._lastModel or {}
 return tostring(m.recommendation or ''):find('reveal three Echoes',1,true)~=nil
end
-- The souvenir is re-published with the same card (a new parse, the same
-- board signature) after the reveal intent is prepared, and that parse armed
-- the timer for the souvenir. Nexus must not send the reveal before the timer
-- has fired: the timer then picks the souvenir, and no reveal is sent.
ctx=Boot({auto=false})
SlashCmdList.NEXUS('auto')
for _=1,200 do
 if Prepared() or #ctx.reveals>0 then break end
 ctx.H.Advance(.05)
end
check(Prepared() and #ctx.reveals==0,'fixture: a reveal is prepared and not yet sent')
ctx.H.perks.currentChoice={Souvenir(Z)};ctx.H.Notify()
NativeArm(ctx,Z)
ctx.H.Advance(3)
check(ctx.nativeSelects==1,'fixture: the native timer picked the souvenir')
check(#ctx.reveals==0,'no reveal is sent on a choice the game just parsed: '..#ctx.reveals)
check(ctx.selects==0,'and Nexus sends no Select of its own')
-- The revealed board's parse armed the timer for a card the game wants: the
-- timer picks it; Nexus does not pick a second card.
ctx=Boot({})
Reply(ctx,{Card(A1),Card(X),Card(A2)})
NativeArm(ctx,A1)
ctx.H.Advance(3)
check(ctx.nativeSelects==1 and ctx.selects==0,'the native pick on the revealed board is not doubled: '
 ..tostring(ctx.nativeSelects)..' '..ctx.selects)
-- A timer whose card is gone (armed on the souvenir, fired after the reply):
-- refused by the game; Nexus then chooses from the revealed board.
ctx=Boot({})
NativeArm(ctx,Z)
Reply(ctx,{Card(A1),Card(X),Card(A2)})
ctx.H.Advance(3)
check(ctx.nativeRefused==1 and Takes(ctx,X)==1,'a timer for the given-up souvenir is refused; Nexus takes the needed Echo')

-- 13. One long frame (adversarial order: Nexus's frames run before the
-- timer's in every frame). After frames summing under 0.18 s, a single frame
-- of 1.2 s makes the re-published souvenir settled for the first time. A
-- reveal sent in that frame would be followed in the same frame by the
-- timer's Select of the souvenir (the reveal sets no client flag).
-- 13a. Adapter level: a caller acting in that very frame. RevealMemory admits
-- a choice only on a frame strictly later than the first settled frame.
do
 local c=Boot({auto=false})
 local A=Nexus.GameAdapter
 local ok={verify=function() return true end,final=function() return true end}
 c.H.perks.currentChoice={Souvenir(Z)}       -- a fresh parse of the souvenir
 A.Board()                                   -- its first observation
 check(A.Board().revealSettling==true,'adapter: the fresh souvenir is settling')
 local caller=CreateFrame('Frame')           -- runs before the timer frame
 caller:SetScript('OnUpdate',function(_,elapsed)
  if elapsed>=1 and not c.called then
   c.called=true;A.Board();c.first={A.RevealMemory(Z,ok)}
  elseif c.called and not c.again then
   c.again=true;A.Board();c.second={A.RevealMemory(Z,ok)}
  end
 end)
 caller:Show()
 NativeArm(c,Z)
 c.H.Advance(.05,.05)
 c.H.Advance(1.2,1.2)
 check(c.called and c.first[1]==false and c.first[2]=='reveal_not_settled',
  'adapter: no reveal in the first settled frame: '..tostring(c.first and c.first[2]))
 check(c.nativeSelects==1 and #c.reveals==0,'adapter: the timer picked the souvenir in that frame; no reveal: '..#c.reveals)
 c.H.Advance(.05,.05)
 check(c.again and c.second[1]==false and #c.reveals==0,
  'adapter: the next frame refuses too (the native pick is pending): '..tostring(c.second and c.second[2]))
 caller:Hide()
end
-- 13b. Runtime level, the same frame shape. Layered: the runtime only
-- prepares in the first settled frame (0.4 s beat) and supersedes a prepared
-- intent when it reads an unsettled choice, so this passes on the earlier
-- candidate too; it pins the end-to-end outcome.
ctx=Boot({auto=false})
SlashCmdList.NEXUS('auto')
for _=1,200 do
 if Prepared() or #ctx.reveals>0 then break end
 ctx.H.Advance(.05)
end
check(Prepared() and #ctx.reveals==0,'long frame fixture: a reveal is prepared and not yet sent')
ctx.H.perks.currentChoice={Souvenir(Z)};ctx.H.Notify()
NativeArm(ctx,Z)
ctx.H.Advance(.05,.05)
check(#ctx.reveals==0 and (ctx.nativeSelects or 0)==0,'long frame fixture: nothing has fired yet')
ctx.H.Advance(1.2,1.2)
check(ctx.nativeSelects==1,'long frame: the native timer picked the souvenir in that frame')
check(#ctx.reveals==0,'long frame: no reveal in the frame the choice first settled: '..#ctx.reveals)
ctx.H.Advance(3)
check(#ctx.reveals==0 and ctx.selects==0,'long frame: none later either (the native pick is pending)')
-- The revealed board in one long frame: one pick only. Layered: the intent
-- beat, the bound-Take settle and the shared Select flag each separate the
-- two picks here (see the mutation record).
ctx=Boot({})
Reply(ctx,{Card(A1),Card(X),Card(A2)})
NativeArm(ctx,A1)
ctx.H.Advance(.05,.05)
ctx.H.Advance(1.2,1.2)
ctx.H.Advance(3)
check(ctx.nativeSelects==1 and ctx.selects==0,'long frame on the revealed board: one pick: '
 ..tostring(ctx.nativeSelects)..' '..ctx.selects)

-- 14. The one-reveal-per-draw key names the run (adapter level). A souvenir
-- draw with the same card, pending count and owned total in a later run is
-- revealable again; in the same run it stays given up.
local function DirectReveal(runBoundary)
 local c=Boot({auto=false})
 local A=Nexus.GameAdapter
 local ok={verify=function() return true end,final=function() return true end}
 A.Board();c.H.Advance(1.2);A.Board();c.H.Advance(.05)
 check(A.Board().revealable==true,'direct: the souvenir is revealable')
 check(A.RevealMemory(Z,ok)==true and #c.reveals==1,'direct: first reveal sent')
 c.H.Advance(12)   -- no reply: the window passes
 if runBoundary then A.RunBoundaryReset() end
 c.H.perks.currentChoice={Souvenir(Z)}
 A.Board();c.H.Advance(1.2);A.Board();c.H.Advance(.05)
 return c,A.Board(),A.RevealMemory(Z,ok)
end
do
 local c,board,sent=DirectReveal(false)
 check(board.revealSent==true and board.revealable==nil and sent==false and #c.reveals==1,
  'same run: the same draw stays given up and is not revealed again')
 c,board,sent=DirectReveal(true)
 check(board.revealSent==nil and board.revealable==true,'after a run boundary the draw is not marked given up')
 check(sent==true and #c.reveals==2,'and it is revealed in the new run: '..#c.reveals)
end

-- A revealed board's binding does not survive a run boundary.
do
 local c=Boot({})
 Reply(c,{Card(A1),Card(A2),Card(A3)})
 check(Nexus.GameAdapter.Board().revealBound==true,'fixture: the reply is bound')
 -- Hold the Take (a foreign Select latch) so the board stays shown.
 c.H.perks.pendingSelectSpellId=A3
 c.H.Advance(.05)
 check(Nexus.GameAdapter.Board().revealBound==true,'fixture: still bound while held')
 Nexus.GameAdapter.RunBoundaryReset()
 check(Nexus.GameAdapter.Board().revealBound==nil,'a run boundary ends the binding')
 c.H.perks.pendingSelectSpellId=nil
end

-- 11. Ordinary admission (restored 2026-11-17): a three-card board that no
-- reveal of Nexus produced is an ordinary draw; its needed Echo is taken once
-- it is actionable, and no reveal is sent. (Before: not chosen from.)
ctx=Boot({board={Card(X),Card(A1),Card(A2)}});ctx.H.Advance(5)
check(Takes(ctx,X)==1 and ctx.selects==1 and #ctx.reveals==0,
 'an unbound three-card board is an ordinary draw: one Take of the needed Echo: '..ctx.selects)

_G.ProjectEbonholdOptionsService=nil
print('PASS souvenir reveal: one request per unneeded souvenir; its bound reply chosen from without a search; unbound three-card boards are ordinary draws ('..checks..' checks)')
