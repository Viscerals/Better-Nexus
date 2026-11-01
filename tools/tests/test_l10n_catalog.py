"""Metadata-contract tests for the declarative Nexus localization documents.

Refs #139, #147. Checks docs/localization/RELEASE_LANGUAGES.json,
docs/localization/KEY_CONTEXT.json and docs/localization/FULL_COVERAGE.md
against independent literal requirements and plain substrings of the current
source. Python 3.9+, standard library only. Files are read as strict UTF-8
bytes. No Lua is executed, imported or evaluated, and no live or private data
is read.

Later sections append public tests of tools/l10n_catalog.py: the parser, the
pure schema API validate_catalog_data and the pure coverage report API
catalog_report on exact in-memory bytes, then subprocess tests of its
read-only confined-root report command line (B3b) on this repository and on
temporary public-only roots. The tool is an implemented draft. This file is
registered in PYTHON_TESTS of tools/run_prototype_tests.py, and
tools/ci_check.py runs it as its own process. Still pending are independent
review, and the human, native and UI gates. Author execution: NOT_RUN; host
results are recorded separately.

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


# The one structural true value: the code-owned `lines = true` schema flag of
# a template key row of KEY_CONTEXT.json (core/Localization.lua "Full-UI
# kinds"). It is a text contract, not acceptance; anywhere else, including a
# text, block or format row, true still fails.
_SCHEMA_LINES = re.compile(r"^\$\.keys\[(\d+)\]\.lines$")


def schema_lines_flag(document, path):
    found = _SCHEMA_LINES.match(path)
    if not found or not isinstance(document, dict) or not isinstance(document.get("keys"), list):
        return False
    rows = document["keys"]
    index = int(found.group(1))
    return index < len(rows) and isinstance(rows[index], dict) and rows[index].get("kind") == "template"


def assert_no_true(test, document):
    for path, value in walk(document):
        if value is True and schema_lines_flag(document, path):
            continue
        test.assertIsNot(value, True, path + " is true; no boolean may imply acceptance")


# Historical fixture and actual current-source expectations (Refs #139, #143,
# #147, #148). EXPECTED_KEYS above and CATALOG_CURRENT_ENGLISH and
# CATALOG_CURRENT_PACKS below keep their old names for compatibility only.
# They are historical, synthetic fixture expectations of the six-key base
# pin: six independently literal English meanings, including the typed
# charge template, and 18 inherited draft pack entries (three per pack) with
# the six autonyms. They are not facts of the current 28-key catalog. The
# helpers below build a coherent six-key historical fixture from those
# literals and the unchanged six key-context rows, for the existing negative
# and partial-data controls. The actual current source is checked separately
# against the independent literals that follow. The helpers are functions,
# called only while a test runs, after this module has defined every name
# they use. No Lua, Git or network is used.

# The 21 static ui/Panel.lua meanings bound at the historical technical
# reference below and still current, from the scoped key and meaning
# requirements: (key, kind, exact English, producer code).
CURRENT_PANEL_KEYS = [
    ("panel.button.my_builds", "text", "My Builds", None),
    ("panel.tooltip.open_my_builds", "text", "Open My Builds", None),
    ("panel.tooltip.my_builds_destination", "text",
     "Open the server My Builds page. Choosing a different Saved Build there changes "
     "the active loadout.", None),
    ("panel.button.assign_wishlist", "text", "Assign Wishlist", None),
    ("panel.tooltip.assignment_heading", "text", "Assign Wishlist", None),
    ("panel.tooltip.assignment_chooser", "text",
     "Opens the Echo Journal with its Wishlist chooser for this loadout. Nothing is "
     "assigned until you choose a Wishlist there.", None),
    ("panel.button.create_wishlist", "text", "Create Wishlist", None),
    ("panel.tooltip.create_wishlist_heading", "text", "Import or create a wishlist", None),
    ("panel.tooltip.create_wishlist_source", "text",
     "Paste a wishlist string or build one directly in Nexus.", None),
    ("panel.tooltip.create_wishlist_draft", "text",
     "This opens the Wishlist editor with a draft. Nothing is saved or assigned until "
     "you press Create & assign or Create unassigned there.", None),
    ("panel.heading.locked_targets", "text", "LOCKED TARGETS", None),
    ("panel.tooltip.locked_remaining", "text", "Locked targets remaining", None),
    ("panel.tooltip.locked_plan", "text",
     "These targets are planned for your locked Echo slots (a plan designs at most six "
     "target copies).", None),
    ("panel.tooltip.locked_acquire", "text",
     "Acquire the exact requested Echo and quality first.", None),
    ("panel.tooltip.locked_placement", "text",
     "Owned copies still need to be placed in locked Echo slots.", None),
    ("panel.tooltip.locked_not_freeze", "text",
     "Current locked Echo slots and card Freeze are separate.", None),
    ("panel.tooltip.locked_acquire_list", "text", "Still need to acquire:", None),
    ("panel.tooltip.open_wishlist_editor", "text", "Click to open Wishlist Editor", None),
    ("panel.heading.progress", "text", "PROGRESS", None),
    ("panel.heading.still_needed", "text", "STILL NEEDED", None),
    ("panel.heading.extra_copies", "text", "EXTRA COPIES", None),
]
# Issue #165: the HUD Options button label, an independent literal. The
# "! " trusted-notice mark is added by ui/Panel.lua and is never part of
# this text. The dated packs held no entry for it; each complete current
# pack does (CURRENT_PACK_VALUE_MAPS).
CURRENT_OPTIONS_KEYS = [("panel.button.options", "text", "Options", None)]
# The 27 keys observed at the historical technical reference: the six
# historical rows, then the 21 panel rows. Its observed counts stay 27.
HISTORICAL_TECHNICAL_KEYS = EXPECTED_KEYS + CURRENT_PANEL_KEYS
# The current-source oracle: those 27 rows, then the Options row.
CURRENT_KEYS = HISTORICAL_TECHNICAL_KEYS + CURRENT_OPTIONS_KEYS
# The 27 keys of the dated pack cohort (the historical technical
# observation) and the dated English-only key. Each complete current pack
# holds every English key, these 27 among them; CATALOG_CURRENT_PACKS stays
# the synthetic historical fixture, not the shipped values.
CURRENT_PACK_KEYS = [row[0] for row in HISTORICAL_TECHNICAL_KEYS]
CURRENT_ENGLISH_ONLY_KEYS = [row[0] for row in CURRENT_OPTIONS_KEYS]
HISTORICAL_HUD_ADOPTED_KEYS = ["readout.charge_counts"]
CURRENT_HUD_ADOPTED_KEYS = (HISTORICAL_HUD_ADOPTED_KEYS + [row[0] for row in CURRENT_PANEL_KEYS]
                            + CURRENT_ENGLISH_ONLY_KEYS)

# KEY_CONTEXT.json keeps its immutable historical55d7350 technical observation.
# The last committed data reference is ac2cdf5: English and decoded pack
# values are unchanged from 55d7350; leading pack comments changed the
# canonical pack bytes. The current packs file is still that ac2cdf5 blob.
# The current English file is not: issue #165 added panel.button.options,
# first committed in a50372ba485fd98043d68ec7d4f732ee947b0c28 as Git blob
# CURRENT_ENGLISH_GIT_BLOB below, unchanged through 8393f5f and the current
# source. Historical and reference (SHA-256, length) tables below refer to
# named Git blobs with LF line ends, never to raw Windows CRLF inputs; only
# CHECKOUT_PHYSICAL_INPUTS holds physical bytes, and says so. The real
# parser/schema/report APIs still receive and hash original physical bytes.
HISTORICAL_TECHNICAL_REFERENCE = {"head": "55d7350c0d5c60fc5bf39385f48027cd62498c71",
                                  "tree": "9a7c51f0683a53adae1aecd833b1f13a590e2595"}
CURRENT_TECHNICAL_REFERENCE = {"head": "ac2cdf5f4924c74f1e744990b2e0bb0405cd1c88",
                               "tree": "458b27a74ba2c65cfb752367c8f8607594a45e79"}
HISTORICAL_REFERENCE_INPUTS = {
    "data/LocalizationEnglish.lua":
        ("2325010efc6c052628d70402542dcb9805e89135b72756442841ece97fccb2fc", 3744),
    "data/LocalizationPacks.lua":
        ("3680a57743479df42854027ad3ad35d0df2407c0e957d993a3a4c3a57159676e", 21041),
}
# The English blob at ac2cdf5 (the same as at 55d7350), superseded by the
# issue #165 English blob; the current English bytes must no longer be this blob.
REFERENCE_ENGLISH_INPUT = ("2325010efc6c052628d70402542dcb9805e89135b72756442841ece97fccb2fc",
                           3744)
# Canonical Git (LF) identities of the current data files.
CURRENT_REFERENCE_INPUTS = {
    "data/LocalizationEnglish.lua":
        ("69d3998950b651f5b666f7b6a65a718c97bfb3719bfb4523d5c60037ed7f20a5", 3916),
    "data/LocalizationPacks.lua":
        ("5c8d10bb711474a0374a0ad851e4f3608ede2389fb58fd01b34ad3c4cda3de95", 21168),
}
# The Git blob that holds those canonical English bytes and the commit that
# first holds it.
CURRENT_ENGLISH_GIT_BLOB = {"blob": "024557e8ffb9d6f587080e46b47b33daea25e492",
                            "firstCommit": "a50372ba485fd98043d68ec7d4f732ee947b0c28"}
# Checkout identity, not a Git blob: the physical (CRLF) bytes that a Git
# checkout writes for CURRENT_ENGLISH_GIT_BLOB, since .gitattributes sets
# eol=crlf for *.lua. Compared only with physical bytes.
CHECKOUT_PHYSICAL_INPUTS = {
    "data/LocalizationEnglish.lua":
        ("755f2f5d434a23bbff28ad01f23711e14601e1a4c8df5ee99269038ee13b5cf8", 3970),
}
# Full visible-UI scope (#143-#148): a file named here was intentionally
# changed after its dated reference above. The dated (SHA-256, length) and
# blob identities stay recorded as history, never refreshed; the current
# bytes must differ from them and keep the dated 28 meanings (checked by the
# tests that read the file). No new hash is attested for the successor.
REFERENCE_SUCCESSORS = {
    "data/LocalizationEnglish.lua": "#143-#148 full visible-UI catalog: the 28 dated meanings first, "
                                    "then the generated NEXUS-L10N-FULL-UI section",
    "data/LocalizationPacks.lua": "#143-#148 six complete draft packs: one entry for every English key "
                                  "of the full visible-UI catalog",
}
# Full visible-UI scope: unlike the English successor, the composed packs and
# the release metadata carry a strong current identity. Packs: the eight
# Saved Build label translations first committed in 351a83b5; release
# metadata: the 529 original entry-review declarations followed by the six
# neutral-template declarations, first committed in 23d61936. Canonical Git
# (LF) SHA-256 and length and the Git blob are compared with canonical
# bytes. Only *.lua is checked out with a fixed eol=crlf, so only the packs
# also record their physical checkout bytes; RELEASE_LANGUAGES.json is
# text=auto and its physical bytes depend on the platform. A later intended
# change of either file needs its own reviewed identity here. The values are
# literal operator facts computed from those immutable Git pins, never from
# the bytes under test.
CURRENT_SUCCESSOR_INPUTS = {
    "data/LocalizationPacks.lua": {
        "canonical": ("066675a24c7250d0621071b0334f5387295b9a70394bd7db05eb2c17f482d50d", 3316523),
        "blob": "dca4ec0fd59b39508be3f71eec17ef4e1e3899ec",
        "firstCommit": "146a062e2ad71f2f0642ee0a04d2ffb2c872abae",
        "physical": ("15e0ee5316f7e5059c1245e808509bc12b59fcdc490558a87a002fa150acd2ba", 3341060)},
    "docs/localization/RELEASE_LANGUAGES.json": {
        "canonical": ("78628e4fd0cd70030ba40e5b62424492f27497590f0813e86c92fbf3bec2986c", 265898),
        "blob": "00fdd4fc3947b4dfaef84c2e4ab43d67502d651b",
        "firstCommit": "23d619366a02fe59e43e47e7842a1423189190fb"},
}
# The superseded strong identities of the same two files, kept as history and
# never refreshed: the truthful-header packs first committed in 31272db6 and
# the 529-declaration release metadata first committed in dd6d35af, with the
# per-language value maps bound to those packs by the accepted six-language
# input selection. The current bytes must differ from them
# (assert_current_successor_identity); the maps are recorded, not compared.
HISTORICAL_SUCCESSOR_INPUTS = {
    "data/LocalizationPacks.lua": {
        "canonical": ("aef3635a65032ecdd693765a8fcd2ba2feb1aee0fa90206ea798696837f2909a", 3314202),
        "blob": "5104fd091157e6c4f78ce78d611d97971e8e76df",
        "firstCommit": "31272db6f8753a18def930ee771da0ac62e666d2",
        "physical": ("4978bfb03e6374d46f1ecb64d1d1086657e46d37527a77f6799a810b39de8c52", 3338739),
        "valueMaps": {
            "frFR": "4ac02d6ef0ad673b4f86fdf51894a041441f345a209942f3c286025b3f0d7bdc",
            "deDE": "55b62590cc1115a81be3f986e5e1586fd53db610f6d61fbf2be5564a42c68676",
            "esES": "ca2fe45bef40eeac6c1f787452f120024c04b20fca0a47d4f250bab0c7ce6529",
            "plPL": "a8bb86be8022e4519cf0521f1c592fe1782e38e0403a02d9d54145931438fdef",
            "ptBR": "0b4dadcad493c2c1e06ee1a2ff6c22448e4f0371a6fd9158d88736bfb2e56baa",
            "ruRU": "eb93be7df74a1c3b5429d6eacfe9ab379a65c140918574be32645a85ccaad4c0"}},
    "docs/localization/RELEASE_LANGUAGES.json": {
        "canonical": ("b0354a8b48c0ff49c301d06d1990c731ef0af3848d618928573b2447f7276eaf", 263240),
        "blob": "63143c5577bdbc2842b36ecb8dba490b28547e8b",
        "firstCommit": "dd6d35af6769751d7214c36d251e4e775baf3578"},
}
# The decoded entries of each current pack: SHA-256 of canonical JSON
# (ensure_ascii false, sorted keys, separators "," and ":") of the key-to-text
# map, as bound per language by the packs pinned at 351a83b5 (literal
# operator facts; esES is unchanged by that commit).
CURRENT_PACK_VALUE_MAPS = {
    "frFR": "ee933bd768676325479ddeb4771db27514c7286a33454c622fa56c0d9a920e1b",
    "deDE": "e1124f68173d6fa89c4564740c9b16b504d26f3ce6f35a4d4984904d19a73aa0",
    "esES": "b361ef47eb8935dcc4a42302285991b1a48f521979a00b9b9645d0c48c40312d",
    "plPL": "9d0e86860c6d11aca2cc73cf83273f77027bf61bfdf5162697b8c32866d4b5f7",
    "ptBR": "16863685d7fc560e74f15413905dd95dd878da83799c8f4871d354896805d915",
    "ruRU": "3f655bc3fa4a728fa43e1e750467c7b741275bc4df8d746db4f8470ff3f75e67",
}
# The actual entry-review declarations: two distinct evidence cohorts, in
# this order, all technical metadata, not fluent human, native, rights or
# whole-pack acceptance. The digest and counts cover the whole list.
CURRENT_DECLARATIONS_SHA256 = "a1bb0991b5c737c8a348277dea8168e33afa5001874727b32946548cbb90374a"
CURRENT_DECLARED_COUNTS = {"frFR": 106, "deDE": 108, "esES": 90, "plPL": 89, "ptBR": 92, "ruRU": 50}
# Cohort 1, first and unchanged: 529 automated, source-paired
# legitimately_identical records bound to one persisted public review.
ORIGINAL_DECLARATION_COUNT = 529
ORIGINAL_DECLARATIONS_SHA256 = "423115440fc785ce68aaa8f9d2e7b1c96042d6de57b77b84fba93f7a45503bd3"
CURRENT_DECLARATION_REVIEWER = "Codex /root/composition_identical_record_assessment (automated)"
CURRENT_DECLARATION_REFERENCE = "https://github.com/Viscerals/Better-Nexus/issues/148#issuecomment-6532515152"
# Cohort 2, appended: the six neutral {reason}. wrapper templates, declared
# legitimately_identical by an independent automated structural review (not
# a human language review) whose retrieved evidence is a private,
# access-restricted page, not a public reference. It covers these six
# entries only.
NEUTRAL_TEMPLATE_KEY = "orb.assignment.identity_found_reason"
NEUTRAL_TEMPLATE_TEXT = "{reason}."
NEUTRAL_TEMPLATE_REVIEWER = "Codex (independent automated structural review)"
NEUTRAL_TEMPLATE_REFERENCE = "https://chatgpt.com/space/page_f0b6446364f08191b862a37611e463ab"
NEUTRAL_TEMPLATE_DECLARATIONS = [
    {"productId": pack_id, "key": NEUTRAL_TEMPLATE_KEY,
     "translatedTextSha256": "04c74dc81035b63d65156f6027cfb8a4caecb8065b6690dc0587bf7af5eab4bf",
     "reviewer": NEUTRAL_TEMPLATE_REVIEWER, "decision": "legitimately_identical",
     "evidenceReference": NEUTRAL_TEMPLATE_REFERENCE, "status": "declared"}
    for pack_id in ("frFR", "deDE", "esES", "plPL", "ptBR", "ruRU")
]
# English-identical entries without a declaration: none. The eight Saved
# Build labels now differ from their English, and the six neutral wrappers
# are declared above; each pack's list stays present and empty.
CURRENT_ENGLISH_PLACEHOLDER_KEYS = {pack_id: [] for pack_id in
                                    ("frFR", "deDE", "esES", "plPL", "ptBR", "ruRU")}
CURRENT_OBSERVATION_GATES = {"finalComposition": "PENDING", "finalButtonFit": "PENDING",
                             "m7Span": "PENDING", "fullUiCoverage": "PENDING",
                             "fluentHumanAcceptance": "UNASSIGNED",
                             "nativeAcceptance": "NOT_RUN"}


# Full visible-UI scope (#143-#148): the reviewed catalog holds 4078 English
# meanings (the runtime cap is 4096). The dated 28 above stay first and
# unchanged; the generated rows that follow them are read from
# KEY_CONTEXT.json with the json module, apart from the tool under test, so
# the English file and the context rows are compared, not the tool with
# itself. Each complete current pack holds an entry for every one of them.
CURRENT_FULL_UI_KEYS = 4078


def current_english_oracle():
    """The dated 28-meaning English table from the independent literals, in
    source order: the six historical meanings, the 21 panel meanings, then
    the Options label. The current source holds them first and unchanged."""
    table = {key: english for key, _, english, _ in CURRENT_KEYS}
    if (len(table) != len(CURRENT_KEYS) or len(CURRENT_PANEL_KEYS) != 21
            or len(CURRENT_OPTIONS_KEYS) != 1):
        raise AssertionError("the current key oracle repeats or lacks a key")
    if {key: table[key] for key in CATALOG_CURRENT_ENGLISH} != CATALOG_CURRENT_ENGLISH:
        raise AssertionError("the two historical English literal tables disagree")
    return table


def full_english_oracle():
    """The whole current English table, in source order: the dated 28 of
    current_english_oracle(), then each generated full visible-UI meaning of
    the KEY_CONTEXT.json rows."""
    table = current_english_oracle()
    rows = load_document("KEY_CONTEXT.json")["keys"]
    if [(row["key"], row["english"]) for row in rows[:len(table)]] != list(table.items()):
        raise AssertionError("the dated 28 meanings are not the first, unchanged context rows")
    for row in rows[len(CURRENT_KEYS):]:
        if row["key"] in table:
            raise AssertionError("a generated row repeats a key: " + row["key"])
        table[row["key"]] = row["english"]
    if len(table) != CURRENT_FULL_UI_KEYS:
        raise AssertionError("the current catalog holds %d meanings" % len(table))
    return table


def pack_value_map_sha256(entries):
    """SHA-256 of the canonical JSON of one decoded key-to-text map (the
    CURRENT_PACK_VALUE_MAPS contract)."""
    return hashlib.sha256(json.dumps(entries, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def current_declaration_keys(release, pack_id):
    """The sorted keys of pack_id's actual entry-review declarations."""
    return sorted(row["key"] for row in release["entryReview"]["declarations"]
                  if row["productId"] == pack_id)


def current_categories(release, pack_id, keys):
    """(draft_unreviewed, reviewed_legitimately_identical,
    deliberate_english_placeholder) keys of one complete current pack, from
    keys (the caller's independent English oracle keys), the actual
    declarations and the literal placeholder list: every key is present,
    none missing."""
    declared = current_declaration_keys(release, pack_id)
    placeholder = CURRENT_ENGLISH_PLACEHOLDER_KEYS[pack_id]
    draft = sorted(set(keys) - set(declared) - set(placeholder))
    return draft, declared, placeholder


def historical_release():
    """The actual release metadata with its entry-review declarations removed.
    The historical six-key fixture predates every declaration; the actual
    declarations bind to the complete shipped packs and would contradict the
    tiny fixture. Every other release field stays the actual one."""
    release = load_document("RELEASE_LANGUAGES.json")
    release["entryReview"]["declarations"] = []
    return release


def canonical_git_lf(data):
    """data with each CRLF pair as LF, as Git stores these text blobs. Only
    the reference-hash check uses it; a lone CR is refused. Parser, schema and
    report APIs always receive the unmodified physical bytes."""
    canonical = bytes(data).replace(b"\r\n", b"\n")
    if b"\r" in canonical:
        raise AssertionError("a lone CR is not comparable with the canonical Git bytes")
    return canonical


def assert_current_reference_bytes(test, relative, physical):
    """Compare the physical bytes of relative with their current identity and
    return the canonical bytes. The canonical Git LF bytes are compared with
    their current reference hash and length, and must not be the superseded
    reference English blob; a physical CRLF hash is never claimed to equal
    them. A file with a recorded checkout identity is also compared, as
    physical bytes, with that identity."""
    canonical = canonical_git_lf(physical)
    digest = (hashlib.sha256(canonical).hexdigest(), len(canonical))
    test.assertNotEqual(digest, REFERENCE_ENGLISH_INPUT, relative)
    physical_digest = (hashlib.sha256(bytes(physical)).hexdigest(), len(physical))
    if relative in REFERENCE_SUCCESSORS:
        # A declared successor: its dated identities are history, not current.
        test.assertNotEqual(digest, CURRENT_REFERENCE_INPUTS[relative], relative)
        if relative in CHECKOUT_PHYSICAL_INPUTS:
            test.assertNotEqual(physical_digest, CHECKOUT_PHYSICAL_INPUTS[relative], relative)
        assert_current_successor_identity(test, relative, physical)
        return canonical
    test.assertEqual(digest, CURRENT_REFERENCE_INPUTS[relative], relative)
    if relative in CHECKOUT_PHYSICAL_INPUTS:
        test.assertEqual(physical_digest, CHECKOUT_PHYSICAL_INPUTS[relative], relative)
    return canonical


def assert_current_successor_identity(test, relative, physical):
    """Where CURRENT_SUCCESSOR_INPUTS records it, the exact current identity:
    canonical Git (LF) SHA-256, length and blob, and for the packs the
    physical checkout bytes. The physical CRLF identity is never claimed to
    equal the canonical one. Where HISTORICAL_SUCCESSOR_INPUTS records a
    superseded identity of the same file, the current bytes must not be it."""
    current = CURRENT_SUCCESSOR_INPUTS.get(relative)
    if current is None:
        return
    canonical = canonical_git_lf(physical)
    digest = (hashlib.sha256(canonical).hexdigest(), len(canonical))
    blob = hashlib.sha1(b"blob %d\0" % len(canonical) + canonical).hexdigest()
    physical_digest = (hashlib.sha256(bytes(physical)).hexdigest(), len(physical))
    test.assertEqual(digest, current["canonical"], relative)
    test.assertEqual(blob, current["blob"], relative)
    if "physical" in current:
        test.assertEqual(physical_digest, current["physical"], relative)
        test.assertNotEqual(current["physical"], current["canonical"], relative)
    historical = HISTORICAL_SUCCESSOR_INPUTS.get(relative)
    if historical is not None:
        test.assertNotEqual(digest, historical["canonical"], relative)
        test.assertNotEqual(blob, historical["blob"], relative)
        if "physical" in historical:
            test.assertNotEqual(physical_digest, historical["physical"], relative)


# The commit that first holds the Options label adoption and the current
# fact anchor of KEY_CONTEXT.json, at which it is unchanged.
OPTIONS_ADOPTION_COMMITS = (CURRENT_ENGLISH_GIT_BLOB["firstCommit"],
                            "8393f5f4b61a0d62b5043b861539be868ebf80f6")


def assert_current_adoption_scope(test, scope):
    """The currentAdoption scope names the historical technical reference,
    not the ac2cdf5 data reference, both full Options adoption commits, and
    its pending review."""
    test.assertIn(HISTORICAL_TECHNICAL_REFERENCE["head"], scope)
    test.assertNotIn(CURRENT_TECHNICAL_REFERENCE["head"], scope)
    for sha in OPTIONS_ADOPTION_COMMITS:
        test.assertIn(sha, scope)
    test.assertIn("pending", scope)


# Issue #141, #147: the current Automatic preference, beside the historical
# automaticMode record of the base pin. The blobs are those of the source
# commit, unchanged since 8393f5f.
CURRENT_AUTOMATIC_PREFERENCE = {
    "nature": "current_fact",
    "sourceBinding": {"commit": "dadfc29b960689957afaf4ec136abca3ade4e8f2",
                      "tree": "8aea7f4cdc7e44231842dec221e52d0143470cd7"},
    "unchangedSince": "8393f5f4b61a0d62b5043b861539be868ebf80f6",
    "unchangedSourceBlobs": {"core/Localization.lua": "02f8d8d8dc4e6fe367501da4d868153236e1dd22",
                             "data/DefaultProfile.lua": "a51a675022b5c6195253ed51bc33fd77e4a30b3c"},
    "preferenceValue": "automatic",
    "isLanguageId": False,
    "resolvesTo": "enUS",
    "evidencedMappings": [],
    "evidencedAliases": [],
    "aliasEvidence": "none",
    "offlineEvidence": "tests/prototype/terminology.lua (Lua harness)",
    "historicalRecord": "automaticMode describes the 5c77eec base and is unchanged",
    "nativeAcceptance": "NOT_RUN",
}


def assert_current_automatic_preference(test, record):
    """The current Automatic preference is the exact recorded value, resolves
    to English, and names no mapping, alias or alias evidence."""
    test.assertEqual(record.get("evidencedMappings"), [])
    test.assertEqual(record.get("evidencedAliases"), [])
    test.assertEqual(record.get("aliasEvidence"), "none")
    test.assertEqual(record.get("resolvesTo"), "enUS")
    test.assertEqual(record, CURRENT_AUTOMATIC_PREFERENCE)


# Issue #147 (R union): the dated record's blobs describe its source commit.
# A file named here was intentionally changed after that observation, so its
# dated blob is bound to the recorded Git object, not to the working tree.
# Every other file of the record must still hold its dated blob.
DATED_SOURCE_SUCCESSORS = {
    "core/Localization.lua": "#147 R union: the code-owned declaration registry",
}


def git_object_store():
    """'complete' for a full Git checkout of this repository, 'shallow' for
    a shallow clone (CI checks out one commit), or None without Git."""
    try:
        run = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--is-shallow-repository"],
                             capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    answer = run.stdout.decode("ascii", "replace").strip()
    if run.returncode != 0 or answer not in ("true", "false"):
        return None
    return "shallow" if answer == "true" else "complete"


def git_object_id(revision):
    """The object ID of a revision expression such as <commit>:<path>, or
    None when this object store does not hold it."""
    try:
        run = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--verify", "--quiet",
                              revision], capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    value = run.stdout.decode("ascii", "replace").strip()
    return value if run.returncode == 0 and re.fullmatch("[0-9a-f]{40}", value) else None


def cohort_blob(relative, commit):
    """The Git blob that the frozen CURRENT_COHORT_EVIDENCE.json records for
    relative at its source pin, when that pin is commit; else None."""
    evidence = load_document("CURRENT_COHORT_EVIDENCE.json")
    if evidence["sourcePin"]["commit"] != commit:
        return None
    rows = [row for row in evidence["sourceInputs"]["files"] if row["path"] == relative]
    return rows[0]["gitBlob"] if len(rows) == 1 else None


def assert_dated_source_blobs(test, record, store=None, successors=DATED_SOURCE_SUCCESSORS):
    """Each recorded blob is the Git object of its file at the recorded source
    commit, whose tree is the recorded tree. With a complete object store
    that is read from Git, and a missing commit or object fails. A shallow
    clone without the commit falls back to the independent frozen cohort
    evidence for the same file at the unchangedSince pin, which must agree.
    The working tree must still hold the dated blob, except for a declared
    successor file, which must now differ from it. store is the object-store
    state ('complete', 'shallow' or 'none' for no Git); None reads it."""
    store = git_object_store() if store is None else store
    store = None if store == "none" else store
    binding = record["sourceBinding"]
    commit, tree = binding.get("commit"), binding.get("tree")
    test.assertRegex(commit or "", "^[0-9a-f]{40}$")
    test.assertRegex(tree or "", "^[0-9a-f]{40}$")
    present = store is not None and git_object_id(commit + "^{commit}") is not None
    if store == "complete":
        test.assertTrue(present, "the dated source commit is not in this repository")
    if present:
        test.assertEqual(git_object_id(commit + "^{tree}"), tree, "dated source tree")
    for relative, blob in record["unchangedSourceBlobs"].items():
        test.assertRegex(blob, "^[0-9a-f]{40}$", relative)
        if present:
            test.assertEqual(git_object_id("%s:%s" % (commit, relative)), blob, relative)
        else:
            test.assertEqual(cohort_blob(relative, record["unchangedSince"]), blob, relative)
        canonical = canonical_git_lf((ROOT / relative).read_bytes())
        current = hashlib.sha1(b"blob %d\0" % len(canonical) + canonical).hexdigest()
        if relative in successors:
            test.assertNotEqual(current, blob, relative)
        else:
            test.assertEqual(current, blob, relative)


def historical_context():
    """A coherent six-key historical fixture projected from the actual
    KEY_CONTEXT.json: its six original key rows, unchanged; a six-key
    adoption; window families whose adopted keys are the six-key projection
    (charge only on the HUD). The later 27-key technical observation is
    removed, not relabelled. The source pin, baseline observation, separate
    pending addition and every other pending field are kept as they are."""
    context = load_document("KEY_CONTEXT.json")
    six = [row[0] for row in EXPECTED_KEYS]
    rows = {row["key"]: row for row in context["keys"]}
    context["keys"] = [rows[key] for key in six]
    context["currentAdoption"]["scope"] = (
        "synthetic historical six-key test fixture: the English semantic keys adopted "
        "through the Localization seam at the base pin; not current 27-key metadata")
    context["currentAdoption"]["keys"] = list(six)
    for family in context["windowFamilies"]:
        family["adoptedKeys"] = [key for key in family["adoptedKeys"] if key in six]
    context["packCoverage"].pop("currentTechnicalObservation", None)
    return context


def historical_raw(context):
    """Exact bytes of the historical fixture: the six literal English
    meanings and 18 inherited pack entries serialized by schema_english_source
    and schema_packs_source, the projected context, and the actual release
    metadata without its entry-review declarations (historical_release)."""
    return {"english": schema_english_source(CATALOG_CURRENT_ENGLISH),
            "packs": schema_packs_source(CATALOG_CURRENT_PACKS),
            "context": schema_json(context),
            "release": schema_json(historical_release())}


def current_raw():
    """The unmodified physical bytes of the four actual catalog inputs."""
    return {"english": (ROOT / "data/LocalizationEnglish.lua").read_bytes(),
            "packs": (ROOT / "data/LocalizationPacks.lua").read_bytes(),
            "context": (ROOT / "docs/localization/KEY_CONTEXT.json").read_bytes(),
            "release": (ROOT / "docs/localization/RELEASE_LANGUAGES.json").read_bytes()}


def assert_historical_fixture(catalog, raw, context):
    """Positive setup checks of the historical fixture, through the real
    parser and schema API, so that a broken setup fails instead of letting a
    negative control pass: six literal keys, partial packs, the projected
    context and the accepted fixture bytes."""
    def require(condition, what):
        if not condition:
            raise AssertionError("historical six-key fixture setup: " + what)
    six = [row[0] for row in EXPECTED_KEYS]
    english = catalog.parse_english(raw["english"])
    require(list(english.items()) == [(key, text) for key, _, text, _ in EXPECTED_KEYS],
            "English is not the six literal meanings")
    require(english == CATALOG_CURRENT_ENGLISH, "English literal tables disagree")
    packs = catalog.parse_packs(raw["packs"])
    require(packs == CATALOG_CURRENT_PACKS and list(packs) == PACK_IDS, "pack tables")
    autonyms = {row[0]: row[3] for row in EXPECTED_PRODUCTS}
    for pack_id, pack in packs.items():
        require(pack["name"] == autonyms[pack_id], pack_id + " autonym")
        require(sorted(pack["entries"]) == sorted(STATIC_AT_BASE), pack_id + " entries")
        require(set(pack["entries"]) < set(english), pack_id + " is not partial")
    require(sum(len(pack["entries"]) for pack in packs.values())
            == len(PACK_IDS) * len(STATIC_AT_BASE), "18 inherited entries")
    rows = [(r["key"], r["kind"], r["english"], r.get("producerCode")) for r in context["keys"]]
    require(rows == EXPECTED_KEYS, "the six key-context rows")
    require(context["currentAdoption"]["keys"] == six, "six-key adoption")
    families = context["windowFamilies"]
    require([family["name"] for family in families] == [row[0] for row in EXPECTED_FAMILIES],
            "window families")
    require(families[0]["adoptedKeys"] == HISTORICAL_HUD_ADOPTED_KEYS, "charge-only HUD")
    require(all(family["adoptedKeys"] == [] for family in families[1:]), "other adoption")
    coverage = context["packCoverage"]
    require("currentTechnicalObservation" not in coverage, "later observation segregated")
    baseline = coverage["baselineObservation"]
    require((baseline["pin"], baseline["inheritedStaticDraftKeys"], baseline["missingKeys"])
            == (BASE, STATIC_AT_BASE, MISSING_AT_BASE), "baseline observation")
    require(json.loads(raw["release"].decode("utf-8"))["entryReview"]["declarations"] == [],
            "declaration-free release")
    result = catalog.validate_catalog_data(raw["english"], raw["packs"], raw["context"],
                                           raw["release"])
    require((result["english"], result["packs"], result["keyContext"])
            == (CATALOG_CURRENT_ENGLISH, CATALOG_CURRENT_PACKS, context), "schema API result")


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
                                          "status": "IMPLEMENTED_DRAFT_REVIEW_PENDING"})
        self.assertEqual(d["requiredCiRegistration"], "REGISTERED_IN_PYTHON_TESTS")
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

    def test_current_automatic_preference_resolves_to_english_without_aliases(self):
        record = self.doc["currentAutomaticPreference"]
        assert_current_automatic_preference(self, record)
        # The historical base record beside it is unchanged.
        self.assertEqual(self.doc["automaticMode"]["chooserProductId"], "NONE_AT_BASE")
        # The current source still declares and resolves the value as recorded.
        profile = read_text("data/DefaultProfile.lua")
        self.assertIn('automatic = "automatic",', profile)
        localization = read_text("core/Localization.lua")
        self.assertIn('local AUTOMATIC = "automatic"', localization)
        self.assertIn("if id == nil or id == AUTOMATIC then return ResolveAutomatic() end",
                      localization)
        self.assertIn("production Automatic holds no evidence and resolves English",
                      read_text("tests/prototype/terminology.lua"))
        # The dated blobs are bound to their recorded source revision (see
        # assert_dated_source_blobs); data/DefaultProfile.lua is still live.
        assert_dated_source_blobs(self, record)
        # Live R control: the current core/Localization.lua is the declared
        # successor, still resolves Automatic as recorded (fragments above) and
        # carries the full declaration registry, in source order, the dated 28
        # first.
        canonical = canonical_git_lf((ROOT / "core/Localization.lua").read_bytes())
        current = hashlib.sha1(b"blob %d\0" % len(canonical) + canonical).hexdigest()
        self.assertNotEqual(current, record["unchangedSourceBlobs"]["core/Localization.lua"])
        declarations = load_catalog_parser().parse_registry_declarations(
            (ROOT / "core/Localization.lua").read_bytes())
        self.assertEqual(len(declarations), CURRENT_FULL_UI_KEYS)
        self.assertEqual(list(declarations), list(full_english_oracle()))
        self.assertEqual(list(declarations)[:len(CURRENT_KEYS)], list(current_english_oracle()))
        # Controls: forged dated evidence fails in each object-store state
        # this checkout can show (Git with the dated commit; no Git, as in a
        # shallow clone without it): the current R blob or another file's
        # blob in place of the dated one, a forged source tree, an unknown
        # commit (Git only), and drift of a dated file that is not a
        # declared successor.
        r_blob = dict(record["unchangedSourceBlobs"], **{"core/Localization.lua": current})
        swapped = dict(record["unchangedSourceBlobs"], **{
            "core/Localization.lua": record["unchangedSourceBlobs"]["data/DefaultProfile.lua"]})
        forged_tree = dict(record["sourceBinding"], tree="0" * 40)
        unknown = dict(record["sourceBinding"], commit="f" * 40)
        forgeries = {"R blob": ("unchangedSourceBlobs", r_blob),
                     "swapped blob": ("unchangedSourceBlobs", swapped),
                     "forged tree": ("sourceBinding", forged_tree),
                     "unknown commit": ("sourceBinding", unknown)}
        with_object = git_object_id(record["sourceBinding"]["commit"] + "^{commit}") is not None
        stores = ["none"] + ([git_object_store()] if with_object else [])
        for store in stores:
            for label, (field, value) in forgeries.items():
                if store == "none" and label in ("forged tree", "unknown commit"):
                    continue  # without the object only the blob is checkable; see below
                with self.subTest(forgery=label, store=store):
                    changed = dict(record)
                    changed[field] = value
                    with self.assertRaises(AssertionError):
                        assert_dated_source_blobs(self, changed, store)
            with self.subTest(forgery="undeclared drift", store=store):
                with self.assertRaises(AssertionError):
                    assert_dated_source_blobs(self, record, store, successors={})
            with self.subTest(store=store):
                assert_dated_source_blobs(self, record, store)
        for label, (field, value) in forgeries.items():
            with self.subTest(forgery=label, check="recorded value"):
                changed = dict(record)
                changed[field] = value
                with self.assertRaises(AssertionError):
                    assert_current_automatic_preference(self, changed)
        # Controls: an invented mapping or alias, a non-English resolution or
        # a missing source commit fails.
        mutations = {
            "mapping": ("evidencedMappings", [{"raw": "frFR", "productId": "frFR"}]),
            "alias": ("evidencedAliases", ["enGB"]),
            "alias-evidence": ("aliasEvidence", "client locale frFR"),
            "resolution": ("resolvesTo", "frFR"),
            "source": ("sourceBinding", {"tree": CURRENT_AUTOMATIC_PREFERENCE["sourceBinding"]["tree"]}),
        }
        for label, (field, value) in mutations.items():
            with self.subTest(control=label):
                changed = dict(record)
                changed[field] = value
                with self.assertRaises(AssertionError):
                    assert_current_automatic_preference(self, changed)

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

    def test_current_keys_are_six_historical_rows_21_panel_rows_then_options(self):
        rows = [(r["key"], r["kind"], r["english"], r.get("producerCode"))
                for r in self.doc["keys"]]
        self.assertEqual(rows[:len(EXPECTED_KEYS)], EXPECTED_KEYS)
        self.assertEqual(rows[len(EXPECTED_KEYS):len(HISTORICAL_TECHNICAL_KEYS)],
                         CURRENT_PANEL_KEYS)
        self.assertEqual(rows[len(HISTORICAL_TECHNICAL_KEYS):len(CURRENT_KEYS)], CURRENT_OPTIONS_KEYS)
        self.assertEqual(rows[:len(CURRENT_KEYS)], CURRENT_KEYS)
        self.assertEqual(list(current_english_oracle()), [row[0] for row in rows[:len(CURRENT_KEYS)]])
        # Full visible-UI scope: every later row is a generated full-UI row
        # (cohort fullui:<family>) for a new key; the dated 28 rows carry none.
        later = self.doc["keys"][len(CURRENT_KEYS):]
        self.assertTrue(all(re.fullmatch(r"fullui:[a-z0-9_]+", r.get("cohort", "")) for r in later))
        self.assertTrue(all("cohort" not in r for r in self.doc["keys"][:len(CURRENT_KEYS)]))
        self.assertFalse({r["key"] for r in later} & set(current_english_oracle()))
        for name, _, _, _ in CURRENT_PANEL_KEYS + CURRENT_OPTIONS_KEYS:
            self.assertEqual(self.keys[name]["placeholders"], [], name)
            self.assertNotIn("resultLimitBytes", self.keys[name], name)
        for name, _, english, _ in CURRENT_OPTIONS_KEYS:
            self.assertNotIn("!", english, name)
        adoption = self.doc["currentAdoption"]
        self.assertEqual(adoption["keys"], [row[0] for row in CURRENT_KEYS])
        self.assertEqual(adoption["allWindowSemanticCoverage"], "PENDING")
        assert_current_adoption_scope(self, adoption["scope"])

    def test_no_true_guard_admits_only_the_template_lines_schema_flag(self):
        rows = [row for row in self.doc["keys"] if row.get("lines") is not None]
        self.assertTrue(rows)
        self.assertTrue(all(row["kind"] == "template" and row["lines"] is True for row in rows))
        assert_no_true(self, self.doc)
        allowed = {"keys": [{"key": "a.b", "kind": "template", "lines": True}]}
        assert_no_true(self, allowed)
        for refused in ({"keys": [{"key": "a.b", "kind": "text", "lines": True}]},
                        {"keys": [{"key": "a.b", "kind": "template", "accepted": True}]},
                        {"keys": [{"key": "a.b", "kind": "template", "lines": True, "x": {"lines": True}}]},
                        {"lines": True},
                        {"review": {"fluentHumanAcceptance": True}},
                        {"rows": [{"kind": "template", "lines": True}]}):
            with self.subTest(refused=refused):
                with self.assertRaises(AssertionError):
                    assert_no_true(self, refused)

    def test_current_adoption_scope_names_both_commits_and_no_stale_qualifier(self):
        scope = self.doc["currentAdoption"]["scope"]
        assert_current_adoption_scope(self, scope)
        self.assertNotIn("uncommitted", scope)
        # Controls: a scope lacking either full commit fails.
        for sha in OPTIONS_ADOPTION_COMMITS:
            with self.subTest(missing=sha):
                with self.assertRaises(AssertionError):
                    assert_current_adoption_scope(self, scope.replace(sha, sha[:7]))

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
        for name, _, text, _ in CURRENT_OPTIONS_KEYS:
            self.assertIn('["%s"] = "%s",' % (name, text), english)
        # The "! " notice mark stays code-owned in ui/Panel.lua, outside the text.
        panel = read_text("ui/Panel.lua")
        for fragment in ('L.Text("panel.button.options")', 'L.Resolve("panel.button.options")',
                         'notice and ("! " .. label) or label'):
            self.assertIn(fragment, panel)

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
        historical_keys = [row[0] for row in EXPECTED_KEYS]
        self.assertEqual(sorted(STATIC_AT_BASE + MISSING_AT_BASE), sorted(historical_keys))
        self.assertLess(set(historical_keys), set(self.keys))
        self.assertEqual(baseline["reviewState"], "draft_unreviewed")
        addition = coverage["separatePendingAddition"]
        self.assertEqual(addition["draftEntries"], len(PACK_IDS) * len(MISSING_AT_BASE))
        self.assertEqual(addition["newEnglishKeys"], 0)
        self.assertEqual(addition["reviewState"], "draft_unreviewed; per-language human review pending")
        self.assertEqual(coverage["fallbackCountsAsTranslation"], "never")
        observation = coverage["currentTechnicalObservation"]
        self.assertEqual(observation["reference"], HISTORICAL_TECHNICAL_REFERENCE)
        self.assertNotEqual(observation["reference"]["head"], CURRENT_TECHNICAL_REFERENCE["head"])
        self.assertIn("historical technical", observation["nature"])
        self.assertIn("not final composition", observation["nature"])
        self.assertEqual(observation["inputSha256"],
                         {path: digest for path, (digest, _) in HISTORICAL_REFERENCE_INPUTS.items()})
        # The observation stays at its own 27 keys; it is not the current count.
        kinds = [row[1] for row in HISTORICAL_TECHNICAL_KEYS]
        self.assertEqual(observation["observedEnglishKeys"], len(HISTORICAL_TECHNICAL_KEYS))
        self.assertNotEqual(observation["observedEnglishKeys"], len(CURRENT_KEYS))
        self.assertEqual(observation["observedEnglishKinds"],
                         {"text": kinds.count("text"), "format": kinds.count("format")})
        self.assertEqual(observation["appliesTo"], PACK_IDS)
        self.assertEqual(observation["observedDraftEntriesPerPack"],
                         len(HISTORICAL_TECHNICAL_KEYS))
        self.assertEqual(observation["reviewState"],
                         "draft_unreviewed; per-language human review pending")
        self.assertIn("not future cardinality", observation["observationScope"])
        self.assertEqual(observation["gates"], CURRENT_OBSERVATION_GATES)
        allowed = {"$.separatePendingAddition.draftEntries",
                   "$.separatePendingAddition.newEnglishKeys",
                   "$.currentTechnicalObservation.observedEnglishKeys",
                   "$.currentTechnicalObservation.observedEnglishKinds.text",
                   "$.currentTechnicalObservation.observedEnglishKinds.format",
                   "$.currentTechnicalObservation.observedDraftEntriesPerPack"}
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


# B1 parser foundation (Refs #147): public grammar tests of parse_english,
# parse_packs and CatalogSyntaxError of tools/l10n_catalog.py, on exact bytes,
# against independent literal tables and error codes. No Lua is executed,
# imported or evaluated. The parser class also holds one direct command-line
# characterization: it runs the tool as a script on this repository and
# compares each report record with catalog_report on the same input bytes.
# The schema API, coverage report and command-line cases are in the later
# sections of this file.

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
    "status": "IMPLEMENTED_DRAFT_REVIEW_PENDING",
    "fullValidation": "IMPLEMENTED_DRAFT",
    "validationScope": "Scoped draft for the text, block and template keys of the key-context rows and the single code-owned charge-count format, within the runtime entry cap; not whole #147. Plural variants, dynamic-key coverage per family, runtime load/fallback parity, per-pack translator provenance/rights and approved terminology validation are not implemented by this component.",
    "message": "scoped static-catalog draft registered in source for required CI; independent review and human, native and full-UI gates pending",
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
        data = (ROOT / "data/LocalizationEnglish.lua").read_bytes()
        table = self.catalog.parse_english(data)
        self.assertIs(type(table), dict)
        expected = current_english_oracle()
        # Full visible-UI scope: the dated 28 meanings keep their exact bytes
        # and order, first; every later key is new, never a changed meaning.
        self.assertEqual({key: table[key] for key in expected}, expected)
        self.assertEqual(list(table)[:len(expected)], list(expected))
        self.assertFalse(set(list(table)[len(expected):]) & set(expected))
        self.assertEqual({key: table[key] for key in CATALOG_CURRENT_ENGLISH},
                         CATALOG_CURRENT_ENGLISH)
        assert_current_reference_bytes(self, "data/LocalizationEnglish.lua", data)

    def test_current_english_is_the_committed_canonical_blob(self):
        name = "data/LocalizationEnglish.lua"
        physical = (ROOT / name).read_bytes()
        canonical = assert_current_reference_bytes(self, name, physical)
        # The Git blob ID of the canonical bytes, computed without Git.
        blob = hashlib.sha1(b"blob %d\0" % len(canonical) + canonical).hexdigest()
        # A declared successor of the dated 28-key blob: that blob is history.
        self.assertIn(name, REFERENCE_SUCCESSORS)
        self.assertNotEqual(blob, CURRENT_ENGLISH_GIT_BLOB["blob"])
        # Where Git can read it, the canonical bytes are exactly the committed blob.
        indexed = git_object_id(":" + name)
        if indexed is not None:
            self.assertEqual(blob, indexed)
        self.assertNotEqual((hashlib.sha256(canonical).hexdigest(), len(canonical)),
                            HISTORICAL_REFERENCE_INPUTS[name])
        # The physical checkout bytes are CRLF, so they are not the canonical bytes.
        self.assertNotEqual(canonical, physical)

    def test_current_packs_file_parses_to_its_literal_tables(self):
        data = (ROOT / "data/LocalizationPacks.lua").read_bytes()
        packs = self.catalog.parse_packs(data)
        self.assertIs(type(packs), dict)
        self.assertEqual(list(packs), ["frFR", "deDE", "esES", "plPL", "ptBR", "ruRU"])
        # Full visible-UI scope: every current English key, in English source
        # order, with exactly the selected draft values of each language.
        keys = list(full_english_oracle())
        autonyms = {row[0]: row[3] for row in EXPECTED_PRODUCTS[1:]}
        for pack_id, pack in packs.items():
            with self.subTest(pack_id):
                self.assertEqual(list(pack), ["name", "entries"])
                self.assertEqual(pack["name"], autonyms[pack_id])
                self.assertEqual(pack["name"], CATALOG_CURRENT_PACKS[pack_id]["name"])
                self.assertEqual(list(pack["entries"]), keys)
                self.assertEqual(len(pack["entries"]), CURRENT_FULL_UI_KEYS)
                self.assertLessEqual(set(CATALOG_CURRENT_PACKS[pack_id]["entries"]), set(keys))
                self.assertEqual(pack_value_map_sha256(pack["entries"]),
                                 CURRENT_PACK_VALUE_MAPS[pack_id])
        assert_current_reference_bytes(self, "data/LocalizationPacks.lua", data)

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

    def test_direct_invocation_runs_the_read_only_report_command_line(self):
        env = dict(os.environ)
        env.pop("PYTHONDONTWRITEBYTECODE", None)
        names = ("data/LocalizationEnglish.lua", "data/LocalizationPacks.lua",
                 "docs/localization/KEY_CONTEXT.json",
                 "docs/localization/RELEASE_LANGUAGES.json", "Nexus.toc")
        inputs = [(ROOT / name).read_bytes() for name in names]
        before = catalog_pycache_names()
        load_catalog_parser()
        runs = [subprocess.run([sys.executable, str(CATALOG_TOOL), *args], capture_output=True,
                               cwd=str(ROOT), env=env)
                for args in ((), ("--root", str(ROOT)), ("--require-complete",))]
        self.assertEqual(catalog_pycache_names(), before)
        self.assertEqual([(ROOT / name).read_bytes() for name in names], inputs)
        expected = self.catalog.catalog_report(*inputs[:4])
        records = []
        for run, code in zip(runs, (0, 0, 1)):
            self.assertEqual(run.returncode, code, run.stderr)
            self.assertEqual(run.stderr, b"")
            self.assertTrue(run.stdout.isascii(), run.stdout[:200])
            lines = run.stdout.decode("ascii").splitlines()
            self.assertEqual(len(lines), 1, run.stdout[:200])
            record = json.loads(lines[0])
            self.assertEqual((record["record"], record["exitCode"]), ("report", code))
            self.assertEqual(record["notice"], CATALOG_NOTICE)
            self.assertEqual(record["report"], expected)
            self.assertEqual(record["toc"]["sha256"], hashlib.sha256(inputs[4]).hexdigest())
            records.append(record)
        self.assertEqual(runs[0].stdout, runs[1].stdout)
        self.assertEqual(expected["completeness"]["state"], "INCOMPLETE")
        self.assertEqual(records[2]["externalReadiness"]["state"], "NOT_ESTABLISHED")
        self.assertEqual(records[2]["externalReadiness"]["reportCompletenessState"],
                         expected["completeness"]["state"])


# B2 schema API (Refs #147): public tests of validate_catalog_data and
# CatalogValidationError. The cases were written against the six-key English
# base and its metadata. Their fixtures are independent of the implementation:
# rebuilt historical six-key English, pack and context inputs from the B1
# literals and historical_context(), plus the actual release bytes and the
# literal scalar and template cases below. Actual current checkout inputs are
# exercised separately. Each case changes one thing in memory and
# passes exact bytes to the real schema API; the expectations are independent
# literals, not the implementation's tables. No Lua is executed and main() is
# not invoked here. Coverage counts and evidence (B3a) and the command line
# (B3b) are tested in the later sections of this file.

import copy

SCHEMA_STATUS = "IMPLEMENTED_DRAFT_REVIEW_PENDING"
SCHEMA_OLD_STATUS = "PARSER_ONLY_" + "FULL_VALIDATION_PENDING"
SCHEMA_CHARGE = "readout.charge_counts"
# The runtime MAX_BASE_ENTRIES of core/Localization.lua (full visible-UI
# scope; it was 64 for the pilot cohort). The cap and cap + 1 controls below
# use it.
SCHEMA_MAX_ENTRIES = 4096
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
        # Default inputs of every existing case: the coherent historical
        # six-key fixture (six literal English meanings, 18 inherited pack
        # entries, the projected six-key context) and the actual release
        # metadata without its entry-review declarations.
        cls.context = historical_context()
        cls.release = historical_release()
        cls.raw = historical_raw(cls.context)
        assert_historical_fixture(cls.catalog, cls.raw, cls.context)
        # The actual complete source, unmodified, for the current-source check.
        cls.current_raw = current_raw()
        cls.current_context = load_document("KEY_CONTEXT.json")
        cls.current_release = load_document("RELEASE_LANGUAGES.json")

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
            self.add_static(english, context, "bulk.key_%04d" % index, "Bulk text %d" % index)

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
        current = self.catalog.validate_catalog_data(
            *[self.current_raw[name] for name in ("english", "packs", "context", "release")])
        self.assertIs(type(current), dict)
        self.assertEqual(sorted(current), ["english", "keyContext", "packs", "release"])
        oracle = full_english_oracle()
        self.assertEqual(current["english"], oracle)
        self.assertEqual(list(current["english"]), list(oracle))
        self.assertEqual(list(current["english"])[:len(CURRENT_KEYS)], list(current_english_oracle()))
        self.assertEqual(current["keyContext"], self.current_context)
        self.assertEqual([(row["key"], row["english"]) for row in current["keyContext"]["keys"]],
                         list(oracle.items()))
        self.assertEqual(current["release"], self.current_release)
        self.assertEqual(list(current["packs"]), PACK_IDS)
        for pack_id, pack in current["packs"].items():
            with self.subTest(pack_id):
                self.assertEqual(list(pack["entries"]), list(oracle))
                self.assertLessEqual(set(CURRENT_PACK_KEYS), set(pack["entries"]))
                self.assertEqual(pack["name"], CATALOG_CURRENT_PACKS[pack_id]["name"])
                self.assertEqual(pack_value_map_sha256(pack["entries"]),
                                 CURRENT_PACK_VALUE_MAPS[pack_id])
        for key, text in CATALOG_CURRENT_ENGLISH.items():
            self.assertEqual(current["english"][key], text, key)
        self.assertEqual(current["release"]["validator"]["status"], SCHEMA_STATUS)
        self.assertEqual((self.catalog.STATUS, self.catalog.NOTICE["fullValidation"]),
                         (SCHEMA_STATUS, "IMPLEMENTED_DRAFT"))

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
            # Upper-case hex digits name the same lone surrogate.
            ("release", self.replaced("release", b'"Deutsch"', b'"Deu\\uDBFFtsch"'),
             "json-surrogate"),
            ("context", self.replaced("context", b'"normalization": "none",',
                                      b'"normalization": "x\\uDc00",'), "json-surrogate"),
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
        # Every case here reports on the coherent historical six-key fixture
        # with the actual release metadata without its entry-review
        # declarations; actual complete reports are checked in
        # CatalogCurrentSource below, never through this fixture.
        cls.context = historical_context()
        cls.release = historical_release()
        cls.raw = historical_raw(cls.context)
        assert_historical_fixture(cls.catalog, cls.raw, cls.context)

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

    def test_current_release_records_the_qualified_declarations_and_states_the_limit(self):
        actual = load_document("RELEASE_LANGUAGES.json")
        contract = actual["entryReview"]
        self.assertEqual(contract["contract"], "nexus.l10n.entry_review_declaration")
        self.assertEqual(contract["contractVersion"], 1)
        declarations = contract["declarations"]
        self.assertEqual(len(declarations), sum(CURRENT_DECLARED_COUNTS.values()))
        self.assertEqual(pack_value_map_sha256(declarations), CURRENT_DECLARATIONS_SHA256)
        self.assertEqual({pack_id: len(current_declaration_keys(actual, pack_id))
                          for pack_id in PACK_IDS}, CURRENT_DECLARED_COUNTS)
        for row in declarations:
            self.assertEqual(list(row), ["productId", "key", "translatedTextSha256", "reviewer",
                                         "decision", "evidenceReference", "status"])
        # Two distinct evidence cohorts, each bound to its own reviewer and
        # reference: the 529 original records stay first and byte-for-value
        # unchanged; exactly the six neutral-template records follow. Neither
        # cohort's reviewer or reference may stand in for the other's.
        original = declarations[:ORIGINAL_DECLARATION_COUNT]
        neutral = declarations[ORIGINAL_DECLARATION_COUNT:]
        self.assertEqual(len(original), ORIGINAL_DECLARATION_COUNT)
        self.assertEqual(pack_value_map_sha256(original), ORIGINAL_DECLARATIONS_SHA256)
        for row in original:
            self.assertEqual((row["reviewer"], row["decision"], row["evidenceReference"],
                              row["status"]),
                             (CURRENT_DECLARATION_REVIEWER, "legitimately_identical",
                              CURRENT_DECLARATION_REFERENCE, "declared"))
        self.assertEqual(neutral, NEUTRAL_TEMPLATE_DECLARATIONS)
        self.assertNotIn(NEUTRAL_TEMPLATE_KEY, {row["key"] for row in original})
        # The neutral records bind the literal wrapper text, not a value read
        # from the packs under test.
        self.assertEqual({row["translatedTextSha256"] for row in neutral},
                         {report_sha(NEUTRAL_TEMPLATE_TEXT)})
        self.assertNotEqual((NEUTRAL_TEMPLATE_REVIEWER, NEUTRAL_TEMPLATE_REFERENCE),
                            (CURRENT_DECLARATION_REVIEWER, CURRENT_DECLARATION_REFERENCE))
        # The historical fixture view stays declaration-free.
        self.assertEqual(self.release["entryReview"]["declarations"], [])
        self.assertEqual({k: v for k, v in actual.items() if k != "entryReview"},
                         {k: v for k, v in self.release.items() if k != "entryReview"})
        self.assertIn(REPORT_NOT_EVIDENCE, contract["notEvidenceOf"])
        self.assertEqual(self.release["terminology"], {
            "status": "pending",
            "reference": "docs/localization/KEYS_AND_GLOSSARY.md (historical proposal, unchanged)",
            "gameTermWording": "UNKNOWN until a verified client reference exists",
        })
        self.assertIn(REPORT_NOT_EVIDENCE, self.catalog.EVIDENCE_NOTICE)
        self.assertEqual(self.catalog.NOTICE["fullValidation"], "IMPLEMENTED_DRAFT")
        self.assertEqual(self.catalog.NOTICE["validationScope"], CATALOG_NOTICE["validationScope"])
        self.assertEqual(self.report()["validationScope"], CATALOG_NOTICE["validationScope"])
        plan = " ".join(read_text("docs/localization/FULL_COVERAGE.md").split())
        for required in ("catalog_report", "CatalogEvidenceError", REPORT_NOT_EVIDENCE, "B3b",
                         "IMPLEMENTED_DRAFT", "Author execution of the new tests: NOT_RUN"):
            self.assertIn(required, plan)

    def test_supplied_partial_data_derives_draft_and_missing_per_optional_pack(self):
        report = self.report()
        english_keys = sorted(CATALOG_CURRENT_ENGLISH)
        self.assertEqual((report["schema"], report["schemaVersion"], report["tool"]),
                         ("nexus.l10n.coverage_report", 1, "tools/l10n_catalog.py"))
        self.assertEqual((report["status"], report["fullValidation"]),
                         (SCHEMA_STATUS, "IMPLEMENTED_DRAFT"))
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


# B3b command line (Refs #147): public subprocess tests of
#     python tools/l10n_catalog.py [--root DIR] [--require-complete]
# Temporary roots hold rebuilt historical six-key English, pack and context
# fixtures plus actual release bytes, changed only where a case says so, and
# a minimal Nexus.toc. Real-repository-root cases use actual current inputs.
# Root files are input data:
# nothing in a root is imported or run. The command-line children of cli_run
# run the tool as a script with bytecode writing enabled, and no parser or API
# is mocked there. The isolated -I -B children of cli_fault_run, used only by
# test_unreadable_input_is_a_stable_error, write no bytecode. They load the
# tool from its file and call its real main(). Only pathlib.Path.read_bytes is
# replaced, and the replacement raises OSError(EACCES) only for a path whose
# final component is the given file name; every other path is read by the
# real method (see CLI_FAULT_DRIVER). Expected reports come from the public
# catalog_report on the same bytes, and changed counts derive from the
# fixture tables above. Fill texts and synthetic declarations are
# fixture-only data, not fluent, human or native evidence.

CLI_INPUTS = ("data/LocalizationEnglish.lua", "data/LocalizationPacks.lua",
              "docs/localization/KEY_CONTEXT.json",
              "docs/localization/RELEASE_LANGUAGES.json", "Nexus.toc")
CLI_TOC_ORDER = ("data/LocalizationEnglish.lua", "data/LocalizationPacks.lua",
                 "core/Localization.lua")
CLI_TOC_HEAD = ("## Interface: 30300", "## Title: Fixture", "# fixture comment", "")
CLI_ERROR_CODES = {"CatalogCliError": "CLI_CODES", "CatalogSyntaxError": "CODES",
                   "CatalogValidationError": "VALIDATION_CODES",
                   "CatalogEvidenceError": "EVIDENCE_CODES"}


def cli_backslash(path):
    return path.replace("/", chr(92))


def cli_toc(*entries, newline="\n"):
    """A minimal Nexus.toc: two metadata lines, a comment, a blank line, then
    the entries, each followed by newline."""
    return "".join(line + newline for line in CLI_TOC_HEAD + entries).encode("utf-8")


# The three required lines use Windows separators, as in Nexus.toc, between
# unrelated modules that no fixture root contains.
CLI_TOC = cli_toc("data/Release.lua", *[cli_backslash(path) for path in CLI_TOC_ORDER],
                  "core/UserText.lua")


def cli_run(*args, cwd):
    """Run the public command line in a new process with bytecode writing
    enabled and return the completed process."""
    env = dict(os.environ)
    env.pop("PYTHONDONTWRITEBYTECODE", None)
    return subprocess.run([sys.executable, str(CATALOG_TOOL), *[str(arg) for arg in args]],
                          capture_output=True, cwd=str(cwd), env=env)


def cli_tree(root):
    """Every directory and file under root, sorted by path, with file bytes."""
    entries = []
    for directory, names, files in os.walk(str(root)):
        base = Path(directory)
        entries.extend((str(base.joinpath(name).relative_to(root)), None) for name in names)
        entries.extend((str(base.joinpath(name).relative_to(root)),
                        base.joinpath(name).read_bytes()) for name in files)
    return sorted(entries, key=lambda entry: entry[0])


# The portable read-fault pair of test_unreadable_input_is_a_stable_error
# runs this in a separate isolated Python (-I -B), as the OS-error cases of
# tools/tests/test_l10n_inventory.py do. It loads the tool from its file,
# makes pathlib.Path.<operation> raise OSError(EACCES) for every path whose
# final component is <name> and calls the tool's real public main() with the
# remaining arguments. When main() returns, it writes each path given to that
# operation, each injected fault and the returned value to the record file,
# outside the input root. Nothing else is replaced. No file permission is
# changed, nothing in the input root is imported or run and, unlike the
# command-line children of cli_run, this child writes no bytecode.
CLI_FAULT_DRIVER = '''\
import errno, importlib.util, json, pathlib, sys
tool, operation, name, record = sys.argv[1:5]
argv = sys.argv[5:]
spec = importlib.util.spec_from_file_location('l10n_catalog_under_fault', tool)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
real = getattr(pathlib.Path, operation)
calls, injected = [], []
def failing(self, *args, **kwargs):
    calls.append(str(self))
    if self.name == name:
        injected.append(str(self))
        raise OSError(errno.EACCES, 'injected filesystem fault', str(self))
    return real(self, *args, **kwargs)
setattr(pathlib.Path, operation, failing)
code = module.main(argv)
with open(record, 'w', encoding='ascii') as handle:
    json.dump({'operation': operation, 'name': name, 'calls': calls,
               'injected': injected, 'returned': code}, handle)
raise SystemExit(code)
'''


def cli_fault_run(test, root, operation, name):
    """Run CLI_FAULT_DRIVER in a new isolated process on main(["--root", root]),
    with root as the working directory and pathlib.Path.<operation> failing
    for name. Return the completed process and the driver's record, read from
    a new temporary directory outside root. If the driver wrote no record,
    the test fails; the control is never skipped or passed."""
    holder = tempfile.TemporaryDirectory()
    test.addCleanup(holder.cleanup)
    record = Path(holder.name) / "fault-record.json"
    command = [sys.executable, "-I", "-B", "-c", CLI_FAULT_DRIVER, str(CATALOG_TOOL),
               operation, name, str(record), "--root", str(root)]
    run = subprocess.run(command, capture_output=True, cwd=str(root))
    if not record.is_file():
        test.fail("the fault driver wrote no record (exit %r): %r"
                  % (run.returncode, run.stderr[-500:]))
    return run, json.loads(record.read_bytes().decode("ascii"))


def cli_link_directory(test, link, target):
    """Create link as a directory symlink to target. Where Windows refuses an
    unprivileged symlink, create a junction instead. If both fail, the test
    fails; the control is never skipped or passed."""
    try:
        os.symlink(str(target), str(link), target_is_directory=True)
        return "symlink"
    except OSError as error:
        if os.name != "nt":
            test.fail("cannot create the directory symlink for this control: %s" % error)
    import _winapi
    try:
        _winapi.CreateJunction(str(target), str(link))
    except OSError as error:
        test.fail("cannot create a symlink or junction for this control: %s" % error)
    return "junction"


def cli_remove_link(link, root, kind):
    """Remove only the directory link created directly inside the temporary
    root, never its target and never recursively."""
    import stat
    link = Path(os.path.abspath(str(link)))
    if link.parent != Path(os.path.abspath(str(root))):
        raise AssertionError("refusing to remove a link outside the temporary root")
    if kind == "symlink":
        verified = os.path.islink(str(link))
    else:
        verified = bool(os.lstat(str(link)).st_file_attributes
                        & stat.FILE_ATTRIBUTE_REPARSE_POINT)
    if not verified:
        raise AssertionError("refusing to remove a path that is not the created link")
    if os.name == "nt":
        os.rmdir(str(link))
    else:
        os.unlink(str(link))


class CatalogCommandLine(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog_parser()
        cls.release = historical_release()
        # Temporary roots copy the coherent historical six-key fixture and the
        # actual release metadata without its entry-review declarations; the
        # real repository root is the actual source.
        context = historical_context()
        historical = historical_raw(context)
        assert_historical_fixture(cls.catalog, historical, context)
        cls.raw = {name: historical[part] for name, part
                   in zip(CLI_INPUTS[:4], ("english", "packs", "context", "release"))}
        cls.current_raw = {name: (ROOT / name).read_bytes() for name in CLI_INPUTS[:4]}

    def temp_dir(self):
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        return Path(holder.name)

    def make_root(self, overrides=None):
        """A temporary public-only root holding the four catalog inputs and
        CLI_TOC, with overrides applied; None removes a file."""
        root = self.temp_dir()
        files = dict(self.raw)
        files["Nexus.toc"] = CLI_TOC
        files.update(overrides or {})
        for name, data in files.items():
            if data is not None:
                path = root.joinpath(*name.split("/"))
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
        return root

    def run_cli(self, root, *args, cwd=None):
        """Run the command line; nothing under root and no tools/__pycache__
        entry may change."""
        tree, cache = cli_tree(root), catalog_pycache_names()
        run = cli_run(*args, cwd=root if cwd is None else cwd)
        self.assertEqual(cli_tree(root), tree)
        self.assertEqual(catalog_pycache_names(), cache)
        return run

    def expected(self, root):
        return self.catalog.catalog_report(*[root.joinpath(*name.split("/")).read_bytes()
                                             for name in CLI_INPUTS[:4]])

    def record(self, run, exit_code):
        """The single report record on stdout, in canonical ASCII JSON."""
        self.assertEqual(run.returncode, exit_code, run.stderr[:500])
        self.assertEqual(run.stderr, b"")
        self.assertTrue(run.stdout.isascii(), run.stdout[:200])
        record = json.loads(run.stdout.decode("ascii"))
        self.assertEqual(run.stdout, (json.dumps(record, sort_keys=True) + "\n").encode("ascii"))
        self.assertEqual((record["record"], record["exitCode"], record["tool"]),
                         ("report", exit_code, "tools/l10n_catalog.py"))
        return record

    def assert_error(self, run, error_class, code, **fields):
        """The single error record on stderr: stable class and code, exit 2,
        nothing on stdout and no traceback."""
        self.assertEqual(run.returncode, 2, run.stderr[:500])
        self.assertEqual(run.stdout, b"")
        self.assertTrue(run.stderr.isascii(), run.stderr[:500])
        record = json.loads(run.stderr.decode("ascii"))
        self.assertEqual(run.stderr, (json.dumps(record, sort_keys=True) + "\n").encode("ascii"))
        self.assertEqual((record["record"], record["errorClass"], record["code"],
                          record["exitCode"]), ("error", error_class, code, 2))
        self.assertIn(code, getattr(self.catalog, CLI_ERROR_CODES[error_class]))
        for name, value in fields.items():
            self.assertEqual(record[name], value, name)
        return record

    def test_public_root_reports_partial_data_and_strict_mode_stays_nonzero(self):
        root = self.make_root()
        expected = self.expected(root)
        default = self.record(self.run_cli(root, "--root", root), 0)
        strict = self.record(self.run_cli(root, "--root", root, "--require-complete"), 1)
        toc = (root / "Nexus.toc").read_bytes()
        for record in (default, strict):
            self.assertEqual(record["report"], expected)
            self.assertEqual(record["notice"], CATALOG_NOTICE)
            self.assertEqual((record["status"], record["fullValidation"]),
                             (SCHEMA_STATUS, "IMPLEMENTED_DRAFT"))
            self.assertEqual(record["validationScope"], CATALOG_NOTICE["validationScope"])
            self.assertEqual((record["toc"]["source"], record["toc"]["sha256"],
                              record["toc"]["byteLength"]),
                             ("Nexus.toc", hashlib.sha256(toc).hexdigest(), len(toc)))
            self.assertEqual([row["path"] for row in record["toc"]["requiredOrder"]],
                             list(CLI_TOC_ORDER))
            for row, name in zip(record["report"]["inputs"], CLI_INPUTS):
                data = self.raw[name]
                self.assertEqual((row["source"], row["sha256"], row["byteLength"]),
                                 (name, hashlib.sha256(data).hexdigest(), len(data)))
            for path, value in walk(record):
                self.assertNotIsInstance(value, (bool, float), path)
        self.assertEqual((default["requireComplete"], strict["requireComplete"]),
                         ("not_requested", "requested"))
        technical = default["technicalCatalog"]
        missing = sum(row["counts"]["missing"] for row in expected["products"])
        self.assertEqual((technical["validity"], technical["englishKeys"],
                          technical["missingEntries"]),
                         ("VALID", expected["denominator"]["englishKeys"], missing))
        self.assertEqual(technical["entryPresence"],
                         "PARTIAL" if missing else "EVERY_CURRENT_ENGLISH_KEY_PRESENT")
        self.assertEqual([(row["productId"], row["counts"]) for row in technical["products"]],
                         [(row["productId"], row["counts"]) for row in expected["products"]])
        readiness = strict["externalReadiness"]
        self.assertEqual(readiness, default["externalReadiness"])
        self.assertEqual((readiness["state"], readiness["externalAcceptance"]),
                         ("NOT_ESTABLISHED", "NOT_ATTESTED"))
        self.assertEqual((readiness["reportCompletenessState"], readiness["reportReasonCount"]),
                         (expected["completeness"]["state"],
                          expected["completeness"]["reasonCount"]))
        self.assertEqual(set(readiness["blockingReasonCodes"]),
                         report_codes(expected) | {"external-acceptance-not-attested"})
        self.assertEqual(readiness["blockingReasonCount"],
                         expected["completeness"]["reasonCount"] + 1)
        text = json.dumps(strict, sort_keys=True).lower()
        for claim in ("release_ready", "releaseready", "release-ready", "100%"):
            self.assertNotIn(claim, text)

    def test_filled_known_entries_change_derived_counts_but_not_readiness(self):
        packs = copy.deepcopy(CATALOG_CURRENT_PACKS)
        for pack in packs.values():
            pack["entries"].update(REPORT_FILL)
        filled_packs = schema_packs_source(packs)
        declarations = [report_declaration(pack_id, key, text)
                        for pack_id, pack in packs.items()
                        for key, text in sorted(pack["entries"].items())]
        release = copy.deepcopy(self.release)
        release["entryReview"]["declarations"] = declarations
        roots = {
            "current": self.make_root(),
            "filled": self.make_root({"data/LocalizationPacks.lua": filled_packs}),
            "declared": self.make_root({"data/LocalizationPacks.lua": filled_packs,
                                        "docs/localization/RELEASE_LANGUAGES.json":
                                            schema_json(release)}),
        }
        records = {}
        for name, root in roots.items():
            with self.subTest(name):
                default = self.record(self.run_cli(root, "--root", root), 0)
                strict = self.record(self.run_cli(root, "--root", root, "--require-complete"), 1)
                expected = self.expected(root)
                self.assertEqual((default["report"], strict["report"]), (expected, expected))
                readiness = strict["externalReadiness"]
                self.assertEqual(readiness, default["externalReadiness"])
                self.assertEqual((readiness["state"], readiness["reportCompletenessState"]),
                                 ("NOT_ESTABLISHED", "INCOMPLETE"))
                self.assertLessEqual(REPORT_REMAINING_REASONS
                                     | {"external-acceptance-not-attested"},
                                     set(readiness["blockingReasonCodes"]))
                records[name] = default
        english_keys = sorted(CATALOG_CURRENT_ENGLISH)
        current = {row["productId"]: row["counts"]
                   for row in records["current"]["technicalCatalog"]["products"]}
        filled = records["filled"]["technicalCatalog"]
        self.assertEqual((filled["entryPresence"], filled["missingEntries"]),
                         ("EVERY_CURRENT_ENGLISH_KEY_PRESENT", 0))
        for row in filled["products"]:
            before = current[row["productId"]]
            self.assertEqual(row["entriesPresent"], len(english_keys))
            self.assertEqual(row["counts"]["missing"], 0)
            self.assertEqual(row["counts"]["draft_unreviewed"],
                             before["draft_unreviewed"] + before["missing"])
        for row in records["declared"]["technicalCatalog"]["products"]:
            self.assertEqual(row["counts"]["translated_and_reviewed"], len(english_keys))
        filled_codes = set(records["filled"]["externalReadiness"]["blockingReasonCodes"])
        self.assertNotIn("entries-missing", filled_codes)
        self.assertIn("entries-draft-unreviewed", filled_codes)
        declared_codes = records["declared"]["externalReadiness"]["blockingReasonCodes"]
        self.assertEqual([code for code in declared_codes if code.startswith("entries-")], [])
        self.assertIn("review-gate-not-established", declared_codes)
        self.assertEqual(records["declared"]["report"]["evidence"]["qualifiedDeclarations"],
                         len(declarations))

    def test_toc_order_duplicates_and_separator_aliases(self):
        english, packs, localization = CLI_TOC_ORDER
        back = cli_backslash
        accepted = (
            ("forward slashes", cli_toc(english, packs, localization)),
            ("mixed separators, whitespace and absent unrelated modules",
             cli_toc("core/UserText.lua", "  " + back(english), packs + " \t",
                     back(localization), "ui/Missing.lua")),
            ("CRLF line ends", cli_toc(*[back(path) for path in CLI_TOC_ORDER], newline="\r\n")),
            ("byte order mark", b"\xef\xbb\xbf" + cli_toc(english, packs, localization)),
        )
        for label, toc in accepted:
            with self.subTest(label):
                root = self.make_root({"Nexus.toc": toc})
                record = self.record(self.run_cli(root, "--root", root), 0)
                self.assertEqual(record["toc"]["sha256"], hashlib.sha256(toc).hexdigest())
                self.assertEqual(record["report"], self.expected(root))
        rejected = (
            ("packs before English", (packs, english, localization), "toc-order", packs),
            ("Localization before packs", (english, localization, packs), "toc-order",
             localization),
            ("Localization first", (localization, english, packs), "toc-order", localization),
            ("English missing", (packs, localization), "toc-missing-entry", english),
            ("English only in a comment", ("# " + english, packs, localization),
             "toc-missing-entry", english),
            ("English only in metadata", ("## X-Load: " + english, packs, localization),
             "toc-missing-entry", english),
            ("Localization missing", (english, packs), "toc-missing-entry", localization),
            ("English twice", (english, english, packs, localization), "toc-duplicate-entry",
             english),
            ("slash and backslash aliases", (back(english), packs, localization, english),
             "toc-duplicate-entry", english),
            ("doubled separator alias",
             (english, packs, localization, "data//LocalizationEnglish.lua"),
             "toc-duplicate-entry", english),
            ("mixed separator alias",
             (english, back(packs), localization, "data" + chr(92) + "/LocalizationPacks.lua"),
             "toc-duplicate-entry", packs),
            ("Localization twice", (english, packs, localization, back(localization)),
             "toc-duplicate-entry", localization),
        )
        for label, entries, code, subject in rejected:
            with self.subTest(label):
                root = self.make_root({"Nexus.toc": cli_toc(*entries)})
                self.assert_error(self.run_cli(root, "--root", root), "CatalogCliError", code,
                                  subject=subject)
        root = self.make_root({"Nexus.toc": b"\xff" + CLI_TOC})
        self.assert_error(self.run_cli(root, "--root", root), "CatalogCliError", "toc-not-utf8",
                          subject="Nexus.toc")

    def test_missing_malformed_and_wrong_kind_inputs_get_stable_codes(self):
        for name in CLI_INPUTS:
            with self.subTest(missing=name):
                root = self.make_root({name: None})
                self.assert_error(self.run_cli(root, "--root", root), "CatalogCliError",
                                  "input-missing", subject=name)
            with self.subTest(directory=name):
                root = self.make_root({name: None})
                root.joinpath(*name.split("/")).mkdir(parents=True)
                self.assert_error(self.run_cli(root, "--root", root), "CatalogCliError",
                                  "input-not-file", subject=name)
        release = copy.deepcopy(self.release)
        release["entryReview"]["declarations"] = [report_declaration(
            "frFR", REPORT_SAVE, "Synthetic fixture text that is not the entry")]
        packs = copy.deepcopy(CATALOG_CURRENT_PACKS)
        packs["deDE"]["entries"][REPORT_LIST] = "a|b"
        cases = (
            ("data/LocalizationEnglish.lua", b"", "CatalogSyntaxError", "bad-bootstrap"),
            ("data/LocalizationPacks.lua", self.raw["data/LocalizationPacks.lua"]
             + b"return Nexus\n", "CatalogSyntaxError", "trailing-content"),
            ("data/LocalizationPacks.lua", schema_packs_source(packs), "CatalogValidationError",
             "invalid-text"),
            ("docs/localization/KEY_CONTEXT.json",
             self.raw["docs/localization/KEY_CONTEXT.json"].rstrip()[:-1],
             "CatalogValidationError", "json-invalid"),
            ("docs/localization/RELEASE_LANGUAGES.json", b"[]", "CatalogValidationError",
             "json-top-level"),
            ("docs/localization/RELEASE_LANGUAGES.json", schema_json(release),
             "CatalogEvidenceError", "evidence-stale"),
        )
        for name, data, error_class, code in cases:
            with self.subTest(name=name, code=code):
                root = self.make_root({name: data})
                self.assert_error(self.run_cli(root, "--root", root), error_class, code)

    def test_unreadable_input_is_a_stable_error(self):
        name = "docs/localization/RELEASE_LANGUAGES.json"
        root = self.make_root()
        target = root.joinpath(*name.split("/"))
        data = target.read_bytes()
        tree, cache = cli_tree(root), catalog_pycache_names()
        resolved = [root.resolve(strict=True).joinpath(*source.split("/"))
                    for source in CLI_INPUTS]
        stop, unused = CLI_INPUTS.index(name), "UNUSED.json"
        self.assertNotIn(unused, [path.name for path in resolved])
        # The permanent matched pair runs the real main() on this root through
        # CLI_FAULT_DRIVER on every platform. With read_bytes failing only for a
        # name that no input has, its output must equal that of the normal
        # command line on the same root, input hashes included. With read_bytes
        # failing for the release file, it must take the real input-unreadable
        # path and stop there. Each driver record lists the paths given to
        # read_bytes and those it faulted, so a missing injection fails here.
        plain = self.run_cli(root, "--root", root)
        control, control_record = cli_fault_run(self, root, "read_bytes", unused)
        fault, fault_record = cli_fault_run(self, root, "read_bytes", target.name)
        self.assertEqual(cli_tree(root), tree)
        self.assertEqual(catalog_pycache_names(), cache)
        self.record(plain, 0)
        report = self.record(control, 0)
        self.assertEqual(control.stdout, plain.stdout)
        self.assertEqual(report["report"], self.expected(root))
        self.assertEqual([row["sha256"] for row in report["report"]["inputs"]]
                         + [report["toc"]["sha256"]],
                         [hashlib.sha256(path.read_bytes()).hexdigest() for path in resolved])
        self.assert_error(fault, "CatalogCliError", "input-unreadable", subject=name)
        for driver, failing, paths, injected, returned in (
                (control_record, unused, resolved, [], 0),
                (fault_record, target.name, resolved[:stop + 1], [resolved[stop]], 2)):
            self.assertEqual((driver["operation"], driver["name"], driver["returned"]),
                             ("read_bytes", failing, returned))
            self.assertEqual([Path(path) for path in driver["calls"]], paths)
            self.assertEqual([Path(path) for path in driver["injected"]], injected)
        # The real OS control, in addition to the pair: a Windows byte-range
        # lock, or mode 000 where this account is actually refused the file.
        if os.name == "nt":
            import msvcrt
            with open(str(target), "rb") as handle:
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, len(data))
                try:
                    run = cli_run("--root", root, cwd=root)
                finally:
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, len(data))
        else:
            mode = target.stat().st_mode & 0o7777
            target.chmod(0)
            try:
                try:
                    with open(str(target), "rb"):
                        denied = False
                except PermissionError:
                    denied = True
                if denied:
                    run = cli_run("--root", root, cwd=root)
            finally:
                target.chmod(mode)
            self.assertEqual(target.stat().st_mode & 0o7777, mode)
            if not denied:
                # Limitation: this account still reads a mode-000 file (root
                # or a privileged container), so no real OS permission denial
                # is established here. The injected fault result above is
                # reused instead; it proves the read-error handling of the
                # command line, not that the OS enforces file permissions.
                run = fault
                print("LIMITATION: mode-000 file readable by this account; real OS denial not established; injected-fault error handling reused", file=sys.stderr)
        self.assertEqual(catalog_pycache_names(), cache)
        self.assert_error(run, "CatalogCliError", "input-unreadable", subject=name)
        self.assertEqual(target.read_bytes(), data)
        self.assertEqual(cli_tree(root), tree)

    def test_symlink_or_junction_escape_is_refused(self):
        data = {name: self.raw[name] for name in CLI_INPUTS[:2]}
        root = self.make_root({name: None for name in data})
        outside, inside = self.temp_dir(), root / "inside-data"
        inside.mkdir()
        for directory in (outside, inside):
            for name, content in data.items():
                directory.joinpath(Path(name).name).write_bytes(content)
        link, cache = root / "data", catalog_pycache_names()
        expected = self.catalog.catalog_report(*[self.raw[name] for name in CLI_INPUTS[:4]])
        for target, escapes in ((outside, True), (inside, False)):
            with self.subTest(escapes=escapes):
                kind = cli_link_directory(self, link, target)
                try:
                    run = cli_run("--root", root, cwd=root)
                finally:
                    cli_remove_link(link, root, kind)
                if escapes:
                    self.assert_error(run, "CatalogCliError", "input-escape",
                                      subject=CLI_INPUTS[0])
                else:
                    self.assertEqual(self.record(run, 0)["report"], expected)
        self.assertFalse(os.path.lexists(str(link)))
        self.assertEqual(catalog_pycache_names(), cache)
        for directory in (outside, inside):
            for name, content in data.items():
                self.assertEqual(directory.joinpath(Path(name).name).read_bytes(), content)

    def test_root_python_and_lua_code_stay_data_and_never_run(self):
        markers = self.temp_dir()
        marker = markers / "executed.marker"
        python = ("open(%r, 'w').close()\n" % str(marker)).encode("utf-8")
        lua = ('io.open("%s", "w"):close() os.execute("exit")' % marker.as_posix()).encode("utf-8")
        english = b"-- " + lua + b"\n" + self.raw["data/LocalizationEnglish.lua"]
        overrides = {"data/LocalizationEnglish.lua": english, "core/Localization.lua": lua + b"\n"}
        for name in ("json.py", "pathlib.py", "types.py", "hashlib.py", "re.py",
                     "sitecustomize.py", "usercustomize.py", "l10n_inventory.py",
                     "tools/l10n_inventory.py", "tools/l10n_catalog.py", "tools/__init__.py",
                     "__main__.py"):
            overrides[name] = python
        root = self.make_root(overrides)
        record = self.record(self.run_cli(root, "--root", root), 0)
        self.assertEqual(record["report"], self.expected(root))
        self.assertEqual(record["report"]["inputs"][0]["sha256"],
                         hashlib.sha256(english).hexdigest())
        self.assertFalse(marker.exists())
        self.assertEqual(list(markers.iterdir()), [])

    def test_repeated_runs_are_identical_ascii_and_bind_no_root_path(self):
        first, second = self.make_root(), self.make_root()
        runs = [self.run_cli(root, "--root", root) for root in (first, second, first)]
        runs.append(self.run_cli(first, "--root=" + str(first / "docs" / ".."), cwd=second))
        self.assertEqual({run.stdout for run in runs}, {runs[0].stdout})
        record = self.record(runs[0], 0)
        text = runs[0].stdout.decode("ascii")
        for root in (first, second):
            self.assertNotIn(root.name, text)
        self.assertEqual(record["report"], self.expected(first))
        toc = (first / "Nexus.toc").read_bytes()
        self.assertEqual(record["toc"]["sha256"], hashlib.sha256(toc).hexdigest())
        self.assertEqual([row["sha256"] for row in record["report"]["inputs"]],
                         [hashlib.sha256(self.raw[name]).hexdigest() for name in CLI_INPUTS[:4]])

    def test_default_root_is_the_tool_repository_not_the_working_directory(self):
        packs = copy.deepcopy(CATALOG_CURRENT_PACKS)
        for pack in packs.values():
            pack["entries"].update(REPORT_FILL)
        elsewhere = self.make_root({"data/LocalizationPacks.lua": schema_packs_source(packs)})
        before = [(ROOT / name).read_bytes() for name in CLI_INPUTS]
        self.assertEqual(before[:4], [self.current_raw[name] for name in CLI_INPUTS[:4]])
        default = self.run_cli(elsewhere, cwd=elsewhere)
        explicit = self.run_cli(elsewhere, "--root", ROOT, cwd=elsewhere)
        relative = self.run_cli(elsewhere, "--root", ".", cwd=ROOT)
        own = self.run_cli(elsewhere, "--root", ".", cwd=elsewhere)
        self.assertEqual([(ROOT / name).read_bytes() for name in CLI_INPUTS], before)
        record = self.record(default, 0)
        self.assertEqual(default.stdout, explicit.stdout)
        self.assertEqual(default.stdout, relative.stdout)
        self.assertEqual(record["report"], self.catalog.catalog_report(*before[:4]))
        self.assertEqual(record["toc"]["sha256"], hashlib.sha256(before[4]).hexdigest())
        self.assertEqual([(row["source"], row["sha256"], row["byteLength"])
                          for row in record["report"]["inputs"]],
                         [(name, hashlib.sha256(data).hexdigest(), len(data))
                          for name, data in zip(CLI_INPUTS[:4], before[:4])])
        self.assertEqual(record["report"]["englishBaseline"]["keys"],
                         sorted(full_english_oracle()))
        own_record = self.record(own, 0)
        self.assertEqual(own_record["report"], self.expected(elsewhere))
        self.assertEqual(own_record["report"]["englishBaseline"]["keys"],
                         sorted(CATALOG_CURRENT_ENGLISH))
        self.assertEqual([row["sha256"] for row in own_record["report"]["inputs"]],
                         [hashlib.sha256(elsewhere.joinpath(*name.split("/")).read_bytes())
                          .hexdigest() for name in CLI_INPUTS[:4]])
        self.assertNotEqual(own_record["report"], record["report"])

    def test_argument_and_root_errors_are_stable_records(self):
        root = self.make_root()
        cases = (
            (("--verbose",), "argument-unknown", "argument[0]"),
            (("-h",), "argument-unknown", "argument[0]"),
            (("--root", root, "extra"), "argument-unknown", "argument[2]"),
            (("--root",), "argument-missing-value", "--root"),
            (("--root=",), "argument-missing-value", "--root"),
            (("--root", root, "--root", root), "argument-duplicate", "--root"),
            (("--root", root, "--root=" + str(root)), "argument-duplicate", "--root"),
            (("--require-complete", "--require-complete"), "argument-duplicate",
             "--require-complete"),
            (("--root", root / "absent"), "root-missing", "root"),
            (("--root", root / "Nexus.toc"), "root-not-directory", "root"),
        )
        for args, code, subject in cases:
            with self.subTest(args=[str(arg) for arg in args]):
                self.assert_error(self.run_cli(root, *args), "CatalogCliError", code,
                                  subject=subject)


# Actual current source (Refs #139, #143, #147, #148): public schema, report
# and command-line tests on the unmodified physical bytes of the actual
# 28-key catalog inputs, kept apart from the historical six-key fixture
# above. Keys, English meanings, autonyms and the 18 inherited translations
# are the independent literals near the top of this file; the remaining 144
# draft pack entries (18 earlier missing-key entries plus 126 panel entries)
# are bound by the canonical reference hash only, are not restated and claim
# no fluent, human or native acceptance. The issue #165 Options label has no
# pack entry: it is missing from every pack, and its English fallback is not
# a translation. Every count comes
# from the real APIs. No Lua, Git or network is used, and nothing is written
# outside a temporary directory.

class CatalogCurrentSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = load_catalog_parser()
        cls.raw = current_raw()
        cls.context = load_document("KEY_CONTEXT.json")
        cls.release = load_document("RELEASE_LANGUAGES.json")

    def arguments(self, english=None, packs=None, context=None):
        """The actual physical bytes, with any given part replaced by the
        bytes of a synthetic in-memory table or document."""
        parts = {"english": english, "packs": packs, "context": context}
        renders = {"english": schema_english_source, "packs": schema_packs_source,
                   "context": schema_json}
        return [self.raw[name] if parts.get(name) is None else renders[name](parts[name])
                for name in ("english", "packs", "context", "release")]

    def test_actual_source_validates_and_every_pack_reports_every_english_key(self):
        oracle = full_english_oracle()
        keys = sorted(oracle)
        result = self.catalog.validate_catalog_data(*self.arguments())
        self.assertEqual(sorted(result), ["english", "keyContext", "packs", "release"])
        self.assertEqual(result["english"], oracle)
        self.assertEqual(list(result["english"]), list(oracle))
        self.assertEqual(list(result["english"])[:len(CURRENT_KEYS)], list(current_english_oracle()))
        self.assertEqual(result["keyContext"], self.context)
        self.assertEqual(list(result["packs"]), PACK_IDS)
        # Independent of the report: declared and placeholder entries are
        # byte-identical to their English, every draft entry differs from it.
        for pack_id, pack in result["packs"].items():
            draft, declared, placeholder = current_categories(self.release, pack_id, keys)
            with self.subTest(pack_id, part="values"):
                self.assertEqual(list(pack["entries"]), list(oracle))
                self.assertEqual([key for key in keys if pack["entries"][key] == oracle[key]],
                                 sorted(declared + placeholder))
        report = self.catalog.catalog_report(*self.arguments())
        self.assertEqual((report["englishBaseline"]["keyCount"], report["englishBaseline"]["keys"]),
                         (CURRENT_FULL_UI_KEYS, keys))
        self.assertEqual(report["denominator"]["englishKeys"], CURRENT_FULL_UI_KEYS)
        self.assertEqual([row["productId"] for row in report["products"]], PACK_IDS)
        for row in report["products"]:
            with self.subTest(row["productId"]):
                self.assertEqual(list(row["counts"]), list(REPORT_CATEGORIES))
                for category in REPORT_CATEGORIES:
                    self.assertEqual(row["counts"][category], len(row["keys"][category]), category)
                draft, declared, placeholder = current_categories(self.release, row["productId"], keys)
                self.assertEqual((row["denominator"], row["entriesPresent"]),
                                 (len(keys), len(keys)))
                self.assertEqual(row["reconciliation"],
                                 {"denominator": len(keys), "inDenominatorTotal": len(keys)})
                self.assertEqual(row["keys"]["draft_unreviewed"], draft)
                self.assertEqual(row["keys"]["reviewed_legitimately_identical"], declared)
                self.assertEqual(row["keys"]["deliberate_english_placeholder"], placeholder)
                self.assertEqual(row["keys"]["missing"], [])
                self.assertEqual(len(declared), CURRENT_DECLARED_COUNTS[row["productId"]])
                for category in REPORT_CATEGORIES:
                    if category not in ("draft_unreviewed", "reviewed_legitimately_identical",
                                        "deliberate_english_placeholder"):
                        self.assertEqual(row["keys"][category], [], category)
                self.assertEqual(row["declarationsApplied"], len(declared))
        self.assertEqual(report_reasons(report, "entries-missing"), [])
        self.assertEqual([r["subject"] for r in report_reasons(report, "entries-draft-unreviewed")],
                         PACK_IDS)
        # The report states a category reason only for a pack whose list is
        # not empty (as for every other entries- reason), so with no held
        # placeholder there is none.
        self.assertEqual([(r["subject"], r["keys"])
                          for r in report_reasons(report, "entries-deliberate-english-placeholder")],
                         [(pack_id, CURRENT_ENGLISH_PLACEHOLDER_KEYS[pack_id]) for pack_id in PACK_IDS
                          if CURRENT_ENGLISH_PLACEHOLDER_KEYS[pack_id]])
        self.assertEqual((report["evidence"]["declarationCount"],
                          report["evidence"]["qualifiedDeclarations"]),
                         (sum(CURRENT_DECLARED_COUNTS.values()), sum(CURRENT_DECLARED_COUNTS.values())))
        self.assertEqual(report["completeness"]["state"], "INCOMPLETE")

    def test_actual_hud_adopts_23_keys_and_every_other_gate_stays_pending(self):
        report = self.catalog.catalog_report(*self.arguments())
        families = report["families"]
        self.assertEqual([(f["name"], f["proposedKeyFamily"], f["issue"], f["paths"])
                          for f in families], EXPECTED_FAMILIES)
        hud = families[0]
        # Full visible-UI scope: the dated 23 HUD keys stay first; every
        # family's keys are those of the independently loaded context.
        declared = {family["name"]: family["adoptedKeys"] for family in self.context["windowFamilies"]}
        reviewed_by_pack = {pack_id: set(current_declaration_keys(self.release, pack_id))
                            for pack_id in PACK_IDS}
        self.assertEqual({pack_id: len(keys) for pack_id, keys in reviewed_by_pack.items()},
                         CURRENT_DECLARED_COUNTS)
        self.assertEqual(hud["adoptedKeys"][:len(CURRENT_HUD_ADOPTED_KEYS)], CURRENT_HUD_ADOPTED_KEYS)
        self.assertEqual((hud["adoptedKeys"], hud["adoptedKeyCount"]),
                         (declared[hud["name"]], len(declared[hud["name"]])))
        for family in families:
            with self.subTest(family["name"]):
                self.assertEqual((family["semanticStatus"], family["coverageStatus"],
                                  family["state"]), ("PENDING", "PENDING", "INCOMPLETE"))
                codes = [reason["code"] for reason in family["reasons"]]
                self.assertEqual(codes[:2], ["family-semantic-status", "family-coverage-status"])
                self.assertEqual(family["adoptedKeys"], declared[family["name"]])
                self.assertEqual("family-no-adopted-key" in codes, not family["adoptedKeys"])
                # Each pack's family row splits the adopted keys by the actual
                # entry-review declarations: a declared key is reviewed and
                # legitimately identical, a held identical key stays a
                # placeholder, every other adopted key stays draft; none is missing.
                self.assertEqual([row["productId"] for row in family["products"]], PACK_IDS)
                adopted_set = set(family["adoptedKeys"])
                for row in family["products"]:
                    reviewed = sorted(adopted_set & reviewed_by_pack[row["productId"]])
                    placeholder = sorted(adopted_set
                                         & set(CURRENT_ENGLISH_PLACEHOLDER_KEYS[row["productId"]]))
                    self.assertEqual(row["keys"]["reviewed_legitimately_identical"], reviewed)
                    self.assertEqual(row["keys"]["deliberate_english_placeholder"], placeholder)
                    self.assertEqual(row["keys"]["draft_unreviewed"],
                                     sorted(adopted_set - set(reviewed) - set(placeholder)))
                    for category in ("translated_and_reviewed", "missing", "invalid", "obsolete"):
                        self.assertEqual(row["keys"][category], [], category)
        # Full visible-UI scope: a key with a qualified entry-review declaration
        # is reviewed, so a family's pending set for a pack is its adopted keys
        # minus that pack's declared keys, and a family whose adopted keys are
        # all declared for a pack has no reason for it.
        pending = [(family["name"], pack_id,
                    sorted(set(family["adoptedKeys"]) - reviewed_by_pack[pack_id]))
                   for family in families if family["adoptedKeys"] for pack_id in PACK_IDS]
        self.assertEqual([(r["subject"], r["value"], r["keys"])
                          for r in report_reasons(report, "family-entries-not-reviewed")],
                         [row for row in pending if row[2]])
        # Not vacuous: the declarations do remove adopted keys from some
        # pending sets, and pending keys remain in every adopted family.
        self.assertTrue(any(len(row[2]) < len(declared[row[0]]) for row in pending))
        self.assertTrue(all(row[2] for row in pending))
        adopted = [key for family in families for key in family["adoptedKeys"]]
        shared = sorted(set(full_english_oracle()) - set(adopted))
        self.assertLessEqual({row[0] for row in EXPECTED_KEYS if row[1] == "text"}, set(shared))
        self.assertEqual([row["key"] for row in report["unassignedKeys"]], shared)
        denominator = report["denominator"]
        self.assertEqual((denominator["familyAdoptedKeyReferences"],
                          denominator["distinctFamilyAdoptedKeys"],
                          denominator["keysOnMultipleFamilies"], denominator["keysWithoutFamily"]),
                         (len(adopted), len(set(adopted)), [], shared))
        self.assertEqual(report_reasons(report, "keys-without-family")[0]["keys"], shared)
        surfaces = report["surfaces"]
        self.assertEqual(surfaces["currentAdoptionKeys"], [row[0] for row in CURRENT_KEYS])
        self.assertEqual((surfaces["allWindowSemanticCoverage"], surfaces["visibleTextDenominator"]),
                         ("PENDING", "NOT_ESTABLISHED"))
        self.assertEqual({item["status"] for item in surfaces["otherVisibleCopy"]},
                         {"PENDING_CLASSIFICATION"})
        self.assertEqual(report["reviewGates"],
                         [{"productId": row[0], "gates": REPORT_PENDING_GATES}
                          for row in EXPECTED_PRODUCTS])
        self.assertEqual(report["nativeFacts"]["establishedByThisReport"], "NOT_RUN")
        self.assertEqual(report["completeness"]["state"], "INCOMPLETE")
        self.assertLessEqual(REPORT_REMAINING_REASONS, report_codes(report))
        assert_no_true(self, self.context)
        assert_no_true(self, self.release)

    def test_actual_report_binds_the_exact_physical_input_bytes(self):
        arguments = self.arguments()
        first = self.catalog.catalog_report(*arguments)
        self.assertEqual(self.catalog.catalog_report(*[bytearray(item) for item in arguments]),
                         first)
        names = ("data/LocalizationEnglish.lua", "data/LocalizationPacks.lua",
                 "docs/localization/KEY_CONTEXT.json", "docs/localization/RELEASE_LANGUAGES.json")
        self.assertEqual([row["source"] for row in first["inputs"]], list(names))
        for row, name, data in zip(first["inputs"], names, arguments):
            with self.subTest(name):
                self.assertEqual(data, (ROOT / name).read_bytes())
                self.assertEqual((row["sha256"], row["byteLength"]),
                                 (hashlib.sha256(data).hexdigest(), len(data)))
                if name in CURRENT_REFERENCE_INPUTS:
                    canonical = assert_current_reference_bytes(self, name, data)
                    reference = CURRENT_REFERENCE_INPUTS[name][0]
                    self.assertEqual(row["sha256"] == reference, canonical == data)
                    self.assertNotEqual((row["sha256"], row["byteLength"]),
                                        REFERENCE_ENGLISH_INPUT)
                if name in CHECKOUT_PHYSICAL_INPUTS and name not in REFERENCE_SUCCESSORS:
                    self.assertEqual((row["sha256"], row["byteLength"]),
                                     CHECKOUT_PHYSICAL_INPUTS[name])
                assert_current_successor_identity(self, name, data)
                if "physical" in CURRENT_SUCCESSOR_INPUTS.get(name, {}):
                    self.assertEqual((row["sha256"], row["byteLength"]),
                                     CURRENT_SUCCESSOR_INPUTS[name]["physical"])
        self.assertNotIn("complete", first)
        self.assertEqual({family["state"] for family in first["families"]}, {"INCOMPLETE"})
        self.assertEqual(first["completeness"]["state"], "INCOMPLETE")
        self.assertEqual(first["nativeFacts"]["establishedByThisReport"], "NOT_RUN")
        lowered = json.dumps(first, sort_keys=True).lower()
        for claim in ("release_ready", "releaseready", "release-ready", "100%"):
            self.assertNotIn(claim, lowered)

    def test_actual_data_and_28_key_context_drift_is_rejected(self):
        english = self.catalog.parse_english(self.raw["english"])
        packs = self.catalog.parse_packs(self.raw["packs"])

        def context_with(change):
            context = copy.deepcopy(self.context)
            change(context)
            return context
        drifted = dict(english)
        drifted["panel.heading.progress"] = "Progress"
        removed = dict(english)
        removed.pop("panel.heading.extra_copies")
        marked = dict(english)
        marked["panel.button.options"] = "! Options"
        orphan = copy.deepcopy(packs)
        orphan["frFR"]["entries"]["panel.tooltip.not_in_english"] = "Orphelin"
        cases = (
            ("context English drift", {"context": context_with(
                lambda c: schema_row(c, "panel.heading.progress").update({"english": "PROGRESS "}))},
             "context-english-mismatch"),
            ("source English drift", {"english": drifted}, "context-english-mismatch"),
            ("context row omitted", {"context": context_with(
                lambda c: c["keys"].remove(schema_row(c, "panel.heading.extra_copies")))},
             "context-key-mismatch"),
            ("English key removed", {"english": removed}, "context-key-mismatch"),
            ("Options context row omitted", {"context": context_with(
                lambda c: c["keys"].remove(schema_row(c, "panel.button.options")))},
             "context-key-mismatch"),
            ("Options English with the notice mark", {"english": marked},
             "context-english-mismatch"),
            ("panel key declared as format", {"context": context_with(
                lambda c: schema_row(c, "panel.button.my_builds").update({"kind": "format"}))},
             "context-kind"),
            ("orphan pack entry", {"packs": orphan}, "orphan-entry"),
            ("historical six-key context on the actual data", {"context": historical_context()},
             "context-key-mismatch"),
            ("actual context on the historical six-key data",
             {"english": CATALOG_CURRENT_ENGLISH, "packs": CATALOG_CURRENT_PACKS},
             "context-key-mismatch"),
        )
        for label, parts, code in cases:
            with self.subTest(label):
                with self.assertRaises(self.catalog.CatalogValidationError) as caught:
                    self.catalog.validate_catalog_data(*self.arguments(**parts))
                self.assertEqual(caught.exception.code, code)
        evidence = (
            ("unknown HUD adopted key", lambda c: c["windowFamilies"][0]["adoptedKeys"].append(
                "panel.tooltip.not_in_english"), "family-unknown-key"),
            ("repeated adoption key", lambda c: c["currentAdoption"]["keys"].append(
                "panel.heading.progress"), "adoption-key"),
        )
        for label, change, code in evidence:
            with self.subTest(label):
                with self.assertRaises(self.catalog.CatalogEvidenceError) as caught:
                    self.catalog.catalog_report(*self.arguments(context=context_with(change)))
                self.assertEqual(caught.exception.code, code)

    def test_actual_full_ui_kind_drift_is_rejected(self):
        # Full visible-UI kinds on the actual data: a block or template row
        # must hold complete typed placeholders, a limit inside the runtime
        # schema and an exact lines flag, and each value its kind's contract.
        english = self.catalog.parse_english(self.raw["english"])
        anchor, guide, block_key = ("command.chat.anchor_set", "guide.body.target_c_select",
                                    "command.chat.wishlist_design_hint")
        self.assertEqual([schema_row(self.context, key)["kind"] for key in (anchor, guide, block_key)],
                         ["template", "template", "block"])
        self.assertIs(schema_row(self.context, guide).get("lines"), True)
        self.assertIn("\n", english[block_key])

        def context_with(key, change):
            context = copy.deepcopy(self.context)
            change(schema_row(context, key))
            return context

        def english_with(key, text):
            table = dict(english)
            table[key] = text
            return table
        cases = (
            ("placeholder without meaning", {"context": context_with(
                anchor, lambda row: row["placeholders"][0].pop("meaning"))}, "context-placeholders"),
            ("blank placeholder meaning", {"context": context_with(
                anchor, lambda row: row["placeholders"][0].update({"meaning": " "}))},
             "context-placeholders"),
            ("unknown slot type", {"context": context_with(
                anchor, lambda row: row["placeholders"][0].update({"type": "number"}))},
             "context-placeholders"),
            ("no placeholder", {"context": context_with(
                anchor, lambda row: row.update({"placeholders": []}))}, "context-placeholders"),
            ("limit above the schema", {"context": context_with(
                anchor, lambda row: row.update({"resultLimitBytes": 2049}))}, "context-result-limit"),
            ("limit zero", {"context": context_with(
                anchor, lambda row: row.update({"resultLimitBytes": 0}))}, "context-result-limit"),
            ("lines false", {"context": context_with(guide, lambda row: row.update({"lines": False}))},
             "context-kind"),
            ("lines on a block", {"context": context_with(
                block_key, lambda row: row.update({"lines": True}))}, "context-kind"),
            ("block declared as text", {"context": context_with(
                block_key, lambda row: row.update({"kind": "text"}))}, "invalid-text"),
            ("block with a carriage return", {"english": english_with(
                block_key, english[block_key].replace("\n", "\r\n"))}, "invalid-text"),
            ("block over 1024 bytes", {"english": english_with(block_key, "x" * 1025)},
             "invalid-text"),
            ("static text with a line feed", {"english": english_with(
                "panel.button.options", "Opt\nions")}, "invalid-text"),
            ("template without lines given a line feed", {"english": english_with(
                anchor, "Adaptive Power\npreference set to {spell}")}, "invalid-template"),
            ("template missing its field", {"english": english_with(
                anchor, "Adaptive Power preference set")}, "invalid-template"),
        )
        for label, parts, code in cases:
            with self.subTest(label):
                with self.assertRaises(self.catalog.CatalogValidationError) as caught:
                    self.catalog.validate_catalog_data(*self.arguments(**parts))
                self.assertEqual(caught.exception.code, code)

    def test_coherent_synthetic_key_on_actual_source_derives_every_count(self):
        english = self.catalog.parse_english(self.raw["english"])
        packs = self.catalog.parse_packs(self.raw["packs"])
        context = copy.deepcopy(self.context)
        extra = "panel.synthetic_extra"
        report_add_static(english, context, extra, "Synthetic extra fixture text")
        context["currentAdoption"]["keys"].append(extra)
        context["windowFamilies"][0]["adoptedKeys"].append(extra)
        packs["frFR"]["entries"][extra] = "Texte de fixture synthetique"
        report = self.catalog.catalog_report(*self.arguments(english, packs, context))
        actual = sorted(full_english_oracle())
        keys = sorted(actual + [extra])
        hud = self.context["windowFamilies"][0]["adoptedKeys"]
        distinct = {key for family in self.context["windowFamilies"] for key in family["adoptedKeys"]}
        self.assertEqual(report["englishBaseline"]["keyCount"], len(actual) + 1)
        self.assertEqual(report["denominator"]["englishKeys"], len(keys))
        for row in report["products"]:
            with self.subTest(row["productId"]):
                self.assertEqual((row["denominator"], row["reconciliation"]["inDenominatorTotal"]),
                                 (len(keys), len(keys)))
                draft, declared, placeholder = current_categories(self.release, row["productId"], actual)
                if row["productId"] == "frFR":
                    draft, missing = sorted(draft + [extra]), []
                else:
                    missing = [extra]
                self.assertEqual(row["keys"]["draft_unreviewed"], draft)
                self.assertEqual(row["keys"]["missing"], missing)
                self.assertEqual(row["keys"]["reviewed_legitimately_identical"], declared)
                self.assertEqual(row["keys"]["deliberate_english_placeholder"], placeholder)
                self.assertEqual(row["entriesPresent"],
                                 len(actual) + (1 if row["productId"] == "frFR" else 0))
        self.assertEqual(report["families"][0]["adoptedKeys"], hud + [extra])
        self.assertEqual(report["families"][0]["adoptedKeys"][:len(CURRENT_HUD_ADOPTED_KEYS)],
                         CURRENT_HUD_ADOPTED_KEYS)
        self.assertEqual(report["denominator"]["distinctFamilyAdoptedKeys"], len(distinct) + 1)
        self.assertNotIn(extra, report["denominator"]["keysWithoutFamily"])
        self.assertEqual(report["surfaces"]["currentAdoptionKeys"][-1], extra)
        self.assertEqual(report["completeness"]["state"], "INCOMPLETE")

    def test_actual_root_command_line_reports_every_entry_without_readiness(self):
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        elsewhere = Path(holder.name)
        before = [(ROOT / name).read_bytes() for name in CLI_INPUTS]
        cache = catalog_pycache_names()
        runs = [cli_run(cwd=elsewhere), cli_run("--root", ROOT, cwd=elsewhere),
                cli_run("--root", ROOT, "--require-complete", cwd=elsewhere)]
        self.assertEqual(catalog_pycache_names(), cache)
        self.assertEqual([(ROOT / name).read_bytes() for name in CLI_INPUTS], before)
        self.assertEqual(list(elsewhere.iterdir()), [])
        self.assertEqual(runs[0].stdout, runs[1].stdout)
        expected = self.catalog.catalog_report(*before[:4])
        count = len(full_english_oracle())
        self.assertEqual(count, CURRENT_FULL_UI_KEYS)
        for index, (run, code) in enumerate(zip(runs, (0, 0, 1))):
            with self.subTest(run=index):
                self.assertEqual(run.returncode, code, run.stderr[:500])
                self.assertEqual(run.stderr, b"")
                self.assertTrue(run.stdout.isascii(), run.stdout[:200])
                record = json.loads(run.stdout.decode("ascii"))
                self.assertEqual(run.stdout,
                                 (json.dumps(record, sort_keys=True) + "\n").encode("ascii"))
                self.assertEqual((record["record"], record["exitCode"]), ("report", code))
                self.assertEqual(record["notice"], CATALOG_NOTICE)
                self.assertEqual(record["report"], expected)
                self.assertEqual([row["sha256"] for row in record["report"]["inputs"]],
                                 [hashlib.sha256(data).hexdigest() for data in before[:4]])
                technical = record["technicalCatalog"]
                self.assertEqual((technical["validity"], technical["englishKeys"],
                                  technical["missingEntries"], technical["entryPresence"]),
                                 ("VALID", count, 0, "EVERY_CURRENT_ENGLISH_KEY_PRESENT"))
                self.assertEqual([(row["productId"], row["denominator"], row["entriesPresent"])
                                  for row in technical["products"]],
                                 [(pack_id, count, count) for pack_id in PACK_IDS])
                readiness = record["externalReadiness"]
                self.assertEqual((readiness["state"], readiness["externalAcceptance"],
                                  readiness["reportCompletenessState"]),
                                 ("NOT_ESTABLISHED", "NOT_ATTESTED", "INCOMPLETE"))


# Full visible-UI scope (Refs #143-#148): the input memo of the tool
# (_memoized) keeps a successful parse or strict verdict of exact input bytes,
# because every seam re-parses the 4078-key catalog. These controls are
# causal: any changed byte is a new key (changed file), a kept result is never
# served for other bytes nor changed by a caller (stale cache), a failure is
# never kept, the memo stays bounded (least recently used first out), a kept
# result equals a fresh computation, and every seam leaves the cyclic
# collector as the caller had it. Each test loads its own tool, so its memo
# starts empty.

import inspect

MEMO_LOCALIZATION = ROOT / "core" / "Localization.lua"
MEMO_OPTIONS_LINE = b'["panel.button.options"] = "Options",'


class CatalogInputMemo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = current_raw()
        cls.four = [cls.raw[name] for name in ("english", "packs", "context", "release")]
        cls.five = cls.four + [MEMO_LOCALIZATION.read_bytes()]

    def fresh(self):
        catalog = load_catalog_parser()
        self.assertEqual(catalog._INPUT_MEMO, {})
        return catalog

    def kinds(self, catalog):
        return sorted(key[0] for key in catalog._INPUT_MEMO)

    def test_a_kept_result_is_served_only_for_the_same_exact_bytes(self):
        catalog = self.fresh()
        english = self.raw["english"]
        self.assertEqual(english.count(MEMO_OPTIONS_LINE), 1)
        self.assertEqual(catalog.parse_english(english)["panel.button.options"], "Options")
        self.assertEqual(self.kinds(catalog), ["LocalizationEnglish"])
        changed = english.replace(MEMO_OPTIONS_LINE, MEMO_OPTIONS_LINE.replace(b"Options", b"Optionz"))
        self.assertEqual(catalog.parse_english(changed)["panel.button.options"], "Optionz")
        self.assertEqual(catalog.parse_english(english)["panel.button.options"], "Options")
        self.assertEqual(self.kinds(catalog), ["LocalizationEnglish", "LocalizationEnglish"])
        # The other line-break representation is other bytes: kept apart, equal values.
        lf = english.replace(b"\r\n", b"\n")
        self.assertNotEqual(lf, english)
        self.assertEqual(catalog.parse_english(lf), catalog.parse_english(english))
        self.assertEqual(len(catalog._INPUT_MEMO), 3)
        # A strict verdict: valid, then the one edited byte string refused, then valid again.
        catalog.validate_catalog_data(*self.four)
        bad = english.replace(MEMO_OPTIONS_LINE, MEMO_OPTIONS_LINE.replace(b"Options", b"Opt|ions"))
        for _ in range(2):
            with self.assertRaises(catalog.CatalogValidationError) as raised:
                catalog.validate_catalog_data(bad, *self.four[1:])
            self.assertEqual((raised.exception.code, raised.exception.key),
                             ("invalid-text", "panel.button.options"))
        self.assertEqual(catalog.validate_catalog_data(*self.four)["english"]["panel.button.options"],
                         "Options")
        registry = catalog.validate_registry_catalog_data(*self.five)
        with self.assertRaises(catalog.CatalogRegistryError) as raised:
            catalog.validate_registry_catalog_data(*self.five[:4], self.five[4].replace(
                b'kind = "format", slot = "count", resultLimit = 254',
                b'kind = "format", slot = "count", resultLimit = 253'))
        self.assertEqual((raised.exception.code, raised.exception.key),
                         ("registry-limit", "readout.charge_counts"))
        self.assertEqual(catalog.validate_registry_catalog_data(*self.five), registry)

    def test_a_returned_value_never_changes_a_later_result(self):
        catalog = self.fresh()
        first = catalog.validate_registry_catalog_data(*self.five)
        snapshot = json.dumps(first, sort_keys=True, default=list)
        for result in (first, catalog.validate_registry_catalog_data(*self.five)):
            result["english"]["panel.button.options"] = "poisoned"
            result["keyContext"]["keys"][0]["english"] = "poisoned"
            result["keyContext"]["keys"].pop()
            result["packs"]["frFR"]["entries"].clear()
            result["release"]["products"].clear()
            del result["declarations"]["readout.charge_counts"]
        again = catalog.validate_registry_catalog_data(*self.five)
        self.assertEqual(json.dumps(again, sort_keys=True, default=list), snapshot)
        parsed = catalog.parse_english(self.raw["english"])
        parsed.clear()
        self.assertEqual(len(catalog.parse_english(self.raw["english"])), CURRENT_FULL_UI_KEYS)
        declarations = catalog.parse_registry_declarations(self.five[4])
        declarations["readout.charge_counts"]["kind"] = "text"
        self.assertEqual(catalog.parse_registry_declarations(self.five[4])["readout.charge_counts"]
                         ["kind"], "format")

    def test_an_input_is_frozen_once_before_it_is_hashed_and_parsed(self):
        # V14 review P2: an accepted bytearray subclass whose conversions show
        # other bytes than its buffer. Each seam takes the buffer once and
        # both hashes and parses that copy, so no conversion is consulted and
        # a kept result always belongs to the bytes it is kept for.
        class Shifting(bytearray):
            def __init__(self, data, shown):
                super().__init__(data)
                self.shown = shown

            def __bytes__(self):
                return self.shown

            def decode(self, *arguments, **options):
                return self.shown.decode(*arguments, **options)

        english = self.raw["english"]
        optionz = english.replace(MEMO_OPTIONS_LINE, MEMO_OPTIONS_LINE.replace(b"Options", b"Optionz"))
        catalog = self.fresh()
        self.assertEqual(catalog.parse_english(Shifting(english, optionz))["panel.button.options"],
                         "Options")
        self.assertEqual(catalog.parse_english(english)["panel.button.options"], "Options")
        self.assertEqual(catalog.parse_english(optionz)["panel.button.options"], "Optionz")
        limit = (b'kind = "format", slot = "count", resultLimit = 254',
                 b'kind = "format", slot = "count", resultLimit = 253')
        refused = self.five[4].replace(*limit)
        self.assertNotEqual(refused, self.five[4])
        seams = (("validate_catalog_data", self.four), ("catalog_report", self.four),
                 ("validate_registry_catalog_data", self.five),
                 ("registry_catalog_report", self.five),
                 ("registry_catalog_diagnostics", self.five),
                 ("pack_provenance_diagnostics", self.five))
        shown = {0: optionz, 4: refused}
        for name, ordinary in seams:
            with self.subTest(seam=name):
                catalog = self.fresh()
                seam = getattr(catalog, name)
                shifting = [Shifting(data, shown.get(index, data[:-1]))
                            for index, data in enumerate(ordinary)]
                first = seam(*shifting)
                self.assertEqual(seam(*ordinary), first)
                self.assertEqual(getattr(self.fresh(), name)(*ordinary), first)
                if name.startswith("validate"):
                    self.assertEqual(first["english"]["panel.button.options"], "Options")
                # The bytes it showed are still judged as themselves.
                with self.assertRaises(catalog.CatalogRegistryError) as raised:
                    catalog.validate_registry_catalog_data(*self.five[:4], refused)
                self.assertEqual(raised.exception.code, "registry-limit")

    def test_a_failure_is_never_kept(self):
        catalog = self.fresh()
        syntax = b'Nexus = Nexus or {}\nNexus.LocalizationEnglish = { ["a.b"] = 1 }'
        for _ in range(2):
            with self.assertRaises(catalog.CatalogSyntaxError) as raised:
                catalog.parse_english(syntax)
            self.assertEqual(raised.exception.code, "unexpected-token")
        self.assertEqual(catalog._INPUT_MEMO, {})
        for _ in range(2):
            with self.assertRaises(catalog.CatalogValidationError) as raised:
                catalog.validate_catalog_data(self.four[0], self.four[1], b'{"a": NaN}', self.four[3])
            self.assertEqual(raised.exception.code, "json-nonstandard-constant")
        self.assertNotIn("catalog", self.kinds(catalog))
        # The refused document is not kept, and the release after it is never reached.
        self.assertNotIn("json", self.kinds(catalog))
        for _ in range(2):
            with self.assertRaises(catalog.CatalogRegistryError) as raised:
                catalog.parse_registry_declarations(b"-- no markers\n")
            self.assertEqual(raised.exception.code, "registry-marker")
        self.assertNotIn("declarations", self.kinds(catalog))

    def test_the_memo_is_bounded_least_recently_used_first(self):
        catalog = self.fresh()
        limit = catalog._INPUT_MEMO_LIMIT
        self.assertTrue(type(limit) is int and 1 < limit <= 64)
        source = b'Nexus = Nexus or {}\nNexus.LocalizationEnglish = { ["a.b"] = "Text %d" }'

        def key(index):
            return ("LocalizationEnglish", hashlib.sha256(source % index).digest())
        for index in range(limit):
            catalog.parse_english(source % index)
        self.assertEqual(len(catalog._INPUT_MEMO), limit)
        self.assertEqual(catalog.parse_english(source % 0), {"a.b": "Text 0"})  # refreshed
        catalog.parse_english(source % limit)
        self.assertEqual(len(catalog._INPUT_MEMO), limit)
        self.assertIn(key(0), catalog._INPUT_MEMO)
        self.assertNotIn(key(1), catalog._INPUT_MEMO)
        self.assertIn(key(limit), catalog._INPUT_MEMO)
        self.assertEqual(catalog.parse_english(source % 1), {"a.b": "Text 1"})  # parsed afresh

    def test_a_kept_result_equals_a_fresh_computation(self):
        warm = self.fresh()
        warm.validate_registry_catalog_data(*self.five)
        warm.catalog_report(*self.four)
        hit = warm.validate_registry_catalog_data(*self.five)
        cold = self.fresh().validate_registry_catalog_data(*self.five)
        self.assertEqual(hit, cold)
        for name in ("english", "packs", "declarations"):
            self.assertEqual(list(hit[name]), list(cold[name]), name)
        self.assertIs(type(hit["declarations"]["readout.charge_counts"]["fields"]), tuple)
        self.assertEqual(warm.catalog_report(*self.four), self.fresh().catalog_report(*self.four))

    def test_every_seam_leaves_the_collector_as_it_was(self):
        import gc
        catalog = self.fresh()
        bad = self.four[0].replace(MEMO_OPTIONS_LINE, MEMO_OPTIONS_LINE.replace(b"Options", b"|"))
        calls = ((catalog.validate_catalog_data, self.four), (catalog.catalog_report, self.four),
                 (catalog.validate_registry_catalog_data, self.five),
                 (catalog.registry_catalog_report, self.five),
                 (catalog.registry_catalog_diagnostics, self.five),
                 (catalog.pack_provenance_diagnostics, self.five),
                 (catalog.validate_catalog_data, [bad] + self.four[1:]))
        for enabled in (True, False):
            for seam, arguments in calls:
                with self.subTest(enabled=enabled, seam=seam.__name__):
                    (gc.enable if enabled else gc.disable)()
                    try:
                        try:
                            seam(*arguments)
                        except catalog.CatalogValidationError:
                            pass
                        self.assertIs(gc.isenabled(), enabled)
                    finally:
                        gc.enable()
        self.assertEqual([seam.__name__ for seam, _ in calls[:6]],
                         ["validate_catalog_data", "catalog_report",
                          "validate_registry_catalog_data", "registry_catalog_report",
                          "registry_catalog_diagnostics", "pack_provenance_diagnostics"])
        self.assertEqual(list(inspect.signature(catalog.validate_catalog_data).parameters),
                         ["english_source", "packs_source", "key_context_json", "release_json"])


if __name__ == "__main__":
    unittest.main()
