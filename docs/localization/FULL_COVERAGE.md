# Full localization coverage plan (#139-#149)

Refs #139, #147. Source pin `5c77eec5b791f64468576e37a70b3855375b7fcb`
(tree `692c6693ba50ba5ffc2bf8f3f724b0bceeeda65c`). Status: declarative plan.
It accepts no issue: not #139, not #147 and no later gate.

## State at the pin

- The #139 recorded public language decision resolves the selected product
  choices: `enUS` English baseline; `frFR`, `deDE`, `esES`, `plPL`, `ptBR`
  and `ruRU` optional Nexus UI packs
  ([RELEASE_LANGUAGES.json](RELEASE_LANGUAGES.json)). Product IDs are not
  client locale codes, and no client alias is evidenced.
- English UI keys, catalog and locale entries, and window-family adoption are
  incomplete. Fluent reviewers are UNASSIGNED and native evidence is NOT_RUN
  for every language.
- The six current English keys ([KEY_CONTEXT.json](KEY_CONTEXT.json)) and the
  three inherited draft translations per pack at the pin are not complete
  localization. A separate owner is adding the three missing existing keys to
  each of the six packs (18 draft entries, no new English key). Those entries
  remain draft until human review. Per-pack counts are derived from catalog
  inputs and are not fixed here.
- Fallback English is not translation. No global 100% coverage, release-ready
  status or whole-#139/#147 acceptance is claimed.

## This contract and the validator

| Part | This four-file contract | Separate next task |
|---|---|---|
| Release languages | `RELEASE_LANGUAGES.json`: product choices, client evidence, review and session states | read-only `tools/l10n_catalog.py` checks catalog inputs against it |
| Keys and context | `KEY_CONTEXT.json`: six keys, byte limits, grammar, families | derived per-pack translated, missing, invalid and obsolete report |
| Tests | `tools/tests/test_l10n_catalog.py`: assertions on these public documents | appended CLI positive and malformed-input fixtures that keep these assertions |
| Required CI | not registered | later authorized append to `PYTHON_TESTS` in `tools/run_prototype_tests.py` |

Until that registration, `tools/ci_check.py` reports an unregistered
`test_*.py` under `tools/tests` as an inventory failure (`CONTRIBUTING.md`,
`VALIDATION.md`). Execution of the new test: NOT_RUN.

## Separate gates

Each gate needs its own evidence and acceptance; passing one accepts no other.

1. #139 selection: resolved. Fluent responsibility per language is
   UNASSIGNED and terminology is pending.
2. #141 Automatic/default: OUTSTANDING. The base code defaults to `enUS` and
   has no Automatic chooser ID. Unknown or unsupported input resolves to
   English. This contract makes no code change.
3. #143, #144, #145 full UI: every window family below, in author batches.
4. #146 native: client locale, alias, font, glyph and layout evidence;
   NOT_RUN.
5. #147 validation: the validator, fixtures and required-CI registration
   above.
6. #148 pack gate and #149 union gate: separate later acceptance.

## Author batches

One window family per batch, at most 60 newly adopted keys. A family whose
measured inventory exceeds 60 is split before dispatch. A family is complete
only when all its batches are accepted; current adopted keys do not make a
family complete.

| Window family | Issue | Status |
|---|---|---|
| Main panel (HUD) | #143 | PENDING (`readout.charge_counts` adopted; family incomplete) |
| Orb window | #143 | PENDING |
| Echo Journal tab | #143 | PENDING |
| Wishlist editor | #144 | PENDING |
| On-screen Wishlist | #144 | PENDING |
| Build Library | #144 | PENDING |
| Leaderboard | #144 | PENDING |
| Unit tooltip | #144 | PENDING |
| First-launch setup | #145 | PENDING |
| Help | #145 | PENDING |
| Auto overwrite consent | #145 | PENDING |
| Loading status | #145 | PENDING |
| Support report | #145 | PENDING |
| Log viewer | #145 | PENDING |
| Release note | #145 | PENDING |

Other visible core and support copy (`core/UserText.lua`, `core/Main.lua`,
`core/SupportReport.lua` wrappers, TOC Title and Notes,
`ui/FlexiblePlanChooser.lua`) stays pending classification. No complete
denominator is claimed. The 25,355 lexical literals and the 21-key #143
preparation are leads at their own pins.

## Consumer migration and history

Consumer migration waits for the current final M7 composition. This contract
migrates nothing and changes no runtime, locale or English bytes. `README.md`,
`INVENTORY.md`, `KEYS_AND_GLOSSARY.md`, `CLIENT_LOCALE_MATRIX.md` and
`VALIDATION.md` are pinned historical evidence and stay unchanged.
