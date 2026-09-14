-- Dedicated leaderboard is separate from Builds and renders dense ranked rows.
local H=dofile("tests/harness.lua")
-- Capture only WoW frame boundaries; all Sync owners and button callbacks below
-- are the shipped implementations.
local syncControls, syncRegions = {}, {}
local createFrame = CreateFrame
CreateFrame = function(kind, name, parent, template)
    local widget = createFrame(kind, name, parent, template)
    if kind == "Button" then
        syncControls[#syncControls + 1] = widget
    end
    if name == "NexusLeaderboardFrame" then
        local createFontString = widget.CreateFontString
        widget.CreateFontString = function(self, ...)
            local region = createFontString(self, ...)
            syncRegions[#syncRegions + 1] = region
            return region
        end
    end
    return widget
end
dofile("core/Codec.lua"); dofile("core/SyncProtocol.lua"); dofile("core/SyncTransport.lua"); dofile("core/SyncCompatibility.lua"); dofile("core/SyncReconciler.lua"); dofile("core/SyncInbound.lua"); dofile("core/SyncDiagnostics.lua"); dofile("core/SyncSession.lua"); dofile("core/Sync.lua"); dofile("core/DpsCapture.lua")
dofile("data/DefaultProfile.lua"); dofile("logic/Model.lua"); dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua"); dofile("logic/Policy.lua"); dofile("core/Store.lua")
dofile("core/GameAdapter.lua"); dofile("ui/CommunityBuilds.lua"); dofile("ui/Leaderboard.lua")
UnitName=function(unit) return unit=="player" and "Viewer" or nil end
UnitClass=function() return "Mage","MAGE" end
NexusDB={communityBuilds={},syncTombstones={},dpsCapture={}}
local DPS=Nexus.DpsCapture
-- MASTER-RC-001 (architecture 1207-1211): Sync.Init and DpsCapture.Init no
-- longer admit the catalog root as a side effect. The same admission is
-- performed explicitly here, before the call, because the removed side
-- effect ran inside Init ahead of Init's own dependent steps. No assertion
-- or expected value in this fixture is changed.
H.AdmitCatalogV1(NexusDB)
DPS.Init({}, {BroadcastBuild=function() return true end})
local a={{spellId=200001,stacks=2},{spellId=200002,stacks=1}}
local b={{spellId=200010,stacks=1},{spellId=200011,stacks=3}}
assert(DPS.ReceiveRecord({v=4,f=DPS.GetEchoKey(a),e=a,c="dummy",d=24000000,u=65,t=100,p="Alpha",k="MAGE",l=80}))
assert(DPS.ReceiveRecord({v=4,f=DPS.GetEchoKey(b),e=b,c="dummy",d=28000000,u=65,t=101,p="Bravo",k="MAGE",l=80}))
Nexus.CommunityBuilds.Init(Nexus.GameAdapter,Nexus.Model)
Nexus.Leaderboard.Init(Nexus.GameAdapter)
Nexus.Leaderboard.Show("dummy")
assert(H.frames.NexusLeaderboardFrame and H.frames.NexusLeaderboardFrame:IsShown(),"leaderboard window did not open")
-- Refreshing a selected record must use WoW 3.3.5 Button:Enable/Disable, not modern SetEnabled.
Nexus.Leaderboard.Refresh()
assert(not H.frames.NexusCommunityBuildsFrame or not H.frames.NexusCommunityBuildsFrame:IsShown(),"build browser should not be required for leaderboard")
Nexus.CommunityBuilds.SetViewMode("lk")
assert(Nexus.Leaderboard.IsShown(),"legacy leaderboard route did not open dedicated window")

-- The projection-free Combined compatibility path carries the same public
-- identity presentation and deterministic equal-score tie used by the normal
-- ViewProjections owner.
local function Upvalue(fn, wanted)
    for index=1,40 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
end
local rowsReader = assert(Upvalue(Nexus.Leaderboard.RefreshData, "Rows"),
    "projection-free Rows reader was not inspectable")
local combinedReader = assert(Upvalue(rowsReader, "CombinedRows"),
    "projection-free Combined reader was not inspectable")
local function PublicRow(ownerKey, category, spellId)
    return {
        player="Twin",displayPlayer="Twin-"..ownerKey:match("@(.+)$"),
        publicIdentityKey="verified:"..ownerKey,
        publicIdentityVerified=true,ownerKey=ownerKey,ownerVerified=true,
        realm=ownerKey:match("@(.+)$"),category=category,
        dps=20000000,ts=200,duration=65,level=80,class="MAGE",
        fingerprint=tostring(spellId).."x1",
        echoes={{spellId=spellId,count=1}},protocolVersion=7,
    }
end
local fallback = {dummy={},lk={}}
for _, realm in ipairs({"realmb","realma"}) do
    local owner = "twin@"..realm
    local spellId = realm == "realma" and 840001 or 840002
    fallback.dummy[#fallback.dummy+1] = PublicRow(owner,"dummy",spellId)
    fallback.lk[#fallback.lk+1] = PublicRow(owner,"lk",spellId)
end
local originalBoard = DPS.GetDpsBoard
DPS.GetDpsBoard = function(category) return fallback[category] or {} end
local fallbackCombined = combinedReader()
DPS.GetDpsBoard = originalBoard
assert(#fallbackCombined == 2
        and fallbackCombined[1].displayPlayer == "Twin-realma"
        and fallbackCombined[2].displayPlayer == "Twin-realmb"
        and fallbackCombined[1].publicIdentityVerified == true
        and fallbackCombined[1].publicIdentityKey
            < fallbackCombined[2].publicIdentityKey,
    "projection-free Combined lost identity presentation or stable realm order")
print("dedicated dense leaderboard window and legacy routing -- OK")


-- MASTER-W3-007: use the shipped Leaderboard button with the real cold hash
-- owner. A helper-only request test cannot observe this omitted UI consumer.
local function Button(label)
    for _, widget in ipairs(syncControls) do
        if widget:GetText() == label
            or (widget.text and type(widget.text) == "table"
                and widget.text:GetText() == label) then return widget end
    end
    error("missing shipped Leaderboard button: " .. label)
end
local syncButton = Button("Sync Now")
local syncClick = assert(syncButton:GetScript("OnClick"))
local statusRegion
local combinedTab = Button("Strongest Pair")
for _, region in ipairs(syncRegions) do
    local _, relative = region:GetPoint()
    if relative == combinedTab then
        statusRegion = region
    end
end
assert(statusRegion, "missing shipped Leaderboard status region")
local S = dofile("tests/catalog_authority_support.lua")
local syncRows = {}
dofile("core/BuildHashCache.lua")
-- Nine valid rows in one real bucket exceed the existing synchronous digest
-- slice. A later record update therefore exercises actual hash invalidation.
local syncBucket = Nexus.BuildHashCache.Bucket("leaderboard-sync-1")
local syncRowCount = 0
for index = 1, 10000 do
    local id = "leaderboard-sync-" .. index
    if Nexus.BuildHashCache.Bucket(id) == syncBucket then
        syncRows[id] = S.LocalBuild(id, 1)
        syncRowCount = syncRowCount + 1
        if syncRowCount == 9 then break end
    end
end
assert(syncRowCount == 9, "could not prepare nine real rows in one hash bucket")
NexusDB = S.Database(syncRows)
H.AdmitCatalogV1(NexusDB)
DPS.Init({}, Nexus.Sync)
assert(DPS.ReceiveRecord({v=4,f=DPS.GetEchoKey(a),e=a,c="dummy",d=24000000,u=65,t=100,p="Alpha",k="MAGE",l=80}))
assert(DPS.ReceiveRecord({v=4,f=DPS.GetEchoKey(b),e=b,c="dummy",d=28000000,u=65,t=101,p="Bravo",k="MAGE",l=80}))
Nexus.Leaderboard.MarkDataDirty()
Nexus.Leaderboard.Show("dummy")
local fixtureFrame = H.frames.NexusLeaderboardFrame
for _ = 1, 20000 do
    fixtureFrame:GetScript("OnUpdate")(fixtureFrame, 0.01)
    if Nexus.Leaderboard.VirtualStats().publishedRows == 2 then break end
end
assert(Nexus.Leaderboard.VirtualStats().publishedRows == 2,
    "real Leaderboard selection rows did not finish preparation")
CreateFrame = createFrame
dofile("core/BuildHashCache.lua")
local realSync = Nexus.Sync
realSync.Init(Nexus.Codec, {})
H.sentChatMessages = {}
assert(realSync.GetCompatibilityHashes() == nil,
    "Leaderboard fixture did not start with a cold hash")
syncClick(syncButton)
assert(realSync.Stats().preparingRequest == true,
    "Leaderboard click did not retain the real preparing intent")
assert(statusRegion:GetText():find("Preparing sync data", 1, true),
    "cold Leaderboard Sync Now did not display preparation: button="
        .. tostring(syncButton:GetText()) .. " status=" .. statusRegion:GetText())
assert(not statusRegion:GetText():find("Syncing", 1, true),
    "cold Leaderboard claimed Syncing before hashes were ready")
print("Leaderboard real button cold-hash preparation -- OK")

local boardFrame = H.frames.NexusLeaderboardFrame
local frameUpdate = assert(boardFrame:GetScript("OnUpdate"))
local function Paint()
    frameUpdate(boardFrame, 1.1)
end
local function Requests()
    local requests = {}
    for _, message in ipairs(H.sentChatMessages) do
        local wire = message.text:gsub("||", "|")
        if wire:find("^WLRQ|") then
            assert(not wire:find("|nil|", 1, true), "Leaderboard sent a nil hash")
            requests[#requests + 1] = wire
        end
    end
    return requests
end
local function Preparing(label)
    assert(realSync.Stats().preparingRequest == true, label .. ": no pending intent")
    assert(syncButton:GetText() == "Preparing...", label .. ": wrong button state")
    assert(statusRegion:GetText():find("Preparing sync data", 1, true),
        label .. ": no visible preparing state")
    assert(not statusRegion:GetText():find("Syncing", 1, true),
        label .. ": claimed Syncing before readiness")
    assert(#Requests() == 0, label .. ": sent before readiness")
end
local function Cleared(label)
    assert(syncButton:GetText() == "Sync Now", label .. ": stale button state")
    assert(not statusRegion:GetText():find("Preparing", 1, true)
        and not statusRegion:GetText():find("Syncing", 1, true),
        label .. ": stale operation status: " .. statusRegion:GetText())
end
local function Click()
    local messages, originalPrint = {}, print
    print = function(message) messages[#messages + 1] = tostring(message) end
    local ok, reason = pcall(syncClick, syncButton)
    print = originalPrint
    assert(ok, "shipped Leaderboard callback failed: " .. tostring(reason))
    return messages
end
local function PumpToSend()
    for _ = 1, 20000 do
        H.now = H.now + 0.05
        Nexus.BuildHashCache.Pump()
        realSync.OnUpdate(0.05)
        Paint()
        if realSync.Stats().queueOutcome == "sent" then
            local requests = Requests()
            assert(#requests == 1, "Leaderboard intent did not send exactly once")
            assert(requests[1]:match("^WLRQ|[^|]+|([^|]+)|")
                    == realSync.GetCompatibilityHashes(),
                "Leaderboard sent the wrong generation hash")
            return
        end
        if boardFrame:IsShown() and realSync.Stats().preparingRequest then
            Preparing("readiness pump")
        end
    end
    error("Leaderboard intent did not reach actual send")
end

Click(); Click()
Paint()
Preparing("repeated cold clicks and periodic refresh")
local firstSelection
local selectedRows = 0
for _, widget in ipairs(syncControls) do
    if type(widget.data) == "table"
        and widget.player and widget:GetScript("OnClick") then
        widget:GetScript("OnClick")(widget)
        local selected = Nexus.Leaderboard.VirtualStats().selectedKey
        assert(selected, "real Leaderboard row did not select")
        if not firstSelection then firstSelection = selected
        else assert(selected ~= firstSelection, "row selection did not change") end
        selectedRows = selectedRows + 1
        Preparing("row selection while preparing")
        if selectedRows == 2 then break end
    end
end
assert(selectedRows == 2, "selection regression needs two real rendered rows")
Button("Lich King"):GetScript("OnClick")()
Preparing("category change while preparing")
Nexus.Leaderboard.Hide()
Nexus.Leaderboard.Show("dummy")
Preparing("reopen before readiness")
Nexus.Leaderboard.Hide()
PumpToSend()
Nexus.Leaderboard.Show("dummy")
assert(statusRegion:GetText():find("Syncing", 1, true)
    and not statusRegion:GetText():find("Preparing", 1, true),
    "reopen after readiness did not show the live syncing state")
assert(syncButton:GetText() == "Sync Now", "preparing button survived actual send")
local activeMessages = Click()
assert(#activeMessages == 1 and activeMessages[1]:find("already syncing", 1, true),
    "active button click did not preserve the actual request result")
Click()
realSync.OnUpdate(0.2)
assert(#Requests() == 1, "repeated active clicks duplicated the request")
-- Drive the session's existing 300-second absolute deadline, then inspect its
-- terminal outcome. Elapsed time is never used to infer hash readiness.
H.now = H.now + 301
realSync.OnUpdate(0.2)
Paint()
assert(realSync.Stats().terminalReason == "expired", "session did not terminate")
Cleared("terminal expiry")
print("Leaderboard real button one-send, selection, reopen and terminal -- OK")

-- A real catalog generation change makes an already-prepared hash unready.
S.PumpCatalogToIdle("Leaderboard fixture before generation change")
local changed = assert(Nexus.BuildCatalog.Get("leaderboard-sync-1"))
changed.title = "Changed Leaderboard generation"
changed.lastModified = changed.lastModified + 1
assert(S.CatalogMutation(function() return Nexus.BuildCatalog.Put(changed) end,
    "Leaderboard hash invalidation"))
assert(realSync.GetCompatibilityHashes() == nil, "real mutation did not invalidate hash")
H.sentChatMessages = {}
local messages = Click()
assert(#messages == 1 and messages[1]:find("preparing sync data", 1, true),
    "Leaderboard did not consume the actual pending result")
Preparing("invalidated generation")
Nexus.Leaderboard.Hide()
realSync.Init(Nexus.Codec, {})
Nexus.Leaderboard.Show("dummy")
Cleared("reset while hidden")
for _ = 1, 20000 do
    if Nexus.BuildHashCache.Pump() == true then break end
end
assert(type(realSync.GetCompatibilityHashes()) == "string", "ready fixture did not settle")
realSync.OnUpdate(0.2)
assert(#Requests() == 0, "reset left a delayed unintended send")
messages = Click()
assert(#messages == 1 and messages[1]:find("asking other players", 1, true),
    "ready button did not consume its successful request result")
assert(not realSync.Stats().preparingRequest, "ready request unexpectedly waited for hashes")
assert(statusRegion:GetText():find("Syncing", 1, true), "ready request lost syncing state")
PumpToSend()
print("Leaderboard real button invalidation, reset and ready hashes -- OK")

-- Disconnect a new pending action, then click the same shipped button when
-- the WoW channel boundary refuses reconnection. Do not fake Sync's result.
H.now = H.now + 301
realSync.OnUpdate(0.2)
dofile("core/BuildHashCache.lua")
realSync.Init(Nexus.Codec, {})
H.sentChatMessages = {}
Click()
Preparing("disconnect fixture")
local joinTemporary, joinByName = JoinTemporaryChannel, JoinChannelByName
JoinTemporaryChannel = function() end
JoinChannelByName = function() end
H.joinedChannels = {}
realSync.OnUpdate(0.2)
Paint()
assert(realSync.Stats().terminalReason == "disconnected", "pending action did not disconnect")
Cleared("disconnected pending action")
messages = Click()
assert(#messages == 1 and messages[1]:find("not connected to the sync channel", 1, true),
    "Leaderboard did not expose the actual synchronous refusal")
Cleared("synchronous refusal")
assert(#Requests() == 0, "refused or cancelled request sent traffic")
JoinTemporaryChannel, JoinChannelByName = joinTemporary, joinByName
print("Leaderboard real button disconnect and refusal -- OK")
