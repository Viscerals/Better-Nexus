# #147 validator contract and implementation plan

Refs #147, #123, #140, #141, #142, #143, #144, #145, #146, #148, #149.

Status: **PLAN ONLY, ROOT REVIEW PENDING.** This is documentation. It
proposes future work and authorizes none of it: no source, test, tool, data,
metadata or family-inventory edit, and no dispatch, merge, push, package,
install, tracker, contact, native or model action. It adds no key and proposes
no cap expansion. The machine-readable form is
[VALIDATOR_147_PLAN.json](VALIDATOR_147_PLAN.json).

## Binding

| Item | Value |
|---|---|
| Author | provider instance `claudeAgent_claude2` (Claude Second), model `claude-opus-5-5`, reported by `orchestrator_capabilities` |
| Branch / worktree | `docs/nexus-147-contract-plan-second-20261029`, its own isolated worktree |
| Initial head / tree | `75178765a90c772c0521829708d365cc7dc3eb35` / `84b230e035a6d2853f48dc26666bf6c7510856e0`, verified, clean |
| Runtime evidence pin | `8393f5f4b61a0d62b5043b861539be868ebf80f6` / `8c1397ba8856d6d6973d5dd28e7fa0aecebb4ada` |
| Union delta from 8393f5f | six documentation files only. The runtime, data, tool, test, runner and TOC blobs are identical (listed in the JSON) |
| Original scope | `task-4/TRACKER_147_CURRENT_SCOPE_READ_20261029.json`, SHA-256 `bf194273…091e1` verified (root-held local input) |
| Public issue | #147 read with read-only `gh issue view` on 2026-10-29. Its body is the scope read plus a trailing newline. One comment |
| Instructions read | `AGENTS.md`, `CONTRIBUTING.md`, `AI_POLICY.md`, `docs/agents/domain.md`, `docs/agents/reporting.md`, installed `implement`, `tdd` and `code-review` skills. `CONTEXT.md` and `docs/adr/` are absent |

The union establishes no new runtime, native, review or language acceptance.

**Focused baseline.** `python -B tools/tests/test_l10n_catalog.py` at
`7517876` (Python 3.14.7) ran 76 tests, OK, and left the tree clean. This is a
focused read-only check, not the full suite and not CI evidence. The full
599-test suite, `ci_check` and `build_package --check` were not run.

## Historical claims versus current source

| Part | Reported pin | Reported result | Object in this store | State |
|---|---|---|---|---|
| U1 corrected registry | `38662fa` | 541 assertions | no | historical, unproven, not integrated |
| U1 earlier draft | `4bce313` | 499; full 557/558 | no | superseded, unproven |
| U2 complete-English admission | none | packet prepared | n/a | prepared only |
| U3a syntax parser | `5f5b462` | catalog 95/96 | no | historical, unproven, not integrated |
| U3b semantic binding | none | n/a | n/a | PENDING |

Current source: `core/Localization.lua` has no registry or declaration
symbol, and `SCHEMAS` (line 232) is its only code-owned schema.
`tools/l10n_catalog.py` is the scoped static-catalog draft
(`parse_english`/`parse_packs`, `validate_catalog_data`, `catalog_report`,
confined-root `main`). It is not the broad registry-bound validator. Its
test file has 76 methods. The old transfer and provider holds and the owner
label `/root/restart_metadata_cli` are history. They are not current
approval or worker evidence. No historical worker is revived and no absent
output is copied.

## Fixed facts (unchanged by this plan)

- 28 English keys: 27 static and one template, `readout.charge_counts`
  (`banish`, `reroll`, `freeze`, slot type `count`, result limit 254).
- 27 `draft_unreviewed` entries in each of `frFR`, `deDE`, `esES`, `plPL`,
  `ptBR` and `ruRU` (162 in total). `panel.button.options` is in no pack and
  resolves to the exact English `Options` (`base`, `missing_candidate`,
  counted).
- Caps: key 64, text 256, base and pack entries 64, autonym 64, languages 16,
  diagnostic keys 8. At most 36 more English entries fit. This plan adds none
  and proposes no expansion.
- Automatic is English-only. There is no evidenced client alias.

## Requirement map

Every clause of the original #147 maps to one ID. The JSON holds anchors,
gaps and slices for each.

| ID | Original clause | Current status | Slice |
|---|---|---|---|
| W1 | distinguish reviewed translations from placeholders | implemented draft | S6 |
| W2 | per-pack/per-surface coverage report | implemented draft; surfaces declared, not verified | S8 |
| W3 | an unreviewed pack is not "complete" because files exist | implemented draft (`--require-complete` exits 1) | R, S6 |
| R1.1 | English key schema | implemented, duplicated in Lua and Python | R |
| R1.2 | context schema | partial; document-only | S5 |
| R1.3 | placeholder schema | implemented, three hand copies | R |
| R1.4 | markup schema | implemented; plain content implicit | S3, S4 |
| R1.5 | pack language identity | implemented; tool hardcodes products | S1, S5 |
| R1.6 | optional-UI versus client mapping | implemented (`productIdIsClientLocale` false) | — |
| R1.7 | source/base revision | **gap** | S7 |
| R1.8 | translator provenance/rights | **gap** | S7 |
| R1.9 | human reviewer status | implemented draft; no reviewer assigned | — |
| R2.1 | key parity | partial | S1, S5 |
| R2.2 | TOC parity | implemented in CLI | — |
| R2.3 | load parity | **gap** | S1 |
| R2.4 | missing | implemented | S4 |
| R2.5 | duplicate | implemented offline; invisible at runtime | S1 |
| R2.6 | obsolete | partial; always empty | S6 |
| R2.7 | orphan | partial; meaning UNKNOWN (pack orphan and/or unbound English) | S6, S8 |
| R2.8 | valid UTF-8 | implemented; Lua 5.1/LuaJIT escape ambiguity unverified | S1 |
| R2.9 | required plural variants | **blocked on #142** | S9 |
| R2.10 | placeholder names | implemented (one template) | R |
| R2.11 | placeholder types | implemented (`count` only) | S9 |
| R2.12 | markup integrity | implemented | — |
| R2.13 | newline integrity | implemented; CRLF/LF control missing | S1 |
| R2.14 | deterministic fallback | runtime only | S1, S6 |
| R2.15 | an invalid fixture fails through required CI | scoped draft | S1, R |
| R2.16 | a valid fixture passes through the same gate | scoped draft | S1, R |
| R3.1 | six categories reported separately | partial; invalid and obsolete always empty | S6 |
| R3.2 | identical name reviewable as identical | implemented | — |
| R3.3 | copied English unreviewed stays placeholder | implemented | — |
| R4.1 | static keys per adopted family | partial; five `reason.*` keys unfamilied | S8 |
| R4.2 | dynamic keys per adopted family | **blocked on #142** | S9 |
| R4.3 | pseudo/test data excluded | implemented | S1 |
| R4.4 | CI registration per final runner contract | implemented | S1, R |
| R4.5 | do not overwrite PR138's frozen runner | current state UNKNOWN | S1 |
| R5.1-R5.3 | rights, attribution, independent authorship | **gap** | S7 |
| R5.4-R5.5 | no foreign corpus, no private content | policy only; attestation field proposed | S7 |
| R5.6 | approved terminology/context | **blocked on Root and #148** | S10 |
| R6.1-R6.4 | pack/family receipt, review and native status | implemented draft (four-input) | R, S8 |
| R6.5 | no "100%"; fallback never counts | implemented draft | R, S6 |
| B1-B4 | #140 exists; #142 dependency; static first; PR138 coordination | satisfied / open / used / open | S9, S1 |
| V1-V6, E1-E2 | compatibility, unchanged semantics, checks, review, separate native and fluent gates, authority, separate tracking | constraints on every slice | all |
| G1 | U1 cannot integrate or ship alone | adopted as a mechanical interlock | S1, R |
| G2 | do not relabel the four-input catalog as registry validation | constraint | S5 |

## The contract

**One contract. Each fact has exactly one owner.** Every other copy is
checked against that owner and is never a second authority.

| Fact | Owner | Checked by |
|---|---|---|
| key existence, kind, placeholder names and order, slot type, result limit, content class | literal declaration table in `core/Localization.lua` (proposed, U1) | runtime admission; nonexecuting parser (U3) |
| exact English text | `data/LocalizationEnglish.lua` | runtime; `parse_english` |
| meaning, consumer, family surface, translator notes | `KEY_CONTEXT.json` `keys[]` | U3b: kind, placeholders and limit rows must equal the declaration |
| family membership | `KEY_CONTEXT.json` `windowFamilies[]` | `_check_families` |
| pack text and autonym | `data/LocalizationPacks.lua` | runtime; `parse_packs` |
| product identity, client mapping, review gates, base revision and provenance | `RELEASE_LANGUAGES.json` `products[]` (revision and provenance proposed in S7) | `_check_release`; S7 |
| language enum | `data/DefaultProfile.lua` `uiLanguages.ids` | runtime; offline cross-check proposed (S5) |
| entry review decisions | `RELEASE_LANGUAGES.json` `entryReview` | `_check_declarations` |

**Declaration shape (proposal).** `["key"] = { kind = "text" }`, or
`["readout.charge_counts"] = { kind = "format", fields = { "banish",
"reroll", "freeze" }, slot = "count", resultLimit = 254 }`. The table sits in
one delimited block. It holds only literal strings, non-negative decimal
integers and nested plain tables, so a nonexecuting parser reads exactly the
bytes the runtime reads. The runtime checks that the charge limit equals
`MAX_TEXT_BYTES - 2` and fails closed otherwise. `plain` is the only content
class: the existing text contract. Markup, such as the Options `! `, stays
code-owned. There are at most 64 declarations, and the declared set equals
the current 28 keys.

**Admission.**

- **U1.** The English base and the packs are admitted against the
  declarations. `SCHEMAS` is derived from them.
- **U2, complete English.** Every declared key needs one valid English
  entry. An undeclared English entry is rejected and counted (proposed
  `base.undeclared`). A declared key without valid English is counted
  (proposed `base.missingDeclared`) and resolves as today: `unavailable`,
  `unknown_key`. The whole-base 64-entry fail-closed rule is unchanged.
- **Packs.** Availability is unchanged: a plain pack with a valid autonym of
  at most 64 bytes and a plain entries table of at most 64 entries is adopted
  and offered. Completion never gates availability, and availability never
  implies completion.
- **Diagnostics.** `Diagnostics()` gains only additive fields. Existing
  fields keep their meaning.

**Invariants.**

- Lua 5.1, interface 30300 and the name `Nexus` are preserved.
- `NexusDB` and `WishlistRealizerDB` are untouched, and so are the
  `uiLanguage` and Automatic values.
- A key is never built from English, player or game text. Raw producer codes
  remain the lookup.
- `Identity.ValidDisplayText` stays a separate policy. Names are kept exactly,
  with no normalization.
- No localized text decides a consent, action, matching or network/resource
  outcome.
- English fallback stays deterministic, with the existing reason codes and
  counts, and a result is never cut.
- The active language is set once per session. Automatic resolves to English.
- The offline tool never executes Lua, including to inspect declarations. The
  Lua harness may run Lua as synthetic test evidence, which is not native
  evidence.

## Runtime/offline parity mapping

The offline check is a strict whole-catalog gate. The runtime degrades one
entry or one pack at a time. Each offline verdict must map to exactly one
runtime outcome. The full table is `parityMapping` in the JSON. The rows that
matter most:

- **P4.** An invalid pack entry is rejected offline. At runtime it is dropped
  at load and later answers `missing_candidate`, not `invalid_candidate`.
  Only the row's `rejected` count remembers it (finding F6).
- **P8.** A duplicate key is rejected offline. At runtime it is invisible,
  because the Lua constructor keeps the last value.
- **P9 and P10.** A pack outside the enum is `pack-unknown` offline and
  never read at runtime, so it is not counted as refused. An enum ID without
  a pack is `pack-missing` offline and refused at runtime.
- **P12-P16.** CRLF and LF bytes, decimal escapes against literal UTF-8,
  overlong and surrogate escapes, newline, CR and `|`, and ASCII-whitespace
  against U+00A0-only text must give equal verdicts on both sides.
- **P19 (UNKNOWN).** `\x`, `\z` and `\u{…}` escapes can mean different things
  in WoW's Lua 5.1 and in the LuaJIT harness. This must be verified before
  S1 fixes an expectation. The proposed new code is `ambiguous-escape`.
- **P20 (UNKNOWN).** How the native loader treats a UTF-8 BOM is unknown.
- **R-P1 to R-P3 (registry).** An undeclared English entry, a declaration
  that disagrees with `KEY_CONTEXT`, and a declared key without English are
  **expected red** against current source.

## Findings F1-F7

| ID | Classification | Meaning | Proposed handling |
|---|---|---|---|
| F1 `test_l10n_catalog.py:202-212, 231-238` | stale commentary, valid assertion | `panel.button.options` was committed in `a50372b`. `755f2f5d…`/3970 is the CRLF checkout (`eol=crlf`) of blob `024557e8`. English is compared by physical bytes, while packs use the canonical LF blob. | Optional rebinding (S0): fix the comments and move English to `CURRENT_REFERENCE_INPUTS` as `69d39989…`/3916. Keep the superseded-blob inequality and the physical-byte equality in the report test. |
| F2 `:534` | historical-phrase assertion | It passes only on a sentence labelled SUPERSEDED. | Test-truth repair (S0): assert `a50372ba485fd98043d68ec7d4f732ee947b0c28` and `8393f5f4b61a0d62b5043b861539be868ebf80f6`, then drop the sentence. |
| F3 `:376, :481, :668` | intentional historical contract pin | It stops the declarative pin `5c77eec` from moving silently. | No change. Optionally add an assertion on `currentSourceBinding`. |
| F4 `:431-438` | historical metadata with a current gap | `automaticMode` describes the base. The current Automatic preference resolves to English (Lua-tested at `terminology.lua:581, 888-889`) but is absent from the release metadata. | Additive `currentAutomaticPreference` with an additive test (S0). Lines 431-438 stay unchanged and no alias is invented. |
| F5 `ui/Panel.lua:3352-3365` | outside #147 | The Plan hub mixes languages. | A #143 item. |
| F6 `core/Localization.lua:446-462` | current diagnostic gap | Runtime cannot name invalid pack entries. | Optional additive diagnostics (S6). |
| F7 `l10n_catalog.py:449` against `DefaultProfile.lua:92` | current parity gap | The tool hardcodes products. | Cross-check (S5). |

No fix may remove a check, a substring or an equality to obtain green.

## Controls

Controls C1-C14 in the JSON have valid and invalid inputs and expected
results. They cover:

- duplicate, missing, orphan and obsolete keys;
- UTF-8, control bytes, markup and newlines;
- placeholder names, types and required variants;
- identity, text and provenance classification;
- the 64/65 boundaries and refused-pack diagnostics;
- source-byte representations;
- runtime/offline disagreement, through a temporary mutant tool and a
  deliberately wrong row;
- the registry interlock and registry admission.

**None was run as red for this plan.** The expected baseline is:

- C1-C11 should agree with current behaviour, except for the UNKNOWN rows
  P19 and P20.
- The C3 obsolete category is expected red until S6.
- C13 passes today because there is no declaration block.
- C14 is expected red until the R union.

## Slices

**S0 (prerequisite, not validator completion).** Repair F1, F2 and F4
(F3 optional).

- Writes: `tools/tests/test_l10n_catalog.py`, the superseded sentence in
  `KEY_CONTEXT.json`, and an additive field in `RELEASE_LANGUAGES.json`.
- Accepted when all 76 tests pass and none is removed or weakened; a scope
  without either SHA fails; the superseded English blob still fails; and an
  alias-naming Automatic record fails.
- First, check whether a test pins the member set of `RELEASE_LANGUAGES.json`.

**S1 (first executable vertical slice).** A shared parity corpus and a
registry-interlock sentinel, run against the **unchanged** runtime.

- Seam: the same case bytes give the mapped runtime outcome in the Lua
  harness and the mapped offline verdict in nonexecuting Python.
- Writes:
  - `tests/prototype/fixtures/l10n_parity/<case>/{english,packs}.lua` in the
    existing real grammars;
  - `tests/prototype/fixtures/l10n_parity/cases.lua`, using a restricted
    literal-table grammar;
  - `tests/prototype/localization_parity.lua`;
  - `tools/tests/test_l10n_parity.py`;
  - a private literal-table parser in `tools/l10n_catalog.py`, reused later
    by U3;
  - append-only registration in `tools/run_prototype_tests.py`, in both
    `NAMES` and `PYTHON_TESTS`.
- Accepted when:
  1. P1-P18 pass on both sides;
  2. P19 and P20 are resolved by evidence or kept UNKNOWN;
  3. LF variants are derived in memory and agree;
  4. a temporary mutant that accepts `|` fails, and its red receipt is kept;
  5. the sentinel fails when a declaration marker appears without a
     registry-bound parser and complete-English cases;
  6. fixtures stay under `tests/` and `shippedProductIds` stays `[]`;
  7. focused runs, then a full `python tools/ci_check.py` at the final pin,
     pass with accepted registration.
- No runtime or package change. PR138's runner state is read first.

**R: the registry union (U1 + U2 + U3).** The four parts below are one
reviewable, shippable candidate:

- **S2 (U3a).** A fresh nonexecuting declaration-block parser.
- **S3 (U1).** Runtime declarations for the 28 keys, with `SCHEMAS` derived
  from them.
- **S4 (U2).** Complete-English and plain-content admission, with additive
  diagnostics.
- **S5 (U3b).** A registry-bound five-input API and report `schemaVersion` 2.
  `_FORMAT_FIELDS` and `_FORMAT_LIMITS` are replaced by parsed declarations,
  `KEY_CONTEXT` rows are checked against declarations, the enum is
  cross-checked, and the CLI reads `core/Localization.lua`.

No part merges, packages or ships alone, and the S1 sentinel enforces this.
The union is accepted when:

- C14 is red before the change and green after it;
- the declared set, the English set and the `KEY_CONTEXT` rows are all the
  same 28 keys;
- the existing fixtures and the 76 tests pass unchanged, or any change is
  justified per test without weakening;
- the four-input API keeps its scoped label;
- `Diagnostics()` changes are additive only;
- pack availability is unchanged;
- a full `ci_check` passes at the composed pin, plus
  `build_package --check` if the package changes.

**Later slices, in order:**

- **S6.** Separate invalid and obsolete reporting: a retired-keys list, a
  collect-all diagnostic mode while the strict gate still fails, and
  optional runtime diagnostics. Root decides whether categories may be
  emitted for an invalid catalog.
- **S7.** Per-pack base revision, provenance, attribution, rights and a
  no-import attestation. A value stays UNKNOWN until supplied; none is
  invented.
- **S8.** Consumer and family binding by a lexical scan with
  `tools/l10n_inventory.py`. Mapped `reason.*` keys are recorded as mapped.
  `FAMILY_144_INVENTORY.*` is read-only.
- **S9.** Plurals and dynamic text. **Blocked on #142.**
- **S10.** Approved terminology and context for consequential prompts.
  **Blocked on Root and #148.**

## Ownership, migration and rejected alternatives

**Write reservations.** Writes to each path are serialized:

- `tools/tests/test_l10n_catalog.py`: S0, S6, and R only where justified.
- `core/Localization.lua`: the R owner only, plus an optional S6 change.
- `tools/l10n_catalog.py`: S1, R, S6, S7 and S8.
- `tools/run_prototype_tests.py`: append-only for S1 and R. It is shared with
  every lane, so check PR138 and concurrent registrations first.
- `KEY_CONTEXT.json`: S0, R and S6.
- `RELEASE_LANGUAGES.json`: S0, R and S7.

The English and pack data files are edited by no slice. A family lane that
adds keys after R must add their declarations in the same change.
`FAMILY_144_INVENTORY.*` belongs to the #144 lane and nothing here writes it.

**Migration.**

1. S0 repairs test truth and changes no behaviour.
2. S1 characterizes current behaviour and changes no runtime or package.
3. R declares the existing 28 keys with a derived schema equal to the current
   one. The four-input API is retained with its label, and the CLI moves to
   report v2.
4. S6-S8 add reporting and metadata.

No saved data changes, so reverting any slice restores the prior behaviour.

**Rejected alternatives:**

- Executing Lua from the tool. This is forbidden.
- `KEY_CONTEXT.json` as the type authority, with generated Lua.
- A new `data/LocalizationDeclarations.lua`. It would move code-owned schema
  into data and change the TOC and package. Root may still prefer it, with
  those gates.
- Porting the absent U1 and U3a objects.
- Gating availability on completion.
- Inventing plural grammar.
- Raising `MAX_BASE_ENTRIES`.
- Editing the F1-F4 assertions to obtain green.

## Gates, owners and resume triggers

**Every slice** needs:

- focused controls with their red and green receipts kept;
- a full `python tools/ci_check.py` at the final pin, with matched
  registration;
- `python tools/build_package.py --check` when packaging or the TOC changes;
- independent Spec review against these requirement IDs;
- independent Standards review against `CONTRIBUTING.md`, `AI_POLICY.md` and
  `AGENTS.md`.

Competent language review (#148), localized native evidence (#146), final
composition (#149) and merge/release authority stay separate.

| Item | Owner | Resumes when |
|---|---|---|
| this plan | Root review | Root verdict |
| S0 | Root assigns | plan accepted |
| S1 | Root assigns | S0 accepted or waived; PR138 state read |
| R | one owner for the whole union | S1 accepted |
| S6-S8 | Root assigns | R accepted |
| S9 | Root assigns | #142 accepted schema |
| S10 | Root assigns | Root terminology approval and a #148 reviewer |

## Unknowns

- PR138's current state.
- How the CI harness's LuaJIT decodes `\x`, `\z` and `\u`.
- How native WoW handles a BOM in an addon Lua file.
- Whether "orphan keys" also means English keys without a consumer.
- Translator identity and rights for the current draft packs.
- Whether a test pins the member set of `RELEASE_LANGUAGES.json`.

## Not claimed

This plan claims none of the following:

- implementation of any slice;
- execution of any proposed red or green control;
- U1, U2 or U3 integration or acceptance;
- family coverage, language review or native acceptance;
- package, install or delivery;
- any new key, translation, alias or cap change;
- the 15 new usability choices.
