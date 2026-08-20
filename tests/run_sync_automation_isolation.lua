-- Stage 18.1 negative control: accepted Nexus Sync/chat and view revisions
-- must not become automation repair triggers.
local F = dofile("tests/automation_live_fixture.lua")
local H = F.H

dofile("core/Codec.lua")
dofile("core/SyncProtocol.lua")
dofile("core/SyncTransport.lua")
dofile("core/SyncCompatibility.lua")
dofile("core/SyncReconciler.lua")
dofile("core/SyncInbound.lua")
dofile("core/SyncDiagnostics.lua")
dofile("core/SyncSession.lua")
dofile("core/Sync.lua")

local Sync = assert(Nexus.Sync)
local Revisions = assert(Nexus.Revisions)
Sync.Init(Nexus.Codec, Nexus.GameAdapter)
assert(Sync.IsConnected(), "real Sync facade failed to initialize")

local before = F.Snapshot()
local revisionBefore = Revisions.Snapshot()
local accepted = 0
for index = 1, 50 do
    local peer = "Bob"
    if Sync.HandleIncoming("WLNP|" .. peer .. "|1.20.0-beta.1", peer) then
        accepted = accepted + 1
    end
    assert(Revisions.Advance(Revisions.SYNC_CHANGED,
        {scope="status",reason="accepted-sync-negative-control"}))
    assert(Revisions.Advance(Revisions.BUILD_LIBRARY_CHANGED,
        {scope="community",reason="accepted-sync-negative-control"}))
    assert(Revisions.Advance(Revisions.DPS_CHANGED,
        {scope="all",reason="accepted-sync-negative-control"}))
    Sync.OnUpdate(0.2)
    H.Advance(0.2, 0.2)
end
local after = F.Snapshot()
local revisionAfter = Revisions.Snapshot()

local function Delta(key) return F.Delta(after, before, key) end
assert(accepted == 50 and Sync.GetPeerInfo("Bob") ~= nil,
    "repeated presence traffic was not accepted by the real Sync facade")
assert((revisionAfter[Revisions.SYNC_CHANGED] or 0)
        - (revisionBefore[Revisions.SYNC_CHANGED] or 0) >= 50,
    "accepted Sync traffic did not advance SYNC_CHANGED")
assert((revisionAfter[Revisions.BUILD_LIBRARY_CHANGED] or 0)
        - (revisionBefore[Revisions.BUILD_LIBRARY_CHANGED] or 0) == 50
    and (revisionAfter[Revisions.DPS_CHANGED] or 0)
        - (revisionBefore[Revisions.DPS_CHANGED] or 0) == 50,
    "Community/DPS negative-control revisions were not exercised exactly")

local echoScans = (after.echoReconcile.scans or 0)
    - (before.echoReconcile.scans or 0)
print(string.format(
    "sync automation isolation: accepted=%d syncRevision=%d communityRevision=%d dpsRevision=%d polls=%d checks=%d echoScans=%d repairs=%d full=%d policy=%d renders=%d associations=%d uploads=%d syncBuildUploads=%d mutations=%d",
    accepted,
    (revisionAfter[Revisions.SYNC_CHANGED] or 0)
        - (revisionBefore[Revisions.SYNC_CHANGED] or 0),
    (revisionAfter[Revisions.BUILD_LIBRARY_CHANGED] or 0)
        - (revisionBefore[Revisions.BUILD_LIBRARY_CHANGED] or 0),
    (revisionAfter[Revisions.DPS_CHANGED] or 0)
        - (revisionBefore[Revisions.DPS_CHANGED] or 0),
    Delta("polls"),Delta("fallbackChecks"),echoScans,Delta("fallbackRepairs"),
    Delta("fullSteps"),Delta("policy"),Delta("panelRenders"),
    Delta("associationRefreshes"),Delta("uploads"),Delta("syncBuildUploads"),
    Delta("characterMutations")))

assert(Delta("polls") == 50,
    "direct 0.2-second Poll cadence changed during Sync traffic")
assert(echoScans == Delta("fallbackChecks"),
    "ordinary direct Poll scanned complete Echo state")
assert(Delta("fallbackRepairs") == 0 and Delta("fullSteps") == 0
    and Delta("policy") == 0 and Delta("panelRenders") == 0
    and Delta("associationRefreshes") == 0 and Delta("uploads") == 0
    and Delta("syncBuildUploads") == 0 and Delta("characterMutations") == 0,
    "accepted Sync/chat or Community/DPS activity triggered automation work")

print("accepted Sync/chat and Community/DPS activity stay isolated from automation -- OK")
