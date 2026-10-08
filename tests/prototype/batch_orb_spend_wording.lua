-- Group 6 (S2-C1): passive Orb wording for a client-observed spend.
-- Native (static data, never executed): orb_of_lost_memories.lua 401-434
-- SendSpend decrements the charges and raises pendingOffers immediately;
-- the SS1220 reply (734-773) is "<charges>,<delta>,<pending>" with no spend
-- identity, so no reply can be correlated with one spend. Nexus counts the
-- one-Orb decrement seen with the offer (OrbRuntime spendConfirmed) and its
-- passive outputs call that observation "confirmed".
-- EXPECT (fails at 8c): after the optimistic decrement and before any reply,
-- the passive RecoveryView does not report spendConfirmed=true; the support
-- report does not say "spend confirmed=yes" and states the spend as observed
-- by the client; the Orb help does not describe Continue's class as a
-- "confirmed spend"; the Continue refusal for an unobserved spend does not
-- call it unconfirmed.
-- GUARD (holds at 8c): the observed spend stays counted (spent 1, reserved 0);
-- after a later refusal-shaped resync and the timeouts the run is PAUSED, the
-- spend stays counted and its receipt retained; exactly one spend and no
-- choice, retry, refund or respend; ordinary actions stay blocked.
-- SETUP: real TOC boot with the synthetic Orb/Perk services of orbs_support;
-- the synthetic ConfirmSpend models the native optimistic field order only.
-- No server correlation is manufactured by this test.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_orb_spend_wording')
local printable=B.printable
local H=dofile('tests/prototype/orbs_support.lua');local M,A,O=H.M,H.A,H.O
H.OrbPlan()
local before=O.charges
local base=ProjectEbonhold.OrbService.ConfirmSpend
ProjectEbonhold.OrbService.ConfirmSpend=function(id,n)
 local accepted=base(id,n)
 if accepted then O.offer=true;O.charges=O.charges-1 end
 return accepted
end
local function Receipt()
 local st=Nexus.Store.State()
 return type(st.orbRefinement)=='table' and st.orbRefinement.pending or nil
end
local board=H.perks.currentChoice
H.Approve(1,false,true)
C.setup(H.Count('orb-spend')==1,'one synthetic spend was submitted')
C.setup(O.charges==before-1 and O.offer==true,'the synthetic native optimistic fields moved synchronously')
C.setup(H.perks.currentChoice==board,'no choice response was delivered')
M.Pump()
local status=M.Status()
C.setup(Receipt()~=nil,'the unresolved action has its durable receipt')
C.guard(status.spent==1 and status.reserved==0,'the observed spend stays counted against the approved budget',
 printable(status.spent)..'/'..printable(status.reserved))

C.scenario('V passive RecoveryView',function()
 local view=M.RecoveryView()
 C.setup(view.pending==true,'V: the passive view shows the unresolved action')
 print('OBSERVED','V spendConfirmed='..printable(view.spendConfirmed))
 C.expect(view.spendConfirmed~=true,'V: the passive view does not label the client-observed spend as confirmed',view.spendConfirmed)
end)

C.scenario('R support report',function()
 local prepared=Nexus.SupportReport.Prepare({extended=true},600)
 local text=table.concat(prepared and prepared.chunks or {},'')
 C.setup(text:find('Orb action: unresolved',1,true)~=nil,'R: the prepared report has the unresolved Orb action section')
 local spendLine
 for line in (text..'\n'):gmatch('([^\n]*)\n') do
  if line:find('choice=',1,true) and line:lower():find('spend',1,true) then spendLine=line end
 end
 print('OBSERVED','R line='..printable(spendLine))
 C.expect(text:find('spend confirmed=yes',1,true)==nil,'R: the report does not say "spend confirmed=yes"',spendLine)
 local lower=tostring(spendLine or ''):lower()
 C.expect(lower:find('observ',1,true)~=nil or lower:find('client',1,true)~=nil,
  'R: the report states the spend as observed by the client',spendLine)
end)

C.scenario('T help and Continue text',function()
 local hits={}
 for _,page in ipairs(Nexus.Help.Pages or {}) do
  local text=tostring(page.text or ''):lower()
  if text:find('confirmed spend',1,true) or text:find('spend confirmed',1,true) then hits[#hits+1]=tostring(page.id) end
 end
 C.setup(#(Nexus.Help.Pages or {})>0,'T: the help pages are loaded')
 C.expect(#hits==0,'T: no help page calls the client-observed spend a "confirmed spend"',table.concat(hits,','))
 local reason=tostring(M.ContinueReason('spend_unconfirmed'))
 print('OBSERVED','T continue refusal='..reason)
 C.expect(reason:lower():find('confirmed',1,true)==nil,
  'T: the Continue refusal for an unobserved spend does not call it unconfirmed',reason)
end)

C.scenario('S safeguards after a refusal-shaped resync',function()
 O.charges=before;O.offer=false;H.perks.currentChoice=nil
 M.Pump();H.Advance(21)
 local final=M.Status()
 print('OBSERVED','S state='..printable(final.state),'spent='..printable(final.spent),'reason='..printable(final.reason))
 C.guard(final.spent==1 and Receipt()~=nil,'S: the spend stays counted and its receipt is retained')
 C.guard(not final.running and final.state=='PAUSED','S: no authoritative result pauses the run',final.state)
 C.guard(H.Count('orb-spend')==1 and H.Count('take')==0,'S: no retry, refund, respend or invented choice')
 C.guard(M.BlocksOrdinary()==true,'S: ordinary actions stay blocked while the receipt is unresolved')
end)

C.finish('(client-observed spend is not labelled confirmed; budgets and gates unchanged)')
