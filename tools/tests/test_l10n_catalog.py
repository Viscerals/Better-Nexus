"""Metadata-contract tests for the declarative Nexus localization documents.

Refs #139, #147. Checks docs/localization/RELEASE_LANGUAGES.json,
docs/localization/KEY_CONTEXT.json and docs/localization/FULL_COVERAGE.md
against independent literal requirements and plain substrings of the current
source. Python 3.9+, standard library only. Files are read as strict UTF-8
bytes. No Lua is executed, imported or evaluated, and no live or private data
is read.

This is not the catalog validator. A read-only validator and CLI
(tools/l10n_catalog.py) with positive and malformed-input fixtures is a
separate later task that appends to this file and keeps these assertions.
This file is not yet registered in tools/run_prototype_tests.py.

Run directly:  python tools/tests/test_l10n_catalog.py -v
"""

import codecs
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = "5c77eec5b791f64468576e37a70b3855375b7fcb"
TREE = "692c6693ba50ba5ffc2bf8f3f724b0bceeeda65c"
INVENTORY_PIN = "18dc5b0313033dbc522bec1ab89c304078aa5645"

MAX_KEY_BYTES = 64
MAX_TEXT_BYTES = 256
CHARGE_RESULT_LIMIT = MAX_TEXT_BYTES - 2
KEY_RE = re.compile(r"^[a-z][a-z0-9_]*(?:[.][a-z][a-z0-9_]*)+$")
ASCII_WHITESPACE = {9, 10, 11, 12, 13, 32}

EXPECTED_PRODUCTS = [
    ("enUS", "english_baseline", "English", "English"),
    ("frFR", "optional_ui_pack", "French", "Fran\u00e7ais"),
    ("deDE", "optional_ui_pack", "German", "Deutsch"),
    ("esES", "optional_ui_pack", "Spanish", "Espa\u00f1ol"),
    ("plPL", "optional_ui_pack", "Polish", "Polski"),
    ("ptBR", "optional_ui_pack", "Brazilian Portuguese", "Portugu\u00eas (Brasil)"),
    ("ruRU", "optional_ui_pack", "Russian",
     "\u0420\u0443\u0441\u0441\u043a\u0438\u0439"),
]
PACK_IDS = [row[0] for row in EXPECTED_PRODUCTS[1:]]

STATIC_AT_BASE = ["reason.save_in_progress", "reason.list_preparing",
                  "reason.saved_data_reading"]
MISSING_AT_BASE = ["reason.wait_three_choices", "reason.wait_pending_pick_count",
                   "readout.charge_counts"]

# (key, kind, exact English, producer code mapped in core/UserText.lua)
EXPECTED_KEYS = [
    ("reason.save_in_progress", "text",
     "Saving is still in progress; wait for its final result", "ROOT_MUTATION_PENDING"),
    ("reason.list_preparing", "text",
     "This list is still being prepared", "CURSOR_REQUIRED"),
    ("reason.saved_data_reading", "text",
     "Reading your saved data", "STORE_PENDING"),
    ("reason.wait_three_choices", "text",
     "Waiting for the next three Echo choices", "waiting for three-card board"),
    ("reason.wait_pending_pick_count", "text",
     "waiting for pending-pick count", "waiting for pending-pick count"),
    ("readout.charge_counts", "format",
     "B:{banish} R:{reroll} F:{freeze}", None),
]
CHARGE_FIELDS = ["banish", "reroll", "freeze"]

# The Window families table of docs/localization/INVENTORY.md, with the
# proposed key families of KEYS_AND_GLOSSARY.md and the owning issue.
EXPECTED_FAMILIES = [
    ("Main panel (HUD)", "panel", 143,
     ["ui/Panel.lua", "ui/Readout.lua", "ui/LayoutMetrics.lua", "ui/Theme.lua",
      "ui/ServerStatus.lua"]),
    ("First-launch setup", "setup", 145, ["ui/QuickStart.lua"]),
    ("Help", "help", 145, ["ui/Help.lua"]),
    ("Auto overwrite consent", "consent", 145, ["ui/OverwriteWarning.lua"]),
    ("Orb window", "orb", 143, ["ui/OrbPanel.lua", "ui/OrbHistory.lua"]),
    ("Echo Journal tab", "journal", 143, ["ui/JournalTab.lua"]),
    ("Wishlist editor", "editor", 144, ["ui/WishlistEditor.lua", "ui/WishlistRenderer.lua"]),
    ("On-screen Wishlist", "overlay", 144, ["ui/WishlistOverlay.lua"]),
    ("Build Library", "library", 144, ["ui/CommunityBuilds.lua", "ui/CommunityRenderer.lua"]),
    ("Leaderboard", "leaderboard", 144, ["ui/Leaderboard.lua"]),
    ("Unit tooltip", "unit_tooltip", 144, ["ui/Nameplate.lua"]),
    ("Loading status", "loading", 145, ["ui/LoadingStatus.lua"]),
    ("Support report", "support", 145, ["ui/SupportReport.lua"]),
    ("Log viewer", "log", 145, ["ui/LogViewer.lua"]),
    ("Release note", "release_note", 145, ["ui/Changelog.lua"]),
]


def read_text(relative):
    data = (ROOT / relative).read_bytes()
    if data.startswith(codecs.BOM_UTF8):
        raise AssertionError(relative + " starts with a UTF-8 byte order mark")
    return data.decode("utf-8")


def _unique_object(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise AssertionError("duplicate JSON member: " + key)
        out[key] = value
    return out


def load_document(name):
    return json.loads(read_text("docs/localization/" + name),
                      object_pairs_hook=_unique_object)


def walk(value, path="$"):
    yield path, value
    if isinstance(value, dict):
        for key, item in value.items():
            yield from walk(item, path + "." + key)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from walk(item, "%s[%d]" % (path, index))


def assert_no_true(test, document):
    for path, value in walk(document):
        test.assertIsNot(value, True, path + " is true; no boolean may imply acceptance")


class ReleaseLanguagesContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = load_document("RELEASE_LANGUAGES.json")

    def test_header_and_scope(self):
        d = self.doc
        self.assertEqual(d["schema"], "nexus.l10n.release_languages")
        self.assertEqual(d["schemaVersion"], 1)
        self.assertEqual(d["sourcePin"], {"base": BASE, "tree": TREE})
        self.assertEqual(d["contractKind"], "declarative_metadata_only")
        self.assertEqual(d["validator"], {"path": "tools/l10n_catalog.py",
                                          "status": "NOT_IMPLEMENTED_SEPARATE_TASK"})
        self.assertEqual(d["requiredCiRegistration"], "NOT_REGISTERED_LATER_AUTHORIZED_APPEND")
        self.assertEqual(d["selectionDecision"]["issue"], 139)
        self.assertEqual(d["selectionDecision"]["status"], "resolved")

    def test_exact_seven_product_choices(self):
        rows = [(p["productId"], p["kind"], p["englishName"], p["autonym"])
                for p in self.doc["products"]]
        self.assertEqual(rows, EXPECTED_PRODUCTS)
        self.assertEqual(self.doc["fallbackProductId"], "enUS")

    def test_autonyms_are_stored_as_exact_utf8(self):
        raw = (ROOT / "docs/localization/RELEASE_LANGUAGES.json").read_bytes()
        for _, _, _, autonym in EXPECTED_PRODUCTS:
            self.assertIn(autonym.encode("utf-8"), raw, autonym)

    def test_product_ids_are_not_client_locales(self):
        for product in self.doc["products"]:
            self.assertEqual(product["clientLocaleCode"], "UNKNOWN")
            self.assertEqual(product["evidencedClientAliases"], [])
            self.assertIs(product["productIdIsClientLocale"], False)
        evidence = self.doc["clientEvidence"]
        self.assertEqual(evidence["evidencedClientAliases"], [])
        for field in ("clientManifest", "clientBuild", "clientHash", "runtimeLocale",
                      "fontFace", "glyphCoverage"):
            self.assertEqual(evidence[field], "UNKNOWN", field)
        self.assertEqual(evidence["nativeLayout"], "NOT_RUN")

    def test_installation_guide_is_historical_not_a_manifest(self):
        guide = self.doc["clientEvidence"]["officialInstallationGuideObservation"]
        self.assertEqual(guide, {
            "observedOn": "2026-10-23",
            "nature": "historical_observation",
            "describes": ["English gameplay", "existing English enUS 3.3.5a installation",
                          "launcher 1.0.6"],
            "isExactClientManifest": False,
        })

    def test_review_and_native_states_are_unassigned_and_pending(self):
        for product in self.doc["products"]:
            review = product["review"]
            self.assertEqual(review["technicalAuthorReview"], {"status": "pending", "records": []})
            self.assertEqual(review["fluentHumanAcceptance"],
                             {"responsibility": "UNASSIGNED", "status": "pending", "records": []})
            self.assertEqual(review["nativeAcceptance"], {"status": "NOT_RUN", "records": []})
            expected = ("existing_english_base_bytes" if product["productId"] == "enUS"
                        else "draft_unreviewed")
            self.assertEqual(product["wordingState"], expected)
        self.assertEqual(self.doc["evidenceRule"],
                         "A well-formed evidence record does not prove fluent or native truth.")
        assert_no_true(self, self.doc)

    def test_automatic_and_session_contract(self):
        auto = self.doc["automaticMode"]
        self.assertEqual(auto["chooserProductId"], "NONE_AT_BASE")
        self.assertEqual(auto["existingCodeDefault"], "enUS")
        self.assertEqual(auto["unknownOrUnsupportedResolvesTo"], "enUS")
        self.assertEqual(auto["evidencedMappings"], [])
        self.assertEqual(auto["followUp"],
                         {"issue": 141, "status": "OUTSTANDING", "codeChangeInThisTask": "none"})
        session = self.doc["sessionRefresh"]
        self.assertEqual(session["preference"], "saved for the next user-requested reload or login")
        self.assertEqual(session["activeLanguage"], "fixed for the Lua session")
        self.assertEqual(session["implicitReload"], "none")
        self.assertEqual(session["halfRefreshedWindows"], "none")

    def test_lineage_names_and_pseudo_data(self):
        lineage = self.doc["sourceLineage"]
        self.assertEqual(lineage["kind"], "independently_drafted_nexus_presentation_text")
        self.assertEqual(lineage["newHumanRightsAttestation"], "none")
        self.assertEqual(lineage["importedCorpus"], "none")
        self.assertEqual(self.doc["names"], {"englishGameNames": "retained",
                                             "userIdentities": "retained_exact",
                                             "transliteration": "none",
                                             "normalization": "none"})
        pseudo = self.doc["pseudoAndTestData"]
        self.assertEqual(pseudo["shippedProductIds"], [])
        self.assertIn("never shipped languages", pseudo["rule"])

    def test_products_match_current_source(self):
        profile = read_text("data/DefaultProfile.lua")
        self.assertIn('default = "enUS",', profile)
        self.assertIn('ids = { "enUS", "frFR", "deDE", "esES", "plPL", "ptBR", "ruRU" },', profile)
        localization = read_text("core/Localization.lua")
        self.assertIn('local DEFAULT_LANGUAGE = "enUS"', localization)
        self.assertIn('local ENGLISH_NAME = "English"', localization)
        packs = read_text("data/LocalizationPacks.lua")
        for pack_id, _, _, autonym in EXPECTED_PRODUCTS[1:]:
            self.assertIn(pack_id + " = {", packs)
            self.assertIn('name = "' + autonym + '",', packs)


class KeyContextContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = load_document("KEY_CONTEXT.json")
        cls.keys = {record["key"]: record for record in cls.doc["keys"]}

    def test_header(self):
        d = self.doc
        self.assertEqual(d["schema"], "nexus.l10n.key_context")
        self.assertEqual(d["schemaVersion"], 1)
        self.assertEqual(d["sourcePin"], {"base": BASE, "tree": TREE})
        self.assertEqual(d["contractKind"], "declarative_metadata_only")
        self.assertEqual(d["authority"], "core/Localization.lua")
        self.assertEqual(d["englishBase"], "data/LocalizationEnglish.lua")

    def test_bounds_and_text_contract(self):
        key_schema = self.doc["keySchema"]
        self.assertEqual((key_schema["minBytes"], key_schema["maxBytes"]), (3, MAX_KEY_BYTES))
        text = self.doc["textContract"]
        self.assertEqual((text["minBytes"], text["maxBytes"]), (1, MAX_TEXT_BYTES))
        self.assertEqual(text["asciiWhitespaceBytes"], sorted(ASCII_WHITESPACE))
        self.assertEqual(text["forbiddenBytes"], "ASCII control bytes 0-31, DEL 127 and | (124)")
        self.assertEqual(text["normalization"], "none")
        self.assertEqual(set(text["notNewlyExcluded"]),
                         {"language punctuation", "combining sequences", "C1 controls",
                          "zero-width scalars", "bidi scalars", "noncharacters"})
        self.assertEqual(self.doc["staticText"], "shown exactly as stored; never formatted")

    def test_template_and_count_grammar(self):
        grammar = self.doc["templateGrammar"]
        self.assertEqual(grammar["literalBraces"], {"{{": "{", "}}": "}"})
        self.assertEqual(grammar["percentSign"], "literal")
        self.assertEqual(set(grammar["invalid"]),
                         {"unknown placeholder name", "missing placeholder", "repeated placeholder",
                          "lone { or }", "positional placeholder such as {1}",
                          "typed format such as {name:d}", "printf-style format"})
        self.assertEqual(grammar["newGrammar"],
                         "none: no plural, date or other placeholder grammar is added")
        self.assertEqual(self.doc["countArgument"], {
            "known": "{known = true, value = N}: N a finite whole number >= 0, shown with tostring",
            "unknown": "{known = false}: shown as ?",
            "zero": "0 is a known count, not unknown",
        })

    def test_exactly_six_current_keys(self):
        rows = [(r["key"], r["kind"], r["english"], r.get("producerCode"))
                for r in self.doc["keys"]]
        self.assertEqual(rows, EXPECTED_KEYS)
        adoption = self.doc["currentAdoption"]
        self.assertEqual(adoption["keys"], [row[0] for row in EXPECTED_KEYS])
        self.assertEqual(adoption["allWindowSemanticCoverage"], "PENDING")

    def test_placeholders_are_typed_and_exact(self):
        for name, kind, english, _ in EXPECTED_KEYS:
            record = self.keys[name]
            if kind == "text":
                self.assertEqual(record["placeholders"], [], name)
                self.assertNotIn("resultLimitBytes", record, name)
                continue
            self.assertEqual(record["placeholders"],
                             [{"name": field, "type": "count"} for field in CHARGE_FIELDS])
            self.assertEqual(record["resultLimitBytes"], CHARGE_RESULT_LIMIT)
            for field in CHARGE_FIELDS:
                self.assertEqual(english.count("{" + field + "}"), 1, field)
            self.assertEqual(english.count("{"), len(CHARGE_FIELDS))
            self.assertEqual(english.count("}"), len(CHARGE_FIELDS))

    def test_keys_and_english_inside_current_bounds(self):
        for name, _, english, _ in EXPECTED_KEYS:
            self.assertTrue(3 <= len(name.encode("ascii")) <= MAX_KEY_BYTES, name)
            self.assertRegex(name, KEY_RE)
            data = english.encode("utf-8")
            self.assertTrue(1 <= len(data) <= MAX_TEXT_BYTES, name)
            self.assertFalse(any(b < 32 or b == 127 or b == 124 for b in data), name)
            self.assertTrue(any(b not in ASCII_WHITESPACE for b in data), name)

    def test_key_contract_matches_current_source(self):
        english = read_text("data/LocalizationEnglish.lua")
        for name, _, text, _ in EXPECTED_KEYS:
            self.assertIn('["%s"] = "%s",' % (name, text), english)
        user_text = read_text("core/UserText.lua")
        for name, _, _, code in EXPECTED_KEYS:
            if code is not None:
                self.assertIn('["%s"]="%s",' % (code, name), user_text)
        localization = read_text("core/Localization.lua")
        for fragment in ("local MAX_KEY_BYTES = 64", "local MAX_TEXT_BYTES = 256",
                         "local CHARGE_RESULT_LIMIT = MAX_TEXT_BYTES - 2",
                         '["readout.charge_counts"] = {fields = {"banish", "reroll", "freeze"},'):
            self.assertIn(fragment, localization)
        readout = read_text("ui/Readout.lua")
        self.assertIn('localization.Format("readout.charge_counts",', readout)

    def test_fifteen_window_families_pending(self):
        families = self.doc["windowFamilies"]
        rows = [(f["name"], f["proposedKeyFamily"], f["issue"], f["paths"]) for f in families]
        self.assertEqual(rows, EXPECTED_FAMILIES)
        toc = read_text("Nexus.toc")
        for family in families:
            self.assertEqual(family["semanticStatus"], "PENDING", family["name"])
            self.assertEqual(family["coverageStatus"], "PENDING", family["name"])
            for path in family["paths"]:
                self.assertTrue((ROOT / path).is_file(), path)
                self.assertIn(path.replace("/", chr(92)), toc)
        adopted = {key for family in families for key in family["adoptedKeys"]}
        self.assertLessEqual(adopted, set(self.keys))

    def test_other_copy_and_historical_leads_are_not_a_denominator(self):
        for item in self.doc["otherVisibleCopy"]:
            self.assertEqual(item["status"], "PENDING_CLASSIFICATION", item["source"])
        sources = {item["source"] for item in self.doc["otherVisibleCopy"]}
        for required in ("core/UserText.lua", "core/Main.lua", "core/SupportReport.lua"):
            self.assertIn(required, sources)
        self.assertEqual(self.doc["visibleTextDenominator"], "NOT_ESTABLISHED")
        leads = {lead["lead"]: lead for lead in self.doc["historicalLeads"]}
        lexical = leads["lexical string-literal inventory"]
        self.assertEqual((lexical["literalRecords"], lexical["files"], lexical["pin"]),
                         (25355, 87, INVENTORY_PIN))
        self.assertEqual(leads["#143 preparation"]["keys"], 21)
        for lead in leads.values():
            self.assertIs(lead["isCurrentSemanticInventory"], False)

    def test_pack_coverage_is_pinned_and_derived(self):
        coverage = self.doc["packCoverage"]
        self.assertIn("derived", coverage["countRule"])
        baseline = coverage["baselineObservation"]
        self.assertEqual(baseline["pin"], BASE)
        self.assertEqual(baseline["appliesTo"], PACK_IDS)
        self.assertEqual(baseline["inheritedStaticDraftKeys"], STATIC_AT_BASE)
        self.assertEqual(baseline["missingKeys"], MISSING_AT_BASE)
        self.assertEqual(sorted(STATIC_AT_BASE + MISSING_AT_BASE), sorted(self.keys))
        self.assertEqual(baseline["reviewState"], "draft_unreviewed")
        addition = coverage["separatePendingAddition"]
        self.assertEqual(addition["draftEntries"], len(PACK_IDS) * len(MISSING_AT_BASE))
        self.assertEqual(addition["newEnglishKeys"], 0)
        self.assertEqual(addition["reviewState"], "draft_unreviewed; per-language human review pending")
        self.assertEqual(coverage["fallbackCountsAsTranslation"], "never")
        allowed = {"$.separatePendingAddition.draftEntries",
                   "$.separatePendingAddition.newEnglishKeys"}
        for path, value in walk(coverage):
            if isinstance(value, int) and not isinstance(value, bool):
                self.assertIn(path, allowed, "hardcoded coverage count at " + path)
        assert_no_true(self, self.doc)


class FullCoveragePlan(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = read_text("docs/localization/FULL_COVERAGE.md")

    def test_states_pins_gates_and_limits(self):
        for required in (BASE, TREE, "#139", "#141", "#143", "#144", "#145", "#146",
                         "#147", "#148", "#149", "OUTSTANDING", "UNASSIGNED", "NOT_RUN",
                         "at most 60 newly adopted keys", "are not complete",
                         "Fallback English is not translation", "tools/l10n_catalog.py",
                         "final M7 composition"):
            self.assertIn(required, self.text)

    def test_lists_every_window_family(self):
        for name, _, issue, _ in EXPECTED_FAMILIES:
            self.assertIn("| " + name + " | #" + str(issue) + " |", self.text)


if __name__ == "__main__":
    unittest.main()
