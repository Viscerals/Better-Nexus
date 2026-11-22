-- A receipt restored after a reload must not lock ordinary Auto when no Orb
-- offer is open (the released 9101 lockout). The receipt is one whose Orb offer
-- this client saw (its spend observed, or, the reported branch of cases 12-16,
-- the offer recorded while the spend is unconfirmed) and that has no recorded choice: no ownership result can
-- settle it, so an ordinary Take cannot be counted as its outcome. The chat
-- (/nexus auto) and panel (the real Auto button) toggles and the final
-- ordinary-board gate are each checked. The cases that must still block are
-- checked too: an Orb offer open now, an Orb state the game does not know, a
-- receipt of this session, a paused run and an Orb offer that appears after
-- the release. A recorded choice, an unobserved spend and a matched-then-closed
-- offer no longer block an ordinary pick (user decision, 2026-11-19; cases 5,
-- 8 and 9), and the Take is not counted as their outcome. Synthetic game
-- services only.
local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
local checks=0
local function check(v,msg) assert(v,msg);checks=checks+1 end
-- The rolling-only block, or the whole block on a build without it (the red run).
local function RollingBlocked(M) return (M.BlocksOrdinaryRolling or M.BlocksOrdinary)() end
local function AutoOn() return Nexus.RecomputeStats().autoEnabled==true end
local function Saved() return NexusDB.chars[Nexus.Store.CurrentOwnerKey()].orbRefinement.pending end
local function Canon(v,seen)
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Canon(v[k]) end
 return '{'..table.concat(out,',')..'}'
end
local BOARD={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}}
local ORDINARY={{spellId=410002,quality=2},{spellId=410005,quality=0},{spellId=410008,quality=1}}
local OTHER={{spellId=410005,quality=0},{spellId=410006,quality=3},{spellId=410008,quality=1}}
local function Roll(H,A,n) for _=1,n or 40 do H.Notify();A.Poll();H.Advance(.25) end end
-- Spend observed with its offer, no choice (Stop before the offer), then a reload.
-- `offerOpen`: the game still shows that Orb offer after the reload.
local function Restored(offerOpen)
 local H,M,A,O=S.Fresh();H.OrbPlan()
 assert(M.Start(3));assert(M.Stop());H.Offer()
 local r=S.Receipt()
 assert(r.spendConfirmed==true and r.offerKey~=nil and r.selectedKey==nil,'setup: spend observed, offer recorded, no choice')
 if not offerOpen then O.offer=false;H.perks.currentChoice=nil end
 M=S.Reload(H);S.Pass(H,M,A);S.Rechecks(H,M,2)
 return H,M,A,O
end
local function Blocked(name,H,M,A)
 check(RollingBlocked(M)==true,name..': ordinary rolling stays blocked')
 check(A.OrdinaryBoardAllowed()~=true,name..': the final ordinary-board gate refuses')
 SlashCmdList.NEXUS('auto')
 check(not AutoOn(),name..': /nexus auto leaves Auto OFF')
end

-- Saved history from an earlier session never blocks an actionable ordinary
-- pick while the live Orb service shows no offer (user decision on the 9106
-- field report, 2026-11-19). The receipt itself is kept unchanged, and the
-- ordinary Take's gain is never counted as its outcome (a receipt that could
-- count it is kept as history before the Take is sent).
local function Released(name,H,M,A)
 local saved=Canon(Saved())
 check(RollingBlocked(M)==false,name..': ordinary rolling is not blocked by the restored receipt')
 local allowed,why=A.OrdinaryBoardAllowed()
 check(allowed==true,name..': the final ordinary-board gate permits: '..tostring(why))
 check(M.BlocksOrdinary()==true,name..': the loadout, lock and upload block (BlocksOrdinary) is unchanged')
 SlashCmdList.NEXUS('auto')
 check(AutoOn(),name..': /nexus auto turns Auto ON')
 local takes=H.Count('take')
 H.Board(ORDINARY);Roll(H,A,20)
 check(H.Count('take')==takes+1,name..': ordinary Auto takes the needed Echo')
 local out=H.Clone(H.granted);out['Desired A']=out['Desired A'] or {};table.insert(out['Desired A'],{spellId=410002,quality=2})
 H.granted=out;H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;Roll(H,A,20)
 check(Canon(Saved())==saved and M.Status().pending,name..': the receipt is kept unchanged; the Take is not counted as its outcome')
end

-- 1. The lockout: no Orb offer open after the reload.
do
 local H,M,A,O=Restored(false)
 local spends,takes,spent=H.Count('orb-spend'),H.Count('take'),M.Status().spent
 local saved=Canon(Saved())
 check(M.Status().pending and M.Status().state=='RECOVERY','1: the restored receipt is unresolved')
 check(M.BlocksOrdinary()==true,'1: the loadout, lock and upload block (BlocksOrdinary) is unchanged')
 check(M.ContinueView().eligible==true,'1: control: the explicit Continue exit is offered')
 check(RollingBlocked(M)==false,'1: no current Orb offer: ordinary rolling is not blocked')
 local allowed,why=A.OrdinaryBoardAllowed()
 check(allowed==true,'1: the final ordinary-board gate permits: '..tostring(why))
 check(not M.Resume(),'1: Resume stays refused (no automatic replay)')
 check(not M.Start(3),'1: a new Orb run stays refused')
 -- the HUD guidance names no ordinary-rolling block
 check(Nexus.OrbGuidance.Observe(nil,nil,nil,{skipHorizon=true}).orbBlock==nil,'1: the HUD guidance names no Orb block on ordinary rolling')
 -- chat path
 SlashCmdList.NEXUS('auto')
 check(AutoOn(),'1: /nexus auto turns Auto ON')
 SlashCmdList.NEXUS('auto')
 check(not AutoOn(),'1: /nexus auto turns Auto OFF again')
 -- panel path: the real Auto button
 SlashCmdList.NEXUS('')
 local btn=NexusPanel and NexusPanel._autoBtn
 check(btn and btn:IsShown(),'1: fixture: the panel Auto button is shown')
 -- a click refused for another reason (Nexus paused) is not called an Orb refusal
 Nexus.SessionPause.Pause();btn:Click()
 local refusal=Nexus.Panel._autoRefusal
 check(not AutoOn() and refusal and refusal.text~=Nexus.Readout.AutoRefusalText('orb',''),'1: a paused-Nexus refusal is not reported as an Orb refusal')
 Nexus.SessionPause.Resume()
 btn:Click()
 check(AutoOn(),'1: the panel Auto button turns Auto ON')
 check(NexusPanel and not (Nexus.Panel and Nexus.Panel._autoRefusal),'1: the panel records no Orb refusal')
 -- final send gate: an ordinary board is taken once
 H.Board(BOARD);Roll(H,A)
 check(H.Count('take')==takes+1,'1: one ordinary Take is sent')
 check(H.Count('orb-spend')==spends,'1: no Orb is spent')
 check(M.Status().pending and M.Status().state=='RECOVERY' and M.Status().spent==spent,
  '1: the old receipt stays unresolved, with its spend unchanged (no attribution of the Take)')
 check(Canon(Saved())==saved,'1: the saved receipt is unchanged')
 check(not M.Resume(),'1: Resume stays refused after the Take')
 -- control: the player's own pick is still kept as the receipt's raw evidence
 local seen=Saved().pickSeen or 0
 H.Board(BOARD);H.service.SelectPerk(410004);H.Advance(.25)
 check((Saved().pickSeen or 0)==seen+1,'1: control: a manual pick is still recorded as raw evidence')
 check(M.Status().pending and M.Status().spent==spent,'1: control: the manual pick settles nothing')
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;S.Pass(H,M,A)
 -- 2. An Orb offer that appears after the release blocks again (a new
 -- offer, spent in the game, that is not the recorded one: not matched to the receipt).
 O.charges=O.charges-1;O.offer=true;H.Board(OTHER);S.Pass(H,M,A)
 check(M.RecoveryView().recovery=='OFFER_UNMATCHED','2: fixture: the new Orb offer is not the recorded one: '..tostring(M.RecoveryView().recovery))
 check(RollingBlocked(M)==true,'2: an Orb offer open now blocks ordinary rolling again')
 check(A.OrdinaryBoardAllowed()~=true,'2: the final ordinary-board gate refuses an open Orb offer')
 local before=H.Count('take');Roll(H,A,12)
 check(H.Count('take')==before,'2: nothing is taken while the Orb offer is open')
end

-- 3. The original Orb offer is still open after the reload.
do
 local H,M,A=Restored(true)
 check(M.Status().pending,'3: setup: restored receipt')
 Blocked('3 offer open',H,M,A)
 check(Nexus.OrbGuidance.Observe(nil,nil,nil,{skipHorizon=true}).orbBlock~=nil,'3: the HUD guidance still names the Orb block')
end

-- 4. The game does not know its Orb state after the reload.
do
 local H,M,A,O=S.Fresh();H.OrbPlan()
 assert(M.Start(3));assert(M.Stop());H.Offer()
 O.offer=false;H.perks.currentChoice=nil;O.known=false
 M=S.Reload(H);S.Pass(H,M,A);S.Rechecks(H,M,2)
 check(M.Status().pending,'4: setup: restored receipt')
 Blocked('4 state unknown',H,M,A)
end

-- 5. A choice was sent and its result is unknown.
do
 local H,M,A,O=S.Fresh();H.OrbPlan()
 H.Approve(1)
 H.Offer()
 local r=S.Receipt()
 check(r.selectedKey~=nil and r.choiceMayHaveBeenSent==true,'5: setup: a choice was sent')
 -- the spend gave up its source Echo (as the game does); the choice's own
 -- result is not shown yet, so an ordinary Take of the same Echo would show
 -- exactly the gain this receipt waits for
 for _,es in pairs(H.granted) do for i=#es,1,-1 do if es[i].spellId==O.source then table.remove(es,i) end end end
 H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil;O.offer=false
 M=S.Reload(H);S.Pass(H,M,A);S.Rechecks(H,M,2)
 check(M.Status().pending,'5: setup: restored receipt with a recorded choice')
 Released('5 recorded choice',H,M,A)
end

-- 6. The receipt of this session (no reload), its offer gone.
do
 local H,M,A,O=S.Fresh();H.OrbPlan()
 assert(M.Start(3));assert(M.Stop());H.Offer()
 O.offer=false;H.perks.currentChoice=nil;S.Pass(H,M,A)
 check(M.Status().pending,'6: setup: unresolved receipt of this session')
 Blocked('6 this session',H,M,A)
end

-- 7. A user Pause of a running run.
do
 local H,M,A=S.Fresh();H.OrbPlan()
 H.Approve(2)
 check(M.Pause(),'7: setup: the player paused the run')
 Blocked('7 paused',H,M,A)
end

-- 8. The Orb was requested and its offer was never seen (spend not observed).
do
 local H,M,A,O=S.Fresh();H.OrbPlan()
 assert(M.Start(3));assert(M.Stop())
 check(S.Receipt() and S.Receipt().spendConfirmed~=true,'8: setup: spend not observed')
 M=S.Reload(H);S.Pass(H,M,A);S.Rechecks(H,M,2)
 check(M.Status().pending,'8: setup: restored receipt')
 Released('8 spend unobserved',H,M,A)
end

-- 9. The recorded offer was matched after the reload, then closed: the live
-- service shows no offer, so it no longer blocks an ordinary pick.
do
 local H,M,A,O=Restored(true)
 O.offer=false;H.perks.currentChoice=nil;S.Pass(H,M,A)
 Released('9 matched offer closed',H,M,A)
end

-- 10. Released, then the game state cannot be read.
do
 local H,M,A=Restored(false)
 check(RollingBlocked(M)==false,'10: setup: released')
 local B=Nexus.GameAdapter.Orbs;local read=B.Read
 B.Read=function() error('synthetic unreadable state') end
 S.Pass(H,M,A)
 check(M.RecoveryView().recovery=='UNREADABLE','10: fixture: the read failed: '..tostring(M.RecoveryView().recovery))
 check(RollingBlocked(M)==true,'10: an unreadable Orb state blocks ordinary rolling again')
 B.Read=read;S.Pass(H,M,A)
 check(RollingBlocked(M)==false,'10: a readable state with no Orb offer releases it again')
end

-- 11. The player's Continue check is under way.
do
 local H,M,A=Restored(false)
 local begun,why=M.ContinueBegin()
 check(begun and M.ContinueView().stage=='checking','11: fixture: the Continue check started: '..tostring(why))
 check(RollingBlocked(M)==true,'11: ordinary rolling waits for the Continue check')
 M.ContinueCancel()
 check(RollingBlocked(M)==false,'11: a cancelled check releases it again')
end

-- The reported branch: the Orb offer was recorded before the client's balance
-- showed the spend (spendConfirmed=false, Continue refuses spend_unconfirmed),
-- Stop, the loadout moved from slot 1 to slot 5, a reload, and an ordinary board.
local function Unconfirmed(opts)
 opts=opts or {}
 local H,M,A,O=S.Fresh()
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
  [5]={name='Five',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 H.OrbPlan()
 assert(M.Start(3))
 O.offer=true;H.Board(BOARD);M.Pump() -- the offer, and no balance drop yet
 assert(M.Stop())
 local r=S.Receipt()
 assert(r.spendConfirmed~=true and r.offerKey~=nil and r.selectedKey==nil and r.originalSlot==1,
  'setup: offer recorded, spend unconfirmed, no choice, slot 1')
 if not opts.offerOpen then O.offer=false;H.perks.currentChoice=nil end
 M=S.Reload(H)
 H.perks.serverActiveSlot=5;S.Pass(H,M,A);S.Rechecks(H,M,2)
 if not opts.offerOpen then H.Board(ORDINARY);S.Pass(H,M,A) end
 return H,M,A,O
end

-- 12. The reported branch is released for ordinary rolling only.
do
 local H,M,A,O=Unconfirmed()
 local r=Saved()
 check(r.spendConfirmed~=true and r.offerKey~=nil and r.selectedKey==nil and r.picks==nil
  and r.loadoutChanged==true and r.originalSlot==1,'12: fixture: the reported receipt shape after the reload')
 check(M.Status().state=='PAUSED' and M.Status().pending,'12: fixture: paused, unresolved')
 check(M.ContinueView().eligible==false and M.ContinueView().reason=='spend_unconfirmed','12: control: Continue refuses an unconfirmed spend (unchanged)')
 local spends,takes=H.Count('orb-spend'),H.Count('take')
 local saved=Canon(Saved())
 check(M.BlocksOrdinary()==true,'12: the loadout, lock and upload block is unchanged')
 check(RollingBlocked(M)==false,'12: the recorded offer is gone: ordinary rolling is not blocked')
 local allowed,why=A.OrdinaryBoardAllowed()
 check(allowed==true,'12: the final ordinary-board gate permits: '..tostring(why))
 check(Nexus.OrbGuidance.Observe(nil,nil,nil,{skipHorizon=true}).orbBlock==nil,'12: the HUD guidance names no Orb block on ordinary rolling')
 check(not M.Resume() and not M.Start(3),'12: Resume and Start stay refused')
 SlashCmdList.NEXUS('auto');check(AutoOn(),'12: /nexus auto turns Auto ON')
 SlashCmdList.NEXUS('auto');check(not AutoOn(),'12: /nexus auto turns Auto OFF')
 SlashCmdList.NEXUS('');NexusPanel._autoBtn:Click();check(AutoOn(),'12: the panel Auto button turns Auto ON')
 Roll(H,A)
 check(H.Count('take')==takes+1 and H.Count('orb-spend')==spends,'12: one ordinary Take, no Orb spend')
 check(Canon(Saved())==saved,'12: the saved receipt is unchanged (the spend stays unconfirmed, nothing attributed)')
 check(M.RecoveryView().spendObserved==false and M.Status().pending,'12: the spend is not confirmed and the outcome stays unresolved')
 check(M.ContinueView().reason=='spend_unconfirmed','12: Continue is still refused')
 -- a new Orb offer (another spend) blocks again
 H.perks.pendingSelectSpellId=nil
 O.charges=O.charges-1;O.offer=true;H.Board(OTHER);S.Pass(H,M,A)
 check(RollingBlocked(M)==true and A.OrdinaryBoardAllowed()~=true,'12: an Orb offer open now blocks again')
 local before=H.Count('take');Roll(H,A,12)
 check(H.Count('take')==before,'12: nothing is taken while the Orb offer is open')
end

-- 13. The same branch while the recorded offer is still open after the reload.
do
 local H,M,A=Unconfirmed({offerOpen=true})
 check(M.Status().pending,'13: setup: restored receipt')
 Blocked('13 recorded offer still open',H,M,A)
end

-- 14. Released, then the game reports an unknown Orb state: the gate refuses.
do
 local H,M,A,O=Unconfirmed()
 check(RollingBlocked(M)==false,'14: setup: released')
 O.known=false
 check(A.OrdinaryBoardAllowed()~=true,'14: an unknown Orb state at the final gate refuses')
 S.Pass(H,M,A)
 check(A.OrdinaryBoardAllowed()~=true,'14: still refused after the next read')
 O.known=true
end

-- 15. A delayed Auto approval (the overwrite warning answers later) rechecks.
do
 local H,M,A,O=Unconfirmed()
 local W=Nexus.OverwriteWarning;local request=W.RequestAuto;local held
 W.RequestAuto=function(_,accept) held=accept;return false end
 SlashCmdList.NEXUS('auto')
 check(held~=nil and not AutoOn(),'15: fixture: the approval is waiting')
 O.charges=O.charges-1;O.offer=true;H.Board(OTHER);S.Pass(H,M,A)
 check(held()==false and not AutoOn(),'15: an approval answered after an Orb offer opened is refused')
 O.offer=false;H.perks.currentChoice=nil;S.Pass(H,M,A)
 held=nil;SlashCmdList.NEXUS('auto')
 check(held~=nil,'15: fixture: a new approval is waiting')
 local accepted=held()
 check(accepted~=false and AutoOn(),'15: control: an approval answered with no Orb offer turns Auto ON')
 W.RequestAuto=request
end

-- 16. Archived history: an ordinary Take settles nothing and changes nothing.
-- A real bounded archive (as orb_recovery_continue S01Archive), then a new
-- acknowledged Start through the real panel, its offer, Stop and a reload.
for _,confirmed in ipairs({true,false}) do
 local R=dofile('tests/prototype/orb_recovery_support.lua');local RS=R.S
 local H,M,A,O=RS.Fresh();RS.Loadouts(H,A);H.perks.currentChoice={};assert(M.Start(1))
 local server=R.Server(H)
 H.service.RequestChoice=function()SendAddonMessage(R.PREFIX,'16','WHISPER',R.ME);server.queue[#server.queue+1]={op=16,body=''}end
 for _=1,180 do if M.Status().state=='FINISHED' then break end;H.Advance(.25) end
 assert(M.Status().state=='FINISHED' and not R.Saved() and #R.SavedRow('orbRecoveryArchive')==1,'16: setup: a real archived UNKNOWN/NONE receipt')
 -- Start/Stop rework: the window's Start runs the new automation; this earlier-runtime
 -- receipt is created through its own API with the represented history review.
 assert(M.SetLimit(3));local review=M.Status().historyReview
 assert(M.Start(3,false,review))
 assert(R.Saved(),'16: setup: a new acknowledged receipt')
 assert(M.Stop()) -- before the offer: no choice is made
 if confirmed then H.Offer() else O.offer=true;H.Board(BOARD);M.Pump() end
 O.offer=false;H.perks.currentChoice=nil
 M=RS.Reload(H);RS.Pass(H,M,A);RS.Rechecks(H,M,2)
 local name='16 '..(confirmed and 'confirmed' or 'unconfirmed')
 local archive,saved=Canon(R.SavedRow('orbRecoveryArchive')),Canon(R.Saved())
 check((R.Saved().spendConfirmed==true)==confirmed and R.Saved().offerKey~=nil and R.Saved().selectedKey==nil,name..': fixture: restored receipt shape')
 check(RollingBlocked(M)==false and A.OrdinaryBoardAllowed()==true,name..': released for ordinary rolling')
 local takes=H.Count('take')
 SlashCmdList.NEXUS('auto');H.Board(ORDINARY);Roll(H,A)
 check(H.Count('take')==takes+1,name..': one ordinary Take')
 -- the Take's Echo is now owned, as the game reports it
 H.granted[H.names[410002]]={{spellId=410002,quality=2}};H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil
 RS.Pass(H,M,A);RS.Rechecks(H,M,2)
 check(Canon(R.Saved())==saved and not R.Saved().attributionAmbiguous,name..': the receipt is unchanged; the gain is not attributed')
 check(Canon(R.SavedRow('orbRecoveryArchive'))==archive,name..': the archive is unchanged')
 check(M.Status().pending,name..': the outcome stays unresolved')
end

print('PASS orb restored ordinary release: '..checks..' checks')
