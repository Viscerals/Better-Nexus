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
        # R-P3 (C14).
        english = replace_once(self.inputs[0], b'    ["panel.button.options"] = "Options",\r\n', b"")
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
        english = replace_once(self.inputs[0], b'    ["panel.button.options"] = "Options",\r\n', b"")
        with self.assertRaises(self.catalog.CatalogRegistryError) as raised:
            self.catalog.registry_catalog_report(english, *self.inputs[1:])
        self.assertEqual(raised.exception.code, "english-incomplete")


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


if __name__ == "__main__":
    unittest.main()
