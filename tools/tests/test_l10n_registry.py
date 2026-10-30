"""Registry-bound localization catalog: the nonexecuting declaration parser
and the five-input API and report v2 of tools/l10n_catalog.py (Refs #147,
slices S2 and S5 of the R union).

core/Localization.lua holds one literal declaration table between the exact
lines "-- NEXUS-L10N-REGISTRY BEGIN" and "-- NEXUS-L10N-REGISTRY END". The
runtime derives its format schemas and English admission from it.
parse_registry_declarations reads the same bytes without evaluating,
importing or executing Lua. validate_registry_catalog_data and
registry_catalog_report take the exact bytes of the English base, the packs,
KEY_CONTEXT.json, RELEASE_LANGUAGES.json and core/Localization.lua; the parsed
declarations, never the four-input tool's fixed constants, govern them. The
four-input validate_catalog_data and catalog_report keep report schemaVersion
1 and their scoped label. F7: the tool's product list is checked here against
the uiLanguages enum of data/DefaultProfile.lua by an explicit equality test
on its bytes, which are not an API input.

S7 adds the required-CI check of the current per-pack provenance records of
RELEASE_LANGUAGES.json through pack_provenance_diagnostics: the real UNKNOWN
records are technically valid with support held, while malformed and stale
variants of the real bytes are refused.

S8 adds the required-CI static consumer binding of the current repository
through consumer_binding_report: the real registry inputs, both TOCs and every
Lua file they load bind all 28 declared keys (23 direct, 5 mapped) with no
problem, each counted site with a proven output, and in-memory mutants of
the real bytes (a removed last consumer with fakes retained, a broken map
chain, a wrong method kind, a TOC or source omission, hash drift and path
collisions) fail the same gate. Review fix 1 adds discarded, overwritten,
compared and unused-helper results, review fix 2 a dispatcher overwritten
through a module alias, and review fix 3 the closed two-TOC contract.

Synthetic offline evidence only: no Lua runs, and this is not fluent, human
or native evidence. Python 3.9+, standard library only. Registered in
PYTHON_TESTS of tools/run_prototype_tests.py.

Run directly:  python tools/tests/test_l10n_registry.py -v
"""

import hashlib
import importlib.util
import inspect
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG_TOOL = ROOT / "tools" / "l10n_catalog.py"
INPUTS = ("data/LocalizationEnglish.lua", "data/LocalizationPacks.lua",
          "docs/localization/KEY_CONTEXT.json", "docs/localization/RELEASE_LANGUAGES.json",
          "core/Localization.lua")
OPEN = "-- NEXUS-L10N-REGISTRY BEGIN"
CLOSE = "-- NEXUS-L10N-REGISTRY END"
CHARGE = "readout.charge_counts"
CHARGE_FIELDS = ("banish", "reroll", "freeze")
# Independent oracle: the 28 current English meanings, in source order. The
# charge row is the only template.
CURRENT_KEYS = (
    "reason.save_in_progress", "reason.list_preparing", "reason.saved_data_reading",
    "reason.wait_three_choices", "reason.wait_pending_pick_count", CHARGE,
    "panel.button.my_builds", "panel.tooltip.open_my_builds",
    "panel.tooltip.my_builds_destination", "panel.button.assign_wishlist",
    "panel.tooltip.assignment_heading", "panel.tooltip.assignment_chooser",
    "panel.button.create_wishlist", "panel.tooltip.create_wishlist_heading",
    "panel.tooltip.create_wishlist_source", "panel.tooltip.create_wishlist_draft",
    "panel.heading.locked_targets", "panel.tooltip.locked_remaining",
    "panel.tooltip.locked_plan", "panel.tooltip.locked_acquire",
    "panel.tooltip.locked_placement", "panel.tooltip.locked_not_freeze",
    "panel.tooltip.locked_acquire_list", "panel.tooltip.open_wishlist_editor",
    "panel.heading.progress", "panel.heading.still_needed", "panel.heading.extra_copies",
    "panel.button.options",
)
CHARGE_DECLARATION = {"kind": "format", "fields": CHARGE_FIELDS, "slot": "count",
                      "resultLimit": 254}
EXPECTED_REGISTRY_CODES = (
    "registry-marker", "registry-structure", "registry-too-many", "registry-key",
    "registry-kind", "registry-field", "registry-placeholders", "registry-slot",
    "registry-limit", "undeclared-entry", "english-incomplete",
    "context-declaration-mismatch",
)
V1_SCOPE_LABEL = "IMPLEMENTED_DRAFT"


def load_catalog(path=CATALOG_TOOL):
    """Load tools/l10n_catalog.py from its file path without writing bytecode."""
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location("l10n_catalog_registry_under_test", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def current_inputs():
    """The exact physical bytes of the five registry inputs."""
    return [(ROOT / relative).read_bytes() for relative in INPUTS]


def block(*items, head="local DECLARATIONS = {", tail="}", newline="\n"):
    """A synthetic core/Localization.lua around one declaration block."""
    lines = ["-- synthetic core/Localization.lua", "local L = {}", OPEN, head]
    lines += ["    " + item for item in items]
    lines += [tail, CLOSE, "return L", ""]
    return newline.join(lines).encode("utf-8")


TEXT_ITEM = '["reason.alpha"] = {kind = "text"},'
CHARGE_ITEM = ('["readout.charge_counts"] = {fields = {"banish", "reroll", "freeze"},'
               ' kind = "format", slot = "count", resultLimit = 254},')


def replace_once(data, old, new):
    if data.count(old) != 1:
        raise AssertionError("expected exactly one %r" % old)
    return data.replace(old, new)


OPTIONS_LINE = b'    ["panel.button.options"] = "Options",'


def representations(data):
    """The canonical LF (Git blob) and the CRLF (checkout) representation of
    source bytes that are one of the two; a lone CR is refused."""
    lf = data.replace(b"\r\n", b"\n")
    if b"\r" in lf:
        raise AssertionError("lone CR")
    return {"lf": lf, "crlf": lf.replace(b"\n", b"\r\n")}


def without_line(data, line):
    """data without its one whole line equal to line, whichever line break
    (LF or CRLF) ends it; every other byte is kept. The line must occur
    exactly once, and the removal must change the bytes by that line and
    its break."""
    lines = data.split(b"\n")
    hits = [index for index, text in enumerate(lines)
            if (text[:-1] if text.endswith(b"\r") else text) == line]
    if len(hits) != 1:
        raise AssertionError("expected exactly one line %r, found %d" % (line, len(hits)))
    del lines[hits[0]]
    result = b"\n".join(lines)
    if result == data or len(data) - len(result) not in (len(line) + 1, len(line) + 2):
        raise AssertionError("the line was not removed exactly once")
    return result


class RegistryParserTests(unittest.TestCase):
    """S2: the nonexecuting parser of the delimited declaration block."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog()
        cls.parse = staticmethod(cls.catalog.parse_registry_declarations)
        cls.source = (ROOT / "core" / "Localization.lua").read_bytes()

    def refuse(self, source, error, code):
        with self.assertRaises(error) as raised:
            self.parse(source)
        self.assertEqual(raised.exception.code, code)
        return raised.exception

    def test_public_seam_and_codes(self):
        catalog = self.catalog
        self.assertEqual(catalog.REGISTRY_CODES, EXPECTED_REGISTRY_CODES)
        self.assertTrue(issubclass(catalog.CatalogRegistryError, ValueError))
        self.assertFalse(set(catalog.REGISTRY_CODES) & set(catalog.CODES))
        self.assertFalse(set(catalog.REGISTRY_CODES) & set(catalog.VALIDATION_CODES))
        self.assertEqual(list(inspect.signature(catalog.parse_registry_declarations).parameters),
                         ["source"])

    def test_actual_block_declares_exactly_the_28_current_keys(self):
        declarations = self.parse(self.source)
        self.assertEqual(list(declarations), list(CURRENT_KEYS))
        self.assertEqual(len(declarations), 28)
        self.assertEqual(declarations[CHARGE], CHARGE_DECLARATION)
        for key in CURRENT_KEYS:
            if key != CHARGE:
                self.assertEqual(declarations[key], {"kind": "text"}, key)
        english = self.catalog.parse_english((ROOT / INPUTS[0]).read_bytes())
        context = json.loads((ROOT / INPUTS[2]).read_text(encoding="utf-8"))
        self.assertEqual(set(declarations), set(english))
        self.assertEqual(set(declarations), {row["key"] for row in context["keys"]})
        self.assertEqual(len(context["keys"]), 28)

    def test_actual_marker_lines_are_the_s1_contract(self):
        lines = self.source.replace(b"\r\n", b"\n").split(b"\n")
        self.assertEqual(lines.count(OPEN.encode()), 1)
        self.assertEqual(lines.count(CLOSE.encode()), 1)
        self.assertEqual(self.source.count(b"NEXUS-L10N-REGISTRY"), 2)
        self.assertLess(lines.index(OPEN.encode()), lines.index(CLOSE.encode()))

    def test_lf_and_crlf_give_the_same_declarations(self):
        lf = self.source.replace(b"\r\n", b"\n")
        crlf = lf.replace(b"\n", b"\r\n")
        self.assertEqual(self.parse(lf), self.parse(crlf))
        self.assertEqual(self.parse(bytearray(lf)), self.parse(lf))
        self.assertEqual(self.parse(block(TEXT_ITEM, CHARGE_ITEM, newline="\r\n")),
                         {"reason.alpha": {"kind": "text"}, CHARGE: CHARGE_DECLARATION})

    def test_takes_bytes_only(self):
        for value in (self.source.decode("utf-8"), None, 1, Path("core/Localization.lua")):
            with self.subTest(value=type(value).__name__), self.assertRaises(TypeError):
                self.parse(value)

    def test_marker_contract_is_exact(self):
        body = block(TEXT_ITEM)
        error = self.catalog.CatalogRegistryError
        cases = {
            "absent": body.replace(OPEN.encode() + b"\n", b"").replace(CLOSE.encode() + b"\n", b""),
            "only open": body.replace(CLOSE.encode() + b"\n", b""),
            "only close": body.replace(OPEN.encode() + b"\n", b""),
            "reversed": body.replace(OPEN.encode(), b"@@").replace(CLOSE.encode(), OPEN.encode())
                            .replace(b"@@", CLOSE.encode()),
            "doubled": body + OPEN.encode() + b"\n" + CLOSE.encode() + b"\n",
            "stray token": body + b"-- see NEXUS-L10N-REGISTRY\n",
            "indented": body.replace(OPEN.encode(), b" " + OPEN.encode()),
            "trailing space": body.replace(CLOSE.encode(), CLOSE.encode() + b" "),
        }
        for name, source in cases.items():
            with self.subTest(case=name):
                self.refuse(source, error, "registry-marker")

    def test_expressions_and_executable_forms_are_refused(self):
        syntax = self.catalog.CatalogSyntaxError
        cases = (
            ('["reason.alpha"] = {kind = "te" .. "xt"},', "unexpected-token"),
            ('["reason.alpha"] = {kind = KIND},', "unexpected-token"),
            ('["reason.alpha"] = {kind = text()},', "unexpected-token"),
            ('["reason.alpha"] = {kind = os.execute("x")},', "unexpected-token"),
            ('["readout.charge_counts"] = {fields = {"banish", "reroll", "freeze"},'
             ' kind = "format", slot = "count", resultLimit = 256 - 2},', "unexpected-token"),
            ('["readout.charge_counts"] = {fields = {"banish", "reroll", "freeze"},'
             ' kind = "format", slot = "count", resultLimit = 0xFE},', "unexpected-token"),
            ('["readout.charge_counts"] = {fields = {"banish", "reroll", "freeze"},'
             ' kind = "format", slot = "count", resultLimit = MAX_TEXT_BYTES},', "unexpected-token"),
            ('["reason.alpha"] = {kind = nil},', "unexpected-token"),
            ('["reason.alpha"] = {kind = "text"}; ["reason.beta"] = {kind = "text"},',
             "unexpected-token"),
            ('[KEY] = {kind = "text"},', "unexpected-token"),
            ('["reason.alpha"] = function() end,', "unexpected-token"),
            ('["reason.alpha"] = {kind = "text"},\n    ["reason.alpha"] = {kind = "text"},',
             "duplicate-key"),
            ('["reason.alpha"] = {kind = "text", kind = "text"},', "duplicate-key"),
            ('["reason.alpha"] = {kind = "text", ["kind"] = "text"},', "duplicate-key"),
        )
        for item, code in cases:
            with self.subTest(item=item):
                self.refuse(block(item), syntax, code)
                self.assertIn(code, self.catalog.CODES)

    def test_block_shape_is_one_local_declarations_table(self):
        syntax = self.catalog.CatalogSyntaxError
        for head, tail, code in (
                ("DECLARATIONS = {", "}", "unexpected-token"),
                ("local Declarations = {", "}", "unexpected-token"),
                ("local DECLARATIONS = setmetatable({", "}, {})", "unexpected-token"),
                ("local DECLARATIONS = {", "} local x = 1", "trailing-content"),
                ("local DECLARATIONS = {", "};", "trailing-content")):
            with self.subTest(head=head, tail=tail):
                self.refuse(block(TEXT_ITEM, head=head, tail=tail), syntax, code)
        # A table cut off inside a value, at the end marker line.
        self.refuse(block('["reason.alpha"] =', tail=""), syntax, "unexpected-end")
        self.refuse(block(head="local DECLARATIONS = {"), self.catalog.CatalogRegistryError,
                    "registry-structure")
        self.refuse(block('{kind = "text"},'), self.catalog.CatalogRegistryError,
                    "registry-structure")
        self.refuse(b"\xff" + block(TEXT_ITEM), syntax, "not-utf8")
        self.refuse(block('["reason.alpha"] = {kind = "\\255"},'), syntax, "value-not-utf8")

    def test_malformed_declarations_are_refused(self):
        error = self.catalog.CatalogRegistryError
        charge = ('["readout.charge_counts"] = {fields = %s, kind = "format", slot = %s,'
                  ' resultLimit = %s},')
        good = ('{"banish", "reroll", "freeze"}', '"count"', "254")
        cases = (
            ('["Reason.Alpha"] = {kind = "text"},', "registry-key"),
            ('["reason"] = {kind = "text"},', "registry-key"),
            ('["reason.' + "a" * 58 + '"] = {kind = "text"},', "registry-key"),
            ('["reason.alpha"] = "text",', "registry-structure"),
            ('["reason.alpha"] = {"text"},', "registry-structure"),
            ('["reason.alpha"] = {},', "registry-structure"),
            ('["reason.alpha"] = {kind = "plural"},', "registry-kind"),
            ('["reason.alpha"] = {kind = true},', "registry-kind"),
            ('["reason.alpha"] = {kind = "text", fields = {"n"}},', "registry-field"),
            ('["reason.alpha"] = {kind = "text", content = "plain"},', "registry-field"),
            ('["reason.alpha"] = {kind = "text", resultLimit = 254},', "registry-field"),
            ('["readout.charge_counts"] = {kind = "format", slot = "count", resultLimit = 254},',
             "registry-field"),
            ('["readout.charge_counts"] = {fields = {"banish"}, kind = "format",'
             ' resultLimit = 254},', "registry-field"),
            ('["readout.charge_counts"] = {fields = {"banish"}, kind = "format", slot = "count"},',
             "registry-field"),
            ('["readout.charge_counts"] = {fields = {"banish"}, kind = "format", slot = "count",'
             ' resultLimit = 254, markup = true},', "registry-field"),
            (charge % ("{}", good[1], good[2]), "registry-placeholders"),
            (charge % ('{"banish", "banish"}', good[1], good[2]), "registry-placeholders"),
            (charge % ('{"Banish"}', good[1], good[2]), "registry-placeholders"),
            (charge % ('{"1st"}', good[1], good[2]), "registry-placeholders"),
            (charge % ('{"ban ish"}', good[1], good[2]), "registry-placeholders"),
            (charge % ('{"banish", 7}', good[1], good[2]), "registry-placeholders"),
            (charge % ('{{"banish"}}', good[1], good[2]), "registry-placeholders"),
            (charge % ('{banish = true}', good[1], good[2]), "registry-placeholders"),
            (charge % ('"banish"', good[1], good[2]), "registry-placeholders"),
            (charge % (good[0], '"number"', good[2]), "registry-slot"),
            (charge % (good[0], "true", good[2]), "registry-slot"),
            (charge % (good[0], good[1], "253"), "registry-limit"),
            (charge % (good[0], good[1], "255"), "registry-limit"),
            (charge % (good[0], good[1], "256"), "registry-limit"),
            (charge % (good[0], good[1], '"254"'), "registry-limit"),
            (charge % (good[0], good[1], "true"), "registry-limit"),
        )
        for item, code in cases:
            with self.subTest(item=item):
                raised = self.refuse(block(item), error, code)
                self.assertIn(raised.code, self.catalog.REGISTRY_CODES)
        self.assertEqual(self.parse(block(charge % good)), {CHARGE: CHARGE_DECLARATION})

    def test_declaration_count_is_bounded_by_the_base_limit(self):
        items = ['["reason.k%02d"] = {kind = "text"},' % index for index in range(64)]
        self.assertEqual(len(self.parse(block(*items))), 64)
        items.append('["reason.k64"] = {kind = "text"},')
        self.refuse(block(*items), self.catalog.CatalogRegistryError, "registry-too-many")

    def test_comments_inside_the_block_are_whitespace(self):
        source = block("-- a comment", TEXT_ITEM, "--[[ long ]]", CHARGE_ITEM)
        self.assertEqual(list(self.parse(source)), ["reason.alpha", CHARGE])


class RegistryApiTests(unittest.TestCase):
    """S5: the five-input registry-bound API, distinct from the four-input API."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog()
        cls.inputs = current_inputs()

    def verdict(self, *data):
        catalog = self.catalog
        try:
            catalog.validate_registry_catalog_data(*data)
        except (catalog.CatalogSyntaxError, catalog.CatalogValidationError,
                catalog.CatalogRegistryError) as error:
            return (error.code, getattr(error, "key", None))
        return ("valid", None)

    def with_input(self, index, value):
        data = list(self.inputs)
        data[index] = value
        return data

    def test_signatures_keep_the_four_input_api_apart(self):
        catalog = self.catalog
        self.assertEqual(list(inspect.signature(catalog.validate_catalog_data).parameters),
                         ["english_source", "packs_source", "key_context_json", "release_json"])
        self.assertEqual(list(inspect.signature(catalog.catalog_report).parameters),
                         ["english_source", "packs_source", "key_context_json", "release_json"])
        five = ["english_source", "packs_source", "key_context_json", "release_json",
                "localization_source"]
        self.assertEqual(list(inspect.signature(catalog.validate_registry_catalog_data).parameters),
                         five)
        self.assertEqual(list(inspect.signature(catalog.registry_catalog_report).parameters), five)

    def test_current_inputs_are_valid_and_return_the_declarations(self):
        result = self.catalog.validate_registry_catalog_data(*self.inputs)
        self.assertEqual(sorted(result), ["declarations", "english", "keyContext", "packs",
                                          "release"])
        self.assertEqual(list(result["declarations"]), list(CURRENT_KEYS))
        self.assertEqual(set(result["english"]), set(CURRENT_KEYS))
        v1 = self.catalog.validate_catalog_data(*self.inputs[:4])
        for name in ("english", "packs", "keyContext", "release"):
            self.assertEqual(result[name], v1[name], name)

    def test_every_argument_must_be_bytes(self):
        names = ["english_source", "packs_source", "key_context_json", "release_json",
                 "localization_source"]
        for index, name in enumerate(names):
            with self.subTest(argument=name):
                with self.assertRaises(TypeError) as raised:
                    self.catalog.validate_registry_catalog_data(
                        *self.with_input(index, self.inputs[index].decode("utf-8")))
                self.assertIn(name, str(raised.exception))

    def test_undeclared_english_entry_is_refused(self):
        # R-P1 (C14): valid text and key, but no declaration.
        english = replace_once(self.inputs[0], b"Nexus.LocalizationEnglish = {",
                               b'Nexus.LocalizationEnglish = {\r\n    ["parity.undeclared"] = '
                               b'"Undeclared parity text",')
        self.assertEqual(self.verdict(*self.with_input(0, english)),
                         ("undeclared-entry", "parity.undeclared"))
        # The four-input API knows no declaration: the same bytes fail its
        # key-context row check instead.
        with self.assertRaises(self.catalog.CatalogValidationError) as raised:
            self.catalog.validate_catalog_data(*self.with_input(0, english)[:4])
        self.assertEqual(raised.exception.code, "context-key-mismatch")

    def test_declared_key_without_english_is_refused(self):
        # R-P3 (C14), in both line-break representations of the English base:
        # the unedited bytes pass, and removing exactly the Options row is refused.
        for name, data in representations(self.inputs[0]).items():
            with self.subTest(representation=name):
                english = without_line(data, OPTIONS_LINE)
                parsed = self.catalog.parse_english(english)
                self.assertEqual(set(self.catalog.parse_english(data)) - set(parsed),
                                 {"panel.button.options"})
                self.assertEqual(len(parsed), 27)
                self.assertEqual(self.verdict(*self.with_input(0, data)), ("valid", None))
                self.assertEqual(self.verdict(*self.with_input(0, english)),
                                 ("english-incomplete", "panel.button.options"))

    def test_invalid_english_for_a_declared_key_is_refused_as_invalid(self):
        english = replace_once(self.inputs[0], b'"Options"', b'"Opt|ions"')
        self.assertEqual(self.verdict(*self.with_input(0, english)),
                         ("invalid-text", "panel.button.options"))
        english = replace_once(self.inputs[0], b'"B:{banish} R:{reroll} F:{freeze}"',
                               b'"B:{banish} R:{reroll}"')
        self.assertEqual(self.verdict(*self.with_input(0, english)), ("invalid-template", CHARGE))

    def test_key_context_must_equal_its_declaration(self):
        # R-P2 (C14): kind, placeholder names in order and type, and limit.
        context = self.inputs[2]
        placeholders = (b'{"name": "banish", "type": "count"},\n'
                        b'        {"name": "reroll", "type": "count"},\n'
                        b'        {"name": "freeze", "type": "count"}')
        self.assertIn(placeholders, context.replace(b"\r\n", b"\n"))
        lf = context.replace(b"\r\n", b"\n")
        cases = {
            "kind": replace_once(lf, b'"kind": "format",', b'"kind": "text",'),
            "text kind": replace_once(lf, b'"key": "panel.button.options",\n      "kind": "text",',
                                      b'"key": "panel.button.options",\n      "kind": "format",'),
            "order": replace_once(lf, placeholders, placeholders.replace(b"banish", b"@")
                                  .replace(b"reroll", b"banish").replace(b"@", b"reroll")),
            "slot type": replace_once(lf, b'{"name": "freeze", "type": "count"}',
                                      b'{"name": "freeze", "type": "number"}'),
            "missing slot": replace_once(lf, b',\n        {"name": "freeze", "type": "count"}', b""),
            "limit": replace_once(lf, b'"resultLimitBytes": 254,', b'"resultLimitBytes": 253,'),
        }
        keys = {"text kind": "panel.button.options"}
        for name, data in cases.items():
            with self.subTest(case=name):
                self.assertEqual(self.verdict(*self.with_input(2, data)),
                                 ("context-declaration-mismatch", keys.get(name, CHARGE)))

    def test_parsed_declarations_govern_not_the_four_input_constants(self):
        source = self.inputs[4]
        old = b'{fields = {"banish", "reroll", "freeze"},'
        # A different but valid declared schema: the current English template
        # no longer fits it, while the four-input API still accepts the bytes.
        changed = replace_once(source, old, b'{fields = {"banish", "reroll", "frost"},')
        self.assertEqual(self.verdict(*self.with_input(4, changed)), ("invalid-template", CHARGE))
        self.catalog.validate_catalog_data(*self.inputs[:4])
        # Declaring the charge row as static text makes its English a valid
        # static text, so the key-context row then disagrees with the declaration.
        static = re.sub(rb'\["readout\.charge_counts"\] = \{[^}]*\},\r?\n[^\n]*\},',
                        b'["readout.charge_counts"] = {kind = "text"},', source, count=1)
        self.assertNotEqual(static, source)
        self.assertEqual(self.verdict(*self.with_input(4, static)),
                         ("context-declaration-mismatch", CHARGE))
        # Without a declaration block nothing is admitted against a registry.
        start, end = source.index(OPEN.encode()), source.index(CLOSE.encode()) + len(CLOSE)
        self.assertEqual(self.verdict(*self.with_input(4, source[:start] + source[end:])),
                         ("registry-marker", None))

    def test_four_input_constants_still_agree_with_the_current_declarations(self):
        # A compatibility check of the historical four-input API against the
        # current authority, not a second authority: v2 never reads them.
        declarations = self.catalog.parse_registry_declarations(self.inputs[4])
        formats = {key: (tuple(value["fields"]), value["resultLimit"])
                   for key, value in declarations.items() if value["kind"] == "format"}
        self.assertEqual(formats, {key: (tuple(fields), self.catalog._FORMAT_LIMITS[key])
                                   for key, fields in self.catalog._FORMAT_FIELDS.items()})

    def test_registry_checks_follow_the_existing_english_checks(self):
        # An invalid key is still the four-input code; an undeclared valid key
        # is the registry code; an empty base stays english-empty.
        english = replace_once(self.inputs[0], b"Nexus.LocalizationEnglish = {",
                               b'Nexus.LocalizationEnglish = {\r\n    ["Bad Key"] = "Bad",')
        self.assertEqual(self.verdict(*self.with_input(0, english)), ("invalid-key", "Bad Key"))
        empty = b"Nexus = Nexus or {}\nNexus.LocalizationEnglish = {}\n"
        self.assertEqual(self.verdict(*self.with_input(0, empty)), ("english-empty", None))


class RegistryReportTests(unittest.TestCase):
    """S5: report schemaVersion 2 beside the unchanged report schemaVersion 1."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog()
        cls.inputs = current_inputs()
        cls.v1 = cls.catalog.catalog_report(*cls.inputs[:4])
        cls.v2 = cls.catalog.registry_catalog_report(*cls.inputs)

    def test_v1_report_is_unchanged(self):
        self.assertEqual((self.v1["schemaVersion"], self.v1["fullValidation"]), (1, V1_SCOPE_LABEL))
        self.assertEqual(self.v1["validationScope"], self.catalog.NOTICE["validationScope"])
        self.assertEqual(len(self.v1["inputs"]), 4)
        self.assertNotIn("registry", self.v1)

    def test_v2_report_header_inputs_and_registry_section(self):
        v2 = self.v2
        self.assertEqual((v2["schema"], v2["schemaVersion"], v2["tool"]),
                         ("nexus.l10n.coverage_report", 2, "tools/l10n_catalog.py"))
        self.assertEqual(self.catalog.REGISTRY_REPORT_SCHEMA_VERSION, 2)
        self.assertEqual(v2["validationScope"], self.catalog.REGISTRY_SCOPE)
        self.assertNotEqual(v2["validationScope"], self.v1["validationScope"])
        self.assertIn("not whole #147", v2["validationScope"])
        self.assertEqual([(row["name"], row["source"]) for row in v2["inputs"]],
                         [("english", INPUTS[0]), ("packs", INPUTS[1]), ("keyContext", INPUTS[2]),
                          ("release", INPUTS[3]), ("localization", INPUTS[4])])
        for row, data in zip(v2["inputs"], self.inputs):
            self.assertEqual((row["sha256"], row["byteLength"]),
                             (hashlib.sha256(data).hexdigest(), len(data)))
        registry = v2["registry"]
        self.assertEqual(registry["source"], "core/Localization.lua")
        self.assertEqual(registry["markers"], {"open": OPEN, "close": CLOSE})
        self.assertEqual((registry["declarationCount"], registry["englishKeys"],
                          registry["keyContextRows"]), (28, 28, 28))
        self.assertEqual([row["key"] for row in registry["declarations"]], list(CURRENT_KEYS))
        charge = [row for row in registry["declarations"] if row["key"] == CHARGE][0]
        self.assertEqual(charge, {"key": CHARGE, "kind": "format",
                                  "placeholders": [{"name": name, "type": "count"}
                                                   for name in CHARGE_FIELDS],
                                  "resultLimitBytes": 254})
        self.assertEqual(registry["nonexecution"],
                         "declarations are parsed from the supplied bytes; no Lua is executed")

    def test_v2_report_derives_the_same_coverage(self):
        skip = {"schemaVersion", "validationScope", "inputs", "registry"}
        self.assertEqual({k: v for k, v in self.v2.items() if k not in skip},
                         {k: v for k, v in self.v1.items() if k not in skip})
        self.assertEqual(self.v2["inputs"][:4], self.v1["inputs"])

    def test_invalid_registry_input_gets_no_report(self):
        # In both line-break representations: the unedited English gets a
        # report; without exactly the Options row it gets none.
        for name, data in representations(self.inputs[0]).items():
            with self.subTest(representation=name):
                english = without_line(data, OPTIONS_LINE)
                self.assertNotIn(b'"panel.button.options"', english)
                self.assertEqual(self.catalog.registry_catalog_report(data, *self.inputs[1:])
                                 ["registry"]["englishKeys"], 28)
                with self.assertRaises(self.catalog.CatalogRegistryError) as raised:
                    self.catalog.registry_catalog_report(english, *self.inputs[1:])
                self.assertEqual((raised.exception.code, raised.exception.key),
                                 ("english-incomplete", "panel.button.options"))

    def test_line_removal_is_exact_once_in_both_representations(self):
        for name, data in representations(self.inputs[0]).items():
            with self.subTest(representation=name):
                removed = without_line(data, OPTIONS_LINE)
                self.assertEqual(len(data) - len(removed),
                                 len(OPTIONS_LINE) + (2 if name == "crlf" else 1))
                with self.assertRaises(AssertionError):
                    without_line(removed, OPTIONS_LINE)
                with self.assertRaises(AssertionError):
                    without_line(data + OPTIONS_LINE + b"\n", OPTIONS_LINE)
                with self.assertRaises(AssertionError):
                    without_line(data, OPTIONS_LINE + b" ")


class EnumCrossCheckTests(unittest.TestCase):
    """F7: the tool's fixed product list equals the runtime language enum."""

    def test_product_roles_equal_the_default_profile_enum(self):
        catalog = load_catalog()
        profile = (ROOT / "data" / "DefaultProfile.lua").read_text(encoding="utf-8")
        found = re.findall(r'^\s*ids = \{([^}]*)\},\s*$', profile, re.M)
        self.assertEqual(len(found), 1)
        ids = re.findall(r'"([A-Za-z]+)"', found[0])
        self.assertEqual([product for product, _ in catalog._PRODUCT_ROLES], ids)
        release = json.loads((ROOT / INPUTS[3]).read_text(encoding="utf-8"))
        self.assertEqual([product["productId"] for product in release["products"]], ids)
        self.assertEqual(ids, ["enUS", "frFR", "deDE", "esES", "plPL", "ptBR", "ruRU"])


class RegistryMetadataTests(unittest.TestCase):
    """Validator-status metadata for the registry-bound API (new members only)."""

    def test_release_languages_registry_validator(self):
        release = json.loads((ROOT / INPUTS[3]).read_text(encoding="utf-8"))
        self.assertEqual(release["validator"], {"path": "tools/l10n_catalog.py",
                                                "status": "IMPLEMENTED_DRAFT_REVIEW_PENDING"})
        record = release["registryValidator"]
        self.assertEqual(record["path"], "tools/l10n_catalog.py")
        self.assertEqual(record["status"], "IMPLEMENTED_DRAFT_REVIEW_PENDING")
        self.assertEqual(record["api"], ["parse_registry_declarations",
                                         "validate_registry_catalog_data",
                                         "registry_catalog_report"])
        self.assertEqual(record["reportSchemaVersion"], 2)
        self.assertEqual(record["inputs"], list(INPUTS))
        self.assertEqual(record["declarationSource"], {"path": "core/Localization.lua",
                                                       "open": OPEN, "close": CLOSE})
        self.assertEqual(record["requiredCiRegistration"], "tools/tests/test_l10n_registry.py")
        self.assertEqual(record["nativeAcceptance"], "NOT_RUN")
        self.assertIn("schemaVersion 1", record["fourInputApi"])
        self.assertIn("not registry validation", record["fourInputApi"])

    def test_key_context_registry_binding(self):
        context = json.loads((ROOT / INPUTS[2]).read_text(encoding="utf-8"))
        self.assertEqual(context["authority"], "core/Localization.lua")
        binding = context["registryBinding"]
        self.assertEqual(binding["declarations"], {"path": "core/Localization.lua",
                                                   "open": OPEN, "close": CLOSE})
        self.assertEqual(binding["declaredKeys"], 28)
        self.assertEqual(binding["checkedFields"], ["kind", "placeholders", "resultLimitBytes"])
        self.assertEqual(binding["mismatchCode"], "context-declaration-mismatch")
        self.assertEqual(binding["status"], "IMPLEMENTED_DRAFT_REVIEW_PENDING")


class RegistryCommandLineTests(unittest.TestCase):
    """--registry reads core/Localization.lua as a sixth fixed input and
    prints report v2; without it the command line is unchanged."""

    def run_cli(self, *args):
        return subprocess.run([sys.executable, "-B", str(CATALOG_TOOL), *[str(a) for a in args]],
                              capture_output=True, cwd=str(ROOT))

    def test_registry_mode_on_the_repository_root(self):
        run = self.run_cli("--registry")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stderr, b"")
        record = json.loads(run.stdout)
        self.assertEqual(record["registryBinding"], "requested")
        self.assertEqual(record["report"]["schemaVersion"], 2)
        self.assertEqual(record["report"]["registry"]["declarationCount"], 28)
        self.assertEqual([row["source"] for row in record["report"]["inputs"]], list(INPUTS))
        self.assertEqual(record["technicalCatalog"]["englishKeys"], 28)
        strict = self.run_cli("--registry", "--require-complete")
        self.assertEqual(strict.returncode, 1)
        default = json.loads(self.run_cli().stdout)
        self.assertNotIn("registryBinding", default)
        self.assertEqual(default["report"]["schemaVersion"], 1)
        self.assertEqual(len(default["report"]["inputs"]), 4)

    def test_registry_mode_arguments_and_missing_source(self):
        run = self.run_cli("--registry", "--registry")
        self.assertEqual(run.returncode, 2)
        self.assertEqual(json.loads(run.stderr)["code"], "argument-duplicate")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for relative in INPUTS[:4] + ("Nexus.toc",):
                target = root.joinpath(*relative.split("/"))
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(str(ROOT / relative), str(target))
            self.assertEqual(self.run_cli("--root", root).returncode, 0)
            run = self.run_cli("--root", root, "--registry")
            self.assertEqual(run.returncode, 2)
            error = json.loads(run.stderr)
            self.assertEqual((error["code"], error["subject"]), ("input-missing",
                                                                 "core/Localization.lua"))
            target = root / "core" / "Localization.lua"
            target.parent.mkdir()
            target.write_bytes(replace_once(current_inputs()[4], b'resultLimit = 254',
                                            b'resultLimit = 253'))
            run = self.run_cli("--root", root, "--registry")
            self.assertEqual(run.returncode, 2)
            error = json.loads(run.stderr)
            self.assertEqual((error["errorClass"], error["code"], error["key"]),
                             ("CatalogRegistryError", "registry-limit", CHARGE))
            self.assertEqual(sorted(os.listdir(str(root))), ["Nexus.toc", "core", "data", "docs"])


# S6 (Refs #147): opt-in static diagnostics. Synthetic inputs are built in
# memory from the real bytes; the synthetic retired and never-known keys
# below exist only here, never in a shipped input.
RETIRED = "reason.retired_example"
NEVER_KNOWN = "reason.never_known"
EXPECTED_DIAGNOSTIC_CODES = ("retired-structure", "retired-key", "retired-duplicate",
                             "retired-order", "retired-active")
FIRST_PACK_TEXT = b"[\"reason.save_in_progress\"] = \"L'enregistrement"
FRENCH_CHARGE = b'"Ban:{banish} Rel:{reroll} Gel:{freeze}"'


def add_entries(packs, pack_id, *lines):
    """packs with lines inserted as the first entries of pack_id, in the line
    break of the source."""
    newline = b"\r\n" if b"\r\n" in packs else b"\n"
    pattern = re.compile(rb"(\n    " + pack_id.encode() + rb" = \{\r?\n        name = "
                         rb"\"[^\"\r\n]*\",\r?\n        entries = \{)")
    if len(pattern.findall(packs)) != 1:
        raise AssertionError("expected exactly one pack %s" % pack_id)
    added = b"".join(newline + b"            " + line for line in lines)
    return pattern.sub(lambda match: match.group(1) + added, packs, count=1)


def with_retired(context, keys):
    """KEY_CONTEXT bytes with retiredKeys.keys replaced (None removes the
    whole member)."""
    document = json.loads(context.decode("utf-8"))
    if keys is None:
        del document["retiredKeys"]
    else:
        document["retiredKeys"]["keys"] = keys
    return json.dumps(document, ensure_ascii=False, indent=2).encode("utf-8")


def with_declaration(release, product_id, key, text, decision="translated"):
    """RELEASE_LANGUAGES bytes with one synthetic, structurally qualified
    entry-review declaration. It is not language or rights evidence."""
    document = json.loads(release.decode("utf-8"))
    document["entryReview"]["declarations"].append({
        "productId": product_id, "key": key,
        "translatedTextSha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "reviewer": "Synthetic Fixture Reviewer", "decision": decision,
        "evidenceReference": "https://example.invalid/synthetic", "status": "declared"})
    return json.dumps(document, ensure_ascii=False, indent=2).encode("utf-8")


def multi_error_inputs(inputs):
    """D1: one structurally valid catalog whose frFR pack has two invalid
    active entries, a known retired entry and a never-known orphan, and whose
    deDE pack has a malformed key."""
    english, packs, context, release, localization = inputs
    packs = replace_once(packs, FIRST_PACK_TEXT, FIRST_PACK_TEXT + b"|")
    packs = replace_once(packs, FRENCH_CHARGE, b'"Ban:{banish} Rel:{reroll}"')
    packs = add_entries(packs, "frFR", b'["%s"] = "Retired text",' % RETIRED.encode(),
                        b'["%s"] = "Unknown text",' % NEVER_KNOWN.encode())
    packs = add_entries(packs, "deDE", b'["Bad Key"] = "Schlecht",')
    return [english, packs, with_retired(context, [RETIRED]), release, localization]


class DiagnosticTests(unittest.TestCase):
    """S6: the opt-in, read-only diagnostic receipt beside the unchanged
    strict gate."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog()
        cls.inputs = current_inputs()
        cls.diagnose = staticmethod(cls.catalog.registry_catalog_diagnostics)
        cls.strict_report = cls.catalog.registry_catalog_report(*cls.inputs)

    def strict_error(self, data):
        catalog = self.catalog
        with self.assertRaises((catalog.CatalogSyntaxError, catalog.CatalogValidationError,
                                catalog.CatalogRegistryError,
                                catalog.CatalogEvidenceError)) as raised:
            catalog.registry_catalog_report(*data)
        error = raised.exception
        return type(error).__name__, error.code, getattr(error, "key", None)

    def assert_incomplete(self, receipt, error_class, code):
        self.assertIs(receipt["valid"], False)
        self.assertEqual(receipt["collection"]["state"], "INCOMPLETE")
        boundary = receipt["collection"]["boundary"]
        self.assertEqual((boundary["errorClass"], boundary["code"]), (error_class, code))
        self.assertEqual(receipt["entryProblems"], [])
        self.assertIsNone(receipt["coverage"])
        self.assertIs(receipt["completeness"]["established"], False)

    def test_d1_multi_error_classes_and_unchanged_strict_failure(self):
        data = multi_error_inputs(self.inputs)
        # The strict gate keeps its first-error contract: the retired key is
        # still an orphan-entry there.
        self.assertEqual(self.strict_error(data),
                         ("CatalogValidationError", "orphan-entry", RETIRED))
        receipt = self.diagnose(*data)
        self.assertIs(receipt["valid"], False)
        self.assertEqual(receipt["strictVerdict"]["result"], "invalid")
        self.assertEqual((receipt["strictVerdict"]["code"], receipt["strictVerdict"]["key"]),
                         ("orphan-entry", RETIRED))
        self.assertEqual(receipt["collection"]["state"], "COMPLETE")
        self.assertIsNone(receipt["collection"]["boundary"])
        self.assertEqual(receipt["entryProblems"], [
            {"productId": "frFR", "key": CHARGE, "category": "invalid", "code": "invalid-template"},
            {"productId": "frFR", "key": NEVER_KNOWN, "category": "orphan", "code": "orphan-entry"},
            {"productId": "frFR", "key": RETIRED, "category": "obsolete", "code": "orphan-entry"},
            {"productId": "frFR", "key": "reason.save_in_progress", "category": "invalid",
             "code": "invalid-text"},
            {"productId": "deDE", "key": "Bad Key", "category": "orphan", "code": "invalid-key"},
        ])
        self.assertEqual(receipt["problemCounts"], {"invalid": 2, "obsolete": 1, "orphan": 2})
        self.assertEqual(receipt["retiredKeys"], [RETIRED])
        self.assertEqual(receipt, self.diagnose(*data))
        json.dumps(receipt, sort_keys=True).encode("ascii")

    def test_d1_input_bindings_are_the_exact_supplied_bytes(self):
        data = multi_error_inputs(self.inputs)
        receipt = self.diagnose(*data)
        self.assertEqual([(row["name"], row["source"]) for row in receipt["inputs"]],
                         [("english", INPUTS[0]), ("packs", INPUTS[1]), ("keyContext", INPUTS[2]),
                          ("release", INPUTS[3]), ("localization", INPUTS[4])])
        for row, value in zip(receipt["inputs"], data):
            self.assertEqual((row["sha256"], row["byteLength"]),
                             (hashlib.sha256(value).hexdigest(), len(value)))

    def test_d2_real_retired_list_is_empty_and_checked(self):
        context = json.loads((ROOT / INPUTS[2]).read_text(encoding="utf-8"))
        self.assertEqual(context["retiredKeys"]["keys"], [])
        receipt = self.diagnose(*self.inputs)
        self.assertEqual(receipt["retiredKeys"], [])
        self.assertEqual(self.catalog.DIAGNOSTIC_CODES, EXPECTED_DIAGNOSTIC_CODES)
        for codes in (self.catalog.CODES, self.catalog.VALIDATION_CODES,
                      self.catalog.EVIDENCE_CODES, self.catalog.REGISTRY_CODES,
                      self.catalog.CLI_CODES):
            self.assertFalse(set(codes) & set(EXPECTED_DIAGNOSTIC_CODES))

    def test_d2_malformed_retired_lists_are_refused(self):
        cases = (
            (None, "retired-structure", None),
            ("reason.retired_example", "retired-structure", None),
            ([RETIRED, 7], "retired-structure", None),
            (["Bad Key"], "retired-key", "Bad Key"),
            (["reason"], "retired-key", "reason"),
            ([RETIRED, RETIRED], "retired-duplicate", RETIRED),
            (["reason.zeta", "reason.alpha"], "retired-order", None),
            (["panel.button.options"], "retired-active", "panel.button.options"),
            ([CHARGE], "retired-active", CHARGE),
        )
        for keys, code, key in cases:
            with self.subTest(keys=keys):
                data = self.with_input(2, with_retired(self.inputs[2], keys))
                # The strict gate does not read retired metadata: unchanged valid.
                self.catalog.registry_catalog_report(*data)
                receipt = self.diagnose(*data)
                self.assert_incomplete(receipt, "CatalogDiagnosticError", code)
                self.assertEqual(receipt["collection"]["boundary"].get("key"), key)
                self.assertEqual(receipt["strictVerdict"], {"result": "valid"})
                self.assertIsNone(receipt["retiredKeys"])

    def test_d2_retired_and_never_known_entries_stay_distinct(self):
        packs = add_entries(self.inputs[1], "ruRU", b'["%s"] = "x",' % RETIRED.encode(),
                            b'["%s"] = "y",' % NEVER_KNOWN.encode())
        for retired, categories in (([], ("orphan", "orphan")),
                                    ([RETIRED], ("obsolete", "orphan")),
                                    ([NEVER_KNOWN, RETIRED], ("obsolete", "obsolete"))):
            with self.subTest(retired=retired):
                receipt = self.diagnose(self.inputs[0], packs,
                                        with_retired(self.inputs[2], retired), *self.inputs[3:])
                rows = {row["key"]: row["category"] for row in receipt["entryProblems"]}
                self.assertEqual((rows[RETIRED], rows[NEVER_KNOWN]), categories)
                obsolete = receipt["coverage"]["products"][-1]["keys"]["obsolete"]
                self.assertEqual(obsolete, sorted(key for key in (RETIRED, NEVER_KNOWN)
                                                  if key in retired))

    def test_d3_active_keys_partition_once_and_bad_extras_do_not_count(self):
        data = multi_error_inputs(self.inputs)
        # A synthetic qualified declaration on an invalid entry must not make
        # it reviewed.
        text = "L'enregistrement|"
        packs = self.catalog.parse_packs(data[1])
        bad = packs["frFR"]["entries"]["reason.save_in_progress"]
        self.assertTrue(bad.startswith(text))
        data[3] = with_declaration(data[3], "frFR", "reason.save_in_progress", bad)
        receipt = self.diagnose(*data)
        self.assertEqual(receipt["collection"]["state"], "COMPLETE")
        rows = {row["productId"]: row for row in receipt["coverage"]["products"]}
        french = rows["frFR"]
        self.assertEqual(french["denominator"], 28)
        self.assertEqual(french["keys"]["invalid"], [CHARGE, "reason.save_in_progress"])
        self.assertEqual(french["keys"]["missing"], ["panel.button.options"])
        self.assertEqual(french["keys"]["obsolete"], [RETIRED])
        self.assertEqual(french["counts"]["translated_and_reviewed"], 0)
        self.assertEqual(french["counts"]["draft_unreviewed"], 25)
        self.assertEqual(french["reconciliation"], {"denominator": 28, "inDenominatorTotal": 28})
        for row in receipt["coverage"]["products"]:
            seen = [key for category in self.catalog.ENTRY_CATEGORIES[:6]
                    for key in row["keys"][category]]
            self.assertEqual(sorted(seen), sorted(CURRENT_KEYS), row["productId"])
            self.assertNotIn(NEVER_KNOWN, row["keys"]["obsolete"])
            self.assertNotIn("Bad Key", sum(row["keys"].values(), []))
        self.assertEqual(rows["deDE"]["counts"], self.strict_report["products"][1]["counts"])
        self.assertEqual(receipt["coverage"]["denominator"]["englishKeys"], 28)
        self.assertEqual(receipt["coverage"]["completeness"]["state"], "INCOMPLETE")
        codes = {reason["code"] for reason in receipt["coverage"]["completeness"]["reasons"]}
        self.assertTrue({"entries-invalid", "entries-obsolete"} <= codes)
        self.assertIs(receipt["completeness"]["established"], False)
        self.assertNotIn("100%", json.dumps(receipt))

    def test_d4_valid_partial_input_keeps_the_strict_report(self):
        receipt = self.diagnose(*self.inputs)
        self.assertIs(receipt["valid"], True)
        self.assertEqual(receipt["strictVerdict"], {"result": "valid"})
        self.assertEqual(receipt["collection"], {"state": "COMPLETE", "boundary": None,
                                                 "rule": receipt["collection"]["rule"]})
        self.assertEqual(receipt["entryProblems"], [])
        self.assertEqual(receipt["problemCounts"], {"invalid": 0, "obsolete": 0, "orphan": 0})
        self.assertEqual(receipt["coverage"], self.strict_report)
        self.assertIs(receipt["completeness"]["established"], False)
        self.assertEqual(receipt["gate"], "NOT_A_GATE")
        # A synthetic declaration and an English-identical entry keep their
        # existing categories; fallback English is never an entry.
        english = self.catalog.parse_english(self.inputs[0])
        packs = replace_once(self.inputs[1], b'"Mes builds"',
                             b'"%s"' % english["panel.button.my_builds"].encode("utf-8"))
        release = with_declaration(self.inputs[3], "deDE", "panel.button.my_builds",
                                   "Meine Builds")
        data = [self.inputs[0], packs, self.inputs[2], release, self.inputs[4]]
        receipt = self.diagnose(*data)
        report = self.catalog.registry_catalog_report(*data)
        self.assertEqual(receipt["coverage"], report)
        rows = {row["productId"]: row["counts"] for row in report["products"]}
        self.assertEqual(rows["frFR"]["deliberate_english_placeholder"], 1)
        self.assertEqual(rows["deDE"]["translated_and_reviewed"], 1)
        self.assertEqual(rows["frFR"]["missing"], 1)
        self.assertEqual(report["completeness"]["state"], "INCOMPLETE")

    def test_d5_strict_apis_codes_and_inputs_are_unchanged(self):
        catalog = self.catalog
        self.assertEqual(list(inspect.signature(catalog.registry_catalog_diagnostics).parameters),
                         ["english_source", "packs_source", "key_context_json", "release_json",
                          "localization_source"])
        self.assertEqual(catalog.REGISTRY_CODES, EXPECTED_REGISTRY_CODES)
        data = multi_error_inputs(self.inputs)
        with self.assertRaises(catalog.CatalogValidationError) as raised:
            catalog.validate_registry_catalog_data(*data)
        self.assertEqual((raised.exception.code, raised.exception.key), ("orphan-entry", RETIRED))
        with self.assertRaises(catalog.CatalogValidationError) as raised:
            catalog.catalog_report(*data[:4])
        self.assertEqual((raised.exception.code, raised.exception.key), ("orphan-entry", RETIRED))
        mutable = [bytearray(value) for value in data]
        before = [hashlib.sha256(value).hexdigest() for value in mutable]
        self.assertEqual(self.diagnose(*mutable), self.diagnose(*data))
        self.assertEqual([hashlib.sha256(value).hexdigest() for value in mutable], before)
        names = ["english_source", "packs_source", "key_context_json", "release_json",
                 "localization_source"]
        for index, name in enumerate(names):
            with self.subTest(argument=name):
                changed = list(self.inputs)
                changed[index] = changed[index].decode("utf-8")
                with self.assertRaises(TypeError) as raised:
                    self.diagnose(*changed)
                self.assertIn(name, str(raised.exception))

    def test_d6_untrustworthy_structure_is_an_explicit_incomplete_collection(self):
        english, packs, context, release, localization = self.inputs
        declaration = b'["panel.button.options"] = {kind = "text"},'
        self.assertEqual(localization.count(declaration), 1)
        cases = {
            "pack syntax": (1, packs + b"x"),
            "duplicate pack key": (1, add_entries(packs, "frFR",
                                                  b'["panel.button.my_builds"] = "Doppel",')),
            "duplicate declaration": (4, localization.replace(declaration,
                                                              declaration + b" " + declaration)),
            "json": (2, context[:-3]),
            "unknown pack": (1, packs.replace(b"    frFR = {", b"    xxXX = {", 1)),
            "invalid English": (0, replace_once(english, b'"Options"', b'"Opt|ions"')),
            "invalid autonym": (1, replace_once(packs, b'name = "Fran\xc3\xa7ais"',
                                                b'name = "Fr|an\xc3\xa7ais"')),
        }
        for name, (index, value) in cases.items():
            with self.subTest(case=name):
                data = self.with_input(index, value)
                error_class, code, key = self.strict_error(data)
                receipt = self.diagnose(*data)
                self.assert_incomplete(receipt, error_class, code)
                self.assertEqual(receipt["strictVerdict"]["code"], code)
                self.assertEqual(receipt["collection"]["boundary"].get("key"), key)
        # Entry errors next to an untrustworthy pack set are not collected,
        # so no partial list is reported as complete.
        mixed = multi_error_inputs(self.inputs)
        mixed[1] = mixed[1].replace(b"    ruRU = {", b"    xxXX = {", 1)
        receipt = self.diagnose(*mixed)
        self.assert_incomplete(receipt, "CatalogValidationError", "pack-unknown")

    def test_retired_keys_are_never_a_shipped_key(self):
        english = self.catalog.parse_english(self.inputs[0])
        packs = self.catalog.parse_packs(self.inputs[1])
        for key in (RETIRED, NEVER_KNOWN):
            self.assertNotIn(key, english)
            self.assertFalse(any(key in pack["entries"] for pack in packs.values()))
            for value in self.inputs:
                self.assertNotIn(key.encode(), value)

    def with_input(self, index, value):
        data = list(self.inputs)
        data[index] = value
        return data


class DiagnosticCommandLineTests(unittest.TestCase):
    """S6: --diagnose prints one diagnostic record; invalid input still
    exits 2, and the default and --registry outcomes are unchanged."""

    def run_cli(self, *args):
        return subprocess.run([sys.executable, "-B", str(CATALOG_TOOL), *[str(a) for a in args]],
                              capture_output=True, cwd=str(ROOT))

    def copy_root(self, root, data):
        for relative, value in zip(INPUTS, data):
            target = root.joinpath(*relative.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)
        shutil.copyfile(str(ROOT / "Nexus.toc"), str(root / "Nexus.toc"))

    def test_valid_repository_root(self):
        run = self.run_cli("--diagnose")
        self.assertEqual((run.returncode, run.stderr), (0, b""))
        record = json.loads(run.stdout)
        self.assertEqual((record["record"], record["exitCode"]), ("diagnostics", 0))
        self.assertIs(record["diagnostics"]["valid"], True)
        self.assertEqual(record["diagnostics"]["coverage"]["registry"]["declarationCount"], 28)
        strict = self.run_cli("--diagnose", "--require-complete")
        self.assertEqual(strict.returncode, 1)
        self.assertEqual(json.loads(strict.stdout)["exitCode"], 1)
        self.assertEqual(self.run_cli("--diagnose", "--diagnose").returncode, 2)

    def test_invalid_root_fails_in_every_mode(self):
        data = multi_error_inputs(current_inputs())
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.copy_root(root, data)
            before = {path: path.read_bytes() for path in root.rglob("*") if path.is_file()}
            for args in ((), ("--registry",), ("--require-complete",)):
                with self.subTest(args=args):
                    run = self.run_cli("--root", root, *args)
                    self.assertEqual((run.returncode, run.stdout), (2, b""))
                    error = json.loads(run.stderr)
                    self.assertEqual((error["code"], error["key"]), ("orphan-entry", RETIRED))
            for args in (("--diagnose",), ("--diagnose", "--require-complete"),
                         ("--diagnose", "--registry")):
                with self.subTest(args=args):
                    run = self.run_cli("--root", root, *args)
                    self.assertEqual((run.returncode, run.stderr), (2, b""))
                    record = json.loads(run.stdout)
                    self.assertEqual(record["exitCode"], 2)
                    self.assertIs(record["diagnostics"]["valid"], False)
                    self.assertEqual(record["diagnostics"]["problemCounts"],
                                     {"invalid": 2, "obsolete": 1, "orphan": 2})
            after = {path: path.read_bytes() for path in root.rglob("*") if path.is_file()}
            self.assertEqual(after, before)


# S7 (Refs #147): per-pack provenance metadata and the opt-in provenance
# receipt. The real records hold UNKNOWN facts; every DECLARED record below is
# a synthetic in-memory edit of the real bytes and is not rights, authorship
# or drafting-history evidence. No URL is fetched.
OPTIONAL_IDS = ("frFR", "deDE", "esES", "plPL", "ptBR", "ruRU")
FACTS = ("authorship", "attribution", "rightsStatement", "importedCorpus")
BASIS = "exact-supplied-english-bytes"
EXPECTED_PROVENANCE_CODES = (
    "provenance-contract", "provenance-structure", "provenance-field",
    "provenance-unknown-product", "provenance-duplicate-product", "provenance-missing-product",
    "provenance-status", "provenance-reason", "provenance-value", "provenance-reference",
    "provenance-basis", "provenance-hash-format", "provenance-stale",
)
# The historical document-level declarations of the accepted predecessor
# 83417bc, kept verbatim; they never fill a per-pack fact.
HISTORICAL_LINEAGE = {
    "kind": "independently_drafted_nexus_presentation_text",
    "newHumanRightsAttestation": "none",
    "importedCorpus": "none",
    "excludedSources": ["another addon's translation corpus", "game client text",
                        "player or private client content"],
}
HISTORICAL_PACK_REVIEW = (
    "data/LocalizationPacks.lua states that the pack wording was drafted and has had a "
    "technical review only, and that no competent human reviewer of each language has "
    "accepted it. No reviewer identity or date is recorded, so no review record is entered "
    "here.")
SYNTHETIC_REFERENCE = "https://example.invalid/synthetic-provenance"


def fact_pattern(product_id, fact):
    """The one-line fact object of one provenance record in the release bytes."""
    return re.compile(rb'("productId": "' + product_id.encode() + rb'",'
                      rb'(?:\r?\n {8}"[A-Za-z]+": \{[^{}\r\n]*\},)*?\r?\n {8}"'
                      + fact.encode() + rb'": )(\{[^{}\r\n]*\})(,?)')


def with_fact(release, product_id, fact, value):
    """release with only the fact object of one record replaced by the JSON of
    value; every other byte is kept."""
    pattern = fact_pattern(product_id, fact)
    found = list(pattern.finditer(release))
    if len(found) != 1:
        raise AssertionError("expected exactly one %s.%s" % (product_id, fact))
    start, end = found[0].span(2)
    text = json.dumps(value, ensure_ascii=False).encode("utf-8")
    return release[:start] + text + release[end:]


def without_fact_line(release, product_id, fact):
    """release without the whole line of one fact (not the last of a record),
    in whichever line break it uses."""
    found = list(fact_pattern(product_id, fact).finditer(release))
    if len(found) != 1 or found[0].group(3) != b",":
        raise AssertionError("expected exactly one inner %s.%s" % (product_id, fact))
    start = release.rindex(b"\n", 0, found[0].start(2))
    start -= 1 if release[start - 1:start] == b"\r" else 0
    return release[:start] + release[found[0].end(3):]


def with_record_id(release, product_id, new_id):
    """release with the productId of one provenance record replaced."""
    old = re.compile(rb'"productId": "' + product_id.encode() + rb'",(?=\r?\n {8}"englishBase")')
    if len(old.findall(release)) != 1:
        raise AssertionError("expected exactly one record %s" % product_id)
    return old.sub(b'"productId": ' + json.dumps(new_id).encode() + b",", release)


def with_provenance(release, change):
    """release re-encoded with change applied to its packProvenance member
    (structural controls only)."""
    document = json.loads(release.decode("utf-8"))
    change(document)
    return json.dumps(document, ensure_ascii=False, indent=2).encode("utf-8")


def declared_base(digest, **extra):
    record = {"status": "DECLARED", "algorithm": "SHA-256", "basis": BASIS, "sha256": digest,
              "evidenceReference": SYNTHETIC_REFERENCE}
    record.update(extra)
    return record


def declared_fact(value, **extra):
    record = {"status": "DECLARED", "value": value, "evidenceReference": SYNTHETIC_REFERENCE}
    record.update(extra)
    return record


def assert_current_provenance(test, catalog, inputs):
    """The required-CI gate on the current repository metadata: technically
    valid, every declared base still matching, every pack held. Returns the
    receipt."""
    receipt = catalog.pack_provenance_diagnostics(*inputs)
    test.assertIs(receipt["valid"], True, receipt["metadata"]["problems"])
    test.assertEqual(receipt["catalogVerdict"], {"result": "valid"})
    test.assertEqual((receipt["metadata"]["technicalValidity"], receipt["metadata"]["problems"]),
                     ("VALID", []))
    test.assertEqual([row["productId"] for row in receipt["packs"]], list(OPTIONAL_IDS))
    test.assertEqual(receipt["baseRelations"]["STALE"], 0)
    for row in receipt["packs"]:
        test.assertIn(row["englishBase"]["relation"], ("UNKNOWN", "MATCHED"))
        test.assertEqual((row["attestedFacts"], row["supportEligibility"]),
                         ("NOT_ESTABLISHED", "HELD"))
    test.assertEqual((receipt["attestedFacts"], receipt["supportEligibility"]),
                     ("NOT_ESTABLISHED", "HELD"))
    test.assertIs(receipt["completeness"]["established"], False)
    return receipt


class ProvenanceTests(unittest.TestCase):
    """S7: per-pack provenance records and the opt-in provenance receipt
    beside the unchanged strict, report and diagnostic seams."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog()
        cls.inputs = current_inputs()
        cls.provenance = staticmethod(cls.catalog.pack_provenance_diagnostics)
        cls.release = json.loads(cls.inputs[3].decode("utf-8"))

    def with_release(self, release):
        return [self.inputs[0], self.inputs[1], self.inputs[2], release, self.inputs[4]]

    def assert_refused(self, release, code, key=None):
        """The provenance receipt refuses release while the strict, report and
        diagnostic seams keep their verdict on the same bytes."""
        data = self.with_release(release)
        self.catalog.registry_catalog_report(*data)
        self.catalog.catalog_report(*data[:4])
        self.assertIs(self.catalog.registry_catalog_diagnostics(*data)["valid"], True)
        receipt = self.provenance(*data)
        self.assertIs(receipt["valid"], False)
        self.assertEqual(receipt["catalogVerdict"], {"result": "valid"})
        self.assertEqual(receipt["metadata"]["technicalValidity"], "INVALID")
        problem = receipt["metadata"]["problems"][0]
        self.assertEqual((problem["code"], problem.get("key")), (code, key))
        self.assertIn(problem["code"], self.catalog.PROVENANCE_CODES)
        self.assertEqual((receipt["attestedFacts"], receipt["supportEligibility"]),
                         ("NOT_ESTABLISHED", "HELD"))
        self.assertIs(receipt["completeness"]["established"], False)
        return receipt

    def test_p1_real_packs_are_unknown_technical_valid_and_held(self):
        receipt = assert_current_provenance(self, self.catalog, self.inputs)
        self.assertEqual(receipt["baseRelations"], {"UNKNOWN": 6, "MATCHED": 0, "STALE": 0})
        for row in receipt["packs"]:
            product_id = row["productId"]
            base = row["englishBase"]
            self.assertEqual((sorted(base), base["status"], base["relation"]),
                             (["reason", "relation", "status"], "UNKNOWN", "UNKNOWN"))
            self.assertEqual(sorted(row["facts"]), sorted(FACTS))
            for name in FACTS:
                fact = row["facts"][name]
                self.assertEqual((sorted(fact), fact["status"]), (["reason", "status"], "UNKNOWN"))
                self.assertTrue(fact["reason"].strip())
            holds = [(reason["code"], reason["subject"]) for reason in row["holdReasons"]]
            self.assertEqual(holds, [("base-unknown", product_id + ".englishBase")]
                             + [("fact-unknown", product_id + "." + name) for name in FACTS]
                             + [("support-gates-outside-provenance", product_id)])
        # The real records: one per optional pack, never the English baseline.
        records = self.release["packProvenance"]["records"]
        self.assertEqual([record["productId"] for record in records], list(OPTIONAL_IDS))
        self.assertEqual((self.release["packProvenance"]["contract"],
                          self.release["packProvenance"]["contractVersion"]),
                         ("nexus.l10n.pack_provenance", 1))
        # Entry and review facts are unchanged: 28 English keys, six packs of
        # 27 draft entries (162), no review declaration or gate upgrade.
        report = self.catalog.registry_catalog_report(*self.inputs)
        self.assertEqual(report["denominator"]["englishKeys"], 28)
        self.assertEqual([row["entriesPresent"] for row in report["products"]], [27] * 6)
        self.assertEqual(sum(row["entriesPresent"] for row in report["products"]), 162)
        for row in report["products"]:
            self.assertEqual((row["counts"]["translated_and_reviewed"],
                              row["counts"]["reviewed_legitimately_identical"]), (0, 0))
        self.assertEqual(self.release["entryReview"]["declarations"], [])
        for product in self.release["products"]:
            self.assertEqual(product["review"]["nativeAcceptance"], {"status": "NOT_RUN",
                                                                     "records": []})
            self.assertEqual(product["review"]["fluentHumanAcceptance"]["status"], "pending")

    def test_p2_malformed_metadata_derived_from_the_real_bytes_is_refused(self):
        release = self.inputs[3]
        reason = self.release["packProvenance"]["records"][1]["authorship"]["reason"]
        digest = hashlib.sha256(self.inputs[0]).hexdigest()
        cases = {
            "status false": (with_fact(release, "deDE", "authorship",
                                       {"status": False, "reason": reason}), "provenance-status"),
            "fact false": (with_fact(release, "deDE", "authorship", False),
                           "provenance-structure"),
            "fact string": (with_fact(release, "deDE", "authorship", "UNKNOWN"),
                            "provenance-structure"),
            "lower-case unknown": (with_fact(release, "deDE", "authorship",
                                             {"status": "unknown", "reason": reason}),
                                   "provenance-status"),
            "pending status": (with_fact(release, "deDE", "rightsStatement",
                                         {"status": "pending", "reason": reason}),
                               "provenance-status"),
            "verified status": (with_fact(release, "deDE", "rightsStatement",
                                          {"status": "VERIFIED", "value": "Granted",
                                           "evidenceReference": SYNTHETIC_REFERENCE}),
                                "provenance-status"),
            "unknown with value": (with_fact(release, "deDE", "authorship",
                                             {"status": "UNKNOWN", "reason": reason,
                                              "value": "Somebody"}), "provenance-field"),
            "unknown without reason": (with_fact(release, "deDE", "authorship",
                                                 {"status": "UNKNOWN"}), "provenance-field"),
            "empty reason": (with_fact(release, "deDE", "authorship",
                                       {"status": "UNKNOWN", "reason": ""}), "provenance-reason"),
            "placeholder reason": (with_fact(release, "deDE", "authorship",
                                             {"status": "UNKNOWN", "reason": "pending"}),
                                   "provenance-reason"),
            "empty identity": (with_fact(release, "deDE", "authorship", declared_fact("")),
                               "provenance-value"),
            "padded identity": (with_fact(release, "deDE", "authorship",
                                          declared_fact(" Somebody")), "provenance-value"),
            "pending identity": (with_fact(release, "deDE", "authorship",
                                           declared_fact("pending")), "provenance-value"),
            "unassigned identity": (with_fact(release, "deDE", "authorship",
                                              declared_fact("UNASSIGNED")), "provenance-value"),
            "none as no-import": (with_fact(release, "deDE", "importedCorpus",
                                            declared_fact("none")), "provenance-value"),
            "false as no-import": (with_fact(release, "deDE", "importedCorpus",
                                             declared_fact(False)), "provenance-value"),
            "unknown as a value": (with_fact(release, "deDE", "attribution",
                                             declared_fact("UNKNOWN")), "provenance-value"),
            "declared without reference": (with_fact(release, "deDE", "authorship",
                                                     {"status": "DECLARED",
                                                      "value": "Somebody"}), "provenance-field"),
            "http reference": (with_fact(release, "deDE", "authorship",
                                         declared_fact("Somebody", evidenceReference=
                                                       "http://example.invalid/x")),
                               "provenance-reference"),
            "missing fact": (without_fact_line(release, "deDE", "authorship"),
                             "provenance-field"),
            "English baseline record": (with_record_id(release, "deDE", "enUS"),
                                        "provenance-unknown-product"),
            "unknown product": (with_record_id(release, "deDE", "xxXX"),
                                "provenance-unknown-product"),
            "duplicate product": (with_record_id(release, "deDE", "frFR"),
                                  "provenance-duplicate-product"),
            "git blob basis": (with_fact(release, "deDE", "englishBase",
                                         declared_base(digest, basis="git-blob-sha1")),
                               "provenance-basis"),
            "decoded entry basis": (with_fact(release, "deDE", "englishBase",
                                              declared_base(digest, basis="decoded-entries")),
                                    "provenance-basis"),
            "other algorithm": (with_fact(release, "deDE", "englishBase",
                                          declared_base(digest, algorithm="SHA-1")),
                                "provenance-basis"),
            "upper-case digest": (with_fact(release, "deDE", "englishBase",
                                            declared_base(digest.upper())),
                                  "provenance-hash-format"),
            "short digest": (with_fact(release, "deDE", "englishBase",
                                       declared_base(digest[:40])), "provenance-hash-format"),
            "base without reference": (with_fact(release, "deDE", "englishBase",
                                                 {key: value for key, value
                                                  in declared_base(digest).items()
                                                  if key != "evidenceReference"}),
                                       "provenance-field"),
        }
        keys = {"English baseline record": "enUS", "unknown product": "xxXX",
                "duplicate product": "frFR"}
        for name, (data, code) in cases.items():
            with self.subTest(case=name):
                self.assertNotEqual(data, release)
                receipt = self.assert_refused(data, code, keys.get(name, "deDE"))
                self.assertIsNone(receipt["packs"])
                self.assertIsNone(receipt["baseRelations"])

    def test_p2_structural_metadata_is_refused(self):
        def drop(document):
            del document["packProvenance"]

        def records(change):
            return lambda document: change(document["packProvenance"]["records"])

        cases = {
            "member absent (the predecessor shape)": (drop, "provenance-structure", None),
            "member not an object": (lambda d: d.update(packProvenance=[]),
                                     "provenance-structure", None),
            "contract version 2": (lambda d: d["packProvenance"].update(contractVersion=2),
                                   "provenance-contract", None),
            "contract version true": (lambda d: d["packProvenance"].update(contractVersion=True),
                                      "provenance-contract", None),
            "other contract": (lambda d: d["packProvenance"].update(contract="nexus.other"),
                               "provenance-contract", None),
            "records object": (lambda d: d["packProvenance"].update(records={}),
                               "provenance-structure", None),
            "record not an object": (records(lambda r: r.__setitem__(2, "esES")),
                                     "provenance-structure", None),
            "extra record field": (records(lambda r: r[2].update(translator={
                "status": "UNKNOWN", "reason": "x y"})), "provenance-field", "esES"),
            "product ID not text": (records(lambda r: r[2].update(productId=7)),
                                    "provenance-field", None),
            "missing record": (records(lambda r: r.pop()), "provenance-missing-product", "ruRU"),
            "repeated record": (records(lambda r: r.append(dict(r[0]))),
                                "provenance-duplicate-product", "frFR"),
        }
        for name, (change, code, key) in cases.items():
            with self.subTest(case=name):
                self.assert_refused(with_provenance(self.inputs[3], change), code, key)

    def test_p3_declared_base_matches_goes_stale_and_is_never_refreshed(self):
        english = self.inputs[0]
        digest = hashlib.sha256(english).hexdigest()
        matched = with_fact(self.inputs[3], "deDE", "englishBase", declared_base(digest))
        receipt = assert_current_provenance(self, self.catalog, self.with_release(matched))
        self.assertEqual(receipt["baseRelations"], {"UNKNOWN": 5, "MATCHED": 1, "STALE": 0})
        rows = {row["productId"]: row for row in receipt["packs"]}
        self.assertEqual(rows["deDE"]["englishBase"], dict(declared_base(digest),
                                                            relation="MATCHED"))
        self.assertEqual(rows["deDE"]["holdReasons"][0]["code"], "base-declared-not-attested")
        self.assertEqual(rows["deDE"]["attestedFacts"], "NOT_ESTABLISHED")
        for product_id in OPTIONAL_IDS:
            if product_id != "deDE":
                self.assertEqual(rows[product_id]["englishBase"]["relation"], "UNKNOWN")
        # A different declared digest is STALE: a technical failure that keeps
        # the declaration as written.
        other = hashlib.sha256(english + b"-- other bytes\n").hexdigest()
        stale = with_fact(self.inputs[3], "deDE", "englishBase", declared_base(other))
        receipt = self.provenance(*self.with_release(stale))
        self.assert_stale(receipt, other, digest)
        # The supplied English changes but stays a valid catalog: the other
        # line-break representation and a trailing comment. The declaration is
        # not normalized to match and not refreshed.
        changed = dict(representations(english))
        changed["comment"] = english + b"-- trailing comment\n"
        for name, value in changed.items():
            if value == english:
                continue
            with self.subTest(english=name):
                data = [value] + self.with_release(matched)[1:]
                self.catalog.registry_catalog_report(*data)
                receipt = self.provenance(*data)
                self.assert_stale(receipt, digest, hashlib.sha256(value).hexdigest())
                self.assertEqual(data[3], matched)
                # UNKNOWN is never stale, whatever the English bytes.
                unknown = self.provenance(value, *self.inputs[1:])
                self.assertIs(unknown["valid"], True)
                self.assertEqual(unknown["baseRelations"],
                                 {"UNKNOWN": 6, "MATCHED": 0, "STALE": 0})

    def assert_stale(self, receipt, declared, observed):
        self.assertIs(receipt["valid"], False)
        self.assertEqual(receipt["catalogVerdict"], {"result": "valid"})
        self.assertEqual(receipt["metadata"]["technicalValidity"], "INVALID")
        self.assertEqual([(problem["code"], problem["key"])
                          for problem in receipt["metadata"]["problems"]],
                         [("provenance-stale", "deDE")])
        self.assertEqual(receipt["baseRelations"], {"UNKNOWN": 5, "MATCHED": 0, "STALE": 1})
        base = {row["productId"]: row for row in receipt["packs"]}["deDE"]["englishBase"]
        self.assertEqual((base["sha256"], base["relation"]), (declared, "STALE"))
        self.assertEqual(receipt["englishObservation"]["sha256"], observed)
        self.assertEqual(receipt["supportEligibility"], "HELD")

    def test_p4_observation_documented_claims_and_facts_stay_apart(self):
        receipt = assert_current_provenance(self, self.catalog, self.inputs)
        digest = hashlib.sha256(self.inputs[0]).hexdigest()
        observation = receipt["englishObservation"]
        self.assertEqual((observation["source"], observation["algorithm"], observation["basis"],
                          observation["sha256"], observation["byteLength"]),
                         (INPUTS[0], "SHA-256", BASIS, digest, len(self.inputs[0])))
        self.assertIn("not a drafting base", observation["role"])
        # The observation and the legacy statements fill no per-pack fact.
        packs = json.dumps(receipt["packs"])
        self.assertNotIn(digest, packs)
        self.assertNotIn(digest.encode(), self.inputs[3])
        for row in receipt["packs"]:
            for fact in [row["englishBase"]] + list(row["facts"].values()):
                self.assertEqual(fact["status"], "UNKNOWN")
                self.assertNotIn(fact["reason"], ("none", HISTORICAL_LINEAGE["kind"]))
        # The historical declarations are kept verbatim and echoed as such.
        self.assertEqual(self.release["sourceLineage"], HISTORICAL_LINEAGE)
        self.assertEqual(self.release["packReviewStatementAtBase"], HISTORICAL_PACK_REVIEW)
        historical = receipt["historicalDeclarations"]
        self.assertEqual((historical["sourceLineage"], historical["packReviewStatementAtBase"]),
                         (HISTORICAL_LINEAGE, HISTORICAL_PACK_REVIEW))
        self.assertEqual(historical["nature"], "documented_claim")
        self.assertEqual(historical["perPackFacts"], "NOT_DERIVED")
        # Changing the legacy statements changes no per-pack fact.
        changed = with_provenance(self.inputs[3], lambda d: d["sourceLineage"].update(
            importedCorpus="UNKNOWN"))
        self.assertEqual(self.provenance(*self.with_release(changed))["packs"], receipt["packs"])
        # Structurally qualified DECLARED facts are recorded, never verified.
        release = with_fact(self.inputs[3], "esES", "englishBase", declared_base(digest))
        for name in FACTS:
            release = with_fact(release, "esES", name, declared_fact("Synthetic %s statement"
                                                                     % name))
        declared = assert_current_provenance(self, self.catalog, self.with_release(release))
        row = {row["productId"]: row for row in declared["packs"]}["esES"]
        for name in FACTS:
            self.assertEqual(row["facts"][name], declared_fact("Synthetic %s statement" % name))
        self.assertEqual([reason["code"] for reason in row["holdReasons"]],
                         ["base-declared-not-attested"] + ["fact-declared-not-verified"] * 4
                         + ["support-gates-outside-provenance"])
        self.assertEqual((row["attestedFacts"], row["supportEligibility"]),
                         ("NOT_ESTABLISHED", "HELD"))

    def test_p5_no_support_review_or_count_upgrade(self):
        digest = hashlib.sha256(self.inputs[0]).hexdigest()
        release = self.inputs[3]
        for product_id in OPTIONAL_IDS:
            release = with_fact(release, product_id, "englishBase", declared_base(digest))
            for name in FACTS:
                release = with_fact(release, product_id, name, declared_fact("Synthetic text"))
        data = self.with_release(release)
        receipt = assert_current_provenance(self, self.catalog, data)
        self.assertEqual(receipt["baseRelations"], {"UNKNOWN": 0, "MATCHED": 6, "STALE": 0})
        self.assertNotIn("100%", json.dumps(receipt))
        # Only the technical verdict may be true; nothing grants support.
        flags = []

        def walk(value, path):
            if value is True:
                flags.append(path)
            elif isinstance(value, dict):
                for name, item in value.items():
                    walk(item, path + "." + name)
            elif isinstance(value, list):
                for index, item in enumerate(value):
                    walk(item, "%s[%d]" % (path, index))

        walk(receipt, "receipt")
        self.assertEqual(flags, ["receipt.valid"])
        # Entry categories, review gates and completeness reasons are those of
        # the real metadata: provenance is not review or coverage.
        for api, count in ((self.catalog.registry_catalog_report, 5),
                           (self.catalog.catalog_report, 4)):
            with self.subTest(api=api.__name__):
                with_records, real = api(*data[:count]), api(*self.inputs[:count])
                del with_records["inputs"], real["inputs"]
                self.assertEqual(with_records, real)

    def test_p6_existing_seams_ignore_provenance_metadata(self):
        stripped = with_provenance(self.inputs[3], lambda d: d.pop("packProvenance"))
        old = self.with_release(stripped)
        for name, count in (("validate_catalog_data", 4), ("catalog_report", 4),
                            ("validate_registry_catalog_data", 5),
                            ("registry_catalog_report", 5),
                            ("registry_catalog_diagnostics", 5)):
            with self.subTest(api=name):
                api = getattr(self.catalog, name)
                new, before = api(*self.inputs[:count]), api(*old[:count])
                for result in (new, before):
                    result.pop("inputs", None)
                    if result.get("coverage"):
                        result["coverage"].pop("inputs")
                    if "release" in result:
                        result["release"].pop("packProvenance", None)
                self.assertEqual(new, before)

    def test_p6_seam_is_pure_deterministic_and_bytes_only(self):
        catalog = self.catalog
        five = ["english_source", "packs_source", "key_context_json", "release_json",
                "localization_source"]
        self.assertEqual(list(inspect.signature(catalog.pack_provenance_diagnostics).parameters),
                         five)
        self.assertEqual(catalog.PROVENANCE_CODES, EXPECTED_PROVENANCE_CODES)
        for codes in (catalog.CODES, catalog.VALIDATION_CODES, catalog.EVIDENCE_CODES,
                      catalog.REGISTRY_CODES, catalog.CLI_CODES, catalog.DIAGNOSTIC_CODES):
            self.assertFalse(set(codes) & set(EXPECTED_PROVENANCE_CODES))
        for index, name in enumerate(five):
            with self.subTest(argument=name):
                changed = list(self.inputs)
                changed[index] = changed[index].decode("utf-8")
                with self.assertRaises(TypeError) as raised:
                    self.provenance(*changed)
                self.assertIn(name, str(raised.exception))
        stale = with_fact(self.inputs[3], "ptBR", "englishBase", declared_base("0" * 64))
        for release in (self.inputs[3], stale):
            data = self.with_release(release)
            mutable = [bytearray(value) for value in data]
            before = [hashlib.sha256(value).hexdigest() for value in mutable]
            expected = self.provenance(*data)
            self.assertEqual(self.provenance(*mutable), expected)
            self.assertEqual([hashlib.sha256(value).hexdigest() for value in mutable], before)
            self.assertEqual(self.provenance(*data), expected)
            json.dumps(expected, sort_keys=True).encode("ascii")
            for row, value in zip(expected["inputs"], data):
                self.assertEqual((row["sha256"], row["byteLength"]),
                                 (hashlib.sha256(value).hexdigest(), len(value)))
            # No file, process or network access during the call.
            blocked = self.blocked_calls()
            try:
                self.assertEqual(self.provenance(*data), expected)
            finally:
                blocked()

    @staticmethod
    def blocked_calls():
        import builtins
        import io
        import socket

        def refuse(*args, **kwargs):
            raise AssertionError("I/O or process access during the provenance call")

        saved = [(builtins, "open"), (io, "open"), (os, "open"), (os, "listdir"),
                 (os, "scandir"), (os, "stat"), (subprocess, "Popen"), (socket, "socket")]
        saved = [(owner, name, getattr(owner, name)) for owner, name in saved]
        for owner, name, _ in saved:
            setattr(owner, name, refuse)

        def restore():
            for owner, name, value in saved:
                setattr(owner, name, value)
        return restore

    def test_p6_catalog_verdict_stays_separate_from_metadata_validity(self):
        data = multi_error_inputs(self.inputs)
        receipt = self.provenance(*data)
        self.assertIs(receipt["valid"], False)
        self.assertEqual((receipt["catalogVerdict"]["result"], receipt["catalogVerdict"]["code"],
                          receipt["catalogVerdict"]["key"]), ("invalid", "orphan-entry", RETIRED))
        self.assertEqual((receipt["metadata"]["technicalValidity"], receipt["metadata"]["problems"]),
                         ("VALID", []))
        self.assertEqual(receipt["baseRelations"], {"UNKNOWN": 6, "MATCHED": 0, "STALE": 0})
        broken = self.provenance(*self.with_release(self.inputs[3][:-3]))
        self.assertEqual(broken["catalogVerdict"]["code"], "json-invalid")
        self.assertEqual([(problem["errorClass"], problem["code"])
                          for problem in broken["metadata"]["problems"]],
                         [("CatalogValidationError", "json-invalid")])
        self.assertIsNone(broken["historicalDeclarations"])

    def test_p7_registered_gate_detects_malformed_and_stale_current_metadata(self):
        # The gate passes the actual repository metadata ...
        assert_current_provenance(self, self.catalog, self.inputs)
        # ... and fails variants of it, each differing only in the targeted field.
        digest = hashlib.sha256(self.inputs[0]).hexdigest()
        variants = {
            "stale base": ("ruRU", "englishBase",
                           declared_base(hashlib.sha256(b"older English").hexdigest())),
            "placeholder authorship": ("plPL", "authorship", declared_fact("pending")),
            "boolean no-import": ("frFR", "importedCorpus", False),
            "Git object basis": ("esES", "englishBase",
                                 declared_base(digest, basis="git-blob-sha1")),
        }
        for name, (product_id, fact, value) in variants.items():
            with self.subTest(variant=name):
                release = with_fact(self.inputs[3], product_id, fact, value)
                # Only the targeted field differs from the real document.
                expected = json.loads(self.inputs[3].decode("utf-8"))
                index = OPTIONAL_IDS.index(product_id)
                expected["packProvenance"]["records"][index][fact] = value
                self.assertEqual(json.loads(release.decode("utf-8")), expected)
                with self.assertRaises(AssertionError):
                    assert_current_provenance(self, self.catalog, self.with_release(release))


class ProvenanceCommandLineTests(unittest.TestCase):
    """S7: --provenance prints one provenance record; the default, --registry
    and --diagnose outcomes are unchanged."""

    def run_cli(self, *args):
        return subprocess.run([sys.executable, "-B", str(CATALOG_TOOL), *[str(a) for a in args]],
                              capture_output=True, cwd=str(ROOT))

    def test_repository_root(self):
        run = self.run_cli("--provenance")
        self.assertEqual((run.returncode, run.stderr), (0, b""))
        record = json.loads(run.stdout)
        self.assertEqual((record["record"], record["exitCode"]), ("provenance", 0))
        expected = load_catalog().pack_provenance_diagnostics(*current_inputs())
        self.assertEqual(record["provenance"], json.loads(json.dumps(expected)))
        held = self.run_cli("--provenance", "--require-complete")
        self.assertEqual((held.returncode, json.loads(held.stdout)["exitCode"]), (1, 1))
        for args, code in ((("--provenance", "--provenance"), "argument-duplicate"),
                           (("--provenance", "--diagnose"), "argument-conflict")):
            with self.subTest(args=args):
                run = self.run_cli(*args)
                self.assertEqual((run.returncode, run.stdout), (2, b""))
                self.assertEqual(json.loads(run.stderr)["code"], code)

    def test_stale_root_fails_only_in_provenance_mode(self):
        data = current_inputs()
        data[3] = with_fact(data[3], "ruRU", "englishBase", declared_base("1" * 64))
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for relative, value in zip(INPUTS, data):
                target = root.joinpath(*relative.split("/"))
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(value)
            shutil.copyfile(str(ROOT / "Nexus.toc"), str(root / "Nexus.toc"))
            before = {path: path.read_bytes() for path in root.rglob("*") if path.is_file()}
            for args in (("--provenance",), ("--provenance", "--require-complete"),
                         ("--provenance", "--registry")):
                with self.subTest(args=args):
                    run = self.run_cli("--root", root, *args)
                    self.assertEqual((run.returncode, run.stderr), (2, b""))
                    receipt = json.loads(run.stdout)["provenance"]
                    self.assertIs(receipt["valid"], False)
                    self.assertEqual([problem["code"] for problem in
                                      receipt["metadata"]["problems"]], ["provenance-stale"])
            for args in ((), ("--registry",), ("--diagnose",)):
                with self.subTest(args=args):
                    self.assertEqual(self.run_cli("--root", root, *args).returncode, 0)
            after = {path: path.read_bytes() for path in root.rglob("*") if path.is_file()}
            self.assertEqual(after, before)


# S8 (Refs #147): static consumer binding. The gate reads the real registry
# inputs, both TOCs and every Lua file they load; every mutant below is an
# in-memory edit of those real bytes and is never written to the checkout.
CONSUMER_TOCS = ("Nexus.toc", "companion/NexusSupport/NexusSupport.toc")
MAPPED_KEYS = CURRENT_KEYS[:5]
DIRECT_KEYS = CURRENT_KEYS[5:]
HUD_FAMILY = "Main panel (HUD)"
DISPATCHER = "Nexus.UserText.Message"
EXPECTED_CONSUMER_CODES = (
    "consumer-input-structure", "consumer-path", "consumer-duplicate-path",
    "consumer-hash-mismatch", "consumer-length-mismatch", "consumer-toc-required",
    "consumer-toc-unknown", "consumer-toc-not-utf8", "consumer-toc-entry", "consumer-toc-duplicate",
    "consumer-source-missing", "consumer-source-unlisted", "consumer-registry-unloaded",
    "consumer-registry-order", "consumer-registry-conflict",
)
EXPECTED_BINDING_PROBLEM_CODES = (
    "binding-unparsed", "binding-unbound", "binding-orphan", "binding-kind",
    "binding-unresolved", "binding-mutation",
)
PANEL, READOUT, USER_TEXT = "ui/Panel.lua", "ui/Readout.lua", "core/UserText.lua"
PROGRESS_CALL = b'progressLabel:SetText((Nexus.Localization.Text("panel.heading.progress")))'
# The progress label loses its only consumer. A long comment, a string
# holding the call text, an unrelated object with a Text method, a local
# Nexus with a Text method, a Has query, a data table and a closing short
# comment keep the key literal on the same line, so no line number moves.
PROGRESS_FAKE_CODE = (
    b'progressLabel:SetText("Progress")'
    b' --[[ Nexus.Localization.Text("panel.heading.progress") ]]'
    b' local fakeCall = \'Nexus.Localization.Text("panel.heading.progress")\''
    b' local Other = {Text = tostring}; Other.Text("panel.heading.progress")'
    b' do local Nexus = {Localization = {Text = tostring}}; Nexus.Localization.Text("panel.heading.progress") end'
    b' local known = Nexus.Localization.Has("panel.heading.progress")'
    b' local data = {["panel.heading.progress"] = "Progress"}')
PROGRESS_FAKE_COMMENT = b' -- Nexus.Localization.Text("panel.heading.progress")'
PROGRESS_FAKES = PROGRESS_FAKE_CODE + PROGRESS_FAKE_COMMENT


def edit(data, old, new):
    """data with its one occurrence of old replaced by new. The match runs on
    the LF form of data, and the result keeps the line breaks of data (LF or
    CRLF), so one edit serves both representations."""
    lf = data.replace(b"\r\n", b"\n")
    crlf = lf != data
    if crlf and b"\n" in data.replace(b"\r\n", b""):
        raise AssertionError("mixed line breaks")
    result = replace_once(lf, old, new)
    return result.replace(b"\n", b"\r\n") if crlf else result


def toc_listing(toc, data):
    """Independent oracle: the Lua paths one TOC loads, in order."""
    base = toc.rpartition("/")[0]
    paths = []
    for line in data.decode("utf-8", "replace").splitlines():
        entry = line.strip()
        if entry and not entry.startswith("#"):
            paths.append((base + "/" if base else "") + entry.replace("\\", "/"))
    return paths


def current_files():
    """The exact physical bytes of the five registry inputs, both TOCs and
    every Lua file the TOCs load, keyed by repository path."""
    files = {path: (ROOT / path).read_bytes() for path in INPUTS + CONSUMER_TOCS}
    for toc in CONSUMER_TOCS:
        for path in toc_listing(toc, files[toc]):
            files[path] = (ROOT / path).read_bytes()
    return files


def record(path, data):
    return {"path": path, "sha256": hashlib.sha256(data).hexdigest(),
            "byteLength": len(data), "data": data}


def binding_args(files, omit=(), extra=()):
    """The seven arguments of consumer_binding_report for files: the five
    registry inputs, a record per TOC and a record per loaded Lua file
    (except omit, plus the extra (path, bytes) records)."""
    tocs = [record(path, files[path]) for path in CONSUMER_TOCS if path in files]
    sources = [record(path, files[path]) for toc in CONSUMER_TOCS if toc in files
               for path in toc_listing(toc, files[toc]) if path in files and path not in omit]
    sources += [record(path, data) for path, data in extra]
    return [files[path] for path in INPUTS] + [tocs, sources]


def with_file(files, path, data):
    changed = dict(files)
    changed[path] = data
    return changed


def assert_current_bindings(test, catalog, args):
    """The registered current-source binding gate over the receipt of args."""
    return assert_binding_receipt(test, catalog.consumer_binding_report(*args))


def assert_binding_receipt(test, receipt):
    """The gate itself: every declared key has a genuine static consumer of
    the expected class, nothing is unresolved, orphaned or mismatched, the
    mapped reasons reach their exported dispatcher, and family declarations
    stay apart from binding."""
    test.assertEqual(receipt["problems"], [])
    test.assertIs(receipt["valid"], True)
    rows = {row["key"]: row for row in receipt["keys"]}
    test.assertEqual([row["key"] for row in receipt["keys"]], list(CURRENT_KEYS))
    expected = dict.fromkeys(MAPPED_KEYS, "MAPPED_TO_CONSUMER")
    expected.update(dict.fromkeys(DIRECT_KEYS, "DIRECT_LITERAL_CONSUMER"))
    test.assertEqual({key: row["binding"] for key, row in rows.items()}, expected)
    test.assertEqual((receipt["counts"]["DIRECT_LITERAL_CONSUMER"],
                      receipt["counts"]["MAPPED_TO_CONSUMER"], receipt["counts"]["UNBOUND"]),
                     (23, 5, 0))
    for key in DIRECT_KEYS:
        test.assertTrue({site["site"] for site in rows[key]["sites"]}
                        & {"direct-call", "wrapper-call"}, key)
        test.assertEqual(rows[key]["family"]["state"], "DECLARED")
        test.assertEqual([family["name"] for family in rows[key]["family"]["families"]],
                         [HUD_FAMILY])
    for key in MAPPED_KEYS:
        test.assertEqual({site["site"] for site in rows[key]["sites"]}, {"map-value"})
        test.assertEqual(rows[key]["family"], {
            "state": "UNCLASSIFIED", "families": [],
            "familySurface": ("PENDING: shared reason text; the families and surfaces "
                              "that show it are not classified")})
    # Review fix 1 (SPEC-147-S8-1): a counted site is one whose localization
    # result reaches an output, never merely a call location.
    for row in receipt["keys"]:
        for site in row["sites"]:
            test.assertTrue(site["outputs"], (row["key"], site))
    test.assertEqual(len(receipt["mapChains"]), 1)
    chain = receipt["mapChains"][0]
    test.assertEqual((chain["wrapper"]["name"], chain["wrapper"]["method"],
                      chain["dispatcher"]), ("LocalizedReason", "Text", DISPATCHER))
    test.assertEqual((chain["established"], chain["wrapperReturnsResult"]), (True, True))
    test.assertTrue(chain["outputs"])
    test.assertEqual(sorted(chain["boundKeys"]), sorted(MAPPED_KEYS))
    return receipt


_S8_CATALOG, _S8_FILES = [], []


def s8_catalog():
    """One loaded tool for every S8 class, so its parse memo is shared."""
    if not _S8_CATALOG:
        _S8_CATALOG.append(load_catalog())
    return _S8_CATALOG[0]


def s8_files():
    """The current input files, read once for every S8 class (callers copy)."""
    if not _S8_FILES:
        _S8_FILES.append(current_files())
    return dict(_S8_FILES[0])


class ConsumerBindingTests(unittest.TestCase):
    """S8: the registered current-repository static consumer binding gate
    and its negative controls on in-memory edits of the real bytes."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = s8_catalog()
        cls.files = s8_files()
        cls.report = staticmethod(cls.catalog.consumer_binding_report)

    def receipt(self, files, **options):
        return self.report(*binding_args(files, **options))

    def refuse(self, args, code):
        with self.assertRaises(self.catalog.CatalogConsumerError) as raised:
            self.report(*args)
        self.assertEqual(raised.exception.code, code)
        return raised.exception

    def gate_fails(self, files, **options):
        """The receipt of files, after the same gate failed on it."""
        receipt = self.receipt(files, **options)
        with self.assertRaises(AssertionError):
            assert_binding_receipt(self, receipt)
        return receipt

    def problems(self, receipt, code=None):
        return [problem for problem in receipt["problems"]
                if code is None or problem["code"] == code]

    def binding(self, receipt, key):
        return next(row for row in receipt["keys"] if row["key"] == key)

    def test_c1_public_seam_codes_and_signature(self):
        catalog = self.catalog
        self.assertEqual(list(inspect.signature(catalog.consumer_binding_report).parameters),
                         ["english_source", "packs_source", "key_context_json", "release_json",
                          "localization_source", "toc_records", "source_records"])
        self.assertEqual(catalog.CONSUMER_CODES, EXPECTED_CONSUMER_CODES)
        self.assertEqual(catalog.BINDING_PROBLEM_CODES, EXPECTED_BINDING_PROBLEM_CODES)
        self.assertEqual(catalog.BINDING_CLASSES,
                         ("DIRECT_LITERAL_CONSUMER", "MAPPED_TO_CONSUMER", "UNBOUND"))
        self.assertTrue(issubclass(catalog.CatalogConsumerError, ValueError))
        ours = set(EXPECTED_CONSUMER_CODES) | set(EXPECTED_BINDING_PROBLEM_CODES)
        self.assertEqual(len(ours), len(EXPECTED_CONSUMER_CODES)
                         + len(EXPECTED_BINDING_PROBLEM_CODES))
        for codes in (catalog.CODES, catalog.VALIDATION_CODES, catalog.EVIDENCE_CODES,
                      catalog.REGISTRY_CODES, catalog.CLI_CODES, catalog.DIAGNOSTIC_CODES,
                      catalog.PROVENANCE_CODES):
            self.assertFalse(set(codes) & ours)
        # The earlier seams keep their exact signatures.
        five = ["english_source", "packs_source", "key_context_json", "release_json",
                "localization_source"]
        for name in ("validate_registry_catalog_data", "registry_catalog_report",
                     "registry_catalog_diagnostics", "pack_provenance_diagnostics"):
            self.assertEqual(list(inspect.signature(getattr(catalog, name)).parameters), five)
        for name in ("validate_catalog_data", "catalog_report"):
            self.assertEqual(list(inspect.signature(getattr(catalog, name)).parameters),
                             five[:4])

    def test_c2_registered_gate_binds_the_current_repository(self):
        args = binding_args(self.files)
        receipt = assert_current_bindings(self, self.catalog, args)
        # The gate ran on the real repository input set, not a fixture.
        self.assertEqual(len(args[6]), 100)
        self.assertEqual([row["path"] for row in receipt["tocs"]], list(CONSUMER_TOCS))
        self.assertEqual([row["path"] for row in receipt["sources"]],
                         [path for toc in CONSUMER_TOCS
                          for path in toc_listing(toc, self.files[toc])])
        for row in receipt["tocs"] + receipt["sources"]:
            data = self.files[row["path"]]
            self.assertEqual((row["sha256"], row["byteLength"]),
                             (hashlib.sha256(data).hexdigest(), len(data)))
        self.assertEqual({row["analysis"] for row in receipt["sources"]}, {"PARSED"})
        self.assertEqual([row["source"] for row in receipt["inputs"]], list(INPUTS))
        roles = {row["path"]: row["role"] for row in receipt["sources"]}
        self.assertEqual((roles["core/Localization.lua"], roles["data/LocalizationEnglish.lua"],
                          roles["data/LocalizationPacks.lua"], roles[PANEL]),
                         ("provider", "catalog-data", "catalog-data", "scanned"))
        self.assertEqual(roles["companion/NexusSupport/Storage.lua"], "scanned")
        rows = {row["key"]: row for row in receipt["keys"]}
        # Format stays Format and Text stays Text; Options also uses Resolve.
        self.assertEqual({site["method"] for site in rows[CHARGE]["sites"]}, {"Format"})
        self.assertEqual({site["method"] for site in rows["panel.button.options"]["sites"]},
                         {"Text", "Resolve"})
        self.assertEqual({site["path"] for site in rows[CHARGE]["sites"]}, {READOUT})
        for key in MAPPED_KEYS:
            self.assertEqual({site["path"] for site in rows[key]["sites"]}, {USER_TEXT})
        # Review fix 1 oracle correction: the Hub menu wrapper returns its
        # localization result, but that result only fills tooltipText of an item
        # for the stock dropdown, which is outside the loaded source. Its site is
        # therefore listed as unproven, never counted; the direct tooltip call binds.
        row = rows["panel.tooltip.create_wishlist_draft"]
        self.assertEqual([site["site"] for site in row["sites"]], ["direct-call"])
        self.assertEqual([(site["site"], site["reason"]) for site in row["unprovenSites"]],
                         [("wrapper-call", "output-not-reached")])
        self.assertEqual(sum(len(row["unprovenSites"]) for row in receipt["keys"]), 5)
        # The proven outputs of the evidenced chains.
        outputs = {(output["path"], output["output"])
                   for site in rows[CHARGE]["sites"] for output in site["outputs"]}
        self.assertEqual(outputs, {(PANEL, "SetText")})
        options = {(output["path"], output["output"]) for site
                   in rows["panel.button.options"]["sites"] for output in site["outputs"]}
        self.assertEqual(options, {(PANEL, "SetText"), (PANEL, "AddLine")})
        chain = receipt["mapChains"][0]
        self.assertIn(("core/Main.lua", "AddMessage"),
                      {(output["path"], output["output"]) for output in chain["outputs"]})
        self.assertEqual(receipt["counts"]["keys"], 28)
        self.assertEqual(receipt["completeness"]["established"], False)
        for family in self.catalog.validate_registry_catalog_data(
                *args[:5])["keyContext"]["windowFamilies"]:
            self.assertEqual(family["coverageStatus"], "PENDING")

    def test_c3_last_genuine_direct_consumer_removed_with_fakes_retained(self):
        key = "panel.heading.progress"
        panel = edit(self.files[PANEL], PROGRESS_CALL, PROGRESS_FAKES)
        self.assertEqual(panel.count(key.encode()), self.files[PANEL].count(key.encode()) + 6)
        receipt = self.gate_fails(with_file(self.files, PANEL, panel))
        self.assertEqual(self.binding(receipt, key)["binding"], "UNBOUND")
        self.assertEqual(self.binding(receipt, key)["sites"], [])
        self.assertEqual([(problem["code"], problem["key"]) for problem in receipt["problems"]],
                         [("binding-unbound", key)])
        # The fakes are seen as literal leads but never bind.
        leads = self.binding(receipt, key)["excludedLiteralLeads"]
        self.assertEqual(leads["byPath"][PANEL], 4)
        self.assertEqual(receipt["counts"]["DIRECT_LITERAL_CONSUMER"], 22)
        # The declaration and English data still hold the key.
        self.assertIn(key.encode(), self.files["data/LocalizationEnglish.lua"])
        self.assertIn(key.encode(), self.files["core/Localization.lua"])

    def test_c3_a_retained_secondary_consumer_still_binds_until_the_last_is_removed(self):
        key, panel = "panel.heading.still_needed", self.files[PANEL]
        first = b'\n    needLabel:SetText((Nexus.Localization.Text("panel.heading.still_needed")))\n'
        second = b'\n        needLabel:SetText((Nexus.Localization.Text("panel.heading.still_needed")))\n'
        one = edit(panel, first, b'\n    needLabel:SetText("Still needed")\n')
        receipt = assert_current_bindings(self, self.catalog,
                                          binding_args(with_file(self.files, PANEL, one)))
        self.assertEqual(len(self.binding(receipt, key)["sites"]), 1)
        both = edit(one, second, b'\n        needLabel:SetText("Still needed")\n')
        receipt = self.gate_fails(with_file(self.files, PANEL, both))
        self.assertEqual(self.binding(receipt, key)["binding"], "UNBOUND")
        # Review fix 1 oracle correction: without its direct tooltip call, the
        # draft key is no longer kept by the Hub menu wrapper, whose result only
        # reaches the stock dropdown outside the loaded source.
        key = "panel.tooltip.create_wishlist_draft"
        direct = (b'GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.create_wishlist_draft"),'
                  b' 0.75, 0.75, 0.75, true)')
        no_direct = edit(panel, direct, b'GameTooltip:AddLine("draft", 0.75, 0.75, 0.75, true)')
        receipt = self.gate_fails(with_file(self.files, PANEL, no_direct))
        self.assertEqual(self.binding(receipt, key)["binding"], "UNBOUND")
        self.assertEqual([site["site"] for site in self.binding(receipt, key)["unprovenSites"]],
                         ["wrapper-call"])
        # A secondary wrapper consumer whose result reaches the tooltip keeps it ...
        shown = edit(panel, direct, b'local function DraftLine(key) return Nexus.Localization.Text'
                     b'(key) end; GameTooltip:AddLine(DraftLine("panel.tooltip.create_wishlist_draft"),'
                     b' 0.75, 0.75, 0.75, true)')
        receipt = assert_current_bindings(self, self.catalog,
                                          binding_args(with_file(self.files, PANEL, shown)))
        self.assertEqual([site["site"] for site in self.binding(receipt, key)["sites"]],
                         ["wrapper-call"])
        # ... until the wrapper discards that result.
        discarded = edit(shown, b"return Nexus.Localization.Text(key) end",
                         b'Nexus.Localization.Text(key); return "draft" end')
        receipt = self.gate_fails(with_file(self.files, PANEL, discarded))
        self.assertEqual(self.binding(receipt, key)["binding"], "UNBOUND")
        self.assertEqual([site["reason"] for site in self.binding(receipt, key)["unprovenSites"]
                          if site["site"] == "wrapper-call" and site["wrapper"]["name"]
                          == "DraftLine"], ["wrapper-result-not-returned"])

    def test_c4_mapped_chain_breaks_fail_the_gate(self):
        user = self.files[USER_TEXT]
        dispatch = b"if localizedReasons[s] then return LocalizedReason(localizedReasons[s],s) end"
        alias = b"local function LocalizedReason(key,code)\n    local localization=Nexus.Localization\n"
        variants = {
            "dispatch argument": (USER_TEXT, edit(user, dispatch, dispatch.replace(
                b"LocalizedReason(localizedReasons[s],s)", b"LocalizedReason(s,s)"))),
            "wrapper receiver": (USER_TEXT, edit(user, alias, alias.replace(
                b"=Nexus.Localization", b"=Nexus.Other"))),
            "wrong Text object": (USER_TEXT, edit(user, b"local text,source=localization.Text(key)",
                                                  b"local text,source=T.Text(key)")),
            "alias reassigned": (USER_TEXT, edit(user, alias, alias + b"    localization={}\n")),
            "wrapper reassigned": (USER_TEXT, edit(user, b"function T.Message(value)\n",
                                                   b"LocalizedReason=nil\nfunction T.Message(value)\n")),
            "earlier unverified return": (USER_TEXT, edit(user, dispatch,
                                                          b'if s=="x" then return s end ' + dispatch)),
            "dispatch variable reassigned": (USER_TEXT, edit(user, dispatch,
                                                             b's=s:lower() ' + dispatch)),
            "map mutated": (USER_TEXT, edit(user, dispatch,
                                            b'localizedReasons.x="reason.list_preparing" ' + dispatch)),
            "dispatcher disconnected": (USER_TEXT, edit(user, b"function T.Message(value)\n",
                                                        b"function T.Unused(value)\n")),
        }
        receipts = {}
        for name, (path, data) in variants.items():
            with self.subTest(variant=name):
                receipt = receipts[name] = self.gate_fails(with_file(self.files, path, data))
                for key in MAPPED_KEYS:
                    self.assertEqual(self.binding(receipt, key)["binding"], "UNBOUND")
                self.assertEqual(receipt["counts"]["DIRECT_LITERAL_CONSUMER"], 23)
        # An earlier reasons-table entry shadows exactly the one mapped code.
        shadow = edit(user, b"local reasons={\n",
                      b'local reasons={\n    ["STORE_PENDING"]="Saved data shadow",\n')
        receipt = self.gate_fails(with_file(self.files, USER_TEXT, shadow))
        self.assertEqual([row["key"] for row in receipt["keys"] if row["binding"] == "UNBOUND"],
                         ["reason.saved_data_reading"])
        self.assertEqual([(row["code"], row["key"]) for row in receipt["shadowedMapEntries"]],
                         [("STORE_PENDING", "reason.saved_data_reading")])
        # The unresolved constructs are named, not assumed bindings.
        for name in ("alias reassigned", "wrapper reassigned", "earlier unverified return",
                     "dispatch variable reassigned", "map mutated"):
            with self.subTest(unresolved=name):
                self.assertTrue(self.problems(receipts[name], "binding-unresolved"))

    def test_c5_method_kind_mismatch_is_not_a_binding(self):
        readout = edit(self.files[READOUT], b'localization.Format("readout.charge_counts",',
                       b'localization.Text("readout.charge_counts",')
        receipt = self.gate_fails(with_file(self.files, READOUT, readout))
        self.assertEqual(self.binding(receipt, CHARGE)["binding"], "UNBOUND")
        self.assertEqual([(problem["code"], problem["key"], problem["method"])
                          for problem in self.problems(receipt, "binding-kind")],
                         [("binding-kind", CHARGE, "Text")])
        panel = edit(self.files[PANEL], PROGRESS_CALL,
                     PROGRESS_CALL.replace(b"Localization.Text(", b"Localization.Format("))
        receipt = self.gate_fails(with_file(self.files, PANEL, panel))
        self.assertEqual([(problem["key"], problem["method"])
                          for problem in self.problems(receipt, "binding-kind")],
                         [("panel.heading.progress", "Format")])

    def test_c6_toc_and_source_omission_fail(self):
        toc = self.files["Nexus.toc"]
        no_panel = edit(toc, b"ui\\Panel.lua\n", b"")
        # Still supplied but no longer loaded: refused, not silently scanned.
        unlisted = binding_args(with_file(self.files, "Nexus.toc", no_panel), extra=(
            (PANEL, self.files[PANEL]),))
        error = self.refuse(unlisted, "consumer-source-unlisted")
        self.assertEqual(error.path, PANEL)
        # Neither loaded nor supplied: the inventory shrinks and the gate fails.
        # The 22 Panel keys lose their calls and, since review fix 1, the charge
        # template its only output, the Panel charge widget: 23 unbound.
        receipt = self.gate_fails(with_file(self.files, "Nexus.toc", no_panel))
        self.assertEqual(receipt["counts"]["UNBOUND"], 23)
        # Loaded but not supplied: refused, never shrunk.
        error = self.refuse(binding_args(self.files, omit=(READOUT,)), "consumer-source-missing")
        self.assertEqual((error.path, error.subject), (READOUT, "Nexus.toc"))
        # A non-TOC file with genuine call text cannot satisfy a consumer.
        fake = b'local x = Nexus.Localization.Text("panel.heading.progress")\n'
        self.refuse(binding_args(self.files, extra=(("tools/fake_consumer.lua", fake),)),
                    "consumer-source-unlisted")
        # The registry Lua sources must be loaded by Nexus.toc, in order.
        no_core = edit(toc, b"core\\Localization.lua\n", b"")
        self.refuse(binding_args(with_file(self.files, "Nexus.toc", no_core)),
                    "consumer-registry-unloaded")
        swapped = edit(edit(toc, b"data\\LocalizationEnglish.lua\n", b""),
                       b"core\\Localization.lua\n",
                       b"core\\Localization.lua\ndata\\LocalizationEnglish.lua\n")
        self.refuse(binding_args(with_file(self.files, "Nexus.toc", swapped)),
                    "consumer-registry-order")
        args = binding_args(self.files)
        args[5] = [row for row in args[5] if row["path"] != "Nexus.toc"]
        args[6] = [row for row in args[6] if row["path"] == "companion/NexusSupport/Storage.lua"]
        self.refuse(args, "consumer-toc-required")

    def test_c7_manifest_hashes_and_paths_are_checked_against_the_bytes(self):
        args = binding_args(self.files)
        panel = next(row for row in args[6] if row["path"] == PANEL)
        drifted = edit(panel["data"], b'"panel.heading.progress"', b'"panel.heading.pROGRESS"')
        self.assertEqual(len(drifted), len(panel["data"]))
        for field, value, code in (("data", drifted, "consumer-hash-mismatch"),
                                   ("byteLength", panel["byteLength"] + 1,
                                    "consumer-length-mismatch"),
                                   ("sha256", "0" * 64, "consumer-hash-mismatch")):
            with self.subTest(field=field):
                changed = binding_args(self.files)
                row = next(row for row in changed[6] if row["path"] == PANEL)
                row[field] = value
                self.assertEqual(self.refuse(changed, code).path, PANEL)
        toc_row = dict(args[5][0], data=args[5][0]["data"] + b"\n")
        self.refuse(args[:5] + [[toc_row, args[5][1]], args[6]], "consumer-hash-mismatch")
        for extra, code in (((("UI/Panel.lua", self.files[PANEL]),), "consumer-duplicate-path"),
                            (((PANEL, self.files[PANEL]),), "consumer-duplicate-path"),
                            ((("../outside.lua", b""),), "consumer-path"),
                            ((("/abs.lua", b""),), "consumer-path"),
                            ((("C:/abs.lua", b""),), "consumer-path"),
                            ((("ui\\Panel2.lua", b""),), "consumer-path"),
                            ((("ui//Panel2.lua", b""),), "consumer-path"),
                            ((("./ui/Panel2.lua", b""),), "consumer-path"),
                            ((("ui/Panel2.txt", b""),), "consumer-path")):
            with self.subTest(extra=extra[0][0]):
                self.refuse(binding_args(self.files, extra=extra), code)
        toc = self.files["Nexus.toc"]
        for line, code in ((b"..\\outside.lua\n", "consumer-toc-entry"),
                           (b"ui\\Panel.xml\n", "consumer-toc-entry"),
                           (b"C:\\abs.lua\n", "consumer-toc-entry"),
                           (b"UI\\Panel.lua\n", "consumer-toc-duplicate")):
            with self.subTest(toc_line=line):
                changed = with_file(self.files, "Nexus.toc", edit(toc, b"core\\Main.lua\n",
                                                                   b"core\\Main.lua\n" + line))
                error = self.refuse(binding_args(changed), code)
                self.assertEqual(error.subject, "Nexus.toc")
                self.assertIsInstance(error.line, int)
        bad_toc = with_file(self.files, "Nexus.toc", toc + b"\xff\n")
        self.refuse(binding_args(bad_toc), "consumer-toc-not-utf8")
        conflict = binding_args(self.files)
        conflict[0] = conflict[0].replace(b"\r\n", b"\n") + b"\n"
        self.refuse(conflict, "consumer-registry-conflict")

    def test_c7_input_structure_and_types(self):
        args = binding_args(self.files)
        for index in range(5):
            with self.subTest(argument=index):
                changed = list(args)
                changed[index] = changed[index].decode("utf-8")
                with self.assertRaises(TypeError):
                    self.report(*changed)
        row = args[6][0]
        for bad in ("not a list", [dict(row, extra=1)], [{k: v for k, v in row.items()
                                                         if k != "sha256"}],
                    [dict(row, data=row["data"].decode("utf-8"))], [dict(row, byteLength=True)],
                    [dict(row, sha256=row["sha256"].upper())], [None]):
            with self.subTest(records=repr(bad)[:40]):
                self.refuse(args[:6] + [bad], "consumer-input-structure")

    def test_c8_fake_and_unrelated_consumers_never_bind(self):
        key = "panel.heading.progress"
        panel = edit(self.files[PANEL], PROGRESS_CALL, PROGRESS_FAKES)
        receipt = self.receipt(with_file(self.files, PANEL, panel))
        self.assertEqual(self.binding(receipt, key)["sites"], [])
        self.assertFalse(self.problems(receipt, "binding-unresolved"))
        # Unsupported forms on the real seam are explicit, never assumed.
        for name, call, construct in (
                ("method call", b'Nexus.Localization:Text("panel.heading.progress")',
                 "method-call"),
                ("indirect reference", b'local T2 = Nexus.Localization.Text',
                 "indirect-key-method"),
                ("method alias call",
                 b'local T2 = Nexus.Localization.Text; T2("panel.heading.progress")',
                 "indirect-key-method"),
                ("rawget reference", b'local T2 = rawget(Nexus.Localization, "Text")',
                 "indirect-key-method"),
                ("reassigned alias",
                 b'do local L2 = Nexus.Localization; L2 = {}; L2.Text("panel.heading.progress") end',
                 "alias")):
            with self.subTest(form=name):
                changed = edit(panel, PROGRESS_FAKES,
                               PROGRESS_FAKE_CODE + b" " + call + PROGRESS_FAKE_COMMENT)
                receipt = self.gate_fails(with_file(self.files, PANEL, changed))
                self.assertEqual(self.binding(receipt, key)["sites"], [])
                self.assertEqual([problem["construct"] for problem in
                                  self.problems(receipt, "binding-unresolved")], [construct])
        # A supported alias of the real seam does bind.
        # Review fix 1 oracle correction: the alias call must also show its
        # result; a discarded alias call is no consumer.
        alias = (b' do local L2 = Nexus.Localization; progressLabel:SetText('
                 b'L2.Text("panel.heading.progress")) end')
        changed = edit(panel, PROGRESS_FAKES, PROGRESS_FAKE_CODE + alias + PROGRESS_FAKE_COMMENT)
        receipt = assert_current_bindings(self, self.catalog,
                                          binding_args(with_file(self.files, PANEL, changed)))
        self.assertEqual([site["receiver"]["form"] for site in self.binding(receipt, key)["sites"]],
                         ["alias"])

    def test_c9_orphan_references_and_seam_mutation_fail(self):
        orphan = edit(self.files[PANEL], PROGRESS_CALL,
                      PROGRESS_CALL + b' local o = Nexus.Localization.Text("panel.never_declared")')
        receipt = self.gate_fails(with_file(self.files, PANEL, orphan))
        self.assertEqual([(problem["code"], problem["key"]) for problem in receipt["problems"]],
                         [("binding-orphan", "panel.never_declared")])
        mapped = edit(self.files[USER_TEXT], b'    ["STORE_PENDING"]="reason.saved_data_reading",\n',
                      b'    ["STORE_PENDING"]="reason.saved_data_reading",\n'
                      b'    ["NEVER"]="reason.never_declared",\n')
        receipt = self.gate_fails(with_file(self.files, USER_TEXT, mapped))
        self.assertEqual([(problem["code"], problem["key"]) for problem in receipt["problems"]],
                         [("binding-orphan", "reason.never_declared")])
        for name, line in (("seam field", b' Nexus.Localization.Text = tostring'),
                           ("seam table", b' Nexus.Localization = {}'),
                           ("global", b' Nexus = {}')):
            with self.subTest(mutation=name):
                changed = edit(self.files[PANEL], PROGRESS_CALL, PROGRESS_CALL + line)
                receipt = self.gate_fails(with_file(self.files, PANEL, changed))
                self.assertEqual([problem["code"] for problem in receipt["problems"]],
                                 ["binding-mutation"])

    def test_c10_unparseable_loaded_source_fails(self):
        broken = edit(self.files[READOUT], b"local M = {}\n", b"local M = {\n")
        receipt = self.gate_fails(with_file(self.files, READOUT, broken))
        rows = {row["path"]: row["analysis"] for row in receipt["sources"]}
        self.assertEqual(rows[READOUT], "UNPARSED")
        self.assertEqual([(problem["code"], problem["path"])
                          for problem in self.problems(receipt, "binding-unparsed")],
                         [("binding-unparsed", READOUT)])
        self.assertEqual(self.binding(receipt, CHARGE)["binding"], "UNBOUND")

    def test_c11_lf_and_crlf_bind_alike_with_exact_hashes(self):
        # Every file on a binding or output chain, both TOCs and the registry
        # Lua sources change representation; the others keep their bytes.
        chained = set(INPUTS + CONSUMER_TOCS) | {PANEL, READOUT, USER_TEXT, "core/Main.lua",
                                                 "core/WishlistController.lua",
                                                 "ui/JournalTab.lua", "ui/WishlistEditor.lua",
                                                 "companion/NexusSupport/Storage.lua"}
        receipts = {}
        for name in ("lf", "crlf"):
            files = {path: representations(data)[name]
                     if path in chained and path.endswith((".lua", ".toc")) else data
                     for path, data in self.files.items()}
            receipts[name] = assert_current_bindings(self, self.catalog, binding_args(files))
            for row in receipts[name]["sources"]:
                data = files[row["path"]]
                self.assertEqual(row["sha256"], hashlib.sha256(data).hexdigest())
        self.assertNotEqual([row["sha256"] for row in receipts["lf"]["sources"]],
                            [row["sha256"] for row in receipts["crlf"]["sources"]])

        def semantic(receipt):
            return (receipt["keys"], receipt["mapChains"], receipt["dynamicUnknown"],
                    receipt["counts"])
        self.assertEqual(semantic(receipts["lf"]), semantic(receipts["crlf"]))

    def test_c12_pure_deterministic_and_never_mutates_caller_inputs(self):
        args = binding_args(self.files)
        expected = self.report(*args)
        mutable = [bytearray(value) for value in args[:5]]
        tocs = [dict(row, data=bytearray(row["data"])) for row in args[5]]
        sources = [dict(row, data=bytearray(row["data"])) for row in args[6]]
        before = json.dumps([[bytes(value).hex() for value in mutable],
                             [dict(row, data=bytes(row["data"]).hex()) for row in tocs + sources]])
        self.assertEqual(self.report(*mutable, tocs, sources), expected)
        after = json.dumps([[bytes(value).hex() for value in mutable],
                            [dict(row, data=bytes(row["data"]).hex()) for row in tocs + sources]])
        self.assertEqual(after, before)
        json.dumps(expected, sort_keys=True).encode("ascii")
        blocked = ProvenanceTests.blocked_calls()
        try:
            self.assertEqual(self.report(*args), expected)
        finally:
            blocked()
        # A caller that rewrites every nested value of a returned receipt
        # cannot change the next receipt through the parse memo.
        snapshot = json.dumps(expected, sort_keys=True)
        stack = [self.report(*args)]
        while stack:
            value = stack.pop()
            items = value.items() if type(value) is dict else enumerate(value) \
                if type(value) is list else ()
            for index, item in list(items):
                if type(item) in (dict, list):
                    stack.append(item)
                else:
                    value[index] = "poisoned"
        self.assertEqual(json.dumps(self.report(*args), sort_keys=True), snapshot)
        # The earlier seams give the same results with the binding seam present.
        registry = args[:5]
        self.assertEqual(self.catalog.registry_catalog_report(*registry)["registry"]
                         ["declarationCount"], 28)
        self.assertIs(self.catalog.registry_catalog_diagnostics(*registry)["valid"], True)
        self.assertIs(self.catalog.pack_provenance_diagnostics(*registry)["valid"], True)

    def test_c13_binding_stays_apart_from_family_status_and_dynamic_leads(self):
        receipt = assert_current_bindings(self, self.catalog, binding_args(self.files))
        # Five keys are bound and still family-unclassified; no family is
        # adopted or complete because of a binding.
        unclassified = [row["key"] for row in receipt["keys"]
                        if row["family"]["state"] == "UNCLASSIFIED"]
        self.assertEqual(unclassified, list(MAPPED_KEYS))
        self.assertEqual({row["binding"] for row in receipt["keys"]
                          if row["key"] in unclassified}, {"MAPPED_TO_CONSUMER"})
        self.assertEqual(receipt["completeness"]["established"], False)
        # Dynamic constructs are listed, never counted toward a key.
        for row in receipt["dynamicUnknown"]:
            self.assertNotIn("key", row)
        self.assertEqual(receipt["counts"]["dynamicUnknown"], len(receipt["dynamicUnknown"]))

    def test_c14_an_invalid_catalog_gets_no_binding_receipt(self):
        core = "core/Localization.lua"
        changed = with_file(self.files, core, edit(self.files[core], b"resultLimit = 254",
                                                   b"resultLimit = 253"))
        with self.assertRaises(self.catalog.CatalogRegistryError) as raised:
            self.receipt(changed)
        self.assertEqual((raised.exception.code, raised.exception.key), ("registry-limit", CHARGE))

    def test_c15_a_localization_result_must_reach_an_output(self):
        # Review fix 1 (SPEC-147-S8-1): a call whose result is overwritten,
        # discarded or only reaches an unused helper never binds.
        user, key = self.files[USER_TEXT], "panel.heading.progress"
        call = b"local text,source=localization.Text(key)"
        receipt = self.gate_fails(with_file(self.files, USER_TEXT, edit(
            user, call, call + b"\n        text=code")))
        self.assertEqual([row["key"] for row in receipt["keys"] if row["binding"] == "UNBOUND"],
                         list(MAPPED_KEYS))
        self.assertEqual(receipt["mapChains"][0]["wrapperReturnsResult"], False)
        self.assertEqual({site["reason"] for key in MAPPED_KEYS
                          for site in self.binding(receipt, key)["unprovenSites"]},
                         {"wrapper-result-not-returned"})
        discard = (b'local function SpecProgress(key) Nexus.Localization.Text(key); return '
                   b'"Progress" end; progressLabel:SetText(SpecProgress("panel.heading.progress"))')
        receipt = self.gate_fails(with_file(self.files, PANEL, edit(
            self.files[PANEL], PROGRESS_CALL, discard)))
        self.assertEqual([(problem["code"], problem["key"]) for problem in receipt["problems"]],
                         [("binding-unbound", key)])
        self.assertEqual([site["reason"] for site in self.binding(receipt, key)["unprovenSites"]],
                         ["wrapper-result-not-returned"])
        # A result only compared, never shown, is no output either; shown
        # through 'and'/'or' and '..' it is.
        compared = (b'progressLabel:SetText(Nexus.Localization.Text("panel.heading.progress") '
                    b'== "x" and "Yes" or "No")')
        receipt = self.gate_fails(with_file(self.files, PANEL, edit(
            self.files[PANEL], PROGRESS_CALL, compared)))
        self.assertEqual([site["reason"] for site in self.binding(receipt, key)["unprovenSites"]],
                         ["output-not-reached"])
        joined = (b'progressLabel:SetText(ready and ("> " .. Nexus.Localization.Text('
                  b'"panel.heading.progress")) or "")')
        assert_current_bindings(self, self.catalog, binding_args(with_file(
            self.files, PANEL, edit(self.files[PANEL], PROGRESS_CALL, joined))))
        # All seven real dispatcher callers disconnected: the mapped keys go,
        # and an unused helper that discards a Message result does not restore them.
        callers = {"core/WishlistController.lua": (b"Nexus.UserText.Message(message)",),
                   READOUT: (b"Nexus.UserText.Message(model.text)",),
                   PANEL: (b"userText.Message(raw)", b"Nexus.UserText.Message(reason)"),
                   "ui/JournalTab.lua": (b"Nexus.UserText.Message(text)",),
                   "ui/WishlistEditor.lua": (b"Nexus.UserText.Message(message)",),
                   "core/Main.lua": (b"Nexus.UserText.Message(msg)",)}
        changed = dict(self.files)
        for path, needles in callers.items():
            for needle in needles:
                changed[path] = edit(changed[path], needle,
                                     needle.replace(b".Message(", b".MessageDisconnected("))
        receipt = self.gate_fails(changed)
        self.assertEqual([row["key"] for row in receipt["keys"] if row["binding"] == "UNBOUND"],
                         list(MAPPED_KEYS))
        changed["core/WishlistController.lua"] += (
            b'\nlocal function SpecUnusedReasonCall() local ignored=Nexus.UserText.Message('
            b'"STORE_PENDING"); return "constant" end\n')
        receipt = self.gate_fails(changed)
        self.assertEqual([row["key"] for row in receipt["keys"] if row["binding"] == "UNBOUND"],
                         list(MAPPED_KEYS))
        self.assertEqual(receipt["mapChains"][0]["established"], False)
        # One real caller restored with its chat output binds them again.
        restored = with_file(changed, "core/Main.lua", self.files["core/Main.lua"])
        receipt = assert_current_bindings(self, self.catalog, binding_args(restored))
        self.assertEqual({(output["path"], output["output"])
                          for output in receipt["mapChains"][0]["outputs"]},
                         {("core/Main.lua", "AddMessage")})

    def test_c16_a_module_alias_overwriting_the_dispatcher_is_unresolved(self):
        # Review fix 2 (SPEC-147-S8-2): a field written through a local alias
        # of the exported module is a definition of that module's field.
        user = self.files[USER_TEXT]
        overwrite = (b'\nlocal userTextAlias=T\nuserTextAlias.Message=function(value) return '
                     b'tostring(value or "") end\n')
        receipt = self.gate_fails(with_file(self.files, USER_TEXT, user + overwrite))
        self.assertEqual([(problem["construct"], problem["detail"]) for problem
                          in self.problems(receipt, "binding-unresolved")],
                         [("dispatcher", "T.Message has 2 definitions, directly or through a "
                                         "local alias")])
        self.assertEqual([row["key"] for row in receipt["keys"] if row["binding"] == "UNBOUND"],
                         list(MAPPED_KEYS))
        for name, tail, detail in (
                ("escaping module", b'\nlocal function Keep(t) return t end Keep(T)\n',
                 "the module table T is assigned again, written through a computed key or "
                 "escapes its file"),
                ("computed field", b'\nlocal fieldName="Message" T[fieldName]=tostring\n',
                 "the module table T is assigned again, written through a computed key or "
                 "escapes its file"),
                ("exported path assigned", b'\nNexus.UserText.Message=tostring\n',
                 "Nexus.UserText or Nexus.UserText.Message is assigned elsewhere")):
            with self.subTest(form=name):
                receipt = self.gate_fails(with_file(self.files, USER_TEXT, user + tail))
                self.assertEqual([problem["detail"] for problem
                                  in self.problems(receipt, "binding-unresolved")], [detail])
        # A same-named alias in another function is a different local.
        benign = (b'\nlocal function SpecOtherScope() local localization=Nexus.Other; '
                  b'localization={}; return localization.Text("not.a.binding") end\n')
        assert_current_bindings(self, self.catalog,
                                binding_args(with_file(self.files, USER_TEXT, user + benign)))

    def test_c17_both_product_tocs_are_required(self):
        # Review fix 3 (SPEC-147-S8-3): the companion TOC and its source cannot
        # disappear together; a TOC outside the product contract is refused.
        support, storage = CONSUMER_TOCS[1], "companion/NexusSupport/Storage.lua"
        paired = dict(self.files)
        del paired[support], paired[storage]
        args = binding_args(paired)
        self.assertEqual((len(args[5]), len(args[6])), (1, 99))
        self.assertEqual(self.refuse(args, "consumer-toc-required").path, support)
        alone = dict(self.files)
        del alone[support]
        self.assertEqual(self.refuse(binding_args(alone, extra=((storage, self.files[storage]),)),
                                     "consumer-toc-required").path, support)
        self.assertEqual(self.refuse(binding_args(self.files, omit=(storage,)),
                                     "consumer-source-missing").path, storage)
        args = binding_args(self.files)
        args[5] = args[5] + [record("tools/Other.toc", b"Other.lua\n")]
        self.assertEqual(self.refuse(args, "consumer-toc-unknown").path, "tools/Other.toc")
        # A genuine addition to a product TOC is derived from its bytes.
        added = "companion/NexusSupport/Extra.lua"
        grown = with_file(self.files, support, self.files[support] + b"Extra.lua\n")
        grown[added] = b"local x = 1\n"
        receipt = assert_current_bindings(self, self.catalog, binding_args(grown))
        self.assertEqual(len(receipt["sources"]), 101)
        self.assertEqual(receipt["tocs"][1]["loaded"], [storage, added])
        self.refuse(binding_args(with_file(self.files, support, grown[support])),
                    "consumer-source-missing")

    def test_c18_accurately_rehashed_benign_source_changes_stay_admissible(self):
        panel = self.files[PANEL] + b"\r\n-- A benign comment; the Panel semantics are unchanged.\r\n"
        receipt = assert_current_bindings(self, self.catalog,
                                          binding_args(with_file(self.files, PANEL, panel)))
        row = next(row for row in receipt["sources"] if row["path"] == PANEL)
        self.assertEqual((row["sha256"], row["byteLength"]),
                         (hashlib.sha256(panel).hexdigest(), len(panel)))
        self.assertNotEqual(row["sha256"], hashlib.sha256(self.files[PANEL]).hexdigest())


class ConsumerCommandLineTests(unittest.TestCase):
    """S8: --consumers reads both TOCs and every Lua file they load from the
    confined root and prints one consumers record; the earlier modes are
    unchanged."""

    def run_process(self, *args):
        return subprocess.run([sys.executable, "-B", str(CATALOG_TOOL), *[str(a) for a in args]],
                              capture_output=True, cwd=str(ROOT))

    def run_cli(self, *args):
        """main() of the shared loaded tool in this process, with the exact
        stdout and stderr bytes it writes; one real process run is kept in
        test_repository_root, and the parse memo keeps the rest within the
        registered time budget."""
        import io
        out, err = io.TextIOWrapper(io.BytesIO()), io.TextIOWrapper(io.BytesIO())
        saved = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = out, err
        try:
            code = s8_catalog().main([str(arg) for arg in args])
        finally:
            sys.stdout, sys.stderr = saved
        return subprocess.CompletedProcess(args, code, out.buffer.getvalue(),
                                           err.buffer.getvalue())

    def copy_root(self, root, files):
        for relative, value in files.items():
            target = root.joinpath(*relative.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)

    def test_repository_root(self):
        # main() on the actual repository root reads both TOCs and all 100
        # loaded files itself and writes exactly the API receipt.
        run = self.run_cli("--consumers")
        self.assertEqual((run.returncode, run.stderr), (0, b""))
        record = json.loads(run.stdout)
        self.assertEqual((record["record"], record["exitCode"]), ("consumers", 0))
        expected = s8_catalog().consumer_binding_report(*binding_args(s8_files()))
        self.assertEqual(record["consumers"], json.loads(json.dumps(expected)))
        self.assertEqual(len(record["consumers"]["sources"]), 100)
        # A real process on a small confined root: the same entry point, exit
        # status and one record, with unbound keys there (exit 2).
        files = s8_files()
        small = {path: files[path] for path in INPUTS + CONSUMER_TOCS[1:]
                 + ("companion/NexusSupport/Storage.lua",)}
        small["Nexus.toc"] = b"".join(line for line in files["Nexus.toc"].splitlines(True)
                                      if b"Localization" in line or line.startswith(b"#"))
        with tempfile.TemporaryDirectory() as temp:
            self.copy_root(Path(temp), small)
            process = self.run_process("--root", temp, "--consumers")
            self.assertEqual((process.returncode, process.stderr), (2, b""))
            self.assertEqual(process.stdout, self.run_cli("--root", temp, "--consumers").stdout)
            receipt = json.loads(process.stdout)["consumers"]
            self.assertEqual((len(receipt["sources"]), receipt["counts"]["UNBOUND"]), (4, 28))
        held = self.run_cli("--consumers", "--require-complete")
        self.assertEqual((held.returncode, json.loads(held.stdout)["exitCode"]), (1, 1))
        for args, code in ((("--consumers", "--consumers"), "argument-duplicate"),
                           (("--consumers", "--diagnose"), "argument-conflict"),
                           (("--provenance", "--consumers"), "argument-conflict")):
            with self.subTest(args=args):
                run = self.run_cli(*args)
                self.assertEqual((run.returncode, run.stdout), (2, b""))
                self.assertEqual(json.loads(run.stderr)["code"], code)

    def test_mutated_root_fails_only_in_consumers_mode(self):
        files = s8_files()
        files[PANEL] = edit(files[PANEL], PROGRESS_CALL, PROGRESS_FAKES)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.copy_root(root, files)
            before = {path: path.read_bytes() for path in root.rglob("*") if path.is_file()}
            run = self.run_cli("--root", root, "--consumers")
            self.assertEqual((run.returncode, run.stderr), (2, b""))
            receipt = json.loads(run.stdout)["consumers"]
            self.assertIs(receipt["valid"], False)
            self.assertEqual([problem["code"] for problem in receipt["problems"]],
                             ["binding-unbound"])
            for args in ((), ("--registry",), ("--diagnose",), ("--provenance",)):
                with self.subTest(args=args):
                    self.assertEqual(self.run_cli("--root", root, *args).returncode, 0)
            after = {path: path.read_bytes() for path in root.rglob("*") if path.is_file()}
            self.assertEqual(after, before)

    def test_unsafe_or_missing_listed_source_fails(self):
        files = s8_files()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            self.copy_root(root, files)
            (Path(temp) / "outside.lua").write_bytes(b"local x = 1\n")
            toc = root / "Nexus.toc"
            toc.write_bytes(edit(files["Nexus.toc"], b"core\\Main.lua\n",
                                 b"core\\Main.lua\n..\\outside.lua\n"))
            run = self.run_cli("--root", root, "--consumers")
            self.assertEqual((run.returncode, run.stdout), (2, b""))
            error = json.loads(run.stderr)
            self.assertEqual((error["code"], error["subject"]), ("consumer-toc-entry", "Nexus.toc"))
            toc.write_bytes(files["Nexus.toc"])
            (root / "ui" / "Readout.lua").unlink()
            run = self.run_cli("--root", root, "--consumers")
            self.assertEqual((run.returncode, run.stdout), (2, b""))
            error = json.loads(run.stderr)
            self.assertEqual((error["code"], error["subject"]), ("input-missing", READOUT))


if __name__ == "__main__":
    unittest.main()
