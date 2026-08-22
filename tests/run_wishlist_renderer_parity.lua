-- Wishlist renderer extraction parity: 1,000 available Echoes and a full
-- 79-copy draft bind only the fixed visible pools, then reuse them.
local H = dofile("tests/harness.lua")
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")

NexusDB = {
    settingsVersion=2, settings={}, chars={}, dpsCapture={},
    editorClassOnly=false, futureRoot={keep=true},
}
UISpecialFrames = {}
Nexus.Store.Init()

local catalog = {rows={}, playerMask=1}
for index = 1, 1000 do
    local spellId = 760000 + index
    catalog.rows[spellId] = {
        spellId=spellId, groupId=spellId,
        name=string.format("Renderer Echo %04d", index),
        quality=index % 5, maxStack=1, classMask=1,
    }
end
local draft = {}
for index = 1, 79 do
    draft[index] = {
        spellId=760000 + index, quality=index % 5, stacks=1,
    }
end

local mutations = {upload=0, association=0}
local Adapter = Nexus.GameAdapter
Adapter.Catalog = function() return catalog end
Adapter.Owned = function() return {bySpell={}} end
Adapter.LockedOwned = function() return {bySpell={}} end
Adapter.Wishlist = function() return nil end
Adapter.GetWishlistCandidates = function() return {} end
Adapter.Slots = function()
    return {activeSlot=0, maxSlots=5, bySlot={}}
end
Adapter.GetLoadoutWishlist = function() return nil end
Adapter.UploadWishlist = function()
    mutations.upload = mutations.upload + 1
    return true
end
Adapter.SetLoadoutWishlist = function()
    mutations.association = mutations.association + 1
    return true
end

local realCreateFrame = CreateFrame
local created = {}
CreateFrame = function(kind, name, parent, template)
    local frame = realCreateFrame(kind, name, parent, template)
    frame._kind, frame._name = kind, name
    frame._parent, frame._template = parent, template
    created[#created + 1] = frame
    return frame
end

local Editor = Nexus.WishlistEditor
Editor.Init(Adapter, Nexus.Model)
Editor.OpenForCandidate({title="Renderer Fixture", echoes=draft})

local main = H.frames.NexusEditorFrame
assert(main and main:IsShown(),
    "renderer changed the established NexusEditorFrame identity")
assert(UISpecialFrames[1] == "NexusEditorFrame",
    "renderer changed escape-close registration")

local leftArea, pickArea
for _, frame in ipairs(created) do
    if frame._kind == "Frame" and frame._parent == main
        and frame.w == 600 and frame.h == 19 * 24 then
        leftArea = frame
    elseif frame._kind == "Frame" and frame._parent == main
        and frame.w == 332 and frame.h == 18 * 24 then
        pickArea = frame
    end
end
assert(leftArea and pickArea,
    "renderer lost the bounded available/pending viewports")

local function DirectRows(parent)
    local rows = {}
    for _, frame in ipairs(created) do
        if frame._kind == "Button" and frame._parent == parent then
            rows[#rows + 1] = frame
        end
    end
    return rows
end

local availableRows, pendingRows = DirectRows(leftArea), DirectRows(pickArea)
assert(#availableRows == 19 and #pendingRows == 18,
    string.format("renderer pools changed: available=%d pending=%d",
        #availableRows, #pendingRows))
local availableVisible, pendingVisible = 0, 0
for _, row in ipairs(availableRows) do
    if row:IsShown() then availableVisible = availableVisible + 1 end
end
for _, row in ipairs(pendingRows) do
    if row:IsShown() then pendingVisible = pendingVisible + 1 end
end
assert(availableVisible == 19 and pendingVisible == 18,
    "large fixtures did not bind the complete fixed visible pools")

local createdBeforeScroll = #created
for _ = 1, 40 do
    leftArea:GetScript("OnMouseWheel")(leftArea, -1)
    pickArea:GetScript("OnMouseWheel")(pickArea, -1)
end
for _ = 1, 5 do Editor.Refresh() end
local scrolled = Editor.DebugDraftState()
assert(scrolled.scrollOffset > 0 and scrolled.pickOffset > 0,
    "renderer scroll bindings did not advance both controller offsets")
assert(#created == createdBeforeScroll,
    "scroll/refresh allocated rows instead of reusing the fixed pools")
assert(mutations.upload == 0 and mutations.association == 0,
    "renderer refresh submitted an upload or association")
assert(NexusDB.futureRoot.keep,
    "renderer damaged an unknown SavedVariables field")

local function FindButton(prefix)
    for _, frame in ipairs(created) do
        if frame._kind == "Button"
            and tostring(frame.text or ""):find(prefix, 1, true) == 1 then
            return frame
        end
    end
end
local loadoutButton = assert(FindButton("Loadout:"),
    "loadout switch binding lost")
local wishlistButton = assert(FindButton("New Wishlist"),
    "wishlist switch binding lost")
loadoutButton:GetScript("OnClick")(loadoutButton)
wishlistButton:GetScript("OnClick")(wishlistButton)
assert(H.frames.NexusWishlistEditorLoadoutMenu
    and H.frames.NexusWishlistEditorSwitchMenu,
    "renderer changed named switch-menu identities")
local createdAfterMenus = #created
loadoutButton:GetScript("OnClick")(loadoutButton)
loadoutButton:GetScript("OnClick")(loadoutButton)
wishlistButton:GetScript("OnClick")(wishlistButton)
wishlistButton:GetScript("OnClick")(wishlistButton)
assert(#created == createdAfterMenus,
    "switch menus rebuilt their row pools on reuse")

-- Same-family exact tiers must bind independent renderer action handles. A
-- plus/remove click on one visible row may not target either sibling.
for offset = 1, 3 do
    local spellId = 762000 + offset
    catalog.rows[spellId] = {
        spellId=spellId,groupId=880,name="Renderer Shared Echo",
        quality=offset,maxStack=3,classMask=1,
    }
end
Editor.OpenForCandidate({title="Renderer exact tiers",echoes={
    {spellId=762001,quality=1,stacks=1},
    {spellId=762002,quality=2,stacks=1},
    {spellId=762003,quality=3,stacks=1},
}})
local exactSearch = assert(H.frames.NexusEditorSearch,
    "renderer search control unavailable")
exactSearch:SetText("Renderer Shared Echo")
exactSearch:GetScript("OnTextChanged")(exactSearch)
Editor.Refresh()
local function AvailableRow(spellId)
    for _, row in ipairs(availableRows) do
        if row.data and tonumber(row.data.spellId) == spellId then return row end
    end
end
for _, spellId in ipairs({762001,762002,762003}) do
    local row = assert(AvailableRow(spellId),
        "renderer lost an available exact-tier row")
    assert(tostring(row.text.text):find("(selected)", 1, true),
        "renderer did not project selected state through the exact draft key")
    assert(not tostring(row.text.text):find("replaces selected quality", 1, true),
        "renderer retained the obsolete family replacement state")
end
local function PendingRow(spellId)
    for _, row in ipairs(pendingRows) do
        if row.data and tonumber(row.data.spellId) == spellId then return row end
    end
end
local low = assert(PendingRow(762001), "renderer lost the low exact tier")
local middle = assert(PendingRow(762002), "renderer lost the middle exact tier")
local high = assert(PendingRow(762003), "renderer lost the high exact tier")
assert(low.data.draftKey ~= middle.data.draftKey
    and middle.data.draftKey ~= high.data.draftKey
    and low.data.draftKey ~= high.data.draftKey,
    "renderer gave same-family tiers a shared action handle")
middle.plus:GetScript("OnClick")({GetParent=function() return middle end})
Editor.Refresh()
low, middle, high = PendingRow(762001), PendingRow(762002), PendingRow(762003)
assert(low.data.stacks == 1 and middle.data.stacks == 2
    and high.data.stacks == 1,
    "renderer plus action modified a sibling exact tier")
low.remove:GetScript("OnClick")({GetParent=function() return low end})
Editor.Refresh()
assert(not PendingRow(762001) and PendingRow(762002) and PendingRow(762003),
    "renderer remove action modified or lost a sibling exact tier")

local function Read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local rendererSource = Read("ui/WishlistRenderer.lua")
for _, forbidden in ipairs({
    "NexusDB", "UploadWishlist", "SetLoadoutWishlist",
    "UpdateWishlistAssociation", "ProjectEbonhold",
    "Nexus.Store", "Nexus.Sync", "BroadcastBuild",
}) do
    assert(not rendererSource:find(forbidden, 1, true),
        "renderer owns forbidden persistence/transport/gameplay path: "
            .. forbidden)
end
local facadeSource = Read("ui/WishlistEditor.lua")
for _, moved in ipairs({
    "local function EnsureFrame", "local function BuildAvailableList",
    "local function ShowWishlistSwitchMenu", "local function SpellIcon",
    "local MAX_ROWS", "local PICK_ROWS", "local frame, rows, pickRows",
}) do
    assert(not facadeSource:find(moved, 1, true),
        "Wishlist facade retained renderer implementation: " .. moved)
end
local controllerSource = Read("core/WishlistController.lua")
assert(not controllerSource:find("CreateFrame", 1, true),
    "Wishlist controller gained frame ownership")

local toc = Read("Nexus.toc")
local rendererAt = assert(toc:find("ui\\WishlistRenderer.lua", 1, true))
local editorAt = assert(toc:find("ui\\WishlistEditor.lua", 1, true))
assert(rendererAt < editorAt, "Wishlist renderer TOC order changed")

print(string.format(
    "wishlist renderer: available=1000/%d pending=79/%d fixed pools reused -- OK",
    #availableRows, #pendingRows))
