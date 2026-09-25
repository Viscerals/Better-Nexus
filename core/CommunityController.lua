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
    local pendingShare
    -- Approved title, description and source of a Share whose local save
    -- failed. Session-only; the Share form offers it back unchanged.
    local failedShareDraft
    -- Explicit Stop Sharing approvals waiting for catalog admission. Bounded,
    -- session-only, one entry per exact ID.
    local pendingRemovals, MAX_PENDING_REMOVALS = {}, 8
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
    local pendingCatalogMutations = setmetatable({}, {__mode="k"})
    local pendingPublications = {}
    local startupJob

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

    -- `origin` is carried only by callers that actually know whether the
    -- record came from this player or from a received one. Everyone else
    -- leaves it unknown rather than guessing.
    local function RetainCatalogMutation(catalog, operation, onComplete,
                                         ok, why, ticket, origin)
        if ok ~= nil or why ~= "ROOT_MUTATION_PENDING"
            or type(ticket) ~= "table" then
            return ok, why
        end
        pendingCatalogMutations[ticket] = {
            operation=operation,onComplete=onComplete,origin=origin,
        }
        if type(catalog.BindMutationCompletion) ~= "function" then
            pendingCatalogMutations[ticket] = nil
            return false, "INVALID_MUTATION_TICKET"
        end
        local bound = catalog.BindMutationCompletion(ticket, function(outcome)
                local retained = pendingCatalogMutations[outcome]
                pendingCatalogMutations[outcome] = nil
                if outcome.committed == true then
                    refreshView()
                elseif retained and retained.operation ~= "publish-imported" then
                    local reason = tostring(outcome.reason or "unknown")
                    local detail = outcome.detail
                    -- A semantic refusal already counted the copies it
                    -- refused: say them, and say which shape was counted.
                    if reason == "SEMANTIC_ENVELOPE" and type(detail) == "table" then
                        local evidence = Nexus and Nexus.LoadoutEvidence
                        local limits = evidence
                            and type(evidence.SemanticLimits) == "function"
                            and evidence.SemanticLimits() or nil
                        reason = string.format(
                            "%s (%s record: %s ordinary, %s locked, %s total Echo copies)",
                            reason, tostring(detail.representation or "unknown"),
                            tostring(detail.ordinary), tostring(detail.locked),
                            tostring(detail.total))
                        if limits then
                            reason = reason .. string.format(
                                "; at most %d ordinary, %d locked, %d total are stored",
                                limits.ordinary, limits.locked, limits.total)
                        end
                        reason = reason .. ". Nothing was saved and the source is unchanged"
                    end
                    local label = tostring(retained
                        and retained.operation or "mutation")
                    notify("Catalog " .. label .. " failed: " .. reason)
                    -- A validation refusal is not a Lua exception, so the
                    -- Errors page never sees it and a support report built
                    -- from errors alone says "no errors recorded" while the
                    -- player is reading this line. Retain the facts that were
                    -- true at THIS boundary, session-only and bounded.
                    local support = Nexus and Nexus.SupportIncidents
                    if support and type(support.Record) == "function" then
                        pcall(support.Record, "catalog-refusal", {
                            reason = tostring(outcome.reason or "unknown"),
                            producer = label,
                            origin = retained and retained.origin or "unknown",
                            operation = label,
                            ticket = outcome.id or outcome.ticketId or nil,
                            build = Nexus.Release and Nexus.Release.buildLabel or nil,
                            representation = type(detail) == "table"
                                and detail.representation or "unknown",
                            counts = type(detail) == "table" and {
                                ordinary=detail.ordinary, locked=detail.locked,
                                total=detail.total} or nil,
                            limits = (Nexus.LoadoutEvidence
                                and type(Nexus.LoadoutEvidence.SemanticLimits) == "function")
                                and Nexus.LoadoutEvidence.SemanticLimits() or nil,
                            readiness = type(detail) == "table" and {
                                generation=detail.generation,
                                semanticGeneration=detail.semanticGeneration,
                                slot=detail.slot} or nil,
                            affected = type(detail) == "table" and detail.affected or nil,
                            committed = false,
                            scope = "this catalog write did not commit; earlier personal or public writes are not covered by this outcome",
                        })
                    end
                end
                if retained and type(retained.onComplete) == "function" then
                    local completed, completeWhy = pcall(
                        retained.onComplete, outcome)
                    if not completed then
                        notify("Catalog completion failed: "
                            .. tostring(completeWhy or "unknown"))
                    end
                end
            end)
        if not bound then
            pendingCatalogMutations[ticket] = nil
            return false, "INVALID_MUTATION_TICKET"
        end
        return nil, why, ticket
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

    -- Every caller names its own operation, so a refusal that reaches the
    -- player identifies the action that produced it instead of a generic put.
    local function SaveBuild(build, onComplete, operation, origin)
        local catalog = Catalog()
        if not (catalog and catalog.Put) then
            return false, "build catalog unavailable"
        end
        local ok, why, ticket = catalog.Put(build)
        return RetainCatalogMutation(catalog, operation or "put", onComplete,
            ok, why, ticket, origin)
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

    local function RemoveOverlay(id, onComplete)
        local catalog = Catalog()
        if catalog and type(catalog.RemoveOverlay) == "function" then
            return RetainCatalogMutation(catalog, "remove-overlay", onComplete,
                catalog.RemoveOverlay(id))
        end
        return false, "build catalog unavailable"
    end

    local function SetTombstone(id, tombstone, options, onComplete)
        local catalog = Catalog()
        if catalog and type(catalog.SetTombstone) == "function" then
            return RetainCatalogMutation(catalog, "set-tombstone", onComplete,
                catalog.SetTombstone(id, tombstone, options))
        end
        return false, "build catalog unavailable"
    end

    -- The catalog's fixed state reason when its root is not serving. A row
    -- reserved deny-only exists but grants no read, mutation, or deletion;
    -- reporting "not found" would misdescribe preserved data.
    local function RootRefusal()
        local catalog = Catalog()
        if not (catalog and type(catalog.RootState) == "function") then
            return "build catalog unavailable"
        end
        local root = catalog.RootState()
        if type(root) ~= "table" or root.state == "ROOT_ADMITTED" then return nil end
        return tostring(root.reason or root.state)
    end

    -- Complete collections are read through the generation-bound record
    -- cursor; every page is a defensive copy and no root-owned table escapes.
    local function Store()
        local catalog = Catalog()
        local out = {}
        if not (catalog and type(catalog.BeginRecordCursor) == "function") then
            return out
        end
        local token = catalog.BeginRecordCursor()
        if not token then return out end
        for _ = 1, 4096 do
            local page, err = catalog.RecordCursorNext(token)
            -- MASTER-RC-018: a cursor error is NOT a clean done. Breaking on
            -- both returned the accumulated prefix as if the collection were
            -- complete, so a mid-walk fault silently produced a short result.
            -- An error now yields the fixed empty result; only page.done ends a
            -- complete walk.
            if err then return {} end
            if type(page) ~= "table" or page.done then break end
            if page.id ~= nil and page.record ~= nil then
                out[page.id] = page.record
            end
        end
        return out
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
        -- A read-only saved root keeps its filters: this session's filters
        -- live in the Store owner's session-only table, seeded from them.
        local writable = Nexus.MainInternals and Nexus.MainInternals.WritableRootV1
        local root = type(writable) == "function"
            and writable(NexusDB, {"buildFilters"}) or NexusDB
        root.buildFilters = type(root.buildFilters) == "table"
            and root.buildFilters or {}
        return root.buildFilters
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

    function M.LockedEchoesForBuild(build, copyAuthorityRequired)
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
        local authorityBuild, currentProvenance = build, nil
        if copyAuthorityRequired == true then
            local related, valid = RelatedBuild(build)
            local catalog = Catalog()
            local current, provenance
            if valid and related and catalog
                and type(catalog.Get) == "function" then
                local loaded, represented, source = pcall(catalog.Get, related.id)
                if loaded and type(represented) == "table"
                    and represented.id ~= nil
                    and type(represented.id) == type(related.id)
                    and tostring(represented.id) == tostring(related.id)
                    and type(related.fingerprint) == "string"
                    and related.fingerprint ~= ""
                    and represented.fingerprint == related.fingerprint then
                    current, provenance = represented, source
                end
            end
            authorityBuild = current
            currentProvenance = provenance
        end
        local ok, result = pcall(resolver.ResolveLocked, {
            build=authorityBuild,dummyRecord=dummy,lkRecord=lk,
            copyAuthorityRequired=copyAuthorityRequired == true,
            currentProvenance=currentProvenance,
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
                        roleSourceValid=live.roleSourceValid,
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
                    local entry = {
                        slot=candidate.slot,name=candidate.name,
                        count=candidate.count,echoes=candidate.echoes,
                        active=candidate.active,sourceKind="Wishlist",
                    }
                    -- A plan without a server slot is its own source. Its
                    -- design is copied as it is: false (cannot be read) must
                    -- stay false so that the Share refuses it.
                    if candidate.slot == nil and candidate.designTargets ~= nil then
                        entry.designTargets = candidate.designTargets
                    end
                    out[#out + 1] = entry
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

    -- Startup owns enumeration and continuation. This operation consumes one
    -- detached row, never a complete defensive-copy collection.
    function M.RemoveLegacyBuilds(id, onComplete)
        return RemoveOverlay(id, onComplete)
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
                            and string.format("Assigned Wishlist: %s - target progress (%d/%d).", destinationName, progress, destinationTotal)
                            or "No Wishlist assigned yet."),
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
                local completionBefore
                savedImportStats.catalogPuts = savedImportStats.catalogPuts + 1
                local saved, saveWhy, ticket = SaveBuild(record,
                    function(outcome)
                        if job.pendingCatalog == outcome then
                            job.pendingCatalog = nil
                        end
                        if savedImportJob ~= job then return end
                        RecordCatalogDelta(completionBefore or CatalogStats())
                        if outcome.committed == true then
                            job.changed = job.changed + 1
                            job.unreportedChanged =
                                (job.unreportedChanged or 0) + 1
                            job.buildRevision = BuildRevision()
                            savedImportStats.writes =
                                savedImportStats.writes + 1
                        end
                    end)
                RecordCatalogDelta(catalogBefore)
                completionBefore = CatalogStats()
                if saved then
                    job.changed = job.changed + 1
                    job.buildRevision = BuildRevision()
                    savedImportStats.writes = savedImportStats.writes + 1
                elseif saveWhy == "ROOT_MUTATION_PENDING"
                    and type(ticket) == "table" then
                    job.pendingCatalog = ticket
                end
            end
        end
    end

    local function PumpSavedImport(limit)
        local job = savedImportJob
        if not job then return 0, false end
        if job.pendingCatalog then return 0, true end
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
        local unreported = job.unreportedChanged or 0
        job.unreportedChanged = 0
        local changedBefore, candidates = job.changed, 0
        savedImportStats.pumps = savedImportStats.pumps + 1
        local work = 0
        while work < limit and savedImportJob == job
            and not job.pendingCatalog do
            if job.phase == "slots" then
                if not job.current then
                    local slot = job.keys[job.index]
                    if slot == nil then
                        local catalog = Catalog()
                        local cursor = catalog
                            and type(catalog.BeginSavedMirrorCursor) == "function"
                            and catalog.BeginSavedMirrorCursor(job.me) or nil
                        job.cleanup = {}
                        job.cleanupCursor = cursor
                        job.cleanupIndex = cursor and nil or 1
                        savedImportStats.cleanupEnumerations =
                            savedImportStats.cleanupEnumerations + 1
                        job.phase = "cleanup"
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
            elseif job.cleanupCursor then
                local catalog = Catalog()
                local page, why = catalog.SavedMirrorCursorNext(
                    job.cleanupCursor)
                work = work + 1
                if not page then
                    local restarted
                    job, restarted = RestartSavedImport(job, "cursor")
                    if restarted then
                        savedImportStats.cursorRestarts =
                            savedImportStats.cursorRestarts + 1
                    else
                        return unreported + job.changed - changedBefore, true
                    end
                elseif page.done then
                    job.cleanupCursor = nil
                    job.cleanupIndex = 1
                elseif page.state ~= "COPY_PENDING" then
                    job.cleanup[#job.cleanup + 1] = {
                        id=page.id,record=page.record,
                    }
                    savedImportStats.cleanupCandidates =
                        savedImportStats.cleanupCandidates + 1
                end
            else
                local cleanup = job.cleanup[job.cleanupIndex]
                if cleanup == nil then
                    savedImportStats.completions = savedImportStats.completions + 1
                    savedRelatedCache = job.cacheUpdates
                    savedRelatedCacheRevision = BuildRevision()
                    lastSavedLoadoutImport = GetTime and GetTime()
                        or lastSavedLoadoutImport
                    savedImportJob = nil
                else
                    savedImportStats.cleanupExamined =
                        savedImportStats.cleanupExamined + 1
                    local id, build = cleanup.id, cleanup.record
                    if Identity.SavedMirrorKind(build) == "saved"
                        and Identity.LocalOwnsSavedMirror(build, job.ownerKey)
                        and not job.seen[id] then
                        local removed, removeWhy, ticket = RemoveOverlay(id,
                            function(outcome)
                                if job.pendingCatalog == outcome then
                                    job.pendingCatalog = nil
                                end
                                if savedImportJob ~= job
                                    or not job.pendingCleanup
                                    or job.pendingCleanup.ticket ~= outcome then
                                    return
                                end
                                job.pendingCleanup = nil
                                job.cleanupIndex = job.cleanupIndex + 1
                                if outcome.committed == true then
                                    if selectedId == id then selectedId = nil end
                                    job.changed = job.changed + 1
                                    job.unreportedChanged =
                                        (job.unreportedChanged or 0) + 1
                                    job.buildRevision = BuildRevision()
                                    savedImportStats.writes =
                                        savedImportStats.writes + 1
                                    savedImportStats.cleanupRemovals =
                                        savedImportStats.cleanupRemovals + 1
                                end
                            end)
                        if removed then
                            if selectedId == id then selectedId = nil end
                            job.changed = job.changed + 1
                            job.buildRevision = BuildRevision()
                            savedImportStats.writes = savedImportStats.writes + 1
                            savedImportStats.cleanupRemovals =
                                savedImportStats.cleanupRemovals + 1
                            job.cleanupIndex = job.cleanupIndex + 1
                        elseif removeWhy == "ROOT_MUTATION_PENDING"
                            and type(ticket) == "table" then
                            job.pendingCleanup = {ticket=ticket,id=id}
                            job.pendingCatalog = ticket
                        else
                            job.cleanupIndex = job.cleanupIndex + 1
                        end
                    else
                        job.cleanupIndex = job.cleanupIndex + 1
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
        return unreported + job.changed - changedBefore,
            savedImportJob ~= nil
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
            local writable = Nexus.MainInternals and Nexus.MainInternals.WritableRootV1
            local root = type(NexusDB) == "table" and (type(writable) == "function"
                and writable(NexusDB, {"buildFilters"}) or NexusDB) or nil
            settings = type(root) == "table"
                and type(root.buildFilters) == "table"
                and root.buildFilters or fallbackFilters
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

    local function BroadcastIfPossible(record, sendOptions)
        local sync = Nexus.Sync
        local callback = sync and (sync.BroadcastBuildSummary
            or sync.BroadcastBuild)
        if type(callback) ~= "function" then
            PeerRecord("share_queue", {id=record and record.id,
                outcome="unavailable",reason="sync unavailable"})
            return false, "sync unavailable", nil
        end
        local called, admitted, why, status = pcall(callback, record,
            sendOptions == true and {retryOnFull=true}
                or type(sendOptions) == "table" and sendOptions or nil)
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

    -- One role reading for every Share source. A copy is permanent only when
    -- the source states it: an inline locked flag or the separate lockedEchoes
    -- list. Nothing is read from order, name, totals or current ownership.
    -- Returns ordinary, locked, counts; or nil, message, diagnostic reason.
    local function ShareRoles(wl, rows)
        local evidence = Nexus and Nexus.LoadoutEvidence
        if not (evidence and type(evidence.SemanticEnvelope) == "function"
            and type(evidence.SemanticLimits) == "function") then
            return nil, "Echo role validation is unavailable", "role validator unavailable"
        end
        local label = tostring(wl and wl.name ~= "" and wl.name or "This source")
        if wl.roleSourceValid == false then
            -- The adapter omitted a server row that it could not read. The
            -- remaining rows are not the complete source.
            return nil, label .. " contains a server Echo row that cannot be read, so its copies are not complete. "
                .. "Nothing was shared.", "source mirror incomplete (roleSourceValid=false)"
        end
        local function Whole(value, minimum)
            return type(value) == "number" and value >= minimum
                and value == math.floor(value) and value < math.huge
        end
        -- Every row of a dense list, or nothing: a hole must not hide rows.
        local function Dense(list)
            local count, length = 0, #list
            for index in pairs(list) do
                if type(index) == "number" then
                    if index < 1 or index > length or index ~= math.floor(index) then return false end
                    count = count + 1
                end
            end
            return count == length
        end
        local function Split(list)
            local ordinary, locked, unstated = {}, {}, 0
            if type(list) ~= "table" or not Dense(list) then return nil end
            for _, e in ipairs(list) do
                if type(e) ~= "table" then return nil end
                local stacks = e.stacks
                if stacks == nil then stacks = e.count end
                if stacks == nil then stacks = 1 end
                local copy = {spellId=e.spellId or e.id, quality=e.quality, stacks=stacks}
                if not Whole(copy.spellId, 1) or not Whole(copy.stacks, 1)
                    or (copy.quality ~= nil and not Whole(copy.quality, 0)) then
                    return nil
                end
                if e.locked == true or e.locked == 1 then
                    copy.locked = true
                    locked[#locked + 1] = copy
                elseif e.locked == nil or e.locked == false then
                    if e.locked == nil then unstated = unstated + 1 end
                    ordinary[#ordinary + 1] = copy
                else
                    return nil
                end
            end
            return ordinary, locked, unstated
        end
        local function Population(list)
            local totals, parts = {}, {}
            for _, e in ipairs(list) do
                local k = tostring(e.spellId) .. ":" .. tostring(e.quality or 0)
                totals[k] = (totals[k] or 0) + (tonumber(e.stacks) or 0)
            end
            for k, copies in pairs(totals) do
                parts[#parts + 1] = k .. ":" .. tostring(copies)
            end
            table.sort(parts)
            return table.concat(parts, ",")
        end
        local ordinary, locked, unstated = Split(rows)
        if not ordinary then
            return nil, label .. " contains an Echo row that cannot be read. Nothing was shared.",
                "malformed source row"
        end
        if wl.lockedEchoes ~= nil and type(wl.lockedEchoes) ~= "table" then
            return nil, label .. " states its locked Echoes in a form that cannot be read. Nothing was shared.",
                "malformed permanent list"
        end
        if type(wl.lockedEchoes) == "table" and next(wl.lockedEchoes) ~= nil then
            -- Same row checks as the inline list; every row here is permanent.
            local forced = {}
            for index, e in pairs(wl.lockedEchoes) do
                if type(e) == "table" then
                    local stacks = e.stacks
                    if stacks == nil then stacks = e.count end
                    if stacks == nil then stacks = 1 end
                    forced[index] = {spellId=e.spellId or e.id, quality=e.quality,
                        stacks=stacks, locked=true}
                else
                    forced[index] = e
                end
            end
            local _, separate = Split(forced)
            if not separate then
                return nil, label .. " contains a locked Echo row that cannot be read. Nothing was shared.",
                    "malformed permanent row"
            end
            -- The same permanent population stated twice is counted once. Two
            -- different statements give no exact answer; nothing is guessed.
            if #locked == 0 then
                locked = separate
            elseif Population(locked) ~= Population(separate) then
                return nil, label .. " states its locked Echoes in two lists that do not agree. "
                    .. "Nothing was shared. Save the source again, then share it.",
                    "permanent roles stated twice with different contents"
            end
        end
        -- A Wishlist made in the Wishlist Editor keeps its permanent targets
        -- beside its server copy: the server Wishlist holds only the ordinary
        -- rows, and the plan's permanent design is saved with its local
        -- assignment. The adapter binds that design to exactly one server
        -- Wishlist slot (same rows and same name). For that exact slot the
        -- design supplies the permanent rows, at any ordinary count. Evidence
        -- that exists but does not match the source refuses; nothing is
        -- guessed, and a source without a saved design is unchanged.
        local function IdCopies(list)
            local totals, parts = {}, {}
            for _, e in ipairs(list) do
                local k = tostring(e.spellId)
                totals[k] = (totals[k] or 0) + (tonumber(e.stacks) or 0)
            end
            for k, copies in pairs(totals) do parts[#parts + 1] = k .. ":" .. tostring(copies) end
            table.sort(parts)
            return table.concat(parts, ",")
        end
        -- A quality that both lists state for one Echo ID must agree.
        local function QualitiesAgree(a, b)
            local stated = {}
            for _, e in ipairs(a) do
                if e.quality ~= nil then
                    if stated[e.spellId] ~= nil and stated[e.spellId] ~= e.quality then return false end
                    stated[e.spellId] = e.quality
                end
            end
            for _, e in ipairs(b) do
                if e.quality ~= nil and stated[e.spellId] ~= nil
                    and stated[e.spellId] ~= e.quality then return false end
            end
            return true
        end
        -- The permanent rows of one saved design. nil: the design has no
        -- permanent target (the editor saves an empty design for every plan
        -- without one). false: the design cannot be read.
        local model, catalog, catalogRead
        local function DesignRows(design)
            if type(design) ~= "table" then return false end
            if next(design) == nil then return nil end
            if not catalogRead then
                catalogRead = true
                model = Nexus and Nexus.WishlistModel
                    and type(Nexus.WishlistModel.New) == "function" and Nexus.WishlistModel.New() or nil
                catalog = Adapter.Catalog and Adapter.Catalog() or nil
            end
            local entries = model and type(model.TargetMapEntries) == "function"
                and model.TargetMapEntries(design, catalog) or nil
            if not entries then return false end
            local rows = {}
            for _, target in ipairs(entries) do
                local source = type(target.value) == "table" and type(target.value.rows) == "table"
                    and target.value.rows or nil
                if source then
                    for _, row in ipairs(source) do
                        rows[#rows + 1] = {spellId=row.spellId, quality=row.quality,
                            stacks=row.stacks, locked=true}
                    end
                else
                    rows[#rows + 1] = {spellId=target.spellId,
                        quality=target.row and target.row.quality, stacks=target.copies, locked=true}
                end
            end
            if #rows == 0 then return nil end
            local _, split = Split(rows)
            if not split or #split ~= #rows then return false end
            return split
        end
        local UNREADABLE = "has a saved locked-target plan that cannot be read. "
            .. "Open the Wishlist in the Wishlist Editor and save its locked targets again."
        local function PlanDesign()
            if wl.sourceKind == "Saved Build" then return nil end
            local slot = tonumber(wl.slot)
            if not slot then
                -- A saved plan listed without a server Wishlist (its server
                -- copy is gone or renamed): the plan is the source itself, so
                -- its own design supplies the permanent rows.
                if wl.designTargets == nil then return nil end
                local rows = DesignRows(wl.designTargets)
                if rows == false then return false, UNREADABLE, "saved plan design unreadable" end
                return rows
            end
            if not Adapter or type(Adapter.GetWishlistCandidates) ~= "function" then return nil end
            local okRead, known = pcall(Adapter.GetWishlistCandidates)
            if not okRead or type(known) ~= "table" then
                return false, UNREADABLE, "saved plan design unreadable"
            end
            -- boundKey: the permanent population of the first design bound to
            -- this slot ("" for an empty design). Every bound design must agree.
            local design, unbound, boundSeen, boundKey = nil, false, false, nil
            for _, c in ipairs(known) do
                if type(c) == "table" and c.designTargets ~= nil then
                    local bound = tonumber(c.slot) == slot and c.mirrorUnavailable ~= true
                    local related = bound
                    if bound then boundSeen = true end
                    if not bound and (c.slot == nil or c.mirrorUnavailable == true) then
                        -- A design that no longer binds to one server Wishlist
                        -- (renamed, changed or copied) but has this name or
                        -- these rows may be this source's design.
                        related = tostring(c.name or "") == tostring(wl.name or "")
                            or (type(c.echoes) == "table" and IdCopies(c.echoes) == IdCopies(ordinary))
                    end
                    if related then
                        local rows = DesignRows(c.designTargets)
                        if rows == false then
                            return false, UNREADABLE, "saved plan design unreadable"
                        end
                        if bound then
                            local key = rows and Population(rows) or ""
                            if boundKey ~= nil and boundKey ~= key then
                                return false, "has two saved locked-target plans that do not agree. "
                                    .. "Open the Wishlist in the Wishlist Editor for each loadout that uses it and save the same locked targets.",
                                    "saved plan designs disagree"
                            end
                            boundKey = key
                        end
                        if rows and not bound then
                            unbound = true
                        elseif rows then
                            if type(c.echoes) ~= "table" or IdCopies(c.echoes) ~= IdCopies(ordinary)
                                or not QualitiesAgree(c.echoes, ordinary) then
                                return false, "changed after its saved locked-target plan was made, so the plan does not match it. "
                                    .. "Open the Wishlist in the Wishlist Editor and save it again.",
                                    "saved plan design does not match the source rows"
                            end
                            design = rows
                        end
                    end
                end
            end
            -- A design bound to this exact slot (even an empty one) decides.
            if unbound and not boundSeen then
                return false, "matches a saved locked-target plan, but Nexus cannot tell which server Wishlist that plan belongs to "
                    .. "(it was renamed, changed or copied), so its locked Echoes are not known. "
                    .. "Open the Wishlist in the Wishlist Editor and save it again.",
                    "saved plan design not bound to one server Wishlist"
            end
            return design
        end
        local design, designMessage, designReason = PlanDesign()
        if design == false then
            return nil, label .. " " .. designMessage .. " Nothing was shared.", designReason
        end
        if design then
            if #locked == 0 then
                locked = design
            elseif IdCopies(locked) ~= IdCopies(design) or not QualitiesAgree(locked, design) then
                return nil, label .. " states locked Echoes that differ from its saved locked-target plan. "
                    .. "Nothing was shared. Save the source again, then share it.",
                    "permanent roles differ from the saved plan"
            end
        end
        local limits = evidence.SemanticLimits()
        local function Counts()
            local o = evidence.SemanticEnvelope(ordinary)
            local l = evidence.SemanticEnvelope(locked, {forceLocked=true})
            if o.reason == "malformed" or l.reason == "malformed" then return nil end
            return {ordinary=o.ordinary, locked=l.locked, total=o.ordinary + l.locked}
        end
        local counts = Counts()
        if not counts then
            return nil, label .. " contains an Echo copy count that cannot be read. Nothing was shared.",
                "malformed copy count"
        end
        if #locked == 0 and counts.total > limits.ordinary and counts.total <= limits.total then
            -- No permanent role is stated and the copies cannot all be ordinary.
            -- This includes the server mirror that marks every row false: the
            -- adapter does not take that as role evidence either. Only the
            -- adapter's own read-only evidence (a content-matched role choice or
            -- the exact verified active loadout) may supply the roles.
            local candidate = {slot=wl.slot, name=wl.name, count=#ordinary,
                echoes=ordinary, active=wl.active}
            local resolved, state, _, why
            -- The source menu lists the raw slot mirror. The adapter's candidate
            -- for that same slot already carries the resolved roles, if any.
            local known = wl.slot ~= nil and Adapter
                and type(Adapter.GetWishlistCandidates) == "function"
                and Adapter.GetWishlistCandidates() or {}
            for _, c in ipairs(type(known) == "table" and known or {}) do
                if type(c) == "table" and tonumber(c.slot) == tonumber(wl.slot) then
                    why = c.lockEvidenceReason
                    if type(Adapter.WishlistEvidenceState) == "function"
                        and Adapter.WishlistEvidenceState(c) == "actionable" then
                        resolved, state = c, "actionable"
                    end
                    break
                end
            end
            if not resolved and Adapter
                and type(Adapter.ResolveWishlistEvidence) == "function" then
                local reason
                resolved, state, _, reason = Adapter.ResolveWishlistEvidence(candidate)
                why = reason or why
            end
            local resolvedOrdinary, resolvedLocked, stillUnstated
            if state == "actionable" and type(resolved) == "table"
                and resolved.lockEvidenceStatus == "authoritative" then
                resolvedOrdinary, resolvedLocked, stillUnstated = Split(resolved.echoes)
            end
            local function Ids(list)
                local all = {}
                for _, e in ipairs(list) do all[#all + 1] = {spellId=e.spellId, quality=0, stacks=e.stacks} end
                return Population(all)
            end
            local combined = {}
            for _, e in ipairs(resolvedOrdinary or {}) do combined[#combined + 1] = e end
            for _, e in ipairs(resolvedLocked or {}) do combined[#combined + 1] = e end
            local settled = resolvedOrdinary and stillUnstated == 0
                and #resolvedLocked > 0 and Ids(combined) == Ids(ordinary)
            -- The roles come from the adapter. A quality that the selected
            -- source states for an ID stays the source's own. When the source
            -- states two qualities for one ID, the role evidence must match
            -- that exact ID-and-quality content; otherwise it does not say
            -- which quality the permanent copies have, and nothing is guessed.
            local stated, mixed = {}, false
            for _, e in ipairs(ordinary) do
                if e.quality ~= nil then
                    if stated[e.spellId] ~= nil and stated[e.spellId] ~= e.quality then mixed = true end
                    stated[e.spellId] = e.quality
                end
            end
            local mixedUnmatched = false
            if settled and mixed and Population(combined) ~= Population(ordinary) then
                settled, mixedUnmatched = false, true
                why = "the source states two qualities for one Echo, and the saved role evidence does not match that exact content"
            end
            if not settled then
                -- The message names what is missing and the supported way to
                -- supply it. A count alone does not tell the user what to do.
                local marks = unstated == 0
                    and "The server copy marks all of them as ordinary, which is not role information: "
                    or "It does not say which copies are locked: "
                -- Only the ways that exist for this source. A Saved Build slot has
                -- no role choice in the Wishlist Editor; a mixed-quality source is
                -- not resolved by either way.
                local way
                if mixedUnmatched then
                    way = "Nexus cannot tell which quality the locked copies have. Change the source so that each Echo has one quality, then share again. "
                elseif wl.sourceKind == "Saved Build" then
                    way = "To resolve it, make this Saved Build your active loadout so that Nexus can read its locked Echoes. Then share again. "
                else
                    way = "To resolve it, open this Wishlist in the Wishlist Editor and choose its locked Echoes, "
                        .. "or make the matching Saved Build your active loadout so that Nexus can read its locked Echoes. Then share again. "
                end
                return nil, string.format("%s has %d Echo copies. %sa Share holds at most %d ordinary copies, "
                    .. "so up to %d of them must be locked Echoes, and Nexus must know which. Missing evidence: %s. "
                    .. "%sNothing was shared and the source is unchanged.",
                    label, counts.total, marks, limits.ordinary, limits.locked,
                    tostring(why or "no role choice is saved for this exact content"), way),
                    string.format("roles unresolved (ordinary=%d permanent=%d total=%d): %s",
                        counts.ordinary, counts.locked, counts.total,
                        tostring(why or state or "no role evidence"))
            end
            do
                for _, e in ipairs(combined) do
                    if not mixed and stated[e.spellId] ~= nil then e.quality = stated[e.spellId] end
                end
                ordinary, locked = resolvedOrdinary, resolvedLocked
                counts = Counts()
                if not counts then
                    return nil, label .. " contains an Echo copy count that cannot be read. Nothing was shared.",
                        "malformed copy count"
                end
            end
        end
        if #ordinary == 0 then
            return nil, label .. " has no ordinary Echoes to share.", "no ordinary Echoes"
        end
        if counts.ordinary > limits.ordinary or counts.locked > limits.locked
            or counts.total > limits.total then
            return nil, string.format("%s has %d ordinary and %d locked Echo copies (%d total). "
                .. "A Share holds at most %d ordinary, %d locked and %d total. "
                .. "Nothing was shared and the source is unchanged.",
                label, counts.ordinary, counts.locked, counts.total,
                limits.ordinary, limits.locked, limits.total),
                string.format("SEMANTIC_ENVELOPE ordinary=%d permanent=%d total=%d",
                    counts.ordinary, counts.locked, counts.total)
        end
        return ordinary, locked, counts
    end

    -- Read-only: the role counts that a Share of this source would carry, from
    -- the same role reading as the Share itself. Nothing is saved or sent.
    -- Returns {ordinary, permanent, ordinaryEchoes, lockedEchoes}; or nil and
    -- the message.
    function M.ShareSourceRoles(wl)
        if type(wl) ~= "table" then return nil, "no source selected" end
        local rows = WishlistEchoes(wl)
        if not rows or #rows == 0 then return nil, "the source has no Echoes" end
        local ok, ordinary, locked, counts = pcall(ShareRoles, wl, rows)
        if not ok then return nil, "Echo roles cannot be read" end
        if not ordinary then return nil, locked end
        return {ordinary=counts.ordinary, permanent=counts.locked,
            ordinaryEchoes=ordinary, lockedEchoes=locked}
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
    function M.EnsureDpsBuildForEchoes(echoes, category, record, onComplete)
        local D = Nexus.DpsCapture
        if not (D and D.GetEchoKey) then return nil end
        if type(onComplete) ~= "function" and type(record) == "table"
            and type(record._catalogBuildCompletion) == "function" then
            onComplete = record._catalogBuildCompletion
        end
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
        local function SavedCompletion(id, build, broadcastOnComplete)
            if not broadcastOnComplete
                and type(onComplete) ~= "function" then return nil end
            return function(outcome)
                if outcome.committed == true then
                    if broadcastOnComplete
                        and Identity.VerifiedOwnerKey(build) then
                        BroadcastIfPossible(build)
                    end
                    if type(onComplete) == "function" then
                        onComplete(id, build)
                    end
                else
                    if type(onComplete) == "function" then
                        onComplete(nil, nil, outcome.reason)
                    end
                end
            end
        end
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
                local saved, saveWhy = SaveBuild(explicitExisting,
                    SavedCompletion(explicitId, explicitExisting, true),
                    "saved-build update")
                if not saved then return nil, nil, saveWhy end
                if Identity.VerifiedOwnerKey(explicitExisting) then
                    BroadcastIfPossible(explicitExisting)
                end
            elseif promoteOwner or presentationChanged then
                explicitExisting.lastModified = NextStamp(
                    explicitExisting.lastModified
                        or explicitExisting.postedAt or 0)
                local saved, saveWhy = SaveBuild(explicitExisting,
                    SavedCompletion(explicitId, explicitExisting, true),
                    "saved-build update")
                if not saved then return nil, nil, saveWhy end
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
                local saved, saveWhy = SaveBuild(ownAutoBuild,
                    SavedCompletion(ownAutoId, ownAutoBuild, true),
                    "automatic saved-build capture")
                if not saved then return nil, nil, saveWhy end
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
        local saved, saveWhy = SaveBuild(build,
            SavedCompletion(id, build, true), "saved-build capture",
            playerIsLocal and "local" or (recordOwner and "received" or "unknown"))
        if not saved then return nil, nil, saveWhy end
        if Identity.VerifiedOwnerKey(build) then BroadcastIfPossible(build) end
        return id, build
    end

    function M.PostCurrentWishlist(title, description, selectedWishlist, selectedClass)
        if not (Adapter and Adapter.Wishlist) then return false, "adapter not ready" end
        if pendingShare then
            -- The one retained request keeps its identity; nothing is added.
            local _, text = M.ShareStatusText()
            return false, text or "A Share is already waiting for local saving.", lastShareOutcome
        end
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
                    roleSourceValid = live.roleSourceValid,
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
        -- Roles are settled and the 79/6/85 envelope is checked here, before
        -- anything is accepted or retained. The catalog still validates the
        -- record again when the local write runs.
        local echoes, lockedEchoes, roleCounts = ShareRoles(wl, sourceEchoes)
        if not echoes then
            local message, diagnostic = lockedEchoes, roleCounts
            PeerRecord("share_source", {outcome="rejected", reason=diagnostic})
            return false, message
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
        if #lockedEchoes > 0 then record.lockedEchoes = lockedEchoes end
        local identityOk, identityErr = RefreshBuildIdentity(record)
        if not identityOk then return false, identityErr end
        PeerRecord("share_created", {id=id,class=record.class or "UNKNOWN",
            echoes=record.echoCount or #echoes,outcome="created"})
        local outcome = {
            id=id,class=record.class or "UNKNOWN",
            echoCount=record.echoCount or #echoes,
            title=title,ordinaryCopies=roleCounts.ordinary,
            permanentCopies=roleCounts.locked,
            buildRevision=BuildRevision(),localSaved=false,
            queueAdmitted=false,queueReason=nil,retryPending=false,
            sent=false,sendCompleted=false,peerStored=nil,
            confirmation="unavailable",
        }
        local catalog = Catalog()
        local preparation = catalog and type(catalog.ManualPreparationStatus) == "function"
            and catalog.ManualPreparationStatus() or nil
        local operation = {database=NexusDB,catalog=catalog,owner=localOwner,
            binding=preparation and preparation.binding,submitted=false,finished=false}
        local function SameOwner()
            if operation.database ~= NexusDB or operation.catalog ~= Catalog()
                or operation.owner ~= CurrentVerifiedOwnerKey() then return false end
            if operation.binding ~= nil then
                local current = type(catalog.ManualPreparationStatus) == "function"
                    and catalog.ManualPreparationStatus() or nil
                -- ownerAgrees also includes evidence freshness. A source edit
                -- may change that after the exact local ticket commits; it is
                -- not a change of player/database/catalog binding. Readiness
                -- is checked separately before the one local submission.
                return current and current.binding == operation.binding or false
            end
            return true
        end
        operation.sameOwner = SameOwner
        pendingShare, lastShareOutcome = operation, outcome
        local function CompleteLocalSave(committed, why)
            if operation.finished then return outcome.localSaved end
            operation.finished = true
            if pendingShare == operation then pendingShare = nil end
            outcome.buildRevision = BuildRevision()
            outcome.localSaved = committed == true
            outcome.localPending = false
            outcome.localStage = committed and "saved" or "failed"
            PeerRecord("share_local", {id=id,
                outcome=committed and "saved" or "rejected",
                reason=why,revision=outcome.buildRevision})
            if not committed or not SameOwner() then
                outcome.queueReason = not committed and (why or "local save failed")
                    or "Share stopped: the player or catalog changed."
                lastShareOutcome = outcome
                -- The approved text and source stay available to the form.
                failedShareDraft = not committed and SameOwner() and {id=id,title=title,
                    description=description,wishlist=selectedWishlist,
                    class=selectedClass} or nil
                if operation.notify then notify("Nexus: " .. tostring(select(2, M.ShareStatusText(id)))) end
                refreshView()
                return false
            end
            failedShareDraft = nil
            local admitted, queueWhy, syncStatus = BroadcastIfPossible(record, true)
            for key, value in pairs(type(syncStatus) == "table"
                and syncStatus or {}) do
                local kind = type(value)
                if kind == "string" or kind == "number"
                    or kind == "boolean" then outcome[key] = value end
            end
            outcome.id = id
            outcome.class = record.class or "UNKNOWN"
            outcome.echoCount = record.echoCount or #echoes
            outcome.buildRevision = BuildRevision()
            outcome.localSaved = true
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
                reason=outcome.queueReason,revision=outcome.buildRevision})
            local D = Nexus.DpsCapture
            if D and D.BroadcastBestForBuild then
                pcall(D.BroadcastBestForBuild, id)
            end
            if operation.notify then notify("Nexus: " .. tostring(select(2, M.ShareStatusText(id)))) end
            refreshView()
            return true
        end
        operation.complete = CompleteLocalSave
        operation.submit = function()
            -- One submission of this immutable record. A rejection is terminal;
            -- a retained ticket owns settlement. Neither path retries Put.
            operation.submitted = true
            local saved, saveWhy = SaveBuild(record, function(ticket)
                CompleteLocalSave(ticket.committed == true,
                    ticket.committed == true and ticket.storedAs or ticket.reason)
            end, "Share local save")
            if operation.finished then
                return outcome.localSaved, outcome.localSaved and id or outcome.queueReason, outcome
            end
            if saved == nil and saveWhy == "ROOT_MUTATION_PENDING" then
                operation.notify = true
                outcome.localPending, outcome.localStage = true, "saving"
                outcome.queueReason = saveWhy
                PeerRecord("share_local", {id=id,outcome="pending",
                    reason=saveWhy,revision=outcome.buildRevision})
                return true, id, outcome
            end
            CompleteLocalSave(saved == true, saveWhy or "local save failed")
            return saved == true, saved and id or outcome.queueReason, outcome
        end
        if preparation and preparation.ownerAgrees == true
            and preparation.relevant == true and not preparation.ready
            and localOwner ~= nil then
            -- Retain one explicit Share intent behind existing incoming work.
            -- The lifecycle submits it at the next ordinary admitted boundary.
            operation.notify = true
            outcome.localPending, outcome.localStage = true, "waiting-catalog"
            outcome.queueReason = "ROOT_MUTATION_PENDING"
            PeerRecord("share_local", {id=id,outcome="waiting",
                reason=outcome.queueReason,revision=outcome.buildRevision})
            return true, id, outcome
        end
        return operation.submit()
    end

    -- The lifecycle gives a waiting removal the same ordinary admission turn
    -- as a waiting Share. Scope, ownership and the approved revision are
    -- rechecked first; a change is a terminal refusal, never a later submit.
    local function PumpPendingRemoval()
        local operation = pendingRemovals[1]
        if not operation then return false, false end
        local outcome = operation.outcome
        local function Refuse(reason)
            table.remove(pendingRemovals, 1)
            outcome.localPending, outcome.localStage = false, "failed"
            outcome.storageReason, outcome.queueReason = reason, reason
            if operation.onComplete then operation.onComplete(false, outcome) end
            refreshView()
            return #pendingRemovals > 0, false
        end
        local catalog = operation.catalog
        local preparation = type(catalog.ManualPreparationStatus) == "function"
            and catalog.ManualPreparationStatus() or nil
        if operation.database ~= NexusDB or catalog ~= Catalog()
            or operation.owner ~= CurrentVerifiedOwnerKey()
            or not preparation or preparation.binding ~= operation.binding then
            return Refuse("the player or catalog changed after approval")
        end
        if preparation.ready ~= true then return true, false end
        local build = LoadBuild(operation.id)
        if not build or not IsOwnBuild(build)
            or Identity.SavedMirrorKind(build) == "saved"
            or (tonumber(build.lastModified) or tonumber(build.postedAt) or 0)
                ~= operation.revision then
            return Refuse("the shared build changed after approval")
        end
        table.remove(pendingRemovals, 1)
        outcome.localPending, outcome.localStage, outcome.storageReason = false, "submitted", nil
        local ok, result = M._SubmitRemoval(operation.id, build, true, outcome,
            operation.onComplete)
        if not (type(result) == "table" and result.localPending) then
            -- Settled without a retained ticket: report it once, as returned.
            if operation.onComplete then operation.onComplete(ok, result) end
            refreshView()
        end
        return #pendingRemovals > 0, true
    end

    function M.PumpPendingShare()
        local operation = pendingShare
        if not operation then return PumpPendingRemoval() end
        if operation.submitted then return true, false end
        if not operation.sameOwner() then
            operation.complete(false, "Share stopped: the player or catalog changed.")
            return false, false
        end
        local catalog = operation.catalog
        local preparation = type(catalog.ManualPreparationStatus) == "function"
            and catalog.ManualPreparationStatus() or nil
        if not preparation or preparation.ready ~= true then return true, false end
        operation.submit()
        return pendingShare ~= nil, true
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
        -- Sync answers an unknown ID with its latest Share of any build. Only
        -- the operation of this exact build may describe this build.
        if type(remote) == "table" and tostring(remote.id) == tostring(current.id) then
            for key, value in pairs(remote) do copy[key] = value end
        end
        copy.peerStored = nil
        copy.confirmation = "unavailable"
        return copy
    end

    -- One truthful sentence for the latest Share, read from the existing
    -- outcome and the existing Sync operation status. It states no timing and
    -- no percentage, and never calls retained work failed. Returns state, text.
    function M.ShareStatusText(id)
        local s = M.ShareStatus(id)
        if not s then return nil end
        local name = type(s.title) == "string" and s.title ~= ""
            and ("\"" .. s.title .. "\"") or "this build"
        if s.localPending then
            -- Two different waits: the record is not yet submitted, or the one
            -- submitted local write is not yet settled. Neither can be cancelled
            -- safely from here, and neither needs a second Share.
            return "preparing", "Preparing " .. name .. " to share — not sent yet. "
                .. (s.localStage == "saving"
                    and "The local save is submitted; the catalog has not finished it. "
                    or "The local catalog is finishing earlier work first. ")
                .. "The same request continues by itself. Do not share it again."
                .. (function()
                    -- A saved Off mode is stated now, not only at the refusal.
                    local policy = Nexus and Nexus.SyncModePolicy
                    if policy and type(policy.Mode) == "function" and policy.Mode() == "off" then
                        return " Your saved Sync mode is Off: it will be saved locally and not sent."
                    end
                    return ""
                end)()
        end
        if s.localSaved ~= true then
            local why = tostring(s.queueReason or "local save failed")
            local evidence = Nexus and Nexus.LoadoutEvidence
            local limits = evidence and type(evidence.SemanticLimits) == "function"
                and evidence.SemanticLimits() or nil
            if why == "SEMANTIC_ENVELOPE" and limits then
                why = string.format("the local catalog refused %d ordinary and %d locked Echo copies; "
                    .. "a Share holds at most %d ordinary, %d locked and %d total",
                    tonumber(s.ordinaryCopies) or 0, tonumber(s.permanentCopies) or 0,
                    limits.ordinary, limits.locked, limits.total)
            end
            -- The draft statement is made only when the form really has it.
            local kept = failedShareDraft and failedShareDraft.id == s.id
            return "refused", "Not shared: " .. name .. " — " .. why:gsub("%.+$", "")
                .. ". Nothing was saved or sent."
                .. (kept and " The Share form keeps the title, description and source." or "")
        end
        if s.sendCompleted == true then
            return "sent", "Sent " .. name .. " — peer receipt not confirmed."
        end
        if s.terminal == true then
            local why = tostring(s.outcome or "stopped")
            if type(s.reason) == "string" and s.reason ~= "" and s.reason ~= "none"
                and s.reason ~= why then
                why = why .. " (" .. s.reason .. ")"
            end
            local retryable = M.CanRetryShare(s.id)
            return "stopped", "Saved " .. name .. " locally — not sent: " .. why
                .. (retryable and ". Open the build to use Retry Share." or ".")
        end
        if s.retryPending == true then
            return "queued", "Saved " .. name .. " locally — the Sync queue is full. One bounded retry is pending."
        end
        if s.queueAdmitted == true then
            return "queued", "Saved " .. name .. " locally — queued for sharing."
        end
        return "saved", "Saved " .. name .. " locally — not queued: "
            .. tostring(s.queueReason or "Sync unavailable"):gsub("%.+$", "") .. "."
    end

    -- The approved draft of a Share whose local save failed, for the form.
    function M.FailedShareDraft()
        local draft = failedShareDraft
        if not draft or type(lastShareOutcome) ~= "table"
            or lastShareOutcome.id ~= draft.id then return nil end
        return draft.title, draft.description, draft.wishlist, draft.class
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
        -- A refusal that depends on the record itself repeats on every retry.
        if outcome == "rejected" and tostring(status.reason or ""):find("too large", 1, true) then
            return false, "the record is too large to send; a retry cannot change that"
        end
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
        outcome.title = type(record.title) == "string" and record.title or nil
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
        if not pendingShare then lastShareOutcome = outcome end
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
        local summary = {dummy=0,lk=0,best=0,average=0,count=0}
        if not (dps and build) then return summary end
        local savedKind = Identity.SavedMirrorKind(build)
        local related, valid = RelatedBuild(build)
        if savedKind ~= "ordinary" and not valid then return summary end
        if type(related) ~= "table"
            or type(related.fingerprint) ~= "string"
            or type(dps.GetCommunityQualification) ~= "function" then
            return summary
        end
        local ok, accepted = pcall(
            dps.GetCommunityQualification, related.fingerprint)
        if not ok or type(accepted) ~= "table" then return summary end
        local dummy, lk = tonumber(accepted.dummy) or 0,
            tonumber(accepted.lk) or 0
        if dummy ~= dummy or dummy == math.huge or dummy == -math.huge
            or dummy < 0 then dummy = 0 end
        if lk ~= lk or lk == math.huge or lk == -math.huge
            or lk < 0 then lk = 0 end
        local average = tonumber(accepted.average) or 0
        if average ~= average or average == math.huge
            or average == -math.huge or average < 0 then average = 0 end
        return {dummy=dummy,lk=lk,best=math.max(dummy,lk),average=average,
            count=(dummy > 0 and 1 or 0) + (lk > 0 and 1 or 0)}
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

    local function RepairedIdentity(build)
        if type(build.echoes) ~= "table" or #build.echoes == 0 then return nil end
        local candidate = ShallowCopy(build)
        if RefreshBuildIdentity(candidate)
            and (build.fingerprint ~= candidate.fingerprint
                or build.fingerprintHash ~= candidate.fingerprintHash
                or build.echoCount ~= candidate.echoCount
                or build.loadoutAvailable ~= candidate.loadoutAvailable
                or build.needsFullBuild ~= candidate.needsFullBuild) then
            return candidate
        end
    end

    function M.RepairOverlayIdentities(candidate, onComplete)
        return SaveBuild(candidate, onComplete, "overlay identity repair")
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

    function M.PublishImportedBuild(id, onComplete)
        local prior = pendingPublications[id]
        if prior then
            if prior.state == "pending" then
                if not prior.onComplete and type(onComplete) == "function" then
                    prior.onComplete = onComplete
                end
                return nil, "ROOT_MUTATION_PENDING", prior.ticket
            end
            pendingPublications[id] = nil
            -- Existing polling callers consume the terminal receipt. A renderer
            -- that already received its callback starts a new explicit update.
            if type(onComplete) ~= "function" then return prior.ok, prior.value end
        end
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
        source.publishedBuildId = publishedId
        source.recordBuildId = publishedId
        source.lastPublishedAt = stamp
        local operation = {state="pending",ok=nil,value=nil,finalized=false}
        local function Finish(ok, value)
            if operation.finalized then return end
            operation.finalized = true
            operation.state, operation.ok, operation.value = "complete", ok,
                value
            if ok then
                BroadcastIfPossible(record)
                local D = Nexus.DpsCapture
                if D and D.BroadcastBestForBuild then
                    pcall(D.BroadcastBestForBuild, publishedId)
                end
            end
            if operation.onComplete then
                operation.onComplete(ok, value, operation.ticket)
            end
        end
        local catalog = Catalog()
        if not (catalog and type(catalog.BeginCatalogMaintenance) == "function"
            and type(catalog.MaintenanceReplaceRow) == "function"
            and type(catalog.CommitMaintenance) == "function") then
            Finish(false, "build catalog unavailable")
            return false, operation.value
        end
        local handle, beginWhy = catalog.BeginCatalogMaintenance({
            database=catalog.BoundDatabase and catalog.BoundDatabase() or NexusDB,
            operation="publish-imported"})
        if not handle then
            Finish(false, beginWhy or "catalog maintenance unavailable")
            return false, operation.value
        end
        local recordStaged, recordWhy = catalog.MaintenanceReplaceRow(
            handle, publishedId, record, {allowInsert=true})
        if not recordStaged then
            catalog.CancelMaintenance(handle)
            Finish(false, recordWhy or "build storage refused")
            return false, operation.value
        end
        local sourceStaged, sourceWhy = catalog.MaintenanceReplaceRow(
            handle, id, source)
        if not sourceStaged then
            catalog.CancelMaintenance(handle)
            Finish(false, sourceWhy or "saved-loadout storage refused")
            return false, operation.value
        end
        local committed, commitWhy, ticket = RetainCatalogMutation(
            catalog, "publish-imported", function(outcome)
                if outcome.committed == true then
                    Finish(true, publishedId)
                else
                    Finish(false, outcome.reason or "build storage refused")
                end
            end, catalog.CommitMaintenance(handle))
        if committed then
            Finish(true, publishedId)
            return true, publishedId
        end
        if commitWhy == "ROOT_MUTATION_PENDING" and type(ticket) == "table" then
            operation.ticket = ticket
            operation.onComplete = type(onComplete) == "function" and onComplete or nil
            pendingPublications[id] = operation
            return nil, commitWhy, ticket
        end
        Finish(false, commitWhy or "build storage refused")
        return false, operation.value
    end

    function M.EditBuild(id, title, description, discordLink)
        local b = LoadBuild(id)
        if not b then return false, "not found" end
        if not IsOwnBuild(b) then return false, "not your build" end
        local catalog, database, owner = Catalog(), NexusDB, CurrentVerifiedOwnerKey()
        local preparation = catalog and type(catalog.ManualPreparationStatus) == "function"
            and catalog.ManualPreparationStatus() or nil
        local binding = preparation and preparation.binding

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
        local outcome = {id=b.id,localSaved=false,localPending=false,queueAdmitted=false,
            sent=false,sendCompleted=false,confirmation="unavailable"}
        local finished = false
        local function Complete(committed, why)
            if finished then return end
            finished, outcome.localPending, outcome.localSaved = true, false, committed == true
            if not committed then
                outcome.message = "Build update failed: " .. tostring(why or "storage refused")
                return
            end
            outcome.message = "Build details saved locally."
            if savedKind ~= "ordinary" then return end
            local current = catalog and type(catalog.ManualPreparationStatus) == "function"
                and catalog.ManualPreparationStatus() or nil
            if database ~= NexusDB or catalog ~= Catalog() or owner ~= CurrentVerifiedOwnerKey()
                or binding ~= nil and (not current or binding ~= current.binding) then
                outcome.queueReason = "player or catalog changed"
            else
                -- Track this explicit same-ID approval without a queue-full
                -- retry. Its immutable summary uses the existing Share owner.
                local admitted, reason = BroadcastIfPossible(b, {explicit=true})
                outcome.queueAdmitted, outcome.queueReason = admitted == true, reason
            end
            outcome.message = outcome.queueAdmitted
                and "Build details saved locally and queued. Peer storage confirmation is unavailable."
                or "Build details saved locally; not queued: " .. tostring(outcome.queueReason)
        end
        local saved, saveWhy, ticket = SaveBuild(b, function(terminal)
            Complete(terminal.committed == true, terminal.reason)
            if terminal.committed == true then notify(outcome.message) end
        end, "build details edit")
        if saved == nil and saveWhy == "ROOT_MUTATION_PENDING" and type(ticket) == "table" then
            -- Accepted and retained: the edit is one retained catalog
            -- mutation whose terminal ticket settles it; the reason lets a
            -- caller distinguish the retained state from a completed save.
            outcome.localPending = true
            outcome.message = "Build update accepted. Waiting to save locally; nothing has been sent."
            return true, saveWhy, outcome
        end
        if not saved then return false, saveWhy or "build storage refused" end
        -- Editing a server Saved Build mirror is local-only. It reaches the
        -- community only through the explicit Upload Build action (or a DPS
        -- record path handled by DpsCapture).
        Complete(true)
        return true, nil, outcome
    end

    function M.UpdateFromWishlist(id)
        local b = LoadBuild(id)
        if not b then return false, "not found" end
        if not IsOwnBuild(b) then return false, "not your build" end
        if Identity.SavedMirrorKind(b) == "saved" then
            return false, "saved loadouts update from the server; edit the server loadout itself to change its Echoes"
        end
        if HasLeaderboardRecord(b) then
            return false, "this Echo list is read-only because a DPS record is attached; share a new build for different Echoes"
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
        local candidate = ShallowCopy(b)
        candidate.echoes = echoes
        local identityOk, identityErr = RefreshBuildIdentity(candidate)
        if not identityOk then return false, identityErr end
        candidate.lastModified = NextStamp(b.lastModified or b.postedAt)
        local function Published()
            BroadcastIfPossible(candidate)
            local D = Nexus.DpsCapture
            if D and D.BroadcastBestForBuild then
                pcall(D.BroadcastBestForBuild, id)
            end
        end
        local saved, saveWhy = SaveBuild(candidate, function(ticket)
            -- A retained replacement broadcasts only from its terminal
            -- committed ticket.
            if ticket.committed == true then Published() end
        end)
        if saved == nil and saveWhy == "ROOT_MUTATION_PENDING" then
            -- Accepted and retained; the reason marks the retained state.
            return true, #echoes, saveWhy
        end
        if not saved then return false, saveWhy or "build storage refused" end
        Published()
        return true, #echoes
    end

    function M.DeleteBuild(id, onComplete)
        local b = LoadBuild(id)
        if not b then
            local refusal = RootRefusal()
            if refusal then
                -- Bounded refusal receipt: nothing was removed, nothing queued.
                return false, {
                    localRemoved=false, queueAdmitted=false, retryPending=false,
                    storageReason=refusal, queueReason=refusal,
                }
            end
            return false, "not found"
        end
        local owner = IsOwnBuild(b)
        if not owner and not IsAdmin() then
            return false, "not your build"
        end
        if Identity.SavedMirrorKind(b) == "saved" then
            return false, "server Saved Builds cannot be deleted here"
        end
        local outcome = {
            localRemoved=false,localPending=false,queueAdmitted=false,retryPending=false,
        }
        if owner then
            for _, waiting in ipairs(pendingRemovals) do
                -- The one retained approval already owns this exact ID.
                if waiting.id == id then return true, waiting.outcome end
            end
            local catalog = Catalog()
            local preparation = catalog and type(catalog.ManualPreparationStatus) == "function"
                and catalog.ManualPreparationStatus() or nil
            if preparation and preparation.ownerAgrees == true
                and preparation.relevant == true and not preparation.ready
                and CurrentVerifiedOwnerKey() ~= nil
                and #pendingRemovals < MAX_PENDING_REMOVALS then
                -- Retain one explicit Stop Sharing approval behind existing
                -- catalog work, as Share does. Nothing is removed or sent yet.
                outcome.localPending, outcome.localStage = true, "waiting-catalog"
                outcome.storageReason = "ROOT_MUTATION_PENDING"
                pendingRemovals[#pendingRemovals + 1] = {
                    id=id,revision=tonumber(b.lastModified) or tonumber(b.postedAt) or 0,
                    database=NexusDB,catalog=catalog,owner=CurrentVerifiedOwnerKey(),
                    binding=preparation.binding,outcome=outcome,
                    onComplete=type(onComplete) == "function" and onComplete or nil,
                }
                return true, outcome
            end
        end
        return M._SubmitRemoval(id, b, owner, outcome, onComplete)
    end

    -- One submission of an approved removal. A refusal here is terminal; a
    -- retained ticket owns settlement. Neither path submits again.
    function M._SubmitRemoval(id, b, owner, outcome, onComplete)
        local function CompleteRemoval()
            if outcome.localRemoved and selectedId == id then selectedId = nil end
            if type(onComplete) == "function" then onComplete(outcome.localRemoved, outcome) end
            refreshView()
        end
        local function SyncRemoval(receipt)
            for _, key in ipairs({"localRemoved","localPending","storageReason",
                "queueAdmitted","retryPending","queueReason"}) do
                outcome[key] = receipt[key]
            end
        end
        if owner then
            local sync = Nexus and Nexus.Sync
            if sync and type(sync.BroadcastDelete) == "function" then
                local called, queued, why, _, removal = pcall(sync.BroadcastDelete, b,
                    function(receipt)
                        SyncRemoval(receipt)
                        CompleteRemoval()
                    end)
                if called then
                    if type(removal) == "table" then
                        SyncRemoval(removal)
                        if outcome.localPending or outcome.localRemoved then
                            if outcome.localRemoved and selectedId == id then selectedId = nil end
                            return true, outcome
                        end
                    end
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
            }, {source="local"}, function(terminal)
                -- The retained row-to-tombstone transaction settles the local
                -- removal exactly once from its terminal committed ticket.
                outcome.localPending = false
                if terminal.committed == true then
                    if selectedId == id then selectedId = nil end
                    outcome.localRemoved = true
                    outcome.storageReason = nil
                else
                    outcome.storageReason = tostring(terminal.reason
                        or "local build removal refused")
                    outcome.queueReason = outcome.queueReason
                        or outcome.storageReason
                end
                CompleteRemoval()
            end)
            if tombstoned == nil and tombstoneWhy == "ROOT_MUTATION_PENDING" then
                -- Accepted and retained: the same outcome table reports
                -- localRemoved=false with this storage reason until the
                -- terminal ticket above settles it.
                outcome.storageReason = tombstoneWhy
                outcome.localPending = true
                return true, outcome
            end
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
            local displayTitle = Identity.DisplaySafeText(
                tostring(title or ""), 1024, false) or "this build"
            notify("|cff4dff80Nexus:|r locked in '"..displayTitle.."'.")
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
        local ok, err, outcome = M.EditBuild(
            draft.id, draft.title, draft.description, draft.link)
        if ok then editDraft = nil end
        return ok, err, outcome
    end

    function M.Initialize(adapter, bundledBuilds,updateStarted,maxUnits)
        Adapter = adapter
        local catalog = Catalog()
        local database = NexusDB
        local function Result(job)
            local phase=job.pending and "commit" or job.phase
            local list=phase=="legacy" and job.removals or phase=="identities" and job.repairs
            local done,total
            if list then done,total=math.min(#list,math.max(0,job.index-1)),#list
            elseif phase=="scan" and job.cursor and catalog
                and type(catalog.RecordCursorProgress)=="function" then
                -- The cursor's own position; no second pass sizes the scan.
                done,total=catalog.RecordCursorProgress(job.cursor)
            end
            return {state=job.state,reason=job.reason,phase=phase,
                mutationTicket=job.pending,recordsSeen=job.scanned or 0,
                progressDone=done,progressTotal=total}
        end
        if not (catalog and catalog.BeginRecordCursor and catalog.RootState) then
            return {state="failed",reason="COMMUNITY_CATALOG_UNAVAILABLE"}
        end
        if not startupJob or startupJob.database ~= database
            or startupJob.catalog ~= catalog or startupJob.bundle ~= bundledBuilds then
            -- A previous callback may still settle, but cannot resume this job.
            if startupJob and startupJob.maintenance then
                startupJob.catalog.CancelMaintenance(startupJob.maintenance)
            end
            startupJob = {database=database,catalog=catalog,bundle=bundledBuilds,
                state="pending",phase="scan",removals={},repairs={},index=1,
                batchIdentities=true}
            catalog.Init(type(database)=="table" and database or {},bundledBuilds)
        end
        local job = startupJob
        local function Fail(why)
            if job.maintenance then
                catalog.CancelMaintenance(job.maintenance)
                job.maintenance=nil
            end
            job.state,job.reason="failed",why or "COMMUNITY_STARTUP_FAILED"
            job.cursor,job.removals,job.repairs=nil,nil,nil
            return Result(job)
        end
        if job.state ~= "pending" then return Result(job) end
        local root = catalog.RootState()
        if job.pending then return Result(job) end
        if root.state ~= "ROOT_ADMITTED" then
            return Fail(root.reason or root.state)
        end
        if root.candidate then return Result(job) end
        if job.generation and (root.generation ~= job.generation
            or root.servingGeneration ~= job.servingGeneration) then
            if job.maintenance then catalog.CancelMaintenance(job.maintenance) end
            -- Local features are now available during background preparation.
            -- Restart an invalidated read cursor on the new committed root;
            -- never publish the old scan or hold local controls in failure.
            startupJob=nil
            return {state="pending",phase="source-changed"}
        end
        job.generation,job.servingGeneration=root.generation,root.servingGeneration
        -- A read-only saved root is served as it was saved: the start-up
        -- placeholder removal and identity repair below are writes, so they do
        -- not run for it (the catalog would refuse them).
        local readOnlyRoot=Nexus.MainInternals and Nexus.MainInternals.SavedRootReadOnlyV1
        if job.phase=="scan" and not job.cursor and type(readOnlyRoot)=="function"
            and readOnlyRoot(job.database) then
            job.state,job.phase="ready","complete"
            job.removals,job.repairs=nil,nil
            return Result(job)
        end

        local function Clock()
            if type(debugprofilestop) ~= "function" then return nil end
            local ok,value=pcall(debugprofilestop)
            if ok and type(value)=="number" and value==value
                and value>=0 and value<math.huge then return value end
        end
        local started=updateStarted or Clock()
        local units=math.max(0,math.min(32,tonumber(maxUnits) or 32))
        for unit=1,units do
            local before=Clock()
            if started and before and before>=started and before-started>=2 then
                return Result(job)
            end
            if job.phase=="scan" then
                if not job.cursor then
                    local token,why=catalog.BeginRecordCursor()
                    if not token then return Fail(why) end
                    job.cursor=token
                end
                local page,why=catalog.RecordCursorNext(job.cursor)
                if why or type(page)~="table" then return Fail(why) end
                if page.done then
                    job.cursor=nil
                    job.phase="legacy"
                elseif page.record then
                    job.scanned=(job.scanned or 0)+1
                    local build=page.record
                    if tostring(build.author or ""):lower()=="wr team" then
                        job.removals[#job.removals+1]=page.id
                    elseif page.source=="overlay" then
                        local candidate=RepairedIdentity(build)
                        if candidate then
                            job.repairs[#job.repairs+1]=candidate
                            -- Put owns baseline-equivalence and reservation
                            -- semantics. Keep that existing route if any row
                            -- cannot use an identity-only overlay transaction.
                            if not (catalog.BeginCatalogMaintenance
                                and catalog.MaintenanceReplaceRow and catalog.CommitMaintenance
                                and catalog.HasBaseline and catalog.BarrierState
                                and catalog.TombstoneState)
                                or catalog.HasBaseline(page.id)
                                or catalog.BarrierState(page.id).state~="BARRIER_NONE"
                                or catalog.TombstoneState(page.id).state~="NONE" then
                                job.batchIdentities=false
                            end
                        end
                    end
                end
            elseif job.phase=="identities" and job.batchIdentities and #job.repairs>0 then
                if not job.maintenance then
                    local handle,why=catalog.BeginCatalogMaintenance({
                        database=job.database,operation="community-startup-identities"})
                    if not handle and why=="MAINTENANCE_ACTIVE" then
                        -- Standalone Store callers may already have an open
                        -- background owner. Preserve the prior Put route and
                        -- its existing arbitration, never steal its handle.
                        job.batchIdentities=false
                        return Result(job)
                    end
                    if not handle then return Fail(why) end
                    job.maintenance=handle
                end
                local item=job.repairs[job.index]
                if item then
                    -- One admitted row is staged per work unit, never the
                    -- entire collection in a single callback. The catalog
                    -- preserves durable unknown fields and verifies ownership.
                    local ok,why=catalog.MaintenanceReplaceRow(job.maintenance,item.id,item)
                    if not ok then return Fail(why) end
                    job.index=job.index+1
                else
                    local function Complete(outcome)
                        if startupJob~=job then return end
                        job.pending=nil
                        if not outcome.committed then Fail(outcome.reason);return end
                        job.state,job.phase="ready","complete"
                        job.removals,job.repairs=nil,nil
                    end
                    local handle=job.maintenance
                    local ok,why,ticket=RetainCatalogMutation(catalog,
                        "startup-identities",Complete,catalog.CommitMaintenance(handle))
                    job.maintenance=nil
                    if ok==nil and why=="ROOT_MUTATION_PENDING" then
                        job.pending=ticket
                        return Result(job)
                    end
                    if not ok then return Fail(why) end
                    Complete({committed=true})
                    return Result(job)
                end
            else
                local list=job.phase=="legacy" and job.removals or job.repairs
                local item=list[job.index]
                if item==nil then
                    if job.phase=="legacy" then
                        job.phase,job.index="identities",1
                    else
                        job.state,job.phase="ready","complete"
                        job.removals,job.repairs=nil,nil
                        return Result(job)
                    end
                else
                    local removing=job.phase=="legacy"
                    local function Complete(outcome)
                        if startupJob~=job then return end
                        job.pending=nil
                        if not outcome.committed then
                            Fail(outcome.reason)
                            return
                        end
                        if removing and selectedId==item then selectedId=nil end
                        local current=catalog.RootState()
                        job.generation,job.servingGeneration=
                            current.generation,current.servingGeneration
                        job.index=job.index+1
                    end
                    local ok,why,ticket
                    if removing then ok,why,ticket=M.RemoveLegacyBuilds(item,Complete)
                    else ok,why,ticket=M.RepairOverlayIdentities(item,Complete) end
                    if ok==nil and why=="ROOT_MUTATION_PENDING" then
                        job.pending=ticket
                        return Result(job)
                    end
                    -- No overlay beneath an immutable legacy bundled row is
                    -- a normal no-op, not a failed required removal.
                    if not ok and not (removing and why==nil) then return Fail(why) end
                    if removing and ok and selectedId==item then selectedId=nil end
                    local current=catalog.RootState()
                    job.generation,job.servingGeneration=
                        current.generation,current.servingGeneration
                    job.index=job.index+1
                end
            end
            local finished=Clock()
            if not started or not finished or finished<started
                or finished-started>=2 then break end
        end
        return Result(job)
    end

    return M
end

Nexus.CommunityInternals.Controller = Controller
