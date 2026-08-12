local H = dofile("tests/harness.lua")
dofile("core/Codec.lua")
dofile("core/Sync.lua")

NexusDB = {
    communityBuilds={
        summary={
            id="summary", title="Needs loadout", author="Peer",
            lastModified=900, fingerprintHash="1", needsFullBuild=true,
        },
    },
}
Nexus.BuildCatalog.Init(NexusDB, Nexus.BundledBuilds)
Nexus.Sync.Init(Nexus.Codec, nil)

local _, requestWhy = Nexus.Sync.RequestLoadout("summary")
assert(requestWhy == "queued for background recovery",
    "test did not populate loadout request history")

local build = {
    id="broadcast-retention", title="Broadcast", author="Boganic",
    class="MAGE", postedAt=1000, lastModified=1000,
    echoes={{spellId=200100,quality=3,stacks=1}},
}
assert(Nexus.Sync.BroadcastBuild(build),
    "test did not populate recent/hot broadcast state")
local removed = Nexus.Sync.PruneTransientState(GetTime() + 1000)
assert(removed.requestedLoadouts >= 1
    and removed.recentBroadcasts >= 1 and removed.hotBuilds >= 1,
    "expired transient Sync state was not pruned")

local ok, why = Nexus.Sync.BroadcastBuild(build)
assert(ok and why ~= "duplicate suppressed",
    "expired broadcast-dedupe state still suppressed a new send")

time = function() return 2000000000 end
Nexus.BuildCatalog.Put({
    id="future-delete", title="Keep", author="Peer", class="MAGE",
    postedAt=1000, lastModified=1000,
    echoes={{spellId=200100,quality=3,stacks=1}},
})
assert(not Nexus.Sync.HandleIncoming(
    "WLRD|Peer|future-delete|999999999999|Peer", "Peer")
    and Nexus.BuildCatalog.Get("future-delete") ~= nil,
    "future-dated delete could poison retention watermarks")

print("transient Sync request and broadcast state is bounded -- OK")
