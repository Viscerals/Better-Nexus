-- Nexus release identity. Development checkouts must not advertise themselves
-- as downloadable public releases.

Nexus = Nexus or {}

Nexus.Release = {
    version = "1.20.0-beta.1",
    baseVersion = "1.19.5",
    buildLabel = "source",
    -- "development" in the repository. tools/build_package.py writes
    -- "public-test" only for an explicitly public package, else "internal".
    channel = "development",
    published = false,
    releasesUrl = "https://github.com/Viscerals/Better-Nexus/releases",
}

-- Display identity of a test package. Packaging replaces the one buildLabel
-- field above. Sync protocol 7 continues to consume Release.version.
function Nexus.RuntimeBuildLabel()
    local label = Nexus.Release and Nexus.Release.buildLabel
    if label == "source" then return label end
    if type(label) ~= "string" or #label > 48
        or not label:match("^test%.%d+%-[0-9a-f]+$") then return "source" end
    local hash = label:match("%-([0-9a-f]+)$")
    return hash and #hash >= 7 and #hash <= 12 and label or "source"
end

-- The one installed identity that update comparison, the announced version and
-- every visible label read. The test number orders builds of one release
-- series. The commit suffix of the label names the source; it never orders.
--   channel  "stable" | "public-test" | "internal" | "development"
--   announce the version this client states to peers. Only a public test
--            package adds its test number, as SemVer build metadata, which
--            existing peers already accept in the same field.
local MAX_TEST = 2147483647
function Nexus.ReleaseIdentity()
    local release = type(Nexus.Release) == "table" and Nexus.Release or {}
    local version = type(release.version) == "string" and release.version or "0.0.0"
    local label = Nexus.RuntimeBuildLabel()
    local digits = label ~= "source" and label:match("^test%.(%d+)%-") or nil
    local test = digits and #digits <= 10 and tonumber(digits) or nil
    if test and (test < 1 or test > MAX_TEST) then test = nil end
    local installedChannel = "development"
    if release.channel == "stable" and not version:find("-", 1, true) then
        installedChannel, test = "stable", nil
    elseif label ~= "source" then
        installedChannel = release.channel == "public-test" and test and "public-test" or "internal"
    end
    local channel = installedChannel
    local announce = version
    if channel == "public-test" then
        local stated = version .. "+test." .. tostring(test)
        if #stated <= 32 then announce = stated end
    end
    return {
        version = version, label = label, test = test, channel = channel,
        announce = announce,
        display = test and (version .. " test." .. tostring(test)) or version,
    }
end
