local H=dofile('tests/prototype/harness.lua');H.Boot()
local T=assert(Nexus.UserText);local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
check(T.Message('unsynced')=='Waiting for current Echo data from the server - automatic choices paused','ownership is not network Sync')
check(T.Message('Take wanted Echo (Pilot)')=='Take a needed Echo','planner provenance outside action')
check(T.Message('ROOT_MUTATION_PENDING'):find('in progress',1,true),'pending is not failure or success')
check(T.Message('MISSING_UNKNOWN_CODE'):find('Details: MISSING_UNKNOWN_CODE',1,true),'unknown raw code retained without forced readiness')
local d=T.Message('exact wishlist progress regressed 25 (gained 6, shed 31 exact stacks)')
check(d:find('25 fewer Wishlist copies',1,true) and d:find('31 fewer',1,true),'save comparison retains exact counts')
check(not d:find('shed',1,true),'no confusing shed wording in save comparison')
check(T.Annotation('returns later')=='Expected later from saved-build sequence','expectation distinct from guarantee')
check(T.Message('wishlist does not exactly match the verified active loadout; locked roles remain unknown.'):find('Choose this Wishlist',1,true),'role wait has actionable explanation')
check(T.Message('cleanup-only save added new excess/wrong-quality pollution'):find('Not saved:',1,true),'save refusal stays refusal')
Nexus.Panel.Show()
local text={};for _,f in ipairs(H.frames)do
 if f.GetText then text[#text+1]=f:GetText()end
 for _,r in ipairs(f.regions or {})do if r.GetText then text[#text+1]=r:GetText() end end
end
local all=table.concat(text,'\n')
check(all:find('EXTRA COPIES',1,true),'panel actual extra-copy heading')
check(not all:find('TO SHED',1,true),'old main heading absent')
SlashCmdList.NEXUS('help');check(NexusHelpWindow.body:GetText():find('experimental',1,true),'help identifies experimental build')
local auto=Nexus.RecomputeStats().autoEnabled
Nexus.Help.Show('rolling');check(NexusHelpWindow.body:GetText():find('Target 2/current 5 means 3 extras',1,true),'extra-copy definition in help')
check(Nexus.RecomputeStats().autoEnabled==auto,'wording/navigation does not enable automation')
Nexus.QuickStart.Show();local help,orbs
for _,f in ipairs(H.frames)do if f:GetParent()==NexusQuickStart then
 if f:GetText()=='Help / Getting Started'then help=f end
 if f:GetText()=='Orbs / Lost Memories'then orbs=f end
end end
check(help and orbs,'persistent help and Orb entry points in welcome')
help:Click();check(NexusHelpWindow:IsShown(),'real welcome help button')
-- Raw policy implementation is retained, not rewritten by display mapping.
local raw='tight horizon';check(T.Message(raw)=='Few selections remain' and raw=='tight horizon','mapping leaves source reason unchanged')
print('PASS terminology, state fidelity, counts and guide discoverability='..checks)
