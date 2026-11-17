-- Souvenir stage on the updated provider: automation does not stall on it.
--
-- Client reference: a STATIC READING of one captured client, offline only; no
-- native result, no server behavior proven. User-provided wow.export
-- extraction of patch-4.MPQ, interface/addons/projectebonhold/modules/perks
-- (the wow.export tool version is not recorded with this extraction; files
-- dated 2026-11-17):
--   perks.lua         SHA-256 43e28daef02a1f95d344eaca880bde2ce1794a0e821113837c5bfc5d5b98b8a2
--                     ("Memory stage" comment above ChoicesAreMemoryStage;
--                     LayoutMemoryStage places carried cards beside it)
--   perks_service.lua SHA-256 3303632eedb997f121b6ac5fa155bd6041b3f17190d71fb7c8b71dd670bd7c51
--                     (flag 3 -> isGuaranteed / memoryRemaining; a fourth
--                     parsed card is dropped; same bytes as CONTRACTS.md pins)
-- As read there: a draw on a loadout that remembers a finished build opens
-- with the souvenir (flag 3), alone or beside carried cards; the three random
-- cards stay hidden until the player gives it up (REQUEST_PERK_MEMORY_DRAW).
-- Nothing of the client is executed or copied here.
--
-- Before this fix EchoWeaver waited for a three-card board, so a souvenir
-- stage never got a decision even when the souvenir was a needed Wishlist
-- Echo and the adapter already admits exactly that Take. Expected here:
--   * a needed souvenir is taken (the one admitted updated-client action);
--   * any other souvenir board (not requested, already owned, covered by a
--     lock, a different spell of the wished family, two flagged cards) is left
--     to the player with the stated souvenir reason, and nothing is sent;
--   * Nexus never gives the souvenir up (no memory draw request);
--   * the existing guards still hold: a pending native pick and an Orb hold
--     send nothing, and a souvenir flag that disappears after the Take is
--     entered (before the native Select) is refused at the send boundary;
--   * the older provider keeps its earlier behavior (no souvenir rule).
-- Real TOC boot (harness), real Wishlist/runtime/EchoWeaver/adapter path;
-- synthetic services and SYNTHETIC ids only. Expected outcomes are written
-- per case; no product helper is the oracle.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local X,Y,X2=200001,200002,200091
local REASON='souvenir: take it or draw three random Echoes; the choice is left to the player'

local function Run(label,spec)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2
 H.granted={}
 for id,n in pairs(spec.owned or {}) do
  H.granted[H.names[id]]={}
  for _=1,n do table.insert(H.granted[H.names[id]],{spellId=id,quality=id%4}) end
 end
 H.locked=spec.locked or {}
 if spec.updated then H.service.GetServerActiveDesign=function() return 0 end end
 if spec.setup then spec.setup(H) end
 -- Any memory draw request would go through the client's sender.
 local sent={}
 ProjectEbonhold.CS=ProjectEbonhold.CS or {}
 ProjectEbonhold.CS.REQUEST_PERK_MEMORY_DRAW=ProjectEbonhold.CS.REQUEST_PERK_MEMORY_DRAW or 'REQUEST_PERK_MEMORY_DRAW'
 ProjectEbonhold.sendToServer=function(op,payload) sent[#sent+1]={op,payload} end
 -- Count every call that reaches the native Select, accepted or not.
 local selects=0
 local select=H.service.SelectPerk
 H.service.SelectPerk=function(...) selects=selects+1;return select(...) end
 H.Boot()
 local A=Nexus.GameAdapter
 local ctx={}
 if spec.afterBoot then spec.afterBoot(H,ctx) end
 check(A.SetFirstLoadoutWishlistIdentity('Synthetic Souvenir',spec.echoes
  or {{spellId=X,quality=X%4,stacks=1},{spellId=Y,quality=Y%4,stacks=1}},spec.design or {})==true,
  label..': fixture: the plan is set')
 H.Board(spec.board)
 if spec.beforeAuto then spec.beforeAuto(H) end
 H.Notify();H.Advance(.5)
 local a0=#H.actions
 SlashCmdList.NEXUS('auto');H.Advance(1.2)
 local first=H.actions[a0+1]
 local log=Nexus.DiagnosticLogs.Snapshot('decision')
 local last=log[#log] or {}
 local tookProposed=nil
 for _,e in ipairs(log) do
  local p=e.proposal
  if p and p.type=='take' then tookProposed=p.spellId end
 end
 return {action=first and first[1],id=first and first[2],actions=#H.actions-a0,sent=#sent,selects=selects,
  reason=tostring((last.proposal or {}).reason or ''),
  proposal=last.proposal or {},tookProposed=tookProposed,ctx=ctx,board=Nexus.GameAdapter.Board(),H=H}
end

local function Souvenir(id,extra)
 local c={spellId=id,quality=id%4,isGuaranteed=true,memoryRemaining=1}
 for k,v in pairs(extra or {}) do c[k]=v end
 return c
end
local function Took(r,id) return r.action=='take' and r.id==id and r.actions==1 end
local function HandedOff(r,label)
 check(r.actions==0,label..': nothing is taken, rerolled, banished or frozen: '..tostring(r.action)..' '..tostring(r.id))
 check(r.sent==0,label..': the souvenir is never given up automatically')
 check(r.reason==REASON,label..': the decision states the souvenir hand-off: '..r.reason)
end
local function row(id,stacks,locked) local r={spellId=id,quality=id%4,stacks=stacks or 1};if locked~=nil then r.locked=locked end;return r end

-- 1. Updated provider, the souvenir alone and needed: it is taken, once.
do
 local r=Run('needed souvenir',{updated=true,board={Souvenir(X)}})
 check(r.board and r.board.memoryStage==true,'the adapter marks the souvenir stage')
 check(r.selects==1,'positive control: exactly one native Select')
 check(Took(r,X),'a needed souvenir is taken: '..tostring(r.action)..' '..tostring(r.id)..' / '..r.reason)
 check(r.sent==0,'no memory draw is requested')
end

-- 2. Updated provider, the souvenir alone and not on the Wishlist.
HandedOff(Run('unrequested souvenir',{updated=true,board={Souvenir(200030)}}),'unrequested souvenir')

-- 3. Updated provider, a needed carried card beside an unneeded souvenir: the
-- carried card is not taken (that gives the souvenir up).
HandedOff(Run('carried beside souvenir',{updated=true,
 board={{spellId=X,quality=X%4,isCarried=true},Souvenir(200030)}}),'carried beside souvenir')

-- 4. Control (expected to pass before the fix too, through the ordinary
-- three-card planner: by reading, not executed on the base source): a needed
-- souvenir beside two carried cards is taken.
do
 local r=Run('needed souvenir with carried',{updated=true,
  board={{spellId=200031,quality=1,isCarried=true},{spellId=200032,quality=2,isCarried=true},Souvenir(Y)}})
 check(Took(r,Y),'control: the needed souvenir is taken: '..tostring(r.action)..' '..tostring(r.id)..' / '..r.reason)
 check(r.sent==0,'no memory draw is requested')
end

-- 5. Older provider control: a lone flagged card keeps the earlier wait (the
-- souvenir rule needs the updated provider's memory card contract).
do
 local r=Run('older provider',{updated=false,board={Souvenir(X)}})
 check(r.board and r.board.memoryStage==nil,'older provider: no souvenir stage is marked')
 check(r.actions==0,'older provider: a one-card board is still not acted on: '..tostring(r.action))
 check(r.reason=='waiting for three-card board','older provider: the earlier wait: '..r.reason)
end

-- 6. Requested, but its copy is already owned: not needed, so not taken.
HandedOff(Run('owned souvenir',{updated=true,owned={[X]=1},board={Souvenir(X)}}),'requested souvenir already owned')

-- 7. A locked target covered by a current lock (explicit roles): not needed.
HandedOff(Run('lock-covered souvenir',{updated=true,locked={{spellId=X,stacks=1}},
 echoes={row(Y,1,false)},
 design={[X]={version=1,copies=1,rows={{spellId=X,quality=X%4,stacks=1,locked=true,sourceRole='locked'}}}},
 board={Souvenir(X)}}),'souvenir covered by a lock')

-- 8. A different spell of the wished family (another quality): not the
-- requested spell, so not taken.
HandedOff(Run('same family, other spell',{updated=true,
 setup=function(H) H.AddEcho(X2,H.names[X],(X%4+2)%4,5) end,
 board={Souvenir(X2)}}),'same-family souvenir of another spell and quality')

-- 9. Two flagged cards, both needed: the souvenir is ambiguous; nothing is sent.
HandedOff(Run('two flagged',{updated=true,board={Souvenir(X),Souvenir(Y)}}),'two flagged cards')

-- 10. Existing guards on the admitted Take still hold.
do
 local r=Run('pending native pick',{updated=true,board={Souvenir(X)},
  beforeAuto=function(H) H.perks.pendingSelectSpellId=Y end})
 check(r.actions==0 and r.sent==0 and r.selects==0,'a pending native pick: Select is never called: '..r.selects)
 r=Run('Orb state unknown',{updated=true,board={Souvenir(X)},
  setup=function() ProjectEbonhold.OrbService={IsStateKnown=function() return false end,
   GetCharges=function() return 0 end,IsOfferPending=function() return false end,RequestCharges=function() end} end})
 check(r.actions==0 and r.sent==0 and r.selects==0,'an unknown Orb state holds the souvenir Take: '..r.selects)
 check(r.reason=='Orb state active or unknown','and the Orb hold is the stated reason: '..r.reason)
 -- The flag is cleared only once GameAdapter.Take has been entered (its
 -- entry admission passed), at its granted read before the native Select;
 -- the earlier ownership reads see the souvenir, so the planner decides it.
 r=Run('flag cleared inside the Take',{updated=true,board={Souvenir(X)},
  afterBoot=function(H,ctx)
   local take=Nexus.GameAdapter.Take
   Nexus.GameAdapter.Take=function(...)
    ctx.entered=(ctx.entered or 0)+1
    local res={take(...)}
    ctx.result=res
    return unpack(res)
   end
   local old=H.service.GetGrantedPerks
   H.service.GetGrantedPerks=function(...)
    if ctx.entered and not ctx.cleared and H.perks.currentChoice and H.perks.currentChoice[1] then
     ctx.cleared=true;H.perks.currentChoice[1].isGuaranteed=false
    end
    return old(...)
   end
  end})
 check(r.tookProposed==X,'the planner decided the souvenir Take: '..tostring(r.tookProposed))
 check(r.ctx.entered==1 and r.ctx.cleared==true,'the Take was entered once and the flag cleared inside it: '
  ..tostring(r.ctx.entered)..' '..tostring(r.ctx.cleared))
 check(r.ctx.result and r.ctx.result[1]==false
  and r.ctx.result[2]=='the memory card state is not known; the choice is left to the player',
  'the send boundary refused the Take: '..tostring(r.ctx.result and r.ctx.result[2]))
 check(r.actions==0 and r.sent==0 and r.selects==0,'a souvenir flag that disappears inside the Take: Select is never called: '..r.selects)
end

-- 11. Planner unit checks (no runtime): an unselectable souvenir and a pending
-- action are not taken; a selectable needed souvenir is (positive control).
do
 local E=Nexus.EchoWeaver
 local function S(card,extra)
  local s={level=40,owned={synced=true,bySpell={}},locked={synced=true,bySpell={}},
   plan={requestedCounts={[X]=1}},horizon=3,charges={banish=5,freeze=3,reroll=2,trustworthy=true},
   board={memoryStage=true,cards={card}}}
  for k,v in pairs(extra or {}) do s[k]=v end
  return s
 end
 local d=E.DecideNexus(S({spellId=X,quality=1,isGuaranteed=true}))
 check(d.type=='take' and d.index==1 and d.spellId==X,'unit control: a needed souvenir is taken')
 d=E.DecideNexus(S({spellId=X,quality=1,isGuaranteed=true,selectable=false}))
 check(d.type=='wait' and d.reason==REASON,'unit: an unselectable souvenir is left to the player')
 d=E.DecideNexus(S({spellId=X,quality=1,isGuaranteed=true},{pendingAction={}}))
 check(d.type=='wait' and d.reason=='waiting for action confirmation','unit: a pending action waits first')
end

print('PASS souvenir stage: needed souvenir taken, others left to the player, never given up ('..checks..' checks)')
