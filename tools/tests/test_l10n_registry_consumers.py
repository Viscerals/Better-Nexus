"""Registry-bound localization catalog, S8 part 1: the registered current-repository
static consumer binding gate (C2) and its rule controls C0-C19 through consumer_binding_report
(Refs #147).

Split from the single registry test file (SPLIT-PLAN.md): its classes are copied
verbatim; shared names come from tools/tests/l10n_registry_support.py. Synthetic offline
evidence only: no Lua runs, and this is not fluent, human or native evidence. Python 3.9+,
standard library only. Registered in PYTHON_TESTS of tools/run_prototype_tests.py.

Run directly:  python tools/tests/test_l10n_registry_consumers.py -v
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


# Part 1 of 2 of the original ConsumerBindingTests (C0-C19, 23 tests). The other part is
# in test_l10n_registry_consumer_flow.py (C20-C38). Its setUpClass and helper
# methods are _ConsumerBindingMixin of l10n_registry_support.py, verbatim.
class ConsumerBindingTests(_ConsumerBindingMixin, unittest.TestCase):
    """S8: the registered current-repository static consumer binding gate
    and its negative controls on in-memory edits of the real bytes."""

    def test_c0_cohort_substrate_binds_the_dated_cohort_as_the_repository_does(self):
        # The substrate is real bytes: every file is the repository's own,
        # only Nexus.toc drops the lines of files outside it.
        for path, data in self.files.items():
            if path != "Nexus.toc":
                self.assertEqual(data, self.full_files[path], path)
        full = self.catalog.consumer_binding_report(*binding_args(self.full_files))
        cohort = self.catalog.consumer_binding_report(*binding_args(self.files))
        self.assertEqual([row["key"] for row in cohort["keys"]], full_keys())
        rows = {row["key"]: row for row in full["keys"]}
        for row in cohort["keys"][:len(CURRENT_KEYS)]:
            with self.subTest(key=row["key"]):
                self.assertEqual({field: row[field] for field in ("binding", "sites", "unprovenSites")},
                                 {field: rows[row["key"]][field]
                                  for field in ("binding", "sites", "unprovenSites")})
        # Two real chains, in file order: reasonKeys through SeamReason
        # (line 340), then localizedReasons through LocalizedReason.
        self.assertEqual([(chain["dispatcher"], chain["wrapper"]["name"])
                          for chain in cohort["mapChains"]],
                         [(DISPATCHER, "SeamReason"), (DISPATCHER, "LocalizedReason")])
        self.assertEqual([problem["code"] for problem in cohort["problems"]
                          if problem["code"] != "binding-unbound"], [])
        assert_binding_receipt(self, cohort_view(cohort))

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
        # The full gate: the real repository and every declared key.
        args = binding_args(self.full_files)
        receipt = assert_binding_receipt(self, self.catalog.consumer_binding_report(*args), full=True)
        # The gate ran on the real repository input set, not a fixture.
        self.assertEqual(len(args[6]), 100)
        self.assertEqual([row["path"] for row in receipt["tocs"]], list(CONSUMER_TOCS))
        self.assertEqual([row["path"] for row in receipt["sources"]],
                         [path for toc in CONSUMER_TOCS
                          for path in toc_listing(toc, self.full_files[toc])])
        for row in receipt["tocs"] + receipt["sources"]:
            data = self.full_files[row["path"]]
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
        self.assertEqual(sum(len(rows[key]["unprovenSites"]) for key in CURRENT_KEYS), 5)
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
        self.assertEqual(receipt["counts"]["keys"], CURRENT_FULL_UI_KEYS)
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
        self.assertEqual([(problem["code"], problem.get("key")) for problem in receipt["problems"]],
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

    def test_c3_excluded_leads_of_a_unit_with_more_lead_values_than_declared_keys(self):
        # The progress heading has its consumer site in ui/Panel.lua (the
        # progress call). The seed adds one plain literal of that key in an
        # unused do/local block after that call, on the same line, so Panel has
        # an excluded lead of the key next to a site of it. The grown fixture
        # keeps the seed and adds, after it on the same line, more distinct
        # plain non-key strings than there are declared keys and one more plain
        # literal of the same key (no localization call, no mutation), so
        # Panel's leads are then counted by looking each declared key up in
        # them. Its site must still be subtracted: compared with the seed, only
        # that key's excluded lead count for Panel may change, by exactly the
        # one added literal, and every other dated key's row stays the same. No
        # line or column of any earlier token moves.
        key = "panel.heading.progress"
        literal = b'"' + key.encode() + b'"'
        seed_block = b' do local specLeadSeed = ' + literal + b' end'
        noise = len(full_keys()) + 84
        table = b"".join(b'"spec lead noise %d", ' % number for number in range(noise))
        grown_block = b' do local specLeadNoise = {' + table + literal + b'} end'
        seeded = edit(self.files[PANEL], PROGRESS_CALL, PROGRESS_CALL + seed_block)
        grown = edit(self.files[PANEL], PROGRESS_CALL, PROGRESS_CALL + seed_block + grown_block)
        self.assertGreater(noise, len(full_keys()))
        # Branch guards from the tool's own parse and declarations, so the
        # comparison stays one of the two loops even if Panel or the catalog
        # changes size: the seed Panel has at most as many distinct lead
        # values as there are declared keys (the per-lead loop), the grown
        # Panel more (the per-declared-key loop).
        declared = len(self.catalog.parse_registry_declarations(self.files[INPUTS[4]]))
        self.assertLessEqual(len(self.catalog._parsed(seeded)[2]), declared)
        self.assertGreater(len(self.catalog._parsed(grown)[2]), declared)
        seed = self.receipt(with_file(self.files, PANEL, seeded))
        changed = self.receipt(with_file(self.files, PANEL, grown))
        self.assertEqual(changed["counts"], seed["counts"])
        # No excluded lead count of 0 is ever stored, in either loop.
        for receipt in (seed, changed):
            for row in receipt["keys"]:
                with self.subTest(key=row["key"]):
                    self.assertTrue(all(count > 0 for count
                                        in row["excludedLiteralLeads"]["byPath"].values()))
        before, after = self.binding(seed, key), self.binding(changed, key)
        self.assertTrue(any(site["path"] == PANEL
                            for site in before["sites"] + before["unprovenSites"]))
        before_leads = before["excludedLiteralLeads"]
        self.assertGreater(before_leads["byPath"].get(PANEL, 0), 0)
        expected = json.loads(json.dumps(before))
        expected["excludedLiteralLeads"]["count"] += 1
        expected["excludedLiteralLeads"]["byPath"][PANEL] += 1
        self.assertEqual(after, expected)
        self.assertEqual(list(after["excludedLiteralLeads"]["byPath"]),
                         list(before_leads["byPath"]))
        for other in CURRENT_KEYS:
            if other != key:
                with self.subTest(key=other):
                    self.assertEqual(self.binding(changed, other), self.binding(seed, other))

    def test_c4_mapped_chain_breaks_fail_the_gate(self):
        user = self.files[USER_TEXT]
        dispatch = b"if localizedReasons[s] then return LocalizedReason(localizedReasons[s],s) end"
        alias = b"local function LocalizedReason(key,code)\n    local localization=Nexus.Localization\n"
        variants = {
            "dispatch argument": (USER_TEXT, edit(user, dispatch, dispatch.replace(
                b"LocalizedReason(localizedReasons[s],s)", b"LocalizedReason(s,s)"))),
            "wrapper receiver": (USER_TEXT, edit(user, alias, alias.replace(
                b"=Nexus.Localization", b"=Nexus.Other"))),
            "wrong Text object": (USER_TEXT, edit(user, LOCALIZED_REASON_CALL,
                                                  LOCALIZED_REASON_CALL.replace(
                                                      b"localization.Text(key", b"T.Text(key", 1))),
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
                # The receipt is kept before the gate assertion, so a later
                # check of this variant never fails on a missing receipt.
                receipt = receipts[name] = self.receipt(with_file(self.files, path, data))
                with self.assertRaises(AssertionError):
                    assert_binding_receipt(self, receipt)
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
        self.assertEqual([(problem["code"], problem.get("key")) for problem in receipt["problems"]],
                         [("binding-orphan", "panel.never_declared")])
        mapped = edit(self.files[USER_TEXT], b'    ["STORE_PENDING"]="reason.saved_data_reading",\n',
                      b'    ["STORE_PENDING"]="reason.saved_data_reading",\n'
                      b'    ["NEVER"]="reason.never_declared",\n')
        receipt = self.gate_fails(with_file(self.files, USER_TEXT, mapped))
        self.assertEqual([(problem["code"], problem.get("key")) for problem in receipt["problems"]],
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
        blocked = provenance_blocked_calls()
        try:
            self.assertEqual(self.report(*args), expected)
        finally:
            blocked()
        # The cyclic collector's state is the caller's after every call,
        # also when a new parse pauses it (review fix 4).
        import gc
        fresh = with_file(self.files, "core/SessionPause.lua",
                          self.files["core/SessionPause.lua"] + b"\n-- gc state control\n")
        for enabled in (True, False):
            (gc.enable if enabled else gc.disable)()
            try:
                self.report(*binding_args(with_file(fresh, "core/SessionPause.lua",
                                                    fresh["core/SessionPause.lua"] + b"-- "
                                                    + str(enabled).encode() + b"\n")))
                self.assertIs(gc.isenabled(), enabled)
            finally:
                gc.enable()
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
                         ["declarationCount"], CURRENT_FULL_UI_KEYS)
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
        charge = b'kind = "format", slot = "count", resultLimit = 254'
        changed = with_file(self.files, core, edit(self.files[core], charge,
                                                   charge.replace(b"254", b"253")))
        with self.assertRaises(self.catalog.CatalogRegistryError) as raised:
            self.receipt(changed)
        self.assertEqual((raised.exception.code, raised.exception.key), ("registry-limit", CHARGE))

    def test_c15_a_localization_result_must_reach_an_output(self):
        # Review fix 1 (SPEC-147-S8-1): a call whose result is overwritten,
        # discarded or only reaches an unused helper never binds.
        user, key = self.files[USER_TEXT], "panel.heading.progress"
        call = LOCALIZED_REASON_CALL
        receipt = self.gate_fails(with_file(self.files, USER_TEXT, edit(
            user, call, call.replace(b"englishPack)\n", b"englishPack)\n        text=code\n", 1))))
        self.assertEqual([row["key"] for row in receipt["keys"] if row["binding"] == "UNBOUND"],
                         list(MAPPED_KEYS))
        self.assertEqual(map_chain(self, receipt, "LocalizedReason")["wrapperReturnsResult"],
                         False)
        # The other real chain has its own wrapper and is untouched.
        other = map_chain(self, receipt, "SeamReason")
        self.assertEqual((other["wrapperReturnsResult"], other["established"],
                          sorted(other["boundKeys"])), (True, True, sorted(REASON_KEYS)))
        self.assertEqual({site["reason"] for key in MAPPED_KEYS
                          for site in self.binding(receipt, key)["unprovenSites"]},
                         {"wrapper-result-not-returned"})
        discard = (b'local function SpecProgress(key) Nexus.Localization.Text(key); return '
                   b'"Progress" end; progressLabel:SetText(SpecProgress("panel.heading.progress"))')
        receipt = self.gate_fails(with_file(self.files, PANEL, edit(
            self.files[PANEL], PROGRESS_CALL, discard)))
        self.assertEqual([(problem["code"], problem.get("key")) for problem in receipt["problems"]],
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
        # Every real dispatcher caller disconnected (six since Source16-23:
        # WishlistEditor's notify now prints the controller's worded line):
        # the mapped keys go, and an unused helper that discards a Message
        # result does not restore them.
        callers = {"core/WishlistController.lua": (b"Nexus.UserText.Message(message)",),
                   READOUT: (b"Nexus.UserText.Message(model.text)",),
                   PANEL: (b"userText.Message(raw)", b"Nexus.UserText.Message(reason)"),
                   "ui/JournalTab.lua": (b"Nexus.UserText.Message(text)",),
                   "core/Main.lua": (b"Nexus.UserText.Message(msg)",)}
        for path in COHORT_SOURCES:
            self.assertEqual(self.files[path].count(b"UserText.Message(")
                             + self.files[path].count(b"userText.Message("),
                             len(callers.get(path, ())), path)
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
        for wrapper in ("LocalizedReason", "SeamReason"):
            chain = map_chain(self, receipt, wrapper)
            self.assertEqual((chain["established"], chain["boundKeys"], chain["outputs"]),
                             (False, [], []), wrapper)
        # One real caller restored with its chat output binds them again.
        restored = with_file(changed, "core/Main.lua", self.files["core/Main.lua"])
        receipt = assert_current_bindings(self, self.catalog, binding_args(restored))
        for wrapper in ("LocalizedReason", "SeamReason"):
            self.assertEqual(chain_outputs(map_chain(self, receipt, wrapper)),
                             {("core/Main.lua", "AddMessage")}, wrapper)

    def test_c16_a_module_alias_overwriting_the_dispatcher_is_unresolved(self):
        # Review fix 2 (SPEC-147-S8-2): a field written through a local alias
        # of the exported module is a definition of that module's field.
        user = self.files[USER_TEXT]
        overwrite = (b'\nlocal userTextAlias=T\nuserTextAlias.Message=function(value) return '
                     b'tostring(value or "") end\n')
        receipt = self.gate_fails(with_file(self.files, USER_TEXT, user + overwrite))
        # One row for each of T.Message's two real dispatches (the reasons
        # table's keys, then the mapped reasons), each at its own call.
        lf = user.replace(b"\r\n", b"\n")
        dispatches = [lf[:lf.index(call)].count(b"\n") + 1 for call in (
            b"SeamReason(reasonKeys[s],reasons[s])", b"LocalizedReason(localizedReasons[s],s)")]
        self.assertEqual(dispatches[1], dispatches[0] + 1)
        self.assertEqual([(problem["construct"], problem["detail"], problem["line"]) for problem
                          in self.problems(receipt, "binding-unresolved")],
                         [("dispatcher", "T.Message has 2 definitions, directly or through a "
                                         "local alias", line) for line in dispatches])
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
                self.assertEqual([(problem["detail"], problem["line"]) for problem
                                  in self.problems(receipt, "binding-unresolved")],
                                 [(detail, line) for line in dispatches])
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
        loaded = len(binding_args(self.files)[6])
        self.assertEqual((len(args[5]), len(args[6])), (1, loaded - 1))
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
        self.assertEqual(len(receipt["sources"]), loaded + 1)
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

    def test_c19_value_origin_and_output_receiver_are_proved(self):
        # Review fix 2 (SPEC-147-S8-RF1-1..3): a field value reaches only a
        # read of the same table, a parameter value returns only to the call
        # that passed it, and an output needs a client receiver.
        key, panel = "panel.heading.progress", self.files[PANEL]
        # The three review reproductions, each replacing the real progress call.
        cases = [
            ("unrelated table field", False, PANEL, (
                b'local specLeft={SpecUniqueField=Nexus.Localization.Text("panel.heading.progress")}; '
                b'local specRight={}; progressLabel:SetText(specRight.SpecUniqueField)')),
            ("distinct call result", False, PANEL, (
                b'local function SpecCarry(value) return value end; local specDiscard=SpecCarry('
                b'Nexus.Localization.Text("panel.heading.progress")); '
                b'progressLabel:SetText(SpecCarry("fixed"))')),
            ("fake local output", False, PANEL, (
                b'local specFake={SetText=function(self,value) return nil end}; '
                b'specFake:SetText(Nexus.Localization.Text("panel.heading.progress"))')),
        ]
        # Further identity and receiver controls in a small loaded file, with
        # the real progress call replaced by fixed text in Panel.
        host, bare = "core/SessionPause.lua", edit(panel, PROGRESS_CALL,
                                                  b'progressLabel:SetText("Progress")')
        label = b'\nlocal specLabel = UIParent:CreateFontString(nil, "OVERLAY")\n'
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        cases += [(name, binds, host, label + code) for name, binds, code in (
            ("same table field", True,
             b'local specLeft={Field=' + text + b'}; specLabel:SetText(specLeft.Field)\n'),
            ("same table through an alias", True,
             b'local specLeft={}; specLeft.Field=' + text + b'; local specAlias=specLeft; '
             b'specLabel:SetText(specAlias.Field)\n'),
            ("reassigned table", False,
             b'local specLeft={}; specLeft.Field=' + text + b'; specLeft={}; '
             b'specLabel:SetText(specLeft.Field)\n'),
            ("same call result", True,
             b'local function SpecCarry(value) return value end; '
             b'specLabel:SetText(SpecCarry(' + text + b'))\n'),
            ("nested calls keep their own return", False,
             b'local function SpecInner(value) return value end; local function SpecOuter(value) '
             b'local ignored=SpecInner(value); return SpecInner("fixed") end; '
             b'specLabel:SetText(SpecOuter(' + text + b'))\n'),
            ("fake field output", False,
             b'local specHolder={}; specHolder._specOut={SetText=function(self,value) end}; '
             b'specHolder._specOut:SetText(' + text + b')\n'),
            ("real widget field output", True,
             b'local specHolder={}; specHolder._specOut=UIParent:CreateFontString(); '
             b'specHolder._specOut:SetText(' + text + b')\n'))]
        for name, binds, path, code in cases:
            with self.subTest(case=name):
                if path == PANEL:
                    files = with_file(self.files, PANEL, edit(panel, PROGRESS_CALL, code))
                else:
                    files = with_file(with_file(self.files, PANEL, bare), host,
                                      self.files[host] + code)
                receipt = self.receipt(files)
                if binds:
                    assert_binding_receipt(self, receipt)
                    continue
                with self.assertRaises(AssertionError):
                    assert_binding_receipt(self, receipt)
                self.assertEqual([(problem["code"], problem.get("key"))
                                  for problem in receipt["problems"]], [("binding-unbound", key)])
                self.assertEqual([site["reason"] for site
                                  in self.binding(receipt, key)["unprovenSites"]],
                                 ["output-not-reached"])
        # A client global assigned by the loaded source is no receiver. Since
        # Source16-23 the mapped reasons' one proved output is Main's chat
        # frame (WishlistEditor's notify prints a line the controller already
        # worded, through a function value no static rule follows): replacing
        # DEFAULT_CHAT_FRAME unbinds them, replacing print alone does not. A
        # print consumer binds until print itself is replaced.
        main, editor = "core/Main.lua", "ui/WishlistEditor.lua"
        chat = self.files[main] + b"\nDEFAULT_CHAT_FRAME = {AddMessage = function() end}\n"
        printer = self.files[editor] + b"\nprint = function() end\n"
        for files, binds in ((with_file(self.files, main, chat), False),
                             (with_file(self.files, editor, printer), True),
                             (with_file(with_file(self.files, main, chat), editor, printer), False)):
            receipt = self.receipt(files)
            self.assertEqual({row["binding"] for row in receipt["keys"] if row["key"]
                              in MAPPED_KEYS}, {"MAPPED_TO_CONSUMER" if binds else "UNBOUND"})
        printed = with_file(with_file(self.files, PANEL, bare), host,
                            self.files[host] + b"\nprint(" + text + b")\n")
        assert_binding_receipt(self, self.receipt(printed))
        receipt = self.receipt(with_file(printed, editor, printer))
        self.assertEqual(self.binding(receipt, key)["binding"], "UNBOUND")
        # A CreateFontString redefined by the loaded source makes no widget.
        made = self.files[host] + b"\nlocal specMaker = {}\nfunction specMaker:CreateFontString() end\n"
        receipt = self.gate_fails(with_file(self.files, host, made))
        self.assertIn(key, [row["key"] for row in receipt["keys"] if row["binding"] == "UNBOUND"])


if __name__ == "__main__":
    unittest.main()
