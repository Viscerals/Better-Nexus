-- Account-wide Saved Build references remain realm-safe and read-only when
-- viewed from a different character identity.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/CommunityBuilds.lua")

local realm = "RealmOne"
UnitName = function() return "SameName" end
UnitClass = function() return "Mage", "MAGE" end
GetNormalizedRealmName = function() return realm end
time = function() return 50000 end

NexusDB = {}
Nexus.Store.Init()
local Adapter, Builds = Nexus.GameAdapter, Nexus.CommunityBuilds
Builds.Init(Adapter, Nexus.Model)
local realCatalogAll = Nexus.BuildCatalog.All
local fullCatalogCopies = 0
Nexus.BuildCatalog.All = function(...)
    fullCatalogCopies = fullCatalogCopies + 1
    return realCatalogAll(...)
end

-- Same-author records are common after syncing multiple loadouts. They must
-- stay as lightweight summaries unless a title or persisted link makes one a
-- plausible match for the partial Saved Build returned by the server.
for index = 1, 40 do
    local echoes = {}
    for echoIndex = 1, 79 do
        echoes[#echoes + 1] = {
            spellId = 800000 + index * 100 + echoIndex,
            stacks = 1,
        }
    end
    assert(Nexus.BuildCatalog.Put({
        id = "unrelated-same-author-" .. index,
        title = "Unrelated build " .. index,
        author = "SameName",
        ownerKey = "samename@realmone",
        class = "MAGE",
        echoes = echoes,
    }))
end

H.DeliverSlots({
    [1]={slot=1,name="Realm One build",verified=true,
        echoes={{spellId=200100,stacks=1}}},
}, 1)
Builds.Show()

local firstId = "saved-samename_realmone-1"
local first = NexusDB.communityBuilds[firstId]
assert(first and first.ownerKey == "samename@realmone"
    and Builds.IsOwnBuild(first) and Builds.IsAccountBuild(first),
    "first realm Saved Build was not imported with a realm-safe identity")

realm = "RealmTwo"
UnitClass = function() return "Warrior", "WARRIOR" end
Nexus.Store.RegisterCurrentCharacter()
H.DeliverSlots({
    [1]={slot=1,name="Realm Two build",verified=true,
        echoes={{spellId=200104,stacks=2}}},
}, 1)
Builds.Show()

local secondId = "saved-samename_realmtwo-1"
local second = NexusDB.communityBuilds[secondId]
assert(second and second.ownerKey == "samename@realmtwo"
    and firstId ~= secondId and NexusDB.communityBuilds[firstId],
    "same-named characters on different realms collided or erased a reference")
assert(not Builds.IsOwnBuild(first) and Builds.IsAccountBuild(first),
    "offline-character build was not exposed as a read-only account reference")
local ok, why = Builds.EditBuild(firstId, "wrong character edit", "blocked")
assert(not ok and why == "not your build",
    "offline-character account reference became editable")
assert(Builds.IsOwnBuild(second) and Builds.IsAccountBuild(second),
    "current character's Saved Build lost normal ownership")
assert(fullCatalogCopies == 0,
    "opening Builds copied the complete catalog while importing Saved Builds")
assert(Builds.VirtualStats().relatedHydrations == 0,
    "opening Builds hydrated unrelated same-author loadouts")

print("account-wide realm-safe Saved Build references -- OK")
