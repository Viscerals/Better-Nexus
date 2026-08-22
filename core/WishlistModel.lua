-- Nexus: core/WishlistModel.lua
-- Pure Wishlist draft, budget, canonicalization, and lock-plan calculations.

Nexus = Nexus or {}

local Factory = {}
Nexus.WishlistModel = Factory

local MAX_WISHLIST_ECHOES = 79
local MAX_LOCK_SLOTS = 6
local TARGET_ENVELOPE_MARKER = "__nexusTargetEnvelope"

local function CopyEntry(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, field in pairs(value) do out[key] = field end
    return out
end

local function CopyMap(value)
    local out = {}
    for key, field in pairs(type(value) == "table" and value or {}) do
        out[key] = CopyEntry(field)
    end
    return out
end

local function CountMap(value)
    local count = 0
    for _ in pairs(type(value) == "table" and value or {}) do
        count = count + 1
    end
    return count
end

local function PositiveInteger(value)
    value = tonumber(value)
    if not value or value ~= value or value <= 0 or value >= math.huge
        or value ~= math.floor(value) then return nil end
    return value
end

local function NonNegativeInteger(value)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value >= math.huge
        or value ~= math.floor(value) then return nil end
    return value
end

local function NormalizeEchoName(name)
    name = tostring(name or ""):lower()
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return name
end

local function Family(spellId, catalog)
    spellId = tonumber(spellId)
    local row = catalog and catalog.rows and catalog.rows[spellId]
    local nameKey = row and NormalizeEchoName(row.name) or ""
    if nameKey ~= "" then
        local groupId = tonumber(row and row.groupId) or 0
        if groupId > 0 then return "ng:" .. nameKey .. ":" .. tostring(groupId) end
        return "n:" .. nameKey
    end
    return "s:" .. tostring(spellId or 0)
end

local function TargetCopies(value, expectedSpellId)
    -- Legacy booleans/numbers represent one exact copy (numbers optionally
    -- name the replacement).  Counted table records are persisted authority,
    -- so unknown or internally inconsistent contracts must fail closed.
    local expectedId
    if expectedSpellId ~= nil then
        expectedId = PositiveInteger(expectedSpellId)
        if not expectedId then return nil end
    end
    if value == true then return 1 end
    if type(value) == "number" then
        local replacement = PositiveInteger(value)
        if not replacement or (expectedId and replacement == expectedId) then
            return nil
        end
        return 1
    end
    if type(value) ~= "table" then return nil end
    if value.version ~= 1 or type(value.rows) ~= "table" then return nil end
    local copies = PositiveInteger(value.copies)
    if not copies or copies > 6 then return nil end
    local topReplacement
    if value.replaces ~= nil then
        if type(value.replaces) ~= "number" then return nil end
        topReplacement = PositiveInteger(value.replaces)
        if not topReplacement
            or (expectedId and topReplacement == expectedId) then return nil end
    end
    local rowCount, highest, total, representedSpellId = 0, 0, 0, nil
    for index, row in pairs(value.rows) do
        local spellId = type(row) == "table"
            and PositiveInteger(row.spellId) or nil
        if type(index) ~= "number" or index < 1 or index ~= math.floor(index)
            or not spellId then
            return nil
        end
        if representedSpellId and representedSpellId ~= spellId then return nil end
        representedSpellId = spellId
        local stacks = PositiveInteger(row.stacks)
        if not stacks then return nil end
        if row.replaces ~= nil then
            if type(row.replaces) ~= "number" then return nil end
            local rowReplacement = PositiveInteger(row.replaces)
            if not rowReplacement
                or (expectedId and rowReplacement == expectedId) then return nil end
        end
        rowCount = rowCount + 1
        highest = math.max(highest, index)
        total = total + stacks
    end
    if rowCount < 1 or highest ~= rowCount or total ~= copies then return nil end
    if expectedId and representedSpellId ~= expectedId then return nil end
    local firstRowReplacement
    for index = 1, rowCount do
        if value.rows[index].replaces ~= nil then
            firstRowReplacement = PositiveInteger(value.rows[index].replaces)
            break
        end
    end
    if topReplacement and firstRowReplacement
        and topReplacement ~= firstRowReplacement then return nil end
    return copies
end

local function TargetReplacement(value, expectedSpellId)
    if TargetCopies(value, expectedSpellId) == nil then return nil end
    if type(value) == "table" then
        return type(value.replaces) == "number" and value.replaces or nil
    end
    return type(value) == "number" and PositiveInteger(value) or nil
end

local function TargetReplacements(value, expectedSpellId)
    if TargetCopies(value, expectedSpellId) == nil then return nil end
    local out, seen = {}, {}
    local function Add(replacement)
        replacement = PositiveInteger(replacement)
        if replacement and not seen[replacement] then
            seen[replacement] = true
            out[#out + 1] = replacement
        end
    end
    if type(value) == "table" then
        for _, row in ipairs(value.rows) do Add(row.replaces) end
        if #out == 0 then Add(value.replaces) end
    elseif type(value) == "number" then
        Add(value)
    end
    return out
end

local function TargetMapEntries(targets)
    if type(targets) ~= "table" then return nil end
    local entries, total, seenSpellIds = {}, 0, {}
    for spellIdKey, value in pairs(targets) do
        local spellId = PositiveInteger(spellIdKey)
        local copies = spellId and TargetCopies(value, spellId)
        if not spellId or not copies or seenSpellIds[spellId] then return nil end
        seenSpellIds[spellId] = true
        total = total + copies
        if total > 6 then return nil end
        entries[#entries + 1] = {
            spellId=spellId,value=value,copies=copies,
            replaces=TargetReplacement(value, spellId),
            replacements=TargetReplacements(value, spellId),
        }
    end
    table.sort(entries, function(left, right)
        return left.spellId < right.spellId
    end)
    return entries, total
end

local function TargetEnvelopeFields(value)
    local out = {}
    for key, field in pairs(type(value) == "table" and value or {}) do
        if key ~= "version" and key ~= "copies" and key ~= "replaces"
            and key ~= "rows" then out[key] = field end
    end
    return out
end

local function TargetRecord(rows, replaces, envelope)
    if type(envelope) ~= "table" then
        for _, row in ipairs(type(rows) == "table" and rows or {}) do
            if type(row) == "table"
                and type(row[TARGET_ENVELOPE_MARKER]) == "table" then
                envelope = row[TARGET_ENVELOPE_MARKER]
                break
            end
        end
    end
    local record = TargetEnvelopeFields(envelope)
    record.version, record.copies, record.rows = 1, 0, {}
    local firstRowReplacement
    for _, source in ipairs(type(rows) == "table" and rows or {}) do
        firstRowReplacement = type(source) == "table"
            and PositiveInteger(source.replaces) or nil
        if firstRowReplacement then break end
    end
    replaces = firstRowReplacement or PositiveInteger(replaces)
    if replaces then record.replaces = replaces end
    for _, source in ipairs(type(rows) == "table" and rows or {}) do
        local row = CopyEntry(source)
        row[TARGET_ENVELOPE_MARKER] = nil
        row.stacks = PositiveInteger(row.stacks or row.count) or 1
        row.locked = true
        row.sourceRole = row.sourceRole or "locked"
        record.copies = record.copies + row.stacks
        record.rows[#record.rows + 1] = row
    end
    if record.copies < 1 then record.copies = 1 end
    return record
end

-- Ordinary draft identity is exact whenever the represented spell ID is a
-- trustworthy positive integer. Family remains presentation/grouping
-- metadata and is only a deterministic compatibility fallback for malformed
-- callers that cannot enter a representable ordinary draft row.
local function DraftKey(spellId, catalog)
    local id = PositiveInteger(spellId)
    if id then return "exact:" .. tostring(id) end
    return "compat:" .. Family(spellId, catalog)
end

-- Preserve compatibility for older single-tier callers that still pass a
-- family handle. It is authoritative only when that family selects exactly
-- one ordinary row; sibling ambiguity fails closed.
local function ResolveDraftKey(pending, rowKey)
    pending = type(pending) == "table" and pending or {}
    if rowKey ~= nil and pending[rowKey] ~= nil then return rowKey end
    local wantedId = PositiveInteger(rowKey)
    local found
    for key, row in pairs(pending) do
        if type(row) == "table"
            and (row.family == rowKey
                or (wantedId and PositiveInteger(row.spellId) == wantedId)) then
            if found ~= nil then return nil end
            found = key
        end
    end
    return found
end

local function MaxStack(spellId, catalog)
    local row = catalog and catalog.rows and catalog.rows[tonumber(spellId)]
    return math.max(1, tonumber(row and row.maxStack) or 1)
end

local function EchoListTotal(echoes)
    local total = 0
    for _, echo in ipairs(type(echoes) == "table" and echoes or {}) do
        total = total + math.max(1, tonumber(echo and echo.stacks) or 1)
    end
    return total
end

local function PendingTotal(pending)
    local total = 0
    for _, row in pairs(type(pending) == "table" and pending or {}) do
        if not (row and row.lockIntent) then
            total = total + math.max(1, tonumber(row and row.stacks) or 1)
        end
    end
    return total
end

local function LockBudgetUsed(pending, pendingLock, lockedBySpell, excludeRealLockedId)
    local realLocked = {}
    for spellId, count in pairs(type(lockedBySpell) == "table" and lockedBySpell or {}) do
        local id, copies = tonumber(spellId), PositiveInteger(count)
        if id and copies then realLocked[id] = copies end
    end
    if excludeRealLockedId then realLocked[tonumber(excludeRealLockedId)] = nil end

    local function ExemptReplaced(row)
        local replaces = row and row.replaces
        if type(replaces) == "number" then realLocked[replaces] = nil end
    end
    for _, row in pairs(type(pending) == "table" and pending or {}) do
        if row and row.lockIntent then ExemptReplaced(row) end
    end
    for _, row in pairs(type(pendingLock) == "table" and pendingLock or {}) do
        ExemptReplaced(row)
    end

    local used = 0
    for _, copies in pairs(realLocked) do used = used + copies end
    for _, row in pairs(type(pending) == "table" and pending or {}) do
        if row and row.lockIntent then used = used + 1 end
    end
    for _, row in pairs(type(pendingLock) == "table" and pendingLock or {}) do
        used = used + (PositiveInteger(row and row.stacks) or 1)
    end
    return used
end

local function NormalizeDraft(echoes, options)
    options = options or {}
    echoes = type(echoes) == "table" and echoes or {}
    local trustOrder = options.trustOrder
    if trustOrder == nil then trustOrder = true end
    local catalog = options.catalog
    local lockedBySpell = type(options.lockedBySpell) == "table" and options.lockedBySpell or {}

    local pending, pendingLock, fulfilledTargets = {}, {}, {}
    local metrics = {
        lockedSkipped = 0,
        overflowSkipped = 0,
        untrustedOverflowSkipped = 0,
        lockDesignCollisions = 0,
        lockBudgetExceeded = 0,
        swapPairs = 0,
    }

    local importedLockedIds = {}
    for _, echo in ipairs(echoes) do
        if echo and echo.locked then
            local id = tonumber(echo.spellId)
            if id then importedLockedIds[id] = true end
        end
    end

    local wantsLockedSlots = next(importedLockedIds) ~= nil
    if not wantsLockedSlots and trustOrder and EchoListTotal(echoes) > MAX_WISHLIST_ECHOES then
        wantsLockedSlots = true
    end
    local swapCandidates = {}
    if wantsLockedSlots then
        for spellId in pairs(lockedBySpell) do
            local id = tonumber(spellId)
            if id and not importedLockedIds[id] then
                swapCandidates[#swapCandidates + 1] = id
            end
        end
        table.sort(swapCandidates)
    end
    local swapIndex = 1
    local remaining = MAX_WISHLIST_ECHOES
    local lockDesignCount = 0

    for _, echo in ipairs(echoes) do
        local id = tonumber(echo and echo.spellId)
        if id and echo and echo.locked and (tonumber(lockedBySpell[id]) or 0) > 0 then
            fulfilledTargets[id] = true
        end
        if id and (tonumber(lockedBySpell[id]) or 0) > 0 then
            metrics.lockedSkipped = metrics.lockedSkipped + 1
        elseif id and echo.locked and lockDesignCount < MAX_LOCK_SLOTS and remaining > 0 then
            local catalogRow = catalog and catalog.rows and catalog.rows[id]
            local family = Family(id, catalog)
            local rowKey = DraftKey(id, catalog)
            local maxStack = MaxStack(id, catalog)
            local swap = swapCandidates[swapIndex]
            if swap then swapIndex = swapIndex + 1 end
            pending[rowKey] = {
                spellId = id,
                family = family,
                quality = tonumber(catalogRow and catalogRow.quality) or tonumber(echo.quality) or 0,
                stacks = 1,
                maxStack = maxStack,
                lockIntent = true,
                replaces = swap,
            }
            lockDesignCount = lockDesignCount + 1
            remaining = MAX_WISHLIST_ECHOES - PendingTotal(pending)
        elseif id and echo.locked and lockDesignCount < MAX_LOCK_SLOTS then
            local catalogRow = catalog and catalog.rows and catalog.rows[id]
            local family = Family(id, catalog)
            local quality = tonumber(catalogRow and catalogRow.quality) or tonumber(echo.quality) or 0
            local existing = pendingLock[family]
            if not existing then
                local swap = swapCandidates[swapIndex]
                if swap then swapIndex = swapIndex + 1 end
                pendingLock[family] = {
                    spellId = id,
                    family = family,
                    quality = quality,
                    name = (catalogRow and catalogRow.name) or ("spell " .. tostring(id)),
                    replaces = swap,
                }
                lockDesignCount = lockDesignCount + 1
            elseif id ~= existing.spellId then
                metrics.lockDesignCollisions = metrics.lockDesignCollisions + 1
                if quality > (tonumber(existing.quality) or 0) then
                    existing.spellId, existing.quality = id, quality
                    existing.name = (catalogRow and catalogRow.name) or ("spell " .. tostring(id))
                end
            end
        elseif id and remaining <= 0 and trustOrder then
            metrics.overflowSkipped = metrics.overflowSkipped + 1
            local catalogRow = catalog and catalog.rows and catalog.rows[id]
            local family = Family(id, catalog)
            local quality = tonumber(catalogRow and catalogRow.quality) or tonumber(echo.quality) or 0
            local existing = pendingLock[family]
            if existing then
                if id ~= existing.spellId then
                    metrics.lockDesignCollisions = metrics.lockDesignCollisions + 1
                    if quality > (tonumber(existing.quality) or 0) then
                        existing.spellId, existing.quality = id, quality
                        existing.name = (catalogRow and catalogRow.name) or ("spell " .. tostring(id))
                    end
                end
            elseif lockDesignCount < MAX_LOCK_SLOTS then
                local swap = swapCandidates[swapIndex]
                if swap then swapIndex = swapIndex + 1 end
                lockDesignCount = lockDesignCount + 1
                pendingLock[family] = {
                    spellId = id,
                    family = family,
                    quality = quality,
                    name = (catalogRow and catalogRow.name) or ("spell " .. tostring(id)),
                    replaces = swap,
                }
            else
                metrics.lockBudgetExceeded = metrics.lockBudgetExceeded + 1
            end
        elseif id and remaining <= 0 then
            metrics.untrustedOverflowSkipped = metrics.untrustedOverflowSkipped + 1
        elseif id then
            local catalogRow = catalog and catalog.rows and catalog.rows[id]
            local family = Family(id, catalog)
            local rowKey = DraftKey(id, catalog)
            local quality = tonumber(catalogRow and catalogRow.quality) or tonumber(echo.quality) or 0
            local maxStack = MaxStack(id, catalog)
            local stacks = math.min(maxStack, math.max(1, tonumber(echo.stacks) or 1), remaining)
            local current = pending[rowKey]
            if not current or quality > (tonumber(current.quality) or 0) then
                local oldStacks = current and math.max(1, tonumber(current.stacks) or 1) or 0
                local keepStacks = math.min(maxStack, math.max(stacks, oldStacks))
                pending[rowKey] = {
                    spellId = id,
                    family = family,
                    quality = quality,
                    stacks = keepStacks,
                    maxStack = maxStack,
                }
                remaining = MAX_WISHLIST_ECHOES - PendingTotal(pending)
            elseif id == current.spellId then
                local add = math.min(stacks, remaining)
                current.stacks = math.min(current.maxStack or maxStack,
                    (tonumber(current.stacks) or 1) + add)
                remaining = MAX_WISHLIST_ECHOES - PendingTotal(pending)
            else
                current.stacks = math.min(current.maxStack or maxStack,
                    math.max(tonumber(current.stacks) or 1, stacks))
                remaining = MAX_WISHLIST_ECHOES - PendingTotal(pending)
            end
        end
    end

    metrics.swapPairs = swapIndex - 1

    return {
        pending = pending,
        pendingLock = pendingLock,
        fulfilledTargets = fulfilledTargets,
        metrics = metrics,
    }
end

-- Leaderboard records carry ordinary and permanently locked Echoes as two
-- independently captured evidence pools.  Keep those roles typed all the way
-- into the draft: ordering and shared spell IDs are never used to infer which
-- pool an entry belongs to.
local function NormalizeCandidateEvidence(ordinaryEchoes, lockedEchoes, options)
    options = options or {}
    if type(ordinaryEchoes) ~= "table" or type(lockedEchoes) ~= "table" then
        return nil, "typed Echo evidence is unavailable"
    end

    local ordinaryTotal = 0
    for _, echo in ipairs(ordinaryEchoes) do
        if type(echo) ~= "table" then
            return nil, "ordinary Echo evidence is invalid"
        end
        local id = PositiveInteger(echo.spellId)
        local stacks = PositiveInteger(echo.stacks or 1)
        local quality = echo.quality
        if not id or not stacks
            or (quality ~= nil and not NonNegativeInteger(quality)) then
            return nil, "ordinary Echo evidence is invalid"
        end
        ordinaryTotal = ordinaryTotal + math.max(1, stacks)
        if ordinaryTotal > MAX_WISHLIST_ECHOES then
            return nil, "ordinary Echo evidence exceeds the 79-copy limit"
        end
    end

    local evidence = Nexus and Nexus.CandidateEvidence
    if type(evidence) ~= "table"
        or type(evidence.NormalizeLockedEchoes) ~= "function" then
        return nil, "locked Echo evidence validator is unavailable"
    end
    local normalizedLocked, lockedReason = evidence.NormalizeLockedEchoes(
        lockedEchoes)
    if not normalizedLocked then
        if tostring(lockedReason):find("six-copy", 1, true) then
            return nil, lockedReason
        end
        return nil, "locked Echo evidence is invalid"
    end

    local explicitIds, explicitCounts, identityRows, explicitRows = {}, {}, {}, {}
    local explicitCount = 0
    for _, echo in ipairs(normalizedLocked) do
        local id, stacks = echo.spellId, echo.stacks
        explicitIds[id] = true
        explicitCounts[id] = (explicitCounts[id] or 0) + stacks
        identityRows[id] = (identityRows[id] or 0) + 1
        explicitRows[id] = explicitRows[id] or {}
        explicitRows[id][#explicitRows[id] + 1] = CopyEntry(echo)
        explicitCount = explicitCount + stacks
    end

    -- Local locked ownership must not consume or suppress an ordinary role
    -- with the same spell ID.  It is considered only while materializing the
    -- separate explicit-lock pool below.
    local prepared = {
        pending={},pendingLock={},fulfilledTargets={},metrics={
            lockedSkipped=0,overflowSkipped=0,untrustedOverflowSkipped=0,
            lockDesignCollisions=0,lockBudgetExceeded=0,swapPairs=0,
        },
    }
    for _, echo in ipairs(ordinaryEchoes) do
        local id, stacks = PositiveInteger(echo.spellId),
            PositiveInteger(echo.stacks or 1)
        local key = DraftKey(id, options.catalog)
        local current = prepared.pending[key]
        if current then
            current.stacks = current.stacks + stacks
            current.maxStack = math.max(current.maxStack, current.stacks)
        else
            local catalogRow = options.catalog and options.catalog.rows
                and options.catalog.rows[id]
            local row = CopyEntry(echo)
            row.spellId = id
            row.family = Family(id, options.catalog)
            row.quality = tonumber(catalogRow and catalogRow.quality)
                or tonumber(echo.quality) or 0
            row.stacks = stacks
            row.maxStack = math.max(MaxStack(id, options.catalog), stacks)
            row.locked, row.sourceRole = nil, "ordinary"
            prepared.pending[key] = row
        end
    end

    local lockedBySpell = type(options.lockedBySpell) == "table"
        and options.lockedBySpell or {}
    local replacementIds = {}
    for spellId in pairs(lockedBySpell) do
        local id = tonumber(spellId)
        if id and not explicitIds[id] then replacementIds[#replacementIds + 1] = id end
    end
    table.sort(replacementIds)

    prepared.pendingLock = {}
    prepared.fulfilledTargets = {}
    local replacementIndex = 1
    local identityOrdinals = {}
    for _, echo in ipairs(normalizedLocked) do
        local id = echo.spellId
        identityOrdinals[id] = (identityOrdinals[id] or 0) + 1
        if (PositiveInteger(lockedBySpell[id]) or 0) == explicitCounts[id] then
            prepared.fulfilledTargets[id] = TargetRecord(explicitRows[id])
        else
            local catalogRow = options.catalog and options.catalog.rows
                and options.catalog.rows[id]
            local replacement = replacementIds[replacementIndex]
            if replacement then replacementIndex = replacementIndex + 1 end
            -- Key by explicit identity, not family.  Two authoritative locked
            -- picks may share a catalog family/quality collision and both must
            -- remain visible and committable.
            local key = "explicit:" .. tostring(id)
            if identityRows[id] > 1 then
                key = key .. ":" .. tostring(identityOrdinals[id])
            end
            local draftRow = CopyEntry(echo)
            draftRow.spellId = id
            draftRow.family = Family(id, options.catalog)
            draftRow.quality = tonumber(echo.quality)
                or tonumber(catalogRow and catalogRow.quality) or 0
            draftRow.name = (catalogRow and catalogRow.name)
                or ("spell " .. tostring(id))
            draftRow.stacks = echo.stacks
            draftRow.replaces = replacement
            draftRow.explicitEvidence = true
            draftRow.locked = true
            draftRow.sourceRole = "locked"
            prepared.pendingLock[key] = draftRow
        end
    end
    prepared.metrics.explicitLocked = explicitCount
    prepared.metrics.explicitFulfilled = CountMap(prepared.fulfilledTargets)
    prepared.metrics.swapPairs = replacementIndex - 1
    return prepared
end

local function ApplyCommittedTargets(prepared, committedTargets, options)
    prepared = type(prepared) == "table" and prepared or {}
    committedTargets = type(committedTargets) == "table" and committedTargets or {}
    local committedEntries = TargetMapEntries(committedTargets) or {}
    options = options or {}
    local catalog = options.catalog
    local lockedBySpell = type(options.lockedBySpell) == "table" and options.lockedBySpell or {}
    local pending = CopyMap(prepared.pending)
    local pendingLock = CopyMap(prepared.pendingLock)
    local fulfilledTargets = CopyMap(prepared.fulfilledTargets)

    for _, target in ipairs(committedEntries) do
        if (tonumber(lockedBySpell[target.spellId]) or 0)
            >= target.copies then
            fulfilledTargets[target.spellId] = target.value
        end
    end
    if #committedEntries > 0 then
        for _, target in ipairs(committedEntries) do
            local id, copies, replaces = target.spellId, target.copies,
                target.value
            local envelope = TargetEnvelopeFields(replaces)
            if (tonumber(lockedBySpell[id]) or 0) < copies then
                local catalogRow = catalog and catalog.rows and catalog.rows[id]
                local family = Family(id, catalog)
                local targetRows = type(replaces) == "table" and replaces.rows
                if type(targetRows) == "table" and #targetRows > 0 then
                    for index, source in ipairs(targetRows) do
                        local lockKey = "committed:" .. tostring(id)
                            .. ":" .. tostring(index)
                        if family and not pendingLock[lockKey] then
                            local row = CopyEntry(source)
                            if next(envelope) then
                                row[TARGET_ENVELOPE_MARKER] = envelope
                            end
                            row.spellId = id
                            row.family = family
                            row.quality = tonumber(row.quality)
                                or tonumber(catalogRow and catalogRow.quality) or 0
                            row.name = row.name or (catalogRow and catalogRow.name)
                                or ("spell " .. tostring(id))
                            row.stacks = PositiveInteger(row.stacks) or 1
                            row.replaces = row.replaces
                                or TargetReplacement(replaces, id)
                            row.locked = true
                            row.sourceRole = row.sourceRole or "locked"
                            pendingLock[lockKey] = row
                        end
                    end
                else
                    local lockKey = "committed:" .. tostring(id)
                    if family and not pendingLock[lockKey] then
                        pendingLock[lockKey] = {
                            spellId = id,
                            family = family,
                            quality = tonumber(catalogRow and catalogRow.quality) or 0,
                            name = (catalogRow and catalogRow.name)
                                or ("spell " .. tostring(id)),
                            stacks = copies,
                            replaces = TargetReplacement(replaces, id),
                        }
                    end
                end
            end
        end
    end

    return {
        pending = pending,
        pendingLock = pendingLock,
        fulfilledTargets = fulfilledTargets,
        metrics = CopyEntry(prepared.metrics),
    }
end

local function AddPending(pending, row, options)
    if not row or not tonumber(row.spellId) then return pending, "invalid" end
    options = options or {}
    local spellId = tonumber(row.spellId)
    local lockedBySpell = type(options.lockedBySpell) == "table" and options.lockedBySpell or {}
    if (tonumber(lockedBySpell[spellId]) or 0) > 0 then return pending, "already_locked" end
    local family = Family(spellId, options.catalog)
    local rowKey = DraftKey(spellId, options.catalog)
    local maxStack = math.max(1, tonumber(row.maxStack) or 1)
    local old = type(pending) == "table" and pending[rowKey]
    if old and tonumber(old.spellId) == spellId then return pending, "unchanged" end
    if not old and PendingTotal(pending) >= MAX_WISHLIST_ECHOES then return pending, "full" end
    local nextPending = CopyMap(pending)
    nextPending[rowKey] = {
        spellId = spellId,
        family = family,
        quality = tonumber(row.quality) or 0,
        stacks = math.min(maxStack, math.max(1, tonumber(old and old.stacks) or 1)),
        maxStack = maxStack,
    }
    return nextPending, "added"
end

local function RemovePending(pending, pendingLock, rowKey)
    if not rowKey then return pending, pendingLock, "invalid" end
    if type(pendingLock) == "table" and pendingLock[rowKey] then
        local nextLock = CopyMap(pendingLock)
        nextLock[rowKey] = nil
        return pending, nextLock, "removed_lock"
    end
    for key, row in pairs(type(pendingLock) == "table" and pendingLock or {}) do
        if row and row.family == rowKey then
            local nextLock = CopyMap(pendingLock)
            nextLock[key] = nil
            return pending, nextLock, "removed_lock"
        end
    end
    local resolved = ResolveDraftKey(pending, rowKey)
    if resolved then
        local nextPending = CopyMap(pending)
        nextPending[resolved] = nil
        return nextPending, pendingLock, "removed"
    end
    return pending, pendingLock, "unchanged"
end

local function ToggleDesignLock(pending, pendingLock, rowKey, options)
    options = options or {}
    if not rowKey then return pending, pendingLock, options.replacingSpellId, "invalid" end
    if type(pendingLock) == "table" and pendingLock[rowKey] then
        local nextLock = CopyMap(pendingLock)
        nextLock[rowKey] = nil
        return pending, nextLock, options.replacingSpellId, "untagged_lock"
    end
    local resolved = ResolveDraftKey(pending, rowKey)
    local row = resolved and pending[resolved]
    if not row then return pending, pendingLock, options.replacingSpellId, "unchanged" end
    local nextPending = CopyMap(pending)
    local nextRow = nextPending[resolved]
    if nextRow.lockIntent then
        if PendingTotal(pending) + math.max(1, tonumber(nextRow.stacks) or 1)
            > MAX_WISHLIST_ECHOES then
            return pending, pendingLock, options.replacingSpellId, "normal_full"
        end
        nextRow.lockIntent = nil
        nextRow.replaces = nil
        return nextPending, pendingLock, options.replacingSpellId, "untagged"
    end
    if LockBudgetUsed(pending, pendingLock, options.lockedBySpell,
        options.replacingSpellId) >= MAX_LOCK_SLOTS then
        return pending, pendingLock, nil, "lock_full"
    end
    nextRow.lockIntent = true
    nextRow.replaces = options.replacingSpellId
    return nextPending, pendingLock, nil, "tagged"
end

local function AdjustStacks(pending, rowKey, delta)
    local resolved = ResolveDraftKey(pending, rowKey)
    local row = resolved and pending[resolved]
    if not row then return pending, "unchanged" end
    local maxStack = math.max(1, tonumber(row.maxStack) or 1)
    local current = math.max(1, tonumber(row.stacks) or 1)
    if delta > 0 and PendingTotal(pending) >= MAX_WISHLIST_ECHOES then
        return pending, "full"
    end
    local room = math.max(0, MAX_WISHLIST_ECHOES - PendingTotal(pending))
    local nextValue = current + delta
    if delta > 0 then nextValue = math.min(nextValue, current + room) end
    local nextPending = CopyMap(pending)
    nextPending[resolved].stacks = math.max(1, math.min(maxStack, nextValue))
    return nextPending, "adjusted"
end

local function AssignLockSlot(pending, pendingLock, data, options)
    options = options or {}
    if not data or not tonumber(data.spellId) then
        return pending, pendingLock, options.replacingSpellId, "invalid"
    end
    local id = tonumber(data.spellId)
    local catalog = options.catalog
    local family = Family(id, catalog)
    local rowKey = DraftKey(id, catalog)
    local row = type(pending) == "table" and pending[rowKey]
    if row then
        local nextPending = pending
        if not row.lockIntent then
            if LockBudgetUsed(pending, pendingLock, options.lockedBySpell,
                options.replacingSpellId) >= MAX_LOCK_SLOTS then
                return pending, pendingLock, nil, "lock_full"
            end
            nextPending = CopyMap(pending)
            nextPending[rowKey].lockIntent = true
            nextPending[rowKey].replaces = options.replacingSpellId
            nextPending[rowKey].stacks = 1
        end
        return nextPending, pendingLock, nil, "tagged"
    end
    for _, lockedRow in pairs(type(pendingLock) == "table" and pendingLock or {}) do
        if lockedRow and lockedRow.family == family then
            return pending, pendingLock, nil, "already"
        end
    end
    if LockBudgetUsed(pending, pendingLock, options.lockedBySpell,
        options.replacingSpellId) >= MAX_LOCK_SLOTS then
        return pending, pendingLock, nil, "lock_full"
    end
    local catalogRow = catalog and catalog.rows and catalog.rows[id]
    local nextLock = CopyMap(pendingLock)
    nextLock[family] = {
        spellId = id,
        family = family,
        quality = tonumber((catalogRow and catalogRow.quality) or data.quality) or 0,
        name = tostring((catalogRow and catalogRow.name) or data.name or ("spell " .. tostring(id))),
        replaces = options.replacingSpellId,
    }
    return pending, nextLock, nil, "queued"
end

local function CanonicalEchoes(pending)
    local echoes = {}
    for _, row in pairs(type(pending) == "table" and pending or {}) do
        if row and not row.lockIntent then
            echoes[#echoes + 1] = {
                spellId = tonumber(row.spellId),
                quality = tonumber(row.quality) or 0,
                stacks = math.max(1,
                    math.min(tonumber(row.maxStack) or 1, tonumber(row.stacks) or 1)),
            }
        end
    end
    table.sort(echoes, function(a, b) return (a.spellId or 0) < (b.spellId or 0) end)
    return echoes
end

local function ExportEntries(pending, pendingLock, lockedBySpell, catalog,
    fulfilledTargets)
    local entries, seenLocked = {}, {}
    local function LockIdentity(value)
        return tonumber(value) or tostring(value)
    end
    for _, row in pairs(type(pending) == "table" and pending or {}) do
        entries[#entries + 1] = {
            spellId = row.spellId,
            quality = row.quality,
            stacks = row.lockIntent and 1 or row.stacks,
            locked = row.lockIntent and true or nil,
        }
        if row.lockIntent then seenLocked[LockIdentity(row.spellId)] = true end
    end
    for _, row in pairs(type(pendingLock) == "table" and pendingLock or {}) do
        local identity = LockIdentity(row.spellId)
        local exported = CopyEntry(row)
        exported[TARGET_ENVELOPE_MARKER] = nil
        exported.spellId = row.spellId
        exported.quality = row.quality
        exported.stacks = PositiveInteger(row.stacks) or 1
        exported.locked = true
        exported.sourceRole = row.sourceRole or "locked"
        entries[#entries + 1] = exported
        seenLocked[identity] = true
    end
    for id, target in pairs(type(fulfilledTargets) == "table"
        and fulfilledTargets or {}) do
        local rows = type(target) == "table" and target.rows or nil
        for _, source in ipairs(type(rows) == "table" and rows or {}) do
            local exported = CopyEntry(source)
            exported[TARGET_ENVELOPE_MARKER] = nil
            exported.spellId = PositiveInteger(exported.spellId) or tonumber(id)
            exported.stacks = PositiveInteger(exported.stacks) or 1
            exported.locked = true
            exported.sourceRole = exported.sourceRole or "locked"
            entries[#entries + 1] = exported
            seenLocked[LockIdentity(exported.spellId)] = true
        end
    end
    for id, count in pairs(type(lockedBySpell) == "table" and lockedBySpell or {}) do
        local identity = LockIdentity(id)
        if not seenLocked[identity] then
            local catalogRow = catalog and catalog.rows and catalog.rows[identity]
            entries[#entries + 1] = {
                spellId = identity,
                quality = catalogRow and tonumber(catalogRow.quality) or 0,
                stacks = count,
                locked = true,
            }
            seenLocked[identity] = true
        end
    end
    return entries
end

local function PlanLockCommit(pending, pendingLock, fulfilledTargets, existingTargets,
    lockedBySpell)
    local fresh, replaced = {}, {}
    for _, row in pairs(type(pending) == "table" and pending or {}) do
        if row.lockIntent and type(row.replaces) == "number" then replaced[row.replaces] = true end
    end
    for _, row in pairs(type(pendingLock) == "table" and pendingLock or {}) do
        if type(row.replaces) == "number" then replaced[row.replaces] = true end
    end
    local fulfilledEntries = TargetMapEntries(type(fulfilledTargets) == "table"
        and fulfilledTargets or {}) or {}
    local existingEntries = TargetMapEntries(type(existingTargets) == "table"
        and existingTargets or {}) or {}
    for _, target in ipairs(fulfilledEntries) do
        for _, replacement in ipairs(target.replacements) do
            replaced[replacement] = true
        end
    end

    lockedBySpell = type(lockedBySpell) == "table" and lockedBySpell or {}
    for _, target in ipairs(existingEntries) do
        local id = target.spellId
        if (tonumber(lockedBySpell[id]) or 0) >= target.copies
            and not replaced[id] then
            fresh[id] = target.value
        end
    end
    for _, target in ipairs(fulfilledEntries) do
        local id = target.spellId
        if (tonumber(lockedBySpell[id]) or 0) >= target.copies
            and not replaced[id] then
            fresh[id] = target.value
        end
    end
    local plannedRows = {}
    local plannedReplacements = {}
    local function PlanRow(row, stacks)
        local id = type(row) == "table" and tonumber(row.spellId)
        if not id then return end
        local copy = CopyEntry(row)
        copy.stacks = PositiveInteger(stacks) or 1
        copy.locked = true
        copy.sourceRole = copy.sourceRole or "locked"
        plannedRows[id] = plannedRows[id] or {}
        plannedRows[id][#plannedRows[id] + 1] = copy
        if plannedReplacements[id] == nil and type(row.replaces) == "number" then
            plannedReplacements[id] = row.replaces
        end
    end
    for _, row in pairs(type(pending) == "table" and pending or {}) do
        if row.lockIntent and tonumber(row.spellId) then
            PlanRow(row, 1)
        end
    end
    for _, row in pairs(type(pendingLock) == "table" and pendingLock or {}) do
        PlanRow(row, row.stacks)
    end
    for id, rows in pairs(plannedRows) do
        fresh[id] = TargetRecord(rows, plannedReplacements[id])
    end
    return TargetMapEntries(fresh) and fresh or {}
end

local function ReconcileLocked(pending, pendingLock, fulfilledTargets, lockedBySpell)
    lockedBySpell = type(lockedBySpell) == "table" and lockedBySpell or {}
    local nextPending, nextLock, nextFulfilled = pending, pendingLock, fulfilledTargets
    local groups = {}
    local function AddTarget(container, key, row, stacks)
        if type(row) ~= "table" or not tonumber(row.spellId) then return end
        local id = tonumber(row.spellId)
        local group = groups[id]
        if not group then
            group = {copies=0,rows={},pendingKeys={},lockKeys={}}
            groups[id] = group
        end
        local copy = CopyEntry(row)
        copy.stacks = PositiveInteger(stacks) or 1
        group.copies = group.copies + copy.stacks
        group.rows[#group.rows + 1] = copy
        if type(row.replaces) == "number" and group.replaces == nil then
            group.replaces = row.replaces
        end
        if container == "pending" then
            group.pendingKeys[#group.pendingKeys + 1] = key
        else
            group.lockKeys[#group.lockKeys + 1] = key
        end
    end
    for rowKey, row in pairs(type(pendingLock) == "table" and pendingLock or {}) do
        AddTarget("lock", rowKey, row, row.stacks)
    end
    for rowKey, row in pairs(type(pending) == "table" and pending or {}) do
        if row.lockIntent then AddTarget("pending", rowKey, row, 1) end
    end
    for id, group in pairs(groups) do
        if (tonumber(lockedBySpell[id]) or 0) >= group.copies then
            if nextFulfilled == fulfilledTargets then
                nextFulfilled = CopyMap(fulfilledTargets)
            end
            nextFulfilled[id] = TargetRecord(group.rows, group.replaces)
            if #group.pendingKeys > 0 then
                if nextPending == pending then nextPending = CopyMap(pending) end
                for _, key in ipairs(group.pendingKeys) do nextPending[key] = nil end
            end
            if #group.lockKeys > 0 then
                if nextLock == pendingLock then nextLock = CopyMap(pendingLock) end
                for _, key in ipairs(group.lockKeys) do nextLock[key] = nil end
            end
        end
    end
    return nextPending, nextLock, nextFulfilled
end

local function TrimName(name)
    name = tostring(name or "")
    return name:gsub("^%s+", ""):gsub("%s+$", "")
end

function Factory.New()
    local Model = {}
    Model.NormalizeEchoName = NormalizeEchoName
    Model.Family = Family
    Model.DraftKey = DraftKey
    Model.ResolveDraftKey = ResolveDraftKey
    Model.MaxStack = MaxStack
    Model.EchoListTotal = EchoListTotal
    Model.PendingTotal = PendingTotal
    Model.LockBudgetUsed = LockBudgetUsed
    Model.TargetCopies = TargetCopies
    Model.TargetReplacement = TargetReplacement
    Model.TargetReplacements = TargetReplacements
    Model.TargetMapEntries = TargetMapEntries
    Model.NormalizeDraft = NormalizeDraft
    Model.NormalizeCandidateEvidence = NormalizeCandidateEvidence
    Model.ApplyCommittedTargets = ApplyCommittedTargets
    Model.AddPending = AddPending
    Model.RemovePending = RemovePending
    Model.ToggleDesignLock = ToggleDesignLock
    Model.AdjustStacks = AdjustStacks
    Model.AssignLockSlot = AssignLockSlot
    Model.CanonicalEchoes = CanonicalEchoes
    Model.ExportEntries = ExportEntries
    Model.PlanLockCommit = PlanLockCommit
    Model.ReconcileLocked = ReconcileLocked
    Model.TrimName = TrimName
    return Model
end
