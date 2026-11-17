-- Pure Project Ebonhold Echo-catalog materialization.
--
-- This module never reads Project Ebonhold globals. GameAdapter captures the
-- source table and spell-name resolver, then publishes only a complete result.

Nexus = Nexus or {}

local Source = {}
Nexus.EchoCatalogSource = Source

local function SafeText(value)
    local ok, text = pcall(tostring, value)
    return ok and tostring(text or "") or "unprintable catalog error"
end
local function Number(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge then return fallback end
    return number
end

local function Encode(value)
    local kind = type(value)
    local text
    if kind == "string" then text = value
    elseif kind == "number" then text = tostring(value)
    elseif kind == "boolean" then text = value and "1" or "0"
    elseif kind == "nil" then text = ""
    else error("non-scalar normalized catalog value") end
    return kind:sub(1, 1) .. tostring(#text) .. ":" .. text
end

local function HashText(text)
    local hash = 5381
    for index = 1, #text do
        hash = ((hash * 33) + text:byte(index)) % 2147483648
    end
    return string.format("%08x", hash)
end

local function ResolveName(resolveSpell, spellId)
    if type(resolveSpell) ~= "function" then return nil end
    local value = resolveSpell(spellId)
    if value ~= nil and type(value) ~= "string" then
        error("spell-name resolver returned a non-string value")
    end
    return value
end

local function EchoName(row, spellId, resolveSpell)
    local name = ResolveName(resolveSpell, spellId)
    if name ~= nil then return name end
    local comment = tostring(row.comment or "")
    return (comment:gsub(" %- %a+$", ""))
end

-- Updated client (wow.export 0.2.19 capture, perks_data.lua header and
-- perks_service.lua 537, 822): a row's requiredSpell is taught by a Tome of
-- Echo only when the row says isTome = true; otherwise it is a talent gate,
-- and the game's tome switch refuses it. A database that marks any row
-- isTome = true uses that contract: there, the normalized requiredSpell
-- keeps only tome gates (the tome lever every consumer reads) and a talent
-- gate is kept as talentSpell (a real requirement, never a tome). A database
-- with no isTome mark at all (the older provider) normalizes exactly as
-- before, with talentSpell 0, and keeps its earlier canonical text and hash.
-- Only a row Materialize takes (a number spellId and a table with maxStack)
-- decides the contract, so a row it skips can never change it, and the
-- bounded row verifier (VerifyRow) sees every row that can.
local function TomeContract(database)
    for spellId, row in pairs(database) do
        if type(spellId) == "number" and Number(spellId) ~= nil
            and type(row) == "table" and row.maxStack and row.isTome == true then
            return true
        end
    end
    return false
end
local function Gates(row, tomeContract)
    local required = Number(row.requiredSpell, 0)
    if tomeContract and required ~= 0 and row.isTome ~= true then return 0, required end
    return required, 0
end

local function MaterializeUnsafe(database, resolveSpell)
    if type(database) ~= "table" then error("PerkDatabase must be a table") end
    local tomeContract = TomeContract(database)

    local spellIds = {}
    for spellId, row in pairs(database) do
        if type(spellId) == "number" and Number(spellId) ~= nil
            and type(row) == "table" and row.maxStack then
            spellIds[#spellIds + 1] = spellId
        end
    end
    table.sort(spellIds)

    local rows, groupCount = {}, {}
    for _, spellId in ipairs(spellIds) do
        local row = database[spellId]
        local tomeGate, talentGate = Gates(row, tomeContract)
        local normalized = {
            spellId=spellId,
            name=EchoName(row, spellId, resolveSpell),
            maxStack=Number(row.maxStack, 1),
            classMask=Number(row.classMask, 0),
            minLevel=Number(row.minLevel, 1),
            quality=Number(row.quality, 0),
            groupId=Number(row.groupId, 0),
            requiredSpell=tomeGate,
            talentSpell=talentGate,
            -- The row's own isTome mark, kept apart from its normalized gates
            -- (third Spec review): a mark on a row whose requiredSpell is 0
            -- changes no gate, yet it alone can decide the whole contract.
            tomeMark=row.isTome == true,
        }
        rows[spellId] = normalized
        if normalized.groupId > 0 then
            groupCount[normalized.groupId] = (groupCount[normalized.groupId] or 0) + 1
        end
    end

    local familyOf, familyMembers, familyName = {}, {}, {}
    for _, spellId in ipairs(spellIds) do
        local row = rows[spellId]
        local family = row.groupId > 0 and (groupCount[row.groupId] or 0) > 1
            and ("g" .. tostring(row.groupId)) or ("s" .. tostring(spellId))
        familyOf[spellId] = family
        local members = familyMembers[family]
        if not members then members = {}; familyMembers[family] = members end
        members[#members + 1] = spellId
        if familyName[family] == nil then familyName[family] = row.name end
    end

    local levers = {}
    for _, spellId in ipairs(spellIds) do
        local row = rows[spellId]
        if row.requiredSpell ~= 0 then
            local lever = levers[row.requiredSpell]
            if not lever then
                lever = {
                    lever=row.requiredSpell,
                    members={},
                    conformant=true,
                    tomeName=ResolveName(resolveSpell, row.requiredSpell),
                }
                levers[row.requiredSpell] = lever
            end
            lever.members[#lever.members + 1] = spellId
            if lever.tomeName ~= ("Tome of " .. row.name) then
                lever.conformant = false
            end
        end
    end

    -- The isTome contract has its own identity: its header names it and each
    -- row adds its talent gate. The older text is unchanged.
    local canonical = {tomeContract and "catalog-source-v2-istome" or "catalog-source-v1"}
    for _, spellId in ipairs(spellIds) do
        local row = rows[spellId]
        local parts = {
            Encode(row.spellId), Encode(row.name), Encode(row.maxStack),
            Encode(row.classMask), Encode(row.minLevel), Encode(row.quality),
            Encode(row.groupId), Encode(row.requiredSpell),
            Encode(row.requiredSpell ~= 0 and levers[row.requiredSpell].tomeName or nil),
        }
        -- Under the contract each row also states its own mark (fourth Root
        -- check): a mark moved or removed between zero-gate rows changes no
        -- gate, so without it the identity would stay equal and the atomic
        -- check would keep the stale catalog. The older text has neither part.
        if tomeContract then
            parts[#parts + 1] = Encode(row.talentSpell)
            parts[#parts + 1] = Encode(row.tomeMark)
        end
        canonical[#canonical + 1] = table.concat(parts)
    end
    canonical = table.concat(canonical)

    return {
        rows=rows,
        familyOf=familyOf,
        familyMembers=familyMembers,
        familyName=familyName,
        levers=levers,
        rowCount=#spellIds,
        tomeContract=tomeContract,
    }, canonical, HashText(canonical)
end

function Source.Materialize(database, resolveSpell)
    local ok, candidate, canonical, hash = pcall(
        MaterializeUnsafe, database, resolveSpell)
    if not ok then return nil, SafeText(candidate) end
    return candidate, canonical, hash
end

-- Number equality as the canonical text sees it: Encode writes tostring, so
-- 0 and -0 differ there although they compare equal.
local function SameNumber(left, right)
    if left ~= right then return false end
    return left ~= 0 or 1 / left == 1 / right
end

-- "skip" for a source entry that Materialize does not take, true when the row
-- normalizes to the published row (name and lever tome name resolved again),
-- false when it differs. Reads one row, at most two names. Never publishes.
local function VerifyRowUnsafe(catalog, spellId, row, resolveSpell)
    if not (type(spellId) == "number" and Number(spellId) ~= nil
        and type(row) == "table" and row.maxStack) then return "skip" end
    local published = catalog.rows[spellId]
    if type(published) ~= "table" then return false end
    if EchoName(row, spellId, resolveSpell) ~= published.name then return false end
    -- The row is normalized under the contract the published catalog used.
    -- Second Spec review: a first isTome mark added in place under a catalog
    -- published without the contract changes the whole contract (every
    -- talent gate, and the canonical identity), so that row does not verify
    -- and the caller falls back to its atomic check and rebuild. A mark
    -- removed or moved under the contract changes that row's gates below.
    if catalog.tomeContract ~= true and row.isTome == true then return false end
    -- Any change of the row's own mark (added, removed or moved, whatever its
    -- gates) can change the contract, so it never verifies: the caller falls
    -- back to its atomic check, which decides the contract again.
    if (row.isTome == true) ~= (published.tomeMark == true) then return false end
    local requiredSpell, talentSpell = Gates(row, catalog.tomeContract == true)
    if not SameNumber(talentSpell, tonumber(published.talentSpell) or 0) then return false end
    if not (SameNumber(Number(row.maxStack, 1), published.maxStack)
        and SameNumber(Number(row.classMask, 0), published.classMask)
        and SameNumber(Number(row.minLevel, 1), published.minLevel)
        and SameNumber(Number(row.quality, 0), published.quality)
        and SameNumber(Number(row.groupId, 0), published.groupId)
        and SameNumber(requiredSpell, published.requiredSpell)) then
        return false
    end
    if requiredSpell ~= 0 then
        local lever = catalog.levers[requiredSpell]
        if type(lever) ~= "table" then return false end
        if ResolveName(resolveSpell, requiredSpell) ~= lever.tomeName then return false end
    end
    return true
end

function Source.VerifyRow(catalog, spellId, row, resolveSpell)
    local ok, result = pcall(VerifyRowUnsafe, catalog, spellId, row, resolveSpell)
    if not ok then return nil, SafeText(result) end
    return result
end

function Source.FamilyDrift(previous, candidate)
    local oldFamilies = type(previous) == "table" and previous.familyOf or nil
    local newFamilies = type(candidate) == "table" and candidate.familyOf or nil
    if type(oldFamilies) ~= "table" or type(newFamilies) ~= "table" then
        return nil
    end
    local spellIds = {}
    for spellId in pairs(oldFamilies) do
        if type(spellId) == "number" and newFamilies[spellId] ~= nil then
            spellIds[#spellIds + 1] = spellId
        end
    end
    table.sort(spellIds)
    for _, spellId in ipairs(spellIds) do
        if oldFamilies[spellId] ~= newFamilies[spellId] then
            return {
                spellId=spellId,
                before=oldFamilies[spellId],
                after=newFamilies[spellId],
            }
        end
    end
    return nil
end
