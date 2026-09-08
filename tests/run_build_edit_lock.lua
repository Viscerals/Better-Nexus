local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/CommunityBuilds.lua")

-- Legacy-to-bundle cutover (state machine line 374): durable fixture rows are
-- seeded as exact PR #68 legacy input before bootstrap, which admits them and
-- builds the first complete bundle. After occupancy a raw legacy write is not
-- an admission input at all.
NexusDB = { communityBuilds = {
 mine = {
  id="mine", title="Recorded", description="old", author="Owner", isMine=true,
  ownerKey="owner@ebonhold",realm="ebonhold",ownerVerified=true,
  echoes={{spellId=200050,stacks=1}}, class="MAGE"
 },
} }
H.wishlist = { name="New Echoes", class="MAGE", entries={{spellId=200100,stacks=1}} }
UnitName = function() return "Owner" end
local CB = Nexus.CommunityBuilds
CB.Init(Nexus.GameAdapter, Nexus.Model)
H.RebindCatalog()
Nexus.DpsCapture = {
 GetLeaderboard=function(id, category)
   if id == "mine" and category == "dummy" then return {{dps=24000000,player="Owner"}} end
   return {}
 end
}
local ok, err = CB.UpdateFromWishlist("mine")
assert(not ok and tostring(err):find("leaderboard record"), "recorded loadout must be immutable")
assert(H.DurableBuilds().mine.echoes[1].spellId == 200050, "locked Echo list changed")
local meta = CB.EditBuild("mine", "Renamed", "new")
assert(meta and H.DurableBuilds().mine.title == "Renamed", "owner metadata edit should remain available")
-- An occupied bundle is authoritative, so the foreign row is admitted through
-- the public write seam instead of a raw legacy write.
Nexus.BuildCatalog.Put({id="remote",title="Remote",author="Other",isMine=false,
 echoes={}}, {source="remote", sender="Other-Ebonhold"})
local remote = CB.EditBuild("remote", "Bad", "Bad")
assert(not remote, "non-owner edit must be rejected")
print("build edit lock OK")
