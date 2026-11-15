-- l10n parity case p05_orphan_entry (Refs #147, S1): test-only data; never listed in Nexus.toc.
Nexus = Nexus or {}
Nexus.LocalizationPacks = {
    qaQA = {
        name = "Qa test",
        entries = {
            ["parity.alpha"] = "Alpha qa",
            ["reason.retired_example"] = "Retired",
        },
    },
}
