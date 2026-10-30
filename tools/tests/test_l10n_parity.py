"""Offline side of the shared runtime/offline localization parity corpus and
the registry interlock sentinel (Refs #147, slice S1).

The corpus is tests/prototype/fixtures/l10n_parity: cases.lua and one
directory per committed case holding english.lua and packs.lua in the real
data grammars. tests/prototype/localization_parity.lua loads the same bytes
into the unchanged core/Localization.lua under LuaJIT and checks each case's
runtime expectation. This file parses the same bytes and never evaluates,
imports or executes Lua: cases.lua is read with the private restricted
literal-table parser _parse_literal_table of tools/l10n_catalog.py, and each
case's offline verdict is the first CatalogSyntaxError or
CatalogValidationError of parse_english, parse_packs and the tool's scoped
English and pack checks (_check_english, _check_packs) against products made
from the case's language enum, or "valid". The two sides keep their own
category names; the declared mapping is the parity claim. LF and CRLF
variants are derived in memory. P19 and P20 native WoW behaviour stays
UNKNOWN; only offline decoding and metadata are checked here.

Registry interlock (G1). The declaration marker convention is exact and
bounded: the ASCII token NEXUS-L10N-REGISTRY in core/Localization.lua may
appear only as the two whole lines "-- NEXUS-L10N-REGISTRY BEGIN" and
"-- NEXUS-L10N-REGISTRY END", once each, BEGIN first, around the future
declaration block. Any other occurrence of the token is malformed. The
sentinel passes only when the marker, the registry-bound parser
(parse_registry_declarations in tools/l10n_catalog.py) and bound registry
rows (R-P1..R-P3 of cases.lua) are all absent, as today, or all present: a
U1-only marker, a U3-only parser or U2-only complete-English rows fail.

Synthetic offline evidence, not native evidence. Python 3.9+, standard
library only. Registered in PYTHON_TESTS of tools/run_prototype_tests.py.

Run directly:  python tools/tests/test_l10n_parity.py -v
"""

import copy
import importlib.util
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


def mismatches(catalog, cases):
    """Every disagreement between the offline verdicts and the declared
    mapping, over both line-break variants of each source."""
    problems = []
    by_id = {case["id"]: case for case in cases}
    for case in cases:
        english, packs = case_sources(case, by_id)
        verdicts = {}
        for english_name, english_bytes in variants(english).items():
            for packs_name, packs_bytes in variants(packs).items():
                label = "%s english=%s packs=%s" % (case["id"], english_name, packs_name)
                verdict = offline_verdict(catalog, english_bytes, packs_bytes, case["enum"])
                verdicts[label] = verdict
                if verdict != case["offline"]:
                    problems.append("%s: offline %r, mapped %r" % (label, verdict, case["offline"]))
        if len({repr(v) for v in verdicts.values()}) != 1:
            problems.append("%s: LF and CRLF verdicts differ: %r" % (case["id"], verdicts))
    return problems


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
        self.assertFalse(hasattr(self.catalog, REGISTRY_PARSER))


class ParityCorpusTests(unittest.TestCase):
    """The same case bytes give the declared offline verdicts."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog()
        cls.corpus = cls.catalog._parse_literal_table(CASES.read_bytes())
        cls.cases = cls.corpus["cases"]
        cls.by_id = {case["id"]: case for case in cls.cases}

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
        self.assertEqual(mismatches(self.catalog, self.cases), [])

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
        problems = mismatches(self.catalog, wrong)
        self.assertEqual(len(problems), 4)
        self.assertTrue(all(problem.startswith("p15_pipe_colour") for problem in problems))

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
        # The synthetic cases below derive from a fixed marker-free source and
        # stand-in catalogs, so they test the sentinel apart from the current
        # state; only test_current_source_passes reads the real file and tool.
        cls.plain = b"-- synthetic core/Localization.lua\r\nlocal L = {}\r\n"

    def bound(self):
        registry = copy.deepcopy(self.registry)
        for row in registry["rows"]:
            row["state"] = BOUND
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

    def test_u1_only_marker_fails(self):
        problems = registry_sentinel(self.marked(), self.without_parser(), self.registry)
        self.assertEqual(len(problems), 1)
        self.assertIn("absent ['bound complete-English registry rows', "
                      "'registry-bound parser parse_registry_declarations']", problems[0])

    def test_partial_unions_fail(self):
        for name, source, catalog, registry in (
                ("U3 parser only", self.plain, self.with_parser(), self.registry),
                ("U2 rows only", self.plain, self.without_parser(), self.bound()),
                ("U1 and U3 without U2", self.marked(), self.with_parser(), self.registry),
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
        registry = copy.deepcopy(self.registry)
        registry["rows"][0]["state"] = BOUND
        self.assertTrue(registry_sentinel(self.marked(), self.with_parser(), registry))
        self.assertTrue(registry_sentinel(self.plain, self.without_parser(), registry))

    def test_absent_union_and_complete_union_pass(self):
        self.assertEqual(registry_sentinel(self.plain, self.without_parser(), self.registry), [])
        self.assertEqual(registry_sentinel(self.marked(), self.with_parser(), self.bound()), [])


if __name__ == "__main__":
    unittest.main()
