-- Nexus: ui/WishlistOverlay.lua
-- The always-on-screen wishlist list some players like to keep visible
-- while leveling -- modeled closely on the EchoWishlist addon's own
-- overlay: one line per echo, bright/quality-colored when you own it,
-- dimmed gray when you don't, locked (click-through) by default so it
-- never blocks clicks on the world underneath it, with a lock toggle,
-- drag-to-move when unlocked, and a scale slider.
--
-- Laid out in COLUMNS side-by-side columns rather than one long list --
-- a 70+ echo wishlist in a single column at the old row height would run
-- past 1000px tall on most screens. Columns + a scale slider keep the
-- whole thing on-screen regardless of wishlist size or display size.

Nexus = Nexus or {}
local M = {}
Nexus.WishlistOverlay = M

local MAX_LINES = 90
local COLUMNS = 3
local ROWS_PER_COLUMN = math.ceil(MAX_LINES / COLUMNS)
local ROW_HEIGHT = 15
local COLUMN_WIDTH = 210
local UPDATE_INTERVAL = 1.0

local QUALITY_COLORS = {
    [0] = { 1, 1, 1 },
    [1] = { 0.12, 1, 0.12 },
    [2] = { 0.2, 0.6, 1 },
    [3] = { 0.72, 0.36, 0.98 },
    [4] = { 1, 0.65, 0 },
}

local frame, lines, lockBtn, controlsFrame, hideBtn
local Adapter, Model
local ticker = 0
local cachedWishlist, cachedOwned, cachedCatalog
local revisionsKnown = false
local lastSlotsRevision, lastActiveRevision, lastGrantedRevision
local lastOwnedRevision
local lastWishlistRevision, lastCatalogRevision
local lineState = {}
local lastStyleTree
local stats = {
    refreshCalls=0,hiddenSkips=0,revisionReads=0,revisionSkips=0,
    projectionBuilds=0,identicalModels=0,rowUpdates=0,
    rowShows=0,rowHides=0,stylePasses=0,
    framesCreated=0,linesCreated=0,cachedLineStates=0,
    wishlistReads=0,ownedReads=0,catalogReads=0,
}

local function IsLocked()
    return NexusDB.overlayLocked ~= false
end

local function ApplyLockState()
    if not frame then return end
    if IsLocked() then
        -- Keep the large list click-through, but leave the tiny control
        -- strip interactive so the overlay can never become stuck.
        frame:EnableMouse(false)
        frame:RegisterForDrag()
        if lockBtn then lockBtn:SetText("Unlock") end
    else
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        if lockBtn then lockBtn:SetText("Lock") end
    end
    if controlsFrame then
        controlsFrame:EnableMouse(true)
        if frame:IsShown() then controlsFrame:Show() else controlsFrame:Hide() end
    end
end

local function ApplyPosition()
    if not frame then return end
    frame:ClearAllPoints()
    local pos = NexusDB.overlayPosition
    if type(pos) == "table" and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("LEFT", UIParent, "LEFT", 18, 0)
    end
end

local function SavePosition()
    if not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    NexusDB.overlayPosition = {
        point = point or "LEFT", relativePoint = relativePoint or point or "LEFT",
        x = math.floor((x or 0) + 0.5), y = math.floor((y or 0) + 0.5),
    }
end

local function ApplyScale()
    if not frame then return end
    local scale = tonumber(NexusDB.overlayScale) or 1.0
    pcall(function() frame:SetScale(scale) end)
    pcall(function() if controlsFrame then controlsFrame:SetScale(scale) end end)
end

local function ApplyTheme()
    local theme = Nexus and Nexus.Theme
    local style = theme and theme.StyleTree
    if controlsFrame and type(style) == "function"
        and style ~= lastStyleTree then
        style(controlsFrame)
        lastStyleTree = style
        stats.stylePasses = stats.stylePasses + 1
    end
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "NexusOverlay", UIParent)
    stats.framesCreated = stats.framesCreated + 1
    frame:SetSize(COLUMNS * COLUMN_WIDTH + 20, ROWS_PER_COLUMN * ROW_HEIGHT + 30)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(60)
    frame:SetMovable(true)
    frame:SetScript("OnDragStart", function(self)
        if not IsLocked() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        ticker = ticker + (elapsed or 0)
        if ticker >= UPDATE_INTERVAL then
            ticker = 0
            M.Refresh()
        end
    end)
    frame:Hide()

    lines = {}
    for i = 1, MAX_LINES do
        local col = math.floor((i - 1) / ROWS_PER_COLUMN)
        local row = (i - 1) % ROWS_PER_COLUMN
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 20 + col * COLUMN_WIDTH, -26 - (row * ROW_HEIGHT))
        fs:SetSize(COLUMN_WIDTH - 10, ROW_HEIGHT)
        fs:SetJustifyH("LEFT")
        pcall(function() fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1) end)
        fs:Hide()
        lines[i] = fs
        stats.linesCreated = stats.linesCreated + 1
    end

    -- The control strip is a sibling of the click-through list. Disabling
    -- mouse input on the overlay body must never disable these controls.
    controlsFrame = CreateFrame("Frame", "NexusOverlayControls", UIParent)
    stats.framesCreated = stats.framesCreated + 1
    controlsFrame:SetSize(80, 22)
    controlsFrame:SetFrameStrata("DIALOG")
    controlsFrame:SetFrameLevel(75)
    controlsFrame:EnableMouse(true)
    controlsFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 4)
    controlsFrame:Hide()

    lockBtn = CreateFrame("Button", nil, controlsFrame, "UIPanelButtonTemplate")
    stats.framesCreated = stats.framesCreated + 1
    lockBtn:SetSize(50, 18)
    lockBtn:SetPoint("LEFT", 0, 0)
    lockBtn:SetScript("OnClick", function()
        NexusDB.overlayLocked = not IsLocked()
        ApplyLockState()
    end)

    -- Hide button: lets the player collapse the overlay without going
    -- into the editor or typing /nexus overlay.
    hideBtn = CreateFrame("Button", nil, controlsFrame, "UIPanelButtonTemplate")
    stats.framesCreated = stats.framesCreated + 1
    hideBtn:SetSize(22, 18)
    hideBtn:SetPoint("LEFT", lockBtn, "RIGHT", 4, 0)
    hideBtn:SetText("-")
    hideBtn:SetScript("OnClick", function() M.Hide() end)
    hideBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Hide the wishlist overlay", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("/nexus overlay to show it again", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    hideBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ApplyPosition()
    ApplyLockState()
    ApplyScale()
    ApplyTheme()
    return frame
end

local function ReadRevisions()
    local reader = Adapter and Adapter.PresentationRevisions
    if type(reader) ~= "function" then return false end
    stats.revisionReads = stats.revisionReads + 1
    local ok, slotsRevision, activeRevision, grantedRevision,
        ownedRevision, wishlistRevision, catalogRevision = pcall(reader)
    if not ok or slotsRevision == nil or activeRevision == nil
        or grantedRevision == nil or ownedRevision == nil
        or wishlistRevision == nil
        or catalogRevision == nil then
        return false
    end
    return true,slotsRevision,activeRevision,grantedRevision,ownedRevision,
        wishlistRevision,catalogRevision
end

local function StoreRevisions(slotsRevision, activeRevision, grantedRevision,
    ownedRevision, wishlistRevision, catalogRevision)
    revisionsKnown = true
    lastSlotsRevision, lastActiveRevision = slotsRevision, activeRevision
    lastGrantedRevision, lastOwnedRevision = grantedRevision, ownedRevision
    lastWishlistRevision = wishlistRevision
    lastCatalogRevision = catalogRevision
end

local function AcquirePresentation()
    local known, slotsRevision, activeRevision, grantedRevision, ownedRevision,
        wishlistRevision, catalogRevision = ReadRevisions()
    if known and revisionsKnown
        and slotsRevision == lastSlotsRevision
        and activeRevision == lastActiveRevision
        and grantedRevision == lastGrantedRevision
        and ownedRevision == lastOwnedRevision
        and wishlistRevision == lastWishlistRevision
        and catalogRevision == lastCatalogRevision then
        stats.revisionSkips = stats.revisionSkips + 1
        return false
    end

    local refreshWishlist = not known or not revisionsKnown
        or slotsRevision ~= lastSlotsRevision
        or activeRevision ~= lastActiveRevision
        or wishlistRevision ~= lastWishlistRevision
    local refreshOwned = not known or not revisionsKnown
        or grantedRevision ~= lastGrantedRevision
        or ownedRevision ~= lastOwnedRevision
    local refreshCatalog = not known or not revisionsKnown
        or catalogRevision ~= lastCatalogRevision
    if refreshWishlist then
        cachedWishlist = Adapter and Adapter.Wishlist and Adapter.Wishlist()
        stats.wishlistReads = stats.wishlistReads + 1
    end
    if refreshOwned then
        cachedOwned = Adapter and Adapter.Owned and Adapter.Owned()
        stats.ownedReads = stats.ownedReads + 1
    end
    if refreshCatalog then
        cachedCatalog = Adapter and Adapter.Catalog and Adapter.Catalog()
        stats.catalogReads = stats.catalogReads + 1
    end
    stats.projectionBuilds = stats.projectionBuilds + 1

    if known then
        -- A Wishlist read may promote the first-run association. Capture the
        -- resulting revision so the next identical tick stays zero-work.
        local finalKnown, finalSlots, finalActive, finalGranted,
            finalOwned, finalWishlist, finalCatalog = ReadRevisions()
        if finalKnown then
            StoreRevisions(finalSlots, finalActive, finalGranted, finalOwned,
                finalWishlist, finalCatalog)
        else
            revisionsKnown = false
        end
    else
        revisionsKnown = false
    end
    return true
end

local function RememberLine(index, key)
    if lineState[index] == nil then
        stats.cachedLineStates = stats.cachedLineStates + 1
    end
    lineState[index] = key
end

local function HideLine(index)
    if lineState[index] == "hidden" then return false end
    lines[index]:Hide()
    RememberLine(index, "hidden")
    stats.rowUpdates = stats.rowUpdates + 1
    stats.rowHides = stats.rowHides + 1
    return true
end

local function ShowLine(index, key, text, red, green, blue, setColor)
    if lineState[index] == key then return false end
    local line = lines[index]
    if setColor then line:SetTextColor(red, green, blue) end
    line:SetText(text)
    line:Show()
    RememberLine(index, key)
    stats.rowUpdates = stats.rowUpdates + 1
    stats.rowShows = stats.rowShows + 1
    return true
end

local function LineKey(text, red, green, blue, setColor)
    return table.concat({
        tostring(#text),text,setColor and "1" or "0",
        tostring(red or ""),tostring(green or ""),tostring(blue or ""),
    }, "|")
end

function M.Refresh()
    stats.refreshCalls = stats.refreshCalls + 1
    if not frame or not frame:IsShown() then
        stats.hiddenSkips = stats.hiddenSkips + 1
        return
    end
    ApplyTheme()
    if not AcquirePresentation() then return end
    local wl, owned, catalog = cachedWishlist, cachedOwned, cachedCatalog
    local byFamily = (owned and owned.byFamily) or {}
    local changed = false
    if not wl then
        local text = "|cff888888No wishlist set|r"
        changed = ShowLine(1, LineKey(text, nil, nil, nil, false),
            text, nil, nil, nil, false) or changed
        for i = 2, MAX_LINES do changed = HideLine(i) or changed end
        if not changed then stats.identicalModels = stats.identicalModels + 1 end
        return
    end

    local list = {}
    for _, e in ipairs(wl.entries or {}) do
        local row = catalog and catalog.rows and catalog.rows[e.spellId]
        list[#list + 1] = { spellId = e.spellId, quality = e.quality,
            stacks = e.stacks, family = e.family,
            name = (row and row.name) or ("spell " .. tostring(e.spellId)) }
    end
    table.sort(list, function(a, b)
        local ac = tonumber(a.quality) or 0
        local bc = tonumber(b.quality) or 0
        if ac ~= bc then return ac > bc end
        return tostring(a.name) < tostring(b.name)
    end)

    for i = 1, MAX_LINES do
        local e = list[i]
        if e then
            local have = tonumber(byFamily[e.family]) or 0
            local want = tonumber(e.stacks) or 1
            local nm = e.name or ("spell " .. tostring(e.spellId))
            local suffix = want > 1 and string.format(" (%d/%d)", math.min(have, want), want) or ""
            local text, red, green, blue
            if have >= want then
                local c = QUALITY_COLORS[e.quality] or QUALITY_COLORS[0]
                red, green, blue = c[1], c[2], c[3]
                text = "|cff40ff80[X]|r " .. nm .. suffix
            elseif have > 0 then
                local c = QUALITY_COLORS[e.quality] or QUALITY_COLORS[0]
                red, green, blue = c[1] * 0.7, c[2] * 0.7, c[3] * 0.7
                text = "[~] " .. nm .. suffix
            else
                red, green, blue = 0.38, 0.38, 0.38
                text = "[ ] " .. nm .. suffix
            end
            changed = ShowLine(i, LineKey(text, red, green, blue, true),
                text, red, green, blue, true) or changed
        else
            changed = HideLine(i) or changed
        end
    end
    if not changed then stats.identicalModels = stats.identicalModels + 1 end
end

function M.Init(adapter, model)
    Adapter, Model = adapter, model
    cachedWishlist, cachedOwned, cachedCatalog = nil, nil, nil
    revisionsKnown = false
end

function M.Show()
    EnsureFrame()
    frame:Show()
    if controlsFrame then controlsFrame:Show() end
    NexusDB.overlayShown = true
    ApplyLockState()
    M.Refresh()
end

function M.Hide()
    if frame then frame:Hide() end
    if controlsFrame then controlsFrame:Hide() end
    NexusDB.overlayShown = false
end

function M.Toggle()
    EnsureFrame()
    if frame:IsShown() then M.Hide() else M.Show() end
end

function M.IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Public lock accessors, so the Wishlist Editor's own Lock/Unlock button
-- can drive and reflect the same state without duplicating logic.
function M.IsLocked()
    return IsLocked()
end

function M.ToggleLock()
    NexusDB.overlayLocked = not IsLocked()
    ApplyLockState()
end

-- Scale control lives in the editor's settings popup, not on the
-- overlay itself (moved there per request 2026-07-24) -- these are the
-- read/write hooks it drives.
function M.ResetPosition()
    NexusDB.overlayPosition = nil
    ApplyPosition()
    if frame then
        frame:Show()
        if controlsFrame then controlsFrame:Show() end
        NexusDB.overlayShown = true
        ApplyLockState()
        M.Refresh()
    end
end

function M.GetScale()
    return tonumber(NexusDB.overlayScale) or 1.0
end

function M.SetScale(value)
    value = tonumber(value) or 1.0
    if value < 0.5 then value = 0.5 end
    if value > 1.6 then value = 1.6 end
    NexusDB.overlayScale = value
    ApplyScale()
end

function M.Stats()
    local out = {}
    for key, value in pairs(stats) do out[key] = value end
    return out
end
