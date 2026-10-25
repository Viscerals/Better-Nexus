-- Nexus: core/FlexiblePlanStore.lua
-- #151 Stage A1: pure codec for the local manual-choice pool record v1
-- (docs/flexible-plans/LOCAL_PERSISTENCE_CONTRACT.md section 2). No frames,
-- Store, SavedVariables, catalog or game reads, draft normalizers, assignment
-- or actions in Encode/Decode. New({store}) at the end of this file is the
-- frame-free persistence owner (Stage A2); it reads through the Store's pure
-- PlanPoolReadV1 seam and writes only through the counted UpdateStateV1.
--
-- Encode(ids, rows, chosen) -> record, bytes | nil, nil (clear) | nil, code
--   ids     plain dense array of 1..256 distinct integer IDs, insertion order.
--   rows    plain map id -> plain {spellId, quality, maxStack, groupId?, name?};
--           exactly one distinct row per ID. name is checked, never stored.
--           locked/sourceRole/lockIntent refuse UNSUPPORTED_ROLE; any other
--           field refuses UNKNOWN_FIELD.
--   chosen  plain map id -> integer count; absent and an explicit 0 both mean
--           unchosen. Counts are 0..min(79, maxStack), total <= 79.
--   Only plain, entry-free ids/rows/chosen return nil, nil (clear the key).
--   Refusal codes: INVALID_INPUT ALIASED_INPUT INVALID_IDS
--   TOO_MANY_ALTERNATIVES INVALID_ID DUPLICATE_ID ROW_MISMATCH INVALID_ROW
--   ALIASED_ROW UNSUPPORTED_ROLE UNKNOWN_FIELD NOT_IN_POOL INVALID_COUNT
--   STACK_LIMIT ORDINARY_LIMIT. Nothing is trimmed, clamped or substituted.
-- Decode(record) -> pool, bytes, "CURRENT" | nil, class, detail
--   ABSENT      record is nil.
--   FUTURE      raw version is an exact integer > 1; checked before traversal.
--   MALFORMED   bad type, metatable, version missing or other than 1, alias,
--               cycle, sparse/unequal/empty arrays, bad value, duplicate ID,
--               count above maxStack or a total above 79.
--   UNSUPPORTED v1 with an unknown or a missing field.
--   OVERSIZED   an array past 256 entries or index 256.
--   With several defects the first one found classifies; only CURRENT loads.
--   pool = {ids = dense array, rows = id -> {spellId, quality, maxStack,
--   groupId?} (absent group is nil, no name), chosen = id -> count > 0}.
--   Every returned table is fresh; nothing aliases the record or a caller.
-- Bounds: next, rawget and rawequal only, so no metamethod runs. Arrays stop
-- at entry 257, maps at the first key outside the pool and records at the
-- first unknown root key; huge tables are never walked. Canonical bytes are
-- "v1|" then "id,quality,maxStack,group,count;" per row, absent group -1.
Nexus = Nexus or {}
local Codec = {}
Nexus.FlexiblePlanStore = Codec

-- Application admission bounds (contract section 2), not native limits.
local MAX_ALTERNATIVES, MAX_ORDINARY, MAX_ID = 256, 79, 2147483647
local MAX_QUALITY, MAX_NAME_BYTES = 255, 256
local ARRAYS = {"ids", "quality", "maxStack", "groupId", "counts"}
local ROOT_FIELDS = {version=true, ids=true, quality=true, maxStack=true,
    groupId=true, counts=true}
local ROW_FIELDS = {spellId=true, quality=true, maxStack=true, groupId=true,
    name=true}
local ROLE_FIELDS = {"locked", "sourceRole", "lockIntent"}

local function Plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end

local function Integer(value, low, high)
    return type(value) == "number" and value == value and value >= low
        and value <= high and value == math.floor(value)
end

-- Length of a plain 1..n array, or nil plus "OVERSIZED"/"MALFORMED". Visits
-- at most MAX_ALTERNATIVES + 1 entries.
local function DenseScan(value)
    local count, highest = 0, 0
    for key in next, value do
        count = count + 1
        if count > MAX_ALTERNATIVES then return nil, "OVERSIZED" end
        if not Integer(key, 1, MAX_ID) then return nil, "MALFORMED" end
        if key > MAX_ALTERNATIVES then return nil, "OVERSIZED" end
        if key > highest then highest = key end
    end
    if count ~= highest then return nil, "MALFORMED" end
    return count
end

local function CanonicalBytes(ids, quality, maxStack, groupId, counts, n)
    local parts = {"v1|"}
    for i = 1, n do
        parts[i + 1] = string.format("%d,%d,%d,%d,%d;", ids[i], quality[i],
            maxStack[i], groupId[i], counts[i])
    end
    return table.concat(parts)
end

function Codec.Encode(ids, rows, chosen)
    if not Plain(ids) or not Plain(rows) or not Plain(chosen) then
        return nil, "INVALID_INPUT"
    end
    if rawequal(ids, rows) or rawequal(ids, chosen) or rawequal(rows, chosen) then
        return nil, "ALIASED_INPUT"
    end
    local n, defect = DenseScan(ids)
    if not n then
        return nil, defect == "OVERSIZED" and "TOO_MANY_ALTERNATIVES" or "INVALID_IDS"
    end
    if n == 0 then
        if next(rows) ~= nil then return nil, "ROW_MISMATCH" end
        if next(chosen) ~= nil then return nil, "NOT_IN_POOL" end
        return nil, nil
    end
    local index, seenRows = {}, {}
    local outIds, outQuality, outMax, outGroup, outCounts = {}, {}, {}, {}, {}
    for i = 1, n do
        local id = rawget(ids, i)
        if not Integer(id, 1, MAX_ID) then return nil, "INVALID_ID" end
        if index[id] then return nil, "DUPLICATE_ID" end
        index[id] = i
        local row = rawget(rows, id)
        if row == nil then return nil, "ROW_MISMATCH" end
        if not Plain(row) then return nil, "INVALID_ROW" end
        if rawequal(row, ids) or rawequal(row, rows) or rawequal(row, chosen)
            or seenRows[row] then
            return nil, "ALIASED_ROW"
        end
        seenRows[row] = true
        for _, field in ipairs(ROLE_FIELDS) do
            if rawget(row, field) ~= nil then return nil, "UNSUPPORTED_ROLE" end
        end
        -- Every key must be known, so at most five keys are visited.
        for key in next, row do
            if not ROW_FIELDS[key] then return nil, "UNKNOWN_FIELD" end
        end
        local quality, maxStack = rawget(row, "quality"), rawget(row, "maxStack")
        local groupId, name = rawget(row, "groupId"), rawget(row, "name")
        if rawget(row, "spellId") ~= id then return nil, "ROW_MISMATCH" end
        if not Integer(quality, 0, MAX_QUALITY) or not Integer(maxStack, 1, MAX_ID)
            or (groupId ~= nil and not Integer(groupId, 0, MAX_ID))
            or (name ~= nil and (type(name) ~= "string" or #name > MAX_NAME_BYTES)) then
            return nil, "INVALID_ROW"
        end
        outIds[i], outQuality[i], outMax[i] = id, quality, maxStack
        outGroup[i], outCounts[i] = groupId == nil and -1 or groupId, 0
    end
    -- Keys are distinct and all IDs have rows, so any extra key is outside
    -- the pool: the scan stops at it after at most n + 1 visits.
    local rowCount = 0
    for key in next, rows do
        rowCount = rowCount + 1
        if rowCount > n or index[key] == nil then return nil, "ROW_MISMATCH" end
    end
    local total = 0
    for key, count in next, chosen do
        local i = index[key]
        if i == nil then return nil, "NOT_IN_POOL" end
        if not Integer(count, 0, MAX_ORDINARY) then return nil, "INVALID_COUNT" end
        if count > outMax[i] then return nil, "STACK_LIMIT" end
        total = total + count
        if total > MAX_ORDINARY then return nil, "ORDINARY_LIMIT" end
        outCounts[i] = count
    end
    local record = {version=1, ids=outIds, quality=outQuality, maxStack=outMax,
        groupId=outGroup, counts=outCounts}
    return record, CanonicalBytes(outIds, outQuality, outMax, outGroup, outCounts, n)
end

local function Refuse(class, detail)
    return nil, class, detail
end

function Codec.Decode(record)
    if record == nil then return Refuse("ABSENT", "NO_RECORD") end
    if type(record) ~= "table" then return Refuse("MALFORMED", "TYPE") end
    if getmetatable(record) ~= nil then return Refuse("MALFORMED", "METATABLE") end
    local version = rawget(record, "version")
    if type(version) == "number" and version == version and version > 1
        and version < math.huge and version == math.floor(version) then
        return Refuse("FUTURE", "VERSION")
    end
    if version ~= 1 then return Refuse("MALFORMED", "VERSION") end
    -- Every root key must be known, so at most six keys are visited.
    for key in next, record do
        if not ROOT_FIELDS[key] then return Refuse("UNSUPPORTED", "UNKNOWN_FIELD") end
    end
    local arrays = {}
    for f, field in ipairs(ARRAYS) do
        arrays[f] = rawget(record, field)
        if arrays[f] == nil then return Refuse("UNSUPPORTED", "MISSING_FIELD") end
    end
    for f, value in ipairs(arrays) do
        if type(value) ~= "table" then return Refuse("MALFORMED", "TYPE") end
        if getmetatable(value) ~= nil then return Refuse("MALFORMED", "METATABLE") end
        if rawequal(value, record) then return Refuse("MALFORMED", "ALIAS") end
        for g = 1, f - 1 do
            if rawequal(value, arrays[g]) then return Refuse("MALFORMED", "ALIAS") end
        end
    end
    local n
    for _, value in ipairs(arrays) do
        local length, defect = DenseScan(value)
        if not length then
            return Refuse(defect, defect == "OVERSIZED" and "LENGTH" or "SPARSE")
        end
        if n == nil then
            n = length
        elseif length ~= n then
            return Refuse("MALFORMED", "LENGTH")
        end
    end
    if n == 0 then return Refuse("MALFORMED", "EMPTY") end
    local ids, quality, maxStack = arrays[1], arrays[2], arrays[3]
    local groupId, counts = arrays[4], arrays[5]
    local outIds, outQuality, outMax, outGroup, outCounts = {}, {}, {}, {}, {}
    local seen, total = {}, 0
    for i = 1, n do
        local id, q, m = rawget(ids, i), rawget(quality, i), rawget(maxStack, i)
        local g, c = rawget(groupId, i), rawget(counts, i)
        if not Integer(id, 1, MAX_ID) or not Integer(q, 0, MAX_QUALITY)
            or not Integer(m, 1, MAX_ID) or not (g == -1 or Integer(g, 0, MAX_ID))
            or not Integer(c, 0, MAX_ORDINARY) then
            return Refuse("MALFORMED", "VALUE")
        end
        if seen[id] then return Refuse("MALFORMED", "DUPLICATE_ID") end
        if c > m then return Refuse("MALFORMED", "STACK_LIMIT") end
        total = total + c
        if total > MAX_ORDINARY then return Refuse("MALFORMED", "ORDINARY_LIMIT") end
        seen[id] = true
        outIds[i], outQuality[i], outMax[i], outGroup[i], outCounts[i] = id, q, m, g, c
    end
    -- Build the session only after the whole record validated (atomic).
    local rows, chosen = {}, {}
    for i = 1, n do
        local id, g = outIds[i], outGroup[i]
        rows[id] = {spellId=id, quality=outQuality[i], maxStack=outMax[i],
            groupId=g ~= -1 and g or nil}
        if outCounts[i] > 0 then chosen[id] = outCounts[i] end
    end
    return {ids=outIds, rows=rows, chosen=chosen},
        CanonicalBytes(outIds, outQuality, outMax, outGroup, outCounts, n), "CURRENT"
end

-- ===================================================================
-- New({store}) -> facade | nil, "INVALID_STORE" (contract sections 5-6).
-- Frame-free owner of the one per-character pool. Every call re-resolves
-- Nexus.MainInternals.StoreAuthorityOwner and requires its `owner` to be
-- exactly `store`: a stub or reloaded Store module refuses
-- STORE_OWNER_MISMATCH; nothing falls back to Store.State or a transient row.
--   Read() -> receipt {mode, reason, class, detail, ownerKey, root, pool,
--     bytes, visited, carried, rowPresent, loadable, saveable}. class is nil
--     while loading/unavailable. Fresh tables on every call.
--   Save(session, receipt) -> {state, reason, detail, bytes, unchanged,
--     restored, receipt}. "saved" only after a durable read-back of the exact
--     bytes, owner key and root; "refused" wrote nothing; "unverified" says
--     whether the prior record identity was restored and read back. The
--     receipt must be one THIS facade issued (Read or an earlier Save); its
--     owner key, root token, class and bytes must all still hold, so equal
--     bytes of another character, root or generation never authorize.
--   Clear(receipt) = Save of an empty session (removes the key).
-- Never calls the adapter, controllers, Sync, Orb, registration or the
-- coordinator mutation machine; never assigns, uploads, shares or spends.
-- ===================================================================
local POOL_KEY = "flexiblePlanPoolV1"
local MODE_REFUSAL = {readOnly="READ_ONLY", loading="LOADING", unavailable="UNAVAILABLE"}

local function OwnerFor(store)
    local internals = type(Nexus) == "table" and rawget(Nexus, "MainInternals") or nil
    local owner = type(internals) == "table" and rawget(internals, "StoreAuthorityOwner") or nil
    if type(owner) ~= "table" or not rawequal(rawget(owner, "owner"), store) then
        return nil, "STORE_OWNER_MISMATCH"
    end
    if rawget(owner, "PLAN_POOL_KEY") ~= POOL_KEY
        or type(rawget(owner, "PlanPoolReadV1")) ~= "function"
        or type(rawget(owner, "IsDurableStateRowV1")) ~= "function"
        or type(rawget(owner, "UpdateStateV1")) ~= "function" then
        return nil, "STORE_SEAM_UNAVAILABLE"
    end
    return owner
end

local function ReadPool(owner)
    local raw = owner.PlanPoolReadV1()
    if type(raw) ~= "table" then error("pool seam returned no read", 0) end
    local read = {mode=raw.mode, reason=raw.reason, ownerKey=raw.ownerKey,
        root=raw.root, visited=raw.visited or 0, carried=raw.carried == true,
        rowPresent=raw.rowPresent == true}
    if read.mode ~= "durable" and read.mode ~= "readOnly" then return read end
    if raw.refusal ~= nil then
        read.class, read.detail = raw.refusal, raw.detail
    elseif not raw.present then
        read.class, read.detail = "ABSENT", "NO_RECORD"
    elseif raw.copy == nil then
        read.class, read.detail = "MALFORMED", "COPY"
    else
        local pool, second, third = Codec.Decode(raw.copy)
        if pool ~= nil then
            read.class, read.pool, read.bytes = third, pool, second
        else
            read.class, read.detail = second, third
        end
    end
    return read
end

local function Matches(read, want)
    return read.mode == "durable" and read.ownerKey == want.ownerKey
        and read.root == want.root and read.class == want.class
        and read.bytes == want.bytes
end

local function Result(state, reason, detail, extra)
    local out = {state=state, reason=reason, detail=detail}
    if extra then for key, value in next, extra do out[key] = value end end
    return out
end

function Codec.New(options)
    local store = Plain(options) and rawget(options, "store") or nil
    if type(store) ~= "table" then return nil, "INVALID_STORE" end
    -- Private facts per issued receipt; weak keys, never read from the
    -- (caller-mutable) receipt fields.
    local issued = setmetatable({}, {__mode="k"})
    local facade = {}
    local function Issue(owner, read)
        read.loadable = read.class == "CURRENT"
            and (read.mode == "durable" or read.mode == "readOnly")
        read.saveable = read.mode == "durable"
            and (read.class == "ABSENT" or read.class == "CURRENT")
        issued[read] = {owner=owner, mode=read.mode, ownerKey=read.ownerKey,
            root=read.root, class=read.class, bytes=read.bytes}
        return read
    end

    function facade.Read()
        local owner, why = OwnerFor(store)
        if not owner then
            return {mode="unavailable", reason=why, visited=0, loadable=false, saveable=false}
        end
        local ok, read = pcall(ReadPool, owner)
        if not ok then
            return {mode="unavailable", reason="READ_FAILED", visited=0,
                loadable=false, saveable=false}
        end
        return Issue(owner, read)
    end

    function facade.Save(session, observed)
        local owner, why = OwnerFor(store)
        if not owner then return Result("refused", why) end
        local facts = type(observed) == "table" and issued[observed] or nil
        if facts == nil then return Result("refused", "RECEIPT_UNKNOWN") end
        if not rawequal(facts.owner, owner) then return Result("refused", "STORE_OWNER_MISMATCH") end
        if not Plain(session) then return Result("refused", "INVALID_SESSION", "INVALID_INPUT") end
        -- Exact shapes before any write: fresh tables, nil,nil only when empty.
        local record, newBytes = Codec.Encode(rawget(session, "ids"),
            rawget(session, "rows"), rawget(session, "chosen"))
        if record == nil and newBytes ~= nil then
            return Result("refused", "INVALID_SESSION", newBytes)
        end
        local okPre, pre = pcall(ReadPool, owner)
        if not okPre then return Result("refused", "READ_FAILED") end
        if pre.mode ~= "durable" then
            return Result("refused", MODE_REFUSAL[pre.mode] or "UNAVAILABLE", pre.reason)
        end
        if pre.class ~= "ABSENT" and pre.class ~= "CURRENT" then
            return Result("refused", "SAVED_" .. tostring(pre.class), pre.detail)
        end
        if facts.mode ~= "durable" then return Result("refused", "RECEIPT_NOT_DURABLE") end
        if pre.ownerKey ~= facts.ownerKey then return Result("refused", "OWNER_CHANGED") end
        if pre.root ~= facts.root then return Result("refused", "ROOT_CHANGED") end
        if pre.class ~= facts.class or pre.bytes ~= facts.bytes then
            return Result("refused", "SAVED_CHANGED")
        end
        local want = {ownerKey=pre.ownerKey, root=pre.root,
            class=record ~= nil and "CURRENT" or "ABSENT", bytes=newBytes}
        if want.class == pre.class and want.bytes == pre.bytes then
            return Result("saved", nil, nil, {unchanged=true, bytes=newBytes,
                receipt=Issue(owner, pre)})
        end
        local outcome = {}
        -- Runs inside the counted UpdateStateV1. Its true result is never
        -- trusted: the row must be the live durable row and the stored facts
        -- must still be the pre-read facts before the one rawset.
        local function Mutator(row)
            if not rawequal(OwnerFor(store), owner) then
                outcome.refusal = "STORE_OWNER_MISMATCH"; return
            end
            if owner.IsDurableStateRowV1(row) ~= true then
                outcome.refusal = "NOT_DURABLE"; return
            end
            local okNested, nested = pcall(ReadPool, owner)
            if not okNested or not Matches(nested, pre) or not nested.rowPresent
                or nested.carried then
                outcome.refusal = okNested and "SAVED_CHANGED" or "READ_FAILED"; return
            end
            local old = rawget(row, POOL_KEY)
            if (old == nil) ~= (pre.class == "ABSENT") then
                outcome.refusal = "SAVED_CHANGED"; return
            end
            rawset(row, POOL_KEY, record)
            outcome.written, outcome.row, outcome.old = true, row, old
            local okVerify, verify = pcall(ReadPool, owner)
            if okVerify and Matches(verify, want) and verify.rowPresent then
                outcome.verified = true; return
            end
            -- Immediate semantic rollback inside the same owner mutator.
            outcome.detail = okVerify and "VERIFY_MISMATCH" or "VERIFY_ERROR"
            if rawequal(rawget(row, POOL_KEY), record) then
                rawset(row, POOL_KEY, old)
                outcome.restored = rawequal(rawget(row, POOL_KEY), old)
            end
        end
        local okUpdate = pcall(owner.UpdateStateV1, Mutator)
        if not outcome.written then
            return Result("refused", outcome.refusal
                or (okUpdate and "WRITE_FAILED" or "WRITE_ERROR"), outcome.detail)
        end
        if okUpdate and outcome.verified then
            local okPost, post = pcall(ReadPool, owner)
            if okPost and rawequal(OwnerFor(store), owner) and Matches(post, want) then
                return Result("saved", nil, nil, {bytes=newBytes, receipt=Issue(owner, post)})
            end
            outcome.detail = okPost and "POST_READ_MISMATCH" or "POST_READ_ERROR"
        elseif not okUpdate then
            outcome.detail = outcome.detail or "UPDATE_ERROR"
        end
        -- Rollback restores the prior record only while the live value is
        -- still this Save's record: a newer operation's record is never
        -- overwritten, and nothing is written through a replaced owner.
        local restored = outcome.restored == true
        if not restored and rawequal(OwnerFor(store), owner) then
            pcall(owner.UpdateStateV1, function(row)
                if rawequal(row, outcome.row) and owner.IsDurableStateRowV1(row) == true
                    and rawequal(rawget(row, POOL_KEY), record) then
                    rawset(row, POOL_KEY, outcome.old)
                    restored = rawequal(rawget(row, POOL_KEY), outcome.old)
                end
            end)
        end
        local okAfter, after = pcall(ReadPool, owner)
        return Result("unverified", "SAVE_UNVERIFIED", outcome.detail, {
            restored=restored and okAfter and Matches(after, pre) or false,
            receipt=okAfter and Issue(owner, after) or nil})
    end

    function facade.Clear(observed)
        return facade.Save({ids={}, rows={}, chosen={}}, observed)
    end
    return facade
end
