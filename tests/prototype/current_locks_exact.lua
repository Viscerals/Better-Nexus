-- Native-reported untagged 85-entry import, exercised through actual adapter,
-- editor, button callbacks, controller, Store and mock Ebonhold services.
-- Test inputs contain no player SavedVariables. No live game/network access.
local H=dofile('tests/prototype/harness.lua')
local raw=[==[EBH1:200050.2.1,200052.2.1,200063.2.1,200205.2.1,200227.2.1,200228.3.1,200230.3.1,200232.3.1,200236.3.1,200237.3.1,200240.3.1,200259.3.1,200270.3.1,200429.0.1,200494.2.1,200495.2.1,200496.2.1,200583.3.1,200585.3.1,200592.3.1,200597.3.1,200601.3.1,200606.3.1,200621.3.1,200627.3.1,200632.3.1,200635.3.1,200639.3.1,200678.2.1,200679.2.1,200690.2.1,200693.3.1,200695.3.1,200722.2.1,200726.2.1,200728.2.1,200730.2.1,200734.2.1,200738.2.1,200742.2.1,200756.3.1,200780.3.1,200798.3.1,200808.3.1,200838.3.1,200844.3.1,200852.2.1,200882.2.1,200886.2.1,200888.2.1,200894.2.1,200896.2.1,200898.2.1,200900.2.1,200950.2.1,200956.3.1,200960.3.1,200962.3.1,201250.2.1,201254.3.1,201256.3.1,201258.3.1,201262.3.1,201270.3.1,201276.3.1,201298.3.1,201304.3.1,201308.3.1,201312.3.1,201324.3.1,201332.3.1,201336.3.1,201340.3.1,201356.3.1,201360.3.1,201366.3.1,201370.3.1,201378.3.1,201382.3.1,201388.3.1,201398.3.1,201406.3.1,201410.3.1,201424.3.1,201428.3.1:MAGE:250 mio]==]
local lockIds={201262,201270,201250,200690,200756,200882}
local names={[200690]="Reaper's Reprieve",[200756]="Overtime Conversion",[200882]="Arcane Density",
 [201250]="Echoing Tides",[201262]="Accelerated Decay",[201270]="Armor Mastery"}
local entries={}
for id,q,copies in raw:match('^EBH1:([^:]+)'):gmatch('(%d+)%.(%d+)%.(%d+)')do
 id,q,copies=tonumber(id),tonumber(q),tonumber(copies)
 H.AddEcho(id,names[id] or ('Target '..id),q,10)
 entries[#entries+1]={spellId=id,quality=q,stacks=copies,locked=false}
end
H.AddEcho(299998,'Different current build',1,10)
H.perks.serverBuildSlots={
 [1]={name='Current loadout',verified=true,echoes={{spellId=299998,quality=1,stacks=1,locked=false}}},
 [101]={name='250 mio untagged',verified=false,echoes=H.Clone(entries)},
}
H.perks.serverActiveSlot=1
for _,id in ipairs(lockIds)do H.locked[#H.locked+1]={spellId=id,stacks=1}end
H.Boot()
local A,E=Nexus.GameAdapter,Nexus.WishlistEditor
local function plan()
 for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==101 then return c end end
end
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local source=H.Clone(H.perks.serverBuildSlots[101].echoes)
check(E.OpenForWishlist(plan(),1),'actual 250 mio existing-build path opens')
check(not NexusWishlistRolePicker or not NexusWishlistRolePicker:IsShown(),'exact user input bypasses role dialog')
local c=plan();local count,ordinary,locked=0,0,0;local locks={}
for _,e in ipairs(c.echoes)do count=count+e.stacks;if e.locked then locked=locked+e.stacks;locks[e.spellId]=e.stacks else ordinary=ordinary+e.stacks end end
check(count==85 and ordinary==79 and locked==6,'exact original 85 retained as 79+6')
for _,id in ipairs(lockIds)do check(locks[id]==1,'reported current lock retained '..id) end
check(E.ResolveAndAssignWishlist(c,1),'assign succeeds without equipped ordinary equality')
E.ImportEBH1String(raw,'250 mio untagged direct')
check(E.DebugPendingCount()==79 and not (NexusWishlistRolePicker and NexusWishlistRolePicker:IsShown()),'raw unmarked import succeeds directly')
check(#H.actions==0,'open, assignment and draft import spend no resources or change locks')
print('PASS exact supplied 250-mio85 input, six current locks, physical-order variation and raw import checks='..checks)
