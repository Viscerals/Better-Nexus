"""Offline side of the shared runtime/offline localization parity corpus and
the registry interlock sentinel (Refs #147, slice S1 and the R union).

The corpus is tests/prototype/fixtures/l10n_parity: cases.lua and one
directory per committed case holding english.lua and packs.lua in the real
data grammars. tests/prototype/localization_parity.lua loads the same bytes
into core/Localization.lua under LuaJIT (with a declaration block derived
from each case's test-only English keys) and checks each case's runtime
expectation. This file parses the same bytes and never evaluates,
imports or executes Lua: cases.lua is read with the private restricted
literal-table parser _parse_literal_table of tools/l10n_catalog.py, and each
case's offline verdict is the first CatalogSyntaxError or
CatalogValidationError of parse_english, parse_packs and the tool's scoped
English and pack checks (_check_english, _check_packs) against products made
from the case's language enum, or "valid". The two sides keep their own
category names; the declared mapping is the parity claim. LF and CRLF
variants are derived in memory. Runtime cap: the tool applies the runtime
MAX_BASE_ENTRIES (runtimeCap.current). The pilot cases keep their dated
pilot-cap verdicts, reproduced by the offline counterpart of the Lua
legacy-cap loader (the real tool with only its one entry-cap line set to
runtimeCap.pilot, compiled in memory), and each derived current cap / cap + 1
control has its own current-cap offline verdict. Each English registry edit is
also padded with generated entries to runtimeCap.current + 1 and must be
refused offline (english-too-many), the counterpart of the Lua harness's
real-data above-cap guard. P19 and P20 native WoW behaviour stays
UNKNOWN; only offline decoding and metadata are checked here.

Registry interlock (G1). The declaration marker convention is exact and
bounded: the ASCII token NEXUS-L10N-REGISTRY in core/Localization.lua may
appear only as the two whole lines "-- NEXUS-L10N-REGISTRY BEGIN" and
"-- NEXUS-L10N-REGISTRY END", once each, BEGIN first, around the future
declaration block. Any other occurrence of the token is malformed. The
sentinel passes only when the marker, the registry-bound parser
(parse_registry_declarations in tools/l10n_catalog.py) and bound registry
rows (R-P1..R-P3 of cases.lua) are all absent or all present: a U1-only
marker, a U3-only parser or U2-only complete-English rows fail. With the R
union all three are present, and presence alone is not enough: the binding
check parses the real declaration block, requires the declared, English and
KEY_CONTEXT key sets to be equal, requires the five real inputs to pass the
registry-bound validate_registry_catalog_data, and reproduces each bound
row's expected offline verdict from its in-memory edit of a real input.

Synthetic offline evidence, not native evidence. Python 3.9+, standard
library only. Registered in PYTHON_TESTS of tools/run_prototype_tests.py.

Run directly:  python tools/tests/test_l10n_parity.py -v
"""

import copy
import importlib.util
import json
import re
import sys
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG_TOOL = ROOT / "tools" / "l10n_catalog.py"
CORPUS = ROOT / "tests" / "prototype" / "fixtures" / "l10n_parity"
CASES = CORPUS / "cases.lua"
LOCALIZATION = ROOT / "core" / "Localization.lua"
LUA_TEST = ROOT / "tests" / "prototype" / "localization_parity.lua"

MAPPED_ROWS = ["P%d" % index for index in range(1, 19)]
UNKNOWN_ROWS = ["P19", "P20"]
MARKER_TOKEN = b"NEXUS-L10N-REGISTRY"
MARKER_OPEN = b"-- NEXUS-L10N-REGISTRY BEGIN"
MARKER_CLOSE = b"-- NEXUS-L10N-REGISTRY END"
REGISTRY_PARSER = "parse_registry_declarations"
REGISTRY_ROWS = ["R-P1", "R-P2", "R-P3"]
PENDING, BOUND = "pending_r_union", "bound"
ENGLISH_ID = "enUS"
PSEUDO_PACK = re.compile(r"^q[a-z][A-Z]{2}$")


def load_catalog(path=CATALOG_TOOL):
    """Load tools/l10n_catalog.py from its file path without writing bytecode."""
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location("l10n_catalog_parity_under_test", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def variants(data):
    """The LF and CRLF variants of source bytes. A lone CR is refused (C11),
    and the bytes must already be one of the two variants."""
    if b"\r" in data.replace(b"\r\n", b""):
        raise ValueError("lone CR")
    lf = data.replace(b"\r\n", b"\n")
    crlf = lf.replace(b"\n", b"\r\n")
    if data not in (lf, crlf):
        raise ValueError("mixed line breaks")
    return {"lf": lf, "crlf": crlf}


def offline_verdict(catalog, english_source, packs_source, enum):
    """The first strict offline failure for a case, as {code, key} for a
    validation error, {code, line, column} for a syntax error, or
    {code: 'valid'}. Products are the English base plus the case enum, with
    each autonym taken from its pack, so only the pack ID set, autonyms and
    entries are judged (release metadata is not part of the runtime seam)."""
    try:
        english = catalog.parse_english(english_source)
        packs = catalog.parse_packs(packs_source)
        catalog._check_english(english)
        products = {ENGLISH_ID: ("case.enum", {"autonym": "English"})}
        for pack_id in enum:
            pack = packs.get(pack_id)
            products[pack_id] = ("case.enum[%r]" % pack_id,
                                 {"autonym": pack["name"] if pack else None})
        catalog._check_packs(packs, english, products)
    except catalog.CatalogSyntaxError as error:
        return {"code": error.code, "line": error.line, "column": error.column}
    except catalog.CatalogValidationError as error:
        verdict = {"code": error.code}
        if error.key is not None:
            verdict["key"] = error.key
        return verdict
    return {"code": "valid"}


def case_sources(case, cases_by_id):
    """(english bytes, packs bytes) of a case as read from the checkout,
    with a derived case's prefix applied in memory."""
    source = case["derive"]["from"] if "derive" in case else case["id"]
    english = (CORPUS / source / "english.lua").read_bytes()
    packs = (CORPUS / source / "packs.lua").read_bytes()
    if "derive" in case:
        prefix = case["derive"]["prefix"].encode("utf-8")
        if case["derive"]["file"] == "english":
            english = prefix + english
        else:
            packs = prefix + packs
    return english, packs


TOOL_CAP_LINE = re.compile(rb"^_MAX_BASE_ENTRIES = (\d+)\r?$", re.M)


def legacy_cap_catalog(pilot, current):
    """The offline counterpart of the Lua legacy-cap loader: the real tool's
    bytes with exactly its one entry-cap line changed from the current to the
    pilot cap, compiled in memory (no bytecode is written, nothing runs but
    the tool's own definitions). Its scoped offline API gives the dated pilot
    verdicts."""
    source = CATALOG_TOOL.read_bytes()
    old = b"\n_MAX_BASE_ENTRIES = %d" % current
    if [int(value) for value in TOOL_CAP_LINE.findall(source)] != [current] \
            or source.count(old) != 1:
        raise AssertionError("the legacy-cap loader changes exactly the cap line")
    module = types.ModuleType("l10n_catalog_parity_legacy_cap")
    module.__file__ = str(CATALOG_TOOL)
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        exec(compile(source.replace(old, b"\n_MAX_BASE_ENTRIES = %d" % pilot), str(CATALOG_TOOL),
                     "exec"), module.__dict__)
    finally:
        sys.dont_write_bytecode = previous
    return module


def mismatches(catalog, cases, pilot=None):
    """Every disagreement between the offline verdicts and the declared
    mapping, over both line-break variants of each source. pilot is
    (legacy-cap catalog, pilot case IDs): those cases are judged by it."""
    problems = []
    by_id = {case["id"]: case for case in cases}
    for case in cases:
        english, packs = case_sources(case, by_id)
        tool = pilot[0] if pilot and case["id"] in pilot[1] else catalog
        verdicts = {}
        for english_name, english_bytes in variants(english).items():
            for packs_name, packs_bytes in variants(packs).items():
                label = "%s english=%s packs=%s" % (case["id"], english_name, packs_name)
                verdict = offline_verdict(tool, english_bytes, packs_bytes, case["enum"])
                verdicts[label] = verdict
                if verdict != case["offline"]:
                    problems.append("%s: offline %r, mapped %r" % (label, verdict, case["offline"]))
        if len({repr(v) for v in verdicts.values()}) != 1:
            problems.append("%s: LF and CRLF verdicts differ: %r" % (case["id"], verdicts))
    return problems


def lua_string(text):
    """A Lua 5.1 double-quoted literal of text (decimal escapes outside
    printable ASCII), for the in-memory control sources."""
    out = []
    for byte in text.encode("utf-8"):
        char = chr(byte)
        out.append(char if 32 <= byte < 127 and char not in '"\\' else "\\%d" % byte)
    return '"' + "".join(out) + '"'


def grow(entries, count):
    """The Lua harness rule: the entries, then parity.gNNNN = "Generated NNNN"
    for N = 1, 2, ... (skipping a key already present) until there are count."""
    out, index = dict(entries), 0
    while len(out) < count:
        index += 1
        out.setdefault("parity.g%04d" % index, "Generated %04d" % index)
    return out


def control_sources(catalog, control, by_id):
    """(english bytes, packs bytes, enum, declared keys) of a derived cap
    control, built in memory from its committed case; declared keys is the
    Lua harness's derived declaration list for a control that declares extra
    keys, else None."""
    source = by_id[control["from"]]
    directory = CORPUS / source["id"]
    english = catalog.parse_english((directory / "english.lua").read_bytes())
    packs = catalog.parse_packs((directory / "packs.lua").read_bytes())
    if control["file"] == "english":
        english = grow(english, control["entries"])
    else:
        pack = packs[source["enum"][0]]
        pack["entries"] = grow(pack["entries"], control["entries"])
    english_bytes = ("Nexus = Nexus or {}\nNexus.LocalizationEnglish = {\n" + "".join(
        "    [%s] = %s,\n" % (lua_string(key), lua_string(text)) for key, text in english.items())
        + "}\n").encode("utf-8")
    packs_bytes = ("Nexus = Nexus or {}\nNexus.LocalizationPacks = {\n" + "".join(
        "    %s = { name = %s, entries = {\n%s    } },\n" % (pack_id, lua_string(pack["name"]), "".join(
            "        [%s] = %s,\n" % (lua_string(key), lua_string(text))
            for key, text in pack["entries"].items())) for pack_id, pack in packs.items())
        + "}\n").encode("utf-8")
    declared = None
    if "extraDeclarations" in control:
        cap = int(TOOL_CAP_LINE.findall(CATALOG_TOOL.read_bytes())[0])
        declared = sorted(key for key in english if KEY_RULE.fullmatch(key))[:cap]
        declared += list(control["extraDeclarations"])
    return english_bytes, packs_bytes, source["enum"], declared


KEY_RULE = re.compile(r"[a-z][a-z0-9_]*(?:[.][a-z][a-z0-9_]*)+")


def control_verdict(catalog, control, by_id):
    """The offline verdict of a derived cap control under the tool's cap: for
    a control that declares extra keys, the registry-bound parser over the
    derived declaration block (each a text declaration), else the scoped
    English and pack checks of offline_verdict."""
    english, packs, enum, declared = control_sources(catalog, control, by_id)
    if declared is None:
        return offline_verdict(catalog, english, packs, enum)
    block = ("-- derived control block\n" + MARKER_OPEN.decode() + "\nlocal DECLARATIONS = {\n"
             + "".join('    [%s] = {kind = "text"},\n' % lua_string(key) for key in declared)
             + "}\n" + MARKER_CLOSE.decode() + "\n").encode("utf-8")
    try:
        getattr(catalog, REGISTRY_PARSER)(block)
    except catalog.CatalogRegistryError as error:
        return {"code": error.code}
    return {"code": "valid"}


def registry_sentinel(localization_source, catalog, registry):
    """The G1 interlock: a list of problems, empty when the declaration
    marker, the registry-bound parser and bound registry rows are all absent
    or all present (see the module documentation)."""
    problems = []
    lines = localization_source.replace(b"\r\n", b"\n").split(b"\n")
    opens = [i for i, line in enumerate(lines) if line == MARKER_OPEN]
    closes = [i for i, line in enumerate(lines) if line == MARKER_CLOSE]
    total = localization_source.count(MARKER_TOKEN)
    marker = total > 0
    if marker and not (len(opens) == 1 and len(closes) == 1 and opens[0] < closes[0]
                       and total == 2):
        problems.append("malformed declaration marker: exactly one BEGIN line before one END "
                        "line, and no other NEXUS-L10N-REGISTRY token")
    parser = callable(getattr(catalog, REGISTRY_PARSER, None))
    states = {row["id"]: row["state"] for row in registry["rows"]}
    if sorted(states) != REGISTRY_ROWS or not set(states.values()) <= {PENDING, BOUND}:
        problems.append("registry rows must be exactly %s, each %s or %s"
                        % (REGISTRY_ROWS, PENDING, BOUND))
    bound = bool(states) and all(state == BOUND for state in states.values())
    if any(state == BOUND for state in states.values()) and not bound:
        problems.append("registry rows are partly bound")
    parts = {"declaration marker in core/Localization.lua": marker,
             "registry-bound parser %s" % REGISTRY_PARSER: parser,
             "bound complete-English registry rows": bound}
    if len(set(parts.values())) != 1:
        present = sorted(name for name, value in parts.items() if value)
        absent = sorted(name for name, value in parts.items() if not value)
        problems.append("U1, U2 and U3 cannot ship apart: present %s, absent %s"
                        % (present, absent))
    return problems


REGISTRY_INPUTS = ("data/LocalizationEnglish.lua", "data/LocalizationPacks.lua",
                   "docs/localization/KEY_CONTEXT.json",
                   "docs/localization/RELEASE_LANGUAGES.json", "core/Localization.lua")
REGISTRY_API = "validate_registry_catalog_data"


def edited_input(data, edit):
    """The bytes of a real input with a bound row's edit applied: one whole
    line inserted after or removed, or one exact text replaced, which must
    each occur exactly once. Line edits keep the input's line breaks."""
    if "replace" in edit:
        old, new = edit["replace"].encode("utf-8"), edit["with"].encode("utf-8")
        if data.count(old) != 1:
            raise ValueError("the replaced text must occur exactly once")
        return data.replace(old, new)
    newline = b"\r\n" if b"\r\n" in data else b"\n"
    lines, found = data.split(newline), 0
    target = (edit.get("after") or edit.get("remove")).encode("utf-8")
    out = []
    for line in lines:
        if "remove" in edit and line == target:
            found += 1
            continue
        out.append(line)
        if "after" in edit and line == target:
            found += 1
            out.append(edit["line"].encode("utf-8"))
    if found != 1:
        raise ValueError("the edited line must occur exactly once")
    return newline.join(out)


def padded_english(data, count):
    """English base bytes with count generated legal entries
    (parity.gNNNN = "Generated NNNN", the corpus controls' rule, undeclared)
    inserted after the table's opening line, in the input's own line breaks.
    The opening line must occur exactly once."""
    newline = b"\r\n" if b"\r\n" in data else b"\n"
    opener = b"Nexus.LocalizationEnglish = {" + newline
    if data.count(opener) != 1:
        raise ValueError("the English table opening line must occur exactly once")
    lines = b"".join(b'    ["parity.g%04d"] = "Generated %04d",' % (index, index) + newline
                     for index in range(1, count + 1))
    return data.replace(opener, opener + lines)


def registry_verdicts(catalog, row, inputs):
    """The registry-bound offline verdict of a bound row, as {code, key},
    for each line-break variant of the edited Lua input (one entry for a
    document edit)."""
    index = REGISTRY_INPUTS.index(row["input"]["file"])
    data = edited_input(inputs[index], row["input"])
    errors = (catalog.CatalogSyntaxError, catalog.CatalogValidationError,
              getattr(catalog, "CatalogRegistryError", catalog.CatalogValidationError))
    variants_of = variants(data) if row["input"]["file"].endswith(".lua") else {"exact": data}
    verdicts = {}
    for name, value in variants_of.items():
        changed = list(inputs)
        changed[index] = value
        try:
            getattr(catalog, REGISTRY_API)(*changed)
            verdicts[name] = {"code": "valid"}
        except errors as error:
            verdicts[name] = {"code": error.code, "key": getattr(error, "key", None)}
    return verdicts


def registry_binding(catalog, registry, inputs):
    """The genuine R-union binding beyond presence (see the module
    documentation): a list of problems, empty when it holds."""
    problems = []
    parser = getattr(catalog, REGISTRY_PARSER, None)
    api = getattr(catalog, REGISTRY_API, None)
    if not callable(parser) or not callable(api):
        return ["registry parser and registry-bound API must both exist"]
    try:
        declared = parser(inputs[4])
        english = catalog.parse_english(inputs[0])
        context = {row.get("key") for row in json.loads(inputs[2].decode("utf-8"))["keys"]}
    except Exception as error:  # a failed parse is a binding problem, reported, not raised
        return ["real inputs do not parse: %r" % (error,)]
    if not (set(declared) == set(english) == context) or not declared:
        problems.append("declared, English and KEY_CONTEXT key sets differ: %d, %d, %d"
                        % (len(declared), len(english), len(context)))
    try:
        api(*inputs)
    except Exception as error:
        problems.append("the real inputs fail the registry-bound API: %r" % (error,))
    for row in registry["rows"]:
        want = (row.get("expect") or {}).get("offline")
        if row.get("state") != BOUND or not want or "input" not in row:
            problems.append("%s: not a bound row with an input and an expected verdict" % row["id"])
            continue
        try:
            verdicts = registry_verdicts(catalog, row, inputs)
        except Exception as error:
            problems.append("%s: verdict not reproducible: %r" % (row["id"], error))
            continue
        for name, verdict in verdicts.items():
            if verdict != want:
                problems.append("%s %s: offline %r, expected %r" % (row["id"], name, verdict, want))
    return problems


class LiteralTableParserTests(unittest.TestCase):
    """The private restricted literal-table parser reads data only."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog()
        cls.parse = staticmethod(cls.catalog._parse_literal_table)

    def test_accepts_literal_tables(self):
        source = (b"-- comment\r\nreturn { a = \"x\", [\"b.c\"] = [[long]], n = 0, m = 123456789,"
                  b" t = true, f = false, list = { \"p\", 7, { q = 1 } }, empty = {}, }\r\n")
        self.assertEqual(self.parse(source), {
            "a": "x", "b.c": "long", "n": 0, "m": 123456789, "t": True, "f": False,
            "list": ["p", 7, {"q": 1}], "empty": []})
        self.assertEqual(self.parse(b"return {}"), [])
        self.assertEqual(self.parse(bytearray(b"return {\"\\194\\160\"}")), ["\u00a0"])

    def test_refuses_executable_and_nonliteral_forms(self):
        refused = {
            b"return { a = f() }": "unexpected-token",
            b"return { a = os.execute(\"x\") }": "unexpected-token",
            b"return { a = 1 + 2 }": "unexpected-token",
            b"return { a = \"x\" .. \"y\" }": "unexpected-token",
            b"return { a = -1 }": "unexpected-token",
            b"return { a = 1.5 }": "unexpected-token",
            b"return { a = 0x10 }": "unexpected-token",
            b"return { a = 1e3 }": "unexpected-token",
            b"return { a = 007 }": "unexpected-token",
            b"return { a = 1234567890 }": "unexpected-token",
            b"return { a = nil }": "unexpected-token",
            b"return { a = b }": "unexpected-token",
            b"return { a = function() end }": "unexpected-token",
            b"return { [1] = 2 }": "unexpected-token",
            b"return { [a] = 2 }": "unexpected-token",
            b"return { a = 1; b = 2 }": "unexpected-token",
            b"return { a = 1, 2 }": "unexpected-token",
            b"return { 2, a = 1 }": "unexpected-token",
            b"return { x }": "unexpected-token",
            b"return { a = #t }": "unexpected-token",
            b"local t = {} return t": "unexpected-token",
            b"Nexus = Nexus or {}": "unexpected-token",
            b"return { a = 1, a = 2 }": "duplicate-key",
            b"return { a = 1, [\"a\"] = 2 }": "duplicate-key",
            b"return { a = 1 } return {}": "trailing-content",
            b"return { a = 1 };": "trailing-content",
            b"return { a = 1 }()": "trailing-content",
            b"return { a = ": "unexpected-end",
            b"\xef\xbb\xbfreturn {}": "unexpected-token",
            b"return { a = \"\\192\" }": "value-not-utf8",
            b"return { a = \"\xff\" }": "not-utf8",
        }
        for source, code in refused.items():
            with self.subTest(source=source):
                with self.assertRaises(self.catalog.CatalogSyntaxError) as raised:
                    self.parse(source)
                self.assertEqual(raised.exception.code, code)
                self.assertIn(code, self.catalog.CODES)

    def test_depth_is_bounded(self):
        self.assertEqual(self.parse(b"return " + b"{" * 8 + b"}" * 8), [[[[[[[[]]]]]]]])
        with self.assertRaises(self.catalog.CatalogSyntaxError) as raised:
            self.parse(b"return " + b"{" * 9 + b"}" * 9)
        self.assertEqual(raised.exception.code, "unexpected-token")

    def test_takes_bytes_only(self):
        for value in ("return {}", None, 1):
            with self.subTest(value=value), self.assertRaises(TypeError):
                self.parse(value)

    def test_public_parsers_still_refuse_digits(self):
        head = b"Nexus = Nexus or {}\nNexus.LocalizationEnglish = { [\"a.b\"] = 1 }"
        with self.assertRaises(self.catalog.CatalogSyntaxError) as raised:
            self.catalog.parse_english(head)
        self.assertEqual((raised.exception.code, raised.exception.line, raised.exception.column),
                         ("unexpected-token", 2, 41))
        self.assertEqual(self.catalog.CODES, (
            "not-utf8", "value-not-utf8", "unfinished-string", "unfinished-comment",
            "invalid-escape", "nested-long-bracket", "bad-bootstrap", "bad-assignment",
            "unexpected-token", "unexpected-end", "trailing-content", "duplicate-key",
            "duplicate-pack", "duplicate-field", "unknown-field", "missing-field"))
        # R union: the registry-bound parser now exists, beside the unchanged
        # public parsers and their unchanged CODES (S1 asserted its absence).
        self.assertTrue(callable(getattr(self.catalog, REGISTRY_PARSER, None)))


class ParityCorpusTests(unittest.TestCase):
    """The same case bytes give the declared offline verdicts."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog()
        cls.corpus = cls.catalog._parse_literal_table(CASES.read_bytes())
        cls.cases = cls.corpus["cases"]
        cls.by_id = {case["id"]: case for case in cls.cases}
        cap = cls.corpus["runtimeCap"]
        cls.pilot = (legacy_cap_catalog(cap["pilot"], cap["current"]), frozenset(cap["pilotCases"]))

    def test_corpus_metadata(self):
        corpus = self.corpus
        self.assertEqual((corpus["schema"], corpus["schemaVersion"]), ("nexus.l10n.parity_cases", 1))
        self.assertEqual(corpus["shippedProductIds"], [])
        self.assertEqual(corpus["mappedRows"], MAPPED_ROWS)
        self.assertEqual(corpus["unknownRows"], UNKNOWN_ROWS)
        self.assertEqual(len(self.by_id), len(self.cases))
        covered = {row for case in self.cases for row in case["rows"]}
        self.assertLessEqual(set(MAPPED_ROWS + UNKNOWN_ROWS), covered)
        for row in UNKNOWN_ROWS:
            for case in self.cases:
                if row in case["rows"]:
                    self.assertEqual(case["native"], "UNKNOWN", case["id"])

    def test_fixtures_stay_tests_only(self):
        committed = {case["id"] for case in self.cases if "derive" not in case}
        on_disk = {path.name for path in CORPUS.iterdir() if path.is_dir()}
        self.assertEqual(on_disk, committed)
        for name in committed:
            self.assertEqual(sorted(p.name for p in (CORPUS / name).iterdir()),
                             ["english.lua", "packs.lua"])
        pack_ids = set()
        for case in self.cases:
            pack_ids.update(case["enum"])
            english, packs = case_sources(case, self.by_id)
            try:
                pack_ids.update(self.catalog.parse_packs(packs))
            except self.catalog.CatalogSyntaxError:
                pass
        self.assertTrue(pack_ids)
        for pack_id in pack_ids:
            self.assertRegex(pack_id, PSEUDO_PACK)
        shipped = [ROOT / "Nexus.toc", ROOT / "data" / "DefaultProfile.lua",
                   ROOT / "data" / "LocalizationPacks.lua",
                   ROOT / "docs" / "localization" / "RELEASE_LANGUAGES.json"]
        for path in shipped:
            data = path.read_bytes()
            self.assertNotIn(b"l10n_parity", data, path.name)
            for pack_id in pack_ids:
                self.assertNotIn(pack_id.encode("ascii"), data, (path.name, pack_id))

    def test_offline_verdicts_follow_the_mapping(self):
        self.assertEqual(mismatches(self.catalog, self.cases, self.pilot), [])

    def test_line_break_variants_decode_identically(self):
        for case in self.cases:
            english, packs = case_sources(case, self.by_id)
            for name, data, parse in (("english", english, self.catalog.parse_english),
                                      ("packs", packs, self.catalog.parse_packs)):
                with self.subTest(case=case["id"], file=name):
                    both = variants(data)
                    self.assertIn(data, both.values())
                    decoded = []
                    for raw in both.values():
                        try:
                            decoded.append(("value", parse(raw)))
                        except self.catalog.CatalogSyntaxError as error:
                            decoded.append(("error", error.code, error.line, error.column))
                    self.assertEqual(decoded[0], decoded[1])

    def test_lone_cr_is_refused_by_the_variant_helper(self):
        with self.assertRaises(ValueError):
            variants(b"a\rb\r\n")
        with self.assertRaises(ValueError):
            variants(b"a\nb\r\n")

    def test_duplicate_keys_diverge_by_design(self):
        # P8: offline rejects; the Lua constructor keeps the last value (checked in Lua).
        for case_id in ("p08_duplicate_english", "p08_duplicate_pack_entry"):
            self.assertEqual(self.by_id[case_id]["offline"]["code"], "duplicate-key")
        self.assertEqual(self.by_id["p08_duplicate_english"]["runtime"]["probes"][0]["text"], "Second")
        self.assertEqual(self.by_id["p08_duplicate_pack_entry"]["runtime"]["probes"][0]["text"], "Deux")

    def test_escape_equivalence(self):
        # P13: literal UTF-8 and decimal escapes decode to the same value.
        directory = CORPUS / "p13_escape_equivalence"
        english = self.catalog.parse_english((directory / "english.lua").read_bytes())
        packs = self.catalog.parse_packs((directory / "packs.lua").read_bytes())
        self.assertEqual(english["parity.ru"], packs["qaQA"]["entries"]["parity.ru"])
        self.assertEqual(english["parity.ru"], "\u0420\u0443\u0441\u0441\u043a\u0438\u0439")

    def test_p19_offline_decoding_is_lua51_and_native_unknown(self):
        case = self.by_id["p19_ambiguous_escapes"]
        self.assertEqual(case["native"], "UNKNOWN")
        self.assertEqual(case["proposedCode"], "ambiguous-escape")
        self.assertNotIn(case["proposedCode"], self.catalog.CODES)
        self.assertNotIn(case["proposedCode"], self.catalog.VALIDATION_CODES)
        self.assertNotEqual(case["decoded"]["lua51"], case["decoded"]["luajit"])
        english = self.catalog.parse_english((CORPUS / case["id"] / "english.lua").read_bytes())
        for key, value in case["decoded"]["lua51"].items():
            self.assertEqual(english[key], value)

    def test_p20_bom_is_derived_in_memory_and_native_unknown(self):
        case = self.by_id["p20_bom"]
        self.assertEqual(case["native"], "UNKNOWN")
        self.assertEqual(case["derive"], {"from": "p01_valid", "file": "english", "prefix": "\ufeff"})
        self.assertEqual(sorted(case["harness"]), ["refused", "same_as_source"])
        english, _ = case_sources(case, self.by_id)
        self.assertTrue(english.startswith(b"\xef\xbb\xbf"))
        # The plan predicted unexpected-token; the tool reports the first refused
        # token as bad-bootstrap. The mapping records the actual code.
        self.assertEqual(case["planPrediction"], "unexpected-token")
        self.assertEqual(case["offline"], {"code": "bad-bootstrap", "line": 1, "column": 1})

    def test_a_wrong_mapping_row_is_detected(self):
        # C12: the comparison is not vacuous.
        wrong = copy.deepcopy(self.cases)
        for case in wrong:
            if case["id"] == "p15_pipe_colour":
                case["offline"] = {"code": "valid"}
        problems = mismatches(self.catalog, wrong, self.pilot)
        self.assertEqual(len(problems), 4)
        self.assertTrue(all(problem.startswith("p15_pipe_colour") for problem in problems))

    def test_runtime_cap_records_agree_with_their_sources(self):
        # The corpus records the cap of the real runtime, which the offline
        # tool applies, and apart the dated pilot cap, which only the
        # legacy-cap loader applies (exactly one tool line changed in memory).
        cap = self.corpus["runtimeCap"]
        found = re.findall(rb"^local MAX_BASE_ENTRIES = (\d+)\r?$", LOCALIZATION.read_bytes(), re.M)
        self.assertEqual([int(value) for value in found], [cap["current"]])
        self.assertEqual(cap["current"], self.catalog._MAX_BASE_ENTRIES)
        self.assertEqual([int(value) for value in TOOL_CAP_LINE.findall(CATALOG_TOOL.read_bytes())],
                         [cap["current"]])
        self.assertEqual(cap["pilot"], self.pilot[0]._MAX_BASE_ENTRIES)
        self.assertLess(cap["pilot"], cap["current"])
        # The pilot cases keep their committed bytes and their pilot-cap
        # offline verdicts; the current-runtime boundaries are derived controls.
        self.assertEqual(cap["pilotCases"], ["p03_english_65", "p06_pack_65", "p17_bounds_64"])
        self.assertEqual([self.by_id[case]["offline"]["code"] for case in cap["pilotCases"]],
                         ["english-too-many", "pack-too-many-entries", "valid"])
        for case in cap["pilotCases"]:
            self.assertNotIn("derive", self.by_id[case])
        self.assertIn("pilotRuntime", self.by_id["p03_english_65"])
        self.assertTrue(self.by_id["p03_english_65"]["pilotRuntime"]["base"]["oversized"])
        self.assertFalse(self.by_id["p03_english_65"]["runtime"]["base"]["oversized"])
        boundaries = sorted((control["file"], control["entries"]) for control in cap["controls"])
        self.assertEqual(boundaries, [("english", cap["current"]), ("english", cap["current"]),
                                      ("english", cap["current"] + 1), ("packs", cap["current"]),
                                      ("packs", cap["current"] + 1)])
        for control in cap["controls"]:
            self.assertIn(control["from"], cap["pilotCases"])
            self.assertNotIn(control["id"], self.by_id)

    def test_cap_controls_reproduce_their_offline_verdicts(self):
        # Each derived cap / cap + 1 control has its own current-cap offline
        # verdict: the same over-cap rule as the dated pilot cases, at the
        # current cap. Every control above the cap is refused offline.
        cap = self.corpus["runtimeCap"]
        current = self.catalog._MAX_BASE_ENTRIES
        for control in cap["controls"]:
            with self.subTest(control["id"]):
                self.assertIn("offline", control)
                self.assertEqual(control_verdict(self.catalog, control, self.by_id),
                                 control["offline"])
                over = control["entries"] > current or "extraDeclarations" in control
                self.assertEqual(control["offline"]["code"] in (
                    "english-too-many", "pack-too-many-entries", "registry-too-many"), over)
        # The control rule is causal: the legacy-cap tool refuses the
        # at-cap controls too, for the same over-cap reason.
        for control in cap["controls"]:
            if control["entries"] == current and "extraDeclarations" not in control:
                with self.subTest(pilot=control["id"]):
                    verdict = control_verdict(self.pilot[0], control, self.by_id)
                    self.assertIn(verdict["code"], ("english-too-many", "pack-too-many-entries"))

    def test_lua_side_reads_the_same_corpus(self):
        source = LUA_TEST.read_bytes()
        self.assertIn(b"local CORPUS='tests/prototype/fixtures/l10n_parity/'", source)
        self.assertIn(b"dofile,'core/Localization.lua'", source)


class RegistrySentinelTests(unittest.TestCase):
    """G1: U1, U2 and U3 can only land together."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog()
        cls.registry = cls.catalog._parse_literal_table(CASES.read_bytes())["registry"]
        cls.source = LOCALIZATION.read_bytes()
        cls.inputs = [(ROOT / relative).read_bytes() for relative in REGISTRY_INPUTS]
        # The synthetic cases below derive from a fixed marker-free source,
        # stand-in catalogs and explicit pending or bound copies of the rows,
        # so they test the sentinel apart from the current state; only the
        # current-source and binding tests read the real files and tool.
        cls.plain = b"-- synthetic core/Localization.lua\r\nlocal L = {}\r\n"

    def bound(self):
        registry = copy.deepcopy(self.registry)
        for row in registry["rows"]:
            row["state"] = BOUND
        return registry

    def pending(self):
        # The S1 state of the rows, now that the committed rows are bound.
        registry = copy.deepcopy(self.registry)
        for row in registry["rows"]:
            row["state"] = PENDING
        return registry

    @staticmethod
    def with_parser():
        return types.SimpleNamespace(**{REGISTRY_PARSER: lambda source: {}})

    @staticmethod
    def without_parser():
        return types.SimpleNamespace()

    def marked(self):
        return self.plain + MARKER_OPEN + b"\r\nlocal DECLARATIONS = {}\r\n" + MARKER_CLOSE + b"\r\n"

    def test_marker_convention_is_recorded_once(self):
        marker = self.registry["marker"]
        self.assertEqual((marker["path"], marker["token"], marker["open"], marker["close"]),
                         ("core/Localization.lua", MARKER_TOKEN.decode(), MARKER_OPEN.decode(),
                          MARKER_CLOSE.decode()))
        self.assertEqual((self.registry["parser"], self.registry["pending"], self.registry["bound"]),
                         (REGISTRY_PARSER, PENDING, BOUND))
        self.assertEqual([row["id"] for row in self.registry["rows"]], REGISTRY_ROWS)

    def test_current_source_passes(self):
        self.assertEqual(registry_sentinel(self.source, self.catalog, self.registry), [])
        # R union: presence is not enough; the binding itself must hold.
        self.assertEqual([row["state"] for row in self.registry["rows"]], [BOUND] * 3)
        self.assertEqual(registry_binding(self.catalog, self.registry, self.inputs), [])

    def test_bound_rows_reproduce_their_offline_verdicts(self):
        # C14 / R-P1..R-P3: undeclared English, context mismatch, missing English.
        expected = {"R-P1": {"code": "undeclared-entry", "key": "parity.undeclared"},
                    "R-P2": {"code": "context-declaration-mismatch", "key": "readout.charge_counts"},
                    "R-P3": {"code": "english-incomplete", "key": "panel.button.options"}}
        for row in self.registry["rows"]:
            with self.subTest(row=row["id"]):
                self.assertEqual(row["expect"]["offline"], expected[row["id"]])
                verdicts = registry_verdicts(self.catalog, row, self.inputs)
                self.assertEqual(sorted(verdicts), ["crlf", "lf"] if row["input"]["file"]
                                 .endswith(".lua") else ["exact"])
                self.assertEqual(list(verdicts.values()), [expected[row["id"]]] * len(verdicts))
        # The unedited real inputs pass, so each verdict comes from its edit.
        self.catalog.validate_registry_catalog_data(*self.inputs)

    def test_english_rows_padded_above_the_cap_are_refused_offline(self):
        # v33 slice A (review finding F1 / SA-1): the real English is below the
        # bounded cap, so a row's own edit no longer goes above it. Each English
        # registry edit, padded with generated entries to exactly
        # runtimeCap.current + 1 (the cap stated by the corpus, not read from the
        # tool), is refused by the registry-bound API with english-too-many in
        # both line-break variants. This is the offline counterpart of the Lua
        # harness's real-data above-cap guard. The rows' own verdicts stay
        # checked on their unpadded edits above.
        cap = self.catalog._parse_literal_table(CASES.read_bytes())["runtimeCap"]["current"]
        errors = (self.catalog.CatalogSyntaxError, self.catalog.CatalogValidationError,
                  getattr(self.catalog, "CatalogRegistryError", self.catalog.CatalogValidationError))
        ran = expected = 0
        for row in self.registry["rows"]:
            if row["input"]["file"] != "data/LocalizationEnglish.lua":
                continue
            data = edited_input(self.inputs[0], row["input"])
            for name, value in variants(data).items():
                expected += 1
                with self.subTest(row=row["id"], variant=name):
                    natural = len(self.catalog.parse_english(value))
                    padded = padded_english(value, max(0, cap + 1 - natural))
                    self.assertEqual(len(self.catalog.parse_english(padded)), max(natural, cap + 1))
                    changed = list(self.inputs)
                    changed[0] = padded
                    try:
                        getattr(self.catalog, REGISTRY_API)(*changed)
                        verdict = {"code": "valid"}
                    except errors as error:
                        verdict = {"code": error.code}
                    self.assertEqual(verdict, {"code": "english-too-many"})
                    ran += 1
        # Liveness: every English row variant reached the above-cap refusal.
        self.assertGreater(expected, 0)
        self.assertEqual(ran, expected)

    def test_registry_enum_is_the_release_product_list(self):
        release = json.loads(self.inputs[3].decode("utf-8"))
        self.assertEqual(self.registry["enum"], [p["productId"] for p in release["products"]])

    def test_binding_fails_for_stand_ins_and_wrong_rows(self):
        catalog = self.catalog
        empty = types.SimpleNamespace(**{REGISTRY_PARSER: lambda source: {},
                                         REGISTRY_API: catalog.validate_registry_catalog_data,
                                         "parse_english": catalog.parse_english})
        self.assertTrue(any("key sets differ" in p
                            for p in registry_binding(empty, self.registry, self.inputs)))
        no_api = types.SimpleNamespace(**{REGISTRY_PARSER: catalog.parse_registry_declarations})
        self.assertEqual(registry_binding(no_api, self.registry, self.inputs),
                         ["registry parser and registry-bound API must both exist"])
        wrong = copy.deepcopy(self.registry)
        wrong["rows"][0]["expect"]["offline"] = {"code": "valid"}
        problems = registry_binding(catalog, wrong, self.inputs)
        self.assertEqual(len(problems), 2)
        self.assertTrue(all(problem.startswith("R-P1") for problem in problems))
        flagged = copy.deepcopy(self.registry)
        del flagged["rows"][2]["input"]
        self.assertEqual(registry_binding(catalog, flagged, self.inputs),
                         ["R-P3: not a bound row with an input and an expected verdict"])
        # Drift of the real English in both line-break representations: the
        # unedited bytes bind, and removing exactly the Options row does not.
        for name, data in variants(self.inputs[0]).items():
            with self.subTest(representation=name):
                drifted = list(self.inputs)
                drifted[0] = data
                self.assertEqual(registry_binding(catalog, self.registry, drifted), [])
                edited = edited_input(data, {"remove": '    ["panel.button.options"] = "Options",'})
                self.assertNotEqual(edited, data)
                parsed = catalog.parse_english(edited)
                self.assertEqual(set(catalog.parse_english(data)) - set(parsed),
                                 {"panel.button.options"})
                self.assertEqual(len(parsed), len(catalog.parse_english(data)) - 1)
                drifted[0] = edited
                problems = registry_binding(catalog, self.registry, drifted)
                self.assertTrue(any("key sets differ" in problem for problem in problems), problems)
                self.assertTrue(any("english-incomplete" in problem for problem in problems), problems)
        with self.assertRaises(ValueError):
            edited_input(self.inputs[0], {"remove": '    ["panel.button.options"] = "Option",'})

    def test_u1_only_marker_fails(self):
        problems = registry_sentinel(self.marked(), self.without_parser(), self.pending())
        self.assertEqual(len(problems), 1)
        self.assertIn("absent ['bound complete-English registry rows', "
                      "'registry-bound parser parse_registry_declarations']", problems[0])

    def test_partial_unions_fail(self):
        for name, source, catalog, registry in (
                ("U3 parser only", self.plain, self.with_parser(), self.pending()),
                ("U2 rows only", self.plain, self.without_parser(), self.bound()),
                ("U1 and U3 without U2", self.marked(), self.with_parser(), self.pending()),
                ("U1 and U2 without U3", self.marked(), self.without_parser(), self.bound())):
            with self.subTest(name=name):
                self.assertTrue(registry_sentinel(source, catalog, registry))

    def test_malformed_marker_fails(self):
        for source in (self.plain + MARKER_OPEN + b"\n",
                       self.plain + MARKER_CLOSE + b"\n" + MARKER_OPEN + b"\n",
                       self.marked() + b"-- see NEXUS-L10N-REGISTRY\n",
                       self.marked() + self.marked(),
                       self.plain + b"--  NEXUS-L10N-REGISTRY BEGIN\n-- NEXUS-L10N-REGISTRY END\n"):
            with self.subTest(source=source[-80:]):
                problems = registry_sentinel(source, self.with_parser(), self.bound())
                self.assertTrue(any(problem.startswith("malformed") for problem in problems))

    def test_partly_bound_rows_fail(self):
        registry = self.pending()
        registry["rows"][0]["state"] = BOUND
        self.assertTrue(registry_sentinel(self.marked(), self.with_parser(), registry))
        self.assertTrue(registry_sentinel(self.plain, self.without_parser(), registry))

    def test_absent_union_and_complete_union_pass(self):
        self.assertEqual(registry_sentinel(self.plain, self.without_parser(), self.pending()), [])
        self.assertEqual(registry_sentinel(self.marked(), self.with_parser(), self.bound()), [])


if __name__ == "__main__":
    unittest.main()
