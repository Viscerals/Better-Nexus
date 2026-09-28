-- Nexus: logic/Strategy.lua
-- Wishlist -> plan compiler. PURE (no WoW API, no ProjectEbonhold, no
-- SavedVariables) so every rule is testable under bare LuaJIT.
--
-- The lever plan partitions catalog.levers into exactly three buckets:
--   skippedNonConformant  NEVER toggled (e.g. the requiredSpell=9
--                         garbage cohort shared by 38 unrelated rows --
--                         a "9|0" send has unknown server blast radius)
--   keep                  at least one member's family is wished, or
--                         the user opted the lever out
--   disable               conformant, not opted out, every member
--                         family off-wishlist
-- Strategy only partitions; conformance itself is adapter-computed
-- (name-exact "Tome of <member name>" rule) and read from the catalog.

Nexus = Nexus or {}
local M = {}
Nexus.Strategy = M

-- Type-safe ascending order: a malformed lever key must not error the
-- sort (numbers first, ascending; anything else by tostring).
local function AscendingKey(a, b)
    local na, nb = type(a) == "number", type(b) == "number"
    if na and nb then return a < b end
    if na ~= nb then return na end
    return tostring(a) < tostring(b)
end

function M.Compile(catalog, wishlist, settings)
    if type(catalog) ~= "table" then catalog = {} end
    if type(settings) ~= "table" then settings = {} end
    -- A malformed wishlist degrades to advisor-only, never errors.
    if type(wishlist) ~= "table" then wishlist = nil end

    local byFamily = (wishlist and type(wishlist.byFamily) == "table")
        and wishlist.byFamily or {}
    local familyOf = type(catalog.familyOf) == "table"
        and catalog.familyOf or {}
    local rows = type(catalog.rows) == "table" and catalog.rows or {}
    local levers = type(catalog.levers) == "table" and catalog.levers or {}
    local optOut = type(settings.leverOptOut) == "table"
        and settings.leverOptOut or {}

    local wishedFamilies = {}
    for familyKey in pairs(byFamily) do
        wishedFamilies[familyKey] = true
    end

    local disable, keep, skipped = {}, {}, {}
    for leverId, lever in pairs(levers) do
        if type(lever) ~= "table" or not lever.conformant then
            skipped[#skipped + 1] = leverId
        else
            local wanted = optOut[leverId] and true or false
            if not wanted then
                local members = type(lever.members) == "table"
                    and lever.members or {}
                for _, spellId in ipairs(members) do
                    local fam = familyOf[spellId]
                    if fam ~= nil and wishedFamilies[fam] then
                        wanted = true
                        break
                    end
                end
            end
            if wanted then
                keep[#keep + 1] = leverId
            else
                disable[#disable + 1] = leverId
            end
        end
    end
    table.sort(disable, AscendingKey)
    table.sort(keep, AscendingKey)
    table.sort(skipped, AscendingKey)

    -- Anchor only when the anchor is an EXACT wishlist spellId that
    -- resolves to a catalog row (addendum A5: exact-spellId match, never a
    -- family/groupId sibling of a wished echo); otherwise the diversity
    -- term stays inert.
    local wishedIds = {}
    if wishlist and type(wishlist.entries) == "table" then
        for _, e in ipairs(wishlist.entries) do
            if type(e) == "table" and e.spellId then wishedIds[e.spellId] = true end
        end
    end
    local anchor = settings.anchorSpellId
    if anchor == nil or rows[anchor] == nil or not wishedIds[anchor] then
        anchor = nil
        -- auto-detect: the wishlist echo whose catalog name matches a
        -- configured anchor name (e.g. "Adaptive Power"). Uses the EXACT
        -- wishlist spellId (addendum A5), never a family sibling.
        local anchorNames = {}
        for _, nm in ipairs(settings.anchorNames or {}) do
            anchorNames[tostring(nm):lower()] = true
        end
        if wishlist and type(wishlist.entries) == "table" and next(anchorNames) then
            for _, e in ipairs(wishlist.entries) do
                local row = e and e.spellId and rows[e.spellId]
                local nm = row and row.name and tostring(row.name):lower()
                if nm and anchorNames[nm] then anchor = e.spellId; break end
            end
        end
    end

    local requestedCounts = {}
    for _, entry in ipairs(wishlist and wishlist.entries or {}) do
        if type(entry) == "table" then
            local id, count = tonumber(entry.spellId), tonumber(entry.stacks) or 1
            if id and id > 0 and id == math.floor(id)
                and count > 0 and count == math.floor(count) then
                requestedCounts[id] = (requestedCounts[id] or 0) + count
            end
        end
    end

    return {
        requestedCounts = requestedCounts,
        targets = byFamily,
        wishedFamilies = wishedFamilies,
        anchorSpellId = anchor,
        leverPlan = {
            disable = disable,
            keep = keep,
            skippedNonConformant = skipped,
        },
        advisorOnly = (wishlist == nil),
    }
end
