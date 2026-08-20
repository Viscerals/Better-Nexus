-- Nexus: pure typed candidate evidence shared by Community, Leaderboard, and
-- the Wishlist editor. This module owns no frames, persistence, adapter I/O,
-- automation, or action state.

Nexus = Nexus or {}
local Evidence = {}
Nexus.CandidateEvidence = Evidence

local CURRENT_KIND = "candidate-typed-v1"
local LEGACY_KIND = "leaderboard-typed-v1"
local MAX_ORDINARY = 79
local MAX_LOCKED = 6

local LOCKED_DISAGREEMENT =
    "record categories disagree on locked Echo evidence"
local LOCKED_CLAIM_MISMATCH =
    "locked Echo fingerprint does not match its evidence"

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return out
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

local function NormalizePool(source, lockedRole, allowOrdinaryOverflow,
    markLockedRole)
    if type(source) ~= "table" then
        return nil, (lockedRole and "locked" or "ordinary")
            .. " Echo evidence is unavailable"
    end
    local entries, maxIndex = 0, 0
    for index, row in pairs(source) do
        if type(index) ~= "number" or index < 1
            or index ~= math.floor(index) or type(row) ~= "table" then
            return nil, (lockedRole and "locked" or "ordinary")
                .. " Echo evidence must be a dense array"
        end
        entries = entries + 1
        if index > maxIndex then maxIndex = index end
    end
    if entries ~= maxIndex then
        return nil, (lockedRole and "locked" or "ordinary")
            .. " Echo evidence must be a dense array"
    end
    if not lockedRole and entries == 0 then
        return nil, "ordinary Echo evidence is still syncing"
    end
    if lockedRole and entries > MAX_LOCKED then
        return nil, "locked Echo evidence exceeds the six-slot limit"
    end

    local out, total, identities = {}, 0, {}
    for index = 1, entries do
        local row = source[index]
        if not lockedRole and (row.locked
            or (row.sourceRole ~= nil
                and tostring(row.sourceRole) ~= "ordinary")) then
            return nil, "ordinary Echo evidence contains locked-role data"
        end
        local id = PositiveInteger(row.spellId or row.spellID
            or row.id or row.perkId or row.perkID)
        local stacks = PositiveInteger(row.stacks or row.stack
            or row.count or row.amount or 1)
        local quality = row.quality
        if not id or not stacks
            or (quality ~= nil and not NonNegativeInteger(quality)) then
            return nil, (lockedRole and "locked" or "ordinary")
                .. " Echo evidence is invalid"
        end
        if lockedRole and identities[id] then
            return nil, "locked Echo evidence contains a duplicate identity"
        end
        identities[id] = true
        total = total + stacks
        if not lockedRole and not allowOrdinaryOverflow
            and total > MAX_ORDINARY then
            return nil, "ordinary Echo evidence exceeds 79 copies"
        end
        local copy = DeepCopy(row)
        copy.spellId, copy.stacks = id, stacks
        copy.quality = quality ~= nil and NonNegativeInteger(quality) or nil
        if lockedRole and markLockedRole then copy.locked = true end
        out[index] = copy
    end
    return out, nil, total
end

local function Token(identity, ordinary, locked)
    local parts = {tostring(identity)}
    for _, row in ipairs(ordinary or {}) do
        parts[#parts + 1] = table.concat({
            "o", tostring(row.spellId), tostring(row.quality or ""),
            tostring(row.stacks),
        }, ":")
    end
    for _, row in ipairs(locked or {}) do
        parts[#parts + 1] = table.concat({
            "l", tostring(row.spellId), tostring(row.quality or ""),
            tostring(row.stacks),
        }, ":")
    end
    return table.concat(parts, "|")
end

local function CanonicalFingerprint(rows)
    local counts, ids = {}, {}
    for _, row in ipairs(rows or {}) do
        local id, stacks = row.spellId, row.stacks
        if counts[id] == nil then ids[#ids + 1] = id end
        counts[id] = (counts[id] or 0) + stacks
    end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return #parts > 0 and table.concat(parts, ",") or "0"
end

local function SameTypedIdentity(left, right)
    return left ~= nil and right ~= nil and type(left) == type(right)
        and tostring(left) == tostring(right)
end

local function LockedOutcome(status, reason, source, fingerprint, rows)
    return {
        status=status,
        reason=reason or "",
        source=source or "none",
        fingerprint=fingerprint or "0",
        lockedEchoes=DeepCopy(rows or {}),
    }
end

local function SplitBuildEchoes(build)
    local ordinary, locked = {}, {}
    if type(build) ~= "table" or type(build.echoes) ~= "table" then
        return nil, nil
    end
    local entries, maxIndex = 0, 0
    for index in pairs(build.echoes) do
        if type(index) ~= "number" or index < 1
            or index ~= math.floor(index) then
            return nil, nil, "build Echo evidence must be a dense array"
        end
        entries = entries + 1
        if index > maxIndex then maxIndex = index end
    end
    if entries ~= maxIndex then
        return nil, nil, "build Echo evidence must be a dense array"
    end
    for index = 1, entries do
        local row = build.echoes[index]
        if type(row) == "table" and row.locked then
            locked[#locked + 1] = row
        else
            ordinary[#ordinary + 1] = row
        end
    end
    return ordinary, locked
end

local function TargetIdentity(options, ordinaryFingerprint)
    local build = type(options.build) == "table" and options.build or nil
    local buildId = options.buildId
    if buildId == nil and build then buildId = build.id end
    local fingerprint = options.fingerprint
    if fingerprint == nil and build then fingerprint = build.fingerprint end
    if buildId ~= nil and ((type(buildId) ~= "string"
        and type(buildId) ~= "number") or tostring(buildId) == "") then
        return nil, nil, "record build identity is invalid"
    end
    if fingerprint ~= nil then
        if (type(fingerprint) ~= "string" and type(fingerprint) ~= "number")
            or tostring(fingerprint) == "" then
            return nil, nil, "record fingerprint is invalid"
        end
        fingerprint = tostring(fingerprint)
        if fingerprint ~= ordinaryFingerprint then
            return nil, nil,
                "record fingerprint does not match its Echo evidence"
        end
    else
        fingerprint = ordinaryFingerprint
    end
    return buildId, fingerprint
end

local function RecordIdentity(record, expectedId, expectedFingerprint,
    allowOrdinaryOverflow)
    if record.recordIdentityMismatch then
        return nil, "record fingerprint does not match its Echo evidence"
    end
    if record.resolvedIdentityMismatch then
        return nil,
            "record categories disagree on resolved build identity"
    end
    local fingerprint = record.fingerprint
    if type(fingerprint) ~= "string" or fingerprint == "" then
        return nil, "record fingerprint is unavailable"
    end
    if fingerprint ~= expectedFingerprint then
        return nil, "record and catalog identities do not match"
    end
    if record.echoes ~= nil then
        if type(record.echoes) ~= "table" then
            return nil, "ordinary Echo evidence is invalid"
        end
        local ordinary, reason = NormalizePool(
            record.echoes, false, allowOrdinaryOverflow)
        if not ordinary then return nil, reason end
        if CanonicalFingerprint(ordinary) ~= fingerprint then
            return nil, "record fingerprint does not match its Echo evidence"
        end
    end

    local resolved = record.resolvedBuildId
    local direct = record.buildId
    if expectedId ~= nil then
        local directMatch = SameTypedIdentity(direct, expectedId)
        local resolvedMatch = SameTypedIdentity(resolved, expectedId)
        if not directMatch and not resolvedMatch then
            return nil, "record and catalog build IDs do not match"
        end
        if resolved ~= nil and directMatch and not resolvedMatch then
            return nil, "record and catalog build IDs do not match"
        end
        if record.buildIdentityMismatch and not resolvedMatch then
            return nil, "record and catalog identities do not match"
        end
    elseif record.buildIdentityMismatch then
        return nil, "record and catalog identities do not match"
    end

    local build = type(record.build) == "table" and record.build or nil
    if build and type(build.fingerprint) == "string"
        and build.fingerprint ~= ""
        and build.fingerprint ~= fingerprint then
        return nil, "record and catalog identities do not match"
    end
    if build and expectedId ~= nil and build.id ~= nil
        and not SameTypedIdentity(build.id, expectedId) then
        return nil, "record and catalog build IDs do not match"
    end
    return resolved ~= nil and resolved or direct
end

local function LockedRecord(record, category, expectedId,
    expectedFingerprint, allowOrdinaryOverflow)
    if record == nil then return nil, nil, nil, nil end
    if type(record) ~= "table" then
        return nil, nil, nil, "locked Echo record is invalid"
    end
    if record.category ~= nil and tostring(record.category) ~= category then
        return nil, nil, nil, "locked Echo record category is invalid"
    end
    local identity, identityReason = RecordIdentity(
        record, expectedId, expectedFingerprint, allowOrdinaryOverflow)
    if identityReason then return nil, nil, nil, identityReason end
    local source = record.lockedEchoes
    if source == nil then source = {} end
    local rows, reason = NormalizePool(source, true)
    if not rows then return nil, nil, nil, reason end
    local fingerprint = CanonicalFingerprint(rows)
    if record.lockedFingerprint ~= nil
        and tostring(record.lockedFingerprint) ~= fingerprint then
        return nil, nil, nil, LOCKED_CLAIM_MISMATCH
    end
    return rows, fingerprint, identity
end

local function LockedPoolOnly(record, category)
    if record == nil then return nil, nil end
    if type(record) ~= "table"
        or (record.category ~= nil
            and tostring(record.category) ~= category) then
        return nil, "locked Echo record category is invalid"
    end
    if record.lockedEchoes ~= nil
        and type(record.lockedEchoes) ~= "table" then
        return nil, "locked Echo evidence is invalid"
    end
    local rows, reason = NormalizePool(record.lockedEchoes or {}, true)
    if not rows then return nil, reason end
    local fingerprint = CanonicalFingerprint(rows)
    if record.lockedFingerprint ~= nil
        and tostring(record.lockedFingerprint) ~= fingerprint then
        return nil, LOCKED_CLAIM_MISMATCH
    end
    return fingerprint
end

local function CategoryRecord(options, category)
    local records = type(options.records) == "table" and options.records
        or type(options.categories) == "table" and options.categories or nil
    local named
    if category == "dummy" then
        named = options.dummyRecord
    else
        named = options.lkRecord
    end
    if named ~= nil then return named end
    if records and records[category] ~= nil then return records[category] end
    return options[category]
end

-- Resolve one exact locked-Echo authority without reading global state. The
-- caller supplies the selected ordinary evidence plus zero, one, or both
-- category records. Every outcome has bounded scalar diagnostics; only an
-- `ok` result carries locked rows, and those rows are always defensive copies.
function Evidence.ResolveLocked(options)
    options = type(options) == "table" and options or {}
    local buildOrdinary, buildLocked, splitReason =
        SplitBuildEchoes(options.build)
    if splitReason then return LockedOutcome("invalid", splitReason) end
    if (buildLocked == nil or #buildLocked == 0)
        and type(options.build) == "table"
        and type(options.build.lockedEchoes) == "table" then
        buildLocked = options.build.lockedEchoes
    end
    local ordinarySource = options.ordinaryEchoes
        or options.echoes or buildOrdinary
    local dummyRecord = CategoryRecord(options, "dummy")
    local lkRecord = CategoryRecord(options, "lk")
    if ordinarySource == nil and dummyRecord ~= nil and lkRecord ~= nil then
        local dummyFingerprint, dummyReason =
            LockedPoolOnly(dummyRecord, "dummy")
        if dummyReason then return LockedOutcome("invalid", dummyReason) end
        local lkFingerprint, lkReason = LockedPoolOnly(lkRecord, "lk")
        if lkReason then return LockedOutcome("invalid", lkReason) end
        if dummyFingerprint ~= lkFingerprint then
            return LockedOutcome("conflict", LOCKED_DISAGREEMENT)
        end
    end
    local allowOrdinaryOverflow = options.allowOrdinaryOverflow == true
        or options.ordinaryComplete == false
    local ordinary, ordinaryReason = NormalizePool(
        ordinarySource, false, allowOrdinaryOverflow)
    if not ordinary then
        return LockedOutcome("unavailable", ordinaryReason)
    end
    local ordinaryFingerprint = CanonicalFingerprint(ordinary)
    local buildId, expectedFingerprint, targetReason = TargetIdentity(
        options, ordinaryFingerprint)
    if targetReason then return LockedOutcome("invalid", targetReason) end

    local dummy, dummyFingerprint, dummyIdentity, dummyReason = LockedRecord(
        dummyRecord, "dummy", buildId, expectedFingerprint,
        allowOrdinaryOverflow)
    if dummyReason then return LockedOutcome("invalid", dummyReason) end
    local lk, lkFingerprint, lkIdentity, lkReason = LockedRecord(
        lkRecord, "lk", buildId, expectedFingerprint,
        allowOrdinaryOverflow)
    if lkReason then return LockedOutcome("invalid", lkReason) end

    if dummyRecord ~= nil and lkRecord ~= nil then
        if dummyFingerprint ~= lkFingerprint then
            return LockedOutcome("conflict", LOCKED_DISAGREEMENT)
        end
        if buildId == nil and dummyIdentity ~= nil and lkIdentity ~= nil
            and not SameTypedIdentity(dummyIdentity, lkIdentity) then
            return LockedOutcome("conflict",
                "record categories disagree on resolved build identity")
        end
        local status = #dummy > 0 and "ok" or "none"
        return LockedOutcome(status, nil, "dummy+lk",
            dummyFingerprint, dummy)
    end
    if dummyRecord ~= nil then
        local status = #dummy > 0 and "ok" or "none"
        return LockedOutcome(status, nil, "dummy", dummyFingerprint, dummy)
    end
    if lkRecord ~= nil then
        local status = #lk > 0 and "ok" or "none"
        return LockedOutcome(status, nil, "lk", lkFingerprint, lk)
    end

    local inlineSource = options.inlineLockedEchoes
        or options.lockedEchoes or buildLocked or {}
    local inline, inlineReason = NormalizePool(inlineSource, true)
    if not inline then return LockedOutcome("invalid", inlineReason) end
    local inlineFingerprint = CanonicalFingerprint(inline)
    local inlineClaim = options.inlineLockedFingerprint
    if inlineClaim == nil then inlineClaim = options.lockedFingerprint end
    if inlineClaim == nil and type(options.build) == "table" then
        inlineClaim = options.build.lockedFingerprint
    end
    if inlineClaim ~= nil and tostring(inlineClaim) ~= inlineFingerprint then
        return LockedOutcome("invalid", LOCKED_CLAIM_MISMATCH)
    end
    return LockedOutcome(#inline > 0 and "ok" or "none", nil,
        #inline > 0 and "inline" or "none", inlineFingerprint, inline)
end

local function RevisionValue(value)
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" then return nil end
    value = tostring(value)
    return value ~= "" and value or nil
end

local function ValidateBound(bound, expectedIdentity, expectedRevision,
    expectedToken, currentOrdinary, currentLocked)
    if tostring(expectedIdentity or "") ~= bound.identity
        or tostring(expectedToken or "") ~= bound.token then
        return false, "record identity changed"
    end
    if tostring(expectedRevision or "") ~= bound.revision then
        return false, bound.evidenceScoped and "record evidence changed"
            or "record projection changed"
    end
    local ordinary, ordinaryReason = NormalizePool(
        currentOrdinary or bound.ordinary, false)
    if not ordinary then return false, ordinaryReason end
    local locked, lockedReason = NormalizePool(
        currentLocked or bound.locked, true)
    if not locked then return false, lockedReason end
    if Token(bound.identity, ordinary, locked) ~= bound.token then
        return false, "record Echo evidence changed"
    end
    local provider = bound.currentEvidence or bound.currentRevision
    if provider then
        local ok, value = pcall(provider)
        if not ok or RevisionValue(value) ~= bound.revision then
            if bound.evidenceScoped then
                return false, ok and "record evidence changed"
                    or "record evidence unavailable"
            end
            return false, ok and "record projection changed"
                or "record projection unavailable"
        end
    end
    return true
end

function Evidence.Build(options)
    options = type(options) == "table" and options or {}
    local identity = options.sourceIdentity
    if (type(identity) ~= "string" and type(identity) ~= "number")
        or tostring(identity) == "" then
        return nil, "record identity is unavailable"
    end
    identity = tostring(identity)
    local selected = options.selectedEvidence
    local revision = RevisionValue(selected ~= nil
        and selected or options.sourceRevision)
    if not revision then
        return nil, selected ~= nil and "record evidence is unavailable"
            or "record revision is unavailable"
    end
    if selected ~= nil and options.sourceRevision ~= nil
        and RevisionValue(options.sourceRevision) ~= revision then
        return nil, "record evidence binding is inconsistent"
    end
    if options.currentEvidence ~= nil
        and type(options.currentEvidence) ~= "function" then
        return nil, "record evidence provider is invalid"
    end
    if options.currentRevision ~= nil
        and type(options.currentRevision) ~= "function" then
        return nil, "record revision provider is invalid"
    end
    if options.currentEvidence ~= nil and options.currentRevision ~= nil then
        return nil, "record evidence provider is ambiguous"
    end

    local ordinary, ordinaryReason = NormalizePool(
        options.ordinaryEchoes, false)
    if not ordinary then return nil, ordinaryReason end
    local locked, lockedReason = NormalizePool(
        options.lockedEchoes, true, false, true)
    if not locked then return nil, lockedReason end
    local token = Token(identity, ordinary, locked)
    local bound = {
        identity=identity, revision=revision, token=token,
        ordinary=DeepCopy(ordinary), locked=DeepCopy(locked),
        currentRevision=options.currentRevision,
        currentEvidence=options.currentEvidence,
        evidenceScoped=selected ~= nil or options.currentEvidence ~= nil,
    }
    local candidate = {
        evidenceKind=CURRENT_KIND,
        title=tostring(options.title or ""),
        ordinaryEchoes=ordinary,
        lockedEchoes=locked,
        sourceIdentity=identity,
        sourceRevision=revision,
        selectedEvidence=selected ~= nil and revision or nil,
        evidenceToken=token,
    }
    candidate.validate = function(expectedIdentity, expectedRevision,
        expectedToken, currentOrdinary, currentLocked)
        return ValidateBound(bound, expectedIdentity, expectedRevision,
            expectedToken, currentOrdinary, currentLocked)
    end
    return candidate
end

function Evidence.Validate(candidate)
    if type(candidate) ~= "table" then
        return nil, "candidate evidence is unavailable"
    end
    if candidate.evidenceKind ~= CURRENT_KIND
        and candidate.evidenceKind ~= LEGACY_KIND then
        return nil, "unsupported candidate evidence contract"
    end
    if type(candidate.validate) ~= "function" then
        return nil, "record validation is unavailable"
    end
    if candidate.selectedEvidence ~= nil
        and RevisionValue(candidate.selectedEvidence)
            ~= RevisionValue(candidate.sourceRevision) then
        return nil, "record evidence changed"
    end
    local ok, current, reason = pcall(candidate.validate,
        candidate.sourceIdentity, candidate.sourceRevision,
        candidate.evidenceToken, candidate.ordinaryEchoes,
        candidate.lockedEchoes)
    if not ok or current ~= true then
        return nil, tostring(ok and reason or "record validation failed")
    end
    local ordinary, ordinaryReason = NormalizePool(
        candidate.ordinaryEchoes, false)
    if not ordinary then return nil, ordinaryReason end
    local locked, lockedReason = NormalizePool(
        candidate.lockedEchoes, true, false, true)
    if not locked then return nil, lockedReason end
    return {
        evidenceKind=candidate.evidenceKind,
        title=tostring(candidate.title or ""),
        ordinaryEchoes=ordinary,
        lockedEchoes=locked,
        sourceIdentity=tostring(candidate.sourceIdentity),
        sourceRevision=tostring(candidate.sourceRevision),
        selectedEvidence=candidate.selectedEvidence ~= nil
            and tostring(candidate.selectedEvidence) or nil,
        evidenceToken=tostring(candidate.evidenceToken),
        validate=candidate.validate,
    }
end

function Evidence.CurrentKind()
    return CURRENT_KIND
end
