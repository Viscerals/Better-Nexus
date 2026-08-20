-- Nexus release identity. Development checkouts must not advertise themselves
-- as downloadable public releases.

Nexus = Nexus or {}

Nexus.Release = {
    version = "1.20.0-beta.1",
    baseVersion = "1.19.5",
    buildLabel = "source",
    published = false,
    releasesUrl = "https://github.com/Viscerals/Better-Nexus/releases",
}

-- Display-only identity for private test packages. Packaging may replace the
-- one buildLabel field above; public update comparison and Sync continue to
-- consume Release.version and protocol 7 independently.
function Nexus.RuntimeBuildLabel()
    local label = Nexus.Release and Nexus.Release.buildLabel
    if label == "source" then return label end
    if type(label) ~= "string" or #label > 48
        or not label:match("^test%.%d+%-[0-9a-f]+$") then return "source" end
    local hash = label:match("%-([0-9a-f]+)$")
    return hash and #hash >= 7 and #hash <= 12 and label or "source"
end
