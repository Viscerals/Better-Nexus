-- l10n parity case p11_template_lone_open (Refs #147, S1): test-only data; never listed in Nexus.toc.
Nexus = Nexus or {}
Nexus.LocalizationPacks = {
    qaQA = {
        name = "Qa test",
        entries = {
            ["readout.charge_counts"] = "{banish} {reroll} {freeze} {",
        },
    },
}
