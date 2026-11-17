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

S7 adds the required-CI check of the current per-pack provenance records of
RELEASE_LANGUAGES.json through pack_provenance_diagnostics: the real UNKNOWN
records are technically valid with support held, while malformed and stale
variants of the real bytes are refused.

S8 adds the required-CI static consumer binding of the current repository
through consumer_binding_report: the real registry inputs, both TOCs and every
Lua file they load bind all 28 declared keys (23 direct, 5 mapped) with no
problem, each counted site with a proven output, and in-memory mutants of
the real bytes (a removed last consumer with fakes retained, a broken map
chain, a wrong method kind, a TOC or source omission, hash drift and path
collisions) fail the same gate. Review fix 1 adds discarded, overwritten,
compared and unused-helper results, review fix 2 a dispatcher overwritten
through a module alias, and review fix 3 the closed two-TOC contract. The
V15 review fixes add trusted globals, string library fields and the global
environment replaced by any route (C27), format arguments that are never
shown (C28), definitions an initializer never runs at load (C29) and the
digest-cache and parse-memo byte bounds (StateBoundTests).

Shared non-test support of the registry test files (Refs #147). The single file
tools/tests/test_l10n_registry.py was split into five registered test files so that each runs
under the whole-file limit. This module holds every top-level statement of that file other
than its test classes, its docstring and its main block, verbatim and in order, plus two
members moved out of test classes verbatim: provenance_blocked_calls (the body of
ProvenanceTests.blocked_calls) and _ConsumerBindingMixin (the setUpClass and helper methods
of ConsumerBindingTests). It defines no TestCase and no test, and is not a test_*.py file.
Each test file loads it once per process and binds every name it defines. Synthetic offline
evidence only: no Lua runs. Python 3.9+, standard library only.
"""

import ast
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
# Full visible-UI scope (#143-#148): the reviewed catalog declares 4096 keys
# (the bounded runtime limit is 5120), the dated 28 above first and
# unchanged. The full key order and each row's kind, slot types, limit and
# lines flag are read from KEY_CONTEXT.json with the json module, apart from
# the tool under test.
# v33 slice A: exact 35 (ea812b41) declares and holds 4096 English meanings.
# KEY_CONTEXT.json has 4078 rows, without the 18 SLICE_A_LEGACY_ROWS below.
# Slice A adds those rows and no meaning, so 4096 is the count after A. Until
# then full_context_rows() reports the real gap. RUNTIME_CAP is an
# independent restatement of the bounded limit (not read from the tool): 5120
# declarations parse and 5121 are refused (registry-too-many). A tool still at
# 4096 refuses the 5120-declaration block.
# v39 (B/C RED): the 20 accepted new meanings (SLICE_BC_NEW_ROWS below) are
# appended after the 4096, so the catalog declares 4116; the bounded limit
# stays 5120 (not patched for the features).
CURRENT_FULL_UI_KEYS = 4116
RUNTIME_CAP = 5120
# v39 (B/C): the 20 accepted new meanings, an independent oracle restated from
# the v33 PLAN newKeys20 (opacity: the v23 Theme reference; FAQ: FAQ_DRAFT r3).
# Each row: key, kind, exact English, (field, slot type) pairs in declared
# order, result limit (None for text and block). They are the LAST 20
# declarations, English entries and context rows, in this order.
SLICE_BC_NEW_ROWS = (
    ("theme.menu.opacity_choice", "template", "Background opacity: {percent}%",
     (("percent", "count"),), 256),
    ("theme.menu.opacity_default", "text", "Background opacity: 100% (default)", (), None),
    ("theme.menu.unknown_opacity", "template",
     "Saved background opacity \"{value}\" is not in this build; it stays saved.",
     (("value", "text"),), 256),
    ("theme.tooltip.opacity", "text",
     "Changes only how see-through Nexus window backgrounds are; text, buttons and the difficulty "
     "card stay solid. 100% is the default look and clears the choice.", (), None),
    ("help.label.faq_echo_not_counted_question", "text",
     "Why doesn't an Echo I can see count for my Wishlist?", (), None),
    ("help.body.faq_echo_not_counted_answer", "block",
     "A target is one exact Echo at one exact quality. A lower-quality copy does not count for a "
     "higher-quality target; on the panel, an offer at another quality can show Wrong quality. An "
     "Echo your Wishlist does not ask for never counts. Only copies you have count, up to the copies "
     "the plan asks for; locked copies count only up to its locked targets. Copies above a target "
     "are extras. See the Wishlists tab above.", (), None),
    ("help.label.faq_orb_start_maximum_question", "text",
     "Does Auto ON start an Orb run, and what is the maximum?", (), None),
    ("help.body.faq_orb_start_maximum_answer", "block",
     "No. Auto never starts an Orb run. A run starts only when you open Orbs, check the maximum and "
     "click Start; starting it turns ordinary Automation off and does not turn it back on. The "
     "maximum is a limit, not a goal. Nexus uses one Orb per replacement and stops when your rolled "
     "targets are complete, so it can use fewer. Orbs used counts spent Orbs against the maximum, "
     "which does not change during a run. Until you type an amount, it follows your confirmed Orb "
     "balance, up to 1000.", (), None),
    ("help.label.faq_orb_blocked_question", "text",
     "Why can't I start an Orb run, or why did it stop early?", (), None),
    ("help.body.faq_orb_blocked_answer", "block",
     "Open the Orb window: it shows what is blocked, then what you can do now. An Orb action "
     "without a confirmed result blocks new runs until it settles, or until you use Continue... "
     "where it is offered. A run ends when your rolled targets are complete or no safe source is "
     "left. Changing the active loadout, assignment or targets pauses it. Orb mode never changes "
     "locked Echo slots. A reload does not settle an unknown result. Do not clear saved data. See "
     "the Orbs tab above.", (), None),
    ("help.label.faq_auto_replace_build_question", "text",
     "Can Auto replace a Saved Build that has Echoes I value?", (), None),
    ("help.body.faq_auto_replace_build_answer", "block",
     "Yes, while Auto is ON. After a finished run, Nexus may save it over your active Saved Build "
     "when overall Wishlist progress is higher, or equal with cleanup. It counts Wishlist progress, "
     "not Orbs spent, so an Echo you got with Orbs can be lost. At level 80 after a finished run, "
     "turning Auto ON or changing the assigned Wishlist can lead to a replacement without a new run. "
     "Saving edits to the assigned Wishlist can also lead to a replacement without a new run. Nexus "
     "cannot undo a save, and Unassign does not restore a Saved Build. There is no separate "
     "automatic-save switch: keep Auto OFF to leave it unchanged.", (), None),
    ("help.label.faq_hidden_panel_reload_question", "text",
     "Does a hidden panel stay hidden after a reload?", (), None),
    ("help.body.faq_hidden_panel_reload_answer", "block",
     "Yes. Hide Nexus Panel is saved as your choice, so the panel stays hidden after a reload or "
     "login. Type /nexus panel to show it again. If Nexus's saved data is read-only, the choice lasts "
     "this session only. Hiding changes no Auto setting.", (), None),
    ("help.label.faq_library_empty_question", "text", "Why is the Build Library empty?", (), None),
    ("help.body.faq_library_empty_answer", "block",
     "Check the scope: All Shared, or Mine (your Saved Builds and shared listings). The class button "
     "can limit the list to your current class; click it to switch between your class and all "
     "classes. Require both DPS records lists only builds with both a Training Dummy and a Lich King "
     "record this client holds; uncheck it to drop that requirement. Updating results... means a "
     "filter change is still applying, and a gray Explore control means shared views are loading or "
     "unavailable (/nexus loading). The list shows only what this client has stored. See the Sharing "
     "tab above.", (), None),
    ("help.label.faq_before_reload_question", "text",
     "Something went wrong. What do I do before a reload?", (), None),
    ("help.body.faq_before_reload_answer", "block",
     "Do not reload, relog or change builds first. Type /nexus report, click Copy summary and paste "
     "it into your report. Add your exact build (/nexus update shows it), what happened versus what "
     "you expected, and Auto ON or OFF. If reporting fails or says Not prepared, say so and send what "
     "you have. Never post the report file in public. See the Problems tab above.", (), None),
    ("help.label.faq_random_roll_leveling_question", "text",
     "Can Nexus pick Echoes while I level without a Wishlist?", (), None),
    ("help.body.faq_random_roll_leveling_answer", "block",
     "Yes, with Random Roll, an optional mode. Type /nexus leveling on or /nexus leveling off; "
     "/nexus leveling alone shows whether it is ON or OFF. It picks only when no Wishlist is "
     "assigned, at levels 2 to 79, with Auto ON and its Take permission allowed. Turning it on does "
     "not turn Auto ON. It takes the highest-rarity Echo offered (the first offer on a tie), not a "
     "random one. If an offer's rarity is unknown, it waits: pick by hand. It never rerolls, "
     "banishes, freezes, spends, saves or uses Orbs, and it makes no new pick at level 80. An "
     "assigned Wishlist always uses the normal rules instead.", (), None),
)
# v33 slice A: the 18 meanings that are declared and in English at exact 35
# but have no KEY_CONTEXT.json row (CONTEXT_SHAPE.json legacyMissingKeys).
# Independent oracle of their declarations, restated from the reviewed block
# of core/Localization.lua at ea812b41 (lines 414-416, 1238-1240, 1271-1273,
# 2426-2427, 2467, 2495, 2789, 4077, 4117, 4166-4167): kind, then for a
# template its (field, slot type) pairs in declared order and result limit.
SLICE_A_LEGACY_ROWS = (
    ("command.chat.reference_random_roll", "template",
     (("command", "text"), ("rule", "text"), ("limits", "text")), 720),
    ("command.chat.reference_random_roll_limits", "text", (), None),
    ("command.chat.reference_random_roll_rule", "text", (), None),
    ("readout.body.scope_random_roll", "template",
     (("value", "text"), ("rule", "text"), ("limits", "text"), ("command", "text")), 816),
    ("readout.body.scope_random_roll_limits", "text", (), None),
    ("readout.body.scope_random_roll_rule", "text", (), None),
    ("readout.menu.random_roll", "template",
     (("value", "text"), ("rule", "text"), ("limits", "text")), 657),
    ("readout.menu.random_roll_limits", "text", (), None),
    ("readout.menu.random_roll_rule", "text", (), None),
    ("panel.button.hub_builds", "text", (), None),
    ("panel.button.hub_wishlist", "text", (), None),
    ("panel.heading.your_offers", "text", (), None),
    ("panel.label.offer_wrong_quality", "text", (), None),
    ("panel.value.wishlist_rarity_mode", "template", (("state", "text"),), 256),
    ("editor.button.rarity_mode", "text", (), None),
    ("editor.chat.manage_restored_from_first_run", "template",
     (("name", "text"), ("slot", "text"), ("state", "text")), 2048),
    ("editor.menu.rarity_mode", "text", (), None),
    ("editor.menu.rarity_mode_state", "template", (("state", "text"),), 256),
)


def full_context_rows():
    """The KEY_CONTEXT.json rows of the current source, in order; the dated
    28 must be first."""
    rows = json.loads((ROOT / INPUTS[2]).read_text(encoding="utf-8"))["keys"]
    if [row["key"] for row in rows[:len(CURRENT_KEYS)]] != list(CURRENT_KEYS) \
            or len(rows) != CURRENT_FULL_UI_KEYS:
        raise AssertionError("the context rows are not the dated 28 then the full catalog")
    return rows


def full_keys():
    return [row["key"] for row in full_context_rows()]


def row_edit(data, key, old, new):
    """KEY_CONTEXT bytes (LF) with old replaced by new exactly once inside the
    row of key, every other byte kept."""
    anchor = b'"key": "%s",' % key.encode()
    if data.count(anchor) != 1:
        raise AssertionError("expected exactly one row %s" % key)
    start = data.index(anchor)
    end = data.index(b"\n    }", start)
    row = data[start:end]
    if row.count(old) != 1:
        raise AssertionError("expected exactly one %r in row %s" % (old, key))
    return data[:start] + row.replace(old, new) + data[end:]
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


def cli_process(*args):
    """The command line as a real process, the repository root as its working
    directory."""
    return subprocess.run([sys.executable, "-B", str(CATALOG_TOOL), *[str(a) for a in args]],
                          capture_output=True, cwd=str(ROOT))


def cli_in_process(*args):
    """main() of the shared loaded tool (s8_catalog) in this process, with
    the exact stdout and stderr bytes it writes and its exit status. Each
    command-line class keeps one real process run that must equal it."""
    import io
    out, err = io.TextIOWrapper(io.BytesIO()), io.TextIOWrapper(io.BytesIO())
    saved = sys.stdout, sys.stderr
    sys.stdout, sys.stderr = out, err
    try:
        code = s8_catalog().main([str(arg) for arg in args])
    finally:
        sys.stdout, sys.stderr = saved
    return subprocess.CompletedProcess(args, code, out.buffer.getvalue(), err.buffer.getvalue())


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


# S7 (Refs #147): per-pack provenance metadata and the opt-in provenance
# receipt. The real records hold UNKNOWN facts; every DECLARED record below is
# a synthetic in-memory edit of the real bytes and is not rights, authorship
# or drafting-history evidence. No URL is fetched.
OPTIONAL_IDS = ("frFR", "deDE", "esES", "plPL", "ptBR", "ruRU")
FACTS = ("authorship", "attribution", "rightsStatement", "importedCorpus")
BASIS = "exact-supplied-english-bytes"
EXPECTED_PROVENANCE_CODES = (
    "provenance-contract", "provenance-structure", "provenance-field",
    "provenance-unknown-product", "provenance-duplicate-product", "provenance-missing-product",
    "provenance-status", "provenance-reason", "provenance-value", "provenance-reference",
    "provenance-basis", "provenance-hash-format", "provenance-stale",
)
# The historical document-level declarations of the accepted predecessor
# 83417bc, kept verbatim; they never fill a per-pack fact.
HISTORICAL_LINEAGE = {
    "kind": "independently_drafted_nexus_presentation_text",
    "newHumanRightsAttestation": "none",
    "importedCorpus": "none",
    "excludedSources": ["another addon's translation corpus", "game client text",
                        "player or private client content"],
}
HISTORICAL_PACK_REVIEW = (
    "data/LocalizationPacks.lua states that the pack wording was drafted and has had a "
    "technical review only, and that no competent human reviewer of each language has "
    "accepted it. No reviewer identity or date is recorded, so no review record is entered "
    "here.")
SYNTHETIC_REFERENCE = "https://example.invalid/synthetic-provenance"


def fact_pattern(product_id, fact):
    """The one-line fact object of one provenance record in the release bytes."""
    return re.compile(rb'("productId": "' + product_id.encode() + rb'",'
                      rb'(?:\r?\n {8}"[A-Za-z]+": \{[^{}\r\n]*\},)*?\r?\n {8}"'
                      + fact.encode() + rb'": )(\{[^{}\r\n]*\})(,?)')


def with_fact(release, product_id, fact, value):
    """release with only the fact object of one record replaced by the JSON of
    value; every other byte is kept."""
    pattern = fact_pattern(product_id, fact)
    found = list(pattern.finditer(release))
    if len(found) != 1:
        raise AssertionError("expected exactly one %s.%s" % (product_id, fact))
    start, end = found[0].span(2)
    text = json.dumps(value, ensure_ascii=False).encode("utf-8")
    return release[:start] + text + release[end:]


def without_fact_line(release, product_id, fact):
    """release without the whole line of one fact (not the last of a record),
    in whichever line break it uses."""
    found = list(fact_pattern(product_id, fact).finditer(release))
    if len(found) != 1 or found[0].group(3) != b",":
        raise AssertionError("expected exactly one inner %s.%s" % (product_id, fact))
    start = release.rindex(b"\n", 0, found[0].start(2))
    start -= 1 if release[start - 1:start] == b"\r" else 0
    return release[:start] + release[found[0].end(3):]


def with_record_id(release, product_id, new_id):
    """release with the productId of one provenance record replaced."""
    old = re.compile(rb'"productId": "' + product_id.encode() + rb'",(?=\r?\n {8}"englishBase")')
    if len(old.findall(release)) != 1:
        raise AssertionError("expected exactly one record %s" % product_id)
    return old.sub(b'"productId": ' + json.dumps(new_id).encode() + b",", release)


def with_provenance(release, change):
    """release re-encoded with change applied to its packProvenance member
    (structural controls only)."""
    document = json.loads(release.decode("utf-8"))
    change(document)
    return json.dumps(document, ensure_ascii=False, indent=2).encode("utf-8")


def declared_base(digest, **extra):
    record = {"status": "DECLARED", "algorithm": "SHA-256", "basis": BASIS, "sha256": digest,
              "evidenceReference": SYNTHETIC_REFERENCE}
    record.update(extra)
    return record


def declared_fact(value, **extra):
    record = {"status": "DECLARED", "value": value, "evidenceReference": SYNTHETIC_REFERENCE}
    record.update(extra)
    return record


def assert_current_provenance(test, catalog, inputs):
    """The required-CI gate on the current repository metadata: technically
    valid, every declared base still matching, every pack held. Returns the
    receipt."""
    receipt = catalog.pack_provenance_diagnostics(*inputs)
    test.assertIs(receipt["valid"], True, receipt["metadata"]["problems"])
    test.assertEqual(receipt["catalogVerdict"], {"result": "valid"})
    test.assertEqual((receipt["metadata"]["technicalValidity"], receipt["metadata"]["problems"]),
                     ("VALID", []))
    test.assertEqual([row["productId"] for row in receipt["packs"]], list(OPTIONAL_IDS))
    test.assertEqual(receipt["baseRelations"]["STALE"], 0)
    for row in receipt["packs"]:
        test.assertIn(row["englishBase"]["relation"], ("UNKNOWN", "MATCHED"))
        test.assertEqual((row["attestedFacts"], row["supportEligibility"]),
                         ("NOT_ESTABLISHED", "HELD"))
    test.assertEqual((receipt["attestedFacts"], receipt["supportEligibility"]),
                     ("NOT_ESTABLISHED", "HELD"))
    test.assertIs(receipt["completeness"]["established"], False)
    return receipt


# S8 (Refs #147): static consumer binding. The gate reads the real registry
# inputs, both TOCs and every Lua file they load; every mutant below is an
# in-memory edit of those real bytes and is never written to the checkout.
CONSUMER_TOCS = ("Nexus.toc", "companion/NexusSupport/NexusSupport.toc")
MAPPED_KEYS = CURRENT_KEYS[:5]
DIRECT_KEYS = CURRENT_KEYS[5:]
HUD_FAMILY = "Main panel (HUD)"
DISPATCHER = "Nexus.UserText.Message"
EXPECTED_CONSUMER_CODES = (
    "consumer-input-structure", "consumer-path", "consumer-duplicate-path",
    "consumer-hash-mismatch", "consumer-length-mismatch", "consumer-toc-required",
    "consumer-toc-unknown", "consumer-toc-not-utf8", "consumer-toc-entry", "consumer-toc-duplicate",
    "consumer-source-missing", "consumer-source-unlisted", "consumer-registry-unloaded",
    "consumer-registry-order", "consumer-registry-conflict",
)
EXPECTED_BINDING_PROBLEM_CODES = (
    "binding-unparsed", "binding-unbound", "binding-orphan", "binding-kind",
    "binding-unresolved", "binding-mutation",
)
PANEL, READOUT, USER_TEXT = "ui/Panel.lua", "ui/Readout.lua", "core/UserText.lua"
# LocalizedReason's consumer call and the two lines after it, the one place in
# core/UserText.lua that holds them (Say and SeamReason share its first line).
LOCALIZED_REASON_CALL = (b'local text,source=localization.Text(key,englishPack)\n'
                         b'        if type(text)=="string" and text~="" then\n'
                         b'            if source=="unavailable" then return text.." "..T.Details(code) end')
PROGRESS_CALL = b'progressLabel:SetText((Nexus.Localization.Text("panel.heading.progress")))'
# The progress label loses its only consumer. A long comment, a string
# holding the call text, an unrelated object with a Text method, a local
# Nexus with a Text method, a Has query, a data table and a closing short
# comment keep the key literal on the same line, so no line number moves.
PROGRESS_FAKE_CODE = (
    b'progressLabel:SetText("Progress")'
    b' --[[ Nexus.Localization.Text("panel.heading.progress") ]]'
    b' local fakeCall = \'Nexus.Localization.Text("panel.heading.progress")\''
    b' local Other = {Text = tostring}; Other.Text("panel.heading.progress")'
    b' do local Nexus = {Localization = {Text = tostring}}; Nexus.Localization.Text("panel.heading.progress") end'
    b' local known = Nexus.Localization.Has("panel.heading.progress")'
    b' local data = {["panel.heading.progress"] = "Progress"}')
PROGRESS_FAKE_COMMENT = b' -- Nexus.Localization.Text("panel.heading.progress")'
PROGRESS_FAKES = PROGRESS_FAKE_CODE + PROGRESS_FAKE_COMMENT


def edit(data, old, new):
    """data with its one occurrence of old replaced by new. The match runs on
    the LF form of data, and the result keeps the line breaks of data (LF or
    CRLF), so one edit serves both representations."""
    lf = data.replace(b"\r\n", b"\n")
    crlf = lf != data
    if crlf and b"\n" in data.replace(b"\r\n", b""):
        raise AssertionError("mixed line breaks")
    result = replace_once(lf, old, new)
    return result.replace(b"\n", b"\r\n") if crlf else result


def toc_listing(toc, data):
    """Independent oracle: the Lua paths one TOC loads, in order."""
    base = toc.rpartition("/")[0]
    paths = []
    for line in data.decode("utf-8", "replace").splitlines():
        entry = line.strip()
        if entry and not entry.startswith("#"):
            paths.append((base + "/" if base else "") + entry.replace("\\", "/"))
    return paths


def current_files():
    """The exact physical bytes of the five registry inputs, both TOCs and
    every Lua file the TOCs load, keyed by repository path."""
    files = {path: (ROOT / path).read_bytes() for path in INPUTS + CONSUMER_TOCS}
    for toc in CONSUMER_TOCS:
        for path in toc_listing(toc, files[toc]):
            files[path] = (ROOT / path).read_bytes()
    return files


def record(path, data):
    return {"path": path, "sha256": hashlib.sha256(data).hexdigest(),
            "byteLength": len(data), "data": data}


def binding_args(files, omit=(), extra=()):
    """The seven arguments of consumer_binding_report for files: the five
    registry inputs, a record per TOC and a record per loaded Lua file
    (except omit, plus the extra (path, bytes) records)."""
    tocs = [record(path, files[path]) for path in CONSUMER_TOCS if path in files]
    sources = [record(path, files[path]) for toc in CONSUMER_TOCS if toc in files
               for path in toc_listing(toc, files[toc]) if path in files and path not in omit]
    sources += [record(path, data) for path, data in extra]
    return [files[path] for path in INPUTS] + [tocs, sources]


def with_file(files, path, data):
    changed = dict(files)
    changed[path] = data
    return changed


def assert_current_bindings(test, catalog, args):
    """The registered binding gate over the receipt of args, through the
    test's own report seam (the cohort view for the rule controls)."""
    report = getattr(test, "report", catalog.consumer_binding_report)
    return assert_binding_receipt(test, report(*args))


# Full visible-UI scope (Source25 continuation). The registered gate is
# assert_binding_receipt(full=True) over the real repository: every one of
# the declared keys (the dated 28 first, with their pilot classes) has a
# genuine static consumer and nothing is unresolved, orphaned or mismatched.
# The binder's rule controls (C3 onward) judge the dated 28, the cohort whose
# consumers, dispatch and outputs these controls were written for, on a
# real-bytes cohort substrate: the five registry inputs, both product TOCs
# (Nexus.toc keeping only the lines of the files below) and the exact bytes
# of every file a control edits or that carries a dated-28 consumer, map
# chain or output. On it the dated 28 bind exactly as on the full repository
# (the same classes, sites, outputs and single map chain) and nothing else
# is a problem except other keys left without a consumer there. cohort_view
# restricts a receipt to the dated 28 and drops only those binding-unbound
# problems of other keys; every other problem (orphan, kind, unresolved,
# mutation, unparsed) stays, so each rule control still fails for its own
# reason. The full-repository gate itself is never judged through the view.
COHORT_SOURCES = (USER_TEXT, READOUT, PANEL, "core/Main.lua", "core/SessionPause.lua",
                  "core/WishlistController.lua", "ui/JournalTab.lua", "ui/WishlistEditor.lua")
_S8_COHORT_FILES = []


def s8_cohort_files():
    """The real-bytes cohort substrate (see above), read once (callers copy)."""
    if not _S8_COHORT_FILES:
        files = s8_files()
        wanted = set(INPUTS) | set(COHORT_SOURCES)
        toc = b"".join(line for line in files["Nexus.toc"].splitlines(True)
                       if not line.strip() or line.strip().startswith(b"#")
                       or line.strip().replace(b"\\", b"/").decode("utf-8") in wanted)
        companion = set(toc_listing(CONSUMER_TOCS[1], files[CONSUMER_TOCS[1]]))
        cohort = {path: data for path, data in files.items()
                  if path in wanted or path in CONSUMER_TOCS or path in companion}
        cohort["Nexus.toc"] = toc
        _S8_COHORT_FILES.append(cohort)
    return dict(_S8_COHORT_FILES[0])


_S8_SETTLED = []


def s8_settle_memo(catalog, files):
    """Once per test process: parse the real repository into the shared
    tool's memo (one receipt, discarded), then move every object alive now
    into the collector's permanent generation (gc.freeze). Later cyclic
    collections then skip the long-lived memoized syntax trees instead of
    rescanning millions of them; garbage made afterwards is still collected,
    and the collector's enabled state (checked by C12) is unchanged. A test
    process memory measure only: no receipt depends on it."""
    if not _S8_SETTLED:
        import gc
        catalog.consumer_binding_report(*binding_args(files))
        gc.freeze()
        _S8_SETTLED.append(True)


def cohort_view(receipt):
    """The dated-28 view of a receipt (see above): its rows and counts for the
    dated 28 only, without the binding-unbound problems of other keys."""
    cohort = set(CURRENT_KEYS)
    view = dict(receipt)
    view["keys"] = [row for row in receipt["keys"] if row["key"] in cohort]
    view["problems"] = [problem for problem in receipt["problems"]
                        if problem["code"] != "binding-unbound" or problem.get("key") in cohort]
    view["valid"] = not view["problems"]
    counts = dict(receipt["counts"])
    rows = view["keys"]
    counts.update({
        "keys": len(rows),
        "DIRECT_LITERAL_CONSUMER": sum(1 for row in rows if row["binding"] == "DIRECT_LITERAL_CONSUMER"),
        "MAPPED_TO_CONSUMER": sum(1 for row in rows if row["binding"] == "MAPPED_TO_CONSUMER"),
        "UNBOUND": sum(1 for row in rows if row["binding"] == "UNBOUND"),
        "sites": sum(len(row["sites"]) for row in rows),
        "unprovenSites": sum(len(row["unprovenSites"]) for row in rows),
        "problems": len(view["problems"])})
    view["counts"] = counts
    return view


def assert_binding_receipt(test, receipt, full=False):
    """The gate itself: every declared key (full: of the real repository; else
    the dated 28 of the cohort view) has a genuine static consumer of the
    expected class, nothing is unresolved, orphaned or mismatched, the mapped
    reasons reach their exported dispatcher, and family declarations stay
    apart from binding."""
    test.assertEqual(receipt["problems"], [])
    test.assertIs(receipt["valid"], True)
    rows = {row["key"]: row for row in receipt["keys"]}
    expected = dict.fromkeys(MAPPED_KEYS, "MAPPED_TO_CONSUMER")
    expected.update(dict.fromkeys(DIRECT_KEYS, "DIRECT_LITERAL_CONSUMER"))
    if full:
        test.assertEqual([row["key"] for row in receipt["keys"]], full_keys())
        test.assertEqual({key: rows[key]["binding"] for key in CURRENT_KEYS}, expected)
        test.assertEqual(receipt["counts"]["UNBOUND"], 0)
    else:
        test.assertEqual([row["key"] for row in receipt["keys"]], list(CURRENT_KEYS))
        test.assertEqual({key: row["binding"] for key, row in rows.items()}, expected)
        test.assertEqual((receipt["counts"]["DIRECT_LITERAL_CONSUMER"],
                          receipt["counts"]["MAPPED_TO_CONSUMER"], receipt["counts"]["UNBOUND"]),
                         (23, 5, 0))
    for key in DIRECT_KEYS:
        test.assertTrue({site["site"] for site in rows[key]["sites"]}
                        & {"direct-call", "wrapper-call"}, key)
        test.assertEqual(rows[key]["family"]["state"], "DECLARED")
        test.assertEqual([family["name"] for family in rows[key]["family"]["families"]],
                         [HUD_FAMILY])
    for key in MAPPED_KEYS:
        test.assertEqual({site["site"] for site in rows[key]["sites"]}, {"map-value"})
        test.assertEqual(rows[key]["family"], {
            "state": "UNCLASSIFIED", "families": [],
            "familySurface": ("PENDING: shared reason text; the families and surfaces "
                              "that show it are not classified")})
    # Review fix 1 (SPEC-147-S8-1): a counted site is one whose localization
    # result reaches an output, never merely a call location.
    for row in receipt["keys"]:
        for site in row["sites"]:
            test.assertTrue(site["outputs"], (row["key"], site))
    chain = map_chain(test, receipt, "LocalizedReason")
    if not full:
        # The real core/UserText.lua has exactly two map chains: the dated
        # mapped reasons and the reasons table's keys (reasonKeys, below).
        test.assertEqual(len(receipt["mapChains"]), 2)
    test.assertEqual((chain["wrapper"]["name"], chain["wrapper"]["method"],
                      chain["dispatcher"]), ("LocalizedReason", "Text", DISPATCHER))
    test.assertEqual((chain["established"], chain["wrapperReturnsResult"]), (True, True))
    test.assertTrue(chain["outputs"])
    test.assertEqual(sorted(chain["boundKeys"]), sorted(MAPPED_KEYS))
    # The second real chain: T.Message's first dispatch, guarded by the
    # parallel reasons table, through SeamReason (seam accessor wrapper).
    second = map_chain(test, receipt, "SeamReason")
    test.assertEqual((second["map"]["name"], second["map"]["path"], second["wrapper"]["method"],
                      second["dispatcher"], second["entries"]),
                     ("reasonKeys", USER_TEXT, "Text", DISPATCHER, 39))
    test.assertEqual((second["established"], second["wrapperReturnsResult"]), (True, True))
    test.assertEqual(second["shadowedEntries"], [])
    test.assertEqual(sorted(second["boundKeys"]), sorted(REASON_KEYS))
    test.assertEqual(chain_outputs(second), chain_outputs(chain))
    return receipt


def map_chain(test, receipt, wrapper):
    """The one map chain of receipt dispatched by Nexus.UserText.Message
    through this wrapper (a stable identity, never a list position)."""
    chains = [chain for chain in receipt["mapChains"]
              if chain["dispatcher"] == DISPATCHER and chain["wrapper"]["name"] == wrapper]
    test.assertEqual(len(chains), 1, wrapper)
    return chains[0]


def chain_outputs(chain):
    return {(output["path"], output["output"]) for output in chain["outputs"]}


# The 36 distinct keys the 39 entries of core/UserText.lua's reasonKeys name
# (reason.wait_echo_data three times, reason.take_needed twice).
REASON_KEYS = (
    "reason.wait_echo_data", "reason.no_wishlist_advisor", "reason.assign_wishlist_targets",
    "reason.wait_remaining_choice_count", "reason.orb_active_or_unconfirmed",
    "reason.orb_state_not_confirmed", "reason.orb_state_unreadable",
    "reason.orb_state_unexposed", "reason.orb_knownness_unreported", "reason.orb_offer_active",
    "reason.take_needed", "reason.take_available", "reason.freeze_needed_before_search",
    "reason.banish_find_targets", "reason.reroll_no_requested", "reason.reroll_none_needed",
    "reason.take_outside_wishlist", "reason.take_outside_no_search",
    "reason.complete_take_outside", "reason.freeze_one_needed",
    "reason.banish_unneeded_before_reroll", "reason.take_held_needed",
    "reason.wishlist_unusable", "reason.saved_build_invalid", "reason.library_preparing",
    "reason.record_key_unsupported", "reason.shared_data_preparing",
    "reason.removing_expired_requests", "reason.wait_send_rate",
    "reason.guaranteed_offer_marked", "reason.no_guarantee_after_activate",
    "reason.reroll_unneeded_guaranteed", "reason.few_selections_remain",
    "reason.use_shown_offer", "term.echo_availability_controls",
    "reason.safety_disablements_cleared",
)
# The twelve literal keys that T.Message returns directly through Say or SayF
# (seam accessor wrappers), in file order.
MESSAGE_KEYS = (
    "usertext.status.disabling_control", "usertext.status.enabling_control",
    "usertext.status.control_detail", "reason.choose_locked_targets",
    "reason.wait_locked_echo_list", "reason.wait_server_wishlist", "reason.draft_changed",
    "reason.not_saved_fewer_copies", "reason.not_saved_adds_excess",
    "reason.not_saved_no_gain", "reason.not_saved_coverage_lost", "reason.unknown_code",
)


_S8_CATALOG, _S8_FILES = [], []


def s8_catalog():
    """One loaded tool for every S8 class, so its parse memo is shared."""
    if not _S8_CATALOG:
        _S8_CATALOG.append(load_catalog())
    return _S8_CATALOG[0]


def s8_files():
    """The current input files, read once for every S8 class (callers copy)."""
    if not _S8_FILES:
        _S8_FILES.append(current_files())
    return dict(_S8_FILES[0])


# The V15 host label (C26 to C29) and the Spec toy module (C29): the toy
# differs between its cases only by INSTALL_MARKER.
V15_LABEL = b'\nlocal specLabel = UIParent:CreateFontString(nil, "OVERLAY")\n'
TOY_SHOW = b'DEFAULT_CHAT_FRAME:AddMessage(Nexus.UserText.Message("STORE_PENDING"))\n'
TOY_USER_TEXT = b'''Nexus = Nexus or {}
local T = {}
Nexus.UserText = T
local keys = {["STORE_PENDING"] = "reason.saved_data_reading"}
local function LocalizedReason(key, code)
    local localization = Nexus.Localization
    return localization.Text(key)
end
local function Install()
    function T.Message(value)
        local s = tostring(value or "")
        if keys[s] then return LocalizedReason(keys[s], s) end
        return s
    end
end
INSTALL_MARKER
setmetatable(T, {__index = function(_, name)
    if name == "Message" then
        return function(value) return "constant" end
    end
end})
''' + TOY_SHOW


def tearDownModule():
    """After the last test: the s8_settle_memo measure once more, for the
    syntax trees memoized since (gc.freeze). Their node/binding cycles then
    stay out of the interpreter's final collection, which would only rescan
    them on the way out of the process. Every test has already run, so no
    result depends on it; the collector's enabled state is unchanged."""
    if _S8_SETTLED:
        import gc
        gc.freeze()


# Moved verbatim from ProvenanceTests.blocked_calls (a staticmethod there); ProvenanceTests
# and ConsumerBindingTests C12 call it.
def provenance_blocked_calls():
    import builtins
    import io
    import socket

    def refuse(*args, **kwargs):
        raise AssertionError("I/O or process access during the provenance call")

    saved = [(builtins, "open"), (io, "open"), (os, "open"), (os, "listdir"),
             (os, "scandir"), (os, "stat"), (subprocess, "Popen"), (socket, "socket")]
    saved = [(owner, name, getattr(owner, name)) for owner, name in saved]
    for owner, name, _ in saved:
        setattr(owner, name, refuse)

    def restore():
        for owner, name, value in saved:
            setattr(owner, name, value)
    return restore


class _ConsumerBindingMixin:
    """The setUpClass and helper methods of the original ConsumerBindingTests, verbatim and
    in their original order, shared by its two parts (test_l10n_registry_consumers.py and
    test_l10n_registry_consumer_flow.py). A plain class, not a TestCase: it holds no test and
    is never collected."""

    @classmethod
    def setUpClass(cls):
        cls.catalog = s8_catalog()
        # The rule controls: the cohort substrate and its dated-28 view (see
        # cohort_view); C2 and the command line keep the full repository.
        cls.files = s8_cohort_files()
        cls.full_files = s8_files()
        catalog = cls.catalog
        s8_settle_memo(catalog, cls.full_files)
        cls.report = staticmethod(lambda *args: cohort_view(catalog.consumer_binding_report(*args)))

    def receipt(self, files, **options):
        return self.report(*binding_args(files, **options))

    def refuse(self, args, code):
        with self.assertRaises(self.catalog.CatalogConsumerError) as raised:
            self.report(*args)
        self.assertEqual(raised.exception.code, code)
        return raised.exception

    def gate_fails(self, files, **options):
        """The receipt of files, after the same gate failed on it."""
        receipt = self.receipt(files, **options)
        with self.assertRaises(AssertionError):
            assert_binding_receipt(self, receipt)
        return receipt

    def problems(self, receipt, code=None):
        return [problem for problem in receipt["problems"]
                if code is None or problem["code"] == code]

    def binding(self, receipt, key):
        return next(row for row in receipt["keys"] if row["key"] == key)

    def assert_unbound_exactly(self, receipt, unbound):
        """The gate fails on receipt with exactly these keys left UNBOUND,
        each with its own binding-unbound problem."""
        with self.assertRaises(AssertionError):
            assert_binding_receipt(self, receipt)
        self.assertEqual(sorted(row["key"] for row in receipt["keys"]
                                if row["binding"] == "UNBOUND"), sorted(unbound))
        self.assertEqual(sorted(problem.get("key") for problem
                                in self.problems(receipt, "binding-unbound")), sorted(unbound))

    def hosted(self, code):
        """The progress heading's only consumer removed from the real Panel,
        then code appended to the real core/SessionPause.lua after a proved
        client label specLabel (the C26 host)."""
        bare = with_file(self.files, PANEL, edit(self.files[PANEL], PROGRESS_CALL,
                                                 b'progressLabel:SetText("Progress")'))
        host = "core/SessionPause.lua"
        return with_file(bare, host, self.files[host] + V15_LABEL + code + b'\n')

    def per_site(self, cases):
        """One receipt for cases of the progress heading that act only on
        their own site (no global write): each case's code on its own line
        in its own do block, then each judged by its own site. A case that
        binds has its site among the proved sites, with an output; one that
        does not has it among the unproven sites only."""
        host = "core/SessionPause.lua"
        first = (self.files[host] + V15_LABEL).count(b"\n") + 1
        code = b"\n".join(b"do " + case + b" end" for _, case, _ in cases)
        row = self.binding(self.receipt(self.hosted(code)), "panel.heading.progress")
        proved = {site["line"] for site in row["sites"] if site["outputs"]}
        unproven = {site["line"] for site in row["unprovenSites"]}
        for line, (name, _, binds) in enumerate(cases, first):
            with self.subTest(case=name):
                self.assertEqual((line in proved, line in unproven), (binds, not binds))
        return row

    def dispatch_line(self, call):
        """The line of the one occurrence of call in the real core/UserText.lua."""
        lf = self.files[USER_TEXT].replace(b"\r\n", b"\n")
        self.assertEqual(lf.count(call), 1)
        return lf[:lf.index(call)].count(b"\n") + 1
