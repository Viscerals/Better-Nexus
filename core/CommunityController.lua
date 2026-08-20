-- Nexus: core/CommunityController.lua
-- Frame-free Community catalog, interaction, retry, and popup-draft owner.

Nexus = Nexus or {}
Nexus.CommunityInternals = Nexus.CommunityInternals or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before CommunityController")

local Controller = {}

local function Measure(name, callback, ...)
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        return performance.Measure(name, callback, ...)
    end
    return callback(...)
end

local function StableIdHash(text)
    text = tostring(text or "")
    local h1, h2 = 5381, 2166136261
    for i = 1, #text do
        local b = text:byte(i)
        h1 = (h1 * 33 + b) % 2147483647
        h2 = (h2 * 131 + b) % 2147483629
    end
    return string.format("%08x%08x", h1, h2)
end

local COLLISION_ATTEMPT_LIMIT = 16

local function CollisionCandidateId(base, token, attempt)
    if attempt == 0 then return base end
    if attempt == 1 then return base .. "-" .. token end
    return base .. "-" .. token .. "-" .. tostring(attempt)
end

function Controller.New(options)
    options = type(options) == "table" and options or {}
    local M = {}
    local Adapter
    local selectedId
    local pendingLockIn
    local lastSavedLoadoutImport = 0
    local savedImportJob
    local lastShareOutcome
    local savedRelatedCache, savedRelatedCacheRevision = {}, -1
    local savedImportStats = {
        jobs=0,jobStarts=0,pumps=0,workUnits=0,maxWorkPerPump=0,
        slotPreparations=0,emptySlots=0,
        wishlistDiscoveryReads=0,wishlistDiscoveries=0,
        candidateAdvances=0,candidates=0,maxCandidatesPerPump=0,
        restarts=0,sourceRevisionRestarts=0,
        buildRevisionRestarts=0,slotGenerationRestarts=0,
        cursorRestarts=0,syncDeferrals=0,finalizations=0,
        catalogPuts=0,catalogPutCalls=0,catalogPutChanges=0,
        compactionCalls=0,compactionWrites=0,
        referenceCalls=0,referenceStores=0,
        relatedIndexUpdates=0,writes=0,
        cleanupEnumerations=0,cleanupCandidates=0,
        cleanupExamined=0,cleanupRemovals=0,completions=0,
    }
    local postDraft = {wishlist=nil,class=nil}
    local editDraft
    local fallbackFilters = {}
    local RefreshBuildIdentity
    local IsOwnBuild
    local RelatedBuild
    local PublishedBuild
    local refreshView = type(options.refresh) == "function"
        and options.refresh or function() end
    local notify = type(options.notify) == "function"
        and options.notify or print

    local function PeerRecord(kind, fields)
        local debugOwner = Nexus and Nexus.PeerDebug
        if not (debugOwner and type(debugOwner.IsEnabled) == "function"
            and debugOwner.IsEnabled()
            and type(debugOwner.Record) == "function") then return false end
        local ok, recorded = pcall(debugOwner.Record, kind, fields)
        return ok and recorded == true
    end

    local CLASS_LABEL = {
        DEATHKNIGHT="Death Knight", DRUID="Druid", HUNTER="Hunter",
        MAGE="Mage", PALADIN="Paladin", PRIEST="Priest",
        ROGUE="Rogue", SHAMAN="Shaman", WARLOCK="Warlock", WARRIOR="Warrior",
    }

    local function Catalog()
        if type(options.catalog) == "function" then return options.catalog() end
        return Nexus and Nexus.BuildCatalog
    end

    local function BuildRevision()
        local revisions = Nexus and Nexus.Revisions
        return revisions and revisions.Get
            and revisions.Get(revisions.BUILD_LIBRARY_CHANGED) or 0
    end

    local function SlotGeneration()
        if not (Adapter and type(Adapter.EchoReconcileStats) == "function") then
            return nil
        end
        local ok, stats = pcall(Adapter.EchoReconcileStats)
        local value = ok and type(stats) == "table"
            and type(stats.generations) == "table"
            and tonumber(stats.generations.slots) or nil
        return value
    end

    local function LoadBuild(id)
        local catalog = Catalog()
        if not (catalog and catalog.Get) then return nil end
        return catalog.Get(id)
    end

    local function ShallowCopy(record)
        if type(record) ~= "table" then return nil end
        local out = {}
        for key, value in pairs(record) do out[key] = value end
        return out
    end

    local function LoadBuildSummary(id)
        local catalog = Catalog()
        if not (catalog and type(catalog.GetSummary) == "function") then
            return nil
        end
        return catalog.GetSummary(id)
    end

    local function AllocationOccupancy(id)
        local catalog = Catalog()
        if catalog and type(catalog.AllocationOccupancy) == "function" then
            local ok, state, represented = pcall(
                catalog.AllocationOccupancy, id)
            if ok and (state == "absent" or state == "visible"
                or state == "bundled" or state == "tombstone"
                or state == "opaque") then
                return state, represented
            end
            return "opaque", nil
        end
        -- Compatibility for injected controller-only tests. The shipped
        -- catalog always supplies AllocationOccupancy and therefore protects
        -- tombstones, bundled IDs, and malformed raw persistence.
        local represented = LoadBuild(id)
        return represented and "visible" or "absent", represented
    end

    local function FindStableCollisionTarget(base, token, reusable)
        local firstFree
        local lastAttempt = token and COLLISION_ATTEMPT_LIMIT or 0
        for attempt = 0, lastAttempt do
            local candidateId = CollisionCandidateId(base, token, attempt)
            local state, candidate = AllocationOccupancy(candidateId)
            if state == "absent" then
                if not firstFree then firstFree = candidateId end
            elseif state == "visible" and type(reusable) == "function"
                and reusable(candidate) then
                return candidateId, candidate
            end
        end
        return firstFree, nil
    end

    local function SaveBuild(build)
        local catalog = Catalog()
        if not (catalog and catalog.Put) then
            return false, "build catalog unavailable"
        end
        return catalog.Put(build)
    end

    local function CatalogStats()
        local catalog = Catalog()
        if not (catalog and type(catalog.DebugStats) == "function") then
            return {}
        end
        local ok, stats = pcall(catalog.DebugStats)
        return ok and type(stats) == "table" and stats or {}
    end

    local function RecordCatalogDelta(before)
        local after = CatalogStats()
        local fields = {
            putCalls="catalogPutCalls",putChanges="catalogPutChanges",
            compactionCalls="compactionCalls",
            compactionWrites="compactionWrites",
            referenceCalls="referenceCalls",
            referenceStores="referenceStores",
            relatedIndexUpdates="relatedIndexUpdates",
        }
        for source, target in pairs(fields) do
            local delta = (tonumber(after[source]) or 0)
                - (tonumber(before[source]) or 0)
            if delta > 0 then
                savedImportStats[target] = savedImportStats[target] + delta
            end
        end
    end

    local function RemoveOverlay(id)
        local catalog = Catalog()
        if catalog and type(catalog.RemoveOverlay) == "function" then
            return catalog.RemoveOverlay(id)
        end
        return false, "build catalog unavailable"
    end

    local function SetTombstone(id, tombstone)
        local catalog = Catalog()
        if catalog and type(catalog.SetTombstone) == "function" then
            return catalog.SetTombstone(id, tombstone)
        end
        return false, "build catalog unavailable"
    end

    local function Store()
        local catalog = Catalog()
        return catalog and catalog.All and catalog.All() or {}
    end

    local function IsAdmin()
        local name = UnitName and UnitName("player")
        return name and tostring(name):lower() == "explore"
    end

    local function EchoProgress(current, target)
        local have = {}
        for _, echo in ipairs(type(current) == "table" and current or {}) do
            local id = tonumber(echo.spellId or echo.id) or 0
            have[id] = (have[id] or 0)
                + (tonumber(echo.stacks or echo.count) or 1)
        end
        local matched, total = 0, 0
        for _, echo in ipairs(type(target) == "table" and target or {}) do
            local id = tonumber(echo.spellId or echo.id) or 0
            local need = tonumber(echo.stacks or echo.count) or 1
            total = total + need
            local count = math.min(need, have[id] or 0)
            matched = matched + count
            have[id] = math.max(0, (have[id] or 0) - count)
        end
        return matched, total
    end

    local function FilterSettings()
        if type(options.filterSettings) == "function" then
            local filters = options.filterSettings()
            if type(filters) == "table" then return filters end
        end
        if type(NexusDB) ~= "table" then return fallbackFilters end
        NexusDB.buildFilters = type(NexusDB.buildFilters) == "table"
            and NexusDB.buildFilters or {}
        return NexusDB.buildFilters
    end


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

    local function CurrentClass()
        if type(UnitClass) ~= "function" then return nil end
        local ok, _, token = pcall(UnitClass, "player")
        return ok and NormalizeClass(token) or nil
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
        return Identity.OwnerKey(name, realm or CurrentRealm())
    end

    local function CurrentOwnerKey()
        return OwnerKey(UnitName and UnitName("player"), CurrentRealm())
    end

    local function CurrentVerifiedOwnerKey()
        local ownerKey = Identity.CanonicalOwnerKey(CurrentOwnerKey())
        return ownerKey and not ownerKey:match("@unknown$")
            and ownerKey or nil
    end

    local function OwnerEvidenceKey(record)
        if type(record) ~= "table" then return nil end
        if record.a ~= nil then return nil end
        local ownerKey
        for _, field in ipairs({"claimedOwnerKey", "ownerKey", "o"}) do
            local value = record[field]
            if value ~= nil then
                local canonical = Identity.CanonicalOwnerKey(value)
                if not canonical or canonical:match("@unknown$")
                    or (ownerKey and ownerKey ~= canonical) then return nil end
                ownerKey = canonical
            end
        end
        local authorFields = {"player", "p", "author"}
        local firstAuthor
        for _, field in ipairs(authorFields) do
            local value = record[field]
            if value ~= nil then
                if type(value) ~= "string" or not Identity.ValidPlayer(value) then
                    return nil
                end
                firstAuthor = firstAuthor or value
            end
        end
        local realmFields = {"realm", "r"}
        local firstRealm
        for _, field in ipairs(realmFields) do
            local value = record[field]
            if value ~= nil then
                if type(value) ~= "string" or value == ""
                    or value:find("[%c|%s]") then return nil end
                firstRealm = firstRealm or value
            end
        end
        if ownerKey == nil and firstAuthor and firstRealm then
            ownerKey = Identity.CanonicalOwnerKey(
                Identity.OwnerKey(firstAuthor, firstRealm))
        end
        if not ownerKey then return nil end
        for _, field in ipairs(authorFields) do
            local author = record[field]
            if author ~= nil then
                if not Identity.OwnerKeyMatchesAuthor(ownerKey, author)
                    or (author:find("-", 1, true)
                        and Identity.CanonicalOwnerFromTransport(author)
                            ~= ownerKey) then return nil end
            end
        end
        local ownerName = ownerKey:match("^([^@]+)@")
        for _, field in ipairs(realmFields) do
            local realm = record[field]
            if realm ~= nil and Identity.CanonicalOwnerKey(
                Identity.OwnerKey(ownerName, realm)) ~= ownerKey then
                return nil
            end
        end
        return ownerKey
    end

    -- A fresh verified DPS owner may repair its own retained auto page even
    -- when old transport aliases made that page non-authoritative. This helper
    -- is promotion-only: it never grants reads, edits, publication, or relay.
    local function CanPromoteOwnerEvidence(record, incomingOwner)
        incomingOwner = Identity.CanonicalOwnerKey(incomingOwner)
        if type(record) ~= "table" or not incomingOwner
            or Identity.SavedMirrorKind(record) ~= "ordinary"
            or record.autoDps ~= true
            or Identity.VerifiedOwnerKey(record) ~= nil then return false end
        local claimedKey = Identity.CanonicalOwnerKey(record.claimedOwnerKey)
        local storedKey = Identity.CanonicalOwnerKey(record.ownerKey)
        if claimedKey and storedKey and claimedKey ~= storedKey then return false end
        local claim = claimedKey or storedKey
        if claim ~= incomingOwner then return false end
        local author = record.author
        if author ~= nil and (type(author) ~= "string"
            or not Identity.OwnerKeyMatchesAuthor(incomingOwner, author)
            or (author:find("-", 1, true)
                and Identity.CanonicalOwnerFromTransport(author)
                    ~= incomingOwner)) then return false end
        return true
    end

    local function VerifiedDpsOwnerKey(record)
        if type(record) ~= "table" or record.ownerVerified ~= true then
            return nil
        end
        local dps = Nexus and Nexus.DpsCapture
        if not (dps and type(dps.VerifiedOwnerKey) == "function") then
            return nil
        end
        return dps.VerifiedOwnerKey(record)
    end

    local function ApplyVerifiedBuildOwner(build, ownerKey, author)
        build.ownerKey = ownerKey
        build.ownerVerified = true
        build.claimedOwnerKey = nil
        build.relaySender = nil
        build.author = author
        build.player = nil
        build.realm = ownerKey:match("@(.+)$")
        build.a, build.o, build.p, build.r = nil, nil, nil, nil
        build.isMine = ownerKey == CurrentVerifiedOwnerKey()
    end

    function M.BindAdapter(adapter)
        Adapter = adapter
    end

    function M.Build(id)
        local build = LoadBuild(id)
        if M.ProjectBuild then return M.ProjectBuild(build) end
        return build
    end

    function M.Builds()
        return Store()
    end

    function M.BuildCount()
        local catalog = Catalog()
        if not (catalog and type(catalog.Count) == "function") then return 0 end
        local ok, count = pcall(catalog.Count)
        return ok and math.max(0, tonumber(count) or 0) or 0
    end

    function M.IsAdmin()
        return IsAdmin() and true or false
    end

    function M.RevisionSnapshot()
        local revisions = Nexus and Nexus.Revisions
        if not (revisions and type(revisions.Get) == "function") then
            return {build=0,dps=0}
        end
        return {
            build=revisions.Get(revisions.BUILD_LIBRARY_CHANGED) or 0,
            dps=revisions.Get(revisions.DPS_CHANGED) or 0,
        }
    end

    function M.ProjectionContext()
        local ownedBySpell = {}
        if Adapter and type(Adapter.Owned) == "function" then
            local ok, owned = pcall(Adapter.Owned)
            if ok and type(owned) == "table"
                and type(owned.bySpell) == "table" then
                ownedBySpell = owned.bySpell
            end
        end
        local detailsAvailable = false
        local dps = Nexus and Nexus.DpsCapture
        if dps and type(dps.IsDetailsAvailable) == "function" then
            local ok, available = pcall(dps.IsDetailsAvailable)
            if ok then detailsAvailable = available and true or false end
        end
        local currentClass = ""
        if type(UnitClass) == "function" then
            local ok, _, token = pcall(UnitClass, "player")
            currentClass = ok and (NormalizeClass(token) or "") or ""
        end
        return {
            ownerKey=CurrentOwnerKey() or "",
            player=Identity.PlayerKey(
                (UnitName and UnitName("player")) or "") or "",
            currentClass=currentClass,
            isAdmin=IsAdmin() and true or false,
            ownedBySpell=ownedBySpell,
            detailsAvailable=detailsAvailable,
        }
    end

    function M.DpsBoard(category)
        local dps = Nexus and Nexus.DpsCapture
        return dps and type(dps.GetDpsBoard) == "function"
            and dps.GetDpsBoard(category) or {}
    end

    function M.DpsRecord(build, category)
        local dps = Nexus and Nexus.DpsCapture
        if type(build) ~= "table" or not (dps
            and type(dps.GetRecordForIdentity) == "function") then return nil end
        local savedKind = Identity.SavedMirrorKind(build)
        local related, valid = RelatedBuild(build)
        if savedKind ~= "ordinary" and not valid then return nil end
        return dps.GetRecordForIdentity(related.id, related.fingerprint,
            related.fingerprintHash, category)
    end

    function M.Leaderboard(buildId, category)
        local dps = Nexus and Nexus.DpsCapture
        return dps and type(dps.GetLeaderboard) == "function"
            and dps.GetLeaderboard(buildId, category) or {}
    end

    function M.PersonalBest(buildId, category)
        local dps = Nexus and Nexus.DpsCapture
        return dps and type(dps.GetPersonalBest) == "function"
            and dps.GetPersonalBest(buildId, category) or nil
    end

    function M.LockedEchoesForBuild(build)
        if type(build) ~= "table" then
            return nil, "build evidence is unavailable"
        end
        local resolver = Nexus and Nexus.CandidateEvidence
        if not (resolver and type(resolver.ResolveLocked) == "function") then
            return nil, "locked Echo resolver is unavailable"
        end

        -- These are the only two represented-data reads in this path.  The
        -- DPS owner resolves both through its revision-scoped identity index;
        -- Community must never recover locked evidence by walking a board.
        local okDummy, dummy = pcall(M.DpsRecord, build, "dummy")
        local okLk, lk = pcall(M.DpsRecord, build, "lk")
        if not okDummy or not okLk then
            return nil, "locked Echo record lookup failed", {
                status="unavailable",reason="locked Echo record lookup failed",
                source="none",fingerprint="0",lockedEchoes={},
            }
        end
        local ok, result = pcall(resolver.ResolveLocked, {
            build=build,dummyRecord=dummy,lkRecord=lk,
        })
        if not ok or type(result) ~= "table" then
            return nil, "locked Echo resolution failed"
        end
        local reason = tostring(result.reason or ""):sub(1, 96)
        if result.status == "ok" and type(result.lockedEchoes) == "table" then
            return result.lockedEchoes, nil, result
        end
        return nil, reason ~= "" and reason or nil, result
    end

    function M.Filters()
        local settings = FilterSettings()
        local currentClass = CurrentClass()
        -- Add new filters in place so legacy and future preference fields keep
        -- their table identity. Current-class and qualification restrictions
        -- remain on by default; only an explicit false opts out.
        if settings.currentClassOnly == nil then
            settings.currentClassOnly = true
        end
        if settings.qualifiedOnly == nil then settings.qualifiedOnly = true end
        local page = tonumber(settings.page)
        settings.page = page and page >= 1 and math.floor(page) or 1
        settings.pageSize = 20
        -- Keep the legacy class field current for older readers. The additive
        -- boolean decides whether the projection uses it.
        if currentClass and settings.classFilter ~= currentClass then
            settings.classFilter = currentClass
        end
        local out = {}
        for key, value in pairs(settings) do out[key] = value end
        out.currentClassOnly = settings.currentClassOnly ~= false
        out.qualifiedOnly = settings.qualifiedOnly ~= false
        if out.currentClassOnly then out.classFilter = currentClass
        else out.classFilter = "ALL" end
        return out
    end

    function M.SetFilter(key, value)
        if key == "classFilter" then
            local currentClass = CurrentClass()
            if not currentClass or NormalizeClass(value) ~= currentClass then
                return false
            end
            local settings = FilterSettings()
            settings.classFilter = currentClass
            settings.page = 1
            return true
        end
        if key == "currentClassOnly" or key == "qualifiedOnly" then
            if type(value) ~= "boolean" then return false end
            local settings = FilterSettings()
            settings[key] = value
            settings.page = 1
            return true
        end
        if key == "page" then
            value = tonumber(value)
            if not value or value < 1 or value ~= math.floor(value) then
                return false
            end
            FilterSettings().page = value
            return true
        end
        local valid = (key == "search" and type(value) == "string")
            or (key == "scope" and (value == "all" or value == "mine"))
            or (key == "sortMode"
                and (value == "dps" or value == "recent"
                    or value == "title"))
        if not valid then return false end
        local settings = FilterSettings()
        settings[key] = value
        settings.page = 1
        return true
    end

    function M.SelectedId()
        return selectedId
    end

    function M.Select(id)
        selectedId = id
        return selectedId
    end

    function M.ClearSelection(id)
        if id == nil or selectedId == id then selectedId = nil end
    end

    function M.SelectedBuild()
        local build = selectedId and LoadBuild(selectedId) or nil
        if M.ProjectBuild then return M.ProjectBuild(build) end
        return build
    end

    function M.SelectedBuildKey()
        local catalog = Catalog()
        if not selectedId then return nil, 0, 0 end
        if catalog and type(catalog.RecordRevision) == "function" then
            local epoch, revision = catalog.RecordRevision(selectedId)
            return selectedId, epoch, revision
        end
        return selectedId, BuildRevision(), 0
    end

    function M.RequestLoadout(id)
        local sync = Nexus and Nexus.Sync
        if id ~= nil and sync and type(sync.RequestLoadout) == "function" then
            sync.RequestLoadout(id)
            return true
        end
        return false
    end

    function M.RequestSync()
        local sync = Nexus and Nexus.Sync
        if sync and type(sync.RequestSync) == "function" then
            local ok, err = sync.RequestSync()
            return ok, err, true
        end
        return nil, nil, false
    end

    function M.PostSourceCandidates()
        local out, seen = {}, {}
        local slots = Adapter and Adapter.Slots and Adapter.Slots()
        if slots and type(slots.bySlot) == "table" then
            local keys = {}
            for slot in pairs(slots.bySlot) do
                keys[#keys + 1] = tonumber(slot) or slot
            end
            table.sort(keys, function(a, b)
                return tonumber(a) < tonumber(b)
            end)
            for _, slot in ipairs(keys) do
                local live = slots.bySlot[slot]
                if live and type(live.echoes) == "table"
                    and #live.echoes > 0 then
                    local kind = (tonumber(slot) or 0) >= 100
                        and "Wishlist" or "Saved Build"
                    out[#out + 1] = {
                        slot=slot,
                        name=live.name or (kind .. " " .. tostring(slot)),
                        count=#live.echoes,echoes=live.echoes,
                        active=slots.activeSlot == slot,sourceKind=kind,
                    }
                    seen[tostring(slot)] = true
                end
            end
        end
        local candidates = Adapter and Adapter.GetWishlistCandidates
            and Adapter.GetWishlistCandidates()
        if type(candidates) == "table" then
            for _, candidate in ipairs(candidates) do
                if not seen[tostring(candidate.slot)]
                    and type(candidate.echoes) == "table"
                    and #candidate.echoes > 0 then
                    out[#out + 1] = {
                        slot=candidate.slot,name=candidate.name,
                        count=candidate.count,echoes=candidate.echoes,
                        active=candidate.active,sourceKind="Wishlist",
                    }
                end
            end
        end
        return out
    end

    function M.EchoDisplayName(spellId)
        local catalog = Adapter and Adapter.Catalog and Adapter.Catalog()
        local row = catalog and catalog.rows
            and catalog.rows[tonumber(spellId)]
        if row and row.name and row.name ~= "" then return row.name end
        local name = GetSpellInfo and GetSpellInfo(spellId)
        return name or ("Echo " .. tostring(spellId))
    end

    function M.BeginPostDraft(wishlist, class)
        postDraft = {wishlist=wishlist,class=class}
    end

    function M.SetPostWishlist(wishlist)
        postDraft.wishlist = wishlist
    end

    function M.SetPostClass(class)
        postDraft.class = class
    end

    function M.PostDraft()
        return postDraft.wishlist, postDraft.class
    end

    function M.BeginEditDraft(id, title, description, link)
        editDraft = {id=id,title=title,description=description,link=link}
    end

    function M.UpdateEditDraft(title, description, link)
        if not editDraft then return false end
        editDraft.title, editDraft.description, editDraft.link =
            title, description, link
        return true
    end

    function M.EditDraft()
        if not editDraft then return nil end
        return {
            id=editDraft.id,title=editDraft.title,
            description=editDraft.description,link=editDraft.link,
        }
    end

    function M.ClearEditDraft()
        editDraft = nil
    end

    function M.RemoveLegacyBuilds()
        local db = Store()
        for id, build in pairs(db) do
            if build and tostring(build.author or ""):lower() == "wr team" then
                RemoveOverlay(id)
                if selectedId == id then selectedId = nil end
            end
        end
        return db
    end


    local function NextStamp(previous)
        local now = (time and time()) or 0
        local prev = tonumber(previous) or 0
        return now > prev and now or prev + 1
    end

    IsOwnBuild = function(build)
        return Identity.LocalOwnsBuild(build, CurrentOwnerKey())
    end

    local function HasVerifiedRelatedOwner(candidate, ownerKey)
        ownerKey = Identity.CanonicalOwnerKey(ownerKey)
        return ownerKey ~= nil and type(candidate) == "table"
            and Identity.SavedMirrorKind(candidate) == "ordinary"
            and Identity.VerifiedOwnerKey(candidate) == ownerKey
    end

    local NewRelatedScorer

    local function BetterRelatedCandidate(candidate, score, best, bestScore,
        keepBestOnTie)
        if not score then return false end
        if score ~= bestScore then return score > bestScore end
        if keepBestOnTie then return false end
        return tostring(candidate and candidate.id or "")
            < tostring(best and best.id or "")
    end

    PublishedBuild = function(source, loadCandidate)
        if Identity.SavedMirrorKind(source) ~= "saved" then
            return nil
        end
        loadCandidate = type(loadCandidate) == "function"
            and loadCandidate or LoadBuild
        local ownerKey = Identity.VerifiedOwnerKey(source)
        if not ownerKey then return nil end
        local seen = {}
        for _, field in ipairs({"publishedBuildId", "recordBuildId"}) do
            local candidateId = source[field]
            if candidateId ~= nil and not seen[candidateId] then
                seen[candidateId] = true
                local candidate = loadCandidate(candidateId)
                if HasVerifiedRelatedOwner(candidate, ownerKey)
                    and candidate.sourceSavedBuildId == source.id then
                    return candidate
                end
            end
        end
        return nil
    end

    local function PreferredRelatedCandidates(source, loadCandidate)
        loadCandidate = type(loadCandidate) == "function"
            and loadCandidate or LoadBuild
        local preferred = {}
        local published = PublishedBuild(source, loadCandidate)
        if published then preferred[#preferred + 1] = published end
        local record = source and source.recordBuildId
            and loadCandidate(source.recordBuildId) or nil
        if record and (not published or record.id ~= published.id) then
            preferred[#preferred + 1] = record
        end
        return preferred
    end

    local function BestPreferredRelated(source, score, loadCandidate)
        local best, bestScore = nil, -1
        for _, candidate in ipairs(
            PreferredRelatedCandidates(source, loadCandidate)) do
            local candidateScore = score(candidate)
            if BetterRelatedCandidate(candidate, candidateScore,
                best, bestScore, true) then
                best, bestScore = candidate, candidateScore
            end
        end
        return best, bestScore
    end

    RelatedBuild = function(build)
        local savedKind = Identity.SavedMirrorKind(build)
        if savedKind == "ordinary" then return build, true end
        if savedKind ~= "saved" then return build, false end
        local ownerKey = Identity.VerifiedOwnerKey(build)
        if not ownerKey then return build, false end
        local score = NewRelatedScorer(
            build.serverTitle or build.title, build.echoes, ownerKey)
        local best = BestPreferredRelated(build, score)
        return best or build, best ~= nil
    end

    function M.IsOwnBuild(idOrBuild)
        local build = type(idOrBuild) == "table" and idOrBuild
            or LoadBuild(idOrBuild)
        return IsOwnBuild(build)
    end

    local function NormalizeTitle(text)
        return tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function EchoPresence(evidence, fingerprintComplete)
        local out = {}
        if type(evidence) == "table" then
            for _, e in ipairs(evidence) do
                local id = tonumber(e.spellId or e.id)
                if id then
                    out[id] = (out[id] or 0)
                        + (tonumber(e.stacks or e.count) or 1)
                end
            end
            return out
        end
        if type(evidence) ~= "string" or fingerprintComplete ~= true
            or evidence == "" or evidence == "0" then return nil end
        local parts = {}
        for part in evidence:gmatch("[^,]+") do
            local rawId, rawCount = part:match("^(%d+)x(%d+)$")
            local id, count = tonumber(rawId), tonumber(rawCount)
            if not id or id <= 0 or not count or count <= 0 then return nil end
            parts[#parts + 1] = part
            out[id] = (out[id] or 0) + count
        end
        if #parts == 0 or table.concat(parts, ",") ~= evidence then return nil end
        return out
    end

    NewRelatedScorer = function(serverTitle, evidence, ownerKey,
        fingerprintComplete)
        local D = Nexus.DpsCapture
        local wanted = EchoPresence(evidence, fingerprintComplete)
        local exactKey = type(evidence) == "table" and D and D.GetEchoKey
            and D.GetEchoKey(evidence) or wanted and evidence or nil
        local titleKey = NormalizeTitle(serverTitle)
        ownerKey = Identity.CanonicalOwnerKey(ownerKey)
        local wantedTotal = 0
        for _, count in pairs(wanted or {}) do wantedTotal = wantedTotal + count end

        local function CandidateScore(candidate)
            if not wanted or not exactKey
                or not HasVerifiedRelatedOwner(candidate, ownerKey) then
                return nil
            end

            local candidateEvidence = type(candidate.echoes) == "table"
                and candidate.echoes or candidate.fingerprint
            local have = EchoPresence(candidateEvidence,
                candidate.ordinaryComplete == true)
            if not have then return nil end
            local candidateKey = type(candidateEvidence) == "table"
                and D and D.GetEchoKey and D.GetEchoKey(candidateEvidence)
                or candidate.fingerprint
            if exactKey and candidateKey == exactKey then return 100000 end

            local overlap = 0
            for id, count in pairs(wanted) do
                overlap = overlap + math.min(count, have[id] or 0)
            end

            -- Server Saved Builds commonly expose only the currently locked Echoes,
            -- while the published leaderboard build contains the complete 79-Echo
            -- loadout. Treat the locked set as a subset match, but only after exact
            -- verified owner authority and strongly prefer the same server title.
            local sameTitle = titleKey ~= "" and NormalizeTitle(
                candidate.title or candidate.serverTitle) == titleKey
            local required = math.min(8,
                math.max(1, math.floor(wantedTotal / 2)))
            if overlap < required then return nil end
            if sameTitle then return 10000 + overlap end
            if overlap == wantedTotal and wantedTotal >= 6 then
                return 1000 + overlap
            end
            return nil
        end
        return CandidateScore, exactKey
    end

    -- A Saved Build mirror and its leaderboard/community record can use different
    -- ids even though they describe the same loadout. Resolve the published/record
    -- copy once so class and DPS stay attached to the local mirror.
    local function BeginRelatedBuild(serverTitle, echoes, old, author, ownerKey)
        local catalog = Catalog()
        local CandidateScore, exactKey = NewRelatedScorer(
            serverTitle, echoes, ownerKey)

        -- Never trust a persisted recordBuildId blindly. Saved slot numbers and
        -- mirrored records survive reloads and can otherwise keep a stale record
        -- from another class attached forever.
        local best, bestScore = BestPreferredRelated(old, CandidateScore)
        local cursor = catalog and catalog.BeginRelatedCursor
            and catalog.BeginRelatedCursor(author, serverTitle, exactKey) or nil
        return {
            cursor=cursor,best=best,bestScore=bestScore,
            bestPreferred=best ~= nil,
            score=CandidateScore,author=author,title=serverTitle,
            exactKey=exactKey,
        }
    end

    local function PumpRelatedBuild(job)
        if job.cached then return job.best, true end
        if not job.cursor then return job.best, true end
        local catalog = Catalog()
        local candidate, done, err = catalog.RelatedCursorNext(job.cursor)
        if err then return nil, false, err end
        if candidate then
            local score = job.score(candidate)
            if BetterRelatedCandidate(candidate, score,
                job.best, job.bestScore, job.bestPreferred) then
                job.best, job.bestScore = candidate, score
                job.bestPreferred = false
            end
        end
        return job.best, done == true, nil, candidate ~= nil
    end

    local function BeginSavedImport(force, restarting)
        if savedImportJob then return true end
        local now = GetTime and GetTime() or 0
        if not force and now > 0 and (now - lastSavedLoadoutImport) < 1.0 then
            return false
        end
        lastSavedLoadoutImport = now
        local slots = Adapter and Adapter.Slots and Adapter.Slots()
        if not (slots and type(slots.bySlot) == "table") then return false end
        local keys = {}
        for rawSlot in pairs(slots.bySlot) do
            local slot = tonumber(rawSlot)
            if slot and slot >= 1 and slot < 100 then keys[#keys + 1] = slot end
        end
        table.sort(keys)
        local me = tostring((UnitName and UnitName("player")) or "You")
        local ownerKey = CurrentVerifiedOwnerKey()
        local buildRevision = BuildRevision()
        local cacheValid = savedRelatedCacheRevision == buildRevision
        if not cacheValid then savedRelatedCache = {} end
        savedImportJob = {
            slots=slots,keys=keys,index=1,me=me,ownerKey=ownerKey,
            meKey=me:lower():gsub("[^%w]", "_"),seen={},
            changed=0,phase="slots",cacheValid=cacheValid,cacheUpdates={},
            buildRevision=buildRevision,slotGeneration=SlotGeneration(),
        }
        savedImportStats.jobStarts = savedImportStats.jobStarts + 1
        if not restarting then
            savedImportStats.jobs = savedImportStats.jobs + 1
        end
        return true
    end

    local function RestartSavedImport(job, reason)
        local carriedChanges = job and job.changed or 0
        savedImportJob = nil
        if not BeginSavedImport(true, true) then
            savedImportJob = job
            return job, false
        end
        savedImportJob.changed = carriedChanges
        savedImportStats.restarts = savedImportStats.restarts + 1
        if reason == "build" then
            savedImportStats.sourceRevisionRestarts =
                savedImportStats.sourceRevisionRestarts + 1
            savedImportStats.buildRevisionRestarts =
                savedImportStats.buildRevisionRestarts + 1
        elseif reason == "slots" then
            savedImportStats.sourceRevisionRestarts =
                savedImportStats.sourceRevisionRestarts + 1
            savedImportStats.slotGenerationRestarts =
                savedImportStats.slotGenerationRestarts + 1
        end
        return savedImportJob, true
    end

    local function SavedImportSourceChanged(job)
        if BuildRevision() ~= job.buildRevision then return "build" end
        local generation = SlotGeneration()
        if job.slotGeneration ~= nil and generation ~= nil
            and generation ~= job.slotGeneration then return "slots" end
        return nil
    end

    local function SavedMirrorReusableBy(candidate, ownerKey)
        return Identity.CanAdoptSavedMirror(candidate, ownerKey)
    end

    local function SavedMirrorId(job, slot)
        local base = string.format("saved-%s-%d", job.meKey, slot)
        local token = job.ownerKey
            and StableIdHash(job.ownerKey):sub(1, 8) or nil
        return FindStableCollisionTarget(base, token, function(candidate)
            return Identity.SavedMirrorKind(candidate) == "saved"
                and tonumber(candidate.serverSlot) == slot
                and SavedMirrorReusableBy(candidate, job.ownerKey)
        end)
    end

    local function PrepareSavedSlot(job, slot)
        savedImportStats.slotPreparations =
            savedImportStats.slotPreparations + 1
        local live = job.slots.bySlot[slot]
        if not (live and type(live.echoes) == "table" and #live.echoes > 0) then
            savedImportStats.emptySlots = savedImportStats.emptySlots + 1
            return nil
        end
        local id = SavedMirrorId(job, slot)
        if not id then return nil end
        local echoes, total = {}, 0
        for _, e in ipairs(live.echoes) do
            local stacks = tonumber(e.stacks or e.count) or 1
            -- Keep the server's per-Echo locked flag in the local mirror.
            echoes[#echoes + 1] = {
                spellId=e.spellId or e.id,quality=e.quality,stacks=stacks,
                locked=e.locked and true or false,
            }
            total = total + stacks
        end
        local serverTitle = (live.name and live.name ~= "")
            and live.name or ("Saved Build " .. slot)
        local old = LoadBuild(id)
        local title = (old and old.userTitle and old.userTitle ~= "")
            and old.userTitle or serverTitle
        savedImportStats.wishlistDiscoveryReads =
            savedImportStats.wishlistDiscoveryReads + 1
        local linked = Adapter.GetLoadoutWishlist
            and Adapter.GetLoadoutWishlist(slot) or nil
        if linked then
            savedImportStats.wishlistDiscoveries =
                savedImportStats.wishlistDiscoveries + 1
        end
        local destinationName = linked and linked.name or nil
        local progress, destinationTotal = EchoProgress(
            echoes, linked and linked.echoes or nil)
        local D = Nexus and Nexus.DpsCapture
        local exactKey = D and D.GetEchoKey and D.GetEchoKey(echoes) or ""
        local inputKey = table.concat({
            tostring(job.ownerKey or ""),serverTitle,tostring(exactKey),
        }, "\0")
        local cached = job.cacheValid and savedRelatedCache[id] or nil
        local cacheMatch = cached and cached.inputKey == inputKey
        local cachedBuild = cacheMatch
            and cached.relatedId and LoadBuild(cached.relatedId) or nil
        if cacheMatch and cached.relatedId then
            local score = NewRelatedScorer(
                serverTitle, echoes, job.ownerKey)
            if not score(cachedBuild) then cacheMatch = false end
        end
        return {
            slot=slot,id=id,live=live,echoes=echoes,total=total,
            serverTitle=serverTitle,old=old,title=title,linked=linked,
            destinationName=destinationName,progress=progress,
            destinationTotal=destinationTotal,
            inputKey=inputKey,
            related=cacheMatch and {
                cached=true,best=cachedBuild,
            } or BeginRelatedBuild(
                serverTitle, echoes, old, job.me, job.ownerKey),
        }
    end

    local function FinalizeSavedSlot(job, current, related)
        savedImportStats.finalizations = savedImportStats.finalizations + 1
        local slot, live, old = current.slot, current.live, current.old
        local echoes, total = current.echoes, current.total
        -- A present server slot is not automatically a valid Saved Build.
        -- Establish complete ordinary evidence before protecting the prior
        -- mirror from cleanup; locked/malformed replacements must retire it.
        if not RefreshBuildIdentity({echoes=echoes}) then return end
        job.seen[current.id] = true
                -- These slots belong to the character currently being viewed. The
                -- current/server class is therefore authoritative for an unpublished
                -- Saved Build. Only a verified published record may override it.
                -- Echo-only inference is a last-resort fallback because partial locked
                -- snapshots can contain mostly shared Echoes and resemble another class.
        local currentClass = (select(2, UnitClass and UnitClass("player"))) or nil
        local class = (related and related.class) or live.class
            or currentClass or InferBuildClass(echoes) or "UNKNOWN"
                -- Do not preserve a stale record link after validation fails. A bad
                -- link was also allowing an unrelated class/record to remain attached.
        local recordBuildId = related and related.id or nil
        local published = old and PublishedBuild(old) or nil
        -- A stale publishedBuildId may be repaired from the already admitted
        -- relation, but only when that verified publication is explicitly bound
        -- to this Saved Build. The relation scorer has already established both
        -- owner authority and content compatibility.
        if not published and related
            and related.sourceSavedBuildId == current.id then
            published = related
        end
        job.cacheUpdates[current.id] = {
            inputKey=current.inputKey,relatedId=recordBuildId,
        }
        local signatureParts = {
            current.serverTitle,tostring(class),tostring(recordBuildId or ""),
            tostring(published and published.id or ""),
            tostring(total),tostring(current.destinationName or ""),
            tostring(current.progress),tostring(current.destinationTotal),
            tostring(job.slots.activeSlot == slot),
        }
        for _, e in ipairs(echoes) do
            signatureParts[#signatureParts + 1] = table.concat({
                tostring(e.spellId or 0),tostring(e.quality or ""),
                tostring(e.stacks or 1),
            }, ":")
        end
        local signature = table.concat(signatureParts, "|")
        local desiredPublishedId = published and published.id or nil
        if not old or old._savedSignature ~= signature
            or old.recordBuildId ~= recordBuildId
            or old.publishedBuildId ~= desiredPublishedId then
            local stamp = NextStamp(old and old.lastModified or 0)
            local localOwner = CurrentVerifiedOwnerKey()
            local record = {
                        id=current.id, title=current.title,
                        serverTitle=current.serverTitle,
                        userTitle=old and old.userTitle or nil,
                        description=(old and old.userDescription) or (destinationName
                            and string.format("Destination wishlist: %s - in progress (%d/%d).", destinationName, progress, destinationTotal)
                            or "No destination wishlist associated yet."),
                        userDescription=old and old.userDescription or nil,
                        publishedBuildId=desiredPublishedId,
                        lastPublishedAt=published and (
                            (old and old.lastPublishedAt)
                            or published.lastModified or published.postedAt) or nil,
                        author=job.me, ownerKey=localOwner,
                        ownerVerified=localOwner and true or false,
                        class=class, echoes=echoes,
                        postedAt=(old and old.postedAt) or stamp, lastModified=stamp,
                        isMine=localOwner ~= nil, importedSavedBuild=true, serverSlot=slot,
                        recordBuildId=recordBuildId,
                        destinationWishlistName=current.destinationName,
                        destinationWishlistSlot=current.linked and current.linked.slot or nil,
                        destinationProgress=current.progress,
                        destinationTotal=current.destinationTotal,
                        activeServerBuild=(job.slots.activeSlot == slot),
                        _savedSignature=signature,
                    }
            if RefreshBuildIdentity(record) then
                local catalogBefore = CatalogStats()
                savedImportStats.catalogPuts = savedImportStats.catalogPuts + 1
                local saved = SaveBuild(record)
                RecordCatalogDelta(catalogBefore)
                if saved then
                    job.changed = job.changed + 1
                    job.buildRevision = BuildRevision()
                    savedImportStats.writes = savedImportStats.writes + 1
                end
            end
        end
    end

    local function PumpSavedImport(limit)
        local job = savedImportJob
        if not job then return 0, false end
        local receiving = Nexus and Nexus.Sync and Nexus.Sync.IsReceiving
            and Nexus.Sync.IsReceiving() or false
        if receiving then
            savedImportStats.syncDeferrals = savedImportStats.syncDeferrals + 1
            return 0, true
        end
        local sourceChange = SavedImportSourceChanged(job)
        if sourceChange then
            local restarted
            job, restarted = RestartSavedImport(job, sourceChange)
            if not restarted then return 0, true end
        end
        limit = math.max(1, math.min(25, tonumber(limit) or 25))
        local changedBefore, candidates = job.changed, 0
        savedImportStats.pumps = savedImportStats.pumps + 1
        local work = 0
        while work < limit and savedImportJob == job do
            if job.phase == "slots" then
                if not job.current then
                    local slot = job.keys[job.index]
                    if slot == nil then
                        local catalog = Catalog()
                        job.cleanup = catalog and catalog.SavedMirrorIds
                            and catalog.SavedMirrorIds(job.me) or {}
                        savedImportStats.cleanupEnumerations =
                            savedImportStats.cleanupEnumerations + 1
                        savedImportStats.cleanupCandidates =
                            savedImportStats.cleanupCandidates + #job.cleanup
                        job.cleanupIndex, job.phase = 1, "cleanup"
                    else
                        job.current = PrepareSavedSlot(job, slot)
                        job.index = job.index + 1
                        work = work + 1
                    end
                else
                    savedImportStats.candidateAdvances =
                        savedImportStats.candidateAdvances + 1
                    local related, done, err, examined = Measure(
                        "community.related-lookup", PumpRelatedBuild,
                        job.current.related)
                    work = work + 1
                    if examined then candidates = candidates + 1 end
                    if err then
                        job.current.related = BeginRelatedBuild(
                            job.current.serverTitle, job.current.echoes,
                            job.current.old, job.me, job.ownerKey)
                        savedImportStats.restarts = savedImportStats.restarts + 1
                        savedImportStats.cursorRestarts =
                            savedImportStats.cursorRestarts + 1
                    elseif done then
                        FinalizeSavedSlot(job, job.current, related)
                        job.current = nil
                    end
                end
            else
                local id = job.cleanup[job.cleanupIndex]
                if id == nil then
                    savedImportStats.completions = savedImportStats.completions + 1
                    savedRelatedCache = job.cacheUpdates
                    savedRelatedCacheRevision = BuildRevision()
                    lastSavedLoadoutImport = GetTime and GetTime()
                        or lastSavedLoadoutImport
                    savedImportJob = nil
                else
                    job.cleanupIndex = job.cleanupIndex + 1
                    savedImportStats.cleanupExamined =
                        savedImportStats.cleanupExamined + 1
                    local build = LoadBuild(id)
                    if Identity.SavedMirrorKind(build) == "saved"
                        and Identity.LocalOwnsSavedMirror(build, job.ownerKey)
                        and not job.seen[id] then
                        if RemoveOverlay(id) then
                            if selectedId == id then selectedId = nil end
                            job.changed = job.changed + 1
                            job.buildRevision = BuildRevision()
                            savedImportStats.writes = savedImportStats.writes + 1
                            savedImportStats.cleanupRemovals =
                                savedImportStats.cleanupRemovals + 1
                        end
                    end
                    work = work + 1
                end
            end
        end
        savedImportStats.candidates = savedImportStats.candidates + candidates
        savedImportStats.maxCandidatesPerPump = math.max(
            savedImportStats.maxCandidatesPerPump, candidates)
        savedImportStats.workUnits = savedImportStats.workUnits + work
        savedImportStats.maxWorkPerPump = math.max(
            savedImportStats.maxWorkPerPump, work)
        return job.changed - changedBefore, savedImportJob ~= nil
    end

    -- Mirror the current character's server Saved Builds into the personal
    -- library. One call performs at most 25 slot/candidate/cleanup work units;
    -- the renderer resumes a larger cold reconciliation from OnUpdate.
    function M.BeginSavedLoadoutImport(force)
        return BeginSavedImport(force)
    end

    function M.PumpSavedLoadoutImport(limit)
        return Measure("community.saved-import", PumpSavedImport, limit)
    end

    function M.HasPendingSavedLoadoutImport()
        return savedImportJob ~= nil
    end

    function M.SavedImportStats()
        local out = {}
        for key, value in pairs(savedImportStats) do out[key] = value end
        out.pending = savedImportJob ~= nil
        out.pendingPhase = savedImportJob and savedImportJob.phase or nil
        out.pendingSlot = savedImportJob and savedImportJob.current
            and savedImportJob.current.slot or nil
        return out
    end

    -- Narrow, read-only diagnostic projection. Search text, identities,
    -- SavedVariables tables, and Echo payloads never leave this owner.
    function M.ViewDiagnosticState()
        local settings
        if type(options.filterSettings) == "function" then
            local ok, value = pcall(options.filterSettings)
            if ok and type(value) == "table" then settings = value end
        end
        if not settings then
            settings = type(NexusDB) == "table"
                and type(NexusDB.buildFilters) == "table"
                and NexusDB.buildFilters or fallbackFilters
        end
        local requestedPage = tonumber(settings.page)
        requestedPage = requestedPage and requestedPage == requestedPage
            and requestedPage < math.huge and requestedPage > -math.huge
            and math.floor(requestedPage) or 1
        requestedPage = math.max(1, math.min(2147483647, requestedPage))
        local currentClassOnly = settings.currentClassOnly ~= false
        local filterClass = currentClassOnly and CurrentClass() or "ALL"
        if not filterClass then filterClass = "UNAVAILABLE" end
        local sortMode = settings.sortMode
        if sortMode ~= "recent" and sortMode ~= "title" then
            sortMode = "dps"
        end
        local phase = savedImportJob and savedImportJob.phase or "idle"
        if phase ~= "slots" and phase ~= "cleanup" and phase ~= "idle" then
            phase = "unknown"
        end
        local catalogStatus = {}
        local catalog = Catalog()
        if catalog and type(catalog.Status) == "function" then
            local ok, value = pcall(catalog.Status)
            if ok and type(value) == "table" then catalogStatus = value end
        end
        local catalogCount = math.floor(tonumber(
            catalogStatus.availableCount) or M.BuildCount() or 0)
        catalogCount = math.max(0, math.min(2147483647, catalogCount))
        local bundledCount = math.floor(tonumber(
            catalogStatus.bundledCount) or catalogCount)
        local overlayCount = math.floor(tonumber(
            catalogStatus.overlayCount) or 0)
        local availableCount = math.floor(tonumber(
            catalogStatus.availableCount) or catalogCount)
        bundledCount = math.max(0, math.min(2147483647, bundledCount))
        overlayCount = math.max(0, math.min(2147483647, overlayCount))
        availableCount = math.max(0, math.min(2147483647, availableCount))
        return {
            catalogCount=catalogCount,
            bundledCount=bundledCount,overlayCount=overlayCount,
            availableCount=availableCount,
            catalogVersion=tostring(catalogStatus.catalogVersion
                or "unversioned"),
            requestedPage=requestedPage,
            filterScope=settings.scope == "mine" and "mine" or "all",
            filterClass=filterClass,
            filterCurrentClassOnly=currentClassOnly,
            filterQualifiedOnly=settings.qualifiedOnly ~= false,
            filterSearchActive=type(settings.search) == "string"
                and settings.search ~= "" or false,
            filterSort=sortMode,
            savedImportPending=savedImportJob ~= nil,
            savedImportPhase=phase,
        }
    end

    function M.ImportCurrentSavedLoadouts(force)
        if not BeginSavedImport(force) then return 0, false end
        return M.PumpSavedLoadoutImport(25)
    end

    local function BroadcastIfPossible(record, retryOnFull)
        local sync = Nexus.Sync
        local callback = sync and (sync.BroadcastBuildSummary
            or sync.BroadcastBuild)
        if type(callback) ~= "function" then
            PeerRecord("share_queue", {id=record and record.id,
                outcome="unavailable",reason="sync unavailable"})
            return false, "sync unavailable", nil
        end
        local called, admitted, why, status = pcall(callback, record,
            retryOnFull and {retryOnFull=true} or nil)
        local ok = called and admitted ~= false
        PeerRecord("share_queue", {id=record and record.id,
            outcome=ok and "admitted" or "rejected",
            reason=called and why or admitted})
        return ok, called and why or admitted,
            called and type(status) == "table" and status or nil
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
            if type(e) == "table" and (e.locked
                or (e.sourceRole ~= nil
                    and tostring(e.sourceRole) ~= "ordinary")) then
                return false, "ordinary Echo list contains locked-role data"
            end
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
        local evidence = Nexus and Nexus.LoadoutEvidence
        local verdict = evidence
            and type(evidence.OrdinaryCompleteness) == "function"
            and evidence.OrdinaryCompleteness({
                echoes=build.echoes,fingerprint=fingerprint,
            }) or nil
        if type(verdict) ~= "table" or verdict.complete ~= true then
            return false, verdict and verdict.reason
                or "ordinary Echo evidence unavailable"
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
        for _, echo in ipairs(type(echoes) == "table" and echoes or {}) do
            if type(echo) == "table" and (echo.locked
                or (echo.sourceRole ~= nil
                    and tostring(echo.sourceRole) ~= "ordinary")) then
                return nil
            end
        end
        local key = D.GetEchoKey(echoes)
        if not key then return nil end
        local explicitClass = NormalizeClass(record and (record.class or record.k))
        local player = tostring(record and record.player
            or (UnitName and UnitName("player")) or "Unknown")
        local recordOwner = VerifiedDpsOwnerKey(record)
        local recordClaim = OwnerEvidenceKey(record)
        local explicitId = record and (record.buildId or record.b)
        if type(explicitId) ~= "string" or explicitId == "" then explicitId = nil end
        local catalog = Catalog()
        if catalog and type(catalog.FindExactFingerprint) == "function" then
            local recoveredId, recovered = catalog.FindExactFingerprint(key)
            local evidence = Nexus and Nexus.LoadoutEvidence
            local verdict = evidence and recovered
                and type(evidence.OrdinaryCompleteness) == "function"
                and evidence.OrdinaryCompleteness(recovered) or nil
            if recoveredId
                and Identity.SavedMirrorKind(recovered) == "ordinary"
                and type(verdict) == "table"
                and verdict.complete == true then
                local recoveredOwner = Identity.VerifiedOwnerKey(recovered)
                local recoveredClaim = OwnerEvidenceKey(recovered)
                local sameAutoOwner
                if recovered.autoDps == true then
                    if recordOwner then
                        sameAutoOwner = recoveredOwner == recordOwner
                            or (not recoveredOwner
                                and (recoveredClaim == recordOwner
                                    or CanPromoteOwnerEvidence(
                                        recovered, recordOwner)))
                    elseif recordClaim then
                        sameAutoOwner = recoveredOwner == recordClaim
                            or (not recoveredOwner
                                and recoveredClaim == recordClaim)
                    else
                        sameAutoOwner = false
                    end
                else
                    sameAutoOwner = recordOwner ~= nil
                        and recoveredOwner == recordOwner
                end
                -- A relay-created page may be reused for ambient reads, but
                -- the exact direct owner must reach the promotion boundary.
                -- Auto-DPS pages are owner-specific even when their ordinary
                -- fingerprint happens to match another player's record.
                if sameAutoOwner and not (recordOwner
                    and not recoveredOwner) then
                    return recoveredId, recovered
                end
            end
        end

        -- A protocol build ID is an identity, not a derived alias. Never attach
        -- its record to a different loadout or owner merely because IDs collide.
        local explicitExisting = explicitId and LoadBuild(explicitId) or nil
        if explicitExisting
            and Identity.SavedMirrorKind(explicitExisting) ~= "ordinary" then
            explicitId, explicitExisting = nil, nil
        end
        if explicitExisting then
            -- Only a verified canonical DPS owner may hydrate or promote an
            -- existing opaque identity.  Claims remain evidence, never power.
            if not recordOwner then return nil end
            local evidence = Nexus and Nexus.LoadoutEvidence
            local existingVerdict = evidence
                and type(evidence.OrdinaryCompleteness) == "function"
                and evidence.OrdinaryCompleteness(explicitExisting) or nil
            local existingComplete = type(existingVerdict) == "table"
                and existingVerdict.complete == true
            local existingKey = existingComplete
                and existingVerdict.fingerprint or nil
            if existingComplete and existingKey ~= key then return nil end
            local existingOwner = Identity.VerifiedOwnerKey(explicitExisting)
            local existingClaim = OwnerEvidenceKey(explicitExisting)
            local producerPromotion = record
                and record._promotedFromUnverified == true
                and explicitExisting.autoDps == true
                and existingClaim == nil
                and Identity.OwnerKeyMatchesAuthor(
                    recordOwner, explicitExisting.author)
            if existingOwner and existingOwner ~= recordOwner then return nil end
            if not existingOwner and existingClaim ~= recordOwner
                and not producerPromotion
                and not CanPromoteOwnerEvidence(
                    explicitExisting, recordOwner) then return nil end
            local promoteOwner = existingOwner == nil
            local presentationChanged = false
            if promoteOwner then
                ApplyVerifiedBuildOwner(explicitExisting, recordOwner, player)
                if explicitExisting.autoDps == true and explicitClass then
                    local verifiedTitle = (CLASS_LABEL[explicitClass]
                        or explicitClass) .. " Record Loadout"
                    if explicitExisting.class ~= explicitClass
                        or explicitExisting.title ~= verifiedTitle then
                        explicitExisting.class = explicitClass
                        explicitExisting.title = verifiedTitle
                        presentationChanged = true
                    end
                end
            end
            if not existingComplete then
                if type(explicitExisting.echoes) == "table"
                    and #explicitExisting.echoes > 0 then return nil end
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
                ApplyVerifiedBuildOwner(explicitExisting, recordOwner, player)
                explicitExisting.class = explicitClass or explicitExisting.class
                    or InferBuildClass(copied) or "UNKNOWN"
                if explicitExisting.title == "Loadout pending" then
                    explicitExisting.title = (CLASS_LABEL[explicitExisting.class]
                        or explicitExisting.class) .. " Record Loadout"
                end
                explicitExisting.description = "Automatically completed from a compatible DPS record. Exact Echo IDs and stack quantities are preserved for copying and comparison."
                explicitExisting.lastModified = NextStamp(
                    explicitExisting.lastModified or explicitExisting.postedAt or 0)
                local saved = SaveBuild(explicitExisting)
                if not saved then return nil end
                if Identity.VerifiedOwnerKey(explicitExisting) then
                    BroadcastIfPossible(explicitExisting)
                end
            elseif promoteOwner or presentationChanged then
                explicitExisting.lastModified = NextStamp(
                    explicitExisting.lastModified
                        or explicitExisting.postedAt or 0)
                local saved = SaveBuild(explicitExisting)
                if not saved then return nil end
                BroadcastIfPossible(explicitExisting)
            end
            return explicitId, explicitExisting
        end

        local ownAutoId, ownAutoBuild
        if not explicitId then
            for id, build in pairs(Store()) do
                local evidence = Nexus and Nexus.LoadoutEvidence
                local verdict = evidence
                    and type(evidence.OrdinaryCompleteness) == "function"
                    and evidence.OrdinaryCompleteness(build) or nil
                if Identity.SavedMirrorKind(build) == "ordinary"
                    and type(verdict) == "table" and verdict.complete == true
                    and verdict.fingerprint == key then
                    if not build.autoDps then
                        if recordOwner
                            and Identity.VerifiedOwnerKey(build)
                                == recordOwner then return id, build end
                    else
                        local buildOwner = Identity.VerifiedOwnerKey(build)
                        local buildClaim = OwnerEvidenceKey(build)
                        local sameOwner = recordOwner and (
                            buildOwner == recordOwner
                            or (not buildOwner and (buildClaim == recordOwner
                                or CanPromoteOwnerEvidence(
                                    build, recordOwner))))
                        local sameClaim = not recordOwner and recordClaim
                            and (buildOwner == recordClaim
                                or (not buildOwner
                                    and buildClaim == recordClaim))
                        if sameOwner or sameClaim then
                            ownAutoId, ownAutoBuild = id, build
                        end
                    end
                end
            end
        end

        local copied = {}
        for _, e in ipairs(echoes or {}) do
            local id = tonumber(e and (e.spellId or e.id))
            copied[#copied + 1] = { spellId=id, quality=e.quality, stacks=e.count or e.stacks or 1 }
        end
        -- Locked Echoes remain supplemental record evidence. They are never
        -- folded into the ordinary build pool or its fingerprint.
        local playerIsLocal = recordOwner ~= nil
            and recordOwner == CurrentVerifiedOwnerKey()
        local localClass
        if playerIsLocal and UnitClass then
            local _, token = UnitClass("player")
            localClass = NormalizeClass(token)
        end
        local class = explicitClass or InferBuildClass(copied)
            or localClass or "UNKNOWN"

        if ownAutoId then
            local changed = false
            if recordOwner and not Identity.VerifiedOwnerKey(ownAutoBuild) then
                if OwnerEvidenceKey(ownAutoBuild) ~= recordOwner
                    and not CanPromoteOwnerEvidence(
                        ownAutoBuild, recordOwner) then return nil end
                ApplyVerifiedBuildOwner(ownAutoBuild, recordOwner, player)
                changed = true
            end
            if recordOwner and explicitClass
                and ownAutoBuild.class ~= explicitClass then
                ownAutoBuild.class = explicitClass
                ownAutoBuild.title = (CLASS_LABEL[explicitClass] or explicitClass)
                    .. " Record Loadout"
                changed = true
            end
            if changed then
                ownAutoBuild.lastModified = NextStamp(
                    ownAutoBuild.lastModified or ownAutoBuild.postedAt)
                local saved = SaveBuild(ownAutoBuild)
                if not saved then return nil end
                if Identity.VerifiedOwnerKey(ownAutoBuild) then
                    BroadcastIfPossible(ownAutoBuild)
                end
            end
            return ownAutoId, ownAutoBuild
        end

        local stamp = NextStamp(0)
        local ownerKey = recordOwner
        local claimKey = not recordOwner and recordClaim or nil
        local identity = ownerKey or claimKey or Identity.PlayerKey(player)
        if not identity then return nil end
        local id = explicitId or ("dps-" .. StableIdHash(key) .. "-"
            .. StableIdHash(identity):sub(1, 8))
        -- Deterministic IDs derived from ambiguous evidence may already belong
        -- to a page that was later promoted. Never replace any represented row
        -- merely because a claimless packet recomputed the same short-name ID.
        if LoadBuild(id) then return nil end
        local build = {
            id=id, title=(CLASS_LABEL[class] or class) .. " Record Loadout",
            description="Automatically created from a compatible DPS record. Exact Echo IDs and stack quantities are preserved for copying and comparison.",
            author=player, ownerKey=ownerKey, claimedOwnerKey=claimKey,
            realm=record and (record.realm or record.r) or nil,
            class=class, echoes=copied,
            postedAt=stamp, lastModified=stamp,
            isMine=ownerKey ~= nil and ownerKey == CurrentVerifiedOwnerKey(),
            autoDps=true, fingerprint=key, loadoutAvailable=true,
            needsFullBuild=false,
            ownerVerified=ownerKey ~= nil,
            relaySender=not ownerKey and record and record.relaySender or nil,
        }
        if record and type(record.lockedEchoes) == "table" then
            build.lockedEchoes = {}
            for _, e in ipairs(record.lockedEchoes) do
                build.lockedEchoes[#build.lockedEchoes + 1] = {
                    spellId=e.spellId or e.id,quality=e.quality,
                    stacks=e.stacks or e.count or 1,locked=true,
                }
            end
        end
        if not RefreshBuildIdentity(build) then return nil end
        local saved = SaveBuild(build)
        if not saved then return nil end
        if Identity.VerifiedOwnerKey(build) then BroadcastIfPossible(build) end
        return id, build
    end

    function M.PostCurrentWishlist(title, description, selectedWishlist, selectedClass)
        if not (Adapter and Adapter.Wishlist) then return false, "adapter not ready" end
        PeerRecord("share_confirmed", {outcome="button confirmed"})

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
            PeerRecord("share_source", {outcome="rejected",
                reason="no wishlist selected"})
            return false, "no wishlist selected to post"
        end
        PeerRecord("share_source", {outcome="selected",
            echoes=#sourceEchoes,class=NormalizeClass(selectedClass)
                or NormalizeClass(wl.class) or "UNKNOWN"})
        title = (title or ""):gsub("^%s+",""):gsub("%s+$","")
        if title == "" then title = (wl.name ~= "" and wl.name) or "Untitled" end
        description = tostring(description or "")
        if #title > 80 then return false, "title is too long" end
        if #description > 2000 then return false, "description is too long" end
        if not Identity.ValidDisplayText(title, 80, false) then
            return false, "title contains unsafe text"
        end
        if not Identity.ValidDisplayText(description, 2000, true, true) then
            return false, "description contains unsafe text"
        end
        local echoes = {}
        for _, e in ipairs(sourceEchoes) do
            echoes[#echoes+1] = { spellId=e.spellId, quality=e.quality, stacks=e.stacks or 1 }
        end
        local stamp = NextStamp(0)
        local id = string.format("mine-%d-%d", stamp, math.random(100000,999999))
        local localOwner = CurrentVerifiedOwnerKey()
        local record = {
            id=id, title=title, description=description,
            author=(UnitName and UnitName("player")) or "You",
            ownerKey=localOwner, ownerVerified=localOwner and true or false,
            class=NormalizeClass(selectedClass) or InferBuildClass(echoes)
                or NormalizeClass(wl.class),
            echoes=echoes, postedAt=stamp, lastModified=stamp,
            isMine=localOwner ~= nil,
        }
        local identityOk, identityErr = RefreshBuildIdentity(record)
        if not identityOk then return false, identityErr end
        PeerRecord("share_created", {id=id,class=record.class or "UNKNOWN",
            echoes=record.echoCount or #echoes,outcome="created"})
        local saved, saveWhy = SaveBuild(record)
        local localSaved = saved == true
        local buildRevision = BuildRevision()
        PeerRecord("share_local", {id=id,
            outcome=localSaved and "saved" or "rejected",
            reason=saveWhy,revision=buildRevision})
        local outcome = {
            id=id,class=record.class or "UNKNOWN",
            echoCount=record.echoCount or #echoes,
            buildRevision=buildRevision,localSaved=localSaved,
            queueAdmitted=false,queueReason=nil,retryPending=false,
            sent=false,sendCompleted=false,peerStored=nil,
            confirmation="unavailable",
        }
        if not localSaved then
            outcome.queueReason = "local save failed"
            lastShareOutcome = outcome
            return false, saveWhy or "local save failed", outcome
        end
        local admitted, queueWhy, syncStatus = BroadcastIfPossible(record, true)
        if syncStatus then
            -- Keep Sync's fixed operation owner immutable outside Sync. The
            -- Community projection retains only a defensive scalar snapshot
            -- and refreshes later transitions through GetShareStatus.
            outcome = {}
            for key, value in pairs(syncStatus) do
                local kind = type(value)
                if kind == "string" or kind == "number"
                    or kind == "boolean" then outcome[key] = value end
            end
            outcome.id = id
            outcome.class = record.class or "UNKNOWN"
            outcome.echoCount = record.echoCount or #echoes
            outcome.buildRevision = buildRevision
            outcome.localSaved = true
        end
        outcome.queueAdmitted = admitted == true
        outcome.queueReason = queueWhy
            or (outcome.queueAdmitted and "queued" or "queue rejected")
        outcome.retryPending = outcome.retryPending == true
        outcome.sent = outcome.sent == true
        outcome.sendCompleted = outcome.sendCompleted == true
        outcome.peerStored = nil
        outcome.confirmation = "unavailable"
        lastShareOutcome = outcome
        PeerRecord("share_outcome", {id=id,
            outcome=outcome.queueAdmitted and "queued"
                or outcome.retryPending and "retry pending" or "not queued",
            reason=outcome.queueReason,revision=buildRevision})
        local D = Nexus.DpsCapture
        if D and D.BroadcastBestForBuild then
            pcall(D.BroadcastBestForBuild, id)
        end
        return true, id, outcome
    end

    function M.ShareStatus(id)
        local wanted = id and tostring(id) or nil
        local current = lastShareOutcome
        if type(current) ~= "table"
            or (wanted and tostring(current.id) ~= wanted) then
            return nil
        end
        local sync = Nexus and Nexus.Sync
        local remote = sync and type(sync.GetShareStatus) == "function"
            and sync.GetShareStatus(current.id) or nil
        local copy = {}
        for key, value in pairs(current) do
            local kind = type(value)
            if kind == "string" or kind == "number" or kind == "boolean" then
                copy[key] = value
            end
        end
        for key, value in pairs(type(remote) == "table" and remote or {}) do
            copy[key] = value
        end
        copy.peerStored = nil
        copy.confirmation = "unavailable"
        return copy
    end

    function M.CanRetryShare(id)
        id = id and tostring(id) or nil
        local build = id and LoadBuild(id) or nil
        if not build then return false, "build not found" end
        if not IsOwnBuild(build) then return false, "not your build" end
        local sync = Nexus and Nexus.Sync
        if not (sync and type(sync.GetShareStatus) == "function"
            and type(sync.BroadcastBuildSummary) == "function") then
            return false, "Sync status unavailable"
        end
        local status = sync.GetShareStatus(id)
        if type(status) ~= "table" or status.kind ~= "share"
            or tostring(status.id or "") ~= id or status.terminal ~= true then
            return false, "Share is not terminal"
        end
        local outcome = tostring(status.outcome or "")
        if outcome ~= "expired" and outcome ~= "dropped"
            and outcome ~= "throttle-exhausted" and outcome ~= "reset"
            and outcome ~= "rejected" then
            return false, "Share is not retryable"
        end
        local representedVersion = tostring(tonumber(build.lastModified)
            or tonumber(build.postedAt) or 0)
        if tostring(status.version or "") ~= representedVersion then
            return false, "build changed since the failed Share"
        end
        return true, nil, status
    end

    function M.RetryShare(id)
        local retryable, retryWhy = M.CanRetryShare(id)
        if not retryable then return false, retryWhy end
        id = tostring(id)
        local record = LoadBuild(id)
        local sync = Nexus and Nexus.Sync
        local called, admitted, queueWhy, syncStatus = pcall(
            sync.BroadcastBuildSummary, record, {retryOnFull=true})
        if not called then
            queueWhy, syncStatus = "Sync retry failed", nil
            admitted = false
        end
        PeerRecord("share_queue", {id=id,
            outcome=admitted ~= false and "admitted" or "rejected",
            reason=queueWhy})
        local outcome = {}
        for key, value in pairs(type(syncStatus) == "table" and syncStatus or {}) do
            local kind = type(value)
            if kind == "string" or kind == "number" or kind == "boolean" then
                outcome[key] = value
            end
        end
        outcome.id = id
        outcome.class = record.class or "UNKNOWN"
        outcome.echoCount = record.echoCount or #(record.echoes or {})
        outcome.buildRevision = BuildRevision()
        outcome.localSaved = true
        outcome.queueAdmitted = outcome.queueAdmitted == true
            or admitted == true
        outcome.queueReason = queueWhy
            or (outcome.queueAdmitted and "queued" or "queue rejected")
        outcome.retryPending = outcome.retryPending == true
        outcome.sent = outcome.sent == true
        outcome.sendCompleted = outcome.sendCompleted == true
        outcome.peerStored = nil
        outcome.confirmation = "unavailable"
        lastShareOutcome = outcome
        local started = outcome.queueAdmitted or outcome.retryPending
        PeerRecord("share_retry_action", {id=id,
            outcome=started and "started" or "rejected",
            reason=outcome.queueReason,attempts=outcome.attempt})
        return started and true or false, outcome.queueReason, outcome
    end

    local function HasLeaderboardRecord(build)
        if not build then return false end
        if Identity.SavedMirrorKind(build) == "saved" then
            local related, valid = RelatedBuild(build)
            if not valid or type(related) ~= "table" then return false end
            build = related
        elseif Identity.SavedMirrorKind(build) ~= "ordinary" then
            return false
        end
        if build.autoDps then return true end
        local D = Nexus.DpsCapture
        if not D or not D.GetLeaderboard then return false end
        local dummy = D.GetLeaderboard(build.id, "dummy") or {}
        local lk = D.GetLeaderboard(build.id, "lk") or {}
        return #dummy > 0 or #lk > 0
    end

    function M.HasLeaderboardRecord(idOrBuild)
        local build = type(idOrBuild) == "table" and idOrBuild
            or LoadBuild(idOrBuild)
        return HasLeaderboardRecord(build)
    end

    function M.RecordBuildId(build)
        local savedKind = Identity.SavedMirrorKind(build)
        local related, valid = RelatedBuild(build)
        if savedKind ~= "ordinary" and not valid then return nil end
        return related and related.id or nil
    end

    -- Compact projection rows deliberately omit Echo arrays. Revalidate only
    -- their persisted relationship hints against compact catalog summaries;
    -- the list projection can then join the accepted target to its one bulk
    -- DPS eligibility snapshot without per-row leaderboard reads.
    function M.SavedProjectionRelation(build)
        if Identity.SavedMirrorKind(build) ~= "saved" then
            return nil
        end
        local ownerKey = Identity.VerifiedOwnerKey(build)
        if not ownerKey then return nil end
        local score = NewRelatedScorer(
            build.serverTitle or build.title, build.fingerprint,
            ownerKey, build.ordinaryComplete == true)
        local related = BestPreferredRelated(build, score, LoadBuildSummary)
        if not related or type(related.id) ~= "string"
            or type(related.fingerprint) ~= "string" then return nil end
        return {
            buildId=related.id,
            fingerprint=related.fingerprint,
            fingerprintHash=related.fingerprintHash,
            class=NormalizeClass(related.class),
        }
    end

    -- One controller-owned projection verdict prevents list, detail, renderer,
    -- and diagnostic consumers from independently interpreting persisted Saved
    -- class or relationship hints. Publication identity is source-bound but
    -- content-independent, so it remains valid across local loadout edits.
    function M.SavedProjectionState(build)
        if Identity.SavedMirrorKind(build) ~= "saved" then return nil end
        local relation = M.SavedProjectionRelation(build)
        local published = PublishedBuild(build, LoadBuildSummary)
        local localOwner = Identity.LocalOwnsSavedMirror(
            build, CurrentOwnerKey())
        local projectedClass = localOwner and CurrentClass() or nil
        projectedClass = NormalizeClass(projectedClass)
            or NormalizeClass(relation and relation.class) or "UNKNOWN"
        return {
            recordBuildId=relation and relation.buildId or nil,
            fingerprint=relation and relation.fingerprint or nil,
            fingerprintHash=relation and relation.fingerprintHash or nil,
            class=projectedClass,
            publishedBuildId=published and published.id or nil,
        }, relation
    end

    -- Public readers receive a defensive Saved projection whose class and
    -- relationship IDs all originate in the verdict above. Ordinary rows keep
    -- their established catalog-reader semantics; malformed markers disappear.
    function M.ProjectBuild(idOrBuild)
        local build = type(idOrBuild) == "table" and idOrBuild
            or LoadBuild(idOrBuild)
        local kind = Identity.SavedMirrorKind(build)
        if kind == "ordinary" then return build, nil end
        if kind ~= "saved" then return nil, nil end
        local state, relation = M.SavedProjectionState(build)
        local projected = ShallowCopy(build)
        projected.recordBuildId = state and state.recordBuildId or nil
        projected.publishedBuildId = state and state.publishedBuildId or nil
        projected.class = NormalizeClass(state and state.class) or "UNKNOWN"
        return projected, relation
    end

    function M.PublishedBuildId(idOrBuild)
        local build = type(idOrBuild) == "table" and idOrBuild
            or LoadBuild(idOrBuild)
        local published = PublishedBuild(build)
        return published and published.id or nil
    end

    function M.DpsSummary(build)
        local dps = Nexus and Nexus.DpsCapture
        local summary = {
            dummy=0,lk=0,best=0,average=0,count=0,
        }
        if not (dps and build) then return summary end
        local savedKind = Identity.SavedMirrorKind(build)
        local related, valid = RelatedBuild(build)
        local recordId = (savedKind == "ordinary" or valid)
            and related and related.id or nil
        local allowEchoFallback = savedKind == "ordinary" or valid
        for _, category in ipairs({"dummy", "lk"}) do
            local rows
            if recordId and dps.GetLeaderboard then
                local ok, result = pcall(
                    dps.GetLeaderboard, recordId, category)
                if ok then rows = result end
            end
            if (not rows or #rows == 0) and allowEchoFallback
                and dps.GetLeaderboardForEchoes and related.echoes then
                local ok, result = pcall(
                    dps.GetLeaderboardForEchoes, related.echoes, category)
                if ok then rows = result end
            end
            if type(rows) == "table" then
                for _, row in ipairs(rows) do
                    local value = tonumber(
                        row.dps or row.value or row.amount) or 0
                    if value > summary[category] then
                        summary[category] = value
                    end
                end
            end
        end
        if summary.dummy > 0 then summary.count = summary.count + 1 end
        if summary.lk > 0 then summary.count = summary.count + 1 end
        summary.best = math.max(summary.dummy, summary.lk)
        if summary.count == 2 then
            summary.average = (summary.dummy + summary.lk) / 2
        elseif summary.count == 1 then
            summary.average = summary.best
        end
        return summary
    end

    function M.PrepareEditDraft(id)
        local build = LoadBuild(id)
        if not build or not IsOwnBuild(build) then return nil end
        local editName = build.title
        if not editName or editName == "" then editName = build.userTitle end
        if (not editName or editName == "")
            and Identity.SavedMirrorKind(build) == "saved" then
            editName = build.serverTitle
            if (not editName or editName == "") and build.serverSlot
                and Adapter and Adapter.Slots then
                local slots = Adapter.Slots()
                local live = slots and slots.bySlot
                    and slots.bySlot[build.serverSlot]
                editName = live and live.name or nil
            end
        end
        editName = (editName and editName ~= "")
            and editName or "Untitled Build"
        M.BeginEditDraft(
            id, editName, build.description or "", build.link)
        return {
            id=id,title=editName,description=build.description or "",
            link=build.link,locked=HasLeaderboardRecord(build),
        }
    end

    function M.RepairOverlayIdentities()
        local catalog = Catalog()
        if not (catalog and type(catalog.Get) == "function") then return 0 end
        local changed = 0
        for id, build in pairs(Store()) do
            local _, source = catalog.Get(id)
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
                    local saved = SaveBuild(build)
                    if saved then changed = changed + 1 end
                end
            end
        end
        return changed
    end

    local function PublicationTarget(source, ownerKey)
        local linked = PublishedBuild(source)
        if linked then return linked.id, linked end

        local base = "published-" .. tostring(source.id)
        local token = StableIdHash(ownerKey):sub(1, 8)
        local candidateId, candidate = FindStableCollisionTarget(
            base, token, function(existing)
            return HasVerifiedRelatedOwner(existing, ownerKey)
                and existing.sourceSavedBuildId == source.id
        end)
        if candidateId then return candidateId, candidate end
        return nil, nil, "no safe publication identity is available"
    end

    function M.PublishImportedBuild(id)
        local source = LoadBuild(id)
        if Identity.SavedMirrorKind(source) ~= "saved" then
            return false, "not a saved loadout"
        end
        if not IsOwnBuild(source) then return false, "not your build" end
        if type(source.echoes) ~= "table" or #source.echoes == 0 then return false, "that build has no echoes" end

        -- Use one stable, source-bound publication per Saved Build mirror.
        -- A stale/colliding persisted ID has no write authority.
        local localOwner = CurrentVerifiedOwnerKey()
        local publishedId, old, targetWhy = PublicationTarget(source, localOwner)
        if not publishedId then return false, targetWhy end
        local stamp = NextStamp(old and old.lastModified or 0)
        local echoes, lockedEchoes = {}, {}
        for _, e in ipairs(source.echoes) do
            local copy = {spellId=e.spellId,quality=e.quality,
                stacks=e.stacks or e.count or 1}
            if e.locked then
                copy.locked = true
                lockedEchoes[#lockedEchoes + 1] = copy
            else
                echoes[#echoes + 1] = copy
            end
        end
        for _, e in ipairs(type(source.lockedEchoes) == "table"
            and source.lockedEchoes or {}) do
            lockedEchoes[#lockedEchoes + 1] = {
                spellId=e.spellId or e.id,quality=e.quality,
                stacks=e.stacks or e.count or 1,locked=true,
            }
        end
        if #echoes == 0 then return false, "that build has no ordinary echoes" end
        local projectionState = M.SavedProjectionState(source)
        local publicationClass = NormalizeClass(
            projectionState and projectionState.class)
            or InferBuildClass(echoes)
        -- Build and validate a complete replacement before changing either record.
        local record = {
            id=publishedId,
            title=source.title or "Saved Build",
            description=source.userDescription or source.description or "",
            author=(UnitName and UnitName("player")) or "You",
            ownerKey=localOwner, ownerVerified=localOwner and true or false,
            class=publicationClass,
            echoes=echoes,
            postedAt=old and old.postedAt or stamp,
            lastModified=stamp,
            isMine=localOwner ~= nil,
            sourceSavedBuildId=id,
            link=old and old.link or nil,
        }
        if #lockedEchoes > 0 then record.lockedEchoes = lockedEchoes end
        local identityOk, identityErr = RefreshBuildIdentity(record)
        if not identityOk then return false, identityErr end
        local recordSaved, recordSaveWhy = SaveBuild(record)
        if not recordSaved then
            return false, recordSaveWhy or "build storage refused"
        end
        source.publishedBuildId = publishedId
        source.recordBuildId = publishedId
        source.lastPublishedAt = stamp
        local sourceSaved, sourceSaveWhy = SaveBuild(source)
        if not sourceSaved then
            return false, sourceSaveWhy or "saved-loadout storage refused"
        end
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
        if not Identity.ValidDisplayText(nextTitle, 80, false) then
            return false, "title contains unsafe text"
        end
        if not Identity.ValidDisplayText(nextDescription, 2000, true, true) then
            return false, "description contains unsafe text"
        end
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
        local savedKind = Identity.SavedMirrorKind(b)
        if savedKind == "saved" then
            b.userTitle = nextTitle
            b.userDescription = nextDescription
        end
        b.lastModified = NextStamp(b.lastModified or b.postedAt)
        local saved, saveWhy = SaveBuild(b)
        if not saved then return false, saveWhy or "build storage refused" end
        -- Editing a server Saved Build mirror is local-only. It reaches the
        -- community only through the explicit Upload Build action (or a DPS
        -- record path handled by DpsCapture).
        if savedKind == "ordinary" then BroadcastIfPossible(b) end
        return true
    end

    function M.UpdateFromWishlist(id)
        local b = LoadBuild(id)
        if not b then return false, "not found" end
        if not IsOwnBuild(b) then return false, "not your build" end
        if Identity.SavedMirrorKind(b) == "saved" then
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
        local saved, saveWhy = SaveBuild(b)
        if not saved then return false, saveWhy or "build storage refused" end
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
        local owner = IsOwnBuild(b)
        if not owner and not IsAdmin() then
            return false, "not your build"
        end
        if Identity.SavedMirrorKind(b) == "saved" then
            return false, "server Saved Builds cannot be deleted here"
        end
        local outcome = {
            localRemoved=false,queueAdmitted=false,retryPending=false,
        }
        if owner then
            local sync = Nexus and Nexus.Sync
            if sync and type(sync.BroadcastDelete) == "function" then
                local called, queued, why = pcall(sync.BroadcastDelete, b)
                if called then
                    outcome.queueAdmitted = queued == true
                    if not queued then
                        outcome.retryPending = why == "queued for retry"
                        outcome.queueReason = tostring(
                            why or "Sync queue rejected withdrawal")
                    end
                else
                    outcome.queueReason = "Sync withdrawal failed"
                end
            else
                outcome.queueReason = "Sync unavailable"
            end
        else
            outcome.localOnly = true
        end
        -- Sync normally creates the authorized tombstone. Keep the catalog
        -- lifecycle correct in focused/offline callers too, and let an explicit
        -- local admin removal hide an immutable bundled row without broadcasting
        -- a forged owner deletion.
        local tombstoneWhy
        if LoadBuild(id) then
            local tombstoned
            tombstoned, tombstoneWhy = SetTombstone(id, {
                stamp=(time and time()) or 0,
                author=tostring(b.author or ""),
                localOnly=not owner or nil,
            })
            if tombstoned then tombstoneWhy = nil end
        end
        local _, removeWhy = RemoveOverlay(id)
        if LoadBuild(id) then
            outcome.storageReason = tostring(tombstoneWhy or removeWhy
                or "local build removal refused")
            outcome.queueReason = outcome.queueReason or outcome.storageReason
            return false, outcome
        end
        if selectedId == id then selectedId = nil end
        outcome.localRemoved = true
        return true, outcome
    end

    ------------------------------------------------------------------------
    -- Friendly error messages
    ------------------------------------------------------------------------

    local FRIENDLY_ERRORS = {
        spacing = "the server is busy -- try again in a moment",
        refused = "the server refused the change",
        ["no echoes"] = "that build has no echoes",
        ["no valid echoes"] = "none of its echoes are valid",
    }

    local function Friendly(err)
        return FRIENDLY_ERRORS[tostring(err)] or tostring(err)
    end

    local function CopyLockInEchoes(echoes)
        local out = {}
        for index, echo in ipairs(type(echoes) == "table" and echoes or {}) do
            if type(echo) ~= "table" then return nil end
            local copy = {}
            for key, value in pairs(echo) do copy[key] = value end
            out[index] = copy
        end
        return out
    end

    local function TryLockIn(title, echoes, replacePending)
        if not (Adapter and type(Adapter.UploadWishlist) == "function") then
            notify("|cffff6060Nexus:|r couldn't lock in: adapter not ready")
            pendingLockIn = nil
            return false, "adapter not ready"
        end
        local ok, err = Adapter.UploadWishlist(0, title, echoes)
        if ok then
            notify("|cff4dff80Nexus:|r locked in '"..tostring(title).."'.")
            pendingLockIn = nil
            refreshView()
            return true
        end
        if tostring(err) == "spacing" then
            if replacePending or not pendingLockIn then
                pendingLockIn = {title=title,echoes=echoes,tries=0}
            end
            return false, err
        end
        notify("|cffff6060Nexus:|r couldn't lock in: "..Friendly(err))
        pendingLockIn = nil
        return false, err
    end

    function M.AcceptLockIn(payload)
        if type(payload) ~= "table" or type(payload.echoes) ~= "table" then
            return false, "invalid lock-in payload"
        end
        -- Snapshot once before the first upload so popup/frame data cannot
        -- mutate a pending retry after the server returns spacing.
        local echoes = CopyLockInEchoes(payload.echoes)
        if not echoes or #echoes == 0 then
            return false, "invalid lock-in payload"
        end
        -- A new explicit confirmation retains the established ability to
        -- supersede older pending work. Only automatic retries are forbidden
        -- from replacing the payload or refreshing its lifetime.
        return TryLockIn(payload.title, echoes, true)
    end

    function M._PumpPendingLockIn()
        local pending = pendingLockIn
        if not pending then return end
        if pending.tries >= 12 then
            notify("|cffff6060Nexus:|r couldn't lock in: "..Friendly("spacing"))
            pendingLockIn = nil
            return false, "expired"
        end
        pending.tries = pending.tries + 1
        return TryLockIn(pending.title, pending.echoes, false)
    end

    function M.IsLockInPending()
        return pendingLockIn ~= nil
    end

    function M.PendingLockIn()
        local pending = pendingLockIn
        if not pending then return nil end
        return {
            title=pending.title,tries=pending.tries,
            echoCount=#pending.echoes,
        }
    end

    function M.PrepareLockInSelected()
        if not selectedId then return nil end
        local build = LoadBuild(selectedId)
        if not build then return nil end
        if type(build.echoes) ~= "table" or #build.echoes == 0 then
            M.RequestLoadout(selectedId)
            notify("|cff7fd5ffNexus:|r this build is still completing its background sync. Try again shortly.")
            return nil
        end

        local lockedBySpell = {}
        if Adapter and Adapter.LockedOwned then
            local locked = Adapter.LockedOwned()
            if locked and type(locked.bySpell) == "table" then
                lockedBySpell = locked.bySpell
            end
        end
        local echoes, total, skippedLocked, skippedOverflow = {}, 0, 0, 0
        for _, echo in ipairs(build.echoes) do
            local id = tonumber(echo and echo.spellId)
            local stacks = math.max(1, tonumber(echo and echo.stacks) or 1)
            if id and (tonumber(lockedBySpell[id]) or 0) > 0 then
                skippedLocked = skippedLocked + 1
            elseif id and total + stacks > 79 then
                skippedOverflow = skippedOverflow + 1
            elseif id then
                echoes[#echoes + 1] = {
                    spellId=id,quality=echo.quality,stacks=stacks,
                }
                total = total + stacks
            end
        end
        if #echoes == 0 then
            notify("|cffff6060Nexus:|r nothing left to lock in -- every Echo in this build is already locked.")
            return nil
        end
        if skippedLocked > 0 or skippedOverflow > 0 then
            notify(string.format(
                "|cffff9040Nexus:|r locking in %d / 79 Echoes -- %d already locked (skipped), %d didn't fit "
                    .. "(skipped). Use |cffffd200Load into Editor|r instead if you need to design locked "
                    .. "slots for the rest.", total, skippedLocked, skippedOverflow))
        end
        return {title=build.title,echoes=echoes}
    end

    function M.WishlistEchoes(wishlist)
        return WishlistEchoes(wishlist)
    end

    function M.InferBuildClass(echoes)
        return InferBuildClass(echoes)
    end

    function M.CommitEditDraft()
        if not editDraft then return false, "not found" end
        local draft = editDraft
        local ok, err = M.EditBuild(
            draft.id, draft.title, draft.description, draft.link)
        if ok then editDraft = nil end
        return ok, err
    end

    function M.Initialize(adapter, bundledBuilds)
        Adapter = adapter
        local catalog = Catalog()
        if catalog and type(catalog.Init) == "function" then
            catalog.Init(type(NexusDB) == "table" and NexusDB or {},
                bundledBuilds)
        end
        M.RemoveLegacyBuilds()
        M.RepairOverlayIdentities()
        return true
    end

    return M
end

Nexus.CommunityInternals.Controller = Controller
