-- l10n parity case p09_pack_unknown (Refs #147, S1): test-only data; never listed in Nexus.toc.
Nexus = Nexus or {}
Nexus.LocalizationPacks = {
    qaQA = {
        name = "Qa test",
        entries = {
            ["parity.alpha"] = "Alpha qa",
        },
    },
    qbQB = {
        name = "Qb test",
        entries = {
            ["parity.alpha"] = "Alpha qa",
        },
    },
}
