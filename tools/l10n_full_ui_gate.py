#!/usr/bin/env python3
"""Full visible-UI localization: the final six-pack composition gate (Refs #143-#148, #147).

Python 3.9+. A `luajit` executable is needed for the runtime cross-check; no network or game.

    python tools/l10n_full_ui_gate.py                       # gate the checkout; exit 0 PASS, 1 FAIL
    python tools/l10n_full_ui_gate.py --output report.json  # also write the complete JSON report
    python tools/l10n_full_ui_gate.py --receipt R.json --require-receipt --archive Nexus-x.zip

It reads the exact bytes of INPUTS once and reports failures and evidence. It writes nothing
in the checkout, and it never declares human translation, rights or native/UI acceptance.

Static gate (evaluate, pure over the supplied bytes). The current key set, kinds, fields, slot
types, lines and result limits come from the DECLARATIONS block of core/Localization.lua,
checked here against an independent restatement of its code-owned schema (CONTRACT): text is 1
to 256 bytes on one line; block 1 to 1024 bytes where only the line feed is an allowed control
byte; the original charge `format` keeps named count slots and result limit 254; a `template`
has unique field names, a parallel list of count/text slots, a result limit of 1 to 2048 and an
optional `lines = true`. Every text is well-formed UTF-8 without "|". Declarations, English and
each pack fail closed above 4096 entries. The English base, KEY_CONTEXT.json rows, the TOC load
order, the uiLanguages enum and the products and autonyms of RELEASE_LANGUAGES.json must agree.
No key count, family total or contract version is hard-coded: a later declaration change is
followed. A supplied composition receipt is checked against the current bytes and declaration
shapes only; its claimed prior version and lineage stay NOT_VERIFIED (see check_receipt).
Each optional product must ship a complete pack: every active key holds a valid entry of its
kind. Entries are classified separately (CATEGORIES). English fallback never counts: missing,
invalid, unknown, orphan, obsolete and english_placeholder (byte-identical to English without a
matching legitimately_identical entryReview declaration) fail. draft (valid and different from
English; no entry review declared) and the two declared categories are reported, not failed. An
entryReview declaration counts only after the existing complete record contract of
tools/l10n_catalog.py _check_declarations accepts it (_entry_reviews); it is a documented claim
and grants no review, rights or native acceptance.

Runtime cross-check (runtime_check). The same files are loaded by the real Nexus.toc boot of
the offline harness (tests/prototype/format5_support.lua) under LuaJIT, once per optional
language, with missing and invalid variants. Every active key resolves through the real seam
(L.Text / L.Format of the session pack) and must give exactly the source, reason and bytes this
module predicts; the load facts of L.Diagnostics and L.Languages must agree too. A bounded list
of real receivers (RECEIVER_PROBES, each naming the production function or property read) is
driven; each must show the predicted candidate, and the exact English when its entry is removed or
invalid. One of them reads a whole Help page and must hold a lines = true template's rendering as a
contiguous segment. A probe that shows English while a valid candidate exists is
receiver-not-localized; one that shows another key's text is receiver-wrong-key. This proves those
receivers only: it is not general reachability of every key or family, and a raw key in a comment,
list or unused value is not a receiver. The report keeps catalog validity, every-key seam checks
and the listed display receivers apart (coverage).

Provenance. The report records the SHA-256 and length of every exact input, and, when Git is
available, the commit, tree, index blob and the worktree blob of each input (hashed by Git under
the checkout's own attribute contract). Raw Git LF and physical CRLF bytes are different
observations; nothing is normalized except where a comparison records its contract. An archive
built by tools/build_package.py holds HEAD blobs, so --archive compares the four localization
runtime-input members with the supplied bytes with every CRLF as LF, under contract
ARCHIVE_CONTRACT; agreement is FOUR_MEMBER_SUBSET_MATCHED (ARCHIVE_SCOPE), never the whole
archive or the packaged revision. A hash agreement is byte agreement only: it is not drafting
history, language quality or rights acceptance.

Reused seam: the literal lexer and parsers of tools/l10n_catalog.py (_tokens, _LiteralParser,
_declaration_block, _parse_literal_table, parse_english, parse_packs) and its entry-review record
validator (_check_declarations), loaded read-only from its file. Their public pilot validators cap
at 64 keys and know only text/format, so this module adds its own checks instead of changing that
reserved file. A later change of those private helpers is a compatibility dependency of this gate.
"""
from __future__ import annotations
import argparse, hashlib, io, json, pathlib, re, shutil, subprocess, sys, tempfile, time, types, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
GATE_SCHEMA = 'nexus.l10n.full_ui_gate'
GATE_SCHEMA_VERSION = 1

INPUTS = (('toc', 'Nexus.toc'), ('profile', 'data/DefaultProfile.lua'),
          ('english', 'data/LocalizationEnglish.lua'), ('packs', 'data/LocalizationPacks.lua'),
          ('localization', 'core/Localization.lua'),
          ('keyContext', 'docs/localization/KEY_CONTEXT.json'),
          ('release', 'docs/localization/RELEASE_LANGUAGES.json'))
INPUT_PATHS = dict(INPUTS)
# The files the runtime loads; the archive comparison covers these (the TOC is stamped by the
# package build and is compared by its own package checks instead).
RUNTIME_INPUTS = ('profile', 'english', 'packs', 'localization')
ARCHIVE_CONTRACT = ('archive member Nexus/<path> == supplied bytes with every CRLF as LF; '
                    'tools/build_package.py packs HEAD blobs and .gitattributes sets eol=crlf for '
                    '*.lua, so a checkout holds CRLF; a lone CR is not comparable')

# Independent restatement of the code-owned contract of core/Localization.lua.
CONTRACT = types.MappingProxyType({
    'MAX_KEY_BYTES': 64, 'MAX_TEXT_BYTES': 256, 'MAX_BASE_ENTRIES': 4096, 'MAX_NAME_BYTES': 64,
    'MAX_LANGUAGES': 16, 'MAX_BLOCK_BYTES': 1024, 'MAX_TEMPLATE_RESULT_BYTES': 2048,
    'MAX_SLOT_TEXT_BYTES': 1024})
MAX_KEY = CONTRACT['MAX_KEY_BYTES']
MAX_TEXT = CONTRACT['MAX_TEXT_BYTES']
MAX_ENTRIES = CONTRACT['MAX_BASE_ENTRIES']
MAX_BLOCK = CONTRACT['MAX_BLOCK_BYTES']
MAX_RESULT = CONTRACT['MAX_TEMPLATE_RESULT_BYTES']
MAX_SLOT_TEXT = CONTRACT['MAX_SLOT_TEXT_BYTES']
CHARGE_RESULT_LIMIT = MAX_TEXT - 2
KINDS = ('text', 'block', 'format', 'template')
TEMPLATE_SLOTS = ('count', 'text')
ENGLISH_ID = 'enUS'
UNAVAILABLE = 'This status cannot be shown right now.'

CATEGORIES = ('draft', 'declared_translated', 'legitimately_identical', 'english_placeholder',
              'missing', 'invalid', 'unknown', 'orphan', 'obsolete')
FAILING = frozenset(('english_placeholder', 'missing', 'invalid', 'unknown', 'orphan', 'obsolete'))

# Real receivers driven by the runtime cross-check. `slots` gives the value each placeholder
# must show: a literal, or {'key': k} for the text another key resolves to in the same run.
# `receiver` names the production function or property whose value is observed. With
# match = 'segment' the observed value is a whole displayed text (a Help page body) that must
# hold the predicted rendering as one contiguous segment; otherwise it must equal it.
RECEIVER_PROBES = (
    {'id': 'usertext.message.root_mutation_pending', 'key': 'reason.save_in_progress',
     'receiver': 'core/UserText.lua T.Message (LocalizedReason)',
     'code': "return (Nexus.UserText.Message('ROOT_MUTATION_PENDING'))"},
    {'id': 'usertext.message.three_card_board', 'key': 'reason.wait_three_choices',
     'receiver': 'core/UserText.lua T.Message (LocalizedReason)',
     'code': "return (Nexus.UserText.Message('waiting for three-card board'))"},
    {'id': 'readout.charges_line', 'key': 'readout.charge_counts',
     'receiver': 'ui/Readout.lua M.ChargesLine',
     'code': 'return Nexus.Readout.ChargesLine({banish = 3, reroll = 0, arrived = true})',
     'slots': {'banish': '3', 'reroll': '0', 'freeze': '?'}},
    {'id': 'panel.detail_name_lines', 'key': 'panel.label.more_count',
     'receiver': 'ui/Panel.lua M.DetailNameLines',
     'code': "return Nexus.Panel.DetailNameLines({'a', 'b', 'c', 'd'})[3]",
     'slots': {'count': '2'}},
    {'id': 'panel.size_menu_hover', 'key': 'panel.tooltip.size_explained',
     'receiver': 'ui/Panel.lua M.PanelSizeMenuItem().tooltipText',
     'code': 'return Nexus.Panel.PanelSizeMenuItem().tooltipText'},
    {'id': 'panel.language_refused', 'key': 'panel.chat.language_refused',
     'receiver': 'ui/Panel.lua M.LanguageResultText',
     'code': "return Nexus.Panel.LanguageResultText({state = 'refused', reason = 'nope'})",
     'slots': {'reason': {'key': 'panel.status.language_reason_refused'}}},
    {'id': 'usertext.glossary', 'key': 'usertext.body.glossary',
     'receiver': 'core/UserText.lua T.GLOSSARY (display-time field)',
     'code': 'return Nexus.UserText.GLOSSARY'},
    # A lines = true template: the Reference window's Troubleshooting page, opened by H.Show and
    # read back from the FontString refresh() filled with PageText; then hidden again.
    {'id': 'help.page_troubleshooting_body', 'key': 'help.body.troubleshooting_commands_2',
     'receiver': 'ui/Help.lua H.Show("troubleshooting") -> NexusHelpWindow.body:GetText()',
     'match': 'segment',
     'code': "local frame = Nexus.Help.Show('troubleshooting')\n"
             "local text = frame.body:GetText()\nframe:Hide()\nreturn text",
     'slots': {'policy_command': '/nexus policy adaptive|released'}},
)
RECEIVER_SCOPE = ('bounded subset: the listed real receiver paths under every optional language, '
                  'with missing and invalid variants; not general reachability of every key, not '
                  'native UI, layout, glyph or reload evidence')


def _load_catalog():
    """tools/l10n_catalog.py compiled in memory from its own file (no bytecode cache, no
    sys.path lookup); its command line does not run."""
    path = pathlib.Path(__file__).resolve().parent / 'l10n_catalog.py'
    module = types.ModuleType('_nexus_l10n_catalog_seam')
    module.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), 'exec', dont_inherit=True), module.__dict__)
    return module


_CATALOG = _load_catalog()
SyntaxFailure = _CATALOG.CatalogSyntaxError


# ---------------------------------------------------------------------------------------------
# The independent contract checks.

_KEY = re.compile(r'[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+')
_FIELD = re.compile(r'[a-z][a-z0-9_]*')


def valid_key(key) -> bool:
    return (isinstance(key, str) and 3 <= len(key.encode('utf-8')) <= MAX_KEY
            and _KEY.fullmatch(key) is not None)


def _scalar_text(value, limit, line_feed):
    if not isinstance(value, str):
        return False
    try:
        data = value.encode('utf-8')
    except UnicodeEncodeError:
        return False
    if not 1 <= len(data) <= limit:
        return False
    if all(byte in (9, 10, 11, 12, 13, 32) for byte in data):
        return False
    return not any((byte < 32 and not (line_feed and byte == 10)) or byte in (124, 127)
                   for byte in data)


def valid_text(value) -> bool:
    return _scalar_text(value, MAX_TEXT, False)


def valid_block(value) -> bool:
    return _scalar_text(value, MAX_BLOCK, True)


def compile_template(text, fields, lines=False):
    """Literal strings and ('field', name) parts, or None (the runtime grammar)."""
    if not (valid_block(text) if lines else valid_text(text)):
        return None
    parts, literal, seen, index = [], [], set(), 0
    while index < len(text):
        char = text[index]
        if char == '{':
            if text[index + 1:index + 2] == '{':
                literal.append('{')
                index += 2
                continue
            close = text.find('}', index + 1)
            if close < 0:
                return None
            name = text[index + 1:close]
            if name not in fields or name in seen:
                return None
            seen.add(name)
            if literal:
                parts.append(''.join(literal))
                literal = []
            parts.append(('field', name))
            index = close + 1
        elif char == '}':
            if text[index + 1:index + 2] != '}':
                return None
            literal.append('}')
            index += 2
        else:
            literal.append(char)
            index += 1
    if len(seen) != len(fields):
        return None
    if literal:
        parts.append(''.join(literal))
    return parts


def render(parts, values, limit):
    text = ''.join(values[part[1]] if isinstance(part, tuple) else part for part in parts)
    return text if len(text.encode('utf-8')) <= limit else None


def entry_valid(declaration, text) -> bool:
    kind = declaration['kind']
    if kind in ('format', 'template'):
        return compile_template(text, declaration['fields'], declaration.get('lines', False)) is not None
    return valid_block(text) if kind == 'block' else valid_text(text)


def entry_problem(declaration, text):
    """Why a text is not a valid entry of its declaration, or None."""
    kind = declaration['kind']
    if not isinstance(text, str):
        return 'not-a-string'
    lines = declaration.get('lines', False) or kind == 'block'
    if not _scalar_text(text, MAX_BLOCK if lines else MAX_TEXT, lines):
        data = text.encode('utf-8')
        if not 1 <= len(data) <= (MAX_BLOCK if lines else MAX_TEXT):
            return 'byte-length'
        if b'\n' in data and not lines:
            return 'line-feed'
        if b'|' in data:
            return 'pipe'
        if any(byte < 32 or byte == 127 for byte in data if byte != 10):
            return 'control-byte'
        return 'whitespace-only'
    if kind in ('format', 'template') and entry_valid(declaration, text) is False:
        return 'template-grammar'
    return None


# ---------------------------------------------------------------------------------------------
# Parsing the supplied bytes (syntax only; the contract checks above decide validity).

def _strict_json(data, where, problems):
    def unique(pairs):
        out = {}
        for key, value in pairs:
            if key in out:
                raise ValueError('duplicate member ' + key)
            out[key] = value
        return out
    try:
        if data.startswith(b'\xef\xbb\xbf'):
            raise ValueError('byte order mark')
        return json.loads(data.decode('utf-8'), object_pairs_hook=unique)
    except (UnicodeDecodeError, ValueError) as error:
        problems.append(_problem('input-syntax', where, detail=str(error)))
        return None


def _problem(code, path, key=None, product=None, detail=None):
    row = {'code': code, 'path': path}
    if key is not None:
        row['key'] = key
    if product is not None:
        row['productId'] = product
    if detail is not None:
        row['detail'] = detail
    return row


def parse_declarations(source: bytes):
    """{key: raw literal value} of the DECLARATIONS block, in source order."""
    text = bytes(source).decode('utf-8')
    parser = _CATALOG._LiteralParser(_CATALOG._tokens(_CATALOG._declaration_block(text), integers=True))
    for kind, value in (('name', 'local'), ('name', 'DECLARATIONS'), ('punct', '='), ('punct', '{')):
        parser.take(kind, value)
    table = parser.table(1)
    token = parser.tokens[parser.index]
    if token.kind != 'eof':
        parser.fail('trailing-content', token)
    return table if isinstance(table, dict) else {}


def check_declaration(key, value):
    """(declaration, None) or (None, reason) for one raw declaration."""
    if not valid_key(key):
        return None, 'key'
    if not isinstance(value, dict) or not value:
        return None, 'structure'
    kind = value.get('kind')
    if kind not in KINDS:
        return None, 'kind'
    if kind in ('text', 'block'):
        return ({'kind': kind}, None) if set(value) == {'kind'} else (None, 'fields')
    fields = value.get('fields')
    if not (isinstance(fields, list) and fields and all(isinstance(name, str) for name in fields)
            and len(set(fields)) == len(fields)
            and all(len(name.encode('utf-8')) <= MAX_KEY and _FIELD.fullmatch(name) for name in fields)):
        return None, 'placeholders'
    limit = value.get('resultLimit')
    if kind == 'format':
        if set(value) != {'kind', 'fields', 'slot', 'resultLimit'}:
            return None, 'fields'
        if value['slot'] != 'count':
            return None, 'slot'
        if type(limit) is not int or limit != CHARGE_RESULT_LIMIT:
            return None, 'result-limit'
        return {'kind': 'format', 'fields': tuple(fields), 'slots': ('count',) * len(fields),
                'resultLimit': limit}, None
    allowed = {'kind', 'fields', 'slots', 'resultLimit'}
    if 'lines' in value:
        if value['lines'] is not True:
            return None, 'lines'
        allowed = allowed | {'lines'}
    if set(value) != allowed:
        return None, 'fields'
    slots = value.get('slots')
    if not (isinstance(slots, list) and len(slots) == len(fields)
            and all(isinstance(slot, str) and slot in TEMPLATE_SLOTS for slot in slots)):
        return None, 'slots'
    if type(limit) is not int or not 1 <= limit <= MAX_RESULT:
        return None, 'result-limit'
    declaration = {'kind': 'template', 'fields': tuple(fields), 'slots': tuple(slots),
                   'resultLimit': limit}
    if value.get('lines') is True:
        declaration['lines'] = True
    return declaration, None


def runtime_constants(source: bytes) -> dict:
    text = bytes(source).decode('utf-8', errors='replace')
    return {name: int(value) for name, value in
            re.findall(r'^local (MAX_[A-Z_]+) = (\d+)\r?$', text, re.M)}


def toc_entries(source: bytes):
    lines = bytes(source).decode('utf-8', errors='replace').splitlines()
    return [line.strip().replace('\\', '/') for line in lines
            if line.strip() and not line.lstrip().startswith('#')]


def profile_languages(source: bytes):
    """The literal uiLanguages table of data/DefaultProfile.lua, or None."""
    text = bytes(source).decode('utf-8')
    found = re.search(r'^DefaultProfile\.uiLanguages = (\{.*?^\})', text, re.M | re.S)
    if not found:
        return None
    return _CATALOG._parse_literal_table(('return ' + found.group(1)).encode('utf-8'))


# ---------------------------------------------------------------------------------------------
# The static gate.

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def evaluate(sources: dict, receipt: bytes = None, require_receipt: bool = False) -> dict:
    """The complete static report over the supplied bytes (name -> bytes of INPUTS). Pure:
    it reads, writes and runs nothing."""
    problems = []
    report = {'schema': GATE_SCHEMA, 'schemaVersion': GATE_SCHEMA_VERSION,
              'inputs': [{'name': name, 'path': path, 'sha256': sha256(sources[name]),
                          'bytes': len(sources[name])} for name, path in INPUTS],
              'contract': dict(CONTRACT), 'problems': problems}

    observed = runtime_constants(sources['localization'])
    for name, value in CONTRACT.items():
        if observed.get(name) != value:
            problems.append(_problem('contract-constant', INPUT_PATHS['localization'], detail=
                                     '%s is %r, gate contract %r' % (name, observed.get(name), value)))

    # Declarations.
    declarations, raw = {}, {}
    try:
        raw = parse_declarations(sources['localization'])
    except (SyntaxFailure, _CATALOG.CatalogRegistryError, UnicodeDecodeError) as error:
        problems.append(_problem('input-syntax', INPUT_PATHS['localization'],
                                 detail='%s: %s' % (type(error).__name__, error)))
    if len(raw) > MAX_ENTRIES:
        problems.append(_problem('declarations-over-cap', INPUT_PATHS['localization'],
                                 detail='%d declarations > %d' % (len(raw), MAX_ENTRIES)))
        raw = {}
    for key, value in raw.items():
        declaration, reason = check_declaration(key, value)
        if declaration is None:
            problems.append(_problem('declaration-invalid', INPUT_PATHS['localization'], key,
                                     detail=reason))
        else:
            declarations[key] = declaration

    # English base.
    english, active, refused = {}, {}, set()
    try:
        english = _CATALOG.parse_english(sources['english'])
    except SyntaxFailure as error:
        problems.append(_problem('input-syntax', INPUT_PATHS['english'], detail=str(error)))
    if len(english) > MAX_ENTRIES:
        problems.append(_problem('english-over-cap', INPUT_PATHS['english'],
                                 detail='%d entries > %d' % (len(english), MAX_ENTRIES)))
        english_admitted = {}
    else:
        english_admitted = english
    for key, text in english_admitted.items():
        declaration = declarations.get(key)
        if declaration is None:
            problems.append(_problem('english-undeclared', INPUT_PATHS['english'], key))
        elif not entry_valid(declaration, text):
            problems.append(_problem('english-invalid', INPUT_PATHS['english'], key,
                                     detail=entry_problem(declaration, text)))
            refused.add(key)
        else:
            active[key] = text
    for key in declarations:
        if key not in active and key not in refused:
            problems.append(_problem('english-missing', INPUT_PATHS['english'], key))
    report['catalog'] = {'declared': len(declarations), 'english': len(english),
                         'active': len(active),
                         'byKind': {kind: sum(1 for key in active if declarations[key]['kind'] == kind)
                                    for kind in KINDS},
                         'lines': sum(1 for key in active if declarations[key].get('lines'))}

    # Key context rows and retired keys.
    context = _strict_json(sources['keyContext'], INPUT_PATHS['keyContext'], problems) or {}
    retired = _check_context(context, declarations, english, problems)

    # TOC, uiLanguages and products.
    optional_ids = _check_languages(sources, problems)
    release = _strict_json(sources['release'], INPUT_PATHS['release'], problems) or {}
    products = _check_products(release, optional_ids, problems)

    # Packs.
    packs = {}
    try:
        packs = _CATALOG.parse_packs(sources['packs'])
    except SyntaxFailure as error:
        problems.append(_problem('input-syntax', INPUT_PATHS['packs'], detail=str(error)))
    if list(packs) != [row['productId'] for row in products]:
        problems.append(_problem('pack-set', INPUT_PATHS['packs'], detail='packs %r, products %r' % (
            list(packs), [row['productId'] for row in products])))
    reviews, report['entryReview'] = _entry_reviews(release, english, packs,
                                                    [row['productId'] for row in products], problems)
    report['products'] = []
    for row in products:
        product = row['productId']
        pack = packs.get(product)
        coverage = classify_pack(product, pack, row, declarations, active, retired, reviews, problems)
        report['products'].append(coverage)

    report['compositionReceipt'] = check_receipt(receipt, sources, declarations,
                                                 [row['productId'] for row in products], problems,
                                                 require_receipt)
    report['model'] = {'declarations': declarations, 'active': active, 'packs': packs,
                       'english': english, 'optionalIds': optional_ids, 'products': products}
    return report


def _check_context(context, declarations, english, problems):
    where = INPUT_PATHS['keyContext']
    rows = context.get('keys') if isinstance(context, dict) else None
    if not isinstance(rows, list):
        problems.append(_problem('context-structure', where, detail='keys is not a list'))
        rows = []
    seen = set()
    for index, row in enumerate(rows):
        key = row.get('key') if isinstance(row, dict) else None
        if key in seen:
            problems.append(_problem('context-duplicate', where, key))
            continue
        seen.add(key)
        declaration = declarations.get(key)
        if declaration is None:
            problems.append(_problem('context-undeclared', where, key, detail='keys[%d]' % index))
            continue
        placeholders = row.get('placeholders')
        shape = ([(p.get('name'), p.get('type')) for p in placeholders]
                 if isinstance(placeholders, list) and all(isinstance(p, dict) for p in placeholders)
                 else None)
        if row.get('kind') != declaration['kind']:
            problems.append(_problem('context-mismatch', where, key, detail='kind'))
        if row.get('english') != english.get(key):
            problems.append(_problem('context-mismatch', where, key, detail='english'))
        if shape != list(zip(declaration.get('fields', ()), declaration.get('slots', ()))):
            problems.append(_problem('context-mismatch', where, key, detail='placeholders'))
        if row.get('resultLimitBytes') != declaration.get('resultLimit'):
            problems.append(_problem('context-mismatch', where, key, detail='resultLimitBytes'))
        if row.get('lines') is not declaration.get('lines'):
            problems.append(_problem('context-mismatch', where, key, detail='lines'))
    for key in declarations:
        if key not in seen:
            problems.append(_problem('context-missing', where, key))
    record = context.get('retiredKeys') if isinstance(context, dict) else None
    retired = record.get('keys') if isinstance(record, dict) else None
    if not (isinstance(retired, list) and all(isinstance(key, str) for key in retired)):
        problems.append(_problem('context-structure', where, detail='retiredKeys.keys'))
        retired = []
    for key in retired:
        if key in declarations:
            problems.append(_problem('retired-active', where, key))
    return frozenset(retired)


def _check_languages(sources, problems):
    entries = toc_entries(sources['toc'])
    order = [INPUT_PATHS[name] for name in ('english', 'packs', 'localization')]
    positions = [[index for index, entry in enumerate(entries) if entry == path] for path in order]
    profile_at = [index for index, entry in enumerate(entries) if entry == INPUT_PATHS['profile']]
    if (any(len(found) != 1 for found in positions) or len(profile_at) != 1
            or [found[0] for found in positions] != list(range(positions[0][0], positions[0][0] + 3))
            or profile_at[0] > positions[2][0]):
        problems.append(_problem('toc-order', INPUT_PATHS['toc'], detail=
                                 'need DefaultProfile before English, Packs, Localization (adjacent, once each)'))
    try:
        enum = profile_languages(sources['profile'])
    except (SyntaxFailure, UnicodeDecodeError) as error:
        enum = None
        problems.append(_problem('input-syntax', INPUT_PATHS['profile'], detail=str(error)))
    ids = enum.get('ids') if isinstance(enum, dict) else None
    if not (isinstance(enum, dict) and enum.get('default') == ENGLISH_ID and isinstance(ids, list)
            and ids and ids[0] == ENGLISH_ID and len(ids) <= CONTRACT['MAX_LANGUAGES']
            and len(set(ids)) == len(ids)
            and all(isinstance(i, str) and re.fullmatch('[a-z]{2}[A-Z]{2}', i) for i in ids)):
        problems.append(_problem('profile-languages', INPUT_PATHS['profile'], detail=repr(enum)))
        return [i for i in (ids or []) if isinstance(i, str) and i != ENGLISH_ID]
    return ids[1:]


def _check_products(release, optional_ids, problems):
    where = INPUT_PATHS['release']
    rows = release.get('products') if isinstance(release, dict) else None
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        problems.append(_problem('products-structure', where))
        return []
    baseline = [row for row in rows if row.get('kind') == 'english_baseline']
    optional = [row for row in rows if row.get('kind') == 'optional_ui_pack']
    if (len(baseline) != 1 or baseline[0].get('productId') != ENGLISH_ID
            or len(baseline) + len(optional) != len(rows)):
        problems.append(_problem('products-structure', where, detail='one enUS english_baseline, '
                                 'every other product an optional_ui_pack'))
    if [row.get('productId') for row in optional] != list(optional_ids):
        problems.append(_problem('products-mismatch', where, detail='products %r, uiLanguages %r' % (
            [row.get('productId') for row in optional], list(optional_ids))))
    return optional


ENTRY_REVIEW_VALIDATOR = ('tools/l10n_catalog.py _check_declarations, unchanged: the container contract once, '
                          'then each record alone against the supplied English and packs')
ENTRY_REVIEW_NOT_EVIDENCE = ('A declaration is a documented claim: it is not evidence of fluent review, '
                             'contributor rights or native acceptance, which stay UNKNOWN or pending.')
# A refused record's catalog code, and the gate code it is reported under.
_REVIEW_CODES = {'evidence-stale': 'entry-review-stale', 'evidence-decision-mismatch': 'entry-review-contradiction'}


def _entry_reviews(release, english, packs, product_ids, problems):
    """The exemptions the entry-review declarations grant, ({(productId, key): (decision, sha256)},
    report section). Every record must pass the existing complete record contract of
    tools/l10n_catalog.py (contract and version, exact seven string fields, declared status, known
    optional product and English key, a present entry with the recorded hash, an assigned reviewer, an
    https reference and a decision that agrees with the entry). It is applied to each record alone, so
    one refused record grants nothing and leaves the others as they are; two records for one entry
    grant nothing. A container outside the contract grants no exemption at all."""
    where = INPUT_PATHS['release']
    container = release.get('entryReview') if isinstance(release, dict) else None
    section = {'validator': ENTRY_REVIEW_VALIDATOR, 'notEvidenceOf': ENTRY_REVIEW_NOT_EVIDENCE}
    errors = (_CATALOG.CatalogEvidenceError,)

    def check(records):
        copy = dict(container, declarations=records)
        _CATALOG._check_declarations(dict(release, entryReview=copy), english, packs, list(product_ids))

    try:
        if not isinstance(container, dict):
            raise _CATALOG.CatalogEvidenceError('evidence-contract', 'release.entryReview')
        check([])
    except errors as error:
        problems.append(_problem('entry-review-invalid', where + ' ' + (error.path or ''), detail=error.code))
        section.update(status='REFUSED', records=None, accepted=0)
        return {}, section
    records = container['declarations']
    valid = {}
    for index, record in enumerate(records):
        path = '%s entryReview.declarations[%d]' % (where, index)
        key = record.get('key') if isinstance(record, dict) else None
        product = record.get('productId') if isinstance(record, dict) else None
        try:
            check([record])
        except errors as error:
            problems.append(_problem(_REVIEW_CODES.get(error.code, 'entry-review-invalid'), path,
                                     key if isinstance(key, str) else None,
                                     product if isinstance(product, str) else None, error.code))
            continue
        except KeyError:  # a known optional product whose pack is absent holds no entry
            problems.append(_problem('entry-review-invalid', path, key, product, 'evidence-no-entry'))
            continue
        valid.setdefault((product, key), []).append(record)
    out = {}
    for (product, key), rows in valid.items():
        if len(rows) > 1:
            detail = 'evidence-duplicate' if all(row == rows[0] for row in rows) else 'evidence-conflict'
            problems.append(_problem('entry-review-duplicate', where + ' entryReview.declarations', key,
                                     product, detail))
            continue
        out[(product, key)] = (rows[0]['decision'], rows[0]['translatedTextSha256'])
    section.update(status='RECORDS_CHECKED', records=len(records), accepted=len(out))
    return out, section


def classify_pack(product, pack, release_row, declarations, active, retired, reviews, problems):
    """Every key of one product in exactly one category (CATEGORIES)."""
    where = INPUT_PATHS['packs']
    categories = {name: [] for name in CATEGORIES}
    invalid_reasons = {}
    autonym = release_row.get('autonym')
    entries = None
    if pack is None:
        problems.append(_problem('pack-absent', where, product=product))
    else:
        name = pack.get('name')
        if not (valid_text(name) and len(name.encode('utf-8')) <= CONTRACT['MAX_NAME_BYTES']):
            problems.append(_problem('pack-name', where, product=product, detail='name contract'))
        elif name != autonym:
            problems.append(_problem('autonym-mismatch', where, product=product,
                                     detail='%r != %r' % (name, autonym)))
        entries = pack.get('entries')
        if len(entries) > MAX_ENTRIES:
            problems.append(_problem('pack-over-cap', where, product=product,
                                     detail='%d entries > %d' % (len(entries), MAX_ENTRIES)))
            entries = None
    entries = entries or {}
    for key in active:
        if key not in entries:
            categories['missing'].append(key)
            continue
        text = entries[key]
        reason = entry_problem(declarations[key], text)
        if reason:
            categories['invalid'].append(key)
            invalid_reasons[key] = reason
            continue
        review = reviews.get((product, key))
        digest = sha256(text.encode('utf-8'))
        if review and review[1] != digest:
            problems.append(_problem('entry-review-stale', INPUT_PATHS['release'], key, product))
            review = None
        identical = text == active[key]
        if review and (review[0] == 'legitimately_identical') != identical:
            problems.append(_problem('entry-review-contradiction', INPUT_PATHS['release'], key, product))
            review = None
        if identical:
            categories['legitimately_identical' if review else 'english_placeholder'].append(key)
        else:
            categories['declared_translated' if review else 'draft'].append(key)
    for key in entries:
        if key in active:
            continue
        if not valid_key(key):
            categories['unknown'].append(key)
        elif key in retired:
            categories['obsolete'].append(key)
        else:
            categories['orphan'].append(key)
    for category in CATEGORIES:
        if category in FAILING and categories[category]:
            problems.append(_problem('entry-' + category.replace('_', '-'), where, product=product,
                                     detail='%d keys' % len(categories[category])))
    return {'productId': product, 'autonym': autonym, 'wordingState': release_row.get('wordingState'),
            'entries': len(entries), 'active': len(active),
            'counts': {name: len(keys) for name, keys in categories.items()},
            'categories': categories, 'invalidReasons': invalid_reasons,
            'complete': not any(categories[name] for name in FAILING)}


RECEIPT_SCHEMA = 'nexus.l10n.composition_receipt'
RECEIPT_BASES = ('exact-supplied-bytes', 'crlf-as-lf')


def _basis_bytes(data, basis):
    if basis == 'exact-supplied-bytes':
        return data
    canonical = data.replace(b'\r\n', b'\n')
    return None if b'\r' in canonical else canonical


RECEIPT_LINEAGE = ('NOT_VERIFIED: no authoritative prior source or version is supplied; contractVersion and '
                   'previousKind are caller claims, and this receipt format is a proposal Root has not adopted')
RECEIPT_VERIFIED = ('the current English, packs and core/Localization.lua bytes under the stated hash basis, the '
                    'product list, and the current kind, lines and result limit of each override key')
_OVERRIDE_FIELDS = frozenset(('key', 'kind', 'previousKind'))
_OVERRIDE_OPTIONAL = frozenset(('lines', 'resultLimit'))


def _override_shape(override):
    """Whether an override is well formed: the three fields, optional lines (exactly true) and
    resultLimit (a whole number), a key string, and a current and a prior kind of KINDS."""
    if not (isinstance(override, dict) and _OVERRIDE_FIELDS <= set(override) <= _OVERRIDE_FIELDS | _OVERRIDE_OPTIONAL):
        return False
    return (isinstance(override['key'], str) and override['kind'] in KINDS and override['previousKind'] in KINDS
            and ('lines' not in override or override['lines'] is True)
            and ('resultLimit' not in override or type(override['resultLimit']) is int))


def check_receipt(receipt, sources, declarations, product_ids, problems, required):
    """A supplied composition receipt is checked against the current supplied bytes only: its input
    hashes under its stated basis, its product list, and for each override the current
    declaration's kind, lines and result limit. A malformed override (an unknown or non-string
    prior kind, a lines value other than true, a missing or extra field) or a repeated key is
    refused. The prior version and lineage cannot be verified (RECEIPT_LINEAGE): a successful check
    is CURRENT_INPUTS_MATCHED, never an approved version or a verified transition. Without a
    receipt the gate reports NOT_SUPPLIED, which fails only when one is required."""
    where = 'composition receipt'
    if receipt is None:
        if required:
            problems.append(_problem('receipt-missing', where))
        return {'status': 'NOT_SUPPLIED'}
    document = _strict_json(receipt, where, problems)
    fields = {'schema', 'schemaVersion', 'contractVersion', 'hashBasis', 'inputs', 'products',
              'contractOverrides'}
    if not (isinstance(document, dict) and set(document) == fields
            and document['schema'] == RECEIPT_SCHEMA and document['schemaVersion'] == 1
            and isinstance(document['contractVersion'], str) and document['contractVersion']
            and document['hashBasis'] in RECEIPT_BASES and isinstance(document['inputs'], dict)
            and isinstance(document['contractOverrides'], list)):
        problems.append(_problem('receipt-structure', where))
        return {'status': 'REFUSED', 'sha256': sha256(receipt), 'priorVersionAndLineage': 'NOT_VERIFIED'}
    refused = False
    names = {path: name for name, path in INPUTS}
    for required_path in (INPUT_PATHS['english'], INPUT_PATHS['packs'], INPUT_PATHS['localization']):
        if required_path not in document['inputs']:
            problems.append(_problem('receipt-structure', where, detail='inputs lack ' + required_path))
            refused = True
    for path, digest in document['inputs'].items():
        data = sources.get(names.get(path)) if path in names else None
        basis = _basis_bytes(data, document['hashBasis']) if data is not None else None
        if basis is None or sha256(basis) != digest:
            problems.append(_problem('receipt-stale', where, detail=path))
            refused = True
    if document['products'] != list(product_ids):
        problems.append(_problem('receipt-products', where))
        refused = True
    seen = set()
    for index, override in enumerate(document['contractOverrides']):
        at = '%s contractOverrides[%d]' % (where, index)
        if not _override_shape(override):
            key = override.get('key') if isinstance(override, dict) else None
            problems.append(_problem('receipt-override-malformed', at, key if isinstance(key, str) else None))
            refused = True
            continue
        key = override['key']
        if key in seen:
            problems.append(_problem('receipt-override-duplicate', at, key))
            refused = True
            continue
        seen.add(key)
        declaration = declarations.get(key)
        if not (declaration is not None and declaration['kind'] == override['kind']
                and declaration.get('lines') is override.get('lines')
                and declaration.get('resultLimit') == override.get('resultLimit',
                                                                    declaration.get('resultLimit'))):
            problems.append(_problem('receipt-override-mismatch', at, key))
            refused = True
        elif override['previousKind'] == override['kind'] and 'lines' not in override:
            problems.append(_problem('receipt-override-noop', at, key))
            refused = True
    return {'status': 'REFUSED' if refused else 'CURRENT_INPUTS_MATCHED', 'sha256': sha256(receipt),
            'verified': RECEIPT_VERIFIED, 'priorVersionAndLineage': 'NOT_VERIFIED', 'lineageNote': RECEIPT_LINEAGE,
            'claimedContractVersion': document['contractVersion'], 'hashBasis': document['hashBasis'],
            'overrides': len(document['contractOverrides'])}


# ---------------------------------------------------------------------------------------------
# The runtime cross-check.

def _lua_string(value: str) -> str:
    """A Lua 5.1 short string literal of value: printable ASCII and non-ASCII UTF-8 as they are,
    every other byte, the quote and the backslash as a three-digit decimal escape (so a digit
    after an escape is never read as part of it)."""
    out = []
    for char in value:
        code = ord(char)
        out.append('\\%03d' % code if code < 32 or code == 127 or char in '"\\' else char)
    return '"' + ''.join(out) + '"'


def _lua_value(value) -> str:
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return _lua_string(value)
    if isinstance(value, (list, tuple)):
        return '{' + ','.join(_lua_value(item) for item in value) + '}'
    return '{' + ','.join('[%s]=%s' % (_lua_string(k), _lua_value(v)) for k, v in value.items()) + '}'


DRIVER = r'''
local spec = dofile(arg[1])
local F = dofile('tests/prototype/format5_support.lua')
local BS = string.char(92)
local function hex(s)
  s = tostring(s)
  return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end))
end
local function out(...) io.write('@@NXG@@\t', table.concat({...}, '\t'), '\n') end
local function hook(path, fn)
  F.fileHooks[path] = fn; F.fileHooks[path:gsub('/', BS)] = fn
end
for _, run in ipairs(spec.runs) do
  F.fileHooks = {}
  local raw
  hook('data/LocalizationEnglish.lua', function()
    if spec.english ~= 'data/LocalizationEnglish.lua' then dofile(spec.english) end
  end)
  hook('data/LocalizationPacks.lua', function()
    if spec.packs ~= 'data/LocalizationPacks.lua' then dofile(spec.packs) end
    local pack = type(Nexus.LocalizationPacks) == 'table' and Nexus.LocalizationPacks[run.lang]
    if type(pack) == 'table' and type(pack.entries) == 'table' then
      for _, key in ipairs(run.remove) do pack.entries[key] = nil end
      for key, text in pairs(run.replace) do pack.entries[key] = text end
      raw = {}
      for key, text in pairs(pack.entries) do raw[key] = text end
    end
  end)
  hook('core/Localization.lua', function()
    if spec.localization ~= 'core/Localization.lua' then dofile(spec.localization) end
    Nexus.Localization.InitializeActiveLanguage(run.lang)
  end)
  F.Boot(F.Database(), function(h) F.OrbService(h) end)
  local L = Nexus.Localization
  local d = L.Diagnostics()
  local b = d.base
  out('B', run.id, tostring(b.present), b.accepted, b.rejected, tostring(b.oversized), b.formatted,
    b.undeclared, b.missingDeclared, d.packs.adopted, d.packs.refused, d.language.active)
  for _, row in ipairs(d.packs.rows) do out('W', run.id, row.id, row.accepted, row.rejected) end
  for _, row in ipairs(L.Languages()) do out('G', run.id, row.id, hex(row.name)) end
  local english = Nexus.LocalizationEnglish
  local function args(k)
    local a = {}
    for i, name in ipairs(k.fields) do
      a[name] = k.slots[i] == 'count' and L.Count(7) or 's'
    end
    return a
  end
  for _, k in ipairs(spec.keys) do
    if run.all or run.keys[k.key] then
      local text, source, reason
      if k.kind == 'text' or k.kind == 'block' then
        text, source, reason = L.Text(k.key)
        local pure, pureSource, pureReason = L.Resolve(k.key)
        if pure ~= english[k.key] or pureSource ~= 'base' or pureReason ~= nil then
          out('P', run.id, k.key, hex(pure), tostring(pureSource), tostring(pureReason))
        end
        if run.keys[k.key] then
          local et, es, er = L.Text(k.key, raw or {})
          out('E', run.id, k.key, tostring(es), tostring(er), hex(et))
        end
      else
        text, source, reason = L.Format(k.key, args(k))
        if run.keys[k.key] then
          local et, es, er = L.Format(k.key, args(k), raw or {})
          out('E', run.id, k.key, tostring(es), tostring(er), hex(et))
        end
      end
      out('R', run.id, k.key, tostring(source), tostring(reason), hex(text))
    end
  end
  for _, probe in ipairs(spec.probes) do
    local chunk, err = loadstring(probe.code, '=' .. probe.id)
    local ok, shown = false, err
    if chunk then ok, shown = pcall(chunk) end
    out('X', run.id, probe.id, ok and 'ok' or 'error', hex(shown))
  end
end
out('END')
'''


def find_luajit(explicit=None):
    return explicit or shutil.which('luajit')


def _runs(model, probes):
    """One complete run per optional language, then a missing and an invalid variant of the
    probe keys in each, so each receiver is seen with its candidate and both fallbacks."""
    keys = sorted({probe['key'] for probe in probes if probe['key'] in model['active']})
    runs = []
    for product in model['optionalIds']:
        runs.append({'id': 'complete:' + product, 'lang': product, 'all': True, 'remove': [],
                     'replace': {}, 'keys': {}})
        runs.append({'id': 'missing:' + product, 'lang': product, 'all': False, 'remove': keys,
                     'replace': {}, 'keys': {key: True for key in keys}})
        runs.append({'id': 'invalid:' + product, 'lang': product, 'all': False, 'remove': [],
                     'replace': {key: 'invalid|entry' for key in keys}, 'keys': {key: True for key in keys}})
    return runs


def _run_entries(model, run):
    pack = model['packs'].get(run['lang'])
    entries = dict(pack['entries']) if pack else {}
    for key in run['remove']:
        entries.pop(key, None)
    entries.update(run['replace'])
    return entries


def _admitted(model, entries):
    """The entries the runtime copies from one pack: valid entries of active keys."""
    return {key: text for key, text in entries.items() if valid_key(key) and key in model['active']
            and entry_valid(model['declarations'][key], text)}


def _arguments(declaration):
    return {name: ('7' if slot == 'count' else 's')
            for name, slot in zip(declaration['fields'], declaration['slots'])}


def predict(model, key, entries, explicit, values=None):
    """(source, reason, text) the seam gives for key with this pack (explicit: Resolve with a
    supplied pack; otherwise the session's admitted pack, None while English is active)."""
    declaration = model['declarations'][key]
    english = model['active'][key]
    candidate = None if entries is None else entries.get(key)
    admitted = candidate is not None and entry_valid(declaration, candidate)
    if entries is None:
        missing = None
    elif explicit and candidate is not None:
        missing = 'invalid_candidate'
    else:
        missing = 'missing_candidate'
    if declaration['kind'] in ('text', 'block'):
        if admitted:
            return 'candidate', None, candidate
        return 'base', missing, english
    values = values or _arguments(declaration)
    lines = declaration.get('lines', False)
    if admitted:
        text = render(compile_template(candidate, declaration['fields'], lines), values,
                      declaration['resultLimit'])
        if text is not None:
            return 'candidate', None, text
        reason = 'output_limit'
    else:
        reason = missing
    text = render(compile_template(english, declaration['fields'], lines), values,
                  declaration['resultLimit'])
    if text is None:
        return 'unavailable', 'output_limit', UNAVAILABLE
    return 'base', reason, text


def _probe_expected(model, probe, admitted):
    def shown(key, values=None):
        return predict(model, key, admitted, False, values)[2]
    values = {}
    for name, value in (probe.get('slots') or {}).items():
        values[name] = shown(value['key']) if isinstance(value, dict) else value
    declaration = model['declarations'].get(probe['key'])
    if declaration is None:
        return None
    return shown(probe['key'], values if declaration['kind'] in ('format', 'template') else None)


def runtime_check(root, model, paths=None, probes=RECEIVER_PROBES, luajit=None, timeout=40):
    """Boot the real TOC under LuaJIT for every run and compare everything it shows with the
    predictions above. Returns (problems, evidence)."""
    root = pathlib.Path(root)
    paths = paths or {name: INPUT_PATHS[name] for name in ('english', 'packs', 'localization')}
    problems, evidence = [], {'scope': RECEIVER_SCOPE, 'probes': [], 'runs': []}
    executable = find_luajit(luajit)
    if not executable:
        problems.append(_problem('runtime-unavailable', 'luajit', detail='no luajit on PATH; '
                                 'the runtime cross-check is NOT_RUN and the gate fails'))
        evidence['status'] = 'NOT_RUN'
        return problems, evidence
    probes = [probe for probe in probes]
    for probe in probes:
        if probe['key'] not in model['active']:
            problems.append(_problem('receiver-key-inactive', 'probe ' + probe['id'], probe['key']))
    runs = _runs(model, probes)
    declarations = model['declarations']
    keys = [{'key': key, 'kind': declarations[key]['kind'],
             'fields': list(declarations[key].get('fields', ())),
             'slots': list(declarations[key].get('slots', ()))} for key in model['active']]
    spec = 'return ' + _lua_value({
        'english': paths['english'], 'packs': paths['packs'], 'localization': paths['localization'],
        'runs': runs, 'keys': keys,
        'probes': [{'id': probe['id'], 'code': probe['code']} for probe in probes]})
    with tempfile.TemporaryDirectory(prefix='nexus-l10n-gate-') as scratch:
        spec_path = pathlib.Path(scratch) / 'spec.lua'
        driver_path = pathlib.Path(scratch) / 'driver.lua'
        spec_path.write_text(spec, encoding='utf-8')
        driver_path.write_text(DRIVER, encoding='utf-8')
        start = time.monotonic()
        try:
            process = subprocess.run([executable, str(driver_path), str(spec_path)], cwd=root,
                                     capture_output=True, timeout=timeout)
        except (OSError, subprocess.TimeoutExpired) as error:
            problems.append(_problem('runtime-failed', 'luajit', detail='%s: %s' % (type(error).__name__, error)))
            evidence['status'] = 'FAILED'
            return problems, evidence
        evidence.update({'executable': executable, 'exit': process.returncode,
                         'seconds': round(time.monotonic() - start, 3)})
    lines = [line.split('\t')[1:] for line in process.stdout.decode('utf-8', 'replace').splitlines()
             if line.startswith('@@NXG@@\t')]
    if process.returncode != 0 or not lines or lines[-1] != ['END']:
        problems.append(_problem('runtime-failed', 'luajit', detail='exit %s; stderr %s' % (
            process.returncode, process.stderr.decode('utf-8', 'replace')[-1500:])))
        evidence['status'] = 'FAILED'
        return problems, evidence
    rows = {}
    for row in lines[:-1]:
        rows.setdefault((row[0], row[1]), []).append(row[2:])
    unhex = lambda value: bytes.fromhex(value).decode('utf-8', 'replace')
    for run in runs:
        rid = run['id']
        entries = _run_entries(model, run)
        admitted = _admitted(model, entries) if _adopted(model, run['lang'], entries) else None
        _compare_load(model, run, rows, problems)
        seen = {}
        for key, source, reason, text in rows.get(('R', rid), []):
            seen[key] = (source, None if reason == 'nil' else reason, unhex(text))
        expected_keys = list(model['active']) if run['all'] else sorted(run['keys'])
        mismatched = [key for key in expected_keys if seen.get(key) != predict(model, key, admitted, False)]
        if mismatched:
            problems.append(_problem('runtime-seam-mismatch', rid, mismatched[0],
                                     detail='%d keys; first runtime %r, predicted %r' % (
                                         len(mismatched), seen.get(mismatched[0]),
                                         predict(model, mismatched[0], admitted, False))))
        for key, source, reason, text in rows.get(('E', rid), []):
            got = (source, None if reason == 'nil' else reason, unhex(text))
            if got != predict(model, key, entries, True):
                problems.append(_problem('runtime-explicit-mismatch', rid, key, detail=repr(got)))
        for row in rows.get(('P', rid), []):
            problems.append(_problem('runtime-resolve-not-pure', rid, row[0]))
        texts = {}
        for key in model['active']:
            if declarations[key]['kind'] in ('text', 'block'):
                texts.setdefault(predict(model, key, admitted, False)[2], key)
        for probe_id, status, shown in rows.get(('X', rid), []):
            probe = next(probe for probe in probes if probe['id'] == probe_id)
            want = _probe_expected(model, probe, admitted)
            got = unhex(shown)
            code = None
            segment = probe.get('match') == 'segment'
            if status != 'ok':
                code = 'receiver-error'
            elif not want or (want not in got if segment else got != want):
                english = _probe_expected(model, probe, {})
                if want != english and (english in got if segment else got == english):
                    code = 'receiver-not-localized'
                elif not segment and got in texts and texts[got] != probe['key']:
                    code = 'receiver-wrong-key'
                else:
                    code = 'receiver-mismatch'
            source = (predict(model, probe['key'], admitted, False)[0]
                      if probe['key'] in model['active'] else None)
            evidence['probes'].append({'run': rid, 'probe': probe_id, 'key': probe['key'],
                                       'source': source, 'result': code or 'PASS'})
            if code:
                problems.append(_problem(code, rid, probe['key'], detail='probe %s shows %r, predicted %r'
                                         % (probe_id, got[:120], (want or '')[:120])))
        evidence['runs'].append({'id': rid, 'keysChecked': len(expected_keys)})
    evidence['status'] = 'RAN'
    return problems, evidence


def _adopted(model, product, entries):
    pack = model['packs'].get(product)
    name = pack.get('name') if pack else None
    return bool(pack and valid_text(name) and len(name.encode('utf-8')) <= CONTRACT['MAX_NAME_BYTES']
                and len(entries) <= MAX_ENTRIES)


def _compare_load(model, run, rows, problems):
    """The base, pack and language load facts of one boot."""
    rid = run['id']
    declarations, active, english = model['declarations'], model['active'], model['english']
    if len(english) > MAX_ENTRIES:
        base = ['true', '0', str(len(english)), 'true', '0', '0', str(len(declarations))]
    else:
        base = ['true', str(len(active)), str(len(english) - len(active)), 'false',
                str(sum(1 for key in active if declarations[key]['kind'] in ('format', 'template'))),
                str(sum(1 for key in english if key not in declarations)),
                str(len(declarations) - len(active))]
    adopted, refused, pack_rows, names = 0, 0, [], [(ENGLISH_ID, 'English')]
    for product in model['optionalIds']:
        pack = model['packs'].get(product)
        entries = (_run_entries(model, run) if product == run['lang']
                   else (dict(pack['entries']) if pack else {}))
        if _adopted(model, product, entries):
            count = len(_admitted(model, entries))
            adopted += 1
            pack_rows.append([product, str(count), str(len(entries) - count)])
            names.append((product, pack['name']))
        else:
            refused += 1
    expected = base + [str(adopted), str(refused),
                       run['lang'] if run['lang'] in dict(names) else ENGLISH_ID]
    got = rows.get(('B', rid), [None])[0]
    if got != expected:
        problems.append(_problem('runtime-load-mismatch', rid, detail='base/packs %r, predicted %r' % (
            got, expected)))
    if rows.get(('W', rid), []) != pack_rows:
        problems.append(_problem('runtime-load-mismatch', rid, detail='pack rows %r, predicted %r' % (
            rows.get(('W', rid)), pack_rows)))
    shown = [(row[0], bytes.fromhex(row[1]).decode('utf-8', 'replace')) for row in rows.get(('G', rid), [])]
    if shown != names:
        problems.append(_problem('runtime-load-mismatch', rid, detail='languages %r, predicted %r' % (
            shown, names)))


# ---------------------------------------------------------------------------------------------
# Provenance and the archive binding.

def _git(root, *arguments):
    try:
        run = subprocess.run(['git', *arguments], cwd=root, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return run.stdout.decode('utf-8', 'replace').strip() if run.returncode == 0 else None


def source_identity(root, names=tuple(INPUT_PATHS)):
    """Commit, tree and per-input Git blob observations, or UNKNOWN without Git. The worktree
    blob is hashed by Git with the checkout's attributes; equal to the index blob, the supplied
    bytes are the checkout of that blob, whatever their physical line ends. Four Git processes
    in all: one per fact, each over every input."""
    head = (_git(root, 'rev-parse', 'HEAD', 'HEAD^{tree}') or '').split()
    if len(head) != 2:
        return {'status': 'UNKNOWN', 'reason': 'not a Git checkout or Git unavailable'}
    paths = [INPUT_PATHS[name] for name in names]
    staged = {}
    for line in (_git(root, 'ls-files', '-s', '--', *paths) or '').splitlines():
        fields, _, path = line.partition('\t')
        if len(fields.split()) == 3:
            staged[path] = fields.split()[1]
    hashed = (_git(root, 'hash-object', '--', *paths) or '').split()
    worktree = dict(zip(paths, hashed)) if len(hashed) == len(paths) else {}
    rows = [{'path': path, 'indexBlob': staged.get(path), 'worktreeBlob': worktree.get(path),
             'matchesIndex': bool(staged.get(path)) and staged.get(path) == worktree.get(path)}
            for path in paths]
    status = _git(root, 'status', '--porcelain', '--', *paths)
    return {'status': 'OBSERVED', 'commit': head[0], 'tree': head[1], 'inputsClean': status == '',
            'blobs': rows}


ARCHIVE_SCOPE = ('four localization runtime-input members only (Nexus/data/DefaultProfile.lua, '
                 'Nexus/data/LocalizationEnglish.lua, Nexus/data/LocalizationPacks.lua, '
                 'Nexus/core/Localization.lua); not the whole archive: the package inventory, TOC, Release, '
                 'notices, every other source file and the packaged or delivered revision are not compared')


def check_archive(archive: bytes, sources, problems):
    """The four localization runtime-input members of a package archive against the supplied bytes
    (ARCHIVE_SCOPE, ARCHIVE_CONTRACT). Agreement is FOUR_MEMBER_SUBSET_MATCHED: it says nothing
    about any other member or about which revision was packaged."""
    rows = []
    try:
        bundle = zipfile.ZipFile(io.BytesIO(archive))
    except zipfile.BadZipFile as error:
        problems.append(_problem('archive-unreadable', 'archive', detail=str(error)))
        return {'status': 'REFUSED', 'scope': ARCHIVE_SCOPE}
    with bundle:
        members = set(bundle.namelist())
        for name in RUNTIME_INPUTS:
            path = INPUT_PATHS[name]
            member = 'Nexus/' + path
            expected = _basis_bytes(sources[name], 'crlf-as-lf')
            if member not in members:
                problems.append(_problem('archive-member-missing', member))
                rows.append({'member': member, 'result': 'MISSING'})
                continue
            data = bundle.read(member)
            same = expected is not None and data == expected
            if not same:
                problems.append(_problem('archive-mismatch', member))
            rows.append({'member': member, 'sha256': sha256(data), 'result': 'MATCHED' if same else 'MISMATCH'})
    matched = all(row['result'] == 'MATCHED' for row in rows)
    return {'status': 'FOUR_MEMBER_SUBSET_MATCHED' if matched else 'REFUSED', 'scope': ARCHIVE_SCOPE,
            'sha256': sha256(archive), 'contract': ARCHIVE_CONTRACT, 'members': rows}


# ---------------------------------------------------------------------------------------------
# The whole gate and its command line.

def read_sources(root):
    return {name: (pathlib.Path(root) / path).read_bytes() for name, path in INPUTS}


def gate(root=ROOT, sources=None, receipt=None, require_receipt=False, archive=None, luajit=None,
         probes=RECEIVER_PROBES, paths=None):
    """Static gate, runtime cross-check, provenance and optional bindings over one root."""
    root = pathlib.Path(root)
    sources = sources or read_sources(root)
    report = evaluate(sources, receipt, require_receipt)
    model = report.pop('model')
    runtime_problems, runtime = runtime_check(root, model, paths, probes, luajit)
    report['problems'].extend(runtime_problems)
    report['runtime'] = runtime
    after = read_sources(root) if paths is None else None
    if after is not None and after != sources:
        report['problems'].append(_problem('input-changed', str(root), detail='an input changed during the gate'))
    report['sourceIdentity'] = source_identity(root)
    report['archive'] = (check_archive(archive, sources, report['problems'])
                         if archive is not None else {'status': 'NOT_SUPPLIED'})
    report['coverage'] = coverage(report, model, probes)
    report['verdict'] = 'FAIL' if report['problems'] else 'PASS'
    report['notEvidenceOf'] = ('fluent or human translation acceptance, rights, native glyph, '
                               'font, layout, reload or full visible-UI completeness')
    return report


def coverage(report, model, probes):
    """Three separate facts: catalog validity, every-key seam resolution and the listed real display
    receivers, each with its own scope. Neither count proves that every UI consumer uses its key."""
    runtime = report.get('runtime', {})
    complete_runs = [row for row in runtime.get('runs', []) if row['id'].startswith('complete:')]
    outcomes = {}
    for row in runtime.get('probes', []):
        condition, product = row['run'].split(':', 1)
        outcomes.setdefault(row['probe'], {}).setdefault(condition, {})[product] = '%s (%s shown)' % (
            row['result'], row['source'])
    return {
        'catalog': {'activeKeys': len(model['active']), 'products': list(model['optionalIds']),
                    'scope': 'declarations, English, key context, TOC, languages and every pack entry, '
                             'checked statically over the supplied bytes'},
        'seam': {'keysPerRun': complete_runs[0]['keysChecked'] if complete_runs else 0,
                 'completeRuns': len(complete_runs),
                 'scope': 'every active key resolved through L.Text / L.Format of the session pack in the '
                          'real TOC boot; a seam result, not a display: it does not show that any UI '
                          'consumer uses the key'},
        'displayReceivers': {'scope': RECEIVER_SCOPE, 'probes': [
            {'id': probe['id'], 'key': probe['key'], 'receiver': probe.get('receiver', 'UNSPECIFIED'),
             'match': probe.get('match', 'exact'), 'outcomes': outcomes.get(probe['id'], {})}
            for probe in probes]},
    }


def summary_lines(report, limit=12):
    lines = []
    identity = report.get('sourceIdentity', {})
    lines.append('source: commit %s tree %s inputsClean %s' % (
        identity.get('commit', 'UNKNOWN'), identity.get('tree', 'UNKNOWN'), identity.get('inputsClean', 'UNKNOWN')))
    for row in report['inputs']:
        lines.append('input: %s sha256 %s bytes %d' % (row['path'], row['sha256'], row['bytes']))
    catalog = report.get('catalog', {})
    lines.append('catalog: declared %s, English %s, active %s, by kind %s, lines %s' % (
        catalog.get('declared'), catalog.get('english'), catalog.get('active'), catalog.get('byKind'),
        catalog.get('lines')))
    for product in report.get('products', []):
        counts = ', '.join('%s %d' % (name, count) for name, count in product['counts'].items())
        lines.append('pack %s: %s; %s' % (product['productId'],
                                          'complete' if product['complete'] else 'INCOMPLETE', counts))
    runtime = report.get('runtime', {})
    probes = runtime.get('probes', [])
    lines.append('runtime: %s; %d runs; receiver probes %d PASS of %d (%s)' % (
        runtime.get('status'), len(runtime.get('runs', [])),
        sum(1 for row in probes if row['result'] == 'PASS'), len(probes), RECEIVER_SCOPE))
    for row in (report.get('coverage') or {}).get('displayReceivers', {}).get('probes', []):
        shown = '; '.join('%s %s' % (condition, ','.join(sorted(set(results.values()))))
                          for condition, results in sorted(row['outcomes'].items()))
        lines.append('receiver %s: %s via %s: %s' % (row['id'], row['key'], row['receiver'], shown or 'NOT_RUN'))
    receipt, archive = report['compositionReceipt'], report['archive']
    lines.append('receipt: %s%s; archive: %s%s' % (
        receipt.get('status'),
        ' (current inputs and shape only; prior version and lineage NOT_VERIFIED)'
        if receipt.get('status') != 'NOT_SUPPLIED' else '',
        archive.get('status'),
        ' (four localization runtime-input members only; not the whole archive or the packaged revision)'
        if archive.get('status') != 'NOT_SUPPLIED' else ''))
    by_code = {}
    for problem in report['problems']:
        by_code.setdefault(problem['code'], []).append(problem)
    for code, rows in sorted(by_code.items()):
        lines.append('FAIL %s: %d' % (code, len(rows)))
        for row in rows[:limit]:
            lines.append('  ' + json.dumps(row, ensure_ascii=False)[:300])
    lines.append('RESULT: %s (%d problems); not evidence of %s' % (
        report['verdict'], len(report['problems']), report['notEvidenceOf']))
    return lines


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', type=pathlib.Path, default=ROOT)
    parser.add_argument('--output', type=pathlib.Path)
    parser.add_argument('--receipt', type=pathlib.Path)
    parser.add_argument('--require-receipt', action='store_true')
    parser.add_argument('--archive', type=pathlib.Path)
    parser.add_argument('--luajit')
    ns = parser.parse_args(argv)
    try:
        receipt = ns.receipt.read_bytes() if ns.receipt else None
        archive = ns.archive.read_bytes() if ns.archive else None
        sources = read_sources(ns.root)
    except OSError as error:
        print('UNREADABLE: %s' % error)
        return 2
    report = gate(ns.root, sources, receipt, ns.require_receipt, archive, ns.luajit)
    for line in summary_lines(report):
        print(line)
    if ns.output:
        ns.output.write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding='utf-8')
    return 0 if report['verdict'] == 'PASS' else 1


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    raise SystemExit(main())
