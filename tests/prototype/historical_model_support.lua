-- Test-only: the free-slot support list and the draw-distribution order
-- statistics of the historical (v1.19.x) scoring engine, moved out of
-- logic/Model.lua when that engine was removed from logic/Policy.lua (it was
-- unreachable: the production TOC always loads EchoWeaver). The policy
-- adapter still builds the production decision state with `support`, so the
-- bodies are kept here verbatim (verbatim fork: EchoOptimizer/logic/Model.lua
-- for the distribution helpers). Pure Lua 5.1; needs Nexus.Model
-- (MaskMatch, Delta) from the root the adapter loaded.
local H = {}

-- Catalog rows still drawable in the two free slots: class-legal,
-- level-eligible, lever not disabled, not exhausted. Exhaustion here is
-- strictly per-spellId (an owned sibling quality does NOT remove this
-- row from the pool -- it only turns its Delta into a duplicate score).
-- params is optional; Delta defaults apply when omitted.
-- Deterministic output order (ascending spellId).
function H.Support(catalog, owned, level, disabledLevers, plan, params)
    local Model = Nexus.Model
    local out = {}
    if type(catalog) ~= "table" or type(catalog.rows) ~= "table" then
        return out
    end
    owned = type(owned) == "table" and owned or {}
    local bySpell = type(owned.bySpell) == "table" and owned.bySpell or {}
    level = tonumber(level) or 0
    disabledLevers = type(disabledLevers) == "table" and disabledLevers or {}
    local levers = type(catalog.levers) == "table" and catalog.levers or {}
    local familyOf = type(catalog.familyOf) == "table"
        and catalog.familyOf or {}
    local playerMask = tonumber(catalog.playerMask) or 0

    local ids = {}
    for id, row in pairs(catalog.rows) do
        if type(row) == "table" then ids[#ids + 1] = id end
    end
    table.sort(ids)

    for i = 1, #ids do
        local id = ids[i]
        local row = catalog.rows[id]
        local ok = Model.MaskMatch(row.classMask, playerMask)
            and (tonumber(row.minLevel) or 0) <= level
        if ok then
            local lever = tonumber(row.requiredSpell) or 0
            if lever ~= 0 and levers[lever] ~= nil
                and disabledLevers[lever] then
                ok = false
            end
        end
        if ok then
            local maxStack = tonumber(row.maxStack) or 1
            if (tonumber(bySpell[id]) or 0) >= maxStack then ok = false end
        end
        if ok then
            local family = familyOf[id]
            if family == nil then family = "s" .. tostring(id) end
            out[#out + 1] = {
                spellId = id,
                family = family,
                quality = tonumber(row.quality) or 0,
                value = Model.Delta(plan, owned, id, catalog, params),
            }
        end
    end
    return out
end

-- entries: array of { key = normName, prob = p, value = v }, probs sum to 1.
-- Values are floored at `floor` (default 0) for the distribution only:
-- a junk card on screen contributes ~nothing to "best offer", it is never
-- force-picked at its negative utility. Live decisions use true values.
function H.BuildDistribution(entries, nBins, floor)
    nBins = nBins or 16
    floor = floor or 0

    local list = {}
    for i = 1, #entries do
        local e = entries[i]
        if e.prob and e.prob > 0 then
            list[#list + 1] = {
                key = e.key, prob = e.prob,
                value = e.value > floor and e.value or floor,
            }
        end
    end
    table.sort(list, function(a, b) return a.value < b.value end)

    local x, p = {}, {}
    local target = 1 / nBins
    local accP, accPV = 0, 0
    for i = 1, #list do
        local e = list[i]
        accP = accP + e.prob
        accPV = accPV + e.prob * e.value
        local isLast = (i == #list)
        local nextDiffers = isLast or (list[i + 1].value > e.value)
        -- Close the bin at the quantile boundary, but never split a tie
        -- group across bins (keeps bin values exact for degenerate pools).
        if (accP >= target and nextDiffers) or isLast then
            x[#x + 1] = accPV / accP
            p[#p + 1] = accP
            accP, accPV = 0, 0
        end
    end

    local F = {}
    local c = 0
    for i = 1, #x do
        c = c + p[i]
        F[i] = c
    end
    if #F > 0 then F[#F] = 1 end -- guard fp drift

    local E1 = 0
    for i = 1, #x do E1 = E1 + x[i] * p[i] end

    return {
        x = x, p = p, F = F, n = #x,
        E1 = E1,
        rawEntries = entries,
        nBins = nBins, floor = floor,
    }
end

-- E[ best of k draws ]
function H.EmaxK(dist, k)
    local ev = 0
    local Fprev = 0
    for i = 1, dist.n do
        local Fi = dist.F[i]
        ev = ev + dist.x[i] * (Fi ^ k - Fprev ^ k)
        Fprev = Fi
    end
    return ev
end

-- E[ max(c, best of k draws) ] for an arbitrary known value c.
function H.EmaxGivenK(dist, c, k)
    local ev = 0
    local Fc = 0
    local Fprev = 0
    for i = 1, dist.n do
        local Fi = dist.F[i]
        if dist.x[i] <= c then
            Fc = Fi
        else
            ev = ev + dist.x[i] * (Fi ^ k - Fprev ^ k)
        end
        Fprev = Fi
    end
    return ev + c * (Fc ^ k)
end

-- Distribution with one echo removed from the pool (banish preview).
function H.WithoutKey(dist, nk)
    local kept, removed = {}, 0
    for i = 1, #dist.rawEntries do
        local e = dist.rawEntries[i]
        if e.key == nk then
            removed = removed + (e.prob or 0)
        else
            kept[#kept + 1] = e
        end
    end
    if removed <= 0 or removed >= 1 then return dist end
    local scale = 1 / (1 - removed)
    local rescaled = {}
    for i = 1, #kept do
        rescaled[i] = { key = kept[i].key, prob = kept[i].prob * scale, value = kept[i].value }
    end
    return H.BuildDistribution(rescaled, dist.nBins, dist.floor)
end

-- Uniform draw belief over the support (theta unmeasured: no quality
-- mix, no counts -- addendum C/M4). Keyed by spellId so WithoutKey
-- matches the per-spellId banish granularity. nil on empty support;
-- callers treat a nil distribution as E = 0.
function H.FreeDist(support)
    if type(support) ~= "table" or #support == 0 then return nil end
    local n = #support
    local entries = {}
    for i = 1, n do
        local s = support[i]
        entries[i] = {
            key = s.spellId,
            prob = 1 / n,
            value = tonumber(s.value) or 0,
        }
    end
    return H.BuildDistribution(entries)
end

return H
