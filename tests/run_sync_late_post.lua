-- Regression: build posted on A AFTER B's receive window closed must be
-- received when B syncs again (the "Fire Mage not received" live bug).
local H = dofile("tests/harness.lua")
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua")
local Codec, Sync = Nexus.Codec, Nexus.Sync
local clock = 1000; GetTime = function() return clock end
local wall = 50000; time = function() return wall end
UnitName = function() return "explore" end

local function deliver(chunks)
    for _,m in ipairs(chunks) do Sync.HandleIncoming(m.text, "explore") end
end
local function drain()
    for i=1,60 do clock=clock+0.2; Sync.OnUpdate(0.2) end
    local out={}; for _,m in ipairs(H.sentChatMessages) do out[#out+1]=m end
    H.sentChatMessages={}; return out
end

local rogueB = {id="r1",title="Rogue ST",author="explore",class="ROGUE",
    echoes={{spellId=200100,quality=3,stacks=1}},postedAt=50000,lastModified=50000,isMine=true}
local mageB  = {id="m1",title="Fire Mage",author="explore",class="MAGE",
    echoes={{spellId=200044,quality=3,stacks=1}},postedAt=50100,lastModified=50100,isMine=true}

-- 1. Both builds received in a single sync
NexusDB = { communityBuilds={}, syncTombstones={} }
Sync.Init(Codec, nil)
H.sentChatMessages={}
Sync.BroadcastBuild(rogueB); Sync.BroadcastBuild(mageB)
local allChunks = drain()
assert(#allChunks > 0, "no chunks produced")
Sync.RequestSync()
deliver(allChunks)
assert(NexusDB.communityBuilds["r1"], "rogue not received in single sync")
assert(NexusDB.communityBuilds["m1"], "mage not received in single sync")
print("both builds received in a single sync -- OK")

-- 2. Late post: mage posted after B's window closed, received on 2nd sync
NexusDB = { communityBuilds={}, syncTombstones={} }
Sync.Init(Codec, nil)

-- Rogue broadcast (will be "hot")
H.sentChatMessages={}
Sync.BroadcastBuild(rogueB)
local rogueChunks = drain()
-- B opens window, receives rogue
Sync.RequestSync()
deliver(rogueChunks)
assert(NexusDB.communityBuilds["r1"], "rogue not received on 1st sync")

-- Window expires
clock = clock + 70
assert(not Sync.IsReceiving(), "window should be closed")

-- Mage posted now. Valid direct-author updates are accepted even when the
-- manual-sync status window is closed; the window is diagnostics, not trust.
wall = wall + 100
H.sentChatMessages={}
Sync.BroadcastBuild(mageB)  -- marks mageB hot
local mageChunks = drain()
deliver(mageChunks)
assert(NexusDB.communityBuilds["m1"],
    "valid direct-author mage build was dropped outside the status window")

-- B presses Sync Now again
clock = clock + 10
Sync.RequestSync()
-- Simulate A answering: BroadcastMine includes hot mageB
NexusDB.communityBuilds["r1"] = rogueB  -- A has rogue in its DB
H.sentChatMessages={}
local n = Sync.BroadcastMine()
local answer2 = drain()
NexusDB.communityBuilds["r1"] = nil  -- restore B's view
assert(n >= 2, "BroadcastMine should include hot mage: got "..n)
print("BroadcastMine answers 2nd sync with "..n.." builds ("..#answer2.." chunks) -- OK")

deliver(answer2)
assert(NexusDB.communityBuilds["m1"],
    "mage must arrive on B's 2nd sync -- this was the live bug")
print("late direct-author build remains available across the next sync -- OK")

-- 3. Library hash: peer with same build set gets nothing
NexusDB = { communityBuilds={
    ["r1"]={id="r1",title="Rogue ST",author="explore",class="ROGUE",
            echoes={{spellId=200100,quality=3,stacks=1}},
            postedAt=50000,lastModified=50000,isMine=true}
}, syncTombstones={} }
Sync.Init(Codec, nil)
Sync.ClearLog()
H.sentChatMessages={}

-- Compute the same hash the answering side would compute
local function bucketHash(builds)
    local buckets={}; for i=1,8 do buckets[i]={} end
    local function bucket(id) local h=5381; for i=1,#id do h=((h*33)+id:byte(i))%2147483648 end; return (h%8)+1 end
    for id,b in pairs(builds) do local n=bucket(id); local complete=(type(b.echoes)=="table" and #b.echoes>0) and "F" or "S"; local fp=tostring(b.fingerprintHash or b.fingerprint or "0"); buckets[n][#buckets[n]+1]=id..":"..tostring(b.lastModified or b.postedAt or 0)..":"..complete..":"..fp end
    local out={}
    for n=1,8 do
        table.sort(buckets[n]); local h=5381
        for _,text in ipairs(buckets[n]) do for i=1,#text do h=((h*33)+text:byte(i))%2147483648 end end
        out[n]=#buckets[n]>0 and string.format("%x",h) or "0"
    end
    return table.concat(out,",")
end
-- Hash that matches A's isMine builds
local matchHash = bucketHash({ ["r1"]={lastModified=50000,
    fingerprint="200100x1",
    echoes={{spellId=200100,quality=3,stacks=1}}} })
Sync.HandleIncoming("WLRQ|peer2|"..matchHash.."|0|matching-state", "peer2")
for i=1,20 do Sync.OnUpdate(0.2) end
local skipped = Sync.Stats().skippedUpToDate or 0
assert(skipped > 0, "peer with matching hash should have been skipped, got "
    ..skipped.." expected="..matchHash.." legacy="..Sync.GetLegacyBuildHash())
print("peer already up to date gets nothing (library hash match) -- OK")
