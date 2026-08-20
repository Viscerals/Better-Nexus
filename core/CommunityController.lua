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

    function M.BindAdapter(adapter)
        Adapter = adapter
    end

    function M.Build(id)
        return LoadBuild(id)
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
        return {
            ownerKey=CurrentOwnerKey() or "",
            player=Identity.PlayerKey(
                (UnitName and UnitName("player")) or "") or "",
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
        return dps.GetRecordForIdentity(build.id, build.fingerprint,
            build.fingerprintHash, category)
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
        return selectedId and LoadBuild(selectedId) or nil
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
        if not build then return false end
        local mine = CurrentOwnerKey()
        if not mine then return false end
        if build.ownerKey then
            return Identity.CanonicalOwnerKey(build.ownerKey) == mine
        end
        -- Legacy builds predate ownerKey. They remain editable only when both
        -- their local marker and author name match the current character.
        if not build.isMine then return false end
        local me = (UnitName and UnitName("player")) or ""
        return Identity.SamePlayer(build.author, me)
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
    local function BeginRelatedBuild(serverTitle, echoes, old, author)
        local catalog = Catalog()
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
            old and old.recordBuildId and LoadBuild(old.recordBuildId) or nil,
            old and old.publishedBuildId and LoadBuild(old.publishedBuildId) or nil,
        }
        local best, bestScore = nil, -1
        for _, candidate in ipairs(preferred) do
            local score = CandidateScore(candidate)
            if score and score > bestScore then best, bestScore = candidate, score end
        end
        local cursor = catalog and catalog.BeginRelatedCursor
            and catalog.BeginRelatedCursor(author, serverTitle, exactKey) or nil
        return {
            cursor=cursor,best=best,bestScore=bestScore,
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
            if score and score > job.bestScore then
                job.best, job.bestScore = candidate, score
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
        local buildRevision = BuildRevision()
        local cacheValid = savedRelatedCacheRevision == buildRevision
        if not cacheValid then savedRelatedCache = {} end
        savedImportJob = {
            slots=slots,keys=keys,index=1,me=me,
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

    local function PrepareSavedSlot(job, slot)
        savedImportStats.slotPreparations =
            savedImportStats.slotPreparations + 1
        local live = job.slots.bySlot[slot]
        if not (live and type(live.echoes) == "table" and #live.echoes > 0) then
            savedImportStats.emptySlots = savedImportStats.emptySlots + 1
            return nil
        end
        local id = string.format("saved-%s-%d", job.meKey, slot)
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
        local inputKey = table.concat({job.me,serverTitle,tostring(exactKey)}, "\0")
        local cached = job.cacheValid and savedRelatedCache[id] or nil
        local cachedBuild = cached and cached.inputKey == inputKey
            and cached.relatedId and LoadBuild(cached.relatedId) or nil
        return {
            slot=slot,id=id,live=live,echoes=echoes,total=total,
            serverTitle=serverTitle,old=old,title=title,linked=linked,
            destinationName=destinationName,progress=progress,
            destinationTotal=destinationTotal,
            inputKey=inputKey,
            related=cached and cached.inputKey == inputKey and {
                cached=true,best=cachedBuild,
            } or BeginRelatedBuild(serverTitle, echoes, old, job.me),
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
        job.cacheUpdates[current.id] = {
            inputKey=current.inputKey,relatedId=recordBuildId,
        }
        local signatureParts = {
            current.serverTitle,tostring(class),tostring(recordBuildId or ""),
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
        if not old or old._savedSignature ~= signature then
            local stamp = NextStamp(old and old.lastModified or 0)
            local record = {
                        id=current.id, title=current.title,
                        serverTitle=current.serverTitle,
                        userTitle=old and old.userTitle or nil,
                        description=(old and old.userDescription) or (destinationName
                            and string.format("Destination wishlist: %s - in progress (%d/%d).", destinationName, progress, destinationTotal)
                            or "No destination wishlist associated yet."),
                        userDescription=old and old.userDescription or nil,
                        publishedBuildId=old and old.publishedBuildId or nil,
                        lastPublishedAt=old and old.lastPublishedAt or nil,
                        author=job.me, ownerKey=CurrentOwnerKey(), class=class, echoes=echoes,
                        postedAt=(old and old.postedAt) or stamp, lastModified=stamp,
                        isMine=true, importedSavedBuild=true, serverSlot=slot,
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
                            job.current.old, job.me)
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
                    if build and build.importedSavedBuild
                        and Identity.SamePlayer(build.author, job.me)
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
        local incomingOwnerVerified = record and record.ownerVerified
        local explicitClass = NormalizeClass(record and (record.class or record.k))
        local player = tostring(record and record.player
            or (UnitName and UnitName("player")) or "Unknown")
        local recordOwner = record and record.ownerKey
        local explicitId = record and (record.buildId or record.b)
        if type(explicitId) ~= "string" or explicitId == "" then explicitId = nil end
        local catalog = Catalog()
        if catalog and type(catalog.FindExactFingerprint) == "function" then
            local recoveredId, recovered = catalog.FindExactFingerprint(key)
            local evidence = Nexus and Nexus.LoadoutEvidence
            local verdict = evidence and recovered
                and type(evidence.OrdinaryCompleteness) == "function"
                and evidence.OrdinaryCompleteness(recovered) or nil
            if recoveredId and type(verdict) == "table"
                and verdict.complete == true then
                local recoveredOwner = recovered.ownerKey
                    and Identity.CanonicalOwnerKey(recovered.ownerKey) or nil
                local incomingOwner = recordOwner
                    and Identity.CanonicalOwnerKey(recordOwner) or nil
                local sameAutoOwner = recovered.autoDps ~= true
                    or (incomingOwner and recoveredOwner
                        and incomingOwner == recoveredOwner)
                    or ((not incomingOwner or not recoveredOwner)
                        and Identity.SamePlayer(recovered.author, player))
                -- A relay-created page may be reused for ambient reads, but
                -- the exact direct owner must reach the promotion boundary.
                -- Auto-DPS pages are owner-specific even when their ordinary
                -- fingerprint happens to match another player's record.
                if sameAutoOwner and not (incomingOwnerVerified == true
                    and recovered.ownerVerified == false) then
                    return recoveredId, recovered
                end
            end
        end

        -- A protocol build ID is an identity, not a derived alias. Never attach
        -- its record to a different loadout or owner merely because IDs collide.
        local explicitExisting = explicitId and LoadBuild(explicitId) or nil
        if explicitExisting then
            -- Relayed DPS evidence may remain visible as an ambient record, but
            -- it cannot hydrate or publish an existing Community identity.
            if record and record.ownerVerified == false then return nil end
            local evidence = Nexus and Nexus.LoadoutEvidence
            local existingVerdict = evidence
                and type(evidence.OrdinaryCompleteness) == "function"
                and evidence.OrdinaryCompleteness(explicitExisting) or nil
            local existingComplete = type(existingVerdict) == "table"
                and existingVerdict.complete == true
            local existingKey = existingComplete
                and existingVerdict.fingerprint or nil
            if existingComplete and existingKey ~= key then return nil end
            if explicitExisting.ownerKey then
                if not recordOwner then return nil end
                local recordOwnerKey = Identity.CanonicalOwnerKey(recordOwner)
                if not recordOwnerKey or recordOwnerKey
                    ~= Identity.CanonicalOwnerKey(explicitExisting.ownerKey) then
                    return nil
                end
            elseif not Identity.SamePlayer(explicitExisting.author, player) then
                return nil
            end
            local promoteOwner = incomingOwnerVerified == true
                and explicitExisting.ownerVerified == false
            if promoteOwner
                and not Identity.SamePlayer(explicitExisting.author, player) then
                return nil
            end
            if promoteOwner then
                explicitExisting.ownerVerified = true
                explicitExisting.relaySender = nil
                explicitExisting.ownerKey = explicitExisting.ownerKey or recordOwner
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
                local saved = SaveBuild(explicitExisting)
                if not saved then return nil end
                if explicitExisting.ownerVerified ~= false then
                    BroadcastIfPossible(explicitExisting)
                end
            elseif promoteOwner then
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
        local manualId, manualBuild
        if not explicitId then
            for id, build in pairs(Store()) do
                local evidence = Nexus and Nexus.LoadoutEvidence
                local verdict = evidence
                    and type(evidence.OrdinaryCompleteness) == "function"
                    and evidence.OrdinaryCompleteness(build) or nil
                if type(verdict) == "table" and verdict.complete == true
                    and verdict.fingerprint == key then
                    if not build.autoDps then
                        if IsOwnBuild(build) then return id, build end
                        manualId, manualBuild = manualId or id, manualBuild or build
                    else
                        local recordOwnerKey = recordOwner
                            and Identity.CanonicalOwnerKey(recordOwner)
                        local sameOwner = recordOwnerKey and build.ownerKey
                            and recordOwnerKey
                                == Identity.CanonicalOwnerKey(build.ownerKey)
                        local sameLegacyAuthor = not recordOwner
                            and Identity.SamePlayer(build.author, player)
                        if sameOwner or sameLegacyAuthor then
                            ownAutoId, ownAutoBuild = id, build
                        end
                    end
                end
            end
        end
        if manualId then return manualId, manualBuild end

        local copied = {}
        for _, e in ipairs(echoes or {}) do
            local id = tonumber(e and (e.spellId or e.id))
            copied[#copied + 1] = { spellId=id, quality=e.quality, stacks=e.count or e.stacks or 1 }
        end
        -- Locked Echoes remain supplemental record evidence. They are never
        -- folded into the ordinary build pool or its fingerprint.
        local me = tostring((UnitName and UnitName("player")) or "")
        local playerIsLocal = Identity.SamePlayer(player, me)
        local localClass
        if playerIsLocal and UnitClass then
            local _, token = UnitClass("player")
            localClass = NormalizeClass(token)
        end
        local class = explicitClass or InferBuildClass(copied)
            or localClass or "UNKNOWN"

        if ownAutoId then
            local changed = false
            if incomingOwnerVerified == true
                and ownAutoBuild.ownerVerified == false then
                if not Identity.SamePlayer(ownAutoBuild.author, player) then
                    return nil
                end
                ownAutoBuild.ownerVerified = true
                ownAutoBuild.relaySender = nil
                ownAutoBuild.ownerKey = ownAutoBuild.ownerKey or recordOwner
                changed = true
            end
            if explicitClass and ownAutoBuild.class ~= explicitClass then
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
                if ownAutoBuild.ownerVerified ~= false then
                    BroadcastIfPossible(ownAutoBuild)
                end
            end
            return ownAutoId, ownAutoBuild
        end

        local stamp = NextStamp(0)
        local ownerKey = recordOwner or (playerIsLocal and CurrentOwnerKey() or nil)
        local buildOwnerVerified
        if incomingOwnerVerified == true then
            buildOwnerVerified = true
        elseif incomingOwnerVerified == false then
            buildOwnerVerified = false
        end
        local identity = ownerKey or Identity.PlayerKey(player)
        if not identity then return nil end
        local id = explicitId or ("dps-" .. FingerprintHash(key) .. "-"
            .. FingerprintHash(identity):sub(1, 8))
        local build = {
            id=id, title=(CLASS_LABEL[class] or class) .. " Record Loadout",
            description="Automatically created from a compatible DPS record. Exact Echo IDs and stack quantities are preserved for copying and comparison.",
            author=player, ownerKey=ownerKey, class=class, echoes=copied,
            postedAt=stamp, lastModified=stamp,
            isMine=(ownerKey and ownerKey == CurrentOwnerKey()) or false,
            autoDps=true, fingerprint=key, loadoutAvailable=true,
            needsFullBuild=false,
            ownerVerified=buildOwnerVerified,
            relaySender=incomingOwnerVerified == false
                and record.relaySender or nil,
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
        if build.ownerVerified ~= false then BroadcastIfPossible(build) end
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
        return build and (build.recordBuildId
            or build.publishedBuildId or build.id) or nil
    end

    function M.DpsSummary(build)
        local dps = Nexus and Nexus.DpsCapture
        local summary = {
            dummy=0,lk=0,best=0,average=0,count=0,
        }
        if not (dps and build) then return summary end
        local recordId = M.RecordBuildId(build)
        for _, category in ipairs({"dummy", "lk"}) do
            local rows
            if recordId and dps.GetLeaderboard then
                local ok, result = pcall(
                    dps.GetLeaderboard, recordId, category)
                if ok then rows = result end
            end
            if (not rows or #rows == 0)
                and dps.GetLeaderboardForEchoes and build.echoes then
                local ok, result = pcall(
                    dps.GetLeaderboardForEchoes, build.echoes, category)
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
            and build.importedSavedBuild then
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
        if #lockedEchoes > 0 then record.lockedEchoes = lockedEchoes end
        local identityOk, identityErr = RefreshBuildIdentity(record)
        if not identityOk then return false, identityErr end
        local recordSaved, recordSaveWhy = SaveBuild(record)
        if not recordSaved then
            return false, recordSaveWhy or "build storage refused"
        end
        source.publishedBuildId = publishedId
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
        if b.importedSavedBuild then
            b.userTitle = nextTitle
            b.userDescription = nextDescription
        end
        b.lastModified = NextStamp(b.lastModified or b.postedAt)
        local saved, saveWhy = SaveBuild(b)
        if not saved then return false, saveWhy or "build storage refused" end
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
        if b.importedSavedBuild then
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
