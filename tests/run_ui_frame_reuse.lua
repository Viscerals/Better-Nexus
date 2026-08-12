local H = dofile("tests/harness.lua")

local realCreateFrame = CreateFrame
local allocations = 0
CreateFrame = function(...)
    allocations = allocations + 1
    return realCreateFrame(...)
end

dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/CommunityBuilds.lua")

NexusDB = {}
H.DeliverSlots({
    [1]={slot=1,name="One",echoes={{spellId=200100,stacks=1}}},
    [2]={slot=2,name="Two",echoes={{spellId=200102,stacks=1}}},
    [100]={slot=100,name="Wishlist",echoes={{spellId=200104,stacks=1}}},
}, 1)
Nexus.CommunityBuilds.Init(Nexus.GameAdapter, Nexus.Model)
Nexus.CommunityBuilds.ShowPostBuild()

local popup = assert(_G.NexusPostPopup, "post popup was not created")
popup._postWishlistBtn.scripts.OnClick()
local afterFirstWishlist = allocations
for _ = 1, 25 do popup._postWishlistBtn.scripts.OnClick() end
assert(allocations == afterFirstWishlist,
    "wishlist dropdown allocated new frames on every refresh")

popup._postClassBtn.scripts.OnClick()
local afterFirstClass = allocations
for _ = 1, 25 do popup._postClassBtn.scripts.OnClick() end
assert(allocations == afterFirstClass,
    "class dropdown allocated new frames on every refresh")

dofile("ui/LogViewer.lua")
Nexus.LogViewer.Init(function() return "diagnostic text" end, function() return true end)
Nexus.LogViewer.Show("state")
H.Advance(0.1)
local afterFirstRepaint = allocations
for _ = 1, 25 do
    Nexus.LogViewer.Show("state")
    H.Advance(0.1)
end
assert(allocations == afterFirstRepaint,
    "LogViewer repaint allocated permanent one-shot frames")

print("dropdown and LogViewer delayed work reuse bounded frame pools -- OK")
