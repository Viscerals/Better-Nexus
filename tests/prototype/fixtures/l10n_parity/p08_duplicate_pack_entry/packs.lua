-- l10n parity case p08_duplicate_pack_entry (Refs #147, S1): test-only data; never listed in Nexus.toc.
Nexus = Nexus or {}
Nexus.LocalizationPacks = {
    qaQA = {
        name = "Qa test",
        entries = {
            ["parity.alpha"] = "Un",
            ["parity.alpha"] = "Deux",
        },
    },
}
