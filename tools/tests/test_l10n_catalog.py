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
                                          "status": "SCHEMA_API_ONLY_REPORT_CLI_PENDING"})
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
    "status": "SCHEMA_API_ONLY_REPORT_CLI_PENDING",
    "fullValidation": "NOT_IMPLEMENTED",
    "message": "syntax and schema API only; coverage validation and report CLI are pending",
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

SCHEMA_STATUS = "SCHEMA_API_ONLY_REPORT_CLI_PENDING"
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


if __name__ == "__main__":
    unittest.main()
