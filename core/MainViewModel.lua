-- Nexus: core/MainViewModel.lua
-- Pure progress and immutable HUD display-model projection owner.

Nexus = Nexus or {}
if type(Nexus.MainInternals) ~= "table" then Nexus.MainInternals = {} end

local ViewModel = {}
Nexus.MainInternals.ViewModel = ViewModel

local QUALITY_NAMES = { [0]="Common", [1]="Uncommon", [2]="Rare", [3]="Epic" }
local function QualityName(quality)
    return QUALITY_NAMES[quality] or ("q" .. quality)
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[Copy(key, seen)] = Copy(child, seen)
    end
    return out
end

local function Equal(left, right, leftSeen, rightSeen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    leftSeen, rightSeen = leftSeen or {}, rightSeen or {}
    local paired = leftSeen[left]
    if paired then return paired == right end
    local reverse = rightSeen[right]
    if reverse then return reverse == left end
    leftSeen[left], rightSeen[right] = right, left
    for key, value in pairs(left) do
        if not Equal(value, right[key], leftSeen, rightSeen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function ActiveSlotRow(slots)
    if not slots or slots.activeSlot == 0 then return nil end
    local row = slots.bySlot[slots.activeSlot]
    if row and row.verified and row.verifiedFieldPresent and not row.suspectParse then
        return row
    end
    return nil
end

local function LockOnlyFamilies(plan, wishlist)
    local out = {}
    if type(plan) ~= "table" or type(plan.wishedFamilies) ~= "table" then return out end
    local realFamilies = (type(wishlist) == "table" and wishlist.byFamily) or {}
    for family in pairs(plan.wishedFamilies) do
        if not realFamilies[family] then out[family] = true end
    end
    return out
end

function ViewModel.New(options)
    options = options or {}
    local Ratchet = assert(options.ratchet, "MainViewModel requires Ratchet")
    local Model = options.model or Nexus.Model
    local WishlistModel = assert(options.wishlistModel,
        "MainViewModel requires WishlistModel")
    local stats = {builds=0,refreshes=0,rebuilds=0,skipped=0}
    local lastHudInput, lastHudModel = nil, nil
    local M = {}

    function M.Copy(value)
        return Copy(value)
    end

    function M.ActiveSlotRow(slots)
        return ActiveSlotRow(slots)
    end

    function M.WishlistProgress(plan, owned, catalog, lockOnlyFamilies,
        lockedOwned, designTargets, wishlist)
        local stackTotal, stackCount, missing, toLock = 0, 0, {}, {}
        if type(plan) ~= "table" or type(plan.wishedFamilies) ~= "table" then
            return 0, 0, missing, toLock
        end
        lockOnlyFamilies = lockOnlyFamilies or {}
        local targets = type(plan.targets) == "table" and plan.targets or {}
        local byFamily = (type(owned) == "table" and owned.byFamily) or {}
        local bySpell = (type(owned) == "table" and owned.bySpell) or {}
        local lockedByFamily = type(lockedOwned) == "table"
            and type(lockedOwned.byFamily) == "table" and lockedOwned.byFamily or {}
        local lockedBySpell = type(lockedOwned) == "table"
            and type(lockedOwned.bySpell) == "table" and lockedOwned.bySpell or {}

        local seenToLock = {}
        if type(designTargets) == "table" then
            local rows = catalog and catalog.rows or {}
            for spellIdKey, target in pairs(designTargets) do
                local id = tonumber(spellIdKey)
                local want = id and WishlistModel.TargetCopies(target, id)
                local have = type(lockedOwned) == "table"
                    and lockedOwned.synced == true
                    and (tonumber(lockedBySpell[id]) or 0) or 0
                if id and want and not seenToLock[id]
                    and have < want then
                    local row = rows[id]
                    local remaining = want - have
                    toLock[#toLock + 1] = tostring((row and row.name)
                        or ("spell " .. tostring(id)))
                        .. (remaining > 1 and (" ×" .. remaining) or "")
                    seenToLock[id] = true
                end
            end
        end

        local explicitRoles = false
        local entries = type(wishlist) == "table" and wishlist.entries or nil
        for _, entry in ipairs(type(entries) == "table" and entries or {}) do
            if type(entry) == "table" and (type(entry.locked) == "boolean"
                or entry.sourceRole == "ordinary"
                or entry.sourceRole == "locked") then
                explicitRoles = true
                break
            end
        end
        if explicitRoles and Model
            and type(Model.WishlistEntryProgress) == "function" then
            local exact = Model.WishlistEntryProgress(entries, owned, lockedOwned)
            local missingBySpell, lockMissingBySpell = {}, {}
            for _, row in ipairs(exact.rows) do
                if row.primary and row.locked then
                    if row.remaining > 0 and row.spellId then
                        lockMissingBySpell[row.spellId] =
                            (lockMissingBySpell[row.spellId] or 0) + row.remaining
                    end
                elseif row.primary then
                    if row.remaining > 0 and row.spellId then
                        missingBySpell[row.spellId] =
                            (missingBySpell[row.spellId] or 0) + row.remaining
                    end
                end
            end
            stackTotal = exact.ordinaryWant
            stackCount = exact.ordinaryHave
            local function ExactLabel(id, remaining)
                local row = catalog and catalog.rows and catalog.rows[id]
                local label = tostring((row and row.name)
                    or ("spell " .. tostring(id)))
                local quality = row and tonumber(row.quality)
                if quality ~= nil then
                    label = label .. " (" .. QualityName(quality) .. ")"
                end
                if remaining > 1 then label = label .. " ×" .. remaining end
                return label
            end
            for id, remaining in pairs(missingBySpell) do
                missing[#missing + 1] = ExactLabel(id, remaining)
            end
            for id, remaining in pairs(lockMissingBySpell) do
                if not seenToLock[id] then
                    toLock[#toLock + 1] = ExactLabel(id, remaining)
                    seenToLock[id] = true
                end
            end
            table.sort(missing)
            table.sort(toLock)
            return stackCount, stackTotal, missing, toLock, exact
        end

        for family in pairs(plan.wishedFamilies) do
            local target = targets[family]
            local exact = Ratchet.TargetExact(target)
            local have, want = Ratchet.ExactCoverage(exact, bySpell)
            local lockedHave = Ratchet.ExactCoverage(exact, lockedBySpell)
            if want <= 0 then
                want = (type(target) == "table" and tonumber(target.targetStacks)) or 1
                have = math.min(tonumber(byFamily[family]) or 0, want)
                lockedHave = tonumber(lockedByFamily[family]) or 0
            end
            if lockedHave >= want then
                -- Permanently locked exact coverage leaves the active target.
            elseif lockOnlyFamilies[family] then
                -- Designed locks do not consume the rolled-wishlist stack cap.
            else
                stackTotal = stackTotal + want
                stackCount = stackCount + have
                if have < want then
                    local name = catalog and catalog.familyName
                        and catalog.familyName[family]
                    local remain = want - have
                    local tiers = type(target) == "table" and target.qualityTiers
                    if tiers and #tiers > 1 then
                        local parts = {}
                        for _, tier in ipairs(tiers) do
                            local ownedTier = tier.spellId
                                and (tonumber(bySpell[tier.spellId]) or 0) or 0
                            local tierRemain = math.max(0,
                                (tonumber(tier.n) or 0) - ownedTier)
                            if tierRemain > 0 then
                                parts[#parts + 1] = QualityName(tier.q) .. ":×" .. tierRemain
                            end
                        end
                        local label = tostring(name or family) .. " ×" .. remain
                        if #parts > 0 then label = label .. " (" .. table.concat(parts, " ") .. ")" end
                        missing[#missing + 1] = label
                    else
                        missing[#missing + 1] = tostring(name or family)
                            .. (remain > 1 and (" ×" .. remain) or "")
                    end
                end
            end
        end
        table.sort(missing)
        table.sort(toLock)
        return stackCount, stackTotal, missing, toLock
    end

    function M.LoadoutCoverage(activeRow, plan, catalog)
        if type(activeRow) ~= "table" or type(activeRow.echoes) ~= "table"
            or type(plan) ~= "table" or type(plan.wishedFamilies) ~= "table" then
            return {}, nil, {}
        end
        local targets = type(plan.targets) == "table" and plan.targets or {}
        local bySpell, locked = {}, {}
        for index = 1, #activeRow.echoes do
            local echo = activeRow.echoes[index]
            local family = echo and echo.family
            local id = echo and tonumber(echo.spellId)
            if family and id and plan.wishedFamilies[family] then
                bySpell[id] = (bySpell[id] or 0) + (tonumber(echo.stacks) or 1)
                if echo.locked then
                    local row = catalog and catalog.rows and catalog.rows[id]
                    locked[#locked + 1] = (row and row.name) or ("spell " .. tostring(id))
                end
            end
        end
        local stackTotal, stackCount, missing = 0, 0, {}
        for family in pairs(plan.wishedFamilies) do
            local target = targets[family]
            local exact = Ratchet.TargetExact(target)
            local have, want = Ratchet.ExactCoverage(exact, bySpell)
            if want <= 0 then
                want = (type(target) == "table" and tonumber(target.targetStacks)) or 1
                have = 0
            end
            stackTotal = stackTotal + want
            stackCount = stackCount + have
            if have < want then
                local name = catalog and catalog.familyName
                    and catalog.familyName[family]
                missing[#missing + 1] = name or family
            end
        end
        table.sort(missing)
        table.sort(locked)
        return missing, {stackCount=stackCount,stackTotal=stackTotal}, locked
    end

    function M.TomeEchoes(wishlistEchoes, designTargets)
        local out, seen = {}, {}
        for _, echo in ipairs(wishlistEchoes or {}) do
            out[#out + 1] = echo
            local id = tonumber(echo and (echo.spellId or echo.id))
            if id then seen[id] = true end
        end
        if type(designTargets) == "table" then
            for spellIdKey, target in pairs(designTargets) do
                local id = tonumber(spellIdKey)
                local copies = id and WishlistModel.TargetCopies(target, id)
                if id and copies and not seen[id] then
                    out[#out + 1] = {spellId=id}
                    seen[id] = true
                end
            end
        end
        return out
    end

    function M.BuildProgress(input)
        input = type(input) == "table" and input or {}
        local plan, owned, slots, catalog = input.plan, input.owned,
            input.slots, input.catalog
        local wishlist = input.wishlist
        local lockOnly = LockOnlyFamilies(plan, wishlist)
        local runStacks, total, missing, toLock, exactProgress = M.WishlistProgress(
            plan, owned, catalog, lockOnly, input.lockedOwned,
            input.designTargets, wishlist)
        local activeRow = ActiveSlotRow(slots)
        local loadoutMissing, loadoutStacks, locked = M.LoadoutCoverage(
            activeRow, plan, catalog)

        local shed = {}
        if type(plan) == "table" and type(owned) == "table"
            and type(owned.bySpell) == "table" then
            local wantedExact, lockedExact = Ratchet.WantedExact(plan), {}
            if type(activeRow) == "table" and type(activeRow.echoes) == "table" then
                for _, echo in ipairs(activeRow.echoes) do
                    if echo.locked and tonumber(echo.spellId) then
                        local id = tonumber(echo.spellId)
                        lockedExact[id] = (lockedExact[id] or 0)
                            + math.max(1, tonumber(echo.stacks or echo.count or echo.stack) or 1)
                    end
                end
            end
            for id, count in pairs(owned.bySpell) do
                local keep = math.max(tonumber(wantedExact[id]) or 0,
                    tonumber(lockedExact[id]) or 0)
                local shedCount = math.max(0, (tonumber(count) or 0) - keep)
                if shedCount > 0 then
                    local row = catalog and catalog.rows and catalog.rows[id]
                    local name = row and row.name or ("spell " .. tostring(id))
                    local quality = row and tonumber(row.quality)
                    local qualityLabel = quality ~= nil and QUALITY_NAMES[quality] or nil
                    shed[#shed + 1] = tostring(name)
                        .. (qualityLabel and (" (" .. qualityLabel .. ")") or "")
                        .. (shedCount > 1 and (" ×" .. shedCount) or "")
                end
            end
            table.sort(shed)
        end

        local echoes = wishlist and (wishlist.echoes or wishlist.entries) or nil
        return {
            owned=runStacks,total=total,missing=missing,
            lockedOwned=exactProgress and exactProgress.lockedHave or nil,
            lockedTotal=exactProgress and exactProgress.lockedWant or nil,
            wishlistRows=exactProgress and Copy(exactProgress.rows) or nil,
            unknownTomes=Copy(type(input.unknownTomes) == "table"
                and input.unknownTomes or {}),
            loadoutMissing=loadoutMissing,loadoutStacks=loadoutStacks,
            locked=locked,shed=shed,toLock=toLock,
            wishlistName=wishlist and ((wishlist.name ~= "" and wishlist.name)
                or "(unnamed)") or nil,
            activeSlot=activeRow and tonumber(activeRow.slot) or 0,
            matchedBuildId=input.matchedBuildId,previewBuildId=input.previewBuildId,
            dpsEchoes=Copy(echoes),
            isCommunityPreview=input.previewBuildId and true or false,
        }
    end

    function M.BuildHudDisplayModel(input)
        input = type(input) == "table" and input or {}
        stats.builds = stats.builds + 1
        if lastHudInput and Equal(input, lastHudInput) then
            stats.skipped = stats.skipped + 1
            return Copy(lastHudModel)
        end
        local out = Copy(type(input.base) == "table" and input.base or {})
        out.status = input.status
        if out.level == nil then out.level = input.level or 0 end
        out.updateNotice = Copy(input.updateNotice)
        if out.updateNotice then out.updateNotice.releaseUrl = input.releaseUrl end
        out.serverStatus = input.useServerStatus and Copy(input.serverStatus) or nil
        out.bestDps = Copy(type(input.bestDps) == "table" and input.bestDps or {
            dummy=nil,lk=nil,info=nil,
        })
        local progress = type(out.progress) == "table" and out.progress or {}
        out.progress = progress
        progress.performance = Copy(type(input.performance) == "table"
            and input.performance or {dummy={},lk={}})
        lastHudInput = Copy(input)
        lastHudModel = Copy(out)
        stats.rebuilds = stats.rebuilds + 1
        return Copy(out)
    end

    function M.NoteRefresh()
        stats.refreshes = stats.refreshes + 1
    end

    function M.Stats()
        return Copy(stats)
    end

    return M
end
