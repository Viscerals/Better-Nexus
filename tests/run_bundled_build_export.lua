local H = dofile("tests/harness.lua")
dofile("data/BundledBuilds.lua")
dofile("core/BuildCatalog.lua")

local bundle = Nexus.BundledBuilds
assert(type(bundle) == "table" and bundle.schemaVersion == 1,
    "generated bundle schema is missing")
assert(type(bundle.catalogVersion) == "string"
    and bundle.catalogVersion ~= "1.19.4-empty.1",
    "generated catalog version was not updated")
assert(type(bundle.generation) == "table"
    and bundle.generation.sourceRows > 0
    and bundle.generation.included > 0
    and bundle.generation.prunableBaselineRows
        + bundle.generation.locallyMarkedIncluded == bundle.generation.included,
    "generated catalog counts are missing")

local forbidden = {
    "isMine", "importedSavedBuild", "serverSlot", "serverTitle",
    "destinationWishlistName", "destinationWishlistSlot",
    "destinationProgress", "destinationTotal", "activeServerBuild",
    "_savedSignature", "_nexusDps", "_nexusBestDps", "ownerVerified",
    "relaySender", "sourceSavedBuildId", "publishedBuildId",
}

local function Fingerprint(echoes)
    local counts, ids = {}, {}
    for _, echo in ipairs(echoes or {}) do
        local id = tonumber(echo.spellId)
        local stacks = tonumber(echo.stacks)
        assert(id and id > 0 and stacks and stacks >= 1
            and stacks == math.floor(stacks), "malformed generated Echo")
        if counts[id] == nil then ids[#ids + 1] = id; counts[id] = 0 end
        counts[id] = counts[id] + stacks
    end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return table.concat(parts, ",")
end

local function Hash(text)
    local h = 5381
    for i = 1, #text do h = ((h * 33) + text:byte(i)) % 2147483648 end
    return string.format("%x", h)
end

local count, echoRows = 0, 0
for id, build in pairs(bundle.builds or {}) do
    count = count + 1
    assert(build.id == id and type(build.title) == "string" and build.title ~= ""
        and type(build.author) == "string" and build.author ~= "",
        "generated build identity is invalid")
    assert(type(build.lastModified) == "number"
        and type(build.postedAt) == "number",
        "generated build revision is invalid")
    assert(type(build.echoes) == "table" and #build.echoes > 0,
        "generated build has no complete loadout")
    local fingerprint = Fingerprint(build.echoes)
    assert(build.fingerprint == fingerprint
        and build.fingerprintHash == Hash(fingerprint),
        "generated fingerprint is not canonical")
    local total = 0
    for _, echo in ipairs(build.echoes) do total = total + echo.stacks end
    assert(total == build.echoCount and total <= 120
        and build.loadoutAvailable == true,
        "generated Echo count is invalid")
    echoRows = echoRows + #build.echoes
    for _, field in ipairs(forbidden) do
        assert(build[field] == nil, "generated build leaked " .. field)
    end
end
assert(count == bundle.generation.included
    and echoRows == bundle.generation.echoRows,
    "generated catalog counts do not match its contents")

NexusDB = {}
local summary = Nexus.BuildCatalog.Init(NexusDB, bundle)
assert(summary.bundled == count and summary.overlay == 0
    and Nexus.BuildCatalog.Count() == count,
    "clean database did not expose only the generated baseline")
assert(next(Nexus.BuildCatalog.OverlaySnapshot()) == nil,
    "clean database gained an overlay while loading the baseline")

print(string.format(
    "bundled catalog validates: %d builds, %d Echo rows, clean overlay -- OK",
    count, echoRows))
