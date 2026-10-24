# Localization planning (issue #123, L10N-01)

Refs #123. Status: first L10N-01 slice, covering inventory, context and
evidence. Source pin `18dc5b0313033dbc522bec1ab89c304078aa5645`.

Nexus presents English text only. This slice adds no locale support,
translation, locale loading, language preference, font or runtime behavior. The
current English text is the baseline, not evidence of a verified client locale.

## Documents

- [INVENTORY.md](INVENTORY.md): the reproducible string-literal inventory, its
  coverage by file and window family, the copy kinds with source examples, the
  manual exclusions and the scanner's limits.
- [KEYS_AND_GLOSSARY.md](KEYS_AND_GLOSSARY.md): proposed stable key, context,
  placeholder and markup rules and English reference terms. Proposal only.
- [CLIENT_LOCALE_MATRIX.md](CLIENT_LOCALE_MATRIX.md): client, locale and font
  evidence. Every locale, alias, font and glyph value is UNKNOWN.
- [VALIDATION.md](VALIDATION.md): historical pinned check results, the required
  Python test integration and open gates, keeping Lua results, Python fixture
  results and native unknowns distinct.

## Tool

`tools/l10n_inventory.py` (Python 3.9+, standard library only) lists the
string literals of named Lua files as ASCII JSON lines. It reads the files as
bytes and never executes, imports or writes them. A `literal` record carries
`text`. A `bytes` record carries `hex` for a value that is not valid UTF-8. An
invalid request prints nothing on stdout, exits 1 and writes one JSON error
line on stderr. The module docstring is the full contract.

A listed literal is a lead for review. It is not proof that the text is
shown to a player or should be translated.

## Commands

From the repository root:

    python tools/tests/test_l10n_inventory.py -v      # focused: the inventory tool's fixtures
    python tools/ci_check.py                          # required full offline suite (needs luajit)
    python tools/ci_check.py --inventory-only         # registration checks only; starts no test

`tools/tests/test_l10n_inventory.py` is a Python unittest file. It is
registered in `PYTHON_TESTS` in `tools/run_prototype_tests.py`, apart from the
Lua test list; the Lua runner never runs or counts it. A complete
`python tools/ci_check.py` run checks the registration, runs the Lua suite and
then starts the file as its own process with the current Python interpreter,
with a 45-second limit. A nonzero exit, a timeout or a launch failure fails the
check. The result is printed on `python:` lines and recorded under
`python_tests` in the `--output` report, apart from the Lua counts. An `--only`
shard runs no Python test, prints it as NOT SELECTED and stays PARTIAL. The
`offline-suite` and `literal-head` CI jobs call `tools/ci_check.py`; no
workflow file changed. Results for this change are recorded in
[VALIDATION.md](VALIDATION.md#required-python-test-integration) only after
they are run.

The inventory capture command and its path list are in
[INVENTORY.md](INVENTORY.md#method). Its output (about 2.8 MB) is generated
evidence and is not checked in.

## Deferred

L10N-02 to L10N-06 are deferred:
- keys and English base loading;
- locale selection and persistence;
- formatting, plurals and names;
- layout and glyph validation;
- translator gates.

They need a verified client locale, alias and font reference and an accepted
presentation contract first. Native rendering, layout and font checks are not
part of this slice.
