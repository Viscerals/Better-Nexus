# Localization inventory validation status

Refs #123. Checked on 2026-10-21 against documentation cut
`c69940effd3d6b7fca33ad2bec1857325826f059`. This is an evidence matrix for
the first inventory slice, not acceptance of localization rollout or a claim
that L10N-01 is complete.

The results in the table are historical. Each belongs to the pin named in its
row. They are not validation of the final successor of the required Python
test integration described [below](#required-python-test-integration). Its
historical integration base is
`a43cf2718359308b956d66906f44b2609ac1034b`, which was public `main` at that
integration step; this is not a claim about all current `main`. Later
current-main composition needs its own evidence. Runtime identity with the
inventory pin `18dc5b0313033dbc522bec1ab89c304078aa5645` is not claimed.

The current source descriptions below were checked against foundation
predecessor `ca51d914044eaa02e3ac6b6210e512340060fd93`. Static source facts
do not establish test execution. Any related runs or reviews retained outside
this record keep their own source pins and scope; no result is transferred to
the final successor by this document.

| Area | Evidence and scope | Status / remaining gate |
|---|---|---|
| Existing Lua regression suite | Official `tools/ci_check.py` run on `a70381032067c933eb0f35c7f3e88d4b75279de4`: 523 PASS, 0 FAIL, 0 NOT_RUN, no missing result rows. | Historical PASS at that pin; 523 is not a count for current `main`. The only tracked change from `a703810` to `c69940e` is the key proposal document. The full suite was **not rerun** on `c69940e`. |
| Scanner fixtures | Four Python unittest methods, including six invalid-input subcases, passed separately on the scanner and fixture revisions below. Their bytes are unchanged at `c69940e`. | Historical focused PASS; at those pins it was not a required-CI result. No new fixture execution is claimed by this document. |
| Required Python test integration | `tools/ci_check.py` checks the Python test registration and, in a complete run, starts each registered Python test file as its own process. See [below](#required-python-test-integration). | **IMPLEMENTED; FINAL-SUCCESSOR VALIDATION PENDING IN THIS RECORD.** This record supplies no final-successor self-test, focused, complete-suite, required-CI or independent-review result. Related evidence at other pins remains separate. |
| Runtime source inventory | Retained complete capture: 87 Nexus-owned TOC Lua files, 25,355 `literal` records and 4 `bytes` records. All 87 source hashes matched at `c69940e`. Record fields, per-file counts and file-family totals were checked locally. | Lexical coverage established for that file set at that pin, not visibility or translation classification. Not recaptured or rehashed at `a43cf27`. `third_party/ChatThrottleLib.lua` and non-runtime files are excluded as described in [INVENTORY.md](INVENTORY.md). |
| Reproducibility | The retained second complete capture matched the first byte-for-byte: 2,786,976 bytes, SHA-256 `1d4ecbf3ddc05166f50dee1988a730ec08abccca9a68fe359784a7ea0d361399`. Source hashes were unchanged. | Existing deterministic-output evidence; no Lua or native client was executed by the scanner. |
| Key proposal | All ten illustrative keys match the documented three-segment window-family form or two-segment shared-group form. Family and group names are disjoint. | Local consistency check passed. Keys are proposals; no runtime key table or loader exists. |
| Semantic classification | Window/context examples and manual exclusions are documented. Dynamic sentences, user text, game data and TOC metadata are not fully classified. | **OPEN.** Literal counts are not counts of visible or translatable strings. |
| Client locale / aliases / fonts / glyphs | No exact versioned client/export reference is supplied. Offline harness `GetLocale`/`GetBuildInfo` values are stubs. | **UNKNOWN.** English source text is a presentation baseline, not verified client-locale support. See [CLIENT_LOCALE_MATRIX.md](CLIENT_LOCALE_MATRIX.md). |
| Native rendering and rollout | No native localization layout, glyph, translated-language, preference or locale-loading test is recorded. | **NOT_RUN / DEFERRED.** L10N-02 through L10N-06 require their own evidence and acceptance. |

## Frozen tooling revisions

These are the historically recorded scanner and fixture hashes associated
with the focused result above, not hashes of the current tooling:

- `tools/l10n_inventory.py`: SHA-256
  `588064b40e0e223073da4cc32abc5f33572755f0f00e948112b613f563ec04fa`.
- `tools/tests/test_l10n_inventory.py`: SHA-256
  `aa1d45be234a54d96707637d560b83f268f4dd6c26cd48b6f688bf71257f738c`.

At foundation predecessor `ca51d914`, the hashes are instead:

| Tooling path | Raw CRLF checkout SHA-256 | Canonical Git blob SHA-256 |
|---|---|---|
| `tools/l10n_inventory.py` | `1a8d3d8de6638cc003f7618dba03cf2162893f1e7a734a074002221bc2938194` | `0f973d73631e7241e310f58c737fb85d6c1b0c3eec8630aaf18c25e8c116d5ce` |
| `tools/tests/test_l10n_inventory.py` | `d2c193b101e9e4de0d9f314df7b821ea7fdcdf1c4b30f269d800c8a9310566dd` | `91aab5ab80a290c4d70ff80144b58f8812a597e48c8886e51bb65054e6a3e185` |

The raw checkout and canonical Git blob hashes describe different byte
representations and must not be compared as if they were the same. The current
fixture statically defines eight unittest methods covering short strings,
Lua 5.1 lexical cases, byte records, UTF-8 columns, argument/source order and
read-only success, ASCII deterministic output, invalid requests and OS errors.
This method count and the hashes are source facts, not a new focused pass.

The scanner emits ASCII JSON lines. Text records carry `text`; non-UTF-8
value records carry exact lowercase hexadecimal `hex` instead. A byte record
is not display text. The retained capture conforms to this contract; that does
not prove every possible scanner input or complete Lua syntax is supported.
The current scanner distinguishes invalid requests (exit 1, empty stdout and
one ASCII JSON error on stderr) from argparse usage errors such as no PATH,
unknown options or a missing option value (exit 2 and argparse's usage text).
Help exits 0. OS errors while resolving `--root` or resolving, checking or
reading a PATH map to `unreadable`; a root-resolution error names the first
PATH. The inventory remains lexical, not a classification of visible text.

## Located byte patterns

All four retained byte records are now located and matched to unchanged source:

| Source location | Exact value bytes (hex) | Source use |
|---|---|---|
| `ui/LayoutMetrics.lua:215`, `:365` | `5b802dbf5d` | `"[\128-\191]"` continuation-byte pattern used in width estimates. |
| `ui/OrbPanel.lua:106`, `:1039` | `5bc02dff5d5b802dbf5d2a24` | `"[\192-\255][\128-\191]*$"` UTF-8 tail pattern used when shortening text. |

These patterns are invariants, not translation targets. Locating them does not
validate native glyph widths or the layout model.

## Required Python test integration

Python unittest files are registered in `PYTHON_TESTS` in
`tools/run_prototype_tests.py`, apart from the Lua `NAMES` list. The only entry
is `tools/tests/test_l10n_inventory.py`. The Lua runner never passes it to a
Lua runtime and never counts it; its report lists it as run by
`tools/ci_check.py`.

`tools/ci_check.py`, which the CI workflow's `offline-suite` and `literal-head` jobs call:

- accepts only canonical relative POSIX `tools/tests/.../test_*.py` entries:
  no backslash or empty, `.` or `..` segment. It fails its inventory check
  for a duplicate entry, a malformed entry, a registered file that is missing, or a
  `test_*.py` file under `tools/tests` that is not registered;
- in a complete run, after the Lua suite has written its report, starts each
  registered file as its own process with the current Python interpreter
  (`-B`, no shell, repository root as working directory, 45-second limit). A
  nonzero exit (FAIL), a timeout (TIMEOUT) or a process that cannot start
  (LAUNCH_FAILED) fails the check;
- prints the results on `python:` lines and records them under
  `python_tests` in the `--output` report. They are not added to the Lua
  passed and failed counts;
- with `--inventory-only`, checks both inventories and starts no test;
- with `--only`, runs only the selected Lua tests. Each registered Python test
  is printed as NOT SELECTED (not run, not a pass), and the run is labelled
  PARTIAL.

`tools/runner_selftest.py` checks these paths with stand-in processes:
invocation, success, nonzero exit, timeout, launch failure, missing, duplicate,
malformed and unregistered entries, `--inventory-only` and a shard. It starts
no Lua runtime and no Python test file. Relative to historical integration
base `a43cf27`, the scanner and fixture are added, and `tools/ci_check.py`,
`tools/run_prototype_tests.py` and `tools/runner_selftest.py` are modified.
The CI workflow and runtime files are unchanged by that tooling integration.
This remaining documentation correction changes neither tooling nor runtime
nor workflow.

Status: **FINAL-SUCCESSOR EVIDENCE PENDING IN THIS RECORD.** Related self-test
RED/GREEN, focused fixture, `--inventory-only`, shard, complete-suite, required
CI or review evidence may exist separately at its own pin. This record does
not claim those results for the final successor. Final validation and review
must identify the actual source checked; a shard remains PARTIAL and does not
supply a complete-suite result.

## Checks

`python tools/tests/test_l10n_inventory.py -v` runs the scanner fixtures on
their own. A complete `python tools/ci_check.py` runs the registered Lua suite
and then the registered Python tests, and reports the two separately. The
historical Lua and scanner results above stay separate evidence for their own
pins. Native client locale, alias, font and glyph evidence remains UNKNOWN, and
runtime localization (L10N-02 to L10N-06) remains deferred. No runtime code,
locale, font, workflow, native action, merge or release is part of this change.
