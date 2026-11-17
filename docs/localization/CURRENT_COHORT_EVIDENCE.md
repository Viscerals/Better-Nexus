# Current localization cohort evidence (#148)

Refs #141, #142, #143, #144, #145, #146, #147, #148, #149.

Source pin `8393f5f4b61a0d62b5043b861539be868ebf80f6` (tree
`8c1397ba8856d6d6973d5dd28e7fa0aecebb4ada`). Status: frozen documentation
evidence. Independent Codex Spec/Standards review is PENDING.

This ledger freezes the current English base, the draft optional-pack cohort
and the runtime contract they load under at that pin. It changes no source,
data, test, tool or release metadata, and it adds no key, translation,
language, alias or wording. It accepts no issue, window family, language,
review or native gate. The machine-readable form is
[CURRENT_COHORT_EVIDENCE.json](CURRENT_COHORT_EVIDENCE.json). It holds the
exact per-entry hashes.

The declarative contract pin of [KEY_CONTEXT.json](KEY_CONTEXT.json),
[RELEASE_LANGUAGES.json](RELEASE_LANGUAGES.json) and
[FULL_COVERAGE.md](FULL_COVERAGE.md) stays the historical
`5c77eec5b791f64468576e37a70b3855375b7fcb` (tree
`692c6693ba50ba5ffc2bf8f3f724b0bceeeda65c`). `KEY_CONTEXT.json` now
anchors its current facts to `8393f5f` in `currentSourceBinding`.

## Source inputs

Hashes are SHA-256 of the committed Git blob (LF line ends), read with
`git show 8393f5f:<path>`. `.gitattributes` checks `*.lua` and `*.toc` out
with CRLF. The checkout hashes of the three localization Lua files equal the
runtime file hashes recorded by the final offline run.

| Path | Git blob | SHA-256 (blob) | Bytes | Checkout CRLF SHA-256 |
|---|---|---|---|---|
| `data/LocalizationEnglish.lua` | `024557e8ffb9d6f587080e46b47b33daea25e492` | `69d3998950b651f5b666f7b6a65a718c97bfb3719bfb4523d5c60037ed7f20a5` | 3916 | `755f2f5d434a23bbff28ad01f23711e14601e1a4c8df5ee99269038ee13b5cf8` (3970) |
| `data/LocalizationPacks.lua` | `1898a5ff36caea52d747d47447fdf034d96b5ce9` | `5c8d10bb711474a0374a0ad851e4f3608ede2389fb58fd01b34ad3c4cda3de95` | 21168 | `5effb6a15a63822acde26c65de73acf54bf2b449fb7d35e7979aae3486d2a78d` (21413) |
| `core/Localization.lua` | `02f8d8d8dc4e6fe367501da4d868153236e1dd22` | `1adb20d8e5aea04501c51eeab647e82f3bf7b8f6b88cfb56fe7675c9fe66e96b` | 32714 | `3e9ae6ed8fc3bf48bc323d456f13611e78893194969f3e9108df156d053beb54` (33404) |
| `core/UserText.lua` | `935076c017e779f1d0d832667fbd22a17c16859f` | `b4bf7a769f0a85511fe6f5f3f6dc27efcce1d12df073eafe66e2e3e21d62eec6` | 73638 | — |
| `ui/Panel.lua` | `c8021912322f33aff406e6bfd75ac0e503107f75` | `1fc48125dcc7e63e7f745812aa8d2dcd96d51243f7aed86ff0e1cd2c07ec8342` | 326675 | — |
| `ui/Readout.lua` | `f4ef71c253fe1506ebf25b0d5b084487ffa03cb0` | `24d229a14fbed3a206f33605c3a4c490204dd1c71d2bf1d70c64f97499da92d1` | 30119 | — |
| `ui/Help.lua` | `8c3ddaafdcd1038114737ed2a2df8b75ac66e8f7` | `ee1bfa688ea7ecb6f99efe5fff7148a21e92c99bca58ff0de16e8762c07f02a1` | 62746 | — |
| `data/DefaultProfile.lua` | `a51a675022b5c6195253ed51bc33fd77e4a30b3c` | `447f0b9405fbf76df98b0693968a5602f640382e9d2dc09bdcfb77a0d078c8f4` | 5513 | — |
| `Nexus.toc` | `38a4b95907a20e97d0d06cfb0df70d6e99b2d01f` | `298532cd416cdf8ef28c08f8381b944bb8506680a23dd8d36c0213b4fa8a4bd3` | 2517 | — |
| `docs/localization/KEY_CONTEXT.json` | `9863469390bdf341ff850c2b8b0c152f61ec80f8` | `11d6a95cafebc7112b2c45f73266a0bf258a55426013319a7137a267413b6894` | 28351 | — |
| `docs/localization/RELEASE_LANGUAGES.json` | `e5dd0bb0f583bc065f0b5b9c96511d8a176b6d57` | `153141a9276effc298206e641b6fa28c25961d60a43743ea018c5d81d961dbec` | 9748 | — |
| `docs/localization/FULL_COVERAGE.md` | `f4208fbe2f4345408a8f3077b32ffce7be91309d` | `fda6618f75ff3b829c9bd078b4a8ce1a990b7a6e30d6546b809b84bbb7813298` | 11111 | — |
| `tools/l10n_catalog.py` | `d4e4b6f64f1cb1f01bde9609dbb87d421827520e` | `dfd1fcb9cabc4131831b6dbafa973b1cbb08faef1ecbdcf104a2c2d960aa94c8` | 73441 | — |
| `tools/tests/test_l10n_catalog.py` | `2faab202d391977591885709fe45dc2dae12790e` | `1711bc71a5116f38b0a058c7ee695e116fe8b13c9073747f8c6e4f7013973823` | 188168 | — |
| `tools/run_prototype_tests.py` | `06101ea378287e1817fb1b659e46f9f2498409a9` | `16e817eee61ea67cbd78be215160caf75b85b4a4d904cb7912496ddfe3669039` | 42140 | — |
| `tools/ci_check.py` | `a2645a77bc207737f50b9b2451a1bd0084e27b2c` | `e00472e6c3c5c060011553cedccd56adb37c35cb795a3103ce90428c09c9d7a6` | 12685 | — |
| `tests/prototype/terminology.lua` | `505f293c899d67c60f4064ebc471cfb518e9b0a4` | `cdca23cb62085c654c9bcd2bd983c89e86b57ac5a3ea9c26dbc57d8b0e107f0d` | 76054 | — |
| `tests/prototype/terminology_consumers.lua` | `d7dc6509d0bd196c20bcb6878c0acb5e3e678891` | `9857d3352743e5fbca0d647d164bc329c79146b6e8448e1df378c2adac6cf02a` | 132280 | — |
| `tests/prototype/panel_options_label.lua` | `111e3a38fd041fbfc72e1a41e353053256ec4bb2` | `9153eb92203154732397267d2e6b776a77808a193b9b0a9f48f67daa454ac1fa` | 16500 | — |

The localization data, core, documents, catalog tool and its tests are
byte-identical across `b1ef408`, `87de3ff` and `8393f5f`.
`KEY_CONTEXT.json` and `FULL_COVERAGE.md` rows show their blobs before this
revision.

## Runtime contract (core/Localization.lua at 8393f5f)

- Lua 5.1 and `## Interface: 30300`, with the addon identity `Nexus`.
  `Nexus.toc` lines 13-15 load `data/LocalizationEnglish.lua`, then
  `data/LocalizationPacks.lua`, then `core/Localization.lua`.
- **Keys.** A key is 3 to 64 bytes: two or more dot-separated segments of
  lower-case ASCII letters, digits and `_`, each starting with a letter. A
  key names a meaning. It is never made from English, player or game text.
- **Text.** Text is 1 to 256 bytes of well-formed, shortest-form UTF-8 of
  Unicode scalar values. It needs at least one byte outside ASCII whitespace
  (9-13 and 32). It may not contain a control byte (0-31, 127) or `|`, so no
  newline and no colour, link or texture markup. Nothing is normalized.
- **Static text** is shown exactly as stored. A static key used with `Format`
  answers `wrong_key_kind`.
- **Templated text.** Only a key with a code-owned schema is a template.
  Today that is `readout.charge_counts`, with the fields `banish`, `reroll`
  and `freeze`. Each named placeholder appears exactly once, in any order.
  `{{` and `}}` are literal braces, and `%` and every other byte are literal.
  `{1}`, `{name:d}`, unknown, missing or repeated names and lone braces make
  a template invalid. A template key used as static text answers
  `format_requires_arguments`.
- **Counts.** A count slot is exactly `{known = true, value = N}`, where N is
  a finite whole number of 0 or more shown with `tostring`, or exactly
  `{known = false}`, shown as `?`. Zero is a known count, never unknown.
  Substitution is one pass.
- **Result limit.** The result limit is 254 bytes (`MAX_TEXT_BYTES - 2`), so
  the consumer's ` ~` estimate marker still fits. An over-limit candidate
  falls back to the English template. An over-limit English result becomes
  the unavailable status. Results are never cut.
- **Unavailable status.** `This status cannot be shown right now.` is the
  English-only safe status for an invalid or unknown key, a kind mismatch and
  invalid arguments. No pack translates it.
- **Fallback.** `Text` and `Format` called without a pack use the active
  pack. A missing or invalid candidate gives the exact English text, or the
  English template with the same arguments, with source `base` and a counted
  reason. `Resolve` and `FormatResolve` are pure supplied-pack functions.
- **Packs.** A pack is adopted only with a valid autonym of at most 64 bytes
  and a plain entries table of at most 64 entries. Otherwise the whole pack
  is refused and not offered. An entry is copied only for an existing English
  key whose text, or compiled template, is valid. A candidate never adds a
  key.
- **Active language.** The active language is set once per Lua session. An
  ID without an adopted pack gives English, and so do an absent value and
  the Automatic preference. This build has no evidenced client alias. A
  changed preference applies at the next reload or login.
- **Caps.** `MAX_KEY_BYTES` 64, `MAX_TEXT_BYTES` 256, `MAX_BASE_ENTRIES` 64,
  `MAX_NAME_BYTES` 64, `MAX_LANGUAGES` 16 and `MAX_DIAGNOSTIC_KEYS` 8.
  `tools/l10n_catalog.py` mirrors them.
- This contract proves no native glyph, font, locale, layout, input or
  visibility behaviour.

## Frozen cohort

| Fact | Value at 8393f5f |
|---|---|
| English keys | 28: 27 static texts, 1 template |
| Draft entries per optional pack | 27: 26 static texts, 1 template |
| Optional packs | `frFR`, `deDE`, `esES`, `plPL`, `ptBR`, `ruRU` |
| Draft entries in total | 162 (6 × 27) |
| Missing in every optional pack | `panel.button.options` |
| Behaviour of the missing key | exact English `Options`, source `base`, reason `missing_candidate`, counted on each call |
| Entries identical to English | 0 |
| Template placeholder order | `banish`, `reroll`, `freeze` in every pack; the grammar permits reordering, but no pack uses it |
| Contract violations in the data | 0 |
| Review state | every optional entry `draft_unreviewed`; no `entryReview` declaration |

Autonyms and their bytes are `Français` (9), `Deutsch` (7), `Español` (8),
`Polski` (6), `Português (Brasil)` (19) and `Русский` (14). Each pack lists
its entries in English order, without the missing key. Fallback English and
autonyms never count as translation.

## Cap arithmetic

`MAX_BASE_ENTRIES = 64` bounds the English base (static texts and templates
together) and, separately, each pack.

- **English base.** 64 - 28 = **36** more English entries fit at this pin.
- **Per pack.** 64 - 27 = 37 free slots. A pack entry is admitted only for
  an existing English key, so today each pack has exactly one more
  admissible entry, `panel.button.options`, until the English base grows.
- **Failure mode.** Above 64, the English base adopts nothing, and every key
  then answers the unavailable status. A pack above 64 is refused
  (`tests/prototype/terminology.lua:335` and `:342`).
- **Batch limit.** The historical limit of 60 newly adopted keys per family
  batch does not raise the cap. Without a separately reviewed contract change
  to `core/Localization.lua`, `tools/l10n_catalog.py` and their tests, no more
  than 36 new English keys can be adopted. Any cap expansion is separate
  engineering work. This ledger does not widen it.

## Per-key context and fallback inventory

Every pack column is `draft` (a `draft_unreviewed` entry is present) or
`EN` (missing; English fallback). Each entry's SHA-256 and byte length, and
the per-pack template order and output bound, are in the JSON ledger.

| # | Key | Kind | Exact English | Bytes | Consumers at 8393f5f | Producer | frFR deDE esES plPL ptBR ruRU |
|---|---|---|---|---|---|---|---|
| 1 | `reason.save_in_progress` | text | `Saving is still in progress; wait for its final result` | 54 | `core/UserText.lua:53` map → `:78` LocalizedReason → `:96` T.Message | `ROOT_MUTATION_PENDING` | draft draft draft draft draft draft |
| 2 | `reason.list_preparing` | text | `This list is still being prepared` | 33 | `core/UserText.lua:54` map → `:78` LocalizedReason → `:96` T.Message | `CURSOR_REQUIRED` | draft draft draft draft draft draft |
| 3 | `reason.saved_data_reading` | text | `Reading your saved data` | 23 | `core/UserText.lua:55` map → `:78` LocalizedReason → `:96` T.Message | `STORE_PENDING` | draft draft draft draft draft draft |
| 4 | `reason.wait_three_choices` | text | `Waiting for the next three Echo choices` | 39 | `core/UserText.lua:58` map → `:78` LocalizedReason → `:96` T.Message | `waiting for three-card board` | draft draft draft draft draft draft |
| 5 | `reason.wait_pending_pick_count` | text | `waiting for pending-pick count` | 30 | `core/UserText.lua:59` map → `:78` LocalizedReason → `:96` T.Message | `waiting for pending-pick count` | draft draft draft draft draft draft |
| 6 | `readout.charge_counts` | format ({banish}, {reroll}, {freeze}; ≤ 68 of 254 B known) | `B:{banish} R:{reroll} F:{freeze}` | 32 | `ui/Readout.lua:326` | — | draft draft draft draft draft draft |
| 7 | `panel.button.my_builds` | text | `My Builds` | 9 | `ui/Panel.lua:2130`; `ui/Panel.lua:5250` | — | draft draft draft draft draft draft |
| 8 | `panel.tooltip.open_my_builds` | text | `Open My Builds` | 14 | `ui/Panel.lua:2145`; `ui/Panel.lua:3363` (Plan hub) | — | draft draft draft draft draft draft |
| 9 | `panel.tooltip.my_builds_destination` | text | `Open the server My Builds page. Choosing a different Saved Build there changes the active loadout.` | 98 | `ui/Panel.lua:2146`; `ui/Panel.lua:3364` (Plan hub) | — | draft draft draft draft draft draft |
| 10 | `panel.button.assign_wishlist` | text | `Assign Wishlist` | 15 | `ui/Panel.lua:2582` | — | draft draft draft draft draft draft |
| 11 | `panel.tooltip.assignment_heading` | text | `Assign Wishlist` | 15 | `ui/Panel.lua:2592`; `ui/Panel.lua:3361` (Plan hub) | — | draft draft draft draft draft draft |
| 12 | `panel.tooltip.assignment_chooser` | text | `Opens the Echo Journal with its Wishlist chooser for this loadout. Nothing is assigned until you choose a Wishlist there.` | 121 | `ui/Panel.lua:2593`; `ui/Panel.lua:3362` (Plan hub) | — | draft draft draft draft draft draft |
| 13 | `panel.button.create_wishlist` | text | `Create Wishlist` | 15 | `ui/Panel.lua:2600` | — | draft draft draft draft draft draft |
| 14 | `panel.tooltip.create_wishlist_heading` | text | `Import or create a wishlist` | 27 | `ui/Panel.lua:2612` | — | draft draft draft draft draft draft |
| 15 | `panel.tooltip.create_wishlist_source` | text | `Paste a wishlist string or build one directly in Nexus.` | 55 | `ui/Panel.lua:2613` | — | draft draft draft draft draft draft |
| 16 | `panel.tooltip.create_wishlist_draft` | text | `This opens the Wishlist editor with a draft. Nothing is saved or assigned until you press Create & assign or Create unassigned there.` | 133 | `ui/Panel.lua:2616`; `ui/Panel.lua:3360` (Plan hub) | — | draft draft draft draft draft draft |
| 17 | `panel.heading.locked_targets` | text | `LOCKED TARGETS` | 14 | `ui/Panel.lua:1376` | — | draft draft draft draft draft draft |
| 18 | `panel.tooltip.locked_remaining` | text | `Locked targets remaining` | 24 | `ui/Panel.lua:1391` | — | draft draft draft draft draft draft |
| 19 | `panel.tooltip.locked_plan` | text | `These targets are planned for your locked Echo slots (a plan designs at most six target copies).` | 96 | `ui/Panel.lua:1392` | — | draft draft draft draft draft draft |
| 20 | `panel.tooltip.locked_acquire` | text | `Acquire the exact requested Echo and quality first.` | 51 | `ui/Panel.lua:1393` | — | draft draft draft draft draft draft |
| 21 | `panel.tooltip.locked_placement` | text | `Owned copies still need to be placed in locked Echo slots.` | 58 | `ui/Panel.lua:1394` | — | draft draft draft draft draft draft |
| 22 | `panel.tooltip.locked_not_freeze` | text | `Current locked Echo slots and card Freeze are separate.` | 55 | `ui/Panel.lua:1395` | — | draft draft draft draft draft draft |
| 23 | `panel.tooltip.locked_acquire_list` | text | `Still need to acquire:` | 22 | `ui/Panel.lua:1397` | — | draft draft draft draft draft draft |
| 24 | `panel.tooltip.open_wishlist_editor` | text | `Click to open Wishlist Editor` | 29 | `ui/Panel.lua:1408`; `ui/Panel.lua:2482` | — | draft draft draft draft draft draft |
| 25 | `panel.heading.progress` | text | `PROGRESS` | 8 | `ui/Panel.lua:2385` | — | draft draft draft draft draft draft |
| 26 | `panel.heading.still_needed` | text | `STILL NEEDED` | 12 | `ui/Panel.lua:2398`; `ui/Panel.lua:5508` | — | draft draft draft draft draft draft |
| 27 | `panel.heading.extra_copies` | text | `EXTRA COPIES` | 12 | `ui/Panel.lua:2489` | — | draft draft draft draft draft draft |
| 28 | `panel.button.options` | text | `Options` | 7 | `ui/Panel.lua:752`; `ui/Panel.lua:759` | — | EN EN EN EN EN EN |

Each key's meaning is recorded in the `meaning` field of
[KEY_CONTEXT.json](KEY_CONTEXT.json), copied unchanged into the ledger.

### Fallback boundaries by consumer

- **Reasons (`reason.*`).** `core/UserText.lua:52` maps a raw producer code
  to a key. The raw code stays the lookup and is never rewritten.
  `LocalizedReason` (`:78`) calls `Text`. A result with source `unavailable`
  shows that English safe status plus `T.Details(code)`. When the seam is
  absent, the two wait reasons keep their exact English bytes
  (`legacyWaitText`, `:63`), and the other three use the generic English
  line with the raw code.
- **Charge row (`readout.charge_counts`).** `ui/Readout.lua:326` normalizes
  each count to a whole number or unknown before `Format`. It appends ` ~`
  after the complete row. A result with source `unavailable`, or an absent
  seam, gives the English row built at `:335`.
- **Panel keys (`panel.*`).** A missing or invalid entry gives the exact
  English base text. `M.OptionsLabel` (`ui/Panel.lua:752`) also replaces a
  resolved label that begins with `!` by the pure English base. Only
  `M.OptionsText` (`:759`) adds the trusted-notice `! `.
- **Plan hub reuse.** Five `panel.tooltip.*` keys are also the tooltip title
  or text of the Plan hub dropdown rows (`ui/Panel.lua:3352`
  `M.HubMenuItems("plan")`, lines 3360-3364). Those rows' labels, the
  `Wishlist Editor` tooltip title and the closing note are hard-coded
  English. The first-run Create Wishlist button and the hub's
  `Wishlist Editor` row both call `Nexus.WishlistEditor.Show()`, so
  `panel.tooltip.create_wishlist_draft` keeps the same action in both.

## #147 history versus current source

The facts below come from the public #147 body, latest checkpoint
2026-10-26 05:45 UTC, read on 2026-10-29. The search for objects used
`git cat-file` over the shared object store and 45 other local repositories.
It was a bounded search, not a global absence claim.

| Part | Reported pin | Reported result | Object found | At 8393f5f | State |
|---|---|---|---|---|---|
| U1 corrected runtime registry | `38662fa6265e22c2bd7e9637ba54c5b8156375e6`, tree `6fd6f983a840c3b649de0a553633801b1bd5e402` | 541 contract assertions, 7 affected fixtures, catalog 76, inventory 8, runner 49 and content check; fresh review not started | no | not integrated | reported, unproven; not accepted |
| U1 earlier draft | `4bce313bf43f666d59b8bc157361ec038b6a1819`, tree `e1230fccdaf5bdc7b66b7d5ba8698a632406c0a7` | 499 assertions; reviews requested fixes; full run 557/558 | no | not integrated | superseded, unproven |
| Stale Store-owner guard correction cited by #147 | `646a37e7aa39f167205b2813f6edd0ddbb406a79` | the correction for the one failed fixture | yes | ancestor | present in history; not U1, U2 or U3 |
| U2 complete-English admission | none | packet rebuilt from `38662fa`; implementation not started | n/a | not integrated | prepared, not started as last reported |
| U3a syntax-only parser | `5f5b4628c91236d65d60f99207a3d2a8741fcb65` | catalog 95/96; the sole failure is a documentation phrase split across a physical newline; documentation-only repair prepared, not launched | no | not integrated | reported, unproven; not fixed or accepted |
| U3b semantic binding | none | n/a | n/a | not integrated | PENDING |

Current source confirms that none of U1, U2 or U3 is integrated:

- `core/Localization.lua`, `tools/l10n_catalog.py` and their test file
  contain no registry symbol.
- The catalog suite has the original 76 test methods, not U3a's 96.
- `MAX_BASE_ENTRIES` is still 64.

The historical implementation owner named on #147 is a label only. No
current localization worker heartbeat was verified, and this ledger assigns
no worker. The transfer and provider-approval holds recorded on #147 are
historical and are not current blockers under the standing scoped
authorization. Nothing is merged, ported or rerun from that lane here.

## Validator bindings

**Current, at 8393f5f:**

- **Tool.** `tools/l10n_catalog.py` has status
  `IMPLEMENTED_DRAFT_REVIEW_PENDING`. It is the scoped static-catalog
  validator: syntax parser, `validate_catalog_data`, `catalog_report` and
  the B3b read-only command line.
- **Tests.** `tools/tests/test_l10n_catalog.py` has 76 tests. It is
  registered second in `PYTHON_TESTS` and runs as its own process from
  `tools/ci_check.py`.
- **Runtime fixtures.** `tests/prototype/terminology.lua`,
  `terminology_consumers.lua` and `panel_options_label.lua` run in a
  synthetic offline Lua 5.1 harness.

**Historical, preserved and not rerun here.** Every pin below is an
ancestor of `8393f5f` in local Git history.

| Pin | What it established |
|---|---|
| `5c77eec` / `692c669` | declarative contract pin: six English keys, three inherited drafts per pack |
| `d830623` | chooser and three-message slice; #148 reports 526/526 full and 98-file content |
| `ea64843` / `0f03f56` (PR #161 head) | 18 added drafts, six messages per pack; published 526 PASS full, 10 focused, 98 content, hosted CI 3/3 (run 40228049254); the earlier failed run 40225470734 (525/1 at `ce24827b`) is retained. PR #161 was open, draft and unmerged when read on 2026-10-29 |
| `55d7350` / `9a7c51f` | Root-admitted technical reference: 27 keys, 27 drafts per pack, 21 `ui/Panel.lua` bindings |
| `ac2cdf5` / `458b27a` | last change to `data/LocalizationPacks.lua`; still the current packs blob |
| `a50372b` / `0f9f685` | first commit holding `panel.button.options` (#165) |

The PR #161 six-message delivery and the current 27-entry-per-pack cohort
are distinct. Neither establishes full family coverage.

## Final offline validation at 8393f5f

These are sanitized facts from a root-held local receipt. The raw receipt
and logs are private and not committed. The receipt's SHA-256 is
`862607b14c0d36dd8254c4b960370a815a492d98454a32c2f3172c00b1f64d43`, and the
results' SHA-256 is
`be61f5092076369c36c1a08641f8de1a9753912259d88a843ce52ab5a6e34040`.

- **Run.** Commit `8393f5f` with tree `8c1397b`, full-ci scope, exit 0. It
  ran from 22:45:36 to 22:59:34 UTC on 2026-10-29.
- **Lua.** 599 PASS, 0 failed, 0 not run, under LuaJIT. The parse row says
  `interpreter=Lua 5.1; not a native WoW assertion`.
- **Python.** Version 3.14.7. Both registered files passed:
  `test_l10n_inventory.py` with 8 cases and `test_l10n_catalog.py` with 76,
  so 84 cases in total.
- **Runtime hashes.** The runner emitted 99 runtime file hashes, and they
  matched the working files, including the three localization Lua files
  above.
- **Limitation.** The source snapshot was taken after CI. No raw pre-CI
  snapshot was recorded, and no measured raw pre/post equality is claimed.

| Row | Status | Relevant assertions |
|---|---|---|
| `terminology` | PASS (2359 checks) | `terminology.lua:74`: base accepted 28, formatted 1, rejected 0. `:112`: exactly 28 sorted keys. `:118-119`: Options resolves from the base. `:165`, `:294-295`: a missing candidate falls back to English and is counted once. `:335`, `:342`: 64 accepted and 65 fail closed |
| `terminology_consumers` | PASS | `:543-545`: the real Readout row (banish 0, reroll unknown, freeze 7) in English and each pack. `:248-251`: a pack without Options records a counted fallback. `:705-724`: the language choice is saved and applies only after reload |
| `panel_options_label` | PASS | `:47-70`: the label is read through the seam, only code adds `! `, and a resolved `!` label is not shown |
| `faq_readability` | PASS (32 checks) | FAQ colour, spacing and measured height over stated font models; native colour, contrast and glyph fit NOT RUN |
| `tools/tests/test_l10n_catalog.py` | PASS (76 cases) | `CatalogCurrentSource` (lines 3039-3074): each pack reports 27 `draft_unreviewed` keys, Options `missing`, 0 declarations, INCOMPLETE |

These rows show that the offline technical contract holds on these inputs.
They do not establish translation quality, fluent acceptance, full family
coverage, localized native glyph/layout/input behaviour, packaging,
installation or delivery.

## Gates that remain open

- **Window families.** All 15 window families are PENDING. The Main panel
  (HUD) has 23 adopted keys and is incomplete. #143's Orb and Journal
  families, #144's five families and #145's seven have none.
- **Language review.** Competent language review is UNASSIGNED for every
  optional pack. No per-entry acceptance exists or is implied.
- **Native.** Localized native evidence is NOT_RUN.
- **Help/FAQ baseline.** Current Help/FAQ text at `8393f5f` (`ui/Help.lua`
  blob `8c3ddaafdcd1038114737ed2a2df8b75ac66e8f7`) is the evidence
  baseline. Future #145 work coordinates against accepted #131/FAQ wording,
  not old screenshots.
- **English screenshots.** The existing English test.163012 screenshots and
  the separate usability review do not establish localized glyph, layout or
  input acceptance.
- **Design references.** The original Main Panel and Setup design references
  are unchanged. No design work is requested.

## Responsibilities, dependencies and resume triggers

Root is accountable for assigning later authors and competent reviewers.
That accountability is not itself proof of fluency. No human is contacted
by this ledger.

| Item | Owner | State | Depends on | Resumes when |
|---|---|---|---|---|
| This documentation revision | Root integration; independent Codex Spec/Standards review | committed locally; review PENDING | none | Codex verdict |
| #141 language activation | Root assigns | partial: explicit chooser, once-per-session activation and an Automatic preference that resolves to English; acceptance open | authorized versioned client evidence for any alias; #146 reload/persistence rows | an evidenced client code or alias, or Root accepts English-only Automatic |
| #142 dynamic invariants | Root assigns | partial: one count template and two wait reasons; other dynamic text unclassified | behaviour-coupling classification of each dynamic producer | a family batch containing dynamic text |
| #143 main, mini, Orb, Journal | Root assigns one non-overlapping author per family; reviewer separately | PENDING (HUD 23 keys, incomplete; Orb and Journal 0) | measured family inventory; ≤ 36 new English keys fit | Root dispatches one family with an exact key list |
| #144 editors, sharing, records | Root assigns | PENDING (5 families, 0 keys) | measured inventory; identity and matching inputs stay invariant | Root dispatch; independent of #145 |
| #145 onboarding, Help, safety, support | Root assigns | PENDING (7 families, 0 keys) | accepted #131/FAQ wording at or after `8393f5f`; complete consent/refusal English fallback rules | #131/FAQ wording accepted, then a family dispatch |
| #146 localized native matrix | Root coordinates the established native operator | NOT_RUN | reviewed language/view/client/font rows on an exact source and package | localized source ready for native rows |
| #147 validation contract | Root decides whether the U1/U2/U3 lane resumes, and its owner | open: static-catalog validator is an implemented draft; U1/U3a unproven and not integrated; U2 not started; U3b pending | the U1/U3a objects, or a fresh reviewed implementation from the current pin | Root assignment; the historical owner is not presumed active |
| #148 competent language review | Root is accountable for assigning competent reviewers | UNASSIGNED | this frozen cohort and its translator context | a reviewer is established for a language; draft authoring need not wait |
| #149 final composition | Root with independent Spec/Standards/content review | queued, dependent | #141, #142, #143-145 coverage, a coherent #147 validator, full matched checks and package, #146 outcomes | a frozen final union exists |

## Findings for Root's separate decision

None of these is repaired in this lane.

- **F1.** In `tools/tests/test_l10n_catalog.py`, lines 202-212 and 231-234
  say `panel.button.options` exists only in an uncommitted working copy that
  no commit, tree or blob holds. It was committed in `a50372b` (blob
  `024557e8`). The recorded working-copy identity (`755f2f5d…`, 3970 bytes)
  is the CRLF checkout of that blob. The commentary is stale, but the
  assertions pass.
- **F2.** `tools/tests/test_l10n_catalog.py:534` requires the phrase
  `uncommitted working copy` in `KEY_CONTEXT.currentAdoption.scope`. The
  scope gives the committed adoption at `8393f5f` (first committed in
  `a50372b`) as a CURRENT FACT. It keeps the phrase only inside a sentence
  labelled HISTORICAL STATEMENT, SUPERSEDED AND NO LONGER TRUE. No metadata
  describes the adoption as currently uncommitted, so the assertion doesn't
  block truthful documentation, but it pins history rather than the current
  fact. Minimal fixture update for Root's assessment, not applied here:
  replace line 534 with
  `self.assertIn("a50372ba485fd98043d68ec7d4f732ee947b0c28", adoption["scope"])`
  and
  `self.assertIn("8393f5f4b61a0d62b5043b861539be868ebf80f6", adoption["scope"])`.
  The historical sentence can then be dropped. A separate, optional update:
  correct the comments in F1 and, as line 233 itself asks, move the English
  identity from `WORKING_COPY_PHYSICAL_INPUTS` to the canonical LF blob
  (`69d39989…`, 3916 bytes) in `CURRENT_REFERENCE_INPUTS`. Neither update
  weakens a check.
- **F3.** `tools/tests/test_l10n_catalog.py:376`, `:481` and `:668` pin the
  declared contract pin of `RELEASE_LANGUAGES.json`, `KEY_CONTEXT.json` and
  `FULL_COVERAGE.md` to `5c77eec`. Current facts are therefore bound to
  `8393f5f` through additive fields and sections only.
- **F4.** `automaticMode` in `docs/localization/RELEASE_LANGUAGES.json`
  (`chooserProductId: NONE_AT_BASE`) describes only the `5c77eec` base. It
  is silent about the current Automatic preference value, which still
  resolves to English. The field is pinned by
  `tools/tests/test_l10n_catalog.py:431-438`, and the file is outside this
  lane.
- **F5.** `ui/Panel.lua:3352-3365` (`M.HubMenuItems("plan")`) shows
  localized tooltip text from five keys under hard-coded English row labels,
  title and note. With a pack active, these rows mix languages. This is a
  #143 coverage item.

## Not claimed

This ledger does not claim:

- localization completion;
- fluent or competent language approval;
- family coverage;
- native acceptance;
- package, install or public delivery;
- an integrated or accepted #147 U1/U2/U3 contract;
- any new key, translation, language, alias or wording change.
