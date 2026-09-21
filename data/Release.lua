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
--   announce the version this client states to peers, with SemVer build
--            metadata that existing peers already accept in the same field:
--            +test.<N> (public test), +dev, +internal, or none (stable).
local MAX_TEST = 2147483647
function Nexus.ReleaseIdentity()
    local release = type(Nexus.Release) == "table" and Nexus.Release or {}
    local version = type(release.version) == "string" and release.version or "0.0.0"
    local label = Nexus.RuntimeBuildLabel()
    local digits = label ~= "source" and label:match("^test%.(%d+)%-") or nil
    local test = digits and #digits <= 10 and digits:sub(1, 1) ~= "0" and tonumber(digits) or nil
    if test and (test < 1 or test > MAX_TEST) then test = nil end
    local installedChannel = "development"
    if release.channel == "stable" and not version:find("-", 1, true) then
        installedChannel, test = "stable", nil
    elseif label ~= "source" then
        installedChannel = release.channel == "public-test" and test and "public-test" or "internal"
    end
    local channel = installedChannel
    -- Only a public test package states a test number. A development or
    -- internal copy marks its version, so a raised version in a checkout is
    -- not read by a peer as a published release. (The mark is dropped only
    -- when the result would exceed the 32-byte field; release versions are far
    -- shorter.) A stable release states the plain version.
    local announce = version
    local mark = channel == "public-test" and ("+test." .. tostring(test))
        or channel == "development" and "+dev" or channel == "internal" and "+internal" or ""
    if #(version .. mark) <= 32 then announce = version .. mark end
    return {
        version = version, label = label, test = test, channel = channel,
        announce = announce,
        display = test and (version .. " test." .. tostring(test)) or version,
    }
end
