-- #47 first milestone: a local, session-only ordinary-alternative pool.
-- No frames, persistence, game reads, assignment, verification or actions.
Nexus = Nexus or {}
local Factory = {}
Nexus.FlexiblePlanModel = Factory

-- Allocation/admission bounds for this model, not native or evidence limits.
local MAX_ALTERNATIVES, MAX_ORDINARY, MAX_ID = 256, 79, 2147483647
local function Plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end
local function Integer(value, low, high)
    return type(value) == "number" and value == value
        and value >= low and value <= high and value == math.floor(value)
end
local function DenseLength(value, limit)
    if not Plain(value) then return nil end
    local count, highest = 0, 0
    for key in next, value do
        count = count + 1
        if count > limit or not Integer(key, 1, limit) then return nil end
        if key > highest then highest = key end
    end
    if count ~= highest then return nil end
    return count
end
local function OnlyFields(value, allowed, limit)
    local count = 0
    for key in next, value do
        count = count + 1
        if count > limit or not allowed[key] then return false end
    end
    return true
end
local function CopyRow(row)
    return {spellId=row.spellId, quality=row.quality, maxStack=row.maxStack,
        name=row.name, groupId=row.groupId}
end
local function HasRole(row)
    return rawget(row, "locked") ~= nil or rawget(row, "sourceRole") ~= nil
        or rawget(row, "lockIntent") ~= nil
end

function Factory.New(options)
    if not Plain(options) or not OnlyFields(options,
        {alternativeSpellIds=true, catalog=true}, 2) then
        return nil, "INVALID_OPTIONS"
    end
    local ids = rawget(options, "alternativeSpellIds")
    local count = DenseLength(ids, MAX_ALTERNATIVES)
    if not count or count == 0 then return nil, "INVALID_ALTERNATIVES" end
    local source = rawget(options, "catalog")
    local sourceRows = Plain(source) and rawget(source, "rows") or nil
    if not Plain(sourceRows) then return nil, "INVALID_CATALOG" end

    local rows, ordered = {}, {}
    for i = 1, count do
        local id = rawget(ids, i)
        if not Integer(id, 1, MAX_ID) then return nil, "INVALID_ALTERNATIVE" end
        if rows[id] then return nil, "DUPLICATE_ALTERNATIVE" end
        local row = rawget(sourceRows, id)
        if not Plain(row) then return nil, "INVALID_CATALOG" end
        if HasRole(row) then return nil, "UNSUPPORTED_ROLE" end
        local quality, maxStack = rawget(row, "quality"), rawget(row, "maxStack")
        local name, groupId = rawget(row, "name"), rawget(row, "groupId")
        if rawget(row, "spellId") ~= id or not Integer(quality, 0, 255)
            or not Integer(maxStack, 1, MAX_ID)
            or (name ~= nil and (type(name) ~= "string" or #name > 256))
            or (groupId ~= nil and not Integer(groupId, 0, MAX_ID)) then
            return nil, "INVALID_CATALOG"
        end
        rows[id] = {spellId=id, quality=quality, maxStack=maxStack,
            name=name, groupId=groupId}
        ordered[i] = id
    end
    local provider = Nexus.WishlistModel
    if type(provider) ~= "table" or type(provider.New) ~= "function" then
        return nil, "MODEL_UNAVAILABLE"
    end
    local exact = provider.New()
    local catalog = {rows=rows}
    local facade = {}

    function facade.Alternatives()
        local out = {}
        for i, id in ipairs(ordered) do out[i] = CopyRow(rows[id]) end
        return out
    end

    function facade.Choose(selection)
        local length = DenseLength(selection, MAX_ORDINARY)
        if not length or length == 0 then return nil, "INVALID_SELECTION" end
        local selected, seen, total = {}, {}, 0
        for i = 1, length do
            local row = rawget(selection, i)
            if not Plain(row) then return nil, "INVALID_SELECTION" end
            if HasRole(row) then
                return nil, "UNSUPPORTED_ROLE"
            end
            if not OnlyFields(row, {spellId=true, stacks=true}, 2) then
                return nil, "INVALID_SELECTION"
            end
            local id, stacks = rawget(row, "spellId"), rawget(row, "stacks")
            if not Integer(id, 1, MAX_ID) or not Integer(stacks, 1, MAX_ORDINARY) then
                return nil, "INVALID_SELECTION"
            end
            local member = rows[id]
            if not member then return nil, "NOT_IN_POOL" end
            if seen[id] then return nil, "DUPLICATE_SELECTION" end
            if stacks > member.maxStack then return nil, "STACK_LIMIT" end
            total = total + stacks
            if total > MAX_ORDINARY then return nil, "ORDINARY_LIMIT" end
            seen[id] = true
            selected[i] = {spellId=id, quality=member.quality, stacks=stacks}
        end

        -- Existing import/Copy normalizers can trim or infer roles. Use only
        -- exact draft operations, then prove a lossless canonical round trip.
        local pending = {}
        for _, row in ipairs(selected) do
            pending = exact.AddPending(pending, rows[row.spellId], {catalog=catalog})
            if row.stacks > 1 then
                pending = exact.AdjustStacks(pending,
                    exact.DraftKey(row.spellId, catalog), row.stacks - 1)
            end
        end
        local echoes = exact.CanonicalEchoes(pending)
        table.sort(selected, function(a, b) return a.spellId < b.spellId end)
        if #echoes ~= #selected then return nil, "DRAFT_MISMATCH" end
        for i, row in ipairs(selected) do
            local actual = echoes[i]
            if actual.spellId ~= row.spellId or actual.quality ~= row.quality
                or actual.stacks ~= row.stacks or actual.locked then
                return nil, "DRAFT_MISMATCH"
            end
        end
        return {pending=pending, pendingLock={}, fulfilledTargets={}, echoes=echoes}
    end

    return facade
end
