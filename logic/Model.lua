-- Nexus: logic/Model.lua
-- Pure math layer: name normalization (forked verbatim from the
-- EchoOptimizer sibling), the ordinal wishlist value function Delta,
-- the free-slot support enumerator, and the discretized draw
-- distribution with its order-statistic helpers.
-- No WoW API calls, no SavedVariables access; runs under plain Lua 5.1.

Nexus = Nexus or {}
local Model = {}
Nexus.Model = Model

------------------------------------------------------------------------
-- Names (verbatim fork: EchoOptimizer/logic/Model.lua)
------------------------------------------------------------------------

-- Server comment keys use curly apostrophes; hand-written config uses
-- straight ones. Both must compare equal.
function Model.NormName(name)
    name = tostring(name or "")
    -- Some ProjectEbonhold database comments append invisible
    -- control-byte discriminators to otherwise identical player-facing
    -- names (documented behavior of the server database). Cut at the
    -- first control byte so config names match what the game sends.
    local cut = name:find("[%c\127]")
    if cut then name = name:sub(1, cut - 1) end
    name = name:gsub("\226\128\153", "'") -- U+2019 -> '
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

-- Some recorded keys carry an " - <rarity>" suffix (observed in live data:
-- "Mana Regeneration - uncommon"). Strip it so all quality variants of an
-- echo share one canonical key.
local RARITY_WORDS = { "common", "uncommon", "rare", "epic", "legendary" }

function Model.StripRaritySuffix(name)
    name = tostring(name or "")
    local lower = name:lower()
    for i = 1, #RARITY_WORDS do
        local w = RARITY_WORDS[i]
        if lower:find(" %- " .. w .. "$") then
            return (name:sub(1, #name - (#w + 3)))
        end
    end
    return name
end

function Model.CanonicalKey(raw)
    return Model.NormName(Model.StripRaritySuffix(raw))
end

------------------------------------------------------------------------
-- Class-mask test (no bit library in logic files)
------------------------------------------------------------------------

-- True iff bitwise AND of the two masks is non-zero, via modular
-- arithmetic (Lua 5.1 has no bit ops without a library).
function Model.MaskMatch(a, b)
    a = tonumber(a) or 0
    b = tonumber(b) or 0
    if a <= 0 or b <= 0 then return false end
    a = math.floor(a)
    b = math.floor(b)
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then return true end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return false
end

------------------------------------------------------------------------
-- Permanent locked-Echo evidence
------------------------------------------------------------------------

local function WholeNumber(value, minimum)
    value = tonumber(value)
    if not value or value ~= value or value < minimum or value >= math.huge
        or value ~= math.floor(value) then return nil end
    return value
end

-- One pure admission boundary for every consumer of GetLockedPerks-derived
-- authority. Locked ownership is the held copies of OCCUPIED RECORDS: the
-- adapter's trusted read already held its records to the live capacity (or
-- the record ceiling) and each record to the per-record ceiling, so no copy
-- count bounds it here and every copy is kept. The read must state its
-- occupied records, one row per record, holding exactly its per-spell
-- copies; occupancy is never inferred from distinct IDs or copies. With a
-- catalog, the supplied family projection must exactly equal the family
-- totals derived from canonical spell IDs. The result keeps the copies, the
-- occupied count, the records and the live capacity the read was held to.
function Model.LockedProjection(locked, catalog)
    if type(locked) ~= "table" or locked.synced ~= true
        or type(locked.bySpell) ~= "table" then return nil end
    local bySpell, seen, total = {}, {}, 0
    for spellIdKey, countValue in pairs(locked.bySpell) do
        local spellId, copies = tonumber(spellIdKey), tonumber(countValue)
        if not spellId or spellId ~= spellId or spellId <= 0
            or spellId >= math.huge or spellId ~= math.floor(spellId)
            or not copies or copies ~= copies or copies <= 0
            or copies >= math.huge or copies ~= math.floor(copies)
            or seen[spellId] then return nil end
        seen[spellId] = true
        total = total + copies
        bySpell[spellId] = copies
    end
    local occupied = WholeNumber(locked.occupied, 0)
    local rows = locked.records
    if not occupied or type(rows) ~= "table" or #rows ~= occupied then
        return nil
    end
    local records, recordsBySpell, held = {}, {}, {}
    for index = 1, occupied do
        local row = rows[index]
        local spellId = type(row) == "table" and WholeNumber(row.spellId, 1)
        local stacks = type(row) == "table" and WholeNumber(row.stacks, 1)
        if not spellId or not stacks or not bySpell[spellId] then return nil end
        records[index] = {spellId=spellId, stacks=stacks}
        recordsBySpell[spellId] = (recordsBySpell[spellId] or 0) + 1
        held[spellId] = (held[spellId] or 0) + stacks
    end
    for spellId, copies in pairs(bySpell) do
        if held[spellId] ~= copies then return nil end
    end
    local capacity = locked.capacity ~= nil and WholeNumber(locked.capacity, 1)
    if locked.capacity ~= nil and (not capacity or occupied > capacity) then
        return nil
    end

    local byFamily = {}
    if catalog ~= nil then
        if type(catalog) ~= "table" or type(catalog.familyOf) ~= "table"
            or type(locked.byFamily) ~= "table" then return nil end
        for spellId, copies in pairs(bySpell) do
            local family = catalog.familyOf[spellId]
            if family == nil then return nil end
            byFamily[family] = (byFamily[family] or 0) + copies
        end
        for family, countValue in pairs(locked.byFamily) do
            local copies = tonumber(countValue)
            if not copies or copies ~= copies or copies < 0
                or copies >= math.huge or copies ~= math.floor(copies)
                or (byFamily[family] or 0) ~= copies then return nil end
        end
        for family, copies in pairs(byFamily) do
            if tonumber(locked.byFamily[family]) ~= copies then return nil end
        end
    end
    return {synced=true,bySpell=bySpell,byFamily=byFamily,total=total,
        occupied=occupied,records=records,recordsBySpell=recordsBySpell,
        capacity=capacity or nil}
end

------------------------------------------------------------------------
-- Marginal value Delta (ordinal, calibration-free)
------------------------------------------------------------------------

-- Mirror of data/DefaultProfile.params: keeps Delta functional when a
-- caller omits params. Keep in lockstep with DefaultProfile.
local DEFAULT_PARAMS = {
    coverage = 100,
    qualityBonus = 2,
    anchorUnlock = 150,
    diversity = 5,
    duplicate = -5,
    filler = -15,
    qualityMiss = -20,
    deferFactor = 0.35,
    rerollPacingBase = 6,
    deferRerollFloor = 4,
}

local function Param(params, key)
    local v = params and tonumber(params[key])
    if v ~= nil then return v end
    return DEFAULT_PARAMS[key]
end

-- Marginal value of taking one copy of spellId given the plan and the owned
-- state. Guarantee subtraction remains family-granular, but wishlist value is
-- quality-qualified: only a requested tier can advance a multi-quality target.
-- Exhaustion inputs stay per-spellId. Pure; returns a single number, 0 on
-- malformed input.
function Model.Delta(plan, owned, spellId, catalog, params)
    plan = type(plan) == "table" and plan or {}
    owned = type(owned) == "table" and owned or {}
    if type(catalog) ~= "table" then return 0 end
    local rows = type(catalog.rows) == "table" and catalog.rows or {}
    local row = rows[spellId]
    if type(row) ~= "table" then return 0 end

    local family = type(catalog.familyOf) == "table"
        and catalog.familyOf[spellId] or nil
    if family == nil then family = "s" .. tostring(spellId) end

    local bySpell = type(owned.bySpell) == "table" and owned.bySpell or {}
    local byFamily = type(owned.byFamily) == "table" and owned.byFamily or {}
    local ownedFam = tonumber(byFamily[family]) or 0
    local ownedSpell = tonumber(bySpell[spellId])
        or tonumber(bySpell[tostring(spellId)]) or 0
    local maxStack = tonumber(row.maxStack) or 1
    if maxStack < 1 then maxStack = 1 end
    local wishedFamilies = type(plan.wishedFamilies) == "table"
        and plan.wishedFamilies or {}
    local familyWanted = wishedFamilies[family] and true or false
    local qualifiedOwned, targetTotal = 0, 1
    local offeredNeeded = false
    if familyWanted then
        qualifiedOwned, targetTotal = Model.TargetProgress(
            plan, catalog, family, owned)
        offeredNeeded = Model.QualityOfferNeeded(
            plan, catalog, family, tonumber(row.quality) or 0, owned, spellId)
    end

    -- Duplicate: family full at maxStack, this exact spellId exhausted,
    -- or any owned maxStack==1 family member (one owned quality variant
    -- of a unique echo exhausts the whole family for value purposes,
    -- even though pool removal stays per-spellId).
    local isDuplicate = ownedSpell >= maxStack
    if not isDuplicate and not (familyWanted and offeredNeeded) then
        isDuplicate = (ownedFam >= maxStack and ownedFam > 0)
        local members = type(catalog.familyMembers) == "table"
            and catalog.familyMembers[family] or nil
        if not isDuplicate then
            for i = 1, #(members or {}) do
                local m = (members or {})[i]
                local mr = rows[m]
                if type(mr) == "table" and (tonumber(mr.maxStack) or 1) == 1
                    and (tonumber(bySpell[m])
                        or tonumber(bySpell[tostring(m)]) or 0) > 0 then
                    isDuplicate = true
                    break
                end
            end
        end
    end
    if isDuplicate then return Param(params, "duplicate") end

    local v
    if familyWanted then
        if not offeredNeeded then
            return Model.FamilyMultiQuality(catalog, family)
                and Param(params, "qualityMiss")
                or Param(params, "duplicate")
        end
        local quality = tonumber(row.quality) or 0
        if qualifiedOwned <= 0 then
            v = Param(params, "coverage")
                + Param(params, "qualityBonus") * quality
        else
            v = Param(params, "coverage")
                * ((targetTotal - qualifiedOwned) / targetTotal)
        end
    else
        v = Param(params, "filler")
    end

    -- Anchor terms only ever attach to a NEW family (the anchor's own
    -- family uncovered -> unlock bonus; anchor already owned -> every
    -- new family earns the diversity bonus, filler included).
    local anchor = plan.anchorSpellId
    if anchor ~= nil and ownedFam <= 0 then
        if spellId == anchor then
            v = v + Param(params, "anchorUnlock")
        end
        local anchorFam = type(catalog.familyOf) == "table"
            and catalog.familyOf[anchor] or nil
        local anchorOwned = (tonumber(bySpell[anchor])
            or tonumber(bySpell[tostring(anchor)]) or 0) > 0
            or (anchorFam ~= nil and (tonumber(byFamily[anchorFam]) or 0) > 0)
        if anchorOwned then
            v = v + Param(params, "diversity")
        end
    end
    return v
end

------------------------------------------------------------------------
-- Scarcity: has this family's guaranteed-slot supply already run dry?
------------------------------------------------------------------------

-- True when the family exists in more than one quality variant (distinct
-- spellIds sharing the group). These are the families where WHICH copy
-- you take matters -- the stat echoes among them.
function Model.FamilyMultiQuality(catalog, family)
    if type(catalog) ~= "table" or family == nil then return false end
    local members = type(catalog.familyMembers) == "table"
        and catalog.familyMembers[family] or nil
    if type(members) ~= "table" or #members < 2 then return false end
    local rows = type(catalog.rows) == "table" and catalog.rows or {}
    local seen = nil
    for i = 1, #members do
        local r = rows[members[i]]
        local q = r and tonumber(r.quality) or nil
        if q ~= nil then
            if seen == nil then seen = q
            elseif q ~= seen then return true end
        end
    end
    return false
end

-- Highest quality any variant of this family exists at in the catalog.
function Model.FamilyPeakQuality(catalog, family)
    if type(catalog) ~= "table" or family == nil then return 0 end
    local members = type(catalog.familyMembers) == "table"
        and catalog.familyMembers[family] or nil
    local rows = type(catalog.rows) == "table" and catalog.rows or {}
    local peak = 0
    for i = 1, #(members or {}) do
        local r = rows[(members or {})[i]]
        local q = r and tonumber(r.quality) or nil
        if q and q > peak then peak = q end
    end
    return peak
end

-- The quality a multi-quality wished family should be CHASED at: the
-- family's peak. Compensates for two live-server realities (2026-07-24):
-- the designed-build wire can lose the clicked variant's quality, and the
-- level-bracket bug can serve a below-peak variant as the guaranteed --
-- "we want the blue of each stat if possible" means the target is what's
-- POSSIBLE, not what a lossy wire happened to store. The stored
-- wishedQuality still acts as a floor for single-variant data.
local function CountFamilyAtQuality(catalog, family, ownedBySpell, quality)
    if type(ownedBySpell) ~= "table" then return 0 end
    local members = type(catalog) == "table"
        and type(catalog.familyMembers) == "table"
        and catalog.familyMembers[family] or nil
    local rows = type(catalog) == "table" and catalog.rows or nil
    local count = 0
    for i = 1, #(members or {}) do
        local id = members[i]
        local row = type(rows) == "table" and rows[id] or nil
        if type(row) == "table"
            and (tonumber(row.quality) or 0) == tonumber(quality) then
            count = count + (tonumber(ownedBySpell[id])
                or tonumber(ownedBySpell[tostring(id)]) or 0)
        end
    end
    return count
end

local function MultiTierTarget(target)
    return type(target) == "table"
        and type(target.qualityTiers) == "table"
        and #target.qualityTiers > 1
end

local function ExactTierTarget(target)
    if type(target) ~= "table" or type(target.qualityTiers) ~= "table"
        or #target.qualityTiers < 1 then return false end
    for _, tier in ipairs(target.qualityTiers) do
        local id = tonumber(type(tier) == "table" and tier.spellId)
        if not id or id <= 0 or id ~= math.floor(id) then return false end
    end
    return true
end

local function ExactOwned(ownedBySpell, spellId)
    if type(ownedBySpell) ~= "table" then return 0 end
    return tonumber(ownedBySpell[spellId])
        or tonumber(ownedBySpell[tostring(spellId)]) or 0
end

function Model.EffectiveWishedQuality(plan, catalog, family, ownedFamCount, ownedBySpell)
    local stored = 0
    local targets = type(plan) == "table" and plan.targets or nil
    local t = targets and targets[family]
    if type(t) == "table" then stored = tonumber(t.wishedQuality) or 0 end

    -- Multi-tier wishlist (e.g. Quick Hands Common×5, Uncommon×50, Rare×20):
    -- the player explicitly wants copies at EVERY listed quality tier. Return
    -- the first tier whose exact quota remains incomplete. Callers validating
    -- one offer use QualityOfferNeeded below.
    if MultiTierTarget(t) then
        for _, tier in ipairs(t.qualityTiers) do
            local need = math.max(0, tonumber(tier.n) or 0)
            local have = ExactTierTarget(t)
                and ExactOwned(ownedBySpell, tonumber(tier.spellId))
                or CountFamilyAtQuality(
                    catalog, family, ownedBySpell, tonumber(tier.q) or 0)
            if have < need then
                return tonumber(tier.q) or stored
            end
        end
        local last = t.qualityTiers[#t.qualityTiers]
        return tonumber(last and last.q) or stored
    end

    -- Single-tier wishlist: escalate to catalog peak for multi-quality
    -- families so the model always chases the best available copy.
    -- (e.g. wishlist has Rare Iron Constitution → reject Common copies)
    if Model.FamilyMultiQuality(catalog, family) then
        local peak = Model.FamilyPeakQuality(catalog, family)
        if peak > stored then return peak end
    end
    return stored
end

-- Quality-qualified progress for a wished family. Multi-tier targets count
-- every exact tier independently; lower-tier surplus cannot satisfy a higher
-- quota. Single-tier multi-quality targets count only acceptable variants.
function Model.TargetProgress(plan, catalog, family, owned)
    local targets = type(plan) == "table" and plan.targets or nil
    local target = targets and targets[family]
    local want = type(target) == "table"
        and tonumber(target.targetStacks) or 1
    if want < 1 then want = 1 end

    local bySpell = type(owned) == "table"
        and type(owned.bySpell) == "table" and owned.bySpell or {}
    local byFamily = type(owned) == "table"
        and type(owned.byFamily) == "table" and owned.byFamily or {}

    if ExactTierTarget(target) then
        local needs = {}
        for _, tier in ipairs(target.qualityTiers) do
            local id = tonumber(tier.spellId)
            needs[id] = (needs[id] or 0)
                + math.max(0, tonumber(tier.n) or 0)
        end
        local have, total = 0, 0
        for id, need in pairs(needs) do
            have = have + math.min(ExactOwned(bySpell, id), need)
            total = total + need
        end
        if total > 0 then return have, total end
    elseif MultiTierTarget(target) then
        local have, total = 0, 0
        for _, tier in ipairs(target.qualityTiers) do
            local need = math.max(0, tonumber(tier.n) or 0)
            local count = CountFamilyAtQuality(
                catalog, family, bySpell, tonumber(tier.q) or 0)
            have = have + math.min(count, need)
            total = total + need
        end
        if total > 0 then return have, total end
    end

    if Model.FamilyMultiQuality(catalog, family) then
        local required = Model.EffectiveWishedQuality(
            plan, catalog, family, nil, bySpell)
        local members = type(catalog) == "table"
            and type(catalog.familyMembers) == "table"
            and catalog.familyMembers[family] or nil
        local rows = type(catalog) == "table" and catalog.rows or nil
        local have = 0
        for i = 1, #(members or {}) do
            local id = members[i]
            local row = type(rows) == "table" and rows[id] or nil
            if type(row) == "table"
                and (tonumber(row.quality) or 0) >= required then
                have = have + (tonumber(bySpell[id])
                    or tonumber(bySpell[tostring(id)]) or 0)
            end
        end
        return math.min(have, want), want
    end

    local have = tonumber(byFamily[family])
        or tonumber(byFamily[tostring(family)]) or 0
    return math.min(have, want), want
end

-- Exact presentation progress for represented Wishlist rows. Duplicate rows
-- share one aggregate (role, spellId) quota, so reload ordering cannot decide
-- which indistinguishable row looks complete. Ordinary run ownership and
-- permanent locked ownership remain separate even when both roles request the
-- same exact tier.
function Model.WishlistEntryProgress(entries, owned, lockedOwned)
    entries = type(entries) == "table" and entries or {}
    local ordinaryBySpell = type(owned) == "table"
        and type(owned.bySpell) == "table" and owned.bySpell or {}
    local lockedBySpell = type(lockedOwned) == "table"
        and type(lockedOwned.bySpell) == "table" and lockedOwned.bySpell or {}
    if type(owned) == "table" and owned.synced == false then
        ordinaryBySpell = {}
    end
    if type(lockedOwned) == "table" and lockedOwned.synced == false then
        lockedBySpell = {}
    end

    local out = {
        rows={}, ordinaryHave=0, ordinaryWant=0,
        lockedHave=0, lockedWant=0,
    }
    local groups = {}
    local function NonNegativeCount(value)
        value = tonumber(value)
        if not value or value ~= value or value < 0 or value >= math.huge then
            return 0
        end
        if value ~= math.floor(value) then return 0 end
        return value
    end

    for index = 1, #entries do
        local entry = entries[index]
        local id = type(entry) == "table" and tonumber(entry.spellId) or nil
        if id and (id <= 0 or id ~= math.floor(id)) then id = nil end
        local want = type(entry) == "table"
            and tonumber(entry.stacks or entry.count) or 1
        if not want or want ~= want or want < 1 or want >= math.huge
            or want ~= math.floor(want) then want = 1 end
        local locked = type(entry) == "table"
            and (entry.locked == true or entry.sourceRole == "locked") or false
        local role = locked and "locked" or "ordinary"
        local key = role .. ":" .. tostring(id or "invalid")
        local group = groups[key]
        if not group then
            group = {role=role,locked=locked,spellId=id,want=0,rows={}}
            groups[key] = group
        end
        group.want = group.want + want
        group.rows[#group.rows + 1] = index
        local row = {
            index=index,spellId=id,
            quality=type(entry) == "table" and tonumber(entry.quality) or nil,
            locked=locked,role=role,rowWant=want,groupKey=key,
        }
        out.rows[index] = row
    end
    for _, group in pairs(groups) do
        local source = group.locked and lockedBySpell or ordinaryBySpell
        local available = group.spellId and NonNegativeCount(
            source[group.spellId] ~= nil and source[group.spellId]
                or source[tostring(group.spellId)]) or 0
        local have = math.min(group.want, available)
        for ordinal, index in ipairs(group.rows) do
            local row = out.rows[index]
            row.have, row.want = have, group.want
            row.remaining = group.want - have
            row.complete = have >= group.want
            row.groupOrdinal = ordinal
            row.primary = ordinal == 1
        end
        if group.locked then
            out.lockedHave = out.lockedHave + have
            out.lockedWant = out.lockedWant + group.want
        else
            out.ordinaryHave = out.ordinaryHave + have
            out.ordinaryWant = out.ordinaryWant + group.want
        end
    end
    out.have = out.ordinaryHave + out.lockedHave
    out.want = out.ordinaryWant + out.lockedWant
    out.complete = out.have >= out.want
    return out
end

-- True while this exact offered quality can satisfy an unmet target quota.
function Model.QualityOfferNeeded(plan, catalog, family, quality, owned, spellId)
    local progress, want = Model.TargetProgress(plan, catalog, family, owned)
    if progress >= want then return false end

    local targets = type(plan) == "table" and plan.targets or nil
    local target = targets and targets[family]
    local bySpell = type(owned) == "table"
        and type(owned.bySpell) == "table" and owned.bySpell or {}
    quality = tonumber(quality) or 0

    if ExactTierTarget(target) then
        spellId = tonumber(spellId)
        if not spellId then return false end
        local need = 0
        for _, tier in ipairs(target.qualityTiers) do
            if tonumber(tier.spellId) == spellId then
                need = need + math.max(0, tonumber(tier.n) or 0)
            end
        end
        return need > 0 and ExactOwned(bySpell, spellId) < need
    elseif MultiTierTarget(target) then
        for _, tier in ipairs(target.qualityTiers) do
            if (tonumber(tier.q) or 0) == quality then
                local need = math.max(0, tonumber(tier.n) or 0)
                return CountFamilyAtQuality(
                    catalog, family, bySpell, quality) < need
            end
        end
        return false
    end

    if Model.FamilyMultiQuality(catalog, family) then
        return quality >= Model.EffectiveWishedQuality(
            plan, catalog, family, nil, bySpell)
    end
    return true
end

-- A wished STACKING family still short of its wishlist stack target
-- (own 0..target-1 of a want-9 echo). The guarantee only ever serves the
-- FIRST copy of a family; every further stack is free-slot RNG, so a
-- free-slot appearance of one of these is always worth banking with a
-- freeze when it isn't this board's pick. Pure; false on malformed input.
function Model.StackWishBelowTarget(plan, owned, family, catalog)
    if family == nil then return false end
    local wishedFamilies = type(plan) == "table" and plan.wishedFamilies or nil
    if not (wishedFamilies and wishedFamilies[family]) then return false end
    local targets = type(plan) == "table" and plan.targets or nil
    local target = targets and targets[family]
    local targetStacks = (type(target) == "table" and tonumber(target.targetStacks)) or 1
    if targetStacks <= 1 then return false end
    if type(Model.TargetProgress) == "function" and catalog then
        local have, want = Model.TargetProgress(plan, catalog, family, owned)
        return have < want
    end
    local byFamily = type(owned) == "table" and owned.byFamily or nil
    local ownedFam = tonumber(byFamily and byFamily[family]) or 0
    return ownedFam < targetStacks
end

-- Ratchet.PredictQueue drops a family from the guaranteed queue the
-- instant ANY copy is owned (family-aware subtraction, addendum B2) --
-- regardless of how far short of the wishlist's targetStacks it still
-- sits. So a partially-stacked wished family (own 3, want 9) will NOT
-- come back around on slot 3; every further copy is free-slot RNG only.
-- A family that is wished but still fully unowned is NOT scarce by this
-- definition -- it's still guarantee-eligible and needs no protecting.
-- Pure; false on malformed input.
function Model.Scarce(plan, owned, family)
    if family == nil then return false end
    local wishedFamilies = type(plan) == "table" and plan.wishedFamilies or nil
    if not (wishedFamilies and wishedFamilies[family]) then return false end
    local byFamily = type(owned) == "table" and owned.byFamily or nil
    local ownedFam = tonumber(byFamily and byFamily[family]) or 0
    if ownedFam <= 0 then return false end
    local targets = type(plan) == "table" and plan.targets or nil
    local target = targets and targets[family]
    local targetStacks = (type(target) == "table" and tonumber(target.targetStacks)) or 1
    return ownedFam < targetStacks
end

-- The free-slot support list (Model.Support) and the draw-distribution order
-- statistics (BuildDistribution, EmaxK, EmaxGivenK, WithoutKey, FreeDist)
-- fed only the historical scoring engine that logic/Policy.lua no longer
-- carries. They live in the test-only
-- tests/prototype/historical_model_support.lua for the policy adapter;
-- nothing in the product reads them.
