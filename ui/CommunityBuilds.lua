-- Nexus: ui/CommunityBuilds.lua
-- Nexus Builds community browser -- modeled on the in-game Echo Journal
-- Community Loadouts screen (see screenshots 2026-07-24): scrollable
-- list of build cards grouped under class headers, each showing echo
-- icons inline, author, and a +/... menu. Click any card to expand a
-- detail panel (all echoes, full description, Copy / owner Edit / Delete). Sync: posts broadcast automatically; receiving is opt-in via
-- "Sync Now".

Nexus = Nexus or {}
local M = {}
Nexus.CommunityBuilds = M

local RefreshBuildIdentity

------------------------------------------------------------------------
-- Constants / lookup tables
------------------------------------------------------------------------

local CARD_HEIGHT    = 88      -- compact, readable build row
local ICON_SIZE      = 26      -- Echo preview icon size
local MAX_ROW_ICONS  = 12      -- preview icons before the remainder count
local ECHO_ICON_SIZE = 22      -- icons in the detail panel

local CLASS_COLOR = {
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    DRUID       = { 1.00, 0.49, 0.04 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    MAGE        = { 0.25, 0.78, 0.92 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    WARLOCK     = { 0.53, 0.53, 0.93 },
    WARRIOR     = { 0.78, 0.61, 0.43 },
}
local CLASS_ORDER = {
    DEATHKNIGHT=1, DRUID=2, HUNTER=3, MAGE=4, PALADIN=5,
    PRIEST=6,      ROGUE=7, SHAMAN=8, WARLOCK=9, WARRIOR=10,
}
local CLASS_LABEL = {
    DEATHKNIGHT="Death Knight", DRUID="Druid",   HUNTER="Hunter",
    MAGE="Mage",    PALADIN="Paladin", PRIEST="Priest",
    ROGUE="Rogue",  SHAMAN="Shaman",   WARLOCK="Warlock", WARRIOR="Warrior",
}
local CLASS_ICON = {
    DEATHKNIGHT="Interface\\Icons\\Spell_DeathKnight_IceboundFortitude",
    DRUID       ="Interface\\Icons\\Spell_Nature_NaturesBlessing",
    HUNTER      ="Interface\\Icons\\Ability_Hunter_BeastCall",
    MAGE        ="Interface\\Icons\\Spell_Frost_Frostbolt02",
    PALADIN     ="Interface\\Icons\\Spell_Holy_HolyBolt",
    PRIEST      ="Interface\\Icons\\Spell_Holy_PowerInfusion",
    ROGUE       ="Interface\\Icons\\Ability_BackStab",
    SHAMAN      ="Interface\\Icons\\Spell_Nature_Lightning",
    WARLOCK     ="Interface\\Icons\\Spell_Shadow_ShadowBolt",
    WARRIOR     ="Interface\\Icons\\Ability_Warrior_Charge",
}

------------------------------------------------------------------------
-- Module state
------------------------------------------------------------------------

local frame, scrollChild, scrollFrame, scrollBar
local detailPanel
local postPopup, editPopup
local searchBox, classDropBtn, dropPanel, sortToggle, sortPanel, scopeBtn, myBuildsBtn, syncStatusText, syncBtn, dropdownShield
local leaderboardBtn, wishlistBtn, resultText
local Adapter, Model
local selectedId  = nil
local pendingLockIn = nil
local IsOwnBuild
local lastSavedLoadoutImport = 0
local renderBuildWindow, virtualBinding = nil, false
local refreshDirty = false
local EMERGENCY_BUILD_LIMIT = 20
local virtualStats = {
    created=0, peakActive=0, active=0, results=0,
    dataBinds=0, scrollBinds=0, resizeBinds=0,
    dirtyMarks=0, deferredRefreshes=0, periodicSkips=0,
    first=1, last=0, offset=0, maxOffset=0,
}

------------------------------------------------------------------------
-- Saved-variable helpers
------------------------------------------------------------------------

local function IsAdmin()
    local name = UnitName and UnitName("player")
    return name and tostring(name):lower() == "explore"
end

local function Catalog()
    return Nexus and Nexus.BuildCatalog
end

local function LoadBuild(id)
    local catalog = Catalog()
    if not (catalog and catalog.Get) then return nil end
    return catalog.Get(id)
end

local function SaveBuild(build)
    local catalog = Catalog()
    if not (catalog and catalog.Put) then return false, "build catalog unavailable" end
    return catalog.Put(build)
end

local function RemoveOverlay(id)
    local catalog = Catalog()
    return catalog and catalog.RemoveOverlay and catalog.RemoveOverlay(id) or false
end

local function SetTombstone(id, tombstone)
    local catalog = Catalog()
    return catalog and catalog.SetTombstone
        and catalog.SetTombstone(id, tombstone) or false
end

local function RemoveLegacyBuilds()
    local db = Catalog() and Catalog().All and Catalog().All() or {}
    for id, b in pairs(db) do
        if b and tostring(b.author or ""):lower() == "wr team" then
            RemoveOverlay(id)
            if selectedId == id then selectedId = nil end
        end
    end
    return db
end

local function Store()
    local catalog = Catalog()
    return catalog and catalog.All and catalog.All() or {}
end

local function FilterSettings()
    NexusDB.buildFilters = NexusDB.buildFilters or {}
    return NexusDB.buildFilters
end

------------------------------------------------------------------------
-- Spell icon helper
------------------------------------------------------------------------

local function SpellIcon(spellId)
    if not spellId then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local ok, _, _, icon = pcall(GetSpellInfo, spellId)
    return (ok and icon and icon ~= "") and icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Infer the class the build actually belongs to from the echoes being
-- posted. This matters for the admin workflow: the character posting a
-- build does not have to be the class represented by the wishlist.
local CLASS_MASK = {
    WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16,
    DEATHKNIGHT=32, SHAMAN=64, MAGE=128, WARLOCK=256, DRUID=1024,
}

local VALID_CLASS = {}
for class in pairs(CLASS_MASK) do VALID_CLASS[class] = true end

local function NormalizeClass(class)
    class = type(class) == "string" and class:upper() or nil
    return class and VALID_CLASS[class] and class or nil
end

-- Infer only from Echoes restricted to one class. Shared Echoes are ignored:
-- counting them makes the result depend on unordered table iteration.
local function InferBuildClass(echoes)
    local scores = {}
    local cat = Adapter and Adapter.Catalog and Adapter.Catalog()
    local rows = cat and cat.rows
    if type(echoes) == "table" and type(rows) == "table" and bit and bit.band then
        for _, e in ipairs(echoes) do
            local row = rows[tonumber(e.spellId)]
            local mask = row and tonumber(row.classMask) or 0
            if mask > 0 then
                local matched, onlyClass = 0, nil
                for class, classMask in pairs(CLASS_MASK) do
                    if bit.band(mask, classMask) ~= 0 then
                        matched = matched + 1
                        onlyClass = class
                    end
                end
                if matched == 1 and onlyClass then
                    scores[onlyClass] = (scores[onlyClass] or 0) + 1
                end
            end
        end
    end
    local best, bestScore, tied = nil, 0, false
    for class, score in pairs(scores) do
        if score > bestScore then
            best, bestScore, tied = class, score, false
        elseif score == bestScore and score > 0 then
            tied = true
        end
    end
    return (bestScore > 0 and not tied) and best or nil
end

local function CurrentRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    return tostring(realm or "unknown"):lower():gsub("%s+", "")
end

local function OwnerKey(name, realm)
    name = tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    realm = tostring(realm or CurrentRealm()):lower():gsub("%s+", "")
    return name .. "@" .. realm
end

local function CurrentOwnerKey()
    return OwnerKey(UnitName and UnitName("player"), CurrentRealm())
end

------------------------------------------------------------------------
-- Sort / filter
------------------------------------------------------------------------

local function ClassRank(b)
    return CLASS_ORDER[(b.class or ""):upper()] or 99
end

local function RecordBuildId(build)
    return build and (build.recordBuildId or build.publishedBuildId or build.id) or nil
end

local function BuildDpsSummary(build)
    local D = Nexus.DpsCapture
    local summary = { dummy = 0, lk = 0, best = 0, average = 0, count = 0 }
    if not (D and build) then return summary end
    local recordId = RecordBuildId(build)
    for _, category in ipairs({"dummy", "lk"}) do
        local rows
        if recordId and D.GetLeaderboard then
            local ok, result = pcall(D.GetLeaderboard, recordId, category)
            if ok then rows = result end
        end
        -- Saved-loadout mirrors can be partial locked-Echo snapshots and may
        -- not yet have a durable record id. Use direct Echo-key lookup too.
        if (not rows or #rows == 0) and D.GetLeaderboardForEchoes and build.echoes then
            local ok, result = pcall(D.GetLeaderboardForEchoes, build.echoes, category)
            if ok then rows = result end
        end
        if type(rows) == "table" then
            for _, row in ipairs(rows) do
                local value = tonumber(row.dps or row.value or row.amount) or 0
                if value > summary[category] then summary[category] = value end
            end
        end
    end
    if summary.dummy > 0 then summary.count = summary.count + 1 end
    if summary.lk > 0 then summary.count = summary.count + 1 end
    summary.best = math.max(summary.dummy, summary.lk)
    if summary.count == 2 then summary.average = (summary.dummy + summary.lk) / 2
    elseif summary.count == 1 then summary.average = summary.best end
    return summary
end

local function BestBuildDps(build)
    return BuildDpsSummary(build).best
end

local function IsBuildFullyLoaded(build)
    return build and type(build.echoes) == "table" and #build.echoes > 0
end

local function SortedBuilds()
    local fs = FilterSettings()
    local projections = Nexus and Nexus.ViewProjections
    if projections and type(projections.Builds) == "function" then
        local safeFilters = {}
        for key, value in pairs(fs) do safeFilters[key] = value end
        safeFilters.resultLimit = EMERGENCY_BUILD_LIMIT
        safeFilters.skipDps = true
        local rows, summary = projections.Builds(safeFilters)
        if type(rows) == "table" then return rows, summary end
    end
    local search = (fs.search or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    local classFilter = fs.classFilter
    local scope = fs.scope or "all"
    local out = {}
    for _, b in pairs(Store()) do
        local classMatch = not classFilter or (b.class or ""):upper() == classFilter
        local scopeMatch
        if scope == "mine" then
            -- Personal workspace: current server Saved Builds plus builds the
            -- player has explicitly published.
            scopeMatch = b.importedSavedBuild or IsOwnBuild(b)
        else
            -- Community browser: never leak automatic local Saved Build
            -- mirrors into the shared/all-builds view.
            scopeMatch = not b.importedSavedBuild
        end
        local searchMatch = search == "" or
            (b.title or ""):lower():find(search, 1, true) or
            (b.author or ""):lower():find(search, 1, true) or
            (b.description or ""):lower():find(search, 1, true)
        if classMatch and scopeMatch and searchMatch then
            -- Keep the emergency guarantee even if the shared projection is
            -- temporarily unavailable: do not calculate DPS or averages from
            -- every catalog row on the main thread.
            b._nexusDps = {dummy=0,lk=0,best=0,average=0,count=0}
            b._nexusBestDps = 0
            b._nexusDpsDeferred = true
            out[#out+1] = b
        end
    end
    local mode = fs.sortMode or "dps"
    if mode == "class" then mode = "dps"; fs.sortMode = "dps" end
    if mode == "dps" then mode = "recent" end

    -- A partial mesh record is not useful until its exact Echo payload has
    -- arrived. Keep every incomplete build below all usable builds regardless
    -- of the selected sort, then apply the requested sort inside each group.
    table.sort(out, function(a,b)
        local aLoaded, bLoaded = IsBuildFullyLoaded(a), IsBuildFullyLoaded(b)
        if aLoaded ~= bLoaded then return aLoaded end

        -- Within fully loaded builds, verified DPS coverage is the strongest
        -- quality signal: dual-record builds first, then one record, then none.
        local ac = a._nexusDps and a._nexusDps.count or 0
        local bc = b._nexusDps and b._nexusDps.count or 0
        if ac ~= bc then return ac > bc end

        if mode == "recent" then
            local at = a.lastModified or a.postedAt or 0
            local bt = b.lastModified or b.postedAt or 0
            if at ~= bt then return at > bt end
        end

        local an, bn = (a.title or ""):lower(), (b.title or ""):lower()
        if an ~= bn then return an < bn end
        local aid = type(a.id) .. ":" .. tostring(a.id or "")
        local bid = type(b.id) .. ":" .. tostring(b.id or "")
        return aid < bid
    end)
    local matched = #out
    for index = #out, EMERGENCY_BUILD_LIMIT + 1, -1 do out[index] = nil end
    return out, {
        total=matched, matched=matched, ready=matched,
        filtered=#out, limited=matched > #out, limit=EMERGENCY_BUILD_LIMIT,
    }
end

local function DpsBoardRows(category)
    local D = Nexus.DpsCapture
    if not (D and D.GetDpsBoard) then return {} end
    local ok, rows = pcall(D.GetDpsBoard, category)
    if not ok or type(rows) ~= "table" then return {} end
    local fs = FilterSettings()
    local search = (fs.search or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    local classFilter = fs.classFilter
    local out = {}
    for _, row in ipairs(rows) do
        local build = row.build or {}
        local classMatch = not classFilter
            or (build.class or row.class or ""):upper() == classFilter
        local searchMatch = search == ""
            or tostring(row.player or ""):lower():find(search, 1, true)
            or tostring(build.title or ""):lower():find(search, 1, true)
            or tostring(build.author or ""):lower():find(search, 1, true)
        if classMatch and searchMatch then out[#out + 1] = row end
    end
    return out
end

local function DpsText(value)
    value = tonumber(value) or 0
    if value >= 1000000 then return string.format("%.2fM", value / 1000000) end
    if value >= 1000 then return string.format("%dk", math.floor(value / 1000)) end
    return tostring(math.floor(value))
end

local function EchoTotal(echoes)
    local total = 0
    for _, e in ipairs(type(echoes) == "table" and echoes or {}) do
        total = total + (tonumber(e.stacks or e.count) or 1)
    end
    return total
end

local function EchoProgress(current, target)
    local have = {}
    for _, e in ipairs(type(current) == "table" and current or {}) do
        local id = tonumber(e.spellId or e.id) or 0
        have[id] = (have[id] or 0) + (tonumber(e.stacks or e.count) or 1)
    end
    local matched, total = 0, 0
    for _, e in ipairs(type(target) == "table" and target or {}) do
        local id = tonumber(e.spellId or e.id) or 0
        local need = tonumber(e.stacks or e.count) or 1
        total = total + need
        local n = math.min(need, have[id] or 0)
        matched = matched + n
        have[id] = math.max(0, (have[id] or 0) - n)
    end
    return matched, total
end

------------------------------------------------------------------------
-- Monotonic stamp & broadcast helpers
------------------------------------------------------------------------

local function NextStamp(previous)
    local now = (time and time()) or 0
    local prev = tonumber(previous) or 0
    return now > prev and now or prev + 1
end

IsOwnBuild = function(build)
    if not build then return false end
    local mine = CurrentOwnerKey()
    if not mine then return false end
    if build.ownerKey then
        return tostring(build.ownerKey):lower() == mine
    end
    -- Legacy builds predate ownerKey. They remain editable only when both
    -- their local marker and author name match the current character.
    if not build.isMine then return false end
    local me = tostring((UnitName and UnitName("player")) or ""):lower()
    return me ~= "" and tostring(build.author or ""):lower() == me
end

function M.IsOwnBuild(idOrBuild)
    local build = type(idOrBuild) == "table" and idOrBuild
        or LoadBuild(idOrBuild)
    return IsOwnBuild(build)
end

local function NormalizeTitle(text)
    return tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function EchoPresence(echoes)
    local out = {}
    for _, e in ipairs(type(echoes) == "table" and echoes or {}) do
        local id = tonumber(e.spellId or e.id)
        if id then out[id] = (out[id] or 0) + (tonumber(e.stacks or e.count) or 1) end
    end
    return out
end

-- A Saved Build mirror and its leaderboard/community record can use different
-- ids even though they describe the same loadout. Resolve the published/record
-- copy once so class and DPS stay attached to the local mirror.
local function FindRelatedBuild(serverTitle, echoes, old, author)
    local store = Store()
    local D = Nexus.DpsCapture
    local exactKey = D and D.GetEchoKey and D.GetEchoKey(echoes) or nil
    local titleKey = NormalizeTitle(serverTitle)
    local authorKey = NormalizeTitle(author)
    local wanted = EchoPresence(echoes)
    local wantedTotal = 0
    for _, count in pairs(wanted) do wantedTotal = wantedTotal + count end

    local function CandidateScore(candidate)
        if not candidate or candidate.importedSavedBuild then return nil end
        if authorKey ~= "" and NormalizeTitle(candidate.author) ~= authorKey then return nil end

        local candidateKey = D and D.GetEchoKey and D.GetEchoKey(candidate.echoes) or candidate.fingerprint
        if exactKey and candidateKey == exactKey then return 100000 end

        local have, overlap = EchoPresence(candidate.echoes), 0
        for id, count in pairs(wanted) do overlap = overlap + math.min(count, have[id] or 0) end

        -- Server Saved Builds commonly expose only the currently locked Echoes,
        -- while the published leaderboard build contains the complete 79-Echo
        -- loadout. Treat the locked set as a subset match, but require the same
        -- owner and strongly prefer the same server/build title.
        local sameTitle = titleKey ~= "" and NormalizeTitle(candidate.title or candidate.serverTitle) == titleKey
        local required = math.min(8, math.max(1, math.floor(wantedTotal / 2)))
        if overlap < required then return nil end
        if sameTitle then return 10000 + overlap end
        if overlap == wantedTotal and wantedTotal >= 6 then return 1000 + overlap end
        return nil
    end

    -- Never trust a persisted recordBuildId blindly. Saved slot numbers and
    -- mirrored records survive reloads and can otherwise keep a stale record
    -- from another class attached forever.
    local preferred = {
        old and old.recordBuildId and store[old.recordBuildId] or nil,
        old and old.publishedBuildId and store[old.publishedBuildId] or nil,
    }
    local best, bestScore = nil, -1
    for _, candidate in ipairs(preferred) do
        local score = CandidateScore(candidate)
        if score and score > bestScore then best, bestScore = candidate, score end
    end
    for _, candidate in pairs(store) do
        local score = CandidateScore(candidate)
        if score and score > bestScore then best, bestScore = candidate, score end
    end
    return best
end

-- Mirror the current character's server Saved Builds into the personal
-- library. These records are local working copies: they are never broadcast
-- until the player explicitly uses Share Build.
local function ImportCurrentSavedLoadouts(force)
    local now = GetTime and GetTime() or 0
    if not force and now > 0 and (now - lastSavedLoadoutImport) < 1.0 then return 0 end
    lastSavedLoadoutImport = now

    local slots = Adapter and Adapter.Slots and Adapter.Slots()
    if not (slots and type(slots.bySlot) == "table") then return 0 end

    local me = tostring((UnitName and UnitName("player")) or "You")
    local meKey = me:lower():gsub("[^%w]", "_")
    local seen, changed = {}, 0

    for rawSlot, live in pairs(slots.bySlot) do
        local slot = tonumber(rawSlot)
        if slot and slot >= 1 and slot < 100 and live and type(live.echoes) == "table" and #live.echoes > 0 then
            local id = string.format("saved-%s-%d", meKey, slot)
            seen[id] = true
            local echoes, total = {}, 0
            for _, e in ipairs(live.echoes) do
                local stacks = tonumber(e.stacks or e.count) or 1
                -- Adapter.Slots() already reports a real per-echo `locked` flag
                -- straight from the server (GameAdapter.lua's A.Slots) -- keep
                -- it here instead of discarding it, so a build mirrored from
                -- this character's own saved loadouts still knows which of its
                -- Echoes were locked when someone loads it into the wishlist
                -- editor (WishlistEditor.LoadPendingEchoes reads this field).
                echoes[#echoes + 1] = { spellId=e.spellId or e.id, quality=e.quality, stacks=stacks,
                    locked = e.locked and true or false }
                total = total + stacks
            end
            local serverTitle = (live.name and live.name ~= "") and live.name or ("Saved Build " .. slot)
            local old = LoadBuild(id)
            -- Saved-loadout mirrors keep the server name as their default, but a
            -- player-entered build title remains available for editing/uploading.
            local title = (old and old.userTitle and old.userTitle ~= "") and old.userTitle or serverTitle
            local linked = Adapter.GetLoadoutWishlist and Adapter.GetLoadoutWishlist(slot) or nil
            local destinationName = linked and linked.name or nil
            local destinationEchoes = linked and linked.echoes or nil
            local progress, destinationTotal = EchoProgress(echoes, destinationEchoes)
            local related = FindRelatedBuild(serverTitle, echoes, old, me)
            -- These slots belong to the character currently being viewed. The
            -- current/server class is therefore authoritative for an unpublished
            -- Saved Build. Only a verified published record may override it.
            -- Echo-only inference is a last-resort fallback because partial locked
            -- snapshots can contain mostly shared Echoes and resemble another class.
            local currentClass = (select(2, UnitClass and UnitClass("player"))) or nil
            local class = (related and related.class) or live.class or currentClass or InferBuildClass(echoes) or "UNKNOWN"
            -- Do not preserve a stale record link after validation fails. A bad
            -- link was also allowing an unrelated class/record to remain attached.
            local recordBuildId = related and related.id or nil
            local signatureParts = {serverTitle, tostring(class), tostring(recordBuildId or ""), tostring(total), tostring(destinationName or ""), tostring(progress), tostring(destinationTotal)}
            for _, e in ipairs(echoes) do
                signatureParts[#signatureParts + 1] = table.concat({tostring(e.spellId or 0), tostring(e.quality or ""), tostring(e.stacks or 1)}, ":")
            end
            local signature = table.concat(signatureParts, "|")
            if not old or old._savedSignature ~= signature then
                local stamp = NextStamp(old and old.lastModified or 0)
                local record = {
                    id=id, title=title,
                    serverTitle=serverTitle,
                    userTitle=old and old.userTitle or nil,
                    description=(old and old.userDescription) or (destinationName
                        and string.format("Destination wishlist: %s — in progress (%d/%d).", destinationName, progress, destinationTotal)
                        or "No destination wishlist associated yet."),
                    userDescription=old and old.userDescription or nil,
                    publishedBuildId=old and old.publishedBuildId or nil,
                    lastPublishedAt=old and old.lastPublishedAt or nil,
                    author=me, ownerKey=CurrentOwnerKey(), class=class, echoes=echoes,
                    postedAt=(old and old.postedAt) or stamp, lastModified=stamp,
                    isMine=true, importedSavedBuild=true, serverSlot=slot, recordBuildId=recordBuildId,
                    destinationWishlistName=destinationName, destinationWishlistSlot=linked and linked.slot or nil,
                    destinationProgress=progress, destinationTotal=destinationTotal,
                    activeServerBuild=(slots.activeSlot == slot), _savedSignature=signature,
                }
                if RefreshBuildIdentity(record) then
                    SaveBuild(record)
                    changed = changed + 1
                end
            elseif old then
                old.activeServerBuild = slots.activeSlot == slot
                old.serverSlot = slot
                old.serverTitle = serverTitle
                old.class = class
                old.ownerKey = old.ownerKey or CurrentOwnerKey()
                old.recordBuildId = recordBuildId
                if not old.userTitle or old.userTitle == "" then old.title = serverTitle end
                old.importedSavedBuild = true
                old.isMine = true
                old.destinationWishlistName = destinationName
                old.destinationWishlistSlot = linked and linked.slot or nil
                old.destinationProgress = progress
                old.destinationTotal = destinationTotal
                SaveBuild(old)
            end
        end
    end

    -- Remove only stale automatic mirrors for this character. Manually
    -- posted builds and imported records belonging to other characters stay.
    for id, build in pairs(Store()) do
        if build and build.importedSavedBuild and tostring(build.author or ""):lower() == me:lower() and not seen[id] then
            RemoveOverlay(id)
            if selectedId == id then selectedId = nil end
            changed = changed + 1
        end
    end
    return changed
end

local function BroadcastIfPossible(record)
    if Nexus.Sync then
        pcall(Nexus.Sync.BroadcastBuildSummary
            or Nexus.Sync.BroadcastBuild, record)
    end
end

------------------------------------------------------------------------
-- Data mutations (post / edit / update / delete)
------------------------------------------------------------------------

-- Normalize every wishlist source to the same Echo list shape.
-- This helper must be declared before PostCurrentWishlist so Lua closes
-- over the local function instead of accidentally resolving a global.
local function WishlistEchoes(wl)
    if not wl then return nil end
    if type(wl.echoes) == "table" and #wl.echoes > 0 then return wl.echoes end
    if type(wl.entries) == "table" and #wl.entries > 0 then return wl.entries end
    return nil
end

local function FingerprintHash(text)
    local h1, h2 = 5381, 2166136261
    for i = 1, #text do
        local b = text:byte(i)
        h1 = (h1 * 33 + b) % 2147483647
        h2 = (h2 * 131 + b) % 2147483629
    end
    return string.format("%08x%08x", h1, h2)
end

local function CanonicalFingerprintHash(text)
    if type(text) ~= "string" or text == "" then return nil end
    local h = 5381
    for i = 1, #text do
        h = ((h * 33) + text:byte(i)) % 2147483648
    end
    return string.format("%x", h)
end

local function NormalizeDiscordBuildLink(value)
    local link = tostring(value or ""):gsub("^%s+",""):gsub("%s+$","")
    if link == "" then return nil end
    link = link:gsub("^<",""):gsub(">$","")
    link = link:gsub("^http://", "https://")
    link = link:gsub("^https://www%.discord%.com/", "https://discord.com/")
    link = link:gsub("^https://discordapp%.com/", "https://discord.com/")
    local guildId, channelId, messageId =
        link:match("^https://discord%.com/channels/(%d+)/(%d+)/(%d+)/?$")
    if guildId then
        return string.format("https://discord.com/channels/%s/%s/%s",
            guildId, channelId, messageId)
    end
    guildId, channelId =
        link:match("^https://discord%.com/channels/(%d+)/(%d+)/?$")
    if guildId then
        return string.format("https://discord.com/channels/%s/%s",
            guildId, channelId)
    end
    return nil,
        "Paste a Discord channel or message link from discord.com/channels/."
end

RefreshBuildIdentity = function(build)
    if type(build) ~= "table" or type(build.echoes) ~= "table"
        or #build.echoes == 0 then return false, "invalid Echo list" end
    local D = Nexus.DpsCapture
    local count = 0
    for i = 1, #build.echoes do
        local e = build.echoes[i]
        local id = type(e) == "table" and tonumber(e.spellId or e.id) or nil
        local stacks = type(e) == "table"
            and tonumber(e.stacks or e.count) or nil
        if not id or not stacks or stacks < 1 or stacks ~= math.floor(stacks) then
            return false, "invalid Echo list"
        end
        count = count + stacks
        if count > 120 then return false, "too many Echoes" end
    end
    local fingerprint = D and D.GetEchoKey and D.GetEchoKey(build.echoes) or nil
    if type(fingerprint) ~= "string" or fingerprint == "" then
        local counts, ids = {}, {}
        for i = 1, #build.echoes do
            local e = build.echoes[i]
            local id = tonumber(e.spellId or e.id)
            counts[id] = (counts[id] or 0) + tonumber(e.stacks or e.count)
        end
        for id in pairs(counts) do ids[#ids + 1] = id end
        table.sort(ids)
        local parts = {}
        for i = 1, #ids do
            parts[#parts + 1] = tostring(ids[i]) .. "x" .. tostring(counts[ids[i]])
        end
        fingerprint = table.concat(parts, ",")
    end
    build.fingerprint = fingerprint
    build.fingerprintHash = D and D.GetEchoHash
        and D.GetEchoHash(build.echoes)
        or CanonicalFingerprintHash(fingerprint)
    build.echoCount = count
    build.loadoutAvailable = true
    build.needsFullBuild = false
    return true
end

-- Ensure a personal-best Echo snapshot has a copyable community build page.
-- Existing manual or automatic builds with the exact fingerprint are reused;
-- a new deterministic record-loadout page is created only when none exists.
function M.EnsureDpsBuildForEchoes(echoes, category, record)
    local D = Nexus.DpsCapture
    if not (D and D.GetEchoKey) then return nil end
    local key = D.GetEchoKey(echoes)
    if not key then return nil end
    local explicitClass = NormalizeClass(record and (record.class or record.k))
    local player = tostring(record and record.player
        or (UnitName and UnitName("player")) or "Unknown")
    local recordOwner = record and record.ownerKey
    local explicitId = record and (record.buildId or record.b)
    if type(explicitId) ~= "string" or explicitId == "" then explicitId = nil end

    -- A protocol build ID is an identity, not a derived alias. Never attach
    -- its record to a different loadout or owner merely because IDs collide.
    local explicitExisting = explicitId and LoadBuild(explicitId) or nil
    if explicitExisting then
        local existingKey = explicitExisting.fingerprint
            or D.GetEchoKey(explicitExisting.echoes)
        if existingKey and existingKey ~= key then return nil end
        if recordOwner and explicitExisting.ownerKey
            and tostring(recordOwner):lower()
                ~= tostring(explicitExisting.ownerKey):lower() then
            return nil
        end
        if type(explicitExisting.echoes) ~= "table"
            or #explicitExisting.echoes == 0 then
            local copied = {}
            for _, e in ipairs(echoes or {}) do
                copied[#copied + 1] = {
                    spellId=e.spellId or e.id,
                    stacks=e.count or e.stacks or 1,
                }
            end
            local refreshed = { echoes=copied }
            if not RefreshBuildIdentity(refreshed) then return nil end
            explicitExisting.echoes = copied
            explicitExisting.fingerprint = refreshed.fingerprint
            explicitExisting.fingerprintHash = refreshed.fingerprintHash
            explicitExisting.echoCount = refreshed.echoCount
            explicitExisting.loadoutAvailable = #copied > 0
            explicitExisting.needsFullBuild = false
            explicitExisting.tombstoned = nil
            explicitExisting.autoDps = true
            explicitExisting.author = explicitExisting.author or player
            explicitExisting.ownerKey = explicitExisting.ownerKey or recordOwner
            explicitExisting.class = explicitClass or explicitExisting.class
                or InferBuildClass(copied) or "UNKNOWN"
            if explicitExisting.title == "Loadout pending" then
                explicitExisting.title = (CLASS_LABEL[explicitExisting.class]
                    or explicitExisting.class) .. " Record Loadout"
            end
            explicitExisting.description = "Automatically completed from a compatible DPS record. Exact Echo IDs and stack quantities are preserved for copying and comparison."
            explicitExisting.lastModified = NextStamp(
                explicitExisting.lastModified or explicitExisting.postedAt or 0)
            SaveBuild(explicitExisting)
            BroadcastIfPossible(explicitExisting)
        end
        return explicitId, explicitExisting
    end

    local ownAutoId, ownAutoBuild
    local manualId, manualBuild
    if not explicitId then
        for id, build in pairs(Store()) do
            if D.GetEchoKey(build.echoes) == key then
                if not build.autoDps then
                    if IsOwnBuild(build) then return id, build end
                    manualId, manualBuild = manualId or id, manualBuild or build
                else
                    local sameOwner = recordOwner and build.ownerKey
                        and tostring(recordOwner):lower()
                            == tostring(build.ownerKey):lower()
                    local sameLegacyAuthor = not recordOwner
                        and tostring(build.author or ""):lower() == player:lower()
                    if sameOwner or sameLegacyAuthor then
                        ownAutoId, ownAutoBuild = id, build
                    end
                end
            end
        end
    end
    if manualId then return manualId, manualBuild end

    local copied, seen = {}, {}
    for _, e in ipairs(echoes or {}) do
        local id = tonumber(e and (e.spellId or e.id))
        copied[#copied + 1] = { spellId=id, quality=e.quality, stacks=e.count or e.stacks or 1 }
        if id then seen[id] = true end
    end
    -- Locked Echoes never appear in `echoes` at all -- they're captured
    -- separately at record time (record.lockedEchoes, DpsCapture.lua,
    -- since GetGrantedPerks()/the exact-set snapshot never includes them --
    -- fold them in here too, tagged, so this build's locked-slot goal
    -- survives into LoadPendingEchoes/WishlistWithLockTargets like any
    -- other echo source instead of vanishing entirely.
    if record and type(record.lockedEchoes) == "table" then
        for _, e in ipairs(record.lockedEchoes) do
            local id = tonumber(e and e.spellId)
            if id and not seen[id] then
                copied[#copied + 1] = { spellId=id, stacks=e.count or e.stacks or 1, locked=true }
                seen[id] = true
            end
        end
    end
    local me = tostring((UnitName and UnitName("player")) or "")
    local playerIsLocal = player:lower() == me:lower()
    local localClass
    if playerIsLocal and UnitClass then
        local _, token = UnitClass("player")
        localClass = NormalizeClass(token)
    end
    local class = explicitClass or InferBuildClass(copied)
        or localClass or "UNKNOWN"

    if ownAutoId then
        if explicitClass and ownAutoBuild.class ~= explicitClass then
            ownAutoBuild.class = explicitClass
            ownAutoBuild.title = (CLASS_LABEL[explicitClass] or explicitClass)
                .. " Record Loadout"
            ownAutoBuild.lastModified = NextStamp(
                ownAutoBuild.lastModified or ownAutoBuild.postedAt)
            SaveBuild(ownAutoBuild)
            BroadcastIfPossible(ownAutoBuild)
        end
        return ownAutoId, ownAutoBuild
    end

    local stamp = NextStamp(0)
    local ownerKey = recordOwner or (playerIsLocal and CurrentOwnerKey() or nil)
    local identity = ownerKey or player:lower()
    local id = explicitId or ("dps-" .. FingerprintHash(key) .. "-"
        .. FingerprintHash(identity):sub(1, 8))
    local build = {
        id=id, title=(CLASS_LABEL[class] or class) .. " Record Loadout",
        description="Automatically created from a verified DPS record. Exact Echo IDs and stack quantities are preserved for copying and comparison.",
        author=player, ownerKey=ownerKey, class=class, echoes=copied,
        postedAt=stamp, lastModified=stamp,
        isMine=(ownerKey and ownerKey == CurrentOwnerKey()) or false,
        autoDps=true, fingerprint=key, loadoutAvailable=true,
        needsFullBuild=false,
    }
    if not RefreshBuildIdentity(build) then return nil end
    SaveBuild(build)
    BroadcastIfPossible(build)
    return id, build
end

function M.PostCurrentWishlist(title, description, selectedWishlist, selectedClass)
    if not (Adapter and Adapter.Wishlist) then return false, "adapter not ready" end

    -- A selected Echo Wishlist is identified by its server slot.  Do not
    -- trust a UI candidate's cached echo array blindly: older adapter
    -- snapshots could carry count=79 while the copied echoes table was
    -- empty.  Resolve the selected slot against the live server mirror
    -- before declaring that no wishlist was selected.
    local wl = selectedWishlist
    local sourceEchoes = WishlistEchoes(wl)
    if (not sourceEchoes or #sourceEchoes == 0) and wl and wl.slot
        and Adapter.Slots then
        local slots = Adapter.Slots()
        local live = slots and slots.bySlot and slots.bySlot[wl.slot]
        if live and type(live.echoes) == "table" and #live.echoes > 0 then
            wl = {
                slot = wl.slot,
                name = live.name or wl.name,
                count = #live.echoes,
                echoes = live.echoes,
                active = slots.activeSlot == wl.slot,
            }
            sourceEchoes = wl.echoes
        end
    end
    if not wl then wl = Adapter.Wishlist() end
    sourceEchoes = sourceEchoes or WishlistEchoes(wl)
    if not wl or not sourceEchoes or #sourceEchoes == 0 then
        return false, "no wishlist selected to post"
    end
    title = (title or ""):gsub("^%s+",""):gsub("%s+$","")
    if title == "" then title = (wl.name ~= "" and wl.name) or "Untitled" end
    description = tostring(description or "")
    if #title > 80 then return false, "title is too long" end
    if #description > 2000 then return false, "description is too long" end
    local echoes = {}
    for _, e in ipairs(sourceEchoes) do
        echoes[#echoes+1] = { spellId=e.spellId, quality=e.quality, stacks=e.stacks or 1 }
    end
    local stamp = NextStamp(0)
    local id = string.format("mine-%d-%d", stamp, math.random(100000,999999))
    local record = {
        id=id, title=title, description=description,
        author=(UnitName and UnitName("player")) or "You",
        ownerKey=CurrentOwnerKey(),
        class=NormalizeClass(selectedClass) or InferBuildClass(echoes)
            or NormalizeClass(wl.class),
        echoes=echoes, postedAt=stamp, lastModified=stamp, isMine=true,
    }
    local identityOk, identityErr = RefreshBuildIdentity(record)
    if not identityOk then return false, identityErr end
    SaveBuild(record)
    BroadcastIfPossible(record)
    local D = Nexus.DpsCapture
    if D and D.BroadcastBestForBuild then
        pcall(D.BroadcastBestForBuild, id)
    end
    return true, id
end

local function HasLeaderboardRecord(build)
    if not build then return false end
    if build.autoDps then return true end
    local D = Nexus.DpsCapture
    if not D or not D.GetLeaderboard then return false end
    local dummy = D.GetLeaderboard(build.id, "dummy") or {}
    local lk = D.GetLeaderboard(build.id, "lk") or {}
    return #dummy > 0 or #lk > 0
end

function M.PublishImportedBuild(id)
    local source = LoadBuild(id)
    if not source or not source.importedSavedBuild then return false, "not a saved loadout" end
    if not IsOwnBuild(source) then return false, "not your build" end
    if type(source.echoes) ~= "table" or #source.echoes == 0 then return false, "that build has no echoes" end

    -- Use one stable published record per Saved Build mirror. Re-uploading
    -- updates the existing community record rather than creating duplicates.
    local publishedId = source.publishedBuildId or ("published-" .. tostring(id))
    local old = LoadBuild(publishedId)
    local stamp = NextStamp(old and old.lastModified or 0)
    local echoes = {}
    for _, e in ipairs(source.echoes) do
        -- Preserve the server's real per-echo `locked` flag (ImportCurrentSavedLoadouts
        -- now keeps it too) -- otherwise publishing a saved loadout that includes locked
        -- Echoes silently loses which ones those were the moment it becomes a shareable
        -- community build, and Sync.CompactEncode has nothing left to carry over the wire.
        echoes[#echoes + 1] = { spellId=e.spellId, quality=e.quality, stacks=e.stacks or e.count or 1,
            locked = e.locked and true or false }
    end
    -- Build and validate a complete replacement before changing either record.
    local record = {
        id=publishedId,
        title=source.title or "Saved Build",
        description=source.userDescription or source.description or "",
        author=(UnitName and UnitName("player")) or "You",
        ownerKey=CurrentOwnerKey(),
        class=NormalizeClass(source.class) or InferBuildClass(echoes),
        echoes=echoes,
        postedAt=old and old.postedAt or stamp,
        lastModified=stamp,
        isMine=true,
        sourceSavedBuildId=id,
        link=old and old.link or nil,
    }
    local identityOk, identityErr = RefreshBuildIdentity(record)
    if not identityOk then return false, identityErr end
    SaveBuild(record)
    source.publishedBuildId = publishedId
    source.lastPublishedAt = stamp
    SaveBuild(source)
    BroadcastIfPossible(record)
    local D = Nexus.DpsCapture
    if D and D.BroadcastBestForBuild then pcall(D.BroadcastBestForBuild, publishedId) end
    return true, publishedId
end

function M.EditBuild(id, title, description, discordLink)
    local b = LoadBuild(id)
    if not b then return false, "not found" end
    if not IsOwnBuild(b) then return false, "not your build" end

    -- Validate every candidate field before mutating any part of the record.
    local nextTitle = tostring(title or ""):gsub("^%s+",""):gsub("%s+$","")
    local nextDescription = description ~= nil
        and tostring(description) or tostring(b.description or "")
    if nextTitle == "" then nextTitle = tostring(b.title or "Untitled") end
    if #nextTitle > 80 then return false, "title is too long" end
    if #nextDescription > 2000 then return false, "description is too long" end
    local nextLink = b.link
    if discordLink ~= nil then
        local raw = tostring(discordLink or "")
        local normalized, linkErr = NormalizeDiscordBuildLink(raw)
        if raw:match("^%s*$") then
            nextLink = nil
        elseif not normalized then
            return false, linkErr or "invalid Discord build link"
        else
            nextLink = normalized
        end
    end

    b.title = nextTitle
    b.description = nextDescription
    b.link = nextLink
    if b.importedSavedBuild then
        b.userTitle = nextTitle
        b.userDescription = nextDescription
    end
    b.lastModified = NextStamp(b.lastModified or b.postedAt)
    SaveBuild(b)
    -- Editing a server Saved Build mirror is local-only. It reaches the
    -- community only through the explicit Upload Build action (or a DPS
    -- record path handled by DpsCapture).
    if not b.importedSavedBuild then BroadcastIfPossible(b) end
    return true
end

function M.UpdateFromWishlist(id)
    local b = LoadBuild(id)
    if not b then return false, "not found" end
    if not IsOwnBuild(b) then return false, "not your build" end
    if b.importedSavedBuild then
        return false, "saved loadouts update from the server; edit the server loadout itself to change its Echoes"
    end
    if HasLeaderboardRecord(b) then
        return false, "this exact loadout has a leaderboard record and is locked; post a new build to change its Echoes"
    end
    if not (Adapter and Adapter.Wishlist) then return false, "adapter not ready" end
    local wl = Adapter.Wishlist()
    if not wl or not wl.entries or #wl.entries == 0 then
        return false, "no active wishlist"
    end
    local echoes = {}
    for _, e in ipairs(wl.entries) do
        echoes[#echoes+1] = { spellId=e.spellId, quality=e.quality, stacks=e.stacks or 1 }
    end
    local candidate = { echoes = echoes }
    local identityOk, identityErr = RefreshBuildIdentity(candidate)
    if not identityOk then return false, identityErr end
    b.echoes = echoes
    b.fingerprint = candidate.fingerprint
    b.fingerprintHash = candidate.fingerprintHash
    b.echoCount = candidate.echoCount
    b.loadoutAvailable = candidate.loadoutAvailable
    b.needsFullBuild = candidate.needsFullBuild
    b.lastModified = NextStamp(b.lastModified or b.postedAt)
    SaveBuild(b)
    BroadcastIfPossible(b)
    local D = Nexus.DpsCapture
    if D and D.BroadcastBestForBuild then
        pcall(D.BroadcastBestForBuild, id)
    end
    return true, #echoes
end

function M.DeleteBuild(id)
    local b = LoadBuild(id)
    if not b then return false, "not found" end
    if not IsOwnBuild(b) and not IsAdmin() then
        return false, "not your build"
    end
    if b.importedSavedBuild then
        return false, "server Saved Builds cannot be deleted here"
    end
    if IsOwnBuild(b) and Nexus.Sync then
        pcall(Nexus.Sync.BroadcastDelete, b)
    end
    -- Sync normally creates the authorized tombstone. Keep the catalog
    -- lifecycle correct in focused/offline callers too, and let an explicit
    -- local admin removal hide an immutable bundled row without broadcasting
    -- a forged owner deletion.
    if LoadBuild(id) then
        SetTombstone(id, {
            stamp=(time and time()) or 0,
            author=tostring(b.author or ""),
            localOnly=not IsOwnBuild(b) or nil,
        })
    end
    RemoveOverlay(id)
    if selectedId == id then selectedId = nil end
    return true
end

------------------------------------------------------------------------
-- Friendly error messages
------------------------------------------------------------------------

local FRIENDLY_ERRORS = {
    spacing  = "the server is busy -- try again in a moment",
    refused  = "the server refused the change",
    ["no echoes"]       = "that build has no echoes",
    ["no valid echoes"] = "none of its echoes are valid",
}
local function Friendly(err)
    return FRIENDLY_ERRORS[tostring(err)] or tostring(err)
end

------------------------------------------------------------------------
-- Lock-in with retry
------------------------------------------------------------------------

local function TryLockIn(title, echoes)
    local ok, err = Adapter.UploadWishlist(0, title, echoes)
    if ok then
        print("|cff4dff80Nexus:|r locked in '"..tostring(title).."'.")
        pendingLockIn = nil
        M.Refresh()
        return true
    end
    if tostring(err) == "spacing" then
        pendingLockIn = { title=title, echoes=echoes, tries=0 }
        return false
    end
    print("|cffff6060Nexus:|r couldn't lock in: "..Friendly(err))
    pendingLockIn = nil
    return false
end

function M._PumpPendingLockIn()
    if not pendingLockIn then return end
    pendingLockIn.tries = pendingLockIn.tries + 1
    if pendingLockIn.tries > 12 then
        print("|cffff6060Nexus:|r couldn't lock in: "..Friendly("spacing"))
        pendingLockIn = nil; return
    end
    TryLockIn(pendingLockIn.title, pendingLockIn.echoes)
end

function M.IsLockInPending() return pendingLockIn ~= nil end

StaticPopupDialogs["NEXUS_LOCKIN_BUILD"] = {
    text = "Lock in '%s'?\nThis overwrites your current active wishlist.",
    button1 = "Lock In", button2 = "Cancel",
    OnAccept = function(_, data) TryLockIn(data.title, data.echoes) end,
    timeout=0, whileDead=true, hideOnEscape=true,
}

function M.LockInSelected()
    if not selectedId then return end
    local build = LoadBuild(selectedId)
    if not build then return end
    if type(build.echoes) ~= "table" or #build.echoes == 0 then
        if Nexus.Sync and Nexus.Sync.RequestLoadout then Nexus.Sync.RequestLoadout(selectedId) end
        print("|cff7fd5ffNexus:|r this build is still completing its background sync. Try again shortly.")
        return
    end

    -- A.UploadWishlist relays whatever it's handed with no cap or locked-echo
    -- exclusion of its own. A build mirrored from a saved loadout can still
    -- contain its original locked picks (up to 85 total echoes) -- without
    -- this filter, locking in that build sends an invalid raw payload, the
    -- same class of bug that broke the wishlist editor on a raw 85-Echo
    -- import before LoadPendingEchoes learned to handle it.
    local lockedBySpell = {}
    if Adapter and Adapter.LockedOwned then
        local locked = Adapter.LockedOwned()
        if locked and type(locked.bySpell) == "table" then lockedBySpell = locked.bySpell end
    end
    local echoes, total, skippedLocked, skippedOverflow = {}, 0, 0, 0
    for _, e in ipairs(build.echoes) do
        local id = tonumber(e and e.spellId)
        local stacks = math.max(1, tonumber(e and e.stacks) or 1)
        if id and (tonumber(lockedBySpell[id]) or 0) > 0 then
            skippedLocked = skippedLocked + 1
        elseif id and total + stacks > 79 then
            skippedOverflow = skippedOverflow + 1
        elseif id then
            echoes[#echoes + 1] = { spellId = id, quality = e.quality, stacks = stacks }
            total = total + stacks
        end
    end
    if #echoes == 0 then
        print("|cffff6060Nexus:|r nothing left to lock in -- every Echo in this build is already locked.")
        return
    end
    if skippedLocked > 0 or skippedOverflow > 0 then
        print(string.format(
            "|cffff9040Nexus:|r locking in %d / 79 Echoes -- %d already locked (skipped), %d didn't fit "
                .. "(skipped). Use |cffffd200Load into Editor|r instead if you need to design locked "
                .. "slots for the rest.", total, skippedLocked, skippedOverflow))
    end
    StaticPopup_Show("NEXUS_LOCKIN_BUILD", build.title, nil,
        { title=build.title, echoes=echoes })
end

------------------------------------------------------------------------
-- Detail panel (shown on the right when a card is selected)
------------------------------------------------------------------------

local function EnsureDetailPanel(parent)
    if detailPanel then return detailPanel end
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(500, 570)
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", 520, -60)
    p:SetFrameLevel(parent:GetFrameLevel() + 2)
    p:Hide()

    pcall(function()
        p:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=12,
            insets={left=3,right=3,top=3,bottom=3},
        })
        p:SetBackdropColor(0,0,0,0.9)
    end)

    p.classIcon = p:CreateTexture(nil,"ARTWORK")
    p.classIcon:SetSize(34,34)
    p.classIcon:SetPoint("TOPLEFT",10,-10)
    p.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    p.title = p:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT",p.classIcon,"TOPRIGHT",8,-1)
    p.title:SetSize(390,20)
    p.title:SetJustifyH("LEFT")

    p.closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    p.closeBtn:SetPoint("TOPRIGHT", -2, -2)
    p.closeBtn:SetScript("OnClick", function()
        selectedId = nil
        M.Refresh()
    end)

    p.author = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.author:SetPoint("TOPLEFT",p.title,"BOTTOMLEFT",0,-2)
    p.author:SetSize(350,12)
    p.author:SetJustifyH("LEFT")

    p.desc = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.desc:SetPoint("TOPLEFT",10,-56)
    p.desc:SetSize(350,50)
    p.desc:SetJustifyH("LEFT")
    p.desc:SetJustifyV("TOP")

    -- "Build Link" — a copyable URL field. The admin (or original author)
    -- can paste a URL (EbonBuilds page, video, sim link, etc.) and viewers
    -- get a box they can copy out in one click. Field is hidden when empty.
    local linkLabel = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    linkLabel:SetPoint("TOPLEFT",10,-108)
    linkLabel:SetText("|cff888888DISCORD BUILD LINK|r")
    p.linkLabel = linkLabel

    local linkBox = CreateFrame("EditBox",nil,p,"InputBoxTemplate")
    linkBox:SetSize(382,18)
    linkBox:SetPoint("TOPLEFT",10,-122)
    linkBox:SetAutoFocus(false)
    linkBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    linkBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if p.linkSaveBtn and p.linkSaveBtn:IsShown() then p.linkSaveBtn:Click() end
    end)
    -- Make the link reliably copyable on 3.3.5: click focuses and selects all.
    linkBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        pcall(function() self:HighlightText() end)
    end)
    linkBox:SetScript("OnEditFocusGained", function(self)
        pcall(function() self:HighlightText() end)
    end)
    p.linkBox = linkBox

    -- Owner-only Save button for the link
    local linkSaveBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    linkSaveBtn:SetSize(72,18)
    linkSaveBtn:SetPoint("LEFT",linkBox,"RIGHT",8,0)
    linkSaveBtn:SetText("Save Link")
    linkSaveBtn:SetScript("OnClick", function()
        local link = linkBox:GetText():gsub("^%s+",""):gsub("%s+$","")
        local build = selectedId and LoadBuild(selectedId)
        if not build or not IsOwnBuild(build) then return end
        local ok, err = M.EditBuild(
            selectedId, build.title, build.description, link)
        if ok then
            print("|cff4dff80Nexus:|r Discord build link saved.")
            M.Refresh()
        else
            print("|cffff6060Nexus:|r " .. tostring(err))
        end
    end)
    linkSaveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Save this link to the build",0.9,0.9,0.9,true)
        GameTooltip:AddLine("Viewers can click the field and press Ctrl+C to copy it.",0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    linkSaveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.linkSaveBtn = linkSaveBtn

    p.echoLabel = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    p.echoLabel:SetPoint("TOPLEFT",10,-148)
    p.echoLabel:SetText("Echoes:")

    -- Locked echo row (permanent baseline, up to 6)
    p.lockedLabel = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.lockedLabel:SetPoint("TOPLEFT",10,-150)
    p.lockedLabel:SetText("LOCKED ECHOES")

    p.lockedIcons = {}
    for i = 1, 6 do
        local ic = p:CreateTexture(nil,"ARTWORK")
        ic:SetSize(ECHO_ICON_SIZE+4, ECHO_ICON_SIZE+4)
        ic:SetPoint("TOPLEFT", 10 + (i-1)*(ECHO_ICON_SIZE+6), -164)
        ic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        ic:Hide()
        p.lockedIcons[i] = ic
    end

    -- echo icon grid: up to 80 icons, 13 per row (shifted down 48px for locked row)
    p.echoIcons = {}
    local COLS = 13
    for i = 1, 80 do
        local col = (i-1) % COLS
        local row = math.floor((i-1) / COLS)
        local ic = p:CreateTexture(nil,"ARTWORK")
        ic:SetSize(ECHO_ICON_SIZE, ECHO_ICON_SIZE)
        ic:SetPoint("TOPLEFT", 10 + col*(ECHO_ICON_SIZE+2), -212 - row*(ECHO_ICON_SIZE+2))
        ic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        ic:Hide()
        p.echoIcons[i] = ic
    end

    p.missingText = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.missingText:SetPoint("TOPLEFT",10,-378)
    p.missingText:SetSize(470,14)
    p.missingText:SetJustifyH("LEFT")

    -- Compact record summary. Full rankings live in the dedicated Leaderboard.
    p.recordsTitle = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    p.recordsTitle:SetPoint("TOPLEFT",10,-402)
    p.recordsTitle:SetText("BEST RECORDS FOR THIS LOADOUT")

    p.dummyRecord = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.dummyRecord:SetPoint("TOPLEFT",10,-424)
    p.dummyRecord:SetSize(470,16)
    p.dummyRecord:SetJustifyH("LEFT")

    p.lkRecord = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.lkRecord:SetPoint("TOPLEFT",10,-446)
    p.lkRecord:SetSize(470,16)
    p.lkRecord:SetJustifyH("LEFT")

    -- Legacy row widgets are retained but hidden for saved UI compatibility.
    -- DPS section: Training Dummy
    local dummyHeader = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    dummyHeader:SetPoint("TOPLEFT",10,-302)
    dummyHeader:SetText("|cffffd200Training Dummy - Best DPS|r")

    p.lbDummyRows = {}
    for i = 1, 5 do
        local row = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row:SetPoint("TOPLEFT",10,-318-(i-1)*16)
        row:SetSize(440,14); row:SetJustifyH("LEFT"); row:Hide()
        p.lbDummyRows[i] = row
    end
    p.lbDummyEmpty = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.lbDummyEmpty:SetPoint("TOPLEFT",10,-318)
    p.lbDummyEmpty:SetSize(440,14)
    p.lbDummyEmpty:SetText("|cff666666No recorded DPS yet -- hit a training dummy|r")

    p.lbDummyPersonal = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.lbDummyPersonal:SetPoint("TOPLEFT",10,-402)
    p.lbDummyPersonal:SetSize(440,14); p.lbDummyPersonal:SetJustifyH("LEFT")
    p.lbDummyPersonal:Hide()

    -- DPS section: Lich King
    local lkHeader = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lkHeader:SetPoint("TOPLEFT",10,-422)
    lkHeader:SetText("|cffffd200Lich King - Best DPS|r")

    p.lbLKRows = {}
    for i = 1, 5 do
        local row = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row:SetPoint("TOPLEFT",10,-438-(i-1)*16)
        row:SetSize(440,14); row:SetJustifyH("LEFT"); row:Hide()
        p.lbLKRows[i] = row
    end
    p.lbLKEmpty = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.lbLKEmpty:SetPoint("TOPLEFT",10,-438)
    p.lbLKEmpty:SetSize(440,14)
    p.lbLKEmpty:SetText("|cff666666No Lich King results yet|r")

    p.lbLKPersonal = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.lbLKPersonal:SetPoint("TOPLEFT",10,-522)
    p.lbLKPersonal:SetSize(440,14); p.lbLKPersonal:SetJustifyH("LEFT")
    p.lbLKPersonal:Hide()

    dummyHeader:Hide()
    lkHeader:Hide()
    p.lbDummyEmpty:Hide()
    p.lbDummyPersonal:Hide()
    p.lbLKEmpty:Hide()
    p.lbLKPersonal:Hide()
    for _, row in ipairs(p.lbDummyRows) do row:Hide() end
    for _, row in ipairs(p.lbLKRows) do row:Hide() end

    -- Details! availability note (shown once at bottom if not installed)
    p.detailsNote = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.detailsNote:SetPoint("TOPLEFT",10,-500)
    p.detailsNote:SetSize(470,12)
    p.detailsNote:SetJustifyH("LEFT")
    p.detailsNote:SetText("|cff666666Install Details! damage meter to enable DPS tracking.|r")

    p.editState = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.editState:SetPoint("TOPLEFT",10,-470)
    p.editState:SetSize(470,26)
    p.editState:SetJustifyH("LEFT")
    p.editState:SetJustifyV("TOP")
    p.editState:Hide()

    -- buttons row
    -- Single consolidated action for the common case: opens the build as a
    -- draft in the Wishlist Editor (name pre-filled from the build's title)
    -- instead of applying immediately -- WishlistEditor.OpenForCandidate ->
    -- LoadPendingEchoes already knows how to split a build's Echoes into
    -- normal picks vs. designed locked slots (using each echo's `locked`
    -- flag). b.echoes' own flags aren't always reliable ground truth though
    -- (see the OnClick handler below), so this resolves against the DPS
    -- record's own lockedEchoes first, same as the display just above it --
    -- carrying locked-Echo intent over whether the source was another
    -- player's build or your own. For a build that's a mirror of your OWN
    -- current server loadout, the same button instead means "publish it"
    -- (see RefreshDetailPanel's label).
    p.lockBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.lockBtn:SetSize(130,22)
    p.lockBtn:SetPoint("BOTTOMLEFT",8,8)
    p.lockBtn:SetText("Copy into Editor")
    p.lockBtn:SetScript("OnClick", function()
        local b = selectedId and LoadBuild(selectedId)
        if not b then return end
        if b.importedSavedBuild then
            local ok, err = M.PublishImportedBuild(selectedId)
            if ok then
                print("|cff4dff80Nexus:|r uploaded '" .. tostring(b.title or "Saved Build") .. "' to community builds.")
                M.Refresh()
            else
                print("|cffff6060Nexus:|r " .. tostring(err))
            end
            return
        end
        if type(b.echoes) ~= "table" or #b.echoes == 0 then
            if Nexus.Sync and Nexus.Sync.RequestLoadout then Nexus.Sync.RequestLoadout(selectedId) end
            print("|cff7fd5ffNexus:|r this build is still completing its background sync. Try again shortly.")
            return
        end
        if Nexus.WishlistEditor and Nexus.WishlistEditor.OpenForCandidate then
            -- b.echoes' own .locked flags aren't reliable ground truth -- a
            -- build can have real locked Echoes without a single entry in
            -- .echoes ever being tagged (synced from a peer on an older
            -- client, or a leaderboard/DPS-record build whose locked Echoes
            -- only ever lived on the DPS record/row, never merged into
            -- .echoes -- the exact bug fixed for the Leaderboard's own
            -- "Copy into Editor" in Dev Test 45). Resolve the same way
            -- RenderDetailPanel already does for its own LOCKED ECHOES
            -- display just above: prefer a verified DPS-record's
            -- lockedEchoes (ground truth from an actual run), falling back
            -- to whatever .locked tags b.echoes already carries. Read-only
            -- -- nothing here touches Store(), Sync, or how old data is
            -- read/displayed elsewhere.
            local lockedEchoes = nil
            local D = Nexus.DpsCapture
            if D and D.GetDpsBoard then
                for _, cat in ipairs({"dummy", "lk"}) do
                    local ok2, board = pcall(D.GetDpsBoard, cat)
                    if ok2 and board then
                        for _, dpsRow in ipairs(board) do
                            if dpsRow.buildId == b.id and dpsRow.lockedEchoes then
                                lockedEchoes = dpsRow.lockedEchoes
                                break
                            end
                        end
                    end
                    if lockedEchoes then break end
                end
            end
            local echoes, seen = {}, {}
            for _, e in ipairs(b.echoes) do
                local id = tonumber(e and e.spellId)
                if id then
                    echoes[#echoes + 1] = { spellId = id, quality = e.quality, stacks = e.stacks, locked = e.locked }
                    seen[id] = true
                end
            end
            for _, e in ipairs(lockedEchoes or {}) do
                local id = tonumber(e and (e.spellId or e.id))
                if id and not seen[id] then
                    echoes[#echoes + 1] = { spellId = id, stacks = e.stacks or e.count or 1, locked = true }
                    seen[id] = true
                end
            end
            parent:Hide()
            Nexus.WishlistEditor.OpenForCandidate({ title = b.title, echoes = echoes })
        end
    end)
    p.lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        local b = selectedId and LoadBuild(selectedId)
        if b and b.importedSavedBuild then
            GameTooltip:AddLine("Publish this saved loadout",0.9,0.9,0.9,true)
            GameTooltip:AddLine("Uploads it to the community build list so others can see and copy it.",0.7,0.7,0.7,true)
        else
            GameTooltip:AddLine("Review before applying",0.9,0.9,0.9,true)
            GameTooltip:AddLine("Opens this build as a draft in the Wishlist Editor, name pre-filled. Any",0.7,0.7,0.7,true)
            GameTooltip:AddLine("Echoes it had locked show up as designed locked slots you can adjust.",0.7,0.7,0.7,true)
        end
        GameTooltip:Show()
    end)
    p.lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    p.editBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.editBtn:SetSize(96,22)
    p.editBtn:SetPoint("LEFT",p.lockBtn,"RIGHT",6,0)
    p.editBtn:SetText("Edit Build")
    p.editBtn:SetScript("OnClick", function() if selectedId then M.ToggleEditPopup(selectedId) end end)

    p.deleteBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.deleteBtn:SetSize(60,22)
    p.deleteBtn:SetPoint("BOTTOMRIGHT",-8,8)
    p.deleteBtn:SetText("Delete")
    p.deleteBtn:SetScript("OnClick", function()
        if selectedId then
            local ok, err = M.DeleteBuild(selectedId)
            if not ok then print("|cffff6060Nexus:|r " .. tostring(err)) end
            M.Refresh()
        end
    end)

    detailPanel = p
    return p
end

local function RefreshDetailPanel(build)
    if not detailPanel then return end
    if not build then detailPanel:Hide(); return end

    local c = CLASS_COLOR[(build.class or ""):upper()] or {1,1,1}
    detailPanel.title:SetTextColor(c[1],c[2],c[3])
    detailPanel.title:SetText(build.title or "")
    if detailPanel.classIcon then
        detailPanel.classIcon:SetTexture(CLASS_ICON[(build.class or ""):upper()] or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    detailPanel.author:SetText("by "..(build.author or "?"))
    detailPanel.desc:SetText((build.description ~= "" and build.description) or "|cff666666(no description)|r")

    -- Link field: always show the box so anyone can copy; only show Save
    -- button for the build's owner. Hide label/box entirely when there's no
    -- link and the viewer isn't the owner (avoids empty-box clutter).
    local hasLink = type(build.link) == "string" and build.link ~= ""
    local ownThis = IsOwnBuild(build) or IsAdmin()
    if detailPanel.linkBox then
        if hasLink or ownThis then
            detailPanel.linkLabel:Show()
            detailPanel.linkBox:Show()
            detailPanel.linkBox:SetText(build.link or "")
            if ownThis then
                detailPanel.linkSaveBtn:Show()
            else
                detailPanel.linkSaveBtn:Hide()
            end
        else
            detailPanel.linkLabel:Hide()
            detailPanel.linkBox:Hide()
            detailPanel.linkSaveBtn:Hide()
        end
    end

    -- Locked echoes: prefer a verified DPS-record lockedEchoes list (ground
    -- truth captured live from an actual run); fall back to the build's own
    -- per-echo `locked` flags -- now threaded through from Adapter.Slots()
    -- via ImportCurrentSavedLoadouts / PublishImportedBuild / Sync -- so the
    -- icons still populate for a build nobody's posted a score for yet.
    local D = Nexus.DpsCapture
    local lockedEchoes = nil
    if D and D.GetDpsBoard then
        for _, cat in ipairs({"dummy","lk"}) do
            local ok2, board = pcall(D.GetDpsBoard, cat)
            if ok2 and board then
                for _, dpsRow in ipairs(board) do
                    if dpsRow.buildId == build.id and dpsRow.lockedEchoes then
                        lockedEchoes = dpsRow.lockedEchoes
                        break
                    end
                end
            end
            if lockedEchoes then break end
        end
    end
    if not lockedEchoes and type(build.echoes) == "table" then
        local fromEchoes = {}
        for _, e in ipairs(build.echoes) do
            if e.locked then fromEchoes[#fromEchoes + 1] = { spellId = e.spellId } end
        end
        if #fromEchoes > 0 then lockedEchoes = fromEchoes end
    end
    if detailPanel.lockedIcons then
        if lockedEchoes and #lockedEchoes > 0 then
            detailPanel.lockedLabel:Show()
            detailPanel.echoLabel:Hide()
            for i, ic in ipairs(detailPanel.lockedIcons) do
                local e = lockedEchoes[i]
                if e then ic:SetTexture(SpellIcon(e.spellId or e.id)); ic:Show()
                else ic:Hide() end
            end
        else
            detailPanel.lockedLabel:Hide()
            detailPanel.echoLabel:Show()
            for _, ic in ipairs(detailPanel.lockedIcons) do ic:Hide() end
        end
    end

    -- echo icons
    local owned = Adapter and Adapter.Owned and Adapter.Owned()
    local bySpell = (owned and owned.bySpell) or {}
    local echoes = build.echoes or {}
    local hasLoadout = type(build.echoes) == "table" and #build.echoes > 0
    if not hasLoadout and Nexus.Sync and Nexus.Sync.RequestLoadout then
        Nexus.Sync.RequestLoadout(build.id)
    end
    local missing = 0
    for i, ic in ipairs(detailPanel.echoIcons) do
        local e = echoes[i]
        if e then
            ic:SetTexture(SpellIcon(e.spellId))
            local have = tonumber(bySpell[e.spellId]) or 0
            local want = tonumber(e.stacks) or 1
            if have < want then
                missing=missing+1
                pcall(function() ic:SetVertexColor(0.4,0.4,0.4) end)
            else
                pcall(function() ic:SetVertexColor(1,1,1) end)
            end
            ic:Show()
        else ic:Hide() end
    end
    if hasLoadout then
        local totalSlots = 0
        for _, e in ipairs(echoes) do totalSlots = totalSlots + (tonumber(e.stacks or e.count) or 1) end
        detailPanel.missingText:SetText(string.format(
            "|cff888888%d echoes|r  --  |cffff9040%d missing|r", totalSlots, missing))
    else
        detailPanel.missingText:SetText("|cffffd200Completing full build sync...|r")
    end

    local mine = IsOwnBuild(build)
    local admin = IsAdmin()
    local loadoutLocked = HasLeaderboardRecord(build)
    if mine then
        detailPanel.editBtn:Show()
        if build.importedSavedBuild then
            detailPanel.deleteBtn:Hide()
        else
            detailPanel.deleteBtn:Show()
            detailPanel.deleteBtn:SetText("Delete")
        end
    elseif admin then
        detailPanel.editBtn:Hide()
        detailPanel.deleteBtn:Show()
        detailPanel.deleteBtn:SetText("Remove")
    else
        detailPanel.editBtn:Hide()
        detailPanel.deleteBtn:Hide()
    end

    if build.importedSavedBuild then
        local state = build.publishedBuildId and "Uploaded. Upload Build again to publish title/description or loadout changes." or "Local server loadout. Edit its title/description, then Upload Build when ready."
        detailPanel.editState:SetText(state)
        detailPanel.editState:Show()
    elseif mine and loadoutLocked then
        detailPanel.editState:SetText("|cffffd200Leaderboard loadout locked.|r Title and description may still be edited.")
        detailPanel.editState:Show()
    elseif mine then
        detailPanel.editState:SetText("You own this build. Edit can also replace its Echoes from your active wishlist.")
        detailPanel.editState:Show()
    else
        detailPanel.editState:Hide()
    end

    if build.importedSavedBuild then
        detailPanel.lockBtn:SetText(build.publishedBuildId and "Update Upload" or "Upload Build")
    else
        detailPanel.lockBtn:SetText(not hasLoadout and "Request Loadout" or "Copy into Editor")
    end

    -- DPS leaderboards
    local D = Nexus.DpsCapture
    local hasDetails = D and D.IsDetailsAvailable()

    local function RenderLbSection(rows, emptyLabel, personalLabel, lb, personal)
        if #lb == 0 then
            emptyLabel:Show()
            for _, r in ipairs(rows) do r:Hide() end
        else
            emptyLabel:Hide()
            for i, row in ipairs(rows) do
                local e = lb[i]
                if e then
                    local dpsStr = e.dps >= 1000000
                        and string.format("%.2fM", e.dps/1000000)
                        or  string.format("%dk",   math.floor(e.dps/1000))
                    row:SetText(string.format(
                        "|cffffd200#%-2d|r  %-16s  |cff4dff80%s|r",
                        i, tostring(e.player):sub(1,16), dpsStr))
                    row:Show()
                else
                    row:Hide()
                end
            end
        end
        if personal then
            local dpsStr = personal.dps >= 1000000
                and string.format("%.2fM", personal.dps/1000000)
                or  string.format("%dk",   math.floor(personal.dps/1000))
            personalLabel:SetText(string.format(
                "|cff888888Your best:|r  |cff4dff80%s|r  (Lv%d)", dpsStr, personal.level))
            personalLabel:Show()
        else
            personalLabel:Hide()
        end
    end

    local function RecordText(label, rows, personal)
        local top = rows and rows[1]
        local best = top and DpsText(top.dps) or "—"
        local holder = top and tostring(top.player or "Unknown") or "No record yet"
        local yours = personal and DpsText(personal.dps) or "—"
        return string.format("|cffffffff%s|r  |cffffd200%s|r |cff888888%s|r   |cff66ff99Your best %s|r",
            label, best, holder, yours)
    end

    if D then
        local recordId = RecordBuildId(build)
        local dummyLb  = D.GetLeaderboard(recordId, "dummy") or {}
        local dummyPB  = D.GetPersonalBest(recordId, "dummy")
        local lkLb     = D.GetLeaderboard(recordId, "lk") or {}
        local lkPB     = D.GetPersonalBest(recordId, "lk")
        detailPanel.dummyRecord:SetText(RecordText("Training Dummy", dummyLb, dummyPB))
        detailPanel.lkRecord:SetText(RecordText("Lich King", lkLb, lkPB))
    else
        detailPanel.dummyRecord:SetText("Training Dummy   —")
        detailPanel.lkRecord:SetText("Lich King   —")
    end

    for _, row in ipairs(detailPanel.lbDummyRows) do row:Hide() end
    for _, row in ipairs(detailPanel.lbLKRows) do row:Hide() end
    detailPanel.lbDummyEmpty:Hide(); detailPanel.lbDummyPersonal:Hide()
    detailPanel.lbLKEmpty:Hide(); detailPanel.lbLKPersonal:Hide()

    -- Show/hide the "install Details!" note
    if detailPanel.detailsNote then
        if hasDetails then detailPanel.detailsNote:Hide()
        else detailPanel.detailsNote:Show() end
    end

    detailPanel:Show()
end

------------------------------------------------------------------------
-- Card pool (reuse pre-built frames to avoid GC churn during scroll)
------------------------------------------------------------------------

local cardPool = {}   -- reusable card frames
local activeCards = {}  -- currently visible cards

local function GetCard(parent)
    if #cardPool > 0 then
        local c = table.remove(cardPool)
        c:SetParent(parent)
        c:Show()
        return c
    end

    local card = CreateFrame("Button", nil, parent)
    virtualStats.created = virtualStats.created + 1
    card:SetHeight(CARD_HEIGHT)
    card:EnableMouse(true)

    pcall(function()
        card:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left=3, right=3, top=3, bottom=3 },
        })
        card:SetBackdropColor(0.035, 0.035, 0.045, 0.94)
        card:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.9)
    end)

    card.selectedHighlight = card:CreateTexture(nil, "BACKGROUND")
    card.selectedHighlight:SetAllPoints(card)
    pcall(function() card.selectedHighlight:SetTexture(0.18, 0.38, 0.62, 0.22) end)
    card.selectedHighlight:Hide()

    card.classIcon = card:CreateTexture(nil, "ARTWORK")
    card.classIcon:SetSize(30, 30)
    card.classIcon:SetPoint("TOPLEFT", 10, -9)
    card.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", card.classIcon, "TOPRIGHT", 8, 0)
    card.title:SetSize(250, 16)
    card.title:SetJustifyH("LEFT")

    card.author = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.author:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2)
    card.author:SetSize(245, 12)
    card.author:SetJustifyH("LEFT")

    card.destination = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.destination:SetPoint("TOPLEFT", card.author, "BOTTOMLEFT", 0, -2)
    card.destination:SetSize(310, 12)
    card.destination:SetJustifyH("LEFT")

    card.echoCount = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.echoCount:SetPoint("TOPRIGHT", -12, -9)
    card.echoCount:SetSize(178, 14)
    card.echoCount:SetJustifyH("RIGHT")

    card.dpsBreakdown = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.dpsBreakdown:SetPoint("TOPRIGHT", card.echoCount, "BOTTOMRIGHT", 0, -2)
    card.dpsBreakdown:SetSize(220, 12)
    card.dpsBreakdown:SetJustifyH("RIGHT")
    card.dpsBreakdown:SetText("")

    card.icons = {}
    for i = 1, MAX_ROW_ICONS do
        local ic = card:CreateTexture(nil, "ARTWORK")
        ic:SetSize(ICON_SIZE, ICON_SIZE)
        ic:SetPoint("BOTTOMLEFT", 10 + (i-1)*(ICON_SIZE+2), 9)
        ic:Hide()
        card.icons[i] = ic
    end

    card.moreText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.moreText:SetPoint("LEFT", card.icons[MAX_ROW_ICONS], "RIGHT", 6, 0)
    card.moreText:SetText("")

    card.mineBadge = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.mineBadge:SetPoint("BOTTOMRIGHT", -64, 13)
    card.mineBadge:SetSize(70, 12)
    card.mineBadge:SetJustifyH("RIGHT")
    card.mineBadge:Hide()

    card.addBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.addBtn:SetSize(52, 22)
    card.addBtn:SetPoint("BOTTOMRIGHT", -8, 7)
    card.addBtn:SetText("View")
    card.addBtn:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        if parent.buildId then
            selectedId = parent.buildId
            M.Refresh()
        end
    end)
    card.addBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Open build details", 1,1,1)
        GameTooltip:AddLine("Inspect records, exact Echoes, and copy the loadout.", 0.8,0.8,0.8, true)
        GameTooltip:Show()
    end)
    card.addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Retained for compatibility with older pooled rows; the whole card and
    -- the explicit View button now perform the same clear action.
    card.menuBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.menuBtn:SetSize(1, 1)
    card.menuBtn:SetPoint("BOTTOMRIGHT", -1, 1)
    card.menuBtn:Hide()

    card:SetScript("OnEnter", function(self)
        if not self.buildId then return end
        pcall(function()
            self:SetBackdropColor(0.07, 0.08, 0.11, 0.98)
            self:SetBackdropBorderColor(0.45, 0.55, 0.7, 1)
        end)
    end)
    card:SetScript("OnLeave", function(self)
        pcall(function()
            self:SetBackdropColor(0.035, 0.035, 0.045, 0.94)
            self:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.9)
        end)
    end)
    card:SetScript("OnClick", function(self)
        if not self.buildId then return end
        selectedId = self.buildId
        M.Refresh()
    end)
    if Nexus.Theme and Nexus.Theme.StyleVirtualRow then
        Nexus.Theme.StyleVirtualRow(card, {card.addBtn, card.menuBtn})
    end
    return card
end

local function ReleaseCard(card)
    card:Hide()
    card:ClearAllPoints()
    card:SetParent(nil)
    cardPool[#cardPool+1] = card
end

local function ReleaseAllCards()
    for _, c in ipairs(activeCards) do ReleaseCard(c) end
    activeCards = {}
end

------------------------------------------------------------------------
-- Class header frames
------------------------------------------------------------------------

local headerPool = {}
local activeHeaders = {}

local function GetHeader(parent)
    if #headerPool > 0 then
        local h = table.remove(headerPool)
        h:SetParent(parent); h:Show(); return h
    end
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(22)
    h.label = h:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    h.label:SetPoint("BOTTOMLEFT",2,-2)
    h.sep = h:CreateTexture(nil,"ARTWORK")
    h.sep:SetHeight(1)
    h.sep:SetPoint("BOTTOMLEFT",h,"BOTTOMLEFT",0,0)
    h.sep:SetPoint("BOTTOMRIGHT",h,"BOTTOMRIGHT",0,0)
    pcall(function() h.sep:SetTexture(0.4,0.4,0.4,0.6) end)
    return h
end
local function ReleaseHeader(h)
    h:Hide(); h:ClearAllPoints(); h:SetParent(nil)
    headerPool[#headerPool+1] = h
end
local function ReleaseAllHeaders()
    for _, h in ipairs(activeHeaders) do ReleaseHeader(h) end
    activeHeaders = {}
end

------------------------------------------------------------------------
-- Main frame construction
------------------------------------------------------------------------

local function EnsureFrame()
    if frame then return frame end

    -- Main browser window: list and detail panel live together in one surface.
    frame = CreateFrame("Frame","NexusCommunityBuildsFrame",UIParent)
    frame:SetClampedToScreen(true)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "NexusCommunityBuildsFrame")
    end
    frame:SetSize(1040,640)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(50)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local retryTicker, statusTicker, dataTicker = 0, 0, 0
    local lastReceiving = false
    frame:SetScript("OnUpdate",function(_,elapsed)
        retryTicker = retryTicker + elapsed
        if retryTicker >= 0.5 then
            retryTicker = 0
            if M._PumpPendingLockIn then M._PumpPendingLockIn() end
        end

        -- Keep the live sync label responsive without rebuilding and sorting
        -- the entire build library every half second. The old full refresh was
        -- especially expensive with 100+ builds because it also resolved DPS
        -- records, recreated every card and recursively restyled the frame.
        statusTicker = statusTicker + elapsed
        if statusTicker >= 0.25 then
            statusTicker = 0
            local receiving = Nexus.Sync and Nexus.Sync.IsReceiving() or false
            local receiveCount = Nexus.Sync and Nexus.Sync.LastSyncNewCount and Nexus.Sync.LastSyncNewCount() or 0
            if syncStatusText and Nexus.Sync then
                if receiving then
                    syncStatusText:SetText(string.format(
                        "|cff4dff80Listening for builds... %ds|r  (%d new so far)",
                        math.ceil(Nexus.Sync.ReceiveTimeLeft()), receiveCount))
                end
                if syncBtn then syncBtn:SetText(receiving and "Listening..." or "Sync Now") end
            end

            -- Build/DPS revisions mark the view dirty while Sync is active.
            -- Publish once when that burst ends; changing the live count alone
            -- is status work and must not rebuild the catalog.
            local receiveEnded = lastReceiving and not receiving
            lastReceiving = receiving
            if receiveEnded and refreshDirty then
                virtualStats.deferredRefreshes =
                    virtualStats.deferredRefreshes + 1
                M.Refresh()
            end
        end

        -- Cheap safety probe for missed invalidations. An unchanged tick does
        -- not request/copy the cached projection or sort/rebind any rows.
        dataTicker = dataTicker + elapsed
        if dataTicker >= 8.0 then
            dataTicker = 0
            local projections = Nexus and Nexus.ViewProjections
            local current = nil
            if projections and type(projections.BuildsCurrent) == "function" then
                local safeFilters = {}
                for key, value in pairs(FilterSettings()) do
                    safeFilters[key] = value
                end
                safeFilters.resultLimit = EMERGENCY_BUILD_LIMIT
                safeFilters.skipDps = true
                local ok, result = pcall(projections.BuildsCurrent,
                    safeFilters)
                if ok then current = result end
            end
            local receiving = Nexus.Sync and Nexus.Sync.IsReceiving
                and Nexus.Sync.IsReceiving() or false
            -- A missing/failing dirty probe must retain the old safe behavior:
            -- attempt the refresh instead of treating an unknown state as
            -- current forever.
            if not receiving and (refreshDirty or current ~= true) then
                M.Refresh()
            else
                virtualStats.periodicSkips = virtualStats.periodicSkips + 1
            end
        end
    end)
    frame:Hide()
    frame:HookScript("OnHide",function()
        if dropPanel then dropPanel:Hide() end
        if sortPanel then sortPanel:Hide() end
        if dropdownShield then dropdownShield:Hide() end
    end)

    pcall(function()
        frame:SetBackdrop({
            bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=32, edgeSize=32,
            insets={left=11,right=12,top=12,bottom=11},
        })
    end)
    pcall(function() frame:SetBackdropColor(0.16,0.165,0.175,0.90) end)

    -- Title bar ---------------------------------------------------------
    local titleText = frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleText:SetPoint("TOP",0,-12)
    titleText:SetText("Nexus  —  Builds")

    local closeBtn = CreateFrame("Button",nil,frame,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",-6,-6)

    -- A single click-away layer and one-open-menu rule make every selector
    -- behave like the same control instead of three unrelated popup frames.
    dropdownShield = CreateFrame("Button","NexusBuildDropdownShield",UIParent)
    dropdownShield:SetAllPoints(UIParent)
    dropdownShield:SetFrameStrata("DIALOG")
    dropdownShield:SetFrameLevel(frame:GetFrameLevel() - 1)
    dropdownShield:EnableMouse(true)
    dropdownShield:Hide()

    local function CloseDropdowns()
        if dropPanel then dropPanel:Hide() end
        if sortPanel then sortPanel:Hide() end
        if dropdownShield then dropdownShield:Hide() end
    end
    dropdownShield:SetScript("OnClick", CloseDropdowns)

    local function OpenDropdown(panel, anchor)
        local wasShown = panel and panel:IsShown()
        CloseDropdowns()
        if wasShown or not panel then return end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
        panel:SetFrameStrata("TOOLTIP")
        panel:SetFrameLevel(dropdownShield:GetFrameLevel() + 2)
        dropdownShield:Show()
        panel:Show()
    end

    local function StyleDropdownPanel(panel)
        panel:EnableMouse(true)
        panel:Hide()
        pcall(function()
            panel:SetBackdrop({
                bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                tile=true, tileSize=16, edgeSize=12,
                insets={left=4,right=4,top=4,bottom=4},
            })
            panel:SetBackdropColor(0.02,0.02,0.025,0.99)
            panel:SetBackdropBorderColor(0.55,0.45,0.22,1)
        end)
    end

    local function AddDropdownRow(panel, entry, index, width, selectedFn, onSelect, color)
        local item = entry
        local row = CreateFrame("Button",nil,panel)
        row:SetSize(width - 10,24)
        row:SetPoint("TOPLEFT",5,-(5+(index-1)*24))
        row:EnableMouse(true)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local check = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        check:SetPoint("LEFT",7,0)
        check:SetText(">")
        local label = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        label:SetPoint("LEFT",check,"RIGHT",7,0)
        label:SetPoint("RIGHT",row,"RIGHT",-8,0)
        label:SetJustifyH("LEFT")
        label:SetText(item.label)
        if color then label:SetTextColor(color[1],color[2],color[3]) end
        row._entry, row._check, row._label = item, check, label
        row:SetScript("OnClick",function()
            onSelect(item)
            CloseDropdowns()
            M.Refresh()
        end)
        panel._rows = panel._rows or {}
        panel._rows[#panel._rows+1] = row
        row._selectedFn = selectedFn
        return row
    end

    local function RefreshDropdown(panel)
        if not panel or not panel._rows then return end
        for _, row in ipairs(panel._rows) do
            local selected = row._selectedFn and row._selectedFn(row._entry)
            if selected then
                row._check:Show()
                row._label:SetTextColor(1,0.82,0.2)
            else
                row._check:Hide()
                local key = row._entry and row._entry.key
                local c = key and CLASS_COLOR[key]
                if c then row._label:SetTextColor(c[1],c[2],c[3])
                else row._label:SetTextColor(0.92,0.92,0.92) end
            end
        end
    end
    frame._CloseDropdowns = CloseDropdowns
    frame._RefreshDropdown = RefreshDropdown

    local function StyleSelectorButton(button)
        button:SetNormalFontObject("GameFontHighlightSmall")
        button:SetHighlightFontObject("GameFontNormalSmall")
        button:SetPushedTextOffset(0, -1)
        if not button._arrow then
            local arrow = button:CreateTexture(nil, "OVERLAY")
            arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
            arrow:SetSize(12, 12)
            arrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)
            arrow:SetTexCoord(0, 1, 0, 1)
            button._arrow = arrow
        end
        local fs = button:GetFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", button, "LEFT", 9, 0)
            fs:SetPoint("RIGHT", button, "RIGHT", -22, 0)
            fs:SetJustifyH("CENTER")
        end
        pcall(function()
            button:SetBackdrop({
                bgFile="Interface\\Buttons\\WHITE8X8",
                edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                tile=false, edgeSize=10,
                insets={left=2,right=2,top=2,bottom=2},
            })
            button:SetBackdropColor(0.025,0.03,0.04,0.96)
            button:SetBackdropBorderColor(0.38,0.38,0.42,0.95)
        end)
        button:SetScript("OnEnter", function(self)
            pcall(function() self:SetBackdropBorderColor(0.9,0.72,0.25,1) end)
        end)
        button:SetScript("OnLeave", function(self)
            pcall(function() self:SetBackdropBorderColor(0.38,0.38,0.42,0.95) end)
            GameTooltip:Hide()
        end)
    end

    -- Primary navigation is centered and visually separate from filtering.
    local navBar = CreateFrame("Frame",nil,frame)
    navBar:SetSize(314,24)
    navBar:SetPoint("TOPLEFT",18,-12)

    local buildsTab = CreateFrame("Button",nil,navBar,"UIPanelButtonTemplate")
    buildsTab:SetSize(92,22)
    buildsTab:SetPoint("LEFT",0,0)
    buildsTab:SetText("|cffffd200Builds|r")
    buildsTab:Disable()

    leaderboardBtn = CreateFrame("Button",nil,navBar,"UIPanelButtonTemplate")
    leaderboardBtn:SetSize(112,22)
    leaderboardBtn:SetPoint("LEFT",buildsTab,"RIGHT",4,0)
    leaderboardBtn:SetText("Leaderboard")
    leaderboardBtn:SetScript("OnClick",function()
        CloseDropdowns()
        frame:Hide()
        if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
    end)

    wishlistBtn = CreateFrame("Button",nil,navBar,"UIPanelButtonTemplate")
    wishlistBtn:SetSize(98,22)
    wishlistBtn:SetPoint("LEFT",leaderboardBtn,"RIGHT",4,0)
    wishlistBtn:SetText("Wishlists")
    wishlistBtn:SetScript("OnClick",function()
        CloseDropdowns()
        frame:Hide()
        if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end
    end)

    -- Browse toolbar ----------------------------------------------------
    local browseLabel = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    browseLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -64)
    browseLabel:SetText("BROWSE BUILDS")

    local actionLabel = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    actionLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -64)
    actionLabel:SetText("ACTIONS")

    searchBox = CreateFrame("EditBox","NexusBuildsSearch",frame,"InputBoxTemplate")
    searchBox:SetSize(250,22)
    searchBox:SetPoint("TOPLEFT",20,-78)
    searchBox:SetAutoFocus(false)
    searchBox:SetText(FilterSettings().search or "")
    searchBox:SetScript("OnTextChanged",function(self)
        FilterSettings().search = self:GetText() or ""
        M.Refresh()
    end)
    local searchLabel = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    searchLabel:SetPoint("LEFT",searchBox,"LEFT",6,0)
    searchLabel:SetText("Search title, author, or description...")
    searchBox:SetScript("OnEditFocusGained",function() searchLabel:Hide(); CloseDropdowns() end)
    searchBox:SetScript("OnEditFocusLost",function(self)
        if self:GetText() == "" then searchLabel:Show() end
    end)
    if (FilterSettings().search or "") ~= "" then searchLabel:Hide() end

    -- Library scope is a direct two-button selector instead of a hidden dropdown.
    scopeBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    scopeBtn:SetSize(92,22)
    scopeBtn:SetPoint("LEFT",searchBox,"RIGHT",10,0)
    scopeBtn:SetText("All Builds")
    scopeBtn:SetScript("OnClick",function()
        FilterSettings().scope = "all"
        selectedId = nil
        CloseDropdowns()
        M.Refresh()
    end)
    scopeBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("All Builds",1,0.82,0.2)
        GameTooltip:AddLine("Browse shared community builds.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    scopeBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    myBuildsBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    myBuildsBtn:SetSize(92,22)
    myBuildsBtn:SetPoint("LEFT",scopeBtn,"RIGHT",4,0)
    myBuildsBtn:SetText("My Builds")
    myBuildsBtn:SetScript("OnClick",function()
        FilterSettings().scope = "mine"
        selectedId = nil
        CloseDropdowns()
        M.Refresh()
    end)
    myBuildsBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("My Builds",1,0.82,0.2)
        GameTooltip:AddLine("Open your saved loadouts and uploaded builds.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    myBuildsBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local CLASSES_DD = {
        {key=nil,label="All Classes"},{key="DEATHKNIGHT",label="Death Knight"},
        {key="DRUID",label="Druid"},{key="HUNTER",label="Hunter"},{key="MAGE",label="Mage"},
        {key="PALADIN",label="Paladin"},{key="PRIEST",label="Priest"},{key="ROGUE",label="Rogue"},
        {key="SHAMAN",label="Shaman"},{key="WARLOCK",label="Warlock"},{key="WARRIOR",label="Warrior"},
    }
    classDropBtn = CreateFrame("Button",nil,frame)
    classDropBtn:SetSize(138,22)
    classDropBtn:SetPoint("LEFT",myBuildsBtn,"RIGHT",8,0)
    frame._classDropBtn = classDropBtn
    StyleSelectorButton(classDropBtn)
    dropPanel = CreateFrame("Frame","NexusClassDropPanel",UIParent)
    dropPanel:SetSize(138,#CLASSES_DD*24+10)
    StyleDropdownPanel(dropPanel)
    for i,entry in ipairs(CLASSES_DD) do
        local c = entry.key and CLASS_COLOR[entry.key] or nil
        AddDropdownRow(dropPanel,entry,i,138,
            function(item) return FilterSettings().classFilter == item.key end,
            function(item) FilterSettings().classFilter=item.key end,c)
    end
    classDropBtn:SetScript("OnClick",function(self) OpenDropdown(dropPanel,self) end)

    local sorts={{key="recent",label="Newest"},{key="title",label="Name"}}
    sortToggle = CreateFrame("Button",nil,frame)
    sortToggle:SetSize(134,22)
    sortToggle:SetPoint("LEFT",classDropBtn,"RIGHT",8,0)
    frame._sortToggle = sortToggle
    StyleSelectorButton(sortToggle)
    sortPanel = CreateFrame("Frame","NexusBuildSortPanel",UIParent)
    sortPanel:SetSize(134,#sorts*24+10)
    StyleDropdownPanel(sortPanel)
    for i,entry in ipairs(sorts) do
        AddDropdownRow(sortPanel,entry,i,134,
            function(item) return (FilterSettings().sortMode or "dps") == item.key end,
            function(item) FilterSettings().sortMode=item.key end)
    end
    sortToggle:SetScript("OnClick",function(self) OpenDropdown(sortPanel,self) end)
    sortToggle:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Sort builds",1,1,1)
        GameTooltip:AddLine("DPS and average-DPS sorting are temporarily disabled to prevent freezing.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    sortToggle:SetScript("OnLeave",function() GameTooltip:Hide() end)

    syncBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    syncBtn:SetSize(88,22)
    syncBtn:SetPoint("TOPRIGHT",-132,-78)
    frame._syncBtn = syncBtn
    syncBtn:SetText("Sync Now")
    syncBtn:SetScript("OnClick",function()
        CloseDropdowns()
        if not Nexus.Sync then return end
        local ok, err = Nexus.Sync.RequestSync()
        if ok then print("|cff7fd5ffNexus:|r asking other players for their builds...")
        else print("|cffff6060Nexus:|r "..tostring(err)) end
    end)
    syncBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Refresh community data",1,1,1)
        GameTooltip:AddLine("Ask nearby Nexus users for builds and DPS records.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local postBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    postBtn:SetSize(110,22)
    postBtn:SetPoint("TOPRIGHT",-15,-78)
    postBtn:SetText("Share Build")
    postBtn:SetScript("OnClick",function() CloseDropdowns(); M.ShowPostBuild() end)
    postBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Share a build",1,1,1)
        GameTooltip:AddLine("Choose a saved loadout or wishlist, then add its title and description.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    postBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    resultText = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    resultText:SetPoint("TOPLEFT",20,-108)
    resultText:SetSize(250,16)
    resultText:SetJustifyH("LEFT")

    syncStatusText = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    syncStatusText:SetPoint("TOPLEFT",280,-108)
    syncStatusText:SetSize(730,14)
    syncStatusText:SetJustifyH("LEFT")

    -- Left: scrollable card list -----------------------------------------
    -- Clip region (SetClipsChildren is retail-only on 3.3.5 -- same class
    -- of API as SetColorTexture; wrap defensively so everything below still
    -- gets created even if this call throws)
    local listClip = CreateFrame("Frame",nil,frame)
    listClip:SetPoint("TOPLEFT",20,-130)
    listClip:SetPoint("BOTTOMLEFT",20,20)
    listClip:SetWidth(480)
    pcall(function() listClip:SetClipsChildren(true) end)

    scrollFrame = CreateFrame("ScrollFrame",nil,listClip)
    scrollFrame:SetAllPoints(listClip)
    scrollFrame:EnableMouseWheel(true)

    scrollChild = CreateFrame("Frame",nil,scrollFrame)
    scrollChild:SetWidth(460)
    scrollChild:SetHeight(1)     -- set dynamically in Refresh
    scrollFrame:SetScrollChild(scrollChild)

    -- Simple scroll offset tracking -- no template, no SetVerticalScroll,
    -- just keep an offset and SetVerticalScroll via pcall (different API
    -- names across WoW versions).
    scrollBar = { value = 0, min = 0, max = 0 }  -- plain table, no template
    local function SetScroll(val)
        val = math.max(scrollBar.min, math.min(scrollBar.max, val))
        scrollBar.value = val
        pcall(function() scrollFrame:SetVerticalScroll(val) end)
        if renderBuildWindow and frame and frame:IsShown()
            and not virtualBinding then
            renderBuildWindow("scroll")
        end
    end
    scrollBar.SetValue = function(_, val) SetScroll(val) end
    scrollBar.GetValue = function(_) return scrollBar.value end
    scrollBar.SetMinMaxValues = function(_, mn, mx) scrollBar.min = mn; scrollBar.max = mx end
    scrollBar.GetMinMaxValues = function(_) return scrollBar.min, scrollBar.max end

    scrollFrame:SetScript("OnMouseWheel",function(_,delta)
        SetScroll(scrollBar.value - delta * CARD_HEIGHT * 3)
    end)
    scrollFrame:SetScript("OnSizeChanged", function()
        if renderBuildWindow and frame and frame:IsShown()
            and not virtualBinding then
            renderBuildWindow("resize")
        end
    end)
    frame._virtualListScrollFrame = scrollFrame

    local emptyState = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyState:SetPoint("TOPLEFT", listClip, "TOPLEFT", 20, 34)
    emptyState:SetSize(400, 80)
    emptyState:SetJustifyH("CENTER")
    emptyState:SetJustifyV("TOP")
    emptyState:Hide()
    frame._emptyState = emptyState

    -- Right: detail panel ------------------------------------------------
    EnsureDetailPanel(frame)
    detailPanel:ClearAllPoints()
    detailPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 520, -130)
    detailPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)
    detailPanel:SetFrameLevel(frame:GetFrameLevel() + 10)

    -- Style the static browser controls once. Dynamic cards are created from
    -- an already dark template and do not need a full recursive restyle on
    -- every refresh.
    if Nexus.Theme then Nexus.Theme.StyleTree(frame) end
    return frame
end


function M.GetSelectedBuildForPanel()
    if not frame or not frame:IsShown() or not selectedId then return nil end
    return LoadBuild(selectedId)
end

function M.VirtualStats()
    local out = {}
    for key, value in pairs(virtualStats) do out[key] = value end
    out.selectedId = selectedId
    out.refreshDirty = refreshDirty
    return out
end

function M.MarkDataDirty()
    if not refreshDirty then
        refreshDirty = true
        virtualStats.dirtyMarks = virtualStats.dirtyMarks + 1
    end
    return true
end

function M.ScrollTo(offset)
    if not scrollBar then return false end
    scrollBar:SetValue(tonumber(offset) or 0)
    return true
end

------------------------------------------------------------------------
-- Refresh  (called every tick while open, and whenever data changes)
------------------------------------------------------------------------

function M.Refresh()
    if not frame or not frame:IsShown() then return end
    local sync = Nexus and Nexus.Sync
    local receiving = sync and type(sync.IsReceiving) == "function"
        and sync.IsReceiving() or false
    if receiving then
        M.MarkDataDirty()
        if syncStatusText then
            syncStatusText:SetText(string.format(
                "|cff4dff80Syncing safely... %ds|r  (%d new so far)",
                math.ceil(sync.ReceiveTimeLeft()), sync.LastSyncNewCount()))
        end
        if syncBtn then syncBtn:SetText("Listening...") end
        if resultText then
            resultText:SetText(
                "|cffffd200Build list paused until Sync finishes to prevent freezing.|r")
        end
        return true
    end
    ImportCurrentSavedLoadouts(false)

    -- Sync status
    if syncStatusText and Nexus.Sync then
        local s = Nexus.Sync
        if s.IsReceiving() then
            syncStatusText:SetText(string.format(
                "|cff4dff80Listening for builds... %ds|r  (%d new so far)",
                math.ceil(s.ReceiveTimeLeft()), s.LastSyncNewCount()))
        elseif s.Stats().received > 0 then
            syncStatusText:SetText(string.format(
                "|cff888888%d build(s) in library. Updated on login; last sync added %d.  Sync Now checks again.|r",
                (function() local n=0 for _ in pairs(Store()) do n=n+1 end return n end)(),
                s.LastSyncNewCount()))
        else
            local total = 0; for _ in pairs(Store()) do total = total + 1 end
            syncStatusText:SetText(string.format("|cff888888%d build(s) available. Sync Now checks the nearby mesh for updates.|r", total))
        end
        if syncBtn then
            syncBtn:SetText(s.IsReceiving() and "Listening..." or "Sync Now")
        end
    end

    -- Update control labels
    local fs = FilterSettings()
    if classDropBtn then
        local cf = fs.classFilter
        if cf then
            classDropBtn:SetText("Class: "..(CLASS_LABEL[cf] or cf))
        else
            classDropBtn:SetText("Class: All")
        end
    end
    if scopeBtn and myBuildsBtn then
        if fs.scope == "mine" then
            scopeBtn:Enable()
            myBuildsBtn:Disable()
        else
            scopeBtn:Disable()
            myBuildsBtn:Enable()
        end
    end
    if sortToggle then
        if fs.sortMode == "class" or not fs.sortMode then fs.sortMode = "dps" end
        local labels={dps="Highest DPS",recent="Newest",title="Name"}
        if fs.sortMode == "dps" then
            sortToggle:SetText("Sort: Newest (safe mode)")
        else
            sortToggle:SetText("Sort: "..(labels[fs.sortMode] or "Newest"))
        end
        sortToggle:Show()
    end
    if frame._RefreshDropdown then
        frame._RefreshDropdown(dropPanel)
        frame._RefreshDropdown(sortPanel)
    end

    -- Build browser contains builds only. DPS rankings are rendered in the
    -- dedicated Leaderboard window.
    local boardRows = nil
    local builds, projectionSummary = SortedBuilds()
    if resultText then
        local total = projectionSummary and projectionSummary.total or 0
        if not projectionSummary then
            for _ in pairs(Store()) do total=total+1 end
        end
        if fs.scope == "mine" then
            local loadouts = projectionSummary and projectionSummary.savedLoadouts or 0
            local uploaded = projectionSummary and projectionSummary.uploaded or 0
            if not projectionSummary then
                for _, b in pairs(Store()) do
                    if b.importedSavedBuild then loadouts = loadouts + 1
                    elseif IsOwnBuild(b) then uploaded = uploaded + 1 end
                end
            end
            resultText:SetText(string.format("|cffd8c7a0%d saved loadouts|r  |cff777777•|r  %d uploaded builds", loadouts, uploaded))
        else
            local ready = projectionSummary and projectionSummary.ready or 0
            local pending = projectionSummary and projectionSummary.pending or 0
            if not projectionSummary then
                for _, b in ipairs(builds) do
                    if IsBuildFullyLoaded(b) then ready = ready + 1 else pending = pending + 1 end
                end
            end
            if pending > 0 then
                resultText:SetText(string.format("|cffd8c7a0%d ready|r  |cff777777•|r  |cffffd200%d syncing|r", ready, pending))
            else
                resultText:SetText(string.format("|cffd8c7a0Showing %d|r community builds", ready))
            end
            if projectionSummary and projectionSummary.limited then
                resultText:SetText(string.format(
                    "|cffd8c7a0%d available|r  |cffffd200showing %d newest (safe mode)|r",
                    ready, tonumber(projectionSummary.filtered) or #builds))
            end
        end
    end
    renderBuildWindow = function(reason)
        if virtualBinding then return end
        virtualBinding = true
        local ok, err = pcall(function()
    ReleaseAllCards()
    ReleaseAllHeaders()

    local rowHeight = CARD_HEIGHT + 4
    local visibleH = math.max(100,
        (scrollFrame and scrollFrame:GetHeight()) or 458)
    local virtual = Nexus.VirtualList.Window(
        #builds, rowHeight, visibleH,
        scrollBar and scrollBar.value or 0, 2)
    local yOffset = (virtual.first - 1) * rowHeight
    local lastClass = "__none__"
    local showHeaders = false

    for index = virtual.first, virtual.last do
        local projected = builds[index]
        local b = LoadBuild(projected.id) or projected
        b._nexusDps = projected._nexusDps
        b._nexusBestDps = projected._nexusBestDps
        b._nexusDpsDeferred = projected._nexusDpsDeferred
        local bClass = (b.class or ""):upper()

        -- Class header when sorted by class and not filtered
        if showHeaders and bClass ~= lastClass then
            lastClass = bClass
            local h = GetHeader(scrollChild)
            h:SetWidth(460)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
            local c = CLASS_COLOR[bClass] or {0.8,0.8,0.8}
            h.label:SetTextColor(c[1],c[2],c[3])
            h.label:SetText(CLASS_LABEL[bClass] or bClass)
            activeHeaders[#activeHeaders+1] = h
            yOffset = yOffset + 26
        end

        -- Build card
        local card = GetCard(scrollChild)
        -- Check cards into the active set before binding data so the failure
        -- path can always reclaim a partially bound card.
        activeCards[#activeCards+1] = card
        card:SetWidth(460)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        card.buildId = b.id

        -- Selection highlight
        if b.id == selectedId then
            card.selectedHighlight:Show()
        else
            card.selectedHighlight:Hide()
        end

        -- Use a stable class-themed icon instead of a question mark.
        pcall(function() card.classIcon:SetTexture(CLASS_ICON[bClass] or "Interface\\Icons\\INV_Misc_QuestionMark") end)

        -- Title (class colored)
        local c = CLASS_COLOR[bClass] or {1,1,1}
        card.title:SetTextColor(c[1],c[2],c[3])
        card.title:SetText(b.title or "")
        do
            local ownerTag = ""
            if b.importedSavedBuild then ownerTag = "  |cff66ccffSaved loadout|r"
            elseif IsOwnBuild(b) then ownerTag = "  |cffffd200Your build|r" end
            card.author:SetText("by "..(b.author or "?")..ownerTag)
        end
        if b.importedSavedBuild then
            if b.destinationWishlistName then
                card.destination:SetText(string.format("|cffffd200Destination:|r %s  |cff66ff99%d/%d in progress|r", b.destinationWishlistName, tonumber(b.destinationProgress) or 0, tonumber(b.destinationTotal) or 79))
            else
                card.destination:SetText("|cff999999No destination wishlist associated|r")
            end
            card.destination:Show()
        else
            card.destination:SetText("")
            card.destination:Hide()
        end

        -- Echo icons
        local echoes = b.echoes or {}
        local shown = math.min(#echoes, MAX_ROW_ICONS)
        for i, ic in ipairs(card.icons) do
            if i <= shown then
                ic:SetTexture(SpellIcon(echoes[i].spellId))
                pcall(function() ic:SetVertexColor(1,1,1) end)
                ic:Show()
            else
                ic:Hide()
            end
        end
        local extra = #echoes - shown
        card.moreText:SetText(extra > 0 and ("|cffff9040+"..extra.."|r") or "")
        if #echoes > 0 then
            do
                local total = EchoTotal(echoes)
                local dps = b._nexusDps
                    or {dummy=0,lk=0,best=0,average=0,count=0}
                if b._nexusDpsDeferred then
                    card.echoCount:SetText("|cff888888DPS in Leaderboard|r")
                    card.dpsBreakdown:SetText("Temporary safe mode")
                elseif dps.count == 2 then
                    card.echoCount:SetText(string.format("|cff4dff80%s avg|r", DpsText(dps.average)))
                    card.dpsBreakdown:SetText(string.format("Dummy %s  |cff777777•|r  LK %s", DpsText(dps.dummy), DpsText(dps.lk)))
                elseif dps.dummy > 0 then
                    card.echoCount:SetText(string.format("|cff4dff80%s DPS|r", DpsText(dps.dummy)))
                    card.dpsBreakdown:SetText("Training Dummy")
                elseif dps.lk > 0 then
                    card.echoCount:SetText(string.format("|cff4dff80%s DPS|r", DpsText(dps.lk)))
                    card.dpsBreakdown:SetText("Lich King")
                else
                    card.echoCount:SetText("|cff777777No DPS record|r")
                    card.dpsBreakdown:SetText("")
                end
            end
        else
            card.echoCount:SetText("|cffffd200Syncing full loadout...|r")
            card.dpsBreakdown:SetText("")
            card.title:SetTextColor(0.65,0.65,0.65)
            card.author:SetText("by "..(b.author or "?").."  |cff777777- waiting for Echoes|r")
        end

        card.mineBadge:Hide()
        card.addBtn:SetText("View")
        card.addBtn:SetSize(52,22)
        card.addBtn:Show()
        card.menuBtn:Hide()
        card.record = nil

        yOffset = yOffset + rowHeight
    end

    -- Empty state
    if #builds == 0 then
        local total = projectionSummary and projectionSummary.total or 0
        if not projectionSummary then
            for _ in pairs(Store()) do total=total+1 end
        end
        local msg
        msg = total == 0
            and "No builds yet.\n\nPost a build from your active Echo Wishlist, or press Sync Now to find builds from other players."
            or  "No builds match your current search or class filter."
        if frame._emptyState then
            frame._emptyState:SetText(msg)
            frame._emptyState:Show()
        end
        scrollChild:SetHeight(80)
        scrollBar:SetMinMaxValues(0,0)
        scrollBar.value = 0
        pcall(function() scrollFrame:SetVerticalScroll(0) end)
        RefreshDetailPanel(nil)
    else
        if frame._emptyState then frame._emptyState:Hide() end
        scrollChild:SetHeight(math.max(virtual.contentHeight, 10))
        scrollBar:SetMinMaxValues(0, virtual.maxOffset)
        scrollBar.value = virtual.offset
        pcall(function() scrollFrame:SetVerticalScroll(virtual.offset) end)
    end
    virtualStats.results = #builds
    virtualStats.active = #activeCards
    virtualStats.peakActive = math.max(virtualStats.peakActive, #activeCards)
    virtualStats.first, virtualStats.last = virtual.first, virtual.last
    virtualStats.offset, virtualStats.maxOffset = virtual.offset, virtual.maxOffset
    virtualStats.selectedVisible = false
    for index = virtual.first, virtual.last do
        if builds[index] and builds[index].id == selectedId then
            virtualStats.selectedVisible = true
            break
        end
    end
    if reason == "scroll" then
        virtualStats.scrollBinds = virtualStats.scrollBinds + 1
    elseif reason == "resize" then
        virtualStats.resizeBinds = virtualStats.resizeBinds + 1
    else
        virtualStats.dataBinds = virtualStats.dataBinds + 1
    end
        end)
        virtualBinding = false
        if not ok then
            pcall(ReleaseAllCards)
            pcall(ReleaseAllHeaders)
            virtualStats.active = 0
            virtualStats.first, virtualStats.last = 1, 0
            virtualStats.selectedVisible = false
            error(err)
        end
    end
    renderBuildWindow("data")

    -- Detail panel
    RefreshDetailPanel(selectedId and LoadBuild(selectedId))

    -- Search placeholder visibility
    if searchBox then
        local lbl = searchBox:GetParent() and searchBox:GetParent().searchLabel
        -- just handle via the text directly: show placeholder if empty
    end
    refreshDirty = false
end

------------------------------------------------------------------------
-- Post popup
------------------------------------------------------------------------

local postTitleBox, postDescBox
local postPreviewIcons = {}
local postSelectedWishlist, postSelectedClass
local postWishlistBtn, postClassBtn, postWishlistMenu, postClassMenu
local RefreshPostPopupPreview

local CLASS_PICK_ORDER = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
    "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local function MakeDropdownMenu(parent, width)
    local menu = CreateFrame("Frame", nil, parent)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetWidth(width)
    menu:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3},
    })
    menu:SetBackdropColor(0.03,0.03,0.03,0.98)
    menu._buttons = {}
    menu:Hide()
    return menu
end

local function AddMenuButton(menu, text, onClick, index)
    menu._buttons = menu._buttons or {}
    local b = menu._buttons[index]
    if not b then
        b = CreateFrame("Button", nil, menu)
        b:SetHeight(22)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local fs = b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        fs:SetPoint("LEFT",6,0); fs:SetPoint("RIGHT",-6,0); fs:SetJustifyH("LEFT")
        b._label = fs
        menu._buttons[index] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT",6,-6-(index-1)*22)
    b:SetPoint("TOPRIGHT",-6,0-(index-1)*22)
    b._label:SetText(text)
    b:SetScript("OnClick", function() menu:Hide(); onClick() end)
    b:Show()
    return b
end

local function HidePostMenus()
    if postWishlistMenu then postWishlistMenu:Hide() end
    if postClassMenu then postClassMenu:Hide() end
end

local function BuildSourceCandidates()
    local out, seen = {}, {}
    local slots = Adapter and Adapter.Slots and Adapter.Slots()
    if slots and type(slots.bySlot) == "table" then
        local keys={}
        for slot in pairs(slots.bySlot) do keys[#keys+1]=tonumber(slot) or slot end
        table.sort(keys,function(a,b) return tonumber(a) < tonumber(b) end)
        for _,slot in ipairs(keys) do
            local live=slots.bySlot[slot]
            if live and type(live.echoes)=="table" and #live.echoes>0 then
                local kind=(tonumber(slot) or 0)>=100 and "Wishlist" or "Saved Build"
                out[#out+1]={slot=slot,name=live.name or (kind.." "..tostring(slot)),count=#live.echoes,echoes=live.echoes,active=slots.activeSlot==slot,sourceKind=kind}
                seen[tostring(slot)]=true
            end
        end
    end
    local candidates = Adapter and Adapter.GetWishlistCandidates and Adapter.GetWishlistCandidates()
    if type(candidates)=="table" then
        for _,c in ipairs(candidates) do
            if not seen[tostring(c.slot)] and type(c.echoes)=="table" and #c.echoes>0 then c.sourceKind="Wishlist"; out[#out+1]=c end
        end
    end
    return out
end

local function BuildWishlistCandidates()
    return BuildSourceCandidates()
end

local function WishlistLabel(wl)
    local kind=(wl and wl.sourceKind) or "Wishlist"
    local name=(wl and wl.name and wl.name~="") and wl.name or ("Unnamed "..kind)
    local count=0
    for _,e in ipairs((wl and wl.echoes) or {}) do count=count+(tonumber(e.stacks or e.count) or 1) end
    return string.format("[%s] %s  —  %d / 79", kind, name, count)
end

local function RefreshPostWishlistMenu()
    if not postWishlistMenu then return end
    for _, child in ipairs(postWishlistMenu._buttons or {}) do
        child:Hide(); child:SetScript("OnClick", nil)
    end
    local candidates = BuildWishlistCandidates()
    local h = math.min(300, 12 + #candidates * 24)
    postWishlistMenu:SetHeight(h)
    for i, c in ipairs(candidates) do
        AddMenuButton(postWishlistMenu, WishlistLabel(c), function()
            postSelectedWishlist = c
            postWishlistBtn:SetText("Source: " .. ((c.name and c.name ~= "") and c.name or "Unnamed"))
            RefreshPostPopupPreview()
        end, i)
    end
    if #candidates == 0 then
        AddMenuButton(postWishlistMenu, "No saved builds or wishlists found", function() end, 1)
        postWishlistMenu:SetHeight(40)
    end
end

local function RefreshPostClassMenu()
    if not postClassMenu then return end
    for _, child in ipairs(postClassMenu._buttons or {}) do
        child:Hide(); child:SetScript("OnClick", nil)
    end
    postClassMenu:SetHeight(12 + #CLASS_PICK_ORDER * 24)
    for i, token in ipairs(CLASS_PICK_ORDER) do
        AddMenuButton(postClassMenu, CLASS_LABEL[token], function()
            postSelectedClass = token
            local cc = CLASS_COLOR[token] or {1,1,1}
            postClassBtn:SetText("Class: " .. CLASS_LABEL[token])
            postClassBtn:GetFontString():SetTextColor(cc[1],cc[2],cc[3])
            RefreshPostPopupPreview()
        end, i)
    end
end

local function EnsurePostPopup()
    if postPopup then return postPopup end
    local p = CreateFrame("Frame","NexusPostPopup",UIParent)
    p:SetSize(760, 560)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true); p:SetMovable(true); p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart",function(self) self:StartMoving() end)
    p:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    p:Hide()
    pcall(function() p:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,insets={left=11,right=12,top=12,bottom=11}}) end)

    local titleBar = p:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleBar:SetPoint("TOP",0,-14); titleBar:SetText("Share a Nexus Build")
    local close = CreateFrame("Button",nil,p,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",-2,-2); close:SetScript("OnClick",function() HidePostMenus(); p:Hide() end)

    local tl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); tl:SetPoint("TOPLEFT",16,-38); tl:SetText("Build Title:")
    postTitleBox = CreateFrame("EditBox",nil,p,"InputBoxTemplate"); postTitleBox:SetSize(330,20); postTitleBox:SetPoint("TOPLEFT",16,-54); postTitleBox:SetAutoFocus(false)

    local dl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); dl:SetPoint("TOPLEFT",16,-88); dl:SetText("Description (what makes this build stand out):")
    local descBg = CreateFrame("Frame",nil,p); descBg:SetPoint("TOPLEFT",14,-104); descBg:SetSize(334,180)
    pcall(function() descBg:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}}); descBg:SetBackdropColor(0,0,0,0.5) end)
    postDescBox = CreateFrame("EditBox",nil,descBg); postDescBox:SetMultiLine(true); postDescBox:SetSize(318,170); postDescBox:SetPoint("TOPLEFT",6,-6); postDescBox:SetAutoFocus(false); postDescBox:SetFontObject("GameFontHighlightSmall"); postDescBox:EnableMouse(true); postDescBox:SetScript("OnMouseDown", function(self) self:SetFocus() end); postDescBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local chooseLabel = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); chooseLabel:SetPoint("TOPLEFT",16,-302); chooseLabel:SetText("1. Choose the exact server loadout or wishlist to share:")
    postWishlistBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); postWishlistBtn:SetSize(334,26); postWishlistBtn:SetPoint("TOPLEFT",16,-320); postWishlistBtn:SetText("Source: Select a saved build or wishlist")
    postWishlistMenu = MakeDropdownMenu(p,334); postWishlistMenu:SetPoint("TOPLEFT",16,-348)
    p._postWishlistBtn, p._postWishlistMenu = postWishlistBtn, postWishlistMenu
    postWishlistBtn:SetScript("OnClick",function() HidePostMenus(); RefreshPostWishlistMenu(); postWishlistMenu:Show() end)

    postClassBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); postClassBtn:SetSize(334,26); postClassBtn:SetPoint("TOPLEFT",16,-360); postClassBtn:SetText("Class: Select a class")
    postClassMenu = MakeDropdownMenu(p,334); postClassMenu:SetPoint("TOPLEFT",16,-388)
    p._postClassBtn, p._postClassMenu = postClassBtn, postClassMenu
    postClassBtn:SetScript("OnClick",function() HidePostMenus(); RefreshPostClassMenu(); postClassMenu:Show() end)

    local previewLabel = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); previewLabel:SetPoint("TOPLEFT",380,-38); previewLabel:SetText("Exact Echo Loadout Preview:")
    local previewWishlist = p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); previewWishlist:SetPoint("TOPLEFT",380,-54); previewWishlist:SetSize(350,16); previewWishlist:SetJustifyH("LEFT"); p._previewWishlist=previewWishlist
    local previewClass = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); previewClass:SetPoint("TOPLEFT",380,-74); previewClass:SetSize(350,14); previewClass:SetJustifyH("LEFT"); p._previewClass=previewClass
    local previewSummary = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); previewSummary:SetPoint("TOPLEFT",380,-92); previewSummary:SetSize(350,14); previewSummary:SetJustifyH("LEFT"); p._previewSummary=previewSummary
    local previewClip=CreateFrame("Frame",nil,p); previewClip:SetPoint("TOPLEFT",374,-112); previewClip:SetSize(370,390); pcall(function() previewClip:SetClipsChildren(true) end); p._previewClip=previewClip
    local previewScroll=CreateFrame("ScrollFrame",nil,previewClip); previewScroll:SetAllPoints(previewClip); previewScroll:EnableMouseWheel(true); p._previewScroll=previewScroll
    local previewChild=CreateFrame("Frame",nil,previewScroll); previewChild:SetWidth(360); previewChild:SetHeight(1); previewScroll:SetScrollChild(previewChild); p._previewChild=previewChild
    p._previewRows={}
    for i=1,100 do
        local row=CreateFrame("Frame",nil,previewChild); row:SetSize(355,22)
        local icon=row:CreateTexture(nil,"ARTWORK"); icon:SetSize(20,20); icon:SetPoint("LEFT",0,0); row.icon=icon
        local text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); text:SetPoint("LEFT",26,0); text:SetSize(325,20); text:SetJustifyH("LEFT"); row.text=text; row:Hide(); p._previewRows[i]=row
    end
    local noWishlistNote=p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); noWishlistNote:SetPoint("TOPLEFT",380,-112); noWishlistNote:SetSize(350,80); noWishlistNote:SetJustifyH("LEFT"); noWishlistNote:SetJustifyV("TOP"); p._noWishlistNote=noWishlistNote

    local postGoBtn=CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); postGoBtn:SetSize(150,28); postGoBtn:SetPoint("BOTTOM",0,16); postGoBtn:SetText("Share Build"); p._postGoBtn=postGoBtn
    postGoBtn:SetScript("OnClick",function()
        if not postSelectedWishlist or not postSelectedClass then print("|cffff6060Nexus:|r Select a source loadout and class before sharing."); return end
        local ok,err=M.PostCurrentWishlist(postTitleBox:GetText(),postDescBox:GetText(),postSelectedWishlist,postSelectedClass)
        if ok then print("|cff4dff80Nexus:|r build shared!"); p:Hide(); M.Refresh() else print("|cffff6060Nexus:|r "..tostring(err)) end
    end)
    postPopup=p; return p
end

local function EchoDisplayName(spellId)
    local cat=Adapter and Adapter.Catalog and Adapter.Catalog(); local row=cat and cat.rows and cat.rows[tonumber(spellId)]
    if row and row.name and row.name ~= "" then return row.name end
    local name=GetSpellInfo and GetSpellInfo(spellId); return name or ("Echo "..tostring(spellId))
end

RefreshPostPopupPreview = function()
    if not postPopup or not postPopup:IsShown() then return end
    local wl=postSelectedWishlist
    local echoes = WishlistEchoes(wl)
    if not wl or not echoes or #echoes==0 then
        for _,row in ipairs(postPopup._previewRows or {}) do row:Hide() end
        postPopup._noWishlistNote:SetText("|cffff6060No source selected.|r\n\nChoose a server Saved Build or Wishlist to share.")
        postPopup._noWishlistNote:Show(); postPopup._previewWishlist:SetText(""); postPopup._previewSummary:SetText(""); postPopup._previewClass:SetText(""); postPopup._postGoBtn:Disable(); return
    end
    postPopup._noWishlistNote:Hide(); postPopup._postGoBtn:Enable()
    local wishlistName=(wl.name and wl.name~="") and wl.name or "Unnamed Echo Wishlist"
    local classToken=postSelectedClass or InferBuildClass(echoes) or ""
    postPopup._previewWishlist:SetText("|cffffd200"..wishlistName.."|r")
    postPopup._previewSummary:SetText(string.format("|cff888888%d Echo rows in this source|r",#echoes))
    local cc=CLASS_COLOR[(classToken or ""):upper()] or {1,1,1}; postPopup._previewClass:SetTextColor(cc[1],cc[2],cc[3]); postPopup._previewClass:SetText("Posting as: "..(CLASS_LABEL[(classToken or ""):upper()] or classToken or "Select a class"))
    local child=postPopup._previewChild
    for i,row in ipairs(postPopup._previewRows or {}) do
        local e=echoes[i]
        if e then row:ClearAllPoints(); row:SetPoint("TOPLEFT",child,"TOPLEFT",0,-(i-1)*22); row.icon:SetTexture(SpellIcon(e.spellId)); local stacks=tonumber(e.stacks) or 1; local suffix=stacks>1 and ("  x"..stacks) or ""; row.text:SetText(string.format("%02d. %s%s",i,EchoDisplayName(e.spellId),suffix)); row:Show() else row:Hide() end
    end
    child:SetHeight(math.max(1,#echoes*22)); pcall(function() postPopup._previewScroll:SetVerticalScroll(0) end)
end

function M.ShowPostBuild()
    EnsurePostPopup()
    if postPopup:IsShown() then HidePostMenus(); postPopup:Hide(); return end
    local candidates=BuildWishlistCandidates(); postSelectedWishlist=candidates[1]
    local wl=postSelectedWishlist
    -- Auto-detect class from echo catalog, then fall back to player's own class
    postSelectedClass = InferBuildClass(WishlistEchoes(wl) or {}) or ""
    if postSelectedClass == "" and UnitClass then
        local _, classToken = UnitClass("player")
        postSelectedClass = (classToken and classToken ~= "UNKNOWN") and tostring(classToken) or ""
    end
    postTitleBox:SetText((wl and wl.name and wl.name~="") and wl.name or "")
    postDescBox:SetText("")
    postWishlistBtn:SetText("Source: "..((wl and wl.name and wl.name~="") and wl.name or "Select a saved build or wishlist"))
    if postSelectedClass ~= "" then
        local cc = CLASS_COLOR[postSelectedClass:upper()] or {1,1,1}
        postClassBtn:SetText("Class: "..(CLASS_LABEL[postSelectedClass:upper()] or postSelectedClass))
        pcall(function() postClassBtn:GetFontString():SetTextColor(cc[1],cc[2],cc[3]) end)
    else
        postClassBtn:SetText("Class: Select a class")
    end
    postPopup:ClearAllPoints(); postPopup:SetPoint("CENTER"); postPopup:Show(); RefreshPostPopupPreview()
end

function M.TogglePostPopup(anchor) M.ShowPostBuild() end

------------------------------------------------------------------------
-- Edit popup
------------------------------------------------------------------------

local editTitleBox, editDescBox, editEchoBtn, editLockText

local function EnsureEditPopup()
    if editPopup then return editPopup end
    local p = CreateFrame("Frame","NexusEditPopup",UIParent)
    p:SetSize(360,282); p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true); p:Hide()

    local title = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOP",0,-12); title:SetText("Edit Build")

    local close = CreateFrame("Button",nil,p,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",-2,-2); close:SetScript("OnClick",function() p:Hide() end)

    local tl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    tl:SetPoint("TOPLEFT",16,-36); tl:SetText("Title:")
    editTitleBox = CreateFrame("EditBox",nil,p,"InputBoxTemplate")
    editTitleBox:SetSize(310,20); editTitleBox:SetPoint("TOPLEFT",20,-52); editTitleBox:SetAutoFocus(false)

    local dl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    dl:SetPoint("TOPLEFT",16,-80); dl:SetText("Description:")
    local descBg = CreateFrame("Frame",nil,p)
    descBg:SetPoint("TOPLEFT",18,-96); descBg:SetSize(324,86)
    pcall(function()
        descBg:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=16,edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
        descBg:SetBackdropColor(0,0,0,0.5)
    end)
    editDescBox = CreateFrame("EditBox",nil,descBg)
    editDescBox:SetMultiLine(true); editDescBox:SetSize(310,76)
    editDescBox:SetPoint("TOPLEFT",6,-6); editDescBox:SetAutoFocus(false)
    editDescBox:SetFontObject("GameFontHighlightSmall")

    editLockText = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    editLockText:SetPoint("TOPLEFT",18,-190)
    editLockText:SetSize(324,30)
    editLockText:SetJustifyH("LEFT")
    editLockText:SetJustifyV("TOP")

    editEchoBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    editEchoBtn:SetSize(210,22)
    editEchoBtn:SetPoint("BOTTOMLEFT",18,16)
    editEchoBtn:SetText("Use Active Wishlist Echoes")
    editEchoBtn:SetScript("OnClick",function()
        if not p._editingId then return end
        local ok, result = M.UpdateFromWishlist(p._editingId)
        if ok then
            print(string.format("|cff4dff80Nexus:|r Echo list replaced with the active wishlist (%d Echoes).", result))
            p:Hide(); M.Refresh()
        else
            print("|cffff6060Nexus:|r " .. tostring(result))
        end
    end)

    local saveBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    saveBtn:SetSize(118,22); saveBtn:SetPoint("BOTTOMRIGHT",-18,16); saveBtn:SetText("Save Details")
    saveBtn:SetScript("OnClick",function()
        if not p._editingId then return end
        local ok, err = M.EditBuild(p._editingId, editTitleBox:GetText(), editDescBox:GetText())
        if ok then print("|cff4dff80Nexus:|r build updated and re-shared."); p:Hide(); M.Refresh()
        else print("|cffff6060Nexus:|r "..tostring(err)) end
    end)
    pcall(function()
        p:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true,tileSize=32,edgeSize=32, insets={left=11,right=12,top=12,bottom=11} })
    end)
    editPopup = p; return p
end

function M.ToggleEditPopup(id)
    EnsureEditPopup()
    if editPopup:IsShown() then editPopup:Hide(); return end
    local b = LoadBuild(id)
    if not b or not IsOwnBuild(b) then return end
    editPopup._editingId = id
    local locked = HasLeaderboardRecord(b)
    if locked then
        editEchoBtn:Disable()
        editLockText:SetText("|cffffd200Echo list locked by leaderboard record.|r Post a new build to use a different loadout.")
    else
        editEchoBtn:Enable()
        editLockText:SetText("Change title/description, or replace the Echo list with your current active wishlist.")
    end
    local editName = b.title
    if not editName or editName == "" then editName = b.userTitle end
    if (not editName or editName == "") and b.importedSavedBuild then
        editName = b.serverTitle
        if (not editName or editName == "") and b.serverSlot and Adapter and Adapter.Slots then
            local slots = Adapter.Slots()
            local live = slots and slots.bySlot and slots.bySlot[b.serverSlot]
            editName = live and live.name or nil
        end
    end
    editTitleBox:SetText((editName and editName ~= "") and editName or "Untitled Build")
    editTitleBox:HighlightText(0, 0)
    editDescBox:SetText(b.description or "")
    editPopup:ClearAllPoints(); editPopup:SetPoint("CENTER")
    editPopup:Show()
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

-- Community data is intentionally empty on first install.
-- The admin can publish real builds from the Post Build flow.

function M.Init(adapter, model)
    Adapter, Model = adapter, model
    if Catalog() and Catalog().Init then
        Catalog().Init(NexusDB or {}, Nexus.BundledBuilds)
    end
    RemoveLegacyBuilds()  -- once at startup, not on every Store() access
    -- Repair hashes written by the short-lived two-part hash implementation.
    -- This is metadata-only: no timestamps or ownership fields are changed.
    for id, build in pairs(Store()) do
        local _, source = Catalog().Get(id)
        if source == "overlay" and type(build.echoes) == "table"
            and #build.echoes > 0 then
            local oldFingerprint = build.fingerprint
            local oldHash = build.fingerprintHash
            local oldCount = build.echoCount
            local oldAvailable = build.loadoutAvailable
            local oldNeeds = build.needsFullBuild
            if RefreshBuildIdentity(build)
                and (oldFingerprint ~= build.fingerprint
                    or oldHash ~= build.fingerprintHash
                    or oldCount ~= build.echoCount
                    or oldAvailable ~= build.loadoutAvailable
                    or oldNeeds ~= build.needsFullBuild) then
                SaveBuild(build)
            end
        end
    end
end

function M.Select(id)
    selectedId = id
    M.Refresh()
end

function M.SetViewMode(mode)
    if mode == "dummy" or mode == "lk" then
        if frame then frame:Hide() end
        if Nexus.Leaderboard then Nexus.Leaderboard.Show(mode) end
        return
    end
    M.Refresh()
end

function M.GetViewMode() return "builds" end

function M.Show()
    EnsureFrame()
    local receiving = Nexus.Sync and Nexus.Sync.IsReceiving
        and Nexus.Sync.IsReceiving() or false
    if receiving then M.MarkDataDirty()
    else ImportCurrentSavedLoadouts(true) end
    if Nexus.Panel and Nexus.Panel.AttachMenuFrame then Nexus.Panel.AttachMenuFrame(frame) end
    if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(frame, 0.96) end
    if Nexus.Panel and Nexus.Panel.CloseOtherWindows then Nexus.Panel.CloseOtherWindows("NexusCommunityBuildsFrame") end
    frame:Show()
    M.Refresh()
end

function M.ShowBuild(id)
    selectedId = id
    M.Show()
    local build = id and LoadBuild(id)
    if build and (not build.echoes or #build.echoes == 0)
        and Nexus.Sync and Nexus.Sync.RequestLoadout then
        Nexus.Sync.RequestLoadout(id)
    end
    M.Refresh()
end

function M.Hide() if frame then frame:Hide() end end
function M.IsShown() return frame and frame:IsShown() or false end

function M.Toggle()
    EnsureFrame()
    if frame:IsShown() then frame:Hide()
    else M.Show() end
end
