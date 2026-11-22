-- Start/Stop Orb automation (OrbAuto; user-authorized rework of 2026-11-19).
-- No Orb maximum, Start and Stop only. A needed Echo is chosen from an Orb
-- offer whatever the balance did; an offer without one is redrawn with the
-- game's own Orb redraw; with nothing on the table one Orb opens a draw; a
-- free draw with a needed Echo is taken through the ordinary Take; one
-- without stays with the ordinary flow. One request in flight, never
-- repeated. Synthetic game services only; the native redraw is a stub of the
-- game's OrbService.CanRerollOffer / RerollOffer.
local checks=0
local function check(v,msg) assert(v,msg);checks=checks+1 end
local TARGET={spellId=410002,quality=2}
local OFFER_HIT={{spellId=410004,quality=3},{spellId=410002,quality=2},{spellId=410005,quality=0}}
local OFFER_MISS={{spellId=410004,quality=3},{spellId=410005,quality=0},{spellId=410006,quality=3}}
local function World(opts)
 opts=opts or {}
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 if NexusOrbAuto then NexusOrbAuto:SetScript('OnUpdate',nil);NexusOrbAuto:SetScript('OnEvent',nil);NexusOrbAuto:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 local O=H.O
 local orb=ProjectEbonhold.OrbService
 O.redraws=0;O.canRedraw=true
 orb.CanRerollOffer=function() return O.canRedraw and O.charges>0 end
 orb.RerollOffer=function() O.redraws=O.redraws+1;H.actions[#H.actions+1]={'orb-redraw'};return true end
 if opts.updated then ProjectEbonhold.PerkService.WantsMoreOfEcho=function() return false end end
 H.OrbPlan(opts.plan or {{spellId=410002,quality=2,stacks=1}})
 return H,Nexus.OrbAuto,H.A,O
end
local function Offer(H,O,cards) O.offer=true;H.Board(cards) end
-- The game takes the chosen Echo: the offer ends, the choice is cleared and
-- ownership shows the Echo (the source given up by a spend is removed).
local function Taken(H,O,id,q)
 local out=H.Clone(H.granted)
 if O.source then
  for _,es in pairs(out) do for i=#es,1,-1 do if es[i].spellId==O.source then table.remove(es,i);O.source=nil;break end end end
 end
 out[H.names[id]]=out[H.names[id]] or {};table.insert(out[H.names[id]],{spellId=id,quality=q})
 H.granted=out;H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 H.Notify();H.A.Poll()
end
local function Pass(H,seconds) H.Advance(seconds or .5) end

-- 1. Fresh pick: an Orb offer with a needed Echo is answered once, no Orb spent,
-- with the balance unchanged (masked) and after it rose (a reward).
for _,balance in ipairs({'unchanged','raised'}) do
 local H,M,A,O=World()
 if balance=='raised' then O.charges=O.charges+3 end
 Offer(H,O,OFFER_HIT)
 local spends=H.Count('orb-spend')
 check(M.Start(),'1 '..balance..': Start')
 Pass(H)
 check(H.Count('take')==1 and H.Count('orb-spend')==spends,'1 '..balance..': the needed Echo is chosen once, no Orb spent')
 Pass(H,2)
 check(H.Count('take')==1,'1 '..balance..': the choice is not repeated while it is in flight')
 check(M.Status().inflight=='select','1 '..balance..': one request in flight')
 Taken(H,O,410002,2);Pass(H)
 check(M.Status().state=='DONE' and not M.Active(),'1 '..balance..': the Wishlist is complete: the run ends normally')
end

-- 2. Clear board, new Start: one Orb opens a draw, the needed Echo is chosen, done.
do
 local H,M,A,O=World()
 check(M.Start(),'2: Start')
 Pass(H)
 check(H.Count('orb-spend')==1 and M.Status().inflight=='spend','2: one Orb spent to open a draw')
 check(Nexus.Store.State().orbRefinement==nil or Nexus.Store.State().orbRefinement.pending==nil,'2: the session-only run writes no Orb receipt')
 Pass(H,3)
 check(H.Count('orb-spend')==1,'2: no second spend while the offer is awaited')
 Offer(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1,'2: the needed Echo is chosen from the opened offer')
 Taken(H,O,410002,2);Pass(H)
 check(M.Status().state=='DONE' and H.Count('orb-spend')==1,'2: complete after one Orb')
end

-- 3. No needed Echo on the Orb offer: the game's own redraw, once per offer.
do
 local H,M,A,O=World()
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'3: Start')
 Pass(H)
 check(O.redraws==1 and H.Count('take')==0 and H.Count('orb-spend')==0,'3: one native redraw, no choice, no spend')
 Pass(H,3)
 check(O.redraws==1,'3: no second redraw before the game answers')
 Offer(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1 and O.redraws==1,'3: the redrawn offer is answered with the needed Echo')
 -- a client without the redraw: the offer is left to the player
 local H2,M2,A2,O2=World()
 ProjectEbonhold.OrbService.RerollOffer=nil
 Offer(H2,O2,OFFER_MISS);check(M2.Start(),'3b: Start');Pass(H2)
 check(not M2.Active() and M2.Status().state=='DONE' and H2.Count('take')==0,'3b: no redraw available: the run ends and the offer is left to the player')
end

-- 4. A request the game never answers is not repeated.
do
 local H,M,A,O=World()
 check(M.Start(),'4: Start');Pass(H)
 local requests=O.requests
 Pass(H,25)
 check(H.Count('orb-spend')==1,'4: no duplicate spend after a long wait')
 check(O.requests==requests+1,'4: one read-only refresh request')
 check(M.Active() and M.Status().state=='WAITING','4: the run waits and says so')
 -- a late answer is still taken
 Offer(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1 and H.Count('orb-spend')==1,'4: the late offer is answered once')
end

-- 5. Stop ends automation immediately.
do
 local H,M,A,O=World()
 check(M.Start(),'5: Start');Pass(H)
 check(H.Count('orb-spend')==1,'5: setup: one Orb spent')
 check(M.Stop() and not M.Active(),'5: Stop')
 check(not A.Orbs.IsOwned(),'5: the Orb ownership is released')
 Offer(H,O,OFFER_HIT);Pass(H,3)
 check(H.Count('take')==0 and H.Count('orb-spend')==1,'5: nothing is sent after Stop')
end

-- 6. A loadout (slot) switch ends the run.
do
 local H,M,A,O=World()
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
  [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 -- both loadouts carry the same ready Wishlist, so only the switch itself can end the run
 assert(A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410002,quality=2,stacks=1}}))
 assert(A.SetLoadoutWishlistIdentity(2,'Second',{{spellId=410002,quality=2,stacks=1}}))
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'6: Start');Pass(H)
 check(O.redraws==1,'6: setup: one redraw')
 H.perks.serverActiveSlot=2;Offer(H,O,OFFER_HIT);Pass(H)
 check(not M.Active() and H.Count('take')==0 and M.Status().reason:find('active loadout changed',1,true),'6: a slot switch ends the run before any further choice: '..tostring(M.Status().reason))
end

-- 7. No Orbs, no eligible source, a complete Wishlist: the run ends normally.
do
 local H,M,A,O=World();O.charges=0
 local ok,why=M.Start();Pass(H)
 check(not ok and tostring(why):find('No confirmed Orbs',1,true) and not M.Active() and H.Count('orb-spend')==0,'7a: no Orbs: Start says so and spends nothing: '..tostring(why))
 local H2,M2,A2,O2=World({plan={{spellId=410002,quality=2,stacks=1}}})
 H2.granted={}; H2.Notify();A2.Poll()
 local ok2,why2=M2.Start();Pass(H2)
 check(not ok2 and tostring(why2):find('No safe surplus',1,true) and H2.Count('orb-spend')==0,'7b: no eligible source: Start says so and spends nothing: '..tostring(why2))
 local H3,M3,A3,O3=World()
 H3.granted['Desired A']={{spellId=410002,quality=2}};H3.Notify();A3.Poll()
 local ok3,why3=M3.Start();Pass(H3)
 check(not ok3 and tostring(why3):find('complete',1,true) and H3.Count('orb-spend')==0,'7c: complete Wishlist: Start says so and spends nothing: '..tostring(why3))
 -- the run that reaches the end on its own ends normally (case 2); and during a
 -- run the last Orb spent ends it once its offer is answered
 local H4,M4,A4,O4=World();O4.charges=1
 check(M4.Start(),'7d: Start with one Orb');Pass(H4)
 check(H4.Count('orb-spend')==1,'7d: the last Orb opens a draw')
 O4.charges=0;Offer(H4,O4,OFFER_MISS);Pass(H4)
 check(not M4.Active() and M4.Status().state=='DONE' and O4.redraws==0,'7d: no Orb left to redraw: the run ends and the offer is left to the player')
end

-- 8. A free (ordinary) draw without a needed Echo keeps the ordinary flow.
-- Ordinary Auto ON before Start stays ON (Start changes no ordinary setting);
-- its standalone action on that board is the action it takes during a run, and
-- no Orb is spent while the board is open. (Ordinary Auto OFF: case 17.)
local function nonOrb(H)
 local out={}
 for _,a in ipairs(H.actions) do if a[1]~='orb-spend' then out[#out+1]=a[1]..':'..tostring(a[2]) end end
 return table.concat(out,',')
end
do
 -- standalone reference: ordinary Auto alone on the same free draw
 local H0,M0,A0,O0=World()
 SlashCmdList.NEXUS('auto');H0.Board(OFFER_MISS);Pass(H0,5)
 local standalone=nonOrb(H0)
 check(standalone~='' and not standalone:find(',',1,true),'8: setup: standalone ordinary Auto acts once on the free draw: '..standalone)
 local H,M,A,O=World()
 SlashCmdList.NEXUS('auto')
 check(Nexus.RecomputeStats().autoEnabled==true,'8: setup: ordinary Auto ON')
 H.Board(OFFER_MISS) -- an ordinary draw, no Orb offer
 local refused,why=M.Start()
 check(not refused and tostring(why):find('Resolve the current Echo action first',1,true),'8: Start waits for an open ordinary choice without a needed Echo: '..tostring(why))
 check(Nexus.RecomputeStats().autoEnabled==true,'8: a refused Start leaves ordinary Auto as it was')
 H.perks.currentChoice=nil;H.perks.pendingBanishIndex=nil;H.perks.pendingReroll=nil;H.Notify();A.Poll();Pass(H,2)
 H.actions={}
 check(M.Start(),'8: Start on a clear table')
 check(Nexus.RecomputeStats().autoEnabled==true,'8: Start leaves ordinary Auto ON')
 Pass(H)
 check(H.Count('orb-spend')==1,'8: setup: one Orb spent')
 check(A.OrdinaryBoardAllowed()~=true,'8: ordinary actions wait while the Orb request is in flight')
 -- the game answers with an ordinary draw instead of an Orb offer
 H.Board(OFFER_MISS);Pass(H,5)
 local during=nonOrb(H)
 check(during==standalone,'8: ordinary Auto handles the free draw as it does alone: '..during..' vs '..standalone)
 check(H.Count('orb-spend')==1 and O.redraws==0,'8: no Orb spent or redrawn over the free draw')
 H.perks.pendingBanishIndex=nil;H.perks.pendingReroll=nil;H.perks.currentChoice=nil;H.Notify();A.Poll();Pass(H)
 check(H.Count('orb-spend')==2 and M.Active(),'8: after the ordinary resolution the run continues: the next Orb opens a draw')
 M.Stop()
 check(Nexus.RecomputeStats().autoEnabled==true,'8: Stop leaves ordinary Auto as it was')
end

-- 9. Updated provider: an Orb offer is answered; a memory card is left to the player.
do
 local H,M,A,O=World({updated=true})
 Offer(H,O,OFFER_HIT)
 check(M.Start(),'9: Start');Pass(H)
 check(H.Count('take')==1,'9: the updated client answers the Orb offer')
 local H2,M2,A2,O2=World({updated=true})
 local memory=H2.Clone(OFFER_HIT);memory[1].isGuaranteed=true
 Offer(H2,O2,memory)
 check(M2.Start(),'9b: Start');Pass(H2,2)
 check(H2.Count('take')==0 and O2.redraws==0,'9b: a memory card on the Orb offer is left to the player')
 local H3,M3,A3,O3=World({updated=true})
 check(M3.Start(),'9c: Start');Pass(H3)
 check(H3.Count('orb-spend')==1,'9c: the updated client spends one Orb on a clear table')
end

-- 10. Old saves: a restored receipt is history; Start is a fresh run.
do
 local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
 local H,R,A,O=S.Fresh();H.OrbPlan()
 assert(R.Start(3));assert(R.Stop());H.Offer()
 O.offer=false;H.perks.currentChoice=nil
 R=S.Reload(H);S.Pass(H,R,A);S.Rechecks(H,R,2)
 local saved=H.Clone(NexusDB.chars[Nexus.Store.CurrentOwnerKey()].orbRefinement.pending)
 check(R.Status().pending,'10: setup: an unresolved restored receipt')
 check(R.BlocksOrdinary()==true,'10: before a new Start the old receipt keeps its loadout, lock and upload block')
 local M=Nexus.OrbAuto
 ProjectEbonhold.OrbService.CanRerollOffer=function() return O.charges>0 end
 ProjectEbonhold.OrbService.RerollOffer=function() H.actions[#H.actions+1]={'orb-redraw'};return true end
 local spends=H.Count('orb-spend')
 check(M.Start(),'10: Start is a fresh run')
 Pass(H)
 check(H.Count('orb-spend')==spends+1,'10: the fresh run spends one Orb')
 Offer(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1,'10: and answers its offer')
 local now=NexusDB.chars[Nexus.Store.CurrentOwnerKey()].orbRefinement.pending
 local function same(a,b)
  for k,v in pairs(a) do if type(v)~='table' and b[k]~=v then return false end end
  for k,v in pairs(b) do if type(v)~='table' and a[k]~=v then return false end end
  return true
 end
 check(now and same(saved,now),'10: the old receipt is kept as it was (nothing attributed to it)')
 Taken(H,O,410002,2);Pass(H)
 check(not M.Active(),'10: the fresh run completed')
 check(R.BlocksOrdinary()==false and A.OrdinaryBoardAllowed()==true,'10: after the new run the old receipt is history and blocks nothing')
 O.offer=true;H.Board(OFFER_MISS)
 check(R.BlocksOrdinary()==true,'10: an Orb offer open now still blocks')
end

-- 11. The Orb window: Start and Stop only; no maximum, Pause, Resume or Continue.
do
 local H,M,A,O=World()
 SlashCmdList.NEXUS('orbs');H.Advance(.2)
 local f=NexusOrbPanel
 check(f and f:IsShown(),'11: the Orb window opens')
 for _,k in ipairs({'limit','max','pause','resume','cont','review'}) do
  check(not (f[k] and f[k]:IsShown()),'11: no '..k..' control is shown')
 end
 check(f.start:IsShown() and f.start:IsEnabled() and f.stop:IsShown() and not f.stop:IsEnabled(),'11: Start enabled, Stop disabled')
 f.start:Click();Pass(H)
 check(M.Active() and H.Count('orb-spend')==1,'11: the Start button starts the run')
 check(not f.start:IsEnabled() and f.stop:IsEnabled(),'11: while ON, Stop is the control')
 f.stop:Click();Pass(H)
 check(not M.Active() and H.Count('orb-spend')==1,'11: the Stop button ends the run')
end

-- 12. The game refuses the Orb spend: the run ends; nothing is repeated.
do
 local H,M,A,O=World();O.mode='refuse'
 check(M.Start(),'12: Start');Pass(H,2)
 check(H.Count('orb-spend')==1 and not M.Active() and M.Status().state=='STOPPED','12: one refused spend ends the run; no retry')
end

-- 13. The last Orb is used during a run: the run ends normally, nothing more is spent.
do
 local H,M,A,O=World({plan={{spellId=410002,quality=2,stacks=3}}})
 O.charges=1
 check(M.Start(),'13: Start');Pass(H)
 check(H.Count('orb-spend')==1,'13: the one Orb is spent')
 O.charges=0;Offer(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1,'13: its offer is answered')
 Taken(H,O,410002,2);Pass(H)
 check(not M.Active() and M.Status().state=='DONE' and M.Status().reason:find('No Orbs remain',1,true) and H.Count('orb-spend')==1,
  '13: no Orb left: the run ends normally with nothing more spent: '..tostring(M.Status().reason))
end

-- 14. The always-visible surfaces show a running Start/Stop run and stop it.
do
 local H,M,A,O=World()
 check(M.Start(),'14: Start');Pass(H)
 local UI=Nexus.OrbPanel
 local mini=UI.ShowMini();H.Advance(.3)
 check(mini.state:GetText()~=Nexus.Localization.Text('orb.status.mini_no_run'),'14: the mini panel shows the run: '..tostring(mini.state:GetText()))
 check(not mini.pause:IsEnabled() and not mini.resume:IsEnabled() and mini.stop:IsEnabled(),'14: the mini offers Stop only')
 local L=Nexus.Localization.Text
 check(M.Status().inflight=='spend' and mini.state:GetText():find(L('orb.status.phase_wait_offer'),1,true)~=nil,'14: with a spend in flight the mini says it waits for the Orb offer: '..tostring(mini.state:GetText()))
 check(mini.pending:GetText()==L('orb.status.mini_result_not_settled'),'14: and its pending line is not "none": '..tostring(mini.pending:GetText()))
 mini.stop:Click()
 check(not M.Active(),'14: the mini Stop ends the run')
 local spends=H.Count('orb-spend')
 check(M.Start(),'14: Start again')
 Nexus.Panel.Show();H.Advance(.3)
 local strip=NexusPanel and NexusPanel._orbControls
 check(strip and strip:IsVisible(),'14: the main-panel strip shows the run')
 strip.refresh()
 check(strip.stop:IsShown() and strip.stop:IsEnabled() and not strip.pause:IsShown() and not strip.resume:IsShown(),'14: the strip offers Stop, no Pause or Resume')
 strip.stop:Click()
 check(not M.Active(),'14: the strip Stop ends the run')
 Offer(H,O,OFFER_HIT);Pass(H,1)
 check(H.Count('take')==0,'14: nothing is chosen after either Stop')
 local line=UI.PanelRunLine()
 check(line==nil,'14: after Stop the panel run line is gone')
end

-- 15. A needed Echo on a free draw at Start: taken through the ordinary Take,
-- no Orb spent, ordinary Auto left OFF and its settings unchanged.
local function settingsKey()
 local st=Nexus.Store.Settings();local keys={}
 for k,v in pairs(st) do if type(v)~='table' then keys[#keys+1]=k..'='..tostring(v) end end
 table.sort(keys);return table.concat(keys,';')
end
do
 local H,M,A,O=World()
 check(Nexus.RecomputeStats().autoEnabled==false,'15: setup: ordinary Auto OFF')
 local before=settingsKey()
 H.Board(OFFER_HIT) -- free draw, no Orb offer
 local ok,why=M.CanStart()
 check(ok==true,'15: Start is available on a free draw with a needed Echo: '..tostring(why))
 check(M.Start(),'15: Start');Pass(H)
 check(H.Count('take')==1 and H.actions[#H.actions][2]==410002,'15: the needed Echo is taken from the free draw')
 check(H.Count('orb-spend')==0 and O.redraws==0,'15: no Orb spent')
 check(Nexus.RecomputeStats().autoEnabled==false and settingsKey()==before,'15: ordinary Auto stays OFF and no setting changed')
 Pass(H,3)
 check(H.Count('take')==1,'15: the pick is not repeated while it is in flight')
 Taken(H,O,410002,2);Pass(H)
 check(not M.Active() and M.Status().state=='DONE','15: the Wishlist is complete: the run ends normally')
end

-- 16. During a run the game answers a spend with a free draw holding a needed
-- Echo: it is taken, no second Orb meanwhile, and the run continues after it.
do
 local H,M,A,O=World({plan={{spellId=410002,quality=2,stacks=1},{spellId=410004,quality=3,stacks=1}}})
 check(M.Start(),'16: Start');Pass(H)
 check(H.Count('orb-spend')==1,'16: setup: one Orb spent')
 H.Board(OFFER_HIT);Pass(H)
 check(H.Count('take')==1 and H.actions[#H.actions][1]=='take','16: the needed Echo on the free draw is taken')
 Pass(H,3)
 check(H.Count('take')==1 and H.Count('orb-spend')==1 and O.redraws==0,'16: no duplicate pick and no Orb while it is in flight')
 Taken(H,O,H.actions[#H.actions][2],H.actions[#H.actions][2]==410004 and 3 or 2);Pass(H)
 check(M.Active() and H.Count('orb-spend')==2,'16: after the pick the run continues with the next Orb')
 M.Stop()
end

-- 17. A free draw without a needed Echo, ordinary Auto OFF: left to the player.
do
 local H,M,A,O=World()
 check(M.Start(),'17: Start');Pass(H)
 H.Board(OFFER_MISS);Pass(H,3)
 check(H.Count('orb-spend')==1 and H.Count('take')==0 and H.Count('banish')==0 and H.Count('reroll')==0 and O.redraws==0,
  '17: nothing is sent over the free draw: no Orb, no pick, no dismiss or reroll')
 check(M.Status().state=='WAITING' and M.Status().reason:find('leaves it to you',1,true),'17: the run waits and says so: '..tostring(M.Status().reason))
 check(A.OrdinaryBoardAllowed()==true,"17: the player's own ordinary actions on the free draw are admitted")
 H.perks.currentChoice=nil;H.Notify();A.Poll();Pass(H)
 check(H.Count('orb-spend')==2,'17: once the player resolved it, the run continues')
 M.Stop()
end

-- 18. A free draw with a needed Echo while ordinary Auto is ON too: one pick only.
do
 local H,M,A,O=World()
 SlashCmdList.NEXUS('auto')
 check(M.Start(),'18: Start');Pass(H)
 H.Board(OFFER_HIT);Pass(H,5)
 check(H.Count('take')==1 and H.Count('orb-spend')==1,'18: the needed Echo is taken once, no Orb meanwhile')
 Taken(H,O,410002,2);Pass(H)
 check(not M.Active() and Nexus.RecomputeStats().autoEnabled==true,'18: the run ends complete; ordinary Auto stays as it was')
end

-- 19. Old saves: a restored receipt, then Start on a free draw with a needed Echo.
do
 local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
 local H,R,A,O=S.Fresh();H.OrbPlan()
 assert(R.Start(3));assert(R.Stop());H.Offer()
 O.offer=false;H.perks.currentChoice=nil
 R=S.Reload(H);S.Pass(H,R,A);S.Rechecks(H,R,2)
 local saved=H.Clone(NexusDB.chars[Nexus.Store.CurrentOwnerKey()].orbRefinement.pending)
 check(R.Status().pending,'19: setup: an unresolved restored receipt')
 local M=Nexus.OrbAuto
 local spends=H.Count('orb-spend')
 local takes=H.Count('take')
 H.Board(OFFER_HIT)
 local ok,why=M.Start()
 check(ok,'19: Start is a fresh run: '..tostring(why));Pass(H)
 check(H.Count('take')==takes+1 and H.Count('orb-spend')==spends,'19: the needed Echo is taken from the free draw, no Orb spent')
 local now=NexusDB.chars[Nexus.Store.CurrentOwnerKey()].orbRefinement.pending
 local same=now~=nil
 for k,v in pairs(saved) do if type(v)~='table' and (not now or now[k]~=v) then same=false end end
 check(same,'19: the old receipt is kept as it was (the pick is not attributed to it)')
 M.Stop()
end

-- 20. Stop around a normal pick: nothing more after Stop.
do
 local H,M,A,O=World({plan={{spellId=410002,quality=2,stacks=1},{spellId=410004,quality=3,stacks=1}}})
 H.Board(OFFER_HIT)
 check(M.Start(),'20: Start');Pass(H)
 check(H.Count('take')==1,'20: setup: the pick is in flight')
 check(M.Stop() and not M.Active(),'20: Stop with the pick in flight')
 Taken(H,O,H.actions[#H.actions][2],H.actions[#H.actions][2]==410004 and 3 or 2);Pass(H,3)
 check(H.Count('orb-spend')==0 and H.Count('take')==1,"20: after Stop and the pick's result nothing more is sent")
 H.Board({{spellId=410004,quality=3},{spellId=410005,quality=0},{spellId=410006,quality=3}});Pass(H,3)
 check(H.Count('take')==1,'20: a later free draw with a needed Echo is not taken after Stop (ordinary Auto OFF)')
 -- Stop before the pick: a run waiting on a spend, Stop, then the free draw
 local H2,M2,A2,O2=World()
 check(M2.Start(),'20b: Start');Pass(H2)
 M2.Stop();H2.Board(OFFER_HIT);Pass(H2,3)
 check(H2.Count('take')==0 and H2.Count('orb-spend')==1,'20b: Stop before the free draw: nothing is taken')
end

-- 21. Normal standalone flow (no run): ordinary Auto takes the needed Echo as before.
do
 local H,M,A,O=World()
 SlashCmdList.NEXUS('auto')
 H.Board(OFFER_HIT);Pass(H,5)
 check(H.Count('take')==1 and H.Count('orb-spend')==0,'21: ordinary Auto alone takes the needed Echo')
 check(not M.Active(),'21: no run was started')
end

-- 22. The pick is granted while the game still shows the same published
-- choice (the grant is seen before the pick's result clears the flag and the
-- choice together, as the client does): that choice is not taken again, even
-- when another copy is needed, and no Orb is spent while it is shown.
do
 local H,M,A,O=World({plan={{spellId=410002,quality=2,stacks=2}}})
 H.Board(OFFER_HIT)
 check(M.Start(),'22: Start');Pass(H)
 check(H.Count('take')==1,'22: setup: one pick')
 local out=H.Clone(H.granted);out['Desired A']=out['Desired A'] or {};table.insert(out['Desired A'],{spellId=410002,quality=2})
 H.granted=out;H.Notify();A.Poll();Pass(H,3)
 check(H.Count('take')==1,'22: the same published choice is not taken a second time')
 check(H.Count('orb-spend')==0,'22: no Orb spent while that choice is shown')
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;H.Notify();A.Poll();Pass(H)
 check(H.Count('orb-spend')==1 and M.Active(),'22: once the result clears it the run continues')
 M.Stop()
end

-- 23. Updated provider: a free draw with a needed Echo is taken the same way.
do
 local H,M,A,O=World({updated=true})
 H.Board(OFFER_HIT)
 check(M.Start(),'23: Start');Pass(H,1) -- the adapter's own pick-settle window first
 check(H.Count('take')==1 and H.Count('orb-spend')==0,'23: the updated client takes the needed Echo from the free draw, no Orb')
 M.Stop()
end

-- 24. A pick the game never answers (its pending-pick flag stays set): the
-- run waits and never sends it again; a pick the ordinary adapter voids (a
-- run boundary) on the same published choice ends the run.
do
 local H,M,A,O=World()
 H.Board(OFFER_HIT)
 check(M.Start(),'24: Start');Pass(H)
 check(H.Count('take')==1,'24: setup: one pick')
 Pass(H,30)
 check(H.Count('take')==1 and H.Count('orb-spend')==0 and M.Active(),'24: no answer: nothing is repeated, no Orb, the run waits')
 check(M.Status().reason=='Waiting for the chosen Echo.','24: and says what it waits for: '..tostring(M.Status().reason))
 A.RunBoundaryReset();H.perks.pendingSelectSpellId=nil;H.Notify();A.Poll();Pass(H,2)
 check(not M.Active() and M.Status().state=='STOPPED' and H.Count('take')==1,'24: the voided pick on the same choice ends the run: '..tostring(M.Status().reason))
end

-- 25. Field stall (2026-11-19): the game refuses a pick. The client clears its
-- pending-pick flag and keeps the same published choice (and an Orb offer)
-- standing. The run ends with the existing refusal reason instead of waiting
-- on it indefinitely; the pick is never sent again, no Orb is spent, and a new
-- Start is a fresh run that decides on the current choice once.
for _,kind in ipairs({'orb','free'}) do
 local H,M,A,O=World()
 if kind=='orb' then O.offer=true end
 H.Board(OFFER_HIT)
 check(M.Start(),'25 '..kind..': Start');Pass(H)
 check(H.Count('take')==1,'25 '..kind..': setup: one pick')
 local choice=H.perks.currentChoice
 H.perks.pendingSelectSpellId=nil;H.Notify();A.Poll() -- the refused result
 Pass(H,2)
 check(rawequal(H.perks.currentChoice,choice),'25 '..kind..': setup: the same choice is still shown')
 check(not M.Active() and M.Status().state=='STOPPED' and M.Status().reason:find('did not take the chosen Echo',1,true),
  '25 '..kind..': the refused pick ends the run with its reason: '..tostring(M.Status().reason))
 Pass(H,30)
 check(H.Count('take')==1 and H.Count('orb-spend')==0 and O.redraws==0,'25 '..kind..': nothing is sent again and no Orb is spent')
 check(M.Stop() and not M.Active() and H.Count('take')==1,'25 '..kind..': Stop after the end sends nothing')
 if kind=='orb' then
  -- A new Start is the player's own decision: one pick on the current offer.
  check(M.Start(),'25 orb: a new Start');Pass(H,3)
  check(H.Count('take')==2 and H.Count('orb-spend')==0,'25 orb: the new run picks once, no Orb')
  M.Stop()
 end
end

-- 26. Stop, then an immediate Start, while a request this session sent is
-- still unanswered: Stop ends every further action at once, but the request
-- is not forgotten. The new run rejoins it: no second Orb, choice or pick is
-- sent before its existing answer, and the answer is then handled as usual.
do
 -- a spend in flight (the reproduced second spend)
 local H,M,A,O=World({plan={{spellId=410002,quality=2,stacks=1},{spellId=410004,quality=3,stacks=1}}})
 check(M.Start(),'26a: Start');Pass(H)
 check(H.Count('orb-spend')==1 and M.Status().inflight=='spend','26a: setup: one spend awaiting its offer')
 check(M.Stop() and not M.Active(),'26a: Stop ends the run')
 Pass(H,2)
 check(H.Count('orb-spend')==1,'26a: nothing is sent while stopped')
 local ok,why=M.CanStart()
 check(ok==true,'26a: Start is available to rejoin the request: '..tostring(why))
 check(M.Start(),'26a: an immediate Start');Pass(H,3)
 check(H.Count('orb-spend')==1 and M.Status().inflight=='spend','26a: the new run rejoins the spend: no second Orb before its answer')
 Offer(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1 and H.Count('orb-spend')==1,'26a: the awaited offer is answered once')
 Taken(H,O,410002,2);Pass(H)
 check(M.Active() and H.Count('orb-spend')==2,'26a: after that answer the run continues normally')
 M.Stop()
end
do
 -- an Orb choice in flight: Stop, Start, then the game refuses it
 local H,M,A,O=World()
 Offer(H,O,OFFER_HIT)
 check(M.Start(),'26b: Start');Pass(H)
 check(H.Count('take')==1,'26b: setup: one choice in flight')
 M.Stop();check(M.Start(),'26b: Stop, then an immediate Start');Pass(H,3)
 check(H.Count('take')==1 and M.Status().inflight=='select','26b: the choice is not sent again; the new run waits on it')
 H.perks.pendingSelectSpellId=nil;H.Notify();A.Poll();Pass(H)
 check(not M.Active() and M.Status().reason:find('did not take the chosen Echo',1,true) and H.Count('take')==1,
  '26b: its refused result ends the run; nothing is repeated: '..tostring(M.Status().reason))
end
do
 -- a free-draw pick in flight: Stop, Start, then the pick is granted
 local H,M,A,O=World({plan={{spellId=410002,quality=2,stacks=1},{spellId=410004,quality=3,stacks=1}}})
 H.Board(OFFER_HIT)
 check(M.Start(),'26c: Start');Pass(H)
 check(H.Count('take')==1,'26c: setup: one free-draw pick in flight')
 M.Stop();check(M.Start(),'26c: Stop, then an immediate Start');Pass(H,3)
 check(H.Count('take')==1 and H.Count('orb-spend')==0,'26c: the pick is not sent again and no Orb is spent before its answer')
 Taken(H,O,H.actions[#H.actions][2],H.actions[#H.actions][2]==410004 and 3 or 2);Pass(H)
 check(M.Active() and H.Count('orb-spend')==1,'26c: after its answer the run continues normally')
 M.Stop()
end
do
 -- negative control: the answer arrives while stopped; the next Start is fresh
 local H,M,A,O=World()
 check(M.Start(),'26d: Start');Pass(H)
 M.Stop()
 Offer(H,O,OFFER_MISS);Pass(H,2)
 check(O.redraws==0 and H.Count('take')==0,'26d: nothing acts on the answer while stopped')
 check(M.Start(),'26d: Start after the answer');Pass(H)
 check(O.redraws==1 and H.Count('orb-spend')==1,'26d: the answered request is not waited on: the new run acts on the current offer')
 M.Stop()
end

do
 -- 26e: the choice is refused while stopped: the next Start is a fresh run
 -- (the player's own decision) and picks once on the current offer
 local H,M,A,O=World()
 Offer(H,O,OFFER_HIT)
 check(M.Start(),'26e: Start');Pass(H)
 check(H.Count('take')==1,'26e: setup: one choice in flight')
 M.Stop()
 H.perks.pendingSelectSpellId=nil;H.Notify();A.Poll();Pass(H,2) -- refused while stopped
 check(H.Count('take')==1,'26e: nothing is sent while stopped')
 check(M.Start(),'26e: Start after the refusal');Pass(H,2)
 check(M.Active() and H.Count('take')==2 and H.Count('orb-spend')==0,'26e: the new run is fresh and picks once on the current offer')
 M.Stop()
end

do
 -- 26f (review finding on a50cd936): the spend's Orb offer arrives while the
 -- run is stopped and the player picks on it in the game; the game clears the
 -- choice and publishes no next one. The answer was observed while stopped,
 -- so the next Start does not rejoin it: it is a fresh run on the current state.
 local H,M,A,O=World({plan={{spellId=410002,quality=2,stacks=1},{spellId=410004,quality=3,stacks=1}}})
 check(M.Start(),'26f: Start');Pass(H)
 check(H.Count('orb-spend')==1,'26f: setup: one spend awaiting its offer')
 M.Stop()
 Offer(H,O,OFFER_HIT);Pass(H,1)          -- the offer is shown while stopped
 check(H.Count('take')==0,'26f: nothing acts on it while stopped')
 H.service.SelectPerk(410002);Taken(H,O,410002,2);Pass(H,1) -- the player's own pick; no next choice
 check(H.perks.currentChoice==nil,'26f: setup: no choice is published after the pick')
 check(M.Start(),'26f: Start after the answer was resolved');Pass(H)
 check(H.Count('orb-spend')==2 and M.Status().inflight=='spend','26f: a fresh run: the next Orb opens a draw')
 M.Stop()
end
do
 -- 26g (unobservable): the answer is published and resolved within one
 -- observation while stopped. Nexus cannot see it from the client's state, so
 -- the rejoined run waits on it, sends nothing again, and says it did not see
 -- an answer (not that the game did not answer).
 local H,M,A,O=World()
 check(M.Start(),'26g: Start');Pass(H)
 M.Stop()
 O.offer=true;H.Board(OFFER_HIT);O.offer=false;H.perks.currentChoice=nil -- no pass in between
 check(M.Start(),'26g: Start');Pass(H,25)
 check(H.Count('orb-spend')==1 and M.Status().inflight=='spend','26g: the rejoined spend is not repeated')
 check(M.Status().reason:find('Nexus did not see an answer',1,true)~=nil,'26g: the wait states what Nexus could not observe: '..tostring(M.Status().reason))
 M.Stop()
end

do
 -- 26h: the refused result arrives in the same moment as the Start (before
 -- the stopped frame's next observation): Start itself sees the answer, so
 -- the run is fresh and picks once on the current offer
 local H,M,A,O=World()
 Offer(H,O,OFFER_HIT)
 check(M.Start(),'26h: Start');Pass(H)
 M.Stop()
 H.perks.pendingSelectSpellId=nil -- refused, and Start at once
 check(M.Start(),'26h: Start in the same moment');Pass(H,2)
 check(M.Active() and H.Count('take')==2,'26h: Start saw the answer: a fresh run picks once')
 M.Stop()
end

-- 27. Field shape (9106 report, sanitized; 2026-11-19): a receipt restored
-- after a reload whose spend is unconfirmed, whose Orb offer was saved, with
-- no recorded choice, and whose loadout changed since (slot 1 -> 2 here).
-- Two independent paths, each with its negative controls:
--  a) LEGACY, no run: ordinary decisions on a visible three-card board are no
--     longer held by that saved history while the live Orb service shows no
--     offer; an open Orb offer or an unknown Orb state still hold them.
--  b) MODERN, a run's own request in flight with the same receipt present:
--     ordinary actions wait, and the wait names the run, not the receipt.
local function FieldReceipt()
 local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
 local H,R,A,O=S.Fresh()
 local slots=S.Loadouts(H,A)
 assert(R.Start(3));assert(R.Stop());H.Offer()
 R=S.Reload(H,function(row,state) row.spendConfirmed=false;state.spendConfirmed=false end)
 O.offer=false;H.perks.currentChoice=nil
 H.perks.serverActiveSlot=2;S.Pass(H,R,A);S.Rechecks(H,R,2)
 local p=Nexus.Store.State().orbRefinement.pending
 assert(p and p.restored and p.spendConfirmed~=true and p.offerKey~=nil and p.selectedKey==nil,'setup: the field receipt shape')
 ProjectEbonhold.OrbService.CanRerollOffer=function() return O.charges>0 end
 ProjectEbonhold.OrbService.RerollOffer=function() H.actions[#H.actions+1]={'orb-redraw'};return true end
 return H,R,A,O,S
end
local NEEDED2={{spellId=410005,quality=0},{spellId=410004,quality=3},{spellId=410006,quality=3}}
do
 local H,R,A,O=FieldReceipt()
 local saved=H.Clone(Nexus.Store.State().orbRefinement.pending)
 check(R.Status().pending~=nil,'27a: setup: the receipt is unresolved')
 SlashCmdList.NEXUS('auto')
 check(Nexus.RecomputeStats().autoEnabled==true,'27a: ordinary Auto can be turned ON')
 local takes=H.Count('take')
 H.Board(NEEDED2);for _=1,20 do H.Notify();A.Poll();H.Advance(.25) end
 check(H.Count('take')==takes+1 and H.actions[#H.actions][2]==410004,'27a: ordinary Auto takes the needed Echo on the visible board')
 check(H.Count('orb-spend')==1,'27a: no Orb is spent')
 local now=Nexus.Store.State().orbRefinement.pending
 local same=now~=nil
 for k,v in pairs(saved) do if type(v)~='table' and now[k]~=v then same=false end end
 check(same,'27a: the saved receipt is kept unchanged')
 check(R.BlocksOrdinary()==true,'27a: its loadout, lock and upload block is unchanged')
end
do
 -- negative control: an Orb offer is open now
 local H,R,A,O=FieldReceipt()
 O.offer=true;H.Board(NEEDED2);H.Notify();A.Poll()
 local ok,why=A.OrdinaryBoardAllowed()
 check(ok~=true,'27a control: an open Orb offer still holds ordinary actions: '..tostring(why))
end
do
 -- negative control: the Orb state is unknown now
 local H,R,A,O=FieldReceipt()
 O.known=false;H.Board(NEEDED2);H.Notify();A.Poll();H.Advance(.5)
 local ok,why=A.OrdinaryBoardAllowed()
 check(ok~=true,'27a control: an unknown Orb state still holds ordinary actions: '..tostring(why))
end
do
 local H,R,A,O=FieldReceipt()
 local M=Nexus.OrbAuto
 check(M.Start(),'27b: Start with the field receipt present');H.Advance(.5)
 check(M.Status().inflight=='spend','27b: setup: the run\'s spend awaits its offer')
 local ok,why=A.OrdinaryBoardAllowed()
 check(ok~=true and tostring(why):find('Orb refinement owns the current action',1,true)~=nil and not tostring(why):find('cannot be confirmed',1,true),
  '27b: the ordinary wait names the run\'s own request, not the receipt: '..tostring(why))
 Offer(H,O,{{spellId=410004,quality=3},{spellId=410005,quality=0},{spellId=410006,quality=3}});H.Advance(.5)
 check(H.Count('take')>=1 and H.actions[#H.actions][2]==410004,'27b: the run answers its Orb offer for the current loadout')
 M.Stop()
 -- negative control: no run, no Orb request: that wait is gone
 O.offer=false;H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;H.Notify();A.Poll()
 local ok2,why2=A.OrdinaryBoardAllowed()
 check(ok2==true,'27b control: after Stop with no Orb request in flight, ordinary actions are not held: '..tostring(why2))
end

-- 28. 9107 field report: the run "waited for redraw" with three cards shown.
-- Nexus only observes that no new choice was published after its Orb redraw;
-- the wait says that, not that the game did not answer. The overdue redraw
-- is sent once more (the approved single retry, case 32) and nothing after
-- that; no Orb is spent, and a later new choice (here the answer of the chooser's
-- own "Use Orbs" button, the same native redraw) is handled once as usual.
do
 local H,M,A,O=World()
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'28: Start');Pass(H)
 check(O.redraws==1 and M.Status().inflight=='redraw','28: setup: one redraw awaiting its new offer')
 local shown=H.perks.currentChoice
 Pass(H,25)
 check(O.redraws==2,'28: setup: the overdue redraw was sent once more (its one retry)')
 Pass(H,25)
 check(rawequal(H.perks.currentChoice,shown),'28: setup: the same choice is still shown')
 local why=M.Status().reason
 check(why:find('Nexus did not see an answer',1,true)~=nil and not why:find('has not answered',1,true),
  '28: the wait states what Nexus observed, not server silence: '..why)
 check(O.redraws==2 and H.Count('orb-spend')==0 and H.Count('take')==0,'28: nothing is repeated after the one retry and no Orb is spent while it waits')
 Offer(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1 and O.redraws==2,'28: a later new offer is answered once')
 M.Stop()
end
do
 -- negative control: a redraw answered with a new choice never shows that wait
 local H,M,A,O=World()
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'28 control: Start');Pass(H)
 Offer(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1 and M.Status().inflight=='select','28 control: the answered redraw is followed by one pick')
 Taken(H,O,410002,2);Pass(H,25)
 check(M.Status().state=='DONE' and not M.Status().reason:find('did not see an answer',1,true),'28 control: an answered redraw and pick are never reported as unseen: '..M.Status().reason)
end

-- 29. Redraw-wait diagnostic (9107 field report: "waited for redraw").
-- RerollOffer's return contract is not in the admitted client reference, so
-- the run does not interpret it. The run's request view, and its support
-- report line, record what the client showed at the send and at the last
-- read, so a naturally occurring stall can be told apart later: nothing
-- published (same table, same cards), a change made in place (same table,
-- other cards), the Orb offer flag or charges changing, and the raw return.
-- Building them sends nothing and changes no behavior. Client state only.
local function report() return table.concat(assert(Nexus.SupportReport.Prepare({})).chunks,'') end
do
 -- a) the redraw call returns false and nothing is published
 local H,M,A,O=World()
 ProjectEbonhold.OrbService.RerollOffer=function() O.redraws=O.redraws+1;H.actions[#H.actions+1]={'orb-redraw'};return false end
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'29a: Start');Pass(H,25)
 check(O.redraws==2,'29a: setup: like any overdue redraw, it was sent once more (its one retry)')
 Pass(H,25)
 local sent=#H.actions
 local v=M.RequestView()
 check(v.kind=='redraw' and v.redrawReturn=='false' and v.sameChoiceTable==true and v.sameCards==true
  and v.offerAtSend==true and v.offerNow==true and v.age>=20,'29a: the view shows the unchanged table and cards and the raw return')
 check(O.redraws==2 and M.Status().inflight=='redraw','29a: false is not interpreted: after its one retry the redraw is not repeated and stays the request')
 local r=report()
 check(r:find('Orb Start/Stop request: on=yes state=WAITING kind=redraw',1,true)~=nil and r:find('redrawReturn=false sameChoiceTable=yes',1,true)~=nil
  and r:find('sameCards=yes offerAtSend=yes offerNow=yes',1,true)~=nil,'29a: the support report carries the line: '..(r:match('Orb Start/Stop request:[^\n]*') or 'missing'))
 check(#H.actions==sent and O.redraws==2,'29a: the view and the report send nothing')
 M.Stop()
end
do
 -- b) the redraw returns true and the shown cards change in place
 local H,M,A,O=World()
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'29b: Start');Pass(H)
 local c=H.perks.currentChoice;c[1].spellId=410006;c[2].spellId=410004
 H.Notify();A.Poll();Pass(H,2)
 local v=M.RequestView()
 check(v.kind=='redraw' and v.redrawReturn=='true' and v.sameChoiceTable==true and v.sameCards==false,
  '29b: the view tells a change in place (same table, other cards) apart')
 M.Stop()
end
do
 -- c) negative control: a redraw answered with a new table is no longer the request
 local H,M,A,O=World()
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'29c: Start');Pass(H)
 Offer(H,O,OFFER_HIT);Pass(H)
 local v=M.RequestView()
 check(v.kind=='select' and v.sameChoiceTable==true,'29c: after the answer the request is the new pick, not the redraw')
 M.Stop()
 -- and with no run and nothing carried, the line says so
 local H2,M2=World()
 check(M2.RequestView().kind=='none' and report():find('Orb Start/Stop request: on=no state=OFF kind=none',1,true)~=nil,'29c: no run: kind=none')
end

-- 30. Redraw outcomes against the admitted provider lifecycle (user-approved
-- behavior, 2026-11-19). In the client reference, Perks.MarkOrbReroll sets
-- Perks.pendingOrbReroll (its caller, the Orb service, is not in the
-- reference). Only the choice message clears it, and the same handler always
-- publishes a new choice table (or none). No refusal message, handler or flag
-- exists for an Orb redraw: "a dropped orb request only leaves the next reveal
-- auto-shown". So:
--  * a genuinely new acknowledged offer (a choice message) is used, once,
--    whether its cards are new or repeated;
--  * a request with no choice message waits: a set flag, a cleared flag, an
--    unchanged board, an idle state or a false or nil return is not a
--    confirmed refusal and is not interpreted. Once the redraw is overdue it
--    is sent once more (the single retry later approved without a refusal
--    signal, case 32), whatever the flag or the return, and never again;
--  * Stop then Start uses a new offer that arrived while stopped, with no
--    extra redraw.
local function Mark(H,O) H.perks.pendingOrbReroll=true end
-- The client's choice message: it clears the redraw flags, then publishes a NEW table.
local function ChoiceMessage(H,O,cards) H.perks.pendingOrbReroll=nil;H.perks.pendingReroll=nil;O.offer=true;H.Board(cards);H.Notify();H.A.Poll() end
local function Redrawing(ret)
 local H,M,A,O=World()
 ProjectEbonhold.OrbService.RerollOffer=function() O.redraws=O.redraws+1;H.actions[#H.actions+1]={'orb-redraw'};Mark(H,O);return ret end
 Offer(H,O,OFFER_MISS)
 return H,M,A,O
end
-- a) a genuinely new acknowledged offer is used, once; new and repeated cards.
for _,cards in ipairs({{'new',OFFER_HIT},{'repeated',OFFER_MISS}}) do
 local H,M,A,O=Redrawing(true)
 check(M.Start(),'30a '..cards[1]..': Start');Pass(H)
 check(O.redraws==1 and H.perks.pendingOrbReroll==true,'30a '..cards[1]..': setup: one redraw, the client flag is set')
 ChoiceMessage(H,O,cards[2]);Pass(H)
 if cards[1]=='new' then
  check(H.Count('take')==1 and O.redraws==1,'30a new: the acknowledged new offer is used once: the needed Echo is chosen')
 else
  check(O.redraws==2 and H.Count('take')==0,'30a repeated: the acknowledged offer with the same cards is a new offer: one redraw for it, none twice')
  Pass(H,3)
  check(O.redraws==2,'30a repeated: no second redraw while the second one awaits its offer')
 end
 M.Stop()
end
-- b) no choice message: refusal and an active request are indistinguishable;
-- the run waits, sends the overdue redraw once more (its one retry) and
-- nothing after that, whatever the flag or the return.
for _,c in ipairs({{'flag set, true',true,false},{'flag set, false',false,false},{'flag set, nil',nil,false},{'flag cleared, same table',true,true}}) do
 local H,M,A,O=Redrawing(c[2])
 check(M.Start(),'30b '..c[1]..': Start');Pass(H)
 if c[3] then H.perks.pendingOrbReroll=nil;H.Notify();A.Poll() end
 Pass(H,25)
 check(O.redraws==2,'30b '..c[1]..': setup: the overdue redraw was sent once more (its one retry)')
 Pass(H,25)
 check(O.redraws==2 and H.Count('take')==0 and H.Count('orb-spend')==0 and M.Status().inflight=='redraw',
  '30b '..c[1]..': not a confirmed refusal: no further retry, no spend, the redraw stays the request')
 check(M.Status().reason:find('Nexus did not see an answer',1,true)~=nil,'30b '..c[1]..': and the wait says what Nexus saw')
 -- a later choice message is still used, once
 ChoiceMessage(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1 and O.redraws==2,'30b '..c[1]..': a later acknowledged offer is used once')
 M.Stop()
end
-- c) an unchanged board and an idle Orb state are not a refusal either.
do
 local H,M,A,O=Redrawing(true)
 check(M.Start(),'30c: Start');Pass(H)
 O.offer=false;H.Notify();A.Poll();Pass(H,25)
 check(O.redraws==1 and H.Count('orb-spend')==0,'30c: the Orb offer flag clearing with the same cards shown is not a refusal: nothing is sent')
 M.Stop()
end
-- d) Stop during the redraw wait; the acknowledged new offer arrives while
-- stopped; Start uses it once, with no extra redraw or spend.
do
 local H,M,A,O=Redrawing(true)
 check(M.Start(),'30d: Start');Pass(H)
 M.Stop()
 ChoiceMessage(H,O,OFFER_HIT);Pass(H,2)
 check(H.Count('take')==0,'30d: nothing acts while stopped')
 check(M.Start(),'30d: Start');Pass(H)
 check(H.Count('take')==1 and O.redraws==1 and H.Count('orb-spend')==0,'30d: the open acknowledged offer is used once; no extra redraw or spend')
 M.Stop()
end

-- 31. Redraw stall correction (user direction 2026-11-19: "Why don't you just
-- pick the next card then?"). While a redraw has no new choice table seen, the
-- visible Orb offer is read every pass and acted on through the real adapter
-- Select (its own checks: the Orb offer flag, three cards, selectable card,
-- unchanged board key, client admission, no pick pending):
--  a) the cards changed in place to a needed Echo: it is picked, once, with no
--     further redraw and no spend;
--  b) the cards changed in place without a needed Echo: not a redraw answer
--     (the client answers a redraw only with a new choice table), so the run
--     keeps waiting: no second paid redraw, no spend;
--  c) the same cards, but the Wishlist now needs one of them: it is picked;
--  d) the same cards and nothing needed: the run waits, no redraw, no spend,
--     until the redraw is overdue (then its one retry, case 32);
--  e) a pick already pending in the game (the player's own): nothing is sent;
--  f) the Orb offer flag is gone: nothing is picked from the leftover cards;
--  g) the game refuses the pick: the run ends with its reason, nothing repeats.
local function Redrawing()
 local H,M,A,O=World()
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'31: Start');Pass(H)
 check(O.redraws==1 and M.Status().inflight=='redraw','31: setup: a redraw with no answer yet')
 return H,M,A,O
end
local function InPlace(H,cards)
 local c=H.perks.currentChoice
 for i,card in ipairs(cards) do c[i].spellId=card.spellId;c[i].quality=card.quality end
 H.Notify();H.A.Poll()
end
do
 local H,M,A,O=Redrawing()
 local shown=H.perks.currentChoice
 InPlace(H,OFFER_HIT);Pass(H)
 check(rawequal(H.perks.currentChoice,shown),'31a: setup: the same choice table, its cards changed in place')
 check(H.Count('take')==1 and H.actions[#H.actions][2]==410002,'31a: the needed Echo now shown is picked')
 check(O.redraws==1 and H.Count('orb-spend')==0,'31a: no further redraw and no spend')
 Pass(H,3)
 check(H.Count('take')==1 and M.Status().inflight=='select','31a: the pick is not repeated while it awaits its result')
 Taken(H,O,410002,2);Pass(H)
 check(M.Status().state=='DONE','31a: its result completes the Wishlist')
end
do
 local H,M,A,O=Redrawing()
 InPlace(H,{{spellId=410006,quality=3},{spellId=410004,quality=3},{spellId=410005,quality=0}});Pass(H,25)
 check(O.redraws==1 and H.Count('take')==0 and H.Count('orb-spend')==0 and M.Status().inflight=='redraw',
  '31b: cards changed in place without a needed Echo: the redraw stays pending; no second redraw, no spend')
 -- the real answer, a new choice table, is still handled once
 Offer(H,O,OFFER_HIT);Pass(H)
 check(H.Count('take')==1 and O.redraws==1,'31b: the later new offer is answered once')
 M.Stop()
end
do
 local H,M,A,O=Redrawing()
 H.OrbPlan({{spellId=410006,quality=3,stacks=1}});Pass(H)
 check(H.Count('take')==1 and H.actions[#H.actions][2]==410006 and O.redraws==1 and H.Count('orb-spend')==0,
  '31c: the same cards now hold a needed Echo: it is picked, with no redraw or spend')
 M.Stop()
end
do
 local H,M,A,O=Redrawing()
 Pass(H,15)
 check(O.redraws==1 and H.Count('take')==0 and H.Count('orb-spend')==0 and M.Status().inflight=='redraw',
  '31d: the same cards and nothing needed: the run waits; no redraw, no pick, no spend')
 Pass(H,15)
 check(O.redraws==2 and H.Count('take')==0 and H.Count('orb-spend')==0,'31d: once overdue, only its one retry')
 M.Stop()
end
do
 local H,M,A,O=Redrawing()
 H.perks.pendingSelectSpellId=410004 -- the player's own pick, pending in the game
 InPlace(H,OFFER_HIT);Pass(H,3)
 check(H.Count('take')==0 and O.redraws==1,'31e: a pick pending in the game: nothing is sent')
 M.Stop()
end
do
 local H,M,A,O=Redrawing()
 O.offer=false;InPlace(H,OFFER_HIT);Pass(H,3)
 check(H.Count('take')==0 and O.redraws==1 and H.Count('orb-spend')==0,'31f: no Orb offer flag: nothing is picked from the leftover cards')
 M.Stop()
end
do
 local H,M,A,O=Redrawing()
 InPlace(H,OFFER_HIT);Pass(H)
 check(H.Count('take')==1,'31g: setup: the pick was sent')
 H.perks.pendingSelectSpellId=nil;H.Notify();A.Poll();Pass(H,3) -- refused: same table, flag cleared, offer stands
 check(not M.Active() and M.Status().reason:find('did not take the chosen Echo',1,true) and H.Count('take')==1 and O.redraws==1,
  '31g: the refused pick ends the run with its reason; nothing is repeated')
end

do
 -- 31h: the updated client, through its real Orb-choice admission
 -- (RunAdmission "choice": Orb offer flag, three cards, no specialization
 -- draw, no memory card). A changed-in-place needed card is picked; with a
 -- memory card shown the same offer is left to the player.
 local H,M,A,O=World({updated=true})
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'31h: Start');Pass(H)
 check(O.redraws==1,'31h: setup: one redraw')
 local c=H.perks.currentChoice;c[2].spellId=410002;c[2].quality=2;H.Notify();A.Poll();Pass(H)
 check(H.Count('take')==1 and O.redraws==1 and H.Count('orb-spend')==0,'31h: the updated client admits the pick of the needed card')
 M.Stop()
 local H2,M2,A2,O2=World({updated=true})
 Offer(H2,O2,OFFER_MISS)
 check(M2.Start(),'31h memory: Start');Pass(H2)
 local c2=H2.perks.currentChoice;c2[2].spellId=410002;c2[2].quality=2;c2[1].isGuaranteed=true;H2.Notify();A2.Poll();Pass(H2,3)
 check(H2.Count('take')==0 and O2.redraws==1 and H2.Count('orb-spend')==0,'31h memory: with a memory card shown nothing is picked or redrawn')
 M2.Stop()
end

do
 -- 31i: the client's own banish handler (perks_service.lua 438-443) replaces
 -- one card in the existing table; it does not answer the redraw. A
 -- replacement without a needed Echo keeps the redraw pending; one with a
 -- needed Echo is picked through the normal Select.
 local function Banish(H,index,id,q)
  local c=H.perks.currentChoice[index];c.spellId=id;c.quality=q;H.Notify();H.A.Poll()
 end
 local H,M,A,O=Redrawing()
 Banish(H,1,410006,3);Pass(H,25)
 check(O.redraws==1 and H.Count('take')==0 and H.Count('orb-spend')==0 and M.Status().inflight=='redraw',
  '31i: a banish replacement without a needed Echo is not a redraw answer: no second redraw')
 Banish(H,2,410002,2);Pass(H)
 check(H.Count('take')==1 and H.actions[#H.actions][2]==410002 and O.redraws==1,'31i: a banish replacement with a needed Echo is picked')
 M.Stop()
end
do
 -- 31j: a pick refused by the local admission before it is sent (updated
 -- client, a memory card shown) keeps the redraw as the pending request, so a
 -- later change in place without a needed Echo cannot spend a second Orb.
 local H,M,A,O=World({updated=true})
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'31j: Start');Pass(H)
 local c=H.perks.currentChoice;c[2].spellId=410002;c[2].quality=2;c[1].isGuaranteed=true;H.Notify();A.Poll();Pass(H,2)
 check(H.Count('take')==0 and M.Status().inflight=='redraw','31j: the refused-before-send pick keeps the redraw pending')
 c[1].isGuaranteed=nil;c[2].spellId=410005;c[2].quality=0;H.Notify();A.Poll();Pass(H,15)
 check(O.redraws==1 and H.Count('take')==0 and H.Count('orb-spend')==0,'31j: a later nonmatch change spends no second Orb (before the redraw is overdue; then only its one retry, case 32)')
 M.Stop()
end
do
 -- 31k: Stop while a redraw is pending, then the cards change in place to a
 -- needed Echo while stopped: nothing is sent while stopped; a new Start
 -- rejoins the pending redraw and picks the visible needed Echo once.
 local H,M,A,O=Redrawing()
 M.Stop()
 InPlace(H,OFFER_HIT);Pass(H,2)
 check(H.Count('take')==0,'31k: nothing is sent while stopped')
 check(M.Start(),'31k: Start');Pass(H)
 check(H.Count('take')==1 and O.redraws==1 and H.Count('orb-spend')==0,'31k: the rejoined run picks the visible needed Echo once')
 M.Stop()
end

-- 32. One retry of an overdue redraw (user-approved 2026-11-19, with the
-- disclosed risk that a late first answer can still arrive and a second Orb
-- can be spent). The game's redraw is modelled as its client source states
-- it: RerollOffer returns nothing, sets the client's redraw flag, sends the
-- request, lowers the shown count at once, and asks for the charge count; a
-- request the server drops answers with that count alone. On the pass where
-- the redraw is overdue, and only when no eligible needed Echo is shown, the
-- same redraw is sent once more through the ordinary adapter, if a fresh
-- read still shows the same Orb offer, the same cards and the same known
-- count, with no pick in flight. An unchanged count is not proof the first
-- redraw failed.
local OFFER_MISS2={{spellId=410006,quality=3},{spellId=410005,quality=0},{spellId=410004,quality=0}}
-- outcomes, one per RerollOffer call: 'drop' (only the charge reply, with the
-- old count), 'lost' (an Orb taken, no new choice seen), or a list of cards
-- (an Orb taken and a new choice table with those cards).
local function Native(H,O,outcomes)
 local orb=ProjectEbonhold.OrbService
 local server=O.charges
 local queue={}
 O.redraws=0
 orb.RerollOffer=function()
  if not orb.CanRerollOffer() then return end
  O.redraws=O.redraws+1;H.actions[#H.actions+1]={'orb-redraw'}
  H.perks.pendingOrbReroll=true
  local o=outcomes[O.redraws] or 'drop'
  if o~='drop' then server=server-1 end
  O.charges=math.max(0,O.charges-1)
  O.requests=O.requests+1
  queue[#queue+1]=o
 end
 local W={initial=O.charges}
 function W.deliver()
  local q=queue;queue={}
  for _,o in ipairs(q) do
   O.charges=server
   if type(o)=='table' then H.perks.pendingOrbReroll=nil;H.Board(o) end
  end
  H.Notify();H.A.Poll()
 end
 function W.gain(n) server=server+n;O.charges=server;H.Notify();H.A.Poll() end
 return W
end
local function NPass(H,W,seconds) for _=1,math.floor((seconds or .5)/.5+.5) do W.deliver();H.Advance(.5) end end
local function Dropped(outcomes)
 local H,M,A,O=World();local W=Native(H,O,outcomes)
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'32: Start');H.Advance(.5)
 check(O.redraws==1 and M.Status().inflight=='redraw','32: setup: one redraw sent, no new offer yet')
 return H,M,A,O,W
end
local GIVEUP='did not see an answer'
-- a) dropped, then the one retry is answered: the run continues normally.
do
 local H,M,A,O,W=Dropped({'drop',OFFER_HIT})
 local before=W.initial
 NPass(H,W,10)
 check(O.redraws==1 and not M.Status().reason:find(GIVEUP,1,true),'32a: no early retry: before the redraw is overdue the run only waits')
 for _=1,22 do if O.redraws>1 then break end;W.deliver();H.Advance(.5) end
 check(O.redraws==2 and H.Count('orb-spend')==0 and H.Count('take')==0,'32a: the overdue redraw is sent once more, through the native redraw')
 NPass(H,W)
 check(H.Count('take')==1 and H.actions[#H.actions][2]==410002,"32a: the retried redraw's new offer is used: the needed Echo is chosen")
 Taken(H,O,410002,2);NPass(H,W)
 check(M.Status().state=='DONE' and O.redraws==2 and O.charges==before-1,'32a: the run completes; one Orb was taken for the redraw that went through')
end
-- b) a new offer before the redraw is overdue is used normally (no retry);
-- the next, independent redraw has its own single retry.
do
 local H,M,A,O,W=Dropped({OFFER_MISS2,'drop','drop'})
 NPass(H,W,2)
 check(O.redraws==2,'32b: the new offer without a needed Echo gets its normal redraw')
 NPass(H,W,21)
 check(O.redraws==3,'32b: that independent redraw gets its own one retry')
 NPass(H,W,30)
 check(O.redraws==3 and M.Status().reason:find(GIVEUP,1,true)~=nil,'32b: no third send for it; the run says it saw no answer')
 M.Stop()
end
-- c) a changed or unavailable balance: no retry.
do
 local H,M,A,O,W=Dropped({'lost'})
 NPass(H,W,25)
 check(O.redraws==1 and M.Status().reason:find(GIVEUP,1,true)~=nil,'32c lost: one fewer Orb than at the send: no retry, the run waits')
 M.Stop()
 H,M,A,O,W=Dropped({'drop'})
 NPass(H,W,5);W.gain(1);NPass(H,W,20)
 check(O.redraws==1,'32c gain: a count above the one at the send: no retry')
 M.Stop()
 H,M,A,O,W=Dropped({'drop'})
 NPass(H,W,5);O.known=false;NPass(H,W,20)
 check(O.redraws==1 and H.Count('orb-spend')==0,'32c unknown: the balance cannot be read: no retry')
 M.Stop()
end
-- d) the eligible needed-Echo pick comes first on the overdue pass.
do
 local H,M,A,O,W=Dropped({'drop'})
 NPass(H,W,19.5)
 check(O.redraws==1,'32d: setup: not yet overdue')
 H.OrbPlan({{spellId=410006,quality=3,stacks=1}});NPass(H,W,2)
 check(H.Count('take')==1 and H.actions[#H.actions][2]==410006 and O.redraws==1,'32d: a visible needed Echo is picked; no retry')
 M.Stop()
end
-- e) the retry is lost too: no third send, nothing spent beyond it.
do
 local H,M,A,O,W=Dropped({'drop','drop'})
 local before=W.initial
 NPass(H,W,22)
 check(O.redraws==2,'32e: setup: the one retry')
 NPass(H,W,40)
 check(O.redraws==2 and H.Count('orb-spend')==0 and H.Count('take')==0 and O.charges==before,'32e: a second loss: no third send')
 check(M.Active() and M.Status().reason:find(GIVEUP,1,true)~=nil,'32e: the run still waits and says it saw no answer; Stop ends it')
 M.Stop()
end
-- f) a pick in flight (the player's own), other cards, or no Orb offer flag: no retry.
do
 local H,M,A,O,W=Dropped({'drop'})
 NPass(H,W,5);H.perks.pendingSelectSpellId=410004;NPass(H,W,20)
 check(O.redraws==1 and M.Status().reason:find(GIVEUP,1,true)~=nil,'32f pick: a pick pending in the game: no retry, nothing attempted')
 M.Stop()
 H,M,A,O,W=Dropped({'drop'})
 NPass(H,W,5);InPlace(H,{{spellId=410006,quality=3},{spellId=410004,quality=3},{spellId=410005,quality=0}});NPass(H,W,20)
 check(O.redraws==1,'32f cards: other cards shown: no retry')
 M.Stop()
 H,M,A,O,W=Dropped({'drop'})
 NPass(H,W,5);O.offer=false;H.Notify();A.Poll();NPass(H,W,20)
 check(O.redraws==1,'32f offer: no Orb offer flag: no retry')
 M.Stop()
end
-- h) a retry refused before it is sent (the client admission) sends nothing
-- and keeps the one retry for the next pass.
do
 local H,M,A,O,W=Dropped({'drop',OFFER_HIT})
 local orbs=Nexus.GameAdapter.Orbs
 local admit=orbs.RunAdmission
 local refused=0
 orbs.RunAdmission=function(kind) if kind=='choice' then refused=refused+1;return false,'Blocked for this check.' end return admit(kind) end
 NPass(H,W,22)
 check(refused>0 and O.redraws==1,'32h: the retry refused before it is sent: nothing is sent')
 orbs.RunAdmission=admit
 for _=1,4 do if O.redraws>1 then break end;H.Advance(.5) end
 check(O.redraws==2,'32h: the retry was kept and is sent on a later pass')
 NPass(H,W)
 check(H.Count('take')==1,'32h: its new offer is used')
 M.Stop()
end
-- g) Stop and Start: nothing is sent while stopped; the one retry is kept
-- across the rejoin, and is not given again after it was used.
do
 local H,M,A,O,W=Dropped({'drop',OFFER_HIT})
 NPass(H,W,5);M.Stop();NPass(H,W,30)
 check(O.redraws==1 and H.Count('take')==0,'32g: nothing is sent while stopped')
 check(M.Start(),'32g: Start rejoins the redraw');NPass(H,W)
 check(O.redraws==2,'32g: the rejoined overdue redraw gets its one retry')
 NPass(H,W)
 check(H.Count('take')==1,'32g: its new offer is used')
 M.Stop()
 H,M,A,O,W=Dropped({'drop','drop'})
 NPass(H,W,22)
 check(O.redraws==2,'32g used: setup: the retry was sent')
 M.Stop();check(M.Start(),'32g used: Start rejoins the retried redraw');NPass(H,W,40)
 check(O.redraws==2,'32g used: no further retry after the rejoin')
 M.Stop()
end

-- 33. Redraw timing in the support report (user-approved 2026-11-19): for
-- each redraw the run sent, the client-clock time from its send (and from its
-- one retry) to the pass on which Nexus saw a new choice table, or pending.
-- Session memory only, the last 8 redraws, on the existing send and answer
-- paths: it sends, reads and changes nothing. Not a server measurement.
local function TView(M) return M.RedrawTimingView() end
local function TLine() return report():match('Orb redraw timing:[^\n]*') or 'missing' end
local function near(n,want) return type(n)=='number' and math.abs(n-want)<=0.51 end
-- a) fast: the new choice table is seen on the next pass.
do
 local H,M,A,O=World();local W=Native(H,O,{OFFER_HIT})
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'33a: Start');NPass(H,W,1)
 local v=TView(M)
 check(v.first==1 and v.retries==0 and v.seen==1 and v.pending==0 and v.picked==0 and #v.recent==1,'33a: one redraw, seen, no retry')
 check(v.recent[1].state=='seen' and v.recent[1].first>=0 and v.recent[1].first<=.5 and v.recent[1].retry==nil,'33a: fast: within one pass: '..tostring(v.recent[1].first))
 local line=TLine()
 check(line:find('redraws=1 retries=0 attempts=1 newChoiceSeen=1 choiceCleared=0 pending=0 pickBeforeNewChoice=0 recent=first:',1,true)~=nil
  and line:find('s/seen (session memory only',1,true)~=nil and not line:lower():find('latency',1,true)
  and not line:lower():find('server response',1,true),'33a: the report line: '..line)
 M.Stop()
end
-- b) slow: the new choice table arrives after 12 s, before any retry.
do
 local H,M,A,O=World();local W=Native(H,O,{OFFER_HIT})
 Offer(H,O,OFFER_MISS)
 check(M.Start(),'33b: Start');H.Advance(12);W.deliver();NPass(H,W,1)
 local v=TView(M)
 check(v.first==1 and v.retries==0 and v.seen==1 and v.recent[1].state=='seen' and v.recent[1].first>=12 and v.recent[1].first<=12.6,
  '33b: slow: about 12 s, no retry: '..tostring(v.recent[1].first))
 check(TLine():find('attempts=1 newChoiceSeen=1',1,true)~=nil,'33b: line')
 M.Stop()
end
-- c) same table, same cards (dropped): pending with its time so far; the
-- retry counts as an attempt, not as a settlement.
do
 local H,M,A,O,W=Dropped({'drop','drop'})
 NPass(H,W,10)
 local v=TView(M)
 check(v.first==1 and v.retries==0 and v.seen==0 and v.pending==1 and v.recent[1].state=='pending' and v.recent[1].first>=10,
  '33c: dropped: pending, time so far: '..tostring(v.recent[1].first))
 NPass(H,W,12)
 v=TView(M)
 check(O.redraws==2 and v.first==1 and v.retries==1 and v.seen==0 and v.pending==1 and v.recent[1].retry~=nil
  and v.recent[1].retry<v.recent[1].first,'33c: the retry: two attempts, nothing settled, still pending')
 check(TLine():find('redraws=1 retries=1 attempts=2 newChoiceSeen=0 choiceCleared=0 pending=1',1,true)~=nil
  and TLine():find(',retry:',1,true)~=nil and TLine():find('/pending',1,true)~=nil,'33c: line: '..TLine())
 M.Stop()
end
-- d) the retry is answered: both durations, from the first send and the retry.
do
 local H,M,A,O,W=Dropped({'drop',OFFER_HIT})
 NPass(H,W,22)
 local v=TView(M)
 check(O.redraws==2 and v.seen==1 and v.retries==1 and v.pending==0,'33d: retried redraw seen')
 local e=v.recent[1]
 check(e.state=='seen' and e.first>=20 and near(e.retry,.5),'33d: from the first send about 20 s, from the retry about one pass: '..tostring(e.first)..' '..tostring(e.retry))
 M.Stop()
end
-- e) a new choice table with the same cards is a new choice seen; the next
-- redraw is a separate record.
do
 local H,M,A,O,W=Dropped({OFFER_MISS,'drop'})
 NPass(H,W,1)
 local v=TView(M)
 check(O.redraws==2 and v.first==2 and v.seen==1 and v.pending==1 and v.recent[1].state=='seen' and v.recent[2].state=='pending',
  '33e: same cards on a new table: seen; the next redraw is its own record')
 M.Stop()
end
-- f) a pick before any new choice table: recorded as pick, not as seen.
do
 local H,M,A,O,W=Dropped({'drop'})
 NPass(H,W,3);H.OrbPlan({{spellId=410006,quality=3,stacks=1}});NPass(H,W,1)
 local v=TView(M)
 check(H.Count('take')==1 and v.seen==0 and v.picked==1 and v.pending==0 and v.recent[1].state=='pick','33f: pick before a new choice')
 check(TLine():find('pickBeforeNewChoice=1',1,true)~=nil and TLine():find('/pick',1,true)~=nil,'33f: line')
 M.Stop()
 -- the game refuses that pick: the run ends, the redraw stays pending (carried), not "pick"
 H,M,A,O,W=Dropped({'drop'})
 H.service.SelectPerk=function() return false end
 NPass(H,W,3);H.OrbPlan({{spellId=410006,quality=3,stacks=1}});NPass(H,W,1)
 v=TView(M)
 check(M.Status().state=='STOPPED' and v.picked==0 and v.pending==1 and v.recent[1].state=='pending','33f refused: a refused pick leaves the redraw pending')
end
-- g) stopped: a new choice table seen while stopped settles the record; the
-- record outlives the run but not the session; the last 8 are kept.
do
 local H,M,A,O,W=Dropped({OFFER_HIT})
 M.Stop();check(TView(M).pending==1,'33g: stopped: still pending')
 W.deliver();H.Advance(1)
 local v=TView(M)
 check(v.seen==1 and v.pending==0 and v.recent[1].state=='seen','33g: seen while stopped')
 check(M.Start(),'33g: a new Start');NPass(H,W,1)
 check(TView(M).first==1 and TView(M).seen==1,'33g: the record is kept across Stop and Start')
 M.Stop()
 -- answered while stopped and seen first by Start itself (no pass between)
 H,M,A,O,W=Dropped({OFFER_HIT})
 M.Stop();W.deliver()
 check(TView(M).pending==1,'33g Start: setup: no pass yet')
 check(M.Start(),'33g Start: Start');v=TView(M)
 check(v.seen==1 and v.pending==0 and v.recent[1].state=='seen' and v.first==1,'33g Start: the answer Start found settles the record')
 M.Stop()
 local outs={}
 for i=1,10 do outs[i]=i%2==1 and OFFER_MISS2 or OFFER_MISS end
 H,M,A,O=World();W=Native(H,O,outs);Offer(H,O,OFFER_MISS)
 check(TView(M).first==0 and #TView(M).recent==0 and TLine():find('redraws=0 retries=0 attempts=0 newChoiceSeen=0 choiceCleared=0 pending=0 pickBeforeNewChoice=0 recent=none',1,true)~=nil,
  '33g: a new session starts empty: '..TLine())
 check(M.Start(),'33g: Start');NPass(H,W,6)
 v=TView(M)
 check(O.redraws>=10 and v.first==O.redraws and #v.recent==8 and v.seen==v.first-v.pending,'33g: totals kept, last 8 listed: '..v.first..' '..#v.recent)
 local items=0;for _ in TLine():gmatch('first:') do items=items+1 end
 check(items==8,'33g: the line lists 8')
 M.Stop()
 local function scan(t,d) if type(t)~='table' or d>12 then return false end
  for k,x in pairs(t) do if k=='retryAt' or k=='timing' or k=='endAt' or scan(x,d+1) then return true end end return false end
 check(not scan(NexusDB,0),'33g: nothing of it is saved')
end
-- h) the outbound calls are the same with the view and the report read on every pass.
do
 local function Run(read)
  local H,M,A,O,W=Dropped({'drop',OFFER_HIT})
  for _=1,50 do if read then M.RedrawTimingView();report() end;NPass(H,W) end
  M.Stop()
  local out={}
  for i,a in ipairs(H.actions) do out[i]=tostring(a[1])..':'..tostring(a[2]) end
  return table.concat(out,','),O.requests,O.redraws,O.charges
 end
 local a1,r1,d1,c1=Run(false)
 local a2,r2,d2,c2=Run(true)
 check(a1==a2 and r1==r2 and d1==d2 and c1==c2,'33h: same outbound calls with and without reading the timing: '..a1..' | '..a2)
end

-- i) a redraw answered by the choice being cleared (no new table): "cleared",
-- never counted as a new choice seen; running, stopped and Start. The run's
-- own actions after it are those of the same scenario as before.
local function Clear(H,O) H.perks.currentChoice=nil;H.perks.pendingOrbReroll=nil;O.offer=false;H.Notify();H.A.Poll() end
local function Cleared(v) return v.seen==0 and v.cleared==1 and v.pending==0 and v.picked==0 and v.recent[1].state=='cleared' end
do
 local H,M,A,O,W=Dropped({'drop'})
 NPass(H,W,3);Clear(H,O);NPass(H,W,1)
 local v=TView(M)
 check(Cleared(v) and v.recent[1].first>=3 and v.recent[1].first<=4.1,'33i running: cleared, not seen: '..tostring(v.recent[1].first))
 local line=TLine()
 check(line:find('newChoiceSeen=0 choiceCleared=1 pending=0',1,true)~=nil and line:find('/cleared',1,true)~=nil
  and line:find('the choice cleared with no new table (cleared; cause not shown)',1,true)~=nil,'33i running: line: '..line)
 check(M.Status().inflight~='redraw','33i running: the run treats it as answered, as before')
 M.Stop()
 H,M,A,O,W=Dropped({'drop'})
 M.Stop();Clear(H,O);H.Advance(1)
 check(Cleared(TView(M)),'33i stopped: cleared while stopped, not seen')
 H,M,A,O,W=Dropped({'drop'})
 M.Stop();Clear(H,O)
 check(TView(M).pending==1,'33i Start: setup: no pass yet')
 M.Start()
 check(Cleared(TView(M)),'33i Start: the clearing Start found is cleared, not seen')
 M.Stop()
 -- a new non-nil table is still seen
 H,M,A,O,W=Dropped({OFFER_HIT});NPass(H,W,1)
 v=TView(M)
 check(v.seen==1 and v.cleared==0 and v.recent[1].state=='seen','33i: a new table stays seen')
 M.Stop()
end
-- j) the existing report rendering: the full line once in the prepared
-- report and its copyable text; a summary keeps whole lines only.
do
 local H,M,A,O,W=Dropped({'drop','drop'})
 NPass(H,W,25)
 local prepared=assert(Nexus.SupportReport.Prepare({}))
 local text=table.concat(prepared.chunks,'')
 local n=0;for _ in text:gmatch('Orb redraw timing:') do n=n+1 end
 local line=text:match('Orb redraw timing:[^\n]*')
 check(n==1 and line:sub(-#'not a server measurement)')=='not a server measurement)','33j: one whole line in the prepared report')
 local summary=Nexus.SupportReport.Summary()
 local s1=summary:match('Orb redraw timing:[^\n]*')
 check(s1==nil and summary:find('omitted',1,true)~=nil or s1~=nil and s1:sub(-#'not a server measurement)')=='not a server measurement)',
  '33j: the summary has the whole line or says lines were omitted')
 M.Stop()
end
print('PASS orb auto start/stop: '..checks..' checks')
