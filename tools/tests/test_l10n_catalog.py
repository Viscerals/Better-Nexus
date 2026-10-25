"""Metadata-contract tests for the declarative Nexus localization documents.

Refs #139, #147. Checks docs/localization/RELEASE_LANGUAGES.json,
docs/localization/KEY_CONTEXT.json and docs/localization/FULL_COVERAGE.md
against independent literal requirements and plain substrings of the current
source. Python 3.9+, standard library only. Files are read as strict UTF-8
bytes. No Lua is executed, imported or evaluated, and no live or private data
is read.

Later sections append public tests of tools/l10n_catalog.py on exact
in-memory bytes: the parser, the pure schema API validate_catalog_data and
the pure coverage report API catalog_report. That tool is not yet a full
validator. Several parts are still pending: its read-only filesystem --root
report command line (a separate later task that appends to this file and
keeps these assertions), required-CI registration, independent review, and
the human, native and UI gates. This file is not yet registered in
tools/run_prototype_tests.py.

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
                                          "status": "COVERAGE_API_ONLY_REPORT_CLI_PENDING"})
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


# B1 parser foundation (Refs #147): public grammar tests for the parser-only
# tools/l10n_catalog.py. The tests use only parse_english, parse_packs and
# CatalogSyntaxError, on exact bytes, against independent literal tables and
# error codes. No Lua is executed, imported or evaluated. Metadata, review,
# coverage, path and full command-line fixtures belong to later tasks.

import importlib.util
import os
import subprocess
import sys
import tempfile

CATALOG_TOOL = ROOT / "tools" / "l10n_catalog.py"
CATALOG_PYCACHE = ROOT / "tools" / "__pycache__"
CATALOG_BOOTSTRAP = b"Nexus = Nexus or {}\n"
CATALOG_HEADS = {
    "english": CATALOG_BOOTSTRAP + b"Nexus.LocalizationEnglish = ",
    "packs": CATALOG_BOOTSTRAP + b"Nexus.LocalizationPacks = ",
}
CATALOG_NOTICE = {
    "record": "notice",
    "tool": "tools/l10n_catalog.py",
    "status": "COVERAGE_API_ONLY_REPORT_CLI_PENDING",
    "fullValidation": "NOT_IMPLEMENTED",
    "message": "coverage report API only; filesystem and report CLI are pending",
}

CATALOG_CURRENT_ENGLISH = {
    "reason.save_in_progress": "Saving is still in progress; wait for its final result",
    "reason.list_preparing": "This list is still being prepared",
    "reason.saved_data_reading": "Reading your saved data",
    "reason.wait_three_choices": "Waiting for the next three Echo choices",
    "reason.wait_pending_pick_count": "waiting for pending-pick count",
    "readout.charge_counts": "B:{banish} R:{reroll} F:{freeze}",
}
CATALOG_CURRENT_PACKS = {
    "frFR": {"name": "Français", "entries": {
        "reason.save_in_progress":
            "L'enregistrement est toujours en cours ; attendez son résultat final",
        "reason.list_preparing": "Cette liste est encore en cours de préparation",
        "reason.saved_data_reading": "Lecture de vos données enregistrées",
    }},
    "deDE": {"name": "Deutsch", "entries": {
        "reason.save_in_progress":
            "Speichern läuft noch; bitte auf das endgültige Ergebnis warten",
        "reason.list_preparing": "Diese Liste wird noch vorbereitet",
        "reason.saved_data_reading": "Gespeicherte Daten werden gelesen",
    }},
    "esES": {"name": "Español", "entries": {
        "reason.save_in_progress": "El guardado sigue en curso; espera a su resultado final",
        "reason.list_preparing": "Esta lista aún se está preparando",
        "reason.saved_data_reading": "Leyendo tus datos guardados",
    }},
    "plPL": {"name": "Polski", "entries": {
        "reason.save_in_progress": "Zapisywanie nadal trwa; poczekaj na ostateczny wynik",
        "reason.list_preparing": "Ta lista jest jeszcze przygotowywana",
        "reason.saved_data_reading": "Odczytywanie zapisanych danych",
    }},
    "ptBR": {"name": "Português (Brasil)", "entries": {
        "reason.save_in_progress":
            "O salvamento ainda está em andamento; aguarde o resultado final",
        "reason.list_preparing": "Esta lista ainda está sendo preparada",
        "reason.saved_data_reading": "Lendo seus dados salvos",
    }},
    "ruRU": {"name": "Русский", "entries": {
        "reason.save_in_progress":
            "Сохранение ещё выполняется; дождитесь окончательного результата",
        "reason.list_preparing": "Этот список ещё подготавливается",
        "reason.saved_data_reading": "Чтение сохранённых данных",
    }},
}

# CRLF lines covering: a long comment before the bootstrap; short and long
# comments between tokens; decimal escapes (at most three digits), named
# escapes and unknown escapes; an escaped line break; long-bracket keys and
# values (the line break right after the opening bracket is dropped); and [[
# inside a level-1 long string.
CATALOG_LEXICAL_LINES = (
    rb"--[==[ leading long comment: Nexus = nil ]] still a comment ]==]",
    rb'Nexus = Nexus or {} -- short comment with { and "quote',
    rb'Nexus.LocalizationEnglish = { --[[ ["x.hidden"] = "hidden" ]]',
    rb'    ["e.decimal"] = "\65\066\0671",',
    rb'    ["e.named"] = "tab\tq\"\\\q",',
    b'    ["e.wrap"] = "a\\',
    rb'b",',
    rb"    [ [[e.long]] ] = [[",
    rb"first",
    rb"second]],",
    rb"    ['e.dash'] = '\226\128\148',",
    rb'    ["e.level"] = [=[ has [[ and ]] inside ]=], -- ]]',
    rb"} -- trailing comment",
)
CATALOG_LEXICAL_TABLE = {
    "e.decimal": "ABC1",
    "e.named": "tab\tq\"\\q",
    "e.wrap": "a\nb",
    "e.long": "first\nsecond",
    "e.dash": "\u2014",
    "e.level": " has [[ and ]] inside ",
}

CATALOG_INERT_SOURCE = CATALOG_HEADS["english"] + (
    b"{\n"
    b'    ["t.percent"] = "100% %s %d %% %1$s",\n'
    b'    ["t.braces"] = "{banish} }}{{ {1} {name:d} {",\n'
    b"    [\"t.code\"] = 'os.execute(\"rm -rf /\") -- not a comment',\n"
    b'    ["t.long"] = [==[function() return Nexus end; ]] setmetatable({}, {})]==],\n'
    b'    ["t.markup"] = "|cffff0000red|r \\124",\n'
    b"}\n"
)
CATALOG_INERT_TABLE = {
    "t.percent": "100% %s %d %% %1$s",
    "t.braces": "{banish} }}{{ {1} {name:d} {",
    "t.code": 'os.execute("rm -rf /") -- not a comment',
    "t.long": "function() return Nexus end; ]] setmetatable({}, {})",
    "t.markup": "|cffff0000red|r |",
}

# (case, parser, table after the assignment, expected result)
CATALOG_SHAPES = (
    ("empty English table", "english", b"{}", {}),
    ("empty packs table", "packs", b"{ }", {}),
    ("empty English value, trailing comma", "english", b'{ ["k.a"] = "", }', {"k.a": ""}),
    ("bare, bracketed and escaped pack IDs, either field order", "packs",
     b"{ -- packs\n"
     b"    xxAA = { name = [[Pack A]], entries = { [ [==[k.a]==] ] = 'A %s {x}' } },\n"
     b'    ["x\\121BB"] = { entries = {}, name = "", },\n'
     b'    _z9 = { name = "Z", entries = { ["k.a"] = "1", ["k.b"] = "2", }, }\n'
     b"}",
     {"xxAA": {"name": "Pack A", "entries": {"k.a": "A %s {x}"}},
      "xyBB": {"name": "", "entries": {}},
      "_z9": {"name": "Z", "entries": {"k.a": "1", "k.b": "2"}}}),
)

# (case, parser, whole source, error code)
CATALOG_HEADER_CASES = (
    ("empty source", "english", b"", "bad-bootstrap"),
    ("comment only", "english", b"-- Nexus = Nexus or {}\n", "bad-bootstrap"),
    ("plain table bootstrap", "english",
     b"Nexus = {}\nNexus.LocalizationEnglish = {}\n", "bad-bootstrap"),
    ("local bootstrap", "english",
     b"local Nexus = Nexus or {}\nNexus.LocalizationEnglish = {}\n", "bad-bootstrap"),
    ("and instead of or", "packs",
     b"Nexus = Nexus and {}\nNexus.LocalizationPacks = {}\n", "bad-bootstrap"),
    ("filled bootstrap table", "packs",
     b"Nexus = Nexus or { x = 1 }\nNexus.LocalizationPacks = {}\n", "bad-bootstrap"),
    ("global table bootstrap", "english",
     b"_G.Nexus = Nexus or {}\nNexus.LocalizationEnglish = {}\n", "bad-bootstrap"),
    ("byte order mark", "english", b"\xef\xbb\xbf" + CATALOG_HEADS["english"] + b"{}\n",
     "bad-bootstrap"),
    ("bootstrap only", "english", CATALOG_BOOTSTRAP, "bad-assignment"),
    ("packs assignment parsed as English", "english", CATALOG_HEADS["packs"] + b"{}\n",
     "bad-assignment"),
    ("English assignment parsed as packs", "packs", CATALOG_HEADS["english"] + b"{}\n",
     "bad-assignment"),
    ("indexed assignment", "english",
     CATALOG_BOOTSTRAP + b'Nexus["LocalizationEnglish"] = {}\n', "bad-assignment"),
    ("local assignment", "english",
     CATALOG_BOOTSTRAP + b"local LocalizationEnglish = {}\n", "bad-assignment"),
    ("fallback expression", "english",
     CATALOG_HEADS["english"] + b"Nexus.LocalizationEnglish or {}\n", "bad-assignment"),
    ("metatable wrapper", "english",
     CATALOG_HEADS["english"] + b"setmetatable({}, { __index = function() end })\n",
     "bad-assignment"),
    ("immediately called function", "packs",
     CATALOG_HEADS["packs"] + b"(function() return {} end)()\n", "bad-assignment"),
    ("missing table", "packs", CATALOG_HEADS["packs"], "bad-assignment"),
)

# (case, parser, table after the assignment, error code, (line, column) or None)
CATALOG_DUPLICATE_CASES = (
    ("repeated English key", "english", b'{ ["k.a"] = "1", ["k.a"] = "2" }',
     "duplicate-key", None),
    ("escaped-equal English key", "english", b'{["k.a"] = "1", ["k\\46a"] = "2"}',
     "duplicate-key", (2, 45)),
    ("long-bracket English key", "english", b'{ ["k.a"] = "1", [ [==[k.a]==] ] = "2" }',
     "duplicate-key", None),
    ("single-quoted English key", "english", b"{ [\"k.a\"] = '1', ['k.a'] = '2' }",
     "duplicate-key", None),
    ("repeated pack ID", "packs",
     b'{ frFR = { name = "F", entries = {} }, frFR = { name = "G", entries = {} } }',
     "duplicate-pack", None),
    ("bare and escaped bracketed pack ID", "packs",
     b'{ frFR = { name = "F", entries = {} }, ["fr\\70R"] = { name = "G", entries = {} } }',
     "duplicate-pack", None),
    ("repeated name field", "packs", b'{ frFR = { name = "F", name = "G", entries = {} } }',
     "duplicate-field", None),
    ("repeated entries field", "packs",
     b'{ frFR = { entries = {}, name = "F", entries = {} } }', "duplicate-field", None),
    ("escaped-equal entry key", "packs",
     b'{ frFR = { name = "F", entries = { ["r.x"] = "1", ["r.\\120"] = "2" } } }',
     "duplicate-key", None),
)

# (case, parser, table after the assignment, error code)
CATALOG_MALFORMED_CASES = (
    ("nested table value", "english", b'{ ["k.a"] = { "x" } }', "unexpected-token"),
    ("number value", "english", b'{ ["k.a"] = 1 }', "unexpected-token"),
    ("boolean value", "english", b'{ ["k.a"] = true }', "unexpected-token"),
    ("nil value", "english", b'{ ["k.a"] = nil }', "unexpected-token"),
    ("concatenation", "english", b'{ ["k.a"] = "a" .. "b" }', "unexpected-token"),
    ("parenthesized value", "english", b'{ ["k.a"] = ("a") }', "unexpected-token"),
    ("call value", "english", b'{ ["k.a"] = tostring("a") }', "unexpected-token"),
    ("string call value", "english", b'{ ["k.a"] = f"a" }', "unexpected-token"),
    ("function value", "english", b'{ ["k.a"] = function() return "a" end }',
     "unexpected-token"),
    ("numeric computed key", "english", b'{ [1] = "a" }', "unexpected-token"),
    ("variable computed key", "english", b'{ [k] = "a" }', "unexpected-token"),
    ("concatenated computed key", "english", b'{ ["k" .. ".a"] = "a" }', "unexpected-token"),
    ("bare English key", "english", b'{ k = "a" }', "unexpected-token"),
    ("positional value", "english", b'{ "a" }', "unexpected-token"),
    ("missing separator", "english", b'{ ["k.a"] = "a" ["k.b"] = "b" }', "unexpected-token"),
    ("leading comma", "english", b"{ , }", "unexpected-token"),
    ("double comma", "english", b'{ ["k.a"] = "a",, }', "unexpected-token"),
    ("semicolon separator", "english", b'{ ["k.a"] = "a"; }', "unexpected-token"),
    ("comparison", "english", b'{ ["k.a"] == "a" }', "unexpected-token"),
    ("non-ASCII outside a string", "english", '{ ["k.a"] = "a", \u00e9 }'.encode("utf-8"),
     "unexpected-token"),
    ("unclosed table", "english", b'{ ["k.a"] = "a",', "unexpected-end"),
    ("missing value", "english", b'{ ["k.a"] =', "unexpected-end"),
    ("missing name", "packs", b"{ frFR = { entries = {} } }", "missing-field"),
    ("missing entries", "packs", b'{ frFR = { name = "F" } }', "missing-field"),
    ("empty pack", "packs", b"{ frFR = {} }", "missing-field"),
    ("unknown field", "packs", b'{ frFR = { name = "F", entries = {}, rights = "x" } }',
     "unknown-field"),
    ("reserved word field", "packs",
     b'{ frFR = { name = "F", entries = {}, function = "x" } }', "unexpected-token"),
    ("bracketed field key", "packs", b'{ frFR = { ["name"] = "F", entries = {} } }',
     "unexpected-token"),
    ("name not a string", "packs", b"{ frFR = { name = 1, entries = {} } }", "unexpected-token"),
    ("name expression", "packs", b'{ frFR = { name = "F" .. "x", entries = {} } }',
     "unexpected-token"),
    ("entries not a table", "packs", b'{ frFR = { name = "F", entries = "x" } }',
     "unexpected-token"),
    ("bare entry key", "packs", b'{ frFR = { name = "F", entries = { k = "x" } } }',
     "unexpected-token"),
    ("nested entry value", "packs",
     b'{ frFR = { name = "F", entries = { ["k.a"] = { "x" } } } }', "unexpected-token"),
    ("pack not a table", "packs", b'{ frFR = "F" }', "unexpected-token"),
    ("positional pack", "packs", b'{ { name = "F", entries = {} } }', "unexpected-token"),
    ("reserved word pack ID", "packs", b'{ nil = { name = "F", entries = {} } }',
     "unexpected-token"),
    ("numeric pack ID", "packs", b'{ [1] = { name = "F", entries = {} } }', "unexpected-token"),
    ("metatable pack", "packs",
     b'{ frFR = setmetatable({ name = "F", entries = {} }, {}) }', "unexpected-token"),
    ("function pack", "packs", b"{ frFR = function() end }", "unexpected-token"),
    ("unclosed pack", "packs", b'{ frFR = { name = "F", entries = {}', "unexpected-end"),
)

# (case, parser, whole source, error code, (line, column) or None)
CATALOG_LEXICAL_ERROR_CASES = (
    ("source not UTF-8", "english",
     CATALOG_HEADS["english"] + b'{ ["k.a"] = "caf\xe9" }', "not-utf8", None),
    ("overlong UTF-8 in source", "english",
     CATALOG_HEADS["english"] + b'{ ["k.a"] = "\xc0\xaf" }', "not-utf8", None),
    ("encoded surrogate in source", "english",
     CATALOG_HEADS["english"] + b'{ ["k.a"] = "\xed\xa0\x80" }', "not-utf8", None),
    ("value escape not UTF-8", "english",
     CATALOG_HEADS["english"] + b'{["k.a"] = "\\200"}', "value-not-utf8", (2, 40)),
    ("value escapes encode a surrogate", "english",
     CATALOG_HEADS["english"] + b'{["k.a"] = "\\237\\160\\128"}', "value-not-utf8", (2, 40)),
    ("key escape not UTF-8", "english",
     CATALOG_HEADS["english"] + b'{["\\255"] = "a"}', "value-not-utf8", (2, 31)),
    ("pack ID escape not UTF-8", "packs",
     CATALOG_HEADS["packs"] + b'{["\\192"] = { name = "F", entries = {} }}',
     "value-not-utf8", (2, 29)),
    ("unfinished string", "english",
     CATALOG_HEADS["english"] + b'{["k.a"] = "open\n}', "unfinished-string", (2, 40)),
    ("unfinished long string", "english",
     CATALOG_HEADS["english"] + b'{["k.a"] = [==[ open ]] }', "unfinished-string", (2, 40)),
    ("unfinished long comment", "english",
     CATALOG_HEADS["english"] + b"{ --[[ open\n}", "unfinished-comment", (2, 31)),
    ("decimal escape above 255", "english",
     CATALOG_HEADS["english"] + b'{["k.a"] = "\\256"}', "invalid-escape", (2, 40)),
    ("[[ inside a level-0 long string", "english",
     CATALOG_HEADS["english"] + b'{["k.a"] = [[a [[ b]]}', "nested-long-bracket", (2, 40)),
    ("[[ inside a level-0 long comment", "english",
     b"--[[ a [[ b ]]\n" + CATALOG_HEADS["english"] + b"{}", "nested-long-bracket", (1, 1)),
)


def load_catalog_parser():
    """Load tools/l10n_catalog.py from its trusted file path. Bytecode caching
    is off while it loads, so no tools/__pycache__ entry is written."""
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location("l10n_catalog_under_test", CATALOG_TOOL)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def catalog_pycache_names():
    """Return the entries of tools/__pycache__, sorted; empty when it is absent."""
    if not CATALOG_PYCACHE.is_dir():
        return []
    return sorted(entry.name for entry in CATALOG_PYCACHE.iterdir())


class CatalogParserGrammar(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog_parser()

    def parser(self, which):
        return getattr(self.catalog, "parse_" + which)

    def assert_rejected(self, parse, source, code, where=None):
        with self.assertRaises(self.catalog.CatalogSyntaxError) as caught:
            parse(source)
        error = caught.exception
        self.assertEqual(error.code, code, source[:300])
        self.assertIn(error.code, self.catalog.CODES)
        if where is not None:
            self.assertEqual((error.line, error.column), where, source[:300])

    def test_current_english_file_parses_to_its_literal_table(self):
        table = self.catalog.parse_english((ROOT / "data/LocalizationEnglish.lua").read_bytes())
        self.assertIs(type(table), dict)
        self.assertEqual(table, CATALOG_CURRENT_ENGLISH)
        self.assertEqual(list(table), list(CATALOG_CURRENT_ENGLISH))

    def test_current_packs_file_parses_to_its_literal_tables(self):
        packs = self.catalog.parse_packs((ROOT / "data/LocalizationPacks.lua").read_bytes())
        self.assertIs(type(packs), dict)
        self.assertEqual(packs, CATALOG_CURRENT_PACKS)
        self.assertEqual(list(packs), ["frFR", "deDE", "esES", "plPL", "ptBR", "ruRU"])

    def test_percent_braces_markup_and_code_in_strings_stay_inert_text(self):
        self.assertEqual(self.catalog.parse_english(CATALOG_INERT_SOURCE), CATALOG_INERT_TABLE)

    def test_comments_long_strings_and_lua_5_1_escapes_decode_exactly(self):
        source = b"\r\n".join(CATALOG_LEXICAL_LINES) + b"\r\n"
        self.assertEqual(self.catalog.parse_english(source), CATALOG_LEXICAL_TABLE)

    def test_pack_ids_fields_commas_and_empty_tables_are_syntax_only(self):
        for label, which, body, expected in CATALOG_SHAPES:
            with self.subTest(label):
                self.assertEqual(self.parser(which)(CATALOG_HEADS[which] + body), expected)

    def test_wrong_bootstrap_or_assignment_is_rejected(self):
        for label, which, source, code in CATALOG_HEADER_CASES:
            with self.subTest(label):
                self.assert_rejected(self.parser(which), source, code)

    def test_duplicates_are_found_after_decoding_before_storing(self):
        for label, which, body, code, where in CATALOG_DUPLICATE_CASES:
            with self.subTest(label):
                self.assert_rejected(self.parser(which), CATALOG_HEADS[which] + body, code, where)

    def test_malformed_nested_expression_function_and_computed_input_is_rejected(self):
        for label, which, body, code in CATALOG_MALFORMED_CASES:
            with self.subTest(label):
                self.assert_rejected(self.parser(which), CATALOG_HEADS[which] + body, code)

    def test_utf8_and_lexical_errors_have_stable_codes(self):
        for label, which, source, code, where in CATALOG_LEXICAL_ERROR_CASES:
            with self.subTest(label):
                self.assert_rejected(self.parser(which), source, code, where)

    def test_executable_prefix_suffix_and_code_are_rejected_and_never_run(self):
        english, packs = self.catalog.parse_english, self.catalog.parse_packs
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "executed.marker"
            touch = ('io.open("%s", "w"):close()' % marker.as_posix()).encode("utf-8")
            valid = CATALOG_HEADS["english"] + b'{ ["k.a"] = "a" }\n'
            valid_packs = CATALOG_HEADS["packs"] + b'{ frFR = { name = "F", entries = {} } }\n'
            cases = (
                ("code before the bootstrap", english, touch + b"\n" + valid, "bad-bootstrap"),
                ("code after the table", english, valid + touch + b"\n", "trailing-content"),
                ("os.execute after the table", english, valid + b'os.execute("x")\n',
                 "trailing-content"),
                ("return after the table", english, valid + b"return Nexus\n", "trailing-content"),
                ("lone terminal semicolon", english, valid.rstrip(b"\n") + b";\n",
                 "trailing-content"),
                ("semicolon then code", english, valid.rstrip(b"\n") + b"; " + touch,
                 "trailing-content"),
                ("second assignment", english, valid + b"Nexus.LocalizationEnglish = {}\n",
                 "trailing-content"),
                ("metatable after packs", packs,
                 valid_packs + b"setmetatable(Nexus.LocalizationPacks, {})\n", "trailing-content"),
                ("code before packs", packs, touch + b"\n" + valid_packs, "bad-bootstrap"),
                ("code as a value", english,
                 CATALOG_HEADS["english"] + b'{ ["k.a"] = ' + touch + b" }\n", "unexpected-token"),
                ("function value with code", english,
                 CATALOG_HEADS["english"] + b'{ ["k.a"] = (function() ' + touch
                 + b' return "a" end)() }\n', "unexpected-token"),
                ("code as an entry key", packs,
                 CATALOG_HEADS["packs"] + b'{ frFR = { name = "F", entries = { [' + touch
                 + b'] = "a" } } }\n', "unexpected-token"),
            )
            for label, parse, source, code in cases:
                with self.subTest(label):
                    self.assert_rejected(parse, source, code)
            inert = CATALOG_HEADS["english"] + b'{ ["k.a"] = [==[' + touch + b"]==] }\n"
            self.assertEqual(english(inert), {"k.a": touch.decode("utf-8")})
            self.assertFalse(marker.exists())

    def test_public_functions_take_bytes_not_paths_or_text(self):
        path = ROOT / "data/LocalizationEnglish.lua"
        text = CATALOG_HEADS["english"].decode("ascii") + "{}"
        for parse in (self.catalog.parse_english, self.catalog.parse_packs):
            for value in (str(path), path, text, None):
                with self.subTest(parse=parse.__name__, value=type(value).__name__):
                    with self.assertRaises(TypeError):
                        parse(value)
        self.assertEqual(self.catalog.parse_english(bytearray(CATALOG_HEADS["english"] + b"{}")), {})

    def test_direct_invocation_is_a_pending_notice_and_exits_nonzero(self):
        env = dict(os.environ)
        env.pop("PYTHONDONTWRITEBYTECODE", None)
        before = catalog_pycache_names()
        load_catalog_parser()
        runs = [subprocess.run([sys.executable, str(CATALOG_TOOL), *args], capture_output=True,
                               cwd=str(ROOT), env=env)
                for args in ((), ("--root", str(ROOT)))]
        self.assertEqual(catalog_pycache_names(), before)
        for run in runs:
            self.assertEqual(run.returncode, 2, run.stderr)
            self.assertEqual(run.stdout, b"")
            self.assertTrue(run.stderr.isascii(), run.stderr)
            lines = run.stderr.decode("ascii").splitlines()
            self.assertEqual(len(lines), 1, run.stderr)
            self.assertEqual(json.loads(lines[0]), CATALOG_NOTICE)
        self.assertEqual(runs[0].stderr, runs[1].stderr)


# B2 schema API (Refs #147): public tests of validate_catalog_data and
# CatalogValidationError. The baseline is the exact current six-key source and
# metadata; each case changes one thing in memory and passes exact bytes. The
# expectations are independent literals, not the implementation's tables. No
# Lua is executed, main() is not invoked here, and coverage counts, evidence
# and the report command line belong to later tasks.

import copy

SCHEMA_STATUS = "COVERAGE_API_ONLY_REPORT_CLI_PENDING"
SCHEMA_OLD_STATUS = "PARSER_ONLY_" + "FULL_VALIDATION_PENDING"
SCHEMA_CHARGE = "readout.charge_counts"
SCHEMA_MAX_ENTRIES = 64
# C1, Unicode spaces, line separator, zero-width, bidi, combining, BOM inside
# text and noncharacters: scalars the runtime text contract does not exclude.
SCHEMA_ALLOWED_SCALARS = (
    "\u0085", "\u00a0", "\u3000", "\u2028", "\u200b", "\u202e", "\u0301", "e\u0301",
    "a\ufeffb", "\ufdd0", "\uffff", "\U0010ffff",
)
SCHEMA_VALID_TEMPLATES = (
    "B:{banish} R:{reroll} F:{freeze}",
    "{freeze}{reroll}{banish}",
    "{{B}} {banish} {{R}} {reroll} {{F}} {freeze} }}{{",
    "{{{banish}}} {reroll} {freeze}",
    "100% {banish} %d {reroll} %s {freeze} %% %1$s",
    "Bannir\u00a0: {banish} \u2022 {reroll} \u2022 {freeze}",
    "{banish}{reroll}{freeze}" + "x" * 232,
)
SCHEMA_INVALID_TEMPLATES = (
    "{banish} {reroll}",
    "{banish} {banish} {reroll} {freeze}",
    "{banish}{reroll}{freeze}{banish}",
    "{banish} {reroll} {freeze} {other}",
    "{BANISH} {reroll} {freeze}",
    "{1} {banish} {reroll} {freeze}",
    "{banish:d} {reroll} {freeze}",
    "{banish} {reroll} {freeze} %s {0}",
    "{ banish} {reroll} {freeze}",
    "{} {banish} {reroll} {freeze}",
    "{{banish}} {reroll} {freeze}",
    "{banish} {reroll} {freeze} {",
    "{banish} {reroll} {freeze} }",
    "{banish} {reroll} {freeze} }}}",
    "|cff{banish} {reroll} {freeze}",
    "{banish} {reroll}\n{freeze}",
    "{banish}{reroll}{freeze}" + "x" * 233,
    "Charges",
)


def schema_lua_string(text):
    """A double-quoted Lua 5.1 literal of text: raw UTF-8 bytes, with decimal
    escapes for control bytes, the quote and the backslash."""
    out = bytearray(b'"')
    for byte in text.encode("utf-8"):
        if byte < 32 or byte in (34, 92, 127):
            out += b"\\%03d" % byte
        else:
            out.append(byte)
    out += b'"'
    return bytes(out)


def schema_items(table):
    return b"".join(b"[" + schema_lua_string(key) + b"] = " + schema_lua_string(value) + b", "
                    for key, value in table.items())


def schema_english_source(table):
    return CATALOG_HEADS["english"] + b"{ " + schema_items(table) + b"}\n"


def schema_packs_source(packs):
    rows = b"".join(b"[" + schema_lua_string(pack_id) + b"] = { name = "
                    + schema_lua_string(pack["name"]) + b", entries = { "
                    + schema_items(pack["entries"]) + b"} }, "
                    for pack_id, pack in packs.items())
    return CATALOG_HEADS["packs"] + b"{ " + rows + b"}\n"


def schema_json(document):
    return json.dumps(document, ensure_ascii=False).encode("utf-8")


def schema_row(context, key):
    return next(row for row in context["keys"] if row["key"] == key)


def schema_product(release, product_id):
    return next(item for item in release["products"] if item["productId"] == product_id)


def schema_slots(*names, kind="count"):
    return [{"name": name, "type": kind} for name in names]


class CatalogSchemaApi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog_parser()
        cls.raw = {
            "english": (ROOT / "data/LocalizationEnglish.lua").read_bytes(),
            "packs": (ROOT / "data/LocalizationPacks.lua").read_bytes(),
            "context": (ROOT / "docs/localization/KEY_CONTEXT.json").read_bytes(),
            "release": (ROOT / "docs/localization/RELEASE_LANGUAGES.json").read_bytes(),
        }
        cls.context = load_document("KEY_CONTEXT.json")
        cls.release = load_document("RELEASE_LANGUAGES.json")

    def fixture(self):
        return (copy.deepcopy(CATALOG_CURRENT_ENGLISH), copy.deepcopy(CATALOG_CURRENT_PACKS),
                copy.deepcopy(self.context), copy.deepcopy(self.release))

    def mutated(self, change):
        english, packs, context, release = self.fixture()
        change(english, packs, context, release)
        return {"english": english, "packs": packs, "context": context, "release": release}

    def run_api(self, english=None, packs=None, context=None, release=None):
        parts = []
        for name, value, render in (("english", english, schema_english_source),
                                    ("packs", packs, schema_packs_source),
                                    ("context", context, schema_json),
                                    ("release", release, schema_json)):
            if value is None:
                value = self.raw[name]
            elif not isinstance(value, (bytes, bytearray)):
                value = render(value)
            parts.append(value)
        return self.catalog.validate_catalog_data(*parts)

    def assert_invalid(self, code, **parts):
        with self.assertRaises(self.catalog.CatalogValidationError) as caught:
            self.run_api(**parts)
        self.assertEqual(caught.exception.code, code)
        self.assertIn(code, self.catalog.VALIDATION_CODES)

    def assert_cases(self, cases):
        """Each case is (label, change, expected code, or None when accepted)."""
        for label, change, code in cases:
            with self.subTest(label):
                parts = self.mutated(change)
                if code is None:
                    self.run_api(**parts)
                else:
                    self.assert_invalid(code, **parts)

    def replaced(self, name, old, new):
        self.assertEqual(self.raw[name].count(old), 1, old)
        return self.raw[name].replace(old, new)

    @staticmethod
    def add_static(english, context, key, text):
        english[key] = text
        context["keys"].append({"key": key, "kind": "text", "english": text, "placeholders": [],
                                "meaning": "synthetic fixture text for " + key})

    @staticmethod
    def set_charge(english, context, template):
        english[SCHEMA_CHARGE] = template
        schema_row(context, SCHEMA_CHARGE)["english"] = template

    def filled(self, english, context):
        for index in range(SCHEMA_MAX_ENTRIES - len(english)):
            self.add_static(english, context, "bulk.key_%02d" % index, "Bulk text %d" % index)

    def test_current_source_is_accepted_as_partial_data(self):
        result = self.run_api()
        self.assertIs(type(result), dict)
        self.assertEqual(sorted(result), ["english", "keyContext", "packs", "release"])
        self.assertEqual(result["english"], CATALOG_CURRENT_ENGLISH)
        self.assertEqual(result["packs"], CATALOG_CURRENT_PACKS)
        self.assertEqual(result["keyContext"], self.context)
        self.assertEqual(result["release"], self.release)
        self.assertEqual({row["key"] for row in result["keyContext"]["keys"]},
                         set(result["english"]))
        for pack_id, pack in result["packs"].items():
            self.assertLess(set(pack["entries"]), set(result["english"]), pack_id)
        self.assertEqual(result["release"]["validator"]["status"], SCHEMA_STATUS)
        self.assertEqual((self.catalog.STATUS, self.catalog.NOTICE["fullValidation"]),
                         (SCHEMA_STATUS, "NOT_IMPLEMENTED"))

    def test_inputs_are_bytes_or_bytearray_only(self):
        names = ("english", "packs", "context", "release")
        for index, name in enumerate(names):
            for value in (self.raw[name].decode("utf-8"), ROOT / "data/LocalizationEnglish.lua",
                          None, memoryview(self.raw[name])):
                arguments = [self.raw[other] for other in names]
                arguments[index] = value
                with self.subTest(argument=name, value=type(value).__name__):
                    with self.assertRaises(TypeError):
                        self.catalog.validate_catalog_data(*arguments)
        result = self.catalog.validate_catalog_data(*[bytearray(self.raw[n]) for n in names])
        self.assertEqual(result["english"], CATALOG_CURRENT_ENGLISH)

    def test_parser_syntax_errors_keep_their_codes(self):
        twice = b'frFR = { name = "F", entries = {} }'
        cases = (
            ({"english": b""}, "bad-bootstrap"),
            ({"packs": CATALOG_HEADS["packs"] + b"{ " + twice + b", " + twice + b" }"},
             "duplicate-pack"),
            ({"english": CATALOG_HEADS["english"] + b'{ ["k.a"] = "\\200" }'}, "value-not-utf8"),
        )
        for parts, code in cases:
            with self.subTest(code):
                with self.assertRaises(self.catalog.CatalogSyntaxError) as caught:
                    self.run_api(**parts)
                self.assertEqual(caught.exception.code, code)

    def test_json_is_strict_utf8_single_objects_without_duplicates(self):
        version = b'"schemaVersion": 1,'
        cases = (
            ("context", self.raw["context"] + b"\xff", "json-not-utf8"),
            ("release", self.replaced("release", b'"Deutsch"', b'"Deu\xed\xa0\x80tsch"'),
             "json-not-utf8"),
            ("release", self.replaced("release", b'"Polski"', b'"Pol\xc0\xafski"'), "json-not-utf8"),
            ("context", b"\xef\xbb\xbf" + self.raw["context"], "json-invalid"),
            ("release", b'{"schema": "nexus.l10n.release_languages",}', "json-invalid"),
            ("context", self.raw["context"].rstrip()[:-1], "json-invalid"),
            ("context", self.replaced("context", version, version + b" " + version),
             "json-duplicate-member"),
            ("context", self.replaced("context", b'"group": "readout",',
                                      b'"group": "readout", "group": "other",'),
             "json-duplicate-member"),
            ("release", self.replaced("release", b'"fallbackProductId": "enUS",',
                                      b'"fallbackProductId": "enUS", "fallbackProductId": "enUS",'),
             "json-duplicate-member"),
            ("context", self.replaced("context", version, b'"schemaVersion": NaN,'),
             "json-nonstandard-constant"),
            ("release", self.replaced("release", version, b'"schemaVersion": Infinity,'),
             "json-nonstandard-constant"),
            ("release", self.replaced("release", version, b'"schemaVersion": -Infinity,'),
             "json-nonstandard-constant"),
            ("context", self.replaced("context", version, b'"schemaVersion": 1e400,'),
             "json-nonfinite-number"),
            ("release", self.replaced("release", b'"Deutsch"', b'"Deu\\ud800tsch"'),
             "json-surrogate"),
            ("context", self.replaced("context", b'"normalization": "none",',
                                      b'"normalization": "\\udc00\\ud800",'), "json-surrogate"),
            ("context", self.replaced("context", b'"refs": ["#139", "#147"],',
                                      b'"refs": ["#139", "#147"], "\\udfffx": 0,'), "json-surrogate"),
        )
        for which in ("context", "release"):
            for document in (b"[]", b'"text"', b"null", b"1", b"true"):
                cases += ((which, document, "json-top-level"),)
        for which, data, code in cases:
            with self.subTest(which=which, code=code, data=data[:60]):
                self.assert_invalid(code, **{which: data})
        pair = self.replaced("context", b'"meaning": "a list is still being prepared",',
                             b'"meaning": "a list is still being prepared \\ud83d\\ude00",')
        meaning = schema_row(self.run_api(context=pair)["keyContext"],
                             "reason.list_preparing")["meaning"]
        self.assertTrue(meaning.endswith("\U0001f600"))

    def test_context_rows_equal_the_english_key_set(self):
        extra = {"key": "reason.not_in_english", "kind": "text", "english": "Extra",
                 "placeholders": [], "meaning": "a row without an English key"}
        row = schema_row
        cases = (
            ("context row omitted", lambda e, p, c, r: c["keys"].pop(1), "context-key-mismatch"),
            ("extra context row", lambda e, p, c, r: c["keys"].append(dict(extra)),
             "context-key-mismatch"),
            ("English key without a row",
             lambda e, p, c, r: e.update({"reason.no_context_row": "No row"}),
             "context-key-mismatch"),
            ("duplicate context row",
             lambda e, p, c, r: c["keys"].append(copy.deepcopy(c["keys"][0])),
             "context-duplicate-key"),
            ("invalid context key", lambda e, p, c, r: c["keys"][0].update({"key": "Reason.Save"}),
             "invalid-key"),
            ("context row without key", lambda e, p, c, r: c["keys"][0].pop("key"), "invalid-key"),
            ("context row not an object", lambda e, p, c, r: c["keys"].append("reason.extra"),
             "context-structure"),
            ("context English drift", lambda e, p, c, r: row(c, "reason.saved_data_reading")
             .update({"english": "Reading your saved data "}), "context-english-mismatch"),
            ("source English drift",
             lambda e, p, c, r: e.update({"reason.list_preparing": "This list is being prepared"}),
             "context-english-mismatch"),
            ("context English not text",
             lambda e, p, c, r: row(c, "reason.list_preparing").update({"english": None}),
             "context-english-mismatch"),
            ("empty meaning", lambda e, p, c, r: c["keys"][2].update({"meaning": ""}),
             "context-meaning"),
            ("blank meaning", lambda e, p, c, r: c["keys"][2].update({"meaning": " \t "}),
             "context-meaning"),
            ("meaning not text", lambda e, p, c, r: c["keys"][2].update({"meaning": ["x"]}),
             "context-meaning"),
            ("meaning missing", lambda e, p, c, r: c["keys"][5].pop("meaning"), "context-meaning"),
        )
        self.assert_cases(cases)

    def test_coherent_extra_static_key_validates_with_derived_cardinality(self):
        english, packs, context, release = self.fixture()
        text = "Static {banish} }{ {1} {name:d} 100% %d %s"
        self.add_static(english, context, "reason.synthetic_extra", text)
        result = self.run_api(english, packs, context, release)
        self.assertEqual(len(result["english"]), len(CATALOG_CURRENT_ENGLISH) + 1)
        self.assertEqual(result["english"]["reason.synthetic_extra"], text)
        packs["frFR"]["entries"]["reason.synthetic_extra"] = "Texte {statique} }{"
        self.assertEqual(self.run_api(english, packs, context, release)["packs"], packs)

    def test_runtime_key_bounds_and_shape(self):
        for key in ("a.b", "a." + "b" * 62, "x9.y_z.w0", "a_.b_"):
            with self.subTest(accepted=key):
                english, packs, context, release = self.fixture()
                self.add_static(english, context, key, "Synthetic")
                self.assertIn(key, self.run_api(english, packs, context, release)["english"])
        for key in ("a." + "b" * 63, "ab", "abc", "a.", ".a.b", "a..b", "_a.b", "1a.b", "A.b",
                    "a.B", "a.1b", "a._b", "a.b-c", "a.b ", "a.\u00e9"):
            with self.subTest(rejected=key):
                english, packs, context, release = self.fixture()
                self.add_static(english, context, key, "Synthetic")
                self.assert_invalid("invalid-key", english=english, packs=packs, context=context,
                                    release=release)
        english, packs, context, release = self.fixture()
        self.filled(english, context)
        self.assertEqual(len(self.run_api(english, packs, context, release)["english"]),
                         SCHEMA_MAX_ENTRIES)
        self.add_static(english, context, "bulk.key_over", "Over")
        self.assert_invalid("english-too-many", english=english, packs=packs, context=context,
                            release=release)
        self.assert_invalid("english-empty", english={})

    def test_runtime_text_contract_bytes(self):
        accepted = ("x" * 256, "\u00e9" * 128, "\u20ac" * 85 + "a", "!", "a b") + SCHEMA_ALLOWED_SCALARS
        rejected = ("", "x" * 257, "\u00e9" * 128 + "a", " ", "     ", "\t", " \n ", "a\tb",
                    "a\nb", "a\rb", "a\x00b", "a\x1fb", "a\x7fb", "a|b", "|")
        for text in accepted:
            with self.subTest(accepted=ascii(text)[:40]):
                english, packs, context, release = self.fixture()
                self.add_static(english, context, "reason.synthetic_text", text)
                packs["frFR"]["entries"]["reason.list_preparing"] = text
                self.run_api(english, packs, context, release)
        for text in rejected:
            with self.subTest(rejected_english=ascii(text)[:40]):
                english, packs, context, release = self.fixture()
                self.add_static(english, context, "reason.synthetic_text", text)
                self.assert_invalid("invalid-text", english=english, context=context)
            with self.subTest(rejected_entry=ascii(text)[:40]):
                english, packs, context, release = self.fixture()
                packs["frFR"]["entries"]["reason.list_preparing"] = text
                self.assert_invalid("invalid-text", packs=packs)

    def test_packs_match_selected_products_and_may_be_partial(self):
        def autonym(packs, release, pack_id, name):
            packs[pack_id]["name"] = name
            schema_product(release, pack_id)["autonym"] = name
        extra_ids = ["q%sZZ" % chr(97 + index) for index in range(11)]
        cases = (
            ("missing individual entry",
             lambda e, p, c, r: p["frFR"]["entries"].pop("reason.list_preparing"), None),
            ("empty entries", lambda e, p, c, r: p["deDE"]["entries"].clear(), None),
            ("translated reordered template", lambda e, p, c, r: p["ruRU"]["entries"].update(
                {SCHEMA_CHARGE: "{freeze} \u0417 {reroll} \u041f {banish} \u0418"}), None),
            ("newly translated key", lambda e, p, c, r: p["esES"]["entries"].update(
                {"reason.wait_three_choices": "Esperando las pr\u00f3ximas tres opciones"}), None),
            ("64-byte autonym", lambda e, p, c, r: autonym(p, r, "plPL", "\u00e9" * 32), None),
            ("orphan entry", lambda e, p, c, r: p["frFR"]["entries"].update(
                {"reason.not_in_english": "Orphan"}), "orphan-entry"),
            ("invalid entry key", lambda e, p, c, r: p["frFR"]["entries"].update({"Reason.Bad": "x"}),
             "invalid-key"),
            ("unknown pack", lambda e, p, c, r: p.update({"itIT": {"name": "Italiano", "entries": {}}}),
             "pack-unknown"),
            ("missing pack", lambda e, p, c, r: p.pop("ruRU"), "pack-missing"),
            ("English pack", lambda e, p, c, r: p.update({"enUS": {"name": "English", "entries": {}}}),
             "pack-english"),
            ("16 packs", lambda e, p, c, r: p.update(
                {pack_id: {"name": pack_id, "entries": {}} for pack_id in extra_ids[:10]}),
             "pack-unknown"),
            ("17 packs", lambda e, p, c, r: p.update(
                {pack_id: {"name": pack_id, "entries": {}} for pack_id in extra_ids}), "pack-count"),
            ("65-byte autonym", lambda e, p, c, r: autonym(p, r, "plPL", "\u00e9" * 32 + "a"),
             "invalid-autonym"),
            ("autonym with pipe", lambda e, p, c, r: autonym(p, r, "frFR", "Fran|cais"),
             "invalid-autonym"),
            ("empty autonym", lambda e, p, c, r: autonym(p, r, "frFR", ""), "invalid-autonym"),
            ("blank autonym", lambda e, p, c, r: autonym(p, r, "frFR", "  "), "invalid-autonym"),
            ("autonym control", lambda e, p, c, r: autonym(p, r, "frFR", "Fran\ncais"),
             "invalid-autonym"),
            ("autonym differs from release", lambda e, p, c, r: p["frFR"].update({"name": "Francais"}),
             "release-autonym"),
            ("entry with pipe", lambda e, p, c, r: p["deDE"]["entries"].update(
                {"reason.list_preparing": "|cffff0000Liste|r"}), "invalid-text"),
            ("positional translated template", lambda e, p, c, r: p["frFR"]["entries"].update(
                {SCHEMA_CHARGE: "{1} {reroll} {freeze}"}), "invalid-template"),
        )
        self.assert_cases(cases)
        english, packs, context, release = self.fixture()
        self.filled(english, context)
        packs["frFR"]["entries"] = dict(english)
        self.run_api(english, packs, context, release)
        packs["frFR"]["entries"]["bulk.key_over"] = "Over"
        self.assert_invalid("pack-too-many-entries", english=english, packs=packs, context=context,
                            release=release)

    def test_charge_template_grammar_for_english_and_translations(self):
        for template in SCHEMA_VALID_TEMPLATES:
            with self.subTest(valid=template[:40]):
                english, packs, context, release = self.fixture()
                self.set_charge(english, context, template)
                packs["frFR"]["entries"][SCHEMA_CHARGE] = template
                result = self.run_api(english, packs, context, release)
                self.assertEqual(result["english"][SCHEMA_CHARGE], template)
                self.assertEqual(result["packs"]["frFR"]["entries"][SCHEMA_CHARGE], template)
        for template in SCHEMA_INVALID_TEMPLATES:
            with self.subTest(english=template[:40]):
                english, packs, context, release = self.fixture()
                self.set_charge(english, context, template)
                self.assert_invalid("invalid-template", english=english, context=context)
            with self.subTest(translation=template[:40]):
                english, packs, context, release = self.fixture()
                packs["plPL"]["entries"][SCHEMA_CHARGE] = template
                self.assert_invalid("invalid-template", packs=packs)

    def test_context_cannot_redefine_the_code_owned_charge_schema(self):
        save = "reason.save_in_progress"
        charge = lambda c: schema_row(c, SCHEMA_CHARGE)
        slots = lambda value: (lambda e, p, c, r: charge(c).update({"placeholders": value}))
        limit = lambda value: (lambda e, p, c, r: charge(c).update({"resultLimitBytes": value}))

        def invented(e, p, c, r):
            e["readout.extra_counts"] = "{banish} and {reroll}"
            c["keys"].append({"key": "readout.extra_counts", "kind": "format",
                              "english": "{banish} and {reroll}", "meaning": "an invented format",
                              "placeholders": schema_slots("banish", "reroll"),
                              "resultLimitBytes": 254})
        cases = (
            ("charge declared as text",
             lambda e, p, c, r: charge(c).update({"kind": "text", "placeholders": []}), "context-kind"),
            ("charge declared as text without limit", lambda e, p, c, r: (
                charge(c).update({"kind": "text", "placeholders": []}),
                charge(c).pop("resultLimitBytes")), "context-kind"),
            ("static declared as format", lambda e, p, c, r: schema_row(c, save).update(
                {"kind": "format", "placeholders": schema_slots("banish", "reroll", "freeze"),
                 "resultLimitBytes": 254}), "context-kind"),
            ("plural kind", lambda e, p, c, r: charge(c).update({"kind": "plural"}), "context-kind"),
            ("kind missing", lambda e, p, c, r: charge(c).pop("kind"), "context-kind"),
            ("invented format key", invented, "context-kind"),
            ("missing slot", slots(schema_slots("banish", "reroll")), "context-placeholders"),
            ("extra slot", slots(schema_slots("banish", "reroll", "freeze", "total")),
             "context-placeholders"),
            ("repeated slot", slots(schema_slots("banish", "banish", "reroll", "freeze")),
             "context-placeholders"),
            ("renamed slot", slots(schema_slots("banish", "reroll", "thaw")), "context-placeholders"),
            ("number type", slots(schema_slots("banish", "reroll") + schema_slots("freeze", kind="number")),
             "context-placeholders"),
            ("typed format", slots(schema_slots("banish", "reroll", "freeze", kind="d")),
             "context-placeholders"),
            ("extra slot member", slots([{"name": "banish", "type": "count", "format": "%d"}]
                                        + schema_slots("reroll", "freeze")), "context-placeholders"),
            ("slot without type", slots([{"name": "banish"}] + schema_slots("reroll", "freeze")),
             "context-placeholders"),
            ("placeholders not a list", slots("banish reroll freeze"), "context-structure"),
            ("limit 256", limit(256), "context-result-limit"),
            ("limit 253", limit(253), "context-result-limit"),
            ("limit as text", limit("254"), "context-result-limit"),
            ("limit as boolean", limit(True), "context-result-limit"),
            ("limit as float", limit(254.0), "context-result-limit"),
            ("limit missing", lambda e, p, c, r: charge(c).pop("resultLimitBytes"),
             "context-result-limit"),
            ("static claims a limit",
             lambda e, p, c, r: schema_row(c, save).update({"resultLimitBytes": 254}),
             "context-result-limit"),
            ("static claims a slot",
             lambda e, p, c, r: schema_row(c, save).update({"placeholders": schema_slots("banish")}),
             "context-placeholders"),
        )
        self.assert_cases(cases)

    def test_key_context_header_containers_and_runtime_limits(self):
        whitespace = lambda value: (
            lambda e, p, c, r: c["textContract"].update({"asciiWhitespaceBytes": value}))
        cases = (
            ("schema", lambda e, p, c, r: c.update({"schema": "nexus.l10n.other"}), "context-schema"),
            ("boolean version", lambda e, p, c, r: c.update({"schemaVersion": True}), "context-schema"),
            ("float version", lambda e, p, c, r: c.update({"schemaVersion": 1.0}), "context-schema"),
            ("text version", lambda e, p, c, r: c.update({"schemaVersion": "1"}), "context-schema"),
            ("version 2", lambda e, p, c, r: c.update({"schemaVersion": 2}), "context-schema"),
            ("contract kind", lambda e, p, c, r: c.update({"contractKind": "runtime_authority"}),
             "context-schema"),
            ("no contract kind", lambda e, p, c, r: c.pop("contractKind"), "context-schema"),
            ("authority", lambda e, p, c, r: c.update({"authority": "core/UserText.lua"}),
             "context-source"),
            ("English base", lambda e, p, c, r: c.update({"englishBase": "data/LocalizationPacks.lua"}),
             "context-source"),
            ("key bytes above runtime", lambda e, p, c, r: c["keySchema"].update({"maxBytes": 65}),
             "context-limit"),
            ("key minimum", lambda e, p, c, r: c["keySchema"].update({"minBytes": 2}), "context-limit"),
            ("text bytes below runtime",
             lambda e, p, c, r: c["textContract"].update({"maxBytes": 254}), "context-limit"),
            ("text minimum", lambda e, p, c, r: c["textContract"].update({"minBytes": 0}),
             "context-limit"),
            ("whitespace omits 11", whitespace([9, 10, 12, 13, 32]), "context-limit"),
            ("Unicode whitespace added", whitespace([9, 10, 11, 12, 13, 32, 133]), "context-limit"),
            ("whitespace as text", whitespace(["9", "10", "11", "12", "13", "32"]), "context-limit"),
            ("printf percent", lambda e, p, c, r: c["templateGrammar"].update({"percentSign": "printf"}),
             "context-grammar"),
            ("brace escapes",
             lambda e, p, c, r: c["templateGrammar"].update({"literalBraces": {"[[": "{"}}),
             "context-grammar"),
            ("keys object", lambda e, p, c, r: c.update({"keys": {}}), "context-structure"),
            ("no window families", lambda e, p, c, r: c.pop("windowFamilies"), "context-structure"),
            ("pack coverage list", lambda e, p, c, r: c.update({"packCoverage": []}),
             "context-structure"),
            ("adoption text", lambda e, p, c, r: c.update({"currentAdoption": "PENDING"}),
             "context-structure"),
            ("no template grammar", lambda e, p, c, r: c.pop("templateGrammar"), "context-structure"),
            ("historical pin differs",
             lambda e, p, c, r: c.update({"sourcePin": {"base": "0" * 40, "tree": "f" * 40}}), None),
            ("later field", lambda e, p, c, r: c.update({"laterCoverage": {"status": "PENDING"}}),
             None),
        )
        self.assert_cases(cases)

    def test_release_metadata_products_and_sources(self):
        product = schema_product
        cases = (
            ("schema", lambda e, p, c, r: r.update({"schema": "nexus.l10n.other"}), "release-schema"),
            ("boolean version", lambda e, p, c, r: r.update({"schemaVersion": True}), "release-schema"),
            ("contract kind", lambda e, p, c, r: r.update({"contractKind": "release_authority"}),
             "release-schema"),
            ("validator path", lambda e, p, c, r: r["validator"].update({"path": "tools/other.py"}),
             "release-validator"),
            ("previous validator status",
             lambda e, p, c, r: r["validator"].update({"status": SCHEMA_OLD_STATUS}),
             "release-validator"),
            ("validator not an object",
             lambda e, p, c, r: r.update({"validator": "tools/l10n_catalog.py"}), "release-validator"),
            ("fallback product", lambda e, p, c, r: r.update({"fallbackProductId": "frFR"}),
             "release-products"),
            ("products object", lambda e, p, c, r: r.update({"products": {}}), "release-structure"),
            ("duplicate product ID",
             lambda e, p, c, r: r["products"].append(copy.deepcopy(r["products"][1])),
             "release-duplicate-product"),
            ("missing product", lambda e, p, c, r: r["products"].pop(4), "release-products"),
            ("unknown product", lambda e, p, c, r: r["products"].append(
                dict(copy.deepcopy(r["products"][1]), productId="itIT")), "release-products"),
            ("client-style product ID",
             lambda e, p, c, r: product(r, "frFR").update({"productId": "fr"}), "release-products"),
            ("product ID not text",
             lambda e, p, c, r: product(r, "esES").update({"productId": 7}), "release-structure"),
            ("pack declared as baseline",
             lambda e, p, c, r: product(r, "frFR").update({"kind": "english_baseline"}),
             "release-product-kind"),
            ("English declared as pack",
             lambda e, p, c, r: product(r, "enUS").update({"kind": "optional_ui_pack"}),
             "release-product-kind"),
            ("English autonym", lambda e, p, c, r: product(r, "enUS").update({"autonym": "Anglais"}),
             "release-autonym"),
            ("pack autonym", lambda e, p, c, r: product(r, "deDE").update({"autonym": "German"}),
             "release-autonym"),
            ("missing autonym", lambda e, p, c, r: product(r, "ruRU").pop("autonym"),
             "release-structure"),
            ("English text source", lambda e, p, c, r: product(r, "enUS").update(
                {"textSource": "data/LocalizationPacks.lua"}), "release-text-source"),
            ("pack text source", lambda e, p, c, r: product(r, "plPL").update(
                {"textSource": "data/LocalizationEnglish.lua"}), "release-text-source"),
            ("product ID as client locale", lambda e, p, c, r: product(r, "ptBR").update(
                {"productIdIsClientLocale": True}), "release-client-locale"),
        )
        self.assert_cases(cases)
        english, packs, context, release = self.fixture()
        release["laterEvidence"] = {"status": "PENDING", "records": []}
        product(release, "frFR")["laterCoverage"] = {"status": "PENDING"}
        result = self.run_api(release=release)
        self.assertEqual(result["release"], release)
        self.assertEqual(product(result["release"], "frFR")["review"],
                         product(self.release, "frFR")["review"])



# B3a coverage report API (Refs #147): public tests of catalog_report and
# CatalogEvidenceError. Each case builds exact bytes in memory from the
# literal tables above and calls the public API. Expected counts come from
# those tables or from the fixture being built, never from the implementation.
# Reviewer names and evidence URLs here are synthetic, fixture-only values:
# they name no person, record no review and claim no fluent, human or native
# acceptance. No file is written, no Lua is executed and main() is not
# invoked here; the filesystem command line belongs to B3b.

import hashlib

REPORT_CATEGORIES = (
    "translated_and_reviewed", "reviewed_legitimately_identical",
    "deliberate_english_placeholder", "draft_unreviewed", "missing", "invalid", "obsolete",
)
REPORT_IN_DENOMINATOR = REPORT_CATEGORIES[:6]
REPORT_FIXTURE_REVIEWER = "Synthetic Fixture Reviewer A (fixture-only, not a person)"
REPORT_OTHER_REVIEWER = "Synthetic Fixture Reviewer B (fixture-only, not a person)"
REPORT_FIXTURE_REFERENCE = "https://example.invalid/fixture-only/review-evidence"
REPORT_NOT_EVIDENCE = "not evidence of fluent competence, contributor rights or native truth"
REPORT_SAVE = "reason.save_in_progress"
REPORT_LIST = "reason.list_preparing"
REPORT_FILL = {
    "reason.wait_three_choices": "Synthetic fixture wait text",
    "reason.wait_pending_pick_count": "Synthetic fixture pick-count text",
    "readout.charge_counts": "Synthetic fixture {freeze} {reroll} {banish}",
}
REPORT_PENDING_GATES = {
    "technicalAuthorReview": {"status": "pending", "recordCount": 0},
    "fluentHumanAcceptance": {"status": "pending", "recordCount": 0,
                              "responsibility": "UNASSIGNED"},
    "nativeAcceptance": {"status": "NOT_RUN", "recordCount": 0},
}
REPORT_REMAINING_REASONS = {
    "review-gate-not-established", "family-semantic-status", "family-coverage-status",
    "family-no-adopted-key", "keys-without-family", "adoption-semantic-coverage",
    "other-visible-copy", "visible-text-denominator", "terminology-status",
    "native-fact-not-established",
}


def report_sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def report_declaration(product_id, key, text, decision="translated", **changes):
    """A synthetic, fixture-only entry-review declaration for text."""
    record = {"productId": product_id, "key": key, "translatedTextSha256": report_sha(text),
              "reviewer": REPORT_FIXTURE_REVIEWER, "decision": decision,
              "evidenceReference": REPORT_FIXTURE_REFERENCE, "status": "declared"}
    record.update(changes)
    return record


def report_without(record, field):
    record = dict(record)
    record.pop(field)
    return record


def report_add_static(english, context, key, text):
    english[key] = text
    context["keys"].append({"key": key, "kind": "text", "english": text, "placeholders": [],
                            "meaning": "synthetic fixture text for " + key})


def report_codes(report):
    return {reason["code"] for reason in report["completeness"]["reasons"]}


def report_reasons(report, code, subject=None):
    return [reason for reason in report["completeness"]["reasons"]
            if reason["code"] == code and (subject is None or reason["subject"] == subject)]


def report_product(report, product_id):
    return next(row for row in report["products"] if row["productId"] == product_id)


class CatalogCoverageReport(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog_parser()
        cls.raw = {
            "english": (ROOT / "data/LocalizationEnglish.lua").read_bytes(),
            "packs": (ROOT / "data/LocalizationPacks.lua").read_bytes(),
            "context": (ROOT / "docs/localization/KEY_CONTEXT.json").read_bytes(),
            "release": (ROOT / "docs/localization/RELEASE_LANGUAGES.json").read_bytes(),
        }
        cls.context = load_document("KEY_CONTEXT.json")
        cls.release = load_document("RELEASE_LANGUAGES.json")

    def fixture(self):
        return (copy.deepcopy(CATALOG_CURRENT_ENGLISH), copy.deepcopy(CATALOG_CURRENT_PACKS),
                copy.deepcopy(self.context), copy.deepcopy(self.release))

    def inputs(self, english=None, packs=None, context=None, release=None):
        parts = []
        for name, value, render in (("english", english, schema_english_source),
                                    ("packs", packs, schema_packs_source),
                                    ("context", context, schema_json),
                                    ("release", release, schema_json)):
            if value is None:
                value = self.raw[name]
            elif not isinstance(value, (bytes, bytearray)):
                value = render(value)
            parts.append(value)
        return parts

    def report(self, **parts):
        return self.catalog.catalog_report(*self.inputs(**parts))

    def declared(self, records, release=None):
        release = copy.deepcopy(self.release if release is None else release)
        release["entryReview"]["declarations"] = copy.deepcopy(records)
        return release

    def assert_evidence(self, code, **parts):
        with self.assertRaises(self.catalog.CatalogEvidenceError) as caught:
            self.report(**parts)
        self.assertEqual(caught.exception.code, code)
        self.assertIn(code, self.catalog.EVIDENCE_CODES)

    def assert_reconciled(self, row, english_keys):
        self.assertEqual(list(row["counts"]), list(REPORT_CATEGORIES))
        self.assertEqual(list(row["keys"]), list(REPORT_CATEGORIES))
        for category in REPORT_CATEGORIES:
            self.assertEqual(row["counts"][category], len(row["keys"][category]), category)
            self.assertEqual(row["keys"][category], sorted(row["keys"][category]), category)
        listed = [key for category in REPORT_IN_DENOMINATOR for key in row["keys"][category]]
        self.assertEqual(len(listed), len(set(listed)))
        self.assertEqual(sorted(listed), sorted(english_keys))
        self.assertEqual(row["denominator"], len(english_keys))
        self.assertEqual(row["reconciliation"], {"denominator": len(english_keys),
                                                 "inDenominatorTotal": len(english_keys)})
        self.assertEqual((row["counts"]["invalid"], row["counts"]["obsolete"]), (0, 0))

    def test_current_release_records_no_declaration_and_states_the_limit(self):
        contract = self.release["entryReview"]
        self.assertEqual(contract["contract"], "nexus.l10n.entry_review_declaration")
        self.assertEqual(contract["contractVersion"], 1)
        self.assertEqual(contract["declarations"], [])
        self.assertIn(REPORT_NOT_EVIDENCE, contract["notEvidenceOf"])
        self.assertEqual(self.release["terminology"], {
            "status": "pending",
            "reference": "docs/localization/KEYS_AND_GLOSSARY.md (historical proposal, unchanged)",
            "gameTermWording": "UNKNOWN until a verified client reference exists",
        })
        self.assertIn(REPORT_NOT_EVIDENCE, self.catalog.EVIDENCE_NOTICE)
        self.assertEqual(self.catalog.NOTICE["fullValidation"], "NOT_IMPLEMENTED")
        plan = " ".join(read_text("docs/localization/FULL_COVERAGE.md").split())
        for required in ("catalog_report", "CatalogEvidenceError", REPORT_NOT_EVIDENCE, "B3b",
                         "NOT_IMPLEMENTED", "Execution of the new tests: NOT_RUN"):
            self.assertIn(required, plan)

    def test_supplied_partial_data_derives_draft_and_missing_per_optional_pack(self):
        report = self.report()
        english_keys = sorted(CATALOG_CURRENT_ENGLISH)
        self.assertEqual((report["schema"], report["schemaVersion"], report["tool"]),
                         ("nexus.l10n.coverage_report", 1, "tools/l10n_catalog.py"))
        self.assertEqual((report["status"], report["fullValidation"]),
                         (SCHEMA_STATUS, "NOT_IMPLEMENTED"))
        self.assertEqual(report["categories"], list(REPORT_CATEGORIES))
        self.assertEqual(tuple(self.catalog.ENTRY_CATEGORIES), REPORT_CATEGORIES)
        baseline = report["englishBaseline"]
        self.assertEqual((baseline["productId"], baseline["kind"], baseline["keyCount"]),
                         ("enUS", "english_baseline", len(english_keys)))
        self.assertEqual(baseline["keys"], english_keys)
        self.assertEqual([row["productId"] for row in report["products"]], PACK_IDS)
        autonyms = {row[0]: row[3] for row in EXPECTED_PRODUCTS}
        for row in report["products"]:
            pack_id = row["productId"]
            with self.subTest(pack_id):
                self.assert_reconciled(row, english_keys)
                self.assertEqual((row["kind"], row["autonym"]),
                                 ("optional_ui_pack", autonyms[pack_id]))
                self.assertEqual(row["keys"]["draft_unreviewed"], sorted(STATIC_AT_BASE))
                self.assertEqual(row["keys"]["missing"], sorted(MISSING_AT_BASE))
                for category in REPORT_CATEGORIES:
                    if category not in ("draft_unreviewed", "missing"):
                        self.assertEqual(row["keys"][category], [], category)
                self.assertEqual(row["entriesPresent"],
                                 len(CATALOG_CURRENT_PACKS[pack_id]["entries"]))
                self.assertEqual(row["declarationsApplied"], 0)
                self.assertEqual(report_reasons(report, "entries-missing", pack_id)[0]["keys"],
                                 sorted(MISSING_AT_BASE))
                self.assertEqual(
                    report_reasons(report, "entries-draft-unreviewed", pack_id)[0]["keys"],
                    sorted(STATIC_AT_BASE))
        self.assertEqual((report["evidence"]["declarationCount"],
                          report["evidence"]["qualifiedDeclarations"]), (0, 0))
        self.assertEqual(report["pseudoAndTestData"]["shippedProductIds"], [])
        self.assertEqual(report["reviewGates"],
                         [{"productId": row[0], "gates": REPORT_PENDING_GATES}
                          for row in EXPECTED_PRODUCTS])
        self.assertEqual(report["completeness"]["state"], "INCOMPLETE")
        self.assertEqual(report["completeness"]["reasonCount"],
                         len(report["completeness"]["reasons"]))
        self.assertLessEqual(REPORT_REMAINING_REASONS, report_codes(report))

    def test_every_family_shared_unassigned_keys_and_no_family_denominator(self):
        report = self.report()
        families = report["families"]
        self.assertEqual([(f["name"], f["proposedKeyFamily"], f["issue"], f["paths"])
                          for f in families], EXPECTED_FAMILIES)
        declared = {f["name"]: f["adoptedKeys"] for f in self.context["windowFamilies"]}
        self.assertEqual(declared["Main panel (HUD)"], [SCHEMA_CHARGE])
        for family in families:
            with self.subTest(family["name"]):
                adopted = declared[family["name"]]
                self.assertEqual(family["adoptedKeys"], adopted)
                self.assertEqual(family["adoptedKeyCount"], len(adopted))
                self.assertEqual((family["semanticStatus"], family["coverageStatus"]),
                                 ("PENDING", "PENDING"))
                self.assertEqual(family["state"], "INCOMPLETE")
                codes = [reason["code"] for reason in family["reasons"]]
                self.assertEqual(codes[:2], ["family-semantic-status", "family-coverage-status"])
                self.assertEqual("family-no-adopted-key" in codes, not adopted)
                self.assertEqual([row["productId"] for row in family["products"]], PACK_IDS)
                for row in family["products"]:
                    self.assertEqual(sum(row["counts"].values()), len(adopted))
                    self.assertEqual(row["keys"]["missing"],
                                     [key for key in sorted(adopted) if key in MISSING_AT_BASE])
        self.assertEqual([(r["subject"], r["value"], r["keys"])
                          for r in report_reasons(report, "family-entries-not-reviewed")],
                         [("Main panel (HUD)", pack_id, [SCHEMA_CHARGE]) for pack_id in PACK_IDS])
        unassigned = sorted(set(CATALOG_CURRENT_ENGLISH) - {SCHEMA_CHARGE})
        self.assertEqual([row["key"] for row in report["unassignedKeys"]], unassigned)
        for row in report["unassignedKeys"]:
            expected = "missing" if row["key"] in MISSING_AT_BASE else "draft_unreviewed"
            self.assertEqual(row["products"], [{"productId": pack_id, "category": expected}
                                               for pack_id in PACK_IDS])
        self.assertEqual(report_reasons(report, "keys-without-family")[0]["keys"], unassigned)
        references = [key for keys in declared.values() for key in keys]
        denominator = report["denominator"]
        self.assertEqual(denominator["englishKeys"], len(CATALOG_CURRENT_ENGLISH))
        self.assertEqual(denominator["familyAdoptedKeyReferences"], len(references))
        self.assertEqual(denominator["distinctFamilyAdoptedKeys"], len(set(references)))
        self.assertEqual(denominator["keysOnMultipleFamilies"], [])
        self.assertEqual(denominator["keysWithoutFamily"], unassigned)
        surfaces = report["surfaces"]
        self.assertEqual(surfaces["currentAdoptionKeys"], self.context["currentAdoption"]["keys"])
        self.assertEqual(surfaces["allWindowSemanticCoverage"], "PENDING")
        self.assertEqual(surfaces["visibleTextDenominator"], "NOT_ESTABLISHED")
        other = self.context["otherVisibleCopy"]
        self.assertEqual([item["status"] for item in surfaces["otherVisibleCopy"]],
                         ["PENDING_CLASSIFICATION"] * len(other))
        self.assertEqual(len(report_reasons(report, "other-visible-copy")), len(other))
        self.assertEqual(report_reasons(report, "visible-text-denominator")[0]["value"],
                         "NOT_ESTABLISHED")
        native = report["nativeFacts"]
        self.assertEqual(native["establishedByThisReport"], "NOT_RUN")
        self.assertEqual((native["declared"]["fontFace"], native["declared"]["glyphCoverage"],
                          native["declared"]["nativeLayout"]), ("UNKNOWN", "UNKNOWN", "NOT_RUN"))
        self.assertEqual(report_reasons(report, "native-fact-not-established",
                                        "release.clientEvidence.fontFace")[0]["value"], "UNKNOWN")

    def test_shared_key_on_two_families_counts_once_in_the_denominator(self):
        english, packs, context, release = self.fixture()
        shared = "reason.synthetic_shared"
        report_add_static(english, context, shared, "Synthetic shared fixture text")
        families = {family["name"]: family for family in context["windowFamilies"]}
        families["Main panel (HUD)"]["adoptedKeys"].append(shared)
        families["Help"]["adoptedKeys"].append(shared)
        report = self.report(english=english, packs=packs, context=context, release=release)
        english_keys = sorted(english)
        self.assertEqual(len(english_keys), len(CATALOG_CURRENT_ENGLISH) + 1)
        references = [key for family in context["windowFamilies"] for key in family["adoptedKeys"]]
        denominator = report["denominator"]
        self.assertEqual(denominator["englishKeys"], len(english_keys))
        self.assertEqual(denominator["keysOnMultipleFamilies"], [shared])
        self.assertEqual(denominator["familyAdoptedKeyReferences"], len(references))
        self.assertEqual(denominator["distinctFamilyAdoptedKeys"], len(set(references)))
        self.assertLess(len(set(references)), len(references))
        self.assertEqual(denominator["keysWithoutFamily"],
                         sorted(set(CATALOG_CURRENT_ENGLISH) - {SCHEMA_CHARGE}))
        self.assertEqual(len(report["families"]), len(EXPECTED_FAMILIES))
        rows = {family["name"]: family for family in report["families"]}
        self.assertEqual(rows["Help"]["adoptedKeys"], [shared])
        self.assertEqual(rows["Main panel (HUD)"]["adoptedKeys"], [SCHEMA_CHARGE, shared])
        for product in rows["Help"]["products"]:
            self.assertEqual(product["keys"]["missing"], [shared])
        for row in report["products"]:
            self.assert_reconciled(row, english_keys)
            self.assertEqual(row["keys"]["missing"], sorted(MISSING_AT_BASE + [shared]))

    def test_coherent_added_static_key_updates_every_denominator(self):
        english, packs, context, release = self.fixture()
        extra = "reason.synthetic_extra"
        report_add_static(english, context, extra, "Synthetic extra fixture text")
        packs["frFR"]["entries"][extra] = "Texte de fixture synthetique"
        report = self.report(english=english, packs=packs, context=context, release=release)
        english_keys = sorted(english)
        self.assertEqual(report["englishBaseline"]["keyCount"], len(CATALOG_CURRENT_ENGLISH) + 1)
        self.assertEqual(report["denominator"]["englishKeys"], len(english_keys))
        for row in report["products"]:
            with self.subTest(row["productId"]):
                self.assert_reconciled(row, english_keys)
                if row["productId"] == "frFR":
                    draft, missing = STATIC_AT_BASE + [extra], MISSING_AT_BASE
                else:
                    draft, missing = STATIC_AT_BASE, MISSING_AT_BASE + [extra]
                self.assertEqual(row["keys"]["draft_unreviewed"], sorted(draft))
                self.assertEqual(row["keys"]["missing"], sorted(missing))
        self.assertIn(extra, report["denominator"]["keysWithoutFamily"])
        self.assertIn(extra, [row["key"] for row in report["unassignedKeys"]])

    def test_no_declared_family_leaves_every_key_without_family(self):
        context = copy.deepcopy(self.context)
        context["windowFamilies"] = []
        report = self.report(context=context)
        self.assertEqual(report["families"], [])
        self.assertEqual(report["denominator"]["englishKeys"], len(CATALOG_CURRENT_ENGLISH))
        self.assertEqual(report["denominator"]["keysWithoutFamily"],
                         sorted(CATALOG_CURRENT_ENGLISH))
        self.assertEqual(len(report_reasons(report, "no-window-family")), 1)
        self.assertEqual(report["completeness"]["state"], "INCOMPLETE")

    def test_filling_missing_known_entries_still_leaves_concrete_reasons(self):
        english, packs, context, release = self.fixture()
        for pack in packs.values():
            pack["entries"].update(REPORT_FILL)
        report = self.report(packs=packs)
        english_keys = sorted(CATALOG_CURRENT_ENGLISH)
        for row in report["products"]:
            self.assert_reconciled(row, english_keys)
            self.assertEqual(row["keys"]["draft_unreviewed"], english_keys)
            self.assertEqual(row["counts"]["missing"], 0)
            self.assertEqual(row["entriesPresent"], len(english_keys))
        codes = report_codes(report)
        self.assertNotIn("entries-missing", codes)
        self.assertEqual([r["subject"] for r in report_reasons(report, "entries-draft-unreviewed")],
                         PACK_IDS)
        self.assertLessEqual(REPORT_REMAINING_REASONS, codes)
        self.assertEqual(report["completeness"]["state"], "INCOMPLETE")
        records = [report_declaration(pack_id, key, text) for pack_id, pack in packs.items()
                   for key, text in sorted(pack["entries"].items())]
        reviewed = self.report(packs=packs, release=self.declared(records))
        for row in reviewed["products"]:
            self.assert_reconciled(row, english_keys)
            self.assertEqual(row["keys"]["translated_and_reviewed"], english_keys)
            self.assertEqual(row["declarationsApplied"], len(english_keys))
        codes = report_codes(reviewed)
        self.assertEqual([code for code in codes if code.startswith("entries-")], [])
        self.assertNotIn("family-entries-not-reviewed", codes)
        self.assertLessEqual(REPORT_REMAINING_REASONS, codes)
        self.assertEqual(reviewed["completeness"]["state"], "INCOMPLETE")
        self.assertEqual(len(report_reasons(reviewed, "review-gate-not-established")),
                         len(EXPECTED_PRODUCTS) * len(REPORT_PENDING_GATES))
        self.assertEqual(reviewed["reviewGates"], report["reviewGates"])
        self.assertEqual(reviewed["evidence"]["qualifiedDeclarations"], len(records))

    def test_english_identical_entry_is_a_placeholder_not_a_translation(self):
        english, packs, context, release = self.fixture()
        packs["frFR"]["entries"][REPORT_LIST] = CATALOG_CURRENT_ENGLISH[REPORT_LIST]
        packs["deDE"]["entries"][SCHEMA_CHARGE] = CATALOG_CURRENT_ENGLISH[SCHEMA_CHARGE]
        report = self.report(packs=packs)
        french, german = report_product(report, "frFR"), report_product(report, "deDE")
        self.assertEqual(french["keys"]["deliberate_english_placeholder"], [REPORT_LIST])
        self.assertEqual(french["keys"]["draft_unreviewed"],
                         sorted(set(STATIC_AT_BASE) - {REPORT_LIST}))
        self.assertEqual(german["keys"]["deliberate_english_placeholder"], [SCHEMA_CHARGE])
        self.assertEqual(german["keys"]["missing"], sorted(set(MISSING_AT_BASE) - {SCHEMA_CHARGE}))
        for row in (french, german):
            self.assert_reconciled(row, sorted(CATALOG_CURRENT_ENGLISH))
            self.assertEqual(row["keys"]["translated_and_reviewed"]
                             + row["keys"]["reviewed_legitimately_identical"], [])
        self.assertEqual(report_reasons(report, "entries-deliberate-english-placeholder",
                                        "frFR")[0]["keys"], [REPORT_LIST])

    def test_qualified_synthetic_declarations_classify_without_acceptance(self):
        english, packs, context, release = self.fixture()
        same = CATALOG_CURRENT_ENGLISH[REPORT_LIST]
        packs["frFR"]["entries"][REPORT_LIST] = same
        save = packs["frFR"]["entries"][REPORT_SAVE]
        release = self.declared([report_declaration("frFR", REPORT_SAVE, save),
                                 report_declaration("frFR", REPORT_LIST, same,
                                                    "legitimately_identical")])
        report = self.report(packs=packs, release=release)
        french = report_product(report, "frFR")
        self.assert_reconciled(french, sorted(CATALOG_CURRENT_ENGLISH))
        self.assertEqual(french["keys"]["translated_and_reviewed"], [REPORT_SAVE])
        self.assertEqual(french["keys"]["reviewed_legitimately_identical"], [REPORT_LIST])
        self.assertEqual(french["keys"]["draft_unreviewed"], ["reason.saved_data_reading"])
        self.assertEqual(french["keys"]["missing"], sorted(MISSING_AT_BASE))
        self.assertEqual(french["declarationsApplied"], 2)
        for row in report["products"]:
            if row["productId"] != "frFR":
                self.assertEqual(row["keys"]["draft_unreviewed"], sorted(STATIC_AT_BASE))
        evidence = report["evidence"]
        self.assertEqual((evidence["declarationCount"], evidence["qualifiedDeclarations"]), (2, 2))
        self.assertIn(REPORT_NOT_EVIDENCE, evidence["notEvidenceOf"])
        self.assertEqual(report["reviewGates"][1], {"productId": "frFR",
                                                    "gates": REPORT_PENDING_GATES})
        self.assertEqual(len(report_reasons(report, "review-gate-not-established",
                                            "frFR.fluentHumanAcceptance")), 1)
        self.assertEqual(report["completeness"]["state"], "INCOMPLETE")
        self.assertEqual(self.release["entryReview"]["declarations"], [])

    def test_invalid_declarations_are_rejected(self):
        fr_save = CATALOG_CURRENT_PACKS["frFR"]["entries"][REPORT_SAVE]
        de_save = CATALOG_CURRENT_PACKS["deDE"]["entries"][REPORT_SAVE]
        good = lambda **changes: dict(report_declaration("frFR", REPORT_SAVE, fr_save), **changes)
        cases = (
            ("hash of other text", [good(translatedTextSha256=report_sha("other text"))],
             "evidence-stale"),
            ("hash of the German entry", [good(translatedTextSha256=report_sha(de_save))],
             "evidence-stale"),
            ("hash of the English text", [good(translatedTextSha256=report_sha(
                CATALOG_CURRENT_ENGLISH[REPORT_SAVE]))], "evidence-stale"),
            ("French text declared for German", [good(productId="deDE")], "evidence-stale"),
            ("hash bound to another key", [good(key=REPORT_LIST)], "evidence-stale"),
            ("upper-case hash", [good(translatedTextSha256=report_sha(fr_save).upper())],
             "evidence-hash-format"),
            ("short hash", [good(translatedTextSha256=report_sha(fr_save)[:63])],
             "evidence-hash-format"),
            ("hash null", [good(translatedTextSha256=None)], "evidence-type"),
            ("unknown product", [good(productId="itIT")], "evidence-unknown-product"),
            ("English baseline product", [good(productId="enUS")], "evidence-unknown-product"),
            ("unknown key", [good(key="reason.not_in_english")], "evidence-unknown-key"),
            ("declaration for a missing entry", [report_declaration(
                "frFR", "reason.wait_three_choices", "Synthetic fixture wait text")],
             "evidence-no-entry"),
            ("duplicate declaration", [good(), good()], "evidence-duplicate"),
            ("conflicting reviewer", [good(), good(reviewer=REPORT_OTHER_REVIEWER)],
             "evidence-conflict"),
            ("conflicting reference",
             [good(), good(evidenceReference=REPORT_FIXTURE_REFERENCE + "/second")],
             "evidence-conflict"),
            ("identical decision on differing text", [good(decision="legitimately_identical")],
             "evidence-decision-mismatch"),
            ("unknown decision", [good(decision="approved")], "evidence-decision"),
            ("decision boolean", [good(decision=True)], "evidence-type"),
            ("reviewed boolean field added", [dict(good(), reviewed=True)], "evidence-field"),
            ("boolean shortcut only", [{"productId": "frFR", "key": REPORT_SAVE, "reviewed": True}],
             "evidence-field"),
            ("generic accepted status", [good(status="accepted")], "evidence-status"),
            ("generic pending status", [good(status="pending")], "evidence-status"),
            ("status boolean", [good(status=True)], "evidence-type"),
            ("missing reviewer", [report_without(good(), "reviewer")], "evidence-field"),
            ("unassigned reviewer", [good(reviewer="UNASSIGNED")], "evidence-reviewer"),
            ("pending reviewer", [good(reviewer="pending")], "evidence-reviewer"),
            ("empty reviewer", [good(reviewer="")], "evidence-reviewer"),
            ("blank reviewer", [good(reviewer="   ")], "evidence-reviewer"),
            ("reviewer null", [good(reviewer=None)], "evidence-type"),
            ("missing reference", [report_without(good(), "evidenceReference")], "evidence-field"),
            ("http reference", [good(evidenceReference="http://example.invalid/review")],
             "evidence-reference"),
            ("file reference", [good(evidenceReference="file:///C:/review.txt")],
             "evidence-reference"),
            ("chat reference", [good(evidenceReference="reviewed in chat")], "evidence-reference"),
            ("reference with a space", [good(evidenceReference="https://example.invalid/a b")],
             "evidence-reference"),
            ("empty reference", [good(evidenceReference="")], "evidence-reference"),
            ("declaration not an object", ["frFR " + REPORT_SAVE], "evidence-structure"),
        )
        for label, records, code in cases:
            with self.subTest(label):
                self.assert_evidence(code, release=self.declared(records))
        packs = copy.deepcopy(CATALOG_CURRENT_PACKS)
        same = CATALOG_CURRENT_ENGLISH[REPORT_LIST]
        packs["frFR"]["entries"][REPORT_LIST] = same
        self.assert_evidence("evidence-decision-mismatch", packs=packs, release=self.declared(
            [report_declaration("frFR", REPORT_LIST, same)]))
        packs = copy.deepcopy(CATALOG_CURRENT_PACKS)
        packs["frFR"]["entries"][REPORT_SAVE] = "Texte de fixture modifie apres la declaration"
        self.assert_evidence("evidence-stale", packs=packs, release=self.declared([good()]))
        contract_cases = (
            ("no contract", lambda r: r.pop("entryReview")),
            ("contract not an object", lambda r: r.update({"entryReview": []})),
            ("other contract name",
             lambda r: r["entryReview"].update({"contract": "nexus.l10n.other"})),
            ("boolean contract version",
             lambda r: r["entryReview"].update({"contractVersion": True})),
            ("contract version 2", lambda r: r["entryReview"].update({"contractVersion": 2})),
            ("declarations object", lambda r: r["entryReview"].update({"declarations": {}})),
            ("declarations missing", lambda r: r["entryReview"].pop("declarations")),
        )
        for label, change in contract_cases:
            with self.subTest(label):
                release = copy.deepcopy(self.release)
                change(release)
                self.assert_evidence("evidence-contract", release=release)

    def test_product_review_states_and_booleans_grant_no_entry_review(self):
        release = copy.deepcopy(self.release)
        product = schema_product(release, "frFR")
        product["review"]["technicalAuthorReview"] = {
            "status": "accepted",
            "records": [{"reviewer": REPORT_FIXTURE_REVIEWER, "reviewed": True}]}
        product["review"]["fluentHumanAcceptance"] = {
            "responsibility": REPORT_FIXTURE_REVIEWER, "status": "accepted", "records": []}
        product["wordingState"] = "reviewed"
        release["reviewed"] = True
        report = self.report(release=release)
        french = report_product(report, "frFR")
        self.assertEqual(french["keys"]["draft_unreviewed"], sorted(STATIC_AT_BASE))
        self.assertEqual(french["keys"]["translated_and_reviewed"], [])
        self.assertEqual(french["keys"]["reviewed_legitimately_identical"], [])
        technical = report_reasons(report, "review-gate-not-established",
                                   "frFR.technicalAuthorReview")
        self.assertEqual(len(technical), 1)
        self.assertIn("status=accepted", technical[0]["value"])
        self.assertEqual(len(report_reasons(report, "review-gate-not-established",
                                            "frFR.fluentHumanAcceptance")), 1)
        self.assertEqual(report_reasons(report, "entries-draft-unreviewed", "frFR")[0]["keys"],
                         sorted(STATIC_AT_BASE))
        self.assertEqual(report["completeness"]["state"], "INCOMPLETE")

    def test_invalid_family_surface_and_gate_metadata_is_rejected(self):
        context_cases = (
            ("unknown adopted key", lambda c: c["windowFamilies"][1]["adoptedKeys"].append(
                "reason.not_in_english"), "family-unknown-key"),
            ("adopted key repeated in a family",
             lambda c: c["windowFamilies"][0]["adoptedKeys"].append(SCHEMA_CHARGE),
             "family-duplicate-key"),
            ("issue as boolean", lambda c: c["windowFamilies"][2].update({"issue": True}),
             "family-structure"),
            ("issue as text", lambda c: c["windowFamilies"][2].update({"issue": "145"}),
             "family-structure"),
            ("family name missing", lambda c: c["windowFamilies"][3].pop("name"),
             "family-structure"),
            ("blank family name", lambda c: c["windowFamilies"][3].update({"name": "  "}),
             "family-structure"),
            ("semantic status missing", lambda c: c["windowFamilies"][5].pop("semanticStatus"),
             "family-structure"),
            ("coverage status boolean",
             lambda c: c["windowFamilies"][6].update({"coverageStatus": False}),
             "family-structure"),
            ("paths as text", lambda c: c["windowFamilies"][7].update({"paths": "ui/Help.lua"}),
             "family-structure"),
            ("repeated family", lambda c: c["windowFamilies"].append(
                copy.deepcopy(c["windowFamilies"][4])), "family-duplicate"),
            ("unknown current adoption key", lambda c: c["currentAdoption"]["keys"].append(
                "reason.not_in_english"), "adoption-key"),
            ("repeated current adoption key",
             lambda c: c["currentAdoption"]["keys"].append(SCHEMA_CHARGE), "adoption-key"),
            ("semantic coverage boolean", lambda c: c["currentAdoption"].update(
                {"allWindowSemanticCoverage": True}), "metadata-structure"),
            ("denominator as a number", lambda c: c.update({"visibleTextDenominator": 6}),
             "metadata-structure"),
            ("other copy without status", lambda c: c["otherVisibleCopy"][0].pop("status"),
             "metadata-structure"),
        )
        for label, change, code in context_cases:
            with self.subTest(label):
                context = copy.deepcopy(self.context)
                change(context)
                self.assert_evidence(code, context=context)
        release_cases = (
            ("pseudo data listed as shipped", lambda r: r["pseudoAndTestData"].update(
                {"shippedProductIds": ["xxPS"]}), "evidence-pseudo-product"),
            ("pseudo list missing", lambda r: r["pseudoAndTestData"].pop("shippedProductIds"),
             "metadata-structure"),
            ("font face boolean", lambda r: r["clientEvidence"].update({"fontFace": False}),
             "metadata-structure"),
            ("terminology status missing", lambda r: r["terminology"].pop("status"),
             "metadata-structure"),
            ("native gate not an object", lambda r: schema_product(r, "ruRU")["review"].update(
                {"nativeAcceptance": "NOT_RUN"}), "evidence-gate-structure"),
            ("gate records not a list", lambda r: schema_product(r, "enUS")["review"][
                "technicalAuthorReview"].update({"records": {}}), "evidence-gate-structure"),
            ("responsibility missing", lambda r: schema_product(r, "plPL")["review"][
                "fluentHumanAcceptance"].pop("responsibility"), "evidence-gate-structure"),
        )
        for label, change, code in release_cases:
            with self.subTest(label):
                release = copy.deepcopy(self.release)
                change(release)
                self.assert_evidence(code, release=release)
        context = copy.deepcopy(self.context)
        context["windowFamilies"][0]["adoptedKeys"] = SCHEMA_CHARGE
        with self.assertRaises(self.catalog.CatalogValidationError) as caught:
            self.report(context=context)
        self.assertEqual(caught.exception.code, "context-structure")

    def test_invalid_catalog_inputs_raise_existing_errors_and_get_no_report(self):
        twice = b'frFR = { name = "F", entries = {} }'
        syntax = (({"english": b""}, "bad-bootstrap"),
                  ({"packs": CATALOG_HEADS["packs"] + b"{ " + twice + b", " + twice + b" }"},
                   "duplicate-pack"))
        for parts, code in syntax:
            with self.subTest(code):
                with self.assertRaises(self.catalog.CatalogSyntaxError) as caught:
                    self.report(**parts)
                self.assertEqual(caught.exception.code, code)
        cases = (
            ("orphan entry", lambda e, p, c, r: p["frFR"]["entries"].update(
                {"reason.not_in_english": "Orphan"}), "orphan-entry"),
            ("pseudo pack", lambda e, p, c, r: p.update(
                {"xxPS": {"name": "Pseudo", "entries": {}}}), "pack-unknown"),
            ("previous validator status",
             lambda e, p, c, r: r["validator"].update({"status": SCHEMA_OLD_STATUS}),
             "release-validator"),
            ("context English drift", lambda e, p, c, r: schema_row(c, REPORT_LIST).update(
                {"english": "Drifted"}), "context-english-mismatch"),
            ("entry with pipe", lambda e, p, c, r: p["deDE"]["entries"].update(
                {REPORT_LIST: "a|b"}), "invalid-text"),
        )
        for label, change, code in cases:
            with self.subTest(label):
                english, packs, context, release = self.fixture()
                change(english, packs, context, release)
                with self.assertRaises(self.catalog.CatalogValidationError) as caught:
                    self.report(english=english, packs=packs, context=context, release=release)
                self.assertEqual(caught.exception.code, code)
                self.assertNotIsInstance(caught.exception, self.catalog.CatalogEvidenceError)
        for value in (self.raw["english"].decode("utf-8"), ROOT / "data/LocalizationEnglish.lua",
                      None):
            with self.subTest(value=type(value).__name__):
                with self.assertRaises(TypeError):
                    self.catalog.catalog_report(value, self.raw["packs"], self.raw["context"],
                                                self.raw["release"])

    def test_report_is_deterministic_and_binds_the_exact_input_bytes(self):
        arguments = self.inputs()
        first = self.catalog.catalog_report(*arguments)
        second = self.catalog.catalog_report(*[bytearray(item) for item in arguments])
        self.assertEqual(first, second)
        dumps = {json.dumps(self.catalog.catalog_report(*arguments), sort_keys=True)
                 for _ in range(3)}
        dumps.add(json.dumps(second, sort_keys=True))
        self.assertEqual(len(dumps), 1)
        text = dumps.pop()
        self.assertTrue(text.isascii())
        self.assertEqual(json.loads(text), first)
        self.assertEqual([row["name"] for row in first["inputs"]],
                         ["english", "packs", "keyContext", "release"])
        self.assertEqual([row["source"] for row in first["inputs"]],
                         ["data/LocalizationEnglish.lua", "data/LocalizationPacks.lua",
                          "docs/localization/KEY_CONTEXT.json",
                          "docs/localization/RELEASE_LANGUAGES.json"])
        for row, data in zip(first["inputs"], arguments):
            self.assertEqual(row["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(row["byteLength"], len(data))
        changed = list(arguments)
        changed[2] = arguments[2] + b"\n"
        third = self.catalog.catalog_report(*changed)
        self.assertEqual(third["inputs"][2]["sha256"], hashlib.sha256(changed[2]).hexdigest())
        self.assertNotEqual(third["inputs"][2]["sha256"], first["inputs"][2]["sha256"])
        self.assertEqual(third["inputs"][:2] + third["inputs"][3:],
                         first["inputs"][:2] + first["inputs"][3:])
        self.assertEqual({k: v for k, v in third.items() if k != "inputs"},
                         {k: v for k, v in first.items() if k != "inputs"})
        for path, value in walk(first):
            self.assertNotIsInstance(value, (bool, float), path)
        lowered = text.lower()
        for claim in ("release_ready", "releaseready", "release-ready", "percent", "100%"):
            self.assertNotIn(claim, lowered)
        self.assertNotIn("complete", first)
        self.assertEqual({family["state"] for family in first["families"]}, {"INCOMPLETE"})
        self.assertEqual(first["completeness"]["state"], "INCOMPLETE")


if __name__ == "__main__":
    unittest.main()
