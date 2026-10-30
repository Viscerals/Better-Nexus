-- l10n parity case p04_pack_invalid_template (Refs #147, S1): test-only data; never listed in Nexus.toc.
Nexus = Nexus or {}
Nexus.LocalizationPacks = {
    qaQA = {
        name = "Qa test",
        entries = {
            ["readout.charge_counts"] = "{banish} {reroll}",
        },
    },
}
