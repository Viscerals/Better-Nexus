-- Group 6 supplement (S2-C1): passive Orb wording for a RESTORED receipt.
-- Native (static data, never executed): orb_of_lost_memories.lua 401-434
-- SendSpend decrements the charges and raises pendingOffers at once; the
-- SS1220 reply (734-773) "<charges>,<delta>,<pending>" carries no spend
-- identity. The one-Orb decrement that Nexus records with the offer is the
-- client's observation of that optimistic change, not a confirmation of the
-- server transaction. After a reload the texts of the restored action still
-- call it a "confirmed spend": the Continue intro (core/OrbRuntime.lua
-- RC_INTRO), the no-exit sentence appended to recovery texts (NO_EXIT), both
-- reload block texts (M.BlockReason) and the support report line.
-- EXPECT (fails at 8c), for the restored class (an observed one-Orb spend, no
-- recorded choice, offer gone):
--   I  the Continue intro does not call the spend confirmed, and states it as
--      observed by the client;
--   N  the PERMANENT_CHANGED recovery instruction (with the no-exit sentence)
--      does not call it confirmed;
--   B1 the block text of a recovery that cannot progress (PAUSED on the
--      loadout hold) and
--   B2 the block text of a recovery that still observes (LOADOUT_UNKNOWN) do
--      not call it confirmed;
--   R  the support report line of the restored action does not say
--      "spend confirmed=yes" and states the spend as observed by the client.
-- GUARD (holds at 8c): the observed spend stays counted (the receipt's own
-- 170 of 219); the class stays eligible for the player's Continue and the
-- intro still names Continue and its read-only check; an unobserved spend
-- stays ineligible (spend_unconfirmed); the receipt is retained, the run is
-- not running, ordinary actions stay blocked; time passing starts no check;
-- no spend, no choice, no take and no addon message by Nexus.
-- Internal compatibility fields (the saved receipt's spendConfirmed and the
-- passive RecoveryView field) are not asserted here; the fixture edit that
-- builds an unobserved spend uses the saved field, as orb_recovery_continue.lua.
-- SETUP: orb_recovery_support.lua R.Class (the deidentified 034 receipt shape;
-- real Store, OrbRuntime, OrbAdapter, GameAdapter and SupportReport) with its
-- synthetic server; each reached recovery kind is SETUP. No server
-- correlation is manufactured; native code is never executed.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('batch_orb_restored_wording')
local printable=B.printable
local R=dofile('tests/prototype/orb_recovery_support.lua');local S=R.S

local function ClaimsConfirmed(text)
 local lower=tostring(text or ''):lower()
 return lower:find('confirmed spend',1,true)~=nil or lower:find('spend confirmed',1,true)~=nil
  or lower:find('spend was confirmed',1,true)~=nil or lower:find('spend is confirmed',1,true)~=nil
end
local function Observed(text)
 local lower=tostring(text or ''):lower()
 return lower:find('observ',1,true)~=nil or lower:find('client',1,true)~=nil
end
local function World(opts)
 local H,M,A,O=R.Class(opts)
 local server=R.Server(H,opts and opts.server)
 S.Pass(H,M,A,2)
 return H,M,A,O,server
end
local function Kind(M) local st=M.Status();return st.recovery and st.recovery.kind or nil end

C.scenario('I/B1/R restored class with the loadout hold',function()
 local H,M,A=World()
 local calls=R.Calls(H)
 local sent=#H.sent
 local st=M.Status()
 print('OBSERVED','B1 state='..printable(st.state),'recovery='..printable(Kind(M)),'spent='..printable(st.spent)..'/'..printable(st.limit))
 C.setup(st.pending==true and Kind(M)=='PAUSED','B1: the restored class is held on its loadout (recovery PAUSED)',Kind(M))
 local v=M.ContinueView()
 print('OBSERVED','I intro='..printable(v.text))
 C.guard(v.eligible==true and v.reason==nil and v.stage=='idle','I: the class stays eligible for the player\'s Continue',v.reason)
 C.expect(not ClaimsConfirmed(v.text),'I: the Continue intro does not call the client-observed spend confirmed',v.text)
 C.expect(Observed(v.text),'I: the Continue intro states the spend as observed by the client',v.text)
 C.guard(tostring(v.text):find('Continue',1,true)~=nil and tostring(v.text):find('read-only',1,true)~=nil,
  'I: the intro still names Continue and its read-only check',v.text)
 local why=M.BlockReason('Ordinary rolling')
 print('OBSERVED','B1 block='..printable(why))
 C.expect(not ClaimsConfirmed(why),'B1: the block text of a recovery that cannot progress does not call the spend confirmed',why)
 C.guard(tostring(why):find('Continue',1,true)~=nil,'B1: the block text still names Continue',why)
 local spendLine
 for _,line in ipairs(Nexus.SupportReport.OrbLines() or {}) do
  if line:find('choice=',1,true) and line:lower():find('spend',1,true) then spendLine=line end
 end
 print('OBSERVED','R line='..printable(spendLine))
 C.setup(spendLine~=nil,'R: the support report has the restored action line')
 C.expect(tostring(spendLine):find('spend confirmed=yes',1,true)==nil,'R: the restored report line does not say "spend confirmed=yes"',spendLine)
 C.expect(Observed(spendLine),'R: the restored report line states the spend as observed by the client',spendLine)
 C.guard(st.spent==170 and st.limit==219,'G: the observed spend stays counted (170 of 219)',printable(st.spent)..'/'..printable(st.limit))
 C.guard(R.Saved()~=nil and st.running==false and M.BlocksOrdinary()==true,
  'G: the receipt is retained, the run is not running and ordinary actions stay blocked')
 H.Advance(10)
 C.guard(M.ContinueView().stage=='idle' and R.Saved()~=nil and M.Status().spent==170,
  'G: time passing starts no check, keeps the receipt and refunds nothing',M.ContinueView().stage)
 C.guard(calls.spend==0 and calls.nexusSelects()==0 and H.Count('orb-spend')==0 and H.Count('take')==0 and #H.sent==sent,
  'G: no spend, no choice, no take and no addon message by Nexus')
end)

C.scenario('B2 restored class still observing (no build-slot data yet)',function()
 local H,M=World({latch=false,known=false})
 print('OBSERVED','B2 recovery='..printable(Kind(M)))
 C.setup(Kind(M)=='LOADOUT_UNKNOWN','B2: the restored class waits for build-slot data (LOADOUT_UNKNOWN)',Kind(M))
 local why=M.BlockReason('Ordinary rolling')
 print('OBSERVED','B2 block='..printable(why))
 C.expect(not ClaimsConfirmed(why),'B2: the block text of an observing recovery does not call the spend confirmed',why)
 C.guard(M.BlocksOrdinary()==true and R.Saved()~=nil,'B2: ordinary actions stay blocked and the receipt is retained')
end)

C.scenario('N restored class whose locked Echoes changed',function()
 local H,M,A=World({latch=false})
 local locked=H.Clone(H.locked)
 local first;for name in pairs(locked) do if first==nil or name<first then first=name end end
 locked[first]=nil
 H.locked=locked
 S.Pass(H,M,A,2)
 local reason=M.Status().reason
 print('OBSERVED','N recovery='..printable(Kind(M)),'reason='..printable(reason))
 C.setup(Kind(M)=='PERMANENT_CHANGED','N: the changed locked Echoes are recognised (PERMANENT_CHANGED)',Kind(M))
 C.expect(not ClaimsConfirmed(reason),'N: the recovery instruction with the no-exit sentence does not call the spend confirmed',reason)
 C.guard(tostring(reason):find('Continue',1,true)~=nil,'N: the instruction still names the player\'s Continue as the exit',reason)
 C.guard(M.BlocksOrdinary()==true and R.Saved()~=nil and M.Status().spent==170,'N: the receipt, its counted spend and the block are kept')
end)

C.scenario('U an unobserved spend stays outside Continue',function()
 local H,M=World({edit=function(row,state) row.spendConfirmed=nil;state.spendConfirmed=nil end})
 local v=M.ContinueView()
 C.guard(v.eligible==false and v.reason=='spend_unconfirmed','U: a restored action without the observed spend is not offered Continue',v.reason)
 C.guard(M.BlocksOrdinary()==true and R.Saved()~=nil,'U: its receipt is retained and ordinary actions stay blocked')
end)

C.finish('(restored Orb texts name the client-observed spend; counting, blocks and Continue unchanged)')
