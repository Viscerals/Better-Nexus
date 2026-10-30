# Full visible-UI catalog (issues #143-#148)

Refs #143, #144, #145, #146, #147, #148. Status: author-composed English catalog,
review pending. This document describes the current full-UI scope; the historical
pins and statements in [FULL_COVERAGE.md](FULL_COVERAGE.md),
[KEYS_AND_GLOSSARY.md](KEYS_AND_GLOSSARY.md) and the other documents here are
unchanged.

## What is in the source

- `core/Localization.lua` keeps the `text` and `format` rules and adds two declared
  kinds (see its "Full-UI kinds" header): `block` (one meaning in several lines, LF
  allowed, at most 1024 bytes) and `template` (named placeholders with code-owned slot
  types `count` or `text`, a per-key result limit up to 2048 bytes, optional
  `lines = true`). `MAX_BASE_ENTRIES` is the bounded 4096 for the declarations, the
  English base and each pack; above it the same fail-closed refusal applies.
- `data/LocalizationEnglish.lua` and the registry block hold the original 28 entries
  first and unchanged, then a generated `NEXUS-L10N-FULL-UI` section per family.
  `docs/localization/KEY_CONTEXT.json` has one row per key (`cohort: fullui:<family>`
  for the new rows) and a `fullUiCatalog` summary.
- 3,366 keys: 28 original, 3,320 keys of ten families (panel, hud, usertext, chat,
  library, wishlist, orb, journal, records, guide) and 18 owner integration keys (labels
  Help quotes by name that the families had kept as literals for tests).
- Every visible string adopted in a family is looked up at its real display receiver
  (`Nexus.Localization.Text/Format`, at call time). English output is byte-identical;
  a missing or invalid pack entry shows the exact English.
- `data/LocalizationPacks.lua` is unchanged: the six optional packs still hold their 27
  draft entries. Translation of the full catalog is separate work; until a pack holds a
  key, that key shows English.

## Evidence in the source

- `tests/prototype/l10n_ui_<family>.lua` (ten files): each family's windows rendered
  through their real entry points under a pseudo pack activated at session start
  (`tests/prototype/l10n_pseudo_support.lua`), English, long and missing-entry runs, and
  passivity checks.
- `tests/prototype/l10n_catalog_consumers.lua`: every declaration has English, every
  key literal passed to the seam is a reviewed key of the matching kind, every reviewed
  key has a consumer (literal, or path-derived and listed by
  `GuidedSetupUI.L10nDerivedKeys`).
- `tests/prototype/l10n_full_contract.lua`, `l10n_settings_identity.lua`,
  `l10n_passivity_library.lua`, `l10n_pseudo_support_guards.lua`.

All of it is synthetic offline evidence. Competent language review is UNASSIGNED and
native glyph, font, layout and input checks are NOT_RUN.

## Not complete

- Visible text still English is listed per entry, with reason, in the translator
  manifest's `pending` list (533 items at the composition pin, mostly Orb runtime
  texts without a display id and Wishlist controller chat that passes through the
  English UserText rewrite); 8 items have unknown visibility.
- No plural, gender, date or number grammar exists; paired one/other keys keep the
  English two-way choice.
- `tools/l10n_catalog.py` and its tests still encode the 64-entry pilot and the two
  pilot kinds, and the shared parity corpus (`tests/prototype/fixtures/l10n_parity`)
  still encodes the 64/65 boundary. Their update is a separate, owned tooling change;
  until then `localization_parity` and the registry-bound Python tests fail on the
  composed catalog.
