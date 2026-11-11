local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2;H.Boot()
local A=Nexus.GameAdapter;local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
check(A.SetFirstLoadoutWishlistIdentity('EchoWeaver planned',{ {spellId=200001,quality=1,stacks=2} }),'set first run plan')
H.Board({{spellId=200001,quality=1},{spellId=200001,quality=1},{spellId=200021,quality=1}})
H.Notify();H.Advance(.5)
check(A.Wishlist()~=nil,'real first-run target resolves')
SlashCmdList.NEXUS('auto');H.Advance(1.2)
local freeze
for _,a in ipairs(H.actions)do if a[1]=='freeze'then freeze=a end end
if not freeze then
 for _,m in ipairs(H.chat)do print('CHAT',m)end
 SlashCmdList.NEXUS('state');for i=math.max(1,#H.chat-12),#H.chat do print('STATE',H.chat[i])end
end
check(freeze and freeze[2]==0,'real automation submitted reference Freeze with zero-based wire index')
local count=#H.actions;H.Advance(.6);check(#H.actions==count,'pending action not duplicated')
-- New controls retain the resource preference without toggling global automation.
SlashCmdList.NEXUS('reroll off');SlashCmdList.NEXUS('freeze off')
check(Nexus.Store.Settings().autoReroll==false and Nexus.Store.Settings().autoFreeze==false,'new commands persist preferences')
ProjectEbonhold.OrbService={IsStateKnown=function()return true end,IsOfferPending=function()return true end}
check(not A.OrdinaryBoardAllowed(),'Orb active recognized')
for _,entry in ipairs({{A.Take,200001},{A.Banish,1},{A.Freeze,1},{A.Reroll}})do
 local ok=entry[1](entry[2]);check(ok==false,'ordinary action blocked while Orb active')
end
check(#H.actions==count,'Orb guard performs no extra actions')
ProjectEbonhold.OrbService={};check(not A.OrdinaryBoardAllowed(),'unknown Orb state blocked')
ProjectEbonhold.OrbService={IsStateKnown=function()return true end,IsOfferPending=function()return false end};check(A.OrdinaryBoardAllowed(),'inactive Orb preserves ordinary board')
-- LEVELING_RARITY: optional rarity-first pick while leveling with no Wishlist.
-- Real TOC boot, adapter, runtime and slash commands; synthetic game surface.
local function LBoot(level,before)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local L=dofile('tests/prototype/harness.lua');L.pendingRolls=40;L.playerLevel=level or 2
 if before then before(L) end
 L.Boot();return L
end
local function Kinds(L)local k={};for _,a in ipairs(L.actions)do k[a[1]]=(k[a[1]] or 0)+1 end;return k end
local function TakeIds(L)local t={};for _,a in ipairs(L.actions)do if a[1]=='take' then t[#t+1]=a[2] end end;return t end
local LBOARD={{spellId=200001,quality=1},{spellId=200004,quality=4},{spellId=200002,quality=2}}
do
 local L=LBoot(2);local LA=Nexus.GameAdapter
 local a=LA.AssignedWishlist()
 check(a.state=='unassigned' and a.knownUnassigned==true and type(a.unassignedKey)=='string',
  'fixture: no Wishlist is positively known unassigned: '..tostring(a.state)..' / '..tostring(a.note))
 check(Nexus.Store.Settings().autoPickLeveling==nil,'first install: the option is absent (OFF)')
 L.Board(LBOARD);L.Notify();L.Advance(.5)
 local board=LA.Board()
 check(board.cards[2].observedQuality==4 and board.cards[1].observedQuality==1,'the board carries the observed rarity')
 -- OLD counterfactual: Auto ON with no Wishlist and the option absent takes nothing.
 SlashCmdList.NEXUS('auto');L.Advance(2)
 check(Nexus.RecomputeStats().autoEnabled and #TakeIds(L)==0,'option absent: Auto ON with no Wishlist takes nothing')
 SlashCmdList.NEXUS('auto')
 SlashCmdList.NEXUS('leveling on')
 check(Nexus.Store.Settings().autoPickLeveling==true and NexusDB.settings.autoPickLeveling==true,'the explicit setter saves exactly true')
 check(not Nexus.RecomputeStats().autoEnabled,'turning the option on never turns Auto ON')
 L.Advance(2);check(#TakeIds(L)==0,'option ON, Auto OFF: no Take')
 SlashCmdList.NEXUS('auto');L.Advance(.25)
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='prepared' and #TakeIds(L)==0,'one prepared beat first')
 L.Advance(1)
 local ids=TakeIds(L)
 check(#ids==1 and ids[1]==200004,'one Take of the current highest rarity: '..tostring(ids[1]))
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='submitted','the Take is submitted through the existing lifecycle')
 local k=Kinds(L)
 check(k.banish==nil and k.freeze==nil and k.reroll==nil and k.save==nil and k.lock==nil and k.toggle==nil and k.activate==nil and k['orb-spend']==nil,
  'no reroll, banish, freeze, save, lock, tome, activation or Orb call')
 L.Advance(3);check(#TakeIds(L)==1,'the submitted Take is not resent')
 -- Submitted at 79-equivalent, then the mode is switched OFF: no cancel or replay.
 SlashCmdList.NEXUS('leveling off');L.Advance(3)
 check(#TakeIds(L)==1 and Nexus.Store.Settings().autoPickLeveling==false,'switching OFF cancels and replays nothing')
end
-- Level 1, 0, 80 and 81: no mode submission, no tome setup, no Save.
for _,lv in ipairs({1,0,80,81}) do
 local L=LBoot(lv)
 SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
 local k=Kinds(L)
 check(k.take==nil and k.toggle==nil and k.save==nil,'level '..lv..': no Take, tome change or Save')
end
-- Level 79: one eligible Take.
do
 local L=LBoot(79);SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(1.5)
 local ids=TakeIds(L);check(#ids==1 and ids[1]==200004,'level 79: one highest-rarity Take')
end
-- Level 79 prepared, then live level 80 before the beat: superseded, no Take.
do
 local L=LBoot(79);SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(.25)
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='prepared','fixture: prepared at 79')
 L.playerLevel=80;L.Advance(2)
 check(#TakeIds(L)==0 and Nexus.RecomputeStats().lastActionLifecycle.state=='superseded','the prepared intent is superseded at 80')
end
-- Unknown rarity on one offer: the whole board is refused (no Common fallback).
do
 local L=LBoot(10);SlashCmdList.NEXUS('leveling on')
 L.Board({{spellId=200001,quality=1},{spellId=200004},{spellId=200002,quality=2}});L.Notify()
 SlashCmdList.NEXUS('auto');L.Advance(3)
 check(#TakeIds(L)==0,'an offer with unknown rarity refuses the board')
end
-- Same signature, quality-only winner change before submission.
do
 local L=LBoot(10);SlashCmdList.NEXUS('leveling on')
 L.Board({{spellId=200001,quality=1},{spellId=200004,quality=4},{spellId=200003,quality=3}});L.Notify()
 SlashCmdList.NEXUS('auto');L.Advance(.25)
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='prepared','fixture: prepared for the quality 4 offer')
 L.perks.currentChoice[2].quality=0 -- same spells and flags: the signature is unchanged
 L.Advance(2)
 for _,id in ipairs(TakeIds(L)) do check(id~=200004,'the stale winner is never submitted') end
end
-- Assignment becomes known between prepare and submit: the stale mode intent never submits.
do
 local L=LBoot(10);SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify()
 SlashCmdList.NEXUS('auto');L.Advance(.25)
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='prepared','fixture: mode intent prepared')
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Late plan',{{spellId=200001,quality=1,stacks=2}}),'a Wishlist is assigned')
 L.Advance(2)
 for _,id in ipairs(TakeIds(L)) do check(id~=200004,'no rarity Take after a Wishlist is assigned') end
end
-- Reentrant drift: a pre-submit read assigns a Wishlist; no stale Take.
do
 local L=LBoot(10);SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify()
 SlashCmdList.NEXUS('auto');L.Advance(.25)
 local LA=Nexus.GameAdapter;local board=LA.Board;local fired=false
 LA.Board=function(...)
  if not fired then fired=true;LA.SetFirstLoadoutWishlistIdentity('Reentrant plan',{{spellId=200001,quality=1,stacks=2}}) end
  return board(...)
 end
 L.Advance(.5);LA.Board=board
 for _,id in ipairs(TakeIds(L)) do check(id~=200004,'a reentrant assignment refuses the prepared rarity Take') end
end
-- A valid assigned Wishlist keeps its planner: no rarity substitution.
do
 local L=LBoot(10);SlashCmdList.NEXUS('leveling on')
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Planner plan',{{spellId=200001,quality=1,stacks=2}}),'plan assigned')
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.knownUnassigned==nil,'an assigned Wishlist is never known unassigned: '..tostring(a.state))
 L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
 for _,id in ipairs(TakeIds(L)) do check(id~=200004,'the planner, not the rarity rule, decides') end
end
-- autoPick false: no Take even with the option and Auto ON.
do
 local L=LBoot(10);SlashCmdList.NEXUS('leveling on');Nexus.Store.Settings().autoPick=false
 L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
 check(#TakeIds(L)==0,'autoPick false: no Take')
end
-- A malformed saved option value is OFF.
do
 local L=LBoot(10,function()NexusDB=nil end);Nexus.Store.Settings().autoPickLeveling='yes'
 L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
 check(#TakeIds(L)==0,'a non-boolean option value is OFF')
end
-- RANDOM_ROLL_SHOWN: the panel model's display-only randomRoll fact and the
-- Play header's Wishlist line that words it, from the real runtime, Main and
-- panel. The fact is exactly true only while Random Roll is what picks now
-- (the exact option, Auto ON, autoPick, no Wishlist, levels 2-79, nothing
-- pausing or holding it) and absent otherwise; it changes nothing that is taken.
-- The line says "Auto-pick by rarity (ON)" only from that fact. While the
-- option is on and nothing is positively assigned, it names the mode with the
-- reason it is not picking (rarity_auto_pick_mode); otherwise None assigned.
do
 local ACTIVE,NONE='Auto-pick by rarity (ON)','Wishlist: None assigned'
 local function Mode(state) return 'Auto-pick by rarity ('..state..')' end
 local function Shown() local m=Nexus.Panel._lastModel;return type(m)=='table' and m.randomRoll or nil end
 local function Line() return NexusPanel and NexusPanel._contextWishlist and NexusPanel._contextWishlist:GetText() or nil end
 local function Is(want,label,line)
  check(Shown()==(want and true or nil) and Line()==(want and ACTIVE or line or NONE),
   'Random rolling shown, '..label..': '..tostring(Shown())..' / '..tostring(Line()))
 end
 -- Between boards: every fact is needed, and each one taken away ends it.
 local L=LBoot(10);L.Advance(.5)
 Is(false,'first install, Auto OFF, option absent')
 SlashCmdList.NEXUS('auto');L.Advance(.5)
 Is(false,'Auto ON, option absent')
 SlashCmdList.NEXUS('auto');SlashCmdList.NEXUS('leveling on');L.Advance(.5)
 Is(false,'option on, Auto OFF',Mode('Auto OFF'))
 SlashCmdList.NEXUS('auto');L.Advance(.5)
 Is(true,'option on, Auto ON, between boards')
 SlashCmdList.NEXUS('pause');L.Advance(.5)
 check(Nexus.SessionPause.IsPaused()==true and Line()==Mode('paused'),'Random rolling shown, session pause: the mode says paused: '..tostring(Line()))
 Nexus.SessionPause.Resume();L.Advance(.5)
 check(Nexus.SessionPause.IsPaused()~=true,'fixture: the session pause ended')
 Is(true,'after Resume')
 local orb=ProjectEbonhold.OrbService
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,IsOfferPending=function()return true end};L.Advance(.5)
 Is(false,'an Orb offer pending',Mode('waiting'))
 ProjectEbonhold.OrbService={};L.Advance(.5)
 Is(false,'an unknown Orb state',Mode('waiting'))
 ProjectEbonhold.OrbService=orb;L.Advance(.5)
 Is(true,'the Orb state idle again')
 -- autoPick has no in-game switch: the fixture writes it, and the option's
 -- own setter (already on) requests the next step.
 Nexus.Store.Settings().autoPick=false;SlashCmdList.NEXUS('leveling on');L.Advance(.5)
 Is(false,'autoPick false',Mode('autoPick off'))
 Nexus.Store.Settings().autoPick=true;SlashCmdList.NEXUS('leveling on');L.Advance(.5)
 Is(true,'autoPick true again')
 SlashCmdList.NEXUS('leveling off');L.Advance(.5)
 Is(false,'option OFF')
 SlashCmdList.NEXUS('leveling on');L.Advance(.5)
 Is(true,'option on again')
 L.playerLevel=80;L.Fire('PLAYER_LEVEL_UP',80);L.Advance(.5)
 Is(false,'level 80',Mode('levels 2-79 only'))
 L.playerLevel=79;L.Fire('PLAYER_LEVEL_UP',79);L.Advance(.5)
 Is(true,'level 79')
 -- The runtime renders nothing for a toggle: the panel renders its last
 -- model again with the new selection, at once.
 SlashCmdList.NEXUS('auto')
 check(not Nexus.RecomputeStats().autoEnabled and Line()==Mode('Auto OFF') and Nexus.Panel._lastModel.auto==false,
  'Random rolling shown, Auto OFF again: the line says Auto OFF at once: '..tostring(Line()))
 L.Advance(.5)
 check(Line()==Mode('Auto OFF'),'Random rolling shown, Auto OFF again, later: '..tostring(Line()))
 check(#L.actions==0,'Random rolling shown: no action without a board')
 -- A board: Random Roll's recommendation with Auto OFF is a recommendation
 -- only; with Auto ON it is Random Roll's own Take, from the prepared beat.
 L.Board(LBOARD);L.Notify();L.Advance(.5)
 Is(false,'a board with Auto OFF (a recommendation only)',Mode('Auto OFF'))
 SlashCmdList.NEXUS('auto');L.Advance(.25)
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='prepared' and #TakeIds(L)==0,'fixture: one prepared beat first')
 Is(true,'a board with Auto ON, prepared')
 L.Advance(1)
 local ids=TakeIds(L)
 check(#ids==1 and ids[1]==200004 and #L.actions==1,'Random rolling shown: the same one Take of the highest rarity, nothing else')
end
-- A board Random Roll refuses, an assigned Wishlist and the level limits.
do
 local ACTIVE='Auto-pick by rarity (ON)'
 local function Shown() local m=Nexus.Panel._lastModel;return type(m)=='table' and m.randomRoll or nil end
 local function Line() return NexusPanel and NexusPanel._contextWishlist and NexusPanel._contextWishlist:GetText() or nil end
 local function Never(label) check(Shown()==nil and Line()~=ACTIVE,'Random rolling not shown, '..label..': '..tostring(Shown())..' / '..tostring(Line())) end
 local L=LBoot(10);SlashCmdList.NEXUS('leveling on')
 L.Board({{spellId=200001,quality=1},{spellId=200004},{spellId=200002,quality=2}});L.Notify()
 SlashCmdList.NEXUS('auto');L.Advance(1)
 Never('a board with an unknown rarity (pick manually)')
 check(#TakeIds(L)==0,'fixture: the refused board takes nothing')
 L=LBoot(10);SlashCmdList.NEXUS('leveling on');SlashCmdList.NEXUS('auto');L.Advance(.5)
 check(Shown()==true and Line()==ACTIVE,'fixture: Random rolling is shown before a Wishlist is assigned: '..tostring(Line()))
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Late plan',{{spellId=200001,quality=1,stacks=2}}),'fixture: a Wishlist is assigned')
 L.Notify();L.Advance(1)
 Never('after a Wishlist is assigned')
 check(tostring(Line()):find('Late plan',1,true)~=nil,'the Wishlist line names the assigned Wishlist: '..tostring(Line()))
 for _,lv in ipairs({1,80,81}) do
  L=LBoot(lv);SlashCmdList.NEXUS('leveling on');SlashCmdList.NEXUS('auto');L.Advance(1)
  Never('level '..lv..' between boards')
  L.Board(LBOARD);L.Notify();L.Advance(1)
  Never('level '..lv..' with a board')
 end
end
-- OFFER_ICONS: the exact spell id of each real board card reaches the panel's
-- offer row through the real adapter, runtime, Readout.CardFacts, Main and
-- panel, and the row shows the client's own texture for that id
-- (GetSpellInfo's third return; invented paths here). A card the client has no
-- texture for keeps its empty slot, and a replaced board moves each icon with
-- its Echo. Auto is OFF: showing an icon takes, sends and toggles nothing.
do
 local L=LBoot(10)
 local real,asked=GetSpellInfo,{}
 local function Path(id) return 'Interface\\Icons\\Fixture_Echo_'..id end
 GetSpellInfo=function(id,...)
  asked[id]=(asked[id] or 0)+1
  local name=real(id,...)
  if id==200001 or id==200004 then return name,nil,Path(id) end
  return name
 end
 local function Icons(card)
  local out={}
  for _,r in ipairs({card:GetRegions()}) do
   local t=r:GetTexture()
   if type(t)=='string' then out[#out+1]=t end
  end
  return table.concat(out,' ')
 end
 local function Rows(label,want)
  local cards=NexusPanel and NexusPanel._offerCards
  local model=Nexus.Panel._lastModel
  check(type(cards)=='table' and type(model)=='table' and type(model.cards)=='table' and #model.cards==3,'offer icons, '..label..': fixture: the panel holds three offer rows')
  for i,w in ipairs(want) do
   local facts=model.cards[i].facts
   check(cards[i]:IsShown() and cards[i].name:GetText()==w[2],'offer icons, '..label..': row '..i..' shows the catalog name '..w[2]..': '..tostring(cards[i].name:GetText()))
   check(type(facts)=='table' and facts.spellId==w[1] and facts.generated==nil,'offer icons, '..label..': row '..i..'\'s facts carry the board\'s exact spell id '..w[1]..': '..tostring(type(facts)=='table' and facts.spellId))
   check(Icons(cards[i])==(w[3] and Path(w[1]) or ''),'offer icons, '..label..': row '..i..' shows '..(w[3] and 'the texture of spell '..w[1] or 'its empty slot, no texture')..': ['..Icons(cards[i])..']')
  end
 end
 L.Board(LBOARD);L.Notify();L.Advance(.5)
 Rows('first board',{{200001,'Echo 1',true},{200004,'Echo 4',true},{200002,'Echo 2',false}})
 check((asked[200001] or 0)>=1 and (asked[200004] or 0)>=1 and (asked[200002] or 0)>=1,'offer icons: each board id was looked up')
 L.Board({{spellId=200002,quality=2},{spellId=200001,quality=1},{spellId=200004,quality=4}});L.Notify();L.Advance(.5)
 Rows('replaced board',{{200002,'Echo 2',false},{200001,'Echo 1',true},{200004,'Echo 4',true}})
 check(not Nexus.RecomputeStats().autoEnabled and #L.actions==0,'offer icons: Auto stayed OFF and nothing was taken or sent')
 GetSpellInfo=real
end
-- LEVELING_RARITY3 (R2-SPEC-01/02): the FINAL adapter Take-read phase, after
-- ordinary preauthorization. Callbacks fire only while Adapter.Take runs:
-- onAssigned after its verifier's AssignedWishlist read (same key returned),
-- onBoard just before A.Take's own last board read.
-- R4C: every native Select ATTEMPT is counted before the harness delegate
-- (session_pause_auto's wrapper pattern), so the delegate's own pending
-- refusal cannot hide an attempt. `firstAttempts` is the attempt delta of the
-- exact Adapter.Take invocation in which the callback fired.
local function Counted(h)
 h.attempts=0
 local call=h.service.SelectPerk;h.service.SelectPerk=function(...)h.attempts=h.attempts+1;return call(...)end
end
local function FinalPhase(level,cards,onAssigned,onBoard,before)
 local L=LBoot(level,function(h)Counted(h);if before then before(h) end end)
 SlashCmdList.NEXUS('leveling on');L.Board(cards or LBOARD);L.Notify()
 local LA=Nexus.GameAdapter;local take,assigned,board=LA.Take,LA.AssignedWishlist,LA.Board
 local inTake,fired,entered=false,false,0
 local firstAttempts=nil
 LA.Take=function(...)
  inTake=true;entered=entered+1
  local was,a0=fired,L.attempts
  local r={take(...)};inTake=false
  if fired and not was then firstAttempts=L.attempts-a0 end
  return unpack(r)
 end
 LA.AssignedWishlist=function(...)
  local r=assigned(...)
  if inTake and onAssigned and not fired then fired=true;onAssigned(L) end
  return r
 end
 LA.Board=function(...)
  if inTake and onBoard and not fired then fired=true;onBoard(L) end
  return board(...)
 end
 SlashCmdList.NEXUS('auto');L.Advance(1.5)
 LA.Take,LA.AssignedWishlist,LA.Board=take,assigned,board
 return L,entered,fired,firstAttempts
end
local function NoOther(L,label)
 local k=Kinds(L)
 check(k.banish==nil and k.freeze==nil and k.reroll==nil and k.save==nil and k.lock==nil and k.unlock==nil
  and k.toggle==nil and k.activate==nil and k.upload==nil and k['orb-spend']==nil,label..': no reroll, banish, freeze, Orb, tome, lock, activation or Save')
end
-- Positive control: unchanged final board and authority submit exactly once.
do
 local L,entered=FinalPhase(10)
 local ids=TakeIds(L)
 check(entered>=1 and #ids==1 and ids[1]==200004,'final phase unchanged: one Take of the highest rarity')
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='submitted','final phase unchanged: submitted once')
 L.Advance(3);check(#TakeIds(L)==1,'final phase unchanged: not resent');NoOther(L,'final phase unchanged')
end
-- P1: the verifier's last AssignedWishlist read turns master Auto OFF.
do
 local L,entered,fired=FinalPhase(10,nil,function()SlashCmdList.NEXUS('auto')end)
 check(entered>=1 and fired,'fixture: Auto OFF ran inside the final Take read')
 check(not Nexus.RecomputeStats().autoEnabled and #TakeIds(L)==0,'Auto OFF inside the final read: no stale Select')
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='superseded','the revoked prepared intent stays superseded')
 L.Advance(3);check(#TakeIds(L)==0,'and nothing later');NoOther(L,'final Auto OFF')
end
-- P1: live level 79 -> 80 inside the final read.
do
 local L,entered,fired=FinalPhase(79,nil,function(h)h.playerLevel=80 end)
 check(entered>=1 and fired,'fixture: level 80 reached inside the final Take read')
 check(#TakeIds(L)==0,'level 80 inside the final read: no Select')
 L.Advance(3);check(#TakeIds(L)==0,'no Take at the cap later');NoOther(L,'final cap')
end
-- P1: a world hold starts inside the final read.
do
 local L,entered,fired=FinalPhase(10,nil,function(h)h.Fire('PLAYER_LEAVING_WORLD')end)
 check(entered>=1 and fired,'fixture: the loading screen began inside the final Take read')
 check(#TakeIds(L)==0,'world leave inside the final read: no Select');NoOther(L,'final world hold')
end
-- P1: the captured intent is superseded by another owner inside the final read
-- (a run-boundary style supersede with Auto still ON).
do
 local L,entered,fired,first=FinalPhase(10,nil,function()
  local life=Nexus.RecomputeStats().lastActionLifecycle
  check(life.state=='prepared','fixture: still prepared inside the final read')
  SlashCmdList.NEXUS('auto');SlashCmdList.NEXUS('auto') -- OFF then ON: the old intent is superseded
 end)
 check(entered>=1 and fired,'fixture: the supersede ran inside the final Take read')
 -- R4C (Standards P2): the FIRST affected invocation itself must attempt no
 -- native Select; R2 attempted exactly one here. A later fresh intent may act.
 check(first==0,'the superseded stale intent made zero native Select attempts in its own Take: '..tostring(first))
 local ids=TakeIds(L)
 check(#ids<=1,'a superseded intent does not add a second Select')
 check(Nexus.RecomputeStats().actionLifecycle.superseded>=1,'the stale intent was superseded')
 L.Advance(3)
 local later=TakeIds(L)
 check(#later<=1 and (later[1]==nil or later[1]==200004),'a later fresh intent may act once on the current winner: '..tostring(later[1]))
 NoOther(L,'final supersede')
end
-- P2: chosen A (q3) unchanged, competitor B gains q4 on the final read.
do
 local L,entered,fired=FinalPhase(10,{{spellId=200001,quality=1},{spellId=200003,quality=3},{spellId=200002,quality=2}},
  nil,function(h)h.perks.currentChoice[3].quality=4 end)
 check(entered>=1 and fired,'fixture: the competitor changed before the final board read')
 for _,id in ipairs(TakeIds(L)) do check(id~=200003,'the stale winner is never sent when a competitor rises') end
 L.Advance(3)
 local ids=TakeIds(L)
 check(#ids<=1 and (ids[1]==nil or ids[1]==200002),'at most one Take, of the new highest rarity: '..tostring(ids[1]))
 NoOther(L,'final competitor rise')
end
-- P2: a competitor ahead in order ties the chosen rarity: the first card wins.
do
 local L,entered,fired=FinalPhase(10,{{spellId=200002,quality=2},{spellId=200003,quality=3},{spellId=200001,quality=1}},
  nil,function(h)h.perks.currentChoice[1].quality=3 end)
 check(entered>=1 and fired,'fixture: a competitor ahead tied before the final board read')
 for _,id in ipairs(TakeIds(L)) do check(id~=200003,'a tie ahead in order is not lost to the stale winner') end
 L.Advance(3)
 local ids=TakeIds(L)
 check(#ids<=1 and (ids[1]==nil or ids[1]==200002),'at most one Take, of the first tied offer: '..tostring(ids[1]))
 NoOther(L,'final tie ahead')
end
-- P2: a competitor's rarity becomes malformed on the final read: the whole board is refused.
do
 local L,entered,fired=FinalPhase(10,{{spellId=200001,quality=1},{spellId=200003,quality=3},{spellId=200002,quality=2}},
  nil,function(h)h.perks.currentChoice[3].quality=nil end)
 check(entered>=1 and fired,'fixture: the competitor became malformed before the final board read')
 L.Advance(3)
 check(#TakeIds(L)==0,'an invalid competing rarity refuses the board: no Select');NoOther(L,'final malformed competitor')
end
-- R4C final-admission class, in the existing onAssigned seam: the callback runs
-- AFTER the verifier's AssignedWishlist getter returned its old (same-key)
-- projection, i.e. after A.Take copied its Board and before its native Select.
-- Chosen A = 200003 (q3) at index 2; card 1 is quality 0 (a valid Common).
local FBOARD={{spellId=200001,quality=0},{spellId=200003,quality=3},{spellId=200002,quality=2}}
local function Choice(h)return h.perks.currentChoice end
local FINAL_CASES={
 {'valid Wishlist installed by its real setter',function()
   check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Final plan',{{spellId=200001,quality=1,stacks=2}}),'fixture: the real setter succeeded')
  end,planner=true},
 {'native pending flag set to a spell (same Perks table)',function(h)h.perks.pendingSelectSpellId=200009 end},
 {'native pending flag false',function(h)h.perks.pendingSelectSpellId=false end},
 {'native pending flag 0',function(h)h.perks.pendingSelectSpellId=0 end},
 {'Perks table replaced by one with a pending flag',function(h)ProjectEbonhold.Perks={pendingSelectSpellId=false,currentChoice=h.perks.currentChoice}end},
 {'Perks table unreadable',function()ProjectEbonhold.Perks=nil end},
 {'competitor rises above the copied winner',function(h)Choice(h)[3].quality=4 end,fresh=200002},
 {'competitor ahead ties the copied winner',function(h)Choice(h)[1].quality=3 end,fresh=200001},
 {'order changes after the copy',function(h)local c=Choice(h);c[1],c[2]=c[2],c[1] end,fresh=200003},
 {'competitor quality 0 becomes missing',function(h)Choice(h)[1].quality=nil end},
 {'competitor quality becomes a numeric string',function(h)Choice(h)[3].quality='2' end},
 {'competitor quality becomes unsupported',function(h)Choice(h)[3].quality=7 end},
 {'granted mirror unreadable (nil) before the baseline',function(h)h.granted=nil end},
 {'granted read throws before the baseline',function(h)h.service.GetGrantedPerks=function()error('synthetic granted read failure')end end},
 {'master Auto OFF',function()SlashCmdList.NEXUS('auto')end},
 {'leveling mode OFF',function()SlashCmdList.NEXUS('leveling off')end},
 {'autoPick OFF',function()Nexus.Store.Settings().autoPick=false end},
 {'session pause',function()SlashCmdList.NEXUS('pause')end},
 {'loading screen',function(h)h.Fire('PLAYER_LEAVING_WORLD')end},
 {'live level reaches 80',function(h)h.playerLevel=80 end},
}
-- Unchanged positive: the same seam, no change, exactly one native attempt.
do
 local L,entered,fired,first=FinalPhase(10,FBOARD,function()end)
 check(fired and first==1,'final seam unchanged: exactly one native Select attempt: '..tostring(first))
 local ids=TakeIds(L);check(#ids==1 and ids[1]==200003,'final seam unchanged: the q3 winner is taken once')
 L.Advance(3);check(L.attempts==1,'final seam unchanged: never resent');NoOther(L,'final seam unchanged')
end
for _,case in ipairs(FINAL_CASES) do
 local L,entered,fired,first=FinalPhase(10,FBOARD,case[2])
 check(entered>=1 and fired,'fixture: '..case[1]..' ran inside the final Take read')
 check(first==0,case[1]..': the affected Take invocation attempts ZERO native Selects: '..tostring(first))
 for _,id in ipairs(TakeIds(L)) do
  if not case.fresh then check(id~=200003,case[1]..': the stale winner is never sent') end
 end
 if case.fresh then
  L.Advance(3)
  local ids=TakeIds(L)
  check(#ids<=1 and (ids[1]==nil or ids[1]==case.fresh),case[1]..': only a fresh decision on the current board may act: '..tostring(ids[1]))
 end
 if not case.planner then NoOther(L,case[1]) end
end
-- R4C ownership readiness before and at admission.
do -- never synchronized: the granted mirror never answers.
 local L=LBoot(10,function(h)Counted(h);h.granted=nil end)
 check(Nexus.GameAdapter.Owned().synced~=true,'fixture: ownership is not synchronized')
 SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
 check(L.attempts==0,'unsynchronized ownership: zero native attempts');NoOther(L,'unsynchronized ownership')
end
for _,variant in ipairs({{'nil after a prior sync',function(h)h.granted=nil end},
 {'throwing read after a prior sync',function(h)h.service.GetGrantedPerks=function()error('synthetic granted read failure')end end}}) do
 local L=LBoot(10,Counted)
 check(Nexus.GameAdapter.Owned().synced==true,'fixture: '..variant[1]..': synchronized first')
 variant[2](L)
 check(Nexus.GameAdapter.Owned().synced==true,'fixture: '..variant[1]..': the stale synced flag survives the unreadable read')
 SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
 check(L.attempts==0,variant[1]..': a stale synced flag cannot authorize a Select without a readable baseline');NoOther(L,variant[1])
end
do -- confirmed-empty current-generation ownership: one pick, then exact grant settlement.
 local L=LBoot(10,Counted)
 local o=Nexus.GameAdapter.Owned()
 check(o.synced==true and o.total==0 and type(L.granted)=='table','fixture: confirmed-empty synchronized ownership')
 SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(1.5)
 check(L.attempts==1 and TakeIds(L)[1]==200004,'confirmed empty: exactly one native attempt for the q4 offer')
 L.Advance(3);check(L.attempts==1,'confirmed empty: no resend while unresolved')
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==0,'no settlement before the exact grant')
 L.perks.pendingSelectSpellId=nil
 local g=L.Clone(L.granted) or {};g['Echo 4']=g['Echo 4'] or {};table.insert(g['Echo 4'],{spellId=200004});L.granted=g;L.Notify()
 L.Advance(1.5)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==1,'the exact grant above the captured baseline settles it once')
 L.Advance(3);check(L.attempts==1 and Nexus.RecomputeStats().actionLifecycle.confirmed==1,'settled once, never resent');NoOther(L,'confirmed empty')
end
-- R4C guard and settlement matrix (acceptance rows).
local function Sent(level,before)
 local L=LBoot(level,function(h)Counted(h);if before then before(h) end end)
 SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(1.5)
 return L
end
for _,lv in ipairs({2.5,-3}) do -- noninteger and negative levels (1/0/80/81 above)
 local L=Sent(lv);check(L.attempts==0,'level '..lv..': no mode submission');NoOther(L,'level '..lv)
end
for _,orb in ipairs({ -- the Orb ordinary gate stays authoritative
 {'known non-pending Orb service',{IsStateKnown=function()return true end,IsOfferPending=function()return false end},1},
 {'pending Orb offer',{IsStateKnown=function()return true end,IsOfferPending=function()return true end},0},
 {'unknown Orb state (no members)',{},0},
 {'Orb member throws',{IsStateKnown=function()error('synthetic Orb failure')end,IsOfferPending=function()return false end},0},
}) do
 local L=Sent(10,function()ProjectEbonhold.OrbService=orb[2] end)
 check(L.attempts==orb[3],orb[1]..': native attempts '..L.attempts..' (expected '..orb[3]..')');NoOther(L,orb[1])
end
for _,run in ipairs({{'charges 0',{remainingBanishes=0,totalRerolls=0,usedRerolls=0,totalFreezes=0,usedFreezes=0}},
 {'abundant charges',{remainingBanishes=20,totalRerolls=20,usedRerolls=0,totalFreezes=10,usedFreezes=0}},{'unknown charges',nil}}) do
 local L=Sent(10,function(h)h.run=run[2] end)
 check(L.attempts==1 and TakeIds(L)[1]==200004,run[1]..': one rarity Take, no resource action');NoOther(L,run[1])
 check(L.run==run[2],run[1]..': the charge ledger is not replaced by the selector')
end
for _,slot in ipairs({{'active slot not yet known',nil,{}},{'active Saved Build row missing',2,{}},
 {'active Saved Build without an echo list',2,{[2]={name='',verified=false}}}}) do
 local L=Sent(10,function(h)h.perks.serverActiveSlot=slot[2];h.perks.serverBuildSlots=slot[3] end)
 check(Nexus.GameAdapter.AssignedWishlist().knownUnassigned~=true,slot[1]..': never known unassigned')
 check(L.attempts==0,slot[1]..': no mode submission');NoOther(L,slot[1])
end
do -- adapter refusal: one native attempt, retained refusal, no retry on repeated notification.
 local L=LBoot(10,function(h)h.attempts=0;h.service.SelectPerk=function()h.attempts=h.attempts+1;return false end end)
 SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(1.5)
 check(L.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.state=='rejected','the refused Take is attempted once and kept rejected')
 L.Notify();L.Advance(2);L.Notify();L.Advance(2)
 check(L.attempts==1,'the same board notified again is not retried');NoOther(L,'adapter refusal')
end
do -- submitted at 79, then the cap before the grant: exact settlement once, no replay or Save.
 local L=Sent(79)
 check(L.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.state=='submitted','fixture: submitted at 79')
 L.playerLevel=80;L.Advance(3)
 check(L.attempts==1 and Nexus.RecomputeStats().actionLifecycle.confirmed==0,'at the cap: no new attempt and no invented settlement')
 L.perks.pendingSelectSpellId=nil
 local g=L.Clone(L.granted) or {};g['Echo 4']=g['Echo 4'] or {};table.insert(g['Echo 4'],{spellId=200004});L.granted=g;L.Notify()
 L.Advance(2)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==1,'the exact grant settles the cap-crossing Take once')
 L.Advance(3);check(L.attempts==1,'never replayed at the cap');NoOther(L,'submitted across the cap')
end
do -- submitted, then a loading screen: the existing world hold; the exact grant settles it.
 local L=Sent(10)
 L.Fire('PLAYER_LEAVING_WORLD')
 L.perks.pendingSelectSpellId=nil;L.Board({{spellId=200005,quality=1},{spellId=200006,quality=2},{spellId=200007,quality=0}});L.Notify();L.Advance(1)
 L.Advance(1);L.Fire('PLAYER_ENTERING_WORLD');L.Advance(14)
 check(L.attempts==1 and Nexus.RecomputeStats().actionLifecycle.confirmed==0,'held across the world change; nothing resent or confirmed')
 local g=L.Clone(L.granted) or {};g['Echo 4']=g['Echo 4'] or {};table.insert(g['Echo 4'],{spellId=200004});L.granted=g;L.Notify()
 L.Advance(1.5)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==1,'the exact grant settles the world-crossing Take once');NoOther(L,'submitted across a world change')
end
do -- a Wishlist assigned while the Take is unresolved: no cancel or replay.
 local L=Sent(10)
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('While sent',{{spellId=200001,quality=1,stacks=2}}),'fixture: Wishlist assigned while submitted')
 L.Advance(3)
 local life=Nexus.RecomputeStats().lastActionLifecycle
 check(L.attempts==1 and life.state~='superseded' and life.state~='rejected','the unresolved Take is neither cancelled nor replayed: '..tostring(life.state))
end
-- R5: the five reviewed reproductions at their ACTUAL final-admission seams.
-- `seam` is a real service getter (L.service.GetCurrentChoice /
-- GetGrantedPerks) or the identity getter (Nexus.Store.CurrentOwnerKey); the
-- mutation runs AFTER the getter returned its unchanged result, on that
-- getter's k-th call inside one Adapter.Take. `first` is that exact
-- invocation's native Select attempt delta (counted before the delegate).
local FBOARD5={{spellId=200001,quality=0},{spellId=200003,quality=3},{spellId=200002,quality=2}}
-- R6: phase-exact seams. The adapter names its current final-admission step
-- in A.LevelingAdmissionPhase; the wrapper fires on the FIRST call of the
-- named getter whose phase matches, AFTER that call returned its unchanged
-- result. `phases` lists every phase the getter was called in (proof of path).
local function Seam(level,seam,phase,mutate,cards,before,after)
 local L=LBoot(level,function(h)Counted(h);if before then before(h) end end)
 if after then after(L) end -- R9: optional real post-boot setup (stored assignments)
 SlashCmdList.NEXUS('leveling on');L.Board(cards or FBOARD5);L.Notify()
 local LA=Nexus.GameAdapter;local take=LA.Take
 local owner,store='CurrentOwnerKey',Nexus.Store
 local orig=seam=='owner' and store[owner] or L.service[seam]
 local inTake,fired,first,seen=false,false,nil,{}
 local wrapped=function(...)
  local r={orig(...)}
  if inTake then
   local p=tostring(LA.LevelingAdmissionPhase);seen[#seen+1]=p
   if p==phase and not fired then fired=true;mutate(L,r) end
  end
  return unpack(r)
 end
 if seam=='owner' then store[owner]=wrapped else L.service[seam]=wrapped end
 LA.Take=function(...)
  inTake=true;local was,a0=fired,L.attempts
  local r={take(...)};inTake=false
  if fired and not was then first=L.attempts-a0 end
  return unpack(r)
 end
 SlashCmdList.NEXUS('auto');L.Advance(1.5)
 LA.Take=take
 if seam=='owner' then store[owner]=orig else L.service[seam]=orig end
 return L,fired,first,table.concat(seen,',')
end
local function GrantOf(L,id)
 local g=L.Clone(L.granted) or {};local key='Echo '..(id-200000);g[key]=g[key] or {}
 table.insert(g[key],{spellId=id});L.granted=g;L.Notify()
end
-- Matched unchanged positives at every seam: the same wrapper and call index
-- with a no-op mutation must attempt exactly ONE Select and settle exactly once.
-- R6 matched positives: EVERY final seam, no-op at that exact phase, must be
-- reached, attempt exactly ONE Select, and settle exactly once from its exact
-- later grant (no blanket refusal can pass these).
local SEAMS={
 {'owner','entry'},{'owner','verify'},{'owner','final_owner'},
 {'GetGrantedPerks','verify'},{'GetGrantedPerks','g1'},{'GetGrantedPerks','g2'},
 {'GetCurrentChoice','board'},{'GetCurrentChoice','raw1'},{'GetCurrentChoice','raw2'},{'GetCurrentChoice','raw3'},
}
for _,s in ipairs(SEAMS) do
 local L,fired,first,path=Seam(10,s[1],s[2],function()end)
 check(fired,'R6 positive '..s[1]..'@'..s[2]..': reached (path '..path..')')
 check(first==1,'R6 positive '..s[1]..'@'..s[2]..': exactly one native attempt: '..tostring(first))
 L.perks.pendingSelectSpellId=nil;GrantOf(L,200003);L.Advance(2)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==1 and L.attempts==1,'R6 positive '..s[1]..'@'..s[2]..': settled once')
 NoOther(L,'R6 positive '..s[1]..'@'..s[2])
end
-- Known nonzero baseline positive: one pre-existing copy, then the real grant.
do
 local L,fired,first=Seam(10,'GetGrantedPerks','g2',function()end,nil,function(h)h.granted={['Echo 3']={{spellId=200003}}} end)
 check(fired and first==1 and Nexus.GameAdapter.Owned().total==1,'R6 known count 1: reached, one attempt')
 L.perks.pendingSelectSpellId=nil;L.Advance(3)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==0,'R6 known count 1: latch clear without a new grant proves nothing')
 GrantOf(L,200003);L.Advance(2)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==1 and L.attempts==1,'R6 known count 1: the second copy settles it once')
end
-- Class1 (R4C-Spec01 retained, R5-SPEC-02 related): cap or Orb revocation in
-- every late PerkService seam: zero attempts in that exact Take.
local LATE={
 {'cap 79->80',function(h)h.playerLevel=80 end,79},
 {'Orb idle->pending',function()ProjectEbonhold.OrbService={IsStateKnown=function()return true end,IsOfferPending=function()return true end}end,10},
}
for _,m in ipairs(LATE) do
 for _,s in ipairs({{'GetGrantedPerks','g1'},{'GetGrantedPerks','g2'},{'GetCurrentChoice','raw2'},{'GetCurrentChoice','raw3'}}) do
  local L,fired,first,path=Seam(m[3],s[1],s[2],m[2])
  check(fired,'Late '..m[1]..' @'..s[2]..': reached (path '..path..')')
  check(first==0,'Late '..m[1]..' @'..s[2]..': zero native attempts in the affected Take: '..tostring(first))
  NoOther(L,'Late '..m[1]..' @'..s[2])
 end
end
-- R4C-Standards01 retained, R5-STANDARDS-01: every owner/identity read
-- (entry, verifier assignment, FINAL owner) returns the same owner while the
-- native pending flag or a real valid assignment changes.
for _,m in ipairs({{'native pending',function(h)h.perks.pendingSelectSpellId=200009 end},
 {'real valid Wishlist setter',function()
   check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Owner seam plan',{{spellId=200001,quality=1,stacks=2}}),'fixture: setter ran')
  end,planner=true}}) do
 for _,phase in ipairs({'entry','verify','final_owner'}) do
  local L,fired,first,path=Seam(10,'owner',phase,m[2])
  check(fired,'Owner '..m[1]..' @'..phase..': reached (path '..path..')')
  check(first==0,'Owner '..m[1]..' @'..phase..': zero native attempts: '..tostring(first))
  for _,id in ipairs(TakeIds(L)) do check(id~=200003,'Owner '..m[1]..' @'..phase..': the stale rarity winner is never sent') end
  if not m.planner then NoOther(L,'Owner '..m[1]..' @'..phase) end
 end
end
-- R5-SPEC-01: final g2 returns the OLD readable zero table while the
-- observable mirror becomes a distinct table that already holds A. The send
-- happens, but the post-send read holds it ambiguous: a latch clear and even a
-- later grant never prove the pre-existing copy as this Select's result.
do
 local returned,observable
 local L,fired,first,path=Seam(10,'GetGrantedPerks','g2',function(h,r)
  returned=r[1]
  h.granted={['Echo 3']={{spellId=200003}}};observable=h.granted
 end)
 check(fired and type(returned)=='table' and observable~=returned,'R5-SPEC-01: g2 returned the old table and the mirror became a distinct one (path '..path..')')
 check(first==1,'R5-SPEC-01: the single send happened: '..tostring(first))
 L.perks.pendingSelectSpellId=nil;L.Advance(3)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==0,'R5-SPEC-01: latch clear with no new grant proves nothing')
 GrantOf(L,200003);L.Advance(3)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==0 and L.attempts==1,'R5-SPEC-01: held ambiguous, never confirmed or replayed')
 NoOther(L,'R5-SPEC-01')
end
-- R5-SPEC-02 (and the late class): after raw2, the final g2 read raises
-- competitor B q2->q4, ties ahead, reorders, makes a quality malformed or a
-- numeric ID a string; raw3 refuses before the Select. A fresh later
-- decision on the CURRENT board is a separate, allowed action.
for _,m in ipairs({
 {'competitor rises q2->q4',function(h)h.perks.currentChoice[3].quality=4 end,200002},
 {'competitor ahead ties',function(h)h.perks.currentChoice[1].quality=3 end,200001},
 {'order changes',function(h)local c=h.perks.currentChoice;c[1],c[2]=c[2],c[1] end,200003},
 {'competitor quality becomes missing',function(h)h.perks.currentChoice[1].quality=nil end},
 {'numeric ID becomes the same text as a string',function(h)h.perks.currentChoice[3].spellId='200002' end},
}) do
 local L,fired,first,path=Seam(10,'GetGrantedPerks','g2',m[2])
 check(fired,'R5-SPEC-02 '..m[1]..': reached g2 (path '..path..')')
 check(first==0,'R5-SPEC-02 '..m[1]..': zero native attempts in the affected Take: '..tostring(first))
 L.Advance(3)
 local ids=TakeIds(L)
 if m[3] then
  check(#ids==1 and ids[1]==m[3],'R5-SPEC-02 '..m[1]..': one later fresh Take of the current winner: '..tostring(ids[1]))
 else
  check(#ids==0,'R5-SPEC-02 '..m[1]..': the malformed board is never taken')
 end
 NoOther(L,'R5-SPEC-02 '..m[1])
end
-- R4C-Spec03 retained: a change inside the verifier's Owned or g1 read is
-- caught by raw2.
for _,phase in ipairs({'verify','g1'}) do
 local L,fired,first,path=Seam(10,'GetGrantedPerks',phase,function(h)h.perks.currentChoice[3].quality=4 end)
 check(fired and first==0,'Copy-to-mark rise @'..phase..': reached, zero attempts: '..tostring(first)..' ('..path..')')
 NoOther(L,'Copy-to-mark @'..phase)
end
-- R5-SPEC-03: each malformed RAW board is installed BEFORE any mode or Auto
-- admission; its shape is asserted; nothing is ever attempted.
for _,b in ipairs({
 {'filtered invalid raw entry plus three valid',{{quality=1},{spellId=200001,quality=0},{spellId=200003,quality=3},{spellId=200002,quality=2}}},
 {'string spell ID',{{spellId='200001',quality=0},{spellId=200003,quality=3},{spellId=200002,quality=2}}},
 {'oversized raw board',{{spellId=200001,quality=0},{spellId=200003,quality=3},{spellId=200002,quality=2},{spellId=200005,quality=1}}},
 {'sparse raw board',{{spellId=200001,quality=0},nil,{spellId=200002,quality=2}}},
 {'numeric-string quality',{{spellId=200001,quality='0'},{spellId=200003,quality=3},{spellId=200002,quality=2}}},
 {'non-finite quality',{{spellId=200001,quality=0/0},{spellId=200003,quality=3},{spellId=200002,quality=2}}},
 {'unsupported quality',{{spellId=200001,quality=9},{spellId=200003,quality=3},{spellId=200002,quality=2}}},
}) do
 local L=LBoot(10,Counted)
 L.Board(b[2]);L.Notify();L.Advance(.5)
 local board=Nexus.GameAdapter.Board()
 check(board==nil or board.strictObservation==false,'R5-SPEC-03 '..b[1]..': the raw board is not a strict observation')
 SlashCmdList.NEXUS('leveling on');SlashCmdList.NEXUS('auto');L.Advance(3)
 check(L.attempts==0,'R5-SPEC-03 '..b[1]..': refused before any admission, zero attempts');NoOther(L,'R5-SPEC-03 '..b[1])
end
do -- R5-SPEC-03 positive: valid numeric IDs with a Common 0 card take once.
 local L=LBoot(10,Counted)
 L.Board(FBOARD5);L.Notify();L.Advance(.5)
 check(Nexus.GameAdapter.Board().strictObservation==true,'R5-SPEC-03 positive: strict observation')
 SlashCmdList.NEXUS('leveling on');SlashCmdList.NEXUS('auto');L.Advance(1.5)
 check(L.attempts==1 and TakeIds(L)[1]==200003,'R5-SPEC-03 positive: exactly one Take of the q3 winner')
end
-- R5 matrix additions (A07, A11, A13, A18, A19).
do -- A07: at the cap with 78 then 79 owned, board present and absent.
 local L=LBoot(80,Counted)
 local g={};for i=2,79 do g['Echo '..i]={{spellId=200000+i}} end;L.granted=g
 Nexus.GameAdapter.RequestGranted();L.Notify();L.Advance(1)
 SlashCmdList.NEXUS('leveling on');SlashCmdList.NEXUS('auto')
 L.Board(LBOARD);L.Notify();L.Advance(3)
 check(L.attempts==0 and Kinds(L).save==nil,'A07: owned 78 at the cap, board present: no Select or Save')
 g['Echo 80']={{spellId=200080}};L.granted=L.Clone(g);L.Board({});L.Notify();L.Advance(3)
 check(L.attempts==0 and Kinds(L).save==nil,'A07: owned 79 at the cap, board absent: no Select or Save')
 NoOther(L,'A07 cap')
end
do -- A11: an explicitly fulfilled Wishlist is still a valid assignment.
 local L=LBoot(10,function(h)Counted(h);h.granted={['Echo 5']={{spellId=200005}}} end)
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Fulfilled',{{spellId=200005,quality=1,stacks=1}}),'fixture: fulfilled plan assigned')
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.knownUnassigned==nil,'A11: a fulfilled Wishlist never grants Random Roll authority: '..tostring(a.state))
end
do -- A13: a throwing or malformed assignment read grants no fallback.
 for _,bad in ipairs({{'throwing read',function()error('synthetic assignment failure')end},
  {'non-table result',function()return 'unassigned' end},
  {'unassigned without the positive flag',function()return {state='unassigned'} end}}) do
  local L=LBoot(10,Counted)
  local LA=Nexus.GameAdapter;local real=LA.AssignedWishlist;LA.AssignedWishlist=bad[2]
  SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
  LA.AssignedWishlist=real
  check(L.attempts==0,'A13 '..bad[1]..': no fallback authority');NoOther(L,'A13 '..bad[1])
 end
end
do -- A18: an Orb run that owns or holds an unresolved action blocks ordinary picks.
 local L=LBoot(10,Counted)
 SlashCmdList.NEXUS('leveling on');SlashCmdList.NEXUS('auto');L.Advance(.5)
 local orb=Nexus.OrbRuntime;local real=orb and orb.BlocksOrdinary
 check(type(real)=='function','fixture: the Orb runtime is loaded')
 orb.BlocksOrdinary=function()return true end
 L.Board(LBOARD);L.Notify();L.Advance(3)
 orb.BlocksOrdinary=real
 check(L.attempts==0,'A18: Orb-owned/unresolved state: zero attempts');NoOther(L,'A18 Orb owned')
end
do -- A19: pause during the beat supersedes the prepared pick; nothing is sent.
 local L=LBoot(10,Counted)
 SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(.25)
 check(Nexus.RecomputeStats().lastActionLifecycle.state=='prepared','fixture: prepared')
 SlashCmdList.NEXUS('pause');L.Advance(2)
 check(L.attempts==0 and Nexus.RecomputeStats().lastActionLifecycle.reason=='session_pause','A19: pause during the beat supersedes, zero attempts')
 SlashCmdList.NEXUS('resume');L.Advance(2)
 check(L.attempts==1,'A19: after Resume one fresh pick');NoOther(L,'A19 pause')
end
-- R6 complete26 additions.
for _,lv in ipairs({{'nil',nil},{'string','5'}}) do -- A06 through the real adapter/dispatch
 local L=LBoot(10,function(h)Counted(h);h.playerLevel=lv[2] end)
 check(UnitLevel('player')==lv[2],'A06 '..lv[1]..': the raw fixture level is '..tostring(lv[2]))
 SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
 check(L.attempts==0 and Kinds(L).toggle==nil and Kinds(L).save==nil,'A06 '..lv[1]..' level: no submission, tome change or Save')
end
local function OwnedTo(n)local g={};for i=2,n+1 do g['Echo '..i]={{spellId=200000+i}} end;return g end
for _,c in ipairs({{78,true},{78,false},{79,true},{79,false}}) do -- A07 full matrix
 local L=LBoot(80,function(h)Counted(h);h.granted=OwnedTo(c[1]) end)
 local o=Nexus.GameAdapter.Owned()
 check(o.synced==true and o.total==c[1],'A07 fixture: owned '..c[1]..' synchronized (total '..tostring(o.total)..')')
 if c[2] then L.Board(LBOARD) else L.Board({}) end;L.Notify();L.Advance(.5)
 check((Nexus.GameAdapter.Board()~=nil)==c[2],'A07 fixture: board '..(c[2] and 'present' or 'absent'))
 SlashCmdList.NEXUS('leveling on');SlashCmdList.NEXUS('auto');L.Advance(3)
 local k=Kinds(L)
 check(L.attempts==0 and k.save==nil and k.take==nil,'A07 owned '..c[1]..' board '..(c[2] and 'present' or 'absent')..': no Select or Save')
 NoOther(L,'A07 '..c[1])
end
do -- A10: submitted at 79, the cap and a loading screen while pending; the exact grant settles once.
 local L=Sent(79)
 check(L.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.state=='submitted','A10 fixture: submitted at 79')
 L.playerLevel=80;L.Advance(1)
 L.Fire('PLAYER_LEAVING_WORLD')
 L.perks.pendingSelectSpellId=nil;L.Board({});L.Notify();L.Advance(1)
 L.Fire('PLAYER_ENTERING_WORLD');L.Advance(14)
 check(L.attempts==1 and Nexus.RecomputeStats().actionLifecycle.confirmed==0,'A10: held at the cap across the world change; nothing resent or confirmed')
 GrantOf(L,200004);L.Advance(2)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==1 and L.attempts==1,'A10: the exact late grant settles it once')
 check(Kinds(L).save==nil,'A10: no Save at the cap');NoOther(L,'A10')
end
do -- A18: a non-boolean Orb state answer blocks.
 local L=Sent(10,function()ProjectEbonhold.OrbService={IsStateKnown=function()return 1 end,IsOfferPending=function()return false end}end)
 check(L.attempts==0,'A18 non-boolean Orb state: zero attempts');NoOther(L,'A18 non-boolean')
end
do -- A22: charge ledger CONTENTS unchanged; forbidden native calls counted before their delegates.
 local FORBID={'BanishPerk','FreezePerk','RequestReroll','LockPerk','UnlockPerk','SaveServerBuildSlot','ActivateServerBuildSlot','ToggleTomeEcho'}
 for _,run in ipairs({{'charges 0',{remainingBanishes=0,totalRerolls=0,usedRerolls=0,totalFreezes=0,usedFreezes=0}},
  {'abundant',{remainingBanishes=20,totalRerolls=20,usedRerolls=0,totalFreezes=10,usedFreezes=0}},{'unknown',nil}}) do
  local calls={}
  local L=LBoot(10,function(h)
   Counted(h);h.run=run[2] and h.Clone(run[2]) or nil
   for _,name in ipairs(FORBID) do
    local call=h.service[name];h.service[name]=function(...)calls[#calls+1]=name;return call(...)end
   end
  end)
  for _,name in ipairs(FORBID) do check(type(L.service[name])=='function','A22 fixture: '..name..' wrapper installed') end
  local before=run[2] and L.Clone(L.run) or nil
  SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
  check(L.attempts==1 and #calls==0,'A22 '..run[1]..': one Select, zero forbidden native attempts ('..table.concat(calls,',')..')')
  if before then
   for key,value in pairs(before) do check(L.run[key]==value,'A22 '..run[1]..': ledger field '..key..' unchanged') end
  else
   check(L.run==nil,'A22 unknown: no ledger is fabricated')
  end
 end
end
for _,change in ipairs({{'mode OFF',function()SlashCmdList.NEXUS('leveling off')end},
 {'Wishlist assigned',function()check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('After send',{{spellId=200001,quality=1,stacks=2}}),'fixture: assigned')end}}) do
 local L=Sent(10) -- A25: the original send settles exactly once from its exact grant
 check(L.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.state=='submitted','A25 '..change[1]..': submitted first')
 change[2]();L.Advance(2)
 check(L.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.state~='superseded','A25 '..change[1]..': not cancelled or replayed')
 L.perks.pendingSelectSpellId=nil;GrantOf(L,200004);L.Advance(2)
 check(Nexus.RecomputeStats().actionLifecycle.confirmed==1,'A25 '..change[1]..': the original send settles once')
end
-- R8 (R6-SPEC-03): inside the final g2 service read, a real same-owner root,
-- owner row or stored association replacement that carries a valid assignment
-- (no setter revision) must refuse in that very Take. The assigned saved data
-- is built by the real setter on a separate rig, so no projection is stubbed.
local function R8AssignedRoot()
 local L=LBoot(10);SlashCmdList.NEXUS('leveling on')
 local owner=Nexus.Store.CurrentOwnerKey()
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('R8 swapped plan',{{spellId=200001,quality=1,stacks=2}}),'R8 fixture: the real setter stored an assignment')
 local row=type(NexusDB.chars)=='table' and NexusDB.chars[owner]
 check(type(owner)=='string' and type(row)=='table' and type(row.firstRunWishlist)=='table'
  and row.firstRunWishlist.key=='200001:2','R8 fixture: the owner row holds the stored assignment')
 check(Nexus.GameAdapter.AssignedWishlist().knownUnassigned==nil,'R8 fixture: that stored root is a real assignment')
 return L.Clone(NexusDB),owner
end
local R8ROOT,R8OWNER=R8AssignedRoot()
local R8CASES={
 {'same-owner NexusDB root swapped for one with a valid assignment',function(h,owner)
   local old=NexusDB;NexusDB=h.Clone(R8ROOT)
   return NexusDB~=old and type(NexusDB.chars[owner])=='table' and type(NexusDB.chars[owner].firstRunWishlist)=='table' end},
 {'owner row alone replaced by a row with a valid assignment',function(h,owner)
   local root,chars,old=NexusDB,NexusDB.chars,NexusDB.chars[owner]
   chars[owner]=h.Clone(R8ROOT.chars[owner])
   return NexusDB==root and NexusDB.chars==chars and chars[owner]~=old and type(chars[owner].firstRunWishlist)=='table' end},
 {'stored association written through the real Store mutator',function(h,owner)
   local row=NexusDB.chars[owner];local src=R8ROOT.chars[owner]
   local ok=Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
    s.firstRunWishlist=h.Clone(src.firstRunWishlist)
    if type(src.loadoutWishlists)=='table' and type(src.loadoutWishlists[1])=='table' then
     s.loadoutWishlists=s.loadoutWishlists or {};s.loadoutWishlists[1]=h.Clone(src.loadoutWishlists[1])
    end
   end)
   return ok==true and NexusDB.chars[owner]==row and type(row.firstRunWishlist)=='table' end},
}
for _,m in ipairs(R8CASES) do
 -- No check() inside the getter: SafeCall would swallow a failure as a refusal.
 local pre={}
 local L,fired,first,path=Seam(10,'GetGrantedPerks','g2',function(h)
  local owner=Nexus.Store.CurrentOwnerKey();local row=type(NexusDB.chars)=='table' and NexusDB.chars[owner]
  pre.owner=owner;pre.rowTable=type(row)=='table'
  pre.unassigned=pre.rowTable and (row.firstRunWishlist==nil or row.firstRunWishlist==false)
  pre.phase=Nexus.GameAdapter.LevelingAdmissionPhase
  pre.ok,pre.changed=pcall(m[2],h,owner)
 end)
 check(fired and pre.phase=='g2','R8 '..m[1]..': reached g2 (path '..path..')')
 check(pre.owner==R8OWNER and pre.rowTable and pre.unassigned,'R8 '..m[1]..': same owner; the stored row was unassigned before the change')
 check(pre.ok and pre.changed==true,'R8 '..m[1]..': the saved memory fact actually changed')
 check(first==0,'R8 '..m[1]..': ZERO native attempts in the affected Take: '..tostring(first))
 check(Nexus.Store.CurrentOwnerKey()==R8OWNER and Nexus.GameAdapter.AssignedWishlist().knownUnassigned==nil,
  'R8 '..m[1]..': the current saved authority is a real assignment, not known unassigned')
 L.Advance(3)
 for _,id in ipairs(TakeIds(L)) do check(id~=200003,'R8 '..m[1]..': the stale rarity winner is never sent later') end
end
do -- R8 matched positive: the same g2 seam, current root/row/association unchanged.
 local pre={}
 local L,fired,first,path=Seam(10,'GetGrantedPerks','g2',function()
  local owner=Nexus.Store.CurrentOwnerKey()
  pre.owner,pre.root,pre.chars=owner,NexusDB,NexusDB.chars
  pre.row=type(NexusDB.chars)=='table' and NexusDB.chars[owner] or nil
 end)
 check(fired and pre.owner==R8OWNER and type(pre.row)=='table','R8 positive: reached g2 with the real owner row (path '..path..')')
 check(NexusDB==pre.root and NexusDB.chars==pre.chars and NexusDB.chars[pre.owner]==pre.row,'R8 positive: root, chars and owner row unchanged')
 check(first==1 and #TakeIds(L)==1 and TakeIds(L)[1]==200003,'R8 positive: exactly one Select, of the q3 winner: '..tostring(first))
 local GA=Nexus.GameAdapter
 local facts=GA.SelectRecoveryFacts();local own=facts.unresolved
 check(type(own)=='table' and own.ordinal==facts.submitted and own.spellId==200003 and own.baseline==0
  and type(own.run)=='number','R8 positive: captured ordinal/run/baseline')
 local ordinal,run=own.ordinal,own.run
 L.perks.pendingSelectSpellId=nil;L.Advance(1)
 local held=GA.SelectRecoveryFacts().unresolved
 check(GA.SelectOutcome(ordinal)=='unresolved' and held and held.ordinal==ordinal and held.run==run and held.baseline==0
  and Nexus.RecomputeStats().actionLifecycle.confirmed==0,'R8 positive: latch clear alone proves nothing; the exact record is retained')
 GrantOf(L,200003);L.Advance(2)
 local last,outcome=GA.LastSelectOutcome()
 check(GA.SelectOutcome(ordinal)=='proven' and last==ordinal and outcome=='proven'
  and Nexus.RecomputeStats().actionLifecycle.confirmed==1,'R8 positive: that exact ordinal is proven once')
 check(GA.SelectRecoveryFacts().unresolved==nil and GA.SelectRecoveryFacts().submitted==ordinal,'R8 positive: no further Select ordinal')
 L.Advance(3);check(L.attempts==1,'R8 positive: never resent');NoOther(L,'R8 positive')
end
-- R9 (R8-SPEC-01): two populated Saved Builds; the real numbered setter
-- assigns slot 2 while active slot 1 has no association. Inside the final g2
-- read ONLY the synthetic native active slot moves 1 -> 2 (no slot read, no
-- assignment getter or setter, no root/row/revision/board/grant change).
local R9SLOTS={[1]={name='Build one',verified=true,echoes={{spellId=200001,quality=1,stacks=2}}},
 [2]={name='Build two',verified=true,echoes={{spellId=200002,quality=2,stacks=1}}}}
local function R9Before(h)h.perks.serverActiveSlot=1;h.perks.serverBuildSlots=h.Clone(R9SLOTS) end
local R9PRE={}
local function R9After(h)
 local GA=Nexus.GameAdapter
 local ok=GA.SetLoadoutWishlistIdentity(2,'R9 slot two plan',{{spellId=200002,quality=2,stacks=1}})
 local st=Nexus.Store.State();local owner=Nexus.Store.CurrentOwnerKey()
 local a=GA.AssignedWishlist()
 R9PRE={set=ok==true,owner=owner,
  stored=type(st.loadoutWishlists)=='table' and type(st.loadoutWishlists[2])=='table' and st.loadoutWishlists[2].key=='200002:1',
  slot1=type(st.loadoutWishlists)=='table' and st.loadoutWishlists[1]==nil,
  first=st.firstRunWishlist==nil or st.firstRunWishlist==false,
  populated=GA.IsLoadoutPopulated(1)==true and GA.IsLoadoutPopulated(2)==true,
  active=GA.Slots().activeSlot,known=a.knownUnassigned,key=a.unassignedKey}
end
local function R9Preconditions(label)
 check(R9PRE.set and R9PRE.stored and R9PRE.slot1 and R9PRE.first and R9PRE.populated,
  label..': both Saved Builds populated, slot 2 assigned by the real setter, slot 1 unassigned, no first-run plan')
 check(R9PRE.active==1 and R9PRE.known==true and R9PRE.key==tostring(R9PRE.owner)..'|1|1',
  label..': real AssignedWishlist knows active slot 1 is unassigned: '..tostring(R9PRE.key))
end
do -- R9 regression: the active slot switches to the assigned slot 2 inside g2.
 local pre={}
 local L,fired,first,path=Seam(10,'GetGrantedPerks','g2',function(h)
  pre.phase=Nexus.GameAdapter.LevelingAdmissionPhase
  pre.from=h.perks.serverActiveSlot
  local root=NexusDB;local chars=NexusDB.chars;local row=chars and chars[R9PRE.owner]
  local lw=row and row.loadoutWishlists;local slots=h.perks.serverBuildSlots
  h.perks.serverActiveSlot=2
  pre.to=h.perks.serverActiveSlot
  pre.same=NexusDB==root and NexusDB.chars==chars and chars[R9PRE.owner]==row
   and row.loadoutWishlists==lw and h.perks.serverBuildSlots==slots
 end,nil,R9Before,R9After)
 R9Preconditions('R9 regression')
 check(fired and pre.phase=='g2','R9 regression: reached g2 (path '..path..')')
 check(pre.from==1 and pre.to==2 and pre.same==true,'R9 regression: only the native active slot changed, 1 -> 2')
 check(first==0,'R9 regression: ZERO native attempts in the affected Take: '..tostring(first))
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.activeSlot==2 and a.knownUnassigned==nil,'R9 regression: the current active slot 2 is really assigned')
 L.Advance(3)
 -- The assigned planner may act later (as in the R8 cases): no NoOther here.
 for _,id in ipairs(TakeIds(L)) do check(id~=200003,'R9 regression: the stale rarity winner is never sent later') end
end
do -- R9 matched positive: same two slots and assignment, active slot 1 unchanged at g2.
 local pre={}
 local L,fired,first,path=Seam(10,'GetGrantedPerks','g2',function(h)
  pre.phase=Nexus.GameAdapter.LevelingAdmissionPhase;pre.active=h.perks.serverActiveSlot
 end,nil,R9Before,R9After)
 R9Preconditions('R9 positive')
 check(fired and pre.phase=='g2' and pre.active==1,'R9 positive: reached g2 with active slot 1 (path '..path..')')
 check(first==1 and #TakeIds(L)==1 and TakeIds(L)[1]==200003,'R9 positive: exactly one Select, of the q3 winner: '..tostring(first))
 local GA=Nexus.GameAdapter
 local facts=GA.SelectRecoveryFacts();local own=facts.unresolved
 check(type(own)=='table' and own.ordinal==facts.submitted and own.spellId==200003 and own.baseline==0
  and type(own.run)=='number','R9 positive: captured ordinal/run/baseline')
 local ordinal,run=own.ordinal,own.run
 L.perks.pendingSelectSpellId=nil;L.Advance(1)
 local held=GA.SelectRecoveryFacts().unresolved
 check(GA.SelectOutcome(ordinal)=='unresolved' and held and held.ordinal==ordinal and held.run==run and held.baseline==0
  and Nexus.RecomputeStats().actionLifecycle.confirmed==0,'R9 positive: latch clear alone proves nothing; the exact record is retained')
 GrantOf(L,200003);L.Advance(2)
 local last,outcome=GA.LastSelectOutcome()
 check(GA.SelectOutcome(ordinal)=='proven' and last==ordinal and outcome=='proven'
  and Nexus.RecomputeStats().actionLifecycle.confirmed==1,'R9 positive: that exact ordinal is proven once')
 check(GA.SelectRecoveryFacts().unresolved==nil and GA.SelectRecoveryFacts().submitted==ordinal,'R9 positive: no further Select ordinal')
 L.Advance(3);check(L.attempts==1,'R9 positive: never resent');NoOther(L,'R9 positive')
end
-- R10/R11 (R6-SPEC-01, R10-SPEC-01): a one-shot unreadable post-send granted
-- read (nil, non-table or thrown; only that one reply) hid whether a copy
-- already sat above the baseline. R11: no later reply -- not a readable
-- unchanged one, not a latch clear, not a later grant -- can attribute it, so
-- it stays held ambiguous: never proven, resent or advanced (liveness OPEN).
-- Matched unchanged positives at the same postsend seam settle normally;
-- known-empty and known-nonzero baselines. Facts captured inside the getter
-- are asserted outside it (SafeCall would swallow a failing check).
local function R10Settles(L,label,ordinal,run,base)
 local GA=Nexus.GameAdapter
 L.perks.pendingSelectSpellId=nil;L.Advance(1)
 local held=GA.SelectRecoveryFacts().unresolved
 check(GA.SelectOutcome(ordinal)=='unresolved' and held and held.ordinal==ordinal and held.run==run and held.baseline==base
  and held.postsend==nil and (held.competing or 0)==0 and Nexus.RecomputeStats().actionLifecycle.confirmed==0,
  label..': readable unchanged state and a latch clear prove nothing; the exact record is retained')
 GrantOf(L,200003);L.Advance(2)
 local last,outcome=GA.LastSelectOutcome()
 check(GA.SelectOutcome(ordinal)=='proven' and last==ordinal and outcome=='proven'
  and Nexus.RecomputeStats().actionLifecycle.confirmed==1,label..': the exact later grant proves that ordinal once')
 check(GA.SelectRecoveryFacts().unresolved==nil and GA.SelectRecoveryFacts().submitted==ordinal,label..': no further Select ordinal')
 L.Advance(3);check(L.attempts==1 and Nexus.RecomputeStats().actionLifecycle.confirmed==1,label..': never resent, settled once')
 NoOther(L,label)
end
local function R10Seam(label,before,unread,afterSend)
 local pre={}
 local L,fired,first,path=Seam(10,'GetGrantedPerks','postsend',function(h,r)
  pre.phase=Nexus.GameAdapter.LevelingAdmissionPhase;pre.attempts=h.attempts
  local own=Nexus.GameAdapter.SelectRecoveryFacts().unresolved
  pre.ordinal=own and own.ordinal;pre.run=own and own.run;pre.baseline=own and own.baseline;pre.spell=own and own.spellId
  pre.readable=type(r[1])=='table'
  if unread then unread(h,r) end -- only this one returned reply is unreadable
 end,nil,before)
 check(fired and pre.phase=='postsend' and pre.readable==true,label..': reached the post-send read (path '..path..')')
 check(pre.attempts==1 and first==1 and #TakeIds(L)==1 and TakeIds(L)[1]==200003,label..': the one successful Select delegate ran before that read')
 check(pre.spell==200003 and type(pre.ordinal)=='number' and type(pre.run)=='number',label..': captured ordinal/run/spell')
 return L,pre
end
for _,b in ipairs({{'known-empty',nil,0},{'known-nonzero',function(h)h.granted={['Echo 3']={{spellId=200003}}} end,1}}) do
 for _,u in ipairs({{'nil',function(h,r)r[1]=nil end},{'non-table',function(h,r)r[1]='unreadable' end},
  {'thrown',function()error('synthetic post-send read failure')end}}) do
  local label='R10 '..u[1]..' post-send, '..b[1]..' baseline'
  local L,pre=R10Seam(label,b[2],u[2])
  check(pre.baseline==b[3],label..': the readable pre-send baseline is '..tostring(pre.baseline))
  local GA=Nexus.GameAdapter;local own=GA.SelectRecoveryFacts().unresolved
  check(type(L.granted)=='table' and own and own.ordinal==pre.ordinal and own.postsend=='unread' and (own.competing or 0)==0
   and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..': the mirror is readable again; held unread, not competing, not proven')
  L.perks.pendingSelectSpellId=nil;L.Advance(1)
  local held=GA.SelectRecoveryFacts().unresolved
  check(GA.SelectOutcome(pre.ordinal)=='unresolved' and held and held.ordinal==pre.ordinal and held.run==pre.run
   and held.baseline==b[3] and held.postsend=='unread' and held.wait=='unread'
   and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..': readable unchanged state and a latch clear do not rehabilitate it')
  GrantOf(L,200003);L.Advance(3)
  check(GA.SelectOutcome(pre.ordinal)=='unresolved' and Nexus.RecomputeStats().actionLifecycle.confirmed==0
   and GA.SelectRecoveryFacts().submitted==pre.ordinal and L.attempts==1,
   label..': a later rise is still unattributable: never proven, no new ordinal, never resent (liveness OPEN)')
  NoOther(L,label)
 end
 local label='R10 positive, '..b[1]..' baseline'
 local L,pre=R10Seam(label,b[2],nil)
 local own=Nexus.GameAdapter.SelectRecoveryFacts().unresolved
 check(pre.baseline==b[3] and own and own.postsend==nil and (own.competing or 0)==0,label..': unchanged readable post-send read keeps it attributable')
 R10Settles(L,label,pre.ordinal,pre.run,b[3])
end
do -- R10 negative: after an unreadable post-send read, the first readable count is NOT the baseline.
 local label='R10 unread then extra copy'
 local L,pre=R10Seam(label,nil,function(h,r)r[1]=nil end)
 check(pre.baseline==0,label..': known-empty baseline')
 L.granted={['Echo 3']={{spellId=200003}}};L.Notify() -- a copy that may predate the Select
 L.perks.pendingSelectSpellId=nil;L.Advance(1)
 local GA=Nexus.GameAdapter;local held=GA.SelectRecoveryFacts().unresolved
 check(held and held.ordinal==pre.ordinal and held.postsend=='unread' and held.wait=='unread',
  label..': an unattributable count after an unreadable read is held ambiguous')
 GrantOf(L,200003);L.Advance(3)
 check(GA.SelectOutcome(pre.ordinal)=='unresolved' and Nexus.RecomputeStats().actionLifecycle.confirmed==0
  and GA.SelectRecoveryFacts().submitted==pre.ordinal and L.attempts==1,label..': never proven, replayed or resent')
 NoOther(L,label)
end
-- R11 (R10-SPEC-01/R10-STANDARDS-01): the retained g2 stale-return counter-
-- example plus an unreadable post-send read and an OLD equal-baseline first
-- recovery reply. g2 returns the old table (count = baseline) while the
-- observable mirror becomes a distinct table that already holds one more A;
-- the own Select succeeds; its post-send read is unreadable; recovery replies
-- return that OLD table while the mirror stays ahead; later replies expose only
-- the pre-existing copy. No new grant ever occurs: nothing may be proven.
local function CountOf(t,id)
 if type(t)~='table' then return nil end
 local n=0
 for _,entries in pairs(t) do
  if type(entries)=='table' then for i=1,#entries do if type(entries[i])=='table' and entries[i].spellId==id then n=n+1 end end end
 end
 return n
end
local function R11Stale(before)
 local L=LBoot(10,function(h)Counted(h);if before then before(h) end end)
 SlashCmdList.NEXUS('leveling on');L.Board(FBOARD5);L.Notify()
 local LA=Nexus.GameAdapter;local take=LA.Take;local orig=L.service.GetGrantedPerks
 local s={mode='admit',seen={},owner=Nexus.Store.CurrentOwnerKey()}
 L.service.GetGrantedPerks=function(...)
  if s.mode=='stale' then -- recovery replies: the OLD equal-baseline table
   s.staleReplies=(s.staleReplies or 0)+1
   if not s.firstRecovery then s.firstRecovery,s.firstObservable=s.old,L.granted end
   return s.old
  end
  local p=LA.LevelingAdmissionPhase
  if s.mode=='admit' and p then
   s.seen[#s.seen+1]=tostring(p)
   if p=='g2' and not s.old then
    local r=orig(...);s.old=r
    local t=L.Clone(r) or {};t['Echo 3']=t['Echo 3'] or {};table.insert(t['Echo 3'],{spellId=200003})
    L.granted=t;s.ahead=t -- a distinct observable mirror, one pre-existing A ahead
    return r
   end
   if p=='postsend' and not s.post then
    s.post=true;s.postAttempts=L.attempts
    local own=LA.SelectRecoveryFacts().unresolved
    s.ordinal=own and own.ordinal;s.run=own and own.run;s.baseline=own and own.baseline;s.spell=own and own.spellId
    return nil -- the one unreadable post-send reply
   end
  end
  return orig(...)
 end
 LA.Take=function(...)
  local a0=L.attempts;local r={take(...)}
  if s.post and s.takeDelta==nil then s.takeDelta=L.attempts-a0;s.mode='stale' end
  return unpack(r)
 end
 SlashCmdList.NEXUS('auto');L.Advance(1.5)
 LA.Take=take
 return L,s
end
for _,b in ipairs({{'baseline 0',nil,0},{'baseline 1',function(h)h.granted={['Echo 3']={{spellId=200003}}} end,1}}) do
 local label='R11 stale equal-baseline recovery, '..b[1]
 local L,s=R11Stale(b[2])
 local GA=Nexus.GameAdapter
 check(s.old~=nil and s.ahead~=s.old and CountOf(s.old,200003)==b[3] and CountOf(s.ahead,200003)==b[3]+1,
  label..': g2 returned the old count while a distinct observable mirror held one more A (seen '..table.concat(s.seen,',')..')')
 check(s.post==true and s.postAttempts==1 and s.takeDelta==1 and #TakeIds(L)==1 and TakeIds(L)[1]==200003,
  label..': one successful own Select delegate, then the reached unreadable post-send read')
 check(s.spell==200003 and s.baseline==b[3] and type(s.ordinal)=='number' and type(s.run)=='number',label..': captured ordinal/run/baseline/spell')
 check((s.staleReplies or 0)>=1 and s.firstRecovery==s.old and s.firstObservable==s.ahead
  and CountOf(s.firstRecovery,200003)==b[3] and CountOf(L.granted,200003)==b[3]+1,
  label..': the first recovery reply was the OLD equal-baseline table while the mirror stayed ahead')
 L.perks.pendingSelectSpellId=nil;L.Advance(1)
 local held=GA.SelectRecoveryFacts().unresolved
 check(held and held.ordinal==s.ordinal and held.run==s.run and held.baseline==b[3] and held.postsend=='unread'
  and GA.SelectOutcome(s.ordinal)=='unresolved' and Nexus.RecomputeStats().actionLifecycle.confirmed==0,
  label..': an old equal-baseline reply and a latch clear do not clear the unread mark')
 s.mode='live';L.Notify();L.Advance(2) -- later replies expose only the pre-existing copy
 check(L.granted==s.ahead and CountOf(L.granted,200003)==b[3]+1,label..': no new matching grant occurred')
 held=GA.SelectRecoveryFacts().unresolved
 check(held and held.ordinal==s.ordinal and held.wait=='unread' and GA.SelectOutcome(s.ordinal)=='unresolved'
  and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..': the pre-existing copy is never proven as this ordinal')
 L.Advance(3)
 check(GA.SelectRecoveryFacts().submitted==s.ordinal and L.attempts==1 and Nexus.RecomputeStats().actionLifecycle.confirmed==0,
  label..': no new ordinal, resend or confirmation')
 NoOther(L,label)
 -- Matched legitimate known-baseline positive: same owner/run/offer/baseline,
 -- readable unchanged admission and post-send evidence, then one real grant.
 local plabel='R11 matched positive, '..b[1]
 local P,pre=R10Seam(plabel,b[2],nil)
 local own=Nexus.GameAdapter.SelectRecoveryFacts().unresolved -- the new rig's adapter
 check(Nexus.Store.CurrentOwnerKey()==s.owner and pre.baseline==b[3] and pre.spell==s.spell and pre.run==s.run
  and own and own.postsend==nil and (own.competing or 0)==0,plabel..': same owner/run/offer/baseline, attributable')
 R10Settles(P,plabel,pre.ordinal,pre.run,b[3])
end
-- R12 (R11 shared P3): truthful Select wait diagnostics through the real
-- consumers: Nexus.AutomationEffectiveState and, for the world hold, the real
-- runtime's AutoAllowed. No reason, outcome, competing field or worldPending is
-- stubbed. Every fact is asserted outside the swallowing service read.
do
 local function Has(s,t) return type(s)=='string' and s:find(t,1,true)~=nil end
 local function Truthful(label,reason)
  check(Has(reason,'could not read the granted Echoes') and Has(reason,'no later grant can settle it') and Has(reason,'nothing is resent'),
   label..': plain unread uncertainty: '..tostring(reason))
  check(not Has(reason,'another selection') and not Has(reason,'re-reads') and not Has(reason,'ordinal') and not Has(reason,'paused'),
   label..': no observed-other, re-read, ordinal or pause claim: '..tostring(reason))
 end
 local BASES={{'baseline 0',nil,0},{'baseline 1',function(h)h.granted={['Echo 3']={{spellId=200003}}} end,1}}
 for _,b in ipairs(BASES) do -- (1) one unread reply, no outside Select, also past the watchdog.
  local label='R12 unread consumer, '..b[1]
  local L,pre=R10Seam(label,b[2],function(h,r)r[1]=nil end)
  L.Advance(.5)
  local GA=Nexus.GameAdapter;local held=GA.SelectRecoveryFacts().unresolved
  check(pre.baseline==b[3] and held and held.ordinal==pre.ordinal and held.run==pre.run and held.baseline==b[3]
   and held.postsend=='unread' and (held.competing or 0)==0 and held.wait=='unread',label..': exact marker, ordinal, run and baseline; no competing evidence')
  local es=Nexus.AutomationEffectiveState()
  check(es.selected==true and es.state=='waiting' and es.hold==true,label..': Auto stays selected, waiting, immediate hold: '..tostring(es.state))
  Truthful(label,es.reason)
  L.Advance(12) -- past the watchdog and the recheck window
  held=GA.SelectRecoveryFacts().unresolved;es=Nexus.AutomationEffectiveState()
  check(held and held.ordinal==pre.ordinal and held.run==pre.run and held.overdue==true and held.wait=='unread' and held.rechecks==0
   and (es.rechecks or 0)==0,label..': past the watchdog: same record, overdue, no recheck')
  check(es.selected==true and es.state=='waiting' and es.hold==true,label..': past the watchdog: still waiting, not rechecking: '..tostring(es.state))
  Truthful(label..' past the watchdog',es.reason)
  check(L.attempts==1 and GA.SelectRecoveryFacts().submitted==pre.ordinal and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..': no resend or confirmation')
  SlashCmdList.NEXUS('auto') -- Auto OFF: the state and permission stay accurate
  es=Nexus.AutomationEffectiveState();held=GA.SelectRecoveryFacts().unresolved
  check(es.selected==false and es.state=='off' and es.hold==false and Has(es.reason,'Auto is OFF')
   and Nexus.Store.Settings().autoPickLeveling==true and held and held.ordinal==pre.ordinal and held.postsend=='unread',label..': Auto OFF keeps the record and the option')
  Truthful(label..' Auto OFF',es.reason)
  L.Advance(2);check(L.attempts==1,label..': nothing sent with Auto OFF');NoOther(L,label)
 end
 for _,c in ipairs({{'same spell',200003},{'unknown spell',nil}}) do -- (2) a really observed outside Select.
  local label='R12 observed outside Select, '..c[1]
  local L,pre=R10Seam(label,nil,nil)
  local GA=Nexus.GameAdapter;local own=GA.SelectRecoveryFacts().unresolved
  check(own and own.ordinal==pre.ordinal and own.postsend==nil and (own.competing or 0)==0 and L.attempts==1
   and L.perks.pendingSelectSpellId~=nil,label..': one own attempt, latch set, no competing evidence yet')
  L.service.SelectPerk(c[2]) -- the real hooked service, not the adapter
  check(L.attempts==2,label..': exactly one outside attempt, counted before the delegate: '..tostring(L.attempts))
  L.Advance(.5)
  local held=GA.SelectRecoveryFacts().unresolved;local es=Nexus.AutomationEffectiveState()
  check(held and held.ordinal==pre.ordinal and held.competing==1 and held.postsend==nil and held.wait=='ambiguous',label..': the hook recorded real competing evidence')
  check(es.selected==true and es.state=='waiting' and es.hold==true and Has(es.reason,'cannot attribute a grant to this selection') and Has(es.reason,'no later grant can settle it')
   and not Has(es.reason,'same Echo') and not Has(es.reason,'another selection')
   and not Has(es.reason,'could not read') and not Has(es.reason,'re-reads'),label..': truthful generic unattributable reason: '..tostring(es.reason))
  L.perks.pendingSelectSpellId=nil;L.Advance(1);GrantOf(L,200003);L.Advance(3)
  check(GA.SelectOutcome(pre.ordinal)=='unresolved' and Nexus.RecomputeStats().actionLifecycle.confirmed==0
   and GA.SelectRecoveryFacts().submitted==pre.ordinal and L.attempts==2,label..': never proven; no automatic replay beyond that one outside attempt')
  NoOther(L,label)
 end
 for _,b in ipairs(BASES) do -- (3) matched known-readable healthy path.
  local label='R12 healthy consumer, '..b[1]
  local L,pre=R10Seam(label,b[2],nil)
  L.Advance(.5)
  local GA=Nexus.GameAdapter;local held=GA.SelectRecoveryFacts().unresolved;local es=Nexus.AutomationEffectiveState()
  check(pre.baseline==b[3] and held and held.ordinal==pre.ordinal and held.postsend==nil and (held.competing or 0)==0 and held.wait=='latch',label..': the normal latch wait')
  check(es.selected==true and es.state=='waiting' and es.hold==false and Has(es.reason,'re-reads')
   and not Has(es.reason,'could not read') and not Has(es.reason,'another selection'),label..': the normal wait text and no immediate hold: '..tostring(es.reason))
  R10Settles(L,label,pre.ordinal,pre.run,b[3])
  es=Nexus.AutomationEffectiveState()
  check(es.selected==true and GA.SelectUnresolved()==nil and not Has(es.reason,'waiting for the result'),label..': settled once; no wait remains')
 end
 -- World hold: the real runtime instance, captured as session_pause_auto does.
 local function R12World(unread)
  Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
  local L=dofile('tests/prototype/harness.lua');L.pendingRolls=40;L.playerLevel=10
  Counted(L)
  for line in io.lines('Nexus.toc') do
   line=line:gsub('\r','')
   if line~='' and not line:match('^#') then
    local chunk,err=loadfile((line:gsub('\\','/')));assert(chunk,err);chunk('Nexus',{})
   end
  end
  local factory=Nexus.MainInternals.AutomationRuntime;local new=factory.New
  factory.New=function(...)L.runtime=new(...);return L.runtime end
  L.Fire('ADDON_LOADED','Nexus');L.Fire('PLAYER_ENTERING_WORLD');L.Advance(20,.05)
  L.AcknowledgeOverwriteWarnings()
  check(L.runtime,'R12 world: the real runtime instance was captured')
  local s={};local orig=L.service.GetGrantedPerks
  L.service.GetGrantedPerks=function(...)
   local r={orig(...)}
   if Nexus.GameAdapter.LevelingAdmissionPhase=='postsend' and not s.post then
    s.post=true;s.attempts=L.attempts
    if unread then return nil end
   end
   return unpack(r)
  end
  SlashCmdList.NEXUS('leveling on');L.Board(FBOARD5);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(2)
  local own=Nexus.GameAdapter.SelectRecoveryFacts().unresolved
  check(s.post==true and s.attempts==1 and L.attempts==1 and TakeIds(L)[1]==200003 and own and own.spellId==200003 and own.baseline==0,
   'R12 world: one own Select, then the reached post-send read')
  s.ordinal,s.run=own.ordinal,own.run
  L.Fire('PLAYER_LEAVING_WORLD')
  local es=Nexus.AutomationEffectiveState()
  check(es.selected==true and es.state=='paused' and Has(es.reason,'loading screen'),'R12 world: the loading screen is named: '..tostring(es.reason))
  L.perks.pendingSelectSpellId=nil;L.Board({{spellId=200005,quality=1},{spellId=200006,quality=2},{spellId=200007,quality=0}});L.Notify();L.Advance(1)
  L.Fire('PLAYER_ENTERING_WORLD');L.Advance(14)
  return L,s
 end
 do -- The unread Select crosses a world change: the actual hold reason is the noGrant branch.
  local label='R12 world hold, unread'
  local L,s=R12World(true)
  local GA=Nexus.GameAdapter
  local function HoldText(tag)
   local ok,why=L.runtime.AutoAllowed()
   check(ok==false and Has(why,'no confirmed result for') and Has(why,'sent before the loading screen')
    and Has(why,'a grant can no longer settle the Echo selection already sent') and Has(why,'Auto off and on ends only this hold')
    and Has(why,'(nothing is resent)'),label..tag..': the actual world hold uses the noGrant branch: '..tostring(why))
   check(not Has(why,'exact grant') and not Has(why,'pending Select flag') and not Has(why,'re-reads'),label..tag..': no grant, latch or re-read promise: '..tostring(why))
  end
  local function Same(tag)
   local held=GA.SelectRecoveryFacts().unresolved
   check(held and held.ordinal==s.ordinal and GA.SelectUnresolved()==s.ordinal and held.run==s.run and held.baseline==0 and held.entries>=1
    and held.postsend=='unread' and (held.competing or 0)==0 and held.wait=='unread' and held.rechecks==0
    and GA.SelectOutcome(s.ordinal)=='unresolved',label..tag..': the same unread record crossed the world entry, no competing evidence')
   local es=Nexus.AutomationEffectiveState()
   check(es.selected==true and es.state=='waiting' and es.hold==true and (es.rechecks or 0)==0,label..tag..': selected, waiting, held, no recheck: '..tostring(es.state))
   Truthful(label..tag,es.reason)
   check(L.attempts==1 and GA.SelectRecoveryFacts().submitted==s.ordinal and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..tag..': no resend, new ordinal or confirmation')
  end
  Same('');HoldText('')
  GrantOf(L,200003);L.Advance(3) -- a late matching count cannot prove it
  check(CountOf(L.granted,200003)==1,label..': the late matching count is visible')
  Same(' after a late matching count');HoldText(' after a late matching count')
  NoOther(L,label)
 end
 do -- Matched control: the same crossing with a readable post-send keeps the exact-grant branch.
  local label='R12 world hold, healthy'
  local L,s=R12World(false)
  local GA=Nexus.GameAdapter
  local ok,why=L.runtime.AutoAllowed()
  check(ok==false and Has(why,'no confirmed result for') and Has(why,'it ends only after the exact grant of the Echo selection already sent')
   and not Has(why,'a grant can no longer settle'),label..': this exact-grant branch needs the hold to track the own ordinal: '..tostring(why))
  check(GA.SelectUnresolved()==s.ordinal and GA.SelectOutcome(s.ordinal)=='unresolved',label..': still unresolved before its grant')
  GrantOf(L,200003);L.Advance(3)
  local after,afterWhy=L.runtime.AutoAllowed()
  -- Current post-hold contract (AutomationRuntime 2812-2816, 4099-4114, 4170-4172; CONTRACTS.md 51-72; R5-SPEC-02 534-535):
  -- the exact grant proves the crossed Select once and ends the hold; Auto then resumes on the CURRENT strict board, so
  -- exactly one fresh Take of its winner (200006) follows. No quiet period is documented; the old 200003 is never resent.
  local facts=GA.SelectRecoveryFacts();local ids=TakeIds(L);local provenRows,provenRow=0,nil
  for _,row in ipairs(facts.outcomes) do if row.ordinal==s.ordinal then provenRows=provenRows+1;provenRow=row end end
  local nextOrdinal,nextPhase,nextSpell=GA.SelectUnresolved()
  check(GA.SelectOutcome(s.ordinal)=='proven' and Nexus.RecomputeStats().actionLifecycle.confirmed==1 and provenRows==1 and provenRow.outcome=='proven'
   and provenRow.run==s.run and provenRow.baseline==0 and provenRow.spellId==200003 and after==true and afterWhy==nil,
   label..': the exact grant proves that ordinal once and ends the hold: '..tostring(after)..' '..tostring(afterWhy))
  check(L.attempts==2 and #ids==2 and ids[1]==200003 and ids[2]==200006 and nextOrdinal~=nil and nextOrdinal~=s.ordinal and facts.submitted==nextOrdinal
   and nextSpell==200006 and nextPhase=='latch' and facts.unresolved and facts.unresolved.ordinal==nextOrdinal and facts.unresolved.spellId==200006,
   label..': after the hold ends, exactly one fresh Take of the current board winner 200006 under a distinct next ordinal; 200003 is never resent: '..table.concat(ids,','))
  NoOther(L,label)
 end
end
-- R13 (R12C shared P3): the real Take post-send count drift. After exactly one
-- real own Select delegate, the readable post-send reply and its backing granted
-- input hold one more copy than the captured baseline; no outside Select is ever
-- called. Only that fixture input changes: the producer, wait, reason and outcome
-- are the real ones, and every fact is asserted outside the swallowing read.
do
 local function Has(s,t) return type(s)=='string' and s:find(t,1,true)~=nil end
 local function Generic(label,reason)
  check(Has(reason,'cannot attribute a grant to this selection') and Has(reason,'no later grant can settle it') and Has(reason,'nothing is resent'),
   label..': truthful generic unattributable reason: '..tostring(reason))
  check(not Has(reason,'same Echo') and not Has(reason,'another selection') and not Has(reason,'could not read') and not Has(reason,'re-reads'),
   label..': no same-Echo, read-failure or re-read claim: '..tostring(reason))
 end
 for _,b in ipairs({{'baseline 0',nil,0},{'baseline 1',function(h)h.granted={['Echo 3']={{spellId=200003}}} end,1}}) do
  local label='R13 post-send count drift, '..b[1]
  local drift={}
  local L,pre=R10Seam(label,b[2],function(h,r)
   local t=h.Clone(r[1]) or {};t['Echo 3']=t['Echo 3'] or {};table.insert(t['Echo 3'],{spellId=200003})
   h.granted=t;r[1]=t;drift.reply=t
  end)
  check(pre.baseline==b[3] and drift.reply~=nil and L.granted==drift.reply and CountOf(drift.reply,200003)==b[3]+1,
   label..': the readable reply and backing input hold one more copy than the captured baseline')
  L.Advance(.5)
  local GA=Nexus.GameAdapter;local held=GA.SelectRecoveryFacts().unresolved
  check(held and held.ordinal==pre.ordinal and held.run==pre.run and held.baseline==b[3] and held.spellId==200003
   and held.competing==1 and held.postsend==nil and held.wait=='ambiguous',label..': the real producer: competing 1, no unread mark, the original record')
  local ordinal,_,_,wait=GA.SelectUnresolved()
  check(ordinal==pre.ordinal and wait=='ambiguous',label..': the real SelectUnresolved names the same ordinal, waiting ambiguous')
  check(L.attempts==1,label..': one own attempt, so no outside Select was called: '..tostring(L.attempts))
  local es=Nexus.AutomationEffectiveState()
  check(es.selected==true and es.state=='waiting' and es.hold==true,label..': selected, waiting and held: '..tostring(es.state))
  Generic(label,es.reason)
  L.perks.pendingSelectSpellId=nil;L.Advance(1);GrantOf(L,200003);L.Advance(3)
  L.Advance(12) -- a later rise, a cleared latch and the watchdog window settle nothing
  held=GA.SelectRecoveryFacts().unresolved;es=Nexus.AutomationEffectiveState()
  check(held and held.ordinal==pre.ordinal and held.run==pre.run and held.baseline==b[3] and held.competing==1 and held.wait=='ambiguous'
   and held.rechecks==0 and GA.SelectOutcome(pre.ordinal)=='unresolved',label..': a later matching grant settles nothing; no recheck')
  check(GA.SelectRecoveryFacts().submitted==pre.ordinal and L.attempts==1 and Nexus.RecomputeStats().actionLifecycle.confirmed==0,
   label..': no resend, new ordinal or confirmation')
  check(es.selected==true and es.state=='waiting' and es.hold==true,label..': still selected, waiting and held: '..tostring(es.state))
  Generic(label..' later',es.reason)
  SlashCmdList.NEXUS('auto') -- Auto OFF: the state and permission stay accurate
  es=Nexus.AutomationEffectiveState();held=GA.SelectRecoveryFacts().unresolved
  check(es.selected==false and es.state=='off' and es.hold==false and Has(es.reason,'Auto is OFF')
   and Nexus.Store.Settings().autoPickLeveling==true and held and held.ordinal==pre.ordinal and held.competing==1,label..': Auto OFF keeps the record and the option')
  Generic(label..' Auto OFF',es.reason)
  L.Advance(2);check(L.attempts==1 and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..': nothing sent or confirmed with Auto OFF');NoOther(L,label)
 end
end
-- R14 (F01 / R6-STANDARDS-01): the retained raw2 granted-drift regression. Inside
-- the affected Take, AFTER the real raw2 GetCurrentChoice returned its unchanged
-- reply, only the backing granted input gains one copy of the winner. g2 then
-- differs from g1 and refuses: zero native attempts in that Take. A genuinely
-- fresh Select follows unconditionally with current baseline 1; a latch clear
-- proves nothing; one new matching grant proves that exact ordinal once. Facts
-- taken inside the getter are asserted outside it (SafeCall would swallow them).
do
 local label='R14 raw2 granted drift'
 local RUN={remainingBanishes=3,totalRerolls=3,usedRerolls=0,totalFreezes=2,usedFreezes=0}
 local pre={}
 local L,fired,first,path=Seam(10,'GetCurrentChoice','raw2',function(h)
  pre.phase=Nexus.GameAdapter.LevelingAdmissionPhase;pre.attempts=h.attempts
  pre.submitted=Nexus.GameAdapter.SelectRecoveryFacts().submitted
  pre.old=h.granted;pre.oldCount=CountOf(h.granted,200003)
  local t=h.Clone(h.granted) or {};t['Echo 3']=t['Echo 3'] or {};table.insert(t['Echo 3'],{spellId=200003})
  h.granted=t;pre.newCount=CountOf(t,200003);pre.drifted=t
 end,nil,function(h)h.run=h.Clone(RUN) end)
 -- The affected Take: reached raw2, real drift, refused before raw3 and the Select.
 check(fired and pre.phase=='raw2',label..': reached raw2 (path '..path..')')
 check(pre.attempts==0 and pre.submitted==0,label..': no earlier native attempt or Select record at the seam')
 check(type(pre.old)=='table' and pre.oldCount==0 and pre.drifted~=nil and pre.drifted~=pre.old and pre.newCount==1,
  label..': the backing granted input really moved from count 0 to a distinct table with count 1')
 local mark=path:find('raw2',1,true)
 check(mark~=nil and path:sub(mark,mark+8)~='raw2,raw3',label..': the affected Take never reached raw3 (path '..path..')')
 check(first==0,label..': ZERO native attempts in the first affected Take: '..tostring(first))
 -- The later fresh Select: required unconditionally, on the current baseline.
 L.Advance(3)
 local GA=Nexus.GameAdapter
 check(Nexus.RecomputeStats().actionLifecycle.superseded>=1,label..': the affected prepared intent was superseded')
 check(L.attempts==1 and #TakeIds(L)==1 and TakeIds(L)[1]==200003,label..': exactly one fresh native Select of the winner: '..tostring(L.attempts))
 local facts=GA.SelectRecoveryFacts();local own=facts.unresolved
 check(type(own)=='table' and type(own.ordinal)=='number' and own.ordinal>=1 and own.ordinal==facts.submitted and own.spellId==200003
  and own.baseline==1 and type(own.run)=='number' and own.postsend==nil and (own.competing or 0)==0,
  label..': the fresh Select captured its ordinal, run and current baseline 1')
 local ordinal,run=own.ordinal,own.run
 check(L.granted==pre.drifted and CountOf(L.granted,200003)==1 and L.perks.pendingSelectSpellId~=nil
  and GA.SelectOutcome(ordinal)=='unresolved' and Nexus.RecomputeStats().actionLifecycle.confirmed==0,
  label..': the existing copy and the set latch prove nothing yet')
 -- A latch clear without another grant.
 L.perks.pendingSelectSpellId=nil;L.Advance(3)
 local held=GA.SelectRecoveryFacts().unresolved
 check(GA.SelectOutcome(ordinal)=='unresolved' and held and held.ordinal==ordinal and held.run==run and held.baseline==1 and held.count==1
  and held.phase=='grant' and held.wait=='grant' and held.postsend==nil and (held.competing or 0)==0
  and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..': a latch clear without another grant leaves that same ordinal unresolved')
 check(L.attempts==1 and GA.SelectRecoveryFacts().submitted==ordinal,label..': no resend or new ordinal after the latch clear')
 -- One new matching grant proves that exact ordinal and run, once.
 GrantOf(L,200003);L.Advance(2)
 check(CountOf(L.granted,200003)==2,label..': the new matching grant is visible above baseline 1')
 local last,outcome=GA.LastSelectOutcome()
 local after=GA.SelectRecoveryFacts();local row=after.outcomes[#after.outcomes]
 check(GA.SelectOutcome(ordinal)=='proven' and last==ordinal and outcome=='proven' and after.unresolved==nil
  and row and row.ordinal==ordinal and row.run==run and row.baseline==1 and row.spellId==200003 and row.outcome=='proven'
  and after.submitted==ordinal and Nexus.RecomputeStats().actionLifecycle.confirmed==1,label..': the new grant proves that exact ordinal and run once')
 L.Advance(3)
 check(L.attempts==1 and #TakeIds(L)==1 and GA.SelectRecoveryFacts().submitted==ordinal
  and Nexus.RecomputeStats().actionLifecycle.confirmed==1,label..': no resend, new ordinal or duplicate confirmation')
 NoOther(L,label)
 for key,value in pairs(RUN) do check(L.run[key]==value,label..': charge ledger field '..key..' unchanged') end
 for key in pairs(L.run) do check(RUN[key]~=nil,label..': no charge ledger field added: '..tostring(key)) end
end
-- R15: F02 provenance, F03 paused opt-in, F06 ledgers and counters, F07 raw
-- shapes and ties. Real boot, adapter, runtime and service delegates; only fixture
-- inputs change. Nothing here runs inside a swallowing service callback.
do
 local RUN={remainingBanishes=3,totalRerolls=3,usedRerolls=0,totalFreezes=2,usedFreezes=0}
 local function Confirmed() return Nexus.RecomputeStats().actionLifecycle.confirmed end
 -- Whole-value comparison, both directions: additions, deletions and changes.
 local function DeepDiff(a,b,path,out)
  if type(a)~='table' or type(b)~='table' then
   if not rawequal(a,b) then out[#out+1]=path end
   return out
  end
  for k,v in pairs(a) do DeepDiff(v,rawget(b,k),path..'.'..tostring(k),out) end
  for k in pairs(b) do if rawget(a,k)==nil then out[#out+1]=path..'.'..tostring(k) end end
  return out
 end
 check(#DeepDiff({a=1,n={b=2}},{a=1,n={b=2}},'x',{})==0,'R15 oracle: equal values show no difference')
 check(#DeepDiff({a=1},{a=1,b=2},'x',{})==1,'R15 oracle: an addition is a difference')
 check(#DeepDiff({a=1,b=2},{a=1},'x',{})==1,'R15 oracle: a deletion is a difference')
 check(#DeepDiff({a=1},{a=2},'x',{})==1,'R15 oracle: a changed value is a difference')
 check(#DeepDiff(nil,{},'x',{})==1 and #DeepDiff({},nil,'x',{})==1 and #DeepDiff(nil,nil,'x',{})==0,'R15 oracle: missing is not empty')
 local function SameLedger(L,label,expected)
  local diff=DeepDiff(expected,L.run,'run',{})
  check(#diff==0,label..': whole charge ledger unchanged: '..table.concat(diff,' '))
 end
 -- The real unresolved record, captured before any interference.
 local function Captured(L,label,spell,base)
  local facts=Nexus.GameAdapter.SelectRecoveryFacts();local own=facts.unresolved
  check(type(own)=='table' and type(own.ordinal)=='number' and own.ordinal>=1 and own.ordinal==facts.submitted and own.spellId==spell
   and own.baseline==base and type(own.run)=='number' and own.postsend==nil and (own.competing or 0)==0,
   label..': the actual ordinal, run, baseline and spell before interference')
  check(L.attempts==1 and #TakeIds(L)==1 and TakeIds(L)[1]==spell and Confirmed()==0,label..': exactly one accepted Select of the actual winner')
  return {ordinal=own.ordinal,run=own.run,baseline=own.baseline,spell=own.spellId,submitted=facts.submitted}
 end
 local function StillHeld(L,label,c)
  local GA=Nexus.GameAdapter;local facts=GA.SelectRecoveryFacts();local own=facts.unresolved
  check(GA.SelectOutcome(c.ordinal)=='unresolved' and own and own.ordinal==c.ordinal and own.run==c.run and own.baseline==c.baseline
   and own.spellId==c.spell and own.postsend==nil and (own.competing or 0)==0 and facts.submitted==c.submitted,label..': the same record stays unresolved')
  check(Confirmed()==0 and L.attempts==1 and #TakeIds(L)==1,label..': no confirmation, resend or new ordinal')
 end
 -- A genuinely new matching grant proves that exact record once; more time cannot.
 local function ProvenOnce(L,label,c)
  local GA=Nexus.GameAdapter;local count=CountOf(L.granted,c.spell)
  check(count==c.baseline,label..': no grant has arrived yet: '..tostring(count))
  GrantOf(L,c.spell);L.Advance(2)
  check(CountOf(L.granted,c.spell)==c.baseline+1,label..': the new matching grant is visible')
  local last,outcome=GA.LastSelectOutcome()
  local after=GA.SelectRecoveryFacts();local row=after.outcomes[#after.outcomes]
  check(GA.SelectOutcome(c.ordinal)=='proven' and last==c.ordinal and outcome=='proven' and after.unresolved==nil
   and row and row.ordinal==c.ordinal and row.run==c.run and row.baseline==c.baseline and row.spellId==c.spell and row.outcome=='proven'
   and after.submitted==c.submitted and Confirmed()==1,label..': that exact ordinal and run are proven once')
  L.Notify();L.Advance(3);L.Notify();L.Advance(3)
  check(GA.SelectOutcome(c.ordinal)=='proven' and GA.SelectRecoveryFacts().submitted==c.submitted and Confirmed()==1
   and L.attempts==1 and #TakeIds(L)==1,label..': more time and notifications neither confirm twice nor resend')
  NoOther(L,label)
 end
 -- F02: ordinary, board, cap, world, mode OFF and Wishlist transitions. Where a
 -- fresh decision would be legitimate after the proof (a moved board, an assigned
 -- planner) the board is removed first, so any later Select here is a resend.
 local MOVED={{spellId=200005,quality=1},{spellId=200006,quality=2},{spellId=200007,quality=0}}
 local function Cross(L,cap)
  L.playerLevel=cap and 80 or L.playerLevel;L.Advance(1)
  L.Fire('PLAYER_LEAVING_WORLD')
  L.perks.pendingSelectSpellId=nil;L.Board({});L.Notify();L.Advance(1)
  L.Fire('PLAYER_ENTERING_WORLD');L.Advance(14)
 end
 for _,row in ipairs({
  {'ordinary known-empty',10,nil,0,function()end,0},
  {'ordinary known-nonzero',10,function(h)h.granted={['Echo 4']={{spellId=200004}}} end,1,function()end,0},
  {'board moved',10,nil,0,function(L)L.Board(MOVED);L.Notify();L.Advance(1);L.Board({});L.Notify();L.Advance(1)
    check(Nexus.GameAdapter.Board()==nil,'R15 F02 board moved: the board is really gone')end,0},
  {'cap',79,nil,0,function(L)L.playerLevel=80;L.Advance(3);check(UnitLevel('player')==80,'R15 F02 cap: live level 80')end,0},
  {'world',10,nil,0,function(L)Cross(L,false)end,1},
  {'cap and world',79,nil,0,function(L)Cross(L,true);check(UnitLevel('player')==80,'R15 F02 cap and world: live level 80')end,1},
  {'mode OFF',10,nil,0,function(L)SlashCmdList.NEXUS('leveling off');L.Advance(2)
    check(Nexus.Store.Settings().autoPickLeveling==false,'R15 F02 mode OFF: the option is really off')end,0},
  {'Wishlist after send',10,nil,0,function(L)
    check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('R15 after send',{{spellId=200001,quality=1,stacks=2}}),'R15 F02 Wishlist: the real setter ran')
    check(Nexus.GameAdapter.AssignedWishlist().knownUnassigned==nil,'R15 F02 Wishlist: current authority is a real assignment')
    L.Advance(2);L.Board({});L.Notify()end,0},
 }) do
  local label='R15 F02 '..row[1]
  local L=Sent(row[2],function(h)h.run=h.Clone(RUN);if row[3] then row[3](h) end end)
  check(Nexus.RecomputeStats().lastActionLifecycle.state=='submitted' and L.perks.pendingSelectSpellId~=nil,label..': submitted, latch set')
  local c=Captured(L,label,200004,row[4])
  row[5](L);StillHeld(L,label..' after its transition',c)
  check((Nexus.GameAdapter.SelectRecoveryFacts().unresolved.entries or 0)>=row[6],label..': the record really crossed the expected world entries')
  L.perks.pendingSelectSpellId=nil;L.Advance(3);StillHeld(L,label..' after a latch clear',c)
  local held=Nexus.GameAdapter.SelectRecoveryFacts().unresolved
  check(held.phase=='grant' and held.wait=='grant' and held.count==row[4],label..': waiting for its grant at the same count')
  L.Advance(12);StillHeld(L,label..' after elapsed time',c)
  ProvenOnce(L,label,c);SameLedger(L,label,RUN)
 end
 -- F03: paused BEFORE the real opt-in. Only the option key changes; no Resume, no
 -- Auto enable, no action or resource change. Auto OFF and Auto ON are separate.
 for _,auto in ipairs({false,true}) do
  local label='R15 F03 paused opt-in, Auto '..(auto and 'ON' or 'OFF')
  local L=LBoot(10,function(h)Counted(h);h.run=h.Clone(RUN) end)
  local P=Nexus.SessionPause
  check(P.IsPaused()~=true and not Nexus.RecomputeStats().autoEnabled and Nexus.Store.Settings().autoPickLeveling==nil,label..': boots unpaused, Auto OFF, option absent')
  if auto then SlashCmdList.NEXUS('auto') end
  SlashCmdList.NEXUS('pause')
  check(P.IsPaused()==true and (Nexus.RecomputeStats().autoEnabled==true)==auto,label..': genuinely paused before the opt-in')
  local epoch,acted,root=P.Status().epoch,#L.actions,L.Clone(NexusDB)
  check(#DeepDiff(root,NexusDB,'root',{})==0 and rawget(NexusDB.settings,'autoPickLeveling')==nil,label..': the snapshot equals the saved root')
  local function OptionOnly(tag)
   local diff=DeepDiff(root,NexusDB,'root',{})
   check(#diff==1 and diff[1]=='root.settings.autoPickLeveling' and rawget(NexusDB.settings,'autoPickLeveling')==true,
    label..tag..': only the option key changed: '..table.concat(diff,' '))
  end
  local function Unmoved(tag)
   check(P.IsPaused()==true and P.Status().epoch==epoch,label..tag..': still paused, same epoch')
   check((Nexus.RecomputeStats().autoEnabled==true)==auto and Nexus.Store.Settings().autoPickLeveling==true,label..tag..': Auto unchanged, option on')
   check(#L.actions==acted and L.attempts==0 and #TakeIds(L)==0,label..tag..': no action or native attempt')
   SameLedger(L,label..tag,RUN);NoOther(L,label..tag)
  end
  SlashCmdList.NEXUS('leveling on')
  OptionOnly(' after the setter');Unmoved(' after the setter')
  L.Board(LBOARD);L.Notify();L.Advance(3)
  Unmoved(' with a board offered')
  if not auto then
   -- R15 F03 post-board (Root decision 2026-11-10): the pause gates action authority and sending, not the
   -- documented per-fresh-board observation writers (decision log, RUN_START audit, roll trace and their
   -- history counters). The old whole-root equality was an overstrict expectation. This block asserts the
   -- closed observation change set positively: exactly these 17 paths, computed from the 1386 snapshot.
   local tag=' with a board offered';local function Len(t) return type(t)=='table' and #t or 0 end
   local diff=DeepDiff(root,NexusDB,'root',{})
   local n0={decision=Len(root.decisionLog),runAudit=Len(root.runAudit),rollTrace=Len(root.rollTraceLog)}
   local want={['root.settings.autoPickLeveling']=true,['root.decisionLog.'..(n0.decision+1)]=true,['root.runAudit.'..(n0.runAudit+1)]=true,
    ['root.rollTraceLog.'..(n0.rollTrace+1)]=true,['root.rollTraceLog.'..(n0.rollTrace+2)]=true}
   for _,name in ipairs({'decision','runAudit','rollTrace'}) do
    for _,leaf in ipairs({'retained','storageTail','storageRetained','appended'}) do want['root.diagnosticMeta.histories.'..name..'.'..leaf]=true end
   end
   local seen,extra,dup,missing={},{},{},{}
   for _,p in ipairs(diff) do if seen[p] then dup[#dup+1]=p elseif want[p] then seen[p]=true else extra[#extra+1]=p end end
   for p in pairs(want) do if not seen[p] then missing[#missing+1]=p end end;table.sort(missing)
   check(#diff==17 and #extra==0 and #dup==0 and #missing==0,label..tag..': exactly the 17 observation paths changed; extra: '
    ..table.concat(extra,' ')..'; missing: '..table.concat(missing,' ')..'; duplicate: '..table.concat(dup,' '))
   check(rawget(NexusDB.settings,'autoPickLeveling')==true and #DeepDiff(root.settings,NexusDB.settings,'root.settings',{})==1,
    label..tag..': the settings delta is still exactly the one boolean')
   check(Len(NexusDB.decisionLog)==n0.decision+1 and Len(NexusDB.runAudit)==n0.runAudit+1 and Len(NexusDB.rollTraceLog)==n0.rollTrace+2,
    label..tag..': one decision, one audit and two trace records were appended')
   local d=NexusDB.decisionLog[n0.decision+1];local offered=L.perks and L.perks.currentChoice
   check(type(d)=='table' and type(d.proposal)=='table' and type(d.cards)=='table' and type(offered)=='table' and #d.cards==#offered and #d.cards>0
    and type(d.t)=='string' and d.run~=nil,label..tag..': the decision record carries a proposal and one card per currently offered Echo')
   local a=NexusDB.runAudit[n0.runAudit+1]
   check(type(a)=='table' and a.kind=='RUN_START' and type(a.t)=='string' and type(a.run)=='number',label..tag..': the audit record is the RUN_START of this run')
   local b,dd=NexusDB.rollTraceLog[n0.rollTrace+1],NexusDB.rollTraceLog[n0.rollTrace+2]
   check(type(b)=='table' and type(dd)=='table' and b.k=='B' and b.kind=='session' and dd.k=='D' and b.s==dd.s and type(b.n)=='number' and dd.n==b.n+1
    and type(dd.pr)=='string',label..tag..': the trace pair is the session boundary then this board decision, same session, consecutive')
   for name,delta in pairs({decision=1,runAudit=1,rollTrace=2}) do
    local m0=root.diagnosticMeta and root.diagnosticMeta.histories and root.diagnosticMeta.histories[name]
    local m1=NexusDB.diagnosticMeta and NexusDB.diagnosticMeta.histories and NexusDB.diagnosticMeta.histories[name]
    check(type(m0)=='table' and type(m1)=='table' and m1.storageTail==m0.storageTail+delta and m1.storageRetained==m0.storageRetained+delta
     and m1.retained==m0.retained+delta and m1.appended==(m0.appended or 0)+delta and rawequal(m1.storageHead,m0.storageHead) and rawequal(m1.dropped,m0.dropped),
     label..tag..': the '..name..' history counters moved by exactly '..delta..' with no eviction or compaction')
   end
  end
  SlashCmdList.NEXUS('resume');L.Advance(2)
  -- The guard was the pause: after Resume only a selected Auto may act.
  check(P.IsPaused()~=true and (Nexus.RecomputeStats().autoEnabled==true)==auto and L.attempts==(auto and 1 or 0),label..': after Resume, attempts follow Auto: '..tostring(L.attempts))
  SameLedger(L,label..' after Resume',RUN);NoOther(L,label..' after Resume')
 end
 -- F06: the counting mechanism, proved on a harmless local table first.
 local function Measure(t,name,calls)
  local orig=t[name]
  t[name]=function(...)calls[#calls+1]=name;return orig(...) end
 end
 do
  local calls,atDelegate={},nil
  local probe={Harmless=function(x)atDelegate=#calls;return x+1 end}
  check(type(probe.Harmless)=='function','R15 F06 positive: callable before the counter')
  Measure(probe,'Harmless',calls)
  check(probe.Harmless(1)==2 and atDelegate==1 and #calls==1 and calls[1]=='Harmless','R15 F06 positive: counted before the delegate, which still ran')
 end
 -- R16: all eight forbidden PerkService originals must be genuine functions before
 -- any counter or measured automation. A missing or non-function value stops here,
 -- naming the method: that exposes unavailable fixture coverage, not a product bug.
 local FORBIDDEN={'BanishPerk','FreezePerk','RequestReroll','LockPerk','UnlockPerk','SaveServerBuildSlot','ActivateServerBuildSlot','ToggleTomeEcho'}
 for _,st in ipairs({
  {'zero',{remainingBanishes=0,totalRerolls=0,usedRerolls=0,totalFreezes=0,usedFreezes=0}},
  {'abundant',{remainingBanishes=20,totalRerolls=20,usedRerolls=0,totalFreezes=10,usedFreezes=0}},
  {'missing',nil},
 }) do
  local label='R15 F06 '..st[1]..' ledger'
  local calls={}
  local L=LBoot(10,function(h)
   check(type(h.service.SelectPerk)=='function',label..': the real Select delegate is callable before its counter')
   local originals={}
   for _,name in ipairs(FORBIDDEN) do
    originals[name]=h.service[name]
    check(type(originals[name])=='function',label..': required original '..name..' is callable before any counter (found '..type(originals[name])..')')
   end
   Counted(h);h.run=st[2] and h.Clone(st[2]) or nil
   for _,name in ipairs(FORBIDDEN) do
    Measure(h.service,name,calls)
    check(h.service[name]~=originals[name],label..': the counter for '..name..' wraps its original')
   end
  end)
  SameLedger(L,label..' after boot',st[2])
  SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
  check(L.attempts==1 and #TakeIds(L)==1 and TakeIds(L)[1]==200004,label..': exactly one real Select of the winner: '..tostring(L.attempts))
  check(#calls==0,label..': zero measured unrelated native attempts: '..table.concat(calls,','))
  SameLedger(L,label,st[2]);NoOther(L,label)
 end
 -- F07: the real runtime instance, for the policy the last decision actually ran.
 local function RuntimeBoot()
  Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
  local L=dofile('tests/prototype/harness.lua');L.pendingRolls=40;L.playerLevel=10
  Counted(L)
  for line in io.lines('Nexus.toc') do
   line=line:gsub('\r','')
   if line~='' and not line:match('^#') then
    local chunk,err=loadfile((line:gsub('\\','/')));assert(chunk,err);chunk('Nexus',{})
   end
  end
  local factory=Nexus.MainInternals.AutomationRuntime;local new=factory.New
  factory.New=function(...)L.runtime=new(...);return L.runtime end
  L.Fire('ADDON_LOADED','Nexus');L.Fire('PLAYER_ENTERING_WORLD');L.Advance(20,.05)
  L.AcknowledgeOverwriteWarnings()
  check(L.runtime,'R15 F07: the real runtime instance was captured')
  return L
 end
 local A0,B3,C2={spellId=200001,quality=0},{spellId=200003,quality=3},{spellId=200002,quality=2}
 for _,row in ipairs({
  {'sparse',{A0,nil,C2},function(r)return type(r[1])=='table' and r[2]==nil and type(r[3])=='table' end,true},
  {'oversized',{A0,B3,C2,{spellId=200005,quality=1}},function(r)return type(r[4])=='table' and r[5]==nil end,true},
  {'string spell ID',{{spellId='200001',quality=0},B3,C2},function(r)return type(r[1].spellId)=='string' end,true},
  {'non-finite quality',{{spellId=200001,quality=0/0},B3,C2},function(r)return r[1].quality~=r[1].quality end,true},
  {'numeric-string quality',{{spellId=200001,quality='0'},B3,C2},function(r)return type(r[1].quality)=='string' end,true},
  {'missing quality',{{spellId=200001},B3,C2},function(r)return r[1].quality==nil and r[1].spellId==200001 end,true},
  {'unsupported quality',{{spellId=200001,quality=9},B3,C2},function(r)return r[1].quality==9 end,true},
  {'empty',{},function(r)return next(r)==nil end,false},
 }) do
  local label='R15 F07 '..row[1]..' raw board'
  local L=RuntimeBoot()
  local GA=Nexus.GameAdapter;local take,entries=GA.Take,0
  GA.Take=function(...)entries=entries+1;return take(...) end -- pass-through
  L.perks.currentChoice=row[2];L.Notify();L.Advance(.5)
  local reply=L.service.GetCurrentChoice()
  check(type(reply)=='table' and row[3](reply),label..': the actual service reply has that raw shape')
  SlashCmdList.NEXUS('leveling on');SlashCmdList.NEXUS('auto');L.Advance(3)
  -- Every other authority holds, so the shape alone is what refuses.
  check(Nexus.RecomputeStats().autoEnabled==true and Nexus.Store.Settings().autoPickLeveling==true and Nexus.Store.Settings().autoPick==true
   and Nexus.SessionPause.IsPaused()~=true and UnitLevel('player')==10,label..': Auto, option, autoPick, no pause, level 10')
  check(GA.AssignedWishlist().knownUnassigned==true and GA.Owned().synced==true and GA.OrdinaryBoardAllowed()==true,label..': known unassigned, synced, ordinary board allowed')
  local board=GA.Board()
  check((board~=nil)==row[4] and (not row[4] or board.strictObservation==false),label..': the real projection marks it not strict')
  local policy=L.runtime.RollingPolicyStatus().lastPolicy
  check((policy=='leveling-rarity-1')==row[4],label..': the real selector ran only where a board exists: '..tostring(policy))
  check(L.attempts==0 and entries==0 and GA.SelectRecoveryFacts().submitted==0,label..': zero attempted Selects, no admission')
  NoOther(L,label)
  -- The same rig is alive: a strict board takes once, so the refusal was the shape.
  L.Board(FBOARD5);L.Notify();L.Advance(2)
  check(GA.Board().strictObservation==true and L.attempts==1 and entries>=1 and TakeIds(L)[1]==200003,label..': a strict board in this rig takes the q3 winner once: '..tostring(L.attempts))
  check(L.runtime.RollingPolicyStatus().lastPolicy=='leveling-rarity-1',label..': decided by the real selector')
  local c=Captured(L,label..' strict board',200003,0)
  check(GA.SelectOutcome(c.ordinal)=='unresolved',label..': the strict board Select is unresolved under its own ordinal')
  NoOther(L,label)
 end
 -- F07: exactly one current winner: first current offer on a tie, Common 0 valid.
 local function Q(id,q)return {spellId=id,quality=q} end
 for _,row in ipairs({
  {'tie, first current offer',{{Q(200001,3),Q(200002,3),Q(200003,1)}},200001},
  {'tie reordered before admission',{{Q(200001,3),Q(200002,3),Q(200003,1)},{Q(200002,3),Q(200001,3),Q(200003,1)}},200002},
  {'all Common 0',{{Q(200005,0),Q(200006,0),Q(200007,0)}},200005},
 }) do
  local label='R15 F07 '..row[1]
  local L=LBoot(10,Counted)
  local GA=Nexus.GameAdapter
  SlashCmdList.NEXUS('leveling on')
  for _,cards in ipairs(row[2]) do L.Board(cards);L.Notify();L.Advance(.5) end
  local board=GA.Board()
  check(board and board.strictObservation==true and board.cards[1].spellId==row[3],label..': the current first offer is '..tostring(row[3]))
  SlashCmdList.NEXUS('auto');L.Advance(1.5)
  local c=Captured(L,label,row[3],0)
  L.perks.pendingSelectSpellId=nil;L.Advance(1);StillHeld(L,label..' after a latch clear',c)
  ProvenOnce(L,label,c)
 end
end
-- R17 (C02 / R6-SPEC-02 rows A04/A15): the GetCurrentChoice@raw3 after-return
-- distinct old-return / new-current-mirror witness, paired with the SAME wrapper's
-- unchanged positive. A local Seam equivalent is used only because the existing
-- Seam calls Counted before its before-callback and so cannot require the genuine
-- originals first; its semantics (after-return mutation, phase path, first-Take
-- attempt delta, restoration) are kept. Facts captured inside the getter are
-- asserted outside it (SafeCall would swallow them). Fixture only: no production,
-- Seam or selected-union change; a service-model witness, not a native observation.
do
 local function R17Seam(level,phase,mutate,label)
  local L=LBoot(level,function(h)
   check(type(h.service.GetCurrentChoice)=='function',label..': genuine original GetCurrentChoice is callable before any wrapper (found '..type(h.service.GetCurrentChoice)..')')
   check(type(h.service.SelectPerk)=='function',label..': genuine original SelectPerk is callable before its counter (found '..type(h.service.SelectPerk)..')')
   Counted(h)
  end)
  SlashCmdList.NEXUS('leveling on');L.Board(FBOARD5);L.Notify()
  local LA=Nexus.GameAdapter;local take=LA.Take
  local orig=L.service.GetCurrentChoice
  local inTake,fired,first,seen=false,false,nil,{}
  L.service.GetCurrentChoice=function(...)
   local r={orig(...)}
   if inTake then
    local p=tostring(LA.LevelingAdmissionPhase);seen[#seen+1]=p
    if p==phase and not fired then fired=true;mutate(L,r,p) end
   end
   return unpack(r)
  end
  LA.Take=function(...)
   inTake=true;local was,a0=fired,L.attempts
   local r={take(...)};inTake=false
   if fired and not was then first=L.attempts-a0 end
   return unpack(r)
  end
  SlashCmdList.NEXUS('auto');L.Advance(1.5)
  LA.Take=take;L.service.GetCurrentChoice=orig
  return L,fired,first,table.concat(seen,',')
 end
 local function Values(t)
  local v={}
  for i=1,#t do local c=t[i];v[i]={spellId=type(c)=='table' and c.spellId or nil,quality=type(c)=='table' and c.quality or nil} end
  return v
 end
 local function SameValues(a,b)
  if type(a)~='table' or type(b)~='table' or #a~=#b then return false end
  for i=1,#a do if a[i].spellId~=b[i].spellId or a[i].quality~=b[i].quality then return false end end
  return true
 end
 local function QualityOf(t,id)
  for i=1,#t do local c=t[i];if type(c)=='table' and c.spellId==id then return c.quality end end
  return nil
 end
 -- The matched unchanged positive: same wrapper and phase, no-op mutation, one
 -- real winner Select, then that exact ordinal settles once (R10Settles).
 do
  local label='R17 C02 raw3 unchanged positive'
  local L,fired,first,path=R17Seam(10,'raw3',function()end,label)
  check(fired and path:find('raw3',1,true)~=nil,label..': reached raw3 (path '..path..')')
  check(first==1,label..': exactly one native attempt in the affected Take: '..tostring(first))
  local GA=Nexus.GameAdapter;local facts=GA.SelectRecoveryFacts();local own=facts.unresolved
  check(type(own)=='table' and own.spellId==200003 and own.ordinal==facts.submitted and own.baseline==0 and type(own.run)=='number',
   label..': the real winner Select captured its ordinal, run, baseline 0 and spell')
  R10Settles(L,label,own.ordinal,own.run,own.baseline)
 end
 -- The witness: AFTER raw3 returned its unchanged reply, only the backing mirror
 -- h.perks.currentChoice is replaced by a DISTINCT clone whose competitor 200002
 -- rises q2->q4 (current winner 200003->200002); the returned table is untouched.
 do
  local label='R17 C02 raw3 old-return/new-current-mirror witness'
  local cap={}
  local L,fired,first,path=R17Seam(10,'raw3',function(h,r,p)
   cap.phase=p;cap.attempts=h.attempts;cap.submitted=Nexus.GameAdapter.SelectRecoveryFacts().submitted
   cap.returned=r[1];cap.returnedValues=type(r[1])=='table' and Values(r[1]) or nil
   cap.backing=h.perks.currentChoice;cap.backingValues=type(cap.backing)=='table' and Values(cap.backing) or nil
   if type(cap.backing)=='table' then
    local clone=h.Clone(cap.backing);cap.changed=0
    for i=1,#clone do local c=clone[i];if type(c)=='table' and c.spellId==200002 and c.quality==2 then c.quality=4;cap.changed=cap.changed+1 end end
    cap.clone=clone;h.perks.currentChoice=clone
   end
  end,label)
  check(fired and cap.phase=='raw3' and path:find('raw3',1,true)~=nil,label..': reached raw3 after the getter returned (path '..path..')')
  check(cap.attempts==0 and cap.submitted==0,label..': no earlier native attempt or Select ordinal at the seam')
  check(type(cap.returned)=='table' and type(cap.backing)=='table' and SameValues(cap.returnedValues,cap.backingValues),
   label..': the returned raw3 board and the backing mirror agreed before the replacement')
  check(cap.changed==1 and type(cap.clone)=='table' and cap.clone~=cap.backing and cap.clone~=cap.returned and L.perks.currentChoice==cap.clone,
   label..': only the backing mirror now points at a distinct clone (one competitor q2->q4)')
  check(SameValues(Values(cap.returned),cap.returnedValues) and QualityOf(cap.returned,200002)==2 and QualityOf(cap.clone,200002)==4,
   label..': the returned table and its values are unchanged while the clone differs')
  local win,q=nil,-1
  for i=1,#cap.clone do local c=cap.clone[i];if type(c)=='table' and type(c.quality)=='number' and c.quality>q then win,q=c.spellId,c.quality end end
  check(win==200002 and q==4,label..': the current mirror winner moved 200003->200002')
  -- The strict-final-choice C02 service-model refusal oracle, asserted on the first
  -- affected Take alone. Predicted RED under the pinned production (5114 compares
  -- the returned raw3 board only; 5140-5157 never compare the whole choice).
  -- Conditional on that service model; not a native defect claim.
  check(first==0,label..': ZERO native attempts in the first affected Take: '..tostring(first))
 end
end
-- F05 (complete26 rows A17/A18/A20; requirement v2): the GENUINE Orb owned/pending
-- lifecycle through the existing, unchanged tests/prototype/orbs_support.lua harness.
-- The ONLY Orb spend in this fixture is the separate MANUAL Orb approval made with
-- Random Roll OFF and Auto OFF (Orb mode's own flow: a safety setup, not Random
-- Roll behaviour and not a Wishlist prerequisite). Random Roll is enabled only
-- afterwards and must be refused by the genuine gate; Auto refusal alone could mask
-- a zero-Take result, so the REAL OrdinaryBoardAllowed is observed through a
-- passthrough inside the REAL A.Take and asserted outside any swallowed callback.
-- No BlocksOrdinary stub, no fabricated token, no fallback unassignment. This block
-- keeps its own explicit one-spend baseline instead of the global NoOther.
do
 local label='F05 genuine owned/pending'
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local L=dofile('tests/prototype/orbs_support.lua');L.playerLevel=10
 check(type(L.service)=='table' and type(L.service.SelectPerk)=='function' and type(L.O)=='table' and type(L.OrbPlan)=='function'
  and type(L.Approve)=='function' and type(L.Count)=='function',label..': genuine support delegates present (precondition)')
 Counted(L)
 local A,M=Nexus.GameAdapter,Nexus.OrbRuntime
 check(type(M)=='table' and type(M.BlocksOrdinary)=='function' and type(M.Status)=='function' and type(A.Orbs)=='table' and type(A.Orbs.IsOwned)=='function',
  label..': genuine Orb runtime and adapter present (precondition)')
 check(UnitLevel('player')==10,label..': live level 10')
 check(Nexus.Store.Settings().autoPickLeveling==nil and not Nexus.RecomputeStats().autoEnabled,label..': Random Roll absent (OFF) and Auto OFF before the manual setup')
 check(L.O.offer==false and L.attempts==0 and L.Count('orb-spend')==0,label..': no offer, no attempt, no spend before the setup')
 check(A.Orbs.IsOwned()==false and M.BlocksOrdinary()==false and A.OrdinaryBoardAllowed()==true,label..': known idle service: ordinary rolling allowed (A17)')
 -- P1: the separate MANUAL Orb approval (Orb mode's own flow; Random Roll OFF).
 L.OrbPlan();local receipt=L.Approve(2,false,true)
 check(type(receipt)=='table',label..': the manual approval returned its receipt')
 if L.Count('orb-spend')==0 then L.Advance(.1) end
 local st=M.Status(false)
 check(A.Orbs.IsOwned()==true and st.running==true and st.pending==true,label..': actual owned and pending status after the manual approval: '..tostring(st.state))
 local baseSpend,baseSpends,baseCharges=L.Count('orb-spend'),L.O.spends,L.O.charges
 check(baseSpend==1 and baseSpends==1 and (L.O.source==410001 or L.O.source==410003),label..': exactly one manual setup spend, made with Random Roll OFF: '..tostring(baseSpend))
 check(L.attempts==0 and #TakeIds(L)==0,label..': the manual setup made no native Select attempt')
 check(M.BlocksOrdinary()==true and A.OrdinaryBoardAllowed()==false,label..': the genuine pending run blocks ordinary rolling')
 check(not Nexus.RecomputeStats().autoEnabled,label..': Auto stays OFF after Confirm')
 -- P2: real unassignment by the existing first-run setter; success asserted, never projected.
 local s0=Nexus.Store.State()
 check(type(s0)=='table' and type(s0.firstRunWishlist)=='table' and type(s0.loadoutWishlists)=='table' and type(s0.loadoutWishlists[1])=='table',
  label..': the Orb plan installed the first-run plan and the stamped slot-1 handoff')
 local a0=A.AssignedWishlist()
 check(a0.state=='ready' and a0.knownUnassigned==nil,label..': assigned before the clear: '..tostring(a0.state))
 check(A.ClearFirstRunWishlist()==true,label..': ClearFirstRunWishlist succeeded')
 local s1=Nexus.Store.State()
 check(s1.firstRunWishlist==false and s1.loadoutWishlists[1]==nil,label..': first-run plan cleared and the stamped slot-1 handoff removed (named precondition: handoff pairing)')
 L.Advance(1);M.Pump()
 local a=A.AssignedWishlist();local owner=Nexus.Store.CurrentOwnerKey()
 check(a.state=='unassigned' and a.knownUnassigned==true and type(owner)=='string' and owner~='' and a.unassignedKey==owner..'|0|'..tostring(L.perks.serverActiveSlot),
  label..': the current owner is positively known unassigned: '..tostring(a.state)..' / '..tostring(a.unassignedKey))
 st=M.Status(false)
 check(A.Orbs.IsOwned()==true and st.pending==true and st.running==false and st.state=='PAUSED' and st.targetChanged==true,
  label..': the pending operation stays owned and paused after the assignment change: '..tostring(st.state))
 check(M.BlocksOrdinary()==true and A.OrdinaryBoardAllowed()==false,label..': still blocked by the genuine state')
 check(L.Count('orb-spend')==baseSpend and L.O.spends==baseSpends and L.attempts==0,label..': the unassignment spent nothing and selected nothing')
 -- P3: Random Roll ON, Auto requested, an ordinary board offered.
 SlashCmdList.NEXUS('leveling on')
 check(Nexus.Store.Settings().autoPickLeveling==true,label..': Random Roll ON only after the separate setup')
 SlashCmdList.NEXUS('auto')
 check(not Nexus.RecomputeStats().autoEnabled,label..': Auto refused while the Orb run blocks ordinary rolling (refusal alone could mask a zero Take)')
 L.Board(LBOARD);L.Notify();L.Advance(3)
 check(L.attempts==0 and #TakeIds(L)==0,label..': zero native Select attempts with the board offered')
 -- Gate consumption proof: passthrough of the REAL gate inside the REAL A.Take; asserted outside.
 local real=A.OrdinaryBoardAllowed;local calls,last,lastWhy=0,nil,nil
 A.OrdinaryBoardAllowed=function(...) calls=calls+1;local r={real(...)};last,lastWhy=r[1],r[2];return unpack(r) end
 local ok,why=A.Take(200004)
 A.OrdinaryBoardAllowed=real
 check(ok==false and type(why)=='string' and calls>=1 and last==false and type(lastWhy)=='string' and why==lastWhy,
  label..': the real entry gate ran inside the real Take and refused: '..tostring(why))
 local ok2,why2=A.OrdinaryBoardAllowed()
 check(ok2==false and type(why2)=='string' and M.BlocksOrdinary()==true and A.Orbs.IsOwned()==true,label..': the unwrapped gate refuses from the genuine owned/pending state (no stub)')
 check(L.attempts==0 and L.perks.pendingSelectSpellId==nil and #TakeIds(L)==0,label..': the direct Take sent nothing')
 local k=Kinds(L)
 check(k.take==nil and k.banish==nil and k.freeze==nil and k.reroll==nil and k.lock==nil and k.unlock==nil and k.toggle==nil and k.activate==nil and k.save==nil and k.upload==nil,
  label..': no forbidden ordinary mutation')
 check(L.Count('orb-spend')==baseSpend and L.O.spends==baseSpends and L.O.charges==baseCharges,label..': no additional Orb mutation and unchanged charges')
 L.Advance(3)
 check(L.attempts==0 and L.Count('orb-spend')==baseSpend and A.Orbs.IsOwned()==true and M.Status(false).pending==true,label..': later time adds nothing; the pending operation remains')
end
-- F05 matched positive: the same genuine known-idle OrbService (orbs_support, NO
-- OrbPlan/Approve), no Wishlist, Random Roll ON: exactly one ordinary highest-rarity
-- Select, captured ordinal/run/baseline, the same ordinal settled once by the real
-- R8 latch/grant sequence, no replay, zero Orb mutations.
do
 local label='F05 known-idle no-Wishlist positive'
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local L=dofile('tests/prototype/orbs_support.lua');L.playerLevel=10;Counted(L)
 local A,M=Nexus.GameAdapter,Nexus.OrbRuntime
 check(type(A.Orbs)=='table' and A.Orbs.IsOwned()==false and M.BlocksOrdinary()==false and A.OrdinaryBoardAllowed()==true,label..': known idle service, nothing owned (A17)')
 local a=A.AssignedWishlist()
 check(a.state=='unassigned' and a.knownUnassigned==true,label..': no Wishlist, positively known unassigned')
 SlashCmdList.NEXUS('leveling on');SlashCmdList.NEXUS('auto');L.Board(LBOARD);L.Notify();L.Advance(1.5)
 check(Nexus.RecomputeStats().autoEnabled==true,label..': Auto ON (no Orb block)')
 local ids=TakeIds(L)
 check(L.attempts==1 and #ids==1 and ids[1]==200004,label..': exactly one ordinary highest-rarity Select: '..tostring(ids[1]))
 local facts=A.SelectRecoveryFacts();local own=facts.unresolved
 check(type(own)=='table' and own.ordinal==facts.submitted and own.spellId==200004 and own.baseline==0 and type(own.run)=='number',label..': captured ordinal/run/baseline')
 local ordinal,run=own.ordinal,own.run
 L.perks.pendingSelectSpellId=nil;L.Advance(1)
 local held=A.SelectRecoveryFacts().unresolved
 check(A.SelectOutcome(ordinal)=='unresolved' and held and held.ordinal==ordinal and held.run==run and held.baseline==0
  and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..': latch clear alone proves nothing; the exact record is retained')
 GrantOf(L,200004);L.Advance(2)
 local last,outcome=A.LastSelectOutcome()
 check(A.SelectOutcome(ordinal)=='proven' and last==ordinal and outcome=='proven' and Nexus.RecomputeStats().actionLifecycle.confirmed==1,label..': that exact ordinal is proven once')
 check(A.SelectRecoveryFacts().unresolved==nil and A.SelectRecoveryFacts().submitted==ordinal,label..': no further Select ordinal')
 L.Advance(3);check(L.attempts==1,label..': never resent');NoOther(L,label)
 check(L.Count('orb-spend')==0 and L.O.spends==nil and L.O.charges==10 and A.Orbs.IsOwned()==false and M.BlocksOrdinary()==false,label..': zero Orb mutations, unchanged charges, nothing owned')
end
-- F05 A18 service-state seams (SYNTHETIC-ONLY provider states on the plain harness,
-- labelled; the real OrbAdapter classifier and the real gates decide): pending,
-- unknown, malformed, member-throw and non-boolean each block ordinary admission at
-- the decision and at the real Take entry gate (passthrough observed outside the
-- callback), with zero native attempts. No native timing or primary-host claim.
for _,case in ipairs({
 {'pending',function() return {IsStateKnown=function() return true end,IsOfferPending=function() return true end} end},
 {'unknown',function() return {IsStateKnown=function() return false end,IsOfferPending=function() return false end} end},
 {'malformed (non-table service)',function() return 'not a table' end},
 {'member throw',function() return setmetatable({},{__index=function() error('synthetic member read failure') end}) end},
 {'non-boolean',function() return {IsStateKnown=function() return 'yes' end,IsOfferPending=function() return 0 end} end},
}) do
 local label='F05 A18 synthetic '..case[1]
 local L=LBoot(10,function(h)Counted(h);ProjectEbonhold.OrbService=case[2]() end)
 local A=Nexus.GameAdapter
 local ok0,why0=A.OrdinaryBoardAllowed()
 check(ok0==false and type(why0)=='string',label..': the real classifier blocks ordinary rolling: '..tostring(why0))
 SlashCmdList.NEXUS('leveling on');L.Board(LBOARD);L.Notify();SlashCmdList.NEXUS('auto');L.Advance(3)
 check(L.attempts==0 and #TakeIds(L)==0,label..': zero native attempts through the ordinary dispatch')
 local real=A.OrdinaryBoardAllowed;local calls,last=0,nil
 A.OrdinaryBoardAllowed=function(...) calls=calls+1;local r={real(...)};last=r[1];return unpack(r) end
 local ok,why=A.Take(200004)
 A.OrdinaryBoardAllowed=real
 check(ok==false and type(why)=='string' and calls>=1 and last==false and L.attempts==0,label..': the real Take entry gate refused: '..tostring(why))
 NoOther(L,label)
end
-- F05 A18 late idle->pending at the Take's own final 'orb' re-check (SYNTHETIC flip
-- of the provider state after the genuine g2 getter returned), with its matched
-- unchanged positive on the same seam. The phase/reach witness is recorded by a
-- passthrough of the real gate and asserted OUTSIDE the swallowed callback.
do
 local function IdleService(h) ProjectEbonhold.OrbService={IsStateKnown=function() return true end,IsOfferPending=function() return false end} end
 local function GateWitness()
  local A=Nexus.GameAdapter;local real=A.OrdinaryBoardAllowed;local log={}
  A.OrdinaryBoardAllowed=function(...) local r={real(...)};log[#log+1]={phase=tostring(A.LevelingAdmissionPhase),allowed=r[1]};return unpack(r) end
  return log,function() A.OrdinaryBoardAllowed=real end
 end
 do
  local label='F05 A18 late idle->pending (synthetic flip after g2)'
  local log,restore
  local L,fired,first,path=Seam(10,'GetGrantedPerks','g2',function()
   ProjectEbonhold.OrbService.IsOfferPending=function() return true end
  end,LBOARD,IdleService,function() log,restore=GateWitness() end)
  restore()
  check(fired and path:find('g2',1,true)~=nil,label..': reached g2 (path '..path..')')
  check(first==0 and L.attempts==0 and #TakeIds(L)==0,label..': ZERO native attempts in the affected Take: '..tostring(first))
  local entryOk,orbRefused=false,false
  for _,e in ipairs(log) do if e.phase=='entry' and e.allowed==true then entryOk=true end;if e.phase=='orb' and e.allowed==false then orbRefused=true end end
  check(entryOk and orbRefused,label..': the real gate allowed at entry and refused at the final orb phase (witness outside the callback)')
  L.Advance(3);check(L.attempts==0,label..': nothing sent later');NoOther(L,label)
 end
 do
  local label='F05 A18 late seam matched positive'
  local log,restore
  local L,fired,first,path=Seam(10,'GetGrantedPerks','g2',function() end,LBOARD,IdleService,function() log,restore=GateWitness() end)
  restore()
  check(fired and path:find('g2',1,true)~=nil,label..': reached g2 (path '..path..')')
  check(first==1 and L.attempts==1 and #TakeIds(L)==1 and TakeIds(L)[1]==200004,label..': exactly one Select of the highest rarity: '..tostring(first))
  local orbAllowed=false
  for _,e in ipairs(log) do if e.phase=='orb' and e.allowed==true then orbAllowed=true end end
  check(orbAllowed,label..': the real gate allowed at the final orb phase (witness outside the callback)')
  local A=Nexus.GameAdapter;local facts=A.SelectRecoveryFacts();local own=facts.unresolved
  check(type(own)=='table' and own.ordinal==facts.submitted and own.spellId==200004 and own.baseline==0 and type(own.run)=='number',label..': captured ordinal/run/baseline')
  local ordinal=own.ordinal
  L.perks.pendingSelectSpellId=nil;L.Advance(1)
  check(A.SelectOutcome(ordinal)=='unresolved' and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..': latch clear alone proves nothing')
  GrantOf(L,200004);L.Advance(2)
  local last,outcome=A.LastSelectOutcome()
  check(A.SelectOutcome(ordinal)=='proven' and last==ordinal and outcome=='proven' and Nexus.RecomputeStats().actionLifecycle.confirmed==1,label..': that exact ordinal is proven once')
  L.Advance(3);check(L.attempts==1 and A.SelectRecoveryFacts().submitted==ordinal,label..': never resent, no further ordinal');NoOther(L,label)
 end
end
-- C02 matched controls for the final mirror guard (GameAdapter A.Take phase
-- 'mirror': the last memory-only strict-key comparison of Perks.currentChoice
-- after expect.final and the pause boundary, immediately before the native
-- Select). Genuine seams only: the real service getters GetCurrentChoice (raw3)
-- and GetServerActiveSlot (slot), each mutated AFTER it returned, and the real
-- Nexus.SessionPause.IsPaused call of the pause boundary (the 2nd 'memory'-phase
-- call inside the Take; the 1st is inside LevelingFinal via expect.final), so a
-- mutation there happens AFTER the genuine expect.final returned. Every fact
-- captured inside a wrapper is asserted outside it. Negatives: zero native
-- attempts in the first affected Take, refusal 'leveling_offer_changed' at phase
-- 'mirror', no recovery record at that moment. An in-place rise leaves a VALID
-- current board whose winner is now 200002: the documented resume (R5-SPEC-02,
-- AutomationRuntime 3576-3581) makes one later fresh Take of 200002, which is
-- asserted positively and settled once with its own ordinal; the stale 200003 is
-- never sent. A nil-cleared mirror leaves no board, so that negative stays at
-- zero attempts for the whole run. Positives: exactly one Select of the FBOARD5
-- winner settled once (R10Settles). Source-model timing only: no native
-- reachability, atomicity or ordering claim; the strict R17 witness is unchanged.
do
 local function C02Seam(level,seamName,phase,nth,mutate,label)
  local L=LBoot(level,function(h)
   check(type(h.service.GetCurrentChoice)=='function' and type(h.service.GetServerActiveSlot)=='function' and type(h.service.SelectPerk)=='function',
    label..': genuine originals callable before any wrapper')
   Counted(h)
  end)
  SlashCmdList.NEXUS('leveling on');L.Board(FBOARD5);L.Notify()
  local LA=Nexus.GameAdapter;local take=LA.Take
  local SP=Nexus.SessionPause
  check(type(SP)=='table' and type(SP.IsPaused)=='function',label..': genuine SessionPause.IsPaused present')
  local holder=seamName=='IsPaused' and SP or L.service
  local orig=holder[seamName]
  check(type(orig)=='function',label..': genuine seam '..seamName..' is a function')
  local inTake,fired,first,seen,matched=false,false,nil,{},0
  local cap={}
  holder[seamName]=function(...)
   local r={orig(...)}
   if inTake then
    local p=tostring(LA.LevelingAdmissionPhase);seen[#seen+1]=p
    if p==phase then
     matched=matched+1
     if matched==nth and not fired then fired=true;cap.firedAtCall=matched;mutate(L,r,p) end
    end
   end
   return unpack(r)
  end
  LA.Take=function(...)
   inTake=true;local was,a0=fired,L.attempts
   local r={take(...)};inTake=false
   if fired and not was then
    first=L.attempts-a0;cap.ok=r[1];cap.err=r[2];cap.phase=LA.LevelingAdmissionPhase
    cap.facts=LA.SelectRecoveryFacts()
   end
   return unpack(r)
  end
  SlashCmdList.NEXUS('auto');L.Advance(1.5)
  LA.Take=take;holder[seamName]=orig
  return L,fired,first,table.concat(seen,','),cap
 end
 -- The immediate first-affected-Take facts shared by every negative.
 local function RefusedAtMirror(label,L,fired,first,path,cap,phaseName)
  check(fired and path:find(phaseName,1,true)~=nil,label..': reached '..phaseName..' (path '..path..')')
  check(first==0,label..': ZERO native attempts in the first affected Take: '..tostring(first))
  check(cap.ok==false and cap.err=='leveling_offer_changed' and cap.phase=='mirror',
   label..': refused at the final mirror phase: '..tostring(cap.err)..' / '..tostring(cap.phase))
  check(type(cap.facts)=='table' and cap.facts.unresolved==nil and cap.facts.submitted==0,label..': no Select recovery record at the refusal')
 end
 -- No board remains (nil-cleared mirror): nothing is ever sent in the whole run.
 local function NoBoardNegative(label,L,fired,first,path,cap,phaseName)
  RefusedAtMirror(label,L,fired,first,path,cap,phaseName)
  check(L.attempts==0 and #TakeIds(L)==0,label..': no native attempt at all')
  L.Advance(3);check(L.attempts==0 and #TakeIds(L)==0,label..': nothing sent later');NoOther(L,label)
 end
 -- A valid current board remains (in-place rise): the stale 200003 is never sent;
 -- the documented resume makes exactly ONE later fresh Take of the current winner
 -- `freshSpell`, whose own ordinal/run/baseline are captured and settled exactly once
 -- by the R8/GrantOf sequence (R10Settles is not used: it hard-codes 200003).
 local function FreshBoardNegative(label,L,fired,first,path,cap,phaseName,freshSpell)
  RefusedAtMirror(label,L,fired,first,path,cap,phaseName)
  for _,id in ipairs(TakeIds(L)) do check(id~=200003,label..': the stale winner 200003 is never sent') end
  L.Advance(3)
  local ids=TakeIds(L)
  for _,id in ipairs(ids) do check(id~=200003,label..': the stale winner 200003 is never sent later') end
  check(L.attempts==1 and #ids==1 and ids[1]==freshSpell,label..': exactly one later fresh Take of the current winner '..tostring(freshSpell)..': '..tostring(ids[1]))
  local GA=Nexus.GameAdapter;local facts=GA.SelectRecoveryFacts();local own=facts.unresolved
  check(type(own)=='table' and own.spellId==freshSpell and own.ordinal==facts.submitted and own.ordinal>cap.facts.submitted and own.baseline==0
   and type(own.run)=='number' and own.postsend==nil and (own.competing or 0)==0,label..': the fresh Select captured its own ordinal, run, baseline 0 and spell')
  local ordinal,run=own.ordinal,own.run
  L.perks.pendingSelectSpellId=nil;L.Advance(1)
  local held=GA.SelectRecoveryFacts().unresolved
  check(GA.SelectOutcome(ordinal)=='unresolved' and held and held.ordinal==ordinal and held.run==run and held.baseline==0
   and Nexus.RecomputeStats().actionLifecycle.confirmed==0,label..': latch clear alone proves nothing; the fresh record is retained')
  GrantOf(L,freshSpell);L.Advance(2)
  local last,outcome=GA.LastSelectOutcome()
  check(GA.SelectOutcome(ordinal)=='proven' and last==ordinal and outcome=='proven' and Nexus.RecomputeStats().actionLifecycle.confirmed==1,
   label..': the matching grant proves that fresh ordinal once')
  check(GA.SelectRecoveryFacts().unresolved==nil and GA.SelectRecoveryFacts().submitted==ordinal,label..': no further Select ordinal')
  L.Advance(3)
  check(L.attempts==1 and #TakeIds(L)==1 and TakeIds(L)[1]==freshSpell and Nexus.RecomputeStats().actionLifecycle.confirmed==1,label..': never resent, settled once')
  NoOther(L,label)
 end
 local function Positive(label,L,fired,first,path,cap,phaseName)
  check(fired and path:find(phaseName,1,true)~=nil,label..': reached '..phaseName..' (path '..path..')')
  check(first==1 and cap.ok==true and L.attempts==1 and #TakeIds(L)==1 and TakeIds(L)[1]==200003,label..': exactly one Select of the winner: '..tostring(first))
  local facts=Nexus.GameAdapter.SelectRecoveryFacts();local own=facts.unresolved
  check(type(own)=='table' and own.spellId==200003 and own.ordinal==facts.submitted and own.baseline==0 and type(own.run)=='number',
   label..': captured ordinal, run, baseline 0 and spell')
  R10Settles(L,label,own.ordinal,own.run,own.baseline)
 end
 local function RaiseInPlace(t) local n=0;if type(t)=='table' then for i=1,#t do local c=t[i];if type(c)=='table' and c.spellId==200002 and c.quality==2 then c.quality=4;n=n+1 end end end;return n end
 -- N2: in-place mutation of the LIVE mirror after the slot getter returned (after raw3 was keyed).
 do
  local label='C02 slot in-place mutation negative';local mutated={}
  local L,fired,first,path,cap=C02Seam(10,'GetServerActiveSlot','slot',1,function(h) mutated.changed=RaiseInPlace(h.perks.currentChoice) end,label)
  check(mutated.changed==1 and cap.firedAtCall==1,label..': one competitor rose q2->q4 in place in the live mirror after raw3')
  FreshBoardNegative(label,L,fired,first,path,cap,'slot',200002)
 end
 -- N3: the mirror cleared to nil after raw3 returned (the returned table is untouched).
 do
  local label='C02 raw3 nil-clear negative';local mutated={}
  local L,fired,first,path,cap=C02Seam(10,'GetCurrentChoice','raw3',1,function(h,r) mutated.wasTable=type(h.perks.currentChoice)=='table';mutated.returned=type(r[1])=='table';h.perks.currentChoice=nil end,label)
  check(mutated.wasTable==true and mutated.returned==true and L.perks.currentChoice==nil,label..': the mirror was a table, the returned table stays, the mirror is now nil')
  NoBoardNegative(label,L,fired,first,path,cap,'raw3')
 end
 -- P2: a DISTINCT value-identical republication after raw3 returned must pass.
 do
  local label='C02 raw3 value-identical republication positive';local mutated={}
  local L,fired,first,path,cap=C02Seam(10,'GetCurrentChoice','raw3',1,function(h,r)
   local clone=h.Clone(h.perks.currentChoice);mutated.distinct=type(clone)=='table' and clone~=h.perks.currentChoice and clone~=r[1];h.perks.currentChoice=clone;mutated.clone=clone
  end,label)
  check(mutated.distinct==true and L.perks.currentChoice==mutated.clone,label..': the mirror now points at a distinct value-identical table')
  Positive(label,L,fired,first,path,cap,'raw3')
 end
 -- N4: late in-place mutation AFTER the genuine expect.final returned (pause-boundary IsPaused, 2nd memory-phase call).
 do
  local label='C02 late post-final in-place mutation negative';local mutated={}
  local L,fired,first,path,cap=C02Seam(10,'IsPaused','memory',2,function(h) mutated.changed=RaiseInPlace(h.perks.currentChoice) end,label)
  check(mutated.changed==1 and cap.firedAtCall==2,label..': one competitor rose q2->q4 after expect.final returned (2nd memory-phase IsPaused)')
  FreshBoardNegative(label,L,fired,first,path,cap,'memory',200002)
 end
 -- P3: the matched unchanged positive on the same late seam (no-op after expect.final).
 do
  local label='C02 late post-final matched positive'
  local L,fired,first,path,cap=C02Seam(10,'IsPaused','memory',2,function() end,label)
  check(cap.firedAtCall==2,label..': the no-op fired on the 2nd memory-phase IsPaused call')
  Positive(label,L,fired,first,path,cap,'memory')
 end
end
print('PASS actual recommendation/automation and resource-safety checks='..checks)
