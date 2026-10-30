-- Shared runtime/offline parity corpus for issue #147, slice S1. Tests only:
-- nothing here is listed in Nexus.toc, packaged or counted as a shipped
-- language, and the pack IDs (qaQA, qbQB) are pseudo IDs (shippedProductIds
-- is empty). Each case names a directory beside this file whose english.lua
-- and packs.lua use the real data grammars. The same bytes are loaded by the
-- LuaJIT harness tests/prototype/localization_parity.lua (runtime outcome)
-- and parsed, never executed, by tools/tests/test_l10n_parity.py (offline
-- verdict). LF and CRLF variants are derived in memory by both.
--
-- This file is a restricted literal table: one "return {...}" holding only
-- literal strings, non-negative decimal integers, true, false and nested
-- tables, without duplicate keys. Lua runs it in an empty environment;
-- Python reads it with the private _parse_literal_table of
-- tools/l10n_catalog.py, which refuses every executable expression.
--
-- offline: the first CatalogSyntaxError or CatalogValidationError of
-- parse_english, parse_packs and the scoped English/pack checks of
-- tools/l10n_catalog.py against the case enum ("valid" when none). runtime:
-- the Diagnostics() load facts, offered languages and probe results of the
-- unchanged core/Localization.lua. The two sides keep their own category
-- names: the mapping, not an equal name, is the parity claim (an invalid
-- pack entry is invalid-text offline and missing_candidate at runtime).
-- P19 and P20 native WoW behaviour is UNKNOWN: their controls record the
-- offline decoding and the LuaJIT harness fact only.
--
-- Registry interlock (G1): the declaration marker is the ASCII token
-- NEXUS-L10N-REGISTRY in core/Localization.lua, used only as the two exact
-- lines registry.marker.open and registry.marker.close around the future
-- declaration block. The sentinel in tools/tests/test_l10n_parity.py passes
-- while the marker, the registry-bound parser (registry.parser in
-- tools/l10n_catalog.py) and bound registry rows are all absent, and only
-- when all three are present together. U1, U2 and U3 cannot ship apart.
return {
    schema = "nexus.l10n.parity_cases",
    schemaVersion = 1,
    status = "S1 characterization of the unchanged runtime; not registry validation",
    shippedProductIds = {},
    unavailable = "This status cannot be shown right now.",
    formatArguments = {banish = {known = true, value = 1}, reroll = {known = false}, freeze = {known = true, value = 3}},
    mappedRows = {
        "P1",
        "P2",
        "P3",
        "P4",
        "P5",
        "P6",
        "P7",
        "P8",
        "P9",
        "P10",
        "P11",
        "P12",
        "P13",
        "P14",
        "P15",
        "P16",
        "P17",
        "P18",
    },
    unknownRows = {"P19", "P20"},
    registry = {
        marker = {
            path = "core/Localization.lua",
            token = "NEXUS-L10N-REGISTRY",
            open = "-- NEXUS-L10N-REGISTRY BEGIN",
            close = "-- NEXUS-L10N-REGISTRY END",
        },
        parser = "parse_registry_declarations",
        pending = "pending_r_union",
        bound = "bound",
        rows = {
            {
                id = "R-P1",
                state = "pending_r_union",
                topic = "complete English",
                case = "undeclared but otherwise valid English entry",
                offline = "undeclared-entry",
                runtime = "rejected and counted (base.undeclared)",
            },
            {
                id = "R-P2",
                state = "pending_r_union",
                topic = "registry-bound parsing",
                case = "declaration and KEY_CONTEXT disagree on kind, placeholders or limit",
                offline = "context-declaration-mismatch",
                runtime = "not applicable",
            },
            {
                id = "R-P3",
                state = "pending_r_union",
                topic = "complete English",
                case = "declared key without English",
                offline = "english-incomplete",
                runtime = "base.missingDeclared +1; key unavailable",
            },
        },
    },
    cases = {
        {
            id = "p01_valid",
            rows = {"P1", "P11", "P12", "P18"},
            enum = {"qaQA"},
            offline = {code = "valid"},
            runtime = {
                base = {present = true, accepted = 4, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 2, rejected = 0},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "text",
                        language = "qaQA",
                        key = "parity.alpha",
                        text = "Alpha qa",
                        source = "candidate",
                    },
                    {
                        kind = "text",
                        language = "qaQA",
                        key = "parity.beta",
                        text = "Beta",
                        source = "base",
                        reason = "missing_candidate",
                    },
                    {
                        kind = "text",
                        key = "parity.braces",
                        text = "Keep {this}, } and 100% as typed",
                        source = "base",
                    },
                    {
                        kind = "format",
                        language = "qaQA",
                        key = "readout.charge_counts",
                        text = "{F} 3 / B 1 / R ?",
                        source = "candidate",
                    },
                    {kind = "format", key = "readout.charge_counts", text = "B:1 R:? F:3", source = "base"},
                    {
                        kind = "text",
                        key = "readout.charge_counts",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "format_requires_arguments",
                    },
                },
            },
        },
        {
            id = "p02_invalid_key",
            rows = {"P2"},
            enum = {},
            offline = {code = "invalid-key", key = "Parity.Upper"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "Parity.Upper",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "invalid_key",
                    },
                },
            },
        },
        {
            id = "p02_invalid_text_empty",
            rows = {"P2"},
            enum = {},
            offline = {code = "invalid-text", key = "parity.empty"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.empty",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p02_invalid_template_english",
            rows = {"P2", "P11"},
            enum = {},
            offline = {code = "invalid-template", key = "readout.charge_counts"},
            runtime = {
                base = {present = true, accepted = 2, rejected = 1, oversized = false, formatted = 0},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "format",
                        key = "readout.charge_counts",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p03_english_65",
            rows = {"P3", "P17"},
            enum = {},
            offline = {code = "english-too-many"},
            runtime = {
                base = {present = true, accepted = 0, rejected = 65, oversized = true, formatted = 0},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.k01",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p17_bounds_64",
            rows = {"P17"},
            enum = {"qaQA"},
            offline = {code = "valid"},
            runtime = {
                base = {present = true, accepted = 64, rejected = 0, oversized = false, formatted = 0},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 64, rejected = 0},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "text",
                        language = "qaQA",
                        key = "parity.kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk",
                        text = "Qa sixty four",
                        source = "candidate",
                    },
                    {kind = "text", key = "parity.k63", text = "Key 63", source = "base"},
                },
            },
        },
        {
            id = "p17_key_65",
            rows = {"P17"},
            enum = {},
            offline = {code = "invalid-key", key = "parity.kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "invalid_key",
                    },
                },
            },
        },
        {
            id = "p04_pack_invalid_text",
            rows = {"P4", "P15"},
            enum = {"qaQA"},
            offline = {code = "invalid-text", key = "parity.alpha"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "text",
                        language = "qaQA",
                        key = "parity.alpha",
                        text = "Alpha",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p04_pack_invalid_template",
            rows = {"P4", "P11"},
            enum = {"qaQA"},
            offline = {code = "invalid-template", key = "readout.charge_counts"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "format",
                        language = "qaQA",
                        key = "readout.charge_counts",
                        text = "B:1 R:? F:3",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p11_template_repeated",
            rows = {"P11"},
            enum = {"qaQA"},
            offline = {code = "invalid-template", key = "readout.charge_counts"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "format",
                        language = "qaQA",
                        key = "readout.charge_counts",
                        text = "B:1 R:? F:3",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p11_template_unknown",
            rows = {"P11"},
            enum = {"qaQA"},
            offline = {code = "invalid-template", key = "readout.charge_counts"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "format",
                        language = "qaQA",
                        key = "readout.charge_counts",
                        text = "B:1 R:? F:3",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p11_template_positional",
            rows = {"P11"},
            enum = {"qaQA"},
            offline = {code = "invalid-template", key = "readout.charge_counts"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "format",
                        language = "qaQA",
                        key = "readout.charge_counts",
                        text = "B:1 R:? F:3",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p11_template_typed",
            rows = {"P11"},
            enum = {"qaQA"},
            offline = {code = "invalid-template", key = "readout.charge_counts"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "format",
                        language = "qaQA",
                        key = "readout.charge_counts",
                        text = "B:1 R:? F:3",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p11_template_lone_open",
            rows = {"P11"},
            enum = {"qaQA"},
            offline = {code = "invalid-template", key = "readout.charge_counts"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "format",
                        language = "qaQA",
                        key = "readout.charge_counts",
                        text = "B:1 R:? F:3",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p11_template_lone_close",
            rows = {"P11"},
            enum = {"qaQA"},
            offline = {code = "invalid-template", key = "readout.charge_counts"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "format",
                        language = "qaQA",
                        key = "readout.charge_counts",
                        text = "B:1 R:? F:3",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p05_orphan_entry",
            rows = {"P5"},
            enum = {"qaQA"},
            offline = {code = "orphan-entry", key = "reason.retired_example"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 1, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "text",
                        language = "qaQA",
                        key = "reason.retired_example",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p06_pack_65",
            rows = {"P6", "P17"},
            enum = {"qaQA"},
            offline = {code = "pack-too-many-entries", key = "qaQA"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 1, rows = {}},
                languages = {"enUS"},
                probes = {
                    {kind = "text", language = "qaQA", key = "parity.alpha", text = "Alpha", source = "base"},
                },
            },
        },
        {
            id = "p07_autonym_65",
            rows = {"P7", "P17"},
            enum = {"qaQA"},
            offline = {code = "invalid-autonym", key = "qaQA"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 1, rows = {}},
                languages = {"enUS"},
                probes = {
                    {kind = "text", language = "qaQA", key = "parity.alpha", text = "Alpha", source = "base"},
                },
            },
        },
        {
            id = "p07_autonym_markup",
            rows = {"P7", "P15"},
            enum = {"qaQA"},
            offline = {code = "invalid-autonym", key = "qaQA"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 1, rows = {}},
                languages = {"enUS"},
                probes = {
                    {kind = "text", language = "qaQA", key = "parity.alpha", text = "Alpha", source = "base"},
                },
            },
        },
        {
            id = "p08_duplicate_english",
            rows = {"P8", "P13"},
            enum = {},
            offline = {code = "duplicate-key", line = 7, column = 5},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {kind = "text", key = "parity.alpha", text = "Second", source = "base"},
                },
            },
        },
        {
            id = "p08_duplicate_pack_entry",
            rows = {"P8"},
            enum = {"qaQA"},
            offline = {code = "duplicate-key", line = 8, column = 13},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 1, rejected = 0},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {kind = "text", language = "qaQA", key = "parity.alpha", text = "Deux", source = "candidate"},
                },
            },
        },
        {
            id = "p09_pack_unknown",
            rows = {"P9"},
            enum = {"qaQA"},
            offline = {code = "pack-unknown", key = "qbQB"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 1, rejected = 0},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {kind = "text", language = "qbQB", key = "parity.alpha", text = "Alpha", source = "base"},
                },
            },
        },
        {
            id = "p10_pack_missing",
            rows = {"P10"},
            enum = {"qaQA", "qbQB"},
            offline = {code = "pack-missing", key = "qbQB"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 1,
                    rows = {
                        {id = "qaQA", accepted = 1, rejected = 0},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {kind = "text", language = "qbQB", key = "parity.alpha", text = "Alpha", source = "base"},
                },
            },
        },
        {
            id = "p10_entries_not_table",
            rows = {"C10"},
            enum = {"qaQA"},
            offline = {code = "unexpected-token", line = 6, column = 19},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 1, rows = {}},
                languages = {"enUS"},
                probes = {
                    {kind = "text", language = "qaQA", key = "parity.alpha", text = "Alpha", source = "base"},
                },
            },
        },
        {
            id = "p13_escape_equivalence",
            rows = {"P13"},
            enum = {"qaQA"},
            offline = {code = "valid"},
            runtime = {
                base = {present = true, accepted = 4, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 1, rejected = 0},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "text",
                        language = "qaQA",
                        key = "parity.ru",
                        text = "\208\160\209\131\209\129\209\129\208\186\208\184\208\185",
                        source = "candidate",
                    },
                },
            },
        },
        {
            id = "p14_overlong",
            rows = {"P14"},
            enum = {},
            offline = {code = "value-not-utf8", line = 7, column = 22},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.bad",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p14_surrogate",
            rows = {"P14"},
            enum = {},
            offline = {code = "value-not-utf8", line = 7, column = 22},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.bad",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p14_above_max",
            rows = {"P14"},
            enum = {},
            offline = {code = "value-not-utf8", line = 7, column = 22},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.bad",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p14_truncated",
            rows = {"P14"},
            enum = {},
            offline = {code = "value-not-utf8", line = 7, column = 22},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.bad",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p15_newline",
            rows = {"P15"},
            enum = {},
            offline = {code = "invalid-text", key = "parity.bad"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.bad",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p15_carriage_return",
            rows = {"P15"},
            enum = {},
            offline = {code = "invalid-text", key = "parity.bad"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.bad",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p15_nul",
            rows = {"P15"},
            enum = {},
            offline = {code = "invalid-text", key = "parity.bad"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.bad",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p15_delete",
            rows = {"P15"},
            enum = {},
            offline = {code = "invalid-text", key = "parity.bad"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.bad",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p15_pipe_colour",
            rows = {"P15"},
            enum = {},
            offline = {code = "invalid-text", key = "parity.bad"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.bad",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p15_pipe_texture",
            rows = {"P4", "P15"},
            enum = {"qaQA"},
            offline = {code = "invalid-text", key = "parity.alpha"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "text",
                        language = "qaQA",
                        key = "parity.alpha",
                        text = "Alpha",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p15_pipe_link",
            rows = {"P4", "P15"},
            enum = {"qaQA"},
            offline = {code = "invalid-text", key = "parity.alpha"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 0, oversized = false, formatted = 1},
                packs = {
                    present = true,
                    adopted = 1,
                    refused = 0,
                    rows = {
                        {id = "qaQA", accepted = 0, rejected = 1},
                    },
                },
                languages = {"enUS", "qaQA"},
                probes = {
                    {
                        kind = "text",
                        language = "qaQA",
                        key = "parity.alpha",
                        text = "Alpha",
                        source = "base",
                        reason = "missing_candidate",
                    },
                },
            },
        },
        {
            id = "p16_ascii_blank",
            rows = {"P16"},
            enum = {},
            offline = {code = "invalid-text", key = "parity.blank"},
            runtime = {
                base = {present = true, accepted = 3, rejected = 1, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {
                        kind = "text",
                        key = "parity.blank",
                        text = "This status cannot be shown right now.",
                        source = "unavailable",
                        reason = "unknown_key",
                    },
                },
            },
        },
        {
            id = "p16_nbsp_only",
            rows = {"P16"},
            enum = {},
            offline = {code = "valid"},
            runtime = {
                base = {present = true, accepted = 4, rejected = 0, oversized = false, formatted = 1},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {kind = "text", key = "parity.nbsp", text = "\194\160", source = "base"},
                },
            },
        },
        {
            id = "p19_ambiguous_escapes",
            rows = {"P19"},
            enum = {},
            offline = {code = "valid"},
            runtime = {
                base = {present = true, accepted = 4, rejected = 0, oversized = false, formatted = 0},
                packs = {present = true, adopted = 0, refused = 0, rows = {}},
                languages = {"enUS"},
                probes = {
                    {kind = "text", key = "parity.alpha", text = "Alpha", source = "base"},
                },
            },
            native = "UNKNOWN",
            proposedCode = "ambiguous-escape",
            decoded = {
                lua51 = {["parity.hex"] = "x41", ["parity.zap"] = "az b", ["parity.uni"] = "u{41}"},
                luajit = {["parity.hex"] = "A", ["parity.zap"] = "ab", ["parity.uni"] = "A"},
            },
        },
        {
            id = "p20_bom",
            rows = {"P20"},
            enum = {"qaQA"},
            derive = {from = "p01_valid", file = "english", prefix = "\239\187\191"},
            offline = {code = "bad-bootstrap", line = 1, column = 1},
            native = "UNKNOWN",
            planPrediction = "unexpected-token",
            harness = {"refused", "same_as_source"},
        },
    },
}
