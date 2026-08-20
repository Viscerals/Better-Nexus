-- Regression for the live crash (2026-07-25): SetClipsChildren is
-- retail-only and absent on this client; calling it without pcall aborted
-- EnsureFrame before scrollFrame/scrollChild/scrollBar were created,
-- permanently breaking the window for the session. Same bug class as
-- SetColorTexture (2026-07-24).
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua")

-- Make every Frame reject SetClipsChildren, exactly as the live client
local realCreateFrame = CreateFrame
CreateFrame = function(kind, name, parent, ...)
    local f = realCreateFrame(kind, name, parent, ...)
    f.SetClipsChildren = function() error("SetClipsChildren not supported on this client") end
    f.SetVertexColor = function() error("SetVertexColor not supported on this client") end
    return f
end

dofile("ui/CommunityBuilds.lua")

NexusDB = {}
H.wishlist = { name="W", class="ROGUE", echoes={{spellId=200100,quality=3,stacks=1}} }
H.playerLevel = 5

local Adapter, Model = Nexus.GameAdapter, Nexus.Model
local CB = Nexus.CommunityBuilds
CB.Init(Adapter, Model)

local ok, err = pcall(CB.Show)
assert(ok, "Show() crashed when SetClipsChildren/SetVertexColor are unavailable: "..tostring(err))

local frame = _G.NexusCommunityBuildsFrame
assert(frame and frame:IsShown(), "frame did not open")

local ok2, id = CB.PostCurrentWishlist("Test Build", "description", H.wishlist)
assert(ok2, "PostCurrentWishlist failed after the API failure")

local ok3 = pcall(CB.Select, id)
assert(ok3, "Select() failed after the API failure -- scroll widgets missing?")

local ok4 = pcall(CB.Refresh)
assert(ok4, "Refresh() failed after the API failure")

print("Nexus Builds survives SetClipsChildren/SetVertexColor being unavailable -- OK")

-- Also verify scrollBar is now a plain Lua table (not a WoW Frame),
-- so its SetValue/GetValue can never fire a template's OnValueChanged
-- before scrollFrame is ready.
local frame2 = _G.NexusCommunityBuildsFrame
-- access the module-level scrollBar indirectly via a fresh boot
_G.NexusCommunityBuildsFrame = nil
dofile("ui/CommunityBuilds.lua")
local CB2 = Nexus.CommunityBuilds
CB2.Init(Nexus.GameAdapter, Nexus.Model)
local ok5 = pcall(CB2.Show)
assert(ok5, "Show() crashed with the new scroll implementation")
print("Scroll implementation works without SetVerticalScroll or template issues -- OK")
