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
                                          "status": "PARSER_ONLY_FULL_VALIDATION_PENDING"})
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
    "status": "PARSER_ONLY_FULL_VALIDATION_PENDING",
    "fullValidation": "NOT_IMPLEMENTED",
    "message": "parser only; full catalog validation is not implemented",
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


if __name__ == "__main__":
    unittest.main()
