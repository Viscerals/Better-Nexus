-- Ordinary (non-final) synchronous search refusals must advance instead of
-- retrying the same client mutation forever.
local H=dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua")
dofile("logic/Strategy.lua"); dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua"); dofile("logic/Policy.lua")
dofile("core/Store.lua"); dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua"); dofile("ui/Panel.lua"); dofile("ui/JournalTab.lua")
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/WishlistModel.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

NexusDB={}
H.playerLevel=20
H.granted={}
H.wishlist={name="Goal",class="MAGE",echoes={{spellId=200100,quality=3,stacks=1}}}
H.FireEvent("ADDON_LOADED","Nexus")
H.FireEvent("PLAYER_ENTERING_WORLD")
SlashCmdList.NEXUS("auto")
H.DeliverSlots({
  [2]={slot=2,name="Snapshot",verified=true,echoes={{spellId=200200,quality=1,stacks=1}}},
  [3]={slot=3,name="Goal",verified=false,echoes={{spellId=200100,quality=3,stacks=1}}},
},2)
assert(Nexus.GameAdapter.SetLoadoutWishlist(2,3))
Nexus.GameAdapter.RequestGranted()
assert(Nexus.GameAdapter.Owned().synced,"owned-state fixture did not synchronize")

H.PushRunData({remainingBanishes=2,totalFreezes=0,usedFreezes=0,
  totalRerolls=2,usedRerolls=0})
H.refuseNextBanish=true
local banishBefore=H.banishAttempts or 0
local rerollsBefore=H.rerollCalls or 0
H.DeliverBoard({{spellId=200200,quality=1},{spellId=200202,quality=1}})
H.Advance(1.5)
assert((H.banishAttempts or 0)==banishBefore+1,
  "refused ordinary Banish was retried")
assert((H.rerollCalls or 0)==rerollsBefore+1,
  "refused ordinary Banish did not advance to Reroll")

H.DeliverBoard({{spellId=200202,quality=1},{spellId=200500,quality=1}})
H.PushRunData({remainingBanishes=0,totalFreezes=0,usedFreezes=0,
  totalRerolls=2,usedRerolls=0})
H.refuseNextReroll=true
local rerollBefore=H.rerollAttempts or 0
local selectsBefore=#H.selectCalls
H.Advance(1.5)
assert((H.rerollAttempts or 0)==rerollBefore+1,
  "refused ordinary Reroll was retried")
assert(#H.selectCalls==selectsBefore+1,
  "refused ordinary Reroll did not advance to the mandatory take")

print("ordinary Banish and Reroll refusal recovery -- OK")
