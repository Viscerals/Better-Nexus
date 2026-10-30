-- l10n parity case p10_pack_missing (Refs #147, S1): test-only data; never listed in Nexus.toc.
Nexus = Nexus or {}
Nexus.LocalizationPacks = {
    qaQA = {
        name = "Qa test",
        entries = {
            ["parity.alpha"] = "Alpha qa",
        },
    },
}
