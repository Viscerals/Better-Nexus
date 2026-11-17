"""Registry-bound localization catalog, S7: the per-pack provenance records of
RELEASE_LANGUAGES.json through pack_provenance_diagnostics and --provenance (Refs #147).

Split from the single registry test file (SPLIT-PLAN.md): its classes are copied
verbatim; shared names come from tools/tests/l10n_registry_support.py. Synthetic offline
evidence only: no Lua runs, and this is not fluent, human or native evidence. Python 3.9+,
standard library only. Registered in PYTHON_TESTS of tools/run_prototype_tests.py.

Run directly:  python tools/tests/test_l10n_registry_provenance.py -v
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


class ProvenanceTests(unittest.TestCase):
    """S7: per-pack provenance records and the opt-in provenance receipt
    beside the unchanged strict, report and diagnostic seams."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = s8_catalog()
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
        # Entry and review facts are unchanged: every current English key
        # (the full visible-UI catalog, 4116), six packs of 4078 draft
        # entries each (24468 in all; each pack still lacks 38 of the 4116
        # keys), no translated entry reviewed and no gate upgrade. The
        # current metadata holds 539 structural entry declarations, every one
        # "legitimately_identical" with status "declared": frFR 110, deDE
        # 108, esES 90, plPL 89, ptBR 92, ruRU 50. They are source facts of
        # RELEASE_LANGUAGES, counted here so that they cannot drift unseen;
        # a declaration is not fluent, rights or native evidence, and the
        # acceptance facts below stay as they were.
        report = self.catalog.registry_catalog_report(*self.inputs)
        self.assertEqual(report["denominator"]["englishKeys"], CURRENT_FULL_UI_KEYS)
        self.assertEqual([row["entriesPresent"] for row in report["products"]], [4078] * 6)
        self.assertEqual(sum(row["entriesPresent"] for row in report["products"]), 24468)
        declared = {"frFR": 110, "deDE": 108, "esES": 90, "plPL": 89, "ptBR": 92, "ruRU": 50}
        self.assertEqual(sorted(row["productId"] for row in report["products"]), sorted(declared))
        for row in report["products"]:
            self.assertEqual((row["counts"]["translated_and_reviewed"],
                              row["counts"]["reviewed_legitimately_identical"]),
                             (0, declared[row["productId"]]), row["productId"])
        declarations = self.release["entryReview"]["declarations"]
        self.assertEqual(len(declarations), 539)
        for declaration in declarations:
            self.assertEqual(sorted(declaration),
                             ["decision", "evidenceReference", "key", "productId", "reviewer",
                              "status", "translatedTextSha256"])
            self.assertEqual({type(value) for value in declaration.values()}, {str})
            self.assertEqual((declaration["decision"], declaration["status"]),
                             ("legitimately_identical", "declared"))
        self.assertEqual({product: sum(1 for declaration in declarations
                                       if declaration["productId"] == product)
                          for product in OPTIONAL_IDS}, declared)
        self.assertEqual(len({(declaration["productId"], declaration["key"])
                              for declaration in declarations}), 539)
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

    # Moved verbatim to l10n_registry_support.provenance_blocked_calls (C12 also calls it).
    blocked_calls = staticmethod(provenance_blocked_calls)

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
        return cli_in_process(*args)

    def test_repository_root(self):
        run = self.run_cli("--provenance")
        process = cli_process("--provenance")
        self.assertEqual((process.returncode, process.stdout, process.stderr),
                         (run.returncode, run.stdout, run.stderr))
        self.assertEqual((run.returncode, run.stderr), (0, b""))
        record = json.loads(run.stdout)
        self.assertEqual((record["record"], record["exitCode"]), ("provenance", 0))
        expected = s8_catalog().pack_provenance_diagnostics(*current_inputs())
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


if __name__ == "__main__":
    unittest.main()
