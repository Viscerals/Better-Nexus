local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("data/BundledBuilds.lua")
dofile("core/Store.lua")
local bundle = Nexus.BundledBuilds
assert(type(bundle) == "table" and bundle.schemaVersion == 1)
assert(next(bundle.builds) == nil, "retired builds still ship in the runtime catalog")
assert(bundle.generation.included == 0 and bundle.generation.sourceRows == 0
    and bundle.generation.echoRows == 0, "empty catalog metadata is false")
NexusDB = {settings={},chars={},communityBuilds={},syncTombstones={},dpsCapture={}}
H.BootstrapStore()
assert(Nexus.BuildCatalog.RootState().state == "ROOT_ADMITTED")
assert(Nexus.BuildCatalog.Status().bundledCount == 0 and Nexus.BuildCatalog.Count() == 0,
    "fresh profile loaded retired builds")

local owner = (UnitName("player")):lower() .. "@" .. (GetNormalizedRealmName()):lower()
local personal = {id="kept-personal",title="Keep this saved build",author=UnitName("player"),
    class="MAGE",ownerKey=owner,ownerVerified=true,isMine=true,
    echoes={{spellId=200001,quality=1,stacks=1}},postedAt=1,lastModified=1,
    futureData={keep="unchanged"}}
local char = {futureWishlist={name="Keep my wishlist",echoes={200001}}}
local dps = {futureDps={keep=123}}
NexusDB = {settings={},chars={[owner]=char},communityBuilds={[personal.id]=personal},
    syncTombstones={},dpsCapture=dps,futureRoot={keep=true}}
H.BootstrapStore()
local found = Nexus.BuildCatalog.Get(personal.id)
assert(found and found.title == personal.title, "empty seed hid a valid personal build")
assert(NexusDB.communityBuilds[personal.id] == personal and personal.futureData.keep == "unchanged",
    "catalog retirement modified preserved saved input")
assert(NexusDB.chars[owner] == char and char.futureWishlist.name == "Keep my wishlist"
    and NexusDB.dpsCapture == dps and dps.futureDps.keep == 123 and NexusDB.futureRoot.keep,
    "catalog retirement changed unrelated profile data")
assert(Nexus.BuildCatalog.Status().bundledCount == 0)
print("bundled catalog retirement: fresh and existing profile preservation PASS")
