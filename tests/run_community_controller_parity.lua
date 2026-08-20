-- Frame-free Community controller transition, authority, and retry parity.
local H = dofile("tests/harness.lua")

UnitName = function() return "Owner" end
GetNormalizedRealmName = function() return "Ebonhold" end
time = function() return 5000 end

local records = {
    owned={
        id="owned",title="Owned",description="before",author="Owner",
        ownerKey="owner@ebonhold",class="MAGE",isMine=true,
        postedAt=1,lastModified=1,
        echoes={{spellId=200100,quality=3,stacks=1}},
    },
    remote={
        id="remote",title="Remote",author="Peer",
        ownerKey="peer@ebonhold",class="MAGE",
        postedAt=1,lastModified=1,
        echoes={{spellId=200101,quality=2,stacks=1}},
    },
    pending={
        id="pending",title="Pending",author="Peer",
        ownerKey="peer@ebonhold",class="MAGE",
        postedAt=1,lastModified=1,echoes={},
    },
}
local tombstones, removals, puts = {}, {}, 0
Nexus.BuildCatalog = {
    Get=function(id)
        return records[id]
    end,
    Put=function(build)
        puts = puts + 1
        records[build.id] = build
        return true
    end,
    All=function()
        return records
    end,
    RemoveOverlay=function(id)
        removals[#removals + 1] = id
        records[id] = nil
        return true
    end,
    SetTombstone=function(id, tombstone)
        tombstones[id] = tombstone
        return true
    end,
}
local broadcasts, broadcastOptions, deletes, requests, syncRequests =
    {}, {}, {}, {}, 0
local shareStatuses = {}
local function CopyScalars(value)
    local copy = {}
    for key, field in pairs(type(value) == "table" and value or {}) do
        local kind = type(field)
        if kind == "string" or kind == "number" or kind == "boolean" then
            copy[key] = field
        end
    end
    return copy
end
Nexus.Sync = {
    BroadcastBuildSummary=function(build, options)
        broadcasts[#broadcasts + 1] = build.id
        broadcastOptions[#broadcastOptions + 1] = options
        if type(options) == "table" and options.retryOnFull == true then
            local prior = shareStatuses[build.id]
            local status = {
                kind="share",id=build.id,
                version=tostring(tonumber(build.lastModified)
                    or tonumber(build.postedAt) or 0),
                operationKey="share:" .. build.id,
                generation=(prior and prior.generation or 0) + 1,
                attempt=(prior and prior.attempt or 0) + 1,
                outcome="queued",terminal=false,queueAdmitted=true,
                retryPending=false,accepted=false,
                confirmation="unavailable",
            }
            shareStatuses[build.id] = status
            return true, "queued", CopyScalars(status)
        end
        return true
    end,
    GetShareStatus=function(id)
        return CopyScalars(shareStatuses[id])
    end,
    BroadcastDelete=function(build)
        deletes[#deletes + 1] = build.id
        return true
    end,
    RequestLoadout=function(id)
        requests[#requests + 1] = id
        return true
    end,
    RequestSync=function()
        syncRequests = syncRequests + 1
        return true
    end,
}
Nexus.DpsCapture = {
    GetEchoKey=function(echoes)
        local parts = {}
        for _, echo in ipairs(echoes or {}) do
            parts[#parts + 1] = tostring(echo.spellId)
                .. "x" .. tostring(echo.stacks or echo.count or 1)
        end
        table.sort(parts)
        return table.concat(parts, ",")
    end,
    GetEchoHash=function(echoes)
        return "hash:" .. tostring(#(echoes or {}))
    end,
    GetLeaderboard=function()
        return {}
    end,
    BroadcastBestForBuild=function() end,
}

local filters = {scope="all",sortMode="dps",future="keep"}
local notices, refreshes = {}, 0
local uploadMode, uploadCalls, retryEchoes, retryTitle, retrySpellId =
    "success", 0, nil, nil, nil
local Adapter = {
    Catalog=function()
        return {rows={
            [200100]={classMask=128},
            [200101]={classMask=128},
        }}
    end,
    Wishlist=function()
        return {name="Active",class="MAGE",entries={
            {spellId=200102,quality=2,stacks=1},
        }}
    end,
    LockedOwned=function()
        return {bySpell={}}
    end,
    UploadWishlist=function(slot, title, echoes)
        uploadCalls = uploadCalls + 1
        assert(slot == 0, "controller changed lock-in destination slot")
        if retryEchoes then
            assert(echoes == retryEchoes and title == retryTitle,
                "retry replaced the immutable title/Echo payload")
            assert(echoes[1].spellId == retrySpellId,
                "popup mutation changed the pending retry payload")
        else
            retryEchoes, retryTitle = echoes, title
            retrySpellId = echoes[1].spellId
        end
        if uploadMode == "spacing" then return false, "spacing" end
        if uploadMode == "refused" then return false, "refused" end
        return true
    end,
}

local factory = assert(Nexus.CommunityInternals
    and Nexus.CommunityInternals.Controller)
local controller = factory.New({
    filterSettings=function() return filters end,
    notify=function(message) notices[#notices + 1] = message end,
    refresh=function() refreshes = refreshes + 1 end,
})
controller.BindAdapter(Adapter)

-- Filters, selection, and popup drafts are controller-owned and defensive.
local snapshot = controller.Filters()
snapshot.scope, snapshot.future = "mine", "changed"
assert(filters.scope == "all" and filters.future == "keep",
    "filter snapshot leaked controller persistence state")
controller.SetFilter("scope", "mine")
assert(filters.scope == "mine", "validated filter intent was not persisted")
assert(not controller.SetFilter("scope", "future")
    and not controller.SetFilter("future", "replace")
    and filters.scope == "mine" and filters.future == "keep",
    "invalid filter intent overwrote persisted or future state")
controller.Select("owned")
assert(controller.SelectedId() == "owned"
    and controller.SelectedBuild() == records.owned,
    "stable-ID selection did not resolve through the catalog owner")
local syncOk, _, syncAvailable = controller.RequestSync()
assert(syncOk and syncAvailable and syncRequests == 1,
    "renderer-facing Sync intention bypassed the Community controller")
local savedSync = Nexus.Sync
Nexus.Sync = nil
local absentOk, absentErr, absentAvailable = controller.RequestSync()
Nexus.Sync = savedSync
assert(absentOk == nil and absentErr == nil and absentAvailable == false,
    "pre-initialization Sync intention lost its silent no-op fallback")
controller.BeginPostDraft({slot=4,name="Draft"}, "MAGE")
local postWishlist, postClass = controller.PostDraft()
assert(postWishlist.slot == 4 and postClass == "MAGE",
    "post popup draft was not retained")
controller.BeginEditDraft("owned", "Next", "Description", nil)
assert(controller.EditDraft().id == "owned",
    "edit popup draft was not retained")

-- Owner validation and BuildCatalog/Sync admission order stay unchanged.
local ok = controller.EditBuild("owned", "Renamed", "after")
assert(ok and records.owned.title == "Renamed"
    and broadcasts[#broadcasts] == "owned" and puts > 0,
    "owned edit did not admit before broadcasting")
assert(not controller.EditBuild("remote", "Forged", "bad")
    and records.remote.title == "Remote",
    "non-owner edit reached catalog mutation")

-- A failed immutable Share can be retried only through an explicit controller
-- action. The same ID/version is retained, the returned receipt is defensive,
-- and a second click while active is idempotently refused.
shareStatuses.owned = {
    kind="share",id="owned",
    version=tostring(records.owned.lastModified),
    operationKey="share:owned",generation=1,attempt=1,
    outcome="expired",terminal=true,queueAdmitted=true,
    accepted=false,confirmation="unavailable",
}
local failedShareVersion = shareStatuses.owned.version
local failedShareStamp = records.owned.lastModified
assert(controller.CanRetryShare("owned") == true,
    "terminal owned Share did not expose the explicit retry action")
local beforeShareRetry = #broadcasts
local retryStarted, retryWhy, retryReceipt = controller.RetryShare("owned")
assert(retryStarted and retryWhy == "queued"
    and #broadcasts == beforeShareRetry + 1
    and broadcasts[#broadcasts] == "owned"
    and broadcastOptions[#broadcastOptions].retryOnFull == true
    and retryReceipt.id == "owned" and retryReceipt.attempt == 2
    and retryReceipt.version == failedShareVersion
    and records.owned.lastModified == failedShareStamp
    and retryReceipt.queueAdmitted == true,
    "explicit Share retry changed identity or bypassed bounded Sync admission")
retryReceipt.outcome = "corrupted"
assert(Nexus.Sync.GetShareStatus("owned").outcome == "queued"
    and controller.CanRetryShare("owned") == false
    and controller.RetryShare("owned") == false
    and #broadcasts == beforeShareRetry + 1,
    "active Share retry was duplicated or its receipt leaked mutation")
shareStatuses.owned = {
    kind="share",id="owned",version="stale",operationKey="share:owned",
    generation=3,attempt=3,outcome="dropped",terminal=true,
}
assert(controller.CanRetryShare("owned") == false,
    "changed build version reused a stale terminal Share identity")
controller.Select("pending")
assert(controller.PrepareLockInSelected() == nil
    and requests[#requests] == "pending",
    "incomplete selection did not emit one explicit loadout request")

-- Initial upload plus at most 12 retries; spacing never replaces payload or
-- refreshes the pending lifetime. The thirteenth pump expires without upload.
controller.Select("owned")
local payload = assert(controller.PrepareLockInSelected())
uploadMode, uploadCalls, retryEchoes, retryTitle, retrySpellId =
    "spacing", 0, nil, nil, nil
assert(not controller.AcceptLockIn(payload)
    and controller.IsLockInPending(),
    "initial spacing did not create one pending retry")
payload.echoes[1].spellId = 999999
for retry = 1, 12 do
    controller._PumpPendingLockIn()
    local pending = assert(controller.PendingLockIn())
    assert(pending.tries == retry and pending.echoCount == 1,
        "retry counter or immutable payload changed")
end
local beforeExpiry = uploadCalls
local expired, reason = controller._PumpPendingLockIn()
assert(not expired and reason == "expired"
    and not controller.IsLockInPending()
    and beforeExpiry == 13 and uploadCalls == 13,
    "bounded expiry made a thirteenth retry upload")
assert(notices[#notices]:find(
        "the server is busy -- try again in a moment", 1, true),
    "expiry lost the established friendly spacing message")

-- Capacity recovery still succeeds exactly once and clears the same record.
payload.echoes[1].spellId = 200100
uploadMode, uploadCalls, retryEchoes, retryTitle, retrySpellId =
    "spacing", 0, nil, nil, nil
assert(not controller.AcceptLockIn(payload))
uploadMode = "success"
assert(controller._PumpPendingLockIn()
    and not controller.IsLockInPending()
    and uploadCalls == 2 and refreshes == 1,
    "pending retry did not resume exactly once after spacing cleared")

-- A new explicit confirmation may supersede old pending work, while the
-- automatic retry continues to preserve the replacement record exactly.
uploadMode, uploadCalls, retryEchoes, retryTitle, retrySpellId =
    "spacing", 0, nil, nil, nil
assert(not controller.AcceptLockIn(payload))
local replacement = {
    title="Replacement",
    echoes={{spellId=200101,quality=2,stacks=1}},
}
retryEchoes, retryTitle, retrySpellId = nil, nil, nil
assert(not controller.AcceptLockIn(replacement))
local replaced = assert(controller.PendingLockIn())
assert(replaced.title == "Replacement" and replaced.tries == 0,
    "explicit confirmation did not supersede older pending work")
uploadMode = "success"
assert(controller._PumpPendingLockIn()
    and uploadCalls == 3 and not controller.IsLockInPending(),
    "replacement pending payload did not resume exactly once")

-- Refusals remain immediate failures and never create durable pending work.
uploadMode, uploadCalls, retryEchoes, retryTitle, retrySpellId =
    "refused", 0, nil, nil, nil
assert(not controller.AcceptLockIn(payload)
    and not controller.IsLockInPending() and uploadCalls == 1,
    "non-spacing refusal acquired retry lifetime")
local callsBeforeMalformed = uploadCalls
assert(not controller.AcceptLockIn({
        title="Malformed",echoes={"not-an-echo"},
    })
    and uploadCalls == callsBeforeMalformed,
    "malformed lock-in payload reached the adapter")

-- Deletion preserves owner broadcast, tombstone, overlay, and selection order.
controller.Select("owned")
assert(controller.DeleteBuild("owned")
    and deletes[#deletes] == "owned"
    and tombstones.owned and removals[#removals] == "owned"
    and controller.SelectedId() == nil,
    "owned deletion lost broadcast/tombstone/selection semantics")
assert(not controller.DeleteBuild("remote")
    and records.remote,
    "non-owner deletion reached catalog mutation")

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local value = handle:read("*a")
    handle:close()
    return value
end
local controllerSource = Read("core/CommunityController.lua")
for _, forbidden in ipairs({
    "CreateFrame", "SetScript", "StaticPopup_Show", "UIPanelButtonTemplate",
}) do
    assert(not controllerSource:find(forbidden, 1, true),
        "frame-free controller acquired rendering authority: " .. forbidden)
end
local rendererSource = Read("ui/CommunityRenderer.lua")
assert(rendererSource:find('SetText("Retry Share")', 1, true)
    and rendererSource:find("controller.RetryShare(selected)", 1, true),
    "terminal Share retry is not reachable from the owned-build detail action")
local uiSource = Read("ui/CommunityBuilds.lua")
for _, forbidden in ipairs({
    "BuildCatalog.Put", "BroadcastDelete", "UploadWishlist",
    "SetTombstone(", "local function TryLockIn",
}) do
    assert(not uiSource:find(forbidden, 1, true),
        "Community rendering retained mutation authority: " .. forbidden)
end

print(string.format(
    "community controller: retries=%d filters=%s requests=%d frames=0 -- OK",
    beforeExpiry - 1, filters.scope, #requests))
