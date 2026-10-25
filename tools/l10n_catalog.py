#!/usr/bin/env python3
"""Syntax foundation and pure schema API for the Nexus localization data (#147).

Status: SCHEMA_API_ONLY_REPORT_CLI_PENDING. parse_english and parse_packs below
check syntax only, and a successful parse alone does not make a catalog valid.
validate_catalog_data, appended after them, is a pure in-memory schema API:
from the exact bytes of the English base, the packs file, KEY_CONTEXT.json and
RELEASE_LANGUAGES.json it checks keys, text, the charge template grammar, pack
IDs, autonyms and entries, the key-context rows and the release product
metadata against the runtime contract of core/Localization.lua, and raises
CatalogValidationError (stable .code) on a semantic failure. Missing translated
entries are valid partial data. Pack coverage counts, review and native
evidence, TOC order, aggregated reports and the --root command line are still
pending, so full validation is NOT_IMPLEMENTED. Schema validity does not claim
that a catalog is reviewed, complete or displayable.

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

Run directly, this file is not a validator. It ignores its arguments, writes one
ASCII JSON notice with status PARSER_ONLY_FULL_VALIDATION_PENDING on stderr and
exits 2. Python 3.9+, standard library only.
"""
from __future__ import annotations

import json
import pathlib
import sys
import types
from collections import namedtuple

STATUS = 'SCHEMA_API_ONLY_REPORT_CLI_PENDING'
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
    'fullValidation': 'NOT_IMPLEMENTED',
    'message': 'syntax and schema API only; coverage validation and report CLI are pending',
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


def _tokens(text):
    """Return every token of text, ending with one 'eof' token. A lexical
    error raises CatalogSyntaxError. Any character outside the data grammar
    becomes an 'other' token, which the parser always refuses."""
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
# nothing in the data. Coverage counts, review and native evidence, TOC order,
# reports and the command line are later tasks.

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


def main() -> int:
    """Direct execution: write the pending notice on stderr and return exit
    status 2. This is not the validator's command line, and any arguments are
    ignored."""
    sys.stderr.write(json.dumps(NOTICE, sort_keys=True) + '\n')
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
