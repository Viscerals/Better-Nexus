local H = dofile("tests/harness.lua")
dofile("ui/CommunityBuilds.lua")

UnitName = function(unit) return unit == "player" and "Boganic" or nil end
GetNormalizedRealmName = function() return "Ebonhold" end
time = function() return 50000 end

local bundled = {
    schemaVersion=1, catalogVersion="runtime-cutover-1", sourceVersion="test",
    builds={
        collision={id="collision",title="Immutable bundled title",author="Remote",
            postedAt=100,lastModified=100,echoes={{spellId=200100,stacks=1}}},
        remote={id="remote",title="Bundled remote",author="Alice",
            postedAt=10,lastModified=10,echoes={{spellId=200101,stacks=1}}},
        bundledOnly={id="bundledOnly",title="Bundled only",author="Carol",
            postedAt=15,lastModified=15,echoes={{spellId=200104,stacks=1}}},
    },
}
Nexus.BundledBuilds = bundled
NexusDB = {
    communityBuilds={
        collision={id="collision",title="My personal override",author="Boganic",
            ownerKey="boganic@ebonhold",isMine=true,postedAt=1,lastModified=1,
            echoes={{spellId=200100,stacks=2}}},
        remote={id="remote",title="Newer remote overlay",author="Alice",
            postedAt=20,lastModified=20,echoes={{spellId=200101,stacks=2}}},
        personal={id="personal",title="Personal only",author="Boganic",
            ownerKey="boganic@ebonhold",isMine=true,postedAt=5,lastModified=5,
            echoes={{spellId=200102,stacks=1}}},
    },
    syncTombstones={},
}

local Catalog = Nexus.BuildCatalog
local Builds = Nexus.CommunityBuilds
Catalog.Init(NexusDB, bundled)
Builds.Init({}, {})
assert(NexusDB.communityBuilds.bundledOnly == nil,
    "startup identity repair copied a bundled-only row into the overlay")

local all = Catalog.All()
local count = 0
for _ in pairs(all) do count = count + 1 end
assert(count == 4 and Catalog.Count() == 4,
    "baseline, collision overlay, and personal row did not merge uniquely")
assert(all.collision.title == "My personal override"
    and all.remote.title == "Newer remote overlay"
    and all.personal.title == "Personal only",
    "merged runtime precedence is wrong")
assert(Builds.IsOwnBuild("collision") and Builds.IsOwnBuild("personal")
    and not Builds.IsOwnBuild("remote"),
    "catalog-backed ownership lookup changed")

local immutableTitle = bundled.builds.collision.title
local ok = Builds.EditBuild("collision", "Edited personal overlay", "Changed")
assert(ok and NexusDB.communityBuilds.collision.title == "Edited personal overlay",
    "catalog-backed edit did not update the overlay")
assert(bundled.builds.collision.title == immutableTitle,
    "catalog-backed edit mutated bundled data")

assert(Builds.DeleteBuild("collision"),
    "catalog-backed delete rejected an owned overlay")
assert(NexusDB.communityBuilds.collision == nil
    and NexusDB.syncTombstones.collision ~= nil
    and Catalog.Get("collision") == nil,
    "delete did not remove only the overlay and hide the bundled row")
assert(bundled.builds.collision.title == immutableTitle,
    "catalog-backed delete mutated bundled data")

local created = {id="created",title="Created locally",author="Boganic",
    ownerKey="boganic@ebonhold",isMine=true,postedAt=30,lastModified=30,
    echoes={{spellId=200103,stacks=1}}}
assert(Catalog.Put(created) and NexusDB.communityBuilds.created,
    "catalog-backed create did not enter the overlay")
created.title = "caller mutation"
assert(Catalog.Get("created").title == "Created locally",
    "catalog-backed create retained caller-owned data")

print("runtime catalog merge and overlay-only mutations -- OK")
