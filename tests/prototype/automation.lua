local H=dofile('tests/prototype/harness.lua');H.pendingRolls=2;H.Boot()
local A=Nexus.GameAdapter;local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
check(A.SetFirstLoadoutWishlistIdentity('EchoWeaver planned',{ {spellId=200001,quality=1,stacks=2} }),'set first run plan')
H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
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
print('PASS actual recommendation/automation and resource-safety checks='..checks)
