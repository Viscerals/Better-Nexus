-- Nexus release identity. Development checkouts must not advertise themselves
-- as downloadable public releases.

Nexus = Nexus or {}

Nexus.Release = {
    version = "1.20.0-beta.5",
    baseVersion = "1.19.5",
    published = false,
    emergencyCommunityOff = false,
    preferStockServerHud = true,
    releasesUrl = "https://github.com/Viscerals/Better-Nexus/releases",
}
