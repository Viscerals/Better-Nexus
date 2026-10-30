#!/usr/bin/env python3
"""Syntax foundation, pure schema API, pure coverage report API and read-only
report command line for the Nexus localization data (#147).

Status: IMPLEMENTED_DRAFT_REVIEW_PENDING. parse_english and parse_packs
below check syntax only, and a successful parse alone does not make a catalog
valid. validate_catalog_data, appended after them, is a pure in-memory schema
API: from the exact bytes of the English base, the packs file, KEY_CONTEXT.json
and RELEASE_LANGUAGES.json it checks keys, text, the charge template grammar,
pack IDs, autonyms and entries, the key-context rows and the release product
metadata against the runtime contract of core/Localization.lua, and raises
CatalogValidationError (stable .code) on a semantic failure. Missing translated
entries are valid partial data. catalog_report, appended after that, is a pure
in-memory coverage and evidence report API. It first calls
validate_catalog_data on the same four byte strings, unchanged, so an invalid
catalog gets no counts. It then derives a deterministic report dict with input
SHA-256 hashes, per-product and per-window-family entry categories over the
actual English keys, English keys without a family and concrete completeness
reasons. Invalid entry-review declarations or family metadata raise
CatalogEvidenceError (stable .code). A structurally qualified review
declaration is not evidence of fluent competence, contributor rights or native
truth. main(), appended last, is the bounded read-only confined-root command
line (B3b) around catalog_report. It adds only root, input and Nexus.toc
load-order checks (CatalogCliError, stable .code) and passes the exact input
bytes to catalog_report unchanged. The legacy fullValidation value
IMPLEMENTED_DRAFT denotes a scoped draft for the currently adopted static
keys and the single code-owned charge-count template, not whole #147;
NOTICE['validationScope'], copied into the catalog_report and command-line
report records, states that plural variants, dynamic-key coverage per
family, runtime load/fallback parity, per-pack translator provenance/rights
and approved terminology validation are not implemented by this component.
Required-CI registration is implemented in source:
tools/tests/test_l10n_catalog.py is registered in PYTHON_TESTS of
tools/run_prototype_tests.py, and tools/ci_check.py runs it as its own
process. Independent review and the human, native and UI gates are still
pending. Author execution of the registered tests is NOT_RUN, and host and
hosted-CI receipts are recorded separately. No schema validity, report or
command-line record claims that a catalog is reviewed, complete or
displayable.

Public seam:

    parse_english(source: bytes) -> dict
        semantic key -> text, from the bytes of data/LocalizationEnglish.lua
    parse_packs(source: bytes) -> dict
        pack ID -> {"name": text, "entries": {key: text}}
    CatalogSyntaxError
        .code (stable, one of CODES), .line and .column (1-based, counted in
        characters, at the start of the token; None for not-utf8)

Both functions take the exact bytes of a source (bytes or bytearray), never a
filename. They read and write no file. They never evaluate, import or execute
Lua, never call back into the data and never interpret its text. After Lua 5.1
whitespace and short or long comments, which may appear between any tokens,
the only accepted form is

    Nexus = Nexus or {}
    Nexus.LocalizationEnglish = { ["key"] = "text", ... }

or

    Nexus = Nexus or {}
    Nexus.LocalizationPacks = {
        packID = { name = "text", entries = { ["key"] = "text", ... } }, ...
    }

followed by the end of the source. A key is a bracketed literal string. A pack
ID is either a bare Lua name that is not a reserved word or a bracketed literal
string. Each pack has exactly the bare fields name and entries, once each, in
either order. Items are separated by commas, and a comma after the last item is
optional. A semicolon is not accepted anywhere, not even after the table.

Any other token is an error. This includes a prefix, suffix, statement,
expression, concatenation, call, function, metatable, number, boolean, nil, and
a nested or computed key or value. No general Lua grammar is implemented. Empty
tables and empty strings are valid syntax; their meaning is a question for the
later validator.

A literal string is either a short string with the Lua 5.1 escapes or a
long-bracket string. Both are lexed by the Scanner of the trusted sibling
tools/l10n_inventory.py, whose Lua 5.1 behaviour is authoritative here (LuaJIT
and Lua 5.2 escapes are not recognised). That module is compiled in memory from
its own file path. No bytecode cache is written for it, and nothing is looked
up on sys.path or in an input root. As in the default Lua 5.1 build, a level-0
long string or comment that contains [[ is also refused.

The source must be strict UTF-8; a byte order mark is an unexpected token.
Every decoded string value must also be strict UTF-8, so escapes cannot produce
invalid UTF-8 or surrogates. Values are returned exactly as decoded. They are
never normalized, transliterated or repaired. Duplicates are compared on the
decoded values before anything is stored, so differently escaped equal keys
count as duplicates. Decoding proves lexical data integrity only. It does not
prove that any client can display the text.

Error codes (CODES):
    not-utf8             the source is not strict UTF-8
    value-not-utf8       a decoded string value is not strict UTF-8
    unfinished-string    a string is not closed (from the scanner)
    unfinished-comment   a long comment is not closed (from the scanner)
    invalid-escape       a decimal escape is above 255 (from the scanner)
    nested-long-bracket  [[ inside a level-0 long string or comment
    bad-bootstrap        the source does not start with Nexus = Nexus or {}
    bad-assignment       the expected Nexus.<table> = { does not follow
    unexpected-token     a token the grammar does not allow there
    unexpected-end       the source ends inside the table
    trailing-content     anything but whitespace or comments after the table
    duplicate-key        a key repeated in one table
    duplicate-pack       a pack ID repeated
    duplicate-field      name or entries repeated in one pack
    unknown-field        a pack field other than name and entries
    missing-field        a pack without name or without entries

Run directly, this file is the read-only report command line:

    python tools/l10n_catalog.py [--root DIR] [--require-complete]

DIR defaults to the repository that contains this tool, never the current
directory. Inside the resolved root it reads exactly
data/LocalizationEnglish.lua, data/LocalizationPacks.lua,
docs/localization/KEY_CONTEXT.json, docs/localization/RELEASE_LANGUAGES.json
and Nexus.toc as bytes, each of which must resolve, through any symlink or
junction, to a regular readable file inside the root. Nexus.toc is read as
UTF-8 data: slash and backslash separators are treated alike, blank, comment
and metadata lines are ignored, and data/LocalizationEnglish.lua,
data/LocalizationPacks.lua and core/Localization.lua must each appear exactly
once, in that order; no other TOC module is opened. The four catalog inputs
then go unchanged to catalog_report. A valid report is one ASCII JSON record
on stdout with the TOC hash, technical dictionary counts kept apart from
external readiness, and exit status 0, also for partial data. With
--require-complete the exit status is 1 while external readiness is not
established; at this stage it never is, because no trusted external
acceptance-record contract exists. An argument, root, input, TOC, syntax,
schema or evidence failure writes one ASCII JSON error record with a stable
code on stderr and exits 2. Nothing is written, imported from the root,
executed, fetched or read from Git. Python 3.9+, standard library only.
"""
from __future__ import annotations

import json
import pathlib
import sys
import types
from collections import namedtuple

STATUS = 'IMPLEMENTED_DRAFT_REVIEW_PENDING'
CODES = (
    'not-utf8', 'value-not-utf8', 'unfinished-string', 'unfinished-comment',
    'invalid-escape', 'nested-long-bracket', 'bad-bootstrap', 'bad-assignment',
    'unexpected-token', 'unexpected-end', 'trailing-content', 'duplicate-key',
    'duplicate-pack', 'duplicate-field', 'unknown-field', 'missing-field',
)
NOTICE = {
    'record': 'notice',
    'tool': 'tools/l10n_catalog.py',
    'status': STATUS,
    'fullValidation': 'IMPLEMENTED_DRAFT',
    'validationScope': 'Scoped draft for currently adopted static keys and the single code-owned charge-count template; not whole #147. Plural variants, dynamic-key coverage per family, runtime load/fallback parity, per-pack translator provenance/rights and approved terminology validation are not implemented by this component.',
    'message': 'scoped static-catalog draft registered in source for required CI; independent review and human, native and full-UI gates pending',
}

_INVENTORY = pathlib.Path(__file__).resolve().parent / 'l10n_inventory.py'


def _load_lexer():
    """Load the trusted sibling tools/l10n_inventory.py, compiled in memory from
    its own file. Unlike an import, this writes no bytecode cache and looks
    nothing up on sys.path. Its command line does not run, because its
    __name__ is not __main__."""
    path = str(_INVENTORY)
    module = types.ModuleType('_nexus_l10n_inventory_lexer')
    module.__file__ = path
    exec(compile(_INVENTORY.read_bytes(), path, 'exec', dont_inherit=True), module.__dict__)
    return module


_LEXER = _load_lexer()
_NEWLINE = _LEXER.NEWLINE
_SPACE = frozenset(' \t\v\f')
_NAME_START = frozenset('_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ')
_NAME_PART = _NAME_START | frozenset('0123456789')
_PUNCT = frozenset('={}[],.')
_RESERVED = frozenset((
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if',
    'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until',
    'while'))
_BOOTSTRAP = (('name', 'Nexus'), ('punct', '='), ('name', 'Nexus'), ('name', 'or'),
              ('punct', '{'), ('punct', '}'))
_FIELDS = ('name', 'entries')
_Token = namedtuple('_Token', 'kind value line column')


class CatalogSyntaxError(ValueError):
    """Raised for source bytes outside the literal data grammar. It carries a
    stable code (one of CODES) and, for a token, the line and column where
    that token starts."""

    def __init__(self, code: str, line: int = None, column: int = None):
        where = '' if line is None else ' at line %d, column %d' % (line, column)
        super().__init__(code + where)
        self.code, self.line, self.column = code, line, column


def _long_body(scanner, code, line, column):
    """Return the body of the long string or comment whose opening bracket is
    at the current position."""
    level = scanner.level()
    body = scanner.long_bracket(level, code, line, column)
    if level == 0 and '[[' in body:
        # The default Lua 5.1 build (LUA_COMPAT_LSTR) refuses [[ inside [[...]].
        raise CatalogSyntaxError('nested-long-bracket', line, column)
    return body


def _tokens(text, integers=False):
    """Return every token of text, ending with one 'eof' token. A lexical
    error raises CatalogSyntaxError. Any character outside the data grammar
    becomes an 'other' token, which the parser always refuses. Only the
    private literal-table parser (S1, at the end of this file) passes
    integers=True; parse_english and parse_packs never do, so a digit stays
    an 'other' token for them."""
    scanner = _LEXER.Scanner(text)
    tokens = []
    try:
        while True:
            char = scanner.peek()
            line, column = scanner.line, scanner.column()
            if char == '':
                tokens.append(_Token('eof', None, line, column))
                return tokens
            if char in _NEWLINE:
                scanner.newline()
            elif char in _SPACE:
                scanner.index += 1
            elif char == '-' and scanner.peek(1) == '-':
                scanner.index += 2
                if scanner.peek() == '[' and scanner.level() >= 0:
                    _long_body(scanner, 'unfinished-comment', line, column)
                else:
                    while scanner.peek() != '' and scanner.peek() not in _NEWLINE:
                        scanner.index += 1
            elif char == '[' and scanner.level() >= 0:
                value = _long_body(scanner, 'unfinished-string', line, column)
                tokens.append(_Token('string', value, line, column))
            elif char in ('"', "'"):
                raw = scanner.short_string(char, line, column)
                try:
                    value = raw.decode('utf-8')
                except UnicodeDecodeError:
                    raise CatalogSyntaxError('value-not-utf8', line, column) from None
                tokens.append(_Token('string', value, line, column))
            elif char in _NAME_START:
                start = scanner.index
                while scanner.peek() in _NAME_PART:
                    scanner.index += 1
                tokens.append(_Token('name', text[start:scanner.index], line, column))
            elif integers and char in _DIGITS:
                start = scanner.index
                while scanner.peek() in _DIGITS:
                    scanner.index += 1
                digits = text[start:scanner.index]
                if (scanner.peek() in _NAME_PART or scanner.peek() == '.'
                        or len(digits) > _LITERAL_MAX_DIGITS
                        or (len(digits) > 1 and digits[0] == '0')):
                    tokens.append(_Token('other', digits, line, column))
                else:
                    tokens.append(_Token('integer', int(digits), line, column))
            else:
                kind = 'punct' if char in _PUNCT else 'other'
                tokens.append(_Token(kind, char, line, column))
                scanner.index += 1
    except _LEXER.SourceError as error:
        raise CatalogSyntaxError(error.code, error.line, error.column) from None


class _Parser:
    """The literal data grammar over a token list. Each method reads tokens in
    order and raises CatalogSyntaxError at the first token it refuses."""

    def __init__(self, tokens):
        self.tokens, self.index = tokens, 0

    def fail(self, code, token):
        raise CatalogSyntaxError(code, token.line, token.column)

    @staticmethod
    def unexpected(token):
        return 'unexpected-end' if token.kind == 'eof' else 'unexpected-token'

    def at(self, kind, value):
        token = self.tokens[self.index]
        return token.kind == kind and token.value == value

    def take(self, kind, value=None, code=None):
        """Return the next token, which must have this kind (and this value,
        if one is given)."""
        token = self.tokens[self.index]
        if token.kind != kind or (value is not None and token.value != value):
            self.fail(code or self.unexpected(token), token)
        self.index += 1
        return token

    def chunk(self, target, table):
        """Read the bootstrap, the Nexus.<target> = { assignment, then
        table(), then require the end of the source."""
        for kind, value in _BOOTSTRAP:
            self.take(kind, value, 'bad-bootstrap')
        for kind, value in (('name', 'Nexus'), ('punct', '.'), ('name', target),
                            ('punct', '='), ('punct', '{')):
            self.take(kind, value, 'bad-assignment')
        result = table()
        token = self.tokens[self.index]
        if token.kind != 'eof':
            self.fail('trailing-content', token)
        return result

    def items(self, item):
        """Call item() for each item of the table whose { was just read.
        Require a comma after every item except, optionally, the last. Read
        through the closing } and return that token."""
        while not self.at('punct', '}'):
            item()
            if not self.at('punct', '}'):
                self.take('punct', ',')
        return self.take('punct', '}')

    def bracketed_string(self):
        self.take('punct', '[')
        value = self.take('string').value
        self.take('punct', ']')
        return value

    def strings(self):
        """Read a table of ["key"] = "text" items: the English table or a
        pack's entries."""
        table = {}

        def item():
            start = self.tokens[self.index]
            key = self.bracketed_string()
            if key in table:
                self.fail('duplicate-key', start)
            self.take('punct', '=')
            table[key] = self.take('string').value

        self.items(item)
        return table

    def packs(self):
        table = {}

        def item():
            start = self.tokens[self.index]
            if start.kind == 'name' and start.value not in _RESERVED:
                self.index += 1
                pack_id = start.value
            else:
                pack_id = self.bracketed_string()
            if pack_id in table:
                self.fail('duplicate-pack', start)
            self.take('punct', '=')
            self.take('punct', '{')
            table[pack_id] = self.pack()

        self.items(item)
        return table

    def pack(self):
        """Read the fields of one pack: name and entries, once each."""
        found = {}

        def item():
            start = self.tokens[self.index]
            if start.kind != 'name' or start.value in _RESERVED:
                self.fail(self.unexpected(start), start)
            if start.value not in _FIELDS:
                self.fail('unknown-field', start)
            if start.value in found:
                self.fail('duplicate-field', start)
            self.index += 1
            self.take('punct', '=')
            if start.value == 'name':
                found['name'] = self.take('string').value
            else:
                self.take('punct', '{')
                found['entries'] = self.strings()

        close = self.items(item)
        for field in _FIELDS:
            if field not in found:
                self.fail('missing-field', close)
        return {'name': found['name'], 'entries': found['entries']}


def _parse(source, target, table):
    if not isinstance(source, (bytes, bytearray)):
        raise TypeError('source must be bytes, not %s' % type(source).__name__)
    try:
        text = bytes(source).decode('utf-8')
    except UnicodeDecodeError:
        raise CatalogSyntaxError('not-utf8') from None
    parser = _Parser(_tokens(text))
    return parser.chunk(target, getattr(parser, table))


def parse_english(source: bytes) -> dict:
    """Parse the bytes of an English base file into a {key: text} dict.
    Syntax only: no key, text or template is validated."""
    return _parse(source, 'LocalizationEnglish', 'strings')


def parse_packs(source: bytes) -> dict:
    """Parse the bytes of a packs file into a
    {pack ID: {'name': text, 'entries': {key: text}}} dict.
    Syntax only: no pack ID, name, key or text is validated."""
    return _parse(source, 'LocalizationPacks', 'packs')


# ---------------------------------------------------------------------------
# B2 (Refs #147): the pure schema API. validate_catalog_data() parses the two
# Lua data files with parse_english and parse_packs above, unchanged, decodes
# the two JSON documents strictly and checks all four against the runtime
# contract of core/Localization.lua, restated below as fixed constants. It
# reads and writes no file, imports or runs no Lua or runtime code and calls
# nothing in the data. This section is only that schema API. The coverage and
# evidence report API (B3a) and the Nexus.toc order check and read-only
# command line (B3b) follow in later sections of this file. Review and native
# acceptance and native client facts stay separate; nothing here attests them.

VALIDATION_CODES = (
    'json-not-utf8', 'json-invalid', 'json-duplicate-member', 'json-nonstandard-constant',
    'json-nonfinite-number', 'json-surrogate', 'json-top-level',
    'english-empty', 'english-too-many', 'invalid-key', 'invalid-text', 'invalid-template',
    'pack-count', 'pack-english', 'pack-unknown', 'pack-missing', 'invalid-autonym',
    'pack-too-many-entries', 'orphan-entry',
    'context-schema', 'context-source', 'context-structure', 'context-limit',
    'context-grammar', 'context-duplicate-key', 'context-key-mismatch',
    'context-english-mismatch', 'context-kind', 'context-meaning', 'context-placeholders',
    'context-result-limit',
    'release-schema', 'release-validator', 'release-structure', 'release-duplicate-product',
    'release-products', 'release-product-kind', 'release-client-locale',
    'release-text-source', 'release-autonym',
)

# Runtime limits and the code-owned format schema of core/Localization.lua. A
# key-context document is checked against these; it cannot redefine them.
_MAX_KEY_BYTES = 64
_MAX_TEXT_BYTES = 256
_MAX_BASE_ENTRIES = 64
_MAX_NAME_BYTES = 64
_MAX_LANGUAGES = 16
_ASCII_WHITESPACE = (9, 10, 11, 12, 13, 32)
_SLOT_TYPE = 'count'
_FORMAT_FIELDS = types.MappingProxyType({'readout.charge_counts': ('banish', 'reroll', 'freeze')})
_FORMAT_LIMITS = types.MappingProxyType({'readout.charge_counts': _MAX_TEXT_BYTES - 2})
_LITERAL_BRACES = {'{{': '{', '}}': '}'}
_CONTRACT_KIND = 'declarative_metadata_only'
_AUTHORITY = 'core/Localization.lua'
_ENGLISH_SOURCE = 'data/LocalizationEnglish.lua'
_PACKS_SOURCE = 'data/LocalizationPacks.lua'
_TOOL_PATH = 'tools/l10n_catalog.py'
_ENGLISH_ID, _ENGLISH_NAME = 'enUS', 'English'
_BASELINE, _OPTIONAL = 'english_baseline', 'optional_ui_pack'
_PRODUCT_ROLES = (('enUS', _BASELINE), ('frFR', _OPTIONAL), ('deDE', _OPTIONAL),
                  ('esES', _OPTIONAL), ('plPL', _OPTIONAL), ('ptBR', _OPTIONAL),
                  ('ruRU', _OPTIONAL))
_KEY_START = frozenset('abcdefghijklmnopqrstuvwxyz')
_KEY_PART = _KEY_START | frozenset('0123456789_')
_INFINITY = float('inf')


class CatalogValidationError(ValueError):
    """Raised by validate_catalog_data for decoded data outside the schema or
    the runtime contract. It carries a stable code (one of VALIDATION_CODES)
    and, when known, the path in the input and the key or ID concerned."""

    def __init__(self, code: str, path: str = None, key=None):
        detail = '' if path is None else ' at ' + path
        if key is not None:
            detail += ' (%r)' % (key,)
        super().__init__(code + detail)
        self.code, self.path, self.key = code, path, key


def _require(condition, code, path, key=None):
    if not condition:
        raise CatalogValidationError(code, path, key)


def _is_int(value, expected):
    """True only for a JSON integer equal to expected (never a bool or float)."""
    return type(value) is int and value == expected


def _is_str_list(value):
    return type(value) is list and all(type(item) is str for item in value)


def _json_members(pairs):
    """object_pairs_hook: refuse a repeated member before anything is stored."""
    members = {}
    for name, value in pairs:
        if name in members:
            raise CatalogValidationError('json-duplicate-member', key=name)
        members[name] = value
    return members


def _json_constant(name):
    raise CatalogValidationError('json-nonstandard-constant', key=name)


def _json_float(literal):
    value = float(literal)
    if value in (_INFINITY, -_INFINITY):
        raise CatalogValidationError('json-nonfinite-number', key=literal)
    return value


def _has_surrogate(text):
    return any(0xD800 <= ord(char) <= 0xDFFF for char in text)


def _strict_json(source, where):
    """Decode one JSON object from strict UTF-8 bytes, without any repair."""
    try:
        text = bytes(source).decode('utf-8')
    except UnicodeDecodeError:
        raise CatalogValidationError('json-not-utf8', where) from None
    try:
        document = json.loads(text, object_pairs_hook=_json_members,
                              parse_constant=_json_constant, parse_float=_json_float)
    except CatalogValidationError as error:
        raise CatalogValidationError(error.code, where, error.key) from None
    except (ValueError, RecursionError):
        raise CatalogValidationError('json-invalid', where) from None
    if type(document) is not dict:
        raise CatalogValidationError('json-top-level', where)
    stack = [(document, where)]
    while stack:
        value, path = stack.pop()
        if type(value) is str:
            _require(not _has_surrogate(value), 'json-surrogate', path)
        elif type(value) is dict:
            for name, item in value.items():
                _require(not _has_surrogate(name), 'json-surrogate', path)
                stack.append((item, '%s.%s' % (path, name)))
        elif type(value) is list:
            stack.extend((item, '%s[%d]' % (path, index)) for index, item in enumerate(value))
    return document


def _valid_key(key):
    """3 to 64 bytes; two or more dot-separated segments of lower-case ASCII
    letters, digits and _, each starting with a letter."""
    if type(key) is not str or not 3 <= len(key) <= _MAX_KEY_BYTES:
        return False
    segments = key.split('.')
    return len(segments) >= 2 and all(
        segment and segment[0] in _KEY_START and all(char in _KEY_PART for char in segment)
        for segment in segments)


def _valid_text(text, limit=_MAX_TEXT_BYTES):
    """The runtime text contract on the exact UTF-8 bytes: 1 to limit bytes, a
    byte outside ASCII whitespace, no byte 0-31, 127 or |. Other Unicode
    scalars are allowed and nothing is normalized."""
    if type(text) is not str:
        return False
    try:
        data = text.encode('utf-8')
    except UnicodeEncodeError:
        return False
    if not 1 <= len(data) <= limit:
        return False
    if all(byte in _ASCII_WHITESPACE for byte in data):
        return False
    return not any(byte < 32 or byte == 127 or byte == 124 for byte in data)


def _valid_template(text, fields):
    """The text contract plus the named count-template grammar: each field as
    {name} exactly once in any order, {{ and }} literal braces, every other
    character (% included) literal. Nothing is rendered or substituted."""
    if not _valid_text(text):
        return False
    seen, index, length = set(), 0, len(text)
    while index < length:
        char = text[index]
        if char == '{':
            if text.startswith('{', index + 1):
                index += 2
                continue
            close = text.find('}', index + 1)
            if close < 0:
                return False
            name = text[index + 1:close]
            if name not in fields or name in seen:
                return False
            seen.add(name)
            index = close + 1
        elif char == '}':
            if not text.startswith('}', index + 1):
                return False
            index += 2
        else:
            index += 1
    return len(seen) == len(fields)


def _check_value(text, key, path):
    fields = _FORMAT_FIELDS.get(key)
    if fields is None:
        _require(_valid_text(text), 'invalid-text', path, key)
    else:
        _require(_valid_template(text, fields), 'invalid-template', path, key)


def _slots_match(placeholders, fields):
    names = []
    for slot in placeholders:
        if type(slot) is not dict or set(slot) != {'name', 'type'}:
            return False
        if type(slot['name']) is not str or slot['type'] != _SLOT_TYPE:
            return False
        names.append(slot['name'])
    return len(names) == len(fields) and set(names) == set(fields)


def _check_english(english):
    _require(len(english) > 0, 'english-empty', 'english')
    _require(len(english) <= _MAX_BASE_ENTRIES, 'english-too-many', 'english')
    for key, text in english.items():
        _require(_valid_key(key), 'invalid-key', 'english', key)
        _check_value(text, key, 'english')


def _check_context(document, english):
    """The key-context document: header, containers, the limits this stage
    uses, and one row per English key whose kind, English text, meaning,
    placeholders and result limit agree with the source and runtime schema."""
    where = 'keyContext'
    _require(document.get('schema') == 'nexus.l10n.key_context', 'context-schema',
             where + '.schema')
    _require(_is_int(document.get('schemaVersion'), 1), 'context-schema', where + '.schemaVersion')
    _require(document.get('contractKind') == _CONTRACT_KIND, 'context-schema',
             where + '.contractKind')
    _require(document.get('authority') == _AUTHORITY, 'context-source', where + '.authority')
    _require(document.get('englishBase') == _ENGLISH_SOURCE, 'context-source',
             where + '.englishBase')
    for name, kind in (('keySchema', dict), ('textContract', dict), ('templateGrammar', dict),
                       ('keys', list), ('currentAdoption', dict), ('windowFamilies', list),
                       ('packCoverage', dict)):
        _require(type(document.get(name)) is kind, 'context-structure', where + '.' + name)
    _require(_is_str_list(document['currentAdoption'].get('keys')), 'context-structure',
             where + '.currentAdoption.keys')
    for index, family in enumerate(document['windowFamilies']):
        _require(type(family) is dict and _is_str_list(family.get('adoptedKeys')),
                 'context-structure', '%s.windowFamilies[%d]' % (where, index))
    key_schema, text, grammar = (document['keySchema'], document['textContract'],
                                 document['templateGrammar'])
    _require(_is_int(key_schema.get('minBytes'), 3)
             and _is_int(key_schema.get('maxBytes'), _MAX_KEY_BYTES),
             'context-limit', where + '.keySchema')
    _require(_is_int(text.get('minBytes'), 1) and _is_int(text.get('maxBytes'), _MAX_TEXT_BYTES),
             'context-limit', where + '.textContract')
    blanks = text.get('asciiWhitespaceBytes')
    _require(type(blanks) is list and all(type(byte) is int for byte in blanks)
             and sorted(blanks) == list(_ASCII_WHITESPACE),
             'context-limit', where + '.textContract.asciiWhitespaceBytes')
    _require(_is_str_list(grammar.get('invalid')), 'context-structure',
             where + '.templateGrammar.invalid')
    _require(grammar.get('literalBraces') == _LITERAL_BRACES
             and grammar.get('percentSign') == 'literal',
             'context-grammar', where + '.templateGrammar')
    rows = {}
    for index, row in enumerate(document['keys']):
        path = '%s.keys[%d]' % (where, index)
        _require(type(row) is dict, 'context-structure', path)
        key = row.get('key')
        _require(_valid_key(key), 'invalid-key', path + '.key', key if type(key) is str else None)
        _require(key not in rows, 'context-duplicate-key', path + '.key', key)
        rows[key] = (path, row)
    drift = sorted(set(english).symmetric_difference(rows))
    _require(not drift, 'context-key-mismatch', where + '.keys', drift[0] if drift else None)
    for key, (path, row) in rows.items():
        fields = _FORMAT_FIELDS.get(key)
        _require(row.get('kind') == ('text' if fields is None else 'format'),
                 'context-kind', path + '.kind', key)
        _require(type(row.get('english')) is str and row['english'] == english[key],
                 'context-english-mismatch', path + '.english', key)
        meaning = row.get('meaning')
        _require(type(meaning) is str and meaning.strip() != '', 'context-meaning',
                 path + '.meaning', key)
        placeholders = row.get('placeholders')
        _require(type(placeholders) is list, 'context-structure', path + '.placeholders', key)
        if fields is None:
            _require(placeholders == [], 'context-placeholders', path + '.placeholders', key)
            _require('resultLimitBytes' not in row, 'context-result-limit',
                     path + '.resultLimitBytes', key)
        else:
            _require(_slots_match(placeholders, fields), 'context-placeholders',
                     path + '.placeholders', key)
            _require(_is_int(row.get('resultLimitBytes'), _FORMAT_LIMITS[key]),
                     'context-result-limit', path + '.resultLimitBytes', key)


def _check_release(document):
    """The release document: header, validator status, and exactly the
    selected product IDs with their roles, text sources and the English
    autonym. Other and later fields are kept and not judged here."""
    where = 'release'
    _require(document.get('schema') == 'nexus.l10n.release_languages', 'release-schema',
             where + '.schema')
    _require(_is_int(document.get('schemaVersion'), 1), 'release-schema', where + '.schemaVersion')
    _require(document.get('contractKind') == _CONTRACT_KIND, 'release-schema',
             where + '.contractKind')
    validator = document.get('validator')
    _require(type(validator) is dict and validator.get('path') == _TOOL_PATH
             and validator.get('status') == STATUS, 'release-validator', where + '.validator')
    _require(document.get('fallbackProductId') == _ENGLISH_ID, 'release-products',
             where + '.fallbackProductId')
    products = document.get('products')
    _require(type(products) is list, 'release-structure', where + '.products')
    roles, found = dict(_PRODUCT_ROLES), {}
    for index, product in enumerate(products):
        path = '%s.products[%d]' % (where, index)
        _require(type(product) is dict, 'release-structure', path)
        for field in ('productId', 'kind', 'autonym', 'textSource'):
            _require(type(product.get(field)) is str, 'release-structure', path + '.' + field)
        product_id = product['productId']
        _require(product_id not in found, 'release-duplicate-product', path, product_id)
        _require(product_id in roles, 'release-products', path, product_id)
        _require(product['kind'] == roles[product_id], 'release-product-kind', path + '.kind',
                 product_id)
        _require(product.get('productIdIsClientLocale') is False, 'release-client-locale',
                 path + '.productIdIsClientLocale', product_id)
        source = _ENGLISH_SOURCE if product_id == _ENGLISH_ID else _PACKS_SOURCE
        _require(product['textSource'] == source, 'release-text-source', path + '.textSource',
                 product_id)
        if product_id == _ENGLISH_ID:
            _require(product['autonym'] == _ENGLISH_NAME, 'release-autonym', path + '.autonym',
                     product_id)
        found[product_id] = (path, product)
    for product_id, _ in _PRODUCT_ROLES:
        _require(product_id in found, 'release-products', where + '.products', product_id)
    return found


def _check_packs(packs, english, products):
    """The packs: within the runtime pack limit, no English pack, exactly the
    selected optional products, each autonym and entry inside the contract
    and each autonym equal to the release metadata. A missing entry is valid
    partial data and is not replaced by English."""
    where = 'packs'
    _require(len(packs) <= _MAX_LANGUAGES, 'pack-count', where)
    _require(_ENGLISH_ID not in packs, 'pack-english', where, _ENGLISH_ID)
    for pack_id in packs:
        _require(pack_id in products and pack_id != _ENGLISH_ID, 'pack-unknown', where, pack_id)
    for product_id in products:
        _require(product_id == _ENGLISH_ID or product_id in packs, 'pack-missing', where,
                 product_id)
    for pack_id, pack in packs.items():
        path = '%s[%r]' % (where, pack_id)
        _require(_valid_text(pack['name'], _MAX_NAME_BYTES), 'invalid-autonym', path + '.name',
                 pack_id)
        entries = pack['entries']
        _require(len(entries) <= _MAX_BASE_ENTRIES, 'pack-too-many-entries', path + '.entries',
                 pack_id)
        for key, text in entries.items():
            _require(_valid_key(key), 'invalid-key', path + '.entries', key)
            _require(key in english, 'orphan-entry', path + '.entries', key)
            _check_value(text, key, path + '.entries')
        product_path, product = products[pack_id]
        _require(product['autonym'] == pack['name'], 'release-autonym', product_path + '.autonym',
                 pack_id)


def validate_catalog_data(english_source: bytes, packs_source: bytes,
                          key_context_json: bytes, release_json: bytes) -> dict:
    """Validate the exact bytes of data/LocalizationEnglish.lua,
    data/LocalizationPacks.lua, docs/localization/KEY_CONTEXT.json and
    docs/localization/RELEASE_LANGUAGES.json as pure data, and return a dict
    with exactly english, packs, keyContext and release holding the decoded
    values unchanged.

    Each argument must be bytes or bytearray, else TypeError. The Lua data is
    parsed by parse_english and parse_packs, whose CatalogSyntaxError codes
    are unchanged. Each JSON document must be one object in strict UTF-8,
    without a duplicate member, NaN, Infinity, an overflowing number or a lone
    surrogate. A semantic failure raises CatalogValidationError. Missing
    translated entries are valid partial data; nothing is rendered, and this
    is not a coverage, review or evidence check."""
    for name, value in (('english_source', english_source), ('packs_source', packs_source),
                        ('key_context_json', key_context_json), ('release_json', release_json)):
        if not isinstance(value, (bytes, bytearray)):
            raise TypeError('%s must be bytes, not %s' % (name, type(value).__name__))
    english = parse_english(english_source)
    packs = parse_packs(packs_source)
    key_context = _strict_json(key_context_json, 'keyContext')
    release = _strict_json(release_json, 'release')
    _check_english(english)
    _check_context(key_context, english)
    products = _check_release(release)
    _check_packs(packs, english, products)
    return {'english': english, 'packs': packs, 'keyContext': key_context, 'release': release}


# ---------------------------------------------------------------------------
# B3a (Refs #147): the pure coverage and evidence report API. catalog_report()
# first calls validate_catalog_data above, unchanged, on the same four byte
# strings. Its TypeError, CatalogSyntaxError and CatalogValidationError
# propagate unchanged, and an invalid catalog never acquires coverage counts.
# It then checks the entry-review declaration contract (entryReview in
# RELEASE_LANGUAGES.json), the shapes of the product review gates and the
# window-family and surface metadata. Any failure raises CatalogEvidenceError
# (stable .code). Only after these checks does it derive the report. It reads
# and writes no file, fetches no reference, renders or formats no text and
# runs no Lua. The confined-root command line main() below (B3b) reads the
# exact input bytes and calls this API unchanged.

import hashlib
import re

REPORT_SCHEMA = 'nexus.l10n.coverage_report'
REPORT_SCHEMA_VERSION = 1
# The seven entry categories in report order. In a report the first six
# partition the English keys of each optional pack, and obsolete lists pack
# entries outside them. invalid and obsolete are always empty in a report,
# because validate_catalog_data rejects such input before any report exists.
ENTRY_CATEGORIES = (
    'translated_and_reviewed', 'reviewed_legitimately_identical',
    'deliberate_english_placeholder', 'draft_unreviewed', 'missing', 'invalid', 'obsolete',
)
EVIDENCE_CODES = (
    'evidence-contract', 'evidence-structure', 'evidence-field', 'evidence-type',
    'evidence-status', 'evidence-unknown-product', 'evidence-unknown-key',
    'evidence-hash-format', 'evidence-reviewer', 'evidence-reference', 'evidence-decision',
    'evidence-no-entry', 'evidence-stale', 'evidence-decision-mismatch', 'evidence-duplicate',
    'evidence-conflict', 'evidence-gate-structure', 'evidence-pseudo-product',
    'family-structure', 'family-duplicate', 'family-unknown-key', 'family-duplicate-key',
    'adoption-key', 'metadata-structure',
)
EVIDENCE_NOTICE = (
    'A structurally qualified entry-review declaration is not evidence of fluent competence, '
    'contributor rights or native truth. Root, fluent human and native acceptance remain '
    'separate gates; this report grants none of them.')

_ENTRY_CONTRACT = 'nexus.l10n.entry_review_declaration'
_DECLARATION_FIELDS = ('productId', 'key', 'translatedTextSha256', 'reviewer', 'decision',
                       'evidenceReference', 'status')
_DECLARED = 'declared'
_DECISIONS = types.MappingProxyType({'translated': 'translated_and_reviewed',
                                     'legitimately_identical': 'reviewed_legitimately_identical'})
_IN_DENOMINATOR = ENTRY_CATEGORIES[:6]
_NOT_REVIEWED = ENTRY_CATEGORIES[2:]
_SHA256_HEX = re.compile('[0-9a-f]{64}')
_HTTPS_REFERENCE = re.compile(
    'https://[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::[0-9]{1,5})?(?:[/?#][!-~]*)?')
_MAX_REVIEWER_CHARS = 128
_MAX_REFERENCE_CHARS = 512
_NOT_A_REVIEWER = frozenset(('unassigned', 'pending', 'unknown', 'none', 'not_run', 'tbd',
                             'n/a', 'null', 'anonymous', 'reviewer'))
_REPORT_INPUTS = (('english', _ENGLISH_SOURCE), ('packs', _PACKS_SOURCE),
                  ('keyContext', 'docs/localization/KEY_CONTEXT.json'),
                  ('release', 'docs/localization/RELEASE_LANGUAGES.json'))
_GATES = (('technicalAuthorReview', ()), ('fluentHumanAcceptance', ('responsibility',)),
          ('nativeAcceptance', ()))
_NATIVE_FACTS = ('clientManifest', 'clientBuild', 'clientHash', 'runtimeLocale', 'fontFace',
                 'glyphCoverage', 'nativeLayout')


class CatalogEvidenceError(ValueError):
    """Raised by catalog_report, after the catalog itself is valid, for invalid
    entry-review declarations, review-gate shapes, window-family or surface
    metadata. It carries a stable code (one of EVIDENCE_CODES) and, when
    known, the path in the input and the key or ID concerned."""

    def __init__(self, code: str, path: str = None, key=None):
        detail = '' if path is None else ' at ' + path
        if key is not None:
            detail += ' (%r)' % (key,)
        super().__init__(code + detail)
        self.code, self.path, self.key = code, path, key


def _evidence(condition, code, path, key=None):
    if not condition:
        raise CatalogEvidenceError(code, path, key)


def _nonblank(value):
    return type(value) is str and value.strip() != ''


def _text_sha256(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def _valid_reviewer(name):
    """An explicitly assigned name: 1 to 128 characters without leading or
    trailing whitespace, C0 or C1 controls or DEL, and not a placeholder such
    as UNASSIGNED or pending. The name is recorded, never verified or trusted."""
    if not 1 <= len(name) <= _MAX_REVIEWER_CHARS or name != name.strip():
        return False
    if any(ord(char) < 32 or 127 <= ord(char) <= 159 for char in name):
        return False
    return name.casefold() not in _NOT_A_REVIEWER


def _valid_reference(reference):
    """An https:// URL of printable ASCII, at most 512 characters. Only its
    form is checked; it is never fetched or resolved."""
    return (len(reference) <= _MAX_REFERENCE_CHARS
            and _HTTPS_REFERENCE.fullmatch(reference) is not None)


def _check_gates(product, path):
    """The shapes of the three declared review gates of one product. No
    acceptance-record contract exists, so no value establishes a gate here."""
    review = product.get('review')
    _evidence(type(review) is dict, 'evidence-gate-structure', path + '.review')
    gates = {}
    for gate, extra in _GATES:
        record = review.get(gate)
        where = '%s.review.%s' % (path, gate)
        _evidence(type(record) is dict and type(record.get('status')) is str
                  and type(record.get('records')) is list, 'evidence-gate-structure', where)
        row = {'status': record['status'], 'recordCount': len(record['records'])}
        for field in extra:
            _evidence(type(record.get(field)) is str, 'evidence-gate-structure',
                      where + '.' + field)
            row[field] = record[field]
        gates[gate] = row
    return gates


def _check_metadata(context, release, english):
    """The surface, terminology, client and pseudo-data metadata the report
    uses. Values are reported as declared; none is judged complete."""
    adoption, seen = context['currentAdoption'], set()
    for key in adoption['keys']:
        _evidence(key in english and key not in seen, 'adoption-key',
                  'keyContext.currentAdoption.keys', key)
        seen.add(key)
    coverage = adoption.get('allWindowSemanticCoverage')
    _evidence(_nonblank(coverage), 'metadata-structure',
              'keyContext.currentAdoption.allWindowSemanticCoverage')
    denominator = context.get('visibleTextDenominator')
    _evidence(_nonblank(denominator), 'metadata-structure', 'keyContext.visibleTextDenominator')
    other = context.get('otherVisibleCopy')
    _evidence(type(other) is list, 'metadata-structure', 'keyContext.otherVisibleCopy')
    copy_rows = []
    for index, item in enumerate(other):
        _evidence(type(item) is dict and _nonblank(item.get('source'))
                  and _nonblank(item.get('status')), 'metadata-structure',
                  'keyContext.otherVisibleCopy[%d]' % index)
        copy_rows.append({'source': item['source'], 'status': item['status']})
    terminology = release.get('terminology')
    _evidence(type(terminology) is dict and _nonblank(terminology.get('status')),
              'metadata-structure', 'release.terminology')
    client = release.get('clientEvidence')
    _evidence(type(client) is dict and _is_str_list(client.get('evidencedClientAliases')),
              'metadata-structure', 'release.clientEvidence')
    native = {}
    for field in _NATIVE_FACTS:
        _evidence(_nonblank(client.get(field)), 'metadata-structure',
                  'release.clientEvidence.' + field)
        native[field] = client[field]
    pseudo = release.get('pseudoAndTestData')
    _evidence(type(pseudo) is dict and _is_str_list(pseudo.get('shippedProductIds')),
              'metadata-structure', 'release.pseudoAndTestData')
    shipped = pseudo['shippedProductIds']
    _evidence(not shipped, 'evidence-pseudo-product',
              'release.pseudoAndTestData.shippedProductIds', shipped[0] if shipped else None)
    return {'adoptionKeys': list(adoption['keys']), 'allWindowSemanticCoverage': coverage,
            'visibleTextDenominator': denominator, 'otherVisibleCopy': copy_rows,
            'terminology': terminology['status'], 'native': native,
            'aliases': list(client['evidencedClientAliases']), 'pseudo': list(shipped)}


def _check_families(context, english):
    """Each window family needs a text name, key family and statuses, an
    integer issue, a list of paths and a unique name. Its adopted keys must be
    distinct English keys. Every family is kept, also one without an adopted
    key."""
    names, families = set(), []
    for index, family in enumerate(context['windowFamilies']):
        path = 'keyContext.windowFamilies[%d]' % index
        for field in ('name', 'proposedKeyFamily', 'semanticStatus', 'coverageStatus'):
            _evidence(_nonblank(family.get(field)), 'family-structure', path + '.' + field)
        _evidence(type(family.get('issue')) is int, 'family-structure', path + '.issue')
        _evidence(_is_str_list(family.get('paths')), 'family-structure', path + '.paths')
        name = family['name']
        _evidence(name not in names, 'family-duplicate', path + '.name', name)
        names.add(name)
        seen = set()
        for key in family['adoptedKeys']:
            _evidence(key in english, 'family-unknown-key', path + '.adoptedKeys', key)
            _evidence(key not in seen, 'family-duplicate-key', path + '.adoptedKeys', key)
            seen.add(key)
        families.append(family)
    return families


def _check_declarations(release, english, packs, optional_ids):
    """Check the entry-review declarations of release.entryReview. Each must
    be a complete, coherent record for a present entry of an optional pack;
    any defect raises CatalogEvidenceError. Returns
    {(product ID, key): decision} and the number of declarations."""
    where = 'release.entryReview'
    contract = release.get('entryReview')
    _evidence(type(contract) is dict, 'evidence-contract', where)
    _evidence(contract.get('contract') == _ENTRY_CONTRACT, 'evidence-contract',
              where + '.contract')
    _evidence(_is_int(contract.get('contractVersion'), 1), 'evidence-contract',
              where + '.contractVersion')
    records = contract.get('declarations')
    _evidence(type(records) is list, 'evidence-contract', where + '.declarations')
    found = {}
    for index, record in enumerate(records):
        path = '%s.declarations[%d]' % (where, index)
        _evidence(type(record) is dict, 'evidence-structure', path)
        _evidence(set(record) == set(_DECLARATION_FIELDS), 'evidence-field', path)
        for field in _DECLARATION_FIELDS:
            _evidence(type(record[field]) is str, 'evidence-type', path + '.' + field)
        product_id, key = record['productId'], record['key']
        digest, decision = record['translatedTextSha256'], record['decision']
        _evidence(record['status'] == _DECLARED, 'evidence-status', path + '.status', key)
        _evidence(product_id in optional_ids, 'evidence-unknown-product', path + '.productId',
                  product_id)
        _evidence(key in english, 'evidence-unknown-key', path + '.key', key)
        _evidence(_SHA256_HEX.fullmatch(digest) is not None, 'evidence-hash-format',
                  path + '.translatedTextSha256', key)
        _evidence(_valid_reviewer(record['reviewer']), 'evidence-reviewer', path + '.reviewer',
                  key)
        _evidence(_valid_reference(record['evidenceReference']), 'evidence-reference',
                  path + '.evidenceReference', key)
        _evidence(decision in _DECISIONS, 'evidence-decision', path + '.decision', key)
        entries = packs[product_id]['entries']
        _evidence(key in entries, 'evidence-no-entry', path + '.key', key)
        _evidence(digest == _text_sha256(entries[key]), 'evidence-stale',
                  path + '.translatedTextSha256', key)
        identical = entries[key] == english[key]
        _evidence(identical == (decision == 'legitimately_identical'),
                  'evidence-decision-mismatch', path + '.decision', key)
        previous = found.get((product_id, key))
        if previous is not None:
            _evidence(previous != record, 'evidence-duplicate', path, key)
            raise CatalogEvidenceError('evidence-conflict', path, key)
        found[(product_id, key)] = record
    return {pair: record['decision'] for pair, record in found.items()}, len(records)


def _classify(ordered, english, entries, decisions, product_id):
    """One category list per ENTRY_CATEGORIES name for one optional pack."""
    keys = {category: [] for category in ENTRY_CATEGORIES}
    for key in ordered:
        if key not in entries:
            category = 'missing'
        elif (product_id, key) in decisions:
            category = _DECISIONS[decisions[(product_id, key)]]
        elif entries[key] == english[key]:
            category = 'deliberate_english_placeholder'
        else:
            category = 'draft_unreviewed'
        keys[category].append(key)
    keys['obsolete'] = sorted(key for key in entries if key not in english)
    return keys


def _counts(keys):
    return {category: len(keys[category]) for category in ENTRY_CATEGORIES}


def _reason(code, subject, value, keys=()):
    return {'code': code, 'subject': subject, 'value': value, 'keys': list(keys)}


def _state(reasons):
    return 'INCOMPLETE' if reasons else 'UNDETERMINED'


def _describe(row):
    return '; '.join('%s=%s' % (name, row[name]) for name in sorted(row))


def catalog_report(english_source: bytes, packs_source: bytes, key_context_json: bytes,
                   release_json: bytes) -> dict:
    """Return a deterministic coverage and evidence report dict for the exact
    bytes of data/LocalizationEnglish.lua, data/LocalizationPacks.lua,
    docs/localization/KEY_CONTEXT.json and docs/localization/RELEASE_LANGUAGES.json.

    validate_catalog_data runs first on the same four arguments, unchanged.
    Its TypeError, CatalogSyntaxError and CatalogValidationError propagate,
    and no partial report or count is produced. After that, invalid
    entry-review declarations, review-gate shapes, window-family or surface
    metadata raise CatalogEvidenceError (one of EVIDENCE_CODES).

    For each optional_ui_pack product, in release order, every English key
    (sorted) is exactly one of ENTRY_CATEGORIES:
    - absent: missing;
    - present with a qualified declaration: translated_and_reviewed or
      reviewed_legitimately_identical, by its decision;
    - present and equal to the English text: deliberate_english_placeholder
      (a technical category that claims nothing about intent);
    - otherwise: draft_unreviewed.
    Fallback English and the autonym never count as an entry. The English
    baseline is reported as the baseline and denominator, never as a pack.
    Every count and list derives from the inputs.

    Window families keep their declared order, including families without an
    adopted key. A key shown by several families is listed in each and
    counted once in the denominator. English keys without a family get their
    own rows.

    completeness.reasons lists the concrete remaining reasons. There is no
    complete or release state and no override. A structurally qualified
    declaration is not evidence of fluent competence, contributor rights or
    native truth, and data inspection establishes no native client fact.
    Nothing is read, written, fetched, rendered or executed."""
    validated = validate_catalog_data(english_source, packs_source, key_context_json,
                                      release_json)
    english, packs = validated['english'], validated['packs']
    context, release = validated['keyContext'], validated['release']
    products = release['products']
    baseline_id = next(item['productId'] for item in products if item['kind'] == _BASELINE)
    optional = [item for item in products if item['kind'] == _OPTIONAL]
    optional_ids = [item['productId'] for item in optional]
    gates = [(item['productId'], _check_gates(item, 'release.products[%d]' % index))
             for index, item in enumerate(products)]
    metadata = _check_metadata(context, release, english)
    families = _check_families(context, english)
    decisions, declaration_count = _check_declarations(release, english, packs,
                                                       frozenset(optional_ids))
    ordered = sorted(english)
    sources = (english_source, packs_source, key_context_json, release_json)
    inputs = [{'name': name, 'source': source, 'sha256': hashlib.sha256(bytes(data)).hexdigest(),
               'byteLength': len(data)} for (name, source), data in zip(_REPORT_INPUTS, sources)]
    reasons, lists, rows = [], {}, []
    for item in optional:
        product_id = item['productId']
        entries = packs[product_id]['entries']
        keys = _classify(ordered, english, entries, decisions, product_id)
        counts = _counts(keys)
        lists[product_id] = keys
        rows.append({
            'productId': product_id, 'kind': _OPTIONAL, 'autonym': item['autonym'],
            'denominator': len(ordered), 'entriesPresent': len(entries),
            'declarationsApplied': sum(1 for pair in decisions if pair[0] == product_id),
            'counts': counts, 'keys': keys,
            'reconciliation': {'denominator': len(ordered), 'inDenominatorTotal':
                               sum(counts[category] for category in _IN_DENOMINATOR)},
        })
        for category in _NOT_REVIEWED:
            if keys[category]:
                reasons.append(_reason('entries-' + category.replace('_', '-'), product_id,
                                       category, keys[category]))
    gate_rows = []
    for product_id, product_gates in gates:
        gate_rows.append({'productId': product_id, 'gates': product_gates})
        for gate, _ in _GATES:
            reasons.append(_reason('review-gate-not-established', product_id + '.' + gate,
                                   _describe(product_gates[gate])))
    family_rows, references = [], {}
    for family in families:
        name, adopted = family['name'], family['adoptedKeys']
        chosen = frozenset(adopted)
        for key in adopted:
            references[key] = references.get(key, 0) + 1
        family_reasons = [_reason('family-semantic-status', name, family['semanticStatus']),
                          _reason('family-coverage-status', name, family['coverageStatus'])]
        if not adopted:
            family_reasons.append(_reason('family-no-adopted-key', name, 'adoptedKeys=0'))
        per_product = []
        for product_id in optional_ids:
            keys = {category: [key for key in lists[product_id][category] if key in chosen]
                    for category in ENTRY_CATEGORIES}
            per_product.append({'productId': product_id, 'counts': _counts(keys), 'keys': keys})
            pending = sorted(key for category in _NOT_REVIEWED for key in keys[category])
            if pending:
                family_reasons.append(_reason('family-entries-not-reviewed', name, product_id,
                                              pending))
        family_rows.append({
            'name': name, 'proposedKeyFamily': family['proposedKeyFamily'],
            'issue': family['issue'], 'paths': list(family['paths']),
            'semanticStatus': family['semanticStatus'],
            'coverageStatus': family['coverageStatus'],
            'adoptedKeys': list(adopted), 'adoptedKeyCount': len(adopted),
            'products': per_product, 'state': _state(family_reasons), 'reasons': family_reasons,
        })
        reasons.extend(_reason(row['code'], row['subject'], row['value'], row['keys'])
                       for row in family_reasons)
    unassigned = [key for key in ordered if key not in references]
    if not families:
        reasons.append(_reason('no-window-family', 'keyContext.windowFamilies',
                               'windowFamilies=0'))
    if unassigned:
        reasons.append(_reason('keys-without-family', 'keyContext.windowFamilies', 'adoptedKeys',
                               unassigned))
    category_of = {product_id: {key: category for category in ENTRY_CATEGORIES
                                for key in lists[product_id][category]}
                   for product_id in optional_ids}
    unassigned_rows = [{'key': key, 'products': [
        {'productId': product_id, 'category': category_of[product_id][key]}
        for product_id in optional_ids]} for key in unassigned]
    reasons.append(_reason('adoption-semantic-coverage',
                           'keyContext.currentAdoption.allWindowSemanticCoverage',
                           metadata['allWindowSemanticCoverage']))
    for row in metadata['otherVisibleCopy']:
        reasons.append(_reason('other-visible-copy', row['source'], row['status']))
    reasons.append(_reason('visible-text-denominator', 'keyContext.visibleTextDenominator',
                           metadata['visibleTextDenominator']))
    reasons.append(_reason('terminology-status', 'release.terminology.status',
                           metadata['terminology']))
    for field in _NATIVE_FACTS:
        reasons.append(_reason('native-fact-not-established', 'release.clientEvidence.' + field,
                               metadata['native'][field]))
    return {
        'schema': REPORT_SCHEMA,
        'schemaVersion': REPORT_SCHEMA_VERSION,
        'tool': _TOOL_PATH,
        'status': STATUS,
        'fullValidation': NOTICE['fullValidation'],
        'validationScope': NOTICE['validationScope'],
        'inputs': inputs,
        'categories': list(ENTRY_CATEGORIES),
        'englishBaseline': {
            'productId': baseline_id, 'kind': _BASELINE, 'source': _ENGLISH_SOURCE,
            'keyCount': len(ordered), 'keys': list(ordered),
            'role': 'explicit baseline and denominator; not an optional translated pack',
        },
        'denominator': {
            'englishKeys': len(ordered),
            'basis': 'distinct semantic keys of the English base',
            'familyAdoptedKeyReferences': sum(references.values()),
            'distinctFamilyAdoptedKeys': len(references),
            'keysOnMultipleFamilies': sorted(key for key, n in references.items() if n > 1),
            'keysWithoutFamily': list(unassigned),
            'rule': 'family rows are presentation rows; their sums are never a denominator',
        },
        'products': rows,
        'reviewGates': gate_rows,
        'families': family_rows,
        'unassignedKeys': unassigned_rows,
        'surfaces': {
            'currentAdoptionKeys': metadata['adoptionKeys'],
            'currentAdoptionBasis': 'declared metadata; consumer adoption is not verified here',
            'allWindowSemanticCoverage': metadata['allWindowSemanticCoverage'],
            'visibleTextDenominator': metadata['visibleTextDenominator'],
            'otherVisibleCopy': metadata['otherVisibleCopy'],
        },
        'nativeFacts': {
            'declared': metadata['native'],
            'evidencedClientAliases': metadata['aliases'],
            'establishedByThisReport': 'NOT_RUN',
            'rule': 'data inspection establishes no client locale, font, glyph or layout fact',
        },
        'pseudoAndTestData': {
            'shippedProductIds': metadata['pseudo'],
            'countedInProductRows': len(metadata['pseudo']),
            'rule': 'pseudo-locale and test fixture data are never shipped products',
        },
        'evidence': {
            'contract': _ENTRY_CONTRACT,
            'declarationCount': declaration_count,
            'qualifiedDeclarations': len(decisions),
            'notEvidenceOf': EVIDENCE_NOTICE,
            'productReviewGates': 'reported in reviewGates; never granted by a declaration',
        },
        'completeness': {
            'state': _state(reasons),
            'reasonCount': len(reasons),
            'reasons': reasons,
            'rule': ('state is INCOMPLETE while any reason remains; this report defines no '
                     'complete or release state and accepts no override'),
        },
    }


# ---------------------------------------------------------------------------
# B3b (Refs #147): the bounded read-only command line around catalog_report.
# main() resolves one root, reads exactly the five fixed files of _CLI_INPUTS
# as bytes, checks only the presence and order of the three localization
# lines in Nexus.toc and passes the four catalog inputs, unchanged, to
# catalog_report above. It writes one ASCII JSON record and no file, imports
# nothing from the root, runs no Lua, fetches nothing and reads no Git state,
# so no metadata source pin is reported as a current revision.

CLI_SCHEMA = 'nexus.l10n.catalog_cli_record'
CLI_SCHEMA_VERSION = 1
CLI_CODES = (
    'argument-unknown', 'argument-missing-value', 'argument-duplicate',
    'root-missing', 'root-not-directory', 'root-unreadable',
    'input-missing', 'input-escape', 'input-not-file', 'input-unreadable',
    'toc-not-utf8', 'toc-missing-entry', 'toc-duplicate-entry', 'toc-order',
)

_EXIT_REPORT, _EXIT_NOT_ESTABLISHED, _EXIT_ERROR = 0, 1, 2
_TOC_SOURCE = 'Nexus.toc'
_CLI_INPUTS = tuple(source for _, source in _REPORT_INPUTS) + (_TOC_SOURCE,)
_TOC_ORDER = (_ENGLISH_SOURCE, _PACKS_SOURCE, _AUTHORITY)
_TOC_LINE_BREAK = re.compile('\r\n|\r|\n')
_TOC_SEPARATORS = re.compile(r'[/\\]+')
_DEFAULT_ROOT = _INVENTORY.parent.parent
_INPUT_BINDING = ('exact bytes read once from the resolved root; no Git revision is read, '
                  'and metadata source pins stay historical')
_TOC_SCOPE = ('only the presence and order of these entries are checked; no other TOC module '
              'is opened or required')
_TECHNICAL_SCOPE = ('technical dictionary data only: syntax, schema and entry categories over '
                    'the current English keys; not translation quality, review, full UI, '
                    'native or external acceptance')
_READINESS_RULE = ('external readiness is separate from technical validity: every remaining '
                   'report reason blocks it, and no trusted external acceptance-record '
                   'contract exists, so a qualified entry declaration is not fluent or native '
                   'truth and nothing here attests acceptance')


class CatalogCliError(ValueError):
    """Raised by the command line for an argument, root, input or Nexus.toc
    failure. It carries a stable code (one of CLI_CODES), the argument, input
    or TOC entry concerned and, for a TOC entry, its 1-based line number. The
    text of an unknown argument is never echoed."""

    def __init__(self, code: str, subject: str = None, line: int = None):
        detail = '' if subject is None else ' at ' + subject
        if line is not None:
            detail += ', line %d' % line
        super().__init__(code + detail)
        self.code, self.subject, self.line = code, subject, line


_CLI_FAILURES = (CatalogCliError, CatalogSyntaxError, CatalogValidationError,
                 CatalogEvidenceError)


def _cli_arguments(arguments):
    """Return (root or None, require_complete). Only --root DIR, --root=DIR
    and --require-complete are accepted, each at most once."""
    root, require_complete, seen, index = None, False, set(), 0
    while index < len(arguments):
        argument, position = arguments[index], index
        index += 1
        if argument == '--require-complete':
            name, value = argument, None
        elif argument == '--root':
            if index >= len(arguments):
                raise CatalogCliError('argument-missing-value', argument)
            name, value = argument, arguments[index]
            index += 1
        elif argument.startswith('--root='):
            name, value = '--root', argument[len('--root='):]
        else:
            raise CatalogCliError('argument-unknown', 'argument[%d]' % position)
        if name in seen:
            raise CatalogCliError('argument-duplicate', name)
        seen.add(name)
        if value is None:
            require_complete = True
        elif value == '':
            raise CatalogCliError('argument-missing-value', name)
        else:
            root = value
    return root, require_complete


def _cli_root(root):
    """Resolve the root, through any symlink or junction, to an existing
    directory."""
    try:
        resolved = pathlib.Path(root).resolve(strict=True)
    except (FileNotFoundError, NotADirectoryError):
        raise CatalogCliError('root-missing', 'root') from None
    except (OSError, RuntimeError, ValueError):
        raise CatalogCliError('root-unreadable', 'root') from None
    if not resolved.is_dir():
        raise CatalogCliError('root-not-directory', 'root')
    return resolved


def _cli_read(root, source):
    """Return the exact bytes of one fixed input. It must resolve, through any
    symlink or junction, to a regular readable file inside the resolved
    root."""
    candidate = root.joinpath(*source.split('/'))
    try:
        resolved = candidate.resolve(strict=True)
    except (FileNotFoundError, NotADirectoryError):
        raise CatalogCliError('input-missing', source) from None
    except (OSError, RuntimeError, ValueError):
        raise CatalogCliError('input-unreadable', source) from None
    if root not in resolved.parents:
        raise CatalogCliError('input-escape', source)
    if not resolved.is_file():
        raise CatalogCliError('input-not-file', source)
    try:
        return resolved.read_bytes()
    except OSError:
        raise CatalogCliError('input-unreadable', source) from None


def _cli_toc(data):
    """Check Nexus.toc as UTF-8 data: after blank, comment and metadata lines
    are skipped and slash or backslash runs become one /, each entry of
    _TOC_ORDER must appear exactly once and in that order. Other lines are
    neither judged nor opened. Returns the entries with their line numbers."""
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        raise CatalogCliError('toc-not-utf8', _TOC_SOURCE) from None
    if text.startswith('\ufeff'):
        text = text[1:]
    lines = {path: [] for path in _TOC_ORDER}
    for number, line in enumerate(_TOC_LINE_BREAK.split(text), 1):
        entry = line.strip()
        if entry and not entry.startswith('#'):
            entry = _TOC_SEPARATORS.sub('/', entry)
            if entry in lines:
                lines[entry].append(number)
    found = []
    for path in _TOC_ORDER:
        numbers = lines[path]
        if not numbers:
            raise CatalogCliError('toc-missing-entry', path)
        if len(numbers) > 1:
            raise CatalogCliError('toc-duplicate-entry', path, numbers[1])
        if found and numbers[0] < found[-1]['line']:
            raise CatalogCliError('toc-order', path, numbers[0])
        found.append({'path': path, 'line': numbers[0]})
    return found


def _cli_technical(report):
    """Technical dictionary validity and entry counts, kept apart from
    external readiness."""
    rows = report['products']
    missing = sum(row['counts']['missing'] for row in rows)
    return {
        'validity': 'VALID',
        'englishKeys': report['denominator']['englishKeys'],
        'missingEntries': missing,
        'entryPresence': 'PARTIAL' if missing else 'EVERY_CURRENT_ENGLISH_KEY_PRESENT',
        'products': [{'productId': row['productId'], 'denominator': row['denominator'],
                      'entriesPresent': row['entriesPresent'], 'counts': row['counts']}
                     for row in rows],
        'scope': _TECHNICAL_SCOPE,
    }


def _cli_readiness(report):
    """External readiness, kept apart from technical validity. Every report
    reason blocks it, and so does the absence of any trusted external
    acceptance-record contract. Returns the blocking reasons and the summary."""
    completeness = report['completeness']
    blocking = list(completeness['reasons'])
    blocking.append(_reason('external-acceptance-not-attested', 'external acceptance gate',
                            'no trusted external acceptance-record contract exists'))
    return blocking, {
        'state': 'NOT_ESTABLISHED',
        'externalAcceptance': 'NOT_ATTESTED',
        'reportCompletenessState': completeness['state'],
        'reportReasonCount': completeness['reasonCount'],
        'blockingReasonCount': len(blocking),
        'blockingReasonCodes': sorted({reason['code'] for reason in blocking}),
        'externalAcceptanceReason': blocking[-1],
        'rule': _READINESS_RULE,
    }


def _cli_error(error):
    """One error record with the stable class and code of error."""
    record = {'schema': CLI_SCHEMA, 'schemaVersion': CLI_SCHEMA_VERSION, 'record': 'error',
              'tool': _TOOL_PATH, 'status': STATUS, 'errorClass': type(error).__name__,
              'code': error.code, 'exitCode': _EXIT_ERROR}
    for field in ('subject', 'path', 'key', 'line', 'column'):
        value = getattr(error, field, None)
        if value is not None:
            record[field] = value if type(value) in (str, int) else repr(value)
    return record


def _cli_emit(stream, record):
    """Write one record as one line of sorted ASCII JSON, as exact bytes."""
    stream.buffer.write(json.dumps(record, sort_keys=True).encode('ascii') + b'\n')
    stream.buffer.flush()


def main(argv=None) -> int:
    """The read-only report command line described in the module documentation:

        python tools/l10n_catalog.py [--root DIR] [--require-complete]

    Exactly one ASCII JSON record is written: a report on stdout or an error
    on stderr. The return value is 0 for a valid report, also for partial
    data; 1 with --require-complete while external readiness is not
    established; 2 for an argument, root, input, TOC, syntax, schema or
    evidence error."""
    arguments = sys.argv[1:] if argv is None else list(argv)
    try:
        root, require_complete = _cli_arguments(arguments)
        resolved = _cli_root(_DEFAULT_ROOT if root is None else root)
        data = [_cli_read(resolved, source) for source in _CLI_INPUTS]
        toc_entries = _cli_toc(data[-1])
        report = catalog_report(*data[:-1])
    except _CLI_FAILURES as error:
        _cli_emit(sys.stderr, _cli_error(error))
        return _EXIT_ERROR
    blocking, readiness = _cli_readiness(report)
    exit_code = _EXIT_NOT_ESTABLISHED if require_complete and blocking else _EXIT_REPORT
    _cli_emit(sys.stdout, {
        'schema': CLI_SCHEMA,
        'schemaVersion': CLI_SCHEMA_VERSION,
        'record': 'report',
        'tool': _TOOL_PATH,
        'status': STATUS,
        'fullValidation': NOTICE['fullValidation'],
        'validationScope': NOTICE['validationScope'],
        'notice': dict(NOTICE),
        'requireComplete': 'requested' if require_complete else 'not_requested',
        'exitCode': exit_code,
        'inputBinding': _INPUT_BINDING,
        'toc': {'name': 'toc', 'source': _TOC_SOURCE,
                'sha256': hashlib.sha256(data[-1]).hexdigest(), 'byteLength': len(data[-1]),
                'requiredOrder': toc_entries, 'scope': _TOC_SCOPE},
        'technicalCatalog': _cli_technical(report),
        'externalReadiness': readiness,
        'report': report,
    })
    return exit_code


# ---------------------------------------------------------------------------
# S1 (Refs #147): a PRIVATE restricted literal-table parser. It reads the
# shared runtime/offline parity corpus tests/prototype/fixtures/l10n_parity/
# cases.lua for tools/tests/test_l10n_parity.py, and a later registry-bound
# parser may reuse it. It is not part of the public seam: CODES and every
# public function, report and label above are unchanged. Like parse_english
# and parse_packs it takes exact bytes, never a filename, reads and writes no
# file, and never evaluates, imports or executes Lua. After Lua 5.1
# whitespace and comments, the only accepted form is
#
#     return <table>
#
# followed by the end of the source. A table holds only positional values
# (returned as a list) or only keyed fields (returned as a dict), never both;
# {} is an empty list. A key is a bare Lua name that is not a reserved word,
# or a bracketed literal string. Both spellings name the same key, so a
# repeated key in either spelling is duplicate-key. A value is a literal
# string, a decimal integer of 1 to _LITERAL_MAX_DIGITS digits without a
# sign, leading zero, fraction or exponent, true, false or a nested table, at
# most _LITERAL_MAX_DEPTH tables deep. Anything else raises CatalogSyntaxError
# with an existing code: nil, a negative, hexadecimal or fractional number, a
# variable, call, operator, concatenation, function, computed or numeric key,
# a semicolon, a second statement or a table that is too deep is
# unexpected-token (unexpected-end at the end of the source), and anything
# after the table is trailing-content.

_DIGITS = frozenset('0123456789')
_LITERAL_MAX_DIGITS = 9
_LITERAL_MAX_DEPTH = 8


class _LiteralParser(_Parser):
    """The restricted literal-table grammar over a token list."""

    def value(self, depth):
        token = self.tokens[self.index]
        if token.kind in ('string', 'integer'):
            self.index += 1
            return token.value
        if token.kind == 'name' and token.value in ('true', 'false'):
            self.index += 1
            return token.value == 'true'
        if token.kind == 'punct' and token.value == '{' and depth < _LITERAL_MAX_DEPTH:
            self.index += 1
            return self.table(depth + 1)
        self.fail(self.unexpected(token), token)

    def table(self, depth):
        """Read the items of the table whose { was just read."""
        keyed, positional = {}, []

        def item():
            start = self.tokens[self.index]
            if start.kind == 'name' and start.value not in _RESERVED:
                self.index += 1
                key = start.value
            elif start.kind == 'punct' and start.value == '[':
                key = self.bracketed_string()
            else:
                if keyed:
                    self.fail('unexpected-token', start)
                positional.append(self.value(depth))
                return
            if positional:
                self.fail('unexpected-token', start)
            if key in keyed:
                self.fail('duplicate-key', start)
            self.take('punct', '=')
            keyed[key] = self.value(depth)

        self.items(item)
        return keyed if keyed else positional


def _parse_literal_table(source):
    """Parse the bytes of a 'return <table>' literal source (grammar above)
    into nested lists, dicts, strings, integers and booleans. Syntax only."""
    if not isinstance(source, (bytes, bytearray)):
        raise TypeError('source must be bytes, not %s' % type(source).__name__)
    try:
        text = bytes(source).decode('utf-8')
    except UnicodeDecodeError:
        raise CatalogSyntaxError('not-utf8') from None
    parser = _LiteralParser(_tokens(text, integers=True))
    parser.take('name', 'return')
    parser.take('punct', '{')
    result = parser.table(1)
    token = parser.tokens[parser.index]
    if token.kind != 'eof':
        parser.fail('trailing-content', token)
    return result


if __name__ == '__main__':
    raise SystemExit(main())
