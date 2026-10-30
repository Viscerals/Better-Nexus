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
- 4,068 keys (the cap is 4,096; 28 entries of headroom): 28 original, 3,320 keys of ten
  families (panel, hud, usertext, chat, library, wishlist, orb, journal, records, guide),
  18 owner integration keys, 629 keys of the v3 supplemental cohort (`remainder_*`
  fragments: Library reasons, Orb runtime/adapter/Continue texts and guidance, Wishlist
  chat and reasons, runtime chat and status lines, /nexus status lines) and 73 keys of
  the v5 supplemental cohort (`v5_source86_supplemental`: Support storage refusals,
  Journal provider sections, generated default names, the Options window title, the
  guide's target trigger line, the unknown-tome fallback). `KEY_CONTEXT.json`'s
  `fullUiCatalog.totalKeys` and the English base hold the same 4,068.
- A visible string is looked up at its real display receiver
  (`Nexus.Localization.Text/Format`, at call time), or, where a producer keeps raw
  English that is compared, recorded or parsed, said at the display through a
  phrasebook (`Localization.Phrase`: exact texts, the producer's own formats with typed
  slots, nested values; a format with two or more slots is used only when the English
  splits one way, otherwise the raw text is shown). Name-bearing Wishlist chat lines are
  presented from the producer's own typed values. A missing or invalid pack entry shows
  the exact English.
- English output is byte-identical except these recorded, authorized changes:
  `panel.note.language_scope` (v4, current scope statement), `guide.body.why_target`
  and `orb.tooltip.mini_usage` (v5 copy corrections, raw leaf/fallback and catalog
  changed together), the guide's target trigger line (v5, latency promise removed), the
  Options window title "Nexus Options" (v5), Wishlist assignment notices for names that
  contain "no net gain" or "coverage lost:" (v5: the notice instead of an inherited false
  "Not saved" refusal), a Wishlist Save/Create Auto consent sentence whose destination
  label exceeds the 1,024-byte slot (v5: the exact English sentence instead of the
  seam's "cannot be shown" status), and generated default names of a new draft (v5:
  in the active language, once, at creation).
- `data/LocalizationPacks.lua` is unchanged: the six optional packs that ship still hold
  their 27 draft entries. Full-catalog translations are task-local drafts that are not
  installed; until a shipped pack holds a key, that key shows English.

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
native glyph, font, layout and input checks are NOT_RUN. The six language drafts, their
composition into packs, the matched full CI, private installation and native review
are separate gates owned outside this source change.

## Not complete

- The original 533 pending and 8 unknown-visibility rows are dispositioned row by row in
  the task-local successor evidence (global v5). Still open at this source:
  - dependencies: record dates, fight durations and K/M number notation stay
    code-formatted (no temporal or number grammar; the surrounding words are keyed), and
    exact client-locale class and NPC names (keyed Nexus copy; equality with the client's
    own names is UNKNOWN);
  - Nexus-owned, not done: the composed GameAdapter note "Wishlist identity found;
    <reason>." (UserText strips its prefix while the Orb window shows it whole, so one
    key cannot keep both English displays), and the Orb saved-format marker line (two
    adjacent producer slots: kept raw rather than split ambiguously).
- In-text legacy rewrites of UserText.Message whose source fragment has no producer at
  this source (ARMED/UNARMED, tight horizon, waiting for owned-echo sync, "non-conformant
  data") are kept for compatibility; this is not proof that no external text reaches
  them.
- No plural, gender, date or number grammar exists; paired one/other keys keep the
  English two-way choice.
- `tools/l10n_catalog.py` and its tests still encode the 64-entry pilot and the two
  pilot kinds, and the shared parity corpus (`tests/prototype/fixtures/l10n_parity`)
  still encodes the 64/65 boundary. Their update is a separate, owned tooling change;
  until then `localization_parity` and the registry-bound Python tests fail on the
  composed catalog.
