-- Reported Orb recovery hold (test.9072), reproduced offline with synthetic data
-- only: after a reload the Orb state is PAUSED, the recovery is PAUSED, the
-- unmet requirement is the loadout, the spend is confirmed, no choice and no
-- selected Echo are recorded, no game pick is in flight, a loadout change is
-- recorded and no automatic refresh was requested.
--
-- This is a CHARACTERIZATION test. It pins what the accepted code does, so a
-- diagnostic change cannot alter an action rule:
--  1. Eight unrelated synthetic causes end in the SAME reported view. The
--     owner's answer and the first two support lines cannot tell them apart.
--  2. The hold is permanent. Return to the original slot, Recheck, Stop and
--     reload never clear it; Resume and a new run stay refused; the ordinary
--     block stays.
--  3. Nothing reaches the game: no second Orb spend, no automatic choice.
--  4. Nothing is inferred or fabricated: the original slot, the offer and the
--     missing choice stay exactly as recorded; a later observation does not
--     fill them in; a choice that the player makes while the hold is set is not
--     recorded for the earlier action; an exact result does not settle it.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
-- The accepted pause text of the hold, word for word (a diagnostic change must not touch it).
local PAUSE_TEXT="The original loadout cannot be verified after a loadout change or an incomplete older receipt. Ownership responses do not identify the original loadout. Pending exposure is retained; no retry is allowed."

-- The passive view states the one-Orb decrement as a client-observed spend
-- (spendObserved); the receipt keeps its saved field spendConfirmed.
local FIELDS={'pending','restored','state','recovery','gate','spendObserved','choiceSent','choiceObserved','selectedKey','removed','loadoutChanged','pickInFlight','autoRefresh'}
local REPORTED={pending=true,restored=true,state='PAUSED',recovery='PAUSED',gate='loadout',spendObserved=true,
 choiceSent=false,choiceObserved=false,selectedKey=nil,loadoutChanged=true,pickInFlight=false,autoRefresh=false}
local function Signature(view,source)
 local out={}
 for _,k in ipairs(FIELDS)do
  local v=view[k]
  out[#out+1]=k..'='..(k=='removed' and (v==source and 'SOURCE' or tostring(v)) or tostring(v))
 end
 return table.concat(out,' ')
end
local function Expected(source)
 local e=setmetatable({removed=source},{__index=REPORTED})
 return Signature(e,source)
end
local function OrbLines()return Nexus.SupportReport.OrbLines()end

local signatures,lineOne,lineTwo={},{},{}
for index,cause in ipairs(S.CAUSES)do
 local H,M,A,O,src,slots=S.Build(cause)
 local name=cause.name
 local key=S.Receipt().removed -- the source Echo key recorded in the receipt
 local view=Nexus.OrbRuntime.RecoveryView()
 local sig=Signature(view,key)
 check(sig==Expected(key),name..': the reported view is reproduced: '..sig)
 signatures[#signatures+1]=sig
 check(M.Status().state=='PAUSED' and M.Status().recovery.kind=='PAUSED' and M.Status().pending,name..': Status is PAUSED / PAUSED with the receipt pending')
 check(M.Status().reason==PAUSE_TEXT,name..': the hold text is exactly the accepted one: '..tostring(M.Status().reason))
 local lines=OrbLines()
 check(lines[1]=='Orb action: unresolved after a reload; state=PAUSED; recovery=PAUSED; waiting for=loadout',name..': first support line: '..tostring(lines[1]))
 check(lines[2]=='  client-observed spend=yes; choice=none; selected=none; source='..key..'; game pick in flight=no; loadout change recorded=yes; automatic refresh=not requested',
  name..': second support line: '..tostring(lines[2]))
 lineOne[#lineOne+1]=lines[1];lineTwo[#lineTwo+1]=(lines[2]:gsub('source=%S+;','source=X;'))

 -- The receipt as recorded.
 local before=H.Clone(S.Receipt())
 check(before.loadoutChanged==true and before.spendConfirmed==true and before.offerKey~=nil
  and before.selectedKey==nil and before.selectionAttempted==nil and before.choiceObserved==nil and before.choiceMayHaveBeenSent==nil,
  name..': the receipt holds a spend and an offer, and no choice')
 check(before.originalSlot==cause.expect.original,name..': the original slot is exactly what was recorded ('..tostring(cause.expect.original)..')')

 local calls=S.CountCalls(H)
 local writes=S.CountOrbWrites()
 check(not M.Resume() and not M.Prepare() and M.BlocksOrdinary()==true,name..': no Resume, no new run, ordinary rolling blocked')
 -- Return to the original slot, Recheck, Stop, reload: none of them clears it.
 H.perks.serverActiveSlot=cause.expect.original or 1;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,3)
 check(Nexus.OrbRuntime.RecoveryView().loadoutChanged==true and M.Status().state=='PAUSED','nothing clears the hold at the original slot: '..name)
 M.Stop();S.Rechecks(H,M,2)
 check(S.Receipt().loadoutChanged==true and M.Status().pending,name..': Stop keeps the receipt and the hold')
 M=S.Reload(H);H.perks.serverActiveSlot=cause.expect.original or 1;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,3)
 check(Signature(Nexus.OrbRuntime.RecoveryView(),key)==Expected(key) and not M.Resume() and not M.Prepare() and M.BlocksOrdinary()==true,
  name..': a reload keeps the hold and every refusal')
 -- A choice that the player makes while the hold is set is not recorded, and an
 -- exact result does not settle the earlier action.
 H.perks.pendingSelectSpellId=nil
 check(calls.pick(410002)==true,name..': the player chooses in the offer window')
 H.Advance(.5)
 local out=H.Clone(H.granted);local removed=false
 for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==src then table.remove(es,i);removed=true end end end
 out['Desired A']={{spellId=410002,quality=2}};H.granted=out
 H.perks.currentChoice=nil;O.offer=false;H.perks.pendingSelectSpellId=nil
 S.Pass(H,M,A);S.Rechecks(H,M,3)
 local after=S.Receipt()
 check(after.selectedKey==nil and not after.selectionAttempted and not after.choiceObserved and not after.choiceMayHaveBeenSent,
  name..': a choice made while the hold is set is not recorded for the earlier action')
 check(after.loadoutChanged==true and M.Status().pending and not M.Resume() and not M.Prepare() and M.BlocksOrdinary()==true,
  name..': the exact result does not settle it')
 check(Nexus.OrbRuntime.RecoveryView().spendObserved==true and M.Status().spent+M.Status().reserved==1,name..': the spend stays counted once')
 -- Nothing was invented.
 check(after.originalSlot==before.originalSlot,name..': the original slot is not inferred or filled in (still '..tostring(before.originalSlot)..')')
 check(after.offerKey==before.offerKey and after.removed==before.removed and after.chargesBefore==before.chargesBefore
  and after.lockedKey==before.lockedKey,name..': offer, source and balance record are unchanged')
 -- 035: the player's pick is the ONE write after the hold is set. It saves the raw pick evidence (receipt.picks and
 -- receipt.pickSeen) and nothing else: every field pinned above is unchanged, and the evidence is not authoritative.
 check(writes()==1,name..': the player\'s pick is the only Orb receipt write after the hold is set (passes, Recheck, Stop, a reload): '..writes())
 check(type(after.picks)=='table' and #after.picks==1 and after.picks[1].u==false and after.pickSeen==1,
  name..': that write is non-authoritative raw pick evidence')
 do
  -- restored and refreshRequested are the two session flags that ANY save of a restored receipt writes (the same
  -- save the recovery makes at its first offer); they are not evidence and not part of this claim.
  local function Rest(r)local c=H.Clone(r);c.picks=nil;c.pickSeen=nil;c.pickDropped=nil;c.restored=nil;c.refreshRequested=nil;return c end
  local function Same(a,b)
   if type(a)~=type(b)then return false end
   if type(a)~='table'then return a==b end
   for k,v in pairs(a)do if not Same(v,b[k])then return false end end
   for k in pairs(b)do if a[k]==nil then return false end end
   return true
  end
  check(Same(Rest(after),Rest(before)),name..': every other field of the receipt is unchanged')
 end
 check(calls.spend==0 and calls.select==calls.player and calls.player==1 and H.Count('orb-spend')==1 and H.Count('take')==1,
  name..': nothing reached the game from Nexus (no second spend, no automatic choice; only the player\'s one pick)')
end
-- The hold is saved by exactly one write, and nothing writes the receipt again.
do
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O)
 M=S.Reload(H);S.Pass(H,M,A);S.Rechecks(H,M,2)
 local writes=S.CountOrbWrites()
 S.Rechecks(H,M,4);H.Advance(5)
 check(writes()==0 and not S.Receipt().loadoutChanged,'an unheld restored receipt is not rewritten by passes')
 H.perks.serverActiveSlot=2;S.Pass(H,M,A)
 check(S.Receipt().loadoutChanged==true and writes()==1,'the hold is saved by exactly one write: '..writes())
 S.Rechecks(H,M,4);H.perks.serverActiveSlot=1;S.Pass(H,M,A);S.Rechecks(H,M,3);M.Stop();S.Rechecks(H,M,2)
 check(writes()==1,'and nothing writes it again: '..writes())
end
-- The eight causes are not distinguishable from the reported view or the two lines.
for i=2,#signatures do
 check(signatures[i]==signatures[1],'cause '..i..' gives the identical reported view')
 check(lineOne[i]==lineOne[1] and lineTwo[i]==lineTwo[1],'cause '..i..' gives the identical first two support lines')
end
print('PASS Orb loadout hold: eight synthetic causes give one identical reported view; the hold is permanent and nothing is inferred or sent checks='..checks)
