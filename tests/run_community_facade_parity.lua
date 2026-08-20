-- Final Community facade/popup cutover: one projection/controller/renderer,
-- stable named popups, exact draft actions, and no duplicate presentation path.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("core/Store.lua")

UnitName = function() return "PopupOwner" end
GetNormalizedRealmName = function() return "Ebonhold" end

NexusDB = {
    settingsVersion=2, settings={}, chars={}, dpsCapture={},
    buildFilters={scope="all",sortMode="title"},
    communityBuilds={
        remote={id="remote",title="Remote",author="Peer",
            ownerKey="peer@ebonhold",class="MAGE",postedAt=1,lastModified=1,
            echoes={{spellId=730001,quality=3,stacks=1}}},
    },
    futureRoot={keep=true},
}
Nexus.Store.Init()

local slotRows = {
    [1]={slot=1,name="Server Fire",verified=true,class="MAGE",echoes={
        {spellId=730001,quality=3,stacks=1,locked=true},
        {spellId=730002,quality=2,stacks=2},
    }},
}
local Adapter = {
    Slots=function() return {bySlot=slotRows,activeSlot=1} end,
    GetWishlistCandidates=function() return {} end,
    Catalog=function() return {rows={
        [730001]={name="Fire One",classMask=128},
        [730002]={name="Fire Two",classMask=128},
    }} end,
    Owned=function() return {bySpell={[730001]=1,[730002]=2}} end,
    LockedOwned=function() return {bySpell={[730001]=true}} end,
    Wishlist=function() return slotRows[1] end,
}
Nexus.DpsCapture = {
    GetLeaderboard=function() return {} end,
    GetLeaderboardForEchoes=function() return {} end,
    GetPersonalBest=function() return nil end,
    GetDpsBoard=function() return {} end,
    IsDetailsAvailable=function() return false end,
}
local broadcasts = {}
Nexus.Sync = {
    BroadcastBuildSummary=function(build)
        broadcasts[#broadcasts + 1] = build.id
        if #broadcasts == 1 then return false, "sync queue full" end
        return true
    end,
    RequestLoadout=function() return true end,
    IsReceiving=function() return false end,
    ReceiveTimeLeft=function() return 0 end,
    LastSyncNewCount=function() return 0 end,
    Stats=function() return {received=0} end,
    RequestSync=function() return true end,
}

-- Popup backdrop failures are cosmetic and must not discard controller state.
local baseCreateFrame = CreateFrame
CreateFrame = function(kind, name, ...)
    local frame = baseCreateFrame(kind, name, ...)
    if name == "NexusPostPopup" or name == "NexusEditPopup" then
        frame.SetBackdrop = function() error("cosmetic popup failure") end
    end
    return frame
end

local counts, instances = {projection=0,controller=0,renderer=0}, {}
for key, factory in pairs({
    projection=Nexus.CommunityInternals.Projection,
    controller=Nexus.CommunityInternals.Controller,
    renderer=Nexus.CommunityInternals.Renderer,
}) do
    local original = factory.New
    factory.New = function(options)
        counts[key] = counts[key] + 1
        local instance = original(options)
        instances[key] = instance
        return instance
    end
end

dofile("ui/CommunityBuilds.lua")
local C = Nexus.CommunityBuilds
C.Init(Adapter, nil)
C.Init(Adapter, nil)

-- Post popup keeps its exact name, inferred draft, preview, and one admitted
-- catalog/broadcast action even when cosmetic frame styling fails.
C.ShowPostBuild()
local post = assert(H.frames.NexusPostPopup)
assert(post:IsShown(), "post popup did not survive cosmetic frame failure")
local draftWishlist, draftClass = instances.controller.PostDraft()
assert(draftWishlist and draftWishlist.slot == 1 and draftClass == "MAGE",
    "post popup did not retain its inferred controller draft")
assert(post._previewRows[1]:IsShown()
    and post._previewRows[1].text:GetText():find("Fire One", 1, true),
    "post popup lost exact Echo preview binding")
post._postTitleBox:SetText("Shared Fire")
post._postDescBox:SetText("Popup parity")
local share = assert(post._postGoBtn:GetScript("OnClick"))
local shareMessages, originalPrint = {}, print
print = function(...)
    local values = {}
    for index = 1, select("#", ...) do
        values[#values + 1] = tostring(select(index, ...))
    end
    shareMessages[#shareMessages + 1] = table.concat(values, " ")
    originalPrint(...)
end
share()
print = originalPrint
assert(not post:IsShown() and #broadcasts == 1,
    "locally saved post did not close or emitted duplicate Sync writes")
local shareText = tostring(shareMessages[#shareMessages] or "")
assert(shareText:find("saved locally; not queued", 1, true)
    and not shareText:lower():find("build shared", 1, true),
    "queue rejection still produced peer-sharing success wording")
local sharedId = broadcasts[1]
local shared = assert(Nexus.BuildCatalog.Get(sharedId))
assert(shared.title == "Shared Fire" and shared.description == "Popup parity"
    and #shared.echoes == 2,
    "post popup changed the admitted title/description/loadout")

-- Edit popup binds the same controller draft and commits exactly once.
C.ToggleEditPopup(sharedId)
local edit = assert(H.frames.NexusEditPopup)
assert(edit:IsShown() and edit._editingId == sharedId,
    "edit popup lost its name or exact edit identity")
assert(instances.controller.EditDraft().id == sharedId,
    "edit popup did not bind the controller draft")
edit._editTitleBox:SetText("Shared Fire Updated")
edit._editDescBox:SetText("Edited once")
local save = assert(edit._saveBtn:GetScript("OnClick"))
save()
shared = assert(Nexus.BuildCatalog.Get(sharedId))
assert(not edit:IsShown() and shared.title == "Shared Fire Updated"
    and shared.description == "Edited once" and #broadcasts == 2
    and instances.controller.EditDraft() == nil,
    "edit popup lost draft clearing or emitted duplicate catalog/Sync writes")
C.ToggleEditPopup("remote")
assert(not edit:IsShown(), "non-owner edit opened the extracted popup")

-- Missing source remains a visible validation error with no write.
slotRows = {}
C.ShowPostBuild()
assert(post:IsShown(), "post popup could not reopen without a source")
share()
assert(post:IsShown() and #broadcasts == 2,
    "invalid post source closed the draft or emitted a write")
C.TogglePostPopup()
assert(not post:IsShown(), "post popup toggle did not retain hide behavior")

-- Repeated facade entry never creates competing owners.
C.Show(); C.Hide(); C.Show(); C.Hide()
assert(counts.projection == 1 and counts.controller == 1
    and counts.renderer == 1,
    string.format("duplicate Community owners: projection=%d controller=%d renderer=%d",
        counts.projection, counts.controller, counts.renderer))
assert(NexusDB.futureRoot.keep, "popup/facade cutover damaged future data")

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end
local facade = Read("ui/CommunityBuilds.lua")
for _, forbidden in ipairs({
    "CreateFrame", "SetScript(", "NexusPostPopup", "NexusEditPopup",
    "EnsurePostPopup", "EnsureEditPopup", "BuildSourceCandidates",
    "NexusDB", "BuildCatalog", "DpsCapture", "SortedBuilds",
    "BuildDpsSummary", "StaticPopupDialogs", "StaticPopup_Show",
}) do
    assert(not facade:find(forbidden, 1, true),
        "thin Community facade retained popup rendering: " .. forbidden)
end
local renderer = Read("ui/CommunityRenderer.lua")
assert(renderer:find('CreateFrame("Frame","NexusPostPopup"', 1, true)
    and renderer:find('CreateFrame("Frame","NexusEditPopup"', 1, true),
    "renderer does not own both established popup frames")
assert(not renderer:find("Adapter.", 1, true),
    "renderer retained direct GameAdapter data preparation")

print(string.format(
    "community facade: owners=%d/%d/%d writes=%d stable popup drafts/frames -- OK",
    counts.projection, counts.controller, counts.renderer, #broadcasts))
