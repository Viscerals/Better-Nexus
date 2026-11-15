-- l10n parity case p01_valid (Refs #147, S1): test-only data; never listed in Nexus.toc.
Nexus = Nexus or {}
Nexus.LocalizationPacks = {
    qaQA = {
        name = "Qa test",
        entries = {
            ["parity.alpha"] = "Alpha qa",
            ["readout.charge_counts"] = "{{F}} {freeze} / B {banish} / R {reroll}",
        },
    },
}
