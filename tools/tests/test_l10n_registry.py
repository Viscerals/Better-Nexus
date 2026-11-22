"""Registry-bound localization catalog: the nonexecuting declaration parser,
the five-input API and report v2, the enum cross-check, the registry metadata, --registry,
and the S6 diagnostic receipt and --diagnose of tools/l10n_catalog.py (Refs #147, slices S2,
S5 and S6 of the R union). See tools/tests/l10n_registry_support.py for the full description.

Split from the single registry test file (SPLIT-PLAN.md): its classes are copied
verbatim; shared names come from tools/tests/l10n_registry_support.py. Synthetic offline
evidence only: no Lua runs, and this is not fluent, human or native evidence. Python 3.9+,
standard library only. Registered in PYTHON_TESTS of tools/run_prototype_tests.py.

Run directly:  python tools/tests/test_l10n_registry.py -v
"""

import importlib.util
import sys
import unittest
from pathlib import Path


def _registry_support():
    """tools/tests/l10n_registry_support.py, loaded once per process from its file path without
    writing bytecode (as load_catalog loads the tool), whatever the working directory."""
    name = "l10n_registry_support"
    if name not in sys.modules:
        previous = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        try:
            spec = importlib.util.spec_from_file_location(
                name, Path(__file__).resolve().with_name(name + ".py"))
            module = importlib.util.module_from_spec(spec)
            sys.modules[name] = module
            try:
                spec.loader.exec_module(module)
            except BaseException:
                del sys.modules[name]
                raise
        finally:
            sys.dont_write_bytecode = previous
    return sys.modules[name]


# Every name the original single test module defined outside its test classes (imports,
# constants, helpers, the shared tool and file memos, tearDownModule), bound here to the same
# objects, so these classes see the namespace they saw there.
globals().update({name: value for name, value in vars(_registry_support()).items()
                  if not name.startswith("__")})


class RegistryParserTests(unittest.TestCase):
    """S2: the nonexecuting parser of the delimited declaration block."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = s8_catalog()
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
        # Full visible-UI scope: the dated 28 stay first and unchanged; every
        # declaration equals its independently read context row.
        declarations = self.parse(self.source)
        self.assertEqual(list(declarations)[:len(CURRENT_KEYS)], list(CURRENT_KEYS))
        self.assertEqual(list(declarations), full_keys())
        self.assertEqual(len(declarations), CURRENT_FULL_UI_KEYS)
        self.assertEqual(declarations[CHARGE], CHARGE_DECLARATION)
        for key in CURRENT_KEYS:
            if key != CHARGE:
                self.assertEqual(declarations[key], {"kind": "text"}, key)
        for row in full_context_rows():
            with self.subTest(key=row["key"]):
                declaration = declarations[row["key"]]
                self.assertEqual(declaration["kind"], row["kind"])
                if row["kind"] == "template":
                    self.assertEqual(declaration, dict(
                        {"kind": "template",
                         "fields": tuple(slot["name"] for slot in row["placeholders"]),
                         "slots": tuple(slot["type"] for slot in row["placeholders"]),
                         "resultLimit": row["resultLimitBytes"]},
                        **({"lines": True} if row.get("lines") else {})))
                elif row["kind"] in ("text", "block"):
                    self.assertEqual(declaration, {"kind": row["kind"]})
        english = self.catalog.parse_english((ROOT / INPUTS[0]).read_bytes())
        context = json.loads((ROOT / INPUTS[2]).read_text(encoding="utf-8"))
        self.assertEqual(set(declarations), set(english))
        self.assertEqual(set(declarations), {row["key"] for row in context["keys"]})
        self.assertEqual(len(context["keys"]), CURRENT_FULL_UI_KEYS)

    def test_slice_a_legacy_meanings_have_matching_context_rows(self):
        # v33 slice A. Each of the 18 declared English meanings without a
        # context row must, after A, have exactly one row at its declaration
        # position. That row repeats the declared kind, the exact English,
        # the typed placeholders in declared order (each with a stated
        # meaning) and, for a template, the declared result limit; a text row
        # has none of these. The declarations and English are checked against
        # the independent oracle first, so a missing row is reported as the
        # context gap and not as declaration drift. At exact 35 every row is
        # missing (the real 18-row gap); no new meaning is added.
        self.assertEqual(len(SLICE_A_LEGACY_ROWS), 18)
        declarations = self.parse(self.source)
        english = self.catalog.parse_english((ROOT / INPUTS[0]).read_bytes())
        context = json.loads((ROOT / INPUTS[2]).read_text(encoding="utf-8"))
        rows = [row for row in context["keys"] if type(row) is dict]
        by_key = {}
        for index, row in enumerate(rows):
            by_key.setdefault(row.get("key"), []).append((index, row))
        order = list(declarations)
        for key, kind, slots, limit in SLICE_A_LEGACY_ROWS:
            with self.subTest(key=key):
                if kind == "template":
                    self.assertEqual(declarations.get(key), {
                        "kind": "template", "fields": tuple(name for name, _ in slots),
                        "slots": tuple(slot for _, slot in slots), "resultLimit": limit})
                else:
                    self.assertEqual(declarations.get(key), {"kind": "text"})
                self.assertIn(key, english)
                found = by_key.get(key, [])
                self.assertEqual(len(found), 1, "slice A: exactly one KEY_CONTEXT row for " + key)
                index, row = found[0]
                self.assertEqual(index, order.index(key),
                                 "the context row stands at its declaration position")
                self.assertEqual(row.get("kind"), kind)
                self.assertEqual(row.get("english"), english[key])
                self.assertIs(type(row.get("meaning")), str)
                self.assertNotEqual(row["meaning"].strip(), "")
                placeholders = row.get("placeholders")
                self.assertIs(type(placeholders), list)
                self.assertEqual([(slot.get("name"), slot.get("type")) for slot in placeholders],
                                 list(slots))
                for slot in placeholders:
                    self.assertIs(type(slot.get("meaning")), str)
                    self.assertNotEqual(slot["meaning"].strip(), "")
                if limit is None:
                    self.assertNotIn("resultLimitBytes", row)
                else:
                    self.assertEqual(row.get("resultLimitBytes"), limit)
                self.assertNotIn("lines", row)
        # After A the three key sets are equal at 4096: no gap and no extra.
        context_keys = {row.get("key") for row in rows}
        self.assertEqual(sorted(set(english) - context_keys), [],
                         "English meanings without a context row")
        self.assertEqual(sorted(context_keys - set(english)), [],
                         "context rows without an English meaning")
        self.assertEqual((len(declarations), len(english), len(rows)), (CURRENT_FULL_UI_KEYS,) * 3)

    def test_slice_bc_new_meanings_are_declared_english_and_context_rows_in_order(self):
        # v39 (B/C RED). The 20 accepted meanings are the LAST 20 declarations,
        # English entries and context rows, in SLICE_BC_NEW_ROWS order. Each
        # is declared with the oracle's kind, typed fields and limit; its
        # English is exactly the accepted text; its context row repeats the
        # kind, the English, the typed placeholders in order (each with a
        # meaning), the limit (absent for text and block) and a non-empty
        # meaning, with no lines flag. FAQ questions are static text of at most
        # 256 bytes, FAQ answers blocks of at most 1024, neither with a
        # placeholder or a '|'. The bounded limit is unchanged.
        self.assertEqual(len(SLICE_BC_NEW_ROWS), 20)
        declarations = self.parse(self.source)
        english = self.catalog.parse_english((ROOT / INPUTS[0]).read_bytes())
        context = json.loads((ROOT / INPUTS[2]).read_text(encoding="utf-8"))
        rows = [row for row in context["keys"] if type(row) is dict]
        keys = [key for key, _, _, _, _ in SLICE_BC_NEW_ROWS]
        # The Orb Start/Stop line and Tome checkbox follow the 20 B/C keys.
        tail = ["orb.status.run_until_goal", "readout.menu.auto_manage_tomes"]
        self.assertEqual(list(declarations)[-22:-2], keys, "the 20 are the last declarations before these two keys, in order")
        self.assertEqual(list(english)[-22:-2], keys, "the 20 are the last English entries before these two keys, in order")
        self.assertEqual([row.get("key") for row in rows[-22:-2]], keys, "the 20 are the last context rows before these two keys, in order")
        self.assertEqual((list(declarations)[-2:], list(english)[-2:], [row.get("key") for row in rows[-2:]]),
                         (tail, tail, tail), "the Orb and Tome meanings are last in declarations, English and context")
        for key, kind, text, slots, limit in SLICE_BC_NEW_ROWS:
            with self.subTest(key=key):
                if kind == "template":
                    self.assertEqual(declarations.get(key), {
                        "kind": "template", "fields": tuple(name for name, _ in slots),
                        "slots": tuple(slot for _, slot in slots), "resultLimit": limit})
                else:
                    self.assertEqual(declarations.get(key), {"kind": kind})
                self.assertEqual(english.get(key), text)
                if key.startswith("help."):
                    self.assertEqual(slots, ())
                    self.assertNotIn("|", text)
                    self.assertNotIn("{", text)
                    if key.startswith("help.label."):
                        self.assertEqual(kind, "text")
                        self.assertLessEqual(len(text.encode("utf-8")), 256)
                        self.assertNotIn("\n", text)
                    else:
                        self.assertEqual(kind, "block")
                        self.assertLessEqual(len(text.encode("utf-8")), 1024)
                found = [row for row in rows if row.get("key") == key]
                self.assertEqual(len(found), 1, "exactly one KEY_CONTEXT row for " + key)
                row = found[0]
                self.assertEqual(row.get("kind"), kind)
                self.assertEqual(row.get("english"), text)
                self.assertIs(type(row.get("meaning")), str)
                self.assertNotEqual(row["meaning"].strip(), "")
                placeholders = row.get("placeholders")
                self.assertIs(type(placeholders), list)
                self.assertEqual([(slot.get("name"), slot.get("type")) for slot in placeholders], list(slots))
                for slot in placeholders:
                    self.assertIs(type(slot.get("meaning")), str)
                    self.assertNotEqual(slot["meaning"].strip(), "")
                if limit is None:
                    self.assertNotIn("resultLimitBytes", row)
                else:
                    self.assertEqual(row.get("resultLimitBytes"), limit)
                self.assertNotIn("lines", row)
        self.assertEqual((len(declarations), len(english), len(rows)), (CURRENT_FULL_UI_KEYS,) * 3)
        self.assertLessEqual(CURRENT_FULL_UI_KEYS, RUNTIME_CAP)

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
        # The runtime cap (MAX_BASE_ENTRIES: 64 for the pilot cohort, 4096,
        # then the bounded 5120 of v33 slice A): the cap is accepted and one
        # more declaration is refused. The key names stay within the key
        # schema at 5120 ("reason.k5119").
        items = ['["reason.k%04d"] = {kind = "text"},' % index for index in range(RUNTIME_CAP)]
        self.assertEqual(len(self.parse(block(*items))), RUNTIME_CAP)
        items.append('["reason.k%04d"] = {kind = "text"},' % RUNTIME_CAP)
        self.refuse(block(*items), self.catalog.CatalogRegistryError, "registry-too-many")

    def test_block_and_template_declarations_follow_the_runtime_schema(self):
        # Full visible-UI kinds, as TemplateSchema admits them (count or text
        # slots, a whole limit from 1 to 2048, lines absent or true).
        error = self.catalog.CatalogRegistryError
        template = ('["reason.alpha"] = {kind = "template", fields = %s, slots = %s,'
                    ' resultLimit = %s%s},')
        good = ('{"name", "count"}', '{"text", "count"}', "300", "")
        self.assertEqual(self.parse(block('["reason.alpha"] = {kind = "block"},')),
                         {"reason.alpha": {"kind": "block"}})
        self.assertEqual(self.parse(block(template % good)), {"reason.alpha": {
            "kind": "template", "fields": ("name", "count"), "slots": ("text", "count"),
            "resultLimit": 300}})
        self.assertEqual(self.parse(block(template % (good[:3] + (", lines = true",)))),
                         {"reason.alpha": {"kind": "template", "fields": ("name", "count"),
                                           "slots": ("text", "count"), "resultLimit": 300,
                                           "lines": True}})
        self.assertEqual(self.parse(block(template % (good[:2] + ("2048", ""))))
                         ["reason.alpha"]["resultLimit"], 2048)
        cases = (
            ('["reason.alpha"] = {kind = "block", lines = true},', "registry-field"),
            (template % (good[:3] + (", lines = false",)), "registry-field"),
            (template % (good[:3] + (', lines = "true"',)), "registry-field"),
            (template % (good[:3] + (", slot = \"count\"",)), "registry-field"),
            ('["reason.alpha"] = {kind = "template", fields = {"name"}, resultLimit = 9},',
             "registry-field"),
            (template % ("{}", "{}", "300", ""), "registry-placeholders"),
            (template % ('{"name", "name"}', good[1], "300", ""), "registry-placeholders"),
            (template % ('{"Name"}', '{"text"}', "300", ""), "registry-placeholders"),
            (template % (good[0], '{"text"}', "300", ""), "registry-slot"),
            (template % (good[0], '{"text", "number"}', "300", ""), "registry-slot"),
            (template % (good[0], '{"text", "count", "text"}', "300", ""), "registry-slot"),
            (template % (good[0], '"text"', "300", ""), "registry-slot"),
            (template % (good[0], good[1], "0", ""), "registry-limit"),
            (template % (good[0], good[1], "2049", ""), "registry-limit"),
            (template % (good[0], good[1], '"300"', ""), "registry-limit"),
            (template % (good[0], good[1], "true", ""), "registry-limit"),
            ('["reason.alpha"] = {kind = "Template"},', "registry-kind"),
        )
        for item, code in cases:
            with self.subTest(item=item):
                raised = self.refuse(block(item), error, code)
                self.assertIn(raised.code, self.catalog.REGISTRY_CODES)

    def test_comments_inside_the_block_are_whitespace(self):
        source = block("-- a comment", TEXT_ITEM, "--[[ long ]]", CHARGE_ITEM)
        self.assertEqual(list(self.parse(source)), ["reason.alpha", CHARGE])


class RegistryApiTests(unittest.TestCase):
    """S5: the five-input registry-bound API, distinct from the four-input API."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = s8_catalog()
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
        self.assertEqual(list(result["declarations"]), full_keys())
        self.assertEqual(list(result["declarations"])[:len(CURRENT_KEYS)], list(CURRENT_KEYS))
        self.assertEqual(set(result["english"]), set(full_keys()))
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
                self.assertEqual(len(parsed), CURRENT_FULL_UI_KEYS - 1)
                self.assertEqual(self.verdict(*self.with_input(0, data)), ("valid", None))
                self.assertEqual(self.verdict(*self.with_input(0, english)),
                                 ("english-incomplete", "panel.button.options"))

    def test_invalid_english_for_a_declared_key_is_refused_as_invalid(self):
        english = replace_once(self.inputs[0], OPTIONS_LINE, OPTIONS_LINE.replace(b'"Options"',
                                                                                  b'"Opt|ions"'))
        self.assertEqual(self.verdict(*self.with_input(0, english)),
                         ("invalid-text", "panel.button.options"))
        english = replace_once(self.inputs[0], b'"B:{banish} R:{reroll} F:{freeze}"',
                               b'"B:{banish} R:{reroll}"')
        self.assertEqual(self.verdict(*self.with_input(0, english)), ("invalid-template", CHARGE))

    def test_key_context_must_equal_its_declaration(self):
        # R-P2 (C14): kind, placeholder names in order and type, limit and,
        # for a template, the lines flag. Each edit is made inside one row of
        # the actual (pretty-printed) document, every other byte kept.
        lf = self.inputs[2].replace(b"\r\n", b"\n")
        slot = b'{\n          "name": "%s",\n          "type": "%s"\n        }'
        placeholders = b",\n        ".join(slot % (name.encode(), b"count") for name in CHARGE_FIELDS)
        self.assertIn(placeholders, lf)
        anchor, guide, block_key = ("command.chat.anchor_set", "guide.body.target_c_select",
                                    "command.chat.wishlist_design_hint")
        cases = {
            "kind": row_edit(lf, CHARGE, b'"kind": "format",', b'"kind": "text",'),
            "text kind": row_edit(lf, "panel.button.options", b'"kind": "text",',
                                  b'"kind": "format",'),
            "order": row_edit(lf, CHARGE, placeholders, placeholders.replace(b"banish", b"@")
                              .replace(b"reroll", b"banish").replace(b"@", b"reroll")),
            "slot type": row_edit(lf, CHARGE, slot % (b"freeze", b"count"),
                                  slot % (b"freeze", b"number")),
            "missing slot": row_edit(lf, CHARGE, b",\n        " + slot % (b"freeze", b"count"), b""),
            "limit": row_edit(lf, CHARGE, b'"resultLimitBytes": 254,', b'"resultLimitBytes": 253,'),
            # Full visible-UI kinds under the same rule.
            "template slot type": row_edit(lf, anchor, b'"type": "text",', b'"type": "count",'),
            "template limit": row_edit(lf, anchor, b'"resultLimitBytes": 154,',
                                       b'"resultLimitBytes": 155,'),
            "template lines removed": row_edit(lf, guide, b'\n      "lines": true,', b""),
            "template lines added": row_edit(lf, anchor, b'"resultLimitBytes": 154,',
                                             b'"resultLimitBytes": 154,\n      "lines": true,'),
            "block as text": row_edit(lf, block_key, b'"kind": "block",', b'"kind": "text",'),
            "text as block": row_edit(lf, "panel.button.options", b'"kind": "text",',
                                      b'"kind": "block",'),
        }
        keys = {"text kind": "panel.button.options", "text as block": "panel.button.options",
                "template slot type": anchor, "template limit": anchor,
                "template lines removed": guide, "template lines added": anchor,
                "block as text": block_key}
        self.assertEqual(self.verdict(*self.with_input(2, lf)), ("valid", None))
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
        cls.catalog = s8_catalog()
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
                          registry["keyContextRows"]), (CURRENT_FULL_UI_KEYS,) * 3)
        self.assertEqual([row["key"] for row in registry["declarations"]], full_keys())
        # A lines template row carries its typed placeholders, limit and flag.
        rows = {row["key"]: row for row in full_context_rows()}
        lines = [row for row in registry["declarations"] if row.get("lines")]
        self.assertEqual([row["key"] for row in lines],
                         [key for key, row in rows.items() if row.get("lines")])
        for row in lines[:3] + [row for row in registry["declarations"]
                                if row["kind"] in ("template", "block")][:3]:
            source = rows[row["key"]]
            expected = {"key": row["key"], "kind": source["kind"]}
            if source["kind"] == "template":
                expected.update({"placeholders": [{"name": slot["name"], "type": slot["type"]}
                                                  for slot in source["placeholders"]],
                                 "resultLimitBytes": source["resultLimitBytes"]})
            if source.get("lines"):
                expected["lines"] = True
            self.assertEqual(row, expected)
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
                                 ["registry"]["englishKeys"], CURRENT_FULL_UI_KEYS)
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
        catalog = s8_catalog()
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
        self.assertEqual(binding["declaredKeys"], CURRENT_FULL_UI_KEYS)
        self.assertEqual(binding["checkedFields"], ["kind", "placeholders", "resultLimitBytes",
                                                    "lines"])
        self.assertEqual(binding["mismatchCode"], "context-declaration-mismatch")
        self.assertEqual(binding["status"], "IMPLEMENTED_DRAFT_REVIEW_PENDING")


class RegistryCommandLineTests(unittest.TestCase):
    """--registry reads core/Localization.lua as a sixth fixed input and
    prints report v2; without it the command line is unchanged."""

    def run_cli(self, *args):
        return cli_in_process(*args)

    def test_registry_mode_on_the_repository_root(self):
        run = self.run_cli("--registry")
        process = cli_process("--registry")
        self.assertEqual((process.returncode, process.stdout, process.stderr),
                         (run.returncode, run.stdout, run.stderr))
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stderr, b"")
        record = json.loads(run.stdout)
        self.assertEqual(record["registryBinding"], "requested")
        self.assertEqual(record["report"]["schemaVersion"], 2)
        self.assertEqual(record["report"]["registry"]["declarationCount"], CURRENT_FULL_UI_KEYS)
        self.assertEqual([row["source"] for row in record["report"]["inputs"]], list(INPUTS))
        self.assertEqual(record["technicalCatalog"]["englishKeys"], CURRENT_FULL_UI_KEYS)
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
            target.write_bytes(replace_once(current_inputs()[4],
                                            b'kind = "format", slot = "count", resultLimit = 254',
                                            b'kind = "format", slot = "count", resultLimit = 253'))
            run = self.run_cli("--root", root, "--registry")
            self.assertEqual(run.returncode, 2)
            error = json.loads(run.stderr)
            self.assertEqual((error["errorClass"], error["code"], error["key"]),
                             ("CatalogRegistryError", "registry-limit", CHARGE))
            self.assertEqual(sorted(os.listdir(str(root))), ["Nexus.toc", "core", "data", "docs"])


class DiagnosticTests(unittest.TestCase):
    """S6: the opt-in, read-only diagnostic receipt beside the unchanged
    strict gate."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = s8_catalog()
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

    def test_d2_real_retired_tome_key_is_checked(self):
        context = json.loads((ROOT / INPUTS[2]).read_text(encoding="utf-8"))
        self.assertEqual(context["retiredKeys"]["keys"], ["readout.menu.tomes"])
        receipt = self.diagnose(*self.inputs)
        self.assertEqual(receipt["retiredKeys"], ["readout.menu.tomes"])
        self.assertTrue(receipt["valid"])
        self.assertEqual(receipt["problemCounts"]["obsolete"], 0)
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
        # A deliberately partial frFR pack: its one entries block keeps only
        # the dated cohort without panel.button.options, selected by key, one
        # line per entry; every other byte of the five inputs is kept.
        keep = set(CURRENT_KEYS) - {"panel.button.options"}
        source = self.inputs[1]
        block = list(re.finditer(
            rb"\n    frFR = \{\r?\n        name = \"[^\"\r\n]*\",\r?\n        entries = \{\r?\n"
            rb"((?: {12}\[\"[^\"\r\n]+\"\] = [^\r\n]*\r?\n)*)", source))
        self.assertEqual(len(block), 1)
        lines = block[0].group(1).splitlines(keepends=True)
        self.assertEqual(len(lines), len(self.catalog.parse_packs(source)["frFR"]["entries"]))
        kept = [line for line in lines
                if re.match(rb' {12}\["([^"\r\n]+)"\]', line).group(1).decode("utf-8") in keep]
        self.assertEqual(len(kept), len(keep))
        start, end = block[0].span(1)
        partial = list(self.inputs)
        # A controlled draft value: the one kept panel.button.my_builds row
        # takes a synthetic, plainly non-English test literal instead of the
        # corpus value, keeping its key, indentation and line break. It is
        # fixture text, not a translation; D4 makes this key English-identical.
        draft = "Lorem ipsum"
        english = self.catalog.parse_english(self.inputs[0])
        self.assertNotEqual(draft, english["panel.button.my_builds"])
        keys = [re.match(rb' {12}\["([^"\r\n]+)"\]', line).group(1) for line in kept]
        self.assertEqual(keys.count(b"panel.button.my_builds"), 1)
        index = keys.index(b"panel.button.my_builds")
        ending = kept[index][len(kept[index].rstrip(b"\r\n")):]
        kept[index] = (b'            ["panel.button.my_builds"] = "%s",' % draft.encode("utf-8")
                       + ending)
        partial[1] = source[:start] + b"".join(kept) + source[end:]
        self.assertEqual(set(self.catalog.parse_packs(partial[1])["frFR"]["entries"]), keep)
        # A controlled review baseline for this synthetic product: no existing
        # frFR entry-review declaration is inherited (some name entries that
        # the partial pack no longer has); every other product's declarations
        # and the rest of the document stay.
        document = json.loads(partial[3].decode("utf-8"))
        document["entryReview"]["declarations"] = [
            declaration for declaration in document["entryReview"]["declarations"]
            if declaration["productId"] != "frFR"]
        partial[3] = json.dumps(document, ensure_ascii=False, indent=2).encode("utf-8")
        data = multi_error_inputs(partial)
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
        packed = self.catalog.parse_packs(partial[1])["frFR"]["entries"]
        self.assertEqual(french["denominator"], CURRENT_FULL_UI_KEYS)
        self.assertEqual(french["keys"]["invalid"], [CHARGE, "reason.save_in_progress"])
        self.assertEqual(french["keys"]["missing"], sorted(set(full_keys()) - set(packed)))
        self.assertIn("panel.button.options", french["keys"]["missing"])
        self.assertEqual(french["keys"]["obsolete"], [RETIRED])
        self.assertEqual(french["counts"]["translated_and_reviewed"], 0)
        self.assertEqual(french["counts"]["draft_unreviewed"], 25)
        self.assertEqual(french["reconciliation"], {"denominator": CURRENT_FULL_UI_KEYS,
                                                    "inDenominatorTotal": CURRENT_FULL_UI_KEYS})
        for row in receipt["coverage"]["products"]:
            seen = [key for category in self.catalog.ENTRY_CATEGORIES[:6]
                    for key in row["keys"][category]]
            self.assertEqual(sorted(seen), sorted(full_keys()), row["productId"])
            self.assertNotIn(NEVER_KNOWN, row["keys"]["obsolete"])
            self.assertNotIn("Bad Key", sum(row["keys"].values(), []))
        self.assertEqual(rows["deDE"]["counts"], self.strict_report["products"][1]["counts"])
        self.assertEqual(receipt["coverage"]["denominator"]["englishKeys"], CURRENT_FULL_UI_KEYS)
        self.assertEqual(receipt["coverage"]["completeness"]["state"], "INCOMPLETE")
        codes = {reason["code"] for reason in receipt["coverage"]["completeness"]["reasons"]}
        self.assertTrue({"entries-invalid", "entries-obsolete"} <= codes)
        self.assertIs(receipt["completeness"]["established"], False)
        self.assertNotIn("100%", json.dumps(receipt))

    def test_d4_valid_partial_input_keeps_the_strict_report(self):
        # The same deliberately partial frFR pack as in D3, selected by key;
        # the strict report and the diagnosis read these same bytes.
        def entry_block(packs, pack_id):
            """The span of pack_id's one entries block and its entry lines,
            one line per parsed entry."""
            block = list(re.finditer(
                rb"\n    " + pack_id.encode() + rb" = \{\r?\n        name = \"[^\"\r\n]*\",\r?\n"
                rb"        entries = \{\r?\n"
                rb"((?: {12}\[\"[^\"\r\n]+\"\] = [^\r\n]*\r?\n)*)", packs))
            self.assertEqual(len(block), 1, pack_id)
            lines = block[0].group(1).splitlines(keepends=True)
            parsed = self.catalog.parse_packs(packs)[pack_id]["entries"]
            self.assertEqual(len(lines), len(parsed), pack_id)
            return block[0].span(1), lines

        def key_of(line):
            return re.match(rb' {12}\["([^"\r\n]+)"\]', line).group(1).decode("utf-8")

        keep = set(CURRENT_KEYS) - {"panel.button.options"}
        (start, end), lines = entry_block(self.inputs[1], "frFR")
        kept = [line for line in lines if key_of(line) in keep]
        self.assertEqual(len(kept), len(keep))
        partial = list(self.inputs)
        partial[1] = self.inputs[1][:start] + b"".join(kept) + self.inputs[1][end:]
        self.assertEqual(set(self.catalog.parse_packs(partial[1])["frFR"]["entries"]), keep)
        # A controlled review baseline for the two products of the controlled
        # examples below: no existing frFR or deDE entry-review declaration is
        # inherited; every other product's declarations and the rest of the
        # document stay. The one deDE declaration below is the only one.
        document = json.loads(partial[3].decode("utf-8"))
        document["entryReview"]["declarations"] = [
            declaration for declaration in document["entryReview"]["declarations"]
            if declaration["productId"] not in ("frFR", "deDE")]
        partial[3] = json.dumps(document, ensure_ascii=False, indent=2).encode("utf-8")
        strict = self.catalog.registry_catalog_report(*partial)
        receipt = self.diagnose(*partial)
        self.assertIs(receipt["valid"], True)
        self.assertEqual(receipt["strictVerdict"], {"result": "valid"})
        self.assertEqual(receipt["collection"], {"state": "COMPLETE", "boundary": None,
                                                 "rule": receipt["collection"]["rule"]})
        self.assertEqual(receipt["entryProblems"], [])
        self.assertEqual(receipt["problemCounts"], {"invalid": 0, "obsolete": 0, "orphan": 0})
        self.assertEqual(receipt["coverage"], strict)
        self.assertIs(receipt["completeness"]["established"], False)
        self.assertEqual(receipt["gate"], "NOT_A_GATE")
        # A synthetic declaration and an English-identical entry keep their
        # existing categories; fallback English is never an entry.
        english = self.catalog.parse_english(partial[0])
        packs = partial[1]
        # By key and in place: frFR's my_builds row takes the English text and
        # deDE's the synthetic text that the synthetic declaration names.
        for pack_id, text in (("frFR", english["panel.button.my_builds"]),
                              ("deDE", "Meine Builds")):
            (start, end), lines = entry_block(packs, pack_id)
            keys = [key_of(line) for line in lines]
            self.assertEqual(keys.count("panel.button.my_builds"), 1, pack_id)
            index = keys.index("panel.button.my_builds")
            ending = lines[index][len(lines[index].rstrip(b"\r\n")):]
            lines[index] = (b'            ["panel.button.my_builds"] = "%s",'
                            % text.encode("utf-8") + ending)
            packs = packs[:start] + b"".join(lines) + packs[end:]
        release = with_declaration(partial[3], "deDE", "panel.button.my_builds",
                                   "Meine Builds")
        data = [partial[0], packs, partial[2], release, partial[4]]
        receipt = self.diagnose(*data)
        report = self.catalog.registry_catalog_report(*data)
        self.assertEqual(receipt["coverage"], report)
        rows = {row["productId"]: row["counts"] for row in report["products"]}
        self.assertEqual(rows["frFR"]["deliberate_english_placeholder"], 1)
        self.assertEqual(rows["deDE"]["translated_and_reviewed"], 1)
        packed = self.catalog.parse_packs(partial[1])["frFR"]["entries"]
        self.assertEqual(rows["frFR"]["missing"], len(set(full_keys()) - set(packed)))
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
            "invalid English": (0, replace_once(english, OPTIONS_LINE, OPTIONS_LINE.replace(
                b'"Options"', b'"Opt|ions"'))),
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
        return cli_in_process(*args)

    def copy_root(self, root, data):
        for relative, value in zip(INPUTS, data):
            target = root.joinpath(*relative.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)
        shutil.copyfile(str(ROOT / "Nexus.toc"), str(root / "Nexus.toc"))

    def test_valid_repository_root(self):
        run = self.run_cli("--diagnose")
        process = cli_process("--diagnose")
        self.assertEqual((process.returncode, process.stdout, process.stderr),
                         (run.returncode, run.stdout, run.stderr))
        self.assertEqual((run.returncode, run.stderr), (0, b""))
        record = json.loads(run.stdout)
        self.assertEqual((record["record"], record["exitCode"]), ("diagnostics", 0))
        self.assertIs(record["diagnostics"]["valid"], True)
        self.assertEqual(record["diagnostics"]["coverage"]["registry"]["declarationCount"],
                         CURRENT_FULL_UI_KEYS)
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
