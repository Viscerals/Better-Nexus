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
- 4,078 keys (the cap is 4,096; 18 entries of headroom): 28 original, 3,320 keys of ten
  families (panel, hud, usertext, chat, library, wishlist, orb, journal, records, guide),
  18 owner integration keys, 629 keys of the v3 supplemental cohort (`remainder_*`
  fragments: Library reasons, Orb runtime/adapter/Continue texts and guidance, Wishlist
  chat and reasons, runtime chat and status lines, /nexus status lines) and 73 keys of
  the v5 supplemental cohort (`v5_source86_supplemental`: Support storage refusals,
  Journal provider sections, generated default names, the Options window title, the
  guide's target trigger line, the unknown-tome fallback) and 8 keys of the v6
  supplemental cohort (`v6_source16_supplemental`: two Journal tome member reasons, the
  identity-found note in its two display forms with and without the editor instruction,
  and the second and third paragraphs of the Orb offer-open text) and 2 keys of the v8
  cohort (`v8_source16_journal_names`: the generated Journal tome and member fallback
  names). `KEY_CONTEXT.json`'s `fullUiCatalog.totalKeys` and the English base hold the
  same 4,078.
- Contracts for complete translations (v6, caps unchanged): fourteen one-line templates
  (two Orb block sentences and twelve Wishlist editor chat lines) are `lines = true`
  templates (raw at most 1,024 bytes, result at most 2,048) that stay one displayed line;
  `orb.runtime.recovery_needs_fresh_reply` and the paused-Continue Orb headline are
  blocks. The Orb offer-open text is shown as three keyed paragraphs, in order, joined by
  one space at the receiver, and only when all three have a valid candidate (otherwise
  the whole exact English).
- A visible string is looked up at its real display receiver
  (`Nexus.Localization.Text/Format`, at call time), or, where a producer keeps raw
  English that is compared, recorded or parsed, said at the display through a
  phrasebook (`Localization.Phrase`: exact texts, the producer's own formats with typed
  slots, nested values; a format with two or more slots is used only when the English
  splits one way, otherwise the raw text is shown). Name-bearing Wishlist chat lines are
  presented from the producer's own typed values; so are the Orb saved-format marker
  refusal (the runtime's display facts for that exact text) and the adapter's
  identity-found note (UserText and /nexus wishlist say it without its lead; the Orb
  window and the /nexus status advisor line say it whole, as each showed before). The
  Journal splits only the tome-state reason lists the producers join with "; ": each
  known reason through its key, an unknown one as given. Its generated tome and member
  fallback names are said from the adapter's facts for exactly that row; a name the game
  client gives stays as given, however it reads. A missing or invalid pack entry shows
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
- `data/LocalizationPacks.lua` holds a draft entry for every one of the 4,078 English
  keys in each of the six optional packs (24,468 entries), in the order of the English
  base; pack IDs and autonyms are unchanged. Each value is taken unchanged from its
  selected per-language draft cohort. Values that later cohorts replace were removed
  before those cohorts were applied, so a missing or invalid entry shows the exact
  English of its key, never an older translation. 543 entries are byte-identical to
  their English (for example product, game or code-owned terms kept as drafted, and
  placeholder-only texts). For 529 of them `RELEASE_LANGUAGES.json` records a
  `legitimately_identical` `entryReview` declaration: an automated source-paired review
  with a public evidence reference, not fluent human or native acceptance. The other 14
  have no declaration yet. Every entry is `draft_unreviewed`: technical and automated
  source-paired review only.

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
native glyph, font, layout and input checks are NOT_RUN. Fluent review of the composed
packs, the matched full CI, private installation and native review are separate gates
owned outside this source change.

## Not complete

- The original 533 pending and 8 unknown-visibility rows are dispositioned row by row in
  the task-local successor evidence (global v8). Still open at this source:
  - dependencies: record dates, fight durations and K/M number notation stay
    code-formatted (no temporal or number grammar; the surrounding words are keyed), and
    exact client-locale class and NPC names (keyed Nexus copy; equality with the client's
    own names is UNKNOWN);
- In-text legacy rewrites of UserText.Message whose source fragment has no producer at
  this source (ARMED/UNARMED, tight horizon, waiting for owned-echo sync, "non-conformant
  data") are kept for compatibility; this is not proof that no external text reaches
  them.
- No plural, gender, date or number grammar exists; paired one/other keys keep the
  English two-way choice.
- `tools/l10n_catalog.py` follows the runtime's 4,096-entry cap (declarations, English
  base and each pack) and its four kinds `text`, `block`, `format` and `template`. The
  shared parity corpus (`tests/prototype/fixtures/l10n_parity`) keeps its committed 64/65
  pilot cases and derives the current 4,096/4,097 boundary controls from them in memory.
  The catalog itself has 4,078 keys, 18 below the cap. Results of the Python tests bound
  to the shipped catalog, packs and release metadata, within their 45-second per-file
  limit, are recorded separately against the final source; none is claimed here.
