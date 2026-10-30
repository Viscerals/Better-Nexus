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


if __name__ == "__main__":
    unittest.main()
