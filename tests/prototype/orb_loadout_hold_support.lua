-- Shared synthetic scenarios for the Orb loadout-hold tests (orb_loadout_hold_repro,
-- orb_loadout_hold_shape, orb_loadout_hold_cause and orb_loadout_hold_history). Real Store, OrbRuntime, OrbAdapter, GameAdapter and
-- SupportReport; only the game services are synthetic. Nothing here uses a real
-- character, account, SavedVariables file or game client.
--
-- Every cause below ends in the same reported hold: the action's Orb spend was
-- confirmed with its offer, no Echo choice was ever recorded for it, and the
-- loadout hold is latched in the saved receipt after a reload.
local S={}
function S.Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 return H,H.M,H.A,H.O
end
function S.Receipt()return Nexus.Store.State().orbRefinement.pending end
-- A reload ends the old Lua state. `saved` edits the saved receipt as the next
-- load reads it (the row and the Store's state of this harness).
function S.Reload(H,saved)
 H.Fire('PLAYER_LOGOUT')
 if saved then saved(NexusDB.chars[Nexus.Store.CurrentOwnerKey()].orbRefinement.pending,Nexus.Store.State().orbRefinement.pending) end
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 H.perks.pendingSelectSpellId=nil -- the game client's Lua restarts too
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 return Nexus.OrbRuntime
end
function S.Loadouts(H,A)
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
  [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 assert(A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410002,quality=2,stacks=2}}))
 assert(A.SetLoadoutWishlistIdentity(2,'Second',{{spellId=410004,quality=3,stacks=2}}))
 return H.perks.serverBuildSlots
end
-- Spend confirmed with its offer, and no choice: Stop before the offer, so the
-- run never chooses. Returns the source key and the build-slot table.
function S.SpendOfferNoChoice(H,M,A,O)
 local slots=S.Loadouts(H,A)
 assert(M.Start(3));assert(M.Stop());H.Offer()
 local r=S.Receipt()
 assert(r.spendConfirmed==true and r.offerKey~=nil and r.selectedKey==nil and r.choiceObserved==nil
  and r.originalSlot==1 and r.loadoutChanged==nil,'setup: spend confirmed, offer recorded, no choice, slot 1, no hold')
 return O.source,slots
end
function S.Pass(H,M,A,seconds)H.Notify();A.Poll();H.Advance(seconds or .5)end
function S.Rechecks(H,M,n)for _=1,n or 3 do H.now=H.now+4;M.Recheck();M.Pump();H.Advance(.5)end end
-- Each cause drives a fresh harness to the latched hold and returns the owner after
-- the last reload. `expect` is what the OLD receipt can be known by: the hold cause
-- that a build with cause tracking records at the moment it first sets the hold, the
-- slot it saw then, and the live slot facts at the end.
S.CAUSES={
 {name='C1 slot data received, a different slot',expect={cause='SLOT_DIFFERS',seen=2,original=1,now=2,nowKnown=true},
  run=function(H,M,A,O,src,slots)
   M=S.Reload(H)
   H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;S.Pass(H,M,A)
   H.perks.serverActiveSlot=2;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,2)
   return M
  end},
 {name='C2 client that reports no slot data, load-time default slot',expect={cause='SLOT_DIFFERS_UNVERIFIED',seen=0,original=1,now=0,nowKnown=nil},
  run=function(H,M,A,O,src,slots)
   M=S.Reload(H)
   H.perks.serverActiveSlot=0;H.service.GetServerBuildSlots=nil;S.Pass(H,M,A)
   return M
  end},
 {name='C3 saved receipt without an original slot',expect={cause='NO_ORIGINAL_SLOT',seen=nil,original=nil,now=1,nowKnown=true},
  run=function(H,M,A,O,src,slots)
   M=S.Reload(H,function(row,state)row.originalSlot=nil;state.originalSlot=nil end)
   S.Pass(H,M,A);S.Rechecks(H,M,2)
   return M
  end},
 {name='C4 different slot pushed before the slot data, then a second reload',expect={cause='SLOT_PUSHED',seen=2,original=1,now=1,nowKnown=true},
  run=function(H,M,A,O,src,slots)
   M=S.Reload(H)
   H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;S.Pass(H,M,A)
   H.perks.serverActiveSlot=2;S.Pass(H,M,A)
   M=S.Reload(H)
   H.perks.serverActiveSlot=1;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,2)
   return M
  end},
 {name='C5 live slot change before the reload, then the slot is restored',expect={cause='SLOT_DIFFERS',seen=2,original=1,now=1,nowKnown=true},
  run=function(H,M,A,O,src,slots)
   H.perks.serverActiveSlot=2;S.Pass(H,M,A)
   H.perks.serverActiveSlot=1;S.Pass(H,M,A)
   M=S.Reload(H)
   H.perks.serverActiveSlot=1;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,2)
   return M
  end},
 {name='C6 slot data received and it names no active slot',expect={cause='SLOT_DIFFERS',seen=0,original=1,now=0,nowKnown=true},
  run=function(H,M,A,O,src,slots)
   M=S.Reload(H)
   H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;S.Pass(H,M,A)
   H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,2)
   return M
  end},
 {name='C8 the client reports no active slot at all',expect={cause='SLOT_DIFFERS',seen=nil,original=1,now=nil,nowKnown=true},
  run=function(H,M,A,O,src,slots)
   M=S.Reload(H)
   H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;S.Pass(H,M,A)
   H.perks.serverActiveSlot=nil;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,2)
   return M
  end},
 -- A designed Wishlist slot (100 and above) as the recorded original slot; the
 -- number is a synthetic stand-in. The saved receipt is edited as the next load
 -- reads it, as C3 does.
 {name='C7 designed-slot original, a different slot afterwards',expect={cause='SLOT_DIFFERS',seen=1,original=107,now=1,nowKnown=true},
  run=function(H,M,A,O,src,slots)
   M=S.Reload(H,function(row,state)row.originalSlot=107;state.originalSlot=107 end)
   S.Pass(H,M,A);S.Rechecks(H,M,2)
   return M
  end},
}
-- Count the writes that replace the saved Orb table (an UpdateStateV1 after which orbRefinement is a new table).
function S.CountOrbWrites()
 local owner=Nexus.MainInternals.StoreAuthorityOwner;local raw=owner.UpdateStateV1;local n=0
 owner.UpdateStateV1=function(fn,...)
  local before=Nexus.Store.State().orbRefinement
  local r=raw(fn,...)
  if Nexus.Store.State().orbRefinement~=before then n=n+1 end
  return r
 end
 return function()return n end
end
-- Count every call that Nexus or the player could make to the game after `from`.
function S.CountCalls(H)
 local calls={select=0,spend=0,player=0}
 local rawSelect=H.service.SelectPerk
 H.service.SelectPerk=function(...)calls.select=calls.select+1;return rawSelect(...)end
 local orb=ProjectEbonhold.OrbService;local rawSpend=orb.ConfirmSpend
 orb.ConfirmSpend=function(...)calls.spend=calls.spend+1;return rawSpend(...)end
 calls.pick=function(id)calls.player=calls.player+1;return H.service.SelectPerk(id)end
 return calls
end
-- Build one cause to its latched hold. Returns H,M,A,O,src and the cause record.
function S.Build(cause)
 local H,M,A,O=S.Fresh()
 local src,slots=S.SpendOfferNoChoice(H,M,A,O)
 M=cause.run(H,M,A,O,src,slots)
 return H,M,A,O,src,slots
end
-- The real receipt SHAPE of the reported hold, as a synthetic fixture (see
-- orb_loadout_hold_shape_support.lua). opts: slot, known (build-slot data; default
-- true), charges, open (the offer is open), gain (a card added to ownership), keepSource,
-- latch (default true), choice (a recorded offered key), noCapability (the client cannot
-- report slot data).
function S.IdQ(key)local id,q=key:match('^(%d+):(%d+)$');return tonumber(id),tonumber(q)end
function S.Shape()return dofile('tests/prototype/orb_loadout_hold_shape_support.lua')end
function S.Offer(F)
 local offer={}
 for key in F.receipt.offerKey:gmatch('(%d+:%d+):true')do offer[#offer+1]=key end
 return offer
end
function S.OwnedMap(F,H,gain,keepSource)
 local out={}
 local function add(key,n)
  local id,q=S.IdQ(key);local name=H.names[id];assert(name,'echo registered '..key)
  for _=1,n do out[name]=out[name] or {};table.insert(out[name],{spellId=id,quality=q}) end
 end
 for key,n in pairs(F.receipt.before)do
  if key==F.receipt.removed and not keepSource then n=n-1 end
  if n>0 then add(key,n) end
 end
 if gain then add(gain,1) end
 return out
end
function S.LockedMap(F,H)
 local out={}
 for key in F.receipt.lockedKey:gmatch('([^,=]+)=')do
  local id,q=S.IdQ(key);out[H.names[id]]={{spellId=id,quality=q}}
 end
 return out
end
function S.Slots()
 local E={{spellId=410001,quality=1,stacks=1}}
 return {[1]={name='One',verified=true,echoes=E},[101]={name='W-One',verified=false,echoes=E},[102]={name='W-Two',verified=false,echoes=E}}
end
function S.World(F,opts)
 ORB_SUPPORT_ECHOES=F.echoes
 local H,M,A,O=S.Fresh()
 ORB_SUPPORT_ECHOES=nil
 H.granted=S.OwnedMap(F,H,opts.gain,opts.keepSource);H.locked=S.LockedMap(F,H)
 O.charges=opts.charges
 H.perks.serverBuildSlots=opts.known~=false and S.Slots() or nil
 H.perks.serverActiveSlot=opts.slot
 if opts.noCapability then H.service.GetServerBuildSlots=nil end
 if opts.open then
  O.offer=true
  local cards={};for i,key in ipairs(S.Offer(F))do local id,q=S.IdQ(key);cards[i]={spellId=id,quality=q} end
  H.Board(cards)
 end
 H.Notify();A.Poll();H.Advance(.5)
 local receipt=H.Clone(F.receipt)
 receipt.guid=UnitGUID('player')
 if opts.latch==false then receipt.loadoutChanged=nil end
 if opts.choice then
  receipt.selectedKey=opts.choice;receipt.selectionAttempted=true;receipt.choiceObserved=true
  receipt.selectionStamp=receipt.beforeStamp;receipt.kind='TARGET'
 end
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 assert(owner.UpdateStateV1(function(s)s.orbRefinement={pending=receipt} end),'inject the saved receipt')
 M=S.Reload(H)
 return H,M,A,O
end
return S
